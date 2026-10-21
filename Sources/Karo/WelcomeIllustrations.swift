import SwiftUI

/// Looping illustrations for the welcome window. Drawn rather than recorded, like
/// `SwitcherStylePreview`, so they stay sharp, follow light and dark mode and the accent
/// color, and never go out of date with the real UI. The windows are stand-ins, not real apps.

// MARK: - Desktop scene

/// A small desktop that acts out one feature. Each feature is a short sequence of phases;
/// the caller advances `phase` and SwiftUI animates between them.
struct DesktopScene: View {
    enum Feature: Int, CaseIterable {
        case snap, keyboard, switcher
    }

    /// Phases per feature, the last one a pause before the loop starts over.
    static let phaseCount = 6

    /// How long a phase stays on screen. The quick actions get longer, there is more to see.
    static func duration(of feature: Feature, phase: Int) -> Duration {
        feature == .switcher && phase == 4 ? .seconds(2) : .seconds(1)
    }

    let feature: Feature
    let phase: Int

    /// On-screen size of one scene point.
    static let displayScale: CGFloat = 1.6
    /// The scene's on-screen width.
    static var displayWidth: CGFloat { size.width * displayScale }

    private nonisolated static let size = CGSize(width: 400, height: 170)
    private nonisolated static let menuBarHeight: CGFloat = 10
    private nonisolated static let inset: CGFloat = 4

    var body: some View {
        let layout = Layout(feature: feature, phase: phase)
        ZStack(alignment: .topLeading) {
            wallpaper

            if let preview = layout.snapPreview {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(.tint.opacity(0.22))
                    .strokeBorder(.tint.opacity(0.7), lineWidth: 1)
                    .placed(in: preview)
                    .transition(.opacity)
                    .zIndex(1)
            }

            ForEach(SceneWindow.Kind.allCases, id: \.self) { kind in
                if let frame = layout.frames[kind] {
                    SceneWindow(kind: kind)
                        .placed(in: frame)
                        .zIndex(2 + Double(layout.order.firstIndex(of: kind) ?? 0))
                        .transition(.opacity)
                }
            }

            if let assist = layout.snapAssist {
                MiniPicker(kinds: [.document, .messages], selected: layout.pickerSelection)
                    .placed(in: assist)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    .zIndex(10)
            }

            if let switcher = layout.switcher {
                Group {
                    switch switcher {
                    case .apps:
                        AppSwitcherBar(apps: [.browser, .document, .messages])
                            .placed(in: CGRect(x: 125, y: 58, width: 150, height: 50))
                    case .windows(let isFanned, let showsActions):
                        WindowSwitcherPanel(isFanned: isFanned, showsActions: showsActions)
                            .placed(in: CGRect(x: 80, y: 46, width: 240, height: 78))
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.92)))
                .zIndex(10)
            }

            if let label = layout.label {
                Text(label)
                    .font(.system(size: 10, weight: .semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.regularMaterial, in: Capsule())
                    .frame(width: Self.size.width)
                    .offset(y: Self.menuBarHeight + 8)
                    .id(label.key)
                    .transition(.opacity)
                    .zIndex(11)
            }

            if let keys = layout.keys {
                KeyCaps(keys: keys)
                    .frame(width: Self.size.width)
                    .offset(y: Self.size.height - 30)
                    .id(keys)
                    .transition(.opacity.combined(with: .offset(y: 6)))
                    .zIndex(11)
            }

            if let cursor = layout.cursor {
                SceneCursor()
                    .offset(x: cursor.x, y: cursor.y)
                    .transition(.opacity)
                    .zIndex(12)
            }
        }
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
        // Laid out in small scene points and drawn larger; SwiftUI draws shapes, symbols and
        // text at the final scale, so it stays sharp.
        .scaleEffect(Self.displayScale, anchor: .topLeading)
        .frame(width: Self.size.width * Self.displayScale, height: Self.size.height * Self.displayScale, alignment: .topLeading)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.separator, lineWidth: 1)
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.82), value: phase)
        .animation(.easeInOut(duration: 0.3), value: feature)
    }

    private var wallpaper: some View {
        ZStack(alignment: .top) {
            // A tint fades from the top-left corner; `.tint` rather than the accent color so a
            // recording can use a neutral color (`ReadmeCapture`).
            Rectangle()
                .fill(.tint.opacity(0.28))
                .mask(LinearGradient(colors: [.black, .black.opacity(0.29)], startPoint: .topLeading, endPoint: .bottomTrailing))
            Rectangle()
                .fill(.background.opacity(0.6))
                .frame(height: Self.menuBarHeight)
        }
        .frame(width: Self.size.width, height: Self.size.height)
    }

    /// Where everything is for a feature at a phase.
    private struct Layout {
        var frames: [SceneWindow.Kind: CGRect] = [:]
        /// Back to front. Each feature sets it.
        var order: [SceneWindow.Kind] = []
        var snapPreview: CGRect?
        var snapAssist: CGRect?
        var switcher: SwitcherOverlay?
        var label: SceneLabel?
        var pickerSelection: Int?
        var keys: String?
        var cursor: CGPoint?

        private static let area = CGRect(
            x: inset, y: menuBarHeight + inset,
            width: size.width - inset * 2, height: size.height - menuBarHeight - inset * 2
        )
        private static let leftHalf = CGRect(x: area.minX, y: area.minY, width: area.width / 2 - 2, height: area.height)
        private static let rightHalf = CGRect(x: area.midX + 2, y: area.minY, width: area.width / 2 - 2, height: area.height)

        private static let browserFloating = CGRect(x: 95, y: 38, width: 150, height: 96)
        private static let documentFloating = CGRect(x: 225, y: 26, width: 140, height: 90)
        private static let messagesFloating = CGRect(x: 160, y: 66, width: 130, height: 84)

        init(feature: Feature, phase: Int) {
            switch feature {
            case .snap: snap(phase)
            case .keyboard: keyboard(phase)
            case .switcher: switcher(phase)
            }
        }

        /// Drag the browser to the left edge, it snaps, Snap Assist offers the rest.
        private mutating func snap(_ phase: Int) {
            frames = [.browser: Self.browserFloating, .document: Self.documentFloating]
            order = [.document, .browser]
            let grab = CGPoint(x: 60, y: 6)
            switch phase {
            case 0:
                cursor = point(in: Self.browserFloating, grab)
            case 1:
                let dragged = CGRect(origin: CGPoint(x: -40, y: 44), size: Self.browserFloating.size)
                frames[.browser] = dragged
                cursor = CGPoint(x: 2, y: 52)
                snapPreview = Self.leftHalf
            case 2:
                frames[.browser] = Self.leftHalf
                cursor = CGPoint(x: 2, y: 52)
            case 3:
                frames[.browser] = Self.leftHalf
                snapAssist = Self.rightHalf.insetBy(dx: 10, dy: 40)
                pickerSelection = 0
                cursor = CGPoint(x: Self.rightHalf.minX + 50, y: Self.rightHalf.midY)
            default:
                frames[.browser] = Self.leftHalf
                frames[.document] = Self.rightHalf
                order = [.browser, .document]
                cursor = CGPoint(x: Self.rightHalf.minX + 50, y: Self.rightHalf.midY)
            }
        }

        /// The same window jumps between places as shortcuts are pressed.
        private mutating func keyboard(_ phase: Int) {
            frames = [.browser: Self.browserFloating, .document: Self.documentFloating]
            order = [.document, .browser]
            switch phase {
            case 1:
                frames[.browser] = Self.leftHalf
                keys = "⌃ ⌥ ←"
            case 2:
                frames[.browser] = Self.rightHalf
                keys = "⌃ ⌥ →"
            case 3:
                frames[.browser] = Self.area
                keys = "⌃ ⌥ ↩"
            case 4:
                keys = "⌃ ⌥ ⌫"
            default:
                break
            }
        }

        /// macOS's ⌘Tab first, which has one icon per app, then Karo's ⌥Tab, which shows
        /// both browser windows (as a deck), offers quick actions and brings the second one up.
        private mutating func switcher(_ phase: Int) {
            frames = [
                .browser: Self.browserFloating,
                .video: Self.browserFloating.offsetBy(dx: -60, dy: 14),
                .document: Self.documentFloating,
                .messages: Self.messagesFloating,
            ]
            order = [.messages, .document, .video, .browser]
            switch phase {
            case 1:
                switcher = .apps
                keys = "⌘ Tab"
                label = .appsOnly
            case 2:
                switcher = .windows(isFanned: false, showsActions: false)
                keys = "⌥ Tab"
                label = .everyWindow
            case 3:
                switcher = .windows(isFanned: true, showsActions: false)
                keys = "⌥ Tab"
                label = .everyWindow
            case 4:
                switcher = .windows(isFanned: true, showsActions: true)
                label = .quickActions
            case 5:
                order = [.messages, .document, .browser, .video]
            default:
                break
            }
        }

        private func point(in frame: CGRect, _ offset: CGPoint) -> CGPoint {
            CGPoint(x: frame.minX + offset.x, y: frame.minY + offset.y)
        }
    }
}

private enum SwitcherOverlay: Equatable {
    case apps
    case windows(isFanned: Bool, showsActions: Bool)
}

private enum SceneLabel {
    case appsOnly, everyWindow, quickActions

    /// Identity for the cross-fade between labels.
    var key: Int {
        switch self {
        case .appsOnly: 0
        case .everyWindow: 1
        case .quickActions: 2
        }
    }
}

private extension Text {
    init(_ label: SceneLabel) {
        switch label {
        case .appsOnly: self.init("macOS ⌘Tab: one icon per app")
        case .everyWindow: self.init("Karo ⌥Tab: every window")
        case .quickActions: self.init("Right-click for quick actions")
        }
    }
}

/// A stand-in window with a title bar and a generic symbol.
private struct SceneWindow: View {
    enum Kind: CaseIterable {
        /// `video` is a second window of the browser.
        case browser, video, document, messages

        var symbol: String {
            switch self {
            case .browser: "safari"
            case .video: "play.rectangle.fill"
            case .document: "doc.text"
            case .messages: "message"
            }
        }

        var tint: Color {
            switch self {
            case .browser, .video: .blue
            case .document: .orange
            case .messages: .green
            }
        }
    }

    let kind: Kind

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 3) {
                ForEach([Color.red, .yellow, .green], id: \.self) { color in
                    Circle().fill(color.opacity(0.8)).frame(width: 4, height: 4)
                }
                Spacer()
            }
            .padding(.horizontal, 5)
            .frame(height: 11)
            .background(kind.tint.opacity(0.25))
            ZStack {
                Rectangle().fill(.background)
                kind.tint.opacity(0.12)
                Image(systemName: kind.symbol)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(kind.tint)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(kind.tint.opacity(0.35), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
    }
}

/// A row of small window cards on glass, for both Snap Assist and the switcher.
private struct MiniPicker: View {
    let kinds: [SceneWindow.Kind]
    let selected: Int?

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(kinds.enumerated()), id: \.offset) { index, kind in
                SceneWindow(kind: kind)
                    .frame(width: 48, height: 34)
                    .padding(3)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(index == selected ? AnyShapeStyle(.tint.opacity(0.35)) : AnyShapeStyle(.clear))
                    )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .shadow(color: .black.opacity(0.2), radius: 6, y: 2)
    }
}

/// macOS's own app switcher: app icons only, so the browser's two windows are one icon.
private struct AppSwitcherBar: View {
    let apps: [SceneWindow.Kind]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(apps.enumerated()), id: \.offset) { index, kind in
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(kind.tint.gradient)
                    .frame(width: 30, height: 30)
                    .overlay {
                        Image(systemName: kind.symbol)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .padding(3)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(index == 0 ? Color.primary.opacity(0.15) : .clear)
                    )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.2), radius: 6, y: 2)
    }
}

/// Karo's switcher in the grid style: the browser's two windows as a deck that fans out
/// when selected, the second window chosen, and the radial quick actions around it.
private struct WindowSwitcherPanel: View {
    let isFanned: Bool
    let showsActions: Bool

    var body: some View {
        HStack(spacing: isFanned ? 34 : 10) {
            ZStack {
                card(.browser, isSelected: false)
                    .offset(x: isFanned ? -24 : 0, y: isFanned ? 0 : -3)
                    .rotationEffect(.degrees(isFanned ? -4 : 0))
                card(.video, isSelected: isFanned)
                    .offset(x: isFanned ? 24 : 3, y: isFanned ? 0 : 0)
                    .rotationEffect(.degrees(isFanned ? 4 : 3))
                    .overlay {
                        // The real menu at the switcher's smallest size, scaled down and inert, so
                        // labels and ring keep the proportions they have in the app.
                        RadialMenu(isOpen: showsActions, outerRadius: 96, onAction: { _ in }, onHoverChange: { _ in })
                            .scaleEffect(0.45)
                            .allowsHitTesting(false)
                            .offset(x: 24)
                    }
            }
            .padding(3)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isFanned ? AnyShapeStyle(.clear) : AnyShapeStyle(.tint.opacity(0.35)))
            )
            .overlay(alignment: .topTrailing) {
                if !isFanned {
                    Text(verbatim: "2")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .background(.tint, in: Capsule())
                        .offset(x: 6, y: -4)
                }
            }
            .zIndex(1)
            card(.document, isSelected: false)
            card(.messages, isSelected: false)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.2), radius: 6, y: 2)
    }

    private func card(_ kind: SceneWindow.Kind, isSelected: Bool) -> some View {
        SceneWindow(kind: kind)
            .frame(width: 48, height: 34)
            .padding(3)
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear), lineWidth: 2)
            }
    }
}

private struct KeyCaps: View {
    let keys: String

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(keys.split(separator: " ").enumerated()), id: \.offset) { _, key in
                Text(key)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 6)
                    .frame(minWidth: 20, minHeight: 20)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(.separator, lineWidth: 0.5)
                    }
            }
        }
    }
}

// MARK: - Permission illustration

/// A miniature of the Accessibility list in System Settings with Karo's switch turning on,
/// so the user knows what to look for after clicking Allow.
struct PermissionIllustration: View {
    /// Until granted the animation loops; once granted it plays once and stays switched on.
    let isGranted: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isOn = false
    @State private var isCursorOnSwitch = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Accessibility")
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
            Divider()
            row(icon: Image(systemName: "app.dashed"), name: Text(verbatim: "…"), isOn: true, isPlaceholder: true)
            Divider().padding(.leading, 36)
            row(icon: Image(nsImage: NSApp.applicationIconImage), name: Text(verbatim: "Karo"), isOn: isOn || (isGranted && reduceMotion), isPlaceholder: false)
                .overlay(alignment: .trailing) { cursor }
        }
        .frame(width: 280)
        .background(.background, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.separator, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.1), radius: 6, y: 2)
        // Drawn at 1.3×, like the desktop scene; the padding makes room for the larger size.
        .scaleEffect(1.3)
        .padding(.vertical, 14)
        .task(id: isGranted) {
            guard !reduceMotion else { return }
            while true {
                if !isOn {
                    guard await pause(0.5) else { return }
                    withAnimation(.easeInOut(duration: 0.6)) { isCursorOnSwitch = true }
                    guard await pause(0.8) else { return }
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { isOn = true }
                }
                guard await pause(isGranted ? 0.6 : 1.8) else { return }
                if isGranted {
                    withAnimation(.easeInOut(duration: 0.4)) { isCursorOnSwitch = false }
                    return
                }
                withAnimation(.easeInOut(duration: 0.4)) {
                    isCursorOnSwitch = false
                    isOn = false
                }
            }
        }
        .accessibilityHidden(true)
    }

    /// - Returns: Whether the animation should go on; `false` once the view has gone away.
    private func pause(_ seconds: Double) async -> Bool {
        try? await Task.sleep(for: .seconds(seconds))
        return !Task.isCancelled
    }

    private func row(icon: Image, name: Text, isOn: Bool, isPlaceholder: Bool) -> some View {
        HStack(spacing: 8) {
            icon
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)
                .foregroundStyle(.tertiary)
            name
                .font(.system(size: 11))
                .foregroundStyle(isPlaceholder ? .tertiary : .primary)
            Spacer()
            MiniSwitch(isOn: isOn)
                .opacity(isPlaceholder ? 0.5 : 1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var cursor: some View {
        if !reduceMotion {
            SceneCursor()
                .offset(x: isCursorOnSwitch ? -14 : -90, y: isCursorOnSwitch ? 6 : 30)
                .opacity(isCursorOnSwitch ? 1 : 0)
        }
    }
}

/// The macOS pointer: black arrow with a white outline. SF Symbols has no filled arrow.
private struct SceneCursor: View {
    var body: some View {
        let arrow = Path { path in
            path.move(to: CGPoint(x: 0, y: 0))
            path.addLine(to: CGPoint(x: 0, y: 14))
            path.addLine(to: CGPoint(x: 3.5, y: 10.8))
            path.addLine(to: CGPoint(x: 6, y: 16))
            path.addLine(to: CGPoint(x: 8.2, y: 15))
            path.addLine(to: CGPoint(x: 5.8, y: 9.8))
            path.addLine(to: CGPoint(x: 10.2, y: 9.8))
            path.closeSubpath()
        }
        ZStack {
            arrow.stroke(.white, style: StrokeStyle(lineWidth: 2.2, lineJoin: .round))
            arrow.fill(.black)
        }
        .frame(width: 11, height: 17, alignment: .topLeading)
        .shadow(color: .black.opacity(0.3), radius: 1, y: 1)
    }
}

private struct MiniSwitch: View {
    let isOn: Bool

    var body: some View {
        Capsule()
            .fill(isOn ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary))
            .frame(width: 26, height: 15)
            .overlay(alignment: isOn ? .trailing : .leading) {
                Circle()
                    .fill(.white)
                    .shadow(color: .black.opacity(0.2), radius: 0.5, y: 0.5)
                    .padding(1.5)
            }
    }
}

private extension View {
    /// Sizes and positions a view at a rect in the scene's top-left coordinates.
    func placed(in rect: CGRect) -> some View {
        frame(width: rect.width, height: rect.height).offset(x: rect.minX, y: rect.minY)
    }
}
