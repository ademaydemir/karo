import AppKit
import OSLog
import TesseraAccessibility
import TesseraCore

/// Follows the pointer during a window drag, previews the snap zone under it and snaps the
/// window on release. Shared by ordinary title-bar drags and modifier drags.
@MainActor
final class SnapZoneTracker {
    var detector = ZoneDetector()

    private let placer: WindowPlacer
    private let overlay = SnapPreviewOverlay()
    private let logger = Logger(subsystem: "dev.ademaydemir.Tessera", category: "drag")
    private var zone: ZoneDetector.Zone?

    init(placer: WindowPlacer) {
        self.placer = placer
    }

    /// - Parameter isSuppressed: Snapping is skipped, e.g. while ⇧ is held.
    func update(cursor: CGPoint, window: AXWindow, isSuppressed: Bool) {
        let newZone = isSuppressed ? nil : detector.zone(at: cursor, displays: ScreenGeometry.displays().map(\.frame))
        guard newZone != zone else { return }
        logger.debug("Zone at \(String(describing: cursor), privacy: .public): \(String(describing: newZone?.action), privacy: .public)")
        zone = newZone
        if newZone != nil { Haptics.tick() }

        let displays = ScreenGeometry.displays()
        guard let newZone,
              displays.indices.contains(newZone.displayIndex),
              let currentFrame = try? window.frame(),
              let target = placer.targetFrame(for: newZone.action, currentFrame: currentFrame, on: displays[newZone.displayIndex]) else {
            overlay.hide()
            return
        }
        overlay.show(target)
    }

    /// Snaps the window into the current zone, if any, and ends tracking.
    func finish(window: AXWindow) {
        defer { cancel() }
        let displays = ScreenGeometry.displays()
        guard let zone, displays.indices.contains(zone.displayIndex) else { return }
        do {
            let currentFrame = try window.frame()
            try placer.place(window, zone.action, from: currentFrame, on: displays[zone.displayIndex])
        } catch {
            logger.error("Snap to \(zone.action.rawValue, privacy: .public) failed: \(String(describing: error), privacy: .public)")
        }
    }

    func cancel() {
        zone = nil
        overlay.hide()
    }
}
