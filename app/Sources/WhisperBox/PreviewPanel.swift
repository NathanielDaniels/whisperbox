// app/Sources/WhisperBox/PreviewPanel.swift
import AppKit
import SwiftUI
import Carbon.HIToolbox

/// Native macOS panel for preview mode — shows transcription text,
/// Enter to confirm and paste, Escape to discard.
class PreviewPanel {
    private var window: NSPanel?
    private var panelState = PreviewPanelState()
    private var eventMonitor: Any?
    var onConfirm: ((String) -> Void)?
    var onDiscard: (() -> Void)?

    func show(text: String) {
        panelState.text = text

        let view = PreviewPanelView(state: panelState, onConfirm: { [weak self] in
            self?.confirm()
        }, onDiscard: { [weak self] in
            self?.discard()
        })

        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: 400, height: 150)

        let panel = NSPanel(
            contentRect: hosting.frame,
            styleMask: [.nonactivatingPanel, .titled, .closable, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.contentView = hosting
        panel.title = "WhisperBox Preview"

        // Center on screen
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.midX - hosting.frame.width / 2
            let y = screenFrame.midY - hosting.frame.height / 2
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        panel.makeKeyAndOrderFront(nil)
        self.window = panel

        // Monitor for Enter/Escape keys (store reference for cleanup)
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard self?.window != nil else { return event }
            if event.keyCode == UInt16(kVK_Return) {
                self?.confirm()
                return nil
            } else if event.keyCode == UInt16(kVK_Escape) {
                self?.discard()
                return nil
            }
            return event
        }
    }

    private func confirm() {
        let text = panelState.text
        hide()
        onConfirm?(text)
    }

    private func discard() {
        hide()
        onDiscard?()
    }

    func hide() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        window?.orderOut(nil)
        window = nil
    }
}

class PreviewPanelState: ObservableObject {
    @Published var text: String = ""
}

struct PreviewPanelView: View {
    @ObservedObject var state: PreviewPanelState
    var onConfirm: () -> Void
    var onDiscard: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Text(state.text)
                .font(.system(size: 14))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(6)

            HStack {
                Text("Enter to paste · Escape to discard")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Spacer()
                Button("Discard") { onDiscard() }
                    .keyboardShortcut(.escape, modifiers: [])
                Button("Paste") { onConfirm() }
                    .keyboardShortcut(.return, modifiers: [])
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .frame(width: 400)
    }
}
