import AppKit
import TesseraAccessibility

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarController: MenuBarController?
    private var permissionMonitor: AccessibilityPermissionMonitor?

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        // NSApplication holds its delegate weakly.
        withExtendedLifetime(delegate) {
            app.run()
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Info.plist sets LSUIElement for the bundled app; this also covers `swift run`.
        NSApp.setActivationPolicy(.accessory)

        let menuBarController = MenuBarController()
        let permissionMonitor = AccessibilityPermissionMonitor { [weak menuBarController] isGranted in
            menuBarController?.update(isAccessibilityGranted: isGranted)
        }
        menuBarController.onMenuWillOpen = { [weak permissionMonitor] in
            permissionMonitor?.check()
        }
        menuBarController.update(isAccessibilityGranted: permissionMonitor.isGranted)

        if !permissionMonitor.isGranted {
            AccessibilityPermission.requestIfNeeded()
            permissionMonitor.start()
        }

        self.menuBarController = menuBarController
        self.permissionMonitor = permissionMonitor
    }
}
