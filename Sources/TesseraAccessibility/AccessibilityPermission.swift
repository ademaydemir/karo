import AppKit
import ApplicationServices

/// Access to the system Accessibility (TCC) permission that Tessera needs to move other apps' windows.
public enum AccessibilityPermission {
    public static var isGranted: Bool {
        AXIsProcessTrusted()
    }

    /// Shows the system prompt that links to System Settings if permission is missing.
    /// - Returns: Whether permission is already granted.
    @discardableResult
    public static func requestIfNeeded() -> Bool {
        // `kAXTrustedCheckOptionPrompt` is a mutable C global that Swift 6 rejects as not
        // concurrency-safe; its value is this fixed string.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    @MainActor
    public static func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
