import AppKit
import OSLog
import KaroAccessibility

/// Offers to move Karo into /Applications when it runs from somewhere else, typically the
/// downloaded disk image, where it cannot update itself and its login item would break.
@MainActor
enum MoveToApplications {
    // Development builds run from build/ and must not ask. A constant rather than wrapping the
    // body in #if keeps its strings visible to scripts/update-strings.sh, which builds debug.
    #if DEBUG
    private static let isDevelopmentBuild = true
    #else
    private static let isDevelopmentBuild = false
    #endif

    /// Returns the moved copy when the user agreed; the caller relaunches from it. The caller
    /// does the relaunch because `NSApp.terminate` does not return, so it has to mark this
    /// copy as handing over first.
    static func offerIfNeeded() -> URL? {
        guard !isDevelopmentBuild else { return nil }

        let bundlePath = Bundle.main.bundleURL.standardized.path
        let systemApplications = "/Applications/"
        var userApplications = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications", isDirectory: true)
            .standardized
            .path
        if !userApplications.hasSuffix("/") {
            userApplications += "/"
        }
        if bundlePath.hasPrefix(systemApplications) || bundlePath.hasPrefix(userApplications) {
            return nil
        }

        let suppressionKey = "MoveToApplicationsSuppressed"
        if UserDefaults.standard.bool(forKey: suppressionKey) {
            return nil
        }

        ApplicationActivation.activateCurrentApplication()

        let alert = NSAlert()
        alert.messageText = String(localized: "Move Karo to the Applications folder?")
        alert.informativeText = String(localized: "Karo is running from outside the Applications folder, for example from the disk image. In Applications it can update itself and start at login.")
        alert.addButton(withTitle: String(localized: "Move to Applications"))
        alert.addButton(withTitle: String(localized: "Do Not Move"))
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = String(localized: "Do not ask again")

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else {
            if alert.suppressionButton?.state == .on {
                UserDefaults.standard.set(true, forKey: suppressionKey)
            }
            return nil
        }

        let fileManager = FileManager.default
        let source = Bundle.main.bundleURL
        let destination = URL(fileURLWithPath: "/Applications").appendingPathComponent(source.lastPathComponent)
        let logger = Logger(subsystem: "dev.ademaydemir.Karo", category: "lifecycle")

        do {
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.trashItem(at: destination, resultingItemURL: nil)
            }
            try fileManager.copyItem(at: source, to: destination)
        } catch {
            logger.error("Could not move Karo to /Applications: \(String(describing: error), privacy: .public)")
            let failureAlert = NSAlert()
            failureAlert.messageText = String(localized: "Karo could not be moved")
            failureAlert.informativeText = String(localized: "Drag Karo to the Applications folder in Finder, then open it from there.")
            failureAlert.runModal()
            return nil
        }

        if !source.path.contains("/AppTranslocation/"),
           (try? source.resourceValues(forKeys: [.volumeIsReadOnlyKey]))?.volumeIsReadOnly == false {
            do {
                try fileManager.trashItem(at: source, resultingItemURL: nil)
            } catch {
                logger.error("Could not trash original bundle at \(source.path, privacy: .public): \(String(describing: error), privacy: .public)")
            }
        }

        return destination
    }
}
