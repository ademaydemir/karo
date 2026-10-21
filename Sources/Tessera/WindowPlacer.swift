import AppKit
import TesseraAccessibility
import TesseraCore

/// Applies placement actions to the focused window.
@MainActor
struct WindowPlacer {
    var gap: CGFloat = 0

    func apply(_ action: WindowAction) throws {
        let window = try AXWindow.focused()
        let currentFrame = try window.frame()
        let displays = Self.visibleDisplayFrames()
        guard let index = DisplaySelector.indexOfDisplay(containing: currentFrame, among: displays) else { return }
        let visibleFrame = displays[index]

        guard let target = LayoutCalculator.frame(
            for: action, in: visibleFrame, currentFrame: currentFrame, gap: gap
        ) else { return }
        try window.setFrame(target)

        // Apps with a minimum size end up larger than requested and may spill off the display.
        let actual = try window.frame()
        if actual.size != target.size {
            try window.setPosition(LayoutCalculator.clamped(actual, to: visibleFrame).origin)
        }
    }

    /// Usable area of every display (menu bar and Dock excluded), in Accessibility coordinates.
    private static func visibleDisplayFrames() -> [CGRect] {
        // `NSScreen.screens[0]` is always the primary display, whose top-left is the
        // Accessibility origin.
        guard let primary = NSScreen.screens.first else { return [] }
        let primaryHeight = primary.frame.height
        return NSScreen.screens.map { CoordinateConverter.flip($0.visibleFrame, primaryScreenHeight: primaryHeight) }
    }
}
