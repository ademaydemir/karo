import AppKit
import SwiftUI
import KaroCore

extension View {
    /// Gives a view a radial quick-action menu: a right click opens a ring of `actions` around
    /// it, and the pointer picks one. This is the only place that knows how the menu opens,
    /// tracks the pointer, closes and takes clicks; a screen just supplies the actions.
    ///
    /// The view keeps its own hover and left clicks, and scrolling over it still works.
    ///
    /// - Parameters:
    ///   - isEnabled: Whether a right click opens the menu. Turning it off closes an open menu.
    ///   - onActiveChange: `true` while the pointer is over the view or its ring, `false` once
    ///     it has stayed off both for a moment.
    func radialMenu(
        isEnabled: Bool,
        outerRadius: CGFloat,
        actions: [SwitcherQuickAction],
        isOpen: Binding<Bool>,
        onAction: @escaping (SwitcherQuickAction) -> Void,
        onActiveChange: @escaping (Bool) -> Void = { _ in }
    ) -> some View {
        modifier(RadialMenuInteraction(
            isEnabled: isEnabled,
            outerRadius: outerRadius,
            actions: actions,
            isOpen: isOpen,
            onAction: onAction,
            onActiveChange: onActiveChange
        ))
    }
}

/// What the pointer tracker needs to know to tell where the pointer is. Both the tracker and
/// the modifier derive the region from this, so they cannot disagree.
private struct RadialMenuLayout: Equatable {
    var outerRadius: CGFloat
    var sliceCount: Int
    /// The item's unscaled frame size: the card scales while the menu is open, but the pointer
    /// must keep being measured against where the item is laid out.
    var itemSize: CGSize
    var isOpen: Bool
    var isEnabled: Bool

    /// The tracker covers the item and the ring, centered on the item. A wide list row is
    /// larger than the ring's square, so it is the union of the two.
    var trackerSize: CGSize {
        CGSize(width: max(outerRadius * 2, itemSize.width), height: max(outerRadius * 2, itemSize.height))
    }

    /// How far beyond the item a right click still opens the menu. The card is drawn scaled,
    /// rotated or offset (hover, Deck, Cover Flow), so where it appears can differ a little from
    /// where it is laid out; this keeps a click on its visible edge from missing the menu.
    static let rightClickTolerance: CGFloat = 8

    /// Whether a right click at `point` (tracker coordinates) should open or stay in the menu.
    func claimsRightClick(at point: CGPoint) -> Bool {
        guard isEnabled else { return false }
        if isOpen, region(of: point) != .outside { return true }
        let center = CGPoint(x: trackerSize.width / 2, y: trackerSize.height / 2)
        let itemRect = CGRect(x: center.x - itemSize.width / 2, y: center.y - itemSize.height / 2, width: itemSize.width, height: itemSize.height)
        return itemRect.insetBy(dx: -Self.rightClickTolerance, dy: -Self.rightClickTolerance).contains(point)
    }

    /// `point` is in the tracker's flipped coordinates; the ring and the item share its center.
    func region(of point: CGPoint) -> RadialMenuRegion {
        let center = CGPoint(x: trackerSize.width / 2, y: trackerSize.height / 2)
        return RadialMenuGeometry.region(
            of: point,
            ringCenter: center,
            innerRadius: RadialMenu.innerRadius(outerRadius: outerRadius),
            outerRadius: outerRadius,
            sliceCount: sliceCount,
            itemRect: CGRect(x: center.x - itemSize.width / 2, y: center.y - itemSize.height / 2, width: itemSize.width, height: itemSize.height),
            isOpen: isOpen
        )
    }
}

private struct RadialMenuInteraction: ViewModifier {
    /// The pointer leaves the item for a moment when it crosses onto a slice or the gap
    /// between slices; closing only after this grace period keeps the menu from flickering.
    private static let closeDelay: Duration = .milliseconds(120)

    let isEnabled: Bool
    let outerRadius: CGFloat
    let actions: [SwitcherQuickAction]
    @Binding var isOpen: Bool
    let onAction: (SwitcherQuickAction) -> Void
    let onActiveChange: (Bool) -> Void

    @State private var itemSize: CGSize = .zero
    /// In the tracker's coordinates; `nil` while the pointer is outside it.
    @State private var pointer: CGPoint?
    @State private var closeTask: Task<Void, Never>?

    private var layout: RadialMenuLayout {
        RadialMenuLayout(outerRadius: outerRadius, sliceCount: actions.count, itemSize: itemSize, isOpen: isOpen, isEnabled: isEnabled)
    }

    private var region: RadialMenuRegion {
        pointer.map { layout.region(of: $0) } ?? .outside
    }

    private var hoveredAction: SwitcherQuickAction? {
        guard isOpen, case .slice(let index) = region, actions.indices.contains(index) else { return nil }
        return actions[index]
    }

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGSize.self, of: \.size) { itemSize = $0 }
            .overlay {
                RadialMenu(isOpen: isOpen, outerRadius: outerRadius, actions: actions, hoveredAction: hoveredAction)
                    .animation(.easeOut(duration: 0.12), value: hoveredAction)
            }
            .overlay {
                RadialMenuTracker(
                    layout: layout,
                    onPointer: { pointer = $0 },
                    onRightClick: open,
                    onSliceClick: { if actions.indices.contains($0) { onAction(actions[$0]) } }
                )
                .frame(width: layout.trackerSize.width, height: layout.trackerSize.height)
            }
            .onChange(of: region != .outside) { _, isActive in
                if isActive {
                    closeTask?.cancel()
                    closeTask = nil
                    onActiveChange(true)
                } else {
                    scheduleClose()
                }
            }
            .onChange(of: isEnabled) { _, isEnabled in
                if !isEnabled, isOpen {
                    withAnimation(.easeOut(duration: 0.16)) { isOpen = false }
                }
            }
            .onDisappear { closeTask?.cancel() }
    }

    private func open() {
        guard isEnabled, !isOpen else { return }
        withAnimation(.spring(response: 0.36, dampingFraction: 0.7)) { isOpen = true }
    }

    private func scheduleClose() {
        guard closeTask == nil else { return }
        closeTask = Task { @MainActor in
            try? await Task.sleep(for: Self.closeDelay)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.16)) { isOpen = false }
            onActiveChange(false)
            closeTask = nil
        }
    }
}

/// Follows the pointer and takes the clicks the menu needs, as one AppKit view. SwiftUI hover
/// and hit-testing on overlapping views proved unreliable here: a view that appears under a
/// resting pointer reports nothing until the mouse moves. A tracking area does not care what
/// is drawn above it, and the current pointer position can be read at any time.
private struct RadialMenuTracker: NSViewRepresentable {
    let layout: RadialMenuLayout
    let onPointer: (CGPoint?) -> Void
    let onRightClick: () -> Void
    let onSliceClick: (Int) -> Void

    func makeNSView(context: Context) -> TrackerView {
        let view = TrackerView()
        update(view)
        return view
    }

    func updateNSView(_ view: TrackerView, context: Context) {
        let opened = layout.isOpen && !view.layout.isOpen
        update(view)
        // Without this the state would stay as it was until the mouse moves.
        if opened { view.reportCurrentLocation() }
    }

    private func update(_ view: TrackerView) {
        view.layout = layout
        view.onPointer = onPointer
        view.onRightClick = onRightClick
        view.onSliceClick = onSliceClick
    }

    final class TrackerView: NSView, SecondaryClickClaiming {
        var layout = RadialMenuLayout(outerRadius: 0, sliceCount: 0, itemSize: .zero, isOpen: false, isEnabled: false)
        var onPointer: (CGPoint?) -> Void = { _ in }
        var onRightClick: () -> Void = {}
        var onSliceClick: (Int) -> Void = { _ in }

        private var pressedSlice: Int?

        override var isFlipped: Bool { true }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(NSTrackingArea(
                rect: .zero,
                options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: self
            ))
            // The view may have moved under a resting pointer, for instance when scrolling.
            reportCurrentLocation()
        }

        /// Reports where the pointer is now, without waiting for it to move. Deferred, because
        /// this can run while SwiftUI is still updating the view.
        func reportCurrentLocation() {
            DispatchQueue.main.async { [weak self] in
                guard let self, let window else { return }
                let point = convert(window.mouseLocationOutsideOfEventStream, from: nil)
                onPointer(bounds.contains(point) ? point : nil)
            }
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            // Claiming only what the menu needs keeps hover, left clicks on the item and
            // scrolling with SwiftUI.
            guard let type = NSApp.currentEvent?.type else { return nil }
            let local = convert(point, from: superview)
            switch type {
            case .rightMouseDown, .rightMouseUp:
                return layout.claimsRightClick(at: local) ? self : nil
            case .leftMouseDown, .leftMouseUp:
                if layout.isOpen, case .slice = layout.region(of: local) { return self }
                return nil
            default:
                return nil
            }
        }

        override func mouseEntered(with event: NSEvent) { reportPointer(of: event) }
        override func mouseMoved(with event: NSEvent) { reportPointer(of: event) }
        override func mouseExited(with event: NSEvent) { onPointer(nil) }

        override func rightMouseDown(with event: NSEvent) {
            reportPointer(of: event)
            onRightClick()
        }

        override func mouseDown(with event: NSEvent) {
            pressedSlice = slice(of: event)
        }

        /// A click counts when it ends on the slice it began on, as with any button.
        override func mouseUp(with event: NSEvent) {
            defer { pressedSlice = nil }
            guard let pressedSlice, pressedSlice == slice(of: event) else { return }
            onSliceClick(pressedSlice)
        }

        private func reportPointer(of event: NSEvent) {
            onPointer(convert(event.locationInWindow, from: nil))
        }

        private func slice(of event: NSEvent) -> Int? {
            guard layout.isOpen, case .slice(let index) = layout.region(of: convert(event.locationInWindow, from: nil)) else { return nil }
            return index
        }
    }
}
