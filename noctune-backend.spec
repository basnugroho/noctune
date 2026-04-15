# -*- mode: python ; coding: utf-8 -*-
# PyInstaller spec file for NOC Tune backend

import sys
import os
from PyInstaller.utils.hooks import collect_data_files, collect_submodules

block_cipher = None

# Project root
project_root = os.path.dirname(os.path.abspath(SPEC))

# Collect dnspython data
datas = collect_data_files('dns')

# Add UI files
datas += [
    (os.path.join(project_root, 'ui', 'templates'), 'ui/templates'),
    (os.path.join(project_root, 'ui', 'static'), 'ui/static'),
]

# Collect all submodules for dns
hiddenimports = collect_submodules('dns')
hiddenimports += [
    'dns.resolver',
    'dns.rdatatype',
    'dns.name',
    'dns.exception',
]

a = Analysis(
    ['main.py'],
    pathex=[project_root],
    binaries=[],
    datas=datas,
    hiddenimports=hiddenimports,
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[
        'tkinter',
        'matplotlib',
        'pandas',
        'numpy',
        'PIL',
        'cv2',
        'scipy',
    ],
    win_no_prefer_redirects=False,
    win_private_assemblies=False,
    cipher=block_cipher,
    noarchive=False,
)

pyz = PYZ(a.pure, a.zipped_data, cipher=block_cipher)

exe = EXE(
    pyz,
    a.scripts,
    a.binaries,
    a.zipfiles,
    a.datas,
    [],
    name='noctune-backend',
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    upx_exclude=[],
    runtime_tmpdir=None,
    console=True,  # Keep console for debugging; set False for release
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
    icon=os.path.join(project_root, 'electron', 'resources', 'icon.icns') if sys.platform == 'darwin' else None,
)

# For macOS app bundle (optional)
if sys.platform == 'darwin':
    app = BUNDLE(
        exe,
        name='NOC Tune Backend.app',
        icon=os.path.join(project_root, 'electron', 'resources', 'icon.icns'),
        bundle_identifier='id.solusee.noctune.backend',
        info_plist={
            'NSHighResolutionCapable': True,
            'LSBackgroundOnly': True,
        },
    )
