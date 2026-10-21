import AppKit
import SwiftUI
import TesseraCore

struct SwitcherItem: Identifiable {
    /// Stable for the session, so previews still find their item after others are removed.
    let id: Int
    let title: String
    let applicationName: String
    let icon: NSImage
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
    var maximumColumns = 6
    var hints: [SwitcherHint] = []
    @ObservationIgnored var onHover: (Int) -> Void = { _ in }
    @ObservationIgnored var onChoose: (Int) -> Void = { _ in }
    @ObservationIgnored var onQuickAction: (Int, SwitcherQuickAction) -> Void = { _, _ in }

    var layout: SwitcherLayout {
        SwitcherLayout(size: size, showsPreviews: showsPreviews)
    }
}

/// The floating panel listing windows while ⌥ is held.
///
/// It never becomes key or active, so the frontmost app keeps focus and keyboard input
/// until a window is chosen.
@MainActor
final class SwitcherPanel {
    let model = SwitcherModel()
    private let panel: NSPanel
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

        hostingView = FirstMouseHostingView(rootView: SwitcherView(model: model))
        panel.contentView = GlassSurface.make(cornerRadius: 28, content: hostingView)
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
        model.maximumColumns = model.layout.columns(fitting: visible.width * 0.9)

        let size = hostingView.fittingSize
        let origin = CGPoint(x: (visible.midX - size.width / 2).rounded(), y: (visible.midY - size.height / 2).rounded())
        panel.setFrame(CGRect(origin: origin, size: size), display: true)
    }
}

/// The panel never becomes key, so without this the first click on an item or a quick
/// action button would be swallowed.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
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

    /// 16:10 matches typical window proportions; previews are aspect-fit inside it.
    var previewSize: CGSize { CGSize(width: itemWidth - 16, height: (itemWidth - 16) * 10 / 16) }
    /// How far the floating buttons reach beyond an item. Each item's hover area includes
    /// this margin, so the buttons stay up while the pointer travels to them; the margins of
    /// neighbouring items also form the gap between them.
    var overhang: CGFloat { 22 }
    var padding: CGFloat { 14 }
    var cellWidth: CGFloat { itemWidth + overhang * 2 }

    func columns(fitting width: CGFloat) -> Int {
        max(1, Int((width - padding * 2) / cellWidth))
    }

    /// Width of the visible items in a row, without the outer hover margins.
    func contentWidth(columns: Int) -> CGFloat {
        CGFloat(columns) * cellWidth - overhang * 2
    }
}

struct SwitcherView: View {
    let model: SwitcherModel
    @State private var hoveredID: Int?

    var body: some View {
        let layout = model.layout
        let columnCount = max(1, min(model.items.count, model.maximumColumns))
        let columns = Array(repeating: GridItem(.fixed(layout.cellWidth), spacing: 0), count: columnCount)

        VStack(spacing: 4) {
            LazyVGrid(columns: columns, spacing: 0) {
                ForEach(Array(model.items.enumerated()), id: \.element.id) { index, item in
                    SwitcherItemView(
                        item: item,
                        isSelected: index == model.selectedIndex,
                        isHovered: hoveredID == item.id,
                        layout: layout,
                        onChoose: { model.onChoose(index) },
                        onQuickAction: { model.onQuickAction(index, $0) }
                    )
                    .zIndex(hoveredID == item.id ? 1 : 0)
                    .onHover { isHovering in
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.72)) {
                            if isHovering {
                                hoveredID = item.id
                            } else if hoveredID == item.id {
                                hoveredID = nil
                            }
                        }
                        if isHovering { model.onHover(index) }
                    }
                }
            }

            HintBar(hints: model.hints)
                .frame(width: layout.contentWidth(columns: columnCount))
                .padding(.bottom, layout.overhang)
        }
        .padding(layout.padding)
        .fixedSize()
    }
}

private struct SwitcherItemView: View {
    let item: SwitcherItem
    let isSelected: Bool
    let isHovered: Bool
    let layout: SwitcherLayout
    let onChoose: () -> Void
    let onQuickAction: (SwitcherQuickAction) -> Void

    var body: some View {
        card
            .overlay { floatingActions }
            // Transparent margin the buttons float into; part of the hover area, not clickable.
            .padding(layout.overhang)
            .contentShape(Rectangle())
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
    }

    private var card: some View {
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
        .frame(maxWidth: .infinity)
        .padding(8)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.32) : .clear)
        }
        .opacity(item.isBackgrounded ? 0.55 : 1)
        .scaleEffect(isHovered ? 1.03 : 1)
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onTapGesture(perform: onChoose)
    }

    /// Buttons that float out around the hovered item, overhanging its edges, so they never
    /// cover the preview. Each group is inserted on its own so it gets its own spring, and
    /// they follow each other by a few milliseconds.
    private var floatingActions: some View {
        ZStack {
            if isHovered {
                QuickActionGroup(actions: SwitcherQuickAction.windowControls, onAction: onQuickAction)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .offset(x: -12, y: -12)
                    .transition(Self.popTransition(delay: 0))
            }
            if isHovered {
                QuickActionGroup(actions: SwitcherQuickAction.applicationControls, onAction: onQuickAction)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .offset(x: 12, y: -12)
                    .transition(Self.popTransition(delay: 0.04))
            }
            if isHovered {
                QuickActionGroup(actions: SwitcherQuickAction.placements, onAction: onQuickAction)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    // Mostly below the card so the bar does not cover the window title.
                    .offset(y: 20)
                    .transition(Self.popTransition(delay: 0.08))
            }
        }
    }

    private static func popTransition(delay: Double) -> AnyTransition {
        .scale(scale: 0.4).combined(with: .opacity)
            .animation(.spring(response: 0.34, dampingFraction: 0.66).delay(delay))
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

/// A row of round floating buttons: Liquid Glass on macOS 26 and later, material before.
private struct QuickActionGroup: View {
    let actions: [SwitcherQuickAction]
    let onAction: (SwitcherQuickAction) -> Void

    var body: some View {
        if #available(macOS 26.0, *) {
            // A shared container lets neighbouring glass buttons blend into one shape.
            GlassEffectContainer(spacing: 6) {
                buttons { $0.glassEffect(.regular.interactive(), in: .circle) }
            }
        } else {
            buttons { $0.background(.regularMaterial, in: Circle()).overlay(Circle().strokeBorder(.separator)) }
        }
    }

    private func buttons(@ViewBuilder style: @escaping (AnyView) -> some View) -> some View {
        HStack(spacing: 6) {
            ForEach(actions, id: \.self) { action in
                Button { onAction(action) } label: {
                    style(AnyView(
                        Image(systemName: action.symbolName)
                            .font(.system(size: 12, weight: .semibold))
                            .frame(width: 28, height: 28)
                            .contentShape(Circle())
                    ))
                }
                .buttonStyle(.plain)
                .help(Text(verbatim: "\(action.title) (\(action.shortcut.displayString))"))
                .accessibilityLabel(Text(verbatim: action.title))
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
