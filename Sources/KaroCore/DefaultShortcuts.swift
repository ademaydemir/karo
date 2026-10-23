public enum DefaultShortcuts {
    /// Keys of the window switcher for a held modifier. All but `forward` / `backward` only act
    /// while the switcher is open, when the modifier is held, so each includes it.
    public struct SwitcherKeys: Equatable, Sendable {
        public let forward, backward, next, previous, choose, cancel, larger, smaller: KeyboardShortcut
    }

    public static func switcher(_ modifier: SwitcherModifier) -> SwitcherKeys {
        let mods = modifier.modifiers
        return SwitcherKeys(
            forward: KeyboardShortcut(keyCode: KeyCode.tab, modifiers: mods),
            backward: KeyboardShortcut(keyCode: KeyCode.tab, modifiers: mods.union(.shift)),
            next: KeyboardShortcut(keyCode: KeyCode.rightArrow, modifiers: mods),
            previous: KeyboardShortcut(keyCode: KeyCode.leftArrow, modifiers: mods),
            choose: KeyboardShortcut(keyCode: KeyCode.returnKey, modifiers: mods),
            cancel: KeyboardShortcut(keyCode: KeyCode.escape, modifiers: mods),
            larger: KeyboardShortcut(keyCode: KeyCode.equal, modifiers: mods),
            smaller: KeyboardShortcut(keyCode: KeyCode.minus, modifiers: mods)
        )
    }

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
