@echo off
title [Antigravity Fleet Gateway - 15 Accounts]
color 0B
cd /d "%~dp0"

echo ====================================================================
echo             ANTIGRAVITY FLEET GATEWAY (15 ACCOUNTS)
echo ====================================================================
echo [*] Checking Python environment...
python --version >nul 2>&1
if %errorlevel% neq 0 (
    echo [!] Python is not installed or not in PATH!
    pause
    exit /b 1
)

echo [*] Setting up USB Port Forwarding for Connected Phone...
adb reverse tcp:8765 tcp:8765 >nul 2>&1
if %errorlevel% equ 0 (
    echo [+] ADB Port Reverse Forwarding Active: phone:8765 -^> windows:8765
) else (
    echo [i] ADB device not detected or ADB not in PATH. LAN IP mode active.
)

echo [*] Starting Fleet Gateway on http://0.0.0.0:8765 ...
echo [*] WebSocket Stream available on ws://0.0.0.0:8765/ws/stream
echo ====================================================================
python -m uvicorn bridge.server:app --host 0.0.0.0 --port 8765 --reload
pause
