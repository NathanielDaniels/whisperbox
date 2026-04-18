# WhisperBox — Local Voice-to-Text for macOS

## What It Is

WhisperBox is a macOS menu bar app that lets you dictate text into any application using a global hotkey. It runs entirely locally — no cloud transcription, no data leaves your machine. Hold the hotkey, speak, release, and your words appear at the cursor.

## How It Works

**Two-process architecture:**

1. **Swift menu bar app** (`app/`) — handles the UI: global hotkey (Ctrl+Shift+Space), floating toast overlay with live audio visualization, text injection via CGEvent paste (Cmd+V), and menu bar controls.

2. **Python transcription service** (`service/`) — handles the backend: captures audio via sounddevice, transcribes with Whisper (whisper.cpp via pywhispercpp), post-processes the text, and communicates with the Swift app over a Unix domain socket.

**The flow:**
1. User holds Ctrl+Shift+Space (configurable)
2. Swift app sends `start_recording` to Python service
3. Python captures 16kHz mono audio, shows live levels in toast
4. User releases hotkey → Python stops recording, runs Whisper
5. Post-processing cleans up the text (capitalize, punctuate, strip filler words, convert "new line"/"new paragraph" to actual line breaks)
6. Text is sent back to Swift and pasted at the cursor via CGEvent Cmd+V
7. Transcribed text stays on clipboard

## Tech Stack

- **Swift** (macOS 13+) — menu bar app, SwiftUI toast, CGEvent text injection
- **Python** — asyncio service, sounddevice for audio, pywhispercpp for transcription
- **IPC** — Unix domain socket with newline-delimited JSON
- **Whisper model** — configurable (tiny/base/small/medium/large-v3), defaults to "small"
- **Config** — TOML at `~/.config/whisperbox/config.toml`

## Features

- **Hold-to-record** — hold hotkey to record, release to transcribe
- **Global hotkey** — works in any app, configurable combo
- **Multi-language auto-detect** — Whisper detects the spoken language automatically
- **Sound feedback** — system sounds on record start/stop (AudioToolbox)
- **Smart line breaks** — say "new line" or "new paragraph" for actual whitespace
- **Append mode** — multiple dictations accumulate; clipboard gets the full text
- **Filler word stripping** — removes "um", "uh", "er", "ah"
- **Expandable toast** — shows full transcription (up to 400px wide, 5 lines), display time scales with text length
- **Preview mode** — optional confirmation before pasting
- **Escape to cancel** — discard recording without pasting
- **Silence detection** — auto-stops after configurable silence timeout
- **Model switching** — swap Whisper models from the menu bar

## Configuration

All settings in `~/.config/whisperbox/config.toml`:

```toml
[hotkey]
combo = "ctrl+shift+space"        # Any modifier+key combo

[transcription]
model = "small"                    # tiny, base, small, medium, large-v3
language = "auto"                  # "auto" for detection, or "en", "es", etc.

[behavior]
mode = "instant"                   # "instant" or "preview"
sound_feedback = true
max_duration = 300                 # Max recording length (seconds)
silence_timeout = 10               # Auto-stop after N seconds of silence
append_mode = true                 # Accumulate text across recordings

[postprocessing]
strip_fillers = true
auto_capitalize = true
auto_punctuate = true
smart_line_breaks = true           # "new line" → \n, "new paragraph" → \n\n
```

## Project Structure

```
~/whisperbox/
  app/                             # Swift menu bar app
    Sources/WhisperBox/
      main.swift                   # App entry point, event handling, text injection
      HotkeyManager.swift          # Global hotkey registration and parsing
      SocketClient.swift           # Unix socket client (JSON protocol)
      ToastOverlay.swift           # Floating recording/transcription indicator
      SoundPlayer.swift            # AudioToolbox sound feedback
      PreviewPanel.swift           # Optional text confirmation UI
      PermissionsCheck.swift       # Accessibility permission onboarding
  service/                         # Python transcription service
    service.py                     # Main orchestrator
    audio.py                       # Audio capture with silence detection
    transcriber.py                 # Whisper wrapper with model management
    postprocess.py                 # Text cleanup pipeline
    injector.py                    # Legacy text injector (unused — Swift handles this now)
    socket_server.py               # Unix socket server
    config.py                      # TOML config loader with defaults
    tests/                         # pytest test suite
```

## Dependencies

**Homebrew:** portaudio (for sounddevice)

**Python (in .venv):** sounddevice, numpy, pywhispercpp

**Swift:** HotKey package (soffes/HotKey)

## Planned (Deferred)

- **AI post-processing** — Claude API polishes grammar/tone in background, updates clipboard with polished version. Spec approved, waiting on API account setup.

## Location

- **Source:** `~/whisperbox/`
- **Deployed app:** `/Applications/WhisperBox.app`
- **Config:** `~/.config/whisperbox/config.toml`
- **Data/logs:** `~/.local/share/whisperbox/`
- **Models:** `~/.local/share/whisperbox/models/`
