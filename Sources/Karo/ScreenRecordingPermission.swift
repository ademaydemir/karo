import AppKit
import CoreGraphics

/// The Screen Recording permission, needed only for window previews in the switcher.
enum ScreenRecordingPermission {
    static var isGranted: Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// Shows the system prompt the first time; afterwards macOS only lists the app in
    /// System Settings, and the app has to be relaunched once the permission is granted.
    static func request() {
        CGRequestScreenCaptureAccess()
    }

    @MainActor
    static func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
