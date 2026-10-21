import AppKit
import ApplicationServices

/// Reports every window that gains focus, in any app, and every window move or resize.
///
/// Combines app activations (`NSWorkspace`) with per-app notifications (`AXObserver`), so
/// switching windows inside one app (e.g. between two Chrome windows) is seen too.
@MainActor
public final class FocusedWindowObserver {
    private static let focusNotifications: Set<String> = [
        kAXFocusedWindowChangedNotification,
        kAXMainWindowChangedNotification,
    ]
    private static let geometryNotifications: Set<String> = [
        kAXWindowMovedNotification,
        kAXWindowResizedNotification,
    ]

    private let onFocus: (WindowIdentity) -> Void
    private let onWindowChange: () -> Void
    private var observers: [pid_t: AXObserver] = [:]
    private var workspaceTokens: [NSObjectProtocol] = []

    /// - Parameter onWindowChange: Called when any window moves or resizes, or an app with
    ///   windows launches or quits.
    public init(onFocus: @escaping (WindowIdentity) -> Void, onWindowChange: @escaping () -> Void = {}) {
        self.onFocus = onFocus
        self.onWindowChange = onWindowChange
    }

    private func handle(_ notification: String, element: AXUIElement) {
        if Self.geometryNotifications.contains(notification) {
            onWindowChange()
        } else {
            onFocus(WindowIdentity(element: element))
        }
    }

    public func start() {
        guard workspaceTokens.isEmpty else { return }
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            observe(app.processIdentifier)
        }
        let center = NSWorkspace.shared.notificationCenter
        workspaceTokens = [
            center.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] note in
                guard let pid = Self.processIdentifier(in: note) else { return }
                MainActor.assumeIsolated {
                    self?.observe(pid, retryingOnce: true)
                    self?.onWindowChange()
                }
            },
            center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
                guard let pid = Self.processIdentifier(in: note) else { return }
                MainActor.assumeIsolated {
                    self?.stopObserving(pid)
                    self?.onWindowChange()
                }
            },
            center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
                guard let pid = Self.processIdentifier(in: note) else { return }
                MainActor.assumeIsolated { self?.reportFocusedWindow(of: pid) }
            },
        ]
    }

    private nonisolated static func processIdentifier(in notification: Notification) -> pid_t? {
        (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
    }

    private func observe(_ processIdentifier: pid_t, retryingOnce: Bool = false) {
        guard observers[processIdentifier] == nil,
              processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }

        var created: AXObserver?
        let callback: AXObserverCallback = { _, element, notification, refcon in
            guard let refcon else { return }
            let observer = Unmanaged<FocusedWindowObserver>.fromOpaque(refcon).takeUnretainedValue()
            let name = notification as String
            // The run loop source is added to the main run loop.
            MainActor.assumeIsolated {
                observer.handle(name, element: element)
            }
        }
        guard AXObserverCreate(processIdentifier, callback, &created) == .success, let observer = created else { return }

        let application = AXUIElementCreateApplication(processIdentifier)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        let added = Self.focusNotifications.union(Self.geometryNotifications).map {
            AXObserverAddNotification(observer, application, $0 as CFString, refcon) == .success
        }
        guard added.contains(true) else {
            // A freshly launched app often is not ready for Accessibility clients yet.
            if retryingOnce {
                Task { [weak self] in
                    try? await Task.sleep(for: .seconds(1))
                    self?.observe(processIdentifier)
                }
            }
            return
        }
        // Common modes keep notifications flowing while a menu is being tracked.
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        observers[processIdentifier] = observer
    }

    private func stopObserving(_ processIdentifier: pid_t) {
        guard let observer = observers.removeValue(forKey: processIdentifier) else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
    }

    private func reportFocusedWindow(of processIdentifier: pid_t) {
        let application = AXUIElementCreateApplication(processIdentifier)
        guard let window = try? application.element(of: kAXFocusedWindowAttribute) else { return }
        onFocus(WindowIdentity(element: window))
    }
}
