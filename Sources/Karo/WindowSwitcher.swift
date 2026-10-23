import AppKit
import OSLog
import KaroAccessibility
import KaroCore

/// Window switching between individual windows rather than apps.
///
/// While the modifier is held, Tab / ⇧Tab move the selection and releasing it activates the selected
/// window. A quick tap switches to the previous window without the panel ever appearing.
/// Windows can also be closed, minimized or placed right from the panel.
@MainActor
final class WindowSwitcher {
    /// What an item switches to: a window, or an app running without windows that is reopened.
    @MainActor
    private enum Target {
        case window(AXWindow)
        case application(NSRunningApplication)

        var processIdentifier: pid_t {
            switch self {
            case .window(let window):
                window.processIdentifier
            case .application(let application):
                application.processIdentifier
            }
        }
    }

    private struct Entry {
        let target: Target
        let windowID: CGWindowID?
        let item: SwitcherItem
    }

    private struct Session {
        /// Parallel to `panel.model.items`.
        var targets: [Target]
        var selection: SwitcherSelection
        var temporaryHotkeys: [HotkeyManager.Token] = []
        var eventMonitors: [Any] = []
        var showTask: Task<Void, Never>?
        var previewTask: Task<Void, Never>?
        /// Cursor location when the panel appeared; hover only selects after the mouse moves,
        /// so a panel opening under a resting cursor does not steal the selection.
        var cursorAtShow: CGPoint?
        /// Where the first forward press goes: the previously used window. In the grid the
        /// items are in display order, so this is not simply the next item.
        var previousWindowIndex: Int?
        var hasMoved = false
    }

    /// A tap released within this delay switches without showing the panel.
    private static let panelDelay: Duration = .milliseconds(150)
    /// Some apps bring their previously main window back on activation; raising again
    /// shortly after makes the chosen window win.
    private static let reraiseDelay: Duration = .milliseconds(60)

    /// Live window thumbnails; only effective with Screen Recording permission.
    var showsPreviews = false
    var size = SwitcherSize.medium {
        didSet { panel.model.size = size }
    }
    var style = SwitcherStyle.grid {
        didSet { panel.model.style = style }
    }
    var modifier = SwitcherModifier.option {
        didSet {
            guard modifier != oldValue else { return }
            close()
            do {
                try registerShortcuts()
            } catch {
                logger.error("Window switcher shortcuts not registered: \(String(describing: error), privacy: .public)")
            }
        }
    }
    /// Called when the user resizes the switcher with the held modifier and + / −, so the choice is saved.
    var onSizeChange: (SwitcherSize) -> Void = { _ in }

    private let hotkeys: HotkeyManager
    private let placer: WindowPlacer
    private let catalog: WindowCatalog
    private let panel = SwitcherPanel()
    private let logger = Logger(subsystem: "dev.ademaydemir.Karo", category: "switcher")
    private var session: Session?
    private var switchTokens: [HotkeyManager.Token] = []

    private var modifierFlags: NSEvent.ModifierFlags {
        switch modifier {
        case .option: .option
        case .command: .command
        }
    }

    init(hotkeys: HotkeyManager, placer: WindowPlacer, catalog: WindowCatalog) {
        self.hotkeys = hotkeys
        self.placer = placer
        self.catalog = catalog
        panel.model.onHover = { [weak self] index in
            guard let self, let cursorAtShow = session?.cursorAtShow, NSEvent.mouseLocation != cursorAtShow else { return }
            select(index)
        }
        panel.model.onChoose = { [weak self] index in
            self?.select(index)
            self?.commit()
        }
        panel.model.onQuickAction = { [weak self] index, action in
            self?.perform(action, at: index)
        }
        panel.model.onSelect = { [weak self] index in
            self?.select(index)
            Haptics.tick()
        }
        panel.model.onScrollStep = { [weak self] step in
            guard let self, session != nil else { return }
            if step > 0 {
                session?.selection.moveForward()
            } else {
                session?.selection.moveBackward()
            }
            panel.model.selectedIndex = session?.selection.index ?? 0
            Haptics.tick()
        }
    }

    func registerShortcuts() throws {
        switchTokens.forEach(hotkeys.unregister)
        switchTokens = []
        let keys = DefaultShortcuts.switcher(modifier)
        let forward = try hotkeys.register(keys.forward) { [weak self] in self?.press(backward: false) }
        let backward = try hotkeys.register(keys.backward) { [weak self] in self?.press(backward: true) }
        switchTokens = [forward, backward]
    }

    // MARK: - Session

    private func press(backward: Bool) {
        if session == nil {
            guard open() else { return }
        }
        if backward {
            session?.selection.moveBackward()
        } else if session?.hasMoved == false, let previous = session?.previousWindowIndex {
            // A quick tap still goes back to the previous window; after that, Tab walks
            // the items in the order they are shown.
            session?.selection.select(previous)
        } else {
            session?.selection.moveForward()
        }
        session?.hasMoved = true
        panel.model.selectedIndex = session?.selection.index ?? 0
    }

    private func open() -> Bool {
        guard AccessibilityPermission.isGranted else {
            NSSound.beep()
            return false
        }
        let windowEntries = catalog.windows(includingWindowIDs: showsPreviews)
        let windowlessApps = catalog.windowlessApplications(excluding: Set(windowEntries.map(\.item.applicationID)))
        guard !windowEntries.isEmpty || !windowlessApps.isEmpty else { return false }

        var entries: [Entry] = windowEntries.map {
            Entry(target: .window($0.window), windowID: $0.windowID, item: $0.item)
        }
        var nextID = entries.count
        for app in windowlessApps {
            let appName = app.localizedName ?? ""
            let item = SwitcherItem(
                id: nextID,
                title: appName,
                applicationName: appName,
                icon: app.icon ?? NSImage(),
                applicationID: app.processIdentifier,
                isBackgrounded: true,
                preview: nil,
                isWindowless: true
            )
            entries.append(Entry(target: .application(app), windowID: nil, item: item))
            nextID += 1
        }

        // Most recently used first; the second is the item a quick tap returns to.
        let previousItemID = entries.count > 1 ? entries[1].item.id : nil
        if style == .grid {
            // The grid shows each app's windows as one deck; listing them deck by deck lets
            // Tab walk through a deck before moving on to the next.
            entries = SwitcherOrdering.grouped(entries) { $0.item.applicationID }
        }

        let capturesPreviews = showsPreviews && ScreenRecordingPermission.isGranted
        panel.model.showsPreviews = capturesPreviews
        panel.model.size = size
        panel.model.style = style
        panel.model.modifier = modifier
        panel.model.hints = hints
        panel.model.items = entries.map(\.item)
        panel.model.selectedIndex = 0
        panel.prepare()
        var session = Session(targets: entries.map(\.target), selection: SwitcherSelection(count: entries.count))
        session.previousWindowIndex = previousItemID.flatMap { id in entries.firstIndex { $0.item.id == id } }
        if capturesPreviews {
            let targets = entries.compactMap { entry in
                entry.windowID.map { (item: entry.item.id, windowID: $0) }
            }
            session.previewTask = Task { [weak self] in
                await self?.catalog.previewProvider.capturePreviews(for: targets) { itemID, preview in
                    // Items may have been removed meanwhile, so match by ID rather than position.
                    guard let self, let index = self.panel.model.items.firstIndex(where: { $0.id == itemID }) else { return }
                    self.panel.model.items[index].preview = preview
                }
            }
        }
        session.temporaryHotkeys = registerSessionHotkeys()
        session.eventMonitors = installModifierMonitors()
        session.showTask = Task { [weak self] in
            try? await Task.sleep(for: Self.panelDelay)
            guard !Task.isCancelled else { return }
            self?.showPanelIfStillHeld()
        }
        self.session = session
        return true
    }

    private func showPanelIfStillHeld() {
        guard session != nil else { return }
        // Safety net in case the modifier release was missed.
        guard NSEvent.modifierFlags.contains(modifierFlags) else {
            commit()
            return
        }
        session?.cursorAtShow = NSEvent.mouseLocation
        panel.show()
    }

    private func select(_ index: Int) {
        session?.selection.select(index)
        // After pointing at a window, Tab continues from there rather than jumping to the
        // previous window.
        session?.hasMoved = true
        panel.model.selectedIndex = session?.selection.index ?? 0
    }

    private func commit() {
        guard let session, session.targets.indices.contains(session.selection.index) else {
            close()
            return
        }
        let target = session.targets[session.selection.index]
        close()
        switch target {
        case .window(let window):
            activate(window)
        case .application(let app):
            reopen(app)
        }
    }

    private func activate(_ window: AXWindow) {
        do {
            try window.bringToFront()
            catalog.touch(window.identity)
            Task {
                try? await Task.sleep(for: Self.reraiseDelay)
                window.raise()
            }
        } catch {
            logger.error("Switching window failed: \(String(describing: error), privacy: .public)")
            NSSound.beep()
        }
    }

    private func reopen(_ application: NSRunningApplication) {
        if let bundleURL = application.bundleURL {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            Task { @MainActor [weak self] in
                do {
                    _ = try await NSWorkspace.shared.openApplication(at: bundleURL, configuration: config)
                } catch {
                    self?.logger.error("Reopening application failed: \(String(describing: error), privacy: .public)")
                    NSSound.beep()
                }
            }
        } else if !application.activate() {
            logger.error("Activating application failed")
            NSSound.beep()
        }
    }

    private func close() {
        guard let session else { return }
        session.showTask?.cancel()
        session.previewTask?.cancel()
        session.temporaryHotkeys.forEach(hotkeys.unregister)
        session.eventMonitors.forEach(NSEvent.removeMonitor)
        panel.hide()
        self.session = nil
    }

    // MARK: - Quick actions

    private func perform(_ action: SwitcherQuickAction, at index: Int) {
        guard let session, session.targets.indices.contains(index) else { return }
        let target = session.targets[index]
        let pid = target.processIdentifier
        let application = NSRunningApplication(processIdentifier: pid)
        switch target {
        case .window(let window):
            do {
                switch action {
                case .close:
                    try window.close()
                    removeItems { $0 == index }
                case .minimize:
                    try window.minimize()
                    panel.model.items[index].isBackgrounded = true
                case .hideApplication:
                    application?.hide()
                    markItems(ofProcess: pid, backgrounded: true)
                case .quitApplication:
                    application?.terminate()
                    let targets = session.targets
                    removeItems { targets[$0].processIdentifier == pid }
                case .leftHalf, .rightHalf, .maximize, .nextDisplay:
                    guard let placement = action.windowAction else { return }
                    close()
                    activate(window)
                    try placer.apply(placement, to: window)
                }
            } catch {
                logger.error("Quick action failed: \(String(describing: error), privacy: .public)")
                NSSound.beep()
            }
        case .application:
            switch action {
            case .hideApplication:
                application?.hide()
                markItems(ofProcess: pid, backgrounded: true)
            case .quitApplication:
                application?.terminate()
                let targets = session.targets
                removeItems { targets[$0].processIdentifier == pid }
            case .close, .minimize, .leftHalf, .rightHalf, .maximize, .nextDisplay:
                NSSound.beep()
            }
        }
    }

    /// Drops items whose window is gone, keeping the panel open on the remaining ones.
    private func removeItems(where shouldRemove: (Int) -> Bool) {
        guard var session else { return }
        for index in session.targets.indices.reversed() where shouldRemove(index) {
            session.targets.remove(at: index)
            session.selection.remove(at: index)
            panel.model.items.remove(at: index)
        }
        self.session = session
        guard !session.targets.isEmpty else {
            close()
            return
        }
        panel.model.selectedIndex = session.selection.index
        panel.relayout()
    }

    private func markItems(ofProcess processIdentifier: pid_t, backgrounded: Bool) {
        guard let session else { return }
        for index in session.targets.indices where session.targets[index].processIdentifier == processIdentifier {
            panel.model.items[index].isBackgrounded = backgrounded
        }
    }

    private func resize(larger: Bool) {
        let newSize = larger ? size.larger : size.smaller
        guard newSize != size else { return }
        size = newSize
        onSizeChange(newSize)
        panel.relayout()
    }

    // MARK: - Keys

    /// Quick action keys shown at the bottom of the panel.
    private var hints: [SwitcherHint] {
        let keys = DefaultShortcuts.switcher(modifier)
        let actions: [SwitcherQuickAction] = [.close, .minimize, .hideApplication, .quitApplication, .maximize]
        var hints = actions.map { SwitcherHint(keys: $0.shortcut(holding: modifier).displayString, title: $0.title) }
        hints.insert(
            SwitcherHint(
                keys: "\(SwitcherQuickAction.leftHalf.shortcut(holding: modifier).displayString) \(SwitcherQuickAction.rightHalf.shortcut(holding: modifier).displayString)",
                title: String(localized: "Halves")
            ),
            at: 4
        )
        hints.append(SwitcherHint(
            keys: "\(keys.larger.displayString) \(keys.smaller.displayString)",
            title: String(localized: "Size")
        ))
        return hints
    }

    /// Keys that only act while the switcher is open, so they keep working in other apps
    /// otherwise. The modifier is held at this point, so each includes it.
    private func registerSessionHotkeys() -> [HotkeyManager.Token] {
        let keys = DefaultShortcuts.switcher(modifier)
        var bindings: [(KeyboardShortcut, @MainActor () -> Void)] = [
            (keys.cancel, { [weak self] in self?.close() }),
            (keys.choose, { [weak self] in self?.commit() }),
            (keys.next, { [weak self] in self?.press(backward: false) }),
            (keys.previous, { [weak self] in self?.press(backward: true) }),
            (keys.larger, { [weak self] in self?.resize(larger: true) }),
            (keys.smaller, { [weak self] in self?.resize(larger: false) }),
        ]
        for action in SwitcherQuickAction.allCases {
            bindings.append((action.shortcut(holding: modifier), { [weak self] in
                guard let self, let index = session?.selection.index else { return }
                perform(action, at: index)
            }))
        }
        return bindings.compactMap { shortcut, handler in
            try? hotkeys.register(shortcut, handler: handler)
        }
    }

    private func installModifierMonitors() -> [Any] {
        let modifierFlags = self.modifierFlags
        let handler: (NSEvent) -> Void = { [weak self] event in
            guard !event.modifierFlags.contains(modifierFlags) else { return }
            // Event monitors are called on the main thread.
            MainActor.assumeIsolated { self?.commit() }
        }
        let global = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: handler)
        let local = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            handler(event)
            return event
        }
        return [global, local].compactMap { $0 }
    }
}
