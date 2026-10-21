import Carbon.HIToolbox
import TesseraCore

enum HotkeyError: Error {
    case handlerInstallationFailed(OSStatus)
    /// `eventHotKeyExistsErr` (-9878) means another app already owns the shortcut.
    case registrationFailed(KeyboardShortcut, OSStatus)
}

/// Registers system-wide keyboard shortcuts through the Carbon Event Manager.
///
/// `RegisterEventHotKey` is still the only public API for global shortcuts that needs no
/// Input Monitoring permission and only sees the registered combinations, not every key press.
///
/// The Carbon callback holds an unretained pointer to the manager, so it must live as long
/// as the app (it is owned by `AppDelegate`).
@MainActor
final class HotkeyManager {
    private static let signature: OSType = 0x5453_5241 // "TSRA"

    private var handlers: [UInt32: @MainActor () -> Void] = [:]
    private var hotKeyRefs: [EventHotKeyRef] = []
    private var nextID: UInt32 = 1
    private var eventHandler: EventHandlerRef?

    func register(_ shortcut: KeyboardShortcut, handler: @escaping @MainActor () -> Void) throws {
        try installEventHandlerIfNeeded()

        let id = nextID
        nextID += 1
        var hotKeyRef: EventHotKeyRef?
        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.modifiers.carbonFlags,
            EventHotKeyID(signature: Self.signature, id: id),
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        guard status == noErr, let hotKeyRef else {
            throw HotkeyError.registrationFailed(shortcut, status)
        }
        hotKeyRefs.append(hotKeyRef)
        handlers[id] = handler
    }

    func unregisterAll() {
        for hotKeyRef in hotKeyRefs {
            UnregisterEventHotKey(hotKeyRef)
        }
        hotKeyRefs.removeAll()
        handlers.removeAll()
    }

    private func handle(_ hotKeyID: EventHotKeyID) {
        guard hotKeyID.signature == Self.signature, let handler = handlers[hotKeyID.id] else { return }
        handler()
    }

    private func installEventHandlerIfNeeded() throws {
        guard eventHandler == nil else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return OSStatus(eventNotHandledErr) }
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard status == noErr else { return status }
                let pressedID = hotKeyID
                let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                // Carbon dispatches application-target events on the main thread.
                MainActor.assumeIsolated {
                    manager.handle(pressedID)
                }
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
        guard status == noErr else { throw HotkeyError.handlerInstallationFailed(status) }
    }
}

private extension KeyboardShortcut.Modifiers {
    var carbonFlags: UInt32 {
        var flags = 0
        if contains(.command) { flags |= cmdKey }
        if contains(.option) { flags |= optionKey }
        if contains(.control) { flags |= controlKey }
        if contains(.shift) { flags |= shiftKey }
        return UInt32(flags)
    }
}
