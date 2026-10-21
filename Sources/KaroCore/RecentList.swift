/// Most-recently-used ordering of items, e.g. windows by last focus.
public struct RecentList<ID: Hashable> {
    /// Most recent first.
    public private(set) var items: [ID] = []
    private let capacity: Int

    public init(capacity: Int = 200) {
        self.capacity = capacity
    }

    public mutating func touch(_ id: ID) {
        items.removeAll { $0 == id }
        items.insert(id, at: 0)
        if items.count > capacity {
            items.removeLast()
        }
    }

    public func rank(of id: ID) -> Int? {
        items.firstIndex(of: id)
    }
}
