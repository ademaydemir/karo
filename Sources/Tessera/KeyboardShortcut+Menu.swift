import AppKit
import TesseraCore

extension KeyboardShortcut {
    /// Shows the shortcut next to a menu item. Only covers keys used by the default shortcuts.
    func apply(to item: NSMenuItem) {
        guard let keyEquivalent = Self.keyEquivalents[keyCode] else { return }
        item.keyEquivalent = keyEquivalent
        item.keyEquivalentModifierMask = modifierFlags
    }

    private var modifierFlags: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if modifiers.contains(.control) { flags.insert(.control) }
        if modifiers.contains(.option) { flags.insert(.option) }
        if modifiers.contains(.shift) { flags.insert(.shift) }
        if modifiers.contains(.command) { flags.insert(.command) }
        return flags
    }

    private static let keyEquivalents: [UInt32: String] = [
        // NSLeftArrowFunctionKey etc.
        KeyCode.leftArrow: "\u{F702}",
        KeyCode.rightArrow: "\u{F703}",
        KeyCode.upArrow: "\u{F700}",
        KeyCode.downArrow: "\u{F701}",
        KeyCode.returnKey: "\r",
        KeyCode.delete: "\u{8}",
        KeyCode.c: "c", KeyCode.d: "d", KeyCode.e: "e", KeyCode.f: "f", KeyCode.g: "g",
        KeyCode.i: "i", KeyCode.j: "j", KeyCode.k: "k", KeyCode.t: "t", KeyCode.u: "u",
    ]
}
