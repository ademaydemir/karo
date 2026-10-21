import CoreGraphics
import Testing
@testable import KaroCore

struct StepSizeFittingTests {
    private let visible = CGRect(x: 0, y: 25, width: 1440, height: 875)

    @Test func recognisesStepShortfalls() {
        #expect(StepSizeFitting.isStepShortfall(14))
        #expect(!StepSizeFitting.isStepShortfall(0.5))
        #expect(!StepSizeFitting.isStepShortfall(120))
    }

    @Test func leftHalfMayGrowDownButNotRight() {
        let leftHalf = CGRect(x: 0, y: 25, width: 720, height: 875)
        #expect(StepSizeFitting.canGrowDown(leftHalf, in: visible))
        #expect(!StepSizeFitting.canGrowRight(leftHalf, in: visible))
    }

    @Test func topQuarterMayNotGrowIntoTheQuarterBelow() {
        let topLeft = CGRect(x: 0, y: 25, width: 720, height: 438)
        #expect(!StepSizeFitting.canGrowDown(topLeft, in: visible))
    }

    @Test func shorterTopQuarterLeansOnTheInnerBottomEdge() {
        let topLeft = CGRect(x: 0, y: 25, width: 720, height: 438)
        let origin = StepSizeFitting.alignedOrigin(for: CGSize(width: 710, height: 426), in: topLeft, visibleFrame: visible)
        // Right and bottom edges meet the neighbours; the gaps go to the screen edges.
        #expect(origin == CGPoint(x: 10, y: 37))
    }

    @Test func fullHeightRegionKeepsItsTop() {
        let rightHalf = CGRect(x: 720, y: 25, width: 720, height: 875)
        let origin = StepSizeFitting.alignedOrigin(for: CGSize(width: 712, height: 860), in: rightHalf, visibleFrame: visible)
        // The left edge meets the left half; the full height span keeps its top.
        #expect(origin == CGPoint(x: 720, y: 25))
    }

    @Test func doublingSearchGrowsByAtMostOneStep() {
        // A Terminal-like app with 17 pt rows, asked for 875 pt: it gives 867 (8 short).
        let step: CGFloat = 17
        let target: CGFloat = 875
        func appHeight(for request: CGFloat) -> CGFloat { (request / step).rounded(.down) * step }
        var extra = target - appHeight(for: target)
        var result = appHeight(for: target)
        while result < target {
            result = appHeight(for: target + extra)
            guard result < target, let next = StepSizeFitting.nextExtra(after: extra) else { break }
            extra = next
        }
        #expect(result >= target)
        #expect(result - target < step)
    }

    @Test func doublingSearchStopsEventually() {
        #expect(StepSizeFitting.nextExtra(after: 10) == 20)
        #expect(StepSizeFitting.nextExtra(after: 50) == nil)
    }
}
