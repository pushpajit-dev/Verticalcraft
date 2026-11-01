@echo off
title VerticalCraft Studio
echo ===================================================
echo             VerticalCraft Studio
echo ===================================================
echo Launching VerticalCraft AI Video Engine...
echo ===================================================

cd /d "%~dp0"
set "PATH=C:\Users\pushp\flutter\bin;%PATH%"

:: Check if backend server is already running on port 8765
netstat -ano | findstr ":8765" | findstr "LISTENING" >nul
if %errorlevel% neq 0 (
    echo Starting FastAPI AI Backend on port 8765...
    start "VerticalCraft Backend" /min "%~dp0.venv\Scripts\python.exe" -m uvicorn backend.main:app --host 127.0.0.1 --port 8765
    timeout /t 2 /nobreak >nul
) else (
    echo Backend is already active on port 8765.
)

echo.
echo [1] Run in Dedicated Chrome Window (Instant CanvasKit UI)
echo [2] Run as Native Windows C++ App
echo [3] Build Web Release Assets
echo.
set /p choice="Select option [1-3] (Default: 1): "
if "%choice%"=="" set choice=1

if "%choice%"=="1" (
    echo Launching VerticalCraft in Dedicated Chrome Window...
    call flutter run -d chrome
) else if "%choice%"=="2" (
    echo Checking Visual Studio C++ Toolchain...
    call flutter run -d windows
) else if "%choice%"=="3" (
    echo Building Flutter Web...
    call flutter build web
    echo Built successfully in build\web.
) else (
    call flutter run -d chrome
)

pause
