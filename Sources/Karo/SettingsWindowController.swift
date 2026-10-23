import AppKit
import SwiftUI
import KaroAccessibility

/// The Settings window: toolbar tabs with icons, the window titled after the selected tab
/// and resized to fit it, like the settings of Apple's own apps.
///
/// Built with AppKit because the app has no SwiftUI `App` lifecycle, so the `Settings`
/// scene is not available.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    enum Tab: String, CaseIterable {
        case general, snapping, switcher, shortcuts
    }

    private let store: SettingsStore
    private let recorder: ShortcutRecorder
    private let updater: Updater
    private let launchAtLogin = LaunchAtLogin()
    private var window: NSWindow?
    private var tabController: SettingsTabViewController?

    init(store: SettingsStore, recorder: ShortcutRecorder, updater: Updater) {
        self.store = store
        self.recorder = recorder
        self.updater = updater
    }

    func show(tab: Tab? = nil) {
        launchAtLogin.refresh()
        let window = self.window ?? makeWindow()
        self.window = window
        if let tab, let index = Tab.allCases.firstIndex(of: tab) {
            tabController?.selectedTabViewItemIndex = index
        }
        // While Settings is open Karo behaves like a regular app (Dock icon, ⌘Tab), so the
        // window can be found again and receives keyboard input for recording shortcuts.
        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        // Shown on top even if activation is refused, which would otherwise leave the window
        // behind the frontmost app.
        window.orderFrontRegardless()
        ApplicationActivation.activateCurrentApplication()
    }

    func windowWillClose(_ notification: Notification) {
        recorder.stopRecording()
        if let window { NSApp.returnToAccessoryIfNoWindowsRemain(besides: window) }
    }

    private func makeWindow() -> NSWindow {
        let tabController = SettingsTabViewController()
        tabController.tabStyle = .toolbar
        for tab in Tab.allCases {
            tabController.addTabViewItem(makeTabItem(tab))
        }
        self.tabController = tabController

        let window = NSWindow(contentViewController: tabController)
        window.styleMask = [.titled, .closable]
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false
        window.delegate = self
        tabController.fitWindowToSelectedTab(animated: false)
        window.center()
        return window
    }

    private func makeTabItem(_ tab: Tab) -> NSTabViewItem {
        let content: AnyView
        let label: String
        let symbol: String
        switch tab {
        case .general:
            content = AnyView(GeneralSettingsView(store: store, launchAtLogin: launchAtLogin, updater: updater))
            (label, symbol) = (String(localized: "General", comment: "Settings tab"), "gearshape")
        case .snapping:
            content = AnyView(SnappingSettingsView(store: store))
            (label, symbol) = (String(localized: "Snapping", comment: "Settings tab"), "rectangle.split.2x1")
        case .switcher:
            content = AnyView(SwitcherSettingsView(store: store))
            (label, symbol) = (String(localized: "Switcher", comment: "Settings tab"), "rectangle.stack")
        case .shortcuts:
            content = AnyView(ShortcutsSettingsView(store: store, recorder: recorder))
            (label, symbol) = (String(localized: "Shortcuts", comment: "Settings tab"), "keyboard")
        }

        let hostingController = NSHostingController(rootView: content)
        hostingController.sizingOptions = [.preferredContentSize]
        hostingController.title = label
        let item = NSTabViewItem(viewController: hostingController)
        item.label = label
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        return item
    }
}

/// Resizes the window to the selected tab's content, keeping its top edge in place.
final class SettingsTabViewController: NSTabViewController {
    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)
        fitWindowToSelectedTab(animated: view.window?.isVisible ?? false)
    }

    func fitWindowToSelectedTab(animated: Bool) {
        guard selectedTabViewItemIndex >= 0,
              let window = view.window,
              let content = tabViewItems[selectedTabViewItemIndex].viewController else { return }
        let size = content.preferredContentSize
        guard size.width > 0, size.height > 0 else { return }

        var frame = window.frameRect(forContentRect: CGRect(origin: .zero, size: size))
        frame.origin = CGPoint(x: window.frame.minX, y: window.frame.maxY - frame.height)
        window.setFrame(frame, display: true, animate: animated)
    }
}
