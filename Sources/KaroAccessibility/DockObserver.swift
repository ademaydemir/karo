import AppKit
import ApplicationServices

/// Reports the Dock icon under the pointer.
///
/// The Dock exposes its icons as an Accessibility list and marks the icon under the pointer
/// as the list's selected child, announcing each change with a notification. Only running
/// apps are reported; folders, the Trash and apps that are not open come back as `nil`.
@MainActor
public final class DockObserver {
    public struct Item: Equatable {
        public let processIdentifier: pid_t
        /// In Accessibility coordinates.
        public let frame: CGRect
    }

    private nonisolated static let bundleIdentifier = "com.apple.dock"

    private let onHover: (Item?) -> Void
    private var observer: AXObserver?
    private var list: AXUIElement?
    private var launchToken: NSObjectProtocol?

    public init(onHover: @escaping (Item?) -> Void) {
        self.onHover = onHover
    }

    /// Needs Accessibility permission. The Dock restarts now and then (e.g. when its
    /// settings change); observing starts over each time it launches.
    public func start() {
        guard launchToken == nil else { return }
        attach()
        launchToken = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let application = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard application?.bundleIdentifier == Self.bundleIdentifier else { return }
            MainActor.assumeIsolated {
                // The new Dock is not ready for Accessibility clients right away.
                _ = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(1))
                    self?.attach()
                }
            }
        }
    }

    public func stop() {
        if let launchToken { NSWorkspace.shared.notificationCenter.removeObserver(launchToken) }
        launchToken = nil
        detach()
    }

    private func attach() {
        detach()
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleIdentifier).first else { return }
        let application = AXUIElementCreateApplication(dock.processIdentifier)
        guard let children = try? application.value(of: kAXChildrenAttribute) as? [AXUIElement],
              let list = children.first(where: { (try? $0.value(of: kAXRoleAttribute) as? String) == kAXListRole }) else { return }

        var created: AXObserver?
        let callback: AXObserverCallback = { _, _, _, refcon in
            guard let refcon else { return }
            let observer = Unmanaged<DockObserver>.fromOpaque(refcon).takeUnretainedValue()
            // The run loop source is added to the main run loop.
            MainActor.assumeIsolated { observer.selectionChanged() }
        }
        guard AXObserverCreate(dock.processIdentifier, callback, &created) == .success, let observer = created,
              AXObserverAddNotification(observer, list, kAXSelectedChildrenChangedNotification as CFString,
                                        Unmanaged.passUnretained(self).toOpaque()) == .success else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        self.observer = observer
        self.list = list
    }

    private func detach() {
        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
        observer = nil
        list = nil
    }

    private func selectionChanged() {
        onHover(list.flatMap(Self.hoveredItem))
    }

    private static func hoveredItem(in list: AXUIElement) -> Item? {
        guard let selected = try? list.value(of: kAXSelectedChildrenAttribute) as? [AXUIElement],
              let icon = selected.first,
              (try? icon.value(of: kAXSubroleAttribute) as? String) == "AXApplicationDockItem",
              let url = try? icon.value(of: kAXURLAttribute) as? URL,
              let position = try? icon.point(of: kAXPositionAttribute),
              let size = try? icon.size(of: kAXSizeAttribute) else { return nil }
        let bundlePath = url.standardizedFileURL.path
        guard let application = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleURL?.standardizedFileURL.path == bundlePath
        }) else { return nil }
        return Item(processIdentifier: application.processIdentifier, frame: CGRect(origin: position, size: size))
    }
}
