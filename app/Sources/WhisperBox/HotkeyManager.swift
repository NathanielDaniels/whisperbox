// app/Sources/WhisperBox/HotkeyManager.swift
import AppKit
import HotKey
import Carbon.HIToolbox

/// Manages global keyboard shortcuts for WhisperBox.
/// Default: Ctrl+Shift+Space to toggle recording, Escape to cancel.
class HotkeyManager {
    private var toggleHotKey: HotKey?
    private var escapeHotKey: HotKey?

    var onToggle: (() -> Void)?
    var onCancel: (() -> Void)?

    func register() {
        // Ctrl+Shift+Space — always active
        toggleHotKey = HotKey(
            key: .space,
            modifiers: [.control, .shift]
        )
        toggleHotKey?.keyDownHandler = { [weak self] in
            self?.onToggle?()
        }
    }

    /// Register/unregister Escape dynamically — only active during recording.
    /// This avoids intercepting Escape globally when not needed.
    func setEscapeEnabled(_ enabled: Bool) {
        if enabled {
            escapeHotKey = HotKey(key: .escape, modifiers: [])
            escapeHotKey?.keyDownHandler = { [weak self] in
                self?.onCancel?()
            }
        } else {
            escapeHotKey = nil  // unregisters the hotkey
        }
    }

    func unregister() {
        toggleHotKey = nil
        escapeHotKey = nil
    }
}
