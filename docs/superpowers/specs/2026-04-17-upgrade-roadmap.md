# WhisperBox Upgrade Roadmap

**Date:** 2026-04-17
**Status:** In Progress

## Batch 1 — Dev & UX Foundations
1. ~~Stable code signing~~ — DONE
2. ~~Configurable hotkey~~ — DONE
3. ~~Sound feedback~~ — DONE (AudioToolbox with system .aiff files, not NSSound)
4. ~~Multi-language auto-detect~~ — DONE

## Batch 2 — Transcription Quality
5. ~~Smart line breaks~~ — DONE (scoped down from smart punctuation; converts "new line"/"new paragraph" to actual whitespace)
6. ~~Append mode~~ — DONE (buffer accumulates text, clipboard gets full text, Clear Buffer menu item)

## Batch 3 — Intelligence Layer (deferred)
7. ~~Per-app context~~ — DROPPED (no current pain point; revisit if needed)
8. AI post-processing via Claude API — DEFERRED (spec approved, needs API account)

## Batch 4 — Architecture
9. Streaming transcription — deprioritized; real issue was toast truncation (now fixed)

## Also Completed (not on original list)
- Hold-to-record (was toggle)
- Text injection moved from Python/osascript to Swift/CGEvent
- Clipboard keeps transcribed text (no restore)
- Menu bar shows Start/Stop correctly
- Deploy target is /Applications/WhisperBox.app
- Expandable toast — full transcription text shown, dynamic sizing up to 400px, adaptive display time
