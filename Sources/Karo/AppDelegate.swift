import AppKit
import OSLog
import KaroAccessibility
import KaroCore

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let logger = Logger(subsystem: "dev.ademaydemir.Karo", category: "placement")
    private let settingsStore = SettingsStore()
    private let windowPlacer = WindowPlacer()
    private let hotkeyManager = HotkeyManager()
    private lazy var shortcutController = ShortcutController(hotkeys: hotkeyManager) { [weak self] action in
        self?.perform(action)
    }
    private let windowCatalog = WindowCatalog()
    private lazy var snapZoneTracker = SnapZoneTracker(placer: windowPlacer)
    private lazy var dragSnapController = DragSnapController(placer: windowPlacer, tracker: snapZoneTracker)
    private lazy var modifierDragController = ModifierDragController(placer: windowPlacer, tracker: snapZoneTracker)
    private lazy var windowSwitcher = WindowSwitcher(hotkeys: hotkeyManager, placer: windowPlacer, catalog: windowCatalog)
    private lazy var snapAssist = SnapAssistController(catalog: windowCatalog, placer: windowPlacer, hotkeys: hotkeyManager)
    private lazy var layoutMemory = LayoutMemoryController(catalog: windowCatalog)
    private lazy var settingsWindowController = SettingsWindowController(
        store: settingsStore,
        recorder: ShortcutRecorder(store: settingsStore, shortcutController: shortcutController)
    )
    private lazy var welcomeWindowController = WelcomeWindowController(launchAtLogin: LaunchAtLogin())
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
            if isGranted { self?.startAccessibilityFeatures() }
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
        menuBarController.onShowWelcome = { [weak self] in
            self?.welcomeWindowController.show()
        }
        welcomeWindowController.onOpenSettings = { [weak self] in
            self?.openSettings()
        }
        menuBarController.update(isAccessibilityGranted: permissionMonitor.isGranted)
        self.menuBarController = menuBarController
        self.permissionMonitor = permissionMonitor

        settingsStore.onChange = { [weak self] settings in
            self?.apply(settings)
        }
        windowSwitcher.onSizeChange = { [weak self] size in
            self?.settingsStore.update { $0.switcherSize = size }
        }
        windowPlacer.onPlace = { [weak self] window, action, frame, display in
            self?.snapAssist.offer(after: window, action: action, frame: frame, display: display)
        }
        windowCatalog.onWindowChange = { [weak self] in
            self?.layoutMemory.windowsChanged()
        }
        apply(settingsStore.settings)

        // Development aid: `open Karo.app --args -ShowSettingsTab shortcuts` opens Settings on launch.
        if let tab = UserDefaults.standard.string(forKey: "ShowSettingsTab").flatMap(SettingsWindowController.Tab.init) {
            settingsWindowController.show(tab: tab)
        }

        if permissionMonitor.isGranted {
            startAccessibilityFeatures()
        } else {
            // On first launch the welcome window explains the permission before asking.
            if welcomeWindowController.hasBeenShown { AccessibilityPermission.requestIfNeeded() }
            permissionMonitor.start()
        }
        if !welcomeWindowController.hasBeenShown {
            welcomeWindowController.show()
        }
    }

    /// Everything that observes or intercepts other apps needs Accessibility permission, so it
    /// starts once the permission is there. Each part ignores repeated calls.
    private func startAccessibilityFeatures() {
        windowCatalog.startTracking()
        layoutMemory.start()
        modifierDragController.start()
    }

    /// Opening Karo again while it runs (Finder, Spotlight, Launchpad) shows Settings. With the
    /// menu bar icon hidden, this is the way back to them.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettings()
        return false
    }

    @objc private func openSettings() {
        settingsWindowController.show()
    }

    private func apply(_ settings: KaroSettings) {
        windowPlacer.gap = settings.gap
        dragSnapController.isEnabled = settings.isDragSnappingEnabled
        snapZoneTracker.detector = ZoneDetector(edgeThreshold: settings.edgeThreshold, cornerSize: settings.cornerSize)
        modifierDragController.modifiers = settings.modifierDrag.modifiers
        snapAssist.isEnabled = settings.isSnapAssistEnabled
        snapAssist.showsPreviews = settings.showsWindowPreviews
        layoutMemory.isEnabled = settings.restoresLayoutOnDisplayChange
        windowSwitcher.showsPreviews = settings.showsWindowPreviews
        windowSwitcher.size = settings.switcherSize
        windowSwitcher.style = settings.switcherStyle
        let shortcuts = settings.effectiveShortcuts
        shortcutController.apply(shortcuts)
        menuBarController?.updateShortcuts(shortcuts)
        menuBarController?.isIconVisible = settings.showsMenuBarIcon
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
