@echo off
title Antigravity Fleet Gateway
cd /d "%~dp0\.."
echo ========================================================
echo  Starting Antigravity Fleet Gateway (15-Account Engine)
echo ========================================================
python -m uvicorn bridge.server:app --host 0.0.0.0 --port 8765 --reload
pause
