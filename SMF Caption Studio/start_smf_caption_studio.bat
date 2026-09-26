@echo off
setlocal
cd /d "%~dp0"

if not exist "%~dp0runtime\node\node.exe" (
  echo [ERROR] Portable Node.js is missing.
  pause
  exit /b 1
)
if not exist "%~dp0server.mjs" (
  echo [ERROR] server.mjs is missing.
  pause
  exit /b 1
)
if not exist "%~dp0.venv\Scripts\python.exe" (
  echo [ERROR] Python environment is missing.
  pause
  exit /b 1
)

echo Starting SMF Caption Studio...
start "" /min "%~dp0runtime\node\node.exe" "%~dp0server.mjs"

for /l %%i in (1,1,30) do (
  powershell -NoProfile -Command "try{$r=Invoke-WebRequest -UseBasicParsing http://127.0.0.1:8787/api/health -TimeoutSec 1;if($r.StatusCode -eq 200){exit 0}else{exit 1}}catch{exit 1}" >nul 2>&1
  if not errorlevel 1 goto ready
  timeout /t 1 /nobreak >nul
)

echo.
echo [ERROR] Server did not start.
echo Run:
echo   "%~dp0runtime\node\node.exe" "%~dp0server.mjs"
echo.
pause
exit /b 1

:ready
echo SMF Caption Studio is ready.
start "" "http://127.0.0.1:8787/"
endlocal
