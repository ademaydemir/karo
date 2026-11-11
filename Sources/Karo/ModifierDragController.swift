import AppKit
import OSLog
import KaroAccessibility
import KaroCore

/// Moves a window by dragging anywhere inside it with the modifier keys held, and resizes it
/// with a right-button drag from the nearest corner, as on many Linux desktops.
///
/// Unlike the title-bar drag, this has to keep the click from reaching the app, so it uses
/// an event tap rather than an event monitor. The tap only swallows clicks while the exact
/// modifier combination is held over a window; everything else passes through untouched.
/// The tap runs on its own thread so that clicks in other apps never wait for the main thread.
@MainActor
final class ModifierDragController {
    private enum Gesture {
        case move(window: AXWindow, startFrame: CGRect, startCursor: CGPoint, hasRestoredSize: Bool)
        case resize(window: AXWindow, startFrame: CGRect, startCursor: CGPoint, corner: ResizeGeometry.Corner, session: LinkedEdgeResize?, lastFrame: CGRect)
    }

    /// What the tap thread needs to decide whether an event concerns Karo. It cannot ask the
    /// main actor without blocking on the main thread, which is what the tap must avoid.
    private final class TapState: @unchecked Sendable {
        private let lock = NSLock()
        private var _modifiers: KeyboardShortcut.Modifiers?
        private var _isGestureActive = false
        private var _tap: CFMachPort?

        var modifiers: KeyboardShortcut.Modifiers? {
            get { lock.withLock { _modifiers } }
            set { lock.withLock { _modifiers = newValue } }
        }
        var isGestureActive: Bool {
            get { lock.withLock { _isGestureActive } }
            set { lock.withLock { _isGestureActive = newValue } }
        }
        var tap: CFMachPort? {
            get { lock.withLock { _tap } }
            set { lock.withLock { _tap = newValue } }
        }
    }

    /// Hands a non-Sendable value to the tap thread, which only passes it on to Core Foundation.
    private struct UncheckedBox<Value>: @unchecked Sendable {
        let value: Value
    }

    /// `nil` turns the feature off and removes the event tap.
    var modifiers: KeyboardShortcut.Modifiers? = [.control, .option] {
        didSet {
            tapState.modifiers = modifiers
            updateTap()
        }
    }

    private let placer: WindowPlacer
    private let tracker: SnapZoneTracker
    private let logger = Logger(subsystem: "dev.ademaydemir.Karo", category: "modifier-drag")
    private nonisolated let tapState = TapState()
    private var tap: CFMachPort?
    private var gesture: Gesture? {
        didSet { tapState.isGestureActive = gesture != nil }
    }

    init(placer: WindowPlacer, tracker: SnapZoneTracker) {
        self.placer = placer
        self.tracker = tracker
        // `didSet` does not fire for the default value.
        tapState.modifiers = modifiers
    }

    /// Installs the event tap. Needs Accessibility permission; call again once it is granted.
    func start() {
        updateTap()
    }

    private func updateTap() {
        if modifiers == nil {
            removeTap()
        } else if tap == nil {
            installTap()
        }
    }

    private func installTap() {
        let types: [CGEventType] = [.leftMouseDown, .leftMouseDragged, .leftMouseUp, .rightMouseDown, .rightMouseDragged, .rightMouseUp]
        let mask = types.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            // The controller lives as long as the app.
            let controller = Unmanaged<ModifierDragController>.fromOpaque(refcon).takeUnretainedValue()
            let state = controller.tapState
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                // macOS disables taps that respond too slowly; turn it back on right here.
                if let tap = state.tap { CGEvent.tapEnable(tap: tap, enable: true) }
                return Unmanaged.passUnretained(event)
            }
            let isPress = type == .leftMouseDown || type == .rightMouseDown
            guard ModifierDragPolicy.isRelevant(
                isPress: isPress,
                held: ModifierDragController.modifiers(in: event.flags),
                configured: state.modifiers,
                isGestureActive: state.isGestureActive
            ) else { return Unmanaged.passUnretained(event) }
            // Only the configured combination or an active gesture blocks on the main thread.
            let location = event.location
            let flags = event.flags
            var consumed = false
            DispatchQueue.main.sync {
                consumed = MainActor.assumeIsolated {
                    controller.handle(type, location: location, flags: flags)
                }
            }
            return consumed ? nil : Unmanaged.passUnretained(event)
        }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            logger.info("Event tap not available yet (Accessibility permission missing)")
            return
        }
        self.tap = tap
        tapState.tap = tap
        let source = UncheckedBox(value: CFMachPortCreateRunLoopSource(nil, tap, 0))
        let thread = Thread {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source.value, .commonModes)
            CFRunLoopRun()
        }
        thread.name = "dev.ademaydemir.Karo.event-tap"
        thread.qualityOfService = .userInteractive
        thread.start()
    }

    private func removeTap() {
        // Invalidating the port removes its source, and a run loop without sources returns from
        // `CFRunLoopRun`, so the tap thread ends by itself. Never wait for it: it may be in `main.sync`.
        if let tap { CFMachPortInvalidate(tap) }
        tap = nil
        tapState.tap = nil
        cancelGesture()
        tracker.cancel()
    }

    private func cancelGesture() {
        switch gesture {
        case .resize(_, _, _, _, let session, _):
            session?.cancel()
        case .move:
            tracker.cancel()
        case nil:
            break
        }
        gesture = nil
    }

    /// - Returns: Whether the event was handled and must not reach the app.
    private func handle(_ type: CGEventType, location: CGPoint, flags: CGEventFlags) -> Bool {
        switch type {
        case .leftMouseDown, .rightMouseDown:
            return begin(isResize: type == .rightMouseDown, at: location, flags: flags)
        case .leftMouseDragged:
            return continueMove(to: location, flags: flags)
        case .rightMouseDragged:
            return continueResize(to: location)
        case .leftMouseUp:
            guard case .move(let window, _, _, _) = gesture else { return false }
            gesture = nil
            tracker.finish(window: window)
            return true
        case .rightMouseUp:
            guard case .resize(let window, _, _, _, let session, let lastFrame) = gesture else { return false }
            gesture = nil
            let finalFrame = (try? window.frame()) ?? lastFrame
            session?.finish(finalFrame: finalFrame)
            return true
        default:
            return false
        }
    }

    private func begin(isResize: Bool, at location: CGPoint, flags: CGEventFlags) -> Bool {
        cancelGesture()
        guard let modifiers, Self.modifiers(in: flags) == modifiers,
              let window = try? AXWindow.window(at: location),
              let frame = try? window.frame() else { return false }
        // Like clicking the window: bring it above its siblings without stealing focus.
        window.raise()
        if isResize {
            let corner = ResizeGeometry.corner(nearest: location, in: frame)
            let session: LinkedEdgeResize?
            if let windowID = WindowServer.match(processIdentifier: window.processIdentifier, frame: frame, in: WindowServer.windows())?.window.id {
                session = LinkedEdgeResize(
                    window: window,
                    windowID: windowID,
                    initialFrame: frame,
                    draggedEdges: corner.edges,
                    placer: placer
                )
            } else {
                session = nil
            }
            gesture = .resize(window: window, startFrame: frame, startCursor: location, corner: corner, session: session, lastFrame: frame)
        } else {
            // A placed window can swap places with another, as with a title-bar drag.
            if let windowID = WindowServer.match(processIdentifier: window.processIdentifier, frame: frame, in: WindowServer.windows())?.window.id {
                tracker.begin(windowID: windowID, slot: placer.isPlaced(window, at: frame) || placer.looksSnapped(frame) ? frame : nil)
            } else {
                tracker.cancel()
            }
            gesture = .move(window: window, startFrame: frame, startCursor: location, hasRestoredSize: false)
        }
        return true
    }

    private func continueMove(to location: CGPoint, flags: CGEventFlags) -> Bool {
        guard case .move(let window, var startFrame, var startCursor, let hasRestoredSize) = gesture else { return false }
        if !hasRestoredSize {
            // A snapped window gets its earlier size back as soon as it is dragged away,
            // like a title-bar drag; continue from the restored frame.
            try? placer.restoreSizeForDrag(of: window, currentFrame: startFrame, cursor: location)
            startFrame = (try? window.frame()) ?? startFrame
            startCursor = location
            gesture = .move(window: window, startFrame: startFrame, startCursor: startCursor, hasRestoredSize: true)
        }
        let origin = CGPoint(x: startFrame.minX + location.x - startCursor.x, y: startFrame.minY + location.y - startCursor.y)
        do {
            try window.setPosition(origin)
        } catch {
            logger.error("Move failed: \(String(describing: error), privacy: .public)")
        }
        // ⌥ already in the configured combo is held for every move, so it cannot also mean "force a swap".
        let forcesSwap = flags.contains(.maskAlternate) && !(modifiers?.contains(.option) ?? false)
        tracker.update(cursor: location, window: window, isSuppressed: flags.contains(.maskShift), forcesSwap: forcesSwap)
        return true
    }

    private func continueResize(to location: CGPoint) -> Bool {
        guard case .resize(let window, let startFrame, let startCursor, let corner, let session, _) = gesture else { return false }
        let delta = CGVector(dx: location.x - startCursor.x, dy: location.y - startCursor.y)
        var frame = ResizeGeometry.resized(startFrame, dragging: corner, by: delta)
        if let session {
            frame = session.update(draggedFrame: frame)
        }
        gesture = .resize(window: window, startFrame: startFrame, startCursor: startCursor, corner: corner, session: session, lastFrame: frame)
        do {
            try window.setFrame(frame)
        } catch {
            logger.error("Resize failed: \(String(describing: error), privacy: .public)")
        }
        return true
    }

    /// Only the keys that can make up a combination; caps lock and the like are ignored.
    /// Shift is left out so it can still suppress snapping during a move.
    private nonisolated static func modifiers(in flags: CGEventFlags) -> KeyboardShortcut.Modifiers {
        var modifiers: KeyboardShortcut.Modifiers = []
        if flags.contains(.maskControl) { modifiers.insert(.control) }
        if flags.contains(.maskAlternate) { modifiers.insert(.option) }
        if flags.contains(.maskCommand) { modifiers.insert(.command) }
        return modifiers
    }
}
