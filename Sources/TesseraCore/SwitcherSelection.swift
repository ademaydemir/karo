/// The highlighted item of an open window switcher.
///
/// Starts on the current window (index 0); every Tab press, including the one that opens
/// the switcher, moves the selection, so ⌥Tab lands on the previous window and ⌥⇧Tab on
/// the least recent one. Selection wraps around at both ends.
public struct SwitcherSelection: Equatable, Sendable {
    public let count: Int
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

    public mutating func select(_ index: Int) {
        guard (0..<count).contains(index) else { return }
        self.index = index
    }
}
