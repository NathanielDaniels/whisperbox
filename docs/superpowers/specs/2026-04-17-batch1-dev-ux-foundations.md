# Batch 1 — Dev & UX Foundations

**Date:** 2026-04-17
**Status:** Approved

## Overview

Four upgrades to WhisperBox's development workflow and user experience. These are foundational — stable signing unblocks rapid iteration, and the other three wire up config values that already exist but aren't implemented.

## 1. Stable Code Signing

**Problem:** Ad-hoc signing (`codesign --sign -`) produces a different identity per build. macOS silently invalidates Accessibility trust, requiring manual re-grant after every rebuild.

**Solution:**
- Create `scripts/create-cert.sh` that generates a self-signed certificate named `WhisperBox Dev` in the login keychain (no-op if it already exists)
- Update `build.sh` to sign with `codesign --force --sign "WhisperBox Dev"` instead of `--sign -`
- Accessibility permission persists across rebuilds because the signing identity is stable

**Files:**
- New: `scripts/create-cert.sh`
- Modified: `build.sh`

## 2. Sound Feedback

**Problem:** `behavior.sound_feedback` defaults to `true` in config but is never read. No audible cue on recording start/stop.

**Solution:**
- Python includes `"sound_feedback": true/false` in `recording_started` and `recording_stopped` events (reads from config)
- Swift plays system sounds when the flag is true:
  - Recording start: `NSSound(named: "Tink")`
  - Recording stop: `NSSound(named: "Pop")`
- No sound on cancel (Escape) — silence communicates "discarded"

**Files:**
- Modified: `service/service.py` (add flag to events)
- Modified: `app/Sources/WhisperBox/main.swift` (play sounds on events)

## 3. Configurable Hotkey

**Problem:** `hotkey.combo` is `"ctrl+shift+space"` in config but Swift hardcodes the key combination.

**Solution:**
- Python sends a `config` event on socket connect with relevant settings including the hotkey combo string
- Swift parses the combo string into `Key` + modifier flags:
  - Supported modifiers: `ctrl`, `shift`, `cmd`/`command`, `option`/`alt`
  - Key: any single character or named key (`space`, `return`, `tab`, `f1`-`f12`)
- `HotkeyManager` gets a `reregister(key:modifiers:)` method to swap hotkeys at runtime
- Falls back to `ctrl+shift+space` if parsing fails

**Config event format:**
```json
{"event": "config", "hotkey_combo": "ctrl+shift+space", "sound_feedback": true}
```

**Files:**
- Modified: `service/service.py` (send config event after client connects)
- Modified: `service/socket_server.py` (notify service on client connect)
- Modified: `app/Sources/WhisperBox/main.swift` (handle config event)
- Modified: `app/Sources/WhisperBox/HotkeyManager.swift` (parse combo, reregister)

## 4. Multi-language Auto-detect

**Problem:** Transcriber always passes `language="en"`. Users speaking other languages must manually edit config.

**Solution:**
- Change `DEFAULT_CONFIG` language from `"en"` to `"auto"`
- In `Transcriber.transcribe()`, when language is `"auto"`, pass empty string to whisper.cpp (triggers built-in language detection)
- Include detected language in `transcription_complete` event for informational display in toast

**Files:**
- Modified: `service/config.py` (change default)
- Modified: `service/transcriber.py` (handle "auto" value)
- Modified: `service/service.py` (pass detected language in event)

## Implementation Order

1. Stable code signing (unblocks frictionless development)
2. Multi-language auto-detect (smallest change, immediate value)
3. Sound feedback (straightforward, no architectural changes)
4. Configurable hotkey (most complex — new event type, string parser)
