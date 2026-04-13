#!/usr/bin/env python3
"""
NOC Tune - Network Quality Measurement Tool

Main entry point for running NOC Tune.

Usage:
    python main.py             # Launch TTFB Test UI (default)
    python main.py --ui        # Launch TTFB Test UI
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
  python main.py --location  Get precise GPS location via browser
  python main.py --check     Check system prerequisites only
        '''
    )
    
    parser.add_argument('--version', '-v', action='version', 
                       version=f'NOC Tune v{__version__}')
    parser.add_argument('--ui', action='store_true',
                       help='Launch TTFB Test UI (default action)')
    parser.add_argument('--location', action='store_true',
                       help='Get precise GPS location via browser')
    parser.add_argument('--check', action='store_true',
                       help='Check system prerequisites only')
    parser.add_argument('--port', type=int, default=8766,
                       help='Port for web UI (default: 8766)')
    
    args = parser.parse_args()
    
    if args.check:
        run_check()
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
    from get_location import main as location_main
    location_main()


def run_ui(port: int = 8766):
    """Run the TTFB Test UI."""
    # Import and call the main function from ttfb_test_ui
    os.chdir(PROJECT_ROOT)
    
    # Modify port in the module
    import ttfb_test_ui
    ttfb_test_ui.PORT = port
    
    print(f"🚀 Starting NOC Tune TTFB Test UI on port {port}...")
    print(f"   Open http://localhost:{port} in your browser")
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
