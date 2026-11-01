@echo off
setlocal
title VerticalCraft - Compile Launchers

cd /d "%~dp0"
echo ========================================================
echo   Compiling VerticalCraft Standalone Launchers
echo ========================================================

echo [*] Compiling 64-bit Windows Executable (VerticalCraft.exe)...
"%SystemRoot%\Microsoft.NET\Framework64\v4.0.30319\csc.exe" /nologo /target:winexe /platform:x64 /win32icon:"windows\runner\resources\app_icon.ico" /reference:System.dll,System.Windows.Forms.dll /out:"VerticalCraft.exe" "launcher.cs"

if %errorlevel% equ 0 (
    echo [OK] VerticalCraft.exe compiled successfully!
) else (
    echo [FAIL] 64-bit compilation failed.
)

echo.
echo [*] Compiling 32-bit Windows Executable (VerticalCraft_32bit.exe)...
"%SystemRoot%\Microsoft.NET\Framework\v4.0.30319\csc.exe" /nologo /target:winexe /platform:x86 /win32icon:"windows\runner\resources\app_icon.ico" /reference:System.dll,System.Windows.Forms.dll /out:"VerticalCraft_32bit.exe" "launcher.cs"

if %errorlevel% equ 0 (
    echo [OK] VerticalCraft_32bit.exe compiled successfully!
) else (
    echo [FAIL] 32-bit compilation failed.
)

echo.
echo Done.
pause
