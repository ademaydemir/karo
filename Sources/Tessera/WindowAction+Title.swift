import TesseraCore

extension WindowAction {
    /// Actions grouped as they appear in the menu and in Settings.
    static let groups: [[WindowAction]] = [
        [.leftHalf, .rightHalf, .topHalf, .bottomHalf],
        [.topLeft, .topRight, .bottomLeft, .bottomRight],
        [.leftThird, .centerThird, .rightThird, .leftTwoThirds, .rightTwoThirds],
        [.maximize, .center, .restore],
        [.nextDisplay, .previousDisplay],
    ]

    var title: String {
        switch self {
        case .leftHalf: String(localized: "Left Half", comment: "Window action")
        case .rightHalf: String(localized: "Right Half", comment: "Window action")
        case .topHalf: String(localized: "Top Half", comment: "Window action")
        case .bottomHalf: String(localized: "Bottom Half", comment: "Window action")
        case .topLeft: String(localized: "Top Left", comment: "Window action")
        case .topRight: String(localized: "Top Right", comment: "Window action")
        case .bottomLeft: String(localized: "Bottom Left", comment: "Window action")
        case .bottomRight: String(localized: "Bottom Right", comment: "Window action")
        case .leftThird: String(localized: "Left Third", comment: "Window action")
        case .centerThird: String(localized: "Center Third", comment: "Window action")
        case .rightThird: String(localized: "Right Third", comment: "Window action")
        case .leftTwoThirds: String(localized: "Left Two Thirds", comment: "Window action")
        case .rightTwoThirds: String(localized: "Right Two Thirds", comment: "Window action")
        case .maximize: String(localized: "Maximize", comment: "Window action")
        case .center: String(localized: "Center", comment: "Window action")
        case .restore: String(localized: "Restore", comment: "Window action")
        case .nextDisplay: String(localized: "Next Display", comment: "Window action")
        case .previousDisplay: String(localized: "Previous Display", comment: "Window action")
        }
    }
}
