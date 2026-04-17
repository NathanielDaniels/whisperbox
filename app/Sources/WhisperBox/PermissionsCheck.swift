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

    /// Check accessibility status without prompting.
    /// Log a message if not granted so the user knows.
    static func promptIfNeeded() {
        if !isAccessibilityGranted {
            print("[WhisperBox] Accessibility not granted — hotkeys may not work. Grant access in System Settings > Privacy & Security > Accessibility.")
        }
    }
}
