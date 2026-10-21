import CoreGraphics
import Testing
@testable import KaroCore

struct ZoneDetectorTests {
    private let detector = ZoneDetector(edgeThreshold: 5, cornerSize: 40)
    private let single = [CGRect(x: 0, y: 0, width: 1440, height: 900)]

    private func action(at point: CGPoint, displays: [CGRect]? = nil) -> WindowAction? {
        detector.zone(at: point, displays: displays ?? single)?.action
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
