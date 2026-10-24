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
        for (index, tab) in Tab.allCases.enumerated() {
            tabController.addTabViewItem(makeTabItem(tab, index: index, in: tabController))
        }
        self.tabController = tabController

        let window = NSWindow(contentViewController: tabController)
        window.styleMask = [.titled, .closable]
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false
        window.delegate = self
        tabController.fitWindowToSelectedTab(animated: false)
        tabController.updateWindowTitle()
        window.center()
        return window
    }

    private func makeTabItem(_ tab: Tab, index: Int, in tabController: SettingsTabViewController) -> NSTabViewItem {
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

        // No sizing options: the hosting controller would pass the size to the tab view
        // controller, which resizes the window at once. The content reports its size itself,
        // and the window follows with an animation.
        let hostingController = NSHostingController(rootView: AnyView(
            content
                .onGeometryChange(for: CGSize.self) { $0.size } action: { [weak tabController] size in
                    tabController?.contentSizeDidChange(size, forTabAt: index)
                }
                // Pinned to the top, so the content stays put while the window resizes below it.
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        ))
        hostingController.sizingOptions = []
        hostingController.title = label
        let item = NSTabViewItem(viewController: hostingController)
        item.label = label
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        return item
    }
}

/// Resizes the window to the selected tab's content, keeping its top edge in place, with an
/// animation like the settings of Apple's own apps.
final class SettingsTabViewController: NSTabViewController {
    /// About as long as Safari's settings take to resize between tabs.
    private static let resizeDuration: TimeInterval = 0.3

    /// The size each tab's content last reported, by tab index.
    private var contentSizes: [Int: CGSize] = [:]
    /// While the window resizes for another tab, its content is hidden and size reports wait.
    private var isSwitchingTabs = false

    override func viewDidLoad() {
        super.viewDidLoad()
        // Tabs swap at once and the window resize is the transition. The title changes with
        // the new content, once the window has its size.
        transitionOptions = []
        canPropagateSelectedChildViewControllerTitle = false
    }

    /// Like Safari: the old content leaves at once, the empty window resizes, then the new
    /// content and title appear together. Content resizing with the window looked like a jump.
    override func tabView(_ tabView: NSTabView, willSelect tabViewItem: NSTabViewItem?) {
        if view.window?.isVisible == true {
            tabView.isHidden = true
        }
        super.tabView(tabView, willSelect: tabViewItem)
    }

    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)
        guard view.window?.isVisible == true else {
            fitWindowToSelectedTab(animated: false)
            updateWindowTitle()
            return
        }
        isSwitchingTabs = true
        fitWindowToSelectedTab(animated: true) { [weak self] in
            guard let self else { return }
            isSwitchingTabs = false
            tabView.isHidden = false
            updateWindowTitle()
            // The new content may have reported a different size meanwhile.
            fitWindowToSelectedTab(animated: true)
        }
    }

    /// Called by a tab's content when it first lays out and whenever its size changes, e.g.
    /// when a warning appears.
    func contentSizeDidChange(_ size: CGSize, forTabAt index: Int) {
        guard contentSizes[index] != size else { return }
        contentSizes[index] = size
        guard index == selectedTabViewItemIndex, !isSwitchingTabs else { return }
        fitWindowToSelectedTab(animated: view.window?.isVisible ?? false)
    }

    func updateWindowTitle() {
        guard selectedTabViewItemIndex >= 0 else { return }
        view.window?.title = tabViewItems[selectedTabViewItemIndex].label
    }

    func fitWindowToSelectedTab(animated: Bool, completion: @escaping @MainActor () -> Void = {}) {
        guard selectedTabViewItemIndex >= 0, let window = view.window else {
            completion()
            return
        }
        // A tab not shown before has not reported its size yet, so it is measured.
        let size = contentSizes[selectedTabViewItemIndex]
            ?? tabViewItems[selectedTabViewItemIndex].viewController?.view.fittingSize
            ?? .zero
        var frame = window.frameRect(forContentRect: CGRect(origin: .zero, size: size))
        frame.origin = CGPoint(x: window.frame.minX, y: window.frame.maxY - frame.height)
        guard size.width > 0, size.height > 0, frame != window.frame else {
            completion()
            return
        }
        guard animated else {
            window.setFrame(frame, display: true)
            completion()
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.resizeDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().setFrame(frame, display: true)
        } completionHandler: {
            MainActor.assumeIsolated { completion() }
        }
    }
}
