import CoreGraphics
import Testing
@testable import KaroCore

struct CoordinateConverterTests {
    @Test func flipsVisibleFrameOfPrimaryDisplay() {
        // AppKit visibleFrame of a 1440x900 display with a 25 pt menu bar and 70 pt Dock.
        let appKit = CGRect(x: 0, y: 70, width: 1440, height: 805)
        #expect(CoordinateConverter.flip(appKit, primaryScreenHeight: 900) == CGRect(x: 0, y: 25, width: 1440, height: 805))
    }

    @Test func flipsDisplayAbovePrimaryToNegativeY() {
        let above = CGRect(x: 0, y: 900, width: 1920, height: 1080)
        #expect(CoordinateConverter.flip(above, primaryScreenHeight: 900) == CGRect(x: 0, y: -1080, width: 1920, height: 1080))
    }

    @Test func flipsCursorLocation() {
        #expect(CoordinateConverter.flip(CGPoint(x: 10, y: 900), primaryScreenHeight: 900) == CGPoint(x: 10, y: 0))
        #expect(CoordinateConverter.flip(CGPoint(x: 10, y: 0), primaryScreenHeight: 900) == CGPoint(x: 10, y: 900))
    }

    @Test func isItsOwnInverse() {
        let rect = CGRect(x: -300, y: 120, width: 640, height: 480)
        let roundTrip = CoordinateConverter.flip(CoordinateConverter.flip(rect, primaryScreenHeight: 1117), primaryScreenHeight: 1117)
        #expect(roundTrip == rect)
    }
}
