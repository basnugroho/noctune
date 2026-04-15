from __future__ import annotations

import csv
import json
import time
from datetime import datetime
from pathlib import Path

from core.ttfb import run_ping_test
from ui.backend_service import build_export_rows, calculate_summary, submit_contribution_rows
from ui.ttfb_test_ui import (
    CONFIG_FILE,
    RESULTS_DIR,
    apply_manual_location_override,
    apply_runtime_overrides,
    detect_network_info,
    get_configured_dns_servers,
    measure_ttfb,
    normalize_target_url,
    normalize_target_urls,
    parse_config,
    parse_dns_servers,
    run_dns_traces_for_session,
)


def parse_location_override(raw_value: str | None) -> tuple[float, float] | None:
    """Parse a --loc value in the form lat,lon."""
    if not raw_value:
        return None

    parts = [part.strip() for part in raw_value.split(',', 1)]
    if len(parts) != 2 or not parts[0] or not parts[1]:
        raise ValueError("Location must use the format lat,lon")

    try:
        latitude = float(parts[0])
        longitude = float(parts[1])
    except ValueError as exc:
        raise ValueError("Latitude and longitude must be numeric values") from exc

    if not -90 <= latitude <= 90:
        raise ValueError("Latitude must be between -90 and 90")
    if not -180 <= longitude <= 180:
        raise ValueError("Longitude must be between -180 and 180")

    return latitude, longitude


def _build_runtime_config(
    config_path: Path,
    targets: list[str] | None = None,
    sample_count: int | None = None,
    delay_seconds: int | None = None,
    ping_count: int | None = None,
    dns_servers: list[str] | None = None,
    auto_contribute: bool | None = None,
) -> dict:
    config = parse_config(config_path)

    if targets is not None:
        config['TARGETS'] = normalize_target_urls(targets)
    else:
        config['TARGETS'] = normalize_target_urls(config.get('TARGETS', []))

    if sample_count is not None:
        config['SAMPLE_COUNT'] = sample_count
    if delay_seconds is not None:
        config['DELAY_SECONDS'] = delay_seconds
    if ping_count is not None:
        config['PING_DURATION'] = ping_count
    if dns_servers is not None:
        parsed_dns_servers = parse_dns_servers(dns_servers)
        config['USE_CUSTOM_DNS'] = bool(parsed_dns_servers)
        config['CUSTOM_DNS_SERVERS'] = ', '.join(parsed_dns_servers)
    if auto_contribute is not None:
        config['AUTO_CONTRIBUTE'] = auto_contribute

    if not config['TARGETS']:
        raise ValueError('No targets configured. Use config.txt or pass --targets.')

    return config


def _signal_category(rssi: int | None, threshold: int) -> str:
    if rssi is None:
        return 'unknown_signal'
    return 'good_signal' if rssi >= threshold else 'bad_signal'


def _signal_status_text(signal_category: str) -> str:
    mapping = {
        'good_signal': 'good',
        'bad_signal': 'weak',
        'unknown_signal': 'unknown',
    }
    return mapping.get(signal_category, 'unknown')


def _session_name(session_id: str, network_info: dict) -> str:
    signal_category = _signal_category(
        network_info.get('wifi_rssi'),
        network_info.get('signal_threshold', -70),
    )
    band_short = (network_info.get('wifi_band') or 'Unknown').replace('.', '_').replace('GHz', 'G')
    dns_short = (network_info.get('dns_primary') or 'UnknownDNS').replace('.', '-')
    return f"session_{signal_category}_{band_short}_{dns_short}_{session_id}"


def _write_json(file_path: Path, payload: dict | list[dict]) -> None:
    file_path.write_text(json.dumps(payload, indent=2), encoding='utf-8')


def _write_csv(file_path: Path, rows: list[dict]) -> None:
    if not rows:
        return

    fieldnames: list[str] = []
    for row in rows:
        for key in row.keys():
            if key not in fieldnames:
                fieldnames.append(key)

    with file_path.open('w', newline='', encoding='utf-8') as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        for row in rows:
            writer.writerow(row)


def run_cli_tests(
    *,
    config_path: Path = CONFIG_FILE,
    targets: list[str] | None = None,
    sample_count: int | None = None,
    delay_seconds: int | None = None,
    ping_count: int | None = None,
    ping_host: str = '8.8.8.8',
    dns_servers: list[str] | None = None,
    auto_contribute: bool | None = None,
    location_override: tuple[float, float] | None = None,
) -> dict:
    """Run a terminal-based TTFB session without starting the browser UI."""
    config = _build_runtime_config(
        config_path=config_path,
        targets=targets,
        sample_count=sample_count,
        delay_seconds=delay_seconds,
        ping_count=ping_count,
        dns_servers=dns_servers,
        auto_contribute=auto_contribute,
    )

    session_id = datetime.now().strftime('%Y%m%d_%H%M%S')
    start_time = datetime.now()
    threshold = config.get('SIGNAL_THRESHOLD_DBM', -70)

    print(f"Starting NOC Tune CLI run at {start_time.isoformat()}")
    print(f"Config file: {config_path}")

    network_info = apply_runtime_overrides(detect_network_info(), config)
    network_info['signal_threshold'] = threshold

    if location_override is not None:
        apply_manual_location_override(
            network_info,
            location_override[0],
            location_override[1],
            source='cli_argument',
            method='Manual (--loc)',
        )

    signal_category = _signal_category(network_info.get('wifi_rssi'), threshold)
    network_info['signal_status'] = _signal_status_text(signal_category)

    print(f"Signal status: {signal_category}")
    print(f"RSSI: {network_info.get('wifi_rssi')}")
    print(f"Band: {network_info.get('wifi_band')}")
    dns_label = 'Test DNS' if network_info.get('dns_override_enabled') else 'DNS'
    print(f"{dns_label}: {network_info.get('dns_primary')}")
    if network_info.get('dns_override_enabled') and network_info.get('system_dns_primary'):
        print(f"System DNS: {network_info.get('system_dns_primary')}")

    location = network_info.get('location') or {}
    if location.get('lat') is not None and location.get('lon') is not None:
        print(
            'Location: '
            f"{location.get('lat')}, {location.get('lon')}"
            f" ({location.get('method', 'unknown')})"
        )

    session_dir = RESULTS_DIR / _session_name(session_id, network_info)
    session_dir.mkdir(parents=True, exist_ok=True)
    print(f"Session directory: {session_dir}")

    print(f"Running ping baseline to {ping_host} with {config['PING_DURATION']} probe(s)")
    ping_result = run_ping_test(host=ping_host, count=config['PING_DURATION'])
    ping_result['host'] = ping_host
    if ping_result.get('avg_ms') is not None:
        print(f"Ping average: {ping_result['avg_ms']} ms")
    elif ping_result.get('error'):
        print(f"Ping error: {ping_result['error']}")

    ping_output = ping_result.get('raw') or ping_result.get('error') or ''
    (session_dir / 'ping_result.txt').write_text(ping_output, encoding='utf-8')

    results: list[dict] = []
    effective_dns_servers = get_configured_dns_servers(config)
    dns_test_scenarios = [[server] for server in effective_dns_servers] if effective_dns_servers else [None]
    total_samples = len(config['TARGETS']) * config['SAMPLE_COUNT'] * len(dns_test_scenarios)
    done = 0

    for target_index, target_url in enumerate(config['TARGETS'], start=1):
        normalized_target_url = normalize_target_url(target_url)
        print(f"Testing target {target_index}/{len(config['TARGETS'])}: {normalized_target_url}")

        for dns_scenario_index, dns_scenario in enumerate(dns_test_scenarios, start=1):
            dns_label = dns_scenario[0] if dns_scenario else (network_info.get('dns_primary') or 'system')
            if effective_dns_servers:
                print(f"  DNS scenario {dns_scenario_index}/{len(dns_test_scenarios)}: {dns_label}")

            for sample_number in range(1, config['SAMPLE_COUNT'] + 1):
                result = measure_ttfb(
                    normalized_target_url,
                    ttfb_good_ms=config['TTFB_GOOD_MS'],
                    ttfb_warning_ms=config['TTFB_WARNING_MS'],
                    dns_servers=dns_scenario,
                )
                result['sample_num'] = sample_number
                result['target_name'] = normalized_target_url
                result['timestamp'] = datetime.now().isoformat()
                result['time_short'] = datetime.now().strftime('%H:%M:%S')
                result['rssi'] = network_info.get('wifi_rssi')
                result['band'] = network_info.get('wifi_band')
                result['dns'] = result.get('dns_primary') or network_info.get('dns_primary')
                result['dns_scenario'] = dns_label
                results.append(result)

                done += 1
                if result.get('ttfb_ms') is not None:
                    print(
                        f"  Sample {sample_number}/{config['SAMPLE_COUNT']} [{dns_label}]: "
                        f"{result['ttfb_ms']} ms [{result['status']}] ({done}/{total_samples})"
                    )
                else:
                    print(
                        f"  Sample {sample_number}/{config['SAMPLE_COUNT']} [{dns_label}]: "
                        f"ERROR - {result.get('error', 'Unknown error')} ({done}/{total_samples})"
                    )

                if sample_number < config['SAMPLE_COUNT'] and config['DELAY_SECONDS'] > 0:
                    time.sleep(config['DELAY_SECONDS'])

    end_time = datetime.now()
    summary = calculate_summary(results)
    
    # Run DNS trace
    print('Running DNS trace...')
    test_dns_servers = effective_dns_servers or []
    system_dns_servers = network_info.get('system_dns_servers', [])
    
    def cli_log(msg, level='info'):
        level_icons = {'info': 'ℹ️', 'success': '✅', 'warning': '⚠️', 'error': '❌'}
        icon = level_icons.get(level, ' ')
        print(f"  {icon} {msg}")
    
    dns_trace_results = run_dns_traces_for_session(
        targets=config['TARGETS'],
        dns_servers=test_dns_servers,
        system_dns=system_dns_servers,
        add_log_fn=cli_log
    )
    
    if dns_trace_results:
        print(f"DNS trace completed: {len(dns_trace_results)} trace(s)")
    else:
        print('DNS trace skipped (dig not available or no DNS servers configured)')
    
    payload = {
        'session_id': session_id,
        'start_time': start_time.isoformat(),
        'end_time': end_time.isoformat(),
        'config': config,
        'network_info': network_info,
        'ping_result': ping_result,
        'ttfb_results': results,
        'dns_trace_results': dns_trace_results,
        'summary': summary,
        'status': 'completed',
        'session_dir': str(session_dir),
        'contribution': {'status': 'idle', 'submitted': 0, 'failed': 0, 'total': len(results), 'errors': []},
    }

    _write_json(session_dir / 'session_info.json', {
        'session_id': session_id,
        'start_time': payload['start_time'],
        'end_time': payload['end_time'],
        'config': config,
        'network_info': network_info,
        'summary': summary,
        'ping_result': ping_result,
        'dns_trace_summary': {
            'total_traces': len(dns_trace_results),
            'successful_traces': sum(1 for t in dns_trace_results if t.get('success')),
        } if dns_trace_results else None,
    })
    _write_json(session_dir / 'ttfb_results.json', results)
    _write_csv(session_dir / 'ttfb_results.csv', results)
    _write_csv(session_dir / 'ttfb_export.csv', build_export_rows(payload))
    
    # Save DNS trace results (local only, not submitted to API)
    if dns_trace_results:
        _write_json(session_dir / 'dns_trace_results.json', dns_trace_results)

    if config.get('AUTO_CONTRIBUTE', True):
        print('Submitting contribution rows...')
        payload['contribution'] = submit_contribution_rows(build_export_rows(payload))
        print(
            'Contribute status: '
            f"{payload['contribution']['status']} "
            f"({payload['contribution']['submitted']}/{payload['contribution']['total']} submitted)"
        )
    else:
        print('Auto contribute disabled for this run')

    print('Summary:')
    print(f"  Total tests: {summary['total_tests']}")
    print(f"  Successful: {summary['successful_tests']}")
    print(f"  Failed: {summary['failed_tests']}")
    if summary.get('mean_ttfb') is not None:
        print(f"  Mean TTFB: {summary['mean_ttfb']:.2f} ms")
        print(f"  Median TTFB: {summary['median_ttfb']:.2f} ms")
        print(f"  Min/Max TTFB: {summary['min_ttfb']:.2f} / {summary['max_ttfb']:.2f} ms")

    print(f"Results saved under: {session_dir}")
    return payload