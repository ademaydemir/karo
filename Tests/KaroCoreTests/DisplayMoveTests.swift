import CoreGraphics
import Testing
@testable import KaroCore

struct DisplayOrderingTests {
    // Laptop in the middle, one display on each side, indices deliberately out of order.
    private let displays = [
        CGRect(x: 0, y: 0, width: 1440, height: 900),
        CGRect(x: 1440, y: -180, width: 1920, height: 1080),
        CGRect(x: -1920, y: -180, width: 1920, height: 1080),
    ]

    @Test func nextGoesRightAndWraps() {
        #expect(DisplayOrdering.index(adjacentTo: 2, among: displays, backward: false) == 0)
        #expect(DisplayOrdering.index(adjacentTo: 0, among: displays, backward: false) == 1)
        #expect(DisplayOrdering.index(adjacentTo: 1, among: displays, backward: false) == 2)
    }

    @Test func previousGoesLeftAndWraps() {
        #expect(DisplayOrdering.index(adjacentTo: 0, among: displays, backward: true) == 2)
        #expect(DisplayOrdering.index(adjacentTo: 2, among: displays, backward: true) == 1)
    }

    @Test func returnsNilWithSingleDisplay() {
        #expect(DisplayOrdering.index(adjacentTo: 0, among: [displays[0]], backward: false) == nil)
    }
}

struct DisplayMoveLayoutTests {
    private let laptop = CGRect(x: 0, y: 25, width: 1440, height: 875)
    private let external = CGRect(x: 1440, y: -155, width: 2560, height: 1415)

    @Test func scaledKeepsLeftHalfALeftHalf() {
        let leftHalf = CGRect(x: 0, y: 25, width: 720, height: 875)
        #expect(LayoutCalculator.scaled(leftHalf, from: laptop, to: external) == CGRect(x: 1440, y: -155, width: 1280, height: 1415))
    }

    @Test func translatedKeepsSizeAndRelativeCenter() {
        let floating = CGRect(x: 320, y: 162, width: 800, height: 600) // centered on the laptop
        let moved = LayoutCalculator.translated(floating, from: laptop, to: external)
        #expect(moved.size == floating.size)
        #expect(moved.midX == external.midX)
    }

    @Test func translatedShrinksWindowLargerThanDestination() {
        let big = CGRect(x: 1440, y: -155, width: 2400, height: 1400)
        let moved = LayoutCalculator.translated(big, from: external, to: laptop)
        #expect(moved == laptop)
    }
}

struct FrameHistoryPlacementStateTests {
    @Test func reportsWhetherWindowIsStillPlaced() {
        var history = FrameHistory<Int>()
        let placed = CGRect(x: 0, y: 25, width: 720, height: 875)
        history.recordPlacement(of: 1, from: CGRect(x: 100, y: 100, width: 800, height: 600), to: placed)
        #expect(history.isPlaced(1, at: placed))
        #expect(!history.isPlaced(1, at: placed.offsetBy(dx: 50, dy: 0)))
        #expect(!history.isPlaced(2, at: placed))
    }
}
