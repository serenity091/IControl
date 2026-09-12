@echo off
powershell.exe -NoProfile -Command "$ErrorActionPreference='Stop'; try { $config=Invoke-RestMethod 'http://localhost:8080/api/bootstrap'; Invoke-RestMethod -Method Post -Uri 'http://localhost:8080/api/stop' -Headers @{'X-Admin-Token'=$config.adminToken}; Write-Host 'IControl stopped.' } catch { Write-Host 'IControl is not running, or could not be stopped.'; exit 1 }"
if errorlevel 1 pause
