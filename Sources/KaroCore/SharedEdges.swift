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

    /// An edge of a window (Accessibility coordinates, y grows downwards).
    public enum Edge: Sendable, Equatable, Hashable, CustomStringConvertible {
        case minX, maxX, minY, maxY

        public var description: String {
            switch self {
            case .minX: "minX"
            case .maxX: "maxX"
            case .minY: "minY"
            case .maxY: "maxY"
            }
        }

        public var isVertical: Bool {
            self == .minX || self == .maxX
        }

        public var opposite: Edge {
            switch self {
            case .minX: .maxX
            case .maxX: .minX
            case .minY: .maxY
            case .maxY: .minY
            }
        }

        public func coordinate(in frame: CGRect) -> CGFloat {
            switch self {
            case .minX: frame.minX
            case .maxX: frame.maxX
            case .minY: frame.minY
            case .maxY: frame.maxY
            }
        }
    }

    /// The edges of `frame` a press at `point` can resize: the point is within `reach` of the edge line,
    /// inside or outside the window, and within the edge's extent grown by `reach` (so corners count for
    /// both edges). Empty when the point is farther from every edge. Accessibility coordinates.
    ///
    /// When `cornerReach` is provided, a point near an edge that is also within `cornerReach` of an
    /// adjacent perpendicular edge line includes that edge too, because macOS treats presses up to
    /// ~20 pt from a corner as corner resizes.
    public static func edges(near point: CGPoint, of frame: CGRect, reach: CGFloat, cornerReach: CGFloat? = nil) -> [Edge] {
        var result: [Edge] = []
        let xRange = (frame.minX - reach)...(frame.maxX + reach)
        let yRange = (frame.minY - reach)...(frame.maxY + reach)

        let nearMinX = abs(point.x - frame.minX) <= reach && yRange.contains(point.y)
        let nearMaxX = abs(point.x - frame.maxX) <= reach && yRange.contains(point.y)
        let nearMinY = abs(point.y - frame.minY) <= reach && xRange.contains(point.x)
        let nearMaxY = abs(point.y - frame.maxY) <= reach && xRange.contains(point.x)

        var includeMinX = nearMinX
        var includeMaxX = nearMaxX
        var includeMinY = nearMinY
        var includeMaxY = nearMaxY

        if let cornerReach {
            if nearMinX || nearMaxX {
                if abs(point.y - frame.minY) <= cornerReach {
                    includeMinY = true
                }
                if abs(point.y - frame.maxY) <= cornerReach {
                    includeMaxY = true
                }
            }
            if nearMinY || nearMaxY {
                if abs(point.x - frame.minX) <= cornerReach {
                    includeMinX = true
                }
                if abs(point.x - frame.maxX) <= cornerReach {
                    includeMaxX = true
                }
            }
        }

        if includeMinX { result.append(.minX) }
        if includeMaxX { result.append(.maxX) }
        if includeMinY { result.append(.minY) }
        if includeMaxY { result.append(.maxY) }
        return result
    }

    /// Returns the edges whose coordinates moved by more than `threshold` between two frames,
    /// in standard order (minX, maxX, minY, maxY).
    public static func movedEdges(from initial: CGRect, to current: CGRect, threshold: CGFloat = 0.5) -> [Edge] {
        var edges: [Edge] = []
        if abs(current.minX - initial.minX) > threshold { edges.append(.minX) }
        if abs(current.maxX - initial.maxX) > threshold { edges.append(.maxX) }
        if abs(current.minY - initial.minY) > threshold { edges.append(.minY) }
        if abs(current.maxY - initial.maxY) > threshold { edges.append(.maxY) }
        return edges
    }

    /// A window that moves when a shared edge line moves.
    public struct LinkedEdge<ID> {
        public let id: ID
        public let frame: CGRect
        /// The edge of this window that lies on the line.
        public let edge: Edge

        public init(id: ID, frame: CGRect, edge: Edge) {
            self.id = id
            self.frame = frame
            self.edge = edge
        }
    }

    /// The windows whose edges lie on the same line as `edge` of `frame` and are connected to it
    /// along that line, transitively. "Same line" means: a window's same edge within `tolerance` of the
    /// line (it sits on the same side as `frame`, e.g. the window below `frame` sharing its left edge), or
    /// its opposite edge at `line ∓ gap` within `tolerance` (it sits across the line). "Connected" means its
    /// extent along the line overlaps, or comes within `gap + tolerance` of, the union of the extents
    /// already in the group, starting with `frame`'s own extent. Repeat until no window is added.
    /// `frame` itself is not in the result.
    public static func linkedEdges<ID>(
        of frame: CGRect, edge: Edge,
        among candidates: [(id: ID, frame: CGRect)],
        gap: CGFloat, tolerance: CGFloat = 3
    ) -> [LinkedEdge<ID>] {
        let line = edge.coordinate(in: frame)
        func extent(of r: CGRect) -> ClosedRange<CGFloat> {
            edge.isVertical ? r.minY...r.maxY : r.minX...r.maxX
        }
        func distance(_ a: ClosedRange<CGFloat>, _ b: ClosedRange<CGFloat>) -> CGFloat {
            max(0, max(a.lowerBound, b.lowerBound) - min(a.upperBound, b.upperBound))
        }

        let sameEdge = edge
        let sameTarget = line
        let oppEdge = edge.opposite
        let oppTarget: CGFloat = (edge == .minX || edge == .minY) ? (line - gap) : (line + gap)

        var groupExtents: [ClosedRange<CGFloat>] = [extent(of: frame)]
        var linked: [LinkedEdge<ID>] = []
        var pool = candidates.filter { $0.frame != frame }

        var changed = true
        while changed {
            changed = false
            var nextPool: [(id: ID, frame: CGRect)] = []
            for candidate in pool {
                let matchesSame = abs(sameEdge.coordinate(in: candidate.frame) - sameTarget) <= tolerance
                let matchesOpp = abs(oppEdge.coordinate(in: candidate.frame) - oppTarget) <= tolerance

                let matchedEdge: Edge
                if matchesSame && !matchesOpp {
                    matchedEdge = sameEdge
                } else if matchesOpp && !matchesSame {
                    matchedEdge = oppEdge
                } else if matchesSame && matchesOpp {
                    matchedEdge = sameEdge
                } else {
                    continue
                }

                let candidateExtent = extent(of: candidate.frame)
                let isConnected = groupExtents.contains { distance($0, candidateExtent) <= gap + tolerance }

                if isConnected {
                    linked.append(LinkedEdge(id: candidate.id, frame: candidate.frame, edge: matchedEdge))
                    groupExtents.append(candidateExtent)
                    changed = true
                } else {
                    nextPool.append(candidate)
                }
            }
            pool = nextPool
        }

        return linked
    }

    /// Clamps a proposed line position so every window on it keeps at least `minimumLength` along the
    /// moved axis. `resized` is the dragged window's ORIGINAL frame with its edge `edge`.
    public static func clampedLine(
        _ proposed: CGFloat, edge: Edge, of resized: CGRect,
        linked: [LinkedEdge<some Any>], gap: CGFloat, minimumLength: CGFloat = 120
    ) -> CGFloat {
        var minLine = -CGFloat.greatestFiniteMagnitude
        var maxLine = CGFloat.greatestFiniteMagnitude

        switch edge {
        case .minX:
            maxLine = min(maxLine, resized.maxX - minimumLength)
        case .maxX:
            minLine = max(minLine, resized.minX + minimumLength)
        case .minY:
            maxLine = min(maxLine, resized.maxY - minimumLength)
        case .maxY:
            minLine = max(minLine, resized.minY + minimumLength)
        }

        for item in linked {
            if item.edge == edge {
                switch item.edge {
                case .minX:
                    maxLine = min(maxLine, item.frame.maxX - minimumLength)
                case .maxX:
                    minLine = max(minLine, item.frame.minX + minimumLength)
                case .minY:
                    maxLine = min(maxLine, item.frame.maxY - minimumLength)
                case .maxY:
                    minLine = max(minLine, item.frame.minY + minimumLength)
                }
            } else {
                switch edge {
                case .minX:
                    minLine = max(minLine, item.frame.minX + minimumLength + gap)
                case .maxX:
                    maxLine = min(maxLine, item.frame.maxX - minimumLength - gap)
                case .minY:
                    minLine = max(minLine, item.frame.minY + minimumLength + gap)
                case .maxY:
                    maxLine = min(maxLine, item.frame.maxY - minimumLength - gap)
                }
            }
        }

        if minLine > maxLine {
            return minLine
        }
        return min(max(proposed, minLine), maxLine)
    }

    /// `frame` with `edge` moved to the line. For a window across the line (its edge is the opposite
    /// of the dragged one) pass the dragged window's line; this function computes the window's own edge
    /// position as: same edge kind as dragged → `line`; opposite edge → `line ± gap`
    /// (maxX/maxY across a minX/minY line get `line - gap`, minX/minY across a maxX/maxY line get `line + gap`).
    public static func moving(_ frame: CGRect, edge: Edge, draggedEdge: Edge, toLine line: CGFloat, gap: CGFloat) -> CGRect {
        let target: CGFloat
        if edge == draggedEdge {
            target = line
        } else {
            if draggedEdge == .minX || draggedEdge == .minY {
                target = line - gap
            } else {
                target = line + gap
            }
        }

        switch edge {
        case .minX:
            return CGRect(x: target, y: frame.minY, width: frame.maxX - target, height: frame.height)
        case .maxX:
            return CGRect(x: frame.minX, y: frame.minY, width: target - frame.minX, height: frame.height)
        case .minY:
            return CGRect(x: frame.minX, y: target, width: frame.width, height: frame.maxY - target)
        case .maxY:
            return CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: target - frame.minY)
        }
    }
}

extension SharedEdges.LinkedEdge: Sendable where ID: Sendable {}
extension SharedEdges.LinkedEdge: Equatable where ID: Equatable {}
