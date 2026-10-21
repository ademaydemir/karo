#if DEBUG
import AppKit
import OSLog
@preconcurrency import ScreenCaptureKit
import SwiftUI
import UniformTypeIdentifiers

/// Development aid that records the README's animations with Karo's own Screen Recording
/// permission: `open build/Karo.app --args -CaptureReadmeAssets <dir>`.
///
/// Each welcome-guide scene is played once in a borderless window on GitHub's page color and
/// recorded as a looping animated PNG, in light and dark; a local script turns
/// them into GIFs. Only Karo's own window is recorded, never the rest of the screen.
/// `done.txt` appears in the directory when finished.
@MainActor
enum ReadmeCapture {
    private static let logger = Logger(subsystem: "dev.ademaydemir.Karo", category: "readme-capture")

    static func run(to directory: URL) async {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            for theme in Theme.allCases {
                for feature in DesktopScene.Feature.allCases {
                    let url = directory.appending(path: "scene-\(String(describing: feature))-\(theme.rawValue).png")
                    try await recordScene(feature, theme: theme, to: url)
                    logger.info("Wrote \(url.lastPathComponent, privacy: .public)")
                }
            }
            logger.info("README capture finished")
        } catch {
            logger.error("README capture failed: \(String(describing: error), privacy: .public)")
            try? "\(error)".write(to: directory.appending(path: "error.txt"), atomically: true, encoding: .utf8)
        }
        try? "done".write(to: directory.appending(path: "done.txt"), atomically: true, encoding: .utf8)
    }

    // MARK: - Scenes

    /// GitHub's page colors, so the scene's rounded corners blend into the README.
    private enum Theme: String, CaseIterable {
        case light, dark

        var appearance: NSAppearance? {
            NSAppearance(named: self == .light ? .aqua : .darkAqua)
        }

        var pageColor: Color {
            self == .light ? Color(red: 1, green: 1, blue: 1) : Color(red: 13 / 255, green: 17 / 255, blue: 23 / 255)
        }
    }

    @Observable
    final class SceneState {
        var phase = 0
    }

    private struct SceneHost: View {
        let feature: DesktopScene.Feature
        let state: SceneState
        let pageColor: Color

        var body: some View {
            DesktopScene(feature: feature, phase: state.phase)
                // The scene's wallpaper is translucent over the welcome window's background.
                .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(12)
                .background(pageColor)
                // The system blue rather than the user's own accent color.
                .tint(.blue)
        }
    }

    /// Plays the feature's phases once, ending with the return to the first phase, so the
    /// recording loops without a jump.
    private static func recordScene(_ feature: DesktopScene.Feature, theme: Theme, to url: URL) async throws {
        let state = SceneState()
        let host = NSHostingView(rootView: SceneHost(feature: feature, state: state, pageColor: theme.pageColor))
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: host.fittingSize), styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = host
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.appearance = theme.appearance
        window.level = .floating
        window.isReleasedWhenClosed = false
        if let screen = NSScreen.main {
            window.setFrameOrigin(CGPoint(x: screen.frame.midX - window.frame.width / 2, y: screen.frame.midY - window.frame.height / 2))
        }
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }
        try await Task.sleep(for: .milliseconds(500))

        let recorder = try await WindowRecorder(windowID: CGWindowID(window.windowNumber), scale: window.backingScaleFactor)
        try await recorder.start()
        for phase in 0..<DesktopScene.phaseCount {
            state.phase = phase
            try await Task.sleep(for: DesktopScene.duration(of: feature, phase: phase))
        }
        state.phase = 0
        // Long enough for the spring back to the first phase to settle.
        try await Task.sleep(for: .milliseconds(700))
        let frames = try await recorder.stop()
        try writeAnimatedPNG(frames, to: url)
    }

    // MARK: - Writing

    private static func writeAnimatedPNG(_ frames: [WindowRecorder.Frame], to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, frames.count, nil) else {
            throw CaptureError.cannotWrite(url)
        }
        let fileProperties = [kCGImagePropertyPNGDictionary: [kCGImagePropertyAPNGLoopCount: 0]]
        CGImageDestinationSetProperties(destination, fileProperties as CFDictionary)
        for frame in frames {
            // ImageIO raises short delays when they are read back; the unclamped one keeps them.
            let properties = [kCGImagePropertyPNGDictionary: [
                kCGImagePropertyAPNGDelayTime: frame.duration,
                kCGImagePropertyAPNGUnclampedDelayTime: frame.duration,
            ]]
            CGImageDestinationAddImage(destination, frame.image, properties as CFDictionary)
        }
        guard CGImageDestinationFinalize(destination) else { throw CaptureError.cannotWrite(url) }
    }

    enum CaptureError: Error {
        case windowNotFound
        case cannotWrite(URL)
    }
}

/// Records one window with ScreenCaptureKit. Frames only arrive when the window changes,
/// so each frame lasts until the next one: still moments become a single long frame.
private final class WindowRecorder: NSObject, SCStreamOutput, @unchecked Sendable {
    struct Frame {
        let image: CGImage
        let duration: Double
    }

    private let stream: SCStream
    private let queue = DispatchQueue(label: "dev.ademaydemir.Karo.readme-capture")
    /// Capture times on the host clock. Only touched on `queue`.
    private var captured: [(image: CGImage, time: Double)] = []

    @MainActor
    init(windowID: CGWindowID, scale: CGFloat) async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let window = content.windows.first(where: { $0.windowID == windowID }) else {
            throw ReadmeCapture.CaptureError.windowNotFound
        }
        let configuration = SCStreamConfiguration()
        configuration.width = Int(window.frame.width * scale)
        configuration.height = Int(window.frame.height * scale)
        // Well above the GIF's 25 frames a second, so every GIF frame has a fresh picture.
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        configuration.queueDepth = 8
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.showsCursor = false
        configuration.ignoreShadowsSingleWindow = true
        stream = SCStream(filter: SCContentFilter(desktopIndependentWindow: window), configuration: configuration, delegate: nil)
        super.init()
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
    }

    func start() async throws {
        try await stream.startCapture()
    }

    func stop() async throws -> [Frame] {
        let end = CMClockGetTime(CMClockGetHostTimeClock()).seconds
        try await stream.stopCapture()
        return queue.sync {
            captured.enumerated().map { index, frame in
                let next = index + 1 < captured.count ? captured[index + 1].time : end
                // Frames can be a sixtieth of a second apart; the GIF step merges them.
                return Frame(image: frame.image, duration: next - frame.time)
            }
        }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        // Idle and blank buffers carry no new picture.
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let rawStatus = attachments.first?[.status] as? Int,
              SCFrameStatus(rawValue: rawStatus) == .complete,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
              let image = Self.copyImage(of: pixelBuffer) else { return }
        // When the frame was captured, not when it got here: a late frame must not stretch time.
        captured.append((image, sampleBuffer.presentationTimeStamp.seconds))
    }

    /// A plain copy of the pixels; converting through Core Image is too slow to keep up.
    private static func copyImage(of pixelBuffer: CVPixelBuffer) -> CGImage? {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        guard let provider = CGDataProvider(data: Data(bytes: base, count: bytesPerRow * height) as CFData) else { return nil }
        return CGImage(
            width: CVPixelBufferGetWidth(pixelBuffer), height: height,
            bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: bytesPerRow,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        )
    }
}
#endif
