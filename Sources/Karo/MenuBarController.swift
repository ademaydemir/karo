import AppKit
import KaroAccessibility
import KaroCore

@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    var onMenuWillOpen: (() -> Void)?
    var onAction: ((WindowAction) -> Void)?
    var onOpenSettings: (() -> Void)?

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let permissionStatusItem = NSMenuItem()
    private let grantPermissionItem = NSMenuItem(
        title: String(localized: "Grant Accessibility Access…"),
        action: #selector(grantPermission),
        keyEquivalent: ""
    )
    private var actionItems: [WindowAction: NSMenuItem] = [:]

    init(shortcuts: [WindowAction: KeyboardShortcut]) {
        super.init()
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "rectangle.split.2x2", accessibilityDescription: "Karo")
            button.image?.isTemplate = true
        }
        statusItem.menu = makeMenu()
        updateShortcuts(shortcuts)
    }

    func update(isAccessibilityGranted: Bool) {
        permissionStatusItem.title = isAccessibilityGranted
            ? String(localized: "Accessibility access granted")
            : String(localized: "Accessibility access required")
        permissionStatusItem.image = NSImage(
            systemSymbolName: isAccessibilityGranted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
            accessibilityDescription: nil
        )
        grantPermissionItem.isHidden = isAccessibilityGranted
        for item in actionItems.values {
            item.isEnabled = isAccessibilityGranted
        }
    }

    func updateShortcuts(_ shortcuts: [WindowAction: KeyboardShortcut]) {
        for (action, item) in actionItems {
            item.keyEquivalent = ""
            item.keyEquivalentModifierMask = []
            shortcuts[action]?.apply(to: item)
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        onMenuWillOpen?()
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        // Enabled state is driven by the permission, not by responder-chain validation.
        menu.autoenablesItems = false

        permissionStatusItem.isEnabled = false
        menu.addItem(permissionStatusItem)
        grantPermissionItem.target = self
        menu.addItem(grantPermissionItem)

        menu.addItem(.separator())
        menu.addItem(.sectionHeader(title: String(localized: "Move Window", comment: "Menu section header")))
        for (index, group) in WindowAction.groups.enumerated() {
            if index > 0 { menu.addItem(.separator()) }
            for action in group {
                let item = NSMenuItem(title: action.title, action: #selector(performAction(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = action.rawValue
                menu.addItem(item)
                actionItems[action] = item
            }
        }

        menu.addItem(.separator())
        let settingsItem = NSMenuItem(title: String(localized: "Settings…"), action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        let aboutItem = NSMenuItem(title: String(localized: "About Karo"), action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)
        menu.addItem(NSMenuItem(
            title: String(localized: "Quit Karo"),
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))
        return menu
    }

    @objc private func performAction(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let action = WindowAction(rawValue: rawValue) else { return }
        onAction?(action)
    }

    @objc private func grantPermission() {
        AccessibilityPermission.openSystemSettings()
    }

    @objc private func openSettings() {
        onOpenSettings?()
    }

    @objc private func showAbout() {
        NSApp.orderFrontStandardAboutPanel(nil)
        // Accessory apps are not active by default, so the panel would open behind other windows.
        ApplicationActivation.activateCurrentApplication()
    }
}
