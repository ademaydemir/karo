import CoreGraphics
import Foundation

/// Live window geometry from the window server.
///
/// While the user drags a window, the window server moves it directly and the app's
/// Accessibility position is not updated until the drag ends, so drag movement has to be
/// read here. Only bounds, owner and layer are read, which needs no Screen Recording
/// permission. Bounds use the same top-left-origin coordinates as Accessibility.
enum WindowServer {
    /// Finds the on-screen window of `processIdentifier` whose bounds match `frame`.
    static func windowID(ownedBy processIdentifier: pid_t, matching frame: CGRect) -> CGWindowID? {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] else { return nil }

        var best: (id: CGWindowID, distance: CGFloat)?
        for info in list {
            guard (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == processIdentifier,
                  (info[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  let id = (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                  let bounds = bounds(from: info),
                  abs(bounds.width - frame.width) <= 1, abs(bounds.height - frame.height) <= 1 else { continue }
            let distance = hypot(bounds.minX - frame.minX, bounds.minY - frame.minY)
            if distance <= 2, distance < (best?.distance ?? .infinity) {
                best = (id, distance)
            }
        }
        return best?.id
    }

    struct StackedWindow {
        let processIdentifier: pid_t
        let bounds: CGRect
    }

    /// Normal-level on-screen windows, front to back.
    static func stackingOrder() -> [StackedWindow] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] else { return [] }
        return list.compactMap { info in
            guard (info[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  let processIdentifier = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  let bounds = bounds(from: info) else { return nil }
            return StackedWindow(processIdentifier: processIdentifier, bounds: bounds)
        }
    }

    static func bounds(of windowID: CGWindowID) -> CGRect? {
        guard let list = CGWindowListCopyWindowInfo(.optionIncludingWindow, windowID) as? [[String: Any]],
              let info = list.first else { return nil }
        return bounds(from: info)
    }

    private static func bounds(from info: [String: Any]) -> CGRect? {
        guard let dictionary = info[kCGWindowBounds as String] as? NSDictionary else { return nil }
        return CGRect(dictionaryRepresentation: dictionary as CFDictionary)
    }
}
