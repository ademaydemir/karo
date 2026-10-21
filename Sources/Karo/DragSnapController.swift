import AppKit
import KaroAccessibility
import KaroCore
import OSLog

/// Snaps windows when they are dragged to a screen edge or corner, swaps placed windows
/// dragged onto each other, and keeps neighbours together when a shared edge is resized.
///
/// Mouse events are observed with a global monitor, which only listens and never blocks
/// or alters them. A press becomes a window drag once the window under it actually moves
/// without changing size, and a resize once its size changes; text selection and file
/// drags change neither and are ignored.
@MainActor
final class DragSnapController {
    private struct Press {
        let window: AXWindow
        let windowID: CGWindowID
        let initialFrame: CGRect
        let cursor: CGPoint
        /// Snapped into a layout slot, so it can swap places with another snapped window.
        let isSnapped: Bool
    }

    private struct Neighbor {
        let window: AXWindow
        let initialFrame: CGRect
        let side: SharedEdges.Side
        var lastFrame: CGRect
    }

    private struct Resize {
        let window: AXWindow
        let windowID: CGWindowID
        let initialFrame: CGRect
        var neighbors: [Neighbor]
        var lastUpdate: ContinuousClock.Instant
    }

    private enum State {
        case idle
        case pressed(Press)
        case dragging(AXWindow)
        case resizing(Resize)
        /// The rest of this gesture is not a window drag.
        case ignored
    }

    /// Cursor travel before the window is checked, so plain clicks cost no extra AX calls.
    private static let dragStartDistance: CGFloat = 4
    /// Cursor travel after which a window that has not moved means this is not a window drag.
    private static let dragGiveUpDistance: CGFloat = 40
    /// Neighbours follow a resize at most this often; each update is a round trip to their apps.
    private static let neighborUpdateInterval: Duration = .milliseconds(33)

    var isEnabled = true

    private let placer: WindowPlacer
    private let tracker: SnapZoneTracker
    private let logger = Logger(subsystem: "dev.ademaydemir.Karo", category: "drag")
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
            state = .pressed(Press(
                window: window, windowID: windowID, initialFrame: frame, cursor: cursor,
                isSnapped: placer.isPlaced(window, at: frame) || placer.looksSnapped(frame)
            ))
        } catch {
            logger.debug("Press at \(String(describing: cursor), privacy: .public) ignored: \(String(describing: error), privacy: .public)")
            state = .ignored
        }
    }

    private func mouseDragged(modifiers: NSEvent.ModifierFlags) {
        let cursor = ScreenGeometry.cursorLocation()
        switch state {
        case .pressed(let press):
            classify(press, cursor: cursor)
        case .dragging(let window):
            // Holding Shift moves the window freely without snapping or swapping.
            tracker.update(cursor: cursor, window: window, isSuppressed: modifiers.contains(.shift))
        case .resizing(var resize):
            guard ContinuousClock.now - resize.lastUpdate >= Self.neighborUpdateInterval else { return }
            resize.lastUpdate = .now
            if let frame = WindowServer.bounds(of: resize.windowID) {
                followResize(&resize, to: frame, isFinal: false)
            }
            state = .resizing(resize)
        case .idle, .ignored:
            break
        }
    }

    private func mouseUp() {
        defer { state = .idle }
        switch state {
        case .dragging(let window):
            tracker.finish(window: window)
        case .resizing(var resize):
            guard let frame = (try? resize.window.frame()) ?? WindowServer.bounds(of: resize.windowID) else { return }
            followResize(&resize, to: frame, isFinal: true)
            placer.recordAdjustment(of: resize.window, from: resize.initialFrame, to: frame)
        default:
            tracker.cancel()
        }
    }

    /// Decides what the press is once the pointer has travelled a little: a move, a resize
    /// of a placed window with neighbours, or neither.
    private func classify(_ press: Press, cursor: CGPoint) {
        let travel = hypot(cursor.x - press.cursor.x, cursor.y - press.cursor.y)
        guard travel >= Self.dragStartDistance else { return }
        guard let frame = WindowServer.bounds(of: press.windowID) else {
            state = .ignored
            return
        }
        let isMoving = frame.origin != press.initialFrame.origin && frame.size == press.initialFrame.size
        let isResizing = frame.size != press.initialFrame.size
        logger.debug("Drag check: travel \(travel, privacy: .public), frame \(String(describing: frame), privacy: .public), moving \(isMoving, privacy: .public)")

        if isMoving {
            // Remember the slot before restoring the pre-snap size, which forgets it.
            tracker.begin(windowID: press.windowID, slot: press.isSnapped ? press.initialFrame : nil)
            do {
                try placer.restoreSizeForDrag(of: press.window, currentFrame: frame, cursor: cursor)
            } catch {
                logger.error("Restore on drag failed: \(String(describing: error), privacy: .public)")
            }
            state = .dragging(press.window)
        } else if isResizing {
            let neighbors = sharedEdgeNeighbors(of: press)
            state = neighbors.isEmpty
                ? .ignored
                : .resizing(Resize(window: press.window, windowID: press.windowID, initialFrame: press.initialFrame,
                                   neighbors: neighbors, lastUpdate: .now))
        } else if travel >= Self.dragGiveUpDistance {
            state = .ignored
        }
    }

    /// Windows that share an edge with the pressed window. Found through the window server
    /// rather than Karo's placement history, so it works for any windows that sit edge to
    /// edge, including ones snapped before Karo last started.
    private func sharedEdgeNeighbors(of press: Press) -> [Neighbor] {
        let others = WindowServer.windows().filter { $0.id != press.windowID }
        let candidates = others.enumerated().map { (id: $0.offset, frame: $0.element.bounds) }
        return SharedEdges.neighbors(of: press.initialFrame, among: candidates, gap: placer.gap).compactMap { neighbor in
            let info = others[neighbor.id]
            guard let window = AXWindow.window(ofApplication: info.processIdentifier, matching: info.bounds) else { return nil }
            return Neighbor(window: window, initialFrame: neighbor.frame, side: neighbor.side, lastFrame: neighbor.frame)
        }
    }

    /// Moves each neighbour's near edge along with the resized window. While dragging the
    /// frames are set directly for speed; on release they are fitted properly (apps that size
    /// in steps) and recorded as still placed.
    private func followResize(_ resize: inout Resize, to frame: CGRect, isFinal: Bool) {
        for index in resize.neighbors.indices {
            let neighbor = resize.neighbors[index]
            let target = SharedEdges.adjusted(neighbor.initialFrame, on: neighbor.side, of: frame, gap: placer.gap)
            do {
                if isFinal {
                    let display = ScreenGeometry.displays().first { $0.visibleFrame.intersects(target) }
                    let actual = try placer.fit(neighbor.window, to: target, within: display?.visibleFrame ?? target)
                    placer.recordAdjustment(of: neighbor.window, from: neighbor.initialFrame, to: actual)
                } else if target != neighbor.lastFrame {
                    try neighbor.window.setFrame(target)
                    resize.neighbors[index].lastFrame = target
                }
            } catch {
                logger.error("Resizing a neighbour failed: \(String(describing: error), privacy: .public)")
            }
        }
    }
}
