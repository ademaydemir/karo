/// A placement or navigation command that can be applied to a window.
///
/// Raw values are persisted (settings, shortcuts, URL scheme), so they must never change.
public enum WindowAction: String, Codable, CaseIterable, Sendable {
    case leftHalf, rightHalf, topHalf, bottomHalf
    case topLeft, topRight, bottomLeft, bottomRight
    case leftThird, centerThird, rightThird, leftTwoThirds, rightTwoThirds
    case maximize, center, restore
    case nextDisplay, previousDisplay
}
