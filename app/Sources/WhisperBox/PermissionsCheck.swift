// app/Sources/WhisperBox/PermissionsCheck.swift
import AppKit
import ApplicationServices

/// Checks and prompts for Accessibility permission, required for
/// global hotkeys (CGEvent taps) and text injection (synthetic paste).
struct PermissionsCheck {

    /// Returns true if the app has Accessibility permission.
    static var isAccessibilityGranted: Bool {
        AXIsProcessTrusted()
    }

    /// Prompt the user to grant Accessibility if not already granted.
    /// This triggers the macOS system dialog on first run.
    static func promptIfNeeded() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        if !trusted {
            print("[WhisperBox] Accessibility not granted — text injection requires access. Grant in System Settings > Privacy & Security > Accessibility.")
        }
    }
}
