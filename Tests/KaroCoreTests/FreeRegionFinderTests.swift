import CoreGraphics
import Testing
@testable import KaroCore

struct FreeRegionFinderTests {
    private let visible = CGRect(x: 0, y: 25, width: 1440, height: 875)

    private func frame(_ action: WindowAction) -> CGRect {
        LayoutCalculator.frame(for: action, in: visible, currentFrame: .zero, gap: 0)!
    }

    private func region(at cursor: CGPoint, snapped: [WindowAction]) -> WindowAction? {
        FreeRegionFinder.region(at: cursor, in: visible, gap: 0, snappedFrames: snapped.map(frame), tolerance: 40)
    }

    @Test func offersTheOtherHalf() {
        #expect(region(at: CGPoint(x: 1100, y: 400), snapped: [.leftHalf]) == .rightHalf)
    }

    @Test func offersNothingWhenBothHalvesAreTaken() {
        #expect(region(at: CGPoint(x: 1100, y: 400), snapped: [.leftHalf, .rightHalf]) == nil)
    }

    @Test func offersNothingOverTheSnappedWindow() {
        #expect(region(at: CGPoint(x: 300, y: 400), snapped: [.leftHalf]) == nil)
    }

    @Test func offersTheQuarterBelowAQuarter() {
        #expect(region(at: CGPoint(x: 300, y: 800), snapped: [.topLeft]) == .bottomLeft)
    }

    @Test func offersTheHalfBesideAQuarter() {
        #expect(region(at: CGPoint(x: 1100, y: 400), snapped: [.topLeft]) == .rightHalf)
    }

    @Test func offersTheTwoThirdsBesideAThird() {
        #expect(region(at: CGPoint(x: 1000, y: 400), snapped: [.leftThird]) == .rightTwoThirds)
    }

    @Test func offersNothingWithoutSnappedWindows() {
        #expect(region(at: CGPoint(x: 1100, y: 400), snapped: []) == nil)
    }
}
