import CoreGraphics
import Testing
@testable import TesseraCore

struct LayoutCalculatorTests {
    /// A 1440x900 display with a 25 pt menu bar, in Accessibility coordinates.
    private let visible = CGRect(x: 0, y: 25, width: 1440, height: 875)
    private let window = CGRect(x: 100, y: 100, width: 800, height: 600)

    private func frame(_ action: WindowAction, in visible: CGRect? = nil, gap: CGFloat = 0) -> CGRect? {
        LayoutCalculator.frame(for: action, in: visible ?? self.visible, currentFrame: window, gap: gap)
    }

    @Test(arguments: [
        (WindowAction.leftHalf, CGRect(x: 0, y: 25, width: 720, height: 875)),
        (.rightHalf, CGRect(x: 720, y: 25, width: 720, height: 875)),
        (.topHalf, CGRect(x: 0, y: 25, width: 1440, height: 438)),
        (.bottomHalf, CGRect(x: 0, y: 463, width: 1440, height: 437)),
        (.topLeft, CGRect(x: 0, y: 25, width: 720, height: 438)),
        (.topRight, CGRect(x: 720, y: 25, width: 720, height: 438)),
        (.bottomLeft, CGRect(x: 0, y: 463, width: 720, height: 437)),
        (.bottomRight, CGRect(x: 720, y: 463, width: 720, height: 437)),
        (.leftThird, CGRect(x: 0, y: 25, width: 480, height: 875)),
        (.centerThird, CGRect(x: 480, y: 25, width: 480, height: 875)),
        (.rightThird, CGRect(x: 960, y: 25, width: 480, height: 875)),
        (.leftTwoThirds, CGRect(x: 0, y: 25, width: 960, height: 875)),
        (.rightTwoThirds, CGRect(x: 480, y: 25, width: 960, height: 875)),
        (.maximize, CGRect(x: 0, y: 25, width: 1440, height: 875)),
    ])
    func placesRegionsOnDisplay(action: WindowAction, expected: CGRect) {
        #expect(frame(action) == expected)
    }

    @Test(arguments: [WindowAction.restore, .nextDisplay, .previousDisplay])
    func returnsNilForNonPlacementActions(action: WindowAction) {
        #expect(frame(action) == nil)
    }

    @Test func adjacentRegionsShareEdgesWhenWidthIsNotDivisible() throws {
        let odd = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let left = try #require(frame(.leftThird, in: odd))
        let center = try #require(frame(.centerThird, in: odd))
        let right = try #require(frame(.rightThird, in: odd))
        #expect(left.maxX == center.minX)
        #expect(center.maxX == right.minX)
        #expect(right.maxX == 1000)
    }

    @Test func gapIsFullAtScreenEdgesAndHalfBetweenWindows() throws {
        let left = try #require(frame(.leftHalf, gap: 10))
        let right = try #require(frame(.rightHalf, gap: 10))
        #expect(left == CGRect(x: 10, y: 35, width: 705, height: 855))
        #expect(right == CGRect(x: 725, y: 35, width: 705, height: 855))
        #expect(right.minX - left.maxX == 10)
    }

    @Test func placesOnSecondaryDisplayWithNegativeOrigin() {
        let secondary = CGRect(x: -1920, y: -200, width: 1920, height: 1080)
        #expect(frame(.rightHalf, in: secondary) == CGRect(x: -960, y: -200, width: 960, height: 1080))
    }

    @Test func centerKeepsSizeAndCentersOnDisplay() {
        #expect(frame(.center) == CGRect(x: 320, y: 163, width: 800, height: 600))
    }

    @Test func centerShrinksWindowLargerThanDisplay() {
        let huge = CGRect(x: 0, y: 0, width: 3000, height: 2000)
        let result = LayoutCalculator.frame(for: .center, in: visible, currentFrame: huge, gap: 0)
        #expect(result == visible)
    }

    @Test func clampedMovesOverflowingWindowBackInside() {
        // A window whose minimum width exceeded the requested right half.
        let overflowing = CGRect(x: 720, y: 25, width: 900, height: 875)
        #expect(LayoutCalculator.clamped(overflowing, to: visible) == CGRect(x: 540, y: 25, width: 900, height: 875))
    }

    @Test func clampedLeavesFittingWindowUntouched() {
        #expect(LayoutCalculator.clamped(window, to: visible) == window)
    }

    @Test func clampedAlignsOversizedWindowToTopLeft() {
        let oversized = CGRect(x: 200, y: 300, width: 2000, height: 1000)
        #expect(LayoutCalculator.clamped(oversized, to: visible).origin == CGPoint(x: 0, y: 25))
    }
}
