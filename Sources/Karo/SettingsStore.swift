import Foundation
import OSLog
import KaroCore

/// Loads and saves `KaroSettings`, and tells the app when they change.
@MainActor
@Observable
final class SettingsStore {
    private static let key = "settings"

    private(set) var settings: KaroSettings
    @ObservationIgnored var onChange: (KaroSettings) -> Void = { _ in }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let logger = Logger(subsystem: "dev.ademaydemir.Karo", category: "settings")

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key) {
            do {
                settings = try JSONDecoder().decode(KaroSettings.self, from: data)
            } catch {
                // Unreadable settings fall back to defaults rather than blocking launch.
                settings = KaroSettings()
                Logger(subsystem: "dev.ademaydemir.Karo", category: "settings")
                    .error("Settings could not be read, using defaults: \(String(describing: error), privacy: .public)")
            }
        } else {
            settings = KaroSettings()
        }
    }

    func update(_ change: (inout KaroSettings) -> Void) {
        var updated = settings
        change(&updated)
        guard updated != settings else { return }
        settings = updated
        save()
        onChange(updated)
    }

    private func save() {
        do {
            defaults.set(try JSONEncoder().encode(settings), forKey: Self.key)
        } catch {
            logger.error("Settings could not be saved: \(String(describing: error), privacy: .public)")
        }
    }
}
