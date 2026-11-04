import CoreGraphics

/// Decides which snap zone the cursor is in while a window is being dragged.
///
/// Zones depend on the cursor, not the window: an edge snaps to a half,
/// the top edge maximizes, the last `cornerSize` points along an edge snap to a quarter,
/// and the bottom edge between its corners snaps to a third.
public struct ZoneDetector: Sendable {
    public struct Zone: Equatable, Sendable {
        public var action: WindowAction
        public var displayIndex: Int
    }

    /// How close to the edge (in points) the cursor must be.
    public var edgeThreshold: CGFloat
    /// Length of the corner segments at both ends of each edge.
    public var cornerSize: CGFloat

    /// How far (in points) past a zone's borders the cursor may stray before the zone is left;
    /// used by `zone(at:displays:current:)`.
    public var hysteresis: CGFloat
    /// How close to an edge shared with another display the cursor must be for it to count,
    /// when shared edges are included. Larger than `edgeThreshold` because the cursor is not
    /// held back at a shared edge.
    public var sharedEdgeThreshold: CGFloat

    public init(
        edgeThreshold: CGFloat = 5,
        cornerSize: CGFloat = 40,
        hysteresis: CGFloat = 8,
        sharedEdgeThreshold: CGFloat = 10
    ) {
        self.edgeThreshold = edgeThreshold
        self.cornerSize = cornerSize
        self.hysteresis = hysteresis
        self.sharedEdgeThreshold = sharedEdgeThreshold
    }

    /// Like `zone(at:displays:)`, but keeps `current` while the pointer is still within
    /// `hysteresis` points of it, so zones do not flicker at their borders.
    public func zone(at point: CGPoint, displays: [CGRect], current: Zone?, includesSharedEdges: Bool = false) -> Zone? {
        let candidate = zone(at: point, displays: displays, includesSharedEdges: includesSharedEdges)
        guard let current, candidate != current else { return candidate }
        // A wider edge and corner keep an edge zone or a corner zone; a smaller corner keeps
        // an edge-half zone that the pointer has slid into a corner segment.
        let keepers = [
            ZoneDetector(edgeThreshold: edgeThreshold + hysteresis, cornerSize: cornerSize + hysteresis, hysteresis: 0, sharedEdgeThreshold: sharedEdgeThreshold + hysteresis),
            ZoneDetector(edgeThreshold: edgeThreshold + hysteresis, cornerSize: max(0, cornerSize - hysteresis), hysteresis: 0, sharedEdgeThreshold: sharedEdgeThreshold + hysteresis),
        ]
        if keepers.contains(where: { $0.zone(at: point, displays: displays, includesSharedEdges: includesSharedEdges) == current }) {
            return current
        }
        return candidate
    }

    /// - Parameters:
    ///   - point: Cursor location in Accessibility coordinates.
    ///   - displays: Full display frames in Accessibility coordinates.
    ///   - includesSharedEdges: Whether an edge shared with another display counts, within
    ///     `sharedEdgeThreshold`. Off by default: the cursor crosses there all the time, so callers
    ///     should ask for it only once the cursor rests.
    public func zone(at point: CGPoint, displays: [CGRect], includesSharedEdges: Bool = false) -> Zone? {
        guard let index = displays.firstIndex(where: { Self.containsInclusive($0, point) }) else { return nil }
        let display = displays[index]

        // An edge shared with another display is where the cursor crosses over; snapping
        // there would trigger on every move between displays, so it counts only on request.
        func isNear(_ distance: CGFloat, beyond probe: CGPoint) -> Bool {
            let isOpen = !displays.indices.contains { $0 != index && Self.containsInclusive(displays[$0], probe) }
            if isOpen { return distance <= edgeThreshold }
            return includesSharedEdges && distance <= sharedEdgeThreshold
        }
        let nearLeft = isNear(point.x - display.minX, beyond: CGPoint(x: display.minX - 1, y: point.y))
        let nearRight = isNear(display.maxX - point.x, beyond: CGPoint(x: display.maxX + 1, y: point.y))
        let nearTop = isNear(point.y - display.minY, beyond: CGPoint(x: point.x, y: display.minY - 1))
        let nearBottom = isNear(display.maxY - point.y, beyond: CGPoint(x: point.x, y: display.maxY + 1))

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
            // The Dock does not react to window drags, so the bottom edge is free to use. Between
            // its corners it is split into thirds, which a drag cannot reach otherwise.
            if inLeftSegment {
                action = .bottomLeft
            } else if inRightSegment {
                action = .bottomRight
            } else {
                let span = (display.width - 2 * cornerSize) / 3
                let offset = point.x - (display.minX + cornerSize)
                action = offset < span ? .leftThird : offset < 2 * span ? .centerThird : .rightThird
            }
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
