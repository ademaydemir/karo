import AppKit

/// macOS's built-in window tiling (macOS 15+), which competes with drag snapping.
enum SystemTiling {
    /// "Drag windows to screen edges to tile". The key is absent until the user changes the
    /// setting, and absent means on.
    static var isEdgeDragTilingEnabled: Bool {
        let value = CFPreferencesCopyAppValue("EnableTilingByEdgeDrag" as CFString, "com.apple.WindowManager" as CFString)
        return (value as? Bool) ?? true
    }

    @MainActor
    static func openSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Desktop-Settings.extension") else { return }
        NSWorkspace.shared.open(url)
    }
}
