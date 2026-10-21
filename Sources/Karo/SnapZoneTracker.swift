import AppKit
import KaroAccessibility
import KaroCore
import OSLog

/// Follows the pointer during a window drag, previews where the window will go and puts it
/// there on release. Shared by ordinary title-bar drags and modifier drags.
///
/// Near a screen edge the window snaps into the zone. Over another snapped window, a
/// snapped window being dragged swaps places with it instead.
@MainActor
final class SnapZoneTracker {
    private struct SwapTarget {
        let window: AXWindow
        let windowID: CGWindowID
        let slot: CGRect
    }

    /// Pointer travel between looks for a swap target; the window list is not read on every event.
    private static let swapProbeDistance: CGFloat = 6

    var detector = ZoneDetector()

    private let placer: WindowPlacer
    private let overlay = SnapPreviewOverlay()
    private let logger = Logger(subsystem: "dev.ademaydemir.Karo", category: "drag")
    private var zone: ZoneDetector.Zone?
    /// The dragged window and the frame it was placed at, when it was placed; only then can it swap.
    private var swapSource: (windowID: CGWindowID, slot: CGRect)?
    private var swapTarget: SwapTarget?
    private var lastSwapProbe: CGPoint?

    init(placer: WindowPlacer) {
        self.placer = placer
    }

    /// Starts a drag.
    /// - Parameter slot: The frame Karo had placed the window at, or `nil` for a free window.
    func begin(windowID: CGWindowID, slot: CGRect?) {
        cancel()
        swapSource = slot.map { (windowID, $0) }
    }

    /// - Parameter isSuppressed: Snapping and swapping are skipped, e.g. while ⇧ is held.
    func update(cursor: CGPoint, window: AXWindow, isSuppressed: Bool) {
        let newZone = isSuppressed ? nil : detector.zone(at: cursor, displays: ScreenGeometry.displays().map(\.frame))
        let zoneChanged = newZone != zone
        if zoneChanged {
            logger.debug("Zone at \(String(describing: cursor), privacy: .public): \(String(describing: newZone?.action), privacy: .public)")
            zone = newZone
            if newZone != nil { Haptics.tick() }
        }

        // An edge zone wins over a window underneath.
        if let newZone {
            swapTarget = nil
            if zoneChanged { showPreview(for: newZone, window: window) }
            return
        }

        let target = isSuppressed ? nil : findSwapTarget(at: cursor)
        if target?.windowID != swapTarget?.windowID {
            swapTarget = target
            if let target {
                overlay.show(target.slot)
                Haptics.tick()
            } else {
                overlay.hide()
            }
        } else if zoneChanged, target == nil {
            overlay.hide()
        }
    }

    /// Snaps the window into the current zone or swaps it with the window under it, then
    /// ends tracking.
    func finish(window: AXWindow) {
        defer { cancel() }
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
        overlay.hide()
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
    private func findSwapTarget(at cursor: CGPoint) -> SwapTarget? {
        guard let swapSource else { return nil }
        if let lastSwapProbe, hypot(cursor.x - lastSwapProbe.x, cursor.y - lastSwapProbe.y) < Self.swapProbeDistance {
            return swapTarget
        }
        lastSwapProbe = cursor

        // Front to back, so this is the window the pointer is over beneath the dragged one.
        guard let hit = WindowServer.windows().first(where: { $0.id != swapSource.windowID && $0.bounds.contains(cursor) }) else {
            return nil
        }
        if let swapTarget, swapTarget.windowID == hit.id { return swapTarget }
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
