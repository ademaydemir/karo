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
/// With the setting on, a snapped window dropped on another display, with no zone, swap or
/// free region in play, takes the same placement there (a left half stays a left half).
///
/// An edge shared with another display is where the pointer crosses over, so it snaps only
/// after the pointer has rested there briefly.
///
/// Away from the edges and from swap targets, resting the pointer for a moment in the free
/// region beside a snapped window (the right half next to a left half) previews that region,
/// and the release puts the window there. The pause keeps ordinary drags across the screen
/// from being surprised.
@MainActor
final class SnapZoneTracker {
    /// A placement that no snapped window occupies, where a dragged window can be dropped.
    private struct FreeRegion: Equatable {
        let action: WindowAction
        let displayIndex: Int
        let frame: CGRect
    }

    private struct SwapTarget {
        let window: AXWindow
        let windowID: CGWindowID
        let slot: CGRect
    }

    /// Pointer travel between looks for a swap target; the window list is not read on every event.
    private static let swapProbeDistance: CGFloat = 6

    /// How long the pointer rests at an edge shared with another display before it snaps.
    private static let sharedEdgeDwell: Duration = .milliseconds(400)

    /// How long the pointer rests in a free region beside a snapped window before it is previewed.
    private static let freeRegionDwell: Duration = .milliseconds(500)

    private static let escapeKeyCode: UInt16 = 53

    var detector = ZoneDetector()
    /// Whether a snapped window dropped on another display takes the same placement there.
    var keepsLayoutAcrossDisplays = false

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
    /// The dragged window, placed or not, so it is left out when looking for snapped neighbours.
    private var draggedWindowID: CGWindowID?
    /// The free region shown on `overlay`; the release places the window there.
    private var freeRegion: FreeRegion?
    /// A free region the pointer is resting in, not yet shown.
    private var pendingFreeRegion: FreeRegion?
    private var freeRegionTask: Task<Void, Never>?
    private var lastFreeRegionProbe: CGPoint?

    init(placer: WindowPlacer) {
        self.placer = placer
    }

    /// Starts a drag.
    /// - Parameter slot: The frame Karo had placed the window at, or `nil` for a free window.
    func begin(windowID: CGWindowID, slot: CGRect?) {
        cancel()
        draggedWindowID = windowID
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
            clearFreeRegion(hidesOverlay: false)
            swapTarget = nil
            swapOverlay.hide()
            if zoneChanged { showPreview(for: newZone, window: window) }
            return
        }

        let target = isSuppressed ? nil : findSwapTarget(at: cursor, forcesSwap: forcesSwap)
        // The swap preview takes over `overlay`, so a free region must not hide it later.
        if target != nil { clearFreeRegion(hidesOverlay: false) }
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
        if target == nil { updateFreeRegion(at: cursor, isSuppressed: isSuppressed) }
    }

    /// Keeps the free region while the pointer is in it; otherwise looks for one and starts the
    /// dwell that shows it.
    private func updateFreeRegion(at cursor: CGPoint, isSuppressed: Bool) {
        if let freeRegion {
            if !isSuppressed, freeRegion.frame.contains(cursor) { return }
            clearFreeRegion(hidesOverlay: true)
        }
        guard !isSuppressed else {
            clearPendingFreeRegion()
            return
        }
        if let lastFreeRegionProbe, hypot(cursor.x - lastFreeRegionProbe.x, cursor.y - lastFreeRegionProbe.y) < Self.swapProbeDistance {
            return
        }
        lastFreeRegionProbe = cursor

        guard let found = findFreeRegion(at: cursor) else {
            clearPendingFreeRegion()
            return
        }
        guard found != pendingFreeRegion else { return }
        pendingFreeRegion = found
        freeRegionTask?.cancel()
        freeRegionTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.freeRegionDwell)
            guard !Task.isCancelled else { return }
            self?.activateFreeRegion(found)
        }
    }

    /// The region beside a snapped window on the cursor's display that nothing occupies and
    /// that the cursor is in.
    private func findFreeRegion(at cursor: CGPoint) -> FreeRegion? {
        let displays = ScreenGeometry.displays()
        guard let index = displays.firstIndex(where: { $0.frame.contains(cursor) }) else { return nil }
        let visibleFrames = displays.map(\.visibleFrame)
        let visibleFrame = visibleFrames[index]
        let snapped = WindowServer.windows().compactMap { info -> CGRect? in
            guard info.id != draggedWindowID,
                  DisplaySelector.indexOfDisplay(containing: info.bounds, among: visibleFrames) == index,
                  isSnapped(info) else { return nil }
            return info.bounds
        }
        guard let action = FreeRegionFinder.region(
            at: cursor, in: visibleFrame, gap: placer.gap, snappedFrames: snapped, tolerance: StepSizeFitting.maximumStep
        ), let frame = LayoutCalculator.frame(for: action, in: visibleFrame, currentFrame: .zero, gap: placer.gap) else { return nil }
        return FreeRegion(action: action, displayIndex: index, frame: frame)
    }

    private func isSnapped(_ info: WindowServer.WindowInfo) -> Bool {
        placer.placedWindows().contains {
            $0.window.processIdentifier == info.processIdentifier && Self.isClose($0.frame, info.bounds)
        } || placer.looksSnapped(info.bounds)
    }

    private func activateFreeRegion(_ region: FreeRegion) {
        guard pendingFreeRegion == region, !isCancelledByUser, zone == nil, swapTarget == nil,
              region.frame.contains(ScreenGeometry.cursorLocation()) else { return }
        logger.debug("Free region after dwell: \(region.action.rawValue, privacy: .public)")
        clearPendingFreeRegion()
        freeRegion = region
        overlay.show(region.frame)
        Haptics.tick()
    }

    private func clearPendingFreeRegion() {
        pendingFreeRegion = nil
        freeRegionTask?.cancel()
        freeRegionTask = nil
    }

    /// - Parameter hidesOverlay: `false` when a zone or swap preview has just taken over `overlay`.
    private func clearFreeRegion(hidesOverlay: Bool) {
        clearPendingFreeRegion()
        lastFreeRegionProbe = nil
        guard freeRegion != nil else { return }
        freeRegion = nil
        if hidesOverlay { overlay.hide() }
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
        clearFreeRegion(hidesOverlay: false)
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
        } else if let freeRegion {
            let displays = ScreenGeometry.displays()
            guard displays.indices.contains(freeRegion.displayIndex) else { return }
            do {
                try placer.place(window, freeRegion.action, from: try window.frame(), on: displays[freeRegion.displayIndex], announces: false)
            } catch {
                logger.error("Placing into \(freeRegion.action.rawValue, privacy: .public) failed: \(String(describing: error), privacy: .public)")
            }
        } else if keepsLayoutAcrossDisplays, let swapSource {
            let displays = ScreenGeometry.displays()
            let visibleFrames = displays.map(\.visibleFrame)
            guard let source = DisplaySelector.indexOfDisplay(containing: swapSource.slot, among: visibleFrames),
                  let destination = displays.firstIndex(where: { $0.frame.contains(ScreenGeometry.cursorLocation()) }),
                  source != destination,
                  let action = LayoutMatcher.action(
                      matching: swapSource.slot, in: visibleFrames[source], gap: placer.gap, tolerance: StepSizeFitting.maximumStep
                  ) else { return }
            do {
                try placer.place(window, action, from: try window.frame(), on: displays[destination])
            } catch {
                logger.error("Keeping \(action.rawValue, privacy: .public) on another display failed: \(String(describing: error), privacy: .public)")
            }
        }
    }

    func cancel() {
        zone = nil
        draggedWindowID = nil
        freeRegion = nil
        lastFreeRegionProbe = nil
        clearPendingFreeRegion()
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
        clearFreeRegion(hidesOverlay: false)
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
