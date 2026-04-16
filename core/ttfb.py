"""
NOC Tune - TTFB Testing

Time To First Byte measurement and testing.
"""

import subprocess
import platform
import json
import re
import time
from pathlib import Path
from datetime import datetime
from typing import Dict, Any, List, Callable, Optional
from urllib.parse import urlparse


def measure_ttfb(url: str, ttfb_good_ms: int = 200, ttfb_warning_ms: int = 500) -> Dict[str, Any]:
    """
    Measure TTFB for a single URL using curl.
    
    Returns dict with ttfb_ms, status, and other timing info.
    """
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
        url
    ]
    
    result = {
        'url': url,
        'ttfb_ms': None,
        'lookup_ms': None,
        'connect_ms': None,
        'appconnect_ms': None,
        'total_ms': None,
        'http_code': None,
        'status': 'unknown',
        'error': None,
        'timestamp': datetime.now().isoformat()
    }
    
    try:
        proc = subprocess.run(cmd, capture_output=True, text=True, timeout=35)
        
        if proc.returncode == 0:
            data = json.loads(proc.stdout)
            result['lookup_ms'] = round(data['time_namelookup'] * 1000, 2)
            result['connect_ms'] = round(data['time_connect'] * 1000, 2)
            result['appconnect_ms'] = round(data['time_appconnect'] * 1000, 2)
            result['ttfb_ms'] = round(data['time_starttransfer'] * 1000, 2)
            result['total_ms'] = round(data['time_total'] * 1000, 2)
            result['http_code'] = data['http_code']
            
            if result['ttfb_ms'] < ttfb_good_ms:
                result['status'] = 'good'
            elif result['ttfb_ms'] < ttfb_warning_ms:
                result['status'] = 'warning'
            else:
                result['status'] = 'poor'
        else:
            result['error'] = proc.stderr or f'Exit code: {proc.returncode}'
            result['status'] = 'error'
    except subprocess.TimeoutExpired:
        result['error'] = 'Timeout (>30s)'
        result['status'] = 'timeout'
    except json.JSONDecodeError as e:
        result['error'] = f'Invalid response: {e}'
        result['status'] = 'error'
    except Exception as e:
        result['error'] = str(e)
        result['status'] = 'error'
    
    return result


def run_ping_test(host: str = "8.8.8.8", count: int = 10) -> Dict[str, Any]:
    """
    Run ping test and return statistics.
    """
    if platform.system() == 'Windows':
        cmd = ['ping', '-n', str(count), host]
    else:
        cmd = ['ping', '-c', str(count), host]
    
    result = {
        'host': host,
        'count': count,
        'packets_sent': None,
        'packets_received': None,
        'loss_percent': None,
        'min_ms': None,
        'avg_ms': None,
        'max_ms': None,
        'raw': None,
        'error': None
    }
    
    try:
        proc = subprocess.run(cmd, capture_output=True, text=True, timeout=count + 30)
        result['raw'] = proc.stdout
        
        if platform.system() == 'Windows':
            # Windows parsing
            match = re.search(r'Sent = (\d+), Received = (\d+)', proc.stdout)
            if match:
                result['packets_sent'] = int(match.group(1))
                result['packets_received'] = int(match.group(2))
                if result['packets_sent'] > 0:
                    result['loss_percent'] = round(
                        (result['packets_sent'] - result['packets_received']) / result['packets_sent'] * 100, 1
                    )
            
            match = re.search(r'Average = (\d+)ms', proc.stdout)
            if match:
                result['avg_ms'] = int(match.group(1))
            
            match = re.search(r'Minimum = (\d+)ms, Maximum = (\d+)ms', proc.stdout)
            if match:
                result['min_ms'] = int(match.group(1))
                result['max_ms'] = int(match.group(2))
        else:
            # Unix parsing
            match = re.search(r'(\d+) packets transmitted, (\d+) (?:packets )?received', proc.stdout)
            if match:
                result['packets_sent'] = int(match.group(1))
                result['packets_received'] = int(match.group(2))
            
            match = re.search(r'(\d+(?:\.\d+)?)% packet loss', proc.stdout)
            if match:
                result['loss_percent'] = float(match.group(1))
            
            match = re.search(r'min/avg/max/(?:mdev|stddev) = ([\d.]+)/([\d.]+)/([\d.]+)', proc.stdout)
            if match:
                result['min_ms'] = float(match.group(1))
                result['avg_ms'] = float(match.group(2))
                result['max_ms'] = float(match.group(3))
                
    except subprocess.TimeoutExpired:
        result['error'] = 'Timeout'
    except Exception as e:
        result['error'] = str(e)
    
    return result


def run_batch_ttfb_test(
    targets: List[str],
    sample_count: int = 5,
    delay_seconds: int = 2,
    ttfb_good_ms: int = 200,
    ttfb_warning_ms: int = 500,
    on_progress: Optional[Callable[[str, str], None]] = None
) -> List[Dict[str, Any]]:
    """
    Run TTFB tests for multiple targets.
    
    Args:
        targets: List of URLs to test
        sample_count: Number of samples per target
        delay_seconds: Delay between samples
        ttfb_good_ms: Threshold for "good" status
        ttfb_warning_ms: Threshold for "warning" status
        on_progress: Callback function for progress updates (message, level)
    
    Returns:
        List of test results
    """
    all_results = []
    
    for target_idx, url in enumerate(targets, 1):
        domain = urlparse(url).netloc
        
        if on_progress:
            on_progress(f"Testing target {target_idx}/{len(targets)}: {domain}", 'info')
        
        for sample_num in range(1, sample_count + 1):
            result = measure_ttfb(url, ttfb_good_ms, ttfb_warning_ms)
            result['sample_num'] = sample_num
            result['target_name'] = domain
            result['target_idx'] = target_idx
            
            all_results.append(result)
            
            if on_progress:
                if result['ttfb_ms']:
                    status_icon = {'good': '[OK]', 'warning': '[!]', 'poor': '[X]'}.get(result['status'], '?')
                    level = {'good': 'success', 'warning': 'warning', 'poor': 'error'}.get(result['status'], 'info')
                    on_progress(f"  Sample {sample_num}/{sample_count}: {result['ttfb_ms']}ms {status_icon}", level)
                else:
                    on_progress(f"  Sample {sample_num}/{sample_count}: ERROR - {result.get('error', 'Unknown')}", 'error')
            
            # Delay between samples (except after last)
            if sample_num < sample_count:
                time.sleep(delay_seconds)
        
        # Summary for this target
        valid_results = [r for r in all_results if r.get('target_name') == domain and r.get('ttfb_ms')]
        if valid_results and on_progress:
            avg = sum(r['ttfb_ms'] for r in valid_results) / len(valid_results)
            on_progress(f"  → {domain} average: {avg:.0f}ms", 'info')
    
    return all_results


def calculate_summary(results: List[Dict[str, Any]]) -> Dict[str, Any]:
    """
    Calculate summary statistics from test results.
    """
    valid_results = [r for r in results if r.get('ttfb_ms')]
    
    if not valid_results:
        return {
            'total_tests': len(results),
            'successful_tests': 0,
            'failed_tests': len(results),
            'mean_ttfb': None,
            'min_ttfb': None,
            'max_ttfb': None,
            'good_count': 0,
            'warning_count': 0,
            'poor_count': 0
        }
    
    ttfbs = [r['ttfb_ms'] for r in valid_results]
    
    return {
        'total_tests': len(results),
        'successful_tests': len(valid_results),
        'failed_tests': len(results) - len(valid_results),
        'mean_ttfb': sum(ttfbs) / len(ttfbs),
        'median_ttfb': sorted(ttfbs)[len(ttfbs) // 2],
        'min_ttfb': min(ttfbs),
        'max_ttfb': max(ttfbs),
        'std_ttfb': (sum((x - sum(ttfbs)/len(ttfbs))**2 for x in ttfbs) / len(ttfbs)) ** 0.5,
        'good_count': len([r for r in valid_results if r['status'] == 'good']),
        'warning_count': len([r for r in valid_results if r['status'] == 'warning']),
        'poor_count': len([r for r in valid_results if r['status'] == 'poor'])
    }
