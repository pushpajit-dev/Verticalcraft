@echo off
title VerticalCraft AI Backend
echo ===================================================
echo       VerticalCraft AI Backend (Port 8765)
echo ===================================================
cd /d "%~dp0"

:: Free port 8765 if an old process is still holding it
for /f "tokens=5" %%a in ('netstat -aon ^| findstr ":8765" ^| findstr "LISTENING"') do (
    echo Freeing port 8765 (Closing PID %%a)...
    taskkill /F /PID %%a >nul 2>&1
)

call .venv\Scripts\activate.bat
echo Starting FastAPI Backend...
python -m uvicorn backend.main:app --host 127.0.0.1 --port 8765 --reload --reload-dir backend
pause
