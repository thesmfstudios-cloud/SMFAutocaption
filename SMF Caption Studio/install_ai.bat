@echo off
setlocal
cd /d "%~dp0"
if not exist "%CD%\.venv\Scripts\python.exe" (
  echo Python environment not found. Run SETUP_SMF_CAPTION_STUDIO.bat first.
  pause
  exit /b 1
)
"%CD%\.venv\Scripts\python.exe" -m pip install --upgrade pip setuptools wheel
"%CD%\.venv\Scripts\python.exe" -m pip install --only-binary=:all: -r requirements.txt
"%CD%\.venv\Scripts\python.exe" -c "import faster_whisper; print('faster-whisper READY')"
pause
endlocal
