# SMF Caption Studio v1.5 - deterministic Windows setup
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$AppName = 'SMF Caption Studio'
$Root = Join-Path $env:LOCALAPPDATA $AppName
$Src = Join-Path $PSScriptRoot 'SMF Caption Studio'
$Runtime = Join-Path $Root 'runtime'
$PyRoot = Join-Path $Runtime 'python312'
$PyExe = Join-Path $PyRoot 'python.exe'
$Venv = Join-Path $Root '.venv'
$VenvPy = Join-Path $Venv 'Scripts\python.exe'
$NodeRoot = Join-Path $Runtime 'node'
$NodeExe = Join-Path $NodeRoot 'node.exe'
$FFRoot = Join-Path $Runtime 'ffmpeg'
$FFmpegExe = Join-Path $FFRoot 'bin\ffmpeg.exe'
$FFprobeExe = Join-Path $FFRoot 'bin\ffprobe.exe'
$Log = Join-Path $Root 'setup.log'
$PipLog = Join-Path $Root 'pip-install.log'

function Ensure-Dir([string]$p) {
  if (-not (Test-Path -LiteralPath $p)) { New-Item -ItemType Directory -Path $p -Force | Out-Null }
}
function Download-File([string]$url,[string]$out,[string]$sha256='') {
  Write-Host "Downloading $url"
  Invoke-WebRequest -Uri $url -OutFile $out -UseBasicParsing
  if ($sha256) {
    $actual = (Get-FileHash -LiteralPath $out -Algorithm SHA256).Hash.ToLower()
    if ($actual -ne $sha256.ToLower()) { throw "SHA-256 mismatch for $out" }
  }
}
function Find-Python312 {
  $c = @(
    (Join-Path $env:LOCALAPPDATA 'Programs\Python\Python312\python.exe'),
    (Join-Path $env:ProgramFiles 'Python312\python.exe')
  )
  foreach ($p in $c) {
    if (Test-Path -LiteralPath $p) {
      try {
        $v = & $p -c "import sys; print(sys.version_info[:2])" 2>$null
        if ($LASTEXITCODE -eq 0 -and $v -match '3, 12') { return $p }
      } catch {}
    }
  }
  try {
    $p = & py -3.12 -c "import sys; print(sys.executable)" 2>$null
    if ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $p.Trim())) { return $p.Trim() }
  } catch {}
  return $null
}

Ensure-Dir $Root
Start-Transcript -Path $Log -Append | Out-Null

try {
  Write-Host '============================================================'
  Write-Host '          SMF STUDIO - CAPTION STUDIO v1.7'
  Write-Host '============================================================'
  Write-Host '[1/6] Copying application files...'
  Copy-Item -Path (Join-Path $Src '*') -Destination $Root -Recurse -Force
  Ensure-Dir $Runtime

  Write-Host '[2/6] Preparing exact Python 3.12.10 x64...'
  $py = Find-Python312
  if (-not $py) {
    $pyInstaller = Join-Path $env:TEMP 'smf-python-3.12.10-amd64.exe'
    Download-File 'https://www.python.org/ftp/python/3.12.10/python-3.12.10-amd64.exe' $pyInstaller '67b5635e80ea51072b87941312d00ec8927c4db9ba18938f7ad2d27b328b95fb'
    $args = '/quiet InstallAllUsers=0 PrependPath=0 Include_launcher=1 Include_pip=1 Include_test=0 Shortcuts=0 TargetDir="' + $PyRoot + '"'
    $p = Start-Process -FilePath $pyInstaller -ArgumentList $args -Wait -PassThru
    if ($p.ExitCode -ne 0) { throw "Python installer failed with exit code $($p.ExitCode)" }
    $py = $PyExe
  }
  if (-not (Test-Path -LiteralPath $py)) { throw 'Python 3.12.10 was not found.' }
  Write-Host ("Using: " + $py)
  & $py --version

  Write-Host '[3/6] Creating private Python environment...'
  if (Test-Path -LiteralPath $Venv) { Remove-Item -LiteralPath $Venv -Recurse -Force }
  & $py -m venv $Venv
  if ($LASTEXITCODE -ne 0) { throw 'venv creation failed.' }

  Write-Host '[4/6] Installing faster-whisper...'
  Write-Host ("  Pip log: " + $PipLog)
  Add-Content -LiteralPath $PipLog -Value ("=== pip bootstrap " + (Get-Date -Format s) + " ===")
  & $VenvPy -m pip install --upgrade pip setuptools wheel *>> $PipLog
  if ($LASTEXITCODE -ne 0) { throw ("pip bootstrap failed. Check " + $PipLog) }
  Add-Content -LiteralPath $PipLog -Value ("=== faster-whisper install " + (Get-Date -Format s) + " ===")
  & $VenvPy -m pip install --only-binary=:all: 'faster-whisper>=1.2.0' *>> $PipLog
  if ($LASTEXITCODE -ne 0) { throw ("faster-whisper installation failed. Check " + $PipLog) }
  Add-Content -LiteralPath $PipLog -Value ("=== import test " + (Get-Date -Format s) + " ===")
  & $VenvPy -c "import faster_whisper,sys; print('AI OK'); print(sys.executable)" *>> $PipLog
  if ($LASTEXITCODE -ne 0) { throw ("faster-whisper import test failed. Check " + $PipLog) }

  Write-Host '[5/6] Preparing portable Node.js + FFmpeg...'
  if (-not (Test-Path -LiteralPath $NodeExe)) {
    $nodeZip = Join-Path $env:TEMP 'smf-node-v24.21.0-win-x64.zip'
    Download-File 'https://nodejs.org/download/release/v24.21.0/node-v24.21.0-win-x64.zip' $nodeZip
    $tmp = Join-Path $env:TEMP ('smf-node-' + [guid]::NewGuid())
    Expand-Archive $nodeZip -DestinationPath $tmp -Force
    $folder = Get-ChildItem $tmp -Directory | Select-Object -First 1
    Ensure-Dir $NodeRoot
    Copy-Item -Path (Join-Path $folder.FullName '*') -Destination $NodeRoot -Recurse -Force
    Remove-Item $tmp -Recurse -Force
  }
  if (-not (Test-Path -LiteralPath $NodeExe)) { throw 'Node.js runtime missing.' }

  if (-not (Test-Path -LiteralPath $FFmpegExe)) {
    $ffZip = Join-Path $env:TEMP 'smf-ffmpeg-win64-gpl.zip'
    $downloaded = $false
    $mirrors = @(
      'https://github.com/BtbN/FFmpeg-Builds/releases/latest/download/ffmpeg-n9.0-latest-win64-gpl-9.0.zip',
      'https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip'
    )
    foreach ($u in $mirrors) {
      try {
        Write-Host "  Trying FFmpeg mirror: $u"
        & curl.exe -L --fail --retry 3 --retry-delay 2 --connect-timeout 15 --max-time 900 -o $ffZip $u
        if ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $ffZip) -and (Get-Item -LiteralPath $ffZip).Length -gt 50000000) {
          $downloaded = $true
          break
        }
      } catch {}
    }
    if ($downloaded) {
      $tmp = Join-Path $env:TEMP ('smf-ffmpeg-' + [guid]::NewGuid())
      Expand-Archive $ffZip -DestinationPath $tmp -Force
      $folder = Get-ChildItem $tmp -Directory | Select-Object -First 1
      Ensure-Dir $FFRoot
      Copy-Item -Path (Join-Path $folder.FullName '*') -Destination $FFRoot -Recurse -Force
      Remove-Item $tmp -Recurse -Force
    } else {
      Write-Host '  Direct mirrors failed. Trying WinGet FFmpeg...'
      try {
        winget install --id Gyan.FFmpeg.Shared -e --accept-source-agreements --accept-package-agreements --silent
      } catch {}
      $cmd = Get-Command ffmpeg.exe -ErrorAction SilentlyContinue
      if ($cmd -and (Test-Path -LiteralPath $cmd.Source)) {
        Ensure-Dir $FFRoot
        Ensure-Dir (Join-Path $FFRoot 'bin')
        Copy-Item -LiteralPath $cmd.Source -Destination $FFmpegExe -Force
        $probe = Get-Command ffprobe.exe -ErrorAction SilentlyContinue
        if ($probe) { Copy-Item -LiteralPath $probe.Source -Destination $FFprobeExe -Force }
      }
    }
  }
  if (-not (Test-Path -LiteralPath $FFmpegExe)) { throw 'FFmpeg runtime missing. Check network access and run setup again.' }

  Write-Host '[6/6] Creating launchers...'
  @'
@echo off
setlocal
cd /d "%~dp0"
set "SMF_PYTHON=%CD%\.venv\Scripts\python.exe"
set "SMF_NODE=%CD%\runtime\node\node.exe"
set "SMF_FFMPEG=%CD%\runtime\ffmpeg\bin\ffmpeg.exe"
set "SMF_FFPROBE=%CD%\runtime\ffmpeg\bin\ffprobe.exe"
if not exist "%SMF_PYTHON%" (
  echo Python missing. Run setup again.
  pause
  exit /b 1
)
if not exist "%SMF_NODE%" (
  echo Node missing. Run setup again.
  pause
  exit /b 1
)
if not exist "%SMF_FFMPEG%" (
  echo FFmpeg missing. Run setup again.
  pause
  exit /b 1
)
if not exist "%SMF_FFPROBE%" (
  echo FFprobe missing. Run setup again.
  pause
  exit /b 1
)
set "FFMPEG=%SMF_FFMPEG%"
set "FFPROBE=%SMF_FFPROBE%"
start "SMF Caption Studio Server" /min "%SMF_NODE%" "%CD%\server.mjs"
for /l %%i in (1,1,30) do (
  powershell -NoProfile -Command "try { $r=Invoke-WebRequest -UseBasicParsing http://127.0.0.1:8787/api/health -TimeoutSec 1; if($r.StatusCode -eq 200){exit 0}else{exit 1} } catch { exit 1 }" >nul 2>&1
  if not errorlevel 1 goto ready
  powershell -NoProfile -Command "Start-Sleep -Seconds 1" >nul 2>&1
)
echo Server failed. Run DIAGNOSTICS.bat.
pause
exit /b 1
:ready
start "" "http://127.0.0.1:8787/"
endlocal
'@ | Set-Content -Encoding ASCII (Join-Path $Root 'START_APP.bat')

  @'
@echo off
setlocal
cd /d "%~dp0"
set "PY=%CD%\.venv\Scripts\python.exe"
"%PY%" -c "import faster_whisper,sys; print('faster-whisper:',getattr(faster_whisper,'__version__','installed')); print('Python:',sys.version); print('EXE:',sys.executable); print('Module:',faster_whisper.__file__)"
pause
endlocal
'@ | Set-Content -Encoding ASCII (Join-Path $Root 'DIAGNOSTICS.bat')

  $desktop = Join-Path ([Environment]::GetFolderPath('Desktop')) 'SMF Caption Studio.lnk'
  $shell = New-Object -ComObject WScript.Shell
  $shortcut = $shell.CreateShortcut($desktop)
  $shortcut.TargetPath = Join-Path $Root 'START_APP.bat'
  $shortcut.WorkingDirectory = $Root
  $shortcut.Description = 'SMF Studio Caption Studio'
  $shortcut.Save()

  Write-Host ''
  Write-Host 'SETUP COMPLETE'
  Write-Host ("App: " + $Root)
  Write-Host 'AI: faster-whisper OK'
  Write-Host 'Node: portable OK'
  Write-Host 'FFmpeg: portable OK'
  Start-Process -FilePath (Join-Path $Root 'START_APP.bat') -WorkingDirectory $Root
}
catch {
  Write-Host ("SETUP FAILED: " + $_.Exception.Message) -ForegroundColor Red
  throw
}
finally {
  Stop-Transcript | Out-Null
}

