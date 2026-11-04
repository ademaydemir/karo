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
}
