import AppKit
import OSLog
import TesseraAccessibility
import TesseraCore

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let logger = Logger(subsystem: "dev.ademaydemir.Tessera", category: "placement")
    private let windowPlacer = WindowPlacer()
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
        menuBarController.onAction = { [weak self] action in
            self?.perform(action)
        }
        menuBarController.update(isAccessibilityGranted: permissionMonitor.isGranted)

        if !permissionMonitor.isGranted {
            AccessibilityPermission.requestIfNeeded()
            permissionMonitor.start()
        }

        self.menuBarController = menuBarController
        self.permissionMonitor = permissionMonitor
    }

    private func perform(_ action: WindowAction) {
        do {
            try windowPlacer.apply(action)
        } catch {
            logger.error("\(action.rawValue, privacy: .public) failed: \(String(describing: error), privacy: .public)")
            NSSound.beep()
        }
    }
}
