import AppKit
import OSLog
import TesseraAccessibility
import TesseraCore

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let logger = Logger(subsystem: "dev.ademaydemir.Tessera", category: "placement")
    private let settingsStore = SettingsStore()
    private let windowPlacer = WindowPlacer()
    private let hotkeyManager = HotkeyManager()
    private lazy var shortcutController = ShortcutController(hotkeys: hotkeyManager) { [weak self] action in
        self?.perform(action)
    }
    private lazy var dragSnapController = DragSnapController(placer: windowPlacer)
    private lazy var windowSwitcher = WindowSwitcher(hotkeys: hotkeyManager)
    private lazy var settingsWindowController = SettingsWindowController(
        store: settingsStore,
        recorder: ShortcutRecorder(store: settingsStore, shortcutController: shortcutController)
    )
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
        NSApp.mainMenu = MainMenu.make(settingsTarget: self, settingsAction: #selector(openSettings))

        dragSnapController.start()
        do {
            try windowSwitcher.registerShortcuts()
        } catch {
            logger.error("Window switcher shortcuts not registered: \(String(describing: error), privacy: .public)")
        }

        let menuBarController = MenuBarController(shortcuts: settingsStore.settings.effectiveShortcuts)
        let permissionMonitor = AccessibilityPermissionMonitor { [weak self, weak menuBarController] isGranted in
            menuBarController?.update(isAccessibilityGranted: isGranted)
            if isGranted { self?.windowSwitcher.startTrackingFocus() }
        }
        menuBarController.onMenuWillOpen = { [weak permissionMonitor] in
            permissionMonitor?.check()
        }
        menuBarController.onAction = { [weak self] action in
            self?.perform(action)
        }
        menuBarController.onOpenSettings = { [weak self] in
            self?.openSettings()
        }
        menuBarController.update(isAccessibilityGranted: permissionMonitor.isGranted)
        self.menuBarController = menuBarController
        self.permissionMonitor = permissionMonitor

        settingsStore.onChange = { [weak self] settings in
            self?.apply(settings)
        }
        apply(settingsStore.settings)

        // Development aid: `open Tessera.app --args -ShowSettingsTab shortcuts` opens Settings on launch.
        if let tab = UserDefaults.standard.string(forKey: "ShowSettingsTab").flatMap(SettingsWindowController.Tab.init) {
            settingsWindowController.show(tab: tab)
        }

        if permissionMonitor.isGranted {
            windowSwitcher.startTrackingFocus()
        } else {
            AccessibilityPermission.requestIfNeeded()
            permissionMonitor.start()
        }
    }

    @objc private func openSettings() {
        settingsWindowController.show()
    }

    private func apply(_ settings: TesseraSettings) {
        windowPlacer.gap = settings.gap
        dragSnapController.isEnabled = settings.isDragSnappingEnabled
        dragSnapController.detector = ZoneDetector(edgeThreshold: settings.edgeThreshold, cornerSize: settings.cornerSize)
        windowSwitcher.showsPreviews = settings.showsWindowPreviews
        let shortcuts = settings.effectiveShortcuts
        shortcutController.apply(shortcuts)
        menuBarController?.updateShortcuts(shortcuts)
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
