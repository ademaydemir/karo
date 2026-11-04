import AppKit
import KaroAccessibility
import KaroCore
import OSLog

/// Follows the pointer during a window drag, previews where the window will go and puts it
/// there on release. Shared by ordinary title-bar drags and modifier drags.
///
/// Near a screen edge the window snaps into the zone. A snapped window being dragged swaps
/// places instead only with a snapped window on the same display, with the pointer near its
/// middle (see `SwapPolicy`). A swap previews both sides: the full preview where the dragged
/// window goes, and a fainter one where the other window goes. Holding ⌥ forces the swap
/// with any snapped window under the pointer, skipping `SwapPolicy`. Esc cancels the snap or
/// swap for the rest of the drag, so the release leaves the window where it was dropped.
///
/// An edge shared with another display is where the pointer crosses over, so it snaps only
/// after the pointer has rested there briefly.
@MainActor
final class SnapZoneTracker {
    private struct SwapTarget {
        let window: AXWindow
        let windowID: CGWindowID
        let slot: CGRect
    }

    /// Pointer travel between looks for a swap target; the window list is not read on every event.
    private static let swapProbeDistance: CGFloat = 6

    /// How long the pointer rests at an edge shared with another display before it snaps.
    private static let sharedEdgeDwell: Duration = .milliseconds(400)

    private static let escapeKeyCode: UInt16 = 53

    var detector = ZoneDetector()

    private let placer: WindowPlacer
    private let overlay = SnapPreviewOverlay()
    /// Shows `swapSource.slot`, where the swap target will go; fainter than `overlay`.
    private let swapOverlay = SnapPreviewOverlay(tintAlpha: 0.08)
    private let logger = Logger(subsystem: "dev.ademaydemir.Karo", category: "drag")
    private var zone: ZoneDetector.Zone?
    /// The dragged window and the frame it was placed at, when it was placed; only then can it swap.
    private var swapSource: (windowID: CGWindowID, slot: CGRect)?
    private var swapTarget: SwapTarget?
    private var lastSwapProbe: CGPoint?
    private var lastForcesSwap = false
    /// Key monitors that watch for Esc while a drag is tracked: global for other apps' windows,
    /// local for Karo's own.
    private var keyMonitors: [Any] = []
    private var isCancelledByUser = false
    /// A zone at a shared display edge the pointer is resting in, not yet active.
    private var pendingSharedZone: ZoneDetector.Zone?
    private var dwellTask: Task<Void, Never>?
    /// The dragged window, for the preview once a dwell completes.
    private var lastWindow: AXWindow?

    init(placer: WindowPlacer) {
        self.placer = placer
    }

    /// Starts a drag.
    /// - Parameter slot: The frame Karo had placed the window at, or `nil` for a free window.
    func begin(windowID: CGWindowID, slot: CGRect?) {
        cancel()
        swapSource = slot.map { (windowID, $0) }
        installKeyMonitors()
    }

    /// - Parameters:
    ///   - isSuppressed: Snapping and swapping are skipped, e.g. while ⇧ is held.
    ///   - forcesSwap: Swaps with any snapped window under the pointer, skipping `SwapPolicy`, e.g. while ⌥ is held.
    func update(cursor: CGPoint, window: AXWindow, isSuppressed: Bool, forcesSwap: Bool) {
        guard !isCancelledByUser else { return }
        lastWindow = window
        let newZone = isSuppressed ? nil : resolveZone(at: cursor)
        let zoneChanged = newZone != zone
        if zoneChanged {
            logger.debug("Zone at \(String(describing: cursor), privacy: .public): \(String(describing: newZone?.action), privacy: .public)")
            zone = newZone
            if newZone != nil { Haptics.tick() }
        }

        // An edge zone wins over a window underneath.
        if let newZone {
            swapTarget = nil
            swapOverlay.hide()
            if zoneChanged { showPreview(for: newZone, window: window) }
            return
        }

        let target = isSuppressed ? nil : findSwapTarget(at: cursor, forcesSwap: forcesSwap)
        if target?.windowID != swapTarget?.windowID {
            swapTarget = target
            if let target, let swapSource {
                overlay.show(target.slot)
                swapOverlay.show(swapSource.slot)
                Haptics.tick()
            } else {
                overlay.hide()
                swapOverlay.hide()
            }
        } else if zoneChanged, target == nil {
            // The swap target was already nil here, so only the edge preview can be showing.
            overlay.hide()
        }
    }

    /// The zone at the cursor. A zone at a shared display edge stays pending until the pointer
    /// has rested there for `sharedEdgeDwell`; one already active stays while the pointer is in it.
    private func resolveZone(at cursor: CGPoint) -> ZoneDetector.Zone? {
        let frames = ScreenGeometry.displays().map(\.frame)
        if let plain = detector.zone(at: cursor, displays: frames, current: zone) {
            clearPendingSharedZone()
            return plain
        }
        guard let shared = detector.zone(at: cursor, displays: frames, current: zone, includesSharedEdges: true) else {
            clearPendingSharedZone()
            return nil
        }
        if shared == zone {
            clearPendingSharedZone()
            return shared
        }
        if shared != pendingSharedZone {
            pendingSharedZone = shared
            dwellTask?.cancel()
            dwellTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: Self.sharedEdgeDwell)
                guard !Task.isCancelled else { return }
                self?.activateSharedZone(shared)
            }
        }
        return nil
    }

    private func activateSharedZone(_ shared: ZoneDetector.Zone) {
        let frames = ScreenGeometry.displays().map(\.frame)
        guard pendingSharedZone == shared, !isCancelledByUser, let lastWindow,
              detector.zone(at: ScreenGeometry.cursorLocation(), displays: frames, current: nil, includesSharedEdges: true) == shared else { return }
        logger.debug("Zone at shared edge after dwell: \(shared.action.rawValue, privacy: .public)")
        clearPendingSharedZone()
        zone = shared
        swapTarget = nil
        swapOverlay.hide()
        showPreview(for: shared, window: lastWindow)
        Haptics.tick()
    }

    private func clearPendingSharedZone() {
        pendingSharedZone = nil
        dwellTask?.cancel()
        dwellTask = nil
    }

    /// Snaps the window into the current zone or swaps it with the window under it, then
    /// ends tracking.
    func finish(window: AXWindow) {
        defer { cancel() }
        guard !isCancelledByUser else { return }
        if let zone {
            let displays = ScreenGeometry.displays()
            guard displays.indices.contains(zone.displayIndex) else { return }
            do {
                let currentFrame = try window.frame()
                try placer.place(window, zone.action, from: currentFrame, on: displays[zone.displayIndex])
            } catch {
                logger.error("Snap to \(zone.action.rawValue, privacy: .public) failed: \(String(describing: error), privacy: .public)")
            }
        } else if let swapTarget, let swapSource {
            do {
                try placer.swap(window, from: swapSource.slot, with: swapTarget.window, at: swapTarget.slot)
            } catch {
                logger.error("Swapping windows failed: \(String(describing: error), privacy: .public)")
            }
        }
    }

    func cancel() {
        zone = nil
        swapSource = nil
        swapTarget = nil
        lastSwapProbe = nil
        lastForcesSwap = false
        isCancelledByUser = false
        clearPendingSharedZone()
        lastWindow = nil
        removeKeyMonitors()
        overlay.hide()
        swapOverlay.hide()
    }

    private func installKeyMonitors() {
        // Both handlers run on the main thread.
        let global = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            MainActor.assumeIsolated {
                if event.keyCode == Self.escapeKeyCode { self?.cancelByUser() }
            }
        }
        let local = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            MainActor.assumeIsolated {
                if event.keyCode == Self.escapeKeyCode { self?.cancelByUser() }
            }
            return event
        }
        keyMonitors = [global, local].compactMap { $0 }
    }

    private func removeKeyMonitors() {
        keyMonitors.forEach(NSEvent.removeMonitor)
        keyMonitors.removeAll()
    }

    /// Drops the preview and makes the release do nothing until the drag ends.
    private func cancelByUser() {
        guard !isCancelledByUser else { return }
        logger.debug("Snap cancelled with Esc")
        isCancelledByUser = true
        clearPendingSharedZone()
        zone = nil
        swapTarget = nil
        overlay.hide()
        swapOverlay.hide()
    }

    private func showPreview(for zone: ZoneDetector.Zone, window: AXWindow) {
        let displays = ScreenGeometry.displays()
        guard displays.indices.contains(zone.displayIndex),
              let currentFrame = try? window.frame(),
              let target = placer.targetFrame(for: zone.action, currentFrame: currentFrame, on: displays[zone.displayIndex]) else {
            overlay.hide()
            return
        }
        overlay.show(target)
    }

    /// The placed window under the pointer, other than the dragged one.
    private func findSwapTarget(at cursor: CGPoint, forcesSwap: Bool) -> SwapTarget? {
        guard let swapSource else { return nil }
        // A change of ⌥ must not wait for the pointer to travel.
        let forcesChanged = forcesSwap != lastForcesSwap
        lastForcesSwap = forcesSwap
        if !forcesChanged, let lastSwapProbe, hypot(cursor.x - lastSwapProbe.x, cursor.y - lastSwapProbe.y) < Self.swapProbeDistance {
            return swapTarget
        }
        lastSwapProbe = cursor

        // Front to back, so this is the window the pointer is over beneath the dragged one.
        guard let hit = WindowServer.windows().first(where: { $0.id != swapSource.windowID && $0.bounds.contains(cursor) }) else {
            return nil
        }
        guard let candidate = swapTarget?.windowID == hit.id ? swapTarget : lookUpSwapTarget(for: hit) else { return nil }
        let allowed = forcesSwap || SwapPolicy.allowsSwap(
            sourceSlot: swapSource.slot,
            targetFrame: candidate.slot,
            cursor: cursor,
            visibleFrames: ScreenGeometry.displays().map(\.visibleFrame)
        )
        return allowed ? candidate : nil
    }

    private func lookUpSwapTarget(for hit: WindowServer.WindowInfo) -> SwapTarget? {
        // Only snapped windows take part; free windows are left alone.
        if let placed = placer.placedWindows().first(where: {
            $0.window.processIdentifier == hit.processIdentifier && Self.isClose($0.frame, hit.bounds)
        }) {
            return SwapTarget(window: placed.window, windowID: hit.id, slot: placed.frame)
        }
        guard placer.looksSnapped(hit.bounds),
              let window = AXWindow.window(ofApplication: hit.processIdentifier, matching: hit.bounds) else { return nil }
        return SwapTarget(window: window, windowID: hit.id, slot: hit.bounds)
    }

    private static func isClose(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) <= 2 && abs(a.minY - b.minY) <= 2 && abs(a.width - b.width) <= 2 && abs(a.height - b.height) <= 2
    }
}
