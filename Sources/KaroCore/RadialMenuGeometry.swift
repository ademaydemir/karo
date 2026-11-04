import CoreGraphics

/// Where the pointer is relative to an item with a radial menu around it.
public enum RadialMenuRegion: Equatable, Sendable {
    case slice(Int)
    /// On the item itself, or in the open ring's hollow center.
    case item
    case outside
}

/// The one place that decides what the pointer is over, so hover, clicks and closing all agree.
public enum RadialMenuGeometry {
    /// - Parameters:
    ///   - point: The pointer, in the same flipped (y-down) space as the other geometry.
    ///   - ringCenter: The center of the ring, which is also the item's center.
    ///   - itemRect: The item's frame.
    ///   - isOpen: Closed, there is no ring, so only the item counts.
    public static func region(
        of point: CGPoint,
        ringCenter: CGPoint,
        innerRadius: CGFloat,
        outerRadius: CGFloat,
        sliceCount: Int,
        itemRect: CGRect,
        isOpen: Bool
    ) -> RadialMenuRegion {
        guard isOpen else { return itemRect.contains(point) ? .item : .outside }
        if let index = RadialHitTest.index(of: point, center: ringCenter, innerRadius: innerRadius, outerRadius: outerRadius, count: sliceCount) {
            return .slice(index)
        }
        // The item stays active even where it extends past the inner circle, and the hollow
        // center belongs to it so the pointer can cross it without closing the menu.
        if itemRect.contains(point) || hypot(point.x - ringCenter.x, point.y - ringCenter.y) < innerRadius {
            return .item
        }
        return .outside
    }
}
