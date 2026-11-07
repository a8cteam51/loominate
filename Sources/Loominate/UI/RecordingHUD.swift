import AppKit
import SwiftUI

/// Small floating timer + Stop control shown while recording. Excluded from the capture by app filter.
final class RecordingHUD: NSPanel {
    init(state: AppState) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 180, height: 44),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        let size = NSSize(width: 200, height: 48)
        let hosting = NSHostingView(rootView: HUDView(state: state))
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.autoresizingMask = [.width, .height]
        contentView = hosting
        setContentSize(size)
        positionAtTopCenter()
    }

    private func positionAtTopCenter() {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let origin = NSPoint(x: visible.midX - frame.width / 2, y: visible.maxY - frame.height - 12)
        setFrameOrigin(origin)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private struct HUDView: View {
    let state: AppState

    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(.red).frame(width: 10, height: 10)
            Text(state.elapsedText)
                .font(.system(.body, design: .monospaced).weight(.medium))
                .monospacedDigit()
            Button {
                Task { await state.stopRecording() }
            } label: {
                Label("Stop", systemImage: "stop.fill")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.white.opacity(0.15)))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
