// app/Sources/WhisperBox/ToastOverlay.swift
import AppKit
import SwiftUI

/// Floating recording indicator with animated sound wave bars.
class ToastOverlay {
    private var window: NSWindow?
    private var hostingView: NSHostingView<ToastView>?
    private var toastState = ToastState()

    func show() {
        guard window == nil else {
            toastState.isRecording = true
            toastState.statusText = "Listening..."
            return
        }

        toastState.isRecording = true
        toastState.statusText = "Listening..."

        let view = ToastView(state: toastState)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: 200, height: 50)

        let window = NSPanel(
            contentRect: hosting.frame,
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        window.isFloatingPanel = true
        window.level = .floating
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.contentView = hosting

        // Position at top-center of main screen
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.midX - hosting.frame.width / 2
            let y = screenFrame.maxY - hosting.frame.height - 20
            window.setFrameOrigin(NSPoint(x: x, y: y))
        }

        window.alphaValue = 0
        window.orderFront(nil)

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.3
            window.animator().alphaValue = 1.0
        }

        self.window = window
        self.hostingView = hosting
    }

    func showTranscribed(text: String) {
        toastState.isRecording = false
        toastState.statusText = text.isEmpty ? "Transcribed!" : text
        resizeToFit()

        // Longer text gets more reading time (1.5s base + 0.5s per 50 chars)
        let displayTime = 1.5 + Double(text.count / 50) * 0.5
        DispatchQueue.main.asyncAfter(deadline: .now() + displayTime) { [weak self] in
            self?.hide()
        }
    }

    func updateAudioLevel(_ level: Double) {
        toastState.audioLevel = level
    }

    func showError(_ message: String) {
        toastState.isRecording = false
        toastState.statusText = message

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.hide()
        }
    }

    private func resizeToFit() {
        guard let window = self.window, let hosting = self.hostingView else { return }

        // Expand hosting view to max width so SwiftUI can lay out text at full width,
        // then ask for fittingSize to get the actual needed dimensions
        hosting.frame = NSRect(x: 0, y: 0, width: 400, height: 500)
        hosting.layoutSubtreeIfNeeded()
        let fittingSize = hosting.fittingSize
        hosting.frame = NSRect(x: 0, y: 0, width: fittingSize.width, height: fittingSize.height)

        // Re-center horizontally, keep at top of screen
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.midX - fittingSize.width / 2
            let y = screenFrame.maxY - fittingSize.height - 20
            window.setFrame(NSRect(x: x, y: y, width: fittingSize.width, height: fittingSize.height), display: true, animate: true)
        }
    }

    func hide() {
        guard let window = self.window else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.3
            window.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            window.orderOut(nil)
            self?.window = nil
            self?.hostingView = nil
        })
    }
}

// MARK: - SwiftUI Views

class ToastState: ObservableObject {
    @Published var isRecording = false
    @Published var statusText = "Listening..."
    @Published var audioLevel: Double = 0.0
}

struct ToastView: View {
    @ObservedObject var state: ToastState

    var body: some View {
        HStack(spacing: 10) {
            if state.isRecording {
                SoundWaveBars(level: state.audioLevel)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.system(size: 16))
            }
            Text(state.statusText)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white)
                .lineLimit(5)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: 400)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.black.opacity(0.85))
        )
    }
}

struct SoundWaveBars: View {
    var level: Double
    let barCount = 5
    let barWidth: CGFloat = 3
    let maxHeight: CGFloat = 20
    let minHeight: CGFloat = 4

    // Each bar gets a slightly different scale for visual variety
    private let barScales: [Double] = [0.6, 0.85, 1.0, 0.75, 0.5]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<barCount, id: \.self) { i in
                let barLevel = level * barScales[i]
                let height = minHeight + (maxHeight - minHeight) * barLevel
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.red)
                    .frame(width: barWidth, height: height)
                    .animation(.easeOut(duration: 0.08), value: level)
            }
        }
        .frame(height: maxHeight)
    }
}
