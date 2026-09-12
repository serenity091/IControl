@echo off
setlocal
cd /d "%~dp0"
if exist "dist\IControl.exe" (
    start "" "%~dp0dist\IControl.exe"
    exit /b 0
)
if not exist ".venv\Scripts\python.exe" (
    echo First run: double-click Setup IControl.cmd, then launch again.
    pause
    exit /b 1
)
".venv\Scripts\python.exe" desktop.py
if errorlevel 1 pause
