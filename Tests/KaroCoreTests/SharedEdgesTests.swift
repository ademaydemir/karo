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

    @Test func threeSplitMovesLeftAndBottomRightTogether() {
        let candidates = [(id: "L", frame: leftHalf), (id: "RB", frame: bottomRight)]
        let linked = SharedEdges.linkedEdges(of: topRight, edge: .minX, among: candidates, gap: 0)
        #expect(linked.count == 2)
        let linkedL = linked.first { $0.id == "L" }
        let linkedRB = linked.first { $0.id == "RB" }
        #expect(linkedL?.edge == .maxX)
        #expect(linkedRB?.edge == .minX)

        let movedL = SharedEdges.moving(leftHalf, edge: .maxX, draggedEdge: .minX, toLine: 800, gap: 0)
        let movedRB = SharedEdges.moving(bottomRight, edge: .minX, draggedEdge: .minX, toLine: 800, gap: 0)
        #expect(movedL.maxX == 800)
        #expect(movedL.minX == leftHalf.minX)
        #expect(movedL.minY == leftHalf.minY)
        #expect(movedL.maxY == leftHalf.maxY)

        #expect(movedRB.minX == 800)
        #expect(movedRB.maxX == bottomRight.maxX)
        #expect(movedRB.minY == bottomRight.minY)
        #expect(movedRB.maxY == bottomRight.maxY)
    }

    @Test func threeSplitRespectsGap() {
        let gap: CGFloat = 10
        let leftWithGap = CGRect(x: 10, y: 35, width: 705, height: 855)
        let topRightWithGap = CGRect(x: 725, y: 35, width: 705, height: 422)
        let bottomRightWithGap = CGRect(x: 725, y: 467, width: 705, height: 423)

        let candidates = [(id: "L", frame: leftWithGap), (id: "RB", frame: bottomRightWithGap)]
        let linked = SharedEdges.linkedEdges(of: topRightWithGap, edge: .minX, among: candidates, gap: gap)
        #expect(linked.count == 2)
        #expect(linked.first { $0.id == "L" }?.edge == .maxX)
        #expect(linked.first { $0.id == "RB" }?.edge == .minX)

        let line: CGFloat = 800
        let movedL = SharedEdges.moving(leftWithGap, edge: .maxX, draggedEdge: .minX, toLine: line, gap: gap)
        let movedRB = SharedEdges.moving(bottomRightWithGap, edge: .minX, draggedEdge: .minX, toLine: line, gap: gap)
        #expect(movedL.maxX == line - gap)
        #expect(movedRB.minX == line)
    }

    @Test func quarterBottomEdgeLinksBottomLeftAndMatchingRightColumn() {
        let trDiff = CGRect(x: 720, y: 25, width: 720, height: 475) // split at y = 500
        let brDiff = CGRect(x: 720, y: 500, width: 720, height: 400)
        let candidatesDiff = [(id: "BL", frame: bottomLeft), (id: "TR", frame: trDiff), (id: "BR", frame: brDiff)]
        let linkedDiff = SharedEdges.linkedEdges(of: topLeft, edge: .maxY, among: candidatesDiff, gap: 0)
        #expect(linkedDiff.map(\.id) == ["BL"])
        #expect(linkedDiff.first?.edge == .minY)

        let candidatesSame = [(id: "BL", frame: bottomLeft), (id: "TR", frame: topRight), (id: "BR", frame: bottomRight)]
        let linkedSame = SharedEdges.linkedEdges(of: topLeft, edge: .maxY, among: candidatesSame, gap: 0)
        #expect(Set(linkedSame.map(\.id)) == ["BL", "TR", "BR"])
        #expect(linkedSame.first { $0.id == "BL" }?.edge == .minY)
        #expect(linkedSame.first { $0.id == "TR" }?.edge == .maxY)
        #expect(linkedSame.first { $0.id == "BR" }?.edge == .minY)
    }

    @Test func distantWindowOnSameLineIsNotLinked() {
        let frame = CGRect(x: 100, y: 0, width: 200, height: 100)
        let far = CGRect(x: 100, y: 500, width: 200, height: 100)
        let linked = SharedEdges.linkedEdges(of: frame, edge: .minX, among: [(id: "far", frame: far)], gap: 0)
        #expect(linked.isEmpty)
    }

    @Test func fiveWindowCaseLinksBothBottomWindows() {
        let gap: CGFloat = 10
        let tl = CGRect(x: 10, y: 20, width: 700, height: 380)
        let tr = CGRect(x: 720, y: 20, width: 700, height: 380)
        let bl = CGRect(x: 10, y: 410, width: 340, height: 390)
        let bm = CGRect(x: 360, y: 410, width: 350, height: 390)
        let br = CGRect(x: 720, y: 410, width: 700, height: 390)

        let candidates = [(id: "TL", frame: tl), (id: "BL", frame: bl), (id: "BM", frame: bm), (id: "BR", frame: br)]
        let linked = SharedEdges.linkedEdges(of: tr, edge: .minX, among: candidates, gap: gap)
        #expect(Set(linked.map(\.id)) == ["TL", "BM", "BR"])
        #expect(linked.first { $0.id == "BM" }?.edge == .maxX)
        #expect(linked.first { $0.id == "BR" }?.edge == .minX)
        #expect(linked.first { $0.id == "TL" }?.edge == .maxX)
    }

    @Test func clampedLineEnforcesMinimumLengthInBothDirections() {
        let linkedX = [
            SharedEdges.LinkedEdge(id: "L", frame: leftHalf, edge: SharedEdges.Edge.maxX),
            SharedEdges.LinkedEdge(id: "RB", frame: bottomRight, edge: SharedEdges.Edge.minX)
        ]
        // RT has minX = 720, maxX = 1440.
        // Dragging right shrinks RT and RB (max limit: 1440 - 120 = 1320).
        let clampedRight = SharedEdges.clampedLine(1400, edge: .minX, of: topRight, linked: linkedX, gap: 0, minimumLength: 120)
        #expect(clampedRight == 1320)

        // Dragging left shrinks L (min limit: 0 + 120 = 120).
        let clampedLeft = SharedEdges.clampedLine(50, edge: .minX, of: topRight, linked: linkedX, gap: 0, minimumLength: 120)
        #expect(clampedLeft == 120)

        // Within bounds: returns proposed unchanged.
        let clampedNormal = SharedEdges.clampedLine(800, edge: .minX, of: topRight, linked: linkedX, gap: 0, minimumLength: 120)
        #expect(clampedNormal == 800)

        // Horizontal test: topLeft bottom edge (.maxY) and bottomLeft (.minY).
        let linkedY = [
            SharedEdges.LinkedEdge(id: "BL", frame: bottomLeft, edge: SharedEdges.Edge.minY)
        ]
        // topLeft minY = 25, maxY = 463. bottomLeft minY = 463, maxY = 900.
        // Dragging down shrinks bottomLeft (max limit: 900 - 120 = 780).
        let clampedDown = SharedEdges.clampedLine(850, edge: .maxY, of: topLeft, linked: linkedY, gap: 0, minimumLength: 120)
        #expect(clampedDown == 780)

        // Dragging up shrinks topLeft (min limit: 25 + 120 = 145).
        let clampedUp = SharedEdges.clampedLine(50, edge: .maxY, of: topLeft, linked: linkedY, gap: 0, minimumLength: 120)
        #expect(clampedUp == 145)
    }

    @Test func findsEdgesNearCursor() {
        let frame = CGRect(x: 100, y: 100, width: 200, height: 200)
        let reach: CGFloat = 8

        let outsideLeft = CGPoint(x: 96, y: 200)
        #expect(SharedEdges.edges(near: outsideLeft, of: frame, reach: reach) == [.minX])

        let insideRight = CGPoint(x: 296, y: 200)
        #expect(SharedEdges.edges(near: insideRight, of: frame, reach: reach) == [.maxX])

        let nearBottomRight = CGPoint(x: 302, y: 302)
        #expect(SharedEdges.edges(near: nearBottomRight, of: frame, reach: reach) == [.maxX, .maxY])

        let centre = CGPoint(x: 200, y: 200)
        #expect(SharedEdges.edges(near: centre, of: frame, reach: reach).isEmpty)

        let aboveLeft = CGPoint(x: 96, y: 50)
        #expect(SharedEdges.edges(near: aboveLeft, of: frame, reach: reach).isEmpty)
    }

    @Test func cornerReachIncludesAdjacentEdge() {
        let frame = CGRect(x: 100, y: 100, width: 200, height: 200)
        let reach: CGFloat = 8
        let cornerReach: CGFloat = 20

        // 3 pt left of the left edge (x = 97) and 15 pt below the top (y = 115)
        let nearTopLeftVertical = CGPoint(x: 97, y: 115)
        #expect(SharedEdges.edges(near: nearTopLeftVertical, of: frame, reach: reach) == [.minX])
        #expect(SharedEdges.edges(near: nearTopLeftVertical, of: frame, reach: reach, cornerReach: cornerReach) == [.minX, .minY])

        // 3 pt outside the right edge at mid height (x = 303, y = 200)
        let midRight = CGPoint(x: 303, y: 200)
        #expect(SharedEdges.edges(near: midRight, of: frame, reach: reach, cornerReach: cornerReach) == [.maxX])

        // 3 pt above the top edge (y = 97), 12 pt right of the left edge (x = 112)
        let nearTopLeftHorizontal = CGPoint(x: 112, y: 97)
        #expect(SharedEdges.edges(near: nearTopLeftHorizontal, of: frame, reach: reach, cornerReach: cornerReach) == [.minX, .minY])
    }

    @Test func movedEdgesIgnoresNudgesAndDetectsDeliberateMoves() {
        let initial = CGRect(x: 100, y: 100, width: 200, height: 200)
        // 2 pt nudge on minX and minY, 30 pt deliberate move on maxX, 0 pt on maxY
        // initial: minX = 100, maxX = 300, minY = 100, maxY = 300
        // current: minX = 98 (diff 2), maxX = 330 (diff 30), minY = 102 (diff 2), maxY = 300 (diff 0)
        let current = CGRect(x: 98, y: 102, width: 232, height: 198)
        let moved = SharedEdges.movedEdges(from: initial, to: current, threshold: 6)
        #expect(moved == [.maxX])
    }

    @Test(arguments: [0, 8] as [CGFloat])
    func twoHalvesLinksOppositeHalf(gap: CGFloat) {
        let width: CGFloat = 700
        let left = CGRect(x: 0, y: 0, width: width, height: 900)
        let right = CGRect(x: width + gap, y: 0, width: width, height: 900)
        let linked = SharedEdges.linkedEdges(of: left, edge: .maxX, among: [(id: "R", frame: right)], gap: gap)
        #expect(linked.count == 1)
        #expect(linked.first?.id == "R")
        #expect(linked.first?.edge == .minX)
    }

    @Test(arguments: [0, 8] as [CGFloat])
    func twoByTwoQuartersDraggingTopLeftMaxXLinksAllThreeOtherQuarters(gap: CGFloat) {
        let width: CGFloat = 600
        let height: CGFloat = 400
        let tl = CGRect(x: 0, y: 0, width: width, height: height)
        let tr = CGRect(x: width + gap, y: 0, width: width, height: height)
        let bl = CGRect(x: 0, y: height + gap, width: width, height: height)
        let br = CGRect(x: width + gap, y: height + gap, width: width, height: height)

        let candidates = [(id: "TR", frame: tr), (id: "BL", frame: bl), (id: "BR", frame: br)]
        let linked = SharedEdges.linkedEdges(of: tl, edge: .maxX, among: candidates, gap: gap)
        #expect(Set(linked.map(\.id)) == ["TR", "BL", "BR"])
        #expect(linked.first { $0.id == "TR" }?.edge == .minX)
        #expect(linked.first { $0.id == "BL" }?.edge == .maxX)
        #expect(linked.first { $0.id == "BR" }?.edge == .minX)
    }

    @Test(arguments: [0, 8] as [CGFloat])
    func twoByTwoQuartersDraggingTopLeftMaxYLinksAllThreeOtherQuarters(gap: CGFloat) {
        let width: CGFloat = 600
        let height: CGFloat = 400
        let tl = CGRect(x: 0, y: 0, width: width, height: height)
        let tr = CGRect(x: width + gap, y: 0, width: width, height: height)
        let bl = CGRect(x: 0, y: height + gap, width: width, height: height)
        let br = CGRect(x: width + gap, y: height + gap, width: width, height: height)

        let candidates = [(id: "TR", frame: tr), (id: "BL", frame: bl), (id: "BR", frame: br)]
        let linked = SharedEdges.linkedEdges(of: tl, edge: .maxY, among: candidates, gap: gap)
        #expect(Set(linked.map(\.id)) == ["TR", "BL", "BR"])
        #expect(linked.first { $0.id == "BL" }?.edge == .minY)
        #expect(linked.first { $0.id == "TR" }?.edge == .maxY)
        #expect(linked.first { $0.id == "BR" }?.edge == .minY)
    }

    @Test(arguments: [0, 8] as [CGFloat])
    func threeColumnsMiddleColumnMinXLinksOnlyLeftColumn(gap: CGFloat) {
        let width: CGFloat = 400
        let c1 = CGRect(x: 0, y: 0, width: width, height: 900)
        let c2 = CGRect(x: width + gap, y: 0, width: width, height: 900)
        let c3 = CGRect(x: 2 * (width + gap), y: 0, width: width, height: 900)

        let candidates = [(id: "C1", frame: c1), (id: "C3", frame: c3)]
        let linked = SharedEdges.linkedEdges(of: c2, edge: .minX, among: candidates, gap: gap)
        #expect(linked.map(\.id) == ["C1"])
        #expect(linked.first?.edge == .maxX)
    }

    @Test(arguments: [0, 8] as [CGFloat])
    func twoRowsThreeColumnsVerticalLineLinksAllFourWindowsOnIt(gap: CGFloat) {
        let width: CGFloat = 400
        let height: CGFloat = 450
        let r1c1 = CGRect(x: 0, y: 0, width: width, height: height)
        let r1c2 = CGRect(x: width + gap, y: 0, width: width, height: height)
        let r1c3 = CGRect(x: 2 * (width + gap), y: 0, width: width, height: height)
        let r2c1 = CGRect(x: 0, y: height + gap, width: width, height: height)
        let r2c2 = CGRect(x: width + gap, y: height + gap, width: width, height: height)
        let r2c3 = CGRect(x: 2 * (width + gap), y: height + gap, width: width, height: height)

        let candidates = [
            (id: "R1C2", frame: r1c2),
            (id: "R1C3", frame: r1c3),
            (id: "R2C1", frame: r2c1),
            (id: "R2C2", frame: r2c2),
            (id: "R2C3", frame: r2c3)
        ]
        let linked = SharedEdges.linkedEdges(of: r1c1, edge: .maxX, among: candidates, gap: gap)
        #expect(Set(linked.map(\.id)) == ["R1C2", "R2C1", "R2C2"])
        #expect(linked.first { $0.id == "R1C2" }?.edge == .minX)
        #expect(linked.first { $0.id == "R2C1" }?.edge == .maxX)
        #expect(linked.first { $0.id == "R2C2" }?.edge == .minX)
    }

    @Test func cornerEdgesMatchOppositeEdges() {
        #expect(ResizeGeometry.Corner.topLeft.edges == [.minX, .minY])
        #expect(ResizeGeometry.Corner.topRight.edges == [.maxX, .minY])
        #expect(ResizeGeometry.Corner.bottomLeft.edges == [.minX, .maxY])
        #expect(ResizeGeometry.Corner.bottomRight.edges == [.maxX, .maxY])
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
