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

    private struct Drag {
        let window: AXWindow
        var zone: ZoneDetector.Zone?
    }

    private enum State {
        case idle
        case pressed(Press)
        case dragging(Drag)
        /// The rest of this gesture is not a window drag.
        case ignored
    }

    /// Cursor travel before the window is checked, so plain clicks cost no extra AX calls.
    private static let dragStartDistance: CGFloat = 4
    /// Cursor travel after which a window that has not moved means this is not a window drag.
    private static let dragGiveUpDistance: CGFloat = 40

    private let placer: WindowPlacer
    private let overlay = SnapPreviewOverlay()
    private let detector = ZoneDetector()
    private let logger = Logger(subsystem: "dev.ademaydemir.Tessera", category: "drag")
    private var state = State.idle
    private var monitor: Any?

    init(placer: WindowPlacer) {
        self.placer = placer
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
        overlay.hide()
        let cursor = ScreenGeometry.cursorLocation()
        do {
            let window = try AXWindow.window(at: cursor)
            let frame = try window.frame()
            guard let windowID = WindowServer.windowID(ownedBy: window.processIdentifier, matching: frame) else {
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
        case .dragging(var drag):
            // Holding Shift moves the window freely without snapping.
            let zone = modifiers.contains(.shift) ? nil : detector.zone(at: cursor, displays: ScreenGeometry.displays().map(\.frame))
            guard zone != drag.zone else { return }
            logger.debug("Zone at \(String(describing: cursor), privacy: .public): \(String(describing: zone?.action), privacy: .public)")
            drag.zone = zone
            state = .dragging(drag)
            updatePreview(for: drag)
        case .idle, .ignored:
            break
        }
    }

    private func mouseUp() {
        defer { state = .idle }
        overlay.hide()
        guard case .dragging(let drag) = state, let zone = drag.zone else { return }
        let displays = ScreenGeometry.displays()
        guard displays.indices.contains(zone.displayIndex) else { return }
        do {
            let currentFrame = try drag.window.frame()
            try placer.place(drag.window, zone.action, from: currentFrame, on: displays[zone.displayIndex])
        } catch {
            logger.error("Snap to \(zone.action.rawValue, privacy: .public) failed: \(String(describing: error), privacy: .public)")
        }
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
            state = .dragging(Drag(window: press.window, zone: nil))
        } else if travel >= Self.dragGiveUpDistance {
            state = .ignored
        }
    }

    private func updatePreview(for drag: Drag) {
        let displays = ScreenGeometry.displays()
        guard let zone = drag.zone,
              displays.indices.contains(zone.displayIndex),
              let currentFrame = try? drag.window.frame(),
              let target = placer.targetFrame(for: zone.action, currentFrame: currentFrame, on: displays[zone.displayIndex]) else {
            overlay.hide()
            return
        }
        overlay.show(target)
    }
}
