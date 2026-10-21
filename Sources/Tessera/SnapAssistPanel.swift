import AppKit
import SwiftUI

/// Presentation state of Snap Assist, owned by `SnapAssistController`.
@MainActor
@Observable
final class SnapAssistModel {
    var items: [SwitcherItem] = []
    var showsPreviews = false
    /// While the hovered window is shown live in this region, the panel's glass steps aside
    /// so the window itself is visible behind the cards.
    var isShowingLivePreview = false
    /// Receives the chosen item's ID.
    @ObservationIgnored var onChoose: (Int) -> Void = { _ in }
    /// Receives the hovered item's ID, or `nil` when the pointer leaves the cards.
    @ObservationIgnored var onHover: (Int?) -> Void = { _ in }
}

/// Fills the free side of the display after a snap and offers the other windows for it.
@MainActor
final class SnapAssistPanel {
    let model = SnapAssistModel()
    private let panel: NSPanel
    private let background: NSView

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
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle, .fullScreenAuxiliary]

        // The glass and the cards are siblings, so the glass can fade out on its own during
        // a live preview while the cards stay.
        let container = NSView()
        background = GlassSurface.make(cornerRadius: 24)
        background.autoresizingMask = [.width, .height]
        container.addSubview(background)
        let hostingView = FirstMouseHostingView(rootView: SnapAssistView(model: model))
        hostingView.autoresizingMask = [.width, .height]
        container.addSubview(hostingView)
        panel.contentView = container
    }

    /// Fades the glass in to cover the region, or out to reveal the window behind it.
    /// Returns when the fade has finished, so window moves can happen behind full cover.
    func setGlassVisible(_ isVisible: Bool, duration: TimeInterval) async {
        model.isShowingLivePreview = !isVisible
        await withCheckedContinuation { continuation in
            NSAnimationContext.runAnimationGroup { context in
                context.duration = duration
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                background.animator().alphaValue = isVisible ? 1 : 0
            } completionHandler: {
                continuation.resume()
            }
        }
    }

    /// - Parameter region: The free side of the display, in Accessibility coordinates.
    func show(in region: CGRect) {
        let frame = ScreenGeometry.appKitFrame(fromAccessibility: region).insetBy(dx: 12, dy: 12)
        panel.setFrame(frame, display: true)
        background.frame = CGRect(origin: .zero, size: frame.size)
        background.alphaValue = 1
        model.isShowingLivePreview = false
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            panel.animator().alphaValue = 1
        }
    }

    func hide() {
        panel.orderOut(nil)
    }
}

private struct SnapAssistView: View {
    private static let padding: CGFloat = 28
    private static let maximumCardWidth: CGFloat = 360

    let model: SnapAssistModel
    @State private var hoveredID: Int?

    var body: some View {
        GeometryReader { geometry in
            // One block of title and cards, centered in the region: it starts in the middle
            // and grows up and down as rows are added, scrolling only once it no longer fits.
            ScrollView {
                VStack(spacing: 20) {
                    VStack(spacing: 4) {
                        Text("Choose a window for this side")
                            .font(.title2.weight(.semibold))
                        Text("Press Esc or click elsewhere to skip.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background {
                        if model.isShowingLivePreview {
                            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.regularMaterial)
                        }
                    }
                    fans(in: geometry.size)
                }
                .padding(Self.padding)
                .frame(width: geometry.size.width)
                .frame(minHeight: geometry.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    // MARK: Fan

    /// Up to this many windows are dealt as a single fanned hand of cards.
    private static let maximumSingleRowCount = 6
    /// With more windows, each row is its own hand of at most this many cards.
    private static let cardsPerRow = 5
    /// Horizontal distance between neighbouring cards in a hand, as a share of card width.
    private static let fanOverlap: CGFloat = 0.62
    /// How far the hovered card lifts out of the hand. Kept small: a card that moves far
    /// away from under the pointer loses its hover, drops back and flickers.
    private static let fanLift: CGFloat = 16
    private static let rowSpacing: CGFloat = 12

    /// The windows as hands of cards, one per row: all visible, overlapping along a gentle arc.
    /// Every row uses the same card size, so the rows line up; a short last row is centered.
    private func fans(in size: CGSize) -> some View {
        let count = model.items.count
        let perRow = count <= Self.maximumSingleRowCount ? count : Self.cardsPerRow
        let rows = stride(from: 0, to: count, by: perRow).map { Array($0..<min($0 + perRow, count)) }
        let available = size.width - Self.padding * 2
        let width = min(Self.maximumCardWidth, max(180, available / (1 + Self.fanOverlap * CGFloat(perRow - 1))))
        let cardHeight = (width - 24) * 10 / 16 + 76
        let hoveredRow = rows.firstIndex { row in row.contains { model.items[$0].id == hoveredID } }

        return VStack(spacing: Self.rowSpacing) {
            ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                fan(row, width: width, cardHeight: cardHeight)
                    // The hovered card's row draws over its neighbours as the card lifts.
                    .zIndex(hoveredRow == rowIndex ? 1 : 0)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .animation(.spring(response: 0.34, dampingFraction: 0.72), value: hoveredID)
    }

    /// One hand of cards. The hovered card straightens and lifts out of it.
    private func fan(_ indices: [Int], width: CGFloat, cardHeight: CGFloat) -> some View {
        let count = indices.count
        return ZStack {
            ForEach(Array(indices.enumerated()), id: \.element) { position, index in
                let item = model.items[index]
                let centered = CGFloat(position) - CGFloat(count - 1) / 2
                let isHovered = hoveredID == item.id
                card(for: item, width: width)
                    .rotationEffect(.degrees(isHovered ? 0 : Double(centered) * 6), anchor: .bottom)
                    .offset(
                        x: centered * width * Self.fanOverlap,
                        y: isHovered ? -Self.fanLift : abs(centered) * abs(centered) * 4
                    )
                    // Hovered on top; otherwise the middle cards above the outer ones.
                    .zIndex(isHovered ? 100 : Double(count) - abs(Double(centered)))
            }
        }
        .frame(height: cardHeight + Self.fanLift * 2)
        .frame(maxWidth: .infinity)
    }

    private func card(for item: SwitcherItem, width: CGFloat) -> some View {
        SnapAssistCard(
            item: item,
            showsPreview: model.showsPreviews,
            width: width,
            isHovered: hoveredID == item.id,
            onHover: { isHovering in
                withAnimation(.easeInOut(duration: 0.22)) {
                    if isHovering {
                        hoveredID = item.id
                    } else if hoveredID == item.id {
                        hoveredID = nil
                    }
                }
                model.onHover(hoveredID)
            },
            onChoose: { model.onChoose(item.id) }
        )
    }
}

private struct SnapAssistCard: View {
    let item: SwitcherItem
    let showsPreview: Bool
    let width: CGFloat
    let isHovered: Bool
    let onHover: (Bool) -> Void
    let onChoose: () -> Void

    private var previewHeight: CGFloat { (width - 24) * 10 / 16 }

    var body: some View {
        Button(action: onChoose) {
            VStack(alignment: .leading, spacing: 10) {
                ZStack(alignment: .bottomLeading) {
                    Group {
                        if showsPreview, let preview = item.preview {
                            Image(nsImage: preview)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
                        } else {
                            Image(nsImage: item.icon)
                                .resizable()
                                .frame(width: 72, height: 72)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    if showsPreview, item.preview != nil {
                        Image(nsImage: item.icon)
                            .resizable()
                            .frame(width: 36, height: 36)
                            .offset(x: -6, y: 6)
                    }
                }
                .frame(height: previewHeight)

                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: item.title)
                        .font(.headline)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(verbatim: item.applicationName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(12)
            .frame(width: width)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.regularMaterial)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(isHovered ? Color.accentColor : Color.primary.opacity(0.08), lineWidth: isHovered ? 2.5 : 1)
            }
            .scaleEffect(isHovered ? 1.03 : 1)
            .shadow(color: .black.opacity(isHovered ? 0.25 : 0.1), radius: isHovered ? 14 : 6, y: isHovered ? 6 : 2)
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover(perform: onHover)
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: isHovered)
        .accessibilityLabel(Text(verbatim: "\(item.title), \(item.applicationName)"))
    }
}
