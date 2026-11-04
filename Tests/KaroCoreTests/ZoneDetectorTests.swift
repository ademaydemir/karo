import CoreGraphics
import Testing
@testable import KaroCore

struct ZoneDetectorTests {
    private let detector = ZoneDetector(edgeThreshold: 5, cornerSize: 40)
    private let single = [CGRect(x: 0, y: 0, width: 1440, height: 900)]

    private func action(at point: CGPoint, displays: [CGRect]? = nil) -> WindowAction? {
        detector.zone(at: point, displays: displays ?? single)?.action
    }

    private func held(_ current: WindowAction?, at point: CGPoint, display: Int = 0, displays: [CGRect]? = nil) -> ZoneDetector.Zone? {
        detector.zone(
            at: point,
            displays: displays ?? single,
            current: current.map { ZoneDetector.Zone(action: $0, displayIndex: display) }
        )
    }

    @Test func hysteresisKeepsAnEdgeHalfInsideACornerSegment() {
        #expect(held(.leftHalf, at: CGPoint(x: 0, y: 38))?.action == .leftHalf)
        #expect(action(at: CGPoint(x: 0, y: 38)) == .topLeft)
        #expect(held(.leftHalf, at: CGPoint(x: 0, y: 30))?.action == .topLeft)
    }

    @Test func hysteresisKeepsACornerJustOutsideItsSegment() {
        #expect(held(.topLeft, at: CGPoint(x: 0, y: 45))?.action == .topLeft)
        #expect(held(.topLeft, at: CGPoint(x: 0, y: 49))?.action == .leftHalf)
    }

    @Test func hysteresisKeepsAZoneJustOutsideTheEdge() {
        #expect(held(.leftHalf, at: CGPoint(x: 10, y: 450))?.action == .leftHalf)
        #expect(held(.leftHalf, at: CGPoint(x: 14, y: 450)) == nil)
    }

    @Test func withoutACurrentZoneHysteresisChangesNothing() {
        for point in [CGPoint(x: 0, y: 38), CGPoint(x: 10, y: 450), CGPoint(x: 720, y: 0), CGPoint(x: 720, y: 450)] {
            #expect(held(nil, at: point) == detector.zone(at: point, displays: single))
        }
    }

    @Test func hysteresisDoesNotKeepAZoneOnAnotherDisplay() {
        let displays = [CGRect(x: 0, y: 0, width: 1440, height: 900), CGRect(x: 1440, y: 0, width: 1440, height: 900)]
        #expect(held(.leftHalf, at: CGPoint(x: 2000, y: 450), display: 0, displays: displays) == nil)
        #expect(held(.leftHalf, at: CGPoint(x: 1445, y: 450), display: 0, displays: displays) == nil)
    }

    @Test(arguments: [
        (CGPoint(x: 0, y: 450), WindowAction.leftHalf),
        (CGPoint(x: 4, y: 450), .leftHalf),
        (CGPoint(x: 1439, y: 450), .rightHalf),
        (CGPoint(x: 720, y: 0), .maximize),
        (CGPoint(x: 0, y: 10), .topLeft),
        (CGPoint(x: 30, y: 0), .topLeft),
        (CGPoint(x: 1439, y: 0), .topRight),
        (CGPoint(x: 0, y: 890), .bottomLeft),
        (CGPoint(x: 1439, y: 899), .bottomRight),
        (CGPoint(x: 20, y: 900), .bottomLeft),
        (CGPoint(x: 1420, y: 900), .bottomRight),
    ])
    func detectsEdgesAndCorners(point: CGPoint, expected: WindowAction) {
        #expect(action(at: point) == expected)
    }

    @Test(arguments: [
        CGPoint(x: 720, y: 450),   // middle of the screen
        CGPoint(x: 6, y: 450),     // just outside the edge threshold
        CGPoint(x: 720, y: 900),   // bottom edge outside the corners
    ])
    func ignoresPointsOutsideZones(point: CGPoint) {
        #expect(action(at: point) == nil)
    }

    @Test func returnsNilOutsideAllDisplays() {
        #expect(action(at: CGPoint(x: 2000, y: 450)) == nil)
    }

    @Test func ignoresEdgeSharedWithAnotherDisplay() {
        let displays = [CGRect(x: 0, y: 0, width: 1440, height: 900), CGRect(x: 1440, y: 0, width: 1920, height: 1080)]
        #expect(action(at: CGPoint(x: 1439, y: 450), displays: displays) == nil)
        #expect(action(at: CGPoint(x: 1441, y: 450), displays: displays) == nil)
        #expect(action(at: CGPoint(x: 0, y: 450), displays: displays) == .leftHalf)
        #expect(action(at: CGPoint(x: 3359, y: 500), displays: displays) == .rightHalf)
    }

    @Test func keepsEdgeOpenWhereNeighbourDoesNotReach() {
        // The taller right display has an open left edge below the primary display.
        let displays = [CGRect(x: 0, y: 0, width: 1440, height: 900), CGRect(x: 1440, y: 0, width: 1920, height: 1080)]
        #expect(action(at: CGPoint(x: 1441, y: 1000), displays: displays) == .leftHalf)
    }

    @Test func reportsDisplayIndexForSecondaryDisplay() {
        let displays = [CGRect(x: 0, y: 0, width: 1440, height: 900), CGRect(x: -1920, y: -180, width: 1920, height: 1080)]
        let zone = detector.zone(at: CGPoint(x: -1920, y: 300), displays: displays)
        #expect(zone == ZoneDetector.Zone(action: .leftHalf, displayIndex: 1))
    }
}
