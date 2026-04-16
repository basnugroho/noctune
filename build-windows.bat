@echo off
REM NOC Tune Windows Build Script
REM Run this on Windows to build the application

echo === NOC Tune Windows Build ===
echo.

REM Check Python
python --version >nul 2>&1
if errorlevel 1 (
    echo ERROR: Python not found. Please install Python 3.10+
    pause
    exit /b 1
)

REM Check Node
node --version >nul 2>&1
if errorlevel 1 (
    echo ERROR: Node.js not found. Please install Node.js 18+
    pause
    exit /b 1
)

echo [1/5] Setting up Python environment...
if not exist .venv (
    python -m venv .venv
)
call .venv\Scripts\activate.bat

echo [2/5] Installing Python dependencies...
pip install -r requirements.txt
pip install pyinstaller

echo [3/5] Building Python backend...
pyinstaller --clean --noconfirm noctune-backend.spec
if errorlevel 1 (
    echo ERROR: PyInstaller build failed
    pause
    exit /b 1
)

echo [4/5] Installing Electron dependencies...
cd electron
call npm install

echo [5/5] Building Electron app...
call npm run build -- --win
if errorlevel 1 (
    echo ERROR: Electron build failed
    pause
    exit /b 1
)

echo.
echo === Build Complete! ===
echo Windows installer: electron\dist\NOC Tune Setup 1.0.0.exe
echo.
pause
