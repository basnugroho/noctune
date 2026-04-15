#!/usr/bin/env python3
"""
NOC Tune - Network Quality Measurement Tool

Main entry point for running NOC Tune.

Usage:
    python main.py             # Launch TTFB Test UI (default)
    python main.py --ui        # Launch TTFB Test UI
    python main.py --run       # Run tests in terminal without UI
    python main.py --run --loc=-6.2,106.8  # Run with manual coordinates
    python main.py --location  # Get precise GPS location
    python main.py --version   # Show version
"""

import sys
import os
from pathlib import Path

# Add the project directory to path
PROJECT_ROOT = Path(__file__).parent.absolute()
sys.path.insert(0, str(PROJECT_ROOT))


def main():
    """Main entry point."""
    import argparse
    from core import __version__
    
    parser = argparse.ArgumentParser(
        description='NOC Tune - Network Quality Measurement Tool',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog='''
    Examples:
      python main.py             Launch TTFB Test UI (opens browser)
      python main.py --run       Run tests in terminal using notebooks/config.txt
      python main.py --run --loc=-6.2000,106.8166
                 Run in terminal with manual coordinates
      python main.py --run --dns=8.8.8.8,8.8.4.4
                 Force curl DNS resolution to custom servers
      python main.py --run --targets=https://example.com,https://google.com --samples=3 --delay=1
                 Run in terminal with CLI overrides
      python main.py --run --ping-host=1.1.1.1 --no-auto-contribute
                 Change baseline ping host and skip contribute
      python main.py --location  Get precise GPS location via browser
      python main.py --check     Check system prerequisites only
        '''
    )

    mode_group = parser.add_mutually_exclusive_group()
    
    parser.add_argument('--version', '-v', action='version', 
                       version=f'NOC Tune v{__version__}')
    mode_group.add_argument('--ui', action='store_true',
                       help='Launch TTFB Test UI (default action)')
    mode_group.add_argument('--run', action='store_true',
                       help='Run TTFB tests in terminal without opening the UI')
    mode_group.add_argument('--location', action='store_true',
                       help='Get precise GPS location via browser')
    mode_group.add_argument('--check', action='store_true',
                       help='Check system prerequisites only')
    parser.add_argument('--port', type=int, default=8766,
                       help='Port for web UI (default: 8766)')
    parser.add_argument('--config', type=Path, default=PROJECT_ROOT / 'notebooks' / 'config.txt',
                       help='Path to config.txt for --run mode (default: notebooks/config.txt)')
    parser.add_argument('--loc',
                       help='Manual coordinates for --run mode in the format lat,lon')
    parser.add_argument('--targets',
                       help='Comma-separated target URLs for --run mode')
    parser.add_argument('--samples', type=int,
                       help='Override sample count for --run mode')
    parser.add_argument('--delay', type=int,
                       help='Override delay between samples in seconds for --run mode')
    parser.add_argument('--ping-count', type=int,
                       help='Override baseline ping probe count for --run mode')
    parser.add_argument('--ping-host', default='8.8.8.8',
                       help='Baseline ping host for --run mode (default: 8.8.8.8). This does not change system DNS.')
    parser.add_argument('--dns',
                       help='Comma-separated DNS servers to force for curl lookups in --run mode, for example --dns=8.8.8.8,8.8.4.4')
    contribute_group = parser.add_mutually_exclusive_group()
    contribute_group.add_argument('--auto-contribute', dest='auto_contribute', action='store_true',
                                 help='Force enable contribute submission in --run mode')
    contribute_group.add_argument('--no-auto-contribute', dest='auto_contribute', action='store_false',
                                 help='Force disable contribute submission in --run mode')
    parser.set_defaults(auto_contribute=None)
    
    args = parser.parse_args()
    
    if args.check:
        run_check()
    elif args.run:
        run_terminal(
            config_path=args.config,
            targets=args.targets,
            sample_count=args.samples,
            delay_seconds=args.delay,
            ping_count=args.ping_count,
            ping_host=args.ping_host,
            dns_servers=args.dns,
            auto_contribute=args.auto_contribute,
            loc=args.loc,
        )
    elif args.location:
        run_location()
    else:
        # Default: run UI
        run_ui(port=args.port)


def run_check():
    """Check system prerequisites."""
    from core.network import check_prerequisites
    
    print("🔍 Checking system prerequisites...\n")
    
    results = check_prerequisites()
    
    all_ok = True
    for name, info in results.items():
        status = info['status']
        message = info['message']
        required = info.get('required', True)
        
        if status == 'ok':
            icon = '✓'
        elif status == 'warning':
            icon = '⚠'
        else:
            icon = '✗'
            if required:
                all_ok = False
        
        req_str = '(required)' if required else '(optional)'
        print(f"  {icon} {name}: {message} {req_str}")
    
    print()
    if all_ok:
        print("✓ All required prerequisites are met!")
    else:
        print("✗ Some required prerequisites are missing.")
        sys.exit(1)


def run_location():
    """Run the precise location script."""
    from ui.get_location import main as location_main
    location_main()


def get_local_ip():
    """Get local IP address for network access."""
    import socket
    try:
        # Connect to an external address to learn the outbound interface.
        # This is not a DNS override and does not force tests to use 8.8.8.8.
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        local_ip = s.getsockname()[0]
        s.close()
        return local_ip
    except Exception:
        return "127.0.0.1"


def run_terminal(
    *,
    config_path: Path,
    targets: str | None,
    sample_count: int | None,
    delay_seconds: int | None,
    ping_count: int | None,
    ping_host: str,
    dns_servers: str | None,
    auto_contribute: bool | None,
    loc: str | None,
):
    """Run the terminal-based TTFB workflow."""
    from core.cli_runner import parse_location_override, run_cli_tests

    if sample_count is not None and sample_count < 1:
        raise SystemExit('--samples must be at least 1')
    if delay_seconds is not None and delay_seconds < 0:
        raise SystemExit('--delay must be 0 or greater')
    if ping_count is not None and ping_count < 1:
        raise SystemExit('--ping-count must be at least 1')

    target_list = None
    if targets:
        target_list = [item.strip() for item in targets.split(',') if item.strip()]

    dns_server_list = None
    if dns_servers is not None:
        dns_server_list = [item.strip() for item in dns_servers.split(',') if item.strip()]

    location_override = parse_location_override(loc)

    run_cli_tests(
        config_path=config_path,
        targets=target_list,
        sample_count=sample_count,
        delay_seconds=delay_seconds,
        ping_count=ping_count,
        ping_host=ping_host,
        dns_servers=dns_server_list,
        auto_contribute=auto_contribute,
        location_override=location_override,
    )


def run_ui(port: int = 8766):
    """Run the TTFB Test UI."""
    # Import and call the main function from ttfb_test_ui
    os.chdir(PROJECT_ROOT)
    
    # Modify port in the module
    from ui import ttfb_test_ui
    ttfb_test_ui.PORT = port
    
    local_ip = get_local_ip()
    
    print(f"🚀 Starting NOC Tune TTFB Test UI on port {port}...")
    print()
    print(f"   📍 Local:   http://localhost:{port}")
    print(f"   🌐 Network: http://{local_ip}:{port}")
    print()
    print("   💡 Other devices on the same network can access via the Network URL")
    print("   Press Ctrl+C to stop\n")
    
    # Call the main function
    if hasattr(ttfb_test_ui, 'main'):
        ttfb_test_ui.main()
    else:
        # Fallback: run the server directly
        import webbrowser
        import http.server
        import socketserver
        
        ttfb_test_ui.Handler = ttfb_test_ui.TTFBHandler
        
        with socketserver.TCPServer(("", port), ttfb_test_ui.TTFBHandler) as httpd:
            webbrowser.open(f'http://localhost:{port}')
            try:
                httpd.serve_forever()
            except KeyboardInterrupt:
                print("\n\n👋 Goodbye!")


if __name__ == '__main__':
    main()
