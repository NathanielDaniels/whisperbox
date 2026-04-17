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
        hosting.frame = NSRect(x: 0, y: 0, width: 180, height: 50)

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
        let preview = text.count > 30 ? String(text.prefix(30)) + "..." : text
        toastState.statusText = preview.isEmpty ? "Transcribed!" : preview

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.hide()
        }
    }

    func showError(_ message: String) {
        toastState.isRecording = false
        toastState.statusText = message

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.hide()
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
}

struct ToastView: View {
    @ObservedObject var state: ToastState

    var body: some View {
        HStack(spacing: 10) {
            if state.isRecording {
                SoundWaveBars()
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.system(size: 16))
            }
            Text(state.statusText)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white)
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.85))
        )
    }
}

struct SoundWaveBars: View {
    @State private var animating = false
    let barCount = 5
    let barWidth: CGFloat = 3
    let maxHeight: CGFloat = 20
    let minHeight: CGFloat = 4

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<barCount, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.red)
                    .frame(width: barWidth, height: animating ? maxHeight : minHeight)
                    .animation(
                        .easeInOut(duration: 0.4 + Double(i) * 0.1)
                        .repeatForever(autoreverses: true),
                        value: animating
                    )
            }
        }
        .frame(height: maxHeight)
        .onAppear { animating = true }
    }
}
