# Batch 2 — Transcription Quality

**Date:** 2026-04-17
**Status:** Approved

## Overview

Two features that improve dictation output quality: smart line breaks convert spoken "new line" / "new paragraph" into actual whitespace, and append mode lets consecutive dictations build up text across multiple recordings.

## 5. Smart Line Breaks

**Problem:** Whisper handles punctuation well natively, but outputs structural commands literally — saying "new line" produces the text `new line` instead of a line break.

**Solution:**
- Add a phrase replacement step to `postprocess.py` that runs before capitalize/punctuate
- Map spoken phrases to whitespace characters:
  - `"new line"` → `\n`
  - `"new paragraph"` → `\n\n`
- Case-insensitive, whole-word matching
- New config flag: `postprocessing.smart_line_breaks = true` (default)
- After replacement, re-run whitespace normalization (collapse spaces, but preserve the inserted `\n`)
- Auto-capitalize applies to the first character after each line break

**Files:**
- Modified: `service/postprocess.py` (add phrase replacement step)
- Modified: `service/config.py` (add `smart_line_breaks` default)
- Modified: `service/tests/test_postprocess.py` (test line break replacement)

## 6. Append Mode

**Problem:** Each dictation replaces the clipboard and injects independently. When dictating longer text across multiple recordings, there's no way to accumulate and no separator between consecutive injections.

**Solution:**
- Python service maintains an `_append_buffer` (list of transcribed strings)
- When `behavior.append_mode = true`:
  - Each transcription appends to the buffer
  - `transcription_complete` event includes:
    - `text`: the new chunk (for injection)
    - `full_text`: all accumulated text joined with spaces (for clipboard)
    - `append`: `true` flag so Swift knows to prepend a space
  - When `append` is true and buffer has prior content, Swift prepends `" "` before injecting
  - Clipboard is set to `full_text` (the complete accumulated text)
- Buffer clears on:
  - Cancel (Escape key)
  - Explicit "Clear Buffer" menu item in menu bar
  - App quit
- When `behavior.append_mode = false` (default): current behavior — no buffer, no `full_text`, no space prepended
- Config event sends `append_mode` flag to Swift on connect

**Files:**
- Modified: `service/config.py` (add `append_mode` default)
- Modified: `service/service.py` (buffer management, send `full_text` and `append` in event)
- Modified: `app/Sources/WhisperBox/main.swift` (handle `full_text` for clipboard, prepend space, add "Clear Buffer" menu item)
