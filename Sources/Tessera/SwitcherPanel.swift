import AppKit
import SwiftUI
import TesseraCore

struct SwitcherItem: Identifiable {
    /// Stable for the session, so previews still find their item after others are removed.
    let id: Int
    let title: String
    let applicationName: String
    let icon: NSImage
    /// The owning app's process, to stack an app's windows into one deck.
    let applicationID: pid_t
    /// Minimized, or its app is hidden.
    var isBackgrounded: Bool
    var preview: NSImage?
}

struct SwitcherHint: Identifiable {
    let keys: String
    let title: String
    var id: String { keys }
}

/// Presentation state of the switcher, owned by `WindowSwitcher`.
@MainActor
@Observable
final class SwitcherModel {
    var items: [SwitcherItem] = []
    /// Index into `items`.
    var selectedIndex = 0
    var showsPreviews = false
    var size = SwitcherSize.medium
    var style = SwitcherStyle.grid
    var maximumColumns = 6
    var hints: [SwitcherHint] = []
    @ObservationIgnored var onHover: (Int) -> Void = { _ in }
    @ObservationIgnored var onChoose: (Int) -> Void = { _ in }
    @ObservationIgnored var onQuickAction: (Int, SwitcherQuickAction) -> Void = { _, _ in }
    /// Selects an item without switching (Cover Flow: clicking a side card, scrolling).
    @ObservationIgnored var onSelect: (Int) -> Void = { _ in }
    /// +1 / -1 from scrolling over the panel.
    @ObservationIgnored var onScrollStep: (Int) -> Void = { _ in }

    var layout: SwitcherLayout {
        SwitcherLayout(size: size, showsPreviews: showsPreviews)
    }
}

/// The floating panel listing windows while ⌥ is held.
///
/// It never becomes key or active, so the frontmost app keeps focus and keyboard input
/// until a window is chosen. The window is larger than its glass background by a clear
/// margin, so the radial menu of an item at the edge can extend past the glass.
@MainActor
final class SwitcherPanel {
    let model = SwitcherModel()
    private let panel: NSPanel
    private let background: NSView
    private let hostingView: FirstMouseHostingView<SwitcherView>

    init() {
        panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle, .fullScreenAuxiliary]

        let container = NSView()
        background = GlassSurface.make(cornerRadius: 28)
        background.autoresizingMask = [.width, .height]
        container.addSubview(background)
        hostingView = FirstMouseHostingView(rootView: SwitcherView(model: model))
        hostingView.autoresizingMask = [.width, .height]
        var accumulator = ScrollStepAccumulator()
        hostingView.onScroll = { [model] event in
            if let step = accumulator.step(for: event) {
                model.onScrollStep(step)
            }
        }
        container.addSubview(hostingView)
        panel.contentView = container
    }

    /// Shows the panel centered on the display under the cursor.
    func show() {
        layoutPanel()
        panel.orderFrontRegardless()
    }

    /// Resizes the panel after items were removed or the size changed.
    func relayout() {
        guard panel.isVisible else { return }
        layoutPanel()
    }

    func hide() {
        panel.orderOut(nil)
    }

    private func layoutPanel() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? .zero
        let layout = model.layout
        model.maximumColumns = layout.columns(fitting: visible.width * 0.9)

        let size = hostingView.fittingSize
        let origin = CGPoint(x: (visible.midX - size.width / 2).rounded(), y: (visible.midY - size.height / 2).rounded())
        panel.setFrame(CGRect(origin: origin, size: size), display: false)
        let bounds = CGRect(origin: .zero, size: size)
        hostingView.frame = bounds
        background.frame = bounds.insetBy(dx: layout.ringMargin, dy: layout.ringMargin)
        panel.display()
    }
}

/// The panel never becomes key, so without this the first click on an item or a quick
/// action would be swallowed.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    /// Scroll events over the view, e.g. to move through Cover Flow.
    var onScroll: ((NSEvent) -> Void)?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func scrollWheel(with event: NSEvent) {
        if let onScroll {
            onScroll(event)
        } else {
            super.scrollWheel(with: event)
        }
    }
}

/// Turns scroll gestures into single steps. A Magic Mouse or trackpad swipe delivers many
/// small precise deltas; a wheel delivers one line per notch.
struct ScrollStepAccumulator {
    /// Points of precise scrolling per step.
    private static let threshold: CGFloat = 36
    private var accumulated: CGFloat = 0

    /// - Returns: +1 to move to the next item, -1 for the previous one, or `nil`.
    mutating func step(for event: NSEvent) -> Int? {
        // Momentum after the fingers lift would keep flinging the selection; only the
        // gesture itself counts.
        guard event.momentumPhase.isEmpty else { return nil }
        if event.phase == .began { accumulated = 0 }
        // Sideways swipes are the natural gesture; a plain wheel only scrolls vertically.
        let delta = abs(event.scrollingDeltaX) >= abs(event.scrollingDeltaY) ? event.scrollingDeltaX : event.scrollingDeltaY
        guard delta != 0 else { return nil }
        guard event.hasPreciseScrollingDeltas else {
            return delta < 0 ? 1 : -1
        }
        accumulated += delta
        guard abs(accumulated) >= Self.threshold else { return nil }
        // Content follows the fingers: swiping left brings the next card in from the right.
        let step = accumulated < 0 ? 1 : -1
        accumulated = 0
        return step
    }
}

/// Item metrics per size, for icon-only and preview styles.
struct SwitcherLayout {
    let size: SwitcherSize
    let showsPreviews: Bool

    var itemWidth: CGFloat {
        switch (size, showsPreviews) {
        case (.small, false): 88
        case (.medium, false): 112
        case (.large, false): 144
        case (.small, true): 168
        case (.medium, true): 216
        case (.large, true): 296
        }
    }

    var iconSize: CGFloat {
        switch size {
        case .small: 48
        case .medium: 64
        case .large: 96
        }
    }

    var radialRadius: CGFloat {
        switch size {
        case .small: 96
        case .medium: 112
        case .large: 132
        }
    }

    /// 16:10 matches typical window proportions; previews are aspect-fit inside it.
    var previewSize: CGSize { CGSize(width: itemWidth - 16, height: (itemWidth - 16) * 10 / 16) }
    var spacing: CGFloat { 18 }
    /// Inside the glass, around the items.
    var padding: CGFloat { 18 }
    /// Clear space around the glass, so a radial menu on an edge item is never cut off.
    /// Sized for an item of no size at all, since item heights vary with titles and
    /// previews; the space is transparent, so being generous costs nothing visible.
    var ringMargin: CGFloat { max(8, radialRadius - padding + 4) }

    /// Cards shown on each side of the selected one in Cover Flow; the outermost fade out.
    static let coverFlowVisibleNeighbours = 4
    var coverFlowWidth: CGFloat { itemWidth * 4.6 }
    var coverFlowHeight: CGFloat { (showsPreviews ? previewSize.height : iconSize) * 1.15 + 90 }

    func columns(fitting width: CGFloat) -> Int {
        max(1, Int((width - (padding + ringMargin) * 2 + spacing) / (itemWidth + spacing)))
    }

    func contentWidth(columns: Int) -> CGFloat {
        CGFloat(columns) * itemWidth + CGFloat(columns - 1) * spacing
    }
}

struct SwitcherView: View {
    let model: SwitcherModel
    /// The item under the pointer, or whose radial menu is under it; drawn above the others.
    @State private var activeID: Int?
    /// The item whose radial menu is open. The hint bar steps aside meanwhile, since the
    /// ring of a bottom-row item would cover it.
    @State private var openRadialID: Int?

    var body: some View {
        let layout = model.layout
        VStack(spacing: 14) {
            switch model.style {
            case .grid: grid(layout: layout)
            case .coverFlow: coverFlow(layout: layout)
            }

            HintBar(hints: hints)
                .frame(width: contentWidth(layout: layout))
                .opacity(openRadialID == nil ? 1 : 0)
                .animation(.easeOut(duration: 0.15), value: openRadialID)
        }
        .padding(layout.padding)
        .padding(layout.ringMargin)
        .fixedSize()
    }

    /// In Cover Flow the quick actions open with a right click, so the hint says so.
    private var hints: [SwitcherHint] {
        guard model.style == .coverFlow else { return model.hints }
        let rightClick = SwitcherHint(
            keys: String(localized: "Right-click", comment: "Mouse action in a hint"),
            title: String(localized: "Quick actions")
        )
        return [rightClick] + model.hints
    }

    // MARK: Grid with app decks

    /// Indices of `model.items`, grouped by app in order of each app's most recent window.
    private var decks: [[Int]] {
        var order: [pid_t] = []
        var groups: [pid_t: [Int]] = [:]
        for (index, item) in model.items.enumerated() {
            if groups[item.applicationID] == nil { order.append(item.applicationID) }
            groups[item.applicationID, default: []].append(index)
        }
        return order.compactMap { groups[$0] }
    }

    private func gridColumns(_ decks: [[Int]]) -> Int {
        max(1, min(decks.count, model.maximumColumns))
    }

    private func contentWidth(layout: SwitcherLayout) -> CGFloat {
        switch model.style {
        case .grid: layout.contentWidth(columns: gridColumns(decks))
        case .coverFlow: layout.coverFlowWidth
        }
    }

    private func grid(layout: SwitcherLayout) -> some View {
        let decks = self.decks
        let columnCount = gridColumns(decks)
        let rows = stride(from: 0, to: decks.count, by: columnCount).map { Array(decks[$0..<min($0 + columnCount, decks.count)]) }
        // Plain rows rather than a grid: zIndex only orders siblings, so the active deck and
        // its row are raised for a fanned deck or an open radial menu to cover the others.
        return VStack(alignment: .leading, spacing: layout.spacing) {
            ForEach(rows, id: \.first) { row in
                HStack(spacing: layout.spacing) {
                    ForEach(row, id: \.first) { deck in
                        DeckView(
                            indices: deck,
                            isExpanded: isExpanded(deck),
                            layout: layout,
                            itemView: { index in itemView(at: index, layout: layout) }
                        )
                        .zIndex(isRaised(deck) ? 1 : 0)
                    }
                }
                .zIndex(row.contains(where: isRaised) ? 1 : 0)
            }
        }
    }

    /// A deck fans out while the pointer is on one of its windows or the selection is in it.
    private func isExpanded(_ deck: [Int]) -> Bool {
        deck.count > 1 && isRaised(deck)
    }

    private func isRaised(_ deck: [Int]) -> Bool {
        deck.contains { $0 == model.selectedIndex || model.items[$0].id == activeID }
    }

    // MARK: Cover Flow

    private func coverFlow(layout: SwitcherLayout) -> some View {
        let selected = model.selectedIndex
        return ZStack {
            ForEach(Array(model.items.enumerated()), id: \.element.id) { index, _ in
                let distance = index - selected
                if abs(distance) <= SwitcherLayout.coverFlowVisibleNeighbours {
                    itemView(at: index, layout: layout, isCentered: distance == 0)
                        .modifier(CoverFlowPlacement(distance: distance, layout: layout))
                        .zIndex(Double(100 - abs(distance)))
                        .transition(.opacity)
                }
            }
        }
        .frame(width: layout.coverFlowWidth, height: layout.coverFlowHeight)
        .animation(.spring(response: 0.4, dampingFraction: 0.82), value: selected)
    }

    // MARK: Items

    private func itemView(at index: Int, layout: SwitcherLayout, isCentered: Bool = true) -> some View {
        let item = model.items[index]
        let isCoverFlow = model.style == .coverFlow
        return SwitcherItemView(
            item: item,
            isSelected: index == model.selectedIndex,
            layout: layout,
            radialTrigger: isCoverFlow ? (isCentered ? .secondaryClick : .none) : .hoverOrSecondaryClick,
            // In Cover Flow a side card is brought to the middle first; the middle one switches.
            onChoose: { isCentered ? model.onChoose(index) : model.onSelect(index) },
            onQuickAction: { model.onQuickAction(index, $0) },
            onActiveChange: { isActive in
                if isActive {
                    activeID = item.id
                    // Pointing selects in the grid; Cover Flow moves by scrolling and clicks,
                    // so the cards do not rotate away under the pointer.
                    if !isCoverFlow { model.onHover(index) }
                } else if activeID == item.id {
                    activeID = nil
                }
            },
            onRadialOpenChange: { isOpen in
                if isOpen {
                    openRadialID = item.id
                } else if openRadialID == item.id {
                    openRadialID = nil
                }
            }
        )
        .frame(width: layout.itemWidth)
        .zIndex(activeID == item.id ? 1 : 0)
    }
}

/// Catches right clicks over a SwiftUI view and lets every other event through. SwiftUI's
/// tap gestures only see the primary button.
private struct SecondaryClickArea: NSViewRepresentable {
    let action: () -> Void

    func makeNSView(context: Context) -> CatcherView {
        let view = CatcherView()
        view.action = action
        return view
    }

    func updateNSView(_ view: CatcherView, context: Context) {
        view.action = action
    }

    final class CatcherView: NSView {
        var action: () -> Void = {}

        override func hitTest(_ point: NSPoint) -> NSView? {
            // Claiming only right clicks keeps hover, left clicks and scrolling with SwiftUI.
            guard let type = NSApp.currentEvent?.type, type == .rightMouseDown || type == .rightMouseUp else { return nil }
            return super.hitTest(point)
        }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func rightMouseDown(with event: NSEvent) {
            action()
        }
    }
}

/// An app's windows as a stack of cards that fans out when expanded. The most recent window
/// is on top and is the only one that takes the pointer while the deck is closed.
private struct DeckView<Item: View>: View {
    let indices: [Int]
    let isExpanded: Bool
    let layout: SwitcherLayout
    let itemView: (Int) -> Item

    var body: some View {
        ZStack {
            ForEach(Array(indices.enumerated()), id: \.element) { position, index in
                itemView(index)
                    .modifier(DeckPlacement(position: position, count: indices.count, isExpanded: isExpanded, layout: layout))
                    .zIndex(Double(indices.count - position))
                    .allowsHitTesting(isExpanded || position == 0)
            }
        }
        .overlay(alignment: .topTrailing) {
            if indices.count > 1, !isExpanded {
                Text(verbatim: "\(indices.count)")
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Color.accentColor, in: Capsule())
                    .foregroundStyle(.white)
                    .offset(x: 6, y: -6)
                    .transition(.scale.combined(with: .opacity))
                    .accessibilityLabel(Text("\(indices.count) windows"))
            }
        }
        .frame(width: layout.itemWidth)
        .animation(.spring(response: 0.38, dampingFraction: 0.74), value: isExpanded)
    }
}

/// Where a card sits in a deck: slightly offset and turned when stacked, spread out in a gentle
/// arc when the deck is fanned.
private struct DeckPlacement: ViewModifier {
    let position: Int
    let count: Int
    let isExpanded: Bool
    let layout: SwitcherLayout

    func body(content: Content) -> some View {
        let centered = CGFloat(position) - CGFloat(count - 1) / 2
        // Fanned cards overlap more as the deck grows, so a large deck stays compact.
        let step = min(layout.itemWidth + 10, layout.itemWidth * 2.4 / CGFloat(max(count - 1, 1)))
        return content
            .offset(
                x: isExpanded ? centered * step : CGFloat(position) * 6,
                y: isExpanded ? abs(centered) * 6 : -CGFloat(position) * 6
            )
            .rotationEffect(.degrees(isExpanded ? Double(centered) * 3 : Double(position) * 3))
            .scaleEffect(isExpanded ? 1 : 1 - CGFloat(position) * 0.03)
    }
}

/// Where a card sits in Cover Flow: flat and large in the middle, tilted away on the sides.
private struct CoverFlowPlacement: ViewModifier {
    let distance: Int
    let layout: SwitcherLayout

    func body(content: Content) -> some View {
        let side = CGFloat(distance.signum())
        let offset = distance == 0 ? 0 : side * layout.itemWidth * 0.62 + CGFloat(distance) * layout.itemWidth * 0.34
        return content
            .scaleEffect(distance == 0 ? 1.15 : 0.86)
            .rotation3DEffect(.degrees(distance == 0 ? 0 : -side * 52), axis: (x: 0, y: 1, z: 0), perspective: 0.55)
            .offset(x: offset)
            .opacity(abs(distance) == SwitcherLayout.coverFlowVisibleNeighbours ? 0.45 : 1)
    }
}

/// How an item's radial menu opens.
enum RadialTrigger: Equatable {
    /// Resting the pointer on the item, or a right click.
    case hoverOrSecondaryClick
    /// Only a right click. In Cover Flow the pointer rests on the middle card while the user
    /// scrolls, so resting cannot mean "show actions" there.
    case secondaryClick
    /// Never, e.g. for Cover Flow's tilted side cards.
    case none
}

private struct SwitcherItemView: View {
    /// Long enough not to open while the pointer passes over items, short enough that the
    /// menu feels like a reaction to pointing at the item.
    private static let radialDelay: Duration = .milliseconds(150)
    /// Hover ends for a moment when the pointer crosses from the item onto a slice or the
    /// gap between slices; closing only after this grace period keeps the menu from flickering.
    private static let closeDelay: Duration = .milliseconds(120)

    let item: SwitcherItem
    let isSelected: Bool
    let layout: SwitcherLayout
    let radialTrigger: RadialTrigger
    let onChoose: () -> Void
    let onQuickAction: (SwitcherQuickAction) -> Void
    let onActiveChange: (Bool) -> Void
    let onRadialOpenChange: (Bool) -> Void

    @State private var isCardHovered = false
    @State private var isRingHovered = false
    @State private var isRadialOpen = false
    @State private var openTask: Task<Void, Never>?
    @State private var closeTask: Task<Void, Never>?

    var body: some View {
        card
            // Hover and clicks use the item's unscaled frame: hit-testing the scaled card
            // would end the hover as the card shrinks away from under the pointer.
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .onHover { isCardHovered = $0; updateRadial() }
            .onTapGesture(perform: onChoose)
            .overlay {
                if radialTrigger != .none {
                    SecondaryClickArea(action: openRadial)
                }
            }
            .overlay {
                RadialMenu(
                    isOpen: isRadialOpen,
                    outerRadius: layout.radialRadius,
                    onAction: onQuickAction,
                    onHoverChange: { isRingHovered = $0; updateRadial() }
                )
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: "\(item.title), \(item.applicationName)"))
            .accessibilityValue(item.isBackgrounded ? Text("Minimized or hidden") : Text(verbatim: ""))
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction { onChoose() }
            .accessibilityActions {
                ForEach(SwitcherQuickAction.allCases, id: \.self) { action in
                    Button(action.title) { onQuickAction(action) }
                }
            }
            .onChange(of: isRadialOpen) { _, isOpen in onRadialOpenChange(isOpen) }
            // A Cover Flow card that scrolls away from the middle loses its menu.
            .onChange(of: radialTrigger) { _, trigger in
                if trigger == .none, isRadialOpen {
                    withAnimation(.easeOut(duration: 0.16)) { isRadialOpen = false }
                }
            }
            .onDisappear {
                openTask?.cancel()
                closeTask?.cancel()
                if isRadialOpen { onRadialOpenChange(false) }
            }
    }

    private var card: some View {
        cardContent
            .frame(maxWidth: .infinity)
            .padding(8)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.32) : .clear)
            }
            .opacity(item.isBackgrounded ? 0.55 : 1)
            // Immediate feedback while the radial menu is about to open; recedes once it is open.
            .scaleEffect(isRadialOpen ? 0.9 : (isCardHovered ? 1.04 : 1))
            .animation(.spring(response: 0.3, dampingFraction: 0.75), value: isCardHovered)
            .animation(.spring(response: 0.3, dampingFraction: 0.75), value: isRadialOpen)
    }

    private var cardContent: some View {
        VStack(spacing: 6) {
            if layout.showsPreviews {
                preview
            } else {
                Image(nsImage: item.icon)
                    .resizable()
                    .frame(width: layout.iconSize, height: layout.iconSize)
            }
            Text(verbatim: item.title)
                .font(.callout)
                .lineLimit(layout.showsPreviews ? 1 : 2)
                .truncationMode(.middle)
                .multilineTextAlignment(.center)
            if !layout.showsPreviews {
                Text(verbatim: item.applicationName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private func openRadial() {
        guard radialTrigger != .none, !isRadialOpen else { return }
        openTask?.cancel()
        openTask = nil
        withAnimation(.spring(response: 0.36, dampingFraction: 0.7)) { isRadialOpen = true }
    }

    /// Opens the menu after a short rest on the item; closes it once the pointer has stayed
    /// off both the item and the ring for a moment.
    private func updateRadial() {
        let isActive = isCardHovered || isRingHovered
        if isActive {
            closeTask?.cancel()
            closeTask = nil
            onActiveChange(true)
            guard radialTrigger == .hoverOrSecondaryClick, !isRadialOpen, openTask == nil else { return }
            openTask = Task { @MainActor in
                try? await Task.sleep(for: Self.radialDelay)
                guard !Task.isCancelled else { return }
                withAnimation(.spring(response: 0.36, dampingFraction: 0.7)) { isRadialOpen = true }
                openTask = nil
            }
        } else {
            openTask?.cancel()
            openTask = nil
            guard closeTask == nil else { return }
            closeTask = Task { @MainActor in
                try? await Task.sleep(for: Self.closeDelay)
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.16)) { isRadialOpen = false }
                onActiveChange(false)
                closeTask = nil
            }
        }
    }

    /// Thumbnail with the app icon badged in the corner, or a large icon until it arrives.
    private var preview: some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let preview = item.preview {
                    Image(nsImage: preview)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .shadow(radius: 2, y: 1)
                } else {
                    Image(nsImage: item.icon)
                        .resizable()
                        .frame(width: layout.iconSize, height: layout.iconSize)
                }
            }
            .frame(width: layout.previewSize.width, height: layout.previewSize.height)

            if item.preview != nil {
                Image(nsImage: item.icon)
                    .resizable()
                    .frame(width: layout.iconSize / 2, height: layout.iconSize / 2)
                    .offset(x: -4, y: 4)
            }
        }
    }
}

/// The quick-action keys, wrapping onto more lines when the panel is narrow.
private struct HintBar: View {
    let hints: [SwitcherHint]

    var body: some View {
        FlowLayout(spacing: 14, lineSpacing: 6) {
            ForEach(hints) { hint in
                HStack(spacing: 4) {
                    Text(verbatim: hint.keys)
                        .fontWeight(.medium)
                    Text(verbatim: hint.title)
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
            }
        }
    }
}

/// Lays children out left to right, centered, starting a new line when one is full.
private struct FlowLayout: Layout {
    var spacing: CGFloat
    var lineSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let lines = lines(for: subviews, width: width)
        let height = lines.map(\.height).reduce(0, +) + lineSpacing * CGFloat(max(lines.count - 1, 0))
        return CGSize(width: proposal.width ?? lines.map(\.width).max() ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for line in lines(for: subviews, width: bounds.width) {
            var x = bounds.midX - line.width / 2
            for index in line.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y + (line.height - size.height) / 2), proposal: .unspecified)
                x += size.width + spacing
            }
            y += line.height + lineSpacing
        }
    }

    private struct Line {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func lines(for subviews: Subviews, width: CGFloat) -> [Line] {
        var lines: [Line] = []
        var current = Line()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if needed > width, !current.indices.isEmpty {
                lines.append(current)
                current = Line()
            }
            current.width = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }
        if !current.indices.isEmpty { lines.append(current) }
        return lines
    }
}
