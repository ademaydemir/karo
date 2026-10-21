import AppKit
import KaroCore

/// Bridges `NSScreen` / `NSEvent` geometry into the Accessibility coordinates used by `KaroCore`.
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

    /// Hardware identity and arrangement of the connected displays, for `DisplayConfiguration`.
    static func displayDescriptors() -> [DisplayConfiguration.Descriptor] {
        let height = primaryScreenHeight
        return NSScreen.screens.compactMap { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return nil
            }
            let displayID = CGDirectDisplayID(number.uint32Value)
            return DisplayConfiguration.Descriptor(
                vendor: CGDisplayVendorNumber(displayID),
                model: CGDisplayModelNumber(displayID),
                serial: CGDisplaySerialNumber(displayID),
                frame: CoordinateConverter.flip(screen.frame, primaryScreenHeight: height)
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
