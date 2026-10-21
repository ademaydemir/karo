import AppKit
import OSLog
import TesseraAccessibility
import TesseraCore

/// Windows-style ⌥Tab switching between individual windows.
///
/// While ⌥ is held, Tab / ⇧Tab move the selection and releasing ⌥ activates the selected
/// window. A quick tap switches to the previous window without the panel ever appearing.
/// Windows can also be closed, minimized or placed right from the panel.
@MainActor
final class WindowSwitcher {
    private struct Session {
        /// Parallel to `panel.model.items`.
        var windows: [AXWindow]
        var selection: SwitcherSelection
        var temporaryHotkeys: [HotkeyManager.Token] = []
        var eventMonitors: [Any] = []
        var showTask: Task<Void, Never>?
        var previewTask: Task<Void, Never>?
        /// Cursor location when the panel appeared; hover only selects after the mouse moves,
        /// so a panel opening under a resting cursor does not steal the selection.
        var cursorAtShow: CGPoint?
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
    /// Called when the user resizes the switcher with ⌥+ / ⌥−, so the choice is saved.
    var onSizeChange: (SwitcherSize) -> Void = { _ in }

    private let hotkeys: HotkeyManager
    private let placer: WindowPlacer
    private let panel = SwitcherPanel()
    private let previewProvider = WindowPreviewProvider()
    private let logger = Logger(subsystem: "dev.ademaydemir.Tessera", category: "switcher")
    private var recent = RecentList<WindowIdentity>()
    private var focusObserver: FocusedWindowObserver?
    private var session: Session?

    init(hotkeys: HotkeyManager, placer: WindowPlacer) {
        self.hotkeys = hotkeys
        self.placer = placer
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
        panel.model.hints = Self.hints
    }

    func registerShortcuts() throws {
        try hotkeys.register(DefaultShortcuts.switchWindowsForward) { [weak self] in self?.press(backward: false) }
        try hotkeys.register(DefaultShortcuts.switchWindowsBackward) { [weak self] in self?.press(backward: true) }
    }

    /// Starts recording window focus for most-recently-used ordering. Needs Accessibility permission.
    func startTrackingFocus() {
        guard focusObserver == nil else { return }
        let observer = FocusedWindowObserver { [weak self] identity in
            self?.recent.touch(identity)
        }
        observer.start()
        focusObserver = observer
        if let current = try? AXWindow.focused() {
            recent.touch(current.identity)
        }
    }

    // MARK: - Session

    private func press(backward: Bool) {
        if session == nil {
            guard open() else { return }
        }
        if backward {
            session?.selection.moveBackward()
        } else {
            session?.selection.moveForward()
        }
        panel.model.selectedIndex = session?.selection.index ?? 0
    }

    private func open() -> Bool {
        guard AccessibilityPermission.isGranted else {
            NSSound.beep()
            return false
        }
        let entries = collectWindows()
        guard !entries.isEmpty else { return false }

        let capturesPreviews = showsPreviews && ScreenRecordingPermission.isGranted
        panel.model.showsPreviews = capturesPreviews
        panel.model.size = size
        panel.model.items = entries.map(\.item)
        panel.model.selectedIndex = 0
        var session = Session(windows: entries.map(\.window), selection: SwitcherSelection(count: entries.count))
        if capturesPreviews {
            let targets = entries.compactMap { entry in
                entry.windowID.map { (item: entry.item.id, windowID: $0) }
            }
            session.previewTask = Task { [weak self] in
                await self?.previewProvider.capturePreviews(for: targets) { itemID, preview in
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
        // Safety net in case the ⌥ release was missed.
        guard NSEvent.modifierFlags.contains(.option) else {
            commit()
            return
        }
        session?.cursorAtShow = NSEvent.mouseLocation
        panel.show()
    }

    private func select(_ index: Int) {
        session?.selection.select(index)
        panel.model.selectedIndex = session?.selection.index ?? 0
    }

    private func commit() {
        guard let session, session.windows.indices.contains(session.selection.index) else {
            close()
            return
        }
        let window = session.windows[session.selection.index]
        close()
        activate(window)
    }

    private func activate(_ window: AXWindow) {
        do {
            try window.bringToFront()
            recent.touch(window.identity)
            Task {
                try? await Task.sleep(for: Self.reraiseDelay)
                window.raise()
            }
        } catch {
            logger.error("Switching window failed: \(String(describing: error), privacy: .public)")
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
        guard let session, session.windows.indices.contains(index) else { return }
        let window = session.windows[index]
        let application = NSRunningApplication(processIdentifier: window.processIdentifier)
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
                markItems(ofProcess: window.processIdentifier, backgrounded: true)
            case .quitApplication:
                application?.terminate()
                let windows = session.windows
                removeItems { windows[$0].processIdentifier == window.processIdentifier }
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
    }

    /// Drops items whose window is gone, keeping the panel open on the remaining ones.
    private func removeItems(where shouldRemove: (Int) -> Bool) {
        guard var session else { return }
        for index in session.windows.indices.reversed() where shouldRemove(index) {
            session.windows.remove(at: index)
            session.selection.remove(at: index)
            panel.model.items.remove(at: index)
        }
        self.session = session
        guard !session.windows.isEmpty else {
            close()
            return
        }
        panel.model.selectedIndex = session.selection.index
        panel.relayout()
    }

    private func markItems(ofProcess processIdentifier: pid_t, backgrounded: Bool) {
        guard let session else { return }
        for index in session.windows.indices where session.windows[index].processIdentifier == processIdentifier {
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
    private static var hints: [SwitcherHint] {
        let actions: [SwitcherQuickAction] = [.close, .minimize, .hideApplication, .quitApplication, .maximize]
        var hints = actions.map { SwitcherHint(keys: $0.shortcut.displayString, title: $0.title) }
        hints.insert(
            SwitcherHint(
                keys: "\(SwitcherQuickAction.leftHalf.shortcut.displayString) \(SwitcherQuickAction.rightHalf.shortcut.displayString)",
                title: String(localized: "Halves")
            ),
            at: 4
        )
        hints.append(SwitcherHint(
            keys: "\(DefaultShortcuts.switcherLarger.displayString) \(DefaultShortcuts.switcherSmaller.displayString)",
            title: String(localized: "Size")
        ))
        return hints
    }

    /// Keys that only act while the switcher is open, so they keep working in other apps
    /// otherwise. ⌥ is held at this point, so each includes the Option modifier.
    private func registerSessionHotkeys() -> [HotkeyManager.Token] {
        var bindings: [(KeyboardShortcut, @MainActor () -> Void)] = [
            (DefaultShortcuts.switcherCancel, { [weak self] in self?.close() }),
            (DefaultShortcuts.switcherChoose, { [weak self] in self?.commit() }),
            (DefaultShortcuts.switcherNext, { [weak self] in self?.press(backward: false) }),
            (DefaultShortcuts.switcherPrevious, { [weak self] in self?.press(backward: true) }),
            (DefaultShortcuts.switcherLarger, { [weak self] in self?.resize(larger: true) }),
            (DefaultShortcuts.switcherSmaller, { [weak self] in self?.resize(larger: false) }),
        ]
        for action in SwitcherQuickAction.allCases {
            bindings.append((action.shortcut, { [weak self] in
                guard let self, let index = session?.selection.index else { return }
                perform(action, at: index)
            }))
        }
        return bindings.compactMap { shortcut, handler in
            try? hotkeys.register(shortcut, handler: handler)
        }
    }

    private func installModifierMonitors() -> [Any] {
        let handler: (NSEvent) -> Void = { [weak self] event in
            guard !event.modifierFlags.contains(.option) else { return }
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

    // MARK: - Window list

    private struct FoundWindow {
        let window: AXWindow
        let application: NSRunningApplication
        let isBackgrounded: Bool
        let windowID: CGWindowID?
    }

    private func collectWindows() -> [(window: AXWindow, windowID: CGWindowID?, item: SwitcherItem)] {
        let ownProcess = ProcessInfo.processInfo.processIdentifier
        let applications = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && $0.processIdentifier != ownProcess
        }
        let stack = WindowServer.windows()
        // Previews need window IDs for every window, minimized ones included.
        let allWindows = showsPreviews ? WindowServer.windows(onScreenOnly: false) : []

        var found: [WindowIdentity: FoundWindow] = [:]
        var candidates: [SwitcherOrdering.Candidate<WindowIdentity>] = []
        for application in applications {
            for window in AXWindow.windows(ofApplication: application.processIdentifier) {
                let isBackgrounded = window.isMinimized || application.isHidden
                // The frame costs two AX calls, so it is only read when needed: for the
                // stacking order of windows never focused since launch, and for previews.
                let needsStackIndex = !isBackgrounded && recent.rank(of: window.identity) == nil
                let frame = (needsStackIndex || showsPreviews) ? try? window.frame() : nil
                let stackIndex = needsStackIndex ? frame.flatMap {
                    WindowServer.match(processIdentifier: window.processIdentifier, frame: $0, in: stack)?.index
                } : nil
                let windowID = showsPreviews ? frame.flatMap {
                    WindowServer.match(processIdentifier: window.processIdentifier, frame: $0, in: allWindows)?.window.id
                } : nil

                candidates.append(SwitcherOrdering.Candidate(id: window.identity, stackIndex: stackIndex, isBackgrounded: isBackgrounded))
                found[window.identity] = FoundWindow(
                    window: window, application: application, isBackgrounded: isBackgrounded, windowID: windowID
                )
            }
        }

        return SwitcherOrdering.order(candidates, recent: recent).enumerated().compactMap { index, identity in
            guard let entry = found[identity] else { return nil }
            let applicationName = entry.application.localizedName ?? ""
            let title = entry.window.title
            let item = SwitcherItem(
                id: index,
                title: title.isEmpty ? applicationName : title,
                applicationName: applicationName,
                icon: entry.application.icon ?? NSImage(),
                isBackgrounded: entry.isBackgrounded,
                preview: entry.windowID.flatMap(previewProvider.cachedPreview)
            )
            return (entry.window, entry.windowID, item)
        }
    }
}
