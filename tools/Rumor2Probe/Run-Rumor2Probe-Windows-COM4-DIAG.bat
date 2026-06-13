@echo off
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0rumor2probe_windows.ps1" -Port COM4 -BrewOnly -ReadVersion
echo.
pause
