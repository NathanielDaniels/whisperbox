# WhisperBox Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a local, system-wide voice-to-text tool for macOS that runs Whisper via whisper.cpp with Metal acceleration.

**Architecture:** Two-process design — a Swift menu bar app (UI, hotkey, toast overlay) communicates over a Unix domain socket with a Python transcription service (audio capture, Whisper inference, text injection). The Swift shell is thin; all logic lives in Python.

**Tech Stack:** Swift 5.9+ (menu bar app), Python 3.12 (transcription service), whisper.cpp via pywhispercpp, sounddevice, HotKey Swift package, Unix domain sockets with newline-delimited JSON.

**Spec:** `docs/superpowers/specs/2026-04-16-whisperbox-design.md`

---

## Chunk 1: Project Scaffolding + Python Config

### Task 1: Install Script & Project Skeleton

**Files:**
- Create: `scripts/install.sh`
- Create: `scripts/build.sh` (placeholder)
- Create: `service/requirements.txt`
- Create: `.gitignore`

- [ ] **Step 1: Create .gitignore**

```gitignore
.venv/
build/
__pycache__/
*.pyc
.DS_Store
*.egg-info/
*.gguf
```

- [ ] **Step 2: Create requirements.txt**

```
pywhispercpp>=1.2.0
sounddevice>=0.4.6
numpy>=1.24.0
tomli>=2.0.0;python_version<"3.11"
tomli_w>=1.0.0
pytest>=7.0.0
pytest-asyncio>=0.21.0
```

Note: Python 3.12 has `tomllib` built-in for reading TOML, but we still need `tomli_w` for writing. We'll use `tomllib` for reads.

- [ ] **Step 3: Write install.sh**

```bash
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
```

- [ ] **Step 4: Create placeholder build.sh**

```bash
#!/usr/bin/env bash
set -euo pipefail
echo "Build script - will be implemented in Task 10"
```

- [ ] **Step 5: Make scripts executable and commit**

```bash
chmod +x scripts/install.sh scripts/build.sh
git add .gitignore service/requirements.txt scripts/
git commit -m "feat: add project scaffolding and install script"
```

---

### Task 2: Python Config Module

**Files:**
- Create: `service/config.py`
- Create: `service/tests/__init__.py`
- Create: `service/tests/test_config.py`

- [ ] **Step 1: Create test directory and conftest.py**

```bash
mkdir -p service/tests
touch service/tests/__init__.py
```

Create `service/conftest.py` so pytest can find modules:

```python
# service/conftest.py
import sys
import os
sys.path.insert(0, os.path.dirname(__file__))
```

- [ ] **Step 2: Write failing test for config loading**

```python
# service/tests/test_config.py
import os
import tempfile
import pytest
from config import load_config, DEFAULT_CONFIG


def test_load_default_config_when_file_missing():
    """When no config file exists, return defaults."""
    config = load_config("/nonexistent/path/config.toml")
    assert config["transcription"]["model"] == "small"
    assert config["behavior"]["mode"] == "instant"
    assert config["behavior"]["max_duration"] == 300
    assert config["behavior"]["silence_timeout"] == 10
    assert config["postprocessing"]["strip_fillers"] is True


def test_load_config_from_file():
    """Load and merge config from a TOML file."""
    with tempfile.NamedTemporaryFile(mode="w", suffix=".toml", delete=False) as f:
        f.write('[transcription]\nmodel = "medium"\n')
        f.flush()
        config = load_config(f.name)
    os.unlink(f.name)
    # Overridden value
    assert config["transcription"]["model"] == "medium"
    # Default preserved
    assert config["behavior"]["mode"] == "instant"


def test_load_config_invalid_toml_returns_defaults():
    """Malformed TOML should fall back to defaults, not crash."""
    with tempfile.NamedTemporaryFile(mode="w", suffix=".toml", delete=False) as f:
        f.write("this is not valid [[[ toml")
        f.flush()
        config = load_config(f.name)
    os.unlink(f.name)
    assert config["transcription"]["model"] == "small"
```

- [ ] **Step 3: Run tests to verify they fail**

```bash
cd ~/whisperbox && .venv/bin/python -m pytest service/tests/test_config.py -v
```

Expected: FAIL — `ModuleNotFoundError: No module named 'config'`

- [ ] **Step 4: Write config.py implementation**

```python
# service/config.py
"""WhisperBox configuration loader.

Reads TOML config from ~/.config/whisperbox/config.toml,
merging with defaults for any missing values.
"""

import copy
import os
import tomllib

DEFAULT_CONFIG = {
    "hotkey": {
        "combo": "ctrl+shift+space",
    },
    "transcription": {
        "model": "small",
        "language": "en",
    },
    "behavior": {
        "mode": "instant",
        "sound_feedback": True,
        "max_duration": 300,
        "silence_timeout": 10,
    },
    "postprocessing": {
        "strip_fillers": True,
        "auto_capitalize": True,
        "auto_punctuate": True,
    },
    "indicator": {
        "enabled": True,
        "position": "top-center",
        "opacity": 0.85,
    },
}

CONFIG_PATH = os.path.expanduser("~/.config/whisperbox/config.toml")


def _deep_merge(base: dict, override: dict) -> dict:
    """Recursively merge override into base, returning a new dict."""
    result = copy.deepcopy(base)
    for key, value in override.items():
        if key in result and isinstance(result[key], dict) and isinstance(value, dict):
            result[key] = _deep_merge(result[key], value)
        else:
            result[key] = copy.deepcopy(value)
    return result


def load_config(path: str | None = None) -> dict:
    """Load config from TOML file, merged with defaults.

    Args:
        path: Path to config file. Defaults to CONFIG_PATH.

    Returns:
        Merged configuration dictionary.
    """
    path = path or CONFIG_PATH
    if not os.path.exists(path):
        return copy.deepcopy(DEFAULT_CONFIG)
    try:
        with open(path, "rb") as f:
            user_config = tomllib.load(f)
        return _deep_merge(DEFAULT_CONFIG, user_config)
    except Exception:
        return copy.deepcopy(DEFAULT_CONFIG)
```

- [ ] **Step 5: Run tests to verify they pass**

```bash
cd ~/whisperbox/service && ../.venv/bin/python -m pytest tests/test_config.py -v
```

Expected: 3 passed

- [ ] **Step 6: Commit**

```bash
git add service/config.py service/tests/
git commit -m "feat: add config module with TOML loading and defaults"
```

---

## Chunk 2: Python Service Core (Socket + Audio + Transcription)

### Task 3: Socket Server

**Files:**
- Create: `service/socket_server.py`
- Create: `service/tests/test_socket_server.py`

- [ ] **Step 1: Write failing tests for socket server**

```python
# service/tests/test_socket_server.py
import asyncio
import json
import os
import tempfile
import pytest
from socket_server import SocketServer


@pytest.fixture
def sock_path(tmp_path):
    return str(tmp_path / "test.sock")


@pytest.mark.asyncio
async def test_server_starts_and_accepts_connection(sock_path):
    """Server should bind to socket and accept a client."""
    server = SocketServer(sock_path)
    received = []
    server.on_command = lambda cmd: received.append(cmd)

    task = asyncio.create_task(server.start())
    await asyncio.sleep(0.1)

    reader, writer = await asyncio.open_unix_connection(sock_path)
    writer.write(json.dumps({"cmd": "start_recording"}).encode() + b"\n")
    await writer.drain()
    await asyncio.sleep(0.1)

    assert len(received) == 1
    assert received[0]["cmd"] == "start_recording"

    writer.close()
    await writer.wait_closed()
    server.stop()
    await task


@pytest.mark.asyncio
async def test_server_sends_event(sock_path):
    """Server should send newline-delimited JSON events to clients."""
    server = SocketServer(sock_path)
    task = asyncio.create_task(server.start())
    await asyncio.sleep(0.1)

    reader, writer = await asyncio.open_unix_connection(sock_path)
    await server.send_event({"event": "model_loaded"})
    await asyncio.sleep(0.1)

    line = await asyncio.wait_for(reader.readline(), timeout=1.0)
    msg = json.loads(line)
    assert msg["event"] == "model_loaded"

    writer.close()
    await writer.wait_closed()
    server.stop()
    await task


@pytest.mark.asyncio
async def test_server_removes_stale_socket(sock_path):
    """If a stale .sock file exists, server should remove it and bind."""
    # Create a stale socket file
    with open(sock_path, "w") as f:
        f.write("stale")

    server = SocketServer(sock_path)
    task = asyncio.create_task(server.start())
    await asyncio.sleep(0.1)

    # Should be able to connect
    reader, writer = await asyncio.open_unix_connection(sock_path)
    writer.close()
    await writer.wait_closed()
    server.stop()
    await task
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd ~/whisperbox/service && ../.venv/bin/python -m pytest tests/test_socket_server.py -v
```

Expected: FAIL — `ModuleNotFoundError: No module named 'socket_server'`

- [ ] **Step 3: Install pytest-asyncio in venv**

```bash
cd ~/whisperbox && .venv/bin/pip install pytest-asyncio
```

- [ ] **Step 4: Write socket_server.py implementation**

```python
# service/socket_server.py
"""Unix domain socket server for IPC with the Swift menu bar app.

Protocol: newline-delimited JSON. Each message is a single JSON object
terminated by \n. The server accepts one client at a time.
"""

import asyncio
import json
import os
from typing import Callable


class SocketServer:
    def __init__(self, sock_path: str):
        self.sock_path = sock_path
        self.on_command: Callable[[dict], None] = lambda cmd: None
        self._server: asyncio.AbstractServer | None = None
        self._writer: asyncio.StreamWriter | None = None
        self._running = False

    async def start(self):
        """Start listening on the Unix domain socket."""
        # Remove stale socket
        if os.path.exists(self.sock_path):
            os.unlink(self.sock_path)

        os.makedirs(os.path.dirname(self.sock_path), exist_ok=True)
        self._running = True
        self._server = await asyncio.start_unix_server(
            self._handle_client, path=self.sock_path
        )
        async with self._server:
            try:
                await self._server.serve_forever()
            except asyncio.CancelledError:
                pass

    def stop(self):
        """Stop the server."""
        self._running = False
        if self._server:
            self._server.close()
        if self._writer:
            self._writer.close()

    async def send_event(self, event: dict):
        """Send a JSON event to the connected client."""
        if self._writer and not self._writer.is_closing():
            line = json.dumps(event, ensure_ascii=False) + "\n"
            self._writer.write(line.encode("utf-8"))
            await self._writer.drain()

    async def _handle_client(
        self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter
    ):
        """Handle a single client connection."""
        self._writer = writer
        try:
            while self._running:
                line = await reader.readline()
                if not line:
                    break
                try:
                    msg = json.loads(line.decode("utf-8").strip())
                    self.on_command(msg)
                except json.JSONDecodeError:
                    continue
        except (ConnectionResetError, BrokenPipeError):
            pass
        finally:
            self._writer = None
            writer.close()
```

- [ ] **Step 5: Run tests to verify they pass**

```bash
cd ~/whisperbox/service && ../.venv/bin/python -m pytest tests/test_socket_server.py -v
```

Expected: 3 passed

- [ ] **Step 6: Commit**

```bash
git add service/socket_server.py service/tests/test_socket_server.py
git commit -m "feat: add Unix domain socket server with newline-delimited JSON"
```

---

### Task 4: Audio Capture Module

**Files:**
- Create: `service/audio.py`
- Create: `service/tests/test_audio.py`

- [ ] **Step 1: Write failing tests for audio capture**

```python
# service/tests/test_audio.py
import numpy as np
import pytest
from unittest.mock import patch, MagicMock
from audio import AudioRecorder


def test_recorder_initial_state():
    """Recorder should start in non-recording state."""
    recorder = AudioRecorder()
    assert not recorder.is_recording
    assert recorder.get_audio() is None


def test_recorder_start_stop():
    """Recorder should track recording state."""
    recorder = AudioRecorder()
    with patch("audio.sd") as mock_sd:
        mock_stream = MagicMock()
        mock_sd.InputStream.return_value = mock_stream
        mock_stream.__enter__ = MagicMock(return_value=mock_stream)
        mock_stream.__exit__ = MagicMock(return_value=False)

        recorder.start()
        assert recorder.is_recording

        recorder.stop()
        assert not recorder.is_recording


def test_recorder_callback_accumulates_audio():
    """Audio callback should accumulate samples into the buffer."""
    recorder = AudioRecorder()
    # Simulate audio callback with fake data
    fake_audio = np.random.randn(1600, 1).astype(np.float32)
    recorder._buffer = []
    recorder._audio_callback(fake_audio, None, None, None)
    assert len(recorder._buffer) == 1
    assert recorder._buffer[0].shape == (1600,)


def test_get_audio_returns_concatenated_float32():
    """get_audio should return a flat float32 numpy array."""
    recorder = AudioRecorder()
    chunk1 = np.ones(800, dtype=np.float32)
    chunk2 = np.ones(800, dtype=np.float32) * 0.5
    recorder._buffer = [chunk1, chunk2]
    recorder._is_recording = False
    audio = recorder.get_audio()
    assert audio.dtype == np.float32
    assert len(audio) == 1600
    assert audio[0] == 1.0
    assert audio[800] == 0.5


def test_silence_detection():
    """Silence detector should return True for near-zero audio."""
    recorder = AudioRecorder(silence_threshold=0.01)
    silent = np.zeros(1600, dtype=np.float32)
    assert recorder._is_silence(silent)
    loud = np.ones(1600, dtype=np.float32) * 0.5
    assert not recorder._is_silence(loud)
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd ~/whisperbox/service && ../.venv/bin/python -m pytest tests/test_audio.py -v
```

Expected: FAIL — `ModuleNotFoundError: No module named 'audio'`

- [ ] **Step 3: Write audio.py implementation**

```python
# service/audio.py
"""Audio capture module using sounddevice.

Records 16kHz mono float32 audio into an in-memory buffer.
Supports silence detection for auto-stop.
"""

import threading
import numpy as np
import sounddevice as sd


class AudioRecorder:
    SAMPLE_RATE = 16000  # Whisper expects 16kHz
    CHANNELS = 1

    def __init__(self, silence_threshold: float = 0.01, silence_timeout: float = 10.0):
        self._buffer: list[np.ndarray] = []
        self._is_recording = False
        self._stream: sd.InputStream | None = None
        self._silence_threshold = silence_threshold
        self._silence_timeout = silence_timeout
        self._silence_frames = 0
        self._frames_per_second = self.SAMPLE_RATE
        self.on_silence_timeout: callable = lambda: None

    @property
    def is_recording(self) -> bool:
        return self._is_recording

    def start(self):
        """Start recording audio from the default input device."""
        self._buffer = []
        self._silence_frames = 0
        self._is_recording = True
        self._stream = sd.InputStream(
            samplerate=self.SAMPLE_RATE,
            channels=self.CHANNELS,
            dtype="float32",
            callback=self._audio_callback,
            blocksize=1600,  # 100ms blocks
        )
        self._stream.start()

    def stop(self):
        """Stop recording and close the stream."""
        self._is_recording = False
        if self._stream:
            self._stream.stop()
            self._stream.close()
            self._stream = None

    def cancel(self):
        """Stop recording and discard the buffer."""
        self.stop()
        self._buffer = []

    def get_audio(self) -> np.ndarray | None:
        """Return recorded audio as a flat float32 array, or None if empty."""
        if not self._buffer:
            return None
        return np.concatenate(self._buffer)

    def _audio_callback(self, indata, frames, time_info, status):
        """sounddevice callback — runs on audio thread."""
        mono = indata[:, 0] if indata.ndim > 1 else indata.flatten()
        self._buffer.append(mono.copy())

        # Silence detection
        if self._is_silence(mono):
            self._silence_frames += len(mono)
            if self._silence_frames >= self._silence_timeout * self.SAMPLE_RATE:
                self.on_silence_timeout()
        else:
            self._silence_frames = 0

    def _is_silence(self, audio: np.ndarray) -> bool:
        """Check if audio chunk is below the silence threshold."""
        return float(np.abs(audio).mean()) < self._silence_threshold
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd ~/whisperbox/service && ../.venv/bin/python -m pytest tests/test_audio.py -v
```

Expected: 5 passed

- [ ] **Step 5: Commit**

```bash
git add service/audio.py service/tests/test_audio.py
git commit -m "feat: add audio capture module with silence detection"
```

---

### Task 5: Transcription Wrapper

**Files:**
- Create: `service/transcriber.py`
- Create: `service/tests/test_transcriber.py`

- [ ] **Step 1: Write failing tests for transcriber**

```python
# service/tests/test_transcriber.py
import numpy as np
import pytest
from unittest.mock import patch, MagicMock
from transcriber import Transcriber

MODEL_DIR = "/tmp/whisperbox-test-models"


@patch("transcriber.Model")
def test_transcriber_loads_model(mock_model_cls):
    """Transcriber should load the specified model on init."""
    t = Transcriber(model_name="small", models_dir=MODEL_DIR)
    t.load()
    mock_model_cls.assert_called_once()
    call_args = mock_model_cls.call_args
    assert "small" in str(call_args)


@patch("transcriber.Model")
def test_transcribe_returns_text(mock_model_cls):
    """Transcribe should return the text from whisper segments."""
    mock_model = MagicMock()
    mock_model.transcribe.return_value = [
        MagicMock(text=" Hello world. "),
        MagicMock(text=" How are you? "),
    ]
    mock_model_cls.return_value = mock_model

    t = Transcriber(model_name="small", models_dir=MODEL_DIR)
    t.load()
    audio = np.zeros(16000, dtype=np.float32)
    result = t.transcribe(audio)
    assert result == "Hello world. How are you?"


@patch("transcriber.Model")
def test_transcribe_empty_audio(mock_model_cls):
    """Transcribe with empty audio should return empty string."""
    mock_model = MagicMock()
    mock_model.transcribe.return_value = []
    mock_model_cls.return_value = mock_model

    t = Transcriber(model_name="small", models_dir=MODEL_DIR)
    t.load()
    audio = np.zeros(100, dtype=np.float32)
    result = t.transcribe(audio)
    assert result == ""


@patch("transcriber.Model")
def test_switch_model(mock_model_cls):
    """Switching models should reload with the new model name."""
    t = Transcriber(model_name="small", models_dir=MODEL_DIR)
    t.load()
    assert mock_model_cls.call_count == 1

    t.switch_model("medium")
    assert mock_model_cls.call_count == 2
    assert t.model_name == "medium"
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd ~/whisperbox/service && ../.venv/bin/python -m pytest tests/test_transcriber.py -v
```

Expected: FAIL — `ModuleNotFoundError: No module named 'transcriber'`

- [ ] **Step 3: Write transcriber.py implementation**

```python
# service/transcriber.py
"""Whisper transcription wrapper using pywhispercpp.

Loads a whisper.cpp model once and keeps it in memory for fast inference.
Models are auto-downloaded to the specified models directory.
"""

import os
import numpy as np
from pywhispercpp.model import Model


class Transcriber:
    VALID_MODELS = ("tiny", "base", "small", "medium", "large-v3")

    def __init__(self, model_name: str = "small", models_dir: str | None = None):
        self.model_name = model_name
        self.models_dir = models_dir or os.path.expanduser(
            "~/.local/share/whisperbox/models"
        )
        self._model: Model | None = None

    @property
    def is_loaded(self) -> bool:
        return self._model is not None

    def load(self):
        """Load the whisper model into memory."""
        os.makedirs(self.models_dir, exist_ok=True)
        self._model = Model(
            self.model_name,
            models_dir=self.models_dir,
            n_threads=os.cpu_count() or 4,
        )

    def transcribe(self, audio: np.ndarray, language: str = "en") -> str:
        """Transcribe audio array to text.

        Args:
            audio: Float32 numpy array of audio at 16kHz.
            language: Language code for transcription.

        Returns:
            Transcribed text, stripped and joined from segments.
        """
        if self._model is None:
            raise RuntimeError("Model not loaded. Call load() first.")

        segments = self._model.transcribe(audio, language=language)
        text = " ".join(seg.text.strip() for seg in segments if seg.text.strip())
        return text

    def switch_model(self, model_name: str):
        """Switch to a different model, reloading it into memory."""
        self.model_name = model_name
        self._model = None
        self.load()
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd ~/whisperbox/service && ../.venv/bin/python -m pytest tests/test_transcriber.py -v
```

Expected: 4 passed

- [ ] **Step 5: Commit**

```bash
git add service/transcriber.py service/tests/test_transcriber.py
git commit -m "feat: add Whisper transcription wrapper with model switching"
```

---

## Chunk 3: Python Service Features (Post-Processing, Injection, Orchestration)

### Task 6: Post-Processing Pipeline

**Files:**
- Create: `service/postprocess.py`
- Create: `service/tests/test_postprocess.py`

- [ ] **Step 1: Write failing tests**

```python
# service/tests/test_postprocess.py
from postprocess import postprocess


def test_capitalize_first_letter():
    assert postprocess("hello world", capitalize=True) == "Hello world."


def test_add_period_when_missing():
    assert postprocess("Hello world", punctuate=True) == "Hello world."


def test_no_double_period():
    assert postprocess("Hello world.", punctuate=True) == "Hello world."


def test_preserve_question_mark():
    assert postprocess("How are you?", punctuate=True) == "How are you?"


def test_preserve_exclamation():
    assert postprocess("Wow!", punctuate=True) == "Wow!"


def test_strip_fillers():
    assert postprocess("Um hello uh world", strip_fillers=True) == "Hello world."


def test_strip_fillers_case_insensitive():
    assert postprocess("UM hello UH world", strip_fillers=True) == "Hello world."


def test_empty_string():
    assert postprocess("") == ""


def test_whitespace_only():
    assert postprocess("   ") == ""


def test_all_options_disabled():
    result = postprocess(
        "um hello", capitalize=False, punctuate=False, strip_fillers=False
    )
    assert result == "um hello"


def test_filler_only_input():
    assert postprocess("um uh", strip_fillers=True) == ""
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd ~/whisperbox/service && ../.venv/bin/python -m pytest tests/test_postprocess.py -v
```

Expected: FAIL — `ModuleNotFoundError: No module named 'postprocess'`

- [ ] **Step 3: Write postprocess.py implementation**

```python
# service/postprocess.py
"""Text post-processing pipeline for transcription output."""

import re

FILLER_WORDS = {"um", "uh", "er", "ah"}
# Match filler words as whole words, case-insensitive
FILLER_PATTERN = re.compile(
    r"\b(" + "|".join(re.escape(w) for w in FILLER_WORDS) + r")\b",
    re.IGNORECASE,
)


def postprocess(
    text: str,
    capitalize: bool = True,
    punctuate: bool = True,
    strip_fillers: bool = True,
) -> str:
    """Clean up transcribed text.

    Args:
        text: Raw transcription text.
        capitalize: Capitalize the first letter.
        punctuate: Add a period if no ending punctuation.
        strip_fillers: Remove filler words (um, uh, etc).

    Returns:
        Cleaned text string.
    """
    text = text.strip()
    if not text:
        return ""

    if strip_fillers:
        text = FILLER_PATTERN.sub("", text)
        text = re.sub(r"\s+", " ", text).strip()

    if not text:
        return ""

    if capitalize and text:
        text = text[0].upper() + text[1:]

    if punctuate and text and text[-1] not in ".!?":
        text += "."

    return text
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd ~/whisperbox/service && ../.venv/bin/python -m pytest tests/test_postprocess.py -v
```

Expected: 11 passed

- [ ] **Step 5: Commit**

```bash
git add service/postprocess.py service/tests/test_postprocess.py
git commit -m "feat: add text post-processing with filler stripping"
```

---

### Task 7: Text Injector

**Files:**
- Create: `service/injector.py`
- Create: `service/tests/test_injector.py`

- [ ] **Step 1: Write failing tests**

```python
# service/tests/test_injector.py
import subprocess
from unittest.mock import patch, MagicMock, call
from injector import TextInjector


@patch("injector.subprocess.run")
def test_inject_uses_applescript_paste(mock_run):
    """Primary injection should use pbcopy + Cmd+V via AppleScript."""
    mock_run.return_value = MagicMock(returncode=0)
    injector = TextInjector()
    injector.inject("Hello world")

    calls = mock_run.call_args_list
    # First call: save clipboard
    # Second call: pbcopy
    # Third call: Cmd+V via osascript
    # Fourth call: restore clipboard
    assert any("pbcopy" in str(c) for c in calls)
    assert any("osascript" in str(c) for c in calls)


@patch("injector.subprocess.run")
def test_inject_empty_text_is_noop(mock_run):
    """Injecting empty text should do nothing."""
    injector = TextInjector()
    injector.inject("")
    mock_run.assert_not_called()


@patch("injector.subprocess.run")
def test_inject_preserves_clipboard(mock_run):
    """Clipboard should be saved and restored around injection."""
    # pbpaste returns old clipboard
    mock_run.side_effect = [
        MagicMock(returncode=0, stdout="old-clipboard"),  # pbpaste (save)
        MagicMock(returncode=0),  # pbcopy (set new text)
        MagicMock(returncode=0),  # osascript (Cmd+V)
        MagicMock(returncode=0),  # pbcopy (restore)
    ]
    injector = TextInjector()
    injector.inject("new text")
    # Last call should restore "old-clipboard"
    last_call = mock_run.call_args_list[-1]
    assert "old-clipboard" in str(last_call) or "pbcopy" in str(last_call)
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd ~/whisperbox/service && ../.venv/bin/python -m pytest tests/test_injector.py -v
```

Expected: FAIL — `ModuleNotFoundError: No module named 'injector'`

- [ ] **Step 3: Write injector.py implementation**

```python
# service/injector.py
"""Text injection into the focused application.

Primary: saves clipboard, copies text via pbcopy, pastes via Cmd+V
(AppleScript), then restores clipboard. Fast and Unicode-safe.
"""

import subprocess
import time


class TextInjector:
    # Small delay to let paste complete before restoring clipboard
    PASTE_DELAY = 0.15

    def inject(self, text: str):
        """Inject text at the current cursor position in the focused app."""
        if not text:
            return

        # Save current clipboard
        saved = self._get_clipboard()

        try:
            # Copy transcribed text to clipboard
            self._set_clipboard(text)

            # Paste via Cmd+V using AppleScript
            subprocess.run(
                [
                    "osascript",
                    "-e",
                    'tell application "System Events" to keystroke "v" using command down',
                ],
                check=True,
                capture_output=True,
            )

            # Wait for paste to complete
            time.sleep(self.PASTE_DELAY)
        finally:
            # Restore original clipboard
            self._set_clipboard(saved)

    def _get_clipboard(self) -> str:
        """Read current clipboard contents."""
        try:
            result = subprocess.run(
                ["pbpaste"], capture_output=True, text=True, timeout=2
            )
            return result.stdout
        except Exception:
            return ""

    def _set_clipboard(self, text: str):
        """Set clipboard contents via pbcopy."""
        subprocess.run(
            ["pbcopy"],
            input=text.encode("utf-8"),
            check=True,
            timeout=2,
        )
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd ~/whisperbox/service && ../.venv/bin/python -m pytest tests/test_injector.py -v
```

Expected: 3 passed

- [ ] **Step 5: Commit**

```bash
git add service/injector.py service/tests/test_injector.py
git commit -m "feat: add text injector with clipboard-based paste"
```

---

### Task 8: Service Orchestrator

**Files:**
- Create: `service/service.py`
- Create: `service/tests/test_service.py`

- [ ] **Step 1: Write failing tests for the orchestrator**

```python
# service/tests/test_service.py
import asyncio
import json
import pytest
from unittest.mock import patch, MagicMock, AsyncMock
from service import WhisperBoxService


@pytest.fixture
def service(tmp_path):
    sock_path = str(tmp_path / "test.sock")
    config = {
        "transcription": {"model": "small", "language": "en"},
        "behavior": {
            "mode": "instant",
            "max_duration": 300,
            "silence_timeout": 10,
            "sound_feedback": False,
        },
        "postprocessing": {
            "strip_fillers": True,
            "auto_capitalize": True,
            "auto_punctuate": True,
        },
    }
    return WhisperBoxService(config=config, sock_path=sock_path)


def test_handle_start_recording(service):
    """start_recording command should begin audio capture."""
    with patch.object(service, "_recorder") as mock_rec:
        service._handle_command({"cmd": "start_recording"})
        mock_rec.start.assert_called_once()
        assert service._state == "recording"


def test_handle_stop_recording(service):
    """stop_recording command should stop capture and trigger transcription."""
    import numpy as np

    service._state = "recording"
    mock_audio = np.zeros(16000, dtype=np.float32)
    with (
        patch.object(service, "_recorder") as mock_rec,
        patch.object(service, "_transcriber") as mock_trans,
        patch.object(service, "_injector") as mock_inj,
    ):
        mock_rec.get_audio.return_value = mock_audio
        mock_trans.transcribe.return_value = "hello world"
        service._handle_command({"cmd": "stop_recording"})
        mock_rec.stop.assert_called_once()
        mock_trans.transcribe.assert_called_once()


def test_handle_cancel_recording(service):
    """cancel_recording should discard audio without transcription."""
    service._state = "recording"
    with (
        patch.object(service, "_recorder") as mock_rec,
        patch.object(service, "_transcriber") as mock_trans,
    ):
        service._handle_command({"cmd": "cancel_recording"})
        mock_rec.cancel.assert_called_once()
        mock_trans.transcribe.assert_not_called()
        assert service._state == "idle"


def test_handle_unknown_command(service):
    """Unknown commands should be ignored."""
    service._handle_command({"cmd": "nonexistent"})
    assert service._state == "idle"
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd ~/whisperbox/service && ../.venv/bin/python -m pytest tests/test_service.py -v
```

Expected: FAIL — `ModuleNotFoundError: No module named 'service'`

- [ ] **Step 3: Write service.py implementation**

```python
# service/service.py
"""WhisperBox transcription service — main orchestrator.

Coordinates audio capture, transcription, post-processing, and text
injection. Communicates with the Swift menu bar app via Unix socket.
"""

import asyncio
import os
import signal
import sys
import threading

from audio import AudioRecorder
from config import load_config
from injector import TextInjector
from postprocess import postprocess
from socket_server import SocketServer
from transcriber import Transcriber


class WhisperBoxService:
    def __init__(self, config: dict | None = None, sock_path: str | None = None):
        self._config = config or load_config()
        tc = self._config["transcription"]
        bc = self._config["behavior"]

        self._sock_path = sock_path or os.path.expanduser(
            "~/.local/share/whisperbox/whisperbox.sock"
        )
        self._server = SocketServer(self._sock_path)
        self._server.on_command = self._handle_command

        self._recorder = AudioRecorder(
            silence_timeout=bc.get("silence_timeout", 10),
        )
        self._recorder.on_silence_timeout = self._on_silence_timeout

        self._transcriber = Transcriber(model_name=tc.get("model", "small"))
        self._injector = TextInjector()

        self._state = "idle"  # idle, recording, transcribing
        self._max_duration = bc.get("max_duration", 300)
        self._duration_timer: threading.Timer | None = None
        self._loop: asyncio.AbstractEventLoop | None = None

    def _handle_command(self, cmd: dict):
        """Dispatch incoming commands from the Swift app."""
        action = cmd.get("cmd")

        if action == "start_recording" and self._state == "idle":
            self._start_recording()
        elif action == "stop_recording" and self._state == "recording":
            self._stop_and_transcribe()
        elif action == "cancel_recording" and self._state == "recording":
            self._cancel_recording()
        elif action == "inject_text":
            # Preview mode: user confirmed text, inject it now
            text = cmd.get("text", "")
            if text:
                self._injector.inject(text)
        elif action == "switch_model":
            model = cmd.get("model", "small")
            self._switch_model(model)
        elif action == "reload_config":
            self._config = load_config()

    def _start_recording(self):
        """Begin audio capture."""
        self._state = "recording"
        self._recorder.start()
        self._send_event({"event": "recording_started"})

        # Max duration safety timer
        self._duration_timer = threading.Timer(
            self._max_duration, self._on_max_duration
        )
        self._duration_timer.start()

    def _stop_and_transcribe(self):
        """Stop recording, transcribe, and inject text."""
        self._cancel_timer()
        self._recorder.stop()
        self._state = "transcribing"
        self._send_event({"event": "recording_stopped"})

        audio = self._recorder.get_audio()
        if audio is None or len(audio) < 1600:  # Less than 100ms
            self._state = "idle"
            self._send_event(
                {"event": "transcription_error", "error": "Recording too short"}
            )
            return

        try:
            pp = self._config["postprocessing"]
            raw_text = self._transcriber.transcribe(
                audio, language=self._config["transcription"].get("language", "en")
            )
            text = postprocess(
                raw_text,
                capitalize=pp.get("auto_capitalize", True),
                punctuate=pp.get("auto_punctuate", True),
                strip_fillers=pp.get("strip_fillers", True),
            )

            mode = self._config["behavior"].get("mode", "instant")
            if mode == "instant" and text:
                self._injector.inject(text)

            self._send_event(
                {
                    "event": "transcription_complete",
                    "text": text,
                    "preview": mode == "preview",
                }
            )
        except Exception as e:
            self._send_event({"event": "transcription_error", "error": str(e)})
        finally:
            self._state = "idle"

    def _cancel_recording(self):
        """Cancel recording without transcription."""
        self._cancel_timer()
        self._recorder.cancel()
        self._state = "idle"
        self._send_event({"event": "recording_stopped"})

    def _switch_model(self, model_name: str):
        """Switch to a different Whisper model."""
        self._send_event({"event": "model_loading", "model": model_name})
        try:
            self._transcriber.switch_model(model_name)
            self._send_event({"event": "model_loaded"})
        except Exception as e:
            self._send_event({"event": "transcription_error", "error": str(e)})

    def _on_silence_timeout(self):
        """Called when silence exceeds the timeout during recording."""
        if self._state == "recording":
            self._stop_and_transcribe()

    def _on_max_duration(self):
        """Called when recording exceeds the maximum duration."""
        if self._state == "recording":
            self._stop_and_transcribe()

    def _cancel_timer(self):
        if self._duration_timer:
            self._duration_timer.cancel()
            self._duration_timer = None

    def _send_event(self, event: dict):
        """Send event to Swift app via socket."""
        if self._loop:
            asyncio.run_coroutine_threadsafe(
                self._server.send_event(event), self._loop
            )

    async def run(self):
        """Main entry point — load model and start socket server."""
        self._loop = asyncio.get_running_loop()

        # Load whisper model
        print(f"Loading Whisper model: {self._transcriber.model_name}")
        self._transcriber.load()
        print("Model loaded, starting socket server...")

        await self._server.start()


def main():
    config = load_config()
    service = WhisperBoxService(config=config)

    def shutdown(sig, frame):
        service._server.stop()
        sys.exit(0)

    signal.signal(signal.SIGTERM, shutdown)
    signal.signal(signal.SIGINT, shutdown)

    asyncio.run(service.run())


if __name__ == "__main__":
    main()
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd ~/whisperbox/service && ../.venv/bin/python -m pytest tests/test_service.py -v
```

Expected: 4 passed

- [ ] **Step 5: Run all Python tests to verify nothing is broken**

```bash
cd ~/whisperbox/service && ../.venv/bin/python -m pytest tests/ -v
```

Expected: All tests pass

- [ ] **Step 6: Commit**

```bash
git add service/service.py service/tests/test_service.py
git commit -m "feat: add service orchestrator with recording state machine"
```

---

## Chunk 4: Swift Menu Bar App

### Task 9: Swift Package Setup

**Files:**
- Create: `app/Package.swift`
- Create: `app/Sources/WhisperBox/main.swift` (placeholder)

- [ ] **Step 1: Create Swift package structure**

```bash
mkdir -p ~/whisperbox/app/Sources/WhisperBox
```

- [ ] **Step 2: Write Package.swift**

```swift
// app/Package.swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WhisperBox",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/soffes/HotKey", from: "0.2.1"),
    ],
    targets: [
        .executableTarget(
            name: "WhisperBox",
            dependencies: ["HotKey"],
            path: "Sources/WhisperBox"
        ),
    ]
)
```

- [ ] **Step 3: Write placeholder main.swift**

```swift
// app/Sources/WhisperBox/main.swift
import AppKit

print("WhisperBox — placeholder, will be implemented in next tasks")
NSApplication.shared.run()
```

- [ ] **Step 4: Verify it compiles**

```bash
cd ~/whisperbox/app && swift build 2>&1
```

Expected: Build succeeds, downloads HotKey dependency

- [ ] **Step 5: Add .build to gitignore and commit**

```bash
echo ".build/" >> ~/whisperbox/.gitignore
git add app/Package.swift app/Sources/ .gitignore
git commit -m "feat: add Swift package skeleton with HotKey dependency"
```

---

### Task 10: Socket Client (Swift)

**Files:**
- Create: `app/Sources/WhisperBox/SocketClient.swift`

- [ ] **Step 1: Write SocketClient.swift**

```swift
// app/Sources/WhisperBox/SocketClient.swift
import Foundation

/// Communicates with the Python transcription service over a Unix domain socket.
/// Protocol: newline-delimited JSON.
class SocketClient {
    private let socketPath: String
    private var fd: Int32 = -1
    private var isConnected = false
    private let readQueue = DispatchQueue(label: "whisperbox.socket.read")
    private let writeQueue = DispatchQueue(label: "whisperbox.socket.write")

    var onEvent: (([String: Any]) -> Void)?

    init(socketPath: String? = nil) {
        self.socketPath = socketPath ?? NSString(
            string: "~/.local/share/whisperbox/whisperbox.sock"
        ).expandingTildeInPath
    }

    func connect() {
        // Create Unix domain socket
        fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            print("[WhisperBox] Failed to create socket")
            return
        }

        // Build sockaddr_un
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        socketPath.withCString { ptr in
            withUnsafeMutablePointer(to: &addr.sun_path.0) { dest in
                _ = strcpy(dest, ptr)
            }
        }

        // Connect
        let addrLen = socklen_t(MemoryLayout<sockaddr_un>.size)
        let result = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Darwin.connect(fd, sockPtr, addrLen)
            }
        }

        guard result == 0 else {
            print("[WhisperBox] Failed to connect: errno=\(errno)")
            Darwin.close(fd)
            fd = -1
            return
        }

        isConnected = true

        // Start reading on background queue
        readQueue.async { [weak self] in
            self?.readLoop()
        }
    }

    func sendCommand(_ command: [String: Any]) {
        writeQueue.async { [weak self] in
            guard let self = self, self.isConnected, self.fd >= 0 else { return }
            guard let data = try? JSONSerialization.data(withJSONObject: command),
                  let jsonString = String(data: data, encoding: .utf8) else { return }

            let line = jsonString + "\n"
            line.utf8.withContiguousStorageIfAvailable { buf in
                Darwin.write(self.fd, buf.baseAddress!, buf.count)
            }
        }
    }

    func disconnect() {
        isConnected = false
        if fd >= 0 {
            Darwin.close(fd)
            fd = -1
        }
    }

    private func readLoop() {
        var buffer = [UInt8](repeating: 0, count: 4096)
        var accumulated = Data()

        while isConnected {
            let bytesRead = Darwin.read(fd, &buffer, buffer.count)
            if bytesRead <= 0 {
                isConnected = false
                break
            }

            accumulated.append(contentsOf: buffer[0..<bytesRead])

            // Process complete newline-delimited JSON lines
            while let newlineIndex = accumulated.firstIndex(of: 0x0A) {
                let lineData = accumulated.subdata(in: accumulated.startIndex..<newlineIndex)
                accumulated.removeSubrange(accumulated.startIndex...newlineIndex)

                if let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] {
                    DispatchQueue.main.async { [weak self] in
                        self?.onEvent?(json)
                    }
                }
            }
        }
    }
}
```

- [ ] **Step 2: Verify it compiles**

```bash
cd ~/whisperbox/app && swift build 2>&1
```

Expected: Build succeeds

- [ ] **Step 3: Commit**

```bash
git add app/Sources/WhisperBox/SocketClient.swift
git commit -m "feat: add Swift Unix domain socket client"
```

---

### Task 11: Permissions Check

**Files:**
- Create: `app/Sources/WhisperBox/PermissionsCheck.swift`

- [ ] **Step 1: Write PermissionsCheck.swift**

```swift
// app/Sources/WhisperBox/PermissionsCheck.swift
import AppKit
import ApplicationServices

/// Checks and prompts for Accessibility permission, required for
/// global hotkeys (CGEvent taps) and text injection (synthetic paste).
struct PermissionsCheck {

    /// Returns true if the app has Accessibility permission.
    static var isAccessibilityGranted: Bool {
        AXIsProcessTrusted()
    }

    /// Prompt the user to grant Accessibility permission.
    /// Shows an alert explaining why, then opens System Settings.
    static func promptIfNeeded() {
        guard !isAccessibilityGranted else { return }

        let alert = NSAlert()
        alert.messageText = "WhisperBox Needs Accessibility Access"
        alert.informativeText = """
            WhisperBox uses a global keyboard shortcut to start/stop recording, \
            and pastes transcribed text into your apps. Both require Accessibility \
            permission.

            Click "Open Settings" to grant access, then restart WhisperBox.
            """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Quit")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            // Open Accessibility pane in System Settings
            let opts = [kAXTrustedCheckOptionPrompt as String: true] as CFDictionary
            AXIsProcessTrustedWithOptions(opts)
        } else {
            NSApp.terminate(nil)
        }
    }
}
```

- [ ] **Step 2: Verify it compiles**

```bash
cd ~/whisperbox/app && swift build 2>&1
```

- [ ] **Step 3: Commit**

```bash
git add app/Sources/WhisperBox/PermissionsCheck.swift
git commit -m "feat: add Accessibility permission check and onboarding"
```

---

### Task 12: Toast Overlay with Voice Animation

**Files:**
- Create: `app/Sources/WhisperBox/ToastOverlay.swift`

- [ ] **Step 1: Write ToastOverlay.swift**

```swift
// app/Sources/WhisperBox/ToastOverlay.swift
import AppKit
import SwiftUI

/// Floating recording indicator with animated sound wave bars.
class ToastOverlay {
    private var window: NSWindow?
    private var hostingView: NSHostingView<ToastView>?
    private var toastState = ToastState()

    func show() {
        guard window == nil else {
            toastState.isRecording = true
            toastState.statusText = "Listening..."
            return
        }

        toastState.isRecording = true
        toastState.statusText = "Listening..."

        let view = ToastView(state: toastState)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: 180, height: 50)

        let window = NSPanel(
            contentRect: hosting.frame,
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        window.isFloatingPanel = true
        window.level = .floating
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.contentView = hosting

        // Position at top-center of main screen
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.midX - hosting.frame.width / 2
            let y = screenFrame.maxY - hosting.frame.height - 20
            window.setFrameOrigin(NSPoint(x: x, y: y))
        }

        window.alphaValue = 0
        window.orderFront(nil)

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.3
            window.animator().alphaValue = 1.0
        }

        self.window = window
        self.hostingView = hosting
    }

    func showTranscribed(text: String) {
        toastState.isRecording = false
        let preview = text.count > 30 ? String(text.prefix(30)) + "..." : text
        toastState.statusText = preview.isEmpty ? "Transcribed!" : preview

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.hide()
        }
    }

    func showError(_ message: String) {
        toastState.isRecording = false
        toastState.statusText = message

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.hide()
        }
    }

    func hide() {
        guard let window = self.window else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.3
            window.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            window.orderOut(nil)
            self?.window = nil
            self?.hostingView = nil
        })
    }
}

// MARK: - SwiftUI Views

class ToastState: ObservableObject {
    @Published var isRecording = false
    @Published var statusText = "Listening..."
}

struct ToastView: View {
    @ObservedObject var state: ToastState

    var body: some View {
        HStack(spacing: 10) {
            if state.isRecording {
                SoundWaveBars()
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.system(size: 16))
            }
            Text(state.statusText)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white)
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.85))
        )
    }
}

struct SoundWaveBars: View {
    @State private var animating = false
    let barCount = 5
    let barWidth: CGFloat = 3
    let maxHeight: CGFloat = 20
    let minHeight: CGFloat = 4

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<barCount, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.red)
                    .frame(width: barWidth, height: animating ? maxHeight : minHeight)
                    .animation(
                        .easeInOut(duration: 0.4 + Double(i) * 0.1)
                        .repeatForever(autoreverses: true),
                        value: animating
                    )
            }
        }
        .frame(height: maxHeight)
        .onAppear { animating = true }
    }
}
```

- [ ] **Step 2: Verify it compiles**

```bash
cd ~/whisperbox/app && swift build 2>&1
```

- [ ] **Step 3: Commit**

```bash
git add app/Sources/WhisperBox/ToastOverlay.swift
git commit -m "feat: add recording toast overlay with animated sound wave bars"
```

---

### Task 13: Preview Panel

**Files:**
- Create: `app/Sources/WhisperBox/PreviewPanel.swift`

- [ ] **Step 1: Write PreviewPanel.swift**

```swift
// app/Sources/WhisperBox/PreviewPanel.swift
import AppKit
import SwiftUI
import Carbon.HIToolbox

/// Native macOS panel for preview mode — shows transcription text,
/// Enter to confirm and paste, Escape to discard.
class PreviewPanel {
    private var window: NSPanel?
    private var panelState = PreviewPanelState()
    private var eventMonitor: Any?
    var onConfirm: ((String) -> Void)?
    var onDiscard: (() -> Void)?

    func show(text: String) {
        panelState.text = text

        let view = PreviewPanelView(state: panelState, onConfirm: { [weak self] in
            self?.confirm()
        }, onDiscard: { [weak self] in
            self?.discard()
        })

        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: 400, height: 150)

        let panel = NSPanel(
            contentRect: hosting.frame,
            styleMask: [.nonactivatingPanel, .titled, .closable, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.contentView = hosting
        panel.title = "WhisperBox Preview"

        // Center on screen
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.midX - hosting.frame.width / 2
            let y = screenFrame.midY - hosting.frame.height / 2
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        panel.makeKeyAndOrderFront(nil)
        self.window = panel

        // Monitor for Enter/Escape keys (store reference for cleanup)
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard self?.window != nil else { return event }
            if event.keyCode == UInt16(kVK_Return) {
                self?.confirm()
                return nil
            } else if event.keyCode == UInt16(kVK_Escape) {
                self?.discard()
                return nil
            }
            return event
        }
    }

    private func confirm() {
        let text = panelState.text
        hide()
        onConfirm?(text)
    }

    private func discard() {
        hide()
        onDiscard?()
    }

    func hide() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        window?.orderOut(nil)
        window = nil
    }
}

class PreviewPanelState: ObservableObject {
    @Published var text: String = ""
}

struct PreviewPanelView: View {
    @ObservedObject var state: PreviewPanelState
    var onConfirm: () -> Void
    var onDiscard: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Text(state.text)
                .font(.system(size: 14))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(6)

            HStack {
                Text("Enter to paste · Escape to discard")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Spacer()
                Button("Discard") { onDiscard() }
                    .keyboardShortcut(.escape, modifiers: [])
                Button("Paste") { onConfirm() }
                    .keyboardShortcut(.return, modifiers: [])
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .frame(width: 400)
    }
}
```

- [ ] **Step 2: Verify it compiles**

```bash
cd ~/whisperbox/app && swift build 2>&1
```

- [ ] **Step 3: Commit**

```bash
git add app/Sources/WhisperBox/PreviewPanel.swift
git commit -m "feat: add preview panel for transcription confirmation"
```

---

### Task 14: Hotkey Manager

**Files:**
- Create: `app/Sources/WhisperBox/HotkeyManager.swift`

- [ ] **Step 1: Write HotkeyManager.swift**

```swift
// app/Sources/WhisperBox/HotkeyManager.swift
import AppKit
import HotKey
import Carbon.HIToolbox

/// Manages global keyboard shortcuts for WhisperBox.
/// Default: Ctrl+Shift+Space to toggle recording, Escape to cancel.
class HotkeyManager {
    private var toggleHotKey: HotKey?
    private var escapeHotKey: HotKey?

    var onToggle: (() -> Void)?
    var onCancel: (() -> Void)?

    func register() {
        // Ctrl+Shift+Space — always active
        toggleHotKey = HotKey(
            key: .space,
            modifiers: [.control, .shift]
        )
        toggleHotKey?.keyDownHandler = { [weak self] in
            self?.onToggle?()
        }
    }

    /// Register/unregister Escape dynamically — only active during recording.
    /// This avoids intercepting Escape globally when not needed.
    func setEscapeEnabled(_ enabled: Bool) {
        if enabled {
            escapeHotKey = HotKey(key: .escape, modifiers: [])
            escapeHotKey?.keyDownHandler = { [weak self] in
                self?.onCancel?()
            }
        } else {
            escapeHotKey = nil  // unregisters the hotkey
        }
    }

    func unregister() {
        toggleHotKey = nil
        escapeHotKey = nil
    }
}
```

- [ ] **Step 2: Verify it compiles**

```bash
cd ~/whisperbox/app && swift build 2>&1
```

- [ ] **Step 3: Commit**

```bash
git add app/Sources/WhisperBox/HotkeyManager.swift
git commit -m "feat: add global hotkey manager with HotKey package"
```

---

### Task 15: Main App Entry Point (Menu Bar App)

**Files:**
- Modify: `app/Sources/WhisperBox/main.swift`

- [ ] **Step 1: Write the full main.swift**

```swift
// app/Sources/WhisperBox/main.swift
import AppKit
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var socketClient: SocketClient!
    private var hotkeyManager: HotkeyManager!
    private var toast: ToastOverlay!
    private var previewPanel: PreviewPanel!
    private var pythonProcess: Process?
    private var isRecording = false
    private var restartCount = 0
    private let maxRestarts = 3

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Check accessibility permission
        PermissionsCheck.promptIfNeeded()

        setupMenuBar()
        setupHotkeys()
        setupSocket()
        setupPreviewPanel()
        startPythonService()

        toast = ToastOverlay()
    }

    // MARK: - Menu Bar

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateMenuBarIcon(recording: false)
        buildMenu()
    }

    private func updateMenuBarIcon(recording: Bool) {
        if let button = statusItem.button {
            let symbolName = recording ? "mic.fill" : "mic"
            let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "WhisperBox")
            image?.isTemplate = !recording
            if recording {
                button.contentTintColor = .systemRed
            } else {
                button.contentTintColor = nil
            }
            button.image = image
        }
    }

    private func buildMenu() {
        let menu = NSMenu()

        let recordItem = NSMenuItem(
            title: "Start Recording",
            action: #selector(toggleRecording),
            keyEquivalent: ""
        )
        recordItem.target = self
        menu.addItem(recordItem)

        menu.addItem(.separator())

        // Model submenu
        let modelMenu = NSMenu()
        for model in ["tiny", "base", "small", "medium", "large-v3"] {
            let item = NSMenuItem(title: model, action: #selector(switchModel(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = model
            modelMenu.addItem(item)
        }
        let modelItem = NSMenuItem(title: "Model", action: nil, keyEquivalent: "")
        modelItem.submenu = modelMenu
        menu.addItem(modelItem)

        let settingsItem = NSMenuItem(
            title: "Settings...",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit WhisperBox",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    // MARK: - Hotkeys

    private func setupHotkeys() {
        hotkeyManager = HotkeyManager()
        hotkeyManager.onToggle = { [weak self] in
            self?.toggleRecording()
        }
        hotkeyManager.onCancel = { [weak self] in
            guard self?.isRecording == true else { return }
            self?.cancelRecording()
        }
        hotkeyManager.register()
        hotkeyManager.setEscapeEnabled(false)
    }

    // MARK: - Socket

    private func setupSocket() {
        socketClient = SocketClient()
        socketClient.onEvent = { [weak self] event in
            self?.handleServiceEvent(event)
        }
    }

    private func handleServiceEvent(_ event: [String: Any]) {
        guard let eventType = event["event"] as? String else { return }

        switch eventType {
        case "recording_started":
            isRecording = true
            updateMenuBarIcon(recording: true)
            hotkeyManager.setEscapeEnabled(true)
            toast.show()

        case "recording_stopped":
            isRecording = false
            updateMenuBarIcon(recording: false)
            hotkeyManager.setEscapeEnabled(false)

        case "transcription_complete":
            let text = event["text"] as? String ?? ""
            let preview = event["preview"] as? Bool ?? false
            if preview {
                previewPanel.show(text: text)
            }
            toast.showTranscribed(text: text)

        case "transcription_error":
            let error = event["error"] as? String ?? "Unknown error"
            toast.showError(error)

        case "model_loading":
            let model = event["model"] as? String ?? ""
            toast.show()
            // Reuse toast to show loading state

        case "model_loaded":
            toast.showTranscribed(text: "Model ready")

        default:
            break
        }
    }

    // MARK: - Preview

    private func setupPreviewPanel() {
        previewPanel = PreviewPanel()
        previewPanel.onConfirm = { [weak self] text in
            // Inject text via socket command — Python handles injection
            self?.socketClient.sendCommand([
                "cmd": "inject_text",
                "text": text,
            ])
        }
    }

    // MARK: - Python Service

    private func startPythonService() {
        let whisperboxDir = NSString(string: "~/whisperbox").expandingTildeInPath
        let pythonPath = "\(whisperboxDir)/.venv/bin/python"
        let servicePath = "\(whisperboxDir)/service/service.py"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: pythonPath)
        process.arguments = [servicePath]
        process.currentDirectoryURL = URL(fileURLWithPath: "\(whisperboxDir)/service")
        process.terminationHandler = { [weak self] proc in
            guard let self = self else { return }
            if proc.terminationStatus != 0 && self.restartCount < self.maxRestarts {
                self.restartCount += 1
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    self.startPythonService()
                }
            } else if self.restartCount >= self.maxRestarts {
                DispatchQueue.main.async {
                    self.updateMenuBarIcon(recording: false)
                    // Could show error state in menu bar
                }
            }
        }

        do {
            try process.run()
            pythonProcess = process
            // Wait a moment for the service to start, then connect
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                self.socketClient.connect()
                self.restartCount = 0
            }
        } catch {
            print("Failed to start Python service: \(error)")
        }
    }

    // MARK: - Actions

    @objc private func toggleRecording() {
        if isRecording {
            socketClient.sendCommand(["cmd": "stop_recording"])
        } else {
            socketClient.sendCommand(["cmd": "start_recording"])
        }
    }

    private func cancelRecording() {
        socketClient.sendCommand(["cmd": "cancel_recording"])
    }

    @objc private func switchModel(_ sender: NSMenuItem) {
        guard let model = sender.representedObject as? String else { return }
        socketClient.sendCommand(["cmd": "switch_model", "model": model])
    }

    @objc private func openSettings() {
        let configPath = NSString(string: "~/.config/whisperbox/config.toml").expandingTildeInPath
        NSWorkspace.shared.open(URL(fileURLWithPath: configPath))
    }

    @objc private func quit() {
        pythonProcess?.terminate()
        hotkeyManager.unregister()
        socketClient.disconnect()
        NSApp.terminate(nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        pythonProcess?.terminate()
    }
}

// MARK: - Launch

let app = NSApplication.shared
app.setActivationPolicy(.accessory)  // Menu bar only, no dock icon
let delegate = AppDelegate()
app.delegate = delegate
app.run()
```

- [ ] **Step 2: Verify it compiles**

```bash
cd ~/whisperbox/app && swift build 2>&1
```

- [ ] **Step 3: Commit**

```bash
git add app/Sources/WhisperBox/main.swift
git commit -m "feat: add main app with menu bar, process management, and event handling"
```

---

## Chunk 5: Build, Integration & Polish

### Task 16: Build Script

**Files:**
- Modify: `scripts/build.sh`

- [ ] **Step 1: Write the build script**

```bash
#!/usr/bin/env bash
set -euo pipefail

WHISPERBOX_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$WHISPERBOX_DIR/app"
BUILD_DIR="$WHISPERBOX_DIR/build"

echo "=== Building WhisperBox ==="

# Build Swift app in release mode
cd "$APP_DIR"
swift build -c release 2>&1

# Copy binary to build dir
mkdir -p "$BUILD_DIR"
BINARY=$(swift build -c release --show-bin-path)/WhisperBox
cp "$BINARY" "$BUILD_DIR/WhisperBox"

# Create .app bundle
APP_BUNDLE="$BUILD_DIR/WhisperBox.app"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"
cp "$BINARY" "$APP_BUNDLE/Contents/MacOS/WhisperBox"

cat > "$APP_BUNDLE/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>WhisperBox</string>
    <key>CFBundleIdentifier</key>
    <string>com.whisperbox.app</string>
    <key>CFBundleVersion</key>
    <string>1.0.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleExecutable</key>
    <string>WhisperBox</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>WhisperBox needs microphone access to record speech for transcription.</string>
</dict>
</plist>
PLIST

echo "=== Build complete ==="
echo "App bundle: $APP_BUNDLE"
echo ""
echo "To run: open $APP_BUNDLE"
echo "Or: $APP_BUNDLE/Contents/MacOS/WhisperBox"
```

- [ ] **Step 2: Make executable and commit**

```bash
chmod +x scripts/build.sh
git add scripts/build.sh
git commit -m "feat: add build script that produces WhisperBox.app bundle"
```

---

### Task 17: End-to-End Integration Test

**Files:**
- Create: `scripts/smoke-test.sh`

- [ ] **Step 1: Write smoke test script**

```bash
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
```

- [ ] **Step 2: Make executable and commit**

```bash
chmod +x scripts/smoke-test.sh
git add scripts/smoke-test.sh
git commit -m "feat: add smoke test script for installation verification"
```

---

### Task 18: First Run — Install, Build, and Test

This task is manual integration — run the full pipeline end to end.

- [ ] **Step 1: Run the install script**

```bash
cd ~/whisperbox && bash scripts/install.sh
```

Expected: Installs brew deps, creates venv, installs Python packages, creates default config.

- [ ] **Step 2: Run all Python tests**

```bash
cd ~/whisperbox/service && ../.venv/bin/python -m pytest tests/ -v
```

Expected: All tests pass.

- [ ] **Step 3: Build the Swift app**

```bash
cd ~/whisperbox && bash scripts/build.sh
```

Expected: Compiles successfully, produces `build/WhisperBox.app`.

- [ ] **Step 4: Run the smoke test**

```bash
cd ~/whisperbox && bash scripts/smoke-test.sh
```

Expected: All checks pass.

- [ ] **Step 5: Launch WhisperBox and test manually**

```bash
open ~/whisperbox/build/WhisperBox.app
```

Expected:
1. Accessibility permission prompt appears — grant it
2. Menu bar shows mic icon
3. Wait ~3s for model to load (first run downloads ~500MB model)
4. Press Ctrl+Shift+Space — toast appears with voice animation
5. Speak a sentence
6. Press Ctrl+Shift+Space again — text is typed into focused app
7. Quit from menu bar

- [ ] **Step 6: Commit any fixes discovered during integration**

```bash
git add -A
git commit -m "fix: integration fixes from first manual test"
```

---

## Summary

| Chunk | Tasks | What it delivers |
|-------|-------|-----------------|
| 1 | 1-2 | Project skeleton, install script, config module |
| 2 | 3-5 | Socket server, audio capture, transcription |
| 3 | 6-8 | Post-processing, text injection, service orchestrator |
| 4 | 9-15 | Swift menu bar app (socket, permissions, toast, preview, hotkeys, main) |
| 5 | 16-18 | Build script, smoke test, end-to-end integration |

**Total: 18 tasks, ~65 steps.** Each task produces a working, committed piece. The Python service (Chunks 1-3) can be developed and tested independently before the Swift app (Chunk 4) connects to it.
