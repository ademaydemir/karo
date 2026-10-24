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
        /// Only filled in with Screen Recording permission.
        let title: String?
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
            return WindowInfo(
                id: id,
                processIdentifier: processIdentifier,
                bounds: bounds,
                title: info[kCGWindowName as String] as? String
            )
        }
    }

    /// The window of `processIdentifier` in `windows` whose bounds match an Accessibility frame.
    ///
    /// Bounds alone cannot tell apart two windows of an app stacked on the same frame, such as
    /// two maximized browser windows; the front one would match both. Listing all of an app's
    /// windows therefore passes the IDs already matched, and the title where known.
    /// - Parameters:
    ///   - title: Preferred among windows with the same bounds; ignored where the window server
    ///     does not report titles.
    ///   - excluded: Windows already matched to another Accessibility window.
    static func match(
        processIdentifier: pid_t,
        frame: CGRect,
        title: String? = nil,
        excluding excluded: Set<CGWindowID> = [],
        in windows: [WindowInfo]
    ) -> (index: Int, window: WindowInfo)? {
        var best: (index: Int, window: WindowInfo, distance: CGFloat, titleMatches: Bool)?
        for (index, window) in windows.enumerated()
        where window.processIdentifier == processIdentifier && !excluded.contains(window.id) {
            guard abs(window.bounds.width - frame.width) <= 2, abs(window.bounds.height - frame.height) <= 2 else { continue }
            let distance = hypot(window.bounds.minX - frame.minX, window.bounds.minY - frame.minY)
            guard distance <= 2 else { continue }
            let titleMatches = title != nil && window.title == title
            // A matching title wins; then the closest bounds; then the frontmost, as listed.
            if let current = best {
                if current.titleMatches && !titleMatches { continue }
                if current.titleMatches == titleMatches && distance >= current.distance { continue }
            }
            best = (index, window, distance, titleMatches)
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
