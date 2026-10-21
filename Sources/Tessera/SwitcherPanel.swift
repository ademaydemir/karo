import AppKit
import SwiftUI

struct SwitcherItem: Identifiable {
    let id: Int
    let title: String
    let applicationName: String
    let icon: NSImage
    /// Minimized, or its app is hidden.
    let isBackgrounded: Bool
}

/// Presentation state of the switcher, owned by `WindowSwitcher`.
@MainActor
@Observable
final class SwitcherModel {
    var items: [SwitcherItem] = []
    var selectedIndex = 0
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

        let background = NSVisualEffectView()
        background.material = .hudWindow
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 16
        background.layer?.masksToBounds = true

        hostingView = NSHostingView(rootView: SwitcherView(model: model))
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: background.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: background.bottomAnchor),
        ])
        panel.contentView = background
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
    private static let maximumColumns = 8
    private static let itemWidth: CGFloat = 120

    let model: SwitcherModel

    var body: some View {
        let columns = Array(
            repeating: GridItem(.fixed(Self.itemWidth), spacing: 8),
            count: max(1, min(model.items.count, Self.maximumColumns))
        )
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(model.items) { item in
                SwitcherItemView(item: item, isSelected: item.id == model.selectedIndex)
                    .onHover { isHovering in
                        if isHovering { model.onHover(item.id) }
                    }
                    .onTapGesture { model.onChoose(item.id) }
            }
        }
        .padding(16)
        .fixedSize()
    }
}

private struct SwitcherItemView: View {
    let item: SwitcherItem
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 6) {
            Image(nsImage: item.icon)
                .resizable()
                .frame(width: 64, height: 64)
            Text(item.title)
                .font(.callout)
                .lineLimit(2)
                .multilineTextAlignment(.center)
            Text(item.applicationName)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(8)
        .background {
            RoundedRectangle(cornerRadius: 10)
                .fill(isSelected ? Color.accentColor.opacity(0.35) : .clear)
        }
        .opacity(item.isBackgrounded ? 0.55 : 1)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(item.title), \(item.applicationName)")
        .accessibilityValue(item.isBackgrounded ? "Minimized or hidden" : "")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
