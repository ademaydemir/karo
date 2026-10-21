import Foundation
import Testing
@testable import TesseraCore

struct SwitcherQuickActionTests {
    /// Everything that is registered while the switcher is open, plus the permanent ⌥Tab keys.
    private var sessionShortcuts: [KeyboardShortcut] {
        SwitcherQuickAction.allCases.map(\.shortcut) + [
            DefaultShortcuts.switchWindowsForward, DefaultShortcuts.switchWindowsBackward,
            DefaultShortcuts.switcherNext, DefaultShortcuts.switcherPrevious,
            DefaultShortcuts.switcherChoose, DefaultShortcuts.switcherCancel,
            DefaultShortcuts.switcherLarger, DefaultShortcuts.switcherSmaller,
        ]
    }

    @Test func sessionShortcutsAreUnique() {
        #expect(Set(sessionShortcuts).count == sessionShortcuts.count)
    }

    @Test func sessionShortcutsAllHoldOption() {
        #expect(sessionShortcuts.allSatisfy { $0.modifiers.contains(.option) })
    }

    @Test func placementActionsMapToWindowActions() {
        #expect(SwitcherQuickAction.leftHalf.windowAction == .leftHalf)
        #expect(SwitcherQuickAction.nextDisplay.windowAction == .nextDisplay)
        #expect(SwitcherQuickAction.close.windowAction == nil)
    }
}

struct SwitcherSizeTests {
    @Test func stepsBetweenSizesAndStopsAtTheEnds() {
        #expect(SwitcherSize.small.larger == .medium)
        #expect(SwitcherSize.large.larger == .large)
        #expect(SwitcherSize.large.smaller == .medium)
        #expect(SwitcherSize.small.smaller == .small)
    }

    @Test func styleDefaultsToGridAndRoundTrips() throws {
        var settings = TesseraSettings()
        #expect(settings.switcherStyle == .grid)
        settings.switcherStyle = .coverFlow
        let data = try JSONEncoder().encode(settings)
        #expect(try JSONDecoder().decode(TesseraSettings.self, from: data).switcherStyle == .coverFlow)
    }

    @Test func settingsFallBackToDefaultForUnknownSize() throws {
        let decoded = try JSONDecoder().decode(TesseraSettings.self, from: Data(#"{"switcherSize": "huge"}"#.utf8))
        #expect(decoded.switcherSize == .medium)
    }
}

struct SwitcherSelectionRemovalTests {
    @Test func removingBeforeSelectionKeepsSameItem() {
        var selection = SwitcherSelection(count: 4)
        selection.select(2)
        selection.remove(at: 0)
        #expect(selection.index == 1)
        #expect(selection.count == 3)
    }

    @Test func removingSelectedItemSelectsTheNextOne() {
        var selection = SwitcherSelection(count: 4)
        selection.select(1)
        selection.remove(at: 1)
        #expect(selection.index == 1)
    }

    @Test func removingLastSelectedItemSelectsNewLast() {
        var selection = SwitcherSelection(count: 3)
        selection.select(2)
        selection.remove(at: 2)
        #expect(selection.index == 1)
    }

    @Test func removingOnlyItemLeavesEmptySelection() {
        var selection = SwitcherSelection(count: 1)
        selection.remove(at: 0)
        #expect(selection.count == 0)
        #expect(selection.index == 0)
    }

    @Test func ignoresOutOfRangeRemoval() {
        var selection = SwitcherSelection(count: 2)
        selection.remove(at: 5)
        #expect(selection.count == 2)
    }
}
