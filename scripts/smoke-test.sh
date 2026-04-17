#!/usr/bin/env bash
set -euo pipefail

WHISPERBOX_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PYTHON="$WHISPERBOX_DIR/.venv/bin/python"

echo "=== WhisperBox Smoke Test ==="

# 1. Check Python venv exists
echo -n "Python venv... "
if [ -x "$PYTHON" ]; then echo "OK"; else echo "FAIL: run scripts/install.sh"; exit 1; fi

# 2. Check imports
echo -n "Python imports... "
cd "$WHISPERBOX_DIR/service"
$PYTHON -c "
from config import load_config
from socket_server import SocketServer
from audio import AudioRecorder
from transcriber import Transcriber
from postprocess import postprocess
from injector import TextInjector
from service import WhisperBoxService
print('OK')
"

# 3. Run unit tests
echo "Running unit tests..."
cd "$WHISPERBOX_DIR/service"
$PYTHON -m pytest tests/ -v --tb=short

# 4. Check Swift build
echo -n "Swift build... "
cd "$WHISPERBOX_DIR/app"
if swift build 2>/dev/null; then echo "OK"; else echo "FAIL"; exit 1; fi

# 5. Check config
echo -n "Config file... "
CONFIG="$HOME/.config/whisperbox/config.toml"
if [ -f "$CONFIG" ]; then echo "OK ($CONFIG)"; else echo "MISSING (run install.sh)"; fi

# 6. Check cliclick
echo -n "cliclick... "
if command -v cliclick &>/dev/null; then echo "OK"; else echo "MISSING (brew install cliclick)"; fi

echo ""
echo "=== Smoke test complete ==="
