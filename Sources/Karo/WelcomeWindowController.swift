import AppKit
import SwiftUI
import KaroAccessibility

/// The welcome window shown on first launch: what Karo does, the permissions it needs, the
/// switcher style and launch at login. It can be opened again from the menu bar.
@MainActor
final class WelcomeWindowController: NSObject, NSWindowDelegate {
    private static let hasBeenShownKey = "hasShownWelcome"

    /// Called when the user asks for Settings from the last step.
    var onOpenSettings: () -> Void = {}

    private let launchAtLogin: LaunchAtLogin
    private let store: SettingsStore
    private let defaults: UserDefaults
    private var window: NSWindow?

    init(launchAtLogin: LaunchAtLogin, store: SettingsStore, defaults: UserDefaults = .standard) {
        self.launchAtLogin = launchAtLogin
        self.store = store
        self.defaults = defaults
    }

    var hasBeenShown: Bool {
        defaults.bool(forKey: Self.hasBeenShownKey)
    }

    func show() {
        launchAtLogin.refresh()
        // A fresh window each time, so it starts at the first step.
        window?.close()
        let window = makeWindow()
        self.window = window
        defaults.set(true, forKey: Self.hasBeenShownKey)
        // Like Settings: a regular app while open, so it can be found again with ⌘Tab.
        NSApp.setActivationPolicy(.regular)
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        ApplicationActivation.activateCurrentApplication()
    }

    func windowWillClose(_ notification: Notification) {
        guard let closing = notification.object as? NSWindow else { return }
        if closing === window { window = nil }
        NSApp.returnToAccessoryIfNoWindowsRemain(besides: closing)
    }

    private func makeWindow() -> NSWindow {
        let view = WelcomeView(launchAtLogin: launchAtLogin, store: store) { [weak self] next in
            self?.window?.close()
            if next == .settings { self?.onOpenSettings() }
        }
        let hostingView = NSHostingView(rootView: view)
        hostingView.sizingOptions = []

        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: WelcomeView.size),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        // The whole window is glass, so the desktop shows through, blurred.
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentView = GlassSurface.make(cornerRadius: 0, content: hostingView)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.title = String(localized: "Welcome to Karo")
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.delegate = self
        return window
    }
}

extension NSApplication {
    /// Karo is a menu bar app and only shows in the Dock and ⌘Tab while one of its windows
    /// is open. Called as a window closes; the other windows may still be open.
    func returnToAccessoryIfNoWindowsRemain(besides closing: NSWindow) {
        let othersOpen = windows.contains { $0 !== closing && $0.isVisible && $0.styleMask.contains(.titled) }
        if !othersOpen { setActivationPolicy(.accessory) }
    }
}
