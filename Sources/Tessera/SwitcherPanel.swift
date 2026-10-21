import AppKit
import SwiftUI

struct SwitcherItem: Identifiable {
    let id: Int
    let title: String
    let applicationName: String
    let icon: NSImage
    /// Minimized, or its app is hidden.
    let isBackgrounded: Bool
    var preview: NSImage?
}

/// Presentation state of the switcher, owned by `WindowSwitcher`.
@MainActor
@Observable
final class SwitcherModel {
    var items: [SwitcherItem] = []
    var selectedIndex = 0
    var showsPreviews = false
    @ObservationIgnored var onHover: (Int) -> Void = { _ in }
    @ObservationIgnored var onChoose: (Int) -> Void = { _ in }
}

/// The floating panel listing windows while ⌥ is held.
///
/// It never becomes key or active, so the frontmost app keeps focus and keyboard input
/// until a window is chosen.
@MainActor
final class SwitcherPanel {
    let model = SwitcherModel()
    private let panel: NSPanel
    private let hostingView: NSHostingView<SwitcherView>

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

        hostingView = NSHostingView(rootView: SwitcherView(model: model))
        panel.contentView = GlassSurface.make(cornerRadius: 24, content: hostingView)
    }

    /// Shows the panel centered on the display under the cursor.
    func show() {
        let size = hostingView.fittingSize
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? .zero
        let origin = CGPoint(x: (visible.midX - size.width / 2).rounded(), y: (visible.midY - size.height / 2).rounded())
        panel.setFrame(CGRect(origin: origin, size: size), display: true)
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }
}

struct SwitcherView: View {
    let model: SwitcherModel

    var body: some View {
        let layout = SwitcherLayout(showsPreviews: model.showsPreviews)
        let columns = Array(
            repeating: GridItem(.fixed(layout.itemWidth), spacing: layout.spacing),
            count: max(1, min(model.items.count, layout.maximumColumns))
        )
        LazyVGrid(columns: columns, spacing: layout.spacing) {
            ForEach(model.items) { item in
                SwitcherItemView(item: item, isSelected: item.id == model.selectedIndex, layout: layout)
                    .onHover { isHovering in
                        if isHovering { model.onHover(item.id) }
                    }
                    .onTapGesture { model.onChoose(item.id) }
            }
        }
        .padding(layout.spacing * 2)
        .fixedSize()
    }
}

/// Item metrics for the two switcher styles.
private struct SwitcherLayout {
    let showsPreviews: Bool

    var itemWidth: CGFloat { showsPreviews ? 208 : 112 }
    var maximumColumns: Int { showsPreviews ? 5 : 8 }
    var spacing: CGFloat { 8 }
    /// 16:10 matches typical window proportions; previews are aspect-fit inside it.
    var previewSize: CGSize { CGSize(width: itemWidth - 16, height: (itemWidth - 16) * 10 / 16) }
}

private struct SwitcherItemView: View {
    let item: SwitcherItem
    let isSelected: Bool
    let layout: SwitcherLayout

    var body: some View {
        VStack(spacing: 6) {
            if layout.showsPreviews {
                preview
            } else {
                Image(nsImage: item.icon)
                    .resizable()
                    .frame(width: 64, height: 64)
            }
            Text(item.title)
                .font(.callout)
                .lineLimit(layout.showsPreviews ? 1 : 2)
                .truncationMode(.middle)
                .multilineTextAlignment(.center)
            if !layout.showsPreviews {
                Text(item.applicationName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(8)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.32) : .clear)
        }
        .opacity(item.isBackgrounded ? 0.55 : 1)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(item.title), \(item.applicationName)"))
        .accessibilityValue(item.isBackgrounded ? Text("Minimized or hidden") : Text(verbatim: ""))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
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
                        .frame(width: 64, height: 64)
                }
            }
            .frame(width: layout.previewSize.width, height: layout.previewSize.height)

            if item.preview != nil {
                Image(nsImage: item.icon)
                    .resizable()
                    .frame(width: 32, height: 32)
                    .offset(x: -4, y: 4)
            }
        }
    }
}
