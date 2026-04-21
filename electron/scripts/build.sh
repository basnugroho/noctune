#!/bin/bash
# Build script for NOC Tune Electron app

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ELECTRON_DIR="$(dirname "$SCRIPT_DIR")"
PROJECT_ROOT="$(dirname "$ELECTRON_DIR")"

echo "=== NOC Tune Build Script ==="
echo "Project root: $PROJECT_ROOT"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# Check dependencies
check_deps() {
    info "Checking dependencies..."
    
    command -v python3 >/dev/null 2>&1 || error "Python 3 is required"
    command -v npm >/dev/null 2>&1 || error "npm is required"
    command -v node >/dev/null 2>&1 || error "Node.js is required"
    
    info "All dependencies found"
}

# Build Python backend with PyInstaller
build_backend() {
    info "Building Python backend..."

    if [ "$(uname -s)" = "Darwin" ]; then
        build_backend_macos
        info "Backend built successfully"
        return
    fi
    
    cd "$PROJECT_ROOT"
    
    # Activate venv if exists
    if [ -d ".venv" ]; then
        source .venv/bin/activate
    fi
    
    # Install PyInstaller if needed
    pip install pyinstaller
    
    # Build
    pyinstaller --clean --noconfirm noctune-backend.spec
    
    info "Backend built successfully"
}

# Install Electron dependencies
install_electron_deps() {
    info "Installing Electron dependencies..."
    
    cd "$ELECTRON_DIR"
    npm install
    
    info "Electron dependencies installed"
}

build_backend_macos_arch() {
    local backend_arch="$1"
    local python_bin="$2"
    local output_name="$3"

    [ -x "$python_bin" ] || error "Required Python not found: $python_bin"

    info "Building macOS backend for ${backend_arch}..."

    cd "$PROJECT_ROOT"

    local venv_dir=".venv-macos-${backend_arch}"
    if [ ! -d "$venv_dir" ]; then
        "$python_bin" -m venv "$venv_dir"
    fi

    # shellcheck disable=SC1090
    source "$venv_dir/bin/activate"

    python -m pip install --upgrade pip setuptools wheel
    python -m pip install pyinstaller dnspython
    python -m pip install pyobjc-framework-CoreWLAN

    rm -f "dist/${output_name}"
    pyinstaller --clean --noconfirm noctune-backend.spec --distpath dist --workpath "build/pyinstaller-${backend_arch}" --target-arch "$backend_arch"
    mv -f dist/noctune-backend "dist/${output_name}"

    deactivate

    info "macOS backend ready: dist/${output_name}"
}

build_backend_macos() {
    build_backend_macos_arch arm64 /opt/homebrew/bin/python3 noctune-backend-arm64
    build_backend_macos_arch x86_64 /usr/local/bin/python3 noctune-backend-x64

    cp -f dist/noctune-backend-arm64 dist/noctune-backend
}

# Build Electron app
build_electron() {
    local platform="${1:-$(uname -s | tr '[:upper:]' '[:lower:]')}"
    
    info "Building Electron app for $platform..."
    
    cd "$ELECTRON_DIR"
    
    case "$platform" in
        darwin|mac|macos)
            npm run build:mac
            ;;
        win32|windows|win)
            npm run build:win
            ;;
        linux)
            npm run build:linux
            ;;
        *)
            npm run build
            ;;
    esac
    
    info "Electron app built successfully"
}

build_all() {
    check_deps
    build_backend
    install_electron_deps
    build_electron "$1"
    
    echo ""
    info "=== Build Complete ==="
    info "Output: $ELECTRON_DIR/dist/"
    ls -la "$ELECTRON_DIR/dist/" 2>/dev/null || true
}

# Parse arguments
case "${1:-all}" in
    backend)
        check_deps
        build_backend
        ;;
    electron)
        check_deps
        install_electron_deps
        build_electron "$2"
        ;;
    deps)
        check_deps
        install_electron_deps
        ;;
    all)
        build_all "$2"
        ;;
    *)
        echo "Usage: $0 {all|backend|electron|deps} [platform]"
        echo ""
        echo "Commands:"
        echo "  all [platform]     - Build everything (default)"
        echo "  backend            - Build Python backend only"
        echo "  electron [platform]- Build Electron app only"
        echo "  deps               - Install dependencies only"
        echo ""
        echo "Platforms: mac, win, linux"
        exit 1
        ;;
esac
