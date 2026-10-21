import CoreGraphics

/// User preferences, persisted as JSON.
///
/// Shortcuts are stored as differences from `DefaultShortcuts`, so actions added in later
/// versions get their default shortcut instead of appearing unassigned.
public struct KaroSettings: Codable, Equatable, Sendable {
    public var gap: CGFloat = 0
    public var isDragSnappingEnabled = true
    public var edgeThreshold: CGFloat = 5
    public var cornerSize: CGFloat = 40
    /// Live window thumbnails in the switcher; needs Screen Recording permission, so off by default.
    public var showsWindowPreviews = false
    public var switcherSize = SwitcherSize.medium
    public var switcherStyle = SwitcherStyle.grid
    public var restoresLayoutOnDisplayChange = true
    public var isSnapAssistEnabled = true
    public var modifierDrag = ModifierDrag.controlOption
    public var customShortcuts: [WindowAction: KeyboardShortcut] = [:]
    public var disabledShortcuts: Set<WindowAction> = []

    public init() {}

    public var effectiveShortcuts: [WindowAction: KeyboardShortcut] {
        var shortcuts: [WindowAction: KeyboardShortcut] = [:]
        for action in WindowAction.allCases {
            shortcuts[action] = shortcut(for: action)
        }
        return shortcuts
    }

    public func shortcut(for action: WindowAction) -> KeyboardShortcut? {
        guard !disabledShortcuts.contains(action) else { return nil }
        return customShortcuts[action] ?? DefaultShortcuts.all[action]
    }

    /// Assigns a shortcut; `nil` leaves the action without one.
    public mutating func setShortcut(_ shortcut: KeyboardShortcut?, for action: WindowAction) {
        customShortcuts[action] = nil
        disabledShortcuts.remove(action)
        guard let shortcut else {
            disabledShortcuts.insert(action)
            return
        }
        if shortcut != DefaultShortcuts.all[action] {
            customShortcuts[action] = shortcut
        }
    }

    public mutating func resetShortcuts() {
        customShortcuts = [:]
        disabledShortcuts = []
    }

    public enum ShortcutConflict: Equatable, Sendable {
        case action(WindowAction)
        case windowSwitcher
    }

    /// What else already uses `shortcut`, ignoring `action` itself.
    public func conflict(for shortcut: KeyboardShortcut, assigningTo action: WindowAction) -> ShortcutConflict? {
        if shortcut == DefaultShortcuts.switchWindowsForward || shortcut == DefaultShortcuts.switchWindowsBackward {
            return .windowSwitcher
        }
        let other = WindowAction.allCases.first { $0 != action && self.shortcut(for: $0) == shortcut }
        return other.map(ShortcutConflict.action)
    }

    // Decoding field by field keeps settings saved by older versions readable when fields are added.
    private enum CodingKeys: String, CodingKey {
        case gap, isDragSnappingEnabled, edgeThreshold, cornerSize, showsWindowPreviews, switcherSize, switcherStyle
        case restoresLayoutOnDisplayChange, isSnapAssistEnabled, modifierDrag
        case customShortcuts, disabledShortcuts
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = KaroSettings()
        gap = try container.decodeIfPresent(CGFloat.self, forKey: .gap) ?? defaults.gap
        isDragSnappingEnabled = try container.decodeIfPresent(Bool.self, forKey: .isDragSnappingEnabled)
            ?? defaults.isDragSnappingEnabled
        edgeThreshold = try container.decodeIfPresent(CGFloat.self, forKey: .edgeThreshold) ?? defaults.edgeThreshold
        cornerSize = try container.decodeIfPresent(CGFloat.self, forKey: .cornerSize) ?? defaults.cornerSize
        showsWindowPreviews = try container.decodeIfPresent(Bool.self, forKey: .showsWindowPreviews)
            ?? defaults.showsWindowPreviews
        // An unknown size from a newer version falls back to the default instead of failing.
        switcherSize = (try? container.decodeIfPresent(SwitcherSize.self, forKey: .switcherSize)) ?? defaults.switcherSize
        switcherStyle = (try? container.decodeIfPresent(SwitcherStyle.self, forKey: .switcherStyle)) ?? defaults.switcherStyle
        restoresLayoutOnDisplayChange = try container.decodeIfPresent(Bool.self, forKey: .restoresLayoutOnDisplayChange)
            ?? defaults.restoresLayoutOnDisplayChange
        isSnapAssistEnabled = try container.decodeIfPresent(Bool.self, forKey: .isSnapAssistEnabled)
            ?? defaults.isSnapAssistEnabled
        modifierDrag = (try? container.decodeIfPresent(ModifierDrag.self, forKey: .modifierDrag)) ?? defaults.modifierDrag
        customShortcuts = try container.decodeIfPresent([WindowAction: KeyboardShortcut].self, forKey: .customShortcuts)
            ?? defaults.customShortcuts
        disabledShortcuts = try container.decodeIfPresent(Set<WindowAction>.self, forKey: .disabledShortcuts)
            ?? defaults.disabledShortcuts
    }
}

/// Encodes `[WindowAction: …]` as a JSON object keyed by raw value instead of a flat array.
extension WindowAction: CodingKeyRepresentable {}
