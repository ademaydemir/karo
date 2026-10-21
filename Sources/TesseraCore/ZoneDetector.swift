import CoreGraphics

/// Decides which snap zone the cursor is in while a window is being dragged.
///
/// Like Windows, zones depend on the cursor, not the window: an edge snaps to a half,
/// the top edge maximizes, and the last `cornerSize` points along an edge snap to a quarter.
public struct ZoneDetector: Sendable {
    public struct Zone: Equatable, Sendable {
        public var action: WindowAction
        public var displayIndex: Int
    }

    /// How close to the edge (in points) the cursor must be.
    public var edgeThreshold: CGFloat
    /// Length of the corner segments at both ends of each edge.
    public var cornerSize: CGFloat

    public init(edgeThreshold: CGFloat = 5, cornerSize: CGFloat = 40) {
        self.edgeThreshold = edgeThreshold
        self.cornerSize = cornerSize
    }

    /// - Parameters:
    ///   - point: Cursor location in Accessibility coordinates.
    ///   - displays: Full display frames in Accessibility coordinates.
    public func zone(at point: CGPoint, displays: [CGRect]) -> Zone? {
        guard let index = displays.firstIndex(where: { Self.containsInclusive($0, point) }) else { return nil }
        let display = displays[index]

        // An edge shared with another display is where the cursor crosses over; snapping
        // there would trigger on every move between displays.
        func isOpenEdge(beyond probe: CGPoint) -> Bool {
            !displays.indices.contains { $0 != index && Self.containsInclusive(displays[$0], probe) }
        }
        let nearLeft = point.x - display.minX <= edgeThreshold
            && isOpenEdge(beyond: CGPoint(x: display.minX - 1, y: point.y))
        let nearRight = display.maxX - point.x <= edgeThreshold
            && isOpenEdge(beyond: CGPoint(x: display.maxX + 1, y: point.y))
        let nearTop = point.y - display.minY <= edgeThreshold
            && isOpenEdge(beyond: CGPoint(x: point.x, y: display.minY - 1))
        let nearBottom = display.maxY - point.y <= edgeThreshold
            && isOpenEdge(beyond: CGPoint(x: point.x, y: display.maxY + 1))

        let inTopSegment = point.y - display.minY <= cornerSize
        let inBottomSegment = display.maxY - point.y <= cornerSize
        let inLeftSegment = point.x - display.minX <= cornerSize
        let inRightSegment = display.maxX - point.x <= cornerSize

        let action: WindowAction?
        if nearLeft {
            action = inTopSegment ? .topLeft : inBottomSegment ? .bottomLeft : .leftHalf
        } else if nearRight {
            action = inTopSegment ? .topRight : inBottomSegment ? .bottomRight : .rightHalf
        } else if nearTop {
            action = inLeftSegment ? .topLeft : inRightSegment ? .topRight : .maximize
        } else if nearBottom {
            // The bottom edge only snaps in its corners, as on Windows.
            action = inLeftSegment ? .bottomLeft : inRightSegment ? .bottomRight : nil
        } else {
            action = nil
        }
        return action.map { Zone(action: $0, displayIndex: index) }
    }

    /// `CGRect.contains` excludes the max edges, but the cursor can sit exactly on them
    /// (e.g. the bottom row of the primary display maps to `y == maxY`).
    private static func containsInclusive(_ rect: CGRect, _ point: CGPoint) -> Bool {
        point.x >= rect.minX && point.x <= rect.maxX && point.y >= rect.minY && point.y <= rect.maxY
    }
}
