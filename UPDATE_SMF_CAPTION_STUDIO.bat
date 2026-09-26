@echo off
setlocal EnableExtensions
title SMF Caption Studio - Update

cd /d "%~dp0"

echo.
echo ============================================================
echo        SMF STUDIO - CAPTION STUDIO UPDATE
echo ============================================================
echo.

where git >nul 2>&1
if errorlevel 1 (
  echo [ERROR] Git is not installed or not available in PATH.
  echo Install Git, then run this updater again.
  pause
  exit /b 1
)

echo [1/3] Pulling latest code from GitHub...
git pull --ff-only origin main
if errorlevel 1 (
  echo.
  echo [ERROR] Git pull failed.
  echo Check the message above.
  pause
  exit /b 1
)

echo.
echo [2/3] Updating installed application files...
set "INSTALL=%LOCALAPPDATA%\SMF Caption Studio"
if not exist "%INSTALL%" (
  echo Installed app not found.
  echo Run SETUP_SMF_CAPTION_STUDIO.bat once for first installation.
  pause
  exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$src=Join-Path '%~dp0' 'SMF Caption Studio'; $dst='%INSTALL%'; if(Test-Path $src){Copy-Item -LiteralPath $src -Destination $dst -Recurse -Force}; Write-Host 'Application files updated.'"

if errorlevel 1 (
  echo [ERROR] Application file update failed.
  pause
  exit /b 1
)

echo.
echo [3/3] Update complete.
echo Your local Git folder and installed SMF Caption Studio are updated.
echo.
echo Launch the app normally from the Desktop shortcut.
echo.
pause
endlocal
