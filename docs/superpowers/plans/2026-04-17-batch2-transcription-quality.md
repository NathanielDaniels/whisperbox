# Batch 2 — Transcription Quality Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add smart line breaks (spoken "new line"/"new paragraph" → actual whitespace) and append mode (consecutive dictations accumulate text) to WhisperBox.

**Architecture:** Smart line breaks is a pure Python postprocessor change — a phrase map runs before capitalize/punctuate. Append mode adds a buffer to the Python service and a small protocol change (new `full_text` and `append` fields in the `transcription_complete` event), with Swift handling the space-prepend and clipboard update. The two features are independent.

**Tech Stack:** Python 3.12, Swift (AppKit, CGEvent), Unix domain sockets (newline-delimited JSON)

**Spec:** `docs/superpowers/specs/2026-04-17-batch2-transcription-quality.md`

---

## File Structure

**Modified files:**
- `service/config.py` — add `smart_line_breaks` and `append_mode` defaults
- `service/postprocess.py` — add line break phrase replacement step
- `service/service.py` — append buffer management, send `full_text`/`append` in event, clear on cancel, send `append_mode` in config event
- `app/Sources/WhisperBox/main.swift` — handle `append`/`full_text` fields, prepend space, "Clear Buffer" menu item

**Test files:**
- `service/tests/test_postprocess.py` — new tests for line break replacement
- `service/tests/test_service.py` — new tests for append buffer behavior

---

## Chunk 1: Smart Line Breaks

### Task 1: Add config default and line break replacement to postprocessor

**Files:**
- Modify: `service/config.py`
- Modify: `service/postprocess.py`
- Modify: `service/tests/test_postprocess.py`

- [ ] **Step 1: Write failing test for "new line" replacement**

In `service/tests/test_postprocess.py`, add:

```python
def test_new_line_replacement():
    result = postprocess("first line new line second line", smart_line_breaks=True)
    assert result == "First line\nSecond line."


def test_new_paragraph_replacement():
    result = postprocess("first paragraph new paragraph second paragraph", smart_line_breaks=True)
    assert result == "First paragraph\n\nSecond paragraph."
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /Users/nathaniel/whisperbox/service && python -m pytest tests/test_postprocess.py::test_new_line_replacement tests/test_postprocess.py::test_new_paragraph_replacement -v`
Expected: FAIL — `postprocess()` does not accept `smart_line_breaks` parameter

- [ ] **Step 3: Add `smart_line_breaks` to DEFAULT_CONFIG**

In `service/config.py`, change:

```python
"postprocessing": {
    "strip_fillers": True,
    "auto_capitalize": True,
    "auto_punctuate": True,
},
```
to:
```python
"postprocessing": {
    "strip_fillers": True,
    "auto_capitalize": True,
    "auto_punctuate": True,
    "smart_line_breaks": True,
},
```

- [ ] **Step 4: Implement line break replacement in postprocess.py**

In `service/postprocess.py`, add the phrase map and update the function:

```python
import re

FILLER_WORDS = {"um", "uh", "er", "ah"}
FILLER_PATTERN = re.compile(
    r"\b(" + "|".join(re.escape(w) for w in FILLER_WORDS) + r")\b",
    re.IGNORECASE,
)

# Line break phrases — order matters: "new paragraph" must match before "new line"
LINE_BREAK_PHRASES = [
    (re.compile(r"\bnew\s+paragraph\b", re.IGNORECASE), "\n\n"),
    (re.compile(r"\bnew\s+line\b", re.IGNORECASE), "\n"),
]


def postprocess(
    text: str,
    capitalize: bool = True,
    punctuate: bool = True,
    strip_fillers: bool = True,
    smart_line_breaks: bool = False,
) -> str:
    """Clean up transcribed text."""
    text = text.strip()
    if not text:
        return ""

    if strip_fillers:
        text = FILLER_PATTERN.sub("", text)
        text = re.sub(r"\s+", " ", text).strip()

    if not text:
        return ""

    if smart_line_breaks:
        for pattern, replacement in LINE_BREAK_PHRASES:
            text = pattern.sub(replacement, text)
        # Clean up spaces around line breaks
        text = re.sub(r" *\n *", "\n", text)

    if capitalize and text:
        # Capitalize first letter and first letter after each line break
        lines = text.split("\n")
        lines = [line[0].upper() + line[1:] if line else line for line in lines]
        text = "\n".join(lines)

    if punctuate and text and text[-1] not in ".!?\n":
        text += "."

    return text
```

- [ ] **Step 5: Run the new tests to verify they pass**

Run: `cd /Users/nathaniel/whisperbox/service && python -m pytest tests/test_postprocess.py::test_new_line_replacement tests/test_postprocess.py::test_new_paragraph_replacement -v`
Expected: PASS

- [ ] **Step 6: Write additional edge case tests**

In `service/tests/test_postprocess.py`, add:

```python
def test_line_break_case_insensitive():
    result = postprocess("hello New Line world", smart_line_breaks=True)
    assert result == "Hello\nWorld."


def test_multiple_line_breaks():
    result = postprocess("one new line two new line three", smart_line_breaks=True)
    assert result == "One\nTwo\nThree."


def test_line_breaks_disabled_by_default():
    """With smart_line_breaks=False (default), phrases pass through literally."""
    result = postprocess("hello new line world")
    assert result == "Hello new line world."


def test_line_break_with_fillers():
    result = postprocess("um first um new line second", strip_fillers=True, smart_line_breaks=True)
    assert result == "First\nSecond."
```

- [ ] **Step 7: Run all postprocess tests**

Run: `cd /Users/nathaniel/whisperbox/service && python -m pytest tests/test_postprocess.py -v`
Expected: All pass

- [ ] **Step 8: Update service.py to pass smart_line_breaks to postprocess**

In `service/service.py`, update the `postprocess` call in `_stop_and_transcribe` (around line 116):

Change:
```python
text = postprocess(
    raw_text,
    capitalize=pp.get("auto_capitalize", True),
    punctuate=pp.get("auto_punctuate", True),
    strip_fillers=pp.get("strip_fillers", True),
)
```
to:
```python
text = postprocess(
    raw_text,
    capitalize=pp.get("auto_capitalize", True),
    punctuate=pp.get("auto_punctuate", True),
    strip_fillers=pp.get("strip_fillers", True),
    smart_line_breaks=pp.get("smart_line_breaks", True),
)
```

- [ ] **Step 9: Commit**

```bash
cd /Users/nathaniel/whisperbox
git add service/config.py service/postprocess.py service/service.py service/tests/test_postprocess.py
git commit -m "feat: smart line breaks — convert spoken 'new line'/'new paragraph' to whitespace"
```

---

## Chunk 2: Append Mode

### Task 2: Add append buffer to Python service

**Files:**
- Modify: `service/config.py`
- Modify: `service/service.py`

- [ ] **Step 1: Add `append_mode` to DEFAULT_CONFIG**

In `service/config.py`, change:

```python
"behavior": {
    "mode": "instant",
    "sound_feedback": True,
    "max_duration": 300,
    "silence_timeout": 10,
},
```
to:
```python
"behavior": {
    "mode": "instant",
    "sound_feedback": True,
    "max_duration": 300,
    "silence_timeout": 10,
    "append_mode": False,
},
```

- [ ] **Step 2: Add append buffer to WhisperBoxService.__init__**

In `service/service.py`, add after `self._duration_timer` init (around line 47):

```python
self._append_buffer: list[str] = []
```

- [ ] **Step 3: Update _stop_and_transcribe to use append buffer**

In `service/service.py`, update the event-sending section of `_stop_and_transcribe`. Replace the block that sends `transcription_complete` (around line 122-132):

```python
            mode = self._config["behavior"].get("mode", "instant")
            append_mode = self._config["behavior"].get("append_mode", False)

            event = {
                "event": "transcription_complete",
                "text": text,
                "preview": mode == "preview",
            }

            if append_mode:
                self._append_buffer.append(text)
                event["full_text"] = " ".join(self._append_buffer)
                event["append"] = len(self._append_buffer) > 1

            await self._send_event(event)
```

- [ ] **Step 4: Clear buffer on cancel**

In `service/service.py`, update `_cancel_recording` to clear the buffer. Add after `self._state = "idle"`:

```python
self._append_buffer.clear()
```

- [ ] **Step 5: Add clear_buffer command handler**

In `service/service.py`, add a new case in `_handle_command` after the `reload_config` case:

```python
elif action == "clear_buffer":
    self._append_buffer.clear()
```

- [ ] **Step 6: Send append_mode in config event**

In `service/service.py`, update `_on_client_connected` to include append_mode:

```python
async def _on_client_connected(self):
    """Send current config to the Swift app on connect."""
    hk = self._config["hotkey"]
    bc = self._config["behavior"]
    await self._send_event({
        "event": "config",
        "hotkey_combo": hk.get("combo", "ctrl+shift+space"),
        "sound_feedback": bc.get("sound_feedback", True),
        "append_mode": bc.get("append_mode", False),
    })
```

- [ ] **Step 7: Commit Python changes**

```bash
cd /Users/nathaniel/whisperbox
git add service/config.py service/service.py
git commit -m "feat: append mode buffer in Python service"
```

### Task 3: Handle append mode in Swift

**Files:**
- Modify: `app/Sources/WhisperBox/main.swift`

- [ ] **Step 1: Add append mode state to AppDelegate**

In `app/Sources/WhisperBox/main.swift`, add after `private var isRecording = false` (around line 25):

```swift
private var appendMode = false
```

- [ ] **Step 2: Update config event handler**

In `handleServiceEvent`, update the `"config"` case:

```swift
case "config":
    let combo = event["hotkey_combo"] as? String ?? "ctrl+shift+space"
    if combo != "ctrl+shift+space" {
        if !hotkeyManager.registerFromString(combo) {
            log("Failed to parse hotkey combo '\(combo)', using default")
        }
    }
    appendMode = event["append_mode"] as? Bool ?? false
```

- [ ] **Step 3: Update transcription_complete handler for append mode**

In `handleServiceEvent`, update the `"transcription_complete"` case:

```swift
case "transcription_complete":
    let text = event["text"] as? String ?? ""
    let preview = event["preview"] as? Bool ?? false
    let isAppend = event["append"] as? Bool ?? false
    let fullText = event["full_text"] as? String ?? text

    if preview {
        previewPanel.show(text: text)
    } else if !text.isEmpty {
        if isAppend {
            injectText(" " + text)
        } else {
            injectText(text)
        }
    }

    // In append mode, clipboard gets the full accumulated text
    if appendMode && !fullText.isEmpty {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(fullText, forType: .string)
    }

    toast.showTranscribed(text: text)
```

- [ ] **Step 4: Add "Clear Buffer" menu item**

In `buildMenu()`, add after the record item and before the separator (around line 78):

```swift
let clearItem = NSMenuItem(
    title: "Clear Buffer",
    action: #selector(clearBuffer),
    keyEquivalent: ""
)
clearItem.target = self
menu.addItem(clearItem)
```

Add the action method (in the `// MARK: - Actions` section):

```swift
@objc private func clearBuffer() {
    socketClient.sendCommand(["cmd": "clear_buffer"])
}
```

- [ ] **Step 5: Build Swift app**

Run: `cd /Users/nathaniel/whisperbox/app && swift build`
Expected: Build complete

- [ ] **Step 6: Commit Swift changes**

```bash
cd /Users/nathaniel/whisperbox
git add app/Sources/WhisperBox/main.swift
git commit -m "feat: append mode support in Swift — space prepend, full clipboard, clear buffer"
```

---

## Final: Test and deploy

- [ ] **Step 1: Run all Python tests**

Run: `cd /Users/nathaniel/whisperbox/service && python -m pytest tests/ -v`
Expected: All pass

- [ ] **Step 2: Full rebuild**

Run: `cd /Users/nathaniel/whisperbox && bash build.sh`
Expected: Build succeeds with stable signing

- [ ] **Step 3: Deploy and smoke test**

```bash
pkill -f WhisperBox 2>/dev/null; pkill -f "whisperbox/service" 2>/dev/null
sleep 1 && rm -f ~/.local/share/whisperbox/whisperbox.sock
open /Applications/WhisperBox.app
```

Verify:
1. Dictate "hello new line world" → output has actual line break
2. Enable append mode in config.toml (`behavior.append_mode = true`)
3. Dictate twice → second injection has space prefix, clipboard has full text
4. Click "Clear Buffer" → next dictation starts fresh
5. Press Escape during recording → buffer clears

- [ ] **Step 4: Update roadmap**

In `docs/superpowers/specs/2026-04-17-upgrade-roadmap.md`, mark items 5 and 6 as done.
