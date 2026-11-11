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
        let processIdentifier: pid_t
        let windowID: CGWindowID
        let initialFrame: CGRect
        let cursor: CGPoint
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

    /// Cursor travel before the window is looked up, so plain clicks make no Accessibility calls.
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

        // Only the window server is asked here: the clicked app is busy handling this very
        // click, so an Accessibility call would stall it. The window is resolved once the
        // press turns into a real move or resize.
        let karo = ProcessInfo.processInfo.processIdentifier
        let topmost = windows.first { $0.bounds.contains(cursor) }
        // A Karo window on top must not hand the press to the window below it.
        let target = topmost.flatMap { $0.processIdentifier == karo ? nil : $0 }
            ?? edgeCandidates.first { $0.processIdentifier != karo }
        guard let target else {
            logger.debug("Press at \(String(describing: cursor), privacy: .public) ignored: no window")
            state = .ignored
            return
        }
        logger.debug("Press on window \(target.id, privacy: .public) at \(String(describing: target.bounds), privacy: .public)")
        state = .pressed(Press(
            processIdentifier: target.processIdentifier,
            windowID: target.id,
            initialFrame: target.bounds,
            cursor: cursor,
            edgeCandidates: edgeCandidates
        ))
    }

    private func mouseDragged(modifiers: NSEvent.ModifierFlags) {
        let cursor = ScreenGeometry.cursorLocation()
        switch state {
        case .pressed(let press):
            classify(press, cursor: cursor)
        case .dragging(let window):
            // Holding Shift moves the window freely without snapping or swapping.
            tracker.update(cursor: cursor, window: window, isSuppressed: modifiers.contains(.shift),
                           forcesSwap: modifiers.contains(.option))
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
            guard let window = resolveWindow(processIdentifier: press.processIdentifier, initialFrame: press.initialFrame, liveFrame: frame, travel: travel) else {
                state = .ignored
                return
            }
            // Snapped into a layout slot, so it can swap places with another snapped window.
            // Decided before restoring the pre-snap size, which forgets the slot.
            let isSnapped = placer.isPlaced(window, at: press.initialFrame) || placer.looksSnapped(press.initialFrame)
            tracker.begin(windowID: press.windowID, slot: isSnapped ? press.initialFrame : nil)
            do {
                try placer.restoreSizeForDrag(of: window, currentFrame: frame, cursor: cursor)
            } catch {
                logger.error("Restore on drag failed: \(String(describing: error), privacy: .public)")
            }
            state = .dragging(window)
            return
        }

        var resizeTarget: (window: AXWindow, windowID: CGWindowID, initialFrame: CGRect, liveFrame: CGRect)?
        if frame.size != press.initialFrame.size {
            guard let window = resolveWindow(processIdentifier: press.processIdentifier, initialFrame: press.initialFrame, liveFrame: frame, travel: travel) else {
                state = .ignored
                return
            }
            resizeTarget = (window, press.windowID, press.initialFrame, frame)
        } else {
            for candidate in press.edgeCandidates where candidate.id != press.windowID {
                guard let candidateFrame = WindowServer.bounds(of: candidate.id) else { continue }
                if candidateFrame.size != candidate.bounds.size {
                    guard let window = resolveWindow(processIdentifier: candidate.processIdentifier, initialFrame: candidate.bounds, liveFrame: candidateFrame, travel: travel) else {
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

    /// The Accessibility window behind a window server window. Only called once a press has
    /// turned into a real move or resize, so plain clicks never message the clicked app.
    private func resolveWindow(processIdentifier: pid_t, initialFrame: CGRect, liveFrame: CGRect, travel: CGFloat) -> AXWindow? {
        // The Accessibility frame lags during a drag and may be anywhere between the two.
        let found = AXWindow.window(ofApplication: processIdentifier, matching: initialFrame)
            ?? AXWindow.window(ofApplication: processIdentifier, matching: liveFrame)
            ?? AXWindow.window(ofApplication: processIdentifier, matching: liveFrame, tolerance: travel + 2)
        // Lookups use a short timeout; placing the window later should get the normal one.
        return found.map { AXWindow(identity: $0.identity) }
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
