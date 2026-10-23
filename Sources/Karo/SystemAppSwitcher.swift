import CoreGraphics
import OSLog

/// The macOS app switcher (⌘Tab, ⌘⇧Tab). Karo turns it off while its own window switcher
/// uses ⌘Tab, because the system handles its shortcuts before any app sees them.
///
/// Uses the private `CGSSetSymbolicHotKeyEnabled`, as other switchers do; there is no public API.
/// The setting lasts for the login session, so it is turned back on when Karo quits.
enum SystemAppSwitcher {
    private static let logger = Logger(subsystem: "dev.ademaydemir.Karo", category: "switcher")
    private static let commandTab: Int32 = 1
    private static let commandShiftTab: Int32 = 2

    static func setEnabled(_ isEnabled: Bool) {
        for hotKey in [commandTab, commandShiftTab] {
            let error = CGSSetSymbolicHotKeyEnabled(hotKey, isEnabled)
            if error != .success {
                logger.error("CGSSetSymbolicHotKeyEnabled(\(hotKey), \(isEnabled)) failed: \(String(describing: error), privacy: .public)")
            }
        }
    }
}

@_silgen_name("CGSSetSymbolicHotKeyEnabled")
private func CGSSetSymbolicHotKeyEnabled(_ hotKey: Int32, _ isEnabled: Bool) -> CGError
