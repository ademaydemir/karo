import AppKit

/// Light taps on Force Touch trackpads, felt only while a finger rests on the trackpad.
@MainActor
enum Haptics {
    /// A selection moved by one step, or a window entered a snap zone.
    static func tick() {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }
}
