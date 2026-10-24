/// Actions on a window right from the open switcher, by mouse or with the held modifier.
public enum SwitcherQuickAction: CaseIterable, Sendable {
    case close
    case minimize
    case hideApplication
    case quitApplication
    case leftHalf
    case maximize
    case rightHalf
    case nextDisplay

    /// The actions that apply to an item: an app without windows can only be hidden or quit,
    /// and an app that cannot be quit, such as Finder, never offers Quit.
    public static func available(isWindowless: Bool, canQuit: Bool) -> Set<SwitcherQuickAction> {
        var actions: Set<SwitcherQuickAction> = isWindowless ? [.hideApplication, .quitApplication] : Set(allCases)
        if !canQuit {
            actions.remove(.quitApplication)
        }
        return actions
    }

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

    /// The modifier is already held while the switcher is open, so every shortcut includes it.
    public func shortcut(holding modifier: SwitcherModifier) -> KeyboardShortcut {
        let mods = modifier.modifiers
        return switch self {
        case .close: KeyboardShortcut(keyCode: KeyCode.w, modifiers: mods)
        case .minimize: KeyboardShortcut(keyCode: KeyCode.m, modifiers: mods)
        case .hideApplication: KeyboardShortcut(keyCode: KeyCode.h, modifiers: mods)
        case .quitApplication: KeyboardShortcut(keyCode: KeyCode.q, modifiers: mods)
        case .leftHalf: KeyboardShortcut(keyCode: KeyCode.leftArrow, modifiers: mods.union(.shift))
        case .maximize: KeyboardShortcut(keyCode: KeyCode.f, modifiers: mods)
        case .rightHalf: KeyboardShortcut(keyCode: KeyCode.rightArrow, modifiers: mods.union(.shift))
        case .nextDisplay: KeyboardShortcut(keyCode: KeyCode.d, modifiers: mods)
        }
    }
}

/// The modifier held while switching windows; Tab is pressed with it.
public enum SwitcherModifier: String, Codable, CaseIterable, Sendable {
    /// ⌥Tab sits next to the system's ⌘Tab without taking it over.
    case option
    /// ⌘Tab replaces the macOS app switcher while Karo runs.
    case command

    public var modifiers: KeyboardShortcut.Modifiers {
        switch self {
        case .option: .option
        case .command: .command
        }
    }
}

/// How the switcher lays out windows.
public enum SwitcherStyle: String, Codable, CaseIterable, Sendable {
    /// All windows at once, with an app's windows stacked into one deck. Fastest to scan.
    case grid
    /// The selected window large in the middle, its neighbours tilted away; scrolls sideways.
    case coverFlow
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
