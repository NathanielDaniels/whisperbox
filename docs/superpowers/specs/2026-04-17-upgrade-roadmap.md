# WhisperBox Upgrade Roadmap

**Date:** 2026-04-17
**Status:** In Progress

## Batch 1 — Dev & UX Foundations
1. ~~Stable code signing~~ — DONE
2. ~~Configurable hotkey~~ — DONE
3. Sound feedback — DEFERRED (NSSound doesn't work in accessory apps, needs AudioToolbox or bundled sound files)
4. ~~Multi-language auto-detect~~ — DONE

## Batch 2 — Transcription Quality
5. Smart punctuation & formatting — detect "new line", "period", "comma" and convert to actual punctuation/formatting
6. Append mode — option to append to existing text instead of replacing clipboard

## Batch 3 — Intelligence Layer
7. Per-app context — different post-processing rules per app (e.g., no capitalization in terminal)
8. AI post-processing via Claude API — grammar, tone, rephrasing

## Batch 4 — Architecture
9. Streaming transcription — show partial results in toast as you speak

## Also Completed (not on original list)
- Hold-to-record (was toggle)
- Text injection moved from Python/osascript to Swift/CGEvent
- Clipboard keeps transcribed text (no restore)
- Menu bar shows Start/Stop correctly
- Deploy target is /Applications/WhisperBox.app
