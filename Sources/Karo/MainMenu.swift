import AppKit

/// The menu bar shown while Settings is open, when Karo acts as a regular app.
///
/// Without it, standard shortcuts such as ⌘W, ⌘Q and ⌘H have no menu item to trigger.
@MainActor
enum MainMenu {
    static func make(settingsTarget: AnyObject, settingsAction: Selector) -> NSMenu {
        let mainMenu = NSMenu()

        // The application menu's title is replaced by the app name.
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: String(localized: "About Karo"),
                        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        let settingsItem = appMenu.addItem(withTitle: String(localized: "Settings…"), action: settingsAction, keyEquivalent: ",")
        settingsItem.target = settingsTarget
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: String(localized: "Hide Karo"), action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = appMenu.addItem(withTitle: String(localized: "Hide Others"),
                                         action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: String(localized: "Show All"),
                        action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: String(localized: "Quit Karo"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        mainMenu.addItem(submenuItem(appMenu))

        let windowMenu = NSMenu(title: String(localized: "Window", comment: "Menu bar menu"))
        windowMenu.addItem(withTitle: String(localized: "Close", comment: "Close the window"),
                           action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowMenu.addItem(.separator())
        windowMenu.addItem(withTitle: String(localized: "Bring All to Front"),
                           action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
        mainMenu.addItem(submenuItem(windowMenu))
        NSApp.windowsMenu = windowMenu

        return mainMenu
    }

    private static func submenuItem(_ menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: menu.title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }
}
