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
}
