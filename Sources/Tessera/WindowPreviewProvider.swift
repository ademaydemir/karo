import AppKit
import ScreenCaptureKit

/// Captures still thumbnails of windows for the switcher.
///
/// Previews of the previous session are cached, so a reopened switcher shows them at once
/// while fresh ones are captured.
@MainActor
final class WindowPreviewProvider {
    /// Longest side of a thumbnail in points: enough for large switcher items and for the
    /// Snap Assist backdrop, which fills half a display, without looking soft.
    private static let maximumSize: CGFloat = 560

    private var cache: [CGWindowID: NSImage] = [:]

    func cachedPreview(for windowID: CGWindowID) -> NSImage? {
        cache[windowID]
    }

    /// Captures previews in the given order and reports each one as it arrives.
    /// - Parameter windows: Switcher item index and window ID pairs.
    func capturePreviews(for windows: [(item: Int, windowID: CGWindowID)], onPreview: (Int, NSImage) -> Void) async {
        guard ScreenRecordingPermission.isGranted,
              let content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false) else {
            return
        }
        let shareable = Dictionary(content.windows.map { ($0.windowID, $0) }, uniquingKeysWith: { first, _ in first })
        // Forget windows that no longer exist.
        cache = cache.filter { shareable[$0.key] != nil }

        let scale = NSScreen.main?.backingScaleFactor ?? 2
        for (item, windowID) in windows {
            guard !Task.isCancelled else { return }
            guard let window = shareable[windowID], window.frame.width > 0, window.frame.height > 0 else { continue }

            let fit = min(1, Self.maximumSize / max(window.frame.width, window.frame.height))
            let configuration = SCStreamConfiguration()
            configuration.width = Int(window.frame.width * fit * scale)
            configuration.height = Int(window.frame.height * fit * scale)
            configuration.showsCursor = false
            configuration.ignoreShadowsSingleWindow = true

            guard let image = try? await SCScreenshotManager.captureImage(
                contentFilter: SCContentFilter(desktopIndependentWindow: window),
                configuration: configuration
            ) else { continue }
            // The switcher may have closed (and reopened with other items) during the capture.
            guard !Task.isCancelled else { return }
            let preview = NSImage(cgImage: image, size: CGSize(width: window.frame.width * fit, height: window.frame.height * fit))
            cache[windowID] = preview
            onPreview(item, preview)
        }
    }
}
