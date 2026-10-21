import CoreGraphics
import Testing
@testable import KaroCore

struct SharedEdgesTests {
    private let gap: CGFloat = 0
    private let leftHalf = CGRect(x: 0, y: 25, width: 720, height: 875)
    private let rightHalf = CGRect(x: 720, y: 25, width: 720, height: 875)
    private let topRight = CGRect(x: 720, y: 25, width: 720, height: 438)
    private let bottomRight = CGRect(x: 720, y: 463, width: 720, height: 437)
    private let topLeft = CGRect(x: 0, y: 25, width: 720, height: 438)
    private let bottomLeft = CGRect(x: 0, y: 463, width: 720, height: 437)

    @Test func findsTheHalfOnTheOtherSide() {
        let neighbors = SharedEdges.neighbors(of: leftHalf, among: [(id: 1, frame: rightHalf)], gap: gap)
        #expect(neighbors.map(\.id) == [1])
        #expect(neighbors.first?.side == .right)
    }

    @Test func quarterHasNeighboursAcrossAndBelowButNotDiagonally() {
        let candidates = [(id: "topRight", frame: topRight), (id: "bottomLeft", frame: bottomLeft), (id: "bottomRight", frame: bottomRight)]
        let neighbors = SharedEdges.neighbors(of: topLeft, among: candidates, gap: gap)
        #expect(Set(neighbors.map(\.id)) == ["topRight", "bottomLeft"])
        #expect(neighbors.first { $0.id == "bottomLeft" }?.side == .bottom)
    }

    @Test func respectsTheGapBetweenWindows() {
        let left = CGRect(x: 10, y: 35, width: 705, height: 855)
        let right = CGRect(x: 725, y: 35, width: 705, height: 855)
        #expect(SharedEdges.neighbors(of: left, among: [(id: 1, frame: right)], gap: 10).count == 1)
        #expect(SharedEdges.neighbors(of: left, among: [(id: 1, frame: right)], gap: 0).isEmpty)
    }

    @Test func rightNeighbourFollowsAWiderLeftWindow() {
        let widened = CGRect(x: 0, y: 25, width: 860, height: 875)
        let adjusted = SharedEdges.adjusted(rightHalf, on: .right, of: widened, gap: 0)
        #expect(adjusted == CGRect(x: 860, y: 25, width: 580, height: 875))
    }

    @Test func leftNeighbourFollowsARightWindowGrowingLeftwards() {
        let grown = CGRect(x: 600, y: 25, width: 840, height: 875)
        let adjusted = SharedEdges.adjusted(leftHalf, on: .left, of: grown, gap: 0)
        #expect(adjusted == CGRect(x: 0, y: 25, width: 600, height: 875))
    }

    @Test func lowerNeighbourFollowsATallerUpperWindow() {
        let taller = CGRect(x: 0, y: 25, width: 720, height: 538)
        let adjusted = SharedEdges.adjusted(bottomLeft, on: .bottom, of: taller, gap: 0)
        #expect(adjusted == CGRect(x: 0, y: 563, width: 720, height: 337))
    }

    @Test func neighbourKeepsAMinimumSize() {
        let almostFull = CGRect(x: 0, y: 25, width: 1400, height: 875)
        let adjusted = SharedEdges.adjusted(rightHalf, on: .right, of: almostFull, gap: 0, minimumLength: 120)
        #expect(adjusted.width == 120)
        #expect(adjusted.maxX == rightHalf.maxX)
    }
}

struct FrameHistoryPlacementsTests {
    @Test func listsPlacedWindowsWithTheirFrames() {
        var history = FrameHistory<Int>()
        let first = CGRect(x: 0, y: 0, width: 100, height: 100)
        let second = CGRect(x: 100, y: 0, width: 100, height: 100)
        history.recordPlacement(of: 1, from: .zero, to: first)
        history.recordPlacement(of: 2, from: .zero, to: second)
        _ = history.takeRestoreFrame(for: 1)
        #expect(history.placements.map(\.window) == [2])
        #expect(history.placements.first?.frame == second)
    }
}
