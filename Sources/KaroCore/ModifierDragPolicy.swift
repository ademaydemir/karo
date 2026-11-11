/// Decides which mouse events the modifier-drag gesture needs to see. Everything else passes
/// straight through the event tap, so clicks never wait for Karo's main thread.
public enum ModifierDragPolicy {
    /// - Parameters:
    ///   - isPress: A mouse button went down (as opposed to a drag or release).
    ///   - held: Modifiers held during the event.
    ///   - configured: The combination that starts a gesture; `nil` when the feature is off.
    ///   - isGestureActive: A gesture is under way, so its drags and release belong to it.
    public static func isRelevant(isPress: Bool, held: KeyboardShortcut.Modifiers, configured: KeyboardShortcut.Modifiers?, isGestureActive: Bool) -> Bool {
        isGestureActive || (isPress && configured != nil && held == configured)
    }
}
