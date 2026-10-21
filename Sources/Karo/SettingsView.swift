import SwiftUI
import KaroAccessibility
import KaroCore

/// Width shared by all settings tabs, so only the height changes when switching.
private let settingsWidth: CGFloat = 500

// MARK: - General

struct GeneralSettingsView: View {
    let store: SettingsStore
    let launchAtLogin: LaunchAtLogin
    @State private var isAccessibilityGranted = AccessibilityPermission.isGranted
    @State private var loginItemError: String?
    @State private var language = AppLanguage.current
    /// The language this instance was launched with; a different selection needs a restart.
    @State private var launchLanguage = AppLanguage.current

    var body: some View {
        Form {
            Section {
                Picker(selection: Binding(get: { language }, set: selectLanguage)) {
                    ForEach(AppLanguage.allCases) { option in
                        Text(verbatim: option.displayName).tag(option)
                    }
                } label: {
                    Text("Language")
                    Text("Karo can use a different language than macOS.")
                }
                if language != launchLanguage {
                    LabeledContent {
                        Button("Restart Now") { AppLanguage.relaunch() }
                    } label: {
                        Text("Restart Karo to use the new language.")
                    }
                }
            }

            Section {
                Toggle(isOn: Binding(get: { launchAtLogin.isEnabled }, set: setLaunchAtLogin)) {
                    Text("Launch at login")
                    Text("Start Karo automatically when you log in.")
                }
                if launchAtLogin.requiresApproval {
                    LabeledContent {
                        Button("Open Login Items…") { launchAtLogin.openSystemSettings() }
                    } label: {
                        Text("Approval needed")
                        Text("Allow Karo in System Settings to finish turning this on.")
                    }
                }
                if let loginItemError {
                    Text(loginItemError)
                        .foregroundStyle(.red)
                }
                Toggle(isOn: store.binding(\.showsMenuBarIcon)) {
                    Text("Show in menu bar")
                    Text("When hidden, open Karo again from Finder or Spotlight to see Settings.")
                }
            }

            Section {
                LabeledContent {
                    if isAccessibilityGranted {
                        Label("Allowed", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Button("Open Privacy Settings…") { AccessibilityPermission.openSystemSettings() }
                    }
                } label: {
                    Text("Accessibility")
                    Text("Required to move and resize other apps’ windows.")
                }
            }
        }
        .settingsFormStyle()
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // The user may have changed these in System Settings and come back.
            isAccessibilityGranted = AccessibilityPermission.isGranted
            launchAtLogin.refresh()
        }
    }

    private func selectLanguage(_ selected: AppLanguage) {
        language = selected
        AppLanguage.select(selected)
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

// MARK: - Snapping

struct SnappingSettingsView: View {
    let store: SettingsStore
    @State private var isSystemTilingEnabled = SystemTiling.isEdgeDragTilingEnabled

    var body: some View {
        Form {
            if isSystemTilingEnabled {
                Section {
                    LabeledContent {
                        Button("Open Desktop & Dock…") { SystemTiling.openSettings() }
                    } label: {
                        Label("macOS tiling is also on", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("“Drag windows to screen edges to tile” reacts to the same drags. Turn it off so only Karo snaps.")
                    }
                }
            }

            Section {
                Toggle(isOn: store.binding(\.isDragSnappingEnabled)) {
                    Text("Snap windows dragged to screen edges")
                    Text("Edges snap to halves, corners to quarters, the top edge maximizes. Hold ⇧ while dragging to move freely.")
                }
                PointSlider(
                    title: "Edge sensitivity",
                    detail: "How close to the edge the pointer must be.",
                    value: store.binding(\.edgeThreshold),
                    range: 1...20
                )
                .disabled(!store.settings.isDragSnappingEnabled)
                PointSlider(
                    title: "Corner size",
                    detail: "Length of the corner areas that snap to quarters.",
                    value: store.binding(\.cornerSize),
                    range: 10...150
                )
                .disabled(!store.settings.isDragSnappingEnabled)
                Toggle(isOn: store.binding(\.isSnapAssistEnabled)) {
                    Text("Suggest windows for the other side")
                    Text("After snapping to a half or a third, pick a window to fill the rest of the screen.")
                }
            } header: {
                Text("Drag to Snap")
            }

            Section {
                Picker(selection: store.binding(\.modifierDrag)) {
                    ForEach(ModifierDrag.allCases, id: \.self) { option in
                        Text(verbatim: option.title).tag(option)
                    }
                } label: {
                    Text("Move and resize from anywhere")
                    Text("Hold these keys and drag anywhere in a window to move it, or right-drag to resize it from the nearest corner.")
                }
            } header: {
                Text("Move and Resize")
            }

            Section {
                PointSlider(
                    title: "Gap between windows",
                    detail: "Space around snapped windows and between neighbours.",
                    value: store.binding(\.gap),
                    range: 0...40
                )
            } header: {
                Text("Layout")
            }

            Section {
                Toggle(isOn: store.binding(\.restoresLayoutOnDisplayChange)) {
                    Text("Remember window positions for each display setup")
                    Text("When you connect or disconnect a display, windows go back to where they were the last time you used that setup.")
                }
            } header: {
                Text("Displays")
            }
        }
        .settingsFormStyle()
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            isSystemTilingEnabled = SystemTiling.isEdgeDragTilingEnabled
        }
    }
}

// MARK: - Switcher

struct SwitcherSettingsView: View {
    let store: SettingsStore
    @State private var isScreenRecordingGranted = ScreenRecordingPermission.isGranted

    var body: some View {
        Form {
            Section {
                LabeledContent {
                    Text(verbatim: "\(DefaultShortcuts.switchWindowsForward.displayString)  \(DefaultShortcuts.switchWindowsBackward.displayString)")
                        .monospaced()
                        .foregroundStyle(.secondary)
                } label: {
                    Text("Switch windows")
                    Text("Hold ⌥ and press Tab to step through windows; release ⌥ to switch.")
                }
            }

            Section {
                Picker(selection: store.binding(\.switcherStyle)) {
                    ForEach(SwitcherStyle.allCases, id: \.self) { style in
                        Text(verbatim: style.title).tag(style)
                    }
                } label: {
                    Text("Style")
                }
                .pickerStyle(.segmented)
                SwitcherStylePreview(style: store.settings.switcherStyle)
                Picker(selection: store.binding(\.switcherSize)) {
                    ForEach(SwitcherSize.allCases, id: \.self) { size in
                        Text(verbatim: size.title).tag(size)
                    }
                } label: {
                    Text("Size")
                    Text("Also \(DefaultShortcuts.switcherLarger.displayString) / \(DefaultShortcuts.switcherSmaller.displayString) while the switcher is open.")
                }
                .pickerStyle(.segmented)
                LabeledContent {
                    EmptyView()
                } label: {
                    Text("Quick actions")
                    Text("Right-click a window in the switcher to close, minimize, hide or place it. Holding ⌥, the same works from the keyboard.")
                }
            }

            Section {
                Toggle(isOn: Binding(get: { store.settings.showsWindowPreviews }, set: setShowsPreviews)) {
                    Text("Show window previews")
                    Text("Show a thumbnail of each window instead of only its app icon.")
                }
                if store.settings.showsWindowPreviews && !isScreenRecordingGranted {
                    LabeledContent {
                        Button("Open Privacy Settings…") { ScreenRecordingPermission.openSystemSettings() }
                    } label: {
                        Label("Screen Recording needed", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("Allow Karo under Screen & System Audio Recording, then quit and reopen Karo. Until then, app icons are shown.")
                    }
                }
            }
        }
        .settingsFormStyle()
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            isScreenRecordingGranted = ScreenRecordingPermission.isGranted
        }
    }

    private func setShowsPreviews(_ enabled: Bool) {
        store.update { $0.showsWindowPreviews = enabled }
        if enabled && !ScreenRecordingPermission.isGranted {
            ScreenRecordingPermission.request()
        }
    }
}

// MARK: - Shortcuts

struct ShortcutsSettingsView: View {
    let store: SettingsStore
    let recorder: ShortcutRecorder

    var body: some View {
        Form {
            ForEach(Array(WindowAction.groups.enumerated()), id: \.offset) { _, group in
                Section {
                    ForEach(group, id: \.self) { action in
                        LabeledContent(action.title) {
                            ShortcutField(
                                shortcut: store.settings.shortcut(for: action),
                                isRecording: recorder.recordingAction == action,
                                onRecord: { recorder.startRecording(action) },
                                onCancel: { recorder.stopRecording() },
                                onClear: { recorder.clear(action) }
                            )
                        }
                    }
                }
            }
            Section {
                if let message = recorder.rejectionMessage {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
                HStack {
                    Text("Click a shortcut, then type the new combination. Press ⎋ to cancel.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Restore Defaults") { recorder.resetAll() }
                }
            }
        }
        .formStyle(.grouped)
        // The list is long; it scrolls inside a fixed-height window.
        .frame(width: settingsWidth, height: 560)
    }
}

private struct ShortcutField: View {
    // Qualified because SwiftUI has its own `KeyboardShortcut`.
    let shortcut: KaroCore.KeyboardShortcut?
    let isRecording: Bool
    let onRecord: () -> Void
    let onCancel: () -> Void
    let onClear: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Button(action: isRecording ? onCancel : onRecord) {
                Text(label)
                    .monospaced()
                    .foregroundStyle(shortcut == nil && !isRecording ? .secondary : .primary)
                    .frame(minWidth: 96)
            }
            .accessibilityHint(isRecording ? Text("Type a shortcut, or press Escape to cancel") : Text("Records a new shortcut"))
            Button(action: onClear) {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .opacity(shortcut == nil ? 0 : 1)
            .disabled(shortcut == nil)
            .accessibilityLabel("Remove shortcut")
        }
    }

    private var label: String {
        if isRecording { return String(localized: "Type shortcut…") }
        return shortcut?.displayString ?? String(localized: "None", comment: "No shortcut assigned")
    }
}

/// A continuous slider (no tick marks) whose value snaps to whole points.
private struct PointSlider: View {
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    let value: Binding<CGFloat>
    let range: ClosedRange<CGFloat>

    var body: some View {
        LabeledContent {
            HStack(spacing: 8) {
                Slider(value: Binding(get: { value.wrappedValue }, set: { value.wrappedValue = $0.rounded() }), in: range)
                    .frame(width: 160)
                    .accessibilityLabel(Text(title))
                    .accessibilityValue(Text("\(Int(value.wrappedValue)) points"))
                Text("\(Int(value.wrappedValue)) pt", comment: "Slider value in points")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 44, alignment: .trailing)
                    .accessibilityHidden(true)
            }
        } label: {
            Text(title)
            Text(detail)
        }
    }
}

private extension View {
    /// Grouped form sized to its content, so the window fits each tab without empty space.
    func settingsFormStyle() -> some View {
        formStyle(.grouped)
            .scrollDisabled(true)
            .scrollContentBackground(.hidden)
            .fixedSize(horizontal: false, vertical: true)
            .frame(width: settingsWidth)
    }
}

extension SettingsStore {
    func binding<Value>(_ keyPath: WritableKeyPath<KaroSettings, Value>) -> Binding<Value> {
        Binding(
            get: { self.settings[keyPath: keyPath] },
            set: { newValue in self.update { $0[keyPath: keyPath] = newValue } }
        )
    }
}
