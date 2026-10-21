import CoreGraphics

public enum DisplaySelector {
    /// Picks the display a window belongs to: the one it overlaps most, or, if it overlaps
    /// none (window dragged fully off-screen), the one whose center is nearest.
    /// - Returns: An index into `displays`, or `nil` if `displays` is empty.
    public static func indexOfDisplay(containing windowFrame: CGRect, among displays: [CGRect]) -> Int? {
        let overlaps = displays.map { display -> CGFloat in
            let intersection = display.intersection(windowFrame)
            return intersection.isNull ? 0 : intersection.width * intersection.height
        }
        if let best = overlaps.indices.max(by: { overlaps[$0] < overlaps[$1] }), overlaps[best] > 0 {
            return best
        }
        return displays.indices.min { distanceSquared(displays[$0], windowFrame) < distanceSquared(displays[$1], windowFrame) }
    }

    private static func distanceSquared(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let dx = a.midX - b.midX
        let dy = a.midY - b.midY
        return dx * dx + dy * dy
    }
}
