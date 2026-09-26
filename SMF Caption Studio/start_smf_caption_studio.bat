@echo off
setlocal EnableExtensions
cd /d "%~dp0"
set "SMF_PYTHON=%CD%\.venv\Scripts\python.exe"
set "SMF_FFMPEG=%CD%\runtime\ffmpeg\bin\ffmpeg.exe"
set "SMF_FFPROBE=%CD%\runtime\ffmpeg\bin\ffprobe.exe"
set "SMF_NODE=%CD%\runtime\node\node.exe"
set "SMF_SERVER=%CD%\server.mjs"

if not exist "%SMF_PYTHON%" (
  echo [ERROR] Python environment missing.
  pause
  exit /b 1
)
if not exist "%SMF_NODE%" (
  echo [ERROR] Node runtime missing.
  pause
  exit /b 1
)
if not exist "%SMF_FFMPEG%" (
  echo [ERROR] FFmpeg runtime missing.
  pause
  exit /b 1
)
if not exist "%SMF_FFPROBE%" (
  echo [ERROR] FFprobe runtime missing.
  pause
  exit /b 1
)
if not exist "%SMF_SERVER%" (
  echo [ERROR] server.mjs missing.
  pause
  exit /b 1
)

echo Starting SMF Caption Studio server...
set "FFMPEG=%SMF_FFMPEG%"
set "FFPROBE=%SMF_FFPROBE%"
start "SMF Caption Studio Server" /min "%SMF_NODE%" "%SMF_SERVER%"

for /l %%i in (1,1,40) do (
  powershell -NoProfile -Command "try{$r=Invoke-WebRequest -UseBasicParsing http://127.0.0.1:8787/api/health -TimeoutSec 1;if($r.StatusCode -eq 200){exit 0}else{exit 1}}catch{exit 1}" >nul 2>&1
  if not errorlevel 1 goto ready
  powershell -NoProfile -Command "Start-Sleep -Seconds 1" >nul 2>&1
)

echo.
echo [ERROR] Server did not start.
echo Run DIAGNOSTICS.bat and try again.
pause
exit /b 1

:ready
echo SMF Caption Studio is ready.
start "" "http://127.0.0.1:8787/"
endlocal

