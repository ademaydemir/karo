import CoreGraphics
import Testing
@testable import KaroCore

struct LayoutMatcherTests {
    private let visible = CGRect(x: 0, y: 25, width: 1440, height: 875)

    @Test func matchesAnExactHalf() {
        let frame = CGRect(x: 0, y: 25, width: 720, height: 875)
        #expect(LayoutMatcher.action(matching: frame, in: visible, gap: 0, tolerance: 40) == .leftHalf)
    }

    @Test func matchesAFrameSlightlyNarrower() {
        let frame = CGRect(x: 0, y: 25, width: 700, height: 875)
        #expect(LayoutMatcher.action(matching: frame, in: visible, gap: 0, tolerance: 40) == .leftHalf)
    }

    @Test func rejectsAFrameInNoPlacement() {
        let frame = CGRect(x: 130, y: 200, width: 500, height: 333)
        #expect(LayoutMatcher.action(matching: frame, in: visible, gap: 0, tolerance: 40) == nil)
    }

    @Test func matchesMaximize() {
        #expect(LayoutMatcher.action(matching: visible, in: visible, gap: 0, tolerance: 40) == .maximize)
    }

    @Test func isWithinAcceptsTheSameFrameAtZeroTolerance() {
        #expect(LayoutMatcher.isWithin(visible, of: visible, tolerance: 0))
    }

    @Test func isWithinAcceptsEachComponentAtTheToleranceEdge() {
        let target = CGRect(x: 10, y: 20, width: 300, height: 400)
        let frame = CGRect(x: 10 - 2, y: 20 + 2, width: 300 + 2, height: 400 - 2)
        #expect(LayoutMatcher.isWithin(frame, of: target, tolerance: 2))
    }

    @Test func isWithinRejectsAComponentPastTheTolerance() {
        let target = CGRect(x: 10, y: 20, width: 300, height: 400)
        let shiftedX = CGRect(x: 10 + 2.5, y: 20, width: 300, height: 400)
        let grownHeight = CGRect(x: 10, y: 20, width: 300, height: 400 + 2.5)
        #expect(!LayoutMatcher.isWithin(shiftedX, of: target, tolerance: 2))
        #expect(!LayoutMatcher.isWithin(grownHeight, of: target, tolerance: 2))
    }
}
