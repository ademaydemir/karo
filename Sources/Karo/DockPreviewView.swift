import SwiftUI

struct DockPreviewItem: Identifiable {
    let id: Int
    let title: String
    let icon: NSImage
    var preview: NSImage?
    var isMinimized: Bool
}

/// Presentation state of the Dock preview, owned by `DockPreviewController`.
@MainActor
@Observable
final class DockPreviewModel {
    var applicationName = ""
    var items: [DockPreviewItem] = []
    /// Cards per row, so the panel fits on the display.
    var columns = 1
    @ObservationIgnored var onChoose: (Int) -> Void = { _ in }
    @ObservationIgnored var onMinimize: (Int) -> Void = { _ in }
    @ObservationIgnored var onClose: (Int) -> Void = { _ in }
}

/// Fixed metrics, so the controller can size the panel from the number of cards alone
/// instead of measuring SwiftUI, which would lag one update behind a change.
enum DockPreviewLayout {
    static let cardWidth: CGFloat = 200
    static let previewHeight: CGFloat = 118
    static let titleHeight: CGFloat = 16
    static let cardPadding: CGFloat = 8
    static let spacing: CGFloat = 10
    static let padding: CGFloat = 14
    static let headerHeight: CGFloat = 18

    static var cardHeight: CGFloat { cardPadding * 2 + previewHeight + 6 + titleHeight }

    static func columns(fittingWidth width: CGFloat) -> Int {
        max(1, Int((width - padding * 2 + spacing) / (cardWidth + spacing)))
    }

    static func size(count: Int, columns: Int) -> CGSize {
        let shownColumns = min(count, columns)
        let rows = (count + columns - 1) / columns
        return CGSize(
            width: padding * 2 + CGFloat(shownColumns) * cardWidth + CGFloat(max(shownColumns - 1, 0)) * spacing,
            height: padding * 2 + headerHeight + spacing + CGFloat(rows) * cardHeight + CGFloat(max(rows - 1, 0)) * spacing
        )
    }
}

/// The windows of the app whose Dock icon is under the pointer.
struct DockPreviewView: View {
    let model: DockPreviewModel

    var body: some View {
        VStack(alignment: .leading, spacing: DockPreviewLayout.spacing) {
            Text(verbatim: model.applicationName)
                .font(.headline)
                .lineLimit(1)
                .padding(.horizontal, DockPreviewLayout.cardPadding)
                .frame(height: DockPreviewLayout.headerHeight)
            VStack(alignment: .leading, spacing: DockPreviewLayout.spacing) {
                ForEach(rows, id: \.first?.id) { row in
                    HStack(spacing: DockPreviewLayout.spacing) {
                        ForEach(row) { item in
                            DockPreviewCard(
                                item: item,
                                onChoose: { model.onChoose(item.id) },
                                onMinimize: { model.onMinimize(item.id) },
                                onClose: { model.onClose(item.id) }
                            )
                        }
                    }
                }
            }
        }
        .padding(DockPreviewLayout.padding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var rows: [[DockPreviewItem]] {
        stride(from: 0, to: model.items.count, by: model.columns).map {
            Array(model.items[$0..<min($0 + model.columns, model.items.count)])
        }
    }
}

private struct DockPreviewCard: View {
    let item: DockPreviewItem
    let onChoose: () -> Void
    let onMinimize: () -> Void
    let onClose: () -> Void

    @State private var isHovered = false

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.quaternary.opacity(0.5))
                if let preview = item.preview {
                    Image(nsImage: preview)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .padding(4)
                } else {
                    // Without Screen Recording permission there is no thumbnail.
                    Image(nsImage: item.icon)
                        .resizable()
                        .frame(width: 48, height: 48)
                }
            }
            .frame(height: DockPreviewLayout.previewHeight)
            .opacity(item.isMinimized ? 0.5 : 1)

            HStack(spacing: 4) {
                if item.isMinimized {
                    Image(systemName: "minus.circle")
                        .foregroundStyle(.secondary)
                }
                Text(verbatim: item.title)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(height: DockPreviewLayout.titleHeight)
        }
        .padding(DockPreviewLayout.cardPadding)
        .frame(width: DockPreviewLayout.cardWidth, height: DockPreviewLayout.cardHeight)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isHovered ? Color.primary.opacity(0.12) : .clear)
        )
        .overlay(alignment: .topTrailing) {
            if isHovered {
                HStack(spacing: 4) {
                    if !item.isMinimized {
                        CardButton(symbol: "minus", title: String(localized: "Minimize"), action: onMinimize)
                    }
                    CardButton(symbol: "xmark", title: String(localized: "Close", comment: "Close the window"), action: onClose)
                }
                .padding(12)
                .transition(.opacity)
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { isHovered = hovering }
        }
        .onTapGesture(perform: onChoose)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: item.title))
        .accessibilityValue(item.isMinimized ? Text("Minimized or hidden") : Text(verbatim: ""))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: Text("Minimize"), onMinimize)
        .accessibilityAction(named: Text("Close", comment: "Close the window"), onClose)
    }
}

private struct CardButton: View {
    let symbol: String
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
                .frame(width: 20, height: 20)
                .background(.regularMaterial, in: Circle())
                .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(Text(verbatim: title))
    }
}
