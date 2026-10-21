import SwiftUI
import KaroCore

/// A small looping animation in Settings that shows how the chosen switcher style behaves.
/// Drawn rather than a recorded GIF, so it stays sharp, follows light and dark mode, and
/// holds still when Reduce Motion is on.
struct SwitcherStylePreview: View {
    let style: SwitcherStyle

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var step = 0

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                switch style {
                case .grid: GridPreview(step: step)
                case .coverFlow: CoverFlowPreview(step: step)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 96)
            // The description lives with the picture instead of beside the picker, where a
            // long text would be squeezed into a narrow column.
            caption
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 12)
                .id(style)
                .transition(.opacity)
        }
        .padding(.vertical, 12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .animation(.spring(response: 0.45, dampingFraction: 0.78), value: step)
        .animation(.easeInOut(duration: 0.25), value: style)
        .task(id: style) {
            step = 0
            guard !reduceMotion else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1.1))
                step += 1
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Preview of the selected style"))
        .accessibilityValue(caption)
    }

    private var caption: Text {
        switch style {
        case .grid: Text("All windows at once; an app’s windows share one deck.")
        case .coverFlow: Text("One large window at a time; swipe sideways on a Magic Mouse or trackpad.")
        }
    }
}

/// A stand-in window: a tinted card with a generic symbol, not any real app.
private struct PreviewCard: View {
    let index: Int

    private static let symbols = ["safari", "terminal", "envelope", "doc.text", "message", "music.note", "photo"]
    private static let tints: [Color] = [.blue, .gray, .indigo, .orange, .green, .pink, .teal]

    var body: some View {
        let tint = Self.tints[index % Self.tints.count]
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(tint.opacity(0.22))
            .overlay(alignment: .top) {
                // A title bar, to read as a window at a glance.
                RoundedRectangle(cornerRadius: 2).fill(tint.opacity(0.35)).frame(height: 5).padding(5)
            }
            .overlay {
                Image(systemName: Self.symbols[index % Self.symbols.count])
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(tint)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(tint.opacity(0.4), lineWidth: 0.5)
            }
            .frame(width: 58, height: 40)
    }
}

/// The grid: one app's three windows stacked into a deck, then single windows. The selection
/// walks across them, and the deck fans out within its own cell while it is selected.
private struct GridPreview: View {
    let step: Int

    /// The deck counts as one stop.
    private static let stops = 3
    /// Room for the fanned-out deck, so it never covers the cards next to it.
    private static let deckWidth: CGFloat = 104

    var body: some View {
        let selected = step % Self.stops
        HStack(spacing: 14) {
            deck(isSelected: selected == 0)
            ForEach(1..<Self.stops, id: \.self) { stop in
                PreviewCard(index: stop + 2)
                    .padding(4)
                    .background(selection(stop == selected))
            }
        }
    }

    private func deck(isSelected: Bool) -> some View {
        ZStack {
            // Back to front: the most recent window is on top.
            ForEach((0..<3).reversed(), id: \.self) { position in
                let centered = 1 - CGFloat(position)
                PreviewCard(index: 0)
                    // At rest a neat cascade, the windows behind fainter; selected, a small fan.
                    .offset(
                        x: isSelected ? centered * 22 : CGFloat(position) * 5,
                        y: isSelected ? abs(centered) * 2 : -CGFloat(position) * 5
                    )
                    .rotationEffect(.degrees(isSelected ? Double(centered) * 5 : 0))
                    .opacity(isSelected || position == 0 ? 1 : 1 - Double(position) * 0.25)
            }
        }
        .frame(width: Self.deckWidth)
        .padding(4)
        .background(selection(isSelected))
        .overlay(alignment: .topTrailing) {
            if !isSelected {
                Text(verbatim: "3")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .background(Color.accentColor, in: Capsule())
                    .offset(x: -14, y: -4)
            }
        }
    }

    private func selection(_ isSelected: Bool) -> some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(isSelected ? Color.accentColor.opacity(0.3) : .clear)
    }
}

/// Cover Flow: the selected card large in the middle, the others tilted away; the selection
/// swings back and forth like a swipe.
private struct CoverFlowPreview: View {
    let step: Int

    private static let count = 7
    /// Middle, right, further right, back, middle, left, further left, back.
    private static let path = [3, 4, 5, 4, 3, 2, 1, 2]

    var body: some View {
        let selected = Self.path[step % Self.path.count]
        ZStack {
            ForEach(0..<Self.count, id: \.self) { index in
                let distance = index - selected
                let side = CGFloat(distance.signum())
                PreviewCard(index: index)
                    .scaleEffect(distance == 0 ? 1.35 : 0.95)
                    .rotation3DEffect(.degrees(distance == 0 ? 0 : -Double(side) * 55), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
                    .offset(x: distance == 0 ? 0 : side * 44 + CGFloat(distance) * 20)
                    .zIndex(Double(10 - abs(distance)))
                    .opacity(abs(distance) > 3 ? 0 : 1)
                    .overlay {
                        if distance == 0 {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(Color.accentColor, lineWidth: 2)
                                .frame(width: 84, height: 60)
                        }
                    }
            }
        }
    }
}
