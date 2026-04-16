const { contextBridge, ipcRenderer, shell } = require('electron');

// Expose protected methods to renderer
contextBridge.exposeInMainWorld('electronAPI', {
    // Platform info
    platform: process.platform,
    
    // App info
    getVersion: () => ipcRenderer.invoke('get-version'),
    
    // Open external URL in default browser
    openExternal: (url) => ipcRenderer.invoke('open-external', url),
    
    // File operations
    openPath: (filePath) => ipcRenderer.invoke('open-path', filePath),
    showItemInFolder: (filePath) => ipcRenderer.invoke('show-in-folder', filePath),
    
    // Dialog
    showSaveDialog: (options) => ipcRenderer.invoke('show-save-dialog', options),
    
    // Notifications
    showNotification: (title, body) => ipcRenderer.send('show-notification', { title, body })
});

// Log when preload completes
console.log('NOC Tune preload script loaded');
