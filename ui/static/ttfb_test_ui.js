        let isReady = false;
        let isRunning = false;
        let isPaused = false;
        let pollInterval = null;
        let activeTab = 'ttfb';
        let lastMapCoords = null;  // Track map coordinates to prevent flickering
        let browserLocation = null;  // Browser geolocation override
        let cachedNetworkInfo = null;  // Last network info from server
        
        // Initialize
        document.addEventListener('DOMContentLoaded', () => {
            setupTabs();
            switchTab('ttfb');
            initializeUi();
            requestBrowserLocation();
            document.getElementById('auto-contribute').addEventListener('change', () => {
                updateAutoContributeBadge(document.getElementById('auto-contribute').checked);
            });
            document.getElementById('use-custom-dns').addEventListener('change', () => {
                checkPrereqs();
            });
        });

        async function initializeUi() {
            await loadConfig();
            await checkPrereqs();
            await loadNetworkInfo();
        }

        function updateRunButtonState() {
            const runBtn = document.getElementById('run-test-btn');
            const hint = document.getElementById('run-test-hint');
            if (!runBtn) return;

            runBtn.disabled = isRunning;
            if (!isRunning) {
                runBtn.innerHTML = '<span class="btn-text">Jalankan Tes Sekarang</span>';
                runBtn.style.display = '';
            }

            if (hint) {
                if (isRunning) {
                    hint.textContent = 'Tes sedang berjalan. Gunakan tombol kontrol di header untuk pause, stop, atau restart.';
                } else if (isReady) {
                    hint.textContent = 'Sistem siap. Klik untuk langsung mulai pengukuran.';
                } else {
                    hint.textContent = 'Jika status belum sinkron, klik tombol ini untuk cek prerequisite ulang lalu mulai tes.';
                }
            }
        }

        function updateAutoContributeBadge(enabled) {
            const badge = document.getElementById('auto-contribute-badge');
            if (!badge) return;
            badge.textContent = `Auto Contribute: ${enabled ? 'ON' : 'OFF'}`;
            badge.className = 'mode-badge ' + (enabled ? 'on' : 'off');
        }

        // URL Tags Management
        let urlTags = [];

        function handleUrlInput(event) {
            if (event.key === 'Enter') {
                event.preventDefault();
                const input = document.getElementById('url-input');
                const url = input.value.trim();
                if (url && !urlTags.includes(url)) {
                    urlTags.push(url);
                    renderUrlTags();
                    input.value = '';
                } else if (urlTags.includes(url)) {
                    input.value = '';
                    input.placeholder = 'URL already added';
                    setTimeout(() => { input.placeholder = 'Type URL and press Enter'; }, 1500);
                }
            }
        }

        function removeUrlTag(index) {
            urlTags.splice(index, 1);
            renderUrlTags();
        }

        function renderUrlTags() {
            const container = document.getElementById('url-tags-container');
            container.innerHTML = urlTags.map((url, i) => `
                <div class="url-tag">
                    <span class="url-tag-text">${escapeHtml(url)}</span>
                    <button class="url-tag-delete" onclick="removeUrlTag(${i})" title="Remove">✕</button>
                </div>
            `).join('');
        }

        function escapeHtml(text) {
            const div = document.createElement('div');
            div.textContent = text;
            return div.innerHTML;
        }

        function getTargetUrls() {
            return urlTags.slice();
        }

        function setTargetUrls(urls) {
            urlTags = (urls || []).filter(u => u && u.trim());
            renderUrlTags();
        }

        function getConfigPayload() {
            const customDnsServers = document.getElementById('custom-dns-servers').value.trim();
            const manualLatitude = document.getElementById('manual-latitude').value.trim();
            const manualLongitude = document.getElementById('manual-longitude').value.trim();

            return {
                TARGETS: getTargetUrls(),
                SAMPLE_COUNT: parseInt(document.getElementById('sample-count').value) || 5,
                DELAY_SECONDS: parseInt(document.getElementById('delay-seconds').value) || 2,
                PING_DURATION: parseInt(document.getElementById('ping-duration').value) || 10,
                AUTO_CONTRIBUTE: document.getElementById('auto-contribute').checked,
                USE_CUSTOM_DNS: document.getElementById('use-custom-dns').checked,
                CUSTOM_DNS_SERVERS: customDnsServers,
                TTFB_GOOD_MS: parseInt(document.getElementById('ttfb-good').value) || 200,
                TTFB_WARNING_MS: parseInt(document.getElementById('ttfb-warning').value) || 500,
                SIGNAL_THRESHOLD_DBM: parseInt(document.getElementById('signal-threshold').value) || -70,
                BRAND: document.getElementById('brand').value.trim(),
                NO_INTERNET: document.getElementById('no-internet').value.trim(),
                MANUAL_LATITUDE: manualLatitude,
                MANUAL_LONGITUDE: manualLongitude
            };
        }

        function setupTabs() {
            document.querySelectorAll('.tab[data-tab]').forEach((tab) => {
                if (tab.classList.contains('disabled')) return;
                tab.addEventListener('click', () => switchTab(tab.dataset.tab));
            });
        }

        function switchTab(tabName) {
            activeTab = tabName;

            document.querySelectorAll('.tab[data-tab]').forEach((tab) => {
                tab.classList.toggle('active', tab.dataset.tab === tabName);
            });

            const isTtfb = tabName === 'ttfb';
            document.querySelector('.config-panel').style.display = isTtfb ? '' : 'none';
            document.querySelector('.results-panel').style.display = isTtfb ? '' : 'none';
            document.querySelector('.logs-panel').style.display = isTtfb ? '' : 'none';

            document.getElementById('about-page').classList.toggle('active', tabName === 'about');
            document.getElementById('privacy-page').classList.toggle('active', tabName === 'privacy');
        }
        
        // Request browser geolocation for precise coordinates
        function requestBrowserLocation() {
            if (!navigator.geolocation) return;
            
            navigator.geolocation.getCurrentPosition(
                async (position) => {
                    const lat = position.coords.latitude;
                    const lon = position.coords.longitude;
                    const accuracy = position.coords.accuracy;
                    
                    browserLocation = {
                        lat: lat,
                        lon: lon,
                        accuracy: accuracy,
                        is_precise: true,
                        method: 'GPS (Browser)'
                    };
                    
                    // Reverse geocode to get city name
                    try {
                        const rgeoUrl = `https://nominatim.openstreetmap.org/reverse?lat=${lat}&lon=${lon}&format=json&zoom=10`;
                        const resp = await fetch(rgeoUrl, { headers: { 'User-Agent': 'NOC-Tune/1.0' } });
                        const data = await resp.json();
                        const addr = data.address || {};
                        browserLocation.city = addr.city || addr.town || addr.municipality || addr.county;
                        browserLocation.region = addr.state;
                        browserLocation.country = addr.country;
                    } catch (e) {
                        console.error('Reverse geocode error:', e);
                    }

                    try {
                        await fetch('/api/location', {
                            method: 'POST',
                            headers: { 'Content-Type': 'application/json' },
                            body: JSON.stringify({
                                latitude: lat,
                                longitude: lon,
                                accuracy: accuracy,
                                altitude: position.coords.altitude,
                                altitudeAccuracy: position.coords.altitudeAccuracy,
                                heading: position.coords.heading,
                                speed: position.coords.speed,
                                timestamp: new Date(position.timestamp).toISOString(),
                                method: 'Browser Geolocation API',
                                highAccuracy: true,
                                source: 'browser_geolocation',
                                city: browserLocation.city || null,
                                region: browserLocation.region || null,
                                country: browserLocation.country || null
                            })
                        });
                        await loadNetworkInfo();
                    } catch (e) {
                        console.error('Failed to persist browser location:', e);
                    }
                    
                    // Re-render with precise location
                    if (cachedNetworkInfo) {
                        updateNetworkInfo(cachedNetworkInfo);
                    }
                },
                (err) => {
                    console.log('Browser geolocation not available:', err.message);
                },
                { enableHighAccuracy: true, timeout: 10000, maximumAge: 300000 }
            );
        }
        
        // Load network info and show URL
        async function loadNetworkInfo() {
            try {
                const response = await fetch('/api/network');
                const info = await response.json();
                
                // Show network URL box with local IP
                const port = window.location.port || (window.location.protocol === 'https:' ? '443' : '80');
                const networkUrlBox = document.getElementById('network-url-box');
                const networkUrlEl = document.getElementById('network-url');
                
                if (info.local_ip) {
                    const url = `http://${info.local_ip}:${port}`;
                    networkUrlBox.style.display = 'block';
                    networkUrlEl.textContent = url;
                    networkUrlEl.dataset.url = url;
                } else {
                    const host = window.location.host;
                    if (!host.includes('localhost') && !host.includes('127.0.0.1')) {
                        const url = `${window.location.protocol}//${host}`;
                        networkUrlBox.style.display = 'block';
                        networkUrlEl.textContent = url;
                        networkUrlEl.dataset.url = url;
                    }
                }
                
                // Update network info display (before running test)
                updateNetworkInfo(info);
                
            } catch (e) {
                console.error('Error loading network info:', e);
            }
        }
        
        // Copy network URL to clipboard
        function copyNetworkUrl() {
            const networkUrlEl = document.getElementById('network-url');
            const url = networkUrlEl.dataset.url || networkUrlEl.textContent;
            
            if (url && !url.includes('Check terminal')) {
                navigator.clipboard.writeText(url).then(() => {
                    networkUrlEl.classList.add('copied');
                    const originalText = networkUrlEl.textContent;
                    networkUrlEl.textContent = '✅ Copied!';
                    setTimeout(() => {
                        networkUrlEl.textContent = originalText;
                        networkUrlEl.classList.remove('copied');
                    }, 1500);
                });
            }
        }
        
        // Toggle prerequisites collapse
        function togglePrereqs() {
            const header = document.getElementById('prereq-header');
            const content = document.getElementById('prereq-content');
            header.classList.toggle('collapsed');
            content.classList.toggle('collapsed');
        }

        function toggleResultsList() {
            const header = document.getElementById('results-list-header');
            const content = document.getElementById('results-list-content');
            header.classList.toggle('collapsed');
            content.classList.toggle('collapsed');
        }
        
        // Pause test
        async function pauseTest() {
            if (!isRunning) return;
            isPaused = !isPaused;
            
            try {
                await fetch('/api/test/pause', { method: 'POST' });
                
                const pauseBtn = document.getElementById('pause-btn');
                const statusBadge = document.getElementById('status-badge');
                
                if (isPaused) {
                    pauseBtn.textContent = '▶️';
                    pauseBtn.title = 'Resume';
                    statusBadge.textContent = 'Paused';
                    statusBadge.className = 'status-badge paused';
                    addLog('Test paused', 'warning');
                } else {
                    pauseBtn.textContent = '⏸️';
                    pauseBtn.title = 'Pause';
                    statusBadge.textContent = 'Running';
                    statusBadge.className = 'status-badge running';
                    addLog('Test resumed', 'info');
                }
            } catch (e) {
                addLog('Error pausing/resuming: ' + e.message, 'error');
            }
        }
        
        // Stop test
        async function stopTest() {
            if (!isRunning) return;
            
            try {
                await fetch('/api/test/stop', { method: 'POST' });
                addLog('Test stopped by user', 'warning');
                
                if (pollInterval) {
                    clearInterval(pollInterval);
                    pollInterval = null;
                }
                
                resetTestUI();
                document.getElementById('control-buttons').style.display = 'none';
                
                const statusBadge = document.getElementById('status-badge');
                statusBadge.textContent = 'Stopped';
                statusBadge.className = 'status-badge stopped';
            } catch (e) {
                addLog('Error stopping: ' + e.message, 'error');
            }
        }
        
        // Restart test
        async function restartTest() {
            await stopTest();
            setTimeout(() => {
                runTests();
            }, 500);
        }
        
        // Load config from server
        async function loadConfig() {
            try {
                const response = await fetch('/api/config');
                const config = await response.json();
                
                setTargetUrls(config.TARGETS || []);
                document.getElementById('sample-count').value = config.SAMPLE_COUNT || 5;
                document.getElementById('delay-seconds').value = config.DELAY_SECONDS || 2;
                document.getElementById('ping-duration').value = config.PING_DURATION || 10;
                document.getElementById('auto-contribute').checked = config.AUTO_CONTRIBUTE !== false;
                updateAutoContributeBadge(config.AUTO_CONTRIBUTE !== false);
                document.getElementById('use-custom-dns').checked = config.USE_CUSTOM_DNS !== false;
                document.getElementById('custom-dns-servers').value = config.CUSTOM_DNS_SERVERS || '8.8.8.8, 8.8.4.4';
                document.getElementById('ttfb-good').value = config.TTFB_GOOD_MS || 200;
                document.getElementById('ttfb-warning').value = config.TTFB_WARNING_MS || 500;
                document.getElementById('signal-threshold').value = config.SIGNAL_THRESHOLD_DBM || -70;
                document.getElementById('brand').value = config.BRAND || '';
                document.getElementById('no-internet').value = config.NO_INTERNET || '';
                document.getElementById('manual-latitude').value = config.MANUAL_LATITUDE || '';
                document.getElementById('manual-longitude').value = config.MANUAL_LONGITUDE || '';
            } catch (e) {
                console.error('Error loading config:', e);
            }
        }
        
        // Reset config to defaults
        function resetToDefaults() {
            setTargetUrls(['https://www.instagram.com', 'https://qt-google-cloud-cdn.bronze.systems']);
            document.getElementById('sample-count').value = 10;
            document.getElementById('delay-seconds').value = 30;
            document.getElementById('ping-duration').value = 60;
            document.getElementById('auto-contribute').checked = true;
            updateAutoContributeBadge(true);
            document.getElementById('use-custom-dns').checked = true;
            document.getElementById('custom-dns-servers').value = '8.8.8.8, 8.8.4.4';
            document.getElementById('ttfb-good').value = 600;
            document.getElementById('ttfb-warning').value = 800;
            document.getElementById('signal-threshold').value = -65;
            document.getElementById('brand').value = '';
            document.getElementById('no-internet').value = '';
            document.getElementById('manual-latitude').value = '';
            document.getElementById('manual-longitude').value = '';
            addLog('Configuration reset to defaults (not saved yet)', 'info');
        }
        
        // Save config to server
        async function saveConfig() {
            const config = getConfigPayload();
            
            try {
                const response = await fetch('/api/config', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify(config)
                });
                
                const result = await response.json();
                if (result.success) {
                    updateAutoContributeBadge(config.AUTO_CONTRIBUTE !== false);
                    await checkPrereqs();
                    await loadNetworkInfo();
                    addLog('Configuration saved', 'success');
                } else {
                    addLog('Failed to save config: ' + result.error, 'error');
                }
            } catch (e) {
                addLog('Error saving config: ' + e.message, 'error');
            }
        }
        
        // Check prerequisites
        async function checkPrereqs() {
            const prereqList = document.getElementById('prereq-list');
            const customDnsEnabled = document.getElementById('use-custom-dns')?.checked !== false;
            prereqList.innerHTML = `
                <div class="prereq-item checking">
                    <span class="prereq-icon"><div class="spinner"></div></span>
                    <div class="prereq-info">
                        <div class="prereq-name">Checking prerequisites...</div>
                    </div>
                </div>
            `;
            
            try {
                const response = await fetch('/api/prereqs');
                const prereqs = await response.json();
                
                let allRequired = true;
                let html = '';
                
                for (const [name, info] of Object.entries(prereqs)) {
                    const isRequired = name === 'custom_dns' ? customDnsEnabled : info.required;
                    const icon = info.status === 'ok' ? '✓' : (info.status === 'warning' ? '⚠' : '✗');
                    html += `
                        <div class="prereq-item ${info.status}">
                            <span class="prereq-icon">${icon}</span>
                            <div class="prereq-info">
                                <div class="prereq-name">${name}</div>
                                <div class="prereq-message">${info.message}</div>
                            </div>
                            <span class="prereq-badge">${isRequired ? 'Required' : 'Optional'}</span>
                        </div>
                    `;
                    
                    if (isRequired && info.status === 'error') {
                        allRequired = false;
                    }
                }
                
                prereqList.innerHTML = html;
                
                const statusBadge = document.getElementById('status-badge');
                
                if (allRequired) {
                    isReady = true;
                    statusBadge.textContent = 'Ready';
                    statusBadge.className = 'status-badge ready';
                } else {
                    isReady = false;
                    statusBadge.textContent = 'Not Ready';
                    statusBadge.className = 'status-badge not-ready';
                }
                updateRunButtonState();
                
            } catch (e) {
                console.error('Error checking prereqs:', e);
                isReady = false;
                const statusBadge = document.getElementById('status-badge');
                statusBadge.textContent = 'Not Ready';
                statusBadge.className = 'status-badge not-ready';
                prereqList.innerHTML = `
                    <div class="prereq-item error">
                        <span class="prereq-icon">✗</span>
                        <div class="prereq-info">
                            <div class="prereq-name">Error</div>
                            <div class="prereq-message">${e.message}</div>
                        </div>
                    </div>
                `;
                updateRunButtonState();
            }
        }
        
        // Run tests
        async function runTests() {
            if (isRunning) return;

            if (!isReady) {
                await checkPrereqs();
                if (!isReady) {
                    addLog('Prerequisites belum siap. Cek panel Prerequisites untuk item yang masih merah.', 'warning');
                    const prereqHeader = document.getElementById('prereq-header');
                    const prereqContent = document.getElementById('prereq-content');
                    if (prereqHeader && prereqContent && prereqContent.classList.contains('collapsed')) {
                        prereqHeader.classList.remove('collapsed');
                        prereqContent.classList.remove('collapsed');
                    }
                    return;
                }
            }
            
            isRunning = true;
            isPaused = false;
            
            const runBtn = document.getElementById('run-test-btn');
            runBtn.innerHTML = '<div class="spinner"></div> Menjalankan Tes...';
            runBtn.disabled = true;
            updateRunButtonState();
            
            const statusBadge = document.getElementById('status-badge');
            statusBadge.textContent = 'Running';
            statusBadge.className = 'status-badge running';
            
            // Show control buttons, hide run button
            document.getElementById('control-buttons').style.display = 'flex';
            document.getElementById('pause-btn').textContent = '⏸️';
            document.getElementById('pause-btn').title = 'Pause';
            
            document.getElementById('empty-state').style.display = 'none';
            document.getElementById('test-progress').style.display = 'block';
            document.getElementById('results-section').style.display = 'none';
            
            // Get current config
            const config = getConfigPayload();
            updateAutoContributeBadge(config.AUTO_CONTRIBUTE !== false);
            
            try {
                // Start test
                const response = await fetch('/api/test/start', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify(config)
                });
                const result = await response.json();
                if (!result.success) {
                    throw new Error(result.error || 'Failed to start test');
                }
                
                // Start polling for updates
                pollInterval = setInterval(pollStatus, 500);
                
            } catch (e) {
                addLog('Error starting test: ' + e.message, 'error');
                resetTestUI();
            }
        }
        
        // Poll for status updates
        async function pollStatus() {
            try {
                // Get logs
                const logsResponse = await fetch('/api/logs');
                const logs = await logsResponse.json();
                
                for (const log of logs) {
                    addLog(log.message, log.level, log.timestamp);
                }
                
                // Get status
                const statusResponse = await fetch('/api/test/status');
                const status = await statusResponse.json();
                
                // Update progress
                if (status.ttfb_results && status.config) {
                    const total = status.config.TARGETS.length * status.config.SAMPLE_COUNT;
                    const current = status.ttfb_results.length;
                    const pct = Math.round((current / total) * 100);
                    document.getElementById('progress-fill').style.width = pct + '%';
                    document.getElementById('progress-count').textContent = current + ' / ' + total;
                    document.getElementById('progress-percent').textContent = pct + '%';
                    
                    // Calculate ETA
                    if (current > 0 && current < total) {
                        const elapsed = status.elapsed_seconds || 0;
                        const avgPerTest = elapsed / current;
                        const remaining = (total - current) * avgPerTest;
                        if (remaining < 60) {
                            document.getElementById('progress-eta').textContent = 'ETA: ' + Math.round(remaining) + 's';
                        } else {
                            document.getElementById('progress-eta').textContent = 'ETA: ' + Math.round(remaining / 60) + 'm ' + Math.round(remaining % 60) + 's';
                        }
                    } else if (current >= total) {
                        document.getElementById('progress-eta').textContent = 'Done!';
                    }
                }
                
                // Update network info
                if (status.network_info) {
                    updateNetworkInfo(status.network_info);
                }
                
                // Update results
                if (status.ttfb_results && status.ttfb_results.length > 0) {
                    updateResults(status);
                }
                
                // Check if done
                if (status.status === 'completed' || status.status === 'error') {
                    clearInterval(pollInterval);
                    pollInterval = null;
                    resetTestUI();
                    
                    if (status.status === 'completed') {
                        document.getElementById('test-progress').style.display = 'none';
                    }
                }
                
            } catch (e) {
                console.error('Poll error:', e);
            }
        }
        
        // Update network info display
        function updateNetworkInfo(info) {
            const container = document.getElementById('network-info');
            const grid = document.getElementById('network-grid');
            
            // Cache network info for browser location updates
            cachedNetworkInfo = info;
            
            container.style.display = 'block';
            
            // Merge browser location if available (more precise)
            const location = Object.assign({}, info.location || {});
            if (browserLocation && location.source !== 'manual_config' && location.source !== 'cli_argument') {
                location.lat = browserLocation.lat;
                location.lon = browserLocation.lon;
                location.accuracy = browserLocation.accuracy;
                location.is_precise = true;
                location.method = 'GPS (Browser)';
                if (browserLocation.city) location.city = browserLocation.city;
                if (browserLocation.region) location.region = browserLocation.region;
                if (browserLocation.country) location.country = browserLocation.country;
            }
            
            let html = '';
            
            // Device section with more info
            html += '<div class="network-section">';
            html += '<div class="section-header">💻 Device</div>';
            html += '<div class="device-grid">';
            
            if (info.device_name) {
                html += '<div class="network-item"><label>Name</label><div class="value">' + info.device_name + '</div></div>';
            }
            if (info.device_model) {
                html += '<div class="network-item"><label>Model</label><div class="value">' + info.device_model + '</div></div>';
            }
            if (info.os_version) {
                html += '<div class="network-item"><label>OS</label><div class="value">' + info.os_version + '</div></div>';
            }
            if (info.battery_level !== null && info.battery_level !== undefined) {
                const batteryIcon = info.battery_charging ? '🔌' : (info.battery_level > 20 ? '🔋' : '🪫');
                const chargingText = info.battery_charging ? ' (Charging)' : '';
                html += '<div class="network-item"><label>Battery</label><div class="value">' + batteryIcon + ' ' + info.battery_level + '%' + chargingText + '</div></div>';
            }
            
            html += '</div>'; // Close device-grid
            html += '</div>'; // Close network-section
            
            // Signal section with status indicator
            const threshold = info.signal_threshold || -70;
            const rssi = info.wifi_rssi;
            let signalStatus = '❓ Unknown';
            let signalClass = 'unknown';
            let signalBarClass = 'unknown';
            let signalPercent = 0;
            
            if (rssi !== null && rssi !== undefined) {
                // Calculate signal strength percentage (-100 to -30 dBm range)
                signalPercent = Math.min(100, Math.max(0, ((rssi + 100) / 70) * 100));
                
                if (rssi >= -50) {
                    signalStatus = '✅ Excellent';
                    signalClass = 'good';
                    signalBarClass = 'excellent';
                } else if (rssi >= -60) {
                    signalStatus = '✅ Good';
                    signalClass = 'good';
                    signalBarClass = 'good';
                } else if (rssi >= -70) {
                    signalStatus = '⚡ Fair';
                    signalClass = 'warning';
                    signalBarClass = 'fair';
                } else if (rssi >= -80) {
                    signalStatus = '⚠️ Weak';
                    signalClass = 'warning';
                    signalBarClass = 'weak';
                } else {
                    signalStatus = '❌ Poor';
                    signalClass = 'warning';
                    signalBarClass = 'poor';
                }
            }
            
            html += '<div class="network-section">';
            html += '<div class="section-header">📶 WiFi Signal <span class="signal-badge ' + signalClass + '">' + signalStatus + '</span></div>';
            
            if (info.wifi_ssid) {
                html += '<div class="network-item"><label>SSID</label><div class="value">' + info.wifi_ssid + '</div></div>';
            } else {
                html += '<div class="network-item"><label>SSID</label><div class="value muted">Not detected <span class="hint">(macOS: grant Location Services permission)</span></div></div>';
            }
            
            if (rssi !== null && rssi !== undefined) {
                html += '<div class="network-item"><label>RSSI</label><div class="value">' + rssi + ' dBm <span class="threshold-info">(threshold: ' + threshold + ' dBm)</span></div></div>';
                
                // Signal bar
                html += '<div class="signal-bar-container">';
                html += '<div class="signal-bar"><div class="signal-bar-fill ' + signalBarClass + '" style="width: ' + signalPercent + '%"></div></div>';
                html += '<div class="signal-labels"><span>Poor</span><span>Weak</span><span>Fair</span><span>Good</span><span>Excellent</span></div>';
                html += '</div>';
            }
            
            if (info.wifi_band) {
                const channelInfo = info.wifi_channel ? ' (Ch ' + info.wifi_channel + ')' : '';
                html += '<div class="network-item"><label>Band</label><div class="value">' + info.wifi_band + channelInfo + '</div></div>';
            }
            
            html += '</div>';
            
            // DNS section
            html += '<div class="network-section">';
            html += '<div class="section-header">🌐 DNS</div>';
            if (info.dns_primary) {
                const primaryLabel = info.dns_override_enabled ? 'Test DNS' : 'Primary';
                html += '<div class="network-item"><label>' + primaryLabel + '</label><div class="value">' + info.dns_primary + '</div></div>';
            }
            if (info.dns_override_enabled && info.system_dns_primary) {
                html += '<div class="network-item"><label>System DNS</label><div class="value">' + info.system_dns_primary + '</div></div>';
            }
            if (info.dns_servers && info.dns_servers.length > 1) {
                const serverLabel = info.dns_override_enabled ? 'Custom Servers' : 'All Servers';
                html += '<div class="network-item"><label>' + serverLabel + '</label><div class="value small">' + info.dns_servers.join(', ') + '</div></div>';
            }
            html += '</div>';
            
            // Location section - text only (map is persistent outside grid)
            if (location.lat || location.city) {
                const isManualLocation = location.input_mode === 'manual' || location.source === 'manual_config' || location.source === 'cli_argument';
                const locMethod = location.method || (location.is_precise ? 'GPS (Browser)' : 'IP Geolocation');
                const locClass = isManualLocation ? 'manual' : (location.is_precise ? 'precise' : 'approximate');
                const locBadge = isManualLocation ? '📍 Manual Input' : (location.is_precise ? '📍 Precise' : '📍 Approximate');
                
                html += '<div class="network-section">';
                html += '<div class="section-header">📍 Location <span class="loc-badge ' + locClass + '">' + locBadge + '</span></div>';
                
                html += '<div class="location-info">';
                
                if (location.lat && location.lon) {
                    const accuracy = location.accuracy ? ' (±' + Math.round(location.accuracy) + 'm)' : '';
                    html += '<div class="network-item"><label>Coordinates' + accuracy + '</label><div class="value">' + location.lat.toFixed(5) + ', ' + location.lon.toFixed(5) + '</div></div>';
                }
                
                const cityParts = [location.city, location.region, location.country].filter(p => p);
                html += '<div class="network-item"><label>Location</label><div class="value">' + cityParts.join(', ') + '</div></div>';
                
                html += '<div class="network-item"><label>ISP</label><div class="value">' + (location.isp || 'N/A') + '</div></div>';
                html += '<div class="network-item"><label>Public IP</label><div class="value">' + (location.ip || 'N/A') + '</div></div>';
                html += '<div class="network-item"><label>Method</label><div class="value">' + locMethod + '</div></div>';
                html += '</div>';
                
                html += '</div>';
            }
            
            // Update the grid with all HTML (no map - map is persistent)
            grid.innerHTML = html || '<div class="network-item"><label>Status</label><div class="value">Detecting...</div></div>';
            
            // Update persistent map (only change src if coords changed)
            if (location.lat && location.lon) {
                const lat = location.lat;
                const lon = location.lon;
                const coordsKey = lat.toFixed(5) + ',' + lon.toFixed(5);
                
                const persistentMap = document.getElementById('persistent-map');
                const mapIframe = document.getElementById('map-iframe');
                persistentMap.style.display = 'block';
                
                if (lastMapCoords !== coordsKey) {
                    lastMapCoords = coordsKey;
                    const zoom = 0.008;
                    const mapUrl = 'https://www.openstreetmap.org/export/embed.html?bbox=' + (lon-zoom) + '%2C' + (lat-zoom) + '%2C' + (lon+zoom) + '%2C' + (lat+zoom) + '&layer=mapnik&marker=' + lat + '%2C' + lon;
                    mapIframe.src = mapUrl;
                }
            }
        }
        
        // Update results display
        function updateResults(status) {
            const resultsSection = document.getElementById('results-section');
            const emptyState = document.getElementById('empty-state');
            const summaryCards = document.getElementById('summary-cards');
            const tbody = document.getElementById('results-tbody');
            const downloadSection = document.getElementById('download-section');
            const contributeBtn = document.getElementById('contribute-btn');
            
            emptyState.style.display = 'none';
            resultsSection.style.display = 'block';
            
            // Update summary
            if (status.summary && status.summary.mean_ttfb) {
                const poorCount = status.summary.poor_count || 0;
                summaryCards.innerHTML = `
                    <div class="summary-card">
                        <div class="value">${status.summary.mean_ttfb.toFixed(0)}</div>
                        <div class="label">Mean TTFB (ms)</div>
                    </div>
                    <div class="summary-card good">
                        <div class="value">${status.summary.good_count || 0}</div>
                        <div class="label">Good</div>
                    </div>
                    <div class="summary-card warning">
                        <div class="value">${status.summary.warning_count || 0}</div>
                        <div class="label">Warning</div>
                    </div>
                    <div class="summary-card poor">
                        <div class="value">${poorCount}</div>
                        <div class="label">Poor</div>
                    </div>
                `;
            }
            
            // Update table
            let html = '';
            for (const result of status.ttfb_results) {
                const ttfbDisplay = result.ttfb_ms ? `${result.ttfb_ms.toFixed(0)}ms` : 'ERR';
                const timeDisplay = result.time_short || '-';
                const rssiDisplay = result.rssi ? `${result.rssi}` : '-';
                const bandDisplay = result.band || '-';
                const dnsDisplay = result.dns ? result.dns.split('.').slice(0, 2).join('.') + '...' : '-';
                html += `
                    <tr>
                        <td class="time-col">${timeDisplay}</td>
                        <td class="target-col" title="${result.target_name || '-'}">${result.target_name || '-'}</td>
                        <td>${result.sample_num || '-'}</td>
                        <td>${ttfbDisplay}</td>
                        <td>${rssiDisplay}</td>
                        <td>${bandDisplay}</td>
                        <td title="${result.dns || '-'}">${dnsDisplay}</td>
                        <td><span class="ttfb-badge ${result.status}">${result.status}</span></td>
                    </tr>
                `;
            }
            tbody.innerHTML = html;
            
            // Show download buttons when completed
            if (status.status === 'completed') {
                downloadSection.style.display = 'block';
                if (contributeBtn) {
                    const autoContribute = status.config && status.config.AUTO_CONTRIBUTE !== false;
                    updateAutoContributeBadge(autoContribute);
                    contributeBtn.style.display = autoContribute ? 'none' : '';
                    contributeBtn.disabled = false;
                    contributeBtn.textContent = '🤝 Contribute';
                }
                drawCharts(status);
            } else {
                downloadSection.style.display = 'none';
            }
        }
        
        // ===== CHART DRAWING (Pure Canvas) =====
        
        function drawCharts(status) {
            const chartsSection = document.getElementById('charts-section');
            chartsSection.style.display = 'block';
            
            const results = status.ttfb_results.filter(r => r.ttfb_ms);
            if (results.length === 0) return;
            
            const config = status.config || {};
            const goodMs = config.TTFB_GOOD_MS || 200;
            const warnMs = config.TTFB_WARNING_MS || 500;
            
            // Group by target
            const byTarget = {};
            for (const r of results) {
                const name = r.target_name || 'Unknown';
                if (!byTarget[name]) byTarget[name] = [];
                byTarget[name].push(r.ttfb_ms);
            }
            const targetNames = Object.keys(byTarget);
            const targetColors = ['#3a7bd5', '#00d2ff', '#f093fb', '#ff6b6b', '#ffd93d', '#6bcb77', '#4d96ff', '#ff922b'];
            
            drawBoxplot('chart-boxplot', byTarget, targetNames, targetColors, goodMs, warnMs);
            drawBarChart('chart-bar', byTarget, targetNames, targetColors, goodMs, warnMs);
            drawLineChart('chart-line', results, targetNames, targetColors, goodMs, warnMs);
            drawPieChart('chart-pie', results);
        }
        
        function getCanvasCtx(id) {
            const canvas = document.getElementById(id);
            const dpr = window.devicePixelRatio || 1;
            const rect = canvas.getBoundingClientRect();
            canvas.width = rect.width * dpr;
            canvas.height = rect.height * dpr;
            const ctx = canvas.getContext('2d');
            ctx.scale(dpr, dpr);
            ctx.clearRect(0, 0, rect.width, rect.height);
            return { ctx, w: rect.width, h: rect.height };
        }
        
        function drawBoxplot(id, byTarget, names, colors, goodMs, warnMs) {
            const { ctx, w, h } = getCanvasCtx(id);
            const pad = { top: 20, right: 20, bottom: 50, left: 55 };
            const plotW = w - pad.left - pad.right;
            const plotH = h - pad.top - pad.bottom;
            
            // Find Y range
            let allVals = [];
            for (const name of names) allVals = allVals.concat(byTarget[name]);
            const yMin = 0;
            const yMax = Math.max(...allVals) * 1.15;
            
            const toY = (v) => pad.top + plotH - (v / yMax * plotH);
            
            // Y axis
            ctx.strokeStyle = 'rgba(255,255,255,0.1)';
            ctx.fillStyle = '#888';
            ctx.font = '11px SF Mono, Consolas, monospace';
            ctx.textAlign = 'right';
            const ySteps = 5;
            for (let i = 0; i <= ySteps; i++) {
                const val = yMin + (yMax - yMin) * i / ySteps;
                const y = toY(val);
                ctx.beginPath();
                ctx.moveTo(pad.left, y);
                ctx.lineTo(w - pad.right, y);
                ctx.stroke();
                ctx.fillText(Math.round(val) + 'ms', pad.left - 5, y + 4);
            }
            
            // Threshold lines
            if (goodMs < yMax) {
                ctx.strokeStyle = 'rgba(76,175,80,0.5)';
                ctx.setLineDash([4, 4]);
                ctx.beginPath();
                ctx.moveTo(pad.left, toY(goodMs));
                ctx.lineTo(w - pad.right, toY(goodMs));
                ctx.stroke();
                ctx.setLineDash([]);
            }
            if (warnMs < yMax) {
                ctx.strokeStyle = 'rgba(255,152,0,0.5)';
                ctx.setLineDash([4, 4]);
                ctx.beginPath();
                ctx.moveTo(pad.left, toY(warnMs));
                ctx.lineTo(w - pad.right, toY(warnMs));
                ctx.stroke();
                ctx.setLineDash([]);
            }
            
            // Draw boxes
            const boxW = Math.min(50, plotW / names.length * 0.6);
            const gap = plotW / names.length;
            
            for (let i = 0; i < names.length; i++) {
                const vals = byTarget[names[i]].slice().sort((a, b) => a - b);
                const cx = pad.left + gap * i + gap / 2;
                const min = vals[0];
                const max = vals[vals.length - 1];
                const q1 = vals[Math.floor(vals.length * 0.25)];
                const q3 = vals[Math.floor(vals.length * 0.75)];
                const median = vals[Math.floor(vals.length * 0.5)];
                
                const color = colors[i % colors.length];
                
                // Whiskers
                ctx.strokeStyle = color;
                ctx.lineWidth = 1.5;
                ctx.beginPath();
                ctx.moveTo(cx, toY(min));
                ctx.lineTo(cx, toY(q1));
                ctx.moveTo(cx, toY(q3));
                ctx.lineTo(cx, toY(max));
                ctx.stroke();
                
                // Whisker caps
                ctx.beginPath();
                ctx.moveTo(cx - boxW * 0.3, toY(min));
                ctx.lineTo(cx + boxW * 0.3, toY(min));
                ctx.moveTo(cx - boxW * 0.3, toY(max));
                ctx.lineTo(cx + boxW * 0.3, toY(max));
                ctx.stroke();
                
                // Box
                ctx.fillStyle = color + '33';
                ctx.strokeStyle = color;
                ctx.lineWidth = 2;
                const bx = cx - boxW / 2;
                const by = toY(q3);
                const bh = toY(q1) - toY(q3);
                ctx.fillRect(bx, by, boxW, bh);
                ctx.strokeRect(bx, by, boxW, bh);
                
                // Median
                ctx.strokeStyle = '#fff';
                ctx.lineWidth = 2;
                ctx.beginPath();
                ctx.moveTo(bx, toY(median));
                ctx.lineTo(bx + boxW, toY(median));
                ctx.stroke();
                
                // Label
                ctx.fillStyle = '#aaa';
                ctx.font = '10px -apple-system, sans-serif';
                ctx.textAlign = 'center';
                const label = names[i].length > 15 ? names[i].substring(0, 13) + '..' : names[i];
                ctx.fillText(label, cx, h - pad.bottom + 15);
            }
        }
        
        function drawBarChart(id, byTarget, names, colors, goodMs, warnMs) {
            const { ctx, w, h } = getCanvasCtx(id);
            const pad = { top: 20, right: 60, bottom: 30, left: 55 };
            const plotW = w - pad.left - pad.right;
            const plotH = h - pad.top - pad.bottom;
            
            const means = names.map(n => {
                const vals = byTarget[n];
                return vals.reduce((a, b) => a + b, 0) / vals.length;
            });
            const xMax = Math.max(...means) * 1.3;
            
            const toX = (v) => pad.left + (v / xMax * plotW);
            const barH = Math.min(30, plotH / names.length * 0.7);
            const gap = plotH / names.length;
            
            // X axis grid
            ctx.strokeStyle = 'rgba(255,255,255,0.08)';
            ctx.fillStyle = '#888';
            ctx.font = '11px SF Mono, Consolas, monospace';
            ctx.textAlign = 'center';
            for (let i = 0; i <= 4; i++) {
                const val = xMax * i / 4;
                const x = toX(val);
                ctx.beginPath();
                ctx.moveTo(x, pad.top);
                ctx.lineTo(x, h - pad.bottom);
                ctx.stroke();
                ctx.fillText(Math.round(val) + 'ms', x, h - pad.bottom + 15);
            }
            
            // Threshold lines
            if (goodMs < xMax) {
                ctx.strokeStyle = 'rgba(76,175,80,0.5)';
                ctx.setLineDash([4, 4]);
                ctx.beginPath();
                ctx.moveTo(toX(goodMs), pad.top);
                ctx.lineTo(toX(goodMs), h - pad.bottom);
                ctx.stroke();
                ctx.setLineDash([]);
            }
            if (warnMs < xMax) {
                ctx.strokeStyle = 'rgba(255,152,0,0.5)';
                ctx.setLineDash([4, 4]);
                ctx.beginPath();
                ctx.moveTo(toX(warnMs), pad.top);
                ctx.lineTo(toX(warnMs), h - pad.bottom);
                ctx.stroke();
                ctx.setLineDash([]);
            }
            
            // Draw bars
            for (let i = 0; i < names.length; i++) {
                const cy = pad.top + gap * i + gap / 2;
                const mean = means[i];
                const color = mean < goodMs ? '#4caf50' : (mean < warnMs ? '#ff9800' : '#f44336');
                
                // Bar
                const bw = toX(mean) - pad.left;
                ctx.fillStyle = color + 'aa';
                ctx.beginPath();
                ctx.roundRect(pad.left, cy - barH / 2, bw, barH, 4);
                ctx.fill();
                
                // Value label
                ctx.fillStyle = '#ddd';
                ctx.font = '11px SF Mono, Consolas, monospace';
                ctx.textAlign = 'left';
                ctx.fillText(Math.round(mean) + 'ms', toX(mean) + 6, cy + 4);
                
                // Target label
                ctx.fillStyle = '#aaa';
                ctx.font = '10px -apple-system, sans-serif';
                ctx.textAlign = 'right';
                const label = names[i].length > 12 ? names[i].substring(0, 10) + '..' : names[i];
                ctx.fillText(label, pad.left - 5, cy + 4);
            }
        }
        
        function drawLineChart(id, results, names, colors, goodMs, warnMs) {
            const { ctx, w, h } = getCanvasCtx(id);
            const pad = { top: 20, right: 20, bottom: 50, left: 55 };
            const plotW = w - pad.left - pad.right;
            const plotH = h - pad.top - pad.bottom;
            
            let maxSample = 0;
            let maxTtfb = 0;
            const byTarget = {};
            for (const r of results) {
                const name = r.target_name || 'Unknown';
                if (!byTarget[name]) byTarget[name] = [];
                byTarget[name].push({ x: r.sample_num, y: r.ttfb_ms });
                if (r.sample_num > maxSample) maxSample = r.sample_num;
                if (r.ttfb_ms > maxTtfb) maxTtfb = r.ttfb_ms;
            }
            maxTtfb *= 1.15;
            
            const toX = (v) => pad.left + ((v - 1) / Math.max(maxSample - 1, 1) * plotW);
            const toY = (v) => pad.top + plotH - (v / maxTtfb * plotH);
            
            // Grid
            ctx.strokeStyle = 'rgba(255,255,255,0.08)';
            ctx.fillStyle = '#888';
            ctx.font = '11px SF Mono, Consolas, monospace';
            ctx.textAlign = 'right';
            for (let i = 0; i <= 5; i++) {
                const val = maxTtfb * i / 5;
                const y = toY(val);
                ctx.beginPath();
                ctx.moveTo(pad.left, y);
                ctx.lineTo(w - pad.right, y);
                ctx.stroke();
                ctx.fillText(Math.round(val) + 'ms', pad.left - 5, y + 4);
            }
            
            // X axis labels
            ctx.textAlign = 'center';
            for (let s = 1; s <= maxSample; s++) {
                ctx.fillText('#' + s, toX(s), h - pad.bottom + 15);
            }
            
            // Threshold lines
            if (goodMs < maxTtfb) {
                ctx.strokeStyle = 'rgba(76,175,80,0.4)';
                ctx.setLineDash([4, 4]);
                ctx.beginPath();
                ctx.moveTo(pad.left, toY(goodMs));
                ctx.lineTo(w - pad.right, toY(goodMs));
                ctx.stroke();
                ctx.setLineDash([]);
            }
            if (warnMs < maxTtfb) {
                ctx.strokeStyle = 'rgba(255,152,0,0.4)';
                ctx.setLineDash([4, 4]);
                ctx.beginPath();
                ctx.moveTo(pad.left, toY(warnMs));
                ctx.lineTo(w - pad.right, toY(warnMs));
                ctx.stroke();
                ctx.setLineDash([]);
            }
            
            // Draw lines
            const targetIdx = {};
            let idx = 0;
            for (const name of names) {
                targetIdx[name] = idx++;
            }
            
            for (const name of Object.keys(byTarget)) {
                const pts = byTarget[name].sort((a, b) => a.x - b.x);
                const ci = targetIdx[name] !== undefined ? targetIdx[name] : 0;
                const color = colors[ci % colors.length];
                
                ctx.strokeStyle = color;
                ctx.lineWidth = 2;
                ctx.beginPath();
                for (let i = 0; i < pts.length; i++) {
                    const x = toX(pts[i].x);
                    const y = toY(pts[i].y);
                    if (i === 0) ctx.moveTo(x, y);
                    else ctx.lineTo(x, y);
                }
                ctx.stroke();
                
                // Dots
                ctx.fillStyle = color;
                for (const pt of pts) {
                    ctx.beginPath();
                    ctx.arc(toX(pt.x), toY(pt.y), 3.5, 0, Math.PI * 2);
                    ctx.fill();
                }
            }
            
            // Legend
            ctx.font = '10px -apple-system, sans-serif';
            let lx = pad.left + 5;
            for (let i = 0; i < names.length; i++) {
                const color = colors[i % colors.length];
                ctx.fillStyle = color;
                ctx.fillRect(lx, h - 15, 12, 3);
                ctx.fillStyle = '#aaa';
                const label = names[i].length > 12 ? names[i].substring(0, 10) + '..' : names[i];
                ctx.textAlign = 'left';
                ctx.fillText(label, lx + 16, h - 11);
                lx += ctx.measureText(label).width + 30;
            }
        }
        
        function drawPieChart(id, results) {
            const { ctx, w, h } = getCanvasCtx(id);
            
            const counts = {};
            for (const r of results) {
                const s = r.status || 'unknown';
                counts[s] = (counts[s] || 0) + 1;
            }
            
            const statusColors = {
                good: '#4caf50',
                warning: '#ff9800',
                poor: '#f44336',
                error: '#9e9e9e',
                timeout: '#757575',
                unknown: '#616161'
            };
            
            const total = Object.values(counts).reduce((a, b) => a + b, 0);
            const cx = w * 0.4;
            const cy = h * 0.5;
            const radius = Math.min(cx - 20, cy - 30) * 0.85;
            
            let startAngle = -Math.PI / 2;
            const slices = Object.entries(counts).sort((a, b) => b[1] - a[1]);
            
            for (const [status, count] of slices) {
                const angle = (count / total) * Math.PI * 2;
                const color = statusColors[status] || '#888';
                
                ctx.fillStyle = color;
                ctx.beginPath();
                ctx.moveTo(cx, cy);
                ctx.arc(cx, cy, radius, startAngle, startAngle + angle);
                ctx.closePath();
                ctx.fill();
                
                // Percentage label
                const midAngle = startAngle + angle / 2;
                const labelR = radius * 0.65;
                const lx = cx + Math.cos(midAngle) * labelR;
                const ly = cy + Math.sin(midAngle) * labelR;
                const pct = ((count / total) * 100).toFixed(1);
                if (parseFloat(pct) > 3) {
                    ctx.fillStyle = '#fff';
                    ctx.font = 'bold 12px -apple-system, sans-serif';
                    ctx.textAlign = 'center';
                    ctx.textBaseline = 'middle';
                    ctx.fillText(pct + '%', lx, ly);
                }
                
                startAngle += angle;
            }
            
            // Legend
            ctx.font = '11px -apple-system, sans-serif';
            ctx.textAlign = 'left';
            ctx.textBaseline = 'top';
            let ly = 25;
            for (const [status, count] of slices) {
                const color = statusColors[status] || '#888';
                const lx = w * 0.75;
                
                ctx.fillStyle = color;
                ctx.beginPath();
                ctx.roundRect(lx, ly, 12, 12, 2);
                ctx.fill();
                
                ctx.fillStyle = '#ccc';
                ctx.fillText(`${status} (${count})`, lx + 18, ly + 1);
                ly += 22;
            }
        }
        
        // Download CSV
        async function downloadCSV() {
            try {
                const response = await fetch('/api/download/csv');
                if (!response.ok) throw new Error('Download failed');
                
                const blob = await response.blob();
                const filename = response.headers.get('Content-Disposition')?.split('filename=')[1]?.replace(/"/g, '') || 'ttfb_results.csv';
                
                const url = window.URL.createObjectURL(blob);
                const a = document.createElement('a');
                a.href = url;
                a.download = filename;
                document.body.appendChild(a);
                a.click();
                document.body.removeChild(a);
                window.URL.revokeObjectURL(url);
                
                addLog('CSV downloaded: ' + filename, 'success');
            } catch (e) {
                addLog('Error downloading CSV: ' + e.message, 'error');
            }
        }
        
        // Download Report
        async function downloadReport() {
            try {
                const response = await fetch('/api/download/report');
                if (!response.ok) throw new Error('Download failed');
                
                const blob = await response.blob();
                const filename = response.headers.get('Content-Disposition')?.split('filename=')[1]?.replace(/"/g, '') || 'ttfb_report.txt';
                
                const url = window.URL.createObjectURL(blob);
                const a = document.createElement('a');
                a.href = url;
                a.download = filename;
                document.body.appendChild(a);
                a.click();
                document.body.removeChild(a);
                window.URL.revokeObjectURL(url);
                
                addLog('Report downloaded: ' + filename, 'success');
            } catch (e) {
                addLog('Error downloading report: ' + e.message, 'error');
            }
        }

        async function contributeResults() {
            const button = document.getElementById('contribute-btn');
            if (!button) return;

            const originalText = button.textContent;
            button.disabled = true;
            button.textContent = '⏳ Contributing...';

            try {
                const response = await fetch('/api/contribute', { method: 'POST' });
                const result = await response.json();

                if (!response.ok || !result.success) {
                    throw new Error(result.error || 'Contribution failed');
                }

                if (result.failed > 0) {
                    button.disabled = false;
                    button.textContent = '🔁 Retry Failed';
                    addLog(`Contribute partial: ${result.submitted}/${result.total} submitted, ${result.failed} failed`, 'warning');
                } else {
                    button.textContent = `✅ Contributed (${result.submitted})`;
                    addLog(`Contribute success: ${result.submitted}/${result.total} rows submitted`, 'success');
                }
            } catch (e) {
                button.disabled = false;
                button.textContent = originalText;
                addLog('Error contributing results: ' + e.message, 'error');
            }
        }
        
        // Reset test UI
        function resetTestUI() {
            isRunning = false;
            isPaused = false;
            
            // Hide control buttons
            document.getElementById('control-buttons').style.display = 'none';
            
            const statusBadge = document.getElementById('status-badge');
            statusBadge.textContent = isReady ? 'Ready' : 'Not Ready';
            statusBadge.className = 'status-badge ' + (isReady ? 'ready' : 'not-ready');
            updateRunButtonState();

            const hasResults = document.getElementById('results-tbody').children.length > 0;
            document.getElementById('empty-state').style.display = hasResults ? 'none' : 'block';
        }
        
        // Add log entry
        function addLog(message, level = 'info', timestamp = null) {
            if (!message && level !== 'divider') return;
            
            const logsContent = document.getElementById('logs-content');
            const entry = document.createElement('div');
            entry.className = 'log-entry ' + level;
            
            if (level === 'divider') {
                entry.innerHTML = '';
            } else {
                const ts = timestamp || new Date().toLocaleTimeString('en-US', { hour12: false });
                entry.innerHTML = `<span class="log-timestamp">[${ts}]</span> ${message}`;
            }
            
            logsContent.appendChild(entry);
            logsContent.scrollTop = logsContent.scrollHeight;
        }
        
        // Clear logs
        function clearLogs() {
            document.getElementById('logs-content').innerHTML = `
                <div class="log-entry info">
                    <span class="log-timestamp">[${new Date().toLocaleTimeString('en-US', { hour12: false })}]</span>
                    Logs cleared
                </div>
            `;
        }
