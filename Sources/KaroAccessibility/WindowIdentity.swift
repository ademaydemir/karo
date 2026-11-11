import ApplicationServices

/// Identifies a window across separate Accessibility lookups.
///
/// Two `AXUIElement`s fetched at different times for the same window compare equal
/// (`CFEqual`), which avoids the private `_AXUIElementGetWindow` API for window IDs.
// `AXUIElement` is an immutable reference to a remote element and is safe to pass between threads.
public struct WindowIdentity: Hashable, @unchecked Sendable {
    let element: AXUIElement
}
