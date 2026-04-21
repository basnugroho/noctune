const fs = require('fs');
const path = require('path');

function resolveBackendName(arch) {
    if (arch === 'arm64') {
        return 'noctune-backend-arm64';
    }
    if (arch === 'x64') {
        return 'noctune-backend-x64';
    }
    throw new Error(`Unsupported mac backend arch code: ${arch}`);
}

exports.default = async function afterPack(context) {
    if (context.electronPlatformName !== 'darwin') {
        return;
    }

    const backendName = resolveBackendName(context.arch);
    const backendSource = path.resolve(context.appDir, '..', 'dist', backendName);
    const backendTarget = path.join(
        context.appOutDir,
        `${context.packager.appInfo.productFilename}.app`,
        'Contents',
        'Resources',
        'backend',
        'noctune-backend'
    );

    if (!fs.existsSync(backendSource)) {
        throw new Error(`Missing packaged backend for ${backendName}: ${backendSource}`);
    }

    fs.copyFileSync(backendSource, backendTarget);
    fs.chmodSync(backendTarget, 0o755);
    console.log(`Replaced mac backend with ${backendName}`);
};