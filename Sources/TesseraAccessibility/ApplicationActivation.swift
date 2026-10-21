import AppKit
import ApplicationServices

public enum ApplicationActivation {
    /// Makes Tessera the active app, e.g. to show its Settings window.
    ///
    /// Since macOS 14 `NSApp.activate()` is only a request that the active app may refuse,
    /// and a menu bar app is usually refused. Setting `kAXFrontmostAttribute` on our own
    /// app element, which the Accessibility permission allows, is honoured.
    @MainActor
    public static func activateCurrentApplication() {
        NSApp.activate()
        guard AccessibilityPermission.isGranted else { return }
        let application = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
        AXUIElementSetAttributeValue(application, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
    }
}
