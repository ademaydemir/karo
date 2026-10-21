/// A placement or navigation command that can be applied to a window.
///
/// Raw values are persisted (settings, shortcuts, URL scheme), so they must never change.
public enum WindowAction: String, Codable, CaseIterable, Sendable {
    case leftHalf, rightHalf, topHalf, bottomHalf
    case topLeft, topRight, bottomLeft, bottomRight
    case leftThird, centerThird, rightThird, leftTwoThirds, rightTwoThirds
    case maximize, center, restore
    case nextDisplay, previousDisplay

    /// The placements that together fill the rest of the display, in the order Snap Assist
    /// offers them. A quarter leaves two regions: the other quarter on its side first, then
    /// the opposite half. Placements that leave no clean regions (maximize, center, the
    /// center third) have none.
    public var snapAssistRegions: [WindowAction] {
        switch self {
        case .leftHalf: [.rightHalf]
        case .rightHalf: [.leftHalf]
        case .topHalf: [.bottomHalf]
        case .bottomHalf: [.topHalf]
        case .leftThird: [.rightTwoThirds]
        case .rightThird: [.leftTwoThirds]
        case .leftTwoThirds: [.rightThird]
        case .rightTwoThirds: [.leftThird]
        case .topLeft: [.bottomLeft, .rightHalf]
        case .bottomLeft: [.topLeft, .rightHalf]
        case .topRight: [.bottomRight, .leftHalf]
        case .bottomRight: [.topRight, .leftHalf]
        default: []
        }
    }
}
