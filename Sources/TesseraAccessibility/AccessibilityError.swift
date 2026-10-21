import ApplicationServices

public enum AccessibilityError: Error, Equatable {
    case permissionDenied
    case noFrontmostApplication
    case noFocusedWindow
    case unexpectedValue(attribute: String)
    case failure(attribute: String, code: AXError)
}
