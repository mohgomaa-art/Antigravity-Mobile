@echo off
title [Antigravity Master Control]
color 0F
cd /d "%~dp0"

echo ====================================================================
echo        ANTIGRAVITY MASTER CONTROL (15-ACCOUNT FLEET + MOBILE)
echo ====================================================================
echo.

echo [1/3] Setting up USB Port Tunneling for Phone...
adb reverse tcp:8765 tcp:8765 >nul 2>&1
if %errorlevel% equ 0 (
    echo [+] USB Tunnel established (Phone port 8765 -^> Windows port 8765)
) else (
    echo [i] No phone over USB detected. LAN IP mode active.
)

echo.
echo [2/3] Starting Windows Fleet Gateway in background...
start "Antigravity Gateway" cmd /c "%~dp0run_gateway.bat"

echo [*] Waiting 3 seconds for gateway initialization...
timeout /t 3 /nobreak >nul

echo.
echo [3/3] Launching Antigravity Companion...
cd /d "%~dp0flutter_app"

adb devices | findstr /r /c:"device$" >nul 2>&1
if %errorlevel% equ 0 (
    echo [+] Connected phone found. Deploying app...
    flutter run -d android
) else (
    echo [i] Phone not detected over ADB. Launching on Windows Desktop...
    flutter run -d windows
)

pause
