import CoreGraphics
import Foundation
import Testing
@testable import TesseraCore

struct DisplayConfigurationTests {
    private let laptop = DisplayConfiguration.Descriptor(vendor: 1552, model: 41_234, serial: 0, frame: CGRect(x: 0, y: 0, width: 1512, height: 982))
    private let monitor = DisplayConfiguration.Descriptor(vendor: 7789, model: 30_000, serial: 123, frame: CGRect(x: 1512, y: -300, width: 2560, height: 1440))

    @Test func keyDoesNotDependOnDisplayOrder() {
        #expect(DisplayConfiguration.key(for: [laptop, monitor]) == DisplayConfiguration.key(for: [monitor, laptop]))
    }

    @Test func keyChangesWhenADisplayIsAddedOrMoved() {
        let alone = DisplayConfiguration.key(for: [laptop])
        let docked = DisplayConfiguration.key(for: [laptop, monitor])
        var movedMonitor = monitor
        movedMonitor.frame.origin.x = -2560
        #expect(alone != docked)
        #expect(docked != DisplayConfiguration.key(for: [laptop, movedMonitor]))
    }

    @Test func keyDistinguishesIdenticalModelsBySerial() {
        var twin = monitor
        twin.serial = 456
        #expect(DisplayConfiguration.key(for: [laptop, monitor]) != DisplayConfiguration.key(for: [laptop, twin]))
    }
}

struct LayoutMemoryTests {
    @Test func remembersFramesPerConfiguration() {
        var memory = LayoutMemory<Int>()
        memory.record([1: CGRect(x: 0, y: 0, width: 100, height: 100)], for: "docked")
        memory.record([1: CGRect(x: 50, y: 50, width: 100, height: 100)], for: "alone")
        #expect(memory.frames(for: "docked")?[1] == CGRect(x: 0, y: 0, width: 100, height: 100))
        #expect(memory.frames(for: "alone")?[1] == CGRect(x: 50, y: 50, width: 100, height: 100))
        #expect(memory.frames(for: "other") == nil)
    }

    @Test func forgetsLeastRecentConfigurationBeyondCapacity() {
        var memory = LayoutMemory<Int>(capacity: 2)
        memory.record([:], for: "a")
        memory.record([:], for: "b")
        memory.record([:], for: "a")
        memory.record([:], for: "c")
        #expect(memory.frames(for: "b") == nil)
        #expect(memory.frames(for: "a") != nil)
    }
}

struct SnapAssistRegionsTests {
    private let visible = CGRect(x: 0, y: 25, width: 1440, height: 875)
    private let window = CGRect(x: 0, y: 0, width: 800, height: 600)

    private func frame(_ action: WindowAction) -> CGRect {
        LayoutCalculator.frame(for: action, in: visible, currentFrame: window)!
    }

    @Test(arguments: [
        WindowAction.leftHalf, .rightHalf, .topHalf, .bottomHalf,
        .leftThird, .rightThird, .leftTwoThirds, .rightTwoThirds,
        .topLeft, .topRight, .bottomLeft, .bottomRight,
    ])
    func regionsFillTheRestOfTheDisplayWithoutOverlap(action: WindowAction) {
        let frames = [frame(action)] + action.snapAssistRegions.map(frame)
        let covered = frames.dropFirst().reduce(frames[0]) { $0.union($1) }
        let area = frames.map { $0.width * $0.height }.reduce(0, +)
        #expect(covered == visible)
        #expect(area == visible.width * visible.height)
    }

    @Test func quarterOffersSameSideQuarterThenOppositeHalf() {
        #expect(WindowAction.bottomRight.snapAssistRegions == [.topRight, .leftHalf])
        #expect(WindowAction.topLeft.snapAssistRegions == [.bottomLeft, .rightHalf])
    }

    @Test(arguments: [WindowAction.maximize, .center, .centerThird, .restore])
    func otherPlacementsOfferNothing(action: WindowAction) {
        #expect(action.snapAssistRegions.isEmpty)
    }
}

struct ResizeGeometryTests {
    private let frame = CGRect(x: 100, y: 100, width: 400, height: 300)

    @Test func picksNearestCorner() {
        #expect(ResizeGeometry.corner(nearest: CGPoint(x: 120, y: 110), in: frame) == .topLeft)
        #expect(ResizeGeometry.corner(nearest: CGPoint(x: 480, y: 110), in: frame) == .topRight)
        #expect(ResizeGeometry.corner(nearest: CGPoint(x: 120, y: 390), in: frame) == .bottomLeft)
        #expect(ResizeGeometry.corner(nearest: CGPoint(x: 480, y: 390), in: frame) == .bottomRight)
    }

    @Test func bottomRightGrowsAwayFromTopLeft() {
        let resized = ResizeGeometry.resized(frame, dragging: .bottomRight, by: CGVector(dx: 50, dy: 30))
        #expect(resized == CGRect(x: 100, y: 100, width: 450, height: 330))
    }

    @Test func topLeftKeepsBottomRightInPlace() {
        let resized = ResizeGeometry.resized(frame, dragging: .topLeft, by: CGVector(dx: -20, dy: 40))
        #expect(resized == CGRect(x: 80, y: 140, width: 420, height: 260))
        #expect(resized.maxX == frame.maxX && resized.maxY == frame.maxY)
    }

    @Test func neverShrinksBelowMinimumSize() {
        let resized = ResizeGeometry.resized(frame, dragging: .topRight, by: CGVector(dx: -1000, dy: 1000), minimumSize: CGSize(width: 100, height: 60))
        #expect(resized.width == 100)
        #expect(resized.height == 60)
        #expect(resized.minX == frame.minX && resized.maxY == frame.maxY)
    }
}

struct ExtraSettingsTests {
    @Test func defaultsAreOnWithControlOptionDrag() {
        let settings = TesseraSettings()
        #expect(settings.restoresLayoutOnDisplayChange)
        #expect(settings.isSnapAssistEnabled)
        #expect(settings.modifierDrag == .controlOption)
    }

    @Test func roundTripsNewFields() throws {
        var settings = TesseraSettings()
        settings.restoresLayoutOnDisplayChange = false
        settings.isSnapAssistEnabled = false
        settings.modifierDrag = .option
        let data = try JSONEncoder().encode(settings)
        #expect(try JSONDecoder().decode(TesseraSettings.self, from: data) == settings)
    }

    @Test func modifierOptionsMapToModifiers() {
        #expect(ModifierDrag.disabled.modifiers == nil)
        #expect(ModifierDrag.controlOption.modifiers == [.control, .option])
    }
}
