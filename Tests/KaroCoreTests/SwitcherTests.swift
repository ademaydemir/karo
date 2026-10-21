import Testing
@testable import KaroCore

struct RecentListTests {
    @Test func touchMovesItemToFront() {
        var list = RecentList<String>()
        list.touch("a")
        list.touch("b")
        list.touch("a")
        #expect(list.items == ["a", "b"])
        #expect(list.rank(of: "b") == 1)
        #expect(list.rank(of: "c") == nil)
    }

    @Test func dropsLeastRecentBeyondCapacity() {
        var list = RecentList<Int>(capacity: 2)
        list.touch(1)
        list.touch(2)
        list.touch(3)
        #expect(list.items == [3, 2])
    }
}

struct SwitcherOrderingTests {
    private typealias Candidate = SwitcherOrdering.Candidate<String>

    @Test func recentWindowsComeFirstInRecencyOrder() {
        var recent = RecentList<String>()
        recent.touch("mail")
        recent.touch("editor") // focused now
        let candidates = [
            Candidate(id: "mail", stackIndex: 1, isBackgrounded: false),
            Candidate(id: "editor", stackIndex: 0, isBackgrounded: false),
        ]
        #expect(SwitcherOrdering.order(candidates, recent: recent) == ["editor", "mail"])
    }

    @Test func unknownWindowsFollowByStackingOrder() {
        var recent = RecentList<String>()
        recent.touch("editor")
        let candidates = [
            Candidate(id: "back", stackIndex: 5, isBackgrounded: false),
            Candidate(id: "front", stackIndex: 2, isBackgrounded: false),
            Candidate(id: "editor", stackIndex: 0, isBackgrounded: false),
        ]
        #expect(SwitcherOrdering.order(candidates, recent: recent) == ["editor", "front", "back"])
    }

    @Test func backgroundedWindowsGoLastEvenIfRecent() {
        var recent = RecentList<String>()
        recent.touch("other")
        recent.touch("minimized")
        let candidates = [
            Candidate(id: "minimized", stackIndex: nil, isBackgrounded: true),
            Candidate(id: "other", stackIndex: 0, isBackgrounded: false),
        ]
        #expect(SwitcherOrdering.order(candidates, recent: recent) == ["other", "minimized"])
    }

    @Test func groupsAppWindowsTogetherInOrderOfFirstAppearance() {
        // Most recent first: Safari, Mail, Safari, Terminal, Safari.
        let windows = [("safari", 1), ("mail", 2), ("safari", 3), ("terminal", 4), ("safari", 5)]
        let grouped = SwitcherOrdering.grouped(windows) { $0.0 }
        #expect(grouped.map(\.1) == [1, 3, 5, 2, 4])
    }

    @Test func keepsInputOrderAsLastTieBreaker() {
        let candidates = [
            Candidate(id: "first", stackIndex: nil, isBackgrounded: true),
            Candidate(id: "second", stackIndex: nil, isBackgrounded: true),
        ]
        #expect(SwitcherOrdering.order(candidates, recent: RecentList()) == ["first", "second"])
    }
}

struct SwitcherSelectionTests {
    @Test func firstForwardPressSelectsPreviousWindow() {
        var selection = SwitcherSelection(count: 4)
        selection.moveForward()
        #expect(selection.index == 1)
    }

    @Test func firstBackwardPressSelectsLeastRecentWindow() {
        var selection = SwitcherSelection(count: 4)
        selection.moveBackward()
        #expect(selection.index == 3)
    }

    @Test func wrapsAroundForward() {
        var selection = SwitcherSelection(count: 2)
        selection.moveForward()
        selection.moveForward()
        #expect(selection.index == 0)
    }

    @Test func singleWindowStaysSelected() {
        var selection = SwitcherSelection(count: 1)
        selection.moveForward()
        #expect(selection.index == 0)
    }

    @Test func emptySelectionDoesNotCrash() {
        var selection = SwitcherSelection(count: 0)
        selection.moveForward()
        selection.moveBackward()
        #expect(selection.index == 0)
    }

    @Test func selectIgnoresOutOfRangeIndex() {
        var selection = SwitcherSelection(count: 3)
        selection.select(2)
        selection.select(7)
        #expect(selection.index == 2)
    }
}
