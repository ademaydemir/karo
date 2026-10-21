import AppKit
import TesseraAccessibility

@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    var onMenuWillOpen: (() -> Void)?

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let permissionStatusItem = NSMenuItem()
    private let grantPermissionItem = NSMenuItem(
        title: "Grant Accessibility Access…",
        action: #selector(grantPermission),
        keyEquivalent: ""
    )

    override init() {
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
    }

    func menuWillOpen(_ menu: NSMenu) {
        onMenuWillOpen?()
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self

        permissionStatusItem.isEnabled = false
        menu.addItem(permissionStatusItem)
        grantPermissionItem.target = self
        menu.addItem(grantPermissionItem)

        menu.addItem(.separator())
        let aboutItem = NSMenuItem(title: "About Tessera", action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)
        menu.addItem(NSMenuItem(title: "Quit Tessera", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        return menu
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
