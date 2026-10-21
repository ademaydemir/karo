import CoreGraphics

/// Remembers where windows were before Tessera placed them, for the `.restore` action.
public struct FrameHistory<WindowID: Hashable> {
    private struct Entry {
        var original: CGRect
        var applied: CGRect
    }

    /// Apps report frames that can be off by a fraction of a point from what was set.
    private static var tolerance: CGFloat { 1 }

    private var entries: [WindowID: Entry] = [:]
    /// Least recently placed first; bounds memory for windows that closed without a restore.
    private var order: [WindowID] = []
    private let capacity: Int

    public init(capacity: Int = 50) {
        self.capacity = capacity
    }

    /// Records a placement Tessera just performed.
    /// - Parameters:
    ///   - previous: The window's frame before the placement.
    ///   - applied: The frame the window actually ended up with.
    public mutating func recordPlacement(of window: WindowID, from previous: CGRect, to applied: CGRect) {
        var original = previous
        // A window still where Tessera last put it is being re-placed (e.g. left half, then
        // maximize): restore should go back to before the first placement. If the user moved
        // it in between, their frame becomes the new restore point.
        if let entry = entries[window], Self.isApproximatelyEqual(entry.applied, previous) {
            original = entry.original
        }
        entries[window] = Entry(original: original, applied: applied)
        order.removeAll { $0 == window }
        order.append(window)
        if order.count > capacity {
            entries.removeValue(forKey: order.removeFirst())
        }
    }

    /// Whether the window is still where Tessera last placed it.
    public func isPlaced(_ window: WindowID, at frame: CGRect) -> Bool {
        guard let entry = entries[window] else { return false }
        return Self.isApproximatelyEqual(entry.applied, frame)
    }

    /// Returns the frame to restore and forgets the window.
    public mutating func takeRestoreFrame(for window: WindowID) -> CGRect? {
        guard let entry = entries.removeValue(forKey: window) else { return nil }
        order.removeAll { $0 == window }
        return entry.original
    }

    /// Returns the frame to restore when the user starts dragging a window Tessera placed.
    ///
    /// By the time a drag is recognised the window has already moved, so only the size is
    /// compared. A different size means the user resized it since, and nothing is restored.
    public mutating func takeRestoreFrame(for window: WindowID, ifSizeMatches currentSize: CGSize) -> CGRect? {
        guard let entry = entries[window],
              abs(entry.applied.width - currentSize.width) <= Self.tolerance,
              abs(entry.applied.height - currentSize.height) <= Self.tolerance else { return nil }
        return takeRestoreFrame(for: window)
    }

    private static func isApproximatelyEqual(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) <= tolerance && abs(a.minY - b.minY) <= tolerance
            && abs(a.width - b.width) <= tolerance && abs(a.height - b.height) <= tolerance
    }
}
