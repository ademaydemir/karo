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
        let window = try AXWindow.focused()

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
        try place(window, action, from: currentFrame, on: displays[index])
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
