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

    /// Fits inside a radial menu slice.
    var shortTitle: String {
        switch self {
        case .close: String(localized: "Close", comment: "Close the window")
        case .minimize: String(localized: "Minimize")
        case .hideApplication: String(localized: "Hide", comment: "Radial menu: hide the app")
        case .quitApplication: String(localized: "Quit", comment: "Radial menu: quit the app")
        case .leftHalf: String(localized: "Left", comment: "Radial menu: left half")
        case .maximize: String(localized: "Maximize", comment: "Window action")
        case .rightHalf: String(localized: "Right", comment: "Radial menu: right half")
        case .nextDisplay: String(localized: "Display", comment: "Radial menu: move to next display")
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

    /// Clockwise from the top. Directional actions sit where they point (right half on the
    /// right, maximize at the top, minimize at the bottom); the rest fill the diagonals.
    static let radialOrder: [SwitcherQuickAction] = [
        .maximize, .nextDisplay, .rightHalf, .quitApplication,
        .minimize, .hideApplication, .leftHalf, .close,
    ]
}
