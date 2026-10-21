/// Actions on a window right from the open switcher, by mouse or with ⌥ held.
public enum SwitcherQuickAction: CaseIterable, Sendable {
    case close
    case minimize
    case hideApplication
    case quitApplication
    case leftHalf
    case maximize
    case rightHalf
    case nextDisplay

    /// The placement it performs, for actions that also activate and place the window.
    public var windowAction: WindowAction? {
        switch self {
        case .leftHalf: .leftHalf
        case .rightHalf: .rightHalf
        case .maximize: .maximize
        case .nextDisplay: .nextDisplay
        case .close, .minimize, .hideApplication, .quitApplication: nil
        }
    }

    /// ⌥ is already held while the switcher is open, so every shortcut includes it.
    public var shortcut: KeyboardShortcut {
        switch self {
        case .close: KeyboardShortcut(keyCode: KeyCode.w, modifiers: [.option])
        case .minimize: KeyboardShortcut(keyCode: KeyCode.m, modifiers: [.option])
        case .hideApplication: KeyboardShortcut(keyCode: KeyCode.h, modifiers: [.option])
        case .quitApplication: KeyboardShortcut(keyCode: KeyCode.q, modifiers: [.option])
        case .leftHalf: KeyboardShortcut(keyCode: KeyCode.leftArrow, modifiers: [.option, .shift])
        case .maximize: KeyboardShortcut(keyCode: KeyCode.f, modifiers: [.option])
        case .rightHalf: KeyboardShortcut(keyCode: KeyCode.rightArrow, modifiers: [.option, .shift])
        case .nextDisplay: KeyboardShortcut(keyCode: KeyCode.d, modifiers: [.option])
        }
    }
}

/// How large the switcher draws its items.
public enum SwitcherSize: String, Codable, CaseIterable, Sendable {
    case small, medium, large

    public var larger: SwitcherSize {
        switch self {
        case .small: .medium
        case .medium, .large: .large
        }
    }

    public var smaller: SwitcherSize {
        switch self {
        case .large: .medium
        case .medium, .small: .small
        }
    }
}
