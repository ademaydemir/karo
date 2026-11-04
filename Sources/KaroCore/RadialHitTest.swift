import CoreGraphics

/// Which slice of a ring of equal slices a point is in. Slice 0 is centered on the top and
/// the rest follow clockwise, in a coordinate space where y grows downwards (SwiftUI / AppKit flipped views).
///
/// Deciding this by angle, rather than by each slice's own hit area, keeps exactly one slice
/// under the pointer however the slices are drawn or layered.
public enum RadialHitTest {
    /// - Returns: The slice index, or `nil` inside the inner radius, outside the outer one, or when `count` is 0.
    public static func index(of point: CGPoint, center: CGPoint, innerRadius: CGFloat, outerRadius: CGFloat, count: Int) -> Int? {
        guard count > 0 else { return nil }
        let dx = point.x - center.x
        let dy = point.y - center.y
        let distance = hypot(dx, dy)
        guard distance >= innerRadius, distance <= outerRadius else { return nil }

        // Clockwise from 3 o'clock, because y grows downwards.
        let angle = atan2(Double(dy), Double(dx)) * 180 / .pi
        let slice = 360.0 / Double(count)
        // Move the origin to the start of slice 0, which is half a slice before the top.
        var relative = (angle + 90 + slice / 2).truncatingRemainder(dividingBy: 360)
        if relative < 0 { relative += 360 }
        return min(count - 1, Int(relative / slice))
    }
}
