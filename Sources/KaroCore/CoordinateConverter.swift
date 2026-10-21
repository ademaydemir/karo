import CoreGraphics

/// Converts between AppKit and Accessibility screen coordinates.
///
/// AppKit (`NSScreen`, `NSWindow`) puts the origin at the bottom-left of the primary display
/// with y growing upwards; the Accessibility API puts it at the top-left with y growing
/// downwards. Both share the same x axis and the same primary display, so the conversion
/// is a vertical flip around the primary display's height, and it is its own inverse.
public enum CoordinateConverter {
    public static func flip(_ rect: CGRect, primaryScreenHeight: CGFloat) -> CGRect {
        CGRect(
            x: rect.minX,
            y: primaryScreenHeight - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    public static func flip(_ point: CGPoint, primaryScreenHeight: CGFloat) -> CGPoint {
        CGPoint(x: point.x, y: primaryScreenHeight - point.y)
    }
}
