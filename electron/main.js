const { app, BrowserWindow, dialog, shell, ipcMain } = require('electron');
const { spawn, spawnSync } = require('child_process');
const path = require('path');
const fs = require('fs');
const log = require('electron-log');

// Disable GPU acceleration for servers without proper GPU drivers
app.disableHardwareAcceleration();
app.commandLine.appendSwitch('disable-gpu');

// App version info
const APP_VERSION = {
    version: '1.0.0',
    releaseDate: 'April 16, 2026',
    githubUrl: 'https://github.com/basnugroho/noctune'
};

// Configure logging
log.transports.file.level = 'info';
log.transports.console.level = 'debug';

let mainWindow;
let pythonProcess = null;
let backendPort = 8765;
const BACKEND_HEALTH_MAX_ATTEMPTS = process.platform === 'win32' ? 120 : 30;
const BACKEND_HEALTH_INTERVAL_MS = 500;

// Determine if we're in development or production
const isDev = process.env.NODE_ENV === 'development';

const gotSingleInstanceLock = app.requestSingleInstanceLock();

if (!gotSingleInstanceLock) {
    app.quit();
}

app.on('second-instance', () => {
    if (mainWindow) {
        if (mainWindow.isMinimized()) {
            mainWindow.restore();
        }
        mainWindow.focus();
    }
});

function getResourcePath(relativePath) {
    if (isDev) {
        // Development: use project root
        return path.join(__dirname, '..', relativePath);
    } else {
        // Production: use app resources
        return path.join(process.resourcesPath, relativePath);
    }
}

function getBackendPath() {
    if (isDev) {
        // Development: use Python directly
        return null; // Will use python command
    }

    // Production: use bundled executable (single file from PyInstaller --onefile)
    const platform = process.platform;
    
    if (platform === 'win32') {
        // Windows: resources/backend/noctune-backend.exe
        return path.join(process.resourcesPath, 'backend', 'noctune-backend.exe');
    } else {
        // macOS/Linux: resources/backend/noctune-backend
        return path.join(process.resourcesPath, 'backend', 'noctune-backend');
    }
}

function cleanupStaleBackendProcesses() {
    if (isDev || process.platform !== 'win32') {
        return;
    }

    try {
        const result = spawnSync('taskkill', ['/im', 'noctune-backend.exe', '/f'], {
            windowsHide: true,
            encoding: 'utf8'
        });

        if (result.status === 0) {
            log.info('Stopped stale noctune-backend.exe process before startup');
            return;
        }

        const output = `${result.stdout || ''}${result.stderr || ''}`.toLowerCase();
        if (output.includes('no running instance') || output.includes('not found') || output.includes('tidak ditemukan')) {
            return;
        }

        if (output.trim()) {
            log.warn(`taskkill returned status ${result.status}: ${output.trim()}`);
        }
    } catch (err) {
        log.warn(`Failed to clean up stale backend process: ${err.message}`);
    }
}

// Health check function to verify backend is ready
function checkBackendHealth(maxAttempts = BACKEND_HEALTH_MAX_ATTEMPTS, intervalMs = BACKEND_HEALTH_INTERVAL_MS) {
    return new Promise((resolve, reject) => {
        const http = require('http');
        let attempts = 0;
        
        const check = () => {
            attempts++;
            log.info(`Health check attempt ${attempts}/${maxAttempts}...`);
            
            const req = http.get(`http://127.0.0.1:${backendPort}/`, (res) => {
                log.info(`Backend health check passed (status ${res.statusCode})`);
                resolve(true);
            });
            
            req.on('error', (err) => {
                log.warn(`Health check error: ${err.code} - ${err.message}`);
                if (attempts >= maxAttempts) {
                    log.error(`Backend health check failed after ${maxAttempts} attempts`);
                    reject(new Error(`Backend did not start within ${maxAttempts * intervalMs / 1000} seconds`));
                } else {
                    setTimeout(check, intervalMs);
                }
            });
            
            req.setTimeout(1000, () => {
                req.destroy();
                log.warn(`Health check timeout at attempt ${attempts}`);
                if (attempts >= maxAttempts) {
                    reject(new Error(`Backend health check timeout after ${maxAttempts} attempts`));
                } else {
                    setTimeout(check, intervalMs);
                }
            });
        };
        
        // Start checking after a brief delay
        setTimeout(check, 500);
    });
}

function startBackend() {
    return new Promise((resolve, reject) => {
        const backendPath = getBackendPath();
        
        if (isDev) {
            // Development mode: run Python directly
            const pythonPath = path.join(__dirname, '..', '.venv', 'bin', 'python');
            const mainPath = path.join(__dirname, '..', 'main.py');
            
            log.info(`Starting backend in dev mode: ${pythonPath} ${mainPath}`);
            
            pythonProcess = spawn(pythonPath, [mainPath, '--ui', `--port=${backendPort}`, '--no-browser'], {
                cwd: path.join(__dirname, '..'),
                env: { ...process.env, PYTHONUNBUFFERED: '1' }
            });
        } else {
            // Production mode: run bundled executable
            if (!fs.existsSync(backendPath)) {
                reject(new Error(`Backend not found at: ${backendPath}`));
                return;
            }

            cleanupStaleBackendProcesses();
            
            log.info(`Starting backend: ${backendPath}`);
            
            // Ensure notebooks directory exists for config
            const notebooksPath = getResourcePath('notebooks');
            if (!fs.existsSync(notebooksPath)) {
                fs.mkdirSync(notebooksPath, { recursive: true });
            }
            
            pythonProcess = spawn(backendPath, ['--ui', `--port=${backendPort}`, '--no-browser'], {
                cwd: path.dirname(backendPath),
                env: { ...process.env, PYTHONUNBUFFERED: '1' }
            });
        }
        
        pythonProcess.stdout.on('data', (data) => {
            const output = data.toString();
            log.info(`Backend: ${output}`);
        });
        
        pythonProcess.stderr.on('data', (data) => {
            log.error(`Backend error: ${data}`);
        });
        
        pythonProcess.on('error', (err) => {
            log.error(`Failed to start backend: ${err}`);
            reject(err);
        });
        
        pythonProcess.on('close', (code) => {
            log.info(`Backend exited with code ${code}`);
            pythonProcess = null;
            // If backend exits before health check succeeds, reject
            if (code !== 0) {
                reject(new Error(`Backend exited with code ${code}`));
            }
        });

        // Use active health check to detect when backend is ready
        log.info(`Starting health check (timeout ${Math.round(BACKEND_HEALTH_MAX_ATTEMPTS * BACKEND_HEALTH_INTERVAL_MS / 1000)}s)...`);
        checkBackendHealth()
            .then(() => {
                log.info('Backend is ready!');
                resolve();
            })
            .catch((err) => {
                log.error(`Backend health check failed: ${err.message}`);
                reject(err);
            });
    });
}

function stopBackend() {
    if (pythonProcess) {
        log.info('Stopping backend...');
        
        if (process.platform === 'win32') {
            spawn('taskkill', ['/pid', pythonProcess.pid, '/f', '/t']);
        } else {
            pythonProcess.kill('SIGTERM');
        }
        
        pythonProcess = null;
    }
}

function createWindow() {
    mainWindow = new BrowserWindow({
        width: 1400,
        height: 900,
        minWidth: 1024,
        minHeight: 700,
        title: 'NOC Tune',
        icon: isDev 
            ? path.join(__dirname, 'resources', 'icon.png')
            : path.join(process.resourcesPath, 'resources', 'icon.png'),
        webPreferences: {
            nodeIntegration: false,
            contextIsolation: true,
            preload: path.join(__dirname, 'preload.js')
        },
        show: false,
        backgroundColor: '#0a1929'
    });
    
    // Load the loading screen first
    const loadingPath = path.join(__dirname, 'loading.html');
    log.info(`Loading splash screen: ${loadingPath}`);
    mainWindow.loadFile(loadingPath);
    
    // Inject version info when loading page is ready
    mainWindow.webContents.on('did-finish-load', () => {
        mainWindow.webContents.executeJavaScript(`
            window.APP_VERSION = ${JSON.stringify(APP_VERSION)};
            if (document.getElementById('version')) {
                document.getElementById('version').textContent = '${APP_VERSION.version}';
                document.getElementById('release-date').textContent = '${APP_VERSION.releaseDate}';
            }
        `);
    });
    
    // Show window when ready
    mainWindow.once('ready-to-show', () => {
        mainWindow.show();
        
        // Only open DevTools in development mode
        if (isDev) {
            mainWindow.webContents.openDevTools();
        }
    });
    
    // Handle external links
    mainWindow.webContents.setWindowOpenHandler(({ url }) => {
        shell.openExternal(url);
        return { action: 'deny' };
    });
    
    mainWindow.on('closed', () => {
        mainWindow = null;
    });
}

function loadApp() {
    const appUrl = `http://127.0.0.1:${backendPort}`;
    log.info(`Loading app: ${appUrl}`);
    
    // Handle page load errors
    mainWindow.webContents.on('did-fail-load', (event, errorCode, errorDesc, validatedURL) => {
        log.error(`Page load failed: ${errorCode} - ${errorDesc} - ${validatedURL}`);
        // Retry after delay
        setTimeout(() => {
            log.info(`Retrying load: ${appUrl}`);
            mainWindow.loadURL(appUrl);
        }, 2000);
    });
    
    mainWindow.loadURL(appUrl);
}

// IPC Handlers
ipcMain.handle('get-version', () => {
    return APP_VERSION;
});

ipcMain.handle('open-external', (event, url) => {
    shell.openExternal(url);
});

// App lifecycle
app.whenReady().then(async () => {
    log.info('NOC Tune starting...');
    log.info(`Version: ${APP_VERSION.version}`);
    log.info(`Mode: ${isDev ? 'development' : 'production'}`);
    log.info(`Platform: ${process.platform}`);
    
    // Create window with loading screen first
    createWindow();
    
    try {
        // Start Python backend and wait until it is reachable
        await startBackend();
        log.info('Backend started successfully');
        
        // Load the actual app
        loadApp();
        
    } catch (err) {
        log.error('Failed to start application:', err);
        
        dialog.showErrorBox(
            'NOC Tune - Startup Error',
            `Failed to start the application:\n\n${err.message}\n\nPlease check the logs for more details.`
        );
        
        app.quit();
    }
});

app.on('window-all-closed', () => {
    stopBackend();
    
    if (process.platform !== 'darwin') {
        app.quit();
    }
});

app.on('activate', () => {
    if (BrowserWindow.getAllWindows().length === 0) {
        createWindow();
    }
});

app.on('before-quit', () => {
    stopBackend();
});

// Handle uncaught exceptions
process.on('uncaughtException', (err) => {
    log.error('Uncaught exception:', err);
    stopBackend();
});
