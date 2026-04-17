#!/usr/bin/env python3
"""
NOC Tune - Browser-based TTFB Testing UI

This script provides a web-based interface for:
- Configuring test parameters (targets, thresholds, etc.)
- Checking system prerequisites (curl, network, etc.)
- Running TTFB tests with live progress
- Viewing real-time results and logs

Usage:
    python ttfb_test_ui.py

The script will open your browser to http://localhost:8766
"""

import http.server
import socketserver
import webbrowser
import json
import os
import sys
import subprocess
import signal
import threading
import time
import re
import platform
import queue
import importlib
from pathlib import Path
from datetime import datetime
from urllib.parse import urlencode, urlparse, parse_qs
import urllib.request

try:
    from ui.backend_service import (
        CONTRIBUTE_API_URL,
        EXPORT_FIELDNAMES,
        build_contribution_row,
        build_export_rows,
        calculate_summary,
        submit_contribution_row,
        submit_contribution_rows,
    )
except ImportError:
    from backend_service import (
        CONTRIBUTE_API_URL,
        EXPORT_FIELDNAMES,
        build_contribution_row,
        build_export_rows,
        calculate_summary,
        submit_contribution_row,
        submit_contribution_rows,
    )

# Configuration
PORT = 8766
NO_BROWSER = False  # Set to True when launched from Electron

# Detect if running in PyInstaller bundle
def get_base_path():
    """Get the base path for resources, handling PyInstaller bundles."""
    if getattr(sys, 'frozen', False) and hasattr(sys, '_MEIPASS'):
        # Running in PyInstaller bundle
        return Path(sys._MEIPASS)
    else:
        # Running in normal Python environment
        return Path(__file__).parent.parent

def get_ui_path():
    """Get the path to UI directory."""
    if getattr(sys, 'frozen', False) and hasattr(sys, '_MEIPASS'):
        # In bundle, UI files are at MEIPASS/ui/
        return Path(sys._MEIPASS) / 'ui'
    else:
        # In dev, UI files are in the same directory as this script
        return Path(__file__).parent

def get_notebooks_path():
    """Get the path to notebooks directory for config/results."""
    if getattr(sys, 'frozen', False):
        # In bundled mode, check relative to executable first
        # Electron sets cwd to backend folder, notebooks is at ../notebooks
        exe_path = Path(sys.executable).parent
        notebooks_from_exe = exe_path.parent / 'notebooks'
        if notebooks_from_exe.exists():
            return notebooks_from_exe
        # Fallback: try cwd/../notebooks (Electron Resources structure)
        cwd_notebooks = Path.cwd().parent / 'notebooks'
        if cwd_notebooks.exists():
            return cwd_notebooks
        # Last fallback: home directory
        home_notebooks = Path.home() / '.noctune'
        home_notebooks.mkdir(parents=True, exist_ok=True)
        return home_notebooks
    else:
        return Path(__file__).parent.parent / "notebooks"

BASE_PATH = get_base_path()
UI_DIR = get_ui_path()
NOTEBOOKS_PATH = get_notebooks_path()
CONFIG_FILE = NOTEBOOKS_PATH / "config.txt"
RESULTS_DIR = NOTEBOOKS_PATH / "results"
PRECISE_LOCATION_FILE = NOTEBOOKS_PATH / "precise_location.json"
TEMPLATE_FILE = UI_DIR / "templates" / "ttfb_test_ui.html"
STATIC_DIR = UI_DIR / "static"
STATIC_ASSETS = {
    '/static/ttfb_test_ui.css': (STATIC_DIR / 'ttfb_test_ui.css', 'text/css; charset=utf-8'),
    '/static/ttfb_test_ui.js': (STATIC_DIR / 'ttfb_test_ui.js', 'application/javascript; charset=utf-8'),
}


def clean_windows_netsh_value(raw_value):
    value = (raw_value or '').strip()
    if not value:
        return None
    normalized = value.lower()
    if normalized in {'not present', 'n/a', 'none', '-'}:
        return None
    return value


def extract_windows_netsh_field(output, field_names):
    for line in output.splitlines():
        if ':' not in line:
            continue
        label, value = line.split(':', 1)
        normalized_label = re.sub(r'\s+', ' ', label).strip().lower()
        if normalized_label in field_names:
            return clean_windows_netsh_value(value)
    return None

# Debug: print paths on startup (will show in logs)
if getattr(sys, 'frozen', False):
    print(f"[DEBUG] Running in frozen/bundled mode")
    print(f"[DEBUG] sys._MEIPASS = {getattr(sys, '_MEIPASS', 'N/A')}")
    print(f"[DEBUG] sys.executable = {sys.executable}")
    print(f"[DEBUG] cwd = {Path.cwd()}")
print(f"[DEBUG] UI_DIR = {UI_DIR}")
print(f"[DEBUG] TEMPLATE_FILE = {TEMPLATE_FILE} (exists: {TEMPLATE_FILE.exists()})")
print(f"[DEBUG] STATIC_DIR = {STATIC_DIR} (exists: {STATIC_DIR.exists()})")
print(f"[DEBUG] NOTEBOOKS_PATH = {NOTEBOOKS_PATH} (exists: {NOTEBOOKS_PATH.exists()})")
for path, (file_path, _) in STATIC_ASSETS.items():
    print(f"[DEBUG] STATIC_ASSETS['{path}'] = {file_path} (exists: {file_path.exists()})")


def load_dns_resolver_module():
    """Load dnspython lazily so newly installed packages are detected without stale startup state."""
    try:
        return importlib.import_module('dns.resolver')
    except ImportError:
        return None


def normalize_target_url(value: str) -> str:
    """Ensure target values are valid absolute URLs for curl and the contribute API."""
    text = (value or '').strip()
    if not text:
        return ''
    if re.match(r'^[A-Za-z][A-Za-z0-9+.-]*://', text):
        return text
    return f'https://{text}'


def normalize_target_urls(values) -> list[str]:
    """Normalize and deduplicate target URL values while preserving order."""
    normalized = []
    seen = set()
    for value in values or []:
        url = normalize_target_url(value)
        if not url or url in seen:
            continue
        normalized.append(url)
        seen.add(url)
    return normalized


def parse_dns_servers(values) -> list[str]:
    """Parse DNS server values from a comma-separated string or sequence."""
    if values is None:
        return []

    if isinstance(values, str):
        raw_values = values.split(',')
    else:
        raw_values = list(values)

    servers = []
    seen = set()
    for value in raw_values:
        server = str(value or '').strip()
        if not server or server in seen:
            continue
        servers.append(server)
        seen.add(server)
    return servers


def parse_manual_coordinates(latitude_value, longitude_value) -> tuple[float, float] | None:
    """Parse manual latitude/longitude values from config or API input."""
    lat_text = '' if latitude_value is None else str(latitude_value).strip()
    lon_text = '' if longitude_value is None else str(longitude_value).strip()

    if not lat_text and not lon_text:
        return None
    if not lat_text or not lon_text:
        raise ValueError('Both manual latitude and longitude are required')

    latitude = float(lat_text)
    longitude = float(lon_text)

    if not -90 <= latitude <= 90:
        raise ValueError('Manual latitude must be between -90 and 90')
    if not -180 <= longitude <= 180:
        raise ValueError('Manual longitude must be between -180 and 180')

    return latitude, longitude


def get_configured_dns_servers(config: dict) -> list[str]:
    """Return the custom DNS servers configured for test execution."""
    if not config.get('USE_CUSTOM_DNS'):
        return []
    return parse_dns_servers(config.get('CUSTOM_DNS_SERVERS'))


def apply_manual_location_override(
    network_info: dict,
    latitude: float,
    longitude: float,
    *,
    source: str = 'manual_config',
    method: str = 'Manual (Config)',
) -> None:
    """Overlay manual coordinates on detected network info."""
    location = dict(network_info.get('location') or {})
    geocoded = reverse_geocode_coordinates(latitude, longitude)

    location['lat'] = latitude
    location['lon'] = longitude
    location['accuracy'] = None
    location['source'] = source
    location['method'] = method
    location['is_precise'] = False
    location['input_mode'] = 'manual'
    location['city'] = geocoded.get('city')
    location['region'] = geocoded.get('region')
    location['country'] = geocoded.get('country')
    network_info['location'] = location


def apply_runtime_overrides(network_info: dict, config: dict) -> dict:
    """Apply DNS and location overrides from config onto detected network info."""
    info = dict(network_info or {})
    system_dns_servers = parse_dns_servers(info.get('dns_servers'))
    system_dns_primary = info.get('dns_primary')
    custom_dns_servers = get_configured_dns_servers(config)

    info['system_dns_primary'] = system_dns_primary
    info['system_dns_servers'] = system_dns_servers
    info['dns_override_enabled'] = bool(custom_dns_servers)

    if custom_dns_servers:
        info['dns_primary'] = custom_dns_servers[0]
        info['dns_servers'] = custom_dns_servers
        info['dns_source'] = 'custom'
    else:
        info['dns_servers'] = system_dns_servers
        info['dns_source'] = 'system'

    manual_coordinates = parse_manual_coordinates(
        config.get('MANUAL_LATITUDE'),
        config.get('MANUAL_LONGITUDE'),
    )
    if manual_coordinates is not None:
        apply_manual_location_override(
            info,
            manual_coordinates[0],
            manual_coordinates[1],
            source='manual_config',
            method='Manual (Config)',
        )

    info['connectivity_type'] = infer_browser_connectivity_type(info)

    return info


def infer_browser_connectivity_type(network_info: dict) -> str | None:
    """Infer browser connectivity conservatively using desktop-detected WiFi identity."""
    info = network_info or {}
    wifi_ssid = info.get('wifi_ssid')
    wifi_ssid_method = info.get('wifi_ssid_method')
    wifi_rssi = info.get('wifi_rssi')
    wifi_channel = info.get('wifi_channel')

    has_live_wifi_ssid = bool(wifi_ssid) and wifi_ssid_method not in (None, 'preferred')
    has_live_wifi_radio = wifi_rssi is not None or wifi_channel is not None

    if has_live_wifi_ssid or has_live_wifi_radio:
        return 'WiFi'

    # Fixed should stay null until desktop flow has explicit wired detection.
    return None


# Mapping from plain DNS server IPs to their DoH JSON API endpoints for fallback
DOH_ENDPOINTS = {
    '8.8.8.8': 'https://dns.google/resolve',
    '8.8.4.4': 'https://dns.google/resolve',
    '1.1.1.1': 'https://cloudflare-dns.com/dns-query',
    '1.0.0.1': 'https://cloudflare-dns.com/dns-query',
    '9.9.9.9': 'https://dns.quad9.net:5053/dns-query',
    '149.112.112.112': 'https://dns.quad9.net:5053/dns-query',
}

# Multiple DoH fallback URLs for resilience when ISP blocks specific providers
DOH_FALLBACK_URLS = [
    'https://dns.google/resolve',          # Google
    'https://cloudflare-dns.com/dns-query', # Cloudflare
    'https://dns.quad9.net:5053/dns-query', # Quad9
    'https://doh.opendns.com/dns-query',    # OpenDNS
]

DOH_FALLBACK_URL = 'https://dns.google/resolve'


def resolve_hostname_doh(
    hostname: str,
    doh_url: str = DOH_FALLBACK_URL,
    timeout: int = 15,
    add_log_fn=None
) -> str | None:
    """Resolve a hostname via DNS-over-HTTPS (DoH) using the JSON API.

    Returns the resolved IP address string or None on failure.
    This bypasses ISP transparent DNS proxying because the query
    travels over HTTPS (port 443) instead of plain DNS (port 53).
    """
    import ssl

    def log(msg, level='info'):
        if add_log_fn:
            add_log_fn(msg, level)
        else:
            print(f'  [DoH {level}] {msg}')

    params = urlencode({'name': hostname, 'type': 'A'})
    url = f'{doh_url}?{params}'
    req = urllib.request.Request(url, headers={
        'Accept': 'application/dns-json',
        'User-Agent': 'NOCTune/1.0',
    })

    ctx = ssl.create_default_context()
    try:
        with urllib.request.urlopen(req, timeout=timeout, context=ctx) as resp:
            data = json.loads(resp.read().decode())
            status = data.get('Status')
            # Status 0 = NOERROR, 3 = NXDOMAIN
            if status != 0:
                status_names = {0: 'NOERROR', 1: 'FORMERR', 2: 'SERVFAIL', 3: 'NXDOMAIN', 5: 'REFUSED'}
                status_name = status_names.get(status, f'CODE_{status}')
                log(f'DoH query returned {status_name} for {hostname} via {doh_url}', 'warning')
                return None
            for answer in data.get('Answer', []):
                # Type 1 = A record
                if answer.get('type') == 1:
                    resolved_ip = answer.get('data')
                    log(f'DoH resolved {hostname} → {resolved_ip} via {doh_url}', 'success')
                    return resolved_ip
            log(f'DoH query returned no A records for {hostname} via {doh_url}', 'warning')
    except urllib.error.HTTPError as e:
        log(f'DoH HTTP error {e.code} for {hostname} via {doh_url}: {e.reason}', 'error')
    except urllib.error.URLError as e:
        log(f'DoH connection failed for {hostname} via {doh_url}: {e.reason}', 'error')
    except json.JSONDecodeError as e:
        log(f'DoH invalid JSON response for {hostname} via {doh_url}: {e}', 'error')
    except ssl.SSLError as e:
        log(f'DoH SSL error for {hostname} via {doh_url}: {e}', 'error')
    except TimeoutError:
        log(f'DoH timeout ({timeout}s) for {hostname} via {doh_url}', 'error')
    except Exception as e:
        log(f'DoH unexpected error for {hostname} via {doh_url}: {type(e).__name__}: {e}', 'error')
    return None


def resolve_hostname_with_dns_servers(
    url: str,
    dns_servers: list[str],
    add_log_fn=None
) -> tuple[str, int, str, str] | None:
    """Resolve a URL hostname via the provided DNS servers for curl --resolve.

    If plain DNS (port 53) fails with NXDOMAIN (common when ISPs perform
    transparent DNS hijacking), automatically retries via DNS-over-HTTPS
    to bypass the interception using multiple DoH providers.
    """
    def log(msg, level='info'):
        if add_log_fn:
            add_log_fn(msg, level)
        else:
            print(f'  [{level}] {msg}')

    effective_dns_servers = parse_dns_servers(dns_servers)
    if not effective_dns_servers:
        return None
    dns_resolver_module = load_dns_resolver_module()
    if dns_resolver_module is None:
        raise RuntimeError('dnspython is required for custom DNS override but is not installed')

    parsed = urlparse(normalize_target_url(url))
    hostname = parsed.hostname
    if not hostname:
        raise ValueError(f'Unable to determine hostname from URL: {url}')

    port = parsed.port
    if port is None:
        port = 443 if parsed.scheme == 'https' else 80

    # --- Phase 1: Try plain DNS (port 53) ---
    last_dns_error = None
    for server in effective_dns_servers:
        resolver = dns_resolver_module.Resolver(configure=False)
        resolver.nameservers = [server]
        resolver.lifetime = 10
        try:
            answer = resolver.resolve(hostname, 'A')
            resolved_ip = answer[0].to_text()
            log(f'Plain DNS resolved {hostname} → {resolved_ip} via {server}', 'success')
            return hostname, port, resolved_ip, str(answer.nameserver)
        except dns_resolver_module.NXDOMAIN:
            log(f'Plain DNS returned NXDOMAIN for {hostname} via {server} (ISP may be blocking)', 'warning')
            last_dns_error = 'NXDOMAIN'
        except dns_resolver_module.NoAnswer:
            log(f'Plain DNS returned no answer for {hostname} via {server}', 'warning')
            last_dns_error = 'NoAnswer'
        except dns_resolver_module.Timeout:
            log(f'Plain DNS timed out for {hostname} via {server}', 'warning')
            last_dns_error = 'Timeout'
        except Exception as exc:
            log(f'Plain DNS error for {hostname} via {server}: {type(exc).__name__}', 'warning')
            last_dns_error = str(exc)

    # --- Phase 2: DoH fallback (bypasses ISP DNS interception) ---
    log(f'⚠️ Plain DNS failed ({last_dns_error}), trying DNS-over-HTTPS fallback...', 'warning')

    # First try DoH endpoints matching our configured DNS servers
    tried_doh_urls = set()
    for server in effective_dns_servers:
        doh_url = DOH_ENDPOINTS.get(server)
        if doh_url and doh_url not in tried_doh_urls:
            tried_doh_urls.add(doh_url)
            resolved_ip = resolve_hostname_doh(hostname, doh_url=doh_url, add_log_fn=add_log_fn)
            if resolved_ip:
                log(f'✅ DoH resolved {hostname} → {resolved_ip} via {doh_url}', 'success')
                return hostname, port, resolved_ip, f'{server} (DoH)'

    # Then try all remaining fallback DoH providers
    for doh_url in DOH_FALLBACK_URLS:
        if doh_url in tried_doh_urls:
            continue
        tried_doh_urls.add(doh_url)
        log(f'Trying additional DoH provider: {doh_url}', 'info')
        resolved_ip = resolve_hostname_doh(hostname, doh_url=doh_url, add_log_fn=add_log_fn)
        if resolved_ip:
            log(f'✅ DoH resolved {hostname} → {resolved_ip} via {doh_url}', 'success')
            return hostname, port, resolved_ip, f'DoH ({doh_url})'
    
    # Both plain DNS and DoH failed
    doh_providers_tried = ', '.join(sorted(tried_doh_urls))
    raise RuntimeError(
        f'DNS resolution failed for {hostname}. '
        f'Plain DNS: {last_dns_error}. '
        f'DoH providers tried: {doh_providers_tried}. '
        f'Your ISP may be blocking both DNS (port 53) and DoH providers. '
        f'Try using a VPN or different network.'
    )


def run_dns_trace(hostname: str, dns_server: str, timeout: int = 30) -> dict:
    """
    Execute dig @dns_server hostname +trace and parse the output.
    
    Returns a dict with:
      - hostname: the queried hostname
      - dns_server: the DNS server used for initial query
      - success: bool indicating if trace completed
      - raw_output: the full dig output
      - hops: list of delegation steps parsed from output
      - final_answer: the resolved IP(s) if successful
      - error: error message if failed
      - timestamp: when the trace was run
    """
    result = {
        'hostname': hostname,
        'dns_server': dns_server,
        'success': False,
        'raw_output': '',
        'hops': [],
        'final_answer': None,
        'error': None,
        'timestamp': datetime.now().isoformat(),
    }
    
    try:
        cmd = ['dig', f'@{dns_server}', hostname, '+trace', '+nodnssec']
        proc = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        result['raw_output'] = proc.stdout + proc.stderr
        
        if proc.returncode != 0:
            result['error'] = f'dig exited with code {proc.returncode}'
            return result
        
        # Parse the trace output
        lines = proc.stdout.split('\n')
        current_hop = None
        hops = []
        final_answers = []
        
        for line in lines:
            line = line.strip()
            if not line or line.startswith(';'):
                # Skip comments and empty lines, but check for section headers
                if ';; Received' in line:
                    # End of a hop section
                    if current_hop:
                        hops.append(current_hop)
                        current_hop = None
                continue
            
            # NS record delegation (e.g., "com. 172800 IN NS a.gtld-servers.net.")
            ns_match = re.match(r'^(\S+)\s+\d+\s+IN\s+NS\s+(\S+)', line)
            if ns_match:
                zone = ns_match.group(1)
                nameserver = ns_match.group(2)
                if current_hop is None or current_hop.get('zone') != zone:
                    if current_hop:
                        hops.append(current_hop)
                    current_hop = {'zone': zone, 'type': 'NS', 'nameservers': []}
                current_hop['nameservers'].append(nameserver)
                continue
            
            # A record (final answer or glue)
            a_match = re.match(r'^(\S+)\s+\d+\s+IN\s+A\s+(\S+)', line)
            if a_match:
                record_name = a_match.group(1)
                ip = a_match.group(2)
                # Check if this is the final answer for our hostname
                if record_name.rstrip('.') == hostname.rstrip('.'):
                    final_answers.append(ip)
                continue
        
        # Don't forget the last hop
        if current_hop:
            hops.append(current_hop)
        
        result['hops'] = hops
        result['final_answer'] = final_answers if final_answers else None
        result['success'] = len(final_answers) > 0
        
    except FileNotFoundError:
        result['error'] = 'dig command not found'
    except subprocess.TimeoutExpired:
        result['error'] = f'DNS trace timed out after {timeout}s'
    except Exception as e:
        result['error'] = str(e)
    
    return result


def run_dns_traces_for_session(
    targets: list[str],
    dns_servers: list[str],
    system_dns: list[str] | None = None,
    add_log_fn=None
) -> list[dict]:
    """
    Run DNS traces for all target/DNS combinations in a test session.
    
    Args:
        targets: list of target URLs to trace
        dns_servers: custom DNS servers configured for test (e.g., ['8.8.8.8', '8.8.4.4'])
        system_dns: system/ISP DNS servers (optional, for comparison)
        add_log_fn: optional logging function
    
    Returns:
        List of trace results for each target/DNS combination
    """
    def log(msg, level='info'):
        if add_log_fn:
            add_log_fn(msg, level)
        else:
            print(f'  [{level}] {msg}')
    
    # Check if dig is available
    try:
        subprocess.run(['dig', '-v'], capture_output=True, timeout=5)
    except FileNotFoundError:
        log('dig not found, skipping DNS trace', 'warning')
        return []
    except Exception as e:
        log(f'dig check failed: {e}, skipping DNS trace', 'warning')
        return []
    
    trace_results = []
    
    # Build list of DNS servers to test
    all_dns_servers = []
    
    # Add custom DNS servers
    for server in (dns_servers or []):
        if server and server not in all_dns_servers:
            all_dns_servers.append(server)
    
    # Add system DNS if provided and different from custom
    for server in (system_dns or []):
        if server and server not in all_dns_servers:
            all_dns_servers.append(server)
    
    if not all_dns_servers:
        log('No DNS servers configured for trace', 'warning')
        return []
    
    # Extract hostnames from target URLs
    hostnames = []
    for target in targets:
        parsed = urlparse(normalize_target_url(target))
        if parsed.hostname and parsed.hostname not in hostnames:
            hostnames.append(parsed.hostname)
    
    total_traces = len(hostnames) * len(all_dns_servers)
    log(f'Running DNS trace for {len(hostnames)} target(s) × {len(all_dns_servers)} DNS server(s) = {total_traces} trace(s)', 'info')
    
    trace_num = 0
    for hostname in hostnames:
        for dns_server in all_dns_servers:
            trace_num += 1
            log(f'  DNS trace {trace_num}/{total_traces}: {hostname} via @{dns_server}', 'info')
            
            trace_result = run_dns_trace(hostname, dns_server)
            trace_results.append(trace_result)
            
            if trace_result['success']:
                answers = ', '.join(trace_result['final_answer'] or [])
                hop_count = len(trace_result['hops'])
                log(f'    → Resolved to {answers} ({hop_count} hops)', 'success')
            else:
                log(f'    → Failed: {trace_result.get("error", "unknown error")}', 'warning')
    
    return trace_results


def sanitize_filename_part(value: str, fallback: str = "Unknown") -> str:
    """Convert arbitrary text to a safe filename fragment."""
    text = (value or fallback).strip()
    text = re.sub(r'[^A-Za-z0-9._-]+', '-', text)
    text = re.sub(r'-+', '-', text).strip('-._')
    return text or fallback


def reverse_geocode_coordinates(lat, lon) -> dict:
    """Resolve coordinates into city/region/country when possible."""
    if lat is None or lon is None:
        return {}

    try:
        rgeo_url = f"https://nominatim.openstreetmap.org/reverse?lat={lat}&lon={lon}&format=json&zoom=10"
        rgeo_req = urllib.request.Request(rgeo_url, headers={'User-Agent': 'NOC-Tune/1.0'})
        with urllib.request.urlopen(rgeo_req, timeout=5) as rgeo_resp:
            rgeo_data = json.loads(rgeo_resp.read().decode())
            addr = rgeo_data.get('address', {})
            return {
                'city': addr.get('city') or addr.get('town') or addr.get('municipality') or addr.get('county'),
                'region': addr.get('state') or addr.get('region'),
                'country': addr.get('country')
            }
    except Exception:
        return {}


def load_precise_location(max_age_hours: int = 24) -> dict | None:
    """Load recent browser geolocation data from disk."""
    if not PRECISE_LOCATION_FILE.exists():
        return None

    try:
        from datetime import timedelta
        with open(PRECISE_LOCATION_FILE, 'r') as f:
            precise_data = json.load(f)

        saved_at = precise_data.get('saved_at')
        if not saved_at:
            return None

        saved_time = datetime.fromisoformat(saved_at.replace('Z', '+00:00'))
        if datetime.now().astimezone() - saved_time >= timedelta(hours=max_age_hours):
            return None

        return precise_data
    except Exception:
        return None


def load_ui_template() -> str:
    """Load the HTML shell from disk."""
    return TEMPLATE_FILE.read_text(encoding='utf-8')


def read_static_asset(request_path: str) -> tuple[bytes, str] | None:
    """Read a static UI asset from disk."""
    asset = STATIC_ASSETS.get(request_path)
    if asset is None:
        print(f"[DEBUG] read_static_asset: '{request_path}' not found in STATIC_ASSETS keys: {list(STATIC_ASSETS.keys())}")
        return None

    file_path, content_type = asset
    print(f"[DEBUG] read_static_asset: reading '{file_path}' (exists: {file_path.exists()})")
    try:
        return file_path.read_bytes(), content_type
    except Exception as e:
        print(f"[DEBUG] read_static_asset: error reading file: {e}")
        return None

# Global state
test_queue = queue.Queue()
log_queue = queue.Queue()
test_running = False
test_paused = False
test_stopped = False
test_results = {}
current_session_dir = None


def parse_config(config_path: Path) -> dict:
    """Parse config.txt file."""
    config = {
        'TARGETS': ['https://www.google.com'],
        'SAMPLE_COUNT': 5,
        'DELAY_SECONDS': 2,
        'PING_DURATION': 10,
        'AUTO_CONTRIBUTE': True,
        'USE_CUSTOM_DNS': True,
        'CUSTOM_DNS_SERVERS': '8.8.8.8, 8.8.4.4',
        'SIGNAL_THRESHOLD_DBM': -70,
        'TTFB_GOOD_MS': 200,
        'TTFB_WARNING_MS': 500,
        'ONT_DNS': '',
        'IS_MOBILE': False,
        'BRAND': '',
        'NO_INTERNET': '',
        'MANUAL_LATITUDE': '',
        'MANUAL_LONGITUDE': '',
    }
    
    if not config_path.exists():
        return config
    
    try:
        with open(config_path, 'r') as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith('#'):
                    continue
                if '=' not in line:
                    continue
                
                key, value = line.split('=', 1)
                key = key.strip()
                value = value.strip()
                
                if key == 'TARGETS':
                    config['TARGETS'] = normalize_target_urls([t.strip() for t in value.split(',') if t.strip()])
                elif key in ['SAMPLE_COUNT', 'DELAY_SECONDS', 'PING_DURATION', 
                           'SIGNAL_THRESHOLD_DBM', 'TTFB_GOOD_MS', 'TTFB_WARNING_MS']:
                    config[key] = int(value)
                elif key in ['AUTO_CONTRIBUTE', 'USE_CUSTOM_DNS', 'IS_MOBILE']:
                    config[key] = value.lower() in ['true', '1', 'yes', 'on']
                elif key in ['ONT_DNS', 'BRAND', 'NO_INTERNET', 'CUSTOM_DNS_SERVERS', 'MANUAL_LATITUDE', 'MANUAL_LONGITUDE']:
                    config[key] = value
    except Exception as e:
        print(f"Error parsing config: {e}")
    
    return config


def save_config(config: dict, config_path: Path) -> bool:
    """Save config to file."""
    try:
        config_path.parent.mkdir(parents=True, exist_ok=True)
        normalized_targets = normalize_target_urls(config.get('TARGETS', []))
        
        with open(config_path, 'w') as f:
            f.write("# NOC Tune Configuration\n")
            f.write("# Auto-generated by TTFB Test UI\n")
            f.write(f"# Last updated: {datetime.now().isoformat()}\n\n")
            
            f.write("# Target URLs (comma-separated)\n")
            f.write(f"TARGETS = {', '.join(normalized_targets)}\n\n")
            
            f.write("# Test Parameters\n")
            f.write(f"SAMPLE_COUNT = {config.get('SAMPLE_COUNT', 5)}\n")
            f.write(f"DELAY_SECONDS = {config.get('DELAY_SECONDS', 2)}\n")
            f.write(f"PING_DURATION = {config.get('PING_DURATION', 10)}\n")
            f.write(f"AUTO_CONTRIBUTE = {'True' if config.get('AUTO_CONTRIBUTE', True) else 'False'}\n\n")

            f.write("# DNS override for test requests only (does not change OS DNS)\n")
            f.write(f"USE_CUSTOM_DNS = {'True' if config.get('USE_CUSTOM_DNS', True) else 'False'}\n")
            f.write(f"CUSTOM_DNS_SERVERS = {', '.join(parse_dns_servers(config.get('CUSTOM_DNS_SERVERS', '8.8.8.8, 8.8.4.4')))}\n\n")
            
            f.write("# Thresholds\n")
            f.write(f"SIGNAL_THRESHOLD_DBM = {config.get('SIGNAL_THRESHOLD_DBM', -70)}\n")
            f.write(f"TTFB_GOOD_MS = {config.get('TTFB_GOOD_MS', 200)}\n")
            f.write(f"TTFB_WARNING_MS = {config.get('TTFB_WARNING_MS', 500)}\n\n")

            f.write("# Optional: Manual coordinates if browser geolocation is unavailable\n")
            f.write(f"MANUAL_LATITUDE = {config.get('MANUAL_LATITUDE', '')}\n")
            f.write(f"MANUAL_LONGITUDE = {config.get('MANUAL_LONGITUDE', '')}\n\n")
            
            f.write("# Optional: ONT DNS (fallback if auto-detect fails)\n")
            f.write(f"ONT_DNS = {config.get('ONT_DNS', '')}\n\n")

            f.write("# Optional: Contribution metadata\n")
            f.write(f"IS_MOBILE = {'True' if config.get('IS_MOBILE', False) else 'False'}\n")
            f.write(f"BRAND = {config.get('BRAND', '')}\n")
            f.write(f"NO_INTERNET = {config.get('NO_INTERNET', '')}\n")
        
        return True
    except Exception as e:
        print(f"Error saving config: {e}")
        return False


def check_prerequisites() -> dict:
    """Check system prerequisites."""
    results = {
        'curl': {'status': 'checking', 'message': '', 'required': True},
        'ping': {'status': 'checking', 'message': '', 'required': True},
        'network': {'status': 'checking', 'message': '', 'required': True},
        'wifi': {'status': 'checking', 'message': '', 'required': False},
        'custom_dns': {'status': 'checking', 'message': '', 'required': True},
        'dig': {'status': 'checking', 'message': '', 'required': False},
        'python_packages': {'status': 'checking', 'message': '', 'required': False}
    }
    
    # Check curl
    try:
        proc = subprocess.run(['curl', '--version'], capture_output=True, text=True, timeout=5)
        if proc.returncode == 0:
            version = proc.stdout.split('\n')[0]
            results['curl'] = {'status': 'ok', 'message': version, 'required': True}
        else:
            results['curl'] = {'status': 'error', 'message': 'curl not working properly', 'required': True}
    except FileNotFoundError:
        results['curl'] = {'status': 'error', 'message': 'curl not found. Please install curl.', 'required': True}
    except Exception as e:
        results['curl'] = {'status': 'error', 'message': str(e), 'required': True}
    
    # Check ping
    try:
        if platform.system() == 'Windows':
            proc = subprocess.run(['ping', '-n', '1', '127.0.0.1'], capture_output=True, timeout=5)
        else:
            proc = subprocess.run(['ping', '-c', '1', '127.0.0.1'], capture_output=True, timeout=5)
        
        if proc.returncode == 0:
            results['ping'] = {'status': 'ok', 'message': 'ping available', 'required': True}
        else:
            results['ping'] = {'status': 'error', 'message': 'ping not working', 'required': True}
    except Exception as e:
        results['ping'] = {'status': 'error', 'message': str(e), 'required': True}
    
    # Check network connectivity
    try:
        req = urllib.request.Request('https://www.google.com', method='HEAD')
        with urllib.request.urlopen(req, timeout=10) as response:
            results['network'] = {'status': 'ok', 'message': 'Internet connected', 'required': True}
    except Exception as e:
        results['network'] = {'status': 'error', 'message': f'No internet: {str(e)}', 'required': True}
    
    # Check WiFi detection
    system = platform.system()
    wifi_status = 'unknown'
    wifi_message = ''
    
    if system == 'Darwin':
        try:
            proc = subprocess.run(['networksetup', '-getairportnetwork', 'en0'], 
                                capture_output=True, text=True, timeout=5)
            if 'Current Wi-Fi Network' in proc.stdout:
                wifi_status = 'ok'
                wifi_message = 'WiFi connected'
            else:
                wifi_status = 'warning'
                wifi_message = 'WiFi not connected or detection failed'
        except:
            wifi_status = 'warning'
            wifi_message = 'Could not check WiFi'
    elif system == 'Windows':
        try:
            proc = subprocess.run(['netsh', 'wlan', 'show', 'interfaces'], 
                                capture_output=True, text=True, timeout=5)
            if 'connected' in proc.stdout.lower():
                wifi_status = 'ok'
                wifi_message = 'WiFi connected'
            else:
                wifi_status = 'warning'
                wifi_message = 'WiFi not connected'
        except:
            wifi_status = 'warning'
            wifi_message = 'Could not check WiFi'
    else:
        wifi_status = 'warning'
        wifi_message = 'WiFi check not implemented for this OS'
    
    results['wifi'] = {'status': wifi_status, 'message': wifi_message, 'required': False}

    # Check custom DNS support
    if load_dns_resolver_module() is None:
        results['custom_dns'] = {
            'status': 'error',
            'message': 'dnspython is missing. Run: pip install dnspython',
            'required': True,
        }
    else:
        results['custom_dns'] = {
            'status': 'ok',
            'message': 'Custom DNS resolver available',
            'required': True,
        }
    
    # Check dig (for DNS trace)
    try:
        proc = subprocess.run(['dig', '-v'], capture_output=True, text=True, timeout=5)
        # dig -v outputs version to stderr
        version_output = proc.stderr or proc.stdout
        version_line = version_output.split('\n')[0] if version_output else 'dig available'
        results['dig'] = {'status': 'ok', 'message': version_line.strip(), 'required': False}
    except FileNotFoundError:
        results['dig'] = {
            'status': 'warning',
            'message': 'dig not found. DNS trace feature unavailable. Install: brew install bind (macOS) or apt install dnsutils (Linux)',
            'required': False
        }
    except Exception as e:
        results['dig'] = {'status': 'warning', 'message': f'dig check failed: {str(e)}', 'required': False}

    # Check Python packages
    package_specs = [
        ('pandas', 'pandas'),
        ('numpy', 'numpy'),
        ('matplotlib', 'matplotlib'),
        ('tqdm', 'tqdm'),
    ]
    missing_packages = []
    installed_packages = []
    for module_name, package_name in package_specs:
        try:
            module = importlib.import_module(module_name)
            version = getattr(module, '__version__', None)
            installed_packages.append(f'{package_name} {version}' if version else package_name)
        except ImportError:
            missing_packages.append(package_name)
    
    if missing_packages:
        results['python_packages'] = {
            'status': 'warning',
            'message': (
                f'Optional for notebook/report workflows: missing {", ".join(missing_packages)}. '
                f'Interpreter: {sys.executable}. '
                f'Run: pip install {" ".join(missing_packages)}'
            ),
            'required': False
        }
    else:
        results['python_packages'] = {
            'status': 'ok',
            'message': f'Optional analysis packages installed via {sys.executable}: {", ".join(installed_packages)}',
            'required': False,
        }
    
    return results


def add_log(message: str, level: str = 'info'):
    """Add a log message to the queue."""
    timestamp = datetime.now().strftime('%H:%M:%S')
    log_queue.put({
        'timestamp': timestamp,
        'level': level,
        'message': message
    })
    # Mirror to terminal
    if level == 'divider':
        print(f'  {"-" * 50}')
    elif message:
        level_icons = {'info': '[i]', 'success': '[OK]', 'warning': '[!]', 'error': '[X]'}
        icon = level_icons.get(level, ' ')
        print(f'  {icon}  {message}')


def measure_ttfb(
    url: str,
    *,
    ttfb_good_ms: int | None = None,
    ttfb_warning_ms: int | None = None,
    dns_servers: list[str] | None = None,
    add_log_fn=None,
) -> dict:
    """Measure TTFB for a single URL, including dig trace output."""
    normalized_url = normalize_target_url(url)
    curl_format = (
        '{"time_namelookup": %{time_namelookup}, '
        '"time_connect": %{time_connect}, '
        '"time_appconnect": %{time_appconnect}, '
        '"time_starttransfer": %{time_starttransfer}, '
        '"time_total": %{time_total}, '
        '"http_code": %{http_code}}'
    )
    
    null_device = 'NUL' if platform.system() == 'Windows' else '/dev/null'
    
    cmd = [
        'curl',
        '-o', null_device,
        '-s',
        '-w', curl_format,
        '--max-time', '30',
        normalized_url
    ]

    resolved_ip = None
    dig_output = None
    dig_query_time_ms = None

    try:
        resolved_host = resolve_hostname_with_dns_servers(
            normalized_url,
            dns_servers or [],
            add_log_fn=add_log_fn
        )
        if resolved_host is not None:
            hostname, port, resolved_ip, resolved_dns_server = resolved_host
            cmd[6:6] = ['--resolve', f'{hostname}:{port}:{resolved_ip}']
            
            # Run dig @dns_server hostname +trace for this specific DNS server
            try:
                dig_cmd = ['dig', f'@{resolved_dns_server}', hostname, '+trace', '+nodnssec']
                dig_proc = subprocess.run(dig_cmd, capture_output=True, text=True, timeout=30)
                dig_output = dig_proc.stdout + dig_proc.stderr
                
                # Parse query time from dig output (";; Query time: XX msec")
                query_time_match = re.search(r';;\s*Received\s+\d+\s+bytes\s+from\s+\S+\s+in\s+(\d+)\s*ms', dig_output)
                if query_time_match:
                    dig_query_time_ms = float(query_time_match.group(1))
            except FileNotFoundError:
                dig_output = 'dig command not found'
            except subprocess.TimeoutExpired:
                dig_output = 'dig timed out'
            except Exception as e:
                dig_output = f'dig error: {e}'
        else:
            resolved_dns_server = None
    except Exception as exc:
        result = {
            'url': normalized_url,
            'ttfb_ms': None,
            'lookup_ms': None,
            'connect_ms': None,
            'total_ms': None,
            'http_code': None,
            'status': 'error',
            'error': f'Custom DNS resolution failed: {exc}',
            'dns_primary': None,
            'dns_servers': [],
            'resolved_ip': None,
            'dig_output': None,
            'dig_query_time_ms': None,
        }
        return result
    
    result = {
        'url': normalized_url,
        'ttfb_ms': None,
        'lookup_ms': None,
        'connect_ms': None,
        'total_ms': None,
        'http_code': None,
        'status': 'unknown',
        'error': None,
        'dns_primary': resolved_dns_server,
        'dns_servers': [resolved_dns_server] if resolved_dns_server else [],
        'resolved_ip': resolved_ip,
        'dig_output': dig_output,
        'dig_query_time_ms': dig_query_time_ms,
    }
    
    try:
        proc = subprocess.run(cmd, capture_output=True, text=True, timeout=35)
        
        if proc.returncode == 0:
            data = json.loads(proc.stdout)
            result['lookup_ms'] = round(data['time_namelookup'] * 1000, 2)
            result['connect_ms'] = round(data['time_connect'] * 1000, 2)
            result['ttfb_ms'] = round(data['time_starttransfer'] * 1000, 2)
            result['total_ms'] = round(data['time_total'] * 1000, 2)
            result['http_code'] = data['http_code']
            
            config = parse_config(CONFIG_FILE)
            good_threshold = ttfb_good_ms if ttfb_good_ms is not None else config['TTFB_GOOD_MS']
            warning_threshold = ttfb_warning_ms if ttfb_warning_ms is not None else config['TTFB_WARNING_MS']
            if result['ttfb_ms'] < good_threshold:
                result['status'] = 'good'
            elif result['ttfb_ms'] < warning_threshold:
                result['status'] = 'warning'
            else:
                result['status'] = 'poor'
        else:
            result['error'] = proc.stderr or f'Exit code: {proc.returncode}'
            result['status'] = 'error'
    except subprocess.TimeoutExpired:
        result['error'] = 'Timeout (>30s)'
        result['status'] = 'timeout'
    except Exception as e:
        result['error'] = str(e)
        result['status'] = 'error'
    
    return result


def detect_network_info() -> dict:
    """Detect current network information."""
    info = {
        'device_name': None,
        'device_model': None,
        'os_name': None,
        'os_version': None,
        'battery_level': None,
        'battery_charging': None,
        'wifi_ssid': None,
        'wifi_ssid_method': None,
        'wifi_rssi': None,
        'wifi_band': None,
        'wifi_channel': None,
        'connectivity_type': None,
        'dns_primary': None,
        'dns_servers': [],
        'location': None,
        'signal_status': None,
        'signal_threshold': -70
    }
    
    system = platform.system()
    
    # Get OS info
    info['os_name'] = system
    try:
        if system == 'Darwin':
            proc = subprocess.run(['sw_vers', '-productVersion'], capture_output=True, text=True, timeout=5)
            if proc.returncode == 0:
                info['os_version'] = f"macOS {proc.stdout.strip()}"
        elif system == 'Windows':
            info['os_version'] = f"Windows {platform.release()}"
        else:
            info['os_version'] = f"{system} {platform.release()}"
    except:
        info['os_version'] = platform.release()
    
    # Get device model
    if system == 'Darwin':
        try:
            # Get Mac model identifier
            proc = subprocess.run(['sysctl', '-n', 'hw.model'], capture_output=True, text=True, timeout=5)
            if proc.returncode == 0:
                model_id = proc.stdout.strip()
                # Try to get human-readable name
                proc2 = subprocess.run(
                    ['system_profiler', 'SPHardwareDataType'],
                    capture_output=True, text=True, timeout=10
                )
                if proc2.returncode == 0:
                    match = re.search(r'Model Name:\s*(.+)', proc2.stdout)
                    if match:
                        info['device_model'] = match.group(1).strip()
                    else:
                        info['device_model'] = model_id
                else:
                    info['device_model'] = model_id
        except:
            pass
    elif system == 'Windows':
        try:
            proc = subprocess.run(['wmic', 'computersystem', 'get', 'model'], 
                                capture_output=True, text=True, timeout=5)
            if proc.returncode == 0:
                lines = [l.strip() for l in proc.stdout.strip().split('\n') if l.strip() and l.strip() != 'Model']
                if lines:
                    info['device_model'] = lines[0]
        except:
            pass
    
    # Get battery info
    if system == 'Darwin':
        try:
            proc = subprocess.run(['pmset', '-g', 'batt'], capture_output=True, text=True, timeout=5)
            if proc.returncode == 0:
                output = proc.stdout
                # Parse battery percentage
                match = re.search(r'(\d+)%', output)
                if match:
                    info['battery_level'] = int(match.group(1))
                # Check if charging
                info['battery_charging'] = 'AC Power' in output or 'charging' in output.lower()
        except:
            pass
    elif system == 'Windows':
        try:
            proc = subprocess.run(['WMIC', 'PATH', 'Win32_Battery', 'Get', 'EstimatedChargeRemaining,BatteryStatus'],
                                capture_output=True, text=True, timeout=5)
            if proc.returncode == 0:
                lines = proc.stdout.strip().split('\n')
                if len(lines) > 1:
                    parts = lines[1].split()
                    if len(parts) >= 2:
                        info['battery_level'] = int(parts[1]) if parts[1].isdigit() else None
                        info['battery_charging'] = parts[0] == '2'  # 2 = charging
        except:
            pass
    
    # Get device name
    if system == 'Darwin':
        try:
            proc = subprocess.run(['scutil', '--get', 'ComputerName'],
                                capture_output=True, text=True, timeout=5)
            if proc.returncode == 0:
                info['device_name'] = proc.stdout.strip()
        except:
            pass
    elif system == 'Windows':
        try:
            info['device_name'] = platform.node() or os.environ.get('COMPUTERNAME')
        except:
            pass
    else:
        try:
            info['device_name'] = platform.node()
        except:
            pass
    
    # Detect WiFi
    if system == 'Darwin':
        # Method 1: Try CoreWLAN first (most reliable for SSID and RSSI)
        try:
            from CoreWLAN import CWWiFiClient
            client = CWWiFiClient.sharedWiFiClient()
            interface = client.interface()
            if interface:
                info['wifi_rssi'] = interface.rssiValue()
                ssid = interface.ssid()
                if ssid:
                    info['wifi_ssid'] = ssid
                    info['wifi_ssid_method'] = 'corewlan'
                channel = interface.wlanChannel()
                if channel:
                    info['wifi_channel'] = channel.channelNumber()
                    info['wifi_band'] = '5GHz' if info['wifi_channel'] >= 36 else '2.4GHz'
        except ImportError:
            pass  # CoreWLAN not installed
        except Exception:
            pass
        
        # Method 2: Try airport command (very reliable for RSSI and SSID)
        if not info['wifi_ssid'] or info['wifi_rssi'] is None:
            try:
                airport_path = '/System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport'
                proc = subprocess.run([airport_path, '-I'], capture_output=True, text=True, timeout=5)
                if proc.returncode == 0:
                    output = proc.stdout
                    # Parse SSID
                    ssid_match = re.search(r'^\s*SSID:\s*(.+)$', output, re.MULTILINE)
                    if ssid_match and not info['wifi_ssid']:
                        info['wifi_ssid'] = ssid_match.group(1).strip()
                        info['wifi_ssid_method'] = 'airport'
                    # Parse RSSI (agrCtlRSSI)
                    rssi_match = re.search(r'^\s*agrCtlRSSI:\s*(-?\d+)$', output, re.MULTILINE)
                    if rssi_match and info['wifi_rssi'] is None:
                        info['wifi_rssi'] = int(rssi_match.group(1))
                    # Parse channel
                    channel_match = re.search(r'^\s*channel:\s*(\d+)', output, re.MULTILINE)
                    if channel_match and not info['wifi_channel']:
                        info['wifi_channel'] = int(channel_match.group(1))
                        info['wifi_band'] = '5GHz' if info['wifi_channel'] >= 36 else '2.4GHz'
            except:
                pass
        
        # Method 3: Try networksetup for SSID (works without extra packages)
        if not info['wifi_ssid']:
            try:
                # Try en0 first (usually WiFi)
                for iface in ['en0', 'en1']:
                    proc = subprocess.run(['networksetup', '-getairportnetwork', iface],
                                        capture_output=True, text=True, timeout=5)
                    match = re.search(r'Current Wi-Fi Network: (.+)', proc.stdout)
                    if match:
                        info['wifi_ssid'] = match.group(1).strip()
                        info['wifi_ssid_method'] = 'networksetup'
                        break
            except:
                pass
        
        # Method 4: Try system_profiler for channel/band info
        if not info['wifi_channel']:
            try:
                proc = subprocess.run(['system_profiler', 'SPAirPortDataType', '-json'],
                                    capture_output=True, text=True, timeout=15)
                if proc.returncode == 0:
                    data = json.loads(proc.stdout)
                    airport_data = data.get('SPAirPortDataType', [])
                    for item in airport_data:
                        interfaces = item.get('spairport_airport_interfaces', [])
                        for iface in interfaces:
                            current_network = iface.get('spairport_current_network_information', {})
                            if current_network:
                                ssid_name = current_network.get('_name')
                                if not info['wifi_ssid'] and ssid_name and ssid_name != '<redacted>':
                                    info['wifi_ssid'] = ssid_name
                                    info['wifi_ssid_method'] = 'system_profiler'
                                channel_str = current_network.get('spairport_current_network_information_channel', '')
                                if channel_str:
                                    ch_match = re.search(r'(\d+)', str(channel_str))
                                    if ch_match:
                                        info['wifi_channel'] = int(ch_match.group(1))
                                        info['wifi_band'] = '5GHz' if info['wifi_channel'] >= 36 else '2.4GHz'
                                break
            except:
                pass
        
        # Method 5: Get channel from SystemConfiguration (reliable on macOS 26+)
        if not info['wifi_channel']:
            try:
                proc = subprocess.run(['scutil'], input='show State:/Network/Interface/en0/AirPort\nquit\n',
                                    capture_output=True, text=True, timeout=5)
                ch_match = re.search(r'CHANNEL\s*:\s*(\d+)', proc.stdout)
                if ch_match:
                    info['wifi_channel'] = int(ch_match.group(1))
                    info['wifi_band'] = '5GHz' if info['wifi_channel'] >= 36 else '2.4GHz'
            except:
                pass
        
        # Method 6: Fallback - use first preferred wireless network (macOS 26+ redacts SSID)
        if not info['wifi_ssid'] or info['wifi_ssid'] in (None, '<redacted>'):
            try:
                proc = subprocess.run(['networksetup', '-listpreferredwirelessnetworks', 'en0'],
                                    capture_output=True, text=True, timeout=5)
                preferred = [l.strip() for l in proc.stdout.splitlines()[1:] if l.strip()]
                if preferred:
                    info['wifi_ssid'] = preferred[0]
                    info['wifi_ssid_method'] = 'preferred'  # Mark as best-guess
            except:
                pass
        
        # Get DNS
        try:
            proc = subprocess.run(['scutil', '--dns'], capture_output=True, text=True, timeout=10)
            matches = re.findall(r'nameserver\[\d+\]\s*:\s*(\d+\.\d+\.\d+\.\d+)', proc.stdout)
            if matches:
                info['dns_servers'] = list(dict.fromkeys(matches))[:4]
                info['dns_primary'] = info['dns_servers'][0]
        except:
            pass
            
    elif system == 'Windows':
        try:
            proc = subprocess.run(['netsh', 'wlan', 'show', 'interfaces'],
                                capture_output=True, text=True, timeout=10)
            output = proc.stdout or proc.stderr or ''

            ssid_value = extract_windows_netsh_field(output, ['ssid'])
            if ssid_value and not ssid_value.lower().startswith('bssid'):
                info['wifi_ssid'] = ssid_value
                info['wifi_ssid_method'] = 'netsh'

            signal_match = re.search(r'(?:signal|sinyal)\s*:\s*(\d+)%', output, flags=re.IGNORECASE)
            if signal_match:
                signal_pct = int(signal_match.group(1))
                info['wifi_rssi'] = int(round(-100 + (signal_pct * 0.7)))

            channel_match = re.search(r'(?:channel|kanal)\s*:\s*(\d+)', output, flags=re.IGNORECASE)
            if channel_match:
                info['wifi_channel'] = int(channel_match.group(1))
                info['wifi_band'] = '5GHz' if info['wifi_channel'] >= 36 else '2.4GHz'

            if not info['wifi_ssid']:
                profile_match = re.search(r'Profile\s*:\s*(.+)', output, flags=re.IGNORECASE)
                if profile_match:
                    profile_value = clean_windows_netsh_value(profile_match.group(1))
                    if profile_value:
                        info['wifi_ssid'] = profile_value
                        info['wifi_ssid_method'] = 'netsh-profile'
        except Exception:
            pass
        
        try:
            proc = subprocess.run(['ipconfig', '/all'], capture_output=True, text=True, timeout=10)
            matches = re.findall(r'DNS Servers[\s.]*:\s*(\d+\.\d+\.\d+\.\d+)', proc.stdout)
            if matches:
                info['dns_servers'] = list(dict.fromkeys(matches))[:4]
                info['dns_primary'] = info['dns_servers'][0]
        except:
            pass
    
    # Get location via IP
    try:
        url = "http://ip-api.com/json/?fields=status,city,regionName,country,lat,lon,isp,query"
        req = urllib.request.Request(url, headers={'User-Agent': 'NOC-Tune/1.0'})
        with urllib.request.urlopen(req, timeout=10) as response:
            data = json.loads(response.read().decode())
            if data.get('status') == 'success':
                info['location'] = {
                    'city': data.get('city'),
                    'region': data.get('regionName'),
                    'country': data.get('country'),
                    'lat': data.get('lat'),
                    'lon': data.get('lon'),
                    'isp': data.get('isp'),
                    'ip': data.get('query'),
                    'is_precise': False,
                    'method': 'IP Geolocation'
                }
    except:
        pass
    
    # Overlay precise browser location when available
    precise_data = load_precise_location()
    if precise_data:
        if info.get('location') is None:
            info['location'] = {}

        info['location']['lat'] = precise_data.get('latitude')
        info['location']['lon'] = precise_data.get('longitude')
        info['location']['accuracy'] = precise_data.get('accuracy')
        info['location']['altitude'] = precise_data.get('altitude')
        info['location']['altitude_accuracy'] = precise_data.get('altitudeAccuracy')
        info['location']['heading'] = precise_data.get('heading')
        info['location']['speed'] = precise_data.get('speed')
        info['location']['browser_timestamp'] = precise_data.get('timestamp')
        info['location']['saved_at'] = precise_data.get('saved_at')
        info['location']['source'] = precise_data.get('source') or 'browser_geolocation'
        info['location']['is_precise'] = True
        info['location']['method'] = precise_data.get('method') or 'GPS (Browser)'

        has_precise_labels = False
        if precise_data.get('city'):
            info['location']['city'] = precise_data.get('city')
            has_precise_labels = True
        if precise_data.get('region'):
            info['location']['region'] = precise_data.get('region')
            has_precise_labels = True
        if precise_data.get('country'):
            info['location']['country'] = precise_data.get('country')
            has_precise_labels = True

        if not has_precise_labels:
            info['location']['city'] = None
            info['location']['region'] = None
            info['location']['country'] = None
            geocoded = reverse_geocode_coordinates(precise_data.get('latitude'), precise_data.get('longitude'))
            if geocoded.get('city'):
                info['location']['city'] = geocoded['city']
            if geocoded.get('region'):
                info['location']['region'] = geocoded['region']
            if geocoded.get('country'):
                info['location']['country'] = geocoded['country']
    
    return info


def get_local_ip() -> str | None:
    import socket

    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        sock.connect(("8.8.8.8", 80))
        local_ip = sock.getsockname()[0]
        sock.close()
        return local_ip
    except Exception:
        return None


def build_network_snapshot(include_debug: bool = False) -> dict:
    network_info = apply_runtime_overrides(detect_network_info(), parse_config(CONFIG_FILE))
    network_info['local_ip'] = get_local_ip()
    if include_debug:
        network_info['wifi_debug'] = get_windows_netsh_debug()
    return network_info


def get_windows_netsh_debug() -> dict:
    debug = {
        'platform': platform.system(),
        'command': 'netsh wlan show interfaces',
        'returncode': None,
        'stdout': '',
        'stderr': '',
        'parsed_ssid': None,
        'parsed_method': None,
        'parsed_rssi': None,
        'parsed_channel': None,
        'parsed_band': None,
    }

    if platform.system() != 'Windows':
        debug['stderr'] = 'netsh debug is only available on Windows.'
        return debug

    try:
        proc = subprocess.run(
            ['netsh', 'wlan', 'show', 'interfaces'],
            capture_output=True,
            text=True,
            timeout=10,
        )
        output = proc.stdout or ''
        debug['returncode'] = proc.returncode
        debug['stdout'] = output
        debug['stderr'] = proc.stderr or ''

        ssid_value = extract_windows_netsh_field(output, ['ssid'])
        if ssid_value and not ssid_value.lower().startswith('bssid'):
            debug['parsed_ssid'] = ssid_value
            debug['parsed_method'] = 'netsh'

        signal_match = re.search(r'(?:signal|sinyal)\s*:\s*(\d+)%', output, flags=re.IGNORECASE)
        if signal_match:
            signal_pct = int(signal_match.group(1))
            debug['parsed_rssi'] = int(round(-100 + (signal_pct * 0.7)))

        channel_match = re.search(r'(?:channel|kanal)\s*:\s*(\d+)', output, flags=re.IGNORECASE)
        if channel_match:
            debug['parsed_channel'] = int(channel_match.group(1))
            debug['parsed_band'] = '5GHz' if debug['parsed_channel'] >= 36 else '2.4GHz'

        if not debug['parsed_ssid']:
            profile_match = re.search(r'Profile\s*:\s*(.+)', output, flags=re.IGNORECASE)
            if profile_match:
                profile_value = clean_windows_netsh_value(profile_match.group(1))
                if profile_value:
                    debug['parsed_ssid'] = profile_value
                    debug['parsed_method'] = 'netsh-profile'
    except Exception as exc:
        debug['stderr'] = str(exc)

    return debug


def run_tests(config: dict):
    """Run TTFB tests."""
    global test_running, test_results, current_session_dir, test_stopped, test_paused
    
    test_running = True
    test_stopped = False
    test_paused = False
    test_start_time = datetime.now()
    test_results = {
        'session_id': datetime.now().strftime('%Y%m%d_%H%M%S'),
        'start_time': test_start_time.isoformat(),
        'config': config,
        'network_info': {},
        'ping_result': {},
        'ttfb_results': [],
        'summary': {},
        'status': 'running',
        'elapsed_seconds': 0,
        'contribution': {'status': 'idle', 'submitted': 0, 'failed': 0, 'total': 0},
        '_start_time_obj': test_start_time  # For internal calculation
    }
    
    try:
        # Detect network info
        add_log('Detecting network information...', 'info')
        test_results['network_info'] = apply_runtime_overrides(detect_network_info(), config)
        
        # Add signal threshold from config to network_info
        test_results['network_info']['signal_threshold'] = config.get('SIGNAL_THRESHOLD_DBM', -70)
        
        wifi_info = test_results['network_info']
        threshold = wifi_info.get('signal_threshold', -70)
        rssi = wifi_info.get('wifi_rssi')
        
        # Log signal status with threshold
        if rssi is not None:
            signal_status = '✅ Good' if rssi >= threshold else '⚠️ Weak'
            add_log(f"Signal: {signal_status} (RSSI: {rssi} dBm, threshold: {threshold} dBm)", 'info' if rssi >= threshold else 'warning')
        else:
            add_log("Signal: ❓ Unknown (RSSI not detected)", 'warning')
        
        if wifi_info.get('wifi_ssid'):
            add_log(f"SSID: {wifi_info['wifi_ssid']}", 'info')
        else:
            add_log("SSID: Not detected", 'warning')
            
        if wifi_info.get('wifi_band'):
            channel_str = f" (Channel {wifi_info.get('wifi_channel')})" if wifi_info.get('wifi_channel') else ""
            add_log(f"Band: {wifi_info['wifi_band']}{channel_str}", 'info')
        if wifi_info.get('dns_primary'):
            dns_label = 'Test DNS' if wifi_info.get('dns_override_enabled') else 'DNS'
            add_log(f"{dns_label}: {wifi_info['dns_primary']}", 'info')
            if wifi_info.get('dns_override_enabled') and wifi_info.get('system_dns_primary'):
                add_log(f"System DNS: {wifi_info['system_dns_primary']}", 'info')
        if wifi_info.get('location'):
            loc = wifi_info['location']
            method = loc.get('method') or ('GPS' if loc.get('is_precise') else 'IP')
            add_log(f"Location: {loc.get('city')}, {loc.get('country')} [{method}]", 'info')
            if loc.get('isp'):
                add_log(f"ISP: {loc.get('isp')}", 'info')
        
        # Create session directory
        signal_cat = 'good_signal' if (rssi or 0) >= threshold else 'bad_signal'
        if rssi is None:
            signal_cat = 'unknown_signal'
        
        band_short = (wifi_info.get('wifi_band') or 'Unknown').replace('.', '_').replace('GHz', 'G')
        dns_short = (wifi_info.get('dns_primary') or 'UnknownDNS').replace('.', '-')
        
        session_name = f"session_{signal_cat}_{band_short}_{dns_short}_{test_results['session_id']}"
        current_session_dir = RESULTS_DIR / session_name
        current_session_dir.mkdir(parents=True, exist_ok=True)
        
        add_log(f"Session: {session_name}", 'info')
        
        # Run ping test
        add_log('', 'divider')
        add_log('Running ping test to 8.8.8.8...', 'info')
        
        ping_count = config.get('PING_DURATION', 10)
        if platform.system() == 'Windows':
            ping_cmd = ['ping', '-n', str(ping_count), '8.8.8.8']
        else:
            ping_cmd = ['ping', '-c', str(ping_count), '8.8.8.8']
        
        try:
            proc = subprocess.run(ping_cmd, capture_output=True, text=True, timeout=ping_count + 30)
            ping_output = proc.stdout
            
            # Parse ping results
            if platform.system() == 'Windows':
                match = re.search(r'Average = (\d+)ms', ping_output)
                avg_ping = int(match.group(1)) if match else None
            else:
                match = re.search(r'min/avg/max/(?:mdev|stddev) = [\d.]+/([\d.]+)/', ping_output)
                avg_ping = float(match.group(1)) if match else None
            
            test_results['ping_result'] = {
                'host': '8.8.8.8',
                'avg_ms': avg_ping,
                'raw': ping_output
            }
            
            if avg_ping:
                add_log(f"Ping average: {avg_ping} ms", 'success')
            else:
                add_log('Ping completed (could not parse average)', 'warning')
            
            # Save ping result
            with open(current_session_dir / 'ping_result.txt', 'w') as f:
                f.write(ping_output)
                
        except Exception as e:
            add_log(f"Ping error: {e}", 'error')
            test_results['ping_result'] = {'error': str(e)}
        
        # Run TTFB tests
        add_log('', 'divider')
        add_log('Starting TTFB tests...', 'info')
        
        targets = config.get('TARGETS', [])
        sample_count = config.get('SAMPLE_COUNT', 5)
        delay = config.get('DELAY_SECONDS', 2)
        auto_contribute = config.get('AUTO_CONTRIBUTE', True)
        dns_test_scenarios = [[server] for server in (wifi_info.get('dns_servers') or [])] if wifi_info.get('dns_override_enabled') else [None]
        total_samples = len(targets) * sample_count * len(dns_test_scenarios)
        test_results['total_samples'] = total_samples
        test_results['dns_scenario_count'] = len(dns_test_scenarios)
        contribution_errors = []

        if auto_contribute:
            test_results['contribution'] = {'status': 'running', 'submitted': 0, 'failed': 0, 'total': total_samples, 'errors': []}
            add_log('Auto Contribute is enabled. Each completed row will be submitted automatically.', 'info')
        else:
            test_results['contribution'] = {'status': 'idle', 'submitted': 0, 'failed': 0, 'total': total_samples, 'errors': []}
            add_log('Auto Contribute is disabled. Use the Contribute button after the test finishes.', 'info')
        
        all_results = []
        
        for target_idx, target_url in enumerate(targets, 1):
            normalized_target_url = normalize_target_url(target_url)
            parsed_target = urlparse(normalized_target_url)
            target_name = normalized_target_url
            display_name = parsed_target.netloc or normalized_target_url
            add_log(f"Testing target {target_idx}/{len(targets)}: {display_name}", 'info')
            
            target_results = []
            
            for dns_scenario_index, dns_scenario in enumerate(dns_test_scenarios, start=1):
                dns_label = dns_scenario[0] if dns_scenario else (wifi_info.get('dns_primary') or 'system')
                if wifi_info.get('dns_override_enabled'):
                    add_log(f"  DNS scenario {dns_scenario_index}/{len(dns_test_scenarios)}: {dns_label}", 'info')

                for sample_num in range(1, sample_count + 1):
                # Check for stop
                    if test_stopped:
                        add_log('Test stopped by user', 'warning')
                        test_results['status'] = 'stopped'
                        test_running = False
                        return
                
                # Check for pause
                    if test_paused:
                        print(f'  [PAUSED] Test paused...')
                    while test_paused and not test_stopped:
                        time.sleep(0.5)
                    if not test_paused and not test_stopped and sample_num > 1:
                        pass  # resumed message handled by POST handler
                
                    result = measure_ttfb(
                        normalized_target_url,
                        ttfb_good_ms=config.get('TTFB_GOOD_MS'),
                        ttfb_warning_ms=config.get('TTFB_WARNING_MS'),
                        dns_servers=dns_scenario,
                        add_log_fn=add_log,
                    )
                    result['sample_num'] = sample_num
                    result['target_name'] = target_name
                    result['timestamp'] = datetime.now().isoformat()
                    result['time_short'] = datetime.now().strftime('%H:%M:%S')
                    result['dns_scenario'] = dns_label
                
                # Add network info to result for expanded table
                    result['rssi'] = test_results['network_info'].get('wifi_rssi')
                    result['band'] = test_results['network_info'].get('wifi_band')
                    result['dns'] = result.get('dns_primary') or test_results['network_info'].get('dns_primary')
                
                    target_results.append(result)
                    all_results.append(result)
                    test_results['ttfb_results'] = all_results
                    test_results['elapsed_seconds'] = (datetime.now() - test_results['_start_time_obj']).total_seconds()
                    test_results['end_time'] = datetime.now().isoformat()
                    test_results['summary'] = calculate_summary(all_results)

                    if auto_contribute:
                        export_rows = build_export_rows(test_results)
                        current_row = export_rows[-1] if export_rows else None
                        if current_row:
                            row_done = len(all_results)
                            ok, error_message = submit_contribution_row(current_row, row_done, total_samples)
                            if ok:
                                test_results['contribution']['submitted'] += 1
                            else:
                                test_results['contribution']['failed'] += 1
                                contribution_errors.append(error_message)
                            test_results['contribution']['errors'] = contribution_errors
                            test_results['contribution']['status'] = 'running'
                
                # Log result
                    if result['ttfb_ms']:
                        status_icon = {'good': '[OK]', 'warning': '[!]', 'poor': '[X]'}.get(result['status'], '?')
                        log_level = {'good': 'success', 'warning': 'warning', 'poor': 'error'}.get(result['status'], 'info')
                        add_log(f"  Sample {sample_num}/{sample_count} [{dns_label}]: {result['ttfb_ms']}ms {status_icon}", log_level)
                    else:
                        add_log(f"  Sample {sample_num}/{sample_count} [{dns_label}]: ERROR - {result.get('error', 'Unknown')}", 'error')
                
                # Terminal progress
                    done = len(all_results)
                    pct = int(done / total_samples * 100)
                    bar_len = 30
                    filled = int(bar_len * done / total_samples)
                    bar = '#' * filled + '-' * (bar_len - filled)
                    elapsed = test_results['elapsed_seconds']
                    eta = (elapsed / done * (total_samples - done)) if done > 0 else 0
                    print(f'\r  [{bar}] {pct}% ({done}/{total_samples}) ETA: {int(eta)}s  ', end='', flush=True)
                
                # Delay between samples
                    if sample_num < sample_count:
                        time.sleep(delay)
            
            # Calculate target summary
            valid_results = [r for r in target_results if r.get('ttfb_ms')]
            if valid_results:
                ttfbs = [r['ttfb_ms'] for r in valid_results]
                avg_ttfb = sum(ttfbs) / len(ttfbs)
                add_log(f"  → {display_name} average: {avg_ttfb:.0f}ms", 'info')
        
        # Calculate overall summary
        add_log('', 'divider')
        add_log('Calculating summary...', 'info')
        
        test_results['summary'] = calculate_summary(all_results)
        summary = test_results['summary']
        if summary.get('successful_tests'):
            add_log(f"Total tests: {summary['total_tests']} ({summary['successful_tests']} successful)", 'info')
            add_log(f"Mean TTFB: {summary['mean_ttfb']:.0f}ms, Median: {summary['median_ttfb']:.0f}ms", 'info')
            add_log(f"Range: {summary['min_ttfb']:.0f}ms - {summary['max_ttfb']:.0f}ms (Std: {summary['std_ttfb']:.0f}ms)", 'info')
            add_log(f"Status: {summary['good_count']} good, {summary['warning_count']} warning, {summary['poor_count']} poor", 'info')
        
        # Run DNS trace
        add_log('', 'divider')
        add_log('Running DNS trace...', 'info')
        
        # Collect DNS servers for trace
        test_dns_servers = wifi_info.get('dns_servers', []) if wifi_info.get('dns_override_enabled') else []
        system_dns_servers = wifi_info.get('system_dns_servers', [])
        
        dns_trace_results = run_dns_traces_for_session(
            targets=targets,
            dns_servers=test_dns_servers,
            system_dns=system_dns_servers,
            add_log_fn=add_log
        )
        
        test_results['dns_trace_results'] = dns_trace_results
        
        if dns_trace_results:
            add_log(f"DNS trace completed: {len(dns_trace_results)} trace(s)", 'success')
        else:
            add_log('DNS trace skipped (dig not available or no DNS servers configured)', 'warning')
        
        # Save results
        add_log('Saving results...', 'info')
        
        # Save session info
        session_info = {
            'session_id': test_results['session_id'],
            'start_time': test_results['start_time'],
            'end_time': datetime.now().isoformat(),
            'config': config,
            'network_info': test_results['network_info'],
            'summary': test_results['summary'],
            'dns_trace_summary': {
                'total_traces': len(dns_trace_results),
                'successful_traces': sum(1 for t in dns_trace_results if t.get('success')),
            } if dns_trace_results else None
        }
        
        with open(current_session_dir / 'session_info.json', 'w') as f:
            json.dump(session_info, f, indent=2)
        
        # Save TTFB results as JSON
        with open(current_session_dir / 'ttfb_results.json', 'w') as f:
            json.dump(all_results, f, indent=2)
        
        # Save DNS trace results as JSON (local only, not submitted to API)
        if dns_trace_results:
            with open(current_session_dir / 'dns_trace_results.json', 'w') as f:
                json.dump(dns_trace_results, f, indent=2)
        
        # Try to save as CSV
        try:
            import pandas as pd
            df = pd.DataFrame(all_results)
            df.to_csv(current_session_dir / 'ttfb_results.csv', index=False)
            add_log(f"Results saved to: {current_session_dir.name}/", 'success')
        except ImportError:
            add_log(f"Results saved to: {current_session_dir.name}/ (JSON only, pandas not available)", 'warning')
        
        test_results['status'] = 'completed'
        test_results['end_time'] = datetime.now().isoformat()
        test_results['session_dir'] = str(current_session_dir)
        if auto_contribute:
            failed = test_results['contribution'].get('failed', 0)
            submitted = test_results['contribution'].get('submitted', 0)
            test_results['contribution']['status'] = 'success' if failed == 0 else ('partial' if submitted > 0 else 'error')
            if failed == 0:
                add_log(f"Auto Contribute finished: {submitted}/{total_samples} row(s) submitted", 'success')
            else:
                add_log(f"Auto Contribute finished with issues: {submitted}/{total_samples} submitted, {failed} failed", 'warning')
        
        # Clear progress bar line
        print()
        add_log('', 'divider')
        add_log('[OK] All tests completed!', 'success')
        elapsed_total = (datetime.now() - test_results['_start_time_obj']).total_seconds()
        print(f'  Total time: {int(elapsed_total)}s')
        
    except Exception as e:
        add_log(f"Test error: {e}", 'error')
        test_results['status'] = 'error'
        test_results['error'] = str(e)
    finally:
        test_running = False


class TTFBHandler(http.server.SimpleHTTPRequestHandler):
    """HTTP handler for TTFB test UI."""
    
    def log_message(self, format, *args):
        pass
    
    def do_GET(self):
        if self.path == '/':
            self.send_response(200)
            self.send_header('Content-type', 'text/html; charset=utf-8')
            self.end_headers()
            html_content = load_ui_template()
            self.wfile.write(html_content.encode())
            
        elif self.path.startswith('/static/'):
            asset = read_static_asset(self.path)
            if asset:
                content, content_type = asset
                self.send_response(200)
                self.send_header('Content-type', content_type)
                self.send_header('Content-Length', len(content))
                self.end_headers()
                self.wfile.write(content)
            else:
                self.send_response(404)
                self.end_headers()
            
        elif self.path == '/api/config':
            config = parse_config(CONFIG_FILE)
            self.send_json(config)
            
        elif self.path == '/api/prereqs':
            prereqs = check_prerequisites()
            self.send_json(prereqs)
            
        elif self.path == '/api/network':
            self.send_json(build_network_snapshot())

        elif self.path == '/api/debug/netsh':
            debug_info = get_windows_netsh_debug()
            add_log(
                f"Wi-Fi debug requested. Parsed SSID: {debug_info.get('parsed_ssid') or 'Not detected'}",
                'info' if debug_info.get('parsed_ssid') else 'warning'
            )
            self.send_json(debug_info)
            
        elif self.path == '/api/logs':
            logs = []
            while not log_queue.empty():
                try:
                    logs.append(log_queue.get_nowait())
                except:
                    break
            self.send_json(logs)
            
        elif self.path == '/api/test/status':
            # Filter out non-serializable fields
            safe_results = {k: v for k, v in test_results.items() if not k.startswith('_')}
            self.send_json(safe_results)
            
        elif self.path == '/api/download/csv':
            self.handle_download_csv()
            
        elif self.path == '/api/download/report':
            self.handle_download_report()

        elif self.path == '/api/contribute/status':
            self.send_json(test_results.get('contribution', {'status': 'idle'}))
            
        else:
            self.send_response(404)
            self.end_headers()
    
    def handle_download_csv(self):
        """Generate and send CSV file for download with ALL available data."""
        global test_results
        
        if not test_results.get('ttfb_results'):
            self.send_json({'error': 'No results available'})
            return
        
        try:
            import csv
            import io
            
            # Generate filename
            session_id = test_results.get('session_id', datetime.now().strftime('%Y%m%d_%H%M%S'))
            network_info = test_results.get('network_info', {})
            location = network_info.get('location', {}) or {}
            config = test_results.get('config', {})
            summary = test_results.get('summary', {})
            band = (network_info.get('wifi_band') or 'Unknown').replace('.', '_').replace('GHz', 'G')
            dns = (network_info.get('dns_primary') or 'UnknownDNS').replace('.', '-')
            city = sanitize_filename_part(location.get('city'), 'UnknownCity')
            
            filename = f"ttfb_results_{city}_{band}_{dns}_{session_id}.csv"
            
            fieldnames = EXPORT_FIELDNAMES

            # Create CSV content
            output = io.StringIO()
            rows = build_export_rows(test_results)
            
            if rows:
                writer = csv.DictWriter(output, fieldnames=fieldnames, extrasaction='ignore')
                writer.writeheader()
                for row in rows:
                    writer.writerow(row)
            
            csv_content = output.getvalue().encode('utf-8')
            
            self.send_response(200)
            self.send_header('Content-Type', 'text/csv')
            self.send_header('Content-Disposition', f'attachment; filename="{filename}"')
            self.send_header('Content-Length', len(csv_content))
            self.end_headers()
            self.wfile.write(csv_content)
            
        except Exception as e:
            self.send_json({'error': str(e)})
    
    def handle_download_report(self):
        """Generate and send text report for download."""
        global test_results
        
        if not test_results.get('ttfb_results'):
            self.send_json({'error': 'No results available'})
            return
        
        try:
            # Generate filename
            session_id = test_results.get('session_id', datetime.now().strftime('%Y%m%d_%H%M%S'))
            network_info = test_results.get('network_info', {})
            location = network_info.get('location', {}) or {}
            band = (network_info.get('wifi_band') or 'Unknown').replace('.', '_').replace('GHz', 'G')
            dns = (network_info.get('dns_primary') or 'UnknownDNS').replace('.', '-')
            city = sanitize_filename_part(location.get('city'), 'UnknownCity')
            
            filename = f"ttfb_report_{city}_{band}_{dns}_{session_id}.txt"
            
            # Generate report content
            lines = []
            lines.append("=" * 70)
            lines.append("NOC Tune - TTFB Test Report")
            lines.append("=" * 70)
            lines.append("")
            lines.append(f"Session ID: {session_id}")
            lines.append(f"Start Time: {test_results.get('start_time', 'N/A')}")
            lines.append(f"End Time: {test_results.get('end_time', 'N/A')}")
            config = test_results.get('config', {})
            if config.get('BRAND'):
                lines.append(f"Brand: {config.get('BRAND')}")
            if config.get('NO_INTERNET'):
                lines.append(f"No Internet: {config.get('NO_INTERNET')}")
            lines.append("")
            
            # Network conditions
            lines.append("-" * 50)
            lines.append("🔍 DETECTED CONDITIONS")
            lines.append("-" * 50)
            
            threshold = network_info.get('signal_threshold', -70)
            rssi = network_info.get('wifi_rssi')
            if rssi is not None:
                signal_status = "✅ Good" if rssi >= threshold else "⚠️ Weak"
                lines.append(f"📶 Signal: {signal_status}")
                lines.append(f"   • RSSI: {rssi} dBm")
                lines.append(f"   • Threshold: {threshold} dBm")
            else:
                lines.append("📶 Signal: ❓ Unknown")
            
            lines.append(f"📻 Band: {network_info.get('wifi_band', 'N/A')}")
            if network_info.get('wifi_channel'):
                lines.append(f"   • Channel: {network_info['wifi_channel']}")
            dns_label = 'Test DNS' if network_info.get('dns_override_enabled') else 'DNS'
            lines.append(f"🌐 {dns_label}: {network_info.get('dns_primary', 'N/A')}")
            if network_info.get('dns_override_enabled') and network_info.get('system_dns_primary'):
                lines.append(f"🌐 System DNS: {network_info.get('system_dns_primary', 'N/A')}")
            lines.append(f"📡 SSID: {network_info.get('wifi_ssid', 'N/A')}")
            lines.append("")
            
            # Location
            loc = location
            if loc:
                lines.append("-" * 50)
                lines.append("📍 LOCATION")
                lines.append("-" * 50)
                lines.append(f"🌍 {loc.get('city', 'N/A')}, {loc.get('region', '')}, {loc.get('country', 'N/A')}")
                if loc.get('lat') and loc.get('lon'):
                    accuracy = f" (±{loc['accuracy']:.0f}m)" if loc.get('accuracy') else ""
                    lines.append(f"📍 Coordinates: {loc['lat']}, {loc['lon']}{accuracy}")
                if loc.get('altitude') is not None:
                    lines.append(f"⛰️ Altitude: {loc.get('altitude')} m")
                if loc.get('heading') is not None:
                    lines.append(f"🧭 Heading: {loc.get('heading')}")
                if loc.get('speed') is not None:
                    lines.append(f"🏃 Speed: {loc.get('speed')}")
                lines.append(f"🏢 ISP: {loc.get('isp', 'N/A')}")
                lines.append(f"🌐 Public IP: {loc.get('ip', 'N/A')}")
                lines.append(f"📡 Method: {loc.get('method', 'N/A')}")
                if loc.get('browser_timestamp'):
                    lines.append(f"🕒 Browser Timestamp: {loc.get('browser_timestamp')}")
                if loc.get('saved_at'):
                    lines.append(f"💾 Saved At: {loc.get('saved_at')}")
                lines.append("")
            
            # Results summary
            lines.append("-" * 50)
            lines.append("📊 TTFB RESULTS SUMMARY")
            lines.append("-" * 50)
            
            summary = test_results.get('summary', {})
            if summary:
                mean_ttfb = summary.get('mean_ttfb', 0)
                ttfb_good = config.get('TTFB_GOOD_MS', 200)
                ttfb_warning = config.get('TTFB_WARNING_MS', 500)
                
                if mean_ttfb < ttfb_good:
                    status_str = "✅ GOOD"
                elif mean_ttfb < ttfb_warning:
                    status_str = "⚠️ WARNING"
                else:
                    status_str = "❌ POOR"
                
                lines.append(f"🎯 Mean TTFB: {mean_ttfb:.2f} ms {status_str}")
                lines.append(f"📊 Median: {summary.get('median_ttfb', 0):.2f} ms")
                lines.append(f"📉 Min: {summary.get('min_ttfb', 0):.2f} ms")
                lines.append(f"📈 Max: {summary.get('max_ttfb', 0):.2f} ms")
                lines.append(f"📏 Std Dev: {summary.get('std_ttfb', 0):.2f} ms")
                lines.append("")
                lines.append(f"Status Breakdown:")
                lines.append(f"   ✅ Good: {summary.get('good_count', 0)}")
                lines.append(f"   ⚠️ Warning: {summary.get('warning_count', 0)}")
                lines.append(f"   ❌ Poor: {summary.get('poor_count', 0)}")
                lines.append(f"   Total: {summary.get('total_tests', 0)}")
            lines.append("")
            
            # Per-target details
            results = test_results.get('ttfb_results', [])
            if results:
                lines.append("-" * 50)
                lines.append("📋 DETAILED RESULTS")
                lines.append("-" * 50)
                
                # Group by target
                targets = {}
                for r in results:
                    target = r.get('target_name', 'Unknown')
                    if target not in targets:
                        targets[target] = []
                    targets[target].append(r)
                
                for target, target_results in targets.items():
                    lines.append(f"\n🎯 {target}:")
                    valid_ttfbs = [r['ttfb_ms'] for r in target_results if r.get('ttfb_ms')]
                    if valid_ttfbs:
                        lines.append(f"   Mean: {sum(valid_ttfbs)/len(valid_ttfbs):.0f}ms, Min: {min(valid_ttfbs):.0f}ms, Max: {max(valid_ttfbs):.0f}ms")
                    for r in target_results:
                        ttfb = f"{r['ttfb_ms']:.0f}ms" if r.get('ttfb_ms') else "ERROR"
                        status = r.get('status', 'unknown')
                        lines.append(f"   Sample {r.get('sample_num', '?')}: {ttfb} [{status}]")
            
            lines.append("")
            lines.append("=" * 70)
            lines.append("Generated by NOC Tune - https://github.com/basnugroho/noctune")
            lines.append("=" * 70)
            
            report_content = "\n".join(lines).encode('utf-8')
            
            self.send_response(200)
            self.send_header('Content-Type', 'text/plain; charset=utf-8')
            self.send_header('Content-Disposition', f'attachment; filename="{filename}"')
            self.send_header('Content-Length', len(report_content))
            self.end_headers()
            self.wfile.write(report_content)
            
        except Exception as e:
            self.send_json({'error': str(e)})
    
    def do_POST(self):
        global test_paused, test_stopped
        
        content_length = int(self.headers.get('Content-Length', 0))
        post_data = self.rfile.read(content_length).decode()
        
        if self.path == '/api/config':
            try:
                config = json.loads(post_data)
                config['IS_MOBILE'] = False
                config['TARGETS'] = normalize_target_urls(config.get('TARGETS', []))
                parse_manual_coordinates(config.get('MANUAL_LATITUDE'), config.get('MANUAL_LONGITUDE'))
                if config.get('USE_CUSTOM_DNS') and not parse_dns_servers(config.get('CUSTOM_DNS_SERVERS')):
                    raise ValueError('At least one custom DNS server is required when DNS override is enabled')
                success = save_config(config, CONFIG_FILE)
                self.send_json({'success': success})
            except Exception as e:
                self.send_json({'success': False, 'error': str(e)})

        elif self.path == '/api/location':
            try:
                location_data = json.loads(post_data) if post_data else {}

                if location_data.get('latitude') is None or location_data.get('longitude') is None:
                    self.send_json({'success': False, 'error': 'latitude and longitude are required'})
                    return

                if not location_data.get('city') or not location_data.get('region') or not location_data.get('country'):
                    geocoded = reverse_geocode_coordinates(location_data.get('latitude'), location_data.get('longitude'))
                    if geocoded.get('city') and not location_data.get('city'):
                        location_data['city'] = geocoded['city']
                    if geocoded.get('region') and not location_data.get('region'):
                        location_data['region'] = geocoded['region']
                    if geocoded.get('country') and not location_data.get('country'):
                        location_data['country'] = geocoded['country']

                location_data['saved_at'] = datetime.now().astimezone().isoformat()
                PRECISE_LOCATION_FILE.parent.mkdir(parents=True, exist_ok=True)
                with open(PRECISE_LOCATION_FILE, 'w') as f:
                    json.dump(location_data, f, indent=2)

                self.send_json({'success': True, 'location': location_data})
            except Exception as e:
                self.send_json({'success': False, 'error': str(e)})

        elif self.path == '/api/network/refresh':
            try:
                network_info = build_network_snapshot()
                add_log(
                    f"Network info refreshed. SSID: {network_info.get('wifi_ssid') or 'Not detected'} | Location method: {(network_info.get('location') or {}).get('method') or 'Unknown'}",
                    'info' if network_info.get('wifi_ssid') else 'warning'
                )
                self.send_json(network_info)
            except Exception as e:
                self.send_json({'error': str(e)})
                
        elif self.path == '/api/test/start':
            if test_running:
                self.send_json({'success': False, 'error': 'Test already running'})
            else:
                try:
                    config = json.loads(post_data)
                    config['IS_MOBILE'] = False
                    config['TARGETS'] = normalize_target_urls(config.get('TARGETS', []))
                    parse_manual_coordinates(config.get('MANUAL_LATITUDE'), config.get('MANUAL_LONGITUDE'))
                    if config.get('USE_CUSTOM_DNS') and not parse_dns_servers(config.get('CUSTOM_DNS_SERVERS')):
                        raise ValueError('At least one custom DNS server is required when DNS override is enabled')
                    # Reset control flags
                    test_paused = False
                    test_stopped = False
                    targets = config.get('TARGETS', [])
                    samples = config.get('SAMPLE_COUNT', 5)
                    print(f'\n[*] Test started: {len(targets)} target(s) x {samples} samples = {len(targets) * samples} total')
                    # Start test in background thread
                    thread = threading.Thread(target=run_tests, args=(config,), daemon=True)
                    thread.start()
                    self.send_json({'success': True})
                except Exception as e:
                    self.send_json({'success': False, 'error': str(e)})
        
        elif self.path == '/api/test/pause':
            test_paused = not test_paused
            state = '[PAUSED] Test PAUSED' if test_paused else '[>] Test RESUMED'
            print(f'\n  {state}')
            self.send_json({'success': True, 'paused': test_paused})
        
        elif self.path == '/api/test/stop':
            test_stopped = True
            print(f'\n  [STOPPED] Test STOPPED by user')
            self.send_json({'success': True})

        elif self.path == '/api/contribute':
            self.handle_contribute_results()
        
        else:
            self.send_response(404)
            self.end_headers()

    def handle_contribute_results(self):
        """Submit completed test rows to the remote contribution API."""
        global test_results

        rows = build_export_rows(test_results)
        if not rows:
            self.send_json({'success': False, 'error': 'No completed results available to contribute'})
            return

        test_results['contribution'] = {
            'status': 'submitting',
            'submitted': 0,
            'failed': 0,
            'total': len(rows),
            'errors': [],
        }
        add_log(f"Contribute started: submitting {len(rows)} row(s) to QoSMic API", 'info')

        contribution_result = submit_contribution_rows(rows, log_callback=add_log)
        test_results['contribution'] = contribution_result

        if contribution_result['failed'] == 0:
            add_log(f"Contribute finished: {contribution_result['submitted']}/{len(rows)} row(s) submitted", 'success')
            self.send_json({
                'success': True,
                'submitted': contribution_result['submitted'],
                'failed': contribution_result['failed'],
                'total': len(rows),
            })
        else:
            self.send_json({
                'success': contribution_result['submitted'] > 0,
                'submitted': contribution_result['submitted'],
                'failed': contribution_result['failed'],
                'total': len(rows),
                'errors': contribution_result['errors'],
                'error': contribution_result['errors'][0] if contribution_result['errors'] else 'Unknown contribution error'
            })
    
    def send_json(self, data):
        self.send_response(200)
        self.send_header('Content-type', 'application/json')
        self.end_headers()
        self.wfile.write(json.dumps(data).encode())


def cleanup_existing_server(port: int) -> list[int]:
    """Best-effort cleanup for any stale server already listening on the port."""
    current_pid = os.getpid()
    stale_pids = []

    try:
        if platform.system() == 'Windows':
            proc = subprocess.run(
                ['netstat', '-ano'],
                capture_output=True,
                text=True,
                timeout=5
            )
            for line in proc.stdout.splitlines():
                if f':{port} ' not in line or 'LISTENING' not in line.upper():
                    continue
                parts = line.split()
                if parts:
                    try:
                        pid = int(parts[-1])
                        if pid != current_pid:
                            stale_pids.append(pid)
                    except ValueError:
                        continue
        else:
            proc = subprocess.run(
                ['lsof', '-t', f'-iTCP:{port}', '-sTCP:LISTEN'],
                capture_output=True,
                text=True,
                timeout=5
            )
            for line in proc.stdout.splitlines():
                line = line.strip()
                if not line:
                    continue
                try:
                    pid = int(line)
                except ValueError:
                    continue
                if pid != current_pid:
                    stale_pids.append(pid)
    except Exception:
        return []

    stale_pids = sorted(set(stale_pids))
    if not stale_pids:
        return []

    for pid in stale_pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except Exception:
            pass

    time.sleep(0.5)

    for pid in stale_pids:
        try:
            os.kill(pid, 0)
        except OSError:
            continue
        except Exception:
            continue

        try:
            os.kill(pid, signal.SIGKILL)
        except Exception:
            pass

    time.sleep(0.2)
    return stale_pids


def main():
    print("=" * 60)
    print("NOC Tune - TTFB Test UI")
    print("=" * 60)
    print()
    
    # Ensure results directory exists
    RESULTS_DIR.mkdir(parents=True, exist_ok=True)

    killed_pids = cleanup_existing_server(PORT)
    if killed_pids:
        print(f"[*] Freed port {PORT} by stopping existing process(es): {', '.join(str(pid) for pid in killed_pids)}")
        print()
    
    # Start server with SO_REUSEADDR
    class ReusableTCPServer(socketserver.TCPServer):
        allow_reuse_address = True

    try:
        httpd = ReusableTCPServer(("", PORT), TTFBHandler)
    except OSError as e:
        if getattr(e, 'errno', None) == 48:
            killed_pids = cleanup_existing_server(PORT)
            if killed_pids:
                print(f"[*] Retrying after stopping process(es): {', '.join(str(pid) for pid in killed_pids)}")
                print()
                httpd = ReusableTCPServer(("", PORT), TTFBHandler)
            else:
                raise
        else:
            raise

    with httpd:
        url = f"http://localhost:{PORT}"
        print(f"[*] Server running at {url}", flush=True)
        print("", flush=True)
        
        if not NO_BROWSER:
            print("Opening browser...", flush=True)
            webbrowser.open(url)
        else:
            print("Browser opening disabled (Electron mode)", flush=True)
        
        print("", flush=True)
        print("Press Ctrl+C to stop the server", flush=True)
        print("", flush=True)
        
        try:
            print("[DEBUG] Starting serve_forever()...", flush=True)
            httpd.serve_forever()
            print("[DEBUG] serve_forever() returned normally", flush=True)
        except KeyboardInterrupt:
            print("\n\nShutting down server...")
        except Exception as e:
            print(f"[ERROR] Server error: {e}", flush=True)
            import traceback
            traceback.print_exc()


if __name__ == "__main__":
    main()
