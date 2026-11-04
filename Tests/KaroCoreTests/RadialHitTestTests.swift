import CoreGraphics
import Testing
@testable import KaroCore

struct RadialHitTestTests {
    private let center = CGPoint(x: 100, y: 100)

    private func index(_ x: CGFloat, _ y: CGFloat, count: Int = 8) -> Int? {
        RadialHitTest.index(of: CGPoint(x: x, y: y), center: center, innerRadius: 46, outerRadius: 100, count: count)
    }

    @Test func cardinalPoints() {
        #expect(index(100, 20) == 0)
        #expect(index(180, 100) == 2)
        #expect(index(100, 180) == 4)
        #expect(index(20, 100) == 6)
    }

    @Test func diagonals() {
        #expect(index(45, 45) == 7)
        #expect(index(155, 45) == 1)
        #expect(index(155, 155) == 3)
    }

    @Test func outsideTheRingIsNil() {
        #expect(index(100, 100) == nil)
        #expect(index(100, 210) == nil)
    }

    @Test func emptyRingIsNil() {
        #expect(index(100, 20, count: 0) == nil)
    }

    @Test func threeSlices() {
        #expect(index(100, 20, count: 3) == 0)
        // 30 degrees clockwise from 3 o'clock is 120 degrees from the top, the middle of slice 1.
        let angle = 30.0 * .pi / 180
        #expect(index(100 + 80 * cos(angle), 100 + 80 * sin(angle), count: 3) == 1)
    }
}
