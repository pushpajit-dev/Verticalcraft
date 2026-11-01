@echo off
setlocal enabledelayedexpansion
title VerticalCraft AI Studio - Automated Setup

echo =======================================================
echo     VerticalCraft AI Studio - GitHub Environment Setup
echo =======================================================
echo.

cd /d "%~dp0"

:: 1. Check Python
python --version >nul 2>&1
if %errorlevel% neq 0 (
    echo [ERROR] Python is not installed or not in PATH.
    echo Please install Python 3.11+ from https://www.python.org/
    pause
    exit /b 1
)

:: 2. Create Python Virtual Environment
if not exist ".venv" (
    echo [*] Creating Python virtual environment in .venv ...
    python -m venv .venv
) else (
    echo [*] Virtual environment .venv already exists.
)

:: 3. Install Python Dependencies
echo [*] Installing backend dependencies from requirements.txt ...
call .venv\Scripts\activate.bat
python -m pip install --upgrade pip
pip install -r requirements.txt

:: 4. Check Flutter & Build Web UI
where flutter >nul 2>&1
if %errorlevel% equ 0 (
    echo [*] Flutter detected. Fetching packages and building CanvasKit web client ...
    call flutter pub get
    call flutter config --enable-windows-desktop >nul 2>&1
    call flutter config --enable-web >nul 2>&1
    call flutter build web
) else (
    echo [!] Flutter CLI not found in PATH. Skipping Flutter build.
    echo [!] If build\web is not present, please install Flutter SDK.
)

:: 5. Compile Windows Executables if needed
if not exist "VerticalCraft.exe" (
    echo [*] Compiling 64-bit VerticalCraft.exe launcher ...
    if exist "%SystemRoot%\Microsoft.NET\Framework64\v4.0.30319\csc.exe" (
        "%SystemRoot%\Microsoft.NET\Framework64\v4.0.30319\csc.exe" /nologo /target:winexe /platform:x64 /win32icon:"windows\runner\resources\app_icon.ico" /reference:System.dll,System.Windows.Forms.dll /out:"VerticalCraft.exe" "launcher.cs"
    )
)

if not exist "VerticalCraft_32bit.exe" (
    echo [*] Compiling 32-bit VerticalCraft_32bit.exe launcher ...
    if exist "%SystemRoot%\Microsoft.NET\Framework\v4.0.30319\csc.exe" (
        "%SystemRoot%\Microsoft.NET\Framework\v4.0.30319\csc.exe" /nologo /target:winexe /platform:x86 /win32icon:"windows\runner\resources\app_icon.ico" /reference:System.dll,System.Windows.Forms.dll /out:"VerticalCraft_32bit.exe" "launcher.cs"
    )
)

echo.
echo =======================================================
echo  Setup Completed Successfully!
echo  Run VerticalCraft.exe to launch the application.
echo =======================================================
echo.
pause
