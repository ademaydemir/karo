public enum DefaultShortcuts {
    /// Rectangle-compatible defaults, so users switching from Rectangle keep their muscle memory.
    ///
    /// `.nextDisplay` / `.previousDisplay` (⌃⌥⌘→ / ⌃⌥⌘←) are added once moving between
    /// displays is implemented.
    public static let all: [WindowAction: KeyboardShortcut] = {
        let controlOption: KeyboardShortcut.Modifiers = [.control, .option]
        func shortcut(_ keyCode: UInt32) -> KeyboardShortcut {
            KeyboardShortcut(keyCode: keyCode, modifiers: controlOption)
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
        ]
    }()
}
