@echo off
setlocal enabledelayedexpansion
cd /d "%~dp0"

echo.
echo ========================================
echo    Alfie D&D Campaign - Main Project
echo ========================================
echo.

echo [*] Starting local server...
start "" python serve_locally.py "." 5000

timeout /t 2 /nobreak > nul

set "CHROME_EXE="
if exist "C:\Program Files\Google\Chrome\Application\chrome.exe" (
    set "CHROME_EXE=C:\Program Files\Google\Chrome\Application\chrome.exe"
) else if exist "C:\Program Files (x86)\Google\Chrome\Application\chrome.exe" (
    set "CHROME_EXE=C:\Program Files (x86)\Google\Chrome\Application\chrome.exe"
) else if exist "%LOCALAPPDATA%\Google\Chrome\Application\chrome.exe" (
    set "CHROME_EXE=%LOCALAPPDATA%\Google\Chrome\Application\chrome.exe"
)

if defined CHROME_EXE (
    echo [*] Opening in Chrome...
    start "" "!CHROME_EXE!" --new-window http://127.0.0.1:5000/
) else (
    echo [!] Chrome not found. Opening in default browser...
    start "" http://127.0.0.1:5000/
)

echo.
echo [✓] Server running at: http://127.0.0.1:5000/
echo [*] You can close this window - the server will keep running
echo [*] To stop the server, use Task Manager to end python.exe
echo.
pause
