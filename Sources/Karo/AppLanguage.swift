import AppKit

/// The app's display language: the system language, or an override for Karo only.
///
/// The override uses the standard `AppleLanguages` preference in Karo's own defaults,
/// the same mechanism as System Settings → Language & Region → Applications. It takes
/// effect on the next launch.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english = "en"
    case turkish = "tr"

    private static let preferenceKey = "AppleLanguages"

    var id: String { rawValue }

    /// Language names are shown in their own language, so they can be found whatever the
    /// current language is.
    var displayName: String {
        switch self {
        case .system:
            String(
                localized: "System Default (\(AppLanguage.systemResolved.displayName))",
                comment: "Language option that follows macOS; the language it currently resolves to in parentheses"
            )
        case .english: "English"
        case .turkish: "Türkçe"
        }
    }

    /// The language macOS picks for Karo when there is no override: the first of the user's
    /// preferred languages that Karo is localized in, else English.
    static var systemResolved: AppLanguage {
        let preferences = UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)?[preferenceKey] as? [String]
            ?? Locale.preferredLanguages
        let candidates = allCases.filter { $0 != .system }.map(\.rawValue)
        let resolved = Bundle.preferredLocalizations(from: candidates, forPreferences: preferences).first
        return resolved == AppLanguage.turkish.rawValue ? .turkish : .english
    }

    static var current: AppLanguage {
        // Only Karo's own domain: `UserDefaults.standard` would also return the global,
        // system-wide language list.
        guard let bundleIdentifier = Bundle.main.bundleIdentifier,
              let languages = UserDefaults.standard.persistentDomain(forName: bundleIdentifier)?[preferenceKey] as? [String],
              let first = languages.first else { return .system }
        return AppLanguage(rawValue: first) ?? .system
    }

    static func select(_ language: AppLanguage) {
        if language == .system {
            UserDefaults.standard.removeObject(forKey: preferenceKey)
        } else {
            UserDefaults.standard.set([language.rawValue], forKey: preferenceKey)
        }
    }

    /// Quits and reopens Karo so the new language is loaded.
    ///
    /// The new instance starts only after this one has exited; running both at once would
    /// leave the new one unable to register the global shortcuts.
    @MainActor
    static func relaunch() {
        AppRelaunch.relaunch()
    }
}
