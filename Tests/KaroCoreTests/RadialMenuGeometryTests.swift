import CoreGraphics
import Testing
@testable import KaroCore

@Suite("RadialMenuGeometry")
struct RadialMenuGeometryTests {
    private let center = CGPoint(x: 100, y: 100)
    private let item = CGRect(x: 50, y: 70, width: 100, height: 60)

    private func region(_ point: CGPoint, isOpen: Bool, count: Int = 4) -> RadialMenuRegion {
        RadialMenuGeometry.region(of: point, ringCenter: center, innerRadius: 40, outerRadius: 100, sliceCount: count, itemRect: item, isOpen: isOpen)
    }

    @Test func closedOnlyTheItemCounts() {
        #expect(region(CGPoint(x: 100, y: 100), isOpen: false) == .item)
        // On the ring's band, but there is no ring while closed.
        #expect(region(CGPoint(x: 100, y: 20), isOpen: false) == .outside)
    }

    @Test func openSliceWinsOverItem() {
        #expect(region(CGPoint(x: 100, y: 20), isOpen: true) == .slice(0))
        #expect(region(CGPoint(x: 180, y: 100), isOpen: true) == .slice(1))
        // Inside the item rect but beyond the inner radius: the slice still wins.
        #expect(region(CGPoint(x: 145, y: 100), isOpen: true) == .slice(1))
    }

    @Test func openCenterAndItemAreTheItem() {
        #expect(region(CGPoint(x: 100, y: 100), isOpen: true) == .item)
        #expect(region(CGPoint(x: 70, y: 100), isOpen: true) == .item)
    }

    @Test func openOutsideEverything() {
        #expect(region(CGPoint(x: 5, y: 5), isOpen: true) == .outside)
        #expect(region(CGPoint(x: 300, y: 100), isOpen: true) == .outside)
    }

    @Test func noSlicesLeavesTheItem() {
        #expect(region(CGPoint(x: 100, y: 20), isOpen: true, count: 0) == .outside)
        #expect(region(CGPoint(x: 100, y: 100), isOpen: true, count: 0) == .item)
    }
}
