import AppKit
import OSLog
import TesseraAccessibility
import TesseraCore

/// Windows-style Snap Assist: after a window is snapped, every free part of the display
/// offers the other windows at once, and the chosen window fills that part.
///
/// A half or a third leaves one region. A quarter leaves two (the other quarter on its side
/// and the opposite half), each with its own panel. A window chosen in one panel disappears
/// from the others; Esc or a click anywhere else closes them all.
///
/// Resting the pointer on a window's card moves that very window into the region, so the
/// suggestion shows exactly how the window will look there (an image could not: apps lay
/// their content out anew at the new size). It goes back when the pointer moves on.
@MainActor
final class SnapAssistController {
    /// A window temporarily moved into a region while its card is hovered.
    private struct LivePreview {
        let region: WindowAction
        let itemID: Int
        let window: AXWindow
        let originalFrame: CGRect
    }

    /// Long enough that moving the pointer across cards does not shuffle windows around.
    private static let livePreviewDelay: Duration = .milliseconds(180)
    /// The glass covers quickly so the swap feels immediate, and clears more slowly so the
    /// new window eases into view.
    private static let coverDuration: TimeInterval = 0.12
    private static let revealDuration: TimeInterval = 0.22

    private struct Session {
        let display: Display
        /// The other windows, as listed when the session started.
        let entries: [WindowCatalog.Entry]
        /// The snapped window and windows placed since.
        var placed: Set<WindowIdentity>
        /// One panel per region still on offer.
        var panels: [WindowAction: SnapAssistPanel] = [:]
        var escapeHotkey: HotkeyManager.Token?
        var mouseMonitor: Any?
        var previewTask: Task<Void, Never>?
        var livePreview: LivePreview?
        var hoverTask: Task<Void, Never>?
    }

    var isEnabled = true
    var showsPreviews = false

    private let catalog: WindowCatalog
    private let placer: WindowPlacer
    private let hotkeys: HotkeyManager
    private let logger = Logger(subsystem: "dev.ademaydemir.Tessera", category: "snap-assist")
    private var session: Session?
    /// The live-preview swap in progress, if any.
    private var transition: Task<Void, Never>?

    init(catalog: WindowCatalog, placer: WindowPlacer, hotkeys: HotkeyManager) {
        self.catalog = catalog
        self.placer = placer
        self.hotkeys = hotkeys
    }

    /// Offers windows for the regions `window` left free after it was placed with `action`.
    func offer(after window: AXWindow, action: WindowAction, frame: CGRect, display: Display) {
        close()
        guard isEnabled else { return }
        let regions = action.snapAssistRegions.compactMap { region -> (WindowAction, CGRect)? in
            guard let frame = placer.targetFrame(for: region, currentFrame: .zero, on: display),
                  !Self.isOccupied(frame) else { return nil }
            return (region, frame)
        }
        guard !regions.isEmpty else { return }

        let capturesPreviews = showsPreviews && ScreenRecordingPermission.isGranted
        let entries = catalog.windows(includingWindowIDs: capturesPreviews).filter {
            $0.window.identity != window.identity && !$0.item.isBackgrounded
        }
        guard !entries.isEmpty else { return }

        var session = Session(display: display, entries: entries, placed: [window.identity])
        for (region, frame) in regions {
            let panel = SnapAssistPanel()
            panel.model.showsPreviews = capturesPreviews
            panel.model.items = entries.map(\.item)
            panel.model.onChoose = { [weak self] itemID in self?.choose(itemID, for: region) }
            panel.model.onHover = { [weak self] itemID in self?.hover(itemID, in: region) }
            session.panels[region] = panel
            panel.show(in: frame)
        }
        if capturesPreviews {
            let targets = entries.compactMap { entry in entry.windowID.map { (item: entry.item.id, windowID: $0) } }
            session.previewTask = Task { [weak self] in
                await self?.catalog.previewProvider.capturePreviews(for: targets) { itemID, preview in
                    self?.setPreview(preview, forItem: itemID)
                }
            }
        }
        // Esc and clicks elsewhere close every panel. Clicks inside a panel are local events
        // and do not reach the global monitor.
        session.escapeHotkey = try? hotkeys.register(KeyboardShortcut(keyCode: KeyCode.escape, modifiers: [])) { [weak self] in
            self?.close()
        }
        session.mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
        self.session = session
    }

    func close() {
        guard let session else { return }
        session.hoverTask?.cancel()
        if let livePreview = session.livePreview {
            revert(livePreview)
        }
        session.previewTask?.cancel()
        if let token = session.escapeHotkey { hotkeys.unregister(token) }
        if let monitor = session.mouseMonitor { NSEvent.removeMonitor(monitor) }
        session.panels.values.forEach { $0.hide() }
        self.session = nil
    }

    private func setPreview(_ preview: NSImage, forItem itemID: Int) {
        guard let session else { return }
        for panel in session.panels.values {
            guard let index = panel.model.items.firstIndex(where: { $0.id == itemID }) else { continue }
            panel.model.items[index].preview = preview
        }
    }

    // MARK: - Live preview

    private func hover(_ itemID: Int?, in region: WindowAction) {
        session?.hoverTask?.cancel()
        session?.hoverTask = Task { [weak self] in
            try? await Task.sleep(for: Self.livePreviewDelay)
            guard !Task.isCancelled, let self else { return }
            // Transitions run one after another; overlapping fades and window moves would
            // leave the glass and windows in a muddle when the pointer moves quickly.
            let previous = self.transition
            let transition = Task { [weak self] in
                await previous?.value
                await self?.transitionLivePreview(to: itemID, in: region)
            }
            self.transition = transition
        }
    }

    /// Swaps the window shown live, as a cross-fade: the glass covers the region, the new
    /// window moves in behind it (before the old one leaves, so the region is never empty),
    /// then the glass clears. Windows can only jump, not animate, so the glass hides the jump.
    private func transitionLivePreview(to itemID: Int?, in region: WindowAction) async {
        guard let session else { return }
        let current = session.livePreview
        if let current {
            guard current.region != region || current.itemID != itemID else { return }
            // Leaving a card only ends its own region's preview; the other panel reports its own.
            guard itemID != nil || current.region == region else { return }
        }
        let next = itemID.flatMap { itemID in session.entries.first { $0.item.id == itemID } }
        guard current != nil || next != nil else { return }

        if let current, let panel = session.panels[current.region] {
            await panel.setGlassVisible(true, duration: Self.coverDuration)
        }
        // The session may have ended or moved on while the glass faded in.
        guard self.session != nil else { return }

        if let next, let itemID,
           let frame = try? next.window.frame(),
           let target = placer.targetFrame(for: region, currentFrame: frame, on: session.display) {
            do {
                next.window.raise()
                try placer.fit(next.window, to: target, within: session.display.visibleFrame)
                self.session?.livePreview = LivePreview(region: region, itemID: itemID, window: next.window, originalFrame: frame)
            } catch {
                logger.error("Live preview failed: \(String(describing: error), privacy: .public)")
                self.session?.livePreview = nil
            }
        } else {
            self.session?.livePreview = nil
        }
        if let current {
            revert(current)
        }

        if self.session?.livePreview != nil, let panel = self.session?.panels[region] {
            await panel.setGlassVisible(false, duration: Self.revealDuration)
        }
    }

    private func revert(_ preview: LivePreview) {
        do {
            try preview.window.setFrame(preview.originalFrame)
        } catch {
            logger.error("Reverting a live preview failed: \(String(describing: error), privacy: .public)")
        }
    }

    // MARK: - Choosing

    private func choose(_ itemID: Int, for region: WindowAction) {
        guard var session,
              let panel = session.panels.removeValue(forKey: region),
              let entry = session.entries.first(where: { $0.item.id == itemID }) else { return }
        panel.hide()
        session.hoverTask?.cancel()
        // A window already shown live here stays; restore later goes back to where it was
        // before the preview. Any other preview is undone.
        var originalFrame: CGRect?
        if let preview = session.livePreview {
            if preview.region == region, preview.itemID == itemID {
                originalFrame = preview.originalFrame
            } else {
                revert(preview)
                if let panel = session.panels[preview.region] {
                    Task { await panel.setGlassVisible(true, duration: Self.coverDuration) }
                }
            }
            session.livePreview = nil
        }
        session.placed.insert(entry.window.identity)
        // The chosen window is no longer on offer for the remaining regions.
        for other in session.panels.values {
            other.model.items.removeAll { $0.id == itemID }
        }
        self.session = session

        do {
            try entry.window.bringToFront()
            catalog.touch(entry.window.identity)
            let frame = try originalFrame ?? entry.window.frame()
            try placer.place(entry.window, region, from: frame, on: session.display, announces: false)
        } catch {
            logger.error("Placing the chosen window failed: \(String(describing: error), privacy: .public)")
            NSSound.beep()
        }

        if session.panels.isEmpty || session.panels.values.allSatisfy({ $0.model.items.isEmpty }) {
            close()
        }
    }

    /// Whether a window already fills the region, in which case there is nothing to offer.
    /// Apps that size in steps fill a region up to one step larger or smaller, see `StepSizeFitting`.
    private static func isOccupied(_ region: CGRect) -> Bool {
        let tolerance = StepSizeFitting.maximumStep
        return WindowServer.windows().contains { window in
            abs(window.bounds.midX - region.midX) <= tolerance && abs(window.bounds.midY - region.midY) <= tolerance
                && abs(window.bounds.width - region.width) <= tolerance && abs(window.bounds.height - region.height) <= tolerance
        }
    }
}
