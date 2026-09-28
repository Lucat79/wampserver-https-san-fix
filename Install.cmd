@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install-WampHttps.ps1" %*
if errorlevel 1 (
    echo Installation failed. Read the error above.
    pause
    exit /b 1
)
pause
