@echo off
setlocal EnableExtensions
cd /d "%~dp0"
set "SMF_PYTHON=%CD%\.venv\Scripts\python.exe"
set "SMF_FFMPEG=%CD%\runtime\ffmpeg\bin\ffmpeg.exe"
set "SMF_NODE=%CD%\runtime\node\node.exe"
if not exist "%SMF_PYTHON%" echo Python environment missing.&pause&exit /b 1
if not exist "%SMF_NODE%" echo Node runtime missing.&pause&exit /b 1
start "SMF Caption Studio Server" /min cmd /c "cd /d ""%CD%"" && set ""SMF_PYTHON=%SMF_PYTHON%"" && set ""FFMPEG=%SMF_FFMPEG%"" && ""%SMF_NODE%"" server.mjs"
for /l %%i in (1,1,30) do (
  powershell -NoProfile -Command "try{$r=Invoke-WebRequest -UseBasicParsing http://127.0.0.1:8787/api/health -TimeoutSec 1;if($r.StatusCode -eq 200){exit 0}else{exit 1}}catch{exit 1}" >nul 2>&1
  if not errorlevel 1 goto ready
  timeout /t 1 /nobreak >nul
)
echo Server failed to start.
pause
exit /b 1
:ready
start "" "http://127.0.0.1:8787/"
endlocal
