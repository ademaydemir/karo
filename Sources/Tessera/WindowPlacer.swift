import AppKit
import TesseraAccessibility
import TesseraCore

/// Applies placement actions to windows and remembers frames for `.restore`.
@MainActor
final class WindowPlacer {
    var gap: CGFloat = 0
    private var history = FrameHistory<WindowIdentity>()

    /// Applies an action to the focused window on the display it mostly overlaps.
    func apply(_ action: WindowAction) throws {
        try apply(action, to: AXWindow.focused())
    }

    /// Applies an action to a given window, e.g. one chosen in the window switcher.
    func apply(_ action: WindowAction, to window: AXWindow) throws {
        if action == .restore {
            guard let frame = history.takeRestoreFrame(for: window.identity) else { return }
            try window.setFrame(frame)
            return
        }

        let currentFrame = try window.frame()
        let displays = ScreenGeometry.displays()
        guard let index = DisplaySelector.indexOfDisplay(
            containing: currentFrame, among: displays.map(\.visibleFrame)
        ) else { return }

        if action == .nextDisplay || action == .previousDisplay {
            guard let destination = DisplayOrdering.index(
                adjacentTo: index, among: displays.map(\.frame), backward: action == .previousDisplay
            ) else { return }
            try move(window, from: currentFrame, between: displays[index], and: displays[destination])
            return
        }
        try place(window, action, from: currentFrame, on: displays[index])
    }

    /// Snapped windows keep their proportions on the new display; free-floating windows keep their size.
    private func move(_ window: AXWindow, from currentFrame: CGRect, between source: Display, and destination: Display) throws {
        let isSnapped = history.isPlaced(window.identity, at: currentFrame)
        let target = isSnapped
            ? LayoutCalculator.scaled(currentFrame, from: source.visibleFrame, to: destination.visibleFrame)
            : LayoutCalculator.translated(currentFrame, from: source.visibleFrame, to: destination.visibleFrame)
        try window.setFrame(target)
        var actual = try window.frame()
        if actual.size != target.size {
            actual = LayoutCalculator.clamped(actual, to: destination.visibleFrame)
            try window.setPosition(actual.origin)
        }
        if isSnapped {
            history.recordPlacement(of: window.identity, from: currentFrame, to: actual)
        }
    }

    /// Target frame for an action, e.g. for previewing a snap before it happens.
    func targetFrame(for action: WindowAction, currentFrame: CGRect, on display: Display) -> CGRect? {
        LayoutCalculator.frame(for: action, in: display.visibleFrame, currentFrame: currentFrame, gap: gap)
    }

    func place(_ window: AXWindow, _ action: WindowAction, from currentFrame: CGRect, on display: Display) throws {
        guard let target = targetFrame(for: action, currentFrame: currentFrame, on: display) else { return }
        try window.setFrame(target)

        // Apps with a minimum size end up larger than requested and may spill off the display.
        var actual = try window.frame()
        if actual.size != target.size {
            actual = LayoutCalculator.clamped(actual, to: display.visibleFrame)
            try window.setPosition(actual.origin)
        }
        history.recordPlacement(of: window.identity, from: currentFrame, to: actual)
    }

    /// Gives a snapped window its pre-snap size back when the user starts dragging it away,
    /// keeping the grab point at the same relative position under the cursor.
    func restoreSizeForDrag(of window: AXWindow, currentFrame: CGRect, cursor: CGPoint) throws {
        guard let original = history.takeRestoreFrame(for: window.identity, ifSizeMatches: currentFrame.size) else {
            return
        }
        let grabRatio = (cursor.x - currentFrame.minX) / currentFrame.width
        let origin = CGPoint(x: (cursor.x - grabRatio * original.width).rounded(), y: currentFrame.minY)
        try window.setFrame(CGRect(origin: origin, size: original.size))
    }
}
