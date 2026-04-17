# WhisperBox — Local Voice-to-Text for macOS

**Date:** 2026-04-16
**Status:** Approved

## Overview

WhisperBox is a local, system-wide voice-to-text tool for macOS. It runs Whisper locally on Apple Silicon via whisper.cpp with Metal GPU acceleration. A Swift menu bar app handles UI and hotkey capture; a Python service handles audio recording, transcription, and text injection. Transcribed text is typed into whatever app has focus at the cursor position.

## Architecture

Two processes connected by a Unix domain socket:

```
┌─────────────────────────────────┐
│   Swift Menu Bar Shell          │
│  • Menu bar icon (gray/red)     │
│  • Global hotkey listener       │
│  • Recording toast overlay      │
│  • Launches/manages Python svc  │
│                                 │
│     Unix Domain Socket          │
└────────────────┬────────────────┘
                 │
                 ▼
┌─────────────────────────────────┐
│   Python Transcription Service  │
│  • Audio capture (sounddevice)  │
│  • Transcription (pywhispercpp) │
│  • Post-processing pipeline     │
│  • Text injection (cliclick)    │
└─────────────────────────────────┘
```

### Communication Protocol (Unix Domain Socket)

Socket path: `~/.local/share/whisperbox/whisperbox.sock`

**Framing:** Newline-delimited JSON (one JSON object per line, terminated by `\n`). Newlines within text fields must be escaped as `\n` in the JSON encoding. On startup, remove stale `.sock` file if it exists before binding.

**Swift → Python:**
- `{"cmd": "start_recording"}`
- `{"cmd": "stop_recording"}`
- `{"cmd": "cancel_recording"}` — discard without transcribing (Escape key)
- `{"cmd": "reload_config"}`
- `{"cmd": "switch_model", "model": "medium"}`

**Python → Swift:**
- `{"event": "recording_started"}`
- `{"event": "recording_stopped"}`
- `{"event": "transcription_complete", "text": "...", "preview": true/false}`
- `{"event": "transcription_error", "error": "..."}`
- `{"event": "model_loaded"}`
- `{"event": "model_loading", "model": "..."}` — sent during model switch

## Swift Menu Bar Shell

### Menu Bar Icon
- Mic icon in macOS menu bar
- Gray = idle/ready
- Red = recording

### Dropdown Menu
- Start/Stop Recording
- Settings (opens config.toml in default editor)
- Model: [submenu with model sizes]
- Quit

### Global Hotkey
- Default: `Ctrl+Shift+Space`
- Registered via `HotKey` Swift package (wraps `CGEvent` taps) — NOT `NSEvent.addGlobalMonitorForEvents` which only observes but doesn't consume events
- Toggle behavior: press to start, press again to stop
- Escape while recording = cancel and discard (no transcription)
- Configurable in config.toml

### Permissions
- App requires **Accessibility** permission (for CGEvent hotkey taps and text injection)
- On first launch, check `AXIsProcessTrusted()` and prompt user to grant permission in System Settings if not trusted
- Show a clear onboarding dialog explaining why the permission is needed

### Recording Toast Overlay
- Floating pill/capsule shape, always-on-top, semi-transparent dark background
- Appears near top-center of screen when recording starts
- Animated sound wave bars (3-5 vertical bars pulsing up and down)
- Non-interactive — clicks pass through to app behind it
- On transcription complete: briefly shows "Transcribed!" or first few words, then fades out (~1.5s)
- Fades in on start, fades out on stop

### Process Management
- On app launch: spawns Python service (`~/whisperbox/.venv/bin/python service.py`)
- On app quit: sends SIGTERM to Python service
- Monitor child process: if Python service crashes, restart it automatically (max 3 retries, then show error in menu bar)
- Optional: add to Login Items for auto-start

## Python Transcription Service

### Audio Capture
- Library: `sounddevice`
- Format: 16kHz mono WAV (Whisper's expected input)
- Records to in-memory buffer (no temp files)

### Transcription
- Library: `pywhispercpp` (whisper.cpp Python bindings with Metal support)
- Model loaded once at startup, kept warm in memory
- Default model: `small` (~500MB download, ~2-4s transcription)
- Models stored at `~/.local/share/whisperbox/models/`
- First launch auto-downloads selected model

### Post-Processing Pipeline
1. Capitalize first letter
2. Add period if missing
3. Strip filler words ("um", "uh") — configurable

Note: No audio-level silence trimming — Whisper handles silence robustly. This is text-level cleanup only.

### Text Injection
- **Primary method:** `NSPasteboard` + synthetic `Cmd+V` paste — fast, handles Unicode and long text correctly
- **Fallback:** `cliclick` for character-by-character typing if paste is unavailable
- Saves and restores the user's clipboard before/after injection so we don't clobber their clipboard
- Types text at current cursor/insertion point in focused app
- If text is selected/highlighted, replaces the selection (standard OS behavior)

### Safety Limits
- Maximum recording duration: 5 minutes (configurable), auto-stops with transcription
- Auto-stop on 10 seconds of continuous silence (configurable)

### Preview Mode
- When `mode = "preview"` in config:
  - Preview window is owned by the **Swift shell** (not Python) — renders as a native macOS panel, always-on-top, borderless
  - Python sends transcription text via socket, Swift displays it
  - Enter = confirm and inject text into focused app
  - Escape = discard

## Configuration

Location: `~/.config/whisperbox/config.toml`

```toml
[hotkey]
combo = "ctrl+shift+space"

[transcription]
model = "small"        # tiny, base, small, medium, large-v3
language = "en"

[behavior]
mode = "instant"       # "instant" or "preview"
sound_feedback = true  # beep on start/stop
max_duration = 300     # seconds, auto-stop recording
silence_timeout = 10   # seconds of silence to auto-stop

[postprocessing]
strip_fillers = true   # remove "um", "uh", etc.
auto_capitalize = true
auto_punctuate = true

[indicator]
enabled = true
position = "top-center"  # top-center, top-right, bottom-center
opacity = 0.85
```

## Project Structure

```
~/whisperbox/
├── app/
│   ├── WhisperBox.swift          # Main app entry, menu bar setup
│   ├── HotkeyManager.swift       # Global hotkey registration
│   ├── SocketClient.swift         # IPC with Python service
│   ├── ToastOverlay.swift         # Recording indicator overlay
│   ├── PreviewPanel.swift         # Preview mode confirmation window
│   ├── PermissionsCheck.swift     # Accessibility permission onboarding
│   └── Info.plist                 # App metadata
├── service/
│   ├── service.py                 # Main service entry point
│   ├── audio.py                   # Audio capture module
│   ├── transcriber.py             # Whisper transcription wrapper
│   ├── postprocess.py             # Text cleanup pipeline
│   ├── injector.py                # Text injection via cliclick
│   ├── socket_server.py           # Unix domain socket server
│   └── config.py                  # Config loading
├── scripts/
│   ├── install.sh                 # Brew deps + venv + model download
│   └── build.sh                   # Compile Swift app
├── docs/
│   └── superpowers/specs/
│       └── 2026-04-16-whisperbox-design.md
├── .venv/                         # Python virtual environment
└── build/
    └── WhisperBox.app             # Compiled macOS app
```

## Dependencies

### Homebrew
- `cliclick` — text injection fallback
- `python@3.12` — dedicated Python for venv

### Python (in venv)
- `pywhispercpp` — whisper.cpp bindings with Metal
- `sounddevice` — audio capture
- `tomli` / `tomli-w` — TOML config

## Hardware Target

- Apple M4 Pro, 48GB unified memory
- Can comfortably run any Whisper model size up to large-v3
- Default `small` model for snappy response (~2-4s transcription)

## Launch Flow

1. User opens WhisperBox.app (or auto-starts at login)
2. Swift app spawns Python service
3. Python loads Whisper model into memory (~2-3s)
4. Menu bar icon turns gray = ready
5. Ctrl+Shift+Space → icon turns red, toast appears with voice animation → recording
6. Ctrl+Shift+Space again → recording stops, toast shows processing
7. Transcription completes → text typed at cursor (instant mode) or preview shown
8. Toast briefly shows confirmation, fades out
