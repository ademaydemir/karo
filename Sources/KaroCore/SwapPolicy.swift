import CoreGraphics

/// Decides whether a placed window dragged over another placed window should swap places
/// with it on release. Swapping is a deliberate gesture: it must not fire while a window is
/// just being carried to another display or across a window that fills its display.
public enum SwapPolicy {
    /// Fraction of the target's width and height, on each side, that does not count as "over" it.
    public static let edgeMarginFraction: CGFloat = 0.2
    /// A target covering at least this share of its display's visible area fills the display.
    public static let fillsDisplayFraction: CGFloat = 0.9

    /// - Parameters:
    ///   - sourceSlot: Frame the dragged window was placed at before the drag.
    ///   - targetFrame: Frame of the placed window under the pointer.
    ///   - cursor: Pointer location.
    ///   - visibleFrames: Visible frames of all displays (same coordinate space as the frames).
    public static func allowsSwap(sourceSlot: CGRect, targetFrame: CGRect, cursor: CGPoint, visibleFrames: [CGRect]) -> Bool {
        guard let display = DisplaySelector.indexOfDisplay(containing: sourceSlot, among: visibleFrames),
              display == DisplaySelector.indexOfDisplay(containing: targetFrame, among: visibleFrames) else { return false }
        let visible = visibleFrames[display]
        guard targetFrame.width * targetFrame.height < fillsDisplayFraction * visible.width * visible.height else { return false }
        let core = targetFrame.insetBy(dx: targetFrame.width * edgeMarginFraction, dy: targetFrame.height * edgeMarginFraction)
        return core.contains(cursor)
    }
}
