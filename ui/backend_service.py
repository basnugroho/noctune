from __future__ import annotations

import json
import urllib.error
import urllib.request
from datetime import datetime
from typing import Callable


CONTRIBUTE_API_URL = "https://qosmic.solusee.id/api/ttfb-results/insert"

EXPORT_FIELDNAMES = [
    'session_id', 'test_start_time', 'test_end_time',
    'timestamp', 'time_short', 'target_name', 'brand', 'is_mobile', 'no_internet', 'sample_num', 'url',
    'ttfb_ms', 'lookup_ms', 'connect_ms', 'total_ms',
    'http_code', 'status', 'error',
    'device_name', 'device_model', 'os_name', 'os_version',
    'battery_level', 'battery_charging',
    'wifi_ssid', 'wifi_ssid_method', 'wifi_rssi', 'wifi_band', 'wifi_channel',
    'connectivity_type',
    'signal_threshold', 'signal_status',
    'dns_primary', 'dns_servers',
    'resolved_ip', 'dig_output', 'dig_query_time_ms',
    'location_city', 'location_region', 'location_country',
    'location_lat', 'location_lon', 'location_accuracy',
    'location_altitude', 'location_altitude_accuracy',
    'location_heading', 'location_speed',
    'location_browser_timestamp', 'location_saved_at', 'location_source',
    'location_method', 'location_is_precise',
    'isp', 'public_ip',
    'config_ttfb_good_ms', 'config_ttfb_warning_ms',
    'config_sample_count', 'config_delay_seconds',
    'summary_mean_ttfb', 'summary_median_ttfb',
    'summary_min_ttfb', 'summary_max_ttfb', 'summary_std_ttfb',
    'summary_good_count', 'summary_warning_count', 'summary_poor_count',
    'summary_total_tests', 'summary_successful_tests', 'summary_failed_tests',
]


def build_export_rows(results_payload: dict) -> list[dict]:
    """Build enriched export rows from test_results state."""
    results = results_payload.get('ttfb_results') or []
    if not results:
        return []

    session_id = results_payload.get('session_id', datetime.now().strftime('%Y%m%d_%H%M%S'))
    test_start_time = results_payload.get('start_time') or datetime.now().isoformat()
    network_info = results_payload.get('network_info', {}) or {}
    location = network_info.get('location', {}) or {}
    config = results_payload.get('config', {}) or {}
    summary = results_payload.get('summary', {}) or {}
    export_rows = []
    for result in results:
        row_dns_servers = result.get('dns_servers')
        if row_dns_servers in (None, '', []):
            row_dns_servers = network_info.get('dns_servers', []) or []
        dns_server_text = ';'.join(row_dns_servers) if isinstance(row_dns_servers, list) else str(row_dns_servers)

        row = {
            'session_id': session_id,
            'test_start_time': test_start_time,
            'test_end_time': results_payload.get('end_time') or result.get('timestamp') or datetime.now().isoformat(),
            'timestamp': result.get('timestamp') or datetime.now().isoformat(),
            'time_short': result.get('time_short', ''),
            'target_name': result.get('target_name', ''),
            'brand': config.get('BRAND') or None,
            'is_mobile': bool(config.get('IS_MOBILE', False)),
            'no_internet': config.get('NO_INTERNET') or None,
            'sample_num': result.get('sample_num', ''),
            'url': result.get('url', ''),
            'ttfb_ms': result.get('ttfb_ms'),
            'lookup_ms': result.get('lookup_ms'),
            'connect_ms': result.get('connect_ms'),
            'total_ms': result.get('total_ms'),
            'http_code': result.get('http_code'),
            'status': result.get('status', ''),
            'error': result.get('error'),
            'device_name': network_info.get('device_name'),
            'device_model': network_info.get('device_model'),
            'os_name': network_info.get('os_name'),
            'os_version': network_info.get('os_version'),
            'battery_level': network_info.get('battery_level'),
            'battery_charging': network_info.get('battery_charging'),
            'wifi_ssid': network_info.get('wifi_ssid'),
            'wifi_ssid_method': network_info.get('wifi_ssid_method') or 'unknown',
            'wifi_rssi': network_info.get('wifi_rssi'),
            'wifi_band': network_info.get('wifi_band'),
            'wifi_channel': network_info.get('wifi_channel'),
            'connectivity_type': result.get('connectivity_type') or network_info.get('connectivity_type'),
            'signal_threshold': network_info.get('signal_threshold'),
            'signal_status': network_info.get('signal_status'),
            'dns_primary': result.get('dns_primary') or network_info.get('dns_primary'),
            'dns_servers': dns_server_text or None,
            'resolved_ip': result.get('resolved_ip'),
            'dig_output': result.get('dig_output'),
            'dig_query_time_ms': result.get('dig_query_time_ms'),
            'location_city': location.get('city'),
            'location_region': location.get('region'),
            'location_country': location.get('country'),
            'location_lat': location.get('latitude', location.get('lat')),
            'location_lon': location.get('longitude', location.get('lon')),
            'location_accuracy': location.get('accuracy'),
            'location_altitude': location.get('altitude'),
            'location_altitude_accuracy': location.get('altitude_accuracy'),
            'location_heading': location.get('heading'),
            'location_speed': location.get('speed'),
            'location_browser_timestamp': location.get('browser_timestamp'),
            'location_saved_at': location.get('saved_at'),
            'location_source': location.get('source'),
            'location_method': location.get('method'),
            'location_is_precise': location.get('is_precise'),
            'isp': location.get('isp'),
            'public_ip': location.get('ip'),
            'config_ttfb_good_ms': config.get('TTFB_GOOD_MS'),
            'config_ttfb_warning_ms': config.get('TTFB_WARNING_MS'),
            'config_sample_count': config.get('SAMPLE_COUNT'),
            'config_delay_seconds': config.get('DELAY_SECONDS'),
            'summary_mean_ttfb': round(summary.get('mean_ttfb', 0), 2) if summary.get('mean_ttfb') is not None else None,
            'summary_median_ttfb': round(summary.get('median_ttfb', 0), 2) if summary.get('median_ttfb') is not None else None,
            'summary_min_ttfb': round(summary.get('min_ttfb', 0), 2) if summary.get('min_ttfb') is not None else None,
            'summary_max_ttfb': round(summary.get('max_ttfb', 0), 2) if summary.get('max_ttfb') is not None else None,
            'summary_std_ttfb': round(summary.get('std_ttfb', 0), 2) if summary.get('std_ttfb') is not None else None,
            'summary_good_count': summary.get('good_count'),
            'summary_warning_count': summary.get('warning_count'),
            'summary_poor_count': summary.get('poor_count'),
            'summary_total_tests': summary.get('total_tests'),
            'summary_successful_tests': summary.get('successful_tests'),
            'summary_failed_tests': summary.get('failed_tests'),
        }
        export_rows.append(row)

    return export_rows


def normalize_sql_datetime(value):
    """Convert ISO-like datetimes into MySQL DATETIME-compatible strings."""
    if value in (None, ''):
        return None

    if isinstance(value, str):
        try:
            parsed = datetime.fromisoformat(value.replace('Z', '+00:00'))
            if parsed.tzinfo is not None:
                parsed = parsed.astimezone().replace(tzinfo=None)
            return parsed.strftime('%Y-%m-%d %H:%M:%S.%f')
        except ValueError:
            return value

    return value


def normalize_contribution_value(value):
    """Convert nested or UI-only values into API-safe primitives."""
    if isinstance(value, bool):
        return int(value)
    if isinstance(value, (list, dict)):
        return json.dumps(value, ensure_ascii=False)
    if isinstance(value, str):
        value = value.strip()
        return value or None
    return value


def build_contribution_row(row: dict) -> dict:
    """Normalize one export row for the remote contribute API."""
    normalized = dict(row)
    for key in ['test_start_time', 'test_end_time', 'timestamp', 'location_browser_timestamp', 'location_saved_at']:
        normalized[key] = normalize_sql_datetime(normalized.get(key))
    for key, value in list(normalized.items()):
        normalized[key] = normalize_contribution_value(value)
    return normalized


def is_duplicate_contribution_error(response_text: str) -> bool:
    """Return True when the contribute API reports an already-inserted row."""
    normalized = (response_text or '').lower()
    return (
        'duplicate entry' in normalized
        or 'integrity constraint violation' in normalized
        or 'uq_ttfb_results_row' in normalized
        or 'sqlstate[23000]' in normalized
    )


def calculate_summary(results: list[dict]) -> dict:
    """Calculate summary metrics for the current result set."""
    valid_results = [result for result in results if result.get('ttfb_ms') is not None]
    if not valid_results:
        return {
            'total_tests': len(results),
            'successful_tests': 0,
            'failed_tests': len(results),
            'mean_ttfb': None,
            'median_ttfb': None,
            'std_ttfb': None,
            'min_ttfb': None,
            'max_ttfb': None,
            'good_count': 0,
            'warning_count': 0,
            'poor_count': 0,
        }

    ttfbs = [result['ttfb_ms'] for result in valid_results]
    sorted_ttfbs = sorted(ttfbs)
    mean_ttfb = sum(ttfbs) / len(ttfbs)
    mid = len(sorted_ttfbs) // 2
    if len(sorted_ttfbs) % 2 == 0:
        median_ttfb = (sorted_ttfbs[mid - 1] + sorted_ttfbs[mid]) / 2
    else:
        median_ttfb = sorted_ttfbs[mid]
    std_ttfb = (sum((value - mean_ttfb) ** 2 for value in ttfbs) / len(ttfbs)) ** 0.5

    return {
        'total_tests': len(results),
        'successful_tests': len(valid_results),
        'failed_tests': len(results) - len(valid_results),
        'mean_ttfb': mean_ttfb,
        'median_ttfb': median_ttfb,
        'std_ttfb': std_ttfb,
        'min_ttfb': min(ttfbs),
        'max_ttfb': max(ttfbs),
        'good_count': len([result for result in valid_results if result['status'] == 'good']),
        'warning_count': len([result for result in valid_results if result['status'] == 'warning']),
        'poor_count': len([result for result in valid_results if result['status'] == 'poor']),
    }


def submit_contribution_row(
    row: dict,
    index: int,
    total: int,
    log_callback: Callable[[str, str], None] | None = None,
) -> tuple[bool, str]:
    """Submit a single row to the contribution API."""
    contribution_row = build_contribution_row(row)
    payload = json.dumps({'row': contribution_row}).encode('utf-8')
    request = urllib.request.Request(
        CONTRIBUTE_API_URL,
        data=payload,
        headers={
            'Content-Type': 'application/json',
            'Accept': 'application/json',
            'User-Agent': 'NOC-Tune/1.0',
        },
        method='POST',
    )

    try:
        with urllib.request.urlopen(request, timeout=20) as response:
            status_code = getattr(response, 'status', 200)
            response_text = response.read().decode('utf-8', errors='replace') if hasattr(response, 'read') else ''
        if status_code >= 400:
            raise RuntimeError(f'HTTP {status_code}: {response_text}')
        if log_callback:
            log_callback(
                f"Contribute row {index}/{total} OK: {row.get('target_name')} sample #{row.get('sample_num')}",
                'success',
            )
        return True, ''
    except urllib.error.HTTPError as e:
        response_text = ''
        try:
            response_text = e.read().decode('utf-8', errors='replace')
        except Exception:
            response_text = ''
        if is_duplicate_contribution_error(response_text):
            if log_callback:
                log_callback(
                    f"Contribute row {index}/{total} SKIP (already submitted): {row.get('target_name')} sample #{row.get('sample_num')}",
                    'info',
                )
            return True, ''
        error_suffix = f" | Response: {response_text}" if response_text else ''
        error_message = f"Row {index} failed for {row.get('target_name')} sample #{row.get('sample_num')}: HTTP {e.code}{error_suffix}"
        if log_callback:
            log_callback(error_message, 'error')
        return False, error_message
    except Exception as e:
        response_text = ''
        if hasattr(e, 'read'):
            try:
                response_text = e.read().decode('utf-8', errors='replace')
            except Exception:
                response_text = ''
        if is_duplicate_contribution_error(response_text):
            if log_callback:
                log_callback(
                    f"Contribute row {index}/{total} SKIP (already submitted): {row.get('target_name')} sample #{row.get('sample_num')}",
                    'info',
                )
            return True, ''
        error_suffix = f" | Response: {response_text}" if response_text else ''
        error_message = f"Row {index} failed for {row.get('target_name')} sample #{row.get('sample_num')}: {e}{error_suffix}"
        if log_callback:
            log_callback(error_message, 'error')
        return False, error_message


def submit_contribution_rows(
    rows: list[dict],
    log_callback: Callable[[str, str], None] | None = None,
) -> dict:
    """Submit all rows to the contribution API and return aggregate status."""
    submitted = 0
    failed = 0
    errors: list[str] = []

    for index, row in enumerate(rows, 1):
        ok, error_message = submit_contribution_row(row, index, len(rows), log_callback=log_callback)
        if ok:
            submitted += 1
        else:
            failed += 1
            errors.append(error_message)

    return {
        'status': 'success' if failed == 0 else ('partial' if submitted > 0 else 'error'),
        'submitted': submitted,
        'failed': failed,
        'total': len(rows),
        'errors': errors,
        'updated_at': datetime.now().isoformat(),
    }