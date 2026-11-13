import CoreGraphics

/// Recognizes windows that already sit in one of the placements.
public enum LayoutMatcher {
    /// Whether every component of `frame` is within `tolerance` of `target`'s: the x and y
    /// of the top-left corner and the width and height.
    ///
    /// Used both to recognize placed windows and to match a window seen in one lookup
    /// (window server, hit test) to an element read in another (Accessibility), where the
    /// frame may have drifted slightly between the two reads.
    public static func isWithin(_ frame: CGRect, of target: CGRect, tolerance: CGFloat) -> Bool {
        abs(target.minX - frame.minX) <= tolerance
            && abs(target.minY - frame.minY) <= tolerance
            && abs(target.width - frame.width) <= tolerance
            && abs(target.height - frame.height) <= tolerance
    }

    /// The placement whose frame `frame` sits in on a display, if any. Apps that size in steps may be up to `tolerance` off.
    ///
    /// With a generous tolerance an odd frame can be near several placements, so the closest one wins.
    public static func action(matching frame: CGRect, in visibleFrame: CGRect, gap: CGFloat, tolerance: CGFloat) -> WindowAction? {
        var best: (action: WindowAction, distance: CGFloat)?
        for action in WindowAction.allCases where action != .center {
            guard let target = LayoutCalculator.frame(for: action, in: visibleFrame, currentFrame: frame, gap: gap) else { continue }
            let differences = [
                abs(target.minX - frame.minX), abs(target.minY - frame.minY),
                abs(target.width - frame.width), abs(target.height - frame.height),
            ]
            guard differences.allSatisfy({ $0 <= tolerance }) else { continue }
            let distance = differences.reduce(0, +)
            if best == nil || distance < best!.distance {
                best = (action, distance)
            }
        }
        return best?.action
    }
}
