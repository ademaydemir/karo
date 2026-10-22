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
        let edgeCandidates: [WindowServer.WindowInfo]
    }

    private enum State {
        case idle
        case pressed(Press)
        case dragging(AXWindow)
        case resizing(LinkedEdgeResize)
        /// The rest of this gesture is not a window drag.
        case ignored
    }

    /// Cursor travel before the window is checked, so plain clicks cost no extra AX calls.
    private static let dragStartDistance: CGFloat = 4
    /// Cursor travel after which a window that has not moved means this is not a window drag.
    /// Only applies when the cursor is not near an edge; edge presses wait for the resize.
    private static let dragGiveUpDistance: CGFloat = 40
    /// macOS accepts resize presses a few points outside a window's edge; 8 pt also covers the band just inside it.
    private static let edgeReach: CGFloat = 8
    /// macOS treats presses up to ~20 pt from a corner as corner resizes.
    private static let cornerReach: CGFloat = 20
    /// Movement threshold to detect an edge that started moving late; larger than the point
    /// or two some apps nudge their size by, smaller than any deliberate drag.
    private static let lateEdgeThreshold: CGFloat = 6
    /// The window server is polled at this interval while resizing so the translucent preview keeps up even after the mouse stops.
    private static let previewUpdateInterval: Duration = .milliseconds(8)

    var isEnabled = true

    private let placer: WindowPlacer
    private let tracker: SnapZoneTracker
    private let logger = Logger(subsystem: "dev.ademaydemir.Karo", category: "drag")
    private var resizeFollowTask: Task<Void, Never>?
    private var state = State.idle {
        didSet {
            guard case .resizing = oldValue else { return }
            if case .resizing = state { return }
            stopResizeFollowTask()
            if case .resizing(let session) = oldValue {
                session.cancel()
            }
        }
    }
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
        stopResizeFollowTask()
        guard isEnabled else {
            state = .ignored
            return
        }
        let cursor = ScreenGeometry.cursorLocation()
        let windows = WindowServer.windows()
        let edgeCandidates = Array(windows.filter {
            !SharedEdges.edges(near: cursor, of: $0.bounds, reach: Self.edgeReach).isEmpty
        }.prefix(2))

        func recordEdgePress() -> Bool {
            guard let candidate = edgeCandidates.first else { return false }
            guard let window = AXWindow.window(ofApplication: candidate.processIdentifier, matching: candidate.bounds) else {
                state = .ignored
                return true
            }
            logger.debug("Edge press on \(edgeCandidates.map(\.id), privacy: .public)")
            state = .pressed(Press(
                window: window,
                windowID: candidate.id,
                initialFrame: candidate.bounds,
                cursor: cursor,
                isSnapped: placer.isPlaced(window, at: candidate.bounds) || placer.looksSnapped(candidate.bounds),
                edgeCandidates: edgeCandidates
            ))
            return true
        }

        do {
            let window = try AXWindow.window(at: cursor)
            let frame = try window.frame()
            guard let windowID = WindowServer.match(
                processIdentifier: window.processIdentifier, frame: frame, in: windows
            )?.window.id else {
                if recordEdgePress() { return }
                logger.debug("Press on window at \(String(describing: frame), privacy: .public) ignored: no window server match")
                state = .ignored
                return
            }
            logger.debug("Press on window \(windowID, privacy: .public) at \(String(describing: frame), privacy: .public)")
            state = .pressed(Press(
                window: window,
                windowID: windowID,
                initialFrame: frame,
                cursor: cursor,
                isSnapped: placer.isPlaced(window, at: frame) || placer.looksSnapped(frame),
                edgeCandidates: edgeCandidates
            ))
        } catch {
            if recordEdgePress() { return }
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
        case .resizing:
            break
        case .idle, .ignored:
            break
        }
    }

    private func mouseUp() {
        defer { state = .idle }
        switch state {
        case .dragging(let window):
            tracker.finish(window: window)
        case .resizing(let session):
            stopResizeFollowTask()
            guard let frame = (try? session.window.frame()) ?? WindowServer.bounds(of: session.windowID) else { return }
            let lateEdges = SharedEdges.movedEdges(from: session.initialFrame, to: frame, threshold: Self.lateEdgeThreshold)
            session.addDraggedEdges(lateEdges)
            session.finish(finalFrame: frame)
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
            return
        }

        var resizeTarget: (window: AXWindow, windowID: CGWindowID, initialFrame: CGRect, liveFrame: CGRect)?
        if frame.size != press.initialFrame.size {
            resizeTarget = (press.window, press.windowID, press.initialFrame, frame)
        } else {
            for candidate in press.edgeCandidates where candidate.id != press.windowID {
                guard let candidateFrame = WindowServer.bounds(of: candidate.id) else { continue }
                if candidateFrame.size != candidate.bounds.size {
                    guard let window = AXWindow.window(ofApplication: candidate.processIdentifier, matching: candidate.bounds) else {
                        state = .ignored
                        return
                    }
                    resizeTarget = (window, candidate.id, candidate.bounds, candidateFrame)
                    break
                }
            }
        }

        if let target = resizeTarget {
            var edges = SharedEdges.edges(near: press.cursor, of: target.initialFrame, reach: Self.edgeReach, cornerReach: Self.cornerReach)
            if edges.isEmpty {
                edges = SharedEdges.movedEdges(from: target.initialFrame, to: target.liveFrame, threshold: 0.5)
            }
            guard !edges.isEmpty,
                  let session = LinkedEdgeResize(
                      window: target.window,
                      windowID: target.windowID,
                      initialFrame: target.initialFrame,
                      draggedEdges: edges,
                      placer: placer,
                      allowEmpty: true
                  ) else {
                state = .ignored
                return
            }
            session.update(draggedFrame: target.liveFrame)
            state = .resizing(session)
            startResizeFollowTask(session: session, liveFrame: target.liveFrame)
        } else if press.edgeCandidates.isEmpty && travel >= Self.dragGiveUpDistance {
            state = .ignored
        }
    }

    private func stopResizeFollowTask() {
        resizeFollowTask?.cancel()
        resizeFollowTask = nil
    }

    private func startResizeFollowTask(session: LinkedEdgeResize, liveFrame: CGRect) {
        stopResizeFollowTask()
        resizeFollowTask = Task { @MainActor [weak self, weak session] in
            var lastFrame = liveFrame
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.previewUpdateInterval)
                guard !Task.isCancelled else { break }
                guard self != nil, let session else { break }
                guard let currentFrame = WindowServer.bounds(of: session.windowID) else { continue }
                if currentFrame != lastFrame {
                    lastFrame = currentFrame
                    let lateEdges = SharedEdges.movedEdges(from: session.initialFrame, to: currentFrame, threshold: Self.lateEdgeThreshold)
                    session.addDraggedEdges(lateEdges)
                    session.update(draggedFrame: currentFrame)
                }
            }
        }
    }
}
