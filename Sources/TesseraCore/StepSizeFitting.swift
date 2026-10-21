import CoreGraphics

/// Placing windows of apps that only resize in steps, such as Terminal (whole rows and
/// columns). They round a requested size down, leaving a gap of up to one step.
///
/// On an outer display edge the gap is closed by growing to the next step; the overshoot
/// goes behind the Dock or past the screen edge. On an inner edge, growing would cover the
/// neighbouring window, so the window is aligned to that edge instead and the gap ends up at
/// the display edge.
public enum StepSizeFitting {
    /// A shortfall larger than this is not step rounding but something else (and is left alone).
    public static let maximumStep: CGFloat = 40

    /// Whether a shortfall is the kind step rounding produces.
    public static func isStepShortfall(_ shortfall: CGFloat) -> Bool {
        shortfall > 1 && shortfall <= maximumStep
    }

    /// Whether the window may grow past the target's bottom edge, i.e. the edge is the
    /// bottom of the usable display area.
    public static func canGrowDown(_ target: CGRect, in visibleFrame: CGRect) -> Bool {
        target.maxY >= visibleFrame.maxY - 1
    }

    /// Whether the window may grow past the target's right edge.
    public static func canGrowRight(_ target: CGRect, in visibleFrame: CGRect) -> Bool {
        target.maxX >= visibleFrame.maxX - 1
    }

    /// Where a window that stays smaller than its target goes: against the target's inner
    /// edges, so it meets the windows next to it and any gap sits at a display edge.
    public static func alignedOrigin(for size: CGSize, in target: CGRect, visibleFrame: CGRect) -> CGPoint {
        let touchesLeft = target.minX <= visibleFrame.minX + 1
        let touchesRight = target.maxX >= visibleFrame.maxX - 1
        let touchesTop = target.minY <= visibleFrame.minY + 1
        let touchesBottom = target.maxY >= visibleFrame.maxY - 1
        // Only an edge-to-inner span has a side to lean towards; a full span keeps the origin.
        let x = (touchesLeft && !touchesRight) ? target.maxX - size.width : target.minX
        let y = (touchesTop && !touchesBottom) ? target.maxY - size.height : target.minY
        return CGPoint(x: x, y: y)
    }

    /// The next extra amount to request while searching for the step above the target.
    ///
    /// Starting at the shortfall and doubling, the first request that reaches the next step
    /// never reaches the one after it, so the window grows by at most one step.
    public static func nextExtra(after extra: CGFloat) -> CGFloat? {
        let next = extra * 2
        return next <= maximumStep * 2 ? next : nil
    }
}
