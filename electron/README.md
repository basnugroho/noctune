# NOC Tune Electron App

Distribusi desktop NOC Tune yang plug-and-play. User tidak perlu install Python atau dependencies.

## Prasyarat untuk Build

- Node.js 18+
- npm
- Python 3.10+ (untuk build backend)
- PyInstaller

## Cara Build

### 1. Build Semua (Recommended)

```bash
cd electron
./scripts/build.sh all
```

### 2. Build per Komponen

```bash
# Build Python backend saja
./scripts/build.sh backend

# Build Electron app saja (setelah backend sudah di-build)
./scripts/build.sh electron mac    # macOS
./scripts/build.sh electron win    # Windows
./scripts/build.sh electron linux  # Linux
```

## Development Mode

```bash
# Install dependencies
cd electron
npm install

# Run in dev mode (uses Python directly)
npm run start:dev
```

## Struktur Output

Setelah build selesai:

```
electron/dist/
├── mac/
│   └── NOC Tune.app           # macOS app bundle
├── mac-arm64/
│   └── NOC Tune.app           # macOS Apple Silicon
├── win-unpacked/
│   └── NOC Tune.exe            # Windows executable
└── linux-unpacked/
    └── noc-tune                # Linux executable
```

## Catatan

1. **Icon**: Letakkan icon di `electron/resources/`:
   - `icon.icns` untuk macOS
   - `icon.ico` untuk Windows
   - `icon.png` untuk Linux (512x512)

2. **Code Signing**: Untuk distribusi production, perlu code signing:
   - macOS: Apple Developer certificate
   - Windows: EV certificate untuk SmartScreen

3. **Auto-update**: Bisa ditambah dengan electron-updater jika diperlukan
