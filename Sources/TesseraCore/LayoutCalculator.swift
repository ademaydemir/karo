import CoreGraphics

/// Computes target window frames for placement actions.
///
/// All rectangles use Accessibility coordinates: origin at the top-left of the primary
/// display, y growing downwards. "Top" therefore means smaller y.
public enum LayoutCalculator {
    /// - Parameters:
    ///   - action: The placement to compute.
    ///   - visibleFrame: The usable area of the target display (menu bar and Dock excluded).
    ///   - currentFrame: The window's current frame; used by size-preserving actions such as `.center`.
    ///   - gap: Spacing around windows. Screen edges get the full gap, shared edges half of it,
    ///     so two adjacent windows end up exactly `gap` apart.
    /// - Returns: The target frame, or `nil` for actions that are not a placement on the
    ///   current display (`.restore`, `.nextDisplay`, `.previousDisplay`).
    public static func frame(
        for action: WindowAction,
        in visibleFrame: CGRect,
        currentFrame: CGRect,
        gap: CGFloat = 0
    ) -> CGRect? {
        if action == .center {
            return centered(currentFrame, in: visibleFrame.insetBy(dx: gap, dy: gap))
        }
        guard let region = UnitRegion(action) else { return nil }
        return place(region, in: visibleFrame, gap: gap)
    }

    /// Maps a snapped window to another display, keeping its proportions, so a left half
    /// stays a left half.
    public static func scaled(_ frame: CGRect, from source: CGRect, to destination: CGRect) -> CGRect {
        let scaleX = destination.width / source.width
        let scaleY = destination.height / source.height
        let left = (destination.minX + (frame.minX - source.minX) * scaleX).rounded()
        let top = (destination.minY + (frame.minY - source.minY) * scaleY).rounded()
        let right = (destination.minX + (frame.maxX - source.minX) * scaleX).rounded()
        let bottom = (destination.minY + (frame.maxY - source.minY) * scaleY).rounded()
        return clamped(CGRect(x: left, y: top, width: right - left, height: bottom - top), to: destination)
    }

    /// Moves a free-floating window to another display, keeping its size (shrunk only if it
    /// does not fit) and its relative position.
    public static func translated(_ frame: CGRect, from source: CGRect, to destination: CGRect) -> CGRect {
        let width = min(frame.width, destination.width)
        let height = min(frame.height, destination.height)
        let relativeCenterX = (frame.midX - source.minX) / source.width
        let relativeCenterY = (frame.midY - source.minY) / source.height
        let moved = CGRect(
            x: (destination.minX + relativeCenterX * destination.width - width / 2).rounded(),
            y: (destination.minY + relativeCenterY * destination.height - height / 2).rounded(),
            width: width,
            height: height
        )
        return clamped(moved, to: destination)
    }

    /// Moves `frame` the minimum distance needed to keep it inside `visibleFrame`.
    ///
    /// Used when an app refuses the requested size (minimum window size) and the larger
    /// window would otherwise spill off the display. If the frame is larger than the
    /// visible area, it is aligned to the top-left corner.
    public static func clamped(_ frame: CGRect, to visibleFrame: CGRect) -> CGRect {
        var origin = frame.origin
        if frame.maxX > visibleFrame.maxX { origin.x = visibleFrame.maxX - frame.width }
        if origin.x < visibleFrame.minX { origin.x = visibleFrame.minX }
        if frame.maxY > visibleFrame.maxY { origin.y = visibleFrame.maxY - frame.height }
        if origin.y < visibleFrame.minY { origin.y = visibleFrame.minY }
        return CGRect(origin: origin, size: frame.size)
    }

    private static func centered(_ frame: CGRect, in area: CGRect) -> CGRect {
        let width = min(frame.width, area.width)
        let height = min(frame.height, area.height)
        return CGRect(
            x: (area.midX - width / 2).rounded(),
            y: (area.midY - height / 2).rounded(),
            width: width,
            height: height
        )
    }

    private static func place(_ region: UnitRegion, in visibleFrame: CGRect, gap: CGFloat) -> CGRect {
        // Edges are rounded before applying the gap so that neighbouring regions share
        // the exact same pixel boundary (e.g. three thirds on a width not divisible by 3).
        func edge(_ fraction: CGFloat, origin: CGFloat, length: CGFloat) -> CGFloat {
            (origin + fraction * length).rounded()
        }
        func inset(isOuter: Bool) -> CGFloat {
            isOuter ? gap : gap / 2
        }

        let left = edge(region.minX, origin: visibleFrame.minX, length: visibleFrame.width)
            + inset(isOuter: region.minX == 0)
        let right = edge(region.maxX, origin: visibleFrame.minX, length: visibleFrame.width)
            - inset(isOuter: region.maxX == 1)
        let top = edge(region.minY, origin: visibleFrame.minY, length: visibleFrame.height)
            + inset(isOuter: region.minY == 0)
        let bottom = edge(region.maxY, origin: visibleFrame.minY, length: visibleFrame.height)
            - inset(isOuter: region.maxY == 1)

        return CGRect(x: left, y: top, width: right - left, height: bottom - top)
    }
}

/// A region of a display expressed as fractions (0...1) of its visible frame.
///
/// Stored as edges rather than origin + size so that `maxX == 1` is exact for
/// regions like two-thirds, which matters for deciding outer vs. shared gaps.
private struct UnitRegion {
    let minX: CGFloat, maxX: CGFloat, minY: CGFloat, maxY: CGFloat

    init?(_ action: WindowAction) {
        let third: CGFloat = 1 / 3
        let twoThirds: CGFloat = 2 / 3
        switch action {
        case .leftHalf: (minX, maxX, minY, maxY) = (0, 0.5, 0, 1)
        case .rightHalf: (minX, maxX, minY, maxY) = (0.5, 1, 0, 1)
        case .topHalf: (minX, maxX, minY, maxY) = (0, 1, 0, 0.5)
        case .bottomHalf: (minX, maxX, minY, maxY) = (0, 1, 0.5, 1)
        case .topLeft: (minX, maxX, minY, maxY) = (0, 0.5, 0, 0.5)
        case .topRight: (minX, maxX, minY, maxY) = (0.5, 1, 0, 0.5)
        case .bottomLeft: (minX, maxX, minY, maxY) = (0, 0.5, 0.5, 1)
        case .bottomRight: (minX, maxX, minY, maxY) = (0.5, 1, 0.5, 1)
        case .leftThird: (minX, maxX, minY, maxY) = (0, third, 0, 1)
        case .centerThird: (minX, maxX, minY, maxY) = (third, twoThirds, 0, 1)
        case .rightThird: (minX, maxX, minY, maxY) = (twoThirds, 1, 0, 1)
        case .leftTwoThirds: (minX, maxX, minY, maxY) = (0, twoThirds, 0, 1)
        case .rightTwoThirds: (minX, maxX, minY, maxY) = (third, 1, 0, 1)
        case .maximize: (minX, maxX, minY, maxY) = (0, 1, 0, 1)
        case .center, .restore, .nextDisplay, .previousDisplay: return nil
        }
    }
}
