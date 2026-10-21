import ApplicationServices

public enum AccessibilityError: Error, Equatable {
    case permissionDenied
    case noFrontmostApplication
    case noFocusedWindow
    /// No standard, non-full-screen window of another app under the point.
    case noWindowAtPosition
    case unexpectedValue(attribute: String)
    case failure(attribute: String, code: AXError)
}
