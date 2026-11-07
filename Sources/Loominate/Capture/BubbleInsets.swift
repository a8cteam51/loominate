import AppKit

/// Screen areas the bubble should stay out of (menu bar, Dock), in points of the captured display.
struct BubbleInsets: Equatable {
    static let marginFraction: CGFloat = 0.15
    static let zero = BubbleInsets(top: 0, left: 0, bottom: 0, right: 0)

    var top: CGFloat
    var left: CGFloat
    var bottom: CGFloat
    var right: CGFloat

    /// Difference between a screen's full frame and its visible frame.
    static func forDisplay(_ screen: NSScreen?) -> BubbleInsets {
        guard let screen else { return .zero }
        let full = screen.frame
        let visible = screen.visibleFrame
        return BubbleInsets(top: max(0, full.maxY - visible.maxY),
                            left: max(0, visible.minX - full.minX),
                            bottom: max(0, visible.minY - full.minY),
                            right: max(0, full.maxX - visible.maxX))
    }

    func scaled(by factor: CGFloat) -> BubbleInsets {
        BubbleInsets(top: top * factor, left: left * factor, bottom: bottom * factor, right: right * factor)
    }
}
