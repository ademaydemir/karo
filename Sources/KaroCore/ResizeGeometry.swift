import CoreGraphics

/// Frame math for resizing a window by dragging anywhere inside it.
public enum ResizeGeometry {
    public enum Corner: Sendable {
        case topLeft, topRight, bottomLeft, bottomRight

        /// The window edges that move when dragging this corner.
        public var edges: [SharedEdges.Edge] {
            switch self {
            case .topLeft: [.minX, .minY]
            case .topRight: [.maxX, .minY]
            case .bottomLeft: [.minX, .maxY]
            case .bottomRight: [.maxX, .maxY]
            }
        }
    }

    /// The corner nearest to the point, i.e. the one the drag will move; the opposite
    /// corner stays put. Accessibility coordinates (y grows downwards).
    public static func corner(nearest point: CGPoint, in frame: CGRect) -> Corner {
        let isLeft = point.x < frame.midX
        let isTop = point.y < frame.midY
        switch (isLeft, isTop) {
        case (true, true): return .topLeft
        case (false, true): return .topRight
        case (true, false): return .bottomLeft
        case (false, false): return .bottomRight
        }
    }

    /// The frame after moving `corner` by `delta`, never smaller than `minimumSize`.
    public static func resized(
        _ frame: CGRect,
        dragging corner: Corner,
        by delta: CGVector,
        minimumSize: CGSize = CGSize(width: 100, height: 60)
    ) -> CGRect {
        var left = frame.minX, right = frame.maxX, top = frame.minY, bottom = frame.maxY
        switch corner {
        case .topLeft:
            left = min(left + delta.dx, right - minimumSize.width)
            top = min(top + delta.dy, bottom - minimumSize.height)
        case .topRight:
            right = max(right + delta.dx, left + minimumSize.width)
            top = min(top + delta.dy, bottom - minimumSize.height)
        case .bottomLeft:
            left = min(left + delta.dx, right - minimumSize.width)
            bottom = max(bottom + delta.dy, top + minimumSize.height)
        case .bottomRight:
            right = max(right + delta.dx, left + minimumSize.width)
            bottom = max(bottom + delta.dy, top + minimumSize.height)
        }
        return CGRect(x: left, y: top, width: right - left, height: bottom - top)
    }
}

/// Which modifier keys turn a click anywhere in a window into a move (left drag) or a
/// resize (right drag).
public enum ModifierDrag: String, Codable, CaseIterable, Sendable {
    case disabled
    /// ⌃⌥. The default: plain ⌥-click already means something in many apps (Finder copies
    /// on ⌥-drag, editors select columns).
    case controlOption
    case commandControl
    case option

    public var modifiers: KeyboardShortcut.Modifiers? {
        switch self {
        case .disabled: nil
        case .controlOption: [.control, .option]
        case .commandControl: [.command, .control]
        case .option: [.option]
        }
    }
}
