import CoreGraphics
import Testing
@testable import TesseraCore

struct DisplaySelectorTests {
    private let displays = [
        CGRect(x: 0, y: 0, width: 1440, height: 900),
        CGRect(x: 1440, y: 0, width: 1920, height: 1080),
    ]

    @Test func picksDisplayContainingWindow() {
        let window = CGRect(x: 1600, y: 100, width: 800, height: 600)
        #expect(DisplaySelector.indexOfDisplay(containing: window, among: displays) == 1)
    }

    @Test func picksDisplayWithLargestOverlapWhenStraddling() {
        let window = CGRect(x: 1000, y: 100, width: 800, height: 600) // 440 pt on the left, 360 pt on the right
        #expect(DisplaySelector.indexOfDisplay(containing: window, among: displays) == 0)
    }

    @Test func fallsBackToNearestDisplayWhenOffScreen() {
        let window = CGRect(x: 4000, y: 100, width: 400, height: 300)
        #expect(DisplaySelector.indexOfDisplay(containing: window, among: displays) == 1)
    }

    @Test func returnsNilWithoutDisplays() {
        #expect(DisplaySelector.indexOfDisplay(containing: .zero, among: []) == nil)
    }
}
