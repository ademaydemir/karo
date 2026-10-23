/// Orders windows for the window switcher.
public enum SwitcherOrdering {
    public struct Candidate<ID: Hashable> {
        public var id: ID
        /// Front-to-back position on screen; `nil` when the window is not on screen.
        public var stackIndex: Int?
        /// Minimized windows and windows of hidden apps go last.
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

    /// Apps by most recent activation; apps never activated keep their given order after them.
    public static func orderApplications<ID>(_ ids: [ID], recent: RecentList<ID>) -> [ID] {
        ids.enumerated()
            .sorted { lhs, rhs in
                (recent.rank(of: lhs.element) ?? .max, lhs.offset)
                    < (recent.rank(of: rhs.element) ?? .max, rhs.offset)
            }
            .map(\.element)
    }

    /// Brings items of the same group (an app's windows) together, keeping the order of
    /// first appearance between groups and the original order within each, so the result
    /// reads deck by deck exactly as the grid shows it.
    public static func grouped<Element, Group: Hashable>(_ elements: [Element], by group: (Element) -> Group) -> [Element] {
        var order: [Group] = []
        var members: [Group: [Element]] = [:]
        for element in elements {
            let key = group(element)
            if members[key] == nil { order.append(key) }
            members[key, default: []].append(element)
        }
        return order.flatMap { members[$0] ?? [] }
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
