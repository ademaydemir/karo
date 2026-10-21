import OSLog
import KaroCore

/// Keeps the global shortcuts for window actions in sync with the settings.
@MainActor
final class ShortcutController {
    private let hotkeys: HotkeyManager
    private let perform: (WindowAction) -> Void
    private let logger = Logger(subsystem: "dev.ademaydemir.Karo", category: "shortcuts")
    private var shortcuts: [WindowAction: KeyboardShortcut] = [:]
    private var tokens: [HotkeyManager.Token] = []
    private var isSuspended = false

    init(hotkeys: HotkeyManager, perform: @escaping (WindowAction) -> Void) {
        self.hotkeys = hotkeys
        self.perform = perform
    }

    func apply(_ shortcuts: [WindowAction: KeyboardShortcut]) {
        self.shortcuts = shortcuts
        guard !isSuspended else { return }
        unregisterAll()
        registerAll()
    }

    /// Releases all shortcuts, e.g. while recording a new one, so pressing an assigned
    /// combination is captured instead of moving a window.
    func suspend() {
        isSuspended = true
        unregisterAll()
    }

    func resume() {
        guard isSuspended else { return }
        isSuspended = false
        registerAll()
    }

    private func registerAll() {
        for (action, shortcut) in shortcuts {
            do {
                tokens.append(try hotkeys.register(shortcut) { [weak self] in self?.perform(action) })
            } catch {
                // Usually another app owns the combination; the rest still work.
                logger.error("Shortcut for \(action.rawValue, privacy: .public) not registered: \(String(describing: error), privacy: .public)")
            }
        }
    }

    private func unregisterAll() {
        tokens.forEach(hotkeys.unregister)
        tokens.removeAll()
    }
}
