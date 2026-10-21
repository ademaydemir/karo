import SwiftUI
import KaroAccessibility

/// The steps of the welcome window. Permissions come after the introduction, so the user
/// knows why Karo asks for them.
struct WelcomeView: View {
    enum Exit { case done, settings }

    private enum Step: Int, CaseIterable {
        case introduction, permissions, ready
    }

    let launchAtLogin: LaunchAtLogin
    let onExit: (Exit) -> Void

    @State private var step = Step.introduction
    @State private var isMovingForward = true

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                // Each step in its own `if`, so it gets its own insertion and removal transition.
                if step == .introduction { IntroductionStep().transition(slide) }
                if step == .permissions { PermissionsStep().transition(slide) }
                if step == .ready { ReadyStep(launchAtLogin: launchAtLogin).transition(slide) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()

            footer
        }
        .frame(width: 560, height: 500)
    }

    private var footer: some View {
        HStack {
            PageIndicator(count: Step.allCases.count, current: step.rawValue)
            Spacer()
            if step == .introduction {
                Button("Skip") { onExit(.done) }
                    .keyboardShortcut(.cancelAction)
            } else {
                Button("Back") { go(by: -1) }
            }
            if step == .ready {
                Button("Open Settings") { onExit(.settings) }
                Button("Get Started") { onExit(.done) }
                    .prominentButtonStyle()
                    .keyboardShortcut(.defaultAction)
            } else {
                Button("Continue") { go(by: 1) }
                    .prominentButtonStyle()
                    .keyboardShortcut(.defaultAction)
            }
        }
        .controlSize(.large)
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
    }

    private var slide: AnyTransition {
        .asymmetric(
            insertion: .move(edge: isMovingForward ? .trailing : .leading).combined(with: .opacity),
            removal: .move(edge: isMovingForward ? .leading : .trailing).combined(with: .opacity)
        )
    }

    private func go(by offset: Int) {
        guard let next = Step(rawValue: step.rawValue + offset) else { return }
        isMovingForward = offset > 0
        withAnimation(.smooth(duration: 0.35)) { step = next }
    }
}

// MARK: - Steps

private struct IntroductionStep: View {
    var body: some View {
        VStack(spacing: 28) {
            VStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 96, height: 96)
                    .accessibilityHidden(true)
                Text("Welcome to Karo")
                    .font(.largeTitle.bold())
                Text("Windows-style window management for your Mac.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 16) {
                FeatureRow(
                    symbol: "rectangle.split.2x1",
                    title: "Drag to snap",
                    detail: "Drag a window to a screen edge or corner to fill a half or a quarter. Karo then suggests windows for the free space."
                )
                FeatureRow(
                    symbol: "keyboard",
                    title: "Place with the keyboard",
                    detail: "⌃⌥← and ⌃⌥→ for halves, ⌃⌥↩ to maximize, ⌃⌥⌫ to restore. All shortcuts can be changed."
                )
                FeatureRow(
                    symbol: "rectangle.stack",
                    title: "Switch between windows",
                    detail: "Hold ⌥ and press Tab to see every window, not just every app."
                )
            }
            .frame(maxWidth: 420)
        }
        .padding(.horizontal, 40)
        .padding(.top, 24)
    }
}

private struct PermissionsStep: View {
    @State private var isAccessibilityGranted = AccessibilityPermission.isGranted
    @State private var isScreenRecordingGranted = ScreenRecordingPermission.isGranted
    @State private var hasRequestedScreenRecording = false

    var body: some View {
        VStack(spacing: 24) {
            StepHeader(
                symbol: "hand.raised.fill",
                title: "Allow Access",
                detail: "Karo works through macOS privacy permissions. Everything stays on your Mac."
            )
            VStack(spacing: 12) {
                PermissionRow(
                    symbol: "accessibility",
                    title: "Accessibility",
                    badge: "Required",
                    detail: "Lets Karo move and resize other apps’ windows.",
                    isGranted: isAccessibilityGranted
                ) {
                    // The system prompt adds Karo to the list and links to System Settings.
                    if AccessibilityPermission.requestIfNeeded() { isAccessibilityGranted = true }
                }
                PermissionRow(
                    symbol: "rectangle.dashed.badge.record",
                    title: "Screen Recording",
                    badge: "Optional",
                    detail: hasRequestedScreenRecording && !isScreenRecordingGranted
                        ? "After allowing it, restart Karo to see window previews."
                        : "Shows live window previews in the switcher and Snap Assist. Nothing is recorded or saved.",
                    isGranted: isScreenRecordingGranted
                ) {
                    // macOS shows its prompt only once; later requests go to System Settings.
                    if hasRequestedScreenRecording {
                        ScreenRecordingPermission.openSystemSettings()
                    } else {
                        ScreenRecordingPermission.request()
                        hasRequestedScreenRecording = true
                    }
                }
            }
            .frame(maxWidth: 460)
        }
        .padding(.horizontal, 40)
        .padding(.top, 36)
        .task {
            // macOS has no notification for permission changes; check while this step is shown.
            while !Task.isCancelled {
                isAccessibilityGranted = AccessibilityPermission.isGranted
                isScreenRecordingGranted = ScreenRecordingPermission.isGranted
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
}

private struct ReadyStep: View {
    let launchAtLogin: LaunchAtLogin
    @State private var loginItemError: String?
    @State private var isSystemTilingEnabled = SystemTiling.isEdgeDragTilingEnabled

    var body: some View {
        VStack(spacing: 24) {
            StepHeader(
                symbol: "checkmark.circle.fill",
                title: "You’re All Set",
                detail: "Karo lives in the menu bar. Click its icon for window actions and Settings."
            )
            VStack(spacing: 12) {
                Card {
                    Toggle(isOn: Binding(get: { launchAtLogin.isEnabled }, set: setLaunchAtLogin)) {
                        Text("Launch at login")
                        Text("Start Karo automatically when you log in.")
                    }
                    .toggleStyle(.switch)
                    if let loginItemError {
                        Text(loginItemError)
                            .font(.callout)
                            .foregroundStyle(.red)
                    }
                }
                if isSystemTilingEnabled {
                    Card {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("macOS tiling is also on")
                                    .fontWeight(.medium)
                                Text("“Drag windows to screen edges to tile” reacts to the same drags. Turn it off so only Karo snaps.")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                            Button("Open Desktop & Dock…") { SystemTiling.openSettings() }
                        }
                    }
                }
            }
            .frame(maxWidth: 460)
        }
        .padding(.horizontal, 40)
        .padding(.top, 36)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // The user may have changed these in System Settings and come back.
            isSystemTilingEnabled = SystemTiling.isEdgeDragTilingEnabled
            launchAtLogin.refresh()
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try launchAtLogin.setEnabled(enabled)
            loginItemError = nil
        } catch {
            loginItemError = String(localized: "Could not change the login item: \(error.localizedDescription)")
        }
    }
}

// MARK: - Components

private struct StepHeader: View {
    let symbol: String
    let title: LocalizedStringKey
    let detail: LocalizedStringKey

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 44))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text(title)
                .font(.largeTitle.bold())
            Text(detail)
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct FeatureRow: View {
    let symbol: String
    let title: LocalizedStringKey
    let detail: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .fontWeight(.semibold)
                Text(detail)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct PermissionRow: View {
    let symbol: String
    let title: LocalizedStringKey
    let badge: LocalizedStringKey
    let detail: LocalizedStringKey
    let isGranted: Bool
    let onAllow: () -> Void

    var body: some View {
        Card {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: symbol)
                    .font(.title2)
                    .foregroundStyle(.tint)
                    .frame(width: 32)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(title)
                            .fontWeight(.semibold)
                        Text(badge)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(.quaternary, in: Capsule())
                    }
                    Text(detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                if isGranted {
                    Label("Allowed", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .fixedSize()
                } else {
                    Button("Allow…", action: onAllow)
                        .fixedSize()
                }
            }
        }
        .animation(.default, value: isGranted)
    }
}

private struct Card<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) { content }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quinary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct PageIndicator: View {
    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(index == current ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary))
                    .frame(width: index == current ? 18 : 7, height: 7)
            }
        }
        .animation(.smooth, value: current)
        .accessibilityElement()
        .accessibilityLabel(Text("Step \(current + 1) of \(count)"))
    }
}

private extension View {
    /// Liquid Glass on macOS 26 and later.
    @ViewBuilder
    func prominentButtonStyle() -> some View {
        if #available(macOS 26.0, *) {
            buttonStyle(.glassProminent)
        } else {
            buttonStyle(.borderedProminent)
        }
    }
}
