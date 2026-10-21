/// The highlighted item of an open window switcher.
///
/// Starts on the current window (index 0); every Tab press, including the one that opens
/// the switcher, moves the selection, so ⌥Tab lands on the previous window and ⌥⇧Tab on
/// the least recent one. Selection wraps around at both ends.
public struct SwitcherSelection: Equatable, Sendable {
    public private(set) var count: Int
    public private(set) var index = 0

    public init(count: Int) {
        self.count = count
    }

    public mutating func moveForward() {
        guard count > 0 else { return }
        index = (index + 1) % count
    }

    public mutating func moveBackward() {
        guard count > 0 else { return }
        index = (index - 1 + count) % count
    }

    /// Drops an item (e.g. a window closed from the switcher). The selection stays on the same
    /// item, or moves to the one that took the removed item's place.
    public mutating func remove(at removed: Int) {
        guard (0..<count).contains(removed) else { return }
        count -= 1
        if removed < index {
            index -= 1
        } else if index >= count {
            index = max(count - 1, 0)
        }
    }

    public mutating func select(_ index: Int) {
        guard (0..<count).contains(index) else { return }
        self.index = index
    }
}
