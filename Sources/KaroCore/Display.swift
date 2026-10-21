import CoreGraphics

/// A display's geometry in Accessibility coordinates.
public struct Display: Equatable, Sendable {
    /// The whole display, used for detecting screen edges.
    public var frame: CGRect
    /// The area windows may occupy (menu bar and Dock excluded), used for placement.
    public var visibleFrame: CGRect

    public init(frame: CGRect, visibleFrame: CGRect) {
        self.frame = frame
        self.visibleFrame = visibleFrame
    }

    /// The usable area, given whether the Dock is currently on this display.
    ///
    /// With separate Spaces per display the Dock can move to any display, so macOS reserves
    /// its space on every one of them. On a display without the Dock that leaves an empty
    /// strip under snapped windows; only the menu bar at the top is kept out.
    public static func usableFrame(visibleFrame: CGRect, frame: CGRect, hostsDock: Bool) -> CGRect {
        guard !hostsDock else { return visibleFrame }
        return CGRect(x: frame.minX, y: visibleFrame.minY, width: frame.width, height: frame.maxY - visibleFrame.minY)
    }
}
