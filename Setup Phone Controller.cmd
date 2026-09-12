@echo off
setlocal
cd /d "%~dp0"
echo Setting up Phone Controller in this folder...
py -3.12 -m venv .venv
if errorlevel 1 (
    echo Install Python 3.12 from python.org, then run setup again.
    pause
    exit /b 1
)
set VGAMEPAD_SKIP_VIGEMBUS_INSTALL=true
".venv\Scripts\python.exe" -m pip install -r requirements.txt
if errorlevel 1 (
    pause
    exit /b 1
)
echo.
echo Setup complete. Double-click Start Phone Controller.cmd.
echo If the dashboard reports a missing driver, install ViGEmBus from:
echo https://github.com/nefarius/ViGEmBus/releases
pause
