import AppKit
import OSLog
import TesseraAccessibility
import TesseraCore

/// Windows-style ⌥Tab switching between individual windows.
///
/// While ⌥ is held, Tab / ⇧Tab move the selection and releasing ⌥ activates the selected
/// window. A quick tap switches to the previous window without the panel ever appearing.
@MainActor
final class WindowSwitcher {
    private struct Session {
        let windows: [AXWindow]
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

    private let hotkeys: HotkeyManager
    private let panel = SwitcherPanel()
    private let previewProvider = WindowPreviewProvider()
    private let logger = Logger(subsystem: "dev.ademaydemir.Tessera", category: "switcher")
    private var recent = RecentList<WindowIdentity>()
    private var focusObserver: FocusedWindowObserver?
    private var session: Session?

    init(hotkeys: HotkeyManager) {
        self.hotkeys = hotkeys
        panel.model.onHover = { [weak self] index in
            guard let self, let cursorAtShow = session?.cursorAtShow, NSEvent.mouseLocation != cursorAtShow else { return }
            select(index)
        }
        panel.model.onChoose = { [weak self] index in
            self?.select(index)
            self?.commit()
        }
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
        panel.model.items = entries.map(\.item)
        var session = Session(windows: entries.map(\.window), selection: SwitcherSelection(count: entries.count))
        if capturesPreviews {
            let targets = entries.enumerated().compactMap { index, entry in
                entry.windowID.map { (item: index, windowID: $0) }
            }
            session.previewTask = Task { [weak self] in
                await self?.previewProvider.capturePreviews(for: targets) { index, preview in
                    guard let self, self.panel.model.items.indices.contains(index) else { return }
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
        guard let session else { return }
        let window = session.windows[session.selection.index]
        close()
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

    /// Keys that only act while the switcher is open, so they keep working in other apps
    /// otherwise. ⌥ is held at this point, so each arrives with the Option modifier.
    private func registerSessionHotkeys() -> [HotkeyManager.Token] {
        let bindings: [(UInt32, @MainActor () -> Void)] = [
            (KeyCode.escape, { [weak self] in self?.close() }),
            (KeyCode.returnKey, { [weak self] in self?.commit() }),
            (KeyCode.rightArrow, { [weak self] in self?.press(backward: false) }),
            (KeyCode.leftArrow, { [weak self] in self?.press(backward: true) }),
        ]
        return bindings.compactMap { keyCode, handler in
            try? hotkeys.register(KeyboardShortcut(keyCode: keyCode, modifiers: [.option]), handler: handler)
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
