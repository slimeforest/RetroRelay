@echo off
cd /d "%~dp0..\..\third_party\bitpim-source\src"
python bp.py -p COM4 -f "LG-LX260 (Rumor)" "ls phone:/"
echo.
pause
