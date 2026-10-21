import ApplicationServices

/// Identifies a window across separate Accessibility lookups.
///
/// Two `AXUIElement`s fetched at different times for the same window compare equal
/// (`CFEqual`), which avoids the private `_AXUIElementGetWindow` API for window IDs.
public struct WindowIdentity: Hashable {
    let element: AXUIElement
}
