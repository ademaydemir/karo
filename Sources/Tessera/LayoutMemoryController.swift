import AppKit
import OSLog
import TesseraAccessibility
import TesseraCore

/// Puts windows back where they were when a display setup returns, e.g. after reconnecting
/// a laptop to its external monitor.
///
/// The layout of each display configuration is recorded shortly after windows stop moving,
/// driven by window notifications rather than polling, so an idle Mac costs nothing. Frames
/// are kept in memory for as long as Tessera runs.
@MainActor
final class LayoutMemoryController {
    /// Windows settle a moment after the last move before they are recorded.
    private static let snapshotDelay: Duration = .seconds(1)
    /// macOS rearranges windows after a display change; restoring waits for that to finish.
    private static let settleDelay: Duration = .seconds(2)

    var isEnabled = true

    private let catalog: WindowCatalog
    private let logger = Logger(subsystem: "dev.ademaydemir.Tessera", category: "layout-memory")
    private var memory = LayoutMemory<WindowIdentity>()
    private var snapshotTask: Task<Void, Never>?
    private var restoreTask: Task<Void, Never>?
    /// While displays change, macOS piles windows onto the remaining display; those
    /// positions must not overwrite the layout being protected.
    private var isSettling = false
    private var screenObserver: NSObjectProtocol?

    init(catalog: WindowCatalog) {
        self.catalog = catalog
    }

    func start() {
        guard screenObserver == nil else { return }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.displaysChanged() }
        }
        scheduleSnapshot()
    }

    /// Call when any window moved, resized or appeared.
    func windowsChanged() {
        guard isEnabled, !isSettling else { return }
        scheduleSnapshot()
    }

    private func scheduleSnapshot() {
        snapshotTask?.cancel()
        snapshotTask = Task { [weak self] in
            try? await Task.sleep(for: Self.snapshotDelay)
            guard !Task.isCancelled, let self, !self.isSettling else { return }
            self.recordSnapshot()
        }
    }

    private func recordSnapshot() {
        guard isEnabled else { return }
        let frames = Dictionary(
            catalog.visibleWindows().map { ($0.window.identity, $0.frame) },
            uniquingKeysWith: { first, _ in first }
        )
        memory.record(frames, for: currentConfiguration())
    }

    private func displaysChanged() {
        snapshotTask?.cancel()
        restoreTask?.cancel()
        isSettling = true
        restoreTask = Task { [weak self] in
            try? await Task.sleep(for: Self.settleDelay)
            guard !Task.isCancelled, let self else { return }
            self.restoreLayout()
            self.isSettling = false
            self.recordSnapshot()
        }
    }

    private func restoreLayout() {
        let configuration = currentConfiguration()
        guard isEnabled, let saved = memory.frames(for: configuration) else { return }
        var restored = 0
        for (window, frame) in catalog.visibleWindows() {
            guard let target = saved[window.identity], !Self.isClose(target, frame) else { continue }
            do {
                try window.setFrame(target)
                restored += 1
            } catch {
                logger.error("Restoring a window failed: \(String(describing: error), privacy: .public)")
            }
        }
        logger.info("Restored \(restored, privacy: .public) windows for the new display setup")
    }

    private func currentConfiguration() -> String {
        DisplayConfiguration.key(for: ScreenGeometry.displayDescriptors())
    }

    private static func isClose(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) <= 1 && abs(a.minY - b.minY) <= 1 && abs(a.width - b.width) <= 1 && abs(a.height - b.height) <= 1
    }
}
