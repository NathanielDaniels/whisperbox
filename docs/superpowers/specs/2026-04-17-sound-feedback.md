# Sound Feedback

**Date:** 2026-04-17
**Status:** Approved

## Overview

Play short system sounds on recording start/stop to give audible confirmation. Uses AudioToolbox (not NSSound, which doesn't work in accessory-mode apps).

## Design

**New file:** `app/Sources/WhisperBox/SoundPlayer.swift` — thin wrapper around `AudioServicesPlaySystemSound`.

- `playRecordStart()` — plays system sound on recording start (e.g., sound ID 1103 "Tink")
- `playRecordStop()` — plays system sound on recording stop (e.g., sound ID 1104 "Pop")
- No sound on cancel (Escape) — silence communicates "discarded"

**Modified file:** `app/Sources/WhisperBox/main.swift` — call `SoundPlayer` from `handleServiceEvent` in `recording_started` and `recording_stopped` cases, gated on the `sound_feedback` flag already present in those events.

**No changes to:** Python service, `injectText`, clipboard, CGEvent paste flow.

## Constraints

- Must not touch or interfere with text injection path
- `sound_feedback` flag already exists in recording events from Python
- `behavior.sound_feedback` already defaults to `true` in config
