import ServiceManagement

/// Registers Karo as a login item. The state lives in the system, not in our settings,
/// because the user can also change it in System Settings → General → Login Items.
@MainActor
@Observable
final class LaunchAtLogin {
    private(set) var isEnabled = false
    /// macOS can require the user to approve the login item in System Settings.
    private(set) var requiresApproval = false

    init() {
        refresh()
    }

    func refresh() {
        let status = SMAppService.mainApp.status
        isEnabled = status == .enabled
        requiresApproval = status == .requiresApproval
    }

    func setEnabled(_ enabled: Bool) throws {
        defer { refresh() }
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
