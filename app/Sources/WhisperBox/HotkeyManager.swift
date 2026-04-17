// app/Sources/WhisperBox/HotkeyManager.swift
import AppKit
import HotKey
import Carbon.HIToolbox

/// Manages global keyboard shortcuts for WhisperBox.
/// Default: Ctrl+Shift+Space (hold to record), Escape to cancel.
class HotkeyManager {
    private var recordHotKey: HotKey?
    private var escapeHotKey: HotKey?

    var onRecordStart: (() -> Void)?
    var onRecordStop: (() -> Void)?
    var onCancel: (() -> Void)?

    func register() {
        registerCombo(key: .space, modifiers: [.control, .shift])
    }

    func registerCombo(key: Key, modifiers: NSEvent.ModifierFlags) {
        recordHotKey = HotKey(key: key, modifiers: modifiers)
        recordHotKey?.keyDownHandler = { [weak self] in
            self?.onRecordStart?()
        }
        recordHotKey?.keyUpHandler = { [weak self] in
            self?.onRecordStop?()
        }
    }

    /// Parse a combo string like "ctrl+shift+space" and reregister.
    /// Returns true if parsing succeeded, false if it fell back to default.
    @discardableResult
    func registerFromString(_ combo: String) -> Bool {
        let parts = combo.lowercased().split(separator: "+").map(String.init)
        guard parts.count >= 2 else { return false }

        var modifiers: NSEvent.ModifierFlags = []
        var keyPart: String?

        for part in parts {
            switch part {
            case "ctrl", "control":
                modifiers.insert(.control)
            case "shift":
                modifiers.insert(.shift)
            case "cmd", "command":
                modifiers.insert(.command)
            case "option", "alt":
                modifiers.insert(.option)
            default:
                keyPart = part
            }
        }

        guard let keyString = keyPart, let key = Self.parseKey(keyString) else {
            return false
        }

        registerCombo(key: key, modifiers: modifiers)
        return true
    }

    private static func parseKey(_ s: String) -> Key? {
        switch s {
        case "space": return .space
        case "return", "enter": return .return
        case "tab": return .tab
        case "escape", "esc": return .escape
        case "delete", "backspace": return .delete
        case "f1": return .f1
        case "f2": return .f2
        case "f3": return .f3
        case "f4": return .f4
        case "f5": return .f5
        case "f6": return .f6
        case "f7": return .f7
        case "f8": return .f8
        case "f9": return .f9
        case "f10": return .f10
        case "f11": return .f11
        case "f12": return .f12
        default:
            if s.count == 1, let char = s.first {
                return Key(string: String(char))
            }
            return nil
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
        recordHotKey = nil
        escapeHotKey = nil
    }
}
