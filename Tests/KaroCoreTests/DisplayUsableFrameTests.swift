import CoreGraphics
import Testing
@testable import KaroCore

struct DisplayUsableFrameTests {
    // An external display in Accessibility coordinates, as measured: a 30 pt menu bar at the
    // top and 50 pt reserved for a Dock that is actually on the other display.
    private let frame = CGRect(x: 1470, y: -484, width: 2560, height: 1440)
    private let visible = CGRect(x: 1470, y: -454, width: 2560, height: 1360)

    @Test func displayWithoutDockUsesTheFullHeightBelowTheMenuBar() {
        let usable = Display.usableFrame(visibleFrame: visible, frame: frame, hostsDock: false)
        #expect(usable == CGRect(x: 1470, y: -454, width: 2560, height: 1410))
        #expect(usable.maxY == frame.maxY)
    }

    @Test func displayWithDockKeepsTheDockSpace() {
        #expect(Display.usableFrame(visibleFrame: visible, frame: frame, hostsDock: true) == visible)
    }

    @Test func sideDockSpaceIsReturnedToo() {
        let leftDockVisible = CGRect(x: 1520, y: -454, width: 2510, height: 1410)
        let usable = Display.usableFrame(visibleFrame: leftDockVisible, frame: frame, hostsDock: false)
        #expect(usable.minX == frame.minX)
        #expect(usable.width == frame.width)
    }
}
