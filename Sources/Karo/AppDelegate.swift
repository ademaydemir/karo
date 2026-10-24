import AppKit
import OSLog
import KaroAccessibility
import KaroCore

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let logger = Logger(subsystem: "dev.ademaydemir.Karo", category: "placement")
    private let lifecycleLogger = Logger(subsystem: "dev.ademaydemir.Karo", category: "lifecycle")
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
    private lazy var dockPreview = DockPreviewController(catalog: windowCatalog)
    private let updater = Updater()
    private lazy var settingsWindowController = SettingsWindowController(
        store: settingsStore,
        recorder: ShortcutRecorder(store: settingsStore, shortcutController: shortcutController),
        updater: updater
    )
    private lazy var welcomeWindowController = WelcomeWindowController(launchAtLogin: LaunchAtLogin(), store: settingsStore)
    private var menuBarController: MenuBarController?
    private var permissionMonitor: AccessibilityPermissionMonitor?
    private var runningApplicationsObservation: NSKeyValueObservation?
    /// Other copies that get a moment to quit by themselves before this one quits them.
    private var copiesBeingQuit: Set<pid_t> = []
    /// Set when this copy quits right after launch (another copy is running, or it is
    /// moving to Applications), so it leaves shared state such as the ⌘Tab switcher alone.
    private var isHandingOver = false

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
        // Opening a second copy (e.g. the one inside the downloaded disk image) while Karo runs
        // would put two icons in the menu bar and register every shortcut twice.
        if let running = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
            .first(where: { $0 != .current }),
           let url = running.bundleURL {
            isHandingOver = true
            // Opening the running copy again makes it show Settings (see applicationShouldHandleReopen).
            // A copy opened from the disk image ejects it on the way out.
            let diskImage = DiskImage.volume(containing: Bundle.main.bundleURL)
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, _ in
                Task { @MainActor in AppRelaunch.quit(ejecting: diskImage) }
            }
            return
        }

        if let move = MoveToApplications.offerIfNeeded() {
            isHandingOver = true
            AppRelaunch.relaunch(from: move.destination, ejecting: move.diskImage)
            return
        }

        // Info.plist sets LSUIElement for the bundled app; this also covers `swift run`.
        NSApp.setActivationPolicy(.accessory)
        NSApp.mainMenu = MainMenu.make(
            settingsTarget: self,
            settingsAction: #selector(openSettings),
            updatesTarget: self,
            updatesAction: #selector(checkForUpdates)
        )

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
        menuBarController.onCheckForUpdates = { [weak self] in
            self?.updater.checkForUpdates()
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

        // `open Karo.app --args -ShowSettingsTab shortcuts` opens Settings on launch. Restarting for a
        // new language uses it to bring Settings back; it is also handy in development.
        if let tab = UserDefaults.standard.string(forKey: "ShowSettingsTab").flatMap(SettingsWindowController.Tab.init) {
            settingsWindowController.show(tab: tab)
        }

        #if DEBUG
        // Development aid: `open Karo.app --args -CaptureReadmeAssets <dir>` records the README animations.
        if let path = UserDefaults.standard.string(forKey: "CaptureReadmeAssets") {
            Task { await ReadmeCapture.run(to: URL(fileURLWithPath: path)) }
        }
        #endif

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

        watchForOtherCopies()
    }

    /// Everything that observes or intercepts other apps needs Accessibility permission, so it
    /// starts once the permission is there. Each part ignores repeated calls.
    private func startAccessibilityFeatures() {
        windowCatalog.startTracking()
        layoutMemory.start()
        modifierDragController.start()
        dockPreview.start()
    }

    /// Copies older than 0.1.1 do not check for a running Karo when they start, so the copy
    /// that is already running quits them; newer copies quit by themselves.
    private func watchForOtherCopies() {
        // NSWorkspace posts no launch notification for menu bar apps like Karo, so watch the
        // list of running applications instead.
        runningApplicationsObservation = NSWorkspace.shared.observe(\.runningApplications) { [weak self] _, _ in
            Task { @MainActor [weak self] in self?.quitOtherCopies() }
        }
    }

    private func quitOtherCopies() {
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
            .filter { $0 != .current && !copiesBeingQuit.contains($0.processIdentifier) }
        for other in others {
            let pid = other.processIdentifier
            copiesBeingQuit.insert(pid)
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(2))
                defer { self?.copiesBeingQuit.remove(pid) }
                guard let self,
                      let runningApp = NSRunningApplication(processIdentifier: pid),
                      !runningApp.isTerminated
                else { return }

                let path = runningApp.bundleURL?.path ?? "<unknown>"
                runningApp.terminate()
                self.lifecycleLogger.info("Terminated older copy of Karo at \(path, privacy: .public)")
                self.openSettings()
                // The quitting copy turns the macOS ⌘Tab switcher back on as it exits.
                try? await Task.sleep(for: .seconds(1))
                SystemAppSwitcher.setEnabled(self.settingsStore.settings.switcherModifier != .command)
            }
        }
    }

    /// Opening Karo again while it runs (Finder, Spotlight, Launchpad) shows Settings. With the
    /// menu bar icon hidden, this is the way back to them.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard !isHandingOver else { return false }
        openSettings()
        return false
    }

    /// Turns the macOS app switcher back on if Karo had disabled it for ⌘Tab switching.
    func applicationWillTerminate(_ notification: Notification) {
        // The ⌘Tab switcher belongs to the instance that keeps running.
        guard !isHandingOver else { return }
        SystemAppSwitcher.setEnabled(true)
    }

    @objc private func openSettings() {
        settingsWindowController.show()
    }

    @objc private func checkForUpdates() {
        updater.checkForUpdates()
    }

    private func apply(_ settings: KaroSettings) {
        windowPlacer.gap = settings.gap
        dragSnapController.isEnabled = settings.isDragSnappingEnabled
        snapZoneTracker.detector = ZoneDetector(edgeThreshold: settings.edgeThreshold, cornerSize: settings.cornerSize)
        modifierDragController.modifiers = settings.modifierDrag.modifiers
        snapAssist.isEnabled = settings.isSnapAssistEnabled
        snapAssist.showsPreviews = settings.showsWindowPreviews
        layoutMemory.isEnabled = settings.restoresLayoutOnDisplayChange
        dockPreview.isEnabled = settings.isDockPreviewEnabled
        windowSwitcher.showsPreviews = settings.showsWindowPreviews
        windowSwitcher.showsWindowlessApps = settings.showsWindowlessApps
        windowSwitcher.size = settings.switcherSize
        windowSwitcher.style = settings.switcherStyle
        SystemAppSwitcher.setEnabled(settings.switcherModifier != .command)
        windowSwitcher.modifier = settings.switcherModifier
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
