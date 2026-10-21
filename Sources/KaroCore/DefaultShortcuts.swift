public enum DefaultShortcuts {
    /// ⌥Tab sits next to the system's ⌘Tab without taking it over.
    public static let switchWindowsForward = KeyboardShortcut(keyCode: KeyCode.tab, modifiers: [.option])
    public static let switchWindowsBackward = KeyboardShortcut(keyCode: KeyCode.tab, modifiers: [.option, .shift])

    /// Keys that only act while the switcher is open (⌥ is held then).
    public static let switcherNext = KeyboardShortcut(keyCode: KeyCode.rightArrow, modifiers: [.option])
    public static let switcherPrevious = KeyboardShortcut(keyCode: KeyCode.leftArrow, modifiers: [.option])
    public static let switcherChoose = KeyboardShortcut(keyCode: KeyCode.returnKey, modifiers: [.option])
    public static let switcherCancel = KeyboardShortcut(keyCode: KeyCode.escape, modifiers: [.option])
    public static let switcherLarger = KeyboardShortcut(keyCode: KeyCode.equal, modifiers: [.option])
    public static let switcherSmaller = KeyboardShortcut(keyCode: KeyCode.minus, modifiers: [.option])

    /// Rectangle-compatible defaults, so users switching from Rectangle keep their muscle memory.
    public static let all: [WindowAction: KeyboardShortcut] = {
        let controlOption: KeyboardShortcut.Modifiers = [.control, .option]
        func shortcut(_ keyCode: UInt32, extra: KeyboardShortcut.Modifiers = []) -> KeyboardShortcut {
            KeyboardShortcut(keyCode: keyCode, modifiers: controlOption.union(extra))
        }
        return [
            .leftHalf: shortcut(KeyCode.leftArrow),
            .rightHalf: shortcut(KeyCode.rightArrow),
            .topHalf: shortcut(KeyCode.upArrow),
            .bottomHalf: shortcut(KeyCode.downArrow),
            .topLeft: shortcut(KeyCode.u),
            .topRight: shortcut(KeyCode.i),
            .bottomLeft: shortcut(KeyCode.j),
            .bottomRight: shortcut(KeyCode.k),
            .leftThird: shortcut(KeyCode.d),
            .centerThird: shortcut(KeyCode.f),
            .rightThird: shortcut(KeyCode.g),
            .leftTwoThirds: shortcut(KeyCode.e),
            .rightTwoThirds: shortcut(KeyCode.t),
            .maximize: shortcut(KeyCode.returnKey),
            .center: shortcut(KeyCode.c),
            .restore: shortcut(KeyCode.delete),
            .nextDisplay: shortcut(KeyCode.rightArrow, extra: .command),
            .previousDisplay: shortcut(KeyCode.leftArrow, extra: .command),
        ]
    }()
}
