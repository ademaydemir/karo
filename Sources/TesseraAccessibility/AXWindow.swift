import AppKit
import ApplicationServices

/// A window of another application, read and moved through the Accessibility API.
///
/// Frames are in Accessibility coordinates (top-left origin of the primary display).
@MainActor
public struct AXWindow {
    /// Unresponsive apps would otherwise block the main thread for the system default of ~6 s.
    private static let messagingTimeout: Float = 1
    /// Undocumented attribute set by assistive tools (VoiceOver, some window managers); while it
    /// is on, apps animate frame changes, which makes successive size/position writes unreliable.
    private static let enhancedUserInterfaceAttribute = "AXEnhancedUserInterface"

    private let element: AXUIElement
    private let application: AXUIElement

    public var identity: WindowIdentity {
        WindowIdentity(element: element)
    }

    /// The focused window of the frontmost application.
    public static func focused() throws -> AXWindow {
        guard AccessibilityPermission.isGranted else { throw AccessibilityError.permissionDenied }
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            throw AccessibilityError.noFrontmostApplication
        }
        let application = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(application, messagingTimeout)
        do {
            let window = try application.element(of: kAXFocusedWindowAttribute)
            return AXWindow(element: window, application: application)
        } catch {
            throw AccessibilityError.noFocusedWindow
        }
    }

    public func frame() throws -> CGRect {
        CGRect(
            origin: try element.point(of: kAXPositionAttribute),
            size: try element.size(of: kAXSizeAttribute)
        )
    }

    /// Moves and resizes the window. Non-resizable windows are only moved.
    ///
    /// The app may enforce a minimum size, so read `frame()` afterwards for the actual result.
    public func setFrame(_ frame: CGRect) throws {
        let isResizable = element.isSettable(kAXSizeAttribute)
        try withEnhancedUserInterfaceDisabled {
            // Size first so the window is not clamped against its old display edge when it
            // moves; size again because some apps cap the size by the space left at the
            // old position.
            if isResizable { try element.setSize(frame.size, of: kAXSizeAttribute) }
            try element.setPoint(frame.origin, of: kAXPositionAttribute)
            if isResizable { try element.setSize(frame.size, of: kAXSizeAttribute) }
        }
    }

    public func setPosition(_ origin: CGPoint) throws {
        try element.setPoint(origin, of: kAXPositionAttribute)
    }

    private func withEnhancedUserInterfaceDisabled(_ body: () throws -> Void) throws {
        let attribute = Self.enhancedUserInterfaceAttribute
        // Most apps do not expose the attribute at all; treat that as "off".
        let wasEnabled = (try? application.value(of: attribute)) as? Bool == true
        guard wasEnabled else { return try body() }

        try? application.setValue(kCFBooleanFalse, of: attribute)
        defer { try? application.setValue(kCFBooleanTrue, of: attribute) }
        try body()
    }
}
