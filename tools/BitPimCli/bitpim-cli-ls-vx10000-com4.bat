@echo off
cd /d "%~dp0..\..\third_party\bitpim-source\src"
python bp.py -p COM4 -f "LG-VX10000 (Voyager)" "ls phone:/"
echo.
pause
