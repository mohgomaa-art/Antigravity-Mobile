@echo off
title [Antigravity Mobile Command - Phone Launcher]
color 0A
cd /d "%~dp0\flutter_app"

echo ====================================================================
echo             ANTIGRAVITY MOBILE - PHONE DEPLOYMENT
echo ====================================================================

echo [*] Ensuring ADB Port Forwarding...
adb reverse tcp:8765 tcp:8765 >nul 2>&1

echo [*] Checking connected devices...
flutter devices

echo.
echo [*] Launching Antigravity Mobile App on connected device...
flutter run -d android
pause
