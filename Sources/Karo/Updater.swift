import KaroAccessibility
import Observation
import Sparkle

/// Checks for new versions with Sparkle, which reads the appcast named by `SUFeedURL` in
/// Info.plist and verifies each download against `SUPublicEDKey`.
@MainActor
@Observable
final class Updater {
    @ObservationIgnored private let controller = SPUStandardUpdaterController(
        startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil
    )

    /// Mirrors Sparkle's own setting, which it stores in user defaults.
    var automaticallyChecksForUpdates: Bool {
        didSet { controller.updater.automaticallyChecksForUpdates = automaticallyChecksForUpdates }
    }

    init() {
        automaticallyChecksForUpdates = controller.updater.automaticallyChecksForUpdates
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
        // Accessory apps are not active by default, so Sparkle's window would open behind other windows.
        ApplicationActivation.activateCurrentApplication()
    }
}
