/// A key combination, identified by physical key position so it works on any keyboard layout.
public struct KeyboardShortcut: Hashable, Codable, Sendable {
    public struct Modifiers: OptionSet, Hashable, Codable, Sendable {
        public let rawValue: UInt8
        public init(rawValue: UInt8) { self.rawValue = rawValue }

        public static let control = Modifiers(rawValue: 1 << 0)
        public static let option = Modifiers(rawValue: 1 << 1)
        public static let shift = Modifiers(rawValue: 1 << 2)
        public static let command = Modifiers(rawValue: 1 << 3)
    }

    /// Virtual key code (`kVK_*` in Carbon's HIToolbox).
    public var keyCode: UInt32
    public var modifiers: Modifiers

    public init(keyCode: UInt32, modifiers: Modifiers) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }
}

/// Virtual key codes used by the default shortcuts, mirroring Carbon's `kVK_*` constants
/// so this module does not depend on Carbon.
public enum KeyCode {
    public static let leftArrow: UInt32 = 0x7B
    public static let rightArrow: UInt32 = 0x7C
    public static let downArrow: UInt32 = 0x7D
    public static let upArrow: UInt32 = 0x7E
    public static let returnKey: UInt32 = 0x24
    public static let delete: UInt32 = 0x33
    public static let tab: UInt32 = 0x30
    public static let escape: UInt32 = 0x35
    public static let equal: UInt32 = 0x18
    public static let minus: UInt32 = 0x1B
    public static let h: UInt32 = 0x04
    public static let m: UInt32 = 0x2E
    public static let q: UInt32 = 0x0C
    public static let w: UInt32 = 0x0D
    public static let c: UInt32 = 0x08
    public static let d: UInt32 = 0x02
    public static let e: UInt32 = 0x0E
    public static let f: UInt32 = 0x03
    public static let g: UInt32 = 0x05
    public static let i: UInt32 = 0x22
    public static let j: UInt32 = 0x26
    public static let k: UInt32 = 0x28
    public static let t: UInt32 = 0x11
    public static let u: UInt32 = 0x20
}
