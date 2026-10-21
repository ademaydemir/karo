import AppKit
import TesseraAccessibility
import TesseraCore

@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    var onMenuWillOpen: (() -> Void)?
    var onAction: ((WindowAction) -> Void)?

    /// Actions offered in the menu, grouped by separators.
    private static let actionGroups: [[WindowAction]] = [
        [.leftHalf, .rightHalf, .topHalf, .bottomHalf],
        [.topLeft, .topRight, .bottomLeft, .bottomRight],
        [.leftThird, .centerThird, .rightThird, .leftTwoThirds, .rightTwoThirds],
        [.maximize, .center, .restore],
    ]

    private let shortcuts: [WindowAction: KeyboardShortcut]

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let permissionStatusItem = NSMenuItem()
    private let grantPermissionItem = NSMenuItem(
        title: "Grant Accessibility Access…",
        action: #selector(grantPermission),
        keyEquivalent: ""
    )
    private var actionItems: [NSMenuItem] = []

    init(shortcuts: [WindowAction: KeyboardShortcut]) {
        self.shortcuts = shortcuts
        super.init()
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "rectangle.split.2x2", accessibilityDescription: "Tessera")
            button.image?.isTemplate = true
        }
        statusItem.menu = makeMenu()
    }

    func update(isAccessibilityGranted: Bool) {
        permissionStatusItem.title = isAccessibilityGranted
            ? "Accessibility access granted"
            : "Accessibility access required"
        permissionStatusItem.image = NSImage(
            systemSymbolName: isAccessibilityGranted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
            accessibilityDescription: nil
        )
        grantPermissionItem.isHidden = isAccessibilityGranted
        for item in actionItems {
            item.isEnabled = isAccessibilityGranted
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
        menu.addItem(.sectionHeader(title: "Move Window"))
        for (index, group) in Self.actionGroups.enumerated() {
            if index > 0 { menu.addItem(.separator()) }
            for action in group {
                let item = NSMenuItem(title: action.title, action: #selector(performAction(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = action.rawValue
                shortcuts[action]?.apply(to: item)
                menu.addItem(item)
                actionItems.append(item)
            }
        }

        menu.addItem(.separator())
        let aboutItem = NSMenuItem(title: "About Tessera", action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)
        menu.addItem(NSMenuItem(title: "Quit Tessera", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
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

    @objc private func showAbout() {
        // Accessory apps are not active by default, so the panel would open behind other windows.
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(nil)
    }
}
