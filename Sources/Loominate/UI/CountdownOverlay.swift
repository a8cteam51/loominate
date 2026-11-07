import AppKit
import Observation
import SwiftUI

@Observable
final class CountdownModel {
    var value = 0
}

/// Transparent full-screen panel showing 3-2-1 before recording starts.
final class CountdownOverlay: NSPanel {
    private let model = CountdownModel()

    init(screen: NSScreen?) {
        let frame = screen?.frame ?? NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        contentView = NSHostingView(rootView: CountdownView(model: model))
        setFrame(frame, display: true)
    }

    func show(_ value: Int) {
        model.value = value
        if !isVisible { orderFrontRegardless() }
    }

    override var canBecomeKey: Bool { false }
}

private struct CountdownView: View {
    let model: CountdownModel

    var body: some View {
        if model.value <= 0 {
            Color.clear.ignoresSafeArea()
        } else {
            countdown
        }
    }

    private var countdown: some View {
        ZStack {
            Color.black.opacity(0.25)
            Text("\(model.value)")
                .font(.system(size: 160, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .padding(60)
                .background(Circle().fill(.black.opacity(0.55)))
                .contentTransition(.numericText(countsDown: true))
                .animation(.easeOut(duration: 0.25), value: model.value)
        }
        .ignoresSafeArea()
    }
}
