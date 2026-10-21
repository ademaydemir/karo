import AppKit
import TesseraCore

/// Bridges `NSScreen` / `NSEvent` geometry into the Accessibility coordinates used by `TesseraCore`.
@MainActor
enum ScreenGeometry {
    static func displays() -> [Display] {
        let height = primaryScreenHeight
        return NSScreen.screens.map {
            Display(
                frame: CoordinateConverter.flip($0.frame, primaryScreenHeight: height),
                visibleFrame: CoordinateConverter.flip($0.visibleFrame, primaryScreenHeight: height)
            )
        }
    }

    static func cursorLocation() -> CGPoint {
        CoordinateConverter.flip(NSEvent.mouseLocation, primaryScreenHeight: primaryScreenHeight)
    }

    static func appKitFrame(fromAccessibility frame: CGRect) -> CGRect {
        CoordinateConverter.flip(frame, primaryScreenHeight: primaryScreenHeight)
    }

    /// `NSScreen.screens[0]` is always the primary display, whose top-left is the
    /// Accessibility origin.
    private static var primaryScreenHeight: CGFloat {
        NSScreen.screens.first?.frame.height ?? 0
    }
}
