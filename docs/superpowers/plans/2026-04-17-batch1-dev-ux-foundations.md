# Batch 1 — Dev & UX Foundations Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add stable code signing, multi-language auto-detect, sound feedback, and configurable hotkeys to WhisperBox.

**Architecture:** All four features are independent. Code signing is a build-script-only change. The other three wire up existing config values: auto-detect is a Python-only change in the transcriber, sound feedback adds a flag to socket events and plays sounds in Swift, configurable hotkey sends config over the socket and adds a key parser in Swift.

**Tech Stack:** Swift (AppKit, HotKey, CGEvent), Python 3.12, whisper.cpp via pywhispercpp, Unix domain sockets (newline-delimited JSON)

**Spec:** `docs/superpowers/specs/2026-04-17-batch1-dev-ux-foundations.md`

---

## File Structure

**New files:**
- `scripts/create-cert.sh` — one-time self-signed certificate creation

**Modified files:**
- `build.sh` — use stable signing identity
- `service/config.py` — change default language to "auto"
- `service/transcriber.py` — handle "auto" language value
- `service/service.py` — add sound_feedback flag to events, send config event on connect
- `service/socket_server.py` — add on_client_connected callback
- `app/Sources/WhisperBox/main.swift` — handle config event, play sounds, call injectText from Swift
- `app/Sources/WhisperBox/HotkeyManager.swift` — parse combo string, reregister hotkey
- `service/tests/test_config.py` — test new default
- `service/tests/test_transcriber.py` — test auto-detect

---

## Chunk 1: Stable Code Signing

### Task 1: Create certificate script and update build

**Files:**
- Create: `scripts/create-cert.sh`
- Modify: `build.sh`

- [ ] **Step 1: Create the certificate generation script**

```bash
#!/usr/bin/env bash
set -euo pipefail

CERT_NAME="WhisperBox Dev"

# Check if certificate already exists
if security find-identity -v -p codesigning login.keychain-db 2>/dev/null | grep -q "$CERT_NAME"; then
    echo "Certificate '$CERT_NAME' already exists."
    exit 0
fi

echo "Creating self-signed certificate '$CERT_NAME'..."

# Create a self-signed code signing certificate in the login keychain
cat > /tmp/whisperbox-cert.cfg <<EOF
[ req ]
default_bits       = 2048
distinguished_name = req_dn
prompt             = no
[ req_dn ]
CN = $CERT_NAME
[ extensions ]
keyUsage = digitalSignature
extendedKeyUsage = codeSigning
EOF

# Generate key and cert
openssl req -x509 -newkey rsa:2048 -keyout /tmp/whisperbox-key.pem \
    -out /tmp/whisperbox-cert.pem -days 3650 -nodes \
    -config /tmp/whisperbox-cert.cfg -extensions extensions 2>/dev/null

# Import into login keychain
security import /tmp/whisperbox-cert.pem -k ~/Library/Keychains/login.keychain-db -T /usr/bin/codesign
security import /tmp/whisperbox-key.pem -k ~/Library/Keychains/login.keychain-db -T /usr/bin/codesign

# Clean up temp files
rm -f /tmp/whisperbox-cert.cfg /tmp/whisperbox-key.pem /tmp/whisperbox-cert.pem

echo "Certificate '$CERT_NAME' created successfully."
echo "You may need to trust it: open Keychain Access > find '$CERT_NAME' > Get Info > Trust > Always Trust"
```

- [ ] **Step 2: Make the script executable**

Run: `chmod +x scripts/create-cert.sh`

- [ ] **Step 3: Update build.sh to use the stable identity**

In `build.sh`, change:
```bash
codesign --force --sign - "$APP_BUNDLE"
```
to:
```bash
CERT_NAME="WhisperBox Dev"
if security find-identity -v -p codesigning login.keychain-db 2>/dev/null | grep -q "$CERT_NAME"; then
    codesign --force --sign "$CERT_NAME" "$APP_BUNDLE"
    echo "Signed with '$CERT_NAME' (stable identity)"
else
    codesign --force --sign - "$APP_BUNDLE"
    echo "WARNING: Signed ad-hoc. Run scripts/create-cert.sh for stable signing."
fi
```

- [ ] **Step 4: Test the build**

Run: `cd /Users/nathaniel/whisperbox && bash scripts/create-cert.sh && bash build.sh`
Expected: Build completes with "Signed with 'WhisperBox Dev' (stable identity)"

- [ ] **Step 5: Commit**

```bash
git add scripts/create-cert.sh build.sh
git commit -m "feat: add stable code signing for persistent Accessibility trust"
```

---

## Chunk 2: Multi-language Auto-detect

### Task 2: Update config default and transcriber

**Files:**
- Modify: `service/config.py`
- Modify: `service/transcriber.py`
- Modify: `service/tests/test_config.py`
- Modify: `service/tests/test_transcriber.py`

- [ ] **Step 1: Write failing test for new config default**

In `service/tests/test_config.py`, add:

```python
def test_default_language_is_auto():
    """Default language should be 'auto' for auto-detection."""
    config = load_config("/nonexistent/path/config.toml")
    assert config["transcription"]["language"] == "auto"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/nathaniel/whisperbox/service && python -m pytest tests/test_config.py::test_default_language_is_auto -v`
Expected: FAIL — currently returns `"en"`

- [ ] **Step 3: Update default config**

In `service/config.py`, change:
```python
"transcription": {
    "model": "small",
    "language": "en",
},
```
to:
```python
"transcription": {
    "model": "small",
    "language": "auto",
},
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /Users/nathaniel/whisperbox/service && python -m pytest tests/test_config.py -v`
Expected: All pass

- [ ] **Step 5: Write failing test for auto-detect transcription**

In `service/tests/test_transcriber.py`, add:

```python
@patch("transcriber.Model")
def test_transcribe_auto_language(mock_model_cls):
    """When language is 'auto', pass empty string to whisper for auto-detection."""
    mock_model = MagicMock()
    mock_model.transcribe.return_value = [MagicMock(text="Bonjour")]
    mock_model_cls.return_value = mock_model

    t = Transcriber(model_name="small", models_dir=MODEL_DIR)
    t.load()
    audio = np.zeros(16000, dtype=np.float32)
    t.transcribe(audio, language="auto")

    call_args = mock_model.transcribe.call_args
    assert call_args[1].get("language", call_args[0][1] if len(call_args[0]) > 1 else None) == ""
```

- [ ] **Step 6: Run test to verify it fails**

Run: `cd /Users/nathaniel/whisperbox/service && python -m pytest tests/test_transcriber.py::test_transcribe_auto_language -v`
Expected: FAIL — currently passes `"auto"` literally

- [ ] **Step 7: Implement auto-detect in transcriber**

In `service/transcriber.py`, update the `transcribe` method:

```python
def transcribe(self, audio: np.ndarray, language: str = "en") -> str:
    if self._model is None:
        raise RuntimeError("Model not loaded. Call load() first.")

    # "auto" triggers whisper's built-in language detection
    lang = "" if language == "auto" else language

    segments = self._model.transcribe(audio, language=lang)
    text = " ".join(seg.text.strip() for seg in segments if seg.text.strip())
    return text
```

- [ ] **Step 8: Run all transcriber tests**

Run: `cd /Users/nathaniel/whisperbox/service && python -m pytest tests/test_transcriber.py -v`
Expected: All pass

- [ ] **Step 9: Commit**

```bash
cd /Users/nathaniel/whisperbox
git add service/config.py service/transcriber.py service/tests/test_config.py service/tests/test_transcriber.py
git commit -m "feat: auto-detect language by default instead of hardcoding English"
```

---

## Chunk 3: Sound Feedback

### Task 3: Add sound feedback flag to events and play sounds in Swift

**Files:**
- Modify: `service/service.py`
- Modify: `app/Sources/WhisperBox/main.swift`

- [ ] **Step 1: Add sound_feedback flag to recording events in Python**

In `service/service.py`, update `_start_recording`:

```python
async def _start_recording(self):
    """Begin audio capture."""
    self._state = "recording"
    self._recorder.start()
    await self._send_event({
        "event": "recording_started",
        "sound_feedback": self._config["behavior"].get("sound_feedback", True),
    })
    # ... rest unchanged
```

Update `_stop_and_transcribe` (the first event send):

```python
await self._send_event({
    "event": "recording_stopped",
    "sound_feedback": self._config["behavior"].get("sound_feedback", True),
})
```

Also update `_cancel_recording`:

```python
async def _cancel_recording(self):
    """Cancel recording without transcription."""
    self._cancel_timer()
    self._recorder.cancel()
    self._state = "idle"
    await self._send_event({
        "event": "recording_stopped",
        "sound_feedback": False,  # No sound on cancel
    })
```

- [ ] **Step 2: Play sounds in Swift on recording events**

In `app/Sources/WhisperBox/main.swift`, update the `recording_started` case:

```swift
case "recording_started":
    isRecording = true
    updateMenuBarIcon(recording: true)
    hotkeyManager.setEscapeEnabled(true)
    toast.show()
    if event["sound_feedback"] as? Bool == true {
        NSSound(named: "Tink")?.play()
    }
```

Update the `recording_stopped` case:

```swift
case "recording_stopped":
    isRecording = false
    updateMenuBarIcon(recording: false)
    hotkeyManager.setEscapeEnabled(false)
    if event["sound_feedback"] as? Bool == true {
        NSSound(named: "Pop")?.play()
    }
```

- [ ] **Step 3: Build Swift app**

Run: `cd /Users/nathaniel/whisperbox/app && swift build`
Expected: Build complete

- [ ] **Step 4: Manual test**

Deploy and test:
```bash
cd /Users/nathaniel/whisperbox
pkill -f WhisperBox 2>/dev/null; pkill -f "whisperbox/service" 2>/dev/null
sleep 1 && rm -f ~/.local/share/whisperbox/whisperbox.sock
cp app/.build/debug/WhisperBox build/WhisperBox.app/Contents/MacOS/WhisperBox
open build/WhisperBox.app
```
Expected: Hear "Tink" on key down, "Pop" on key up. No sound on Escape cancel.

- [ ] **Step 5: Commit**

```bash
cd /Users/nathaniel/whisperbox
git add service/service.py app/Sources/WhisperBox/main.swift
git commit -m "feat: add sound feedback on recording start/stop"
```

---

## Chunk 4: Configurable Hotkey

### Task 4: Send config from Python on connect

**Files:**
- Modify: `service/socket_server.py`
- Modify: `service/service.py`

- [ ] **Step 1: Add on_client_connected callback to SocketServer**

In `service/socket_server.py`, add a callback attribute and call it when a client connects:

```python
class SocketServer:
    def __init__(self, sock_path: str):
        self.sock_path = sock_path
        self.on_command: Callable[[dict], None] | None = None
        self.on_client_connected: Callable[[], None] | None = None  # NEW
        self._server: asyncio.AbstractServer | None = None
        self._writer: asyncio.StreamWriter | None = None
        self._running = False
```

In `_handle_client`, add after setting `self._writer`:

```python
async def _handle_client(self, reader, writer):
    self._writer = writer
    # Notify service that a client connected
    if self.on_client_connected:
        result = self.on_client_connected()
        if asyncio.iscoroutine(result):
            await result
    try:
        # ... rest unchanged
```

- [ ] **Step 2: Send config event on client connect in service**

In `service/service.py`, in `__init__`, add after `self._server.on_command = self._handle_command`:

```python
self._server.on_client_connected = self._on_client_connected
```

Add the handler method:

```python
async def _on_client_connected(self):
    """Send current config to the Swift app on connect."""
    hk = self._config["hotkey"]
    bc = self._config["behavior"]
    await self._send_event({
        "event": "config",
        "hotkey_combo": hk.get("combo", "ctrl+shift+space"),
        "sound_feedback": bc.get("sound_feedback", True),
    })
```

- [ ] **Step 3: Commit Python changes**

```bash
cd /Users/nathaniel/whisperbox
git add service/socket_server.py service/service.py
git commit -m "feat: send config event to Swift app on client connect"
```

### Task 5: Parse hotkey combo and reregister in Swift

**Files:**
- Modify: `app/Sources/WhisperBox/HotkeyManager.swift`
- Modify: `app/Sources/WhisperBox/main.swift`

- [ ] **Step 1: Add combo parser and reregister to HotkeyManager**

In `app/Sources/WhisperBox/HotkeyManager.swift`, add a static parser and reregister method:

```swift
import AppKit
import HotKey
import Carbon.HIToolbox

class HotkeyManager {
    private var recordHotKey: HotKey?
    private var escapeHotKey: HotKey?

    var onRecordStart: (() -> Void)?
    var onRecordStop: (() -> Void)?
    var onCancel: (() -> Void)?

    func register() {
        registerCombo(key: .space, modifiers: [.control, .shift])
    }

    func registerCombo(key: Key, modifiers: NSEvent.ModifierFlags) {
        recordHotKey = HotKey(key: key, modifiers: modifiers)
        recordHotKey?.keyDownHandler = { [weak self] in
            self?.onRecordStart?()
        }
        recordHotKey?.keyUpHandler = { [weak self] in
            self?.onRecordStop?()
        }
    }

    /// Parse a combo string like "ctrl+shift+space" and reregister.
    /// Returns true if parsing succeeded, false if it fell back to default.
    @discardableResult
    func registerFromString(_ combo: String) -> Bool {
        let parts = combo.lowercased().split(separator: "+").map(String.init)
        guard parts.count >= 2 else { return false }

        var modifiers: NSEvent.ModifierFlags = []
        var keyPart: String?

        for part in parts {
            switch part {
            case "ctrl", "control":
                modifiers.insert(.control)
            case "shift":
                modifiers.insert(.shift)
            case "cmd", "command":
                modifiers.insert(.command)
            case "option", "alt":
                modifiers.insert(.option)
            default:
                keyPart = part
            }
        }

        guard let keyString = keyPart, let key = Self.parseKey(keyString) else {
            return false
        }

        registerCombo(key: key, modifiers: modifiers)
        return true
    }

    private static func parseKey(_ s: String) -> Key? {
        switch s {
        case "space": return .space
        case "return", "enter": return .return
        case "tab": return .tab
        case "escape", "esc": return .escape
        case "delete", "backspace": return .delete
        case "f1": return .f1
        case "f2": return .f2
        case "f3": return .f3
        case "f4": return .f4
        case "f5": return .f5
        case "f6": return .f6
        case "f7": return .f7
        case "f8": return .f8
        case "f9": return .f9
        case "f10": return .f10
        case "f11": return .f11
        case "f12": return .f12
        default:
            // Single character keys
            if s.count == 1, let char = s.first {
                return Key(string: String(char))
            }
            return nil
        }
    }

    func setEscapeEnabled(_ enabled: Bool) {
        if enabled {
            escapeHotKey = HotKey(key: .escape, modifiers: [])
            escapeHotKey?.keyDownHandler = { [weak self] in
                self?.onCancel?()
            }
        } else {
            escapeHotKey = nil
        }
    }

    func unregister() {
        recordHotKey = nil
        escapeHotKey = nil
    }
}
```

- [ ] **Step 2: Handle config event in main.swift**

In `app/Sources/WhisperBox/main.swift`, add a new case in `handleServiceEvent`:

```swift
case "config":
    let combo = event["hotkey_combo"] as? String ?? "ctrl+shift+space"
    if !hotkeyManager.registerFromString(combo) {
        log("Failed to parse hotkey combo '\(combo)', using default")
    }
```

- [ ] **Step 3: Build Swift app**

Run: `cd /Users/nathaniel/whisperbox/app && swift build`
Expected: Build complete

- [ ] **Step 4: Test with custom hotkey**

Create/edit `~/.config/whisperbox/config.toml`:
```toml
[hotkey]
combo = "cmd+shift+space"
```

Deploy, launch, and verify the new hotkey works. Then revert config to original combo.

- [ ] **Step 5: Commit**

```bash
cd /Users/nathaniel/whisperbox
git add app/Sources/WhisperBox/HotkeyManager.swift app/Sources/WhisperBox/main.swift
git commit -m "feat: configurable hotkey combo via config.toml"
```

---

## Final: Deploy and verify all features

- [ ] **Step 1: Run all Python tests**

Run: `cd /Users/nathaniel/whisperbox/service && python -m pytest tests/ -v`
Expected: All pass

- [ ] **Step 2: Full rebuild with stable signing**

Run: `cd /Users/nathaniel/whisperbox && bash build.sh`
Expected: "Signed with 'WhisperBox Dev' (stable identity)"

- [ ] **Step 3: Deploy and smoke test all features**

```bash
pkill -f WhisperBox 2>/dev/null; pkill -f "whisperbox/service" 2>/dev/null
sleep 1 && rm -f ~/.local/share/whisperbox/whisperbox.sock
open build/WhisperBox.app
```

Verify:
1. Sound plays on record start/stop
2. Hold-to-record works
3. Transcription works (try speaking in another language to test auto-detect)
4. Text injects into focused input
