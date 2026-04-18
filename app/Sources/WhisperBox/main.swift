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
    private var isRecording = false
    private var appendMode = false
    private var restartCount = 0
    private let maxRestarts = 3

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

        let recordItem = NSMenuItem(
            title: "Start Recording",
            action: #selector(toggleRecording),
            keyEquivalent: ""
        )
        recordItem.target = self
        menu.addItem(recordItem)

        clearMenuItem = NSMenuItem(
            title: "Clear Buffer",
            action: #selector(clearBuffer),
            keyEquivalent: ""
        )
        clearMenuItem.target = self
        clearMenuItem.isHidden = true  // hidden by default since append_mode defaults to false
        menu.addItem(clearMenuItem)

        menu.addItem(.separator())

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

        case "audio_level":
            let level = event["level"] as? Double ?? 0.0
            toast.updateAudioLevel(level)

        case "recording_stopped":
            isRecording = false
            updateMenuBarIcon(recording: false)
            hotkeyManager.setEscapeEnabled(false)

        case "transcription_complete":
            let text = event["text"] as? String ?? ""
            let preview = event["preview"] as? Bool ?? false
            let isAppend = event["append"] as? Bool ?? false
            let fullText = event["full_text"] as? String ?? text

            if preview {
                previewPanel.show(text: text)
            } else if !text.isEmpty {
                if isAppend {
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

            toast.showTranscribed(text: text)

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
            clearMenuItem.isHidden = !appendMode

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
