import CoreGraphics

/// Finds the part of a display that snapped windows leave free, for dropping a window into it.
public enum FreeRegionFinder {
    /// Share of a region another window may cover before the region no longer counts as free.
    private static let allowedOverlap: CGFloat = 0.1

    /// A region beside a snapped window that no snapped window occupies and that contains `cursor`.
    /// - Parameter snappedFrames: Frames of the other snapped windows on this display (not the dragged one).
    public static func region(at cursor: CGPoint, in visibleFrame: CGRect, gap: CGFloat, snappedFrames: [CGRect], tolerance: CGFloat) -> WindowAction? {
        for snapped in snappedFrames {
            guard let action = LayoutMatcher.action(matching: snapped, in: visibleFrame, gap: gap, tolerance: tolerance) else { continue }
            for candidate in action.snapAssistRegions {
                guard let frame = LayoutCalculator.frame(for: candidate, in: visibleFrame, currentFrame: .zero, gap: gap),
                      frame.contains(cursor) else { continue }
                let area = frame.width * frame.height
                let isFree = snappedFrames.allSatisfy { other in
                    let overlap = other.intersection(frame)
                    return overlap.isNull || overlap.width * overlap.height <= area * allowedOverlap
                }
                if isFree { return candidate }
            }
        }
        return nil
    }
}
