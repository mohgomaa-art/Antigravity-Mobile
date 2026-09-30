@echo off
setlocal
cd /d "%~dp0"

:: Check for administrative rights
net session >nul 2>&1
if %errorLevel% == 0 (
    echo [OK] Running with Administrative privileges.
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0silent_firewall_setup.ps1"
    pause
) else (
    echo Requesting Administrator elevation...
    powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process cmd.exe -ArgumentList '/c \"\"%~f0\"\"' -Verb RunAs"
)

