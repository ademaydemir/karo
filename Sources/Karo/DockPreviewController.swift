import AppKit
import OSLog
import KaroAccessibility

/// Shows an app's windows when the pointer rests on its Dock icon; clicking one brings it
/// forward, and its buttons minimize or close it.
///
/// The panel opens after a short rest, so sweeping across the Dock does not flash it, and
/// then follows the pointer from icon to icon at once. It closes when the pointer has left
/// both the icon and the panel for a moment, or on any click elsewhere.
@MainActor
final class DockPreviewController {
    /// Rest on an icon before the panel opens.
    private static let openDelay: Duration = .milliseconds(300)
    /// Time outside icon and panel before the panel closes; covers the gap between them.
    private static let closeDelay: Duration = .milliseconds(300)
    /// Distance between the icon and the panel.
    private static let offset: CGFloat = 8
    /// Some apps bring their previously main window back on activation; raising again
    /// shortly after makes the chosen window win.
    private static let reraiseDelay: Duration = .milliseconds(60)

    var isEnabled = true {
        didSet {
            guard isEnabled != oldValue else { return }
            if isEnabled { start() } else { stop() }
        }
    }

    private let catalog: WindowCatalog
    private let model = DockPreviewModel()
    private let panel: NSPanel
    private let background: NSView
    private let hostingView: FirstMouseHostingView<DockPreviewView>
    private let logger = Logger(subsystem: "dev.ademaydemir.Karo", category: "dock-preview")
    private lazy var observer = DockObserver { [weak self] item in self?.hover(item) }
    private var isStarted = false

    /// The icon under the pointer, as last reported by the Dock.
    private var hoveredItem: DockObserver.Item?
    /// The icon the panel belongs to, and the windows it shows (parallel to `model.items`).
    private var shownItem: DockObserver.Item?
    private var windows: [AXWindow] = []
    private var showTask: Task<Void, Never>?
    private var previewTask: Task<Void, Never>?
    private var trackingTimer: Timer?
    private var lastInside = ContinuousClock.now
    private var clickMonitor: Any?

    init(catalog: WindowCatalog) {
        self.catalog = catalog
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle, .fullScreenAuxiliary]

        let container = NSView()
        background = GlassSurface.make(cornerRadius: 20)
        background.autoresizingMask = [.width, .height]
        container.addSubview(background)
        hostingView = FirstMouseHostingView(rootView: DockPreviewView(model: model))
        hostingView.autoresizingMask = [.width, .height]
        container.addSubview(hostingView)
        panel.contentView = container

        model.onChoose = { [weak self] id in self?.choose(id) }
        model.onMinimize = { [weak self] id in self?.minimize(id) }
        model.onClose = { [weak self] id in self?.close(id) }
    }

    /// Needs Accessibility permission; call again once it is granted.
    func start() {
        guard isEnabled, !isStarted else { return }
        isStarted = true
        observer.start()
    }

    private func stop() {
        guard isStarted else { return }
        isStarted = false
        observer.stop()
        hide()
    }

    // MARK: - Hover

    private func hover(_ item: DockObserver.Item?) {
        hoveredItem = item
        guard let item else { return }
        if panel.isVisible {
            // Already open: follow the pointer to the next icon at once.
            if item != shownItem { show(item) }
            return
        }
        showTask?.cancel()
        showTask = Task { [weak self] in
            try? await Task.sleep(for: Self.openDelay)
            guard !Task.isCancelled, let self, self.hoveredItem == item else { return }
            self.show(item)
        }
    }

    private func show(_ item: DockObserver.Item) {
        let capturesPreviews = ScreenRecordingPermission.isGranted
        let entries = catalog.windows(includingWindowIDs: capturesPreviews, ofApplication: item.processIdentifier)
        guard !entries.isEmpty else {
            hide()
            return
        }
        shownItem = item
        windows = entries.map(\.window)
        model.applicationName = NSRunningApplication(processIdentifier: item.processIdentifier)?.localizedName ?? ""
        model.items = entries.map { entry in
            DockPreviewItem(
                id: entry.item.id, title: entry.item.title, icon: entry.item.icon,
                preview: entry.item.preview, isMinimized: entry.item.isBackgrounded
            )
        }
        layoutPanel()
        panel.orderFrontRegardless()
        startTracking()

        previewTask?.cancel()
        if capturesPreviews {
            let targets = entries.compactMap { entry in entry.windowID.map { (item: entry.item.id, windowID: $0) } }
            previewTask = Task { [weak self] in
                await self?.catalog.previewProvider.capturePreviews(for: targets) { id, preview in
                    guard let self, let index = self.model.items.firstIndex(where: { $0.id == id }) else { return }
                    self.model.items[index].preview = preview
                }
            }
        }
    }

    private func hide() {
        showTask?.cancel()
        previewTask?.cancel()
        trackingTimer?.invalidate()
        trackingTimer = nil
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        clickMonitor = nil
        panel.orderOut(nil)
        shownItem = nil
        windows = []
    }

    // MARK: - Placement

    /// Next to the icon, on the side away from the Dock's screen edge.
    private func layoutPanel() {
        guard let shownItem else { return }
        let icon = ScreenGeometry.appKitFrame(fromAccessibility: shownItem.frame)
        let center = CGPoint(x: icon.midX, y: icon.midY)
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(center) }) ?? NSScreen.main else { return }
        let bounds = screen.frame

        model.columns = DockPreviewLayout.columns(fittingWidth: bounds.width * 0.9)
        let size = DockPreviewLayout.size(count: model.items.count, columns: model.columns)
        // The Dock hugs one screen edge; its icons sit close to it.
        let edgeDistance: CGFloat = 100
        var origin: CGPoint
        if icon.minY - bounds.minY < edgeDistance {
            origin = CGPoint(x: icon.midX - size.width / 2, y: icon.maxY + Self.offset)
        } else if icon.minX - bounds.minX < edgeDistance {
            origin = CGPoint(x: icon.maxX + Self.offset, y: icon.midY - size.height / 2)
        } else {
            origin = CGPoint(x: icon.minX - Self.offset - size.width, y: icon.midY - size.height / 2)
        }
        // Kept on the display and clear of the menu bar.
        origin.x = min(max(origin.x, bounds.minX + 4), bounds.maxX - size.width - 4)
        origin.y = min(max(origin.y, bounds.minY + 4), screen.visibleFrame.maxY - size.height - 4)

        let frame = CGRect(origin: origin, size: size).integral
        panel.setFrame(frame, display: false)
        let contentBounds = CGRect(origin: .zero, size: frame.size)
        hostingView.frame = contentBounds
        background.frame = contentBounds
        panel.display()
    }

    // MARK: - Tracking

    private func startTracking() {
        lastInside = .now
        if trackingTimer == nil {
            let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.checkPointer() }
            }
            RunLoop.main.add(timer, forMode: .common)
            trackingTimer = timer
        }
        if clickMonitor == nil {
            // Clicks in the panel are local events and do not reach this monitor.
            clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                MainActor.assumeIsolated { self?.hide() }
            }
        }
    }

    private func checkPointer() {
        let pointer = NSEvent.mouseLocation
        let icon = shownItem.map { ScreenGeometry.appKitFrame(fromAccessibility: $0.frame) } ?? .null
        let isInside = panel.frame.insetBy(dx: -6, dy: -6).contains(pointer)
            || icon.insetBy(dx: -4, dy: -4).contains(pointer)
            || hoveredItem != nil
        if isInside {
            lastInside = .now
        } else if ContinuousClock.now - lastInside > Self.closeDelay {
            hide()
        }
    }

    // MARK: - Actions

    private func window(for id: Int) -> AXWindow? {
        guard let index = model.items.firstIndex(where: { $0.id == id }), windows.indices.contains(index) else { return nil }
        return windows[index]
    }

    private func choose(_ id: Int) {
        guard let window = window(for: id) else { return }
        hide()
        do {
            try window.bringToFront()
            catalog.touch(window.identity)
            Task {
                try? await Task.sleep(for: Self.reraiseDelay)
                window.raise()
            }
        } catch {
            logger.error("Bringing a window forward failed: \(String(describing: error), privacy: .public)")
            NSSound.beep()
        }
    }

    private func minimize(_ id: Int) {
        guard let window = window(for: id), let index = model.items.firstIndex(where: { $0.id == id }) else { return }
        do {
            try window.minimize()
            model.items[index].isMinimized = true
        } catch {
            logger.error("Minimizing a window failed: \(String(describing: error), privacy: .public)")
            NSSound.beep()
        }
    }

    private func close(_ id: Int) {
        guard let window = window(for: id), let index = model.items.firstIndex(where: { $0.id == id }) else { return }
        do {
            try window.close()
        } catch {
            logger.error("Closing a window failed: \(String(describing: error), privacy: .public)")
            NSSound.beep()
            return
        }
        model.items.remove(at: index)
        windows.remove(at: index)
        if model.items.isEmpty {
            hide()
        } else {
            layoutPanel()
        }
    }
}
