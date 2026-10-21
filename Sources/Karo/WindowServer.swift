import CoreGraphics
import Foundation

/// Live window geometry from the window server.
///
/// While the user drags a window, the window server moves it directly and the app's
/// Accessibility position is not updated until the drag ends, so drag movement has to be
/// read here. Only IDs, bounds, owner and layer are read, which needs no Screen Recording
/// permission. Bounds use the same top-left-origin coordinates as Accessibility.
enum WindowServer {
    struct WindowInfo {
        let id: CGWindowID
        let processIdentifier: pid_t
        let bounds: CGRect
    }

    /// Normal-level windows, front to back. Off-screen windows include minimized ones.
    static func windows(onScreenOnly: Bool = true) -> [WindowInfo] {
        let options: CGWindowListOption = onScreenOnly
            ? [.optionOnScreenOnly, .excludeDesktopElements]
            : [.optionAll, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return [] }
        return list.compactMap { info in
            guard (info[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  let id = (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                  let processIdentifier = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  let bounds = bounds(from: info) else { return nil }
            return WindowInfo(id: id, processIdentifier: processIdentifier, bounds: bounds)
        }
    }

    /// The window of `processIdentifier` in `windows` whose bounds match an Accessibility frame.
    static func match(processIdentifier: pid_t, frame: CGRect, in windows: [WindowInfo]) -> (index: Int, window: WindowInfo)? {
        var best: (index: Int, window: WindowInfo, distance: CGFloat)?
        for (index, window) in windows.enumerated() where window.processIdentifier == processIdentifier {
            guard abs(window.bounds.width - frame.width) <= 2, abs(window.bounds.height - frame.height) <= 2 else { continue }
            let distance = hypot(window.bounds.minX - frame.minX, window.bounds.minY - frame.minY)
            if distance <= 2, distance < (best?.distance ?? .infinity) {
                best = (index, window, distance)
            }
        }
        return best.map { ($0.index, $0.window) }
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
