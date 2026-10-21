import TesseraCore

extension SwitcherSize {
    var title: String {
        switch self {
        case .small: String(localized: "Small", comment: "Switcher size")
        case .medium: String(localized: "Medium", comment: "Switcher size")
        case .large: String(localized: "Large", comment: "Switcher size")
        }
    }
}

extension SwitcherQuickAction {
    var title: String {
        switch self {
        case .close: String(localized: "Close", comment: "Close the window")
        case .minimize: String(localized: "Minimize")
        case .hideApplication: String(localized: "Hide App")
        case .quitApplication: String(localized: "Quit App")
        case .leftHalf: String(localized: "Left Half", comment: "Window action")
        case .maximize: String(localized: "Maximize", comment: "Window action")
        case .rightHalf: String(localized: "Right Half", comment: "Window action")
        case .nextDisplay: String(localized: "Move to Next Display")
        }
    }

    var symbolName: String {
        switch self {
        case .close: "xmark"
        case .minimize: "minus"
        case .hideApplication: "eye.slash"
        case .quitApplication: "power"
        case .leftHalf: "rectangle.lefthalf.filled"
        case .maximize: "arrow.up.left.and.arrow.down.right"
        case .rightHalf: "rectangle.righthalf.filled"
        case .nextDisplay: "display.2"
        }
    }

    /// Window controls float at the top-left corner, like a window's own buttons; app
    /// controls at the top-right; placements along the bottom edge.
    static let windowControls: [SwitcherQuickAction] = [.close, .minimize]
    static let applicationControls: [SwitcherQuickAction] = [.hideApplication, .quitApplication]
    static let placements: [SwitcherQuickAction] = [.leftHalf, .maximize, .rightHalf, .nextDisplay]
}
