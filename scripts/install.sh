#!/usr/bin/env bash
set -euo pipefail

WHISPERBOX_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DATA_DIR="$HOME/.local/share/whisperbox"
CONFIG_DIR="$HOME/.config/whisperbox"

echo "=== WhisperBox Installer ==="

# Homebrew deps
echo "Installing Homebrew dependencies..."
brew install cliclick python@3.12 2>/dev/null || true

# Python venv
echo "Creating Python virtual environment..."
PYTHON=$(brew --prefix python@3.12)/bin/python3.12
$PYTHON -m venv "$WHISPERBOX_DIR/.venv"
source "$WHISPERBOX_DIR/.venv/bin/activate"
pip install --upgrade pip
pip install -r "$WHISPERBOX_DIR/service/requirements.txt"

# Directories
mkdir -p "$DATA_DIR/models"
mkdir -p "$CONFIG_DIR"

# Default config if not exists
if [ ! -f "$CONFIG_DIR/config.toml" ]; then
    cat > "$CONFIG_DIR/config.toml" << 'TOML'
[hotkey]
combo = "ctrl+shift+space"

[transcription]
model = "small"
language = "en"

[behavior]
mode = "instant"
sound_feedback = true
max_duration = 300
silence_timeout = 10

[postprocessing]
strip_fillers = true
auto_capitalize = true
auto_punctuate = true

[indicator]
enabled = true
position = "top-center"
opacity = 0.85
TOML
    echo "Created default config at $CONFIG_DIR/config.toml"
fi

echo "=== Installation complete ==="
echo "Next: run scripts/build.sh to compile the Swift app"
