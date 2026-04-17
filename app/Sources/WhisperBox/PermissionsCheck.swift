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

    /// Prompt the user to grant Accessibility permission.
    /// Shows an alert explaining why, then opens System Settings.
    static func promptIfNeeded() {
        guard !isAccessibilityGranted else { return }

        let alert = NSAlert()
        alert.messageText = "WhisperBox Needs Accessibility Access"
        alert.informativeText = """
            WhisperBox uses a global keyboard shortcut to start/stop recording, \
            and pastes transcribed text into your apps. Both require Accessibility \
            permission.

            Click "Open Settings" to grant access, then restart WhisperBox.
            """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Quit")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            // Open Accessibility pane in System Settings
            let opts = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true] as CFDictionary
            AXIsProcessTrustedWithOptions(opts)
        } else {
            NSApp.terminate(nil)
        }
    }
}
