import AppKit
import KaroCore

/// Bridges `NSScreen` / `NSEvent` geometry into the Accessibility coordinates used by `KaroCore`.
@MainActor
enum ScreenGeometry {
    /// Reading the window list on every drag event would be wasteful; the Dock rarely moves.
    private static let dockLookupLifetime: Duration = .seconds(1)
    private static var cachedDockDisplay: (frame: CGRect?, time: ContinuousClock.Instant)?

    /// Every display with the area windows may use. macOS reserves Dock space on all displays
    /// when each has its own Spaces; the reservation is dropped where the Dock is not.
    static func displays() -> [Display] {
        let height = primaryScreenHeight
        let dockDisplay = dockDisplayFrame()
        return NSScreen.screens.map { screen in
            let frame = CoordinateConverter.flip(screen.frame, primaryScreenHeight: height)
            let visibleFrame = CoordinateConverter.flip(screen.visibleFrame, primaryScreenHeight: height)
            // When the Dock's display cannot be told, keep what macOS reserved.
            let hostsDock = dockDisplay.map { frame.contains(CGPoint(x: $0.midX, y: $0.midY)) } ?? true
            return Display(
                frame: frame,
                visibleFrame: Display.usableFrame(visibleFrame: visibleFrame, frame: frame, hostsDock: hostsDock)
            )
        }
    }

    /// The display the Dock is on, in Accessibility coordinates. The Dock's own window spans
    /// that whole display. Window bounds and owners need no Screen Recording permission.
    private static func dockDisplayFrame() -> CGRect? {
        if let cached = cachedDockDisplay, ContinuousClock.now - cached.time < dockLookupLifetime {
            return cached.frame
        }
        var frame: CGRect?
        if let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first,
           let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] {
            let dockLevel = Int(CGWindowLevelForKey(.dockWindow))
            frame = list.lazy
                .filter {
                    ($0[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == dock.processIdentifier
                        && ($0[kCGWindowLayer as String] as? NSNumber)?.intValue == dockLevel
                }
                .compactMap { ($0[kCGWindowBounds as String] as? NSDictionary).flatMap { CGRect(dictionaryRepresentation: $0 as CFDictionary) } }
                .first
        }
        cachedDockDisplay = (frame, .now)
        return frame
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
