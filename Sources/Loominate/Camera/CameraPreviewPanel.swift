import AppKit
import AVFoundation

/// Floating circular self-view. Sized and placed exactly like the bubble in the recording, so the
/// preview is a faithful stand-in. Drag it anywhere; on release it snaps to the nearest corner and
/// reports that corner so the setting follows. Never captured (the app is excluded from the filter).
final class CameraPreviewPanel: NSPanel {
    var onSnap: ((BubbleCorner) -> Void)?
    private(set) var bubbleSize: BubbleSize
    private(set) var corner: BubbleCorner
    private let preview: PreviewView

    init(previewLayer: AVCaptureVideoPreviewLayer, size: BubbleSize, corner: BubbleCorner) {
        bubbleSize = size
        self.corner = corner
        let screen = NSScreen.main
        let diameter = Self.diameter(for: size, on: screen)
        preview = PreviewView(previewLayer: previewLayer, frame: NSRect(x: 0, y: 0, width: diameter, height: diameter))
        super.init(contentRect: NSRect(x: 0, y: 0, width: diameter, height: diameter),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = false   // PreviewView drags the window itself so it can snap on release
        hidesOnDeactivate = false
        contentView = preview
        preview.onDragEnded = { [weak self] in self?.snapToNearestCorner() }
        setFrame(Self.frame(for: corner, size: size, on: screen), display: false)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Let the bubble sit exactly where the recording puts it, even near screen edges.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }

    // MARK: Geometry shared with the compositor

    static func diameter(for size: BubbleSize, on screen: NSScreen?) -> CGFloat {
        ((screen?.frame.height ?? 1000) * size.fraction).rounded(.down)
    }

    static func margin(for diameter: CGFloat) -> CGFloat {
        (diameter * BubbleInsets.marginFraction).rounded()
    }

    /// Window frame for a corner, in screen coordinates, inside the screen's visible area.
    static func frame(for corner: BubbleCorner, size: BubbleSize, on screen: NSScreen?) -> NSRect {
        guard let screen else { return NSRect(x: 24, y: 24, width: 180, height: 180) }
        let d = diameter(for: size, on: screen)
        let m = margin(for: d)
        let visible = screen.visibleFrame
        let origin: NSPoint
        switch corner {
        case .bottomLeft: origin = NSPoint(x: visible.minX + m, y: visible.minY + m)
        case .bottomRight: origin = NSPoint(x: visible.maxX - d - m, y: visible.minY + m)
        case .topLeft: origin = NSPoint(x: visible.minX + m, y: visible.maxY - d - m)
        case .topRight: origin = NSPoint(x: visible.maxX - d - m, y: visible.maxY - d - m)
        }
        return NSRect(origin: origin, size: NSSize(width: d, height: d))
    }

    // MARK: Layout

    func apply(size: BubbleSize, corner: BubbleCorner, animated: Bool) {
        bubbleSize = size
        self.corner = corner
        let target = Self.frame(for: corner, size: size, on: screen ?? NSScreen.main)
        setFrame(target, display: true, animate: animated)
    }

    func snapToNearestCorner() {
        let screen = self.screen ?? NSScreen.main
        let center = NSPoint(x: frame.midX, y: frame.midY)
        var best: (corner: BubbleCorner, distance: CGFloat)?
        for candidate in BubbleCorner.allCases {
            let rect = Self.frame(for: candidate, size: bubbleSize, on: screen)
            let distance = hypot(rect.midX - center.x, rect.midY - center.y)
            if best == nil || distance < best!.distance { best = (candidate, distance) }
        }
        guard let nearest = best?.corner else { return }
        apply(size: bubbleSize, corner: nearest, animated: true)
        onSnap?(nearest)
    }
}

private final class PreviewView: NSView {
    private let previewLayer: AVCaptureVideoPreviewLayer
    private var dragOffset = NSPoint.zero
    var onDragEnded: (() -> Void)?

    init(previewLayer: AVCaptureVideoPreviewLayer, frame: NSRect) {
        self.previewLayer = previewLayer
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true
        layer?.borderWidth = 3
        layer?.borderColor = NSColor.white.withAlphaComponent(0.9).cgColor
        layer?.backgroundColor = NSColor.black.cgColor
        previewLayer.frame = bounds
        layer?.addSublayer(previewLayer)
        layer?.cornerRadius = frame.width / 2
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layout() {
        super.layout()
        previewLayer.frame = bounds
        layer?.cornerRadius = bounds.width / 2
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        let location = NSEvent.mouseLocation
        dragOffset = NSPoint(x: location.x - window.frame.minX, y: location.y - window.frame.minY)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window else { return }
        let location = NSEvent.mouseLocation
        window.setFrameOrigin(NSPoint(x: location.x - dragOffset.x, y: location.y - dragOffset.y))
    }

    override func mouseUp(with event: NSEvent) {
        onDragEnded?()
    }
}
