# AI Post-Processing via Claude API

**Date:** 2026-04-17
**Status:** Approved

## Overview

After transcription and basic post-processing, WhisperBox optionally sends text to Claude for grammar/tone cleanup. The raw text is pasted immediately (zero latency impact), and the polished version lands on the clipboard ~1-2s later with a toast notification. The user can Cmd+A, Cmd+V to replace with the polished version, or just keep the raw text.

## Flow

1. User dictates → Whisper transcribes → `postprocess()` runs → text pastes immediately (existing flow, unchanged)
2. In background: Python sends the post-processed text to Claude API with a configurable system prompt
3. Claude returns polished text
4. Python sends a new socket event (`ai_polish_complete`) to Swift with the polished text
5. Swift updates the clipboard with polished text and shows a toast: "Polished — ⌘V"
6. User can Cmd+A, Cmd+V to replace, or ignore

## Python Side

### New file: `service/ai_polish.py`

`AIPolisher` class with:

- `__init__(config)` — reads `[ai]` config section
- `async polish(text: str) -> str | None` — sends text to Claude, returns polished text or None on failure
- `is_available` property — True if API key is found and `ai.enabled` is True

API key resolution order:
1. macOS Keychain: `security find-generic-password -a whisperbox -s whisperbox-claude-api-key -w`
2. Environment variable: `ANTHROPIC_API_KEY`
3. If neither found, `is_available` returns False — AI processing is silently skipped

Uses the `anthropic` Python SDK with async client (`AsyncAnthropic`).

Default model: `claude-haiku-4-5-20251001` (fast, cheap — configurable to any Claude model).

The system prompt is configurable. Default:
```
Fix grammar and smooth phrasing. Keep the speaker's voice and intent. Do not add or remove meaning. Return only the corrected text with no explanation.
```

API key is resolved once at init time (before the event loop starts), not per-request. This avoids blocking the event loop and is consistent with how `Transcriber` loads models at startup.

Error handling: on any failure (network, auth, rate limit), log a warning and return None — raw text is already pasted, so failure is invisible to the user but debuggable via logs.

### Config: `~/.config/whisperbox/config.toml`

```toml
[ai]
enabled = true
model = "claude-haiku-4-5-20251001"
system_prompt = "Fix grammar and smooth phrasing. Keep the speaker's voice and intent. Do not add or remove meaning. Return only the corrected text with no explanation."
```

All fields optional — defaults are applied from `DEFAULT_CONFIG`.

### Modified: `service/config.py`

Add `ai` section to `DEFAULT_CONFIG`:

```python
"ai": {
    "enabled": True,
    "model": "claude-haiku-4-5-20251001",
    "max_chars": 5000,
    "system_prompt": "Fix grammar and smooth phrasing. Keep the speaker's voice and intent. Do not add or remove meaning. Return only the corrected text with no explanation.",
},
```

### Modified: `service/service.py`

In `_stop_and_transcribe`, after sending the `transcription_complete` event:

```python
# Fire-and-forget AI polish in background — cancel any in-flight polish first
if self._ai_polisher and self._ai_polisher.is_available:
    if self._polish_task and not self._polish_task.done():
        self._polish_task.cancel()
    self._polish_task = asyncio.create_task(self._polish_and_notify(text))
```

New instance variable in `__init__`: `self._polish_task: asyncio.Task | None = None`

New method:

```python
async def _polish_and_notify(self, text: str):
    polished = await self._ai_polisher.polish(text)
    if polished and polished.strip() != text.strip():
        await self._send_event({
            "event": "ai_polish_complete",
            "text": polished,
        })
```

The stale-cancellation ensures that if the user records again before the AI call returns, the old polish is discarded and won't clobber the new text.

`AIPolisher` is instantiated in `__init__` alongside the other components.

## Swift Side

### Modified: `main.swift`

New case in `handleServiceEvent`:

```swift
case "ai_polish_complete":
    let polished = event["text"] as? String ?? ""
    if !polished.isEmpty {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(polished, forType: .string)
        toast.showTranscribed(text: "Polished — ⌘V")
    }
```

No other Swift changes needed.

## Append Mode Interaction

AI polish is **skipped** when append mode is active. Reason: append mode overwrites the clipboard with `full_text` after a 0.3s delay, which would race with the `ai_polish_complete` clipboard write. Since append mode accumulates text across multiple recordings, polishing individual chunks in isolation would also produce inconsistent results. Users who want AI polish should use the default (non-append) mode.

## Preview Mode Interaction

When preview mode is active (`behavior.mode = "preview"`), the raw text is shown in the preview panel — not pasted. AI polish still runs. If the polished version arrives before the user confirms, the clipboard is updated silently (no toast), so if the user copies from the preview panel, they get the original. If they Cmd+V after confirming, they get the polished version. This is acceptable — preview mode users are already reviewing text manually.

## API Key Setup

One-time setup:

```bash
security add-generic-password -a whisperbox -s whisperbox-claude-api-key -w "sk-ant-api03-..."
```

To update:

```bash
security delete-generic-password -a whisperbox -s whisperbox-claude-api-key
security add-generic-password -a whisperbox -s whisperbox-claude-api-key -w "sk-ant-new-key..."
```

## Safety Guards

- **Max input length:** `ai.max_chars` config option (default 5000). Text exceeding this limit skips AI polish — prevents unexpected API costs from long dictations (max_duration is 300s).
- **Stale cancellation:** New recordings cancel any in-flight polish task.
- **No API key = no-op:** Entire feature is invisible if no key is configured.

## Dependencies

Add to `requirements.txt` / venv:
- `anthropic>=0.39.0`

## What Stays the Same

- All existing post-processing (capitalize, punctuate, fillers, line breaks) runs first
- Immediate paste behavior — no latency added
- If AI is disabled or no API key, existing behavior is 100% preserved
- Preview mode, append mode, sound feedback all unaffected

## Files Summary

| File | Action |
|------|--------|
| `service/ai_polish.py` | Create |
| `service/tests/test_ai_polish.py` | Create |
| `service/config.py` | Modify (add `ai` defaults) |
| `service/service.py` | Modify (integrate AIPolisher) |
| `app/Sources/WhisperBox/main.swift` | Modify (handle `ai_polish_complete` event) |
