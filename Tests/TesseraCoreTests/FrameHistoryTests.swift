import CoreGraphics
import Testing
@testable import TesseraCore

struct FrameHistoryTests {
    private let floating = CGRect(x: 100, y: 100, width: 800, height: 600)
    private let leftHalf = CGRect(x: 0, y: 25, width: 720, height: 875)
    private let maximized = CGRect(x: 0, y: 25, width: 1440, height: 875)

    @Test func restoresFrameFromBeforePlacement() {
        var history = FrameHistory<Int>()
        history.recordPlacement(of: 1, from: floating, to: leftHalf)
        #expect(history.takeRestoreFrame(for: 1) == floating)
    }

    @Test func chainedPlacementsKeepOriginalFrame() {
        var history = FrameHistory<Int>()
        history.recordPlacement(of: 1, from: floating, to: leftHalf)
        history.recordPlacement(of: 1, from: leftHalf, to: maximized)
        #expect(history.takeRestoreFrame(for: 1) == floating)
    }

    @Test func toleratesSubPointDifferencesWhenChaining() {
        var history = FrameHistory<Int>()
        history.recordPlacement(of: 1, from: floating, to: leftHalf)
        history.recordPlacement(of: 1, from: leftHalf.offsetBy(dx: 0.5, dy: 0), to: maximized)
        #expect(history.takeRestoreFrame(for: 1) == floating)
    }

    @Test func manualMoveBetweenPlacementsBecomesNewRestorePoint() {
        var history = FrameHistory<Int>()
        let movedByUser = CGRect(x: 300, y: 200, width: 700, height: 500)
        history.recordPlacement(of: 1, from: floating, to: leftHalf)
        history.recordPlacement(of: 1, from: movedByUser, to: maximized)
        #expect(history.takeRestoreFrame(for: 1) == movedByUser)
    }

    @Test func restoreForgetsWindow() {
        var history = FrameHistory<Int>()
        history.recordPlacement(of: 1, from: floating, to: leftHalf)
        _ = history.takeRestoreFrame(for: 1)
        #expect(history.takeRestoreFrame(for: 1) == nil)
    }

    @Test func tracksWindowsIndependently() {
        var history = FrameHistory<Int>()
        history.recordPlacement(of: 1, from: floating, to: leftHalf)
        history.recordPlacement(of: 2, from: maximized, to: leftHalf)
        #expect(history.takeRestoreFrame(for: 1) == floating)
        #expect(history.takeRestoreFrame(for: 2) == maximized)
    }

    @Test func dragRestoreMatchesOnSizeOnly() {
        var history = FrameHistory<Int>()
        history.recordPlacement(of: 1, from: floating, to: leftHalf)
        // The drag has already moved the window by the time it is recognised.
        #expect(history.takeRestoreFrame(for: 1, ifSizeMatches: leftHalf.size) == floating)
        #expect(history.takeRestoreFrame(for: 1) == nil)
    }

    @Test func dragRestoreSkipsWindowResizedByUser() {
        var history = FrameHistory<Int>()
        history.recordPlacement(of: 1, from: floating, to: leftHalf)
        #expect(history.takeRestoreFrame(for: 1, ifSizeMatches: CGSize(width: 500, height: 875)) == nil)
    }

    @Test func evictsLeastRecentlyPlacedWindowBeyondCapacity() {
        var history = FrameHistory<Int>(capacity: 2)
        history.recordPlacement(of: 1, from: floating, to: leftHalf)
        history.recordPlacement(of: 2, from: floating, to: leftHalf)
        history.recordPlacement(of: 1, from: leftHalf, to: maximized) // 1 is now most recent
        history.recordPlacement(of: 3, from: floating, to: leftHalf)
        #expect(history.takeRestoreFrame(for: 2) == nil)
        #expect(history.takeRestoreFrame(for: 1) == floating)
        #expect(history.takeRestoreFrame(for: 3) == floating)
    }
}
