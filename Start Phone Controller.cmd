@echo off
setlocal
cd /d "%~dp0"
if exist "dist\Phone Controller.exe" (
    start "" "%~dp0dist\Phone Controller.exe"
    exit /b 0
)
if not exist ".venv\Scripts\python.exe" (
    echo First run: double-click Setup Phone Controller.cmd, then launch again.
    pause
    exit /b 1
)
".venv\Scripts\python.exe" desktop.py
if errorlevel 1 pause
