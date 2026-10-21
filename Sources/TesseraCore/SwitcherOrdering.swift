/// Orders windows for the window switcher.
public enum SwitcherOrdering {
    public struct Candidate<ID: Hashable> {
        public var id: ID
        /// Front-to-back position on screen; `nil` when the window is not on screen.
        public var stackIndex: Int?
        /// Minimized windows and windows of hidden apps go last, like on Windows.
        public var isBackgrounded: Bool

        public init(id: ID, stackIndex: Int?, isBackgrounded: Bool) {
            self.id = id
            self.stackIndex = stackIndex
            self.isBackgrounded = isBackgrounded
        }
    }

    /// Visible windows before backgrounded ones; within each group, recently focused windows
    /// first, then windows never focused since launch by their on-screen stacking order.
    public static func order<ID>(_ candidates: [Candidate<ID>], recent: RecentList<ID>) -> [ID] {
        candidates.enumerated()
            .sorted { lhs, rhs in
                key(lhs.element, recent: recent, position: lhs.offset)
                    < key(rhs.element, recent: recent, position: rhs.offset)
            }
            .map(\.element.id)
    }

    private struct SortKey: Comparable {
        let isBackgrounded: Int
        let recency: Int
        let stackIndex: Int
        let position: Int

        static func < (lhs: SortKey, rhs: SortKey) -> Bool {
            (lhs.isBackgrounded, lhs.recency, lhs.stackIndex, lhs.position)
                < (rhs.isBackgrounded, rhs.recency, rhs.stackIndex, rhs.position)
        }
    }

    private static func key<ID>(_ candidate: Candidate<ID>, recent: RecentList<ID>, position: Int) -> SortKey {
        SortKey(
            isBackgrounded: candidate.isBackgrounded ? 1 : 0,
            recency: recent.rank(of: candidate.id) ?? .max,
            stackIndex: candidate.stackIndex ?? .max,
            position: position
        )
    }
}
