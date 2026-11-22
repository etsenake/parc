import Foundation
import Testing
@testable import Parc
@testable import ParcCore

struct NoteHandlesModelTestsHandleGeometryAndScrolling {
    private let frame = CGRect(x: 200, y: 100, width: 400, height: 60)

    @Test func theGripSitsASmallGapLeftOfTheBlock() {
        #expect(NoteHandleGeometry.rects(blockFrame: frame, anchorY: 14).grip.maxX == frame.minX - NoteHandleGeometry.contentGap)
    }

    @Test func plusComesBeforeTheGrip() {
        let rects = NoteHandleGeometry.rects(blockFrame: frame, anchorY: 14)
        #expect(rects.plus.maxX == rects.grip.minX - NoteHandleGeometry.buttonGap)
    }

    @Test func bothCentreOnTheBlocksFirstLine() {
        let rects = NoteHandleGeometry.rects(blockFrame: frame, anchorY: 14)
        #expect(rects.plus.midY == 114)
        #expect(rects.grip.midY == 114)
    }

    @Test func buttonsKeepTheirSize() {
        #expect(NoteHandleGeometry.rects(blockFrame: frame, anchorY: 14).plus.size == NoteHandleGeometry.buttonSize)
    }

    @Test func nestedBlocksGetHandlesAtTheirIndent() {
        let rects = NoteHandleGeometry.rects(blockFrame: frame, anchorY: 14)
        #expect(NoteHandleGeometry.rects(blockFrame: frame.offsetBy(dx: 26, dy: 0), anchorY: 14).grip.minX == rects.grip.minX + 26)
    }

    @Test func handlesNeverLeaveTheCanvas() {
        #expect(NoteHandleGeometry.rects(blockFrame: CGRect(x: 10, y: 0, width: 300, height: 20), anchorY: 10, minimumX: 0).plus.minX >= 0)
    }

    @Test func theBarHoldsBothButtons() {
        #expect(NoteHandleGeometry.barWidth == NoteHandleGeometry.buttonSize.width * 2 + NoteHandleGeometry.buttonGap)
    }

    private struct Targets {
        let a = NoteBlockID(), b = NoteBlockID(), child = NoteBlockID(), container = NoteBlockID(), left = NoteBlockID(), right = NoteBlockID()

        var flat: [NoteHandleTarget] {
            [NoteHandleTarget(id: a, frame: CGRect(x: 100, y: 0, width: 500, height: 30), depth: 0, anchorY: 15),
             NoteHandleTarget(id: b, frame: CGRect(x: 100, y: 32, width: 500, height: 30), depth: 0, anchorY: 15)]
        }

        var tree: [NoteHandleTarget] {
            [NoteHandleTarget(id: container, frame: CGRect(x: 100, y: 0, width: 500, height: 100), depth: 0, anchorY: 15),
             NoteHandleTarget(id: child, frame: CGRect(x: 126, y: 40, width: 474, height: 30), depth: 1, anchorY: 15)]
        }

        var columns: [NoteHandleTarget] {
            [NoteHandleTarget(id: left, frame: CGRect(x: 100, y: 0, width: 220, height: 30), depth: 2, anchorY: 15),
             NoteHandleTarget(id: right, frame: CGRect(x: 366, y: 0, width: 220, height: 30), depth: 2, anchorY: 15)]
        }
    }

    private let targets = Targets()

    @Test func thePointerOverABlockPicksIt() {
        #expect(NoteHandleGeometry.target(at: CGPoint(x: 300, y: 10), in: targets.flat)?.id == targets.a)
    }

    @Test func theLeftGutterCountsAsTheBlock() {
        #expect(NoteHandleGeometry.target(at: CGPoint(x: 70, y: 40), in: targets.flat)?.id == targets.b)
    }

    @Test func theGapBetweenBlocksStillShowsAHandle() {
        #expect(NoteHandleGeometry.target(at: CGPoint(x: 300, y: 31), in: targets.flat) != nil)
    }

    @Test(arguments: [CGPoint(x: 20, y: 10), CGPoint(x: 300, y: 200)])
    func farFromTheBlocksShowsNothing(point: CGPoint) {
        #expect(NoteHandleGeometry.target(at: point, in: targets.flat) == nil)
    }

    @Test func theDeepestBlockUnderThePointerWins() {
        #expect(NoteHandleGeometry.target(at: CGPoint(x: 300, y: 50), in: targets.tree)?.id == targets.child)
    }

    @Test func aNestedBlocksGutterIsItsOwn() {
        #expect(NoteHandleGeometry.target(at: CGPoint(x: 110, y: 50), in: targets.tree)?.id == targets.child)
    }

    @Test func theContainersOwnRowIsTheContainer() {
        #expect(NoteHandleGeometry.target(at: CGPoint(x: 300, y: 10), in: targets.tree)?.id == targets.container)
    }

    @Test func eachColumnBlockHasItsOwnHandle() {
        #expect(NoteHandleGeometry.target(at: CGPoint(x: 400, y: 10), in: targets.columns)?.id == targets.right)
    }

    @Test func theColumnGapBelongsToTheNextColumn() {
        #expect(NoteHandleGeometry.target(at: CGPoint(x: 345, y: 10), in: targets.columns)?.id == targets.right)
    }

    @Test func justPastAColumnsEdgeIsStillThatColumn() {
        #expect(NoteHandleGeometry.target(at: CGPoint(x: 325, y: 10), in: targets.columns)?.id == targets.left)
    }

    private func velocity(_ pointerY: CGFloat, top: CGFloat = 1000, bottom: CGFloat = 1600) -> CGFloat {
        NoteAutoscroll.velocity(pointerY: pointerY, visibleMinY: top, visibleMaxY: bottom)
    }

    @Test func theMiddleOfTheViewNeverScrolls() {
        #expect(velocity(1300) == 0)
    }

    @Test func theTopEdgeScrollsUpFasterTheCloserYouGet() {
        let near = velocity(1040), at = velocity(1000), above = velocity(940)
        #expect(near < 0)
        #expect(at < near)
        #expect(above < at)
    }

    @Test func speedTopsOut() {
        #expect(velocity(1000 - 5000) == -NoteAutoscroll.maximumSpeed)
    }

    @Test func theEdgeZoneNeverCrawlsBelowTheMinimumSpeed() {
        #expect(velocity(1040) <= -NoteAutoscroll.minimumSpeed)
    }

    @Test func theBottomEdgeMirrorsTheTop() {
        #expect(velocity(1600 - 40) == -velocity(1000 + 40))
    }

    @Test func justOutsideTheZoneIsStill() {
        #expect(velocity(1000 + NoteAutoscroll.edgeZone + 1) == 0)
    }

    @Test func aShortViewKeepsAStillMiddle() {
        #expect(velocity(50, top: 0, bottom: 120) == 0)
    }

    @Test func aFrameMovesVelocityTimesTime() {
        #expect(NoteAutoscroll.step(velocity: 600, elapsed: 1.0 / 60) == 10)
    }

    @Test func aStalledFrameNeverJumpsFar() {
        #expect(NoteAutoscroll.step(velocity: 600, elapsed: 2) == 30)
    }
}
