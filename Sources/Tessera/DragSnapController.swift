import AppKit
import OSLog
import TesseraAccessibility
import TesseraCore

/// Snaps windows when they are dragged to a screen edge or corner.
///
/// Mouse events are observed with a global monitor, which only listens and never blocks
/// or alters them. A press only becomes a window drag once the window under it actually
/// moves without changing size, so text selection, file drags and edge resizing are ignored.
@MainActor
final class DragSnapController {
    private struct Press {
        let window: AXWindow
        let windowID: CGWindowID
        let initialFrame: CGRect
        let cursor: CGPoint
    }

    private enum State {
        case idle
        case pressed(Press)
        case dragging(AXWindow)
        /// The rest of this gesture is not a window drag.
        case ignored
    }

    /// Cursor travel before the window is checked, so plain clicks cost no extra AX calls.
    private static let dragStartDistance: CGFloat = 4
    /// Cursor travel after which a window that has not moved means this is not a window drag.
    private static let dragGiveUpDistance: CGFloat = 40

    var isEnabled = true

    private let placer: WindowPlacer
    private let tracker: SnapZoneTracker
    private let logger = Logger(subsystem: "dev.ademaydemir.Tessera", category: "drag")
    private var state = State.idle
    private var monitor: Any?

    init(placer: WindowPlacer, tracker: SnapZoneTracker) {
        self.placer = placer
        self.tracker = tracker
    }

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { [weak self] event in
            // Global monitors are called on the main thread.
            MainActor.assumeIsolated {
                self?.handle(event)
            }
        }
    }

    private func handle(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown: mouseDown()
        case .leftMouseDragged: mouseDragged(modifiers: event.modifierFlags)
        case .leftMouseUp: mouseUp()
        default: break
        }
    }

    private func mouseDown() {
        tracker.cancel()
        guard isEnabled else {
            state = .ignored
            return
        }
        let cursor = ScreenGeometry.cursorLocation()
        do {
            let window = try AXWindow.window(at: cursor)
            let frame = try window.frame()
            guard let windowID = WindowServer.match(
                processIdentifier: window.processIdentifier, frame: frame, in: WindowServer.windows()
            )?.window.id else {
                logger.debug("Press on window at \(String(describing: frame), privacy: .public) ignored: no window server match")
                state = .ignored
                return
            }
            logger.debug("Press on window \(windowID, privacy: .public) at \(String(describing: frame), privacy: .public)")
            state = .pressed(Press(window: window, windowID: windowID, initialFrame: frame, cursor: cursor))
        } catch {
            logger.debug("Press at \(String(describing: cursor), privacy: .public) ignored: \(String(describing: error), privacy: .public)")
            state = .ignored
        }
    }

    private func mouseDragged(modifiers: NSEvent.ModifierFlags) {
        let cursor = ScreenGeometry.cursorLocation()
        switch state {
        case .pressed(let press):
            beginDragIfWindowMoved(press, cursor: cursor)
        case .dragging(let window):
            // Holding Shift moves the window freely without snapping.
            tracker.update(cursor: cursor, window: window, isSuppressed: modifiers.contains(.shift))
        case .idle, .ignored:
            break
        }
    }

    private func mouseUp() {
        defer { state = .idle }
        guard case .dragging(let window) = state else {
            tracker.cancel()
            return
        }
        tracker.finish(window: window)
    }

    private func beginDragIfWindowMoved(_ press: Press, cursor: CGPoint) {
        let travel = hypot(cursor.x - press.cursor.x, cursor.y - press.cursor.y)
        guard travel >= Self.dragStartDistance else { return }
        guard let frame = WindowServer.bounds(of: press.windowID) else {
            state = .ignored
            return
        }
        // Resizing from the left or top edge also moves the origin, but changes the size.
        let isMoving = frame.origin != press.initialFrame.origin && frame.size == press.initialFrame.size
        logger.debug("Drag check: travel \(travel, privacy: .public), frame \(String(describing: frame), privacy: .public), moving \(isMoving, privacy: .public)")
        if isMoving {
            do {
                try placer.restoreSizeForDrag(of: press.window, currentFrame: frame, cursor: cursor)
            } catch {
                logger.error("Restore on drag failed: \(String(describing: error), privacy: .public)")
            }
            state = .dragging(press.window)
        } else if travel >= Self.dragGiveUpDistance {
            state = .ignored
        }
    }
}
