@echo off
setlocal
cd /d "%~dp0"
".venv\Scripts\python.exe" scripts\install_windows_dependencies.py --build
if errorlevel 1 exit /b 1
".venv\Scripts\python.exe" build_exe.py
if errorlevel 1 pause
