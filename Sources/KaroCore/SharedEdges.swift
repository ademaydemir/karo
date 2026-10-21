import CoreGraphics

/// Placed windows that sit side by side share an edge (with the configured gap between
/// them). When one of them is resized along that edge, its neighbours follow, so the layout
/// stays gap-free.
public enum SharedEdges {
    /// Where the neighbour sits relative to the resized window.
    public enum Side: Sendable {
        case left, right, top, bottom
    }

    public struct Neighbor<ID> {
        public let id: ID
        public let frame: CGRect
        public let side: Side
    }

    /// Windows directly next to `frame`: across one of its edges at `gap` distance, and
    /// overlapping it along that edge (a quarter below another quarter is a neighbour; the
    /// one diagonally across is not).
    public static func neighbors<ID>(
        of frame: CGRect,
        among candidates: [(id: ID, frame: CGRect)],
        gap: CGFloat,
        tolerance: CGFloat = 3
    ) -> [Neighbor<ID>] {
        candidates.compactMap { candidate in
            let other = candidate.frame
            let overlapsVertically = min(frame.maxY, other.maxY) - max(frame.minY, other.minY) > tolerance
            let overlapsHorizontally = min(frame.maxX, other.maxX) - max(frame.minX, other.minX) > tolerance
            func touches(_ a: CGFloat, _ b: CGFloat) -> Bool { abs(a - b) <= tolerance }

            let side: Side?
            if overlapsVertically, touches(other.minX, frame.maxX + gap) {
                side = .right
            } else if overlapsVertically, touches(other.maxX, frame.minX - gap) {
                side = .left
            } else if overlapsHorizontally, touches(other.minY, frame.maxY + gap) {
                side = .bottom
            } else if overlapsHorizontally, touches(other.maxY, frame.minY - gap) {
                side = .top
            } else {
                side = nil
            }
            return side.map { Neighbor(id: candidate.id, frame: other, side: $0) }
        }
    }

    /// The neighbour's frame after `resized` moved the shared edge: the near edge follows,
    /// the far edge stays, and the neighbour never gets narrower than `minimumLength`.
    public static func adjusted(
        _ neighbor: CGRect,
        on side: Side,
        of resized: CGRect,
        gap: CGFloat,
        minimumLength: CGFloat = 120
    ) -> CGRect {
        switch side {
        case .right:
            let minX = min(resized.maxX + gap, neighbor.maxX - minimumLength)
            return CGRect(x: minX, y: neighbor.minY, width: neighbor.maxX - minX, height: neighbor.height)
        case .left:
            let maxX = max(resized.minX - gap, neighbor.minX + minimumLength)
            return CGRect(x: neighbor.minX, y: neighbor.minY, width: maxX - neighbor.minX, height: neighbor.height)
        case .bottom:
            let minY = min(resized.maxY + gap, neighbor.maxY - minimumLength)
            return CGRect(x: neighbor.minX, y: minY, width: neighbor.width, height: neighbor.maxY - minY)
        case .top:
            let maxY = max(resized.minY - gap, neighbor.minY + minimumLength)
            return CGRect(x: neighbor.minX, y: neighbor.minY, width: neighbor.width, height: maxY - neighbor.minY)
        }
    }
}
