import SwiftUI
import KaroCore

/// A ring of quick actions around a switcher item, opened by resting the pointer on it.
///
/// Every slice is the same distance from the center, which makes them quick to hit. Only
/// the slices take the pointer: the center lets it through to the item underneath, so
/// clicking there still switches to the window and the item keeps its hover.
struct RadialMenu: View {
    /// The menu stays in the view tree while closed, so opening inserts each slice on its
    /// own and each gets its own staggered transition.
    let isOpen: Bool
    let outerRadius: CGFloat
    var modifier: SwitcherModifier = .option
    var actions: [SwitcherQuickAction] = SwitcherQuickAction.radialOrder
    let onAction: (SwitcherQuickAction) -> Void
    /// Whether the pointer is over any slice.
    let onHoverChange: (Bool) -> Void

    @State private var hoveredAction: SwitcherQuickAction?

    private var innerRadius: CGFloat { outerRadius * 0.46 }

    var body: some View {
        ZStack {
            backdrop
            slices
            hitLayer
            center
        }
        .frame(width: outerRadius * 2, height: outerRadius * 2)
        // Closed, it must not catch the pointer over neighbouring items.
        .allowsHitTesting(isOpen)
        .onChange(of: hoveredAction) { _, action in onHoverChange(action != nil) }
    }

    /// The one view that takes the pointer. The slices are drawn but never hit-tested: with
    /// interactive glass in a container their hit areas stop being their own sector, and the
    /// topmost slice caught hover and taps across the whole ring. The slice is decided by
    /// angle instead. The ring shape leaves the center open, so the pointer still reaches the
    /// item underneath.
    @ViewBuilder
    private var hitLayer: some View {
        if isOpen {
            Color.clear
                .frame(width: outerRadius * 2, height: outerRadius * 2)
                .contentShape(RingShape(innerRatio: innerRadius / outerRadius), eoFill: true)
                .onContinuousHover(coordinateSpace: .local) { phase in
                    let hovered: SwitcherQuickAction?
                    switch phase {
                    case .active(let location): hovered = action(at: location)
                    case .ended: hovered = nil
                    }
                    guard hovered != hoveredAction else { return }
                    withAnimation(.easeOut(duration: 0.12)) { hoveredAction = hovered }
                }
                .gesture(SpatialTapGesture().onEnded { value in
                    if let action = action(at: value.location) { onAction(action) }
                })
        }
    }

    private func action(at location: CGPoint) -> SwitcherQuickAction? {
        RadialHitTest.index(
            of: location,
            center: CGPoint(x: outerRadius, y: outerRadius),
            innerRadius: innerRadius,
            outerRadius: outerRadius,
            count: actions.count
        ).map { actions[$0] }
    }

    /// A solid band behind the slices. Glass alone lets item titles and neighbouring items
    /// show through, which makes the labels hard to read. The center stays open, so the
    /// item itself remains visible inside the ring.
    @ViewBuilder
    private var backdrop: some View {
        if isOpen {
            Circle()
                .strokeBorder(.thickMaterial, lineWidth: outerRadius - innerRadius + 6)
                .padding(-3)
                .shadow(color: .black.opacity(0.18), radius: 8, y: 2)
                .allowsHitTesting(false)
                .transition(.scale(scale: 0.6).combined(with: .opacity).animation(.spring(response: 0.3, dampingFraction: 0.8)))
        }
    }

    @ViewBuilder
    private var slices: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: 4) {
                if isOpen {
                    ForEach(Array(actions.enumerated()), id: \.element) { index, action in
                        slice(action, index: index)
                            .background { shape(for: index).fill(color(for: action) ?? .clear) }
                            .glassEffect(.regular.interactive(), in: shape(for: index))
                            .transition(Self.transition(index: index))
                    }
                }
            }
        } else if isOpen {
            ForEach(Array(actions.enumerated()), id: \.element) { index, action in
                slice(action, index: index)
                    .background {
                        if let color = color(for: action) {
                            shape(for: index).fill(color)
                        } else {
                            shape(for: index).fill(.regularMaterial)
                        }
                    }
                    .overlay { shape(for: index).stroke(.separator, lineWidth: 0.5) }
                    .transition(Self.transition(index: index))
            }
        }
    }

    private static func transition(index: Int) -> AnyTransition {
        .radialAppear.animation(.spring(response: 0.36, dampingFraction: 0.68).delay(Double(index) * 0.018))
    }

    /// The slice's color, drawn as its own layer between the glass and the label. A glass
    /// tint alone is too faint to read, especially over the ring's backdrop.
    private func color(for action: SwitcherQuickAction) -> Color? {
        if hoveredAction == action { return action.tint.opacity(0.85) }
        return action.restingTint
    }

    private func shape(for index: Int) -> AnnularSector {
        let slice = 360.0 / Double(actions.count)
        // Index 0 is centered on the top; angles are measured clockwise from 3 o'clock.
        let middle = Double(index) * slice - 90
        return AnnularSector(
            startAngle: .degrees(middle - slice / 2),
            endAngle: .degrees(middle + slice / 2),
            innerRatio: innerRadius / outerRadius,
            gap: 3
        )
    }

    private func slice(_ action: SwitcherQuickAction, index: Int) -> some View {
        let isHovered = hoveredAction == action
        let angle = (Double(index) * 360.0 / Double(actions.count) - 90) * .pi / 180
        let labelRadius = (innerRadius + outerRadius) / 2
        return VStack(spacing: 2) {
            Image(systemName: action.symbolName)
                .font(.system(size: 14, weight: .semibold))
            Text(verbatim: action.shortTitle)
                .font(.caption2)
                .lineLimit(1)
        }
        .foregroundStyle(isHovered ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
        .offset(x: cos(angle) * labelRadius, y: sin(angle) * labelRadius)
        .frame(width: outerRadius * 2, height: outerRadius * 2)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: action.title))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onAction(action) }
    }

    /// Names the slice under the pointer.
    private var center: some View {
        ZStack {
            if isOpen, let hoveredAction {
                Text(verbatim: hoveredAction.title)
                    .font(.caption.weight(.medium))
                    .multilineTextAlignment(.center)
                    .padding(6)
                    .background(.regularMaterial, in: Capsule())
                    .transition(.opacity)
            }
        }
        .frame(width: innerRadius * 2 - 8, height: innerRadius * 2 - 8)
        .allowsHitTesting(false)
    }
}

/// The whole ring, for hit-testing: the outer circle with the inner one cut out when filled
/// even-odd.
private struct RingShape: Shape {
    /// Inner radius as a fraction of the outer one.
    var innerRatio: CGFloat

    func path(in rect: CGRect) -> Path {
        let outer = min(rect.width, rect.height) / 2
        let inner = outer * innerRatio
        let center = CGPoint(x: rect.midX, y: rect.midY)
        var path = Path()
        path.addEllipse(in: CGRect(x: center.x - outer, y: center.y - outer, width: outer * 2, height: outer * 2))
        path.addEllipse(in: CGRect(x: center.x - inner, y: center.y - inner, width: inner * 2, height: inner * 2))
        return path
    }
}

/// One slice of a ring.
struct AnnularSector: Shape {
    var startAngle: Angle
    var endAngle: Angle
    /// Inner radius as a fraction of the outer one.
    var innerRatio: CGFloat
    /// Space between neighbouring slices, in points.
    var gap: CGFloat

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) / 2
        let inner = outer * innerRatio
        // The same gap in points is a larger angle on the inner edge.
        let outerInset = Angle.radians(Double(gap / 2 / outer))
        let innerInset = Angle.radians(Double(gap / 2 / max(inner, 1)))

        var path = Path()
        path.addArc(center: center, radius: outer, startAngle: startAngle + outerInset, endAngle: endAngle - outerInset, clockwise: false)
        path.addArc(center: center, radius: inner, startAngle: endAngle - innerInset, endAngle: startAngle + innerInset, clockwise: true)
        path.closeSubpath()
        return path
    }
}

private struct RadialAppear: ViewModifier {
    let progress: CGFloat

    func body(content: Content) -> some View {
        content
            .scaleEffect(0.35 + 0.65 * progress)
            .rotationEffect(.degrees(-28 * (1 - progress)))
            .opacity(progress)
    }
}

extension SwitcherQuickAction {
    /// Close, minimize and maximize borrow the colors of a window's own buttons, so they
    /// read as familiar at a glance.
    var tint: Color {
        switch self {
        case .close, .quitApplication: .red
        // Orange rather than the traffic light's yellow, which is too light for white labels.
        case .minimize: .orange
        case .maximize: .green
        case .leftHalf, .rightHalf: .blue
        case .nextDisplay: .teal
        case .hideApplication: .gray
        }
    }

    /// Quitting closes every window of the app, so it stays faintly red even at rest.
    var restingTint: Color? {
        self == .quitApplication ? .red.opacity(0.25) : nil
    }
}

extension AnyTransition {
    /// Slices fan out from the center with a slight twist.
    static var radialAppear: AnyTransition {
        .modifier(active: RadialAppear(progress: 0), identity: RadialAppear(progress: 1))
    }
}
