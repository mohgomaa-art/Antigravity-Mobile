# -*- mode: python ; coding: utf-8 -*-


import os

windir = os.environ.get("WINDIR", r"C:\Windows")
sys32 = os.path.join(windir, "System32")
adb_dir = os.path.join(SPECPATH, "tools", "adb")
cf_exe = os.path.join(SPECPATH, "tools", "cloudflared.exe")

vc_dlls = [
    (os.path.join(sys32, "msvcp140.dll"), "."),
    (os.path.join(sys32, "msvcp140_1.dll"), "."),
    (os.path.join(sys32, "msvcp140_2.dll"), "."),
    (os.path.join(sys32, "msvcp140_atomic_wait.dll"), "."),
    (os.path.join(sys32, "msvcp140_codecvt_ids.dll"), "."),
    (os.path.join(sys32, "vcruntime140.dll"), "."),
    (os.path.join(sys32, "vcruntime140_1.dll"), "."),
    (os.path.join(sys32, "vcruntime140_threads.dll"), "."),
    (os.path.join(adb_dir, "adb.exe"), "."),
    (os.path.join(adb_dir, "AdbWinApi.dll"), "."),
    (os.path.join(adb_dir, "AdbWinUsbApi.dll"), "."),
    (cf_exe, "."),
]

a = Analysis(
    ['bridge_entrypoint.py'],
    pathex=[],
    binaries=vc_dlls,
    datas=[('bridge/config', 'bridge/config')],
    hiddenimports=['uvicorn.logging', 'uvicorn.loops', 'uvicorn.loops.auto', 'uvicorn.protocols', 'uvicorn.protocols.http', 'uvicorn.protocols.http.auto', 'uvicorn.protocols.websockets', 'uvicorn.protocols.websockets.auto', 'uvicorn.lifespan', 'uvicorn.lifespan.on', 'websockets', 'websockets.legacy', 'websockets.legacy.client', 'bridge.core.cdp_client', 'psutil', 'multipart'],
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[],
    noarchive=False,
    optimize=0,
)
pyz = PYZ(a.pure)

exe = EXE(
    pyz,
    a.scripts,
    [],
    exclude_binaries=True,
    name='antigravity_bridge',
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    console=True,
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
    icon=['flutter_app/windows/runner/resources/app_icon.ico'],
)
coll = COLLECT(
    exe,
    a.binaries,
    a.datas,
    strip=False,
    upx=True,
    upx_exclude=[],
    name='antigravity_bridge',
)
