# SMF Caption Studio v1.5

## Windows install
1. Clone or download this repository.
2. Run `SETUP_SMF_CAPTION_STUDIO.bat` from the repository root.
3. The setup creates a private installation under `%LOCALAPPDATA%\\SMF Caption Studio`.
4. After setup, use the desktop shortcut **SMF Caption Studio**.

## What setup installs
- Python 3.12.10 x64, selected explicitly
- Private Python virtual environment
- faster-whisper
- Portable Node.js
- Portable FFmpeg

The setup does not use whichever Python happens to be first on Windows PATH.

## Development layout
- `SMF Caption Studio/SMF_Caption_Studio.html` - main UI
- `SMF Caption Studio/server.mjs` - local API/render server
- `SMF Caption Studio/tools/transcribe.py` - Whisper worker
- `SMF Caption Studio/requirements.txt` - AI dependency
