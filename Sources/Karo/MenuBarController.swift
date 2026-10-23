import AppKit
import KaroAccessibility
import KaroCore

@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    var onMenuWillOpen: (() -> Void)?
    var onAction: ((WindowAction) -> Void)?
    var onOpenSettings: (() -> Void)?
    var onCheckForUpdates: (() -> Void)?
    var onShowWelcome: (() -> Void)?

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
        statusItem.button?.image = Self.icon()
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

    var isIconVisible: Bool {
        get { statusItem.isVisible }
        set { statusItem.isVisible = newValue }
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

    /// The app icon's four tiles as a template image: the active tile solid with its title
    /// bar cut out, the others fainter, in the same proportions as `Support/AppIcon.icon`.
    private static func icon() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            // The icon's tiles span 560 of its 1024 units; here they span 16 points.
            let unit: CGFloat = 16 / 560
            let tile = 262 * unit
            let step = 298 * unit
            let radius = 56 * unit
            let origin = CGPoint(x: 1, y: 1)
            func rect(column: Int, row: Int) -> CGRect {
                CGRect(x: origin.x + CGFloat(column) * step, y: origin.y + CGFloat(row) * step, width: tile, height: tile)
            }

            let active = NSBezierPath(roundedRect: rect(column: 0, row: 0), xRadius: radius, yRadius: radius)
            let titleBar = CGRect(x: origin.x + 36 * unit, y: origin.y + 34 * unit, width: 140 * unit, height: 24 * unit)
            active.append(NSBezierPath(roundedRect: titleBar, xRadius: 12 * unit, yRadius: 12 * unit))
            active.windingRule = .evenOdd
            NSColor.black.setFill()
            active.fill()

            for (column, row, alpha) in [(1, 0, 0.55), (0, 1, 0.35), (1, 1, 0.55)] {
                NSColor.black.withAlphaComponent(alpha).setFill()
                NSBezierPath(roundedRect: rect(column: column, row: row), xRadius: radius, yRadius: radius).fill()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Karo"
        return image
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
        let welcomeItem = NSMenuItem(title: String(localized: "Welcome Guide…"), action: #selector(showWelcome), keyEquivalent: "")
        welcomeItem.target = self
        menu.addItem(welcomeItem)
        let aboutItem = NSMenuItem(title: String(localized: "About Karo"), action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)
        let updatesItem = NSMenuItem(
            title: String(localized: "Check for Updates…"),
            action: #selector(checkForUpdates),
            keyEquivalent: ""
        )
        updatesItem.target = self
        menu.addItem(updatesItem)
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

    @objc private func showWelcome() {
        onShowWelcome?()
    }

    @objc private func checkForUpdates() {
        onCheckForUpdates?()
    }

    @objc private func showAbout() {
        NSApp.orderFrontStandardAboutPanel(nil)
        // Accessory apps are not active by default, so the panel would open behind other windows.
        ApplicationActivation.activateCurrentApplication()
    }
}
