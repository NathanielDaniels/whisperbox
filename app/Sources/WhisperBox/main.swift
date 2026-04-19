// app/Sources/WhisperBox/main.swift
import AppKit
import SwiftUI

func log(_ message: String) {
    let path = NSString(string: "~/.local/share/whisperbox/app.log").expandingTildeInPath
    let line = "\(Date()): \(message)\n"
    if let handle = FileHandle(forWritingAtPath: path) {
        handle.seekToEndOfFile()
        handle.write(line.data(using: .utf8)!)
        handle.closeFile()
    } else {
        FileManager.default.createFile(atPath: path, contents: line.data(using: .utf8))
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var socketClient: SocketClient!
    private var hotkeyManager: HotkeyManager!
    private var toast: ToastOverlay!
    private var previewPanel: PreviewPanel!
    private var pythonProcess: Process?
    private var clearMenuItem: NSMenuItem!
    private var appendMenuItem: NSMenuItem!
    private var muteMenuItem: NSMenuItem!
    private var historyMenu: NSMenu!
    private var isRecording = false
    private var appendMode = false
    private var pauseMediaEnabled = true
    private var transcriptionHistory: [String] = []
    private let maxHistoryItems = 10
    private var restartCount = 0
    private let maxRestarts = 3
    private var didMuteAudio = false
    private var wasMutedBefore = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Check accessibility permission
        PermissionsCheck.promptIfNeeded()

        setupMenuBar()
        setupHotkeys()
        setupSocket()
        setupPreviewPanel()
        startPythonService()

        toast = ToastOverlay()
    }

    // MARK: - Menu Bar

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateMenuBarIcon(recording: false)
        buildMenu()
    }

    private func updateMenuBarIcon(recording: Bool) {
        if let button = statusItem.button {
            let symbolName = recording ? "mic.fill" : "mic"
            let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "WhisperBox")
            image?.isTemplate = !recording
            if recording {
                button.contentTintColor = .systemRed
            } else {
                button.contentTintColor = nil
            }
            button.image = image
        }
        // Update menu item title
        if let menu = statusItem.menu, let recordItem = menu.items.first {
            recordItem.title = recording ? "Stop Recording" : "Start Recording"
        }
    }

    private func buildMenu() {
        let menu = NSMenu()

        // Record
        let recordItem = NSMenuItem(
            title: "Start Recording",
            action: #selector(toggleRecording),
            keyEquivalent: ""
        )
        recordItem.target = self
        menu.addItem(recordItem)

        menu.addItem(.separator())

        // Toggles
        appendMenuItem = NSMenuItem(
            title: "Append Mode",
            action: #selector(toggleAppendMode),
            keyEquivalent: ""
        )
        appendMenuItem.target = self
        menu.addItem(appendMenuItem)

        clearMenuItem = NSMenuItem(
            title: "Clear Buffer",
            action: #selector(clearBuffer),
            keyEquivalent: ""
        )
        clearMenuItem.target = self
        clearMenuItem.isHidden = true
        menu.addItem(clearMenuItem)

        muteMenuItem = NSMenuItem(
            title: "Mute During Recording",
            action: #selector(toggleMuteDuringRecording),
            keyEquivalent: ""
        )
        muteMenuItem.target = self
        menu.addItem(muteMenuItem)

        updateToggleIcons()

        menu.addItem(.separator())

        // Dictation history
        historyMenu = NSMenu()
        let historyItem = NSMenuItem(title: "Dictation History", action: nil, keyEquivalent: "")
        historyItem.submenu = historyMenu
        updateHistoryMenu()
        menu.addItem(historyItem)

        // Model submenu
        let modelMenu = NSMenu()
        for model in ["tiny", "base", "small", "medium", "large-v3"] {
            let item = NSMenuItem(title: model, action: #selector(switchModel(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = model
            modelMenu.addItem(item)
        }
        let modelItem = NSMenuItem(title: "Model", action: nil, keyEquivalent: "")
        modelItem.submenu = modelMenu
        menu.addItem(modelItem)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(
            title: "Settings...",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit WhisperBox",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    private func updateHistoryMenu() {
        historyMenu.removeAllItems()
        if transcriptionHistory.isEmpty {
            let emptyItem = NSMenuItem(title: "No history", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            historyMenu.addItem(emptyItem)
        } else {
            for (i, text) in transcriptionHistory.reversed().enumerated() {
                let preview = text.count > 50 ? String(text.prefix(50)) + "..." : text
                let item = NSMenuItem(title: preview, action: #selector(copyHistoryItem(_:)), keyEquivalent: "")
                item.target = self
                item.tag = transcriptionHistory.count - 1 - i
                historyMenu.addItem(item)
            }
            historyMenu.addItem(.separator())
            let clearItem = NSMenuItem(title: "Clear History", action: #selector(clearHistory), keyEquivalent: "")
            clearItem.target = self
            historyMenu.addItem(clearItem)
        }
    }

    private func addToHistory(_ text: String) {
        guard !text.isEmpty else { return }
        transcriptionHistory.append(text)
        if transcriptionHistory.count > maxHistoryItems {
            transcriptionHistory.removeFirst()
        }
        updateHistoryMenu()
    }

    @objc private func toggleAppendMode() {
        appendMode.toggle()
        clearMenuItem.isHidden = !appendMode
        if !appendMode {
            socketClient.sendCommand(["cmd": "clear_buffer"])
        }
        updateToggleIcons()
    }

    @objc private func toggleMuteDuringRecording() {
        pauseMediaEnabled.toggle()
        updateToggleIcons()
    }

    private func updateToggleIcons() {
        // Append mode: text.append vs text.badge.xmark
        let appendIcon = appendMode ? "text.append" : "text.badge.xmark"
        appendMenuItem.image = NSImage(systemSymbolName: appendIcon, accessibilityDescription: nil)
        appendMenuItem.state = .off  // no checkmark, icon shows state

        // Mute: speaker.slash.fill (muting on) vs speaker.wave.2 (muting off)
        let muteIcon = pauseMediaEnabled ? "speaker.slash.fill" : "speaker.wave.2"
        muteMenuItem.image = NSImage(systemSymbolName: muteIcon, accessibilityDescription: nil)
        muteMenuItem.state = .off  // no checkmark, icon shows state
    }

    @objc private func copyHistoryItem(_ sender: NSMenuItem) {
        let index = sender.tag
        guard index >= 0, index < transcriptionHistory.count else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(transcriptionHistory[index], forType: .string)
    }

    @objc private func clearHistory() {
        transcriptionHistory.removeAll()
        updateHistoryMenu()
    }

    // MARK: - Hotkeys

    private func setupHotkeys() {
        hotkeyManager = HotkeyManager()
        hotkeyManager.onRecordStart = { [weak self] in
            guard self?.isRecording == false else { return }
            self?.startRecording()
        }
        hotkeyManager.onRecordStop = { [weak self] in
            guard self?.isRecording == true else { return }
            self?.stopRecording()
        }
        hotkeyManager.onCancel = { [weak self] in
            guard self?.isRecording == true else { return }
            self?.cancelRecording()
        }
        hotkeyManager.register()
        hotkeyManager.setEscapeEnabled(false)
    }

    // MARK: - Socket

    private func setupSocket() {
        socketClient = SocketClient()
        socketClient.onEvent = { [weak self] event in
            self?.handleServiceEvent(event)
        }
    }

    private func handleServiceEvent(_ event: [String: Any]) {
        guard let eventType = event["event"] as? String else { return }

        switch eventType {
        case "recording_started":
            isRecording = true
            updateMenuBarIcon(recording: true)
            hotkeyManager.setEscapeEnabled(true)
            toast.show()
            if event["sound_feedback"] as? Bool == true {
                SoundPlayer.playRecordStart()
            }
            // Mute after sound plays so the start sound is audible
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                self?.pauseMedia()
            }

        case "audio_level":
            let level = event["level"] as? Double ?? 0.0
            toast.updateAudioLevel(level)

        case "recording_stopped":
            isRecording = false
            updateMenuBarIcon(recording: false)
            hotkeyManager.setEscapeEnabled(false)
            // Unmute before stop sound so it's audible
            resumeMedia()
            if event["sound_feedback"] as? Bool == true {
                SoundPlayer.playRecordStop()
            }

        case "transcription_complete":
            let text = event["text"] as? String ?? ""
            let preview = event["preview"] as? Bool ?? false
            let fullText = event["full_text"] as? String ?? text

            if preview {
                previewPanel.show(text: text)
            } else if !text.isEmpty {
                if needsLeadingSpace() {
                    injectText(" " + text)
                } else {
                    injectText(text)
                }
            }

            // In append mode, clipboard gets the full accumulated text after paste completes
            if appendMode && !fullText.isEmpty {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(fullText, forType: .string)
                }
            }

            if text.isEmpty {
                toast.hide()
            } else {
                toast.showTranscribed(text: text)
                addToHistory(text)
            }

        case "transcription_error":
            let error = event["error"] as? String ?? "Unknown error"
            toast.showError(error)

        case "model_loading":
            let _ = event["model"] as? String ?? ""
            toast.show()

        case "model_loaded":
            toast.showTranscribed(text: "Model ready")

        case "config":
            // Hotkey is registered at startup; only re-register if user changed it
            let combo = event["hotkey_combo"] as? String ?? "ctrl+shift+space"
            if combo != "ctrl+shift+space" {
                if !hotkeyManager.registerFromString(combo) {
                    log("Failed to parse hotkey combo '\(combo)', using default")
                }
            }
            appendMode = event["append_mode"] as? Bool ?? false
            pauseMediaEnabled = event["pause_media"] as? Bool ?? true
            clearMenuItem.isHidden = !appendMode
            updateToggleIcons()

        case "ai_polish_complete":
            let polished = event["text"] as? String ?? ""
            if !polished.isEmpty {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(polished, forType: .string)
                toast.showTranscribed(text: "Polished — ⌘V")
            }

        default:
            break
        }
    }

    // MARK: - Preview

    private func setupPreviewPanel() {
        previewPanel = PreviewPanel()
        previewPanel.onConfirm = { [weak self] text in
            self?.injectText(text)
        }
    }

    // MARK: - Python Service

    private func startPythonService() {
        let whisperboxDir = NSString(string: "~/whisperbox").expandingTildeInPath
        let pythonPath = "\(whisperboxDir)/.venv/bin/python"
        let servicePath = "\(whisperboxDir)/service/service.py"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: pythonPath)
        process.arguments = [servicePath]
        process.currentDirectoryURL = URL(fileURLWithPath: "\(whisperboxDir)/service")
        process.terminationHandler = { [weak self] proc in
            guard let self = self else { return }
            if proc.terminationStatus != 0 && self.restartCount < self.maxRestarts {
                self.restartCount += 1
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    self.startPythonService()
                }
            } else if self.restartCount >= self.maxRestarts {
                DispatchQueue.main.async {
                    self.updateMenuBarIcon(recording: false)
                    // Could show error state in menu bar
                }
            }
        }

        do {
            try process.run()
            pythonProcess = process
            // Wait a moment for the service to start, then connect
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                self.socketClient.connect()
                self.restartCount = 0
            }
        } catch {
            print("Failed to start Python service: \(error)")
        }
    }

    // MARK: - Actions

    private func startRecording() {
        socketClient.sendCommand(["cmd": "start_recording"])
    }

    private func stopRecording() {
        socketClient.sendCommand(["cmd": "stop_recording"])
    }

    @objc private func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    @objc private func clearBuffer() {
        socketClient.sendCommand(["cmd": "clear_buffer"])
    }

    private func cancelRecording() {
        socketClient.sendCommand(["cmd": "cancel_recording"])
        resumeMedia()
    }

    /// Check the character before the cursor in the focused text element.
    /// Returns nil if Accessibility can't read it, "" if at position 0/empty,
    /// or the single character before the cursor.
    private func characterBeforeCursor() -> String? {
        guard let focusedElement = NSWorkspace.shared.frontmostApplication?.processIdentifier else {
            return nil
        }

        let appRef = AXUIElementCreateApplication(focusedElement)
        var focusedUI: AnyObject?
        guard AXUIElementCopyAttributeValue(appRef, kAXFocusedUIElementAttribute as CFString, &focusedUI) == .success else {
            return nil
        }
        let element = focusedUI as! AXUIElement

        // Get the selected text range (cursor position)
        var rangeValue: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeValue) == .success else {
            return nil
        }
        var range = CFRange(location: 0, length: 0)
        guard AXValueGetValue(rangeValue as! AXValue, .cfRange, &range) else {
            return nil
        }

        // Cursor at position 0 — nothing before it
        if range.location == 0 {
            return ""
        }

        // Get the character just before the cursor
        var charRange = CFRange(location: range.location - 1, length: 1)
        guard let axCharRange = AXValueCreate(.cfRange, &charRange) else { return nil }

        // Use parameterized attribute to get string for range
        var charValue: AnyObject?
        guard AXUIElementCopyParameterizedAttributeValue(element, kAXStringForRangeParameterizedAttribute as CFString, axCharRange, &charValue) == .success else {
            return nil
        }

        return charValue as? String
    }

    /// Determine if a space should be prepended before injecting text.
    private func needsLeadingSpace() -> Bool {
        guard let charBefore = characterBeforeCursor() else {
            // Can't read — default to space (safer than no space)
            return true
        }
        if charBefore.isEmpty {
            return false  // At position 0 or empty field
        }
        // Don't add space if there's already whitespace or newline
        return !charBefore.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func injectText(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Simulate Cmd+V via CGEvent
        let source = CGEventSource(stateID: .hidSystemState)
        let vKeyCode: CGKeyCode = 9  // 'v' key

        if let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true),
           let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false) {
            keyDown.flags = .maskCommand
            keyUp.flags = .maskCommand
            keyDown.post(tap: .cgSessionEventTap)
            keyUp.post(tap: .cgSessionEventTap)
        } else {
            log("ERROR: Failed to create CGEvents — check Accessibility permission")
        }
    }

    // MARK: - Audio Mute/Unmute
    //
    // Mutes system audio during recording so media doesn't interfere
    // with Whisper. Restores previous mute state after transcription.
    // Videos keep playing silently — no play/pause state changes.

    private func pauseMedia() {
        guard pauseMediaEnabled, !didMuteAudio else { return }
        // Save current mute state so we don't unmute if user was already muted
        wasMutedBefore = isSystemMuted()
        if !wasMutedBefore {
            setSystemMuted(true)
            didMuteAudio = true
        }
    }

    private func resumeMedia() {
        if didMuteAudio {
            setSystemMuted(false)
            didMuteAudio = false
        }
    }

    private func isSystemMuted() -> Bool {
        let script = NSAppleScript(source: "output muted of (get volume settings)")
        var error: NSDictionary?
        let result = script?.executeAndReturnError(&error)
        return result?.booleanValue ?? false
    }

    private func setSystemMuted(_ muted: Bool) {
        let script = NSAppleScript(source: "set volume output muted \(muted)")
        var error: NSDictionary?
        script?.executeAndReturnError(&error)
    }

    @objc private func switchModel(_ sender: NSMenuItem) {
        guard let model = sender.representedObject as? String else { return }
        socketClient.sendCommand(["cmd": "switch_model", "model": model])
    }

    @objc private func openSettings() {
        let configPath = NSString(string: "~/.config/whisperbox/config.toml").expandingTildeInPath
        NSWorkspace.shared.open(URL(fileURLWithPath: configPath))
    }

    @objc private func quit() {
        pythonProcess?.terminate()
        hotkeyManager.unregister()
        socketClient.disconnect()
        NSApp.terminate(nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        pythonProcess?.terminate()
    }
}

// MARK: - Launch

let app = NSApplication.shared
app.setActivationPolicy(.accessory)  // Menu bar only, no dock icon
let delegate = AppDelegate()
app.delegate = delegate
app.run()
