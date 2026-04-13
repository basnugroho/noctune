#!/usr/bin/env python3
"""
NOC Tune - Browser-based Geolocation Script

This script opens a local web page in your browser to get precise GPS location
using the browser's Geolocation API (which requires user permission).

Usage:
    python get_location.py

The script will:
1. Start a local web server on port 8765
2. Open your browser to http://localhost:8765
3. Ask for location permission
4. Display detected location info
5. Save the location to notebooks/precise_location.json

The notebook can then read this file for more accurate location data.
"""

import http.server
import socketserver
import webbrowser
import json
import os
import sys
import threading
import time
from pathlib import Path
from urllib.parse import parse_qs, urlparse
from datetime import datetime

# Configuration
PORT = 8765
OUTPUT_FILE = Path(__file__).parent / "notebooks" / "precise_location.json"
TIMEOUT_SECONDS = 120  # Auto-close after 2 minutes

# Global state
location_received = threading.Event()
location_data = {}


HTML_TEMPLATE = """
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>NOC Tune - Location Detection</title>
    <style>
        * {
            box-sizing: border-box;
            margin: 0;
            padding: 0;
        }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, sans-serif;
            background: linear-gradient(135deg, #1a1a2e 0%, #16213e 100%);
            min-height: 100vh;
            color: #fff;
            padding: 20px;
        }
        .container {
            max-width: 600px;
            margin: 0 auto;
        }
        .header {
            text-align: center;
            padding: 30px 0;
        }
        .header h1 {
            font-size: 2.5em;
            margin-bottom: 10px;
            background: linear-gradient(90deg, #00d2ff, #3a7bd5);
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
        }
        .header p {
            color: #888;
            font-size: 1.1em;
        }
        .card {
            background: rgba(255, 255, 255, 0.05);
            border-radius: 16px;
            padding: 24px;
            margin-bottom: 20px;
            backdrop-filter: blur(10px);
            border: 1px solid rgba(255, 255, 255, 0.1);
        }
        .card h2 {
            display: flex;
            align-items: center;
            gap: 10px;
            margin-bottom: 16px;
            font-size: 1.2em;
        }
        .status {
            display: flex;
            align-items: center;
            gap: 12px;
            padding: 16px;
            border-radius: 12px;
            margin-bottom: 16px;
        }
        .status.waiting {
            background: rgba(255, 193, 7, 0.15);
            border: 1px solid rgba(255, 193, 7, 0.3);
        }
        .status.success {
            background: rgba(76, 175, 80, 0.15);
            border: 1px solid rgba(76, 175, 80, 0.3);
        }
        .status.error {
            background: rgba(244, 67, 54, 0.15);
            border: 1px solid rgba(244, 67, 54, 0.3);
        }
        .status-icon {
            font-size: 1.5em;
        }
        .spinner {
            width: 24px;
            height: 24px;
            border: 3px solid rgba(255, 255, 255, 0.2);
            border-top-color: #00d2ff;
            border-radius: 50%;
            animation: spin 1s linear infinite;
        }
        @keyframes spin {
            to { transform: rotate(360deg); }
        }
        .data-grid {
            display: grid;
            grid-template-columns: 1fr 1fr;
            gap: 12px;
        }
        .data-item {
            background: rgba(255, 255, 255, 0.03);
            padding: 12px;
            border-radius: 8px;
        }
        .data-item.full-width {
            grid-column: 1 / -1;
        }
        .data-item label {
            display: block;
            color: #888;
            font-size: 0.85em;
            margin-bottom: 4px;
        }
        .data-item .value {
            font-size: 1.1em;
            font-weight: 500;
            color: #fff;
        }
        .data-item .value.highlight {
            color: #00d2ff;
        }
        .btn {
            display: inline-flex;
            align-items: center;
            justify-content: center;
            gap: 8px;
            padding: 14px 28px;
            border: none;
            border-radius: 12px;
            font-size: 1em;
            font-weight: 600;
            cursor: pointer;
            transition: all 0.2s;
            width: 100%;
        }
        .btn-primary {
            background: linear-gradient(90deg, #00d2ff, #3a7bd5);
            color: #fff;
        }
        .btn-primary:hover {
            transform: translateY(-2px);
            box-shadow: 0 10px 40px rgba(0, 210, 255, 0.3);
        }
        .btn-primary:disabled {
            opacity: 0.5;
            cursor: not-allowed;
            transform: none;
        }
        .btn-success {
            background: linear-gradient(90deg, #4caf50, #45a049);
            color: #fff;
        }
        .progress-bar {
            height: 4px;
            background: rgba(255, 255, 255, 0.1);
            border-radius: 2px;
            overflow: hidden;
            margin-top: 16px;
        }
        .progress-bar .fill {
            height: 100%;
            background: linear-gradient(90deg, #00d2ff, #3a7bd5);
            width: 0%;
            transition: width 0.3s;
        }
        .capabilities {
            display: flex;
            flex-wrap: wrap;
            gap: 8px;
            margin-top: 12px;
        }
        .capability {
            display: inline-flex;
            align-items: center;
            gap: 6px;
            padding: 6px 12px;
            background: rgba(255, 255, 255, 0.05);
            border-radius: 20px;
            font-size: 0.85em;
        }
        .capability.available {
            background: rgba(76, 175, 80, 0.2);
            color: #81c784;
        }
        .capability.unavailable {
            background: rgba(244, 67, 54, 0.2);
            color: #e57373;
        }
        .footer {
            text-align: center;
            padding: 20px;
            color: #666;
            font-size: 0.9em;
        }
        .map-link {
            display: inline-flex;
            align-items: center;
            gap: 6px;
            color: #00d2ff;
            text-decoration: none;
            margin-top: 8px;
        }
        .map-link:hover {
            text-decoration: underline;
        }
        #close-message {
            display: none;
            text-align: center;
            padding: 20px;
            background: rgba(76, 175, 80, 0.15);
            border-radius: 12px;
            margin-top: 20px;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🔧 NOC Tune</h1>
            <p>Browser-based Precise Location Detection</p>
        </div>

        <!-- Capabilities Card -->
        <div class="card">
            <h2>📡 Detection Capabilities</h2>
            <p style="color: #888; margin-bottom: 12px;">Checking available detection methods...</p>
            <div class="capabilities" id="capabilities"></div>
        </div>

        <!-- Status Card -->
        <div class="card">
            <h2>📍 Location Status</h2>
            <div id="status-container">
                <div class="status waiting" id="status">
                    <div class="spinner"></div>
                    <div>
                        <strong>Waiting for permission...</strong>
                        <p style="color: #888; font-size: 0.9em;">Click the button below to start</p>
                    </div>
                </div>
                <button class="btn btn-primary" id="get-location-btn" onclick="getLocation()">
                    🎯 Get My Location
                </button>
            </div>
            <div class="progress-bar" id="progress-bar" style="display: none;">
                <div class="fill" id="progress-fill"></div>
            </div>
        </div>

        <!-- Location Data Card -->
        <div class="card" id="location-card" style="display: none;">
            <h2>📊 Detected Information</h2>
            <div class="data-grid">
                <div class="data-item">
                    <label>Latitude</label>
                    <div class="value highlight" id="latitude">-</div>
                </div>
                <div class="data-item">
                    <label>Longitude</label>
                    <div class="value highlight" id="longitude">-</div>
                </div>
                <div class="data-item">
                    <label>Accuracy</label>
                    <div class="value" id="accuracy">-</div>
                </div>
                <div class="data-item">
                    <label>Altitude</label>
                    <div class="value" id="altitude">-</div>
                </div>
                <div class="data-item">
                    <label>Speed</label>
                    <div class="value" id="speed">-</div>
                </div>
                <div class="data-item">
                    <label>Heading</label>
                    <div class="value" id="heading">-</div>
                </div>
                <div class="data-item full-width">
                    <label>Timestamp</label>
                    <div class="value" id="timestamp">-</div>
                </div>
            </div>
            <a class="map-link" id="map-link" href="#" target="_blank">
                🗺️ View on Google Maps
            </a>
        </div>

        <!-- Save Card -->
        <div class="card" id="save-card" style="display: none;">
            <h2>💾 Save Location</h2>
            <p style="color: #888; margin-bottom: 16px;">
                Save this location for use in the NOC Tune notebook.
            </p>
            <button class="btn btn-success" id="save-btn" onclick="saveLocation()">
                ✅ Save & Close
            </button>
        </div>

        <div id="close-message">
            <p style="font-size: 1.2em; margin-bottom: 8px;">✅ Location saved successfully!</p>
            <p style="color: #888;">You can close this window now.</p>
        </div>

        <div class="footer">
            <p>NOC Tune - Network Quality Measurement Tool</p>
            <p style="margin-top: 4px;">Location data is only used locally and not sent to any external server.</p>
        </div>
    </div>

    <script>
        let locationData = null;

        // Check capabilities
        function checkCapabilities() {
            const container = document.getElementById('capabilities');
            const capabilities = [
                {
                    name: 'Geolocation API',
                    available: 'geolocation' in navigator,
                    icon: '📍'
                },
                {
                    name: 'Secure Context (HTTPS)',
                    available: window.isSecureContext || location.hostname === 'localhost',
                    icon: '🔒'
                },
                {
                    name: 'High Accuracy Mode',
                    available: 'geolocation' in navigator,
                    icon: '🎯'
                }
            ];

            container.innerHTML = capabilities.map(cap => `
                <span class="capability ${cap.available ? 'available' : 'unavailable'}">
                    ${cap.icon} ${cap.name} ${cap.available ? '✓' : '✗'}
                </span>
            `).join('');
        }

        // Get location
        function getLocation() {
            if (!navigator.geolocation) {
                showError('Geolocation is not supported by your browser');
                return;
            }

            const btn = document.getElementById('get-location-btn');
            btn.disabled = true;
            btn.innerHTML = '<div class="spinner"></div> Getting location...';

            const status = document.getElementById('status');
            status.className = 'status waiting';
            status.innerHTML = `
                <div class="spinner"></div>
                <div>
                    <strong>Getting location...</strong>
                    <p style="color: #888; font-size: 0.9em;">Please allow location access if prompted</p>
                </div>
            `;

            // Show progress bar
            const progressBar = document.getElementById('progress-bar');
            progressBar.style.display = 'block';
            animateProgress();

            const options = {
                enableHighAccuracy: true,
                timeout: 30000,
                maximumAge: 0
            };

            navigator.geolocation.getCurrentPosition(
                onSuccess,
                onError,
                options
            );
        }

        function animateProgress() {
            const fill = document.getElementById('progress-fill');
            let width = 0;
            const interval = setInterval(() => {
                if (width >= 90 || locationData) {
                    clearInterval(interval);
                    if (locationData) {
                        fill.style.width = '100%';
                    }
                } else {
                    width += Math.random() * 10;
                    fill.style.width = Math.min(width, 90) + '%';
                }
            }, 200);
        }

        function onSuccess(position) {
            locationData = {
                latitude: position.coords.latitude,
                longitude: position.coords.longitude,
                accuracy: position.coords.accuracy,
                altitude: position.coords.altitude,
                altitudeAccuracy: position.coords.altitudeAccuracy,
                heading: position.coords.heading,
                speed: position.coords.speed,
                timestamp: new Date(position.timestamp).toISOString(),
                method: 'Browser Geolocation API',
                highAccuracy: true
            };

            // Update UI
            const status = document.getElementById('status');
            status.className = 'status success';
            status.innerHTML = `
                <span class="status-icon">✅</span>
                <div>
                    <strong>Location detected!</strong>
                    <p style="color: #81c784; font-size: 0.9em;">High accuracy mode enabled</p>
                </div>
            `;

            const btn = document.getElementById('get-location-btn');
            btn.style.display = 'none';

            // Show location data
            document.getElementById('location-card').style.display = 'block';
            document.getElementById('latitude').textContent = locationData.latitude.toFixed(6);
            document.getElementById('longitude').textContent = locationData.longitude.toFixed(6);
            document.getElementById('accuracy').textContent = locationData.accuracy ? `±${locationData.accuracy.toFixed(1)}m` : 'N/A';
            document.getElementById('altitude').textContent = locationData.altitude ? `${locationData.altitude.toFixed(1)}m` : 'N/A';
            document.getElementById('speed').textContent = locationData.speed ? `${locationData.speed.toFixed(1)} m/s` : 'N/A';
            document.getElementById('heading').textContent = locationData.heading ? `${locationData.heading.toFixed(1)}°` : 'N/A';
            document.getElementById('timestamp').textContent = new Date(locationData.timestamp).toLocaleString();

            // Map link
            const mapLink = document.getElementById('map-link');
            mapLink.href = `https://www.google.com/maps?q=${locationData.latitude},${locationData.longitude}`;

            // Show save button
            document.getElementById('save-card').style.display = 'block';
        }

        function onError(error) {
            let message = 'Unknown error';
            switch (error.code) {
                case error.PERMISSION_DENIED:
                    message = 'Location permission denied. Please allow location access.';
                    break;
                case error.POSITION_UNAVAILABLE:
                    message = 'Location information unavailable.';
                    break;
                case error.TIMEOUT:
                    message = 'Location request timed out.';
                    break;
            }
            showError(message);
        }

        function showError(message) {
            const status = document.getElementById('status');
            status.className = 'status error';
            status.innerHTML = `
                <span class="status-icon">❌</span>
                <div>
                    <strong>Error</strong>
                    <p style="color: #e57373; font-size: 0.9em;">${message}</p>
                </div>
            `;

            const btn = document.getElementById('get-location-btn');
            btn.disabled = false;
            btn.innerHTML = '🔄 Try Again';
        }

        function saveLocation() {
            if (!locationData) return;

            const btn = document.getElementById('save-btn');
            btn.disabled = true;
            btn.innerHTML = '<div class="spinner"></div> Saving...';

            // Send to server
            fetch('/save-location', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json'
                },
                body: JSON.stringify(locationData)
            })
            .then(response => response.json())
            .then(data => {
                if (data.success) {
                    document.getElementById('save-card').style.display = 'none';
                    document.getElementById('close-message').style.display = 'block';
                    
                    // Auto-close after 3 seconds
                    setTimeout(() => {
                        fetch('/shutdown');
                    }, 2000);
                } else {
                    throw new Error(data.error || 'Failed to save');
                }
            })
            .catch(error => {
                btn.disabled = false;
                btn.innerHTML = '❌ Error - Try Again';
                console.error('Save error:', error);
            });
        }

        // Initialize
        checkCapabilities();
    </script>
</body>
</html>
"""


class LocationHandler(http.server.SimpleHTTPRequestHandler):
    """Custom HTTP handler for location detection."""
    
    def log_message(self, format, *args):
        """Suppress default logging."""
        pass
    
    def do_GET(self):
        """Handle GET requests."""
        if self.path == '/':
            self.send_response(200)
            self.send_header('Content-type', 'text/html')
            self.end_headers()
            self.wfile.write(HTML_TEMPLATE.encode())
        elif self.path == '/shutdown':
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            self.wfile.write(b'{"success": true}')
            # Signal shutdown
            location_received.set()
        else:
            self.send_response(404)
            self.end_headers()
    
    def do_POST(self):
        """Handle POST requests."""
        if self.path == '/save-location':
            content_length = int(self.headers['Content-Length'])
            post_data = self.rfile.read(content_length)
            
            try:
                global location_data
                location_data = json.loads(post_data.decode())
                
                # Save to file
                OUTPUT_FILE.parent.mkdir(parents=True, exist_ok=True)
                
                # Add metadata
                location_data['saved_at'] = datetime.now().isoformat()
                location_data['source'] = 'browser_geolocation'
                
                with open(OUTPUT_FILE, 'w') as f:
                    json.dump(location_data, f, indent=2)
                
                print(f"\n✅ Location saved to: {OUTPUT_FILE}")
                print(f"   📍 Coordinates: {location_data['latitude']}, {location_data['longitude']}")
                print(f"   🎯 Accuracy: ±{location_data.get('accuracy', 'N/A')}m")
                
                self.send_response(200)
                self.send_header('Content-type', 'application/json')
                self.end_headers()
                self.wfile.write(b'{"success": true}')
                
            except Exception as e:
                print(f"❌ Error saving location: {e}")
                self.send_response(500)
                self.send_header('Content-type', 'application/json')
                self.end_headers()
                self.wfile.write(json.dumps({'success': False, 'error': str(e)}).encode())
        else:
            self.send_response(404)
            self.end_headers()


def run_server():
    """Run the HTTP server."""
    with socketserver.TCPServer(("", PORT), LocationHandler) as httpd:
        httpd.timeout = 1
        print(f"🌐 Server running at http://localhost:{PORT}")
        
        while not location_received.is_set():
            httpd.handle_request()


def main():
    """Main entry point."""
    print("=" * 60)
    print("🔧 NOC Tune - Browser-based Location Detection")
    print("=" * 60)
    print()
    print("This script will open your browser to get precise GPS location.")
    print("The browser's Geolocation API can use:")
    print("  📡 GPS (if available)")
    print("  📶 WiFi positioning")
    print("  📱 Cell tower triangulation")
    print()
    print(f"📁 Output file: {OUTPUT_FILE}")
    print()
    
    # Start server in background thread
    server_thread = threading.Thread(target=run_server, daemon=True)
    server_thread.start()
    
    # Wait a moment for server to start
    time.sleep(0.5)
    
    # Open browser
    url = f"http://localhost:{PORT}"
    print(f"🌐 Opening browser: {url}")
    webbrowser.open(url)
    
    print()
    print("⏳ Waiting for location... (timeout: 2 minutes)")
    print("   Please allow location access in your browser.")
    print()
    
    # Wait for location or timeout
    start_time = time.time()
    while not location_received.is_set():
        if time.time() - start_time > TIMEOUT_SECONDS:
            print("\n⏱️ Timeout reached. Closing server.")
            break
        time.sleep(0.5)
    
    if location_data:
        print()
        print("=" * 60)
        print("✅ LOCATION DETECTION COMPLETE")
        print("=" * 60)
        print()
        print(f"📍 Latitude:  {location_data.get('latitude', 'N/A')}")
        print(f"📍 Longitude: {location_data.get('longitude', 'N/A')}")
        print(f"🎯 Accuracy:  ±{location_data.get('accuracy', 'N/A')}m")
        if location_data.get('altitude'):
            print(f"⛰️  Altitude:  {location_data['altitude']}m")
        print()
        print(f"💾 Saved to: {OUTPUT_FILE}")
        print()
        print("You can now run the NOC Tune notebook to use this location.")
        print("=" * 60)
    else:
        print()
        print("❌ No location data received.")
        print("   Try running the script again and allow location access.")
    
    return 0 if location_data else 1


if __name__ == "__main__":
    sys.exit(main())
