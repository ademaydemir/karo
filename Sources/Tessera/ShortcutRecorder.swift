import AppKit
import TesseraCore

/// Captures the next key combination typed in the settings window and assigns it to an action.
@MainActor
@Observable
final class ShortcutRecorder {
    private(set) var recordingAction: WindowAction?
    /// Why the last recorded combination was rejected, shown under the shortcut list.
    private(set) var rejectionMessage: String?

    @ObservationIgnored private let store: SettingsStore
    @ObservationIgnored private let shortcutController: ShortcutController
    @ObservationIgnored private var monitor: Any?

    init(store: SettingsStore, shortcutController: ShortcutController) {
        self.store = store
        self.shortcutController = shortcutController
    }

    func startRecording(_ action: WindowAction) {
        stopRecording()
        rejectionMessage = nil
        recordingAction = action
        shortcutController.suspend()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let keyCode = event.keyCode
            let shortcut = KeyboardShortcut(event: event)
            // Local monitors are called on the main thread.
            let consumed = MainActor.assumeIsolated {
                self?.handleKey(keyCode: keyCode, shortcut: shortcut) ?? false
            }
            return consumed ? nil : event
        }
    }

    func stopRecording() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        if recordingAction != nil {
            recordingAction = nil
            shortcutController.resume()
        }
    }

    func clear(_ action: WindowAction) {
        stopRecording()
        rejectionMessage = nil
        store.update { $0.setShortcut(nil, for: action) }
    }

    func resetAll() {
        stopRecording()
        rejectionMessage = nil
        store.update { $0.resetShortcuts() }
    }

    private func handleKey(keyCode: UInt16, shortcut: KeyboardShortcut?) -> Bool {
        guard let action = recordingAction else { return false }
        if UInt32(keyCode) == KeyCode.escape, shortcut == nil {
            stopRecording()
            return true
        }
        guard let shortcut else {
            rejectionMessage = String(localized: "Shortcuts need ⌃, ⌥ or ⌘.")
            NSSound.beep()
            return true
        }
        switch store.settings.conflict(for: shortcut, assigningTo: action) {
        case .windowSwitcher:
            rejectionMessage = String(localized: "\(shortcut.displayString) is used by the window switcher.")
            NSSound.beep()
        case .action(let other):
            rejectionMessage = String(
                localized: "\(shortcut.displayString) is already used by \(other.title).",
                comment: "Shortcut conflict: the shortcut, then the action already using it"
            )
            NSSound.beep()
        case nil:
            store.update { $0.setShortcut(shortcut, for: action) }
            stopRecording()
        }
        return true
    }
}
