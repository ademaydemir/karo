import AppKit
import Carbon.HIToolbox
import TesseraCore

/// Human-readable names and menu key equivalents for virtual key codes.
@MainActor
enum KeyNames {
    private struct SpecialKey {
        let symbol: String
        let menuKeyEquivalent: String
    }

    /// Keys whose label does not come from the keyboard layout. Menu equivalents are the
    /// AppKit function-key characters (NSLeftArrowFunctionKey etc.).
    private static let specialKeys: [Int: SpecialKey] = [
        kVK_LeftArrow: SpecialKey(symbol: "←", menuKeyEquivalent: "\u{F702}"),
        kVK_RightArrow: SpecialKey(symbol: "→", menuKeyEquivalent: "\u{F703}"),
        kVK_UpArrow: SpecialKey(symbol: "↑", menuKeyEquivalent: "\u{F700}"),
        kVK_DownArrow: SpecialKey(symbol: "↓", menuKeyEquivalent: "\u{F701}"),
        kVK_Return: SpecialKey(symbol: "↩", menuKeyEquivalent: "\r"),
        kVK_Delete: SpecialKey(symbol: "⌫", menuKeyEquivalent: "\u{8}"),
        kVK_ForwardDelete: SpecialKey(symbol: "⌦", menuKeyEquivalent: "\u{7F}"),
        kVK_Tab: SpecialKey(symbol: "⇥", menuKeyEquivalent: "\t"),
        kVK_Escape: SpecialKey(symbol: "⎋", menuKeyEquivalent: "\u{1B}"),
        kVK_Space: SpecialKey(symbol: String(localized: "Space", comment: "Space bar in a shortcut"), menuKeyEquivalent: " "),
        kVK_Home: SpecialKey(symbol: "↖", menuKeyEquivalent: "\u{F729}"),
        kVK_End: SpecialKey(symbol: "↘", menuKeyEquivalent: "\u{F72B}"),
        kVK_PageUp: SpecialKey(symbol: "⇞", menuKeyEquivalent: "\u{F72C}"),
        kVK_PageDown: SpecialKey(symbol: "⇟", menuKeyEquivalent: "\u{F72D}"),
        kVK_F1: SpecialKey(symbol: "F1", menuKeyEquivalent: "\u{F704}"),
        kVK_F2: SpecialKey(symbol: "F2", menuKeyEquivalent: "\u{F705}"),
        kVK_F3: SpecialKey(symbol: "F3", menuKeyEquivalent: "\u{F706}"),
        kVK_F4: SpecialKey(symbol: "F4", menuKeyEquivalent: "\u{F707}"),
        kVK_F5: SpecialKey(symbol: "F5", menuKeyEquivalent: "\u{F708}"),
        kVK_F6: SpecialKey(symbol: "F6", menuKeyEquivalent: "\u{F709}"),
        kVK_F7: SpecialKey(symbol: "F7", menuKeyEquivalent: "\u{F70A}"),
        kVK_F8: SpecialKey(symbol: "F8", menuKeyEquivalent: "\u{F70B}"),
        kVK_F9: SpecialKey(symbol: "F9", menuKeyEquivalent: "\u{F70C}"),
        kVK_F10: SpecialKey(symbol: "F10", menuKeyEquivalent: "\u{F70D}"),
        kVK_F11: SpecialKey(symbol: "F11", menuKeyEquivalent: "\u{F70E}"),
        kVK_F12: SpecialKey(symbol: "F12", menuKeyEquivalent: "\u{F70F}"),
    ]

    /// E.g. "⌃⌥←" or "⌃⌥U", in Apple's modifier order.
    static func displayString(for shortcut: KeyboardShortcut) -> String {
        var text = ""
        if shortcut.modifiers.contains(.control) { text += "⌃" }
        if shortcut.modifiers.contains(.option) { text += "⌥" }
        if shortcut.modifiers.contains(.shift) { text += "⇧" }
        if shortcut.modifiers.contains(.command) { text += "⌘" }
        let key = specialKeys[Int(shortcut.keyCode)]?.symbol ?? character(for: shortcut.keyCode)?.uppercased() ?? "?"
        return text + key
    }

    static func menuKeyEquivalent(for keyCode: UInt32) -> String? {
        specialKeys[Int(keyCode)]?.menuKeyEquivalent ?? character(for: keyCode)?.lowercased()
    }

    /// The character the key produces in the current keyboard layout, so labels match
    /// what is printed on the user's keyboard (e.g. Turkish Q, AZERTY).
    private static func character(for keyCode: UInt32) -> String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let layoutPointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let layoutData = Unmanaged<CFData>.fromOpaque(layoutPointer).takeUnretainedValue()
        guard let bytes = CFDataGetBytePtr(layoutData) else { return nil }

        var deadKeyState: UInt32 = 0
        var characters = [UniChar](repeating: 0, count: 4)
        var length = 0
        let status = bytes.withMemoryRebound(to: UCKeyboardLayout.self, capacity: 1) { layout in
            UCKeyTranslate(
                layout,
                UInt16(keyCode),
                UInt16(kUCKeyActionDisplay),
                0,
                UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState,
                characters.count,
                &length,
                &characters
            )
        }
        guard status == noErr, length > 0 else { return nil }
        return String(utf16CodeUnits: characters, count: length)
    }
}

extension KeyboardShortcut {
    init?(event: NSEvent) {
        var modifiers: Modifiers = []
        let flags = event.modifierFlags
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.command) { modifiers.insert(.command) }
        // Shift alone would steal ordinary typing (capital letters) system-wide.
        guard !modifiers.isDisjoint(with: [.control, .option, .command]) else { return nil }
        self.init(keyCode: UInt32(event.keyCode), modifiers: modifiers)
    }

    @MainActor
    var displayString: String {
        KeyNames.displayString(for: self)
    }
}
