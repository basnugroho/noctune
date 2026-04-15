const { app, BrowserWindow, dialog, shell } = require('electron');
const { spawn } = require('child_process');
const path = require('path');
const fs = require('fs');
const log = require('electron-log');

// Configure logging
log.transports.file.level = 'info';
log.transports.console.level = 'debug';

let mainWindow;
let pythonProcess = null;
let backendPort = 8765;

// Determine if we're in development or production
const isDev = process.env.NODE_ENV === 'development';

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

    // Production: use bundled executable
    const platform = process.platform;
    let execName = 'noctune-backend';
    
    if (platform === 'win32') {
        execName = 'noctune-backend.exe';
    }
    
    return path.join(process.resourcesPath, 'backend', execName);
}

function startBackend() {
    return new Promise((resolve, reject) => {
        const backendPath = getBackendPath();
        
        if (isDev) {
            // Development mode: run Python directly
            const pythonPath = path.join(__dirname, '..', '.venv', 'bin', 'python');
            const mainPath = path.join(__dirname, '..', 'main.py');
            
            log.info(`Starting backend in dev mode: ${pythonPath} ${mainPath}`);
            
            pythonProcess = spawn(pythonPath, [mainPath, '--ui', `--port=${backendPort}`], {
                cwd: path.join(__dirname, '..'),
                env: { ...process.env, PYTHONUNBUFFERED: '1' }
            });
        } else {
            // Production mode: run bundled executable
            if (!fs.existsSync(backendPath)) {
                reject(new Error(`Backend not found at: ${backendPath}`));
                return;
            }
            
            log.info(`Starting backend: ${backendPath}`);
            
            // Ensure notebooks directory exists for config
            const notebooksPath = getResourcePath('notebooks');
            if (!fs.existsSync(notebooksPath)) {
                fs.mkdirSync(notebooksPath, { recursive: true });
            }
            
            pythonProcess = spawn(backendPath, ['--ui', `--port=${backendPort}`], {
                cwd: path.dirname(backendPath),
                env: { ...process.env }
            });
        }
        
        pythonProcess.stdout.on('data', (data) => {
            const output = data.toString();
            log.info(`Backend: ${output}`);
            
            // Check if server is ready
            if (output.includes('Starting server') || output.includes(`port ${backendPort}`)) {
                setTimeout(() => resolve(), 500);
            }
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
        });
        
        // Fallback: resolve after timeout
        setTimeout(() => resolve(), 3000);
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
    
    // Load the app
    const appUrl = `http://localhost:${backendPort}`;
    log.info(`Loading: ${appUrl}`);
    
    mainWindow.loadURL(appUrl);
    
    // Show window when ready
    mainWindow.once('ready-to-show', () => {
        mainWindow.show();
        
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

// App lifecycle
app.whenReady().then(async () => {
    log.info('NOC Tune starting...');
    log.info(`Mode: ${isDev ? 'development' : 'production'}`);
    log.info(`Platform: ${process.platform}`);
    
    try {
        // Start Python backend
        await startBackend();
        log.info('Backend started successfully');
        
        // Create window
        createWindow();
        
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
