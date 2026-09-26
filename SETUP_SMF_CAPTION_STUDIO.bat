@echo off
setlocal
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup.ps1"
set "RC=%ERRORLEVEL%"
echo.
if not "%RC%"=="0" echo SETUP FAILED. See the log shown above.
pause
exit /b %RC%
