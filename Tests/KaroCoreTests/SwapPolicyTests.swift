import CoreGraphics
import Testing
@testable import KaroCore

struct SwapPolicyTests {
    private let left = CGRect(x: 0, y: 25, width: 1440, height: 875)
    private let right = CGRect(x: 1440, y: 0, width: 1920, height: 1080)
    private var displays: [CGRect] { [left, right] }

    private var leftHalf: CGRect { CGRect(x: 0, y: 25, width: 720, height: 875) }
    private var rightHalfOfLeft: CGRect { CGRect(x: 720, y: 25, width: 720, height: 875) }
    private var rightDisplayLeftHalf: CGRect { CGRect(x: 1440, y: 0, width: 960, height: 1080) }

    private func allows(source: CGRect, target: CGRect, cursor: CGPoint) -> Bool {
        SwapPolicy.allowsSwap(sourceSlot: source, targetFrame: target, cursor: cursor, visibleFrames: displays)
    }

    @Test func swapsHalvesOnTheSameDisplayWithCursorInTheMiddle() {
        #expect(allows(source: leftHalf, target: rightHalfOfLeft, cursor: CGPoint(x: 1080, y: 460)))
    }

    @Test func rejectsTargetOnAnotherDisplay() {
        #expect(!allows(source: leftHalf, target: right, cursor: CGPoint(x: 2400, y: 540)))
        #expect(!allows(source: leftHalf, target: rightDisplayLeftHalf, cursor: CGPoint(x: 1920, y: 540)))
    }

    @Test func rejectsTargetThatFillsItsDisplay() {
        #expect(!allows(source: rightDisplayLeftHalf, target: right, cursor: CGPoint(x: 2400, y: 540)))
    }

    @Test func rejectsCursorInTheOuterMargin() {
        // Target spans x 720...1440; the middle 60% is 864...1296.
        #expect(!allows(source: leftHalf, target: rightHalfOfLeft, cursor: CGPoint(x: 730, y: 460)))
        #expect(!allows(source: leftHalf, target: rightHalfOfLeft, cursor: CGPoint(x: 1080, y: 40)))
    }

    @Test func fillThresholdSitsAtNinetyPercentOfTheDisplayArea() {
        let nearlyFull = CGRect(x: 1440, y: 0, width: 1920 * 0.94, height: 1080 * 0.94) // 88% of the area
        let almostFull = CGRect(x: 1440, y: 0, width: 1920 * 0.96, height: 1080 * 0.96) // 92% of the area
        let cursor = CGPoint(x: 2400, y: 540)
        #expect(allows(source: rightDisplayLeftHalf, target: nearlyFull, cursor: cursor))
        #expect(!allows(source: rightDisplayLeftHalf, target: almostFull, cursor: cursor))
    }
}
