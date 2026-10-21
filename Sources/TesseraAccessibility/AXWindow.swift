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
    /// Not exported as a constant by the SDK.
    private static let fullScreenAttribute = "AXFullScreen"

    private let element: AXUIElement
    private let application: AXUIElement
    public let processIdentifier: pid_t

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
            // Timeouts are per element; child elements would otherwise use the ~6 s default.
            AXUIElementSetMessagingTimeout(window, messagingTimeout)
            return AXWindow(element: window, application: application, processIdentifier: app.processIdentifier)
        } catch {
            throw AccessibilityError.noFocusedWindow
        }
    }

    /// The standard window under a screen point, e.g. the window the user clicked.
    ///
    /// Panels, sheets, the desktop and full-screen windows are rejected: they should not snap.
    public static func window(at point: CGPoint) throws -> AXWindow {
        guard AccessibilityPermission.isGranted else { throw AccessibilityError.permissionDenied }
        var hit: AXUIElement?
        let result = AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(), Float(point.x), Float(point.y), &hit)
        guard result == .success, let hit else { throw AccessibilityError.noWindowAtPosition }

        var processIdentifier: pid_t = 0
        guard AXUIElementGetPid(hit, &processIdentifier) == .success,
              processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            throw AccessibilityError.noWindowAtPosition
        }
        let application = AXUIElementCreateApplication(processIdentifier)
        AXUIElementSetMessagingTimeout(application, messagingTimeout)
        AXUIElementSetMessagingTimeout(hit, messagingTimeout)

        let window: AXUIElement
        if (try? hit.value(of: kAXRoleAttribute)) as? String == kAXWindowRole {
            window = hit
        } else if let parent = try? hit.element(of: kAXWindowAttribute) {
            window = parent
        } else {
            throw AccessibilityError.noWindowAtPosition
        }
        AXUIElementSetMessagingTimeout(window, messagingTimeout)
        guard (try? window.value(of: kAXSubroleAttribute)) as? String == kAXStandardWindowSubrole,
              (try? window.value(of: fullScreenAttribute)) as? Bool != true else {
            throw AccessibilityError.noWindowAtPosition
        }
        return AXWindow(element: window, application: application, processIdentifier: processIdentifier)
    }

    /// Standard windows of an app, including minimized ones.
    ///
    /// Most apps only report windows on the current Space. A short timeout keeps a hung
    /// app from stalling the window switcher.
    public static func windows(ofApplication processIdentifier: pid_t, timeout: Float = 0.25) -> [AXWindow] {
        let application = AXUIElementCreateApplication(processIdentifier)
        AXUIElementSetMessagingTimeout(application, timeout)
        guard let value = try? application.value(of: kAXWindowsAttribute),
              let elements = value as? [AXUIElement] else { return [] }
        // Timeouts are per element; child elements would otherwise use the ~6 s system default.
        elements.forEach { AXUIElementSetMessagingTimeout($0, timeout) }
        return elements
            .filter { (try? $0.value(of: kAXSubroleAttribute)) as? String == kAXStandardWindowSubrole }
            .map { AXWindow(element: $0, application: application, processIdentifier: processIdentifier) }
    }

    public var title: String {
        ((try? element.value(of: kAXTitleAttribute)) as? String) ?? ""
    }

    public var isMinimized: Bool {
        ((try? element.value(of: kAXMinimizedAttribute)) as? Bool) ?? false
    }

    /// Makes this window the active window: un-minimizes it, raises it and brings its app
    /// to the front.
    ///
    /// The app is activated through `kAXFrontmostAttribute` because since macOS 14
    /// `NSRunningApplication.activate()` is cooperative and is ignored when requested by a
    /// background app such as Tessera.
    public func bringToFront() throws {
        if isMinimized {
            try element.setValue(kCFBooleanFalse, of: kAXMinimizedAttribute)
        }
        raise()
        try application.setValue(kCFBooleanTrue, of: kAXFrontmostAttribute)
    }

    /// Puts the window above the app's other windows without activating the app.
    public func raise() {
        AXUIElementPerformAction(element, kAXRaiseAction as CFString)
        try? element.setValue(kCFBooleanTrue, of: kAXMainAttribute)
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
