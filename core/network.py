"""
NOC Tune - Network Detection

Auto-detect network conditions: WiFi, DNS, Location.
"""

import subprocess
import platform
import re
import json
import urllib.request
from pathlib import Path
from typing import Dict, Any, Optional
from datetime import datetime, timedelta


def check_prerequisites() -> Dict[str, Dict[str, Any]]:
    """Check system prerequisites for running tests."""
    results = {
        'curl': {'status': 'checking', 'message': '', 'required': True},
        'ping': {'status': 'checking', 'message': '', 'required': True},
        'network': {'status': 'checking', 'message': '', 'required': True},
        'wifi': {'status': 'checking', 'message': '', 'required': False},
        'python_packages': {'status': 'checking', 'message': '', 'required': True}
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
    
    # Check Python packages
    missing_packages = []
    try:
        import pandas
    except ImportError:
        missing_packages.append('pandas')
    
    try:
        import numpy
    except ImportError:
        missing_packages.append('numpy')
    
    try:
        import matplotlib
    except ImportError:
        missing_packages.append('matplotlib')
    
    try:
        from tqdm import tqdm
    except ImportError:
        missing_packages.append('tqdm')
    
    if missing_packages:
        results['python_packages'] = {
            'status': 'error', 
            'message': f'Missing: {", ".join(missing_packages)}. Run: pip install {" ".join(missing_packages)}',
            'required': True
        }
    else:
        results['python_packages'] = {'status': 'ok', 'message': 'All required packages installed', 'required': True}
    
    return results


def get_wifi_info_macos() -> Dict[str, Any]:
    """Get WiFi info on macOS."""
    info = {
        'ssid': None,
        'rssi': None,
        'channel': None,
        'band': None
    }
    
    # Method 1: Try system_profiler
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
                        info['ssid'] = current_network.get('_name')
                        channel_str = current_network.get('spairport_current_network_information_channel', '')
                        if channel_str:
                            ch_match = re.search(r'(\d+)', str(channel_str))
                            if ch_match:
                                info['channel'] = int(ch_match.group(1))
                                info['band'] = '5GHz' if info['channel'] >= 36 else '2.4GHz'
                        break
    except:
        pass
    
    # Method 2: Try networksetup for SSID
    if not info['ssid']:
        try:
            proc = subprocess.run(['networksetup', '-getairportnetwork', 'en0'],
                                capture_output=True, text=True, timeout=5)
            match = re.search(r'Current Wi-Fi Network: (.+)', proc.stdout)
            if match:
                info['ssid'] = match.group(1).strip()
        except:
            pass
    
    # Method 3: Try CoreWLAN for RSSI (if pyobjc installed)
    try:
        from CoreWLAN import CWWiFiClient
        client = CWWiFiClient.sharedWiFiClient()
        interface = client.interface()
        if interface:
            info['rssi'] = interface.rssiValue()
            if not info['ssid']:
                info['ssid'] = interface.ssid()
            if interface.wlanChannel():
                ch = interface.wlanChannel().channelNumber()
                info['channel'] = ch
                info['band'] = '5GHz' if ch >= 36 else '2.4GHz'
    except:
        pass
    
    return info


def get_wifi_info_windows() -> Dict[str, Any]:
    """Get WiFi info on Windows."""
    info = {
        'ssid': None,
        'rssi': None,
        'channel': None,
        'band': None
    }
    
    try:
        proc = subprocess.run(['netsh', 'wlan', 'show', 'interfaces'],
                            capture_output=True, text=True, timeout=10)
        output = proc.stdout
        
        match = re.search(r'SSID\s+:\s+(.+)', output)
        if match:
            info['ssid'] = match.group(1).strip()
        
        match = re.search(r'Signal\s+:\s+(\d+)%', output)
        if match:
            signal_pct = int(match.group(1))
            info['rssi'] = int(-100 + (signal_pct * 0.7))
        
        match = re.search(r'Channel\s+:\s+(\d+)', output)
        if match:
            info['channel'] = int(match.group(1))
            info['band'] = '5GHz' if info['channel'] >= 36 else '2.4GHz'
    except:
        pass
    
    return info


def get_dns_servers() -> Dict[str, Any]:
    """Get current DNS servers."""
    info = {
        'primary': None,
        'servers': []
    }
    
    system = platform.system()
    
    if system == 'Darwin':
        try:
            proc = subprocess.run(['scutil', '--dns'], capture_output=True, text=True, timeout=10)
            matches = re.findall(r'nameserver\[\d+\]\s*:\s*(\d+\.\d+\.\d+\.\d+)', proc.stdout)
            if matches:
                info['servers'] = list(dict.fromkeys(matches))[:4]
                info['primary'] = info['servers'][0]
        except:
            pass
    elif system == 'Windows':
        try:
            proc = subprocess.run(['ipconfig', '/all'], capture_output=True, text=True, timeout=10)
            matches = re.findall(r'DNS Servers[\s.]*:\s*(\d+\.\d+\.\d+\.\d+)', proc.stdout)
            if matches:
                info['servers'] = list(dict.fromkeys(matches))[:4]
                info['primary'] = info['servers'][0]
        except:
            pass
    else:
        try:
            with open('/etc/resolv.conf', 'r') as f:
                matches = re.findall(r'nameserver\s+(\d+\.\d+\.\d+\.\d+)', f.read())
                if matches:
                    info['servers'] = matches[:4]
                    info['primary'] = info['servers'][0]
        except:
            pass
    
    return info


def get_location(precise_location_file: Optional[Path] = None) -> Dict[str, Any]:
    """
    Get device location.
    
    First checks for precise location from browser-based script.
    Falls back to IP geolocation if not available.
    """
    location = {
        'latitude': None,
        'longitude': None,
        'accuracy': None,
        'city': None,
        'region': None,
        'country': None,
        'isp': None,
        'ip': None,
        'method': None,
        'is_precise': False
    }
    
    # Method 1: Check for precise location file (from get_location.py)
    if precise_location_file and precise_location_file.exists():
        try:
            with open(precise_location_file, 'r') as f:
                precise_data = json.load(f)
            
            # Check if data is recent (within last 24 hours)
            saved_at = precise_data.get('saved_at')
            if saved_at:
                try:
                    saved_time = datetime.fromisoformat(saved_at.replace('Z', '+00:00'))
                    if datetime.now().astimezone() - saved_time < timedelta(hours=24):
                        location['latitude'] = precise_data.get('latitude')
                        location['longitude'] = precise_data.get('longitude')
                        location['accuracy'] = precise_data.get('accuracy')
                        location['method'] = 'GPS (Browser)'
                        location['is_precise'] = True
                except:
                    pass
        except:
            pass
    
    # Method 2: IP Geolocation API
    try:
        url = "http://ip-api.com/json/?fields=status,city,regionName,country,lat,lon,isp,query"
        req = urllib.request.Request(url, headers={'User-Agent': 'NOC-Tune/1.0'})
        with urllib.request.urlopen(req, timeout=10) as response:
            data = json.loads(response.read().decode())
            if data.get('status') == 'success':
                # Only use lat/lon from IP if we don't have precise location
                if not location['is_precise']:
                    location['latitude'] = data.get('lat')
                    location['longitude'] = data.get('lon')
                    location['method'] = 'IP Geolocation'
                
                # Always get city/country/ISP from IP API
                location['city'] = data.get('city')
                location['region'] = data.get('regionName')
                location['country'] = data.get('country')
                location['isp'] = data.get('isp')
                location['ip'] = data.get('query')
    except:
        pass
    
    return location


def detect_network_info(precise_location_file: Optional[Path] = None) -> Dict[str, Any]:
    """Detect all network information."""
    info = {
        'wifi_ssid': None,
        'wifi_rssi': None,
        'wifi_band': None,
        'wifi_channel': None,
        'dns_primary': None,
        'dns_servers': [],
        'location': None
    }
    
    system = platform.system()
    
    # Get WiFi info
    if system == 'Darwin':
        wifi = get_wifi_info_macos()
    elif system == 'Windows':
        wifi = get_wifi_info_windows()
    else:
        wifi = {'ssid': None, 'rssi': None, 'channel': None, 'band': None}
    
    info['wifi_ssid'] = wifi.get('ssid')
    info['wifi_rssi'] = wifi.get('rssi')
    info['wifi_channel'] = wifi.get('channel')
    info['wifi_band'] = wifi.get('band')
    
    # Get DNS
    dns = get_dns_servers()
    info['dns_primary'] = dns.get('primary')
    info['dns_servers'] = dns.get('servers', [])
    
    # Get location
    info['location'] = get_location(precise_location_file)
    
    return info
