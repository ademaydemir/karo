import AppKit
import KaroAccessibility
import KaroCore

/// The windows of all apps, in most-recently-used order, shared by the window switcher,
/// Snap Assist and layout memory.
@MainActor
final class WindowCatalog {
    struct Entry {
        let window: AXWindow
        /// Window server ID, when requested; needed for previews.
        let windowID: CGWindowID?
        let item: SwitcherItem
    }

    let previewProvider = WindowPreviewProvider()
    /// Called when any window moves, resizes or gains focus, or an app launches or quits.
    var onWindowChange: () -> Void = {}

    private var recent = RecentList<WindowIdentity>()
    private var recentApplications = RecentList<pid_t>()
    private var focusObserver: FocusedWindowObserver?
    private var activationObserver: Any?

    /// Starts recording window focus and changes. Needs Accessibility permission.
    func startTracking() {
        guard focusObserver == nil else { return }
        let observer = FocusedWindowObserver(
            onFocus: { [weak self] identity in
                self?.recent.touch(identity)
                self?.onWindowChange()
            },
            onWindowChange: { [weak self] in self?.onWindowChange() }
        )
        observer.start()
        focusObserver = observer
        if let current = try? AXWindow.focused() {
            recent.touch(current.identity)
        }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let pid = (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
            MainActor.assumeIsolated {
                if let pid {
                    self?.recentApplications.touch(pid)
                }
            }
        }
        if let frontmost = NSWorkspace.shared.frontmostApplication {
            recentApplications.touch(frontmost.processIdentifier)
        }
    }

    func touch(_ identity: WindowIdentity) {
        recent.touch(identity)
    }

    /// How recently an app was the active one: 0 is the most recent, `nil` if never since launch.
    func activationRank(of processIdentifier: pid_t) -> Int? {
        recentApplications.rank(of: processIdentifier)
    }

    /// Standard windows of regular apps in switcher order: visible windows first, most
    /// recently focused first; then minimized windows and those of hidden apps.
    /// - Parameter processIdentifier: Only this app's windows, e.g. for a Dock icon.
    func windows(includingWindowIDs: Bool, ofApplication processIdentifier: pid_t? = nil) -> [Entry] {
        let applications = Self.applications().filter { processIdentifier == nil || $0.processIdentifier == processIdentifier }
        let stack = WindowServer.windows()
        // Window IDs are needed for every window, minimized ones included.
        let allWindows = includingWindowIDs ? WindowServer.windows(onScreenOnly: false) : []

        var found: [WindowIdentity: (window: AXWindow, application: NSRunningApplication, isBackgrounded: Bool, windowID: CGWindowID?)] = [:]
        var candidates: [SwitcherOrdering.Candidate<WindowIdentity>] = []
        // Each window server window goes to one Accessibility window only.
        var matchedIDs = Set<CGWindowID>()
        for application in applications {
            for window in AXWindow.windows(ofApplication: application.processIdentifier) {
                let isBackgrounded = window.isMinimized || application.isHidden
                // The frame costs two AX calls, so it is only read when needed: for the
                // stacking order of windows never focused since launch, and for window IDs.
                let needsStackIndex = !isBackgrounded && recent.rank(of: window.identity) == nil
                let frame = (needsStackIndex || includingWindowIDs) ? try? window.frame() : nil
                let stackIndex = needsStackIndex ? frame.flatMap {
                    WindowServer.match(processIdentifier: window.processIdentifier, frame: $0, in: stack)?.index
                } : nil
                let windowID = includingWindowIDs ? frame.flatMap {
                    WindowServer.match(
                        processIdentifier: window.processIdentifier,
                        frame: $0,
                        title: window.title,
                        excluding: matchedIDs,
                        in: allWindows
                    )?.window.id
                } : nil
                if let windowID { matchedIDs.insert(windowID) }

                candidates.append(SwitcherOrdering.Candidate(id: window.identity, stackIndex: stackIndex, isBackgrounded: isBackgrounded))
                found[window.identity] = (window, application, isBackgrounded, windowID)
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
                applicationID: entry.application.processIdentifier,
                isBackgrounded: entry.isBackgrounded,
                preview: entry.windowID.flatMap(previewProvider.cachedPreview)
            )
            return Entry(window: entry.window, windowID: entry.windowID, item: item)
        }
    }

    /// Windows that are on screen (not minimized, app not hidden) with their frames.
    func visibleWindows() -> [(window: AXWindow, frame: CGRect)] {
        Self.applications()
            .filter { !$0.isHidden }
            .flatMap { AXWindow.windows(ofApplication: $0.processIdentifier) }
            .filter { !$0.isMinimized }
            .compactMap { window in (try? window.frame()).map { (window, $0) } }
    }

    /// Regular apps that are running without any window, for the switcher to reopen;
    /// most recently active first.
    /// - Parameter processesWithWindows: Apps already known to have windows, e.g. from
    ///   `windows(includingWindowIDs:)`, so their windows are not looked up again.
    func windowlessApplications(excluding processesWithWindows: Set<pid_t>) -> [NSRunningApplication] {
        let candidates = Self.applications().filter {
            !processesWithWindows.contains($0.processIdentifier)
                && AXWindow.windows(ofApplication: $0.processIdentifier).isEmpty
        }
        let orderedPIDs = SwitcherOrdering.orderApplications(candidates.map(\.processIdentifier), recent: recentApplications)
        let appsByPID = Dictionary(candidates.map { ($0.processIdentifier, $0) }, uniquingKeysWith: { first, _ in first })
        return orderedPIDs.compactMap { appsByPID[$0] }
    }

    private static func applications() -> [NSRunningApplication] {
        let ownProcess = ProcessInfo.processInfo.processIdentifier
        return NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && $0.processIdentifier != ownProcess
        }
    }
}
