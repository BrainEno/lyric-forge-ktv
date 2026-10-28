@echo off
setlocal
cd /d "%~dp0.."
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0flutter_test_failed_only.ps1" %*
exit /b %ERRORLEVEL%
