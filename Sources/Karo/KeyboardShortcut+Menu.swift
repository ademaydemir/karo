import AppKit
import KaroCore

extension KeyboardShortcut {
    /// Shows the shortcut next to a menu item.
    @MainActor
    func apply(to item: NSMenuItem) {
        guard let keyEquivalent = KeyNames.menuKeyEquivalent(for: keyCode) else { return }
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
}
