import Foundation
import Testing
@testable import ParcCore

struct EaselArrangeLayoutTests {
    @Test func undoingAMoveSelectsTheMovedObject() {
        let a = EaselArrangeTestsSupport.box(0, 0), b = EaselArrangeTestsSupport.box(300, 0)
        var arrow = EaselArrangeTestsSupport.box(100, 50, 200, 1, kind: .arrow)
        arrow.startConnection = EaselConnection(itemID: a.id, side: nil, anchor: nil)
        arrow.endConnection = EaselConnection(itemID: b.id, side: nil, anchor: nil)
        let board = EaselArrangeTestsSupport.document([a, b, arrow])
        var moved = board
        moved.items[0].frame.x = 40
        moved.items[2].frame.x = 140
        #expect(EaselArrange.historySelection(from: moved, to: board) == [a.id], "Undoing a move selects the moved object, not the connector that followed it")
        var removed = board
        removed.items.remove(at: 1)
        removed.items[2 - 1].endConnection = nil
        #expect(EaselArrange.historySelection(from: removed, to: board) == [b.id], "Undoing a delete selects what came back")
        #expect(EaselArrange.historySelection(from: board, to: removed) == nil, "Redoing a delete leaves the selection alone")
        var restacked = board
        for index in restacked.items.indices { restacked.items[index].zIndex = 10 - index }
        #expect(EaselArrange.historySelection(from: restacked, to: board) == nil, "Undoing a layer move keeps the current selection")
        var section = EaselArrangeTestsSupport.box(0, 0, 600, 400, kind: .section)
        section.zIndex = -1
        let inside = EaselArrangeTestsSupport.box(20, 20, 50, 50)
        let framed = EaselArrangeTestsSupport.document([section, inside])
        var dragged = framed
        dragged.items[0].frame.x = 100
        dragged.items[1].frame.x = 120
        #expect(EaselArrange.historySelection(from: dragged, to: framed) == [section.id], "Undoing a section move selects the section without its contents")
    }

    @Test
    func leftAlignmentUsesTheLeftmostEdge() {
        let a = EaselArrangeTestsSupport.box(10, 10), b = EaselArrangeTestsSupport.box(200, 50, 50, 50), c = EaselArrangeTestsSupport.box(90, 300, 300, 20)
        let board = EaselArrangeTestsSupport.document([a, b, c])
        let ids: Set<UUID> = [a.id, b.id, c.id]
        let left = EaselArrange.aligned(board, ids: ids, to: .left)
        #expect([a, b, c].allSatisfy { EaselArrangeTestsSupport.frame(left, $0.id)?.x == 10 }, "Align Left lines every object up with the leftmost edge")
    }

    @Test
    func rightAlignmentUsesTheRightmostEdge() {
        let a = EaselArrangeTestsSupport.box(10, 10), b = EaselArrangeTestsSupport.box(200, 50, 50, 50), c = EaselArrangeTestsSupport.box(90, 300, 300, 20)
        let board = EaselArrangeTestsSupport.document([a, b, c])
        let ids: Set<UUID> = [a.id, b.id, c.id]
        let right = EaselArrange.aligned(board, ids: ids, to: .right)
        #expect([a, b, c].allSatisfy { EaselArrangeTestsSupport.frame(right, $0.id).map { EaselArrangeTestsSupport.near($0.x + $0.width, 390) } == true }, "Align Right uses the rightmost edge")
    }

    @Test
    func horizontalCentreAlignmentUsesTheSelectionCentre() {
        let a = EaselArrangeTestsSupport.box(10, 10), b = EaselArrangeTestsSupport.box(200, 50, 50, 50), c = EaselArrangeTestsSupport.box(90, 300, 300, 20)
        let board = EaselArrangeTestsSupport.document([a, b, c])
        let ids: Set<UUID> = [a.id, b.id, c.id]
        let center = EaselArrange.aligned(board, ids: ids, to: .center)
        #expect([a, b, c].allSatisfy { EaselArrangeTestsSupport.frame(center, $0.id).map { EaselArrangeTestsSupport.near($0.x + $0.width / 2, 200) } == true }, "Align Center centres on the selection")
    }

    @Test
    func bottomAlignmentUsesTheLowestEdge() {
        let a = EaselArrangeTestsSupport.box(10, 10), b = EaselArrangeTestsSupport.box(200, 50, 50, 50), c = EaselArrangeTestsSupport.box(90, 300, 300, 20)
        let board = EaselArrangeTestsSupport.document([a, b, c])
        let ids: Set<UUID> = [a.id, b.id, c.id]
        let bottom = EaselArrange.aligned(board, ids: ids, to: .bottom)
        #expect([a, b, c].allSatisfy { EaselArrangeTestsSupport.frame(bottom, $0.id).map { EaselArrangeTestsSupport.near($0.y + $0.height, 320) } == true }, "Align Bottom uses the lowest edge")
    }

    @Test
    func verticalCentreAlignmentUsesTheSelectionCentre() {
        let a = EaselArrangeTestsSupport.box(10, 10), b = EaselArrangeTestsSupport.box(200, 50, 50, 50), c = EaselArrangeTestsSupport.box(90, 300, 300, 20)
        let board = EaselArrangeTestsSupport.document([a, b, c])
        let ids: Set<UUID> = [a.id, b.id, c.id]
        let middle = EaselArrange.aligned(board, ids: ids, to: .middle)
        #expect([a, b, c].allSatisfy { EaselArrangeTestsSupport.frame(middle, $0.id).map { EaselArrangeTestsSupport.near($0.y + $0.height / 2, 165) } == true }, "Align Middle centres vertically")
    }

    @Test
    func topAlignmentUsesTheHighestEdge() {
        let a = EaselArrangeTestsSupport.box(10, 10), b = EaselArrangeTestsSupport.box(200, 50, 50, 50), c = EaselArrangeTestsSupport.box(90, 300, 300, 20)
        let board = EaselArrangeTestsSupport.document([a, b, c])
        let ids: Set<UUID> = [a.id, b.id, c.id]
        #expect(EaselArrangeTestsSupport.frame(EaselArrange.aligned(board, ids: ids, to: .top), c.id)?.y == 10, "Align Top uses the highest edge")
    }

    @Test
    func aSingleObjectHasNothingToAlignTo() {
        let a = EaselArrangeTestsSupport.box(10, 10), b = EaselArrangeTestsSupport.box(200, 50, 50, 50), c = EaselArrangeTestsSupport.box(90, 300, 300, 20)
        let board = EaselArrangeTestsSupport.document([a, b, c])
        #expect(EaselArrange.aligned(board, ids: [a.id], to: .left) == nil, "One object has nothing to align to")
    }

    @Test
    func wholeGroupsAlignAsOneBlock() {
        var g1 = EaselArrangeTestsSupport.box(0, 0), g2 = EaselArrangeTestsSupport.box(150, 100)
        let group = UUID()
        g1.groupID = group; g2.groupID = group
        let loose = EaselArrangeTestsSupport.box(400, 400)
        let grouped = EaselArrangeTestsSupport.document([g1, g2, loose])
        let moved = EaselArrange.aligned(grouped, ids: [g1.id, g2.id, loose.id], to: .right)
        #expect(EaselArrangeTestsSupport.frame(moved, g1.id)?.x == 250 && EaselArrangeTestsSupport.frame(moved, g2.id)?.x == 400, "A whole group aligns as one block and keeps its shape")
        #expect(EaselArrangeTestsSupport.frame(moved, loose.id)?.x == 400, "The object with the rightmost edge stays put")
    }

    @Test
    func alignmentSkipsLockedObjects() {
        let a = EaselArrangeTestsSupport.box(10, 10), b = EaselArrangeTestsSupport.box(200, 50, 50, 50)
        var locked = EaselArrangeTestsSupport.box(500, 0); locked.locked = true
        let withLock = EaselArrangeTestsSupport.document([a, b, locked])
        let lockedResult = EaselArrange.aligned(withLock, ids: [a.id, b.id, locked.id], to: .left)
        #expect(EaselArrangeTestsSupport.frame(lockedResult, locked.id)?.x == 500, "Locked objects never move when aligning")
        #expect(EaselArrangeTestsSupport.frame(lockedResult, b.id)?.x == 10, "Locked objects don't count towards the alignment edge")
    }

    @Test
    func connectedArrowsDoNotAlignIndependently() {
        let a = EaselArrangeTestsSupport.box(10, 10), b = EaselArrangeTestsSupport.box(200, 50, 50, 50)
        var arrow = EaselItem(kind: .arrow, frame: EaselRect(x: 300, y: 300, width: 50, height: 50),
                              points: [EaselPoint(x: 0, y: 0), EaselPoint(x: 50, y: 50)])
        arrow.startConnection = EaselConnection(itemID: a.id)
        let connected = EaselArrangeTestsSupport.document([a, b, arrow])
        let skipped = EaselArrange.aligned(connected, ids: [a.id, b.id, arrow.id], to: .left)
        #expect(EaselArrangeTestsSupport.frame(skipped, arrow.id)?.x == 300, "Connected arrows follow their objects instead of aligning on their own")
    }

    @Test
    func aFreeArrowsManualBendsTravelWithIt() {
        let a = EaselArrangeTestsSupport.box(10, 10)
        var bent = EaselArrangeTestsSupport.box(400, 400, 10, 10, kind: .arrow)
        bent.points = [EaselPoint(x: 0, y: 0), EaselPoint(x: 10, y: 10)]
        bent.waypoints = [EaselPoint(x: 405, y: 450)]
        let bentResult = EaselArrange.aligned(EaselArrangeTestsSupport.document([a, bent]), ids: [a.id, bent.id], to: .left)
        #expect(bentResult?.items.first { $0.id == bent.id }?.waypoints == [EaselPoint(x: 15, y: 450)], "Manual bends travel with a free arrow")
    }

    @Test func distributeLeavesEqualGapsBetweenNeighbours() {
        let a = EaselArrangeTestsSupport.box(0, 0, 100), b = EaselArrangeTestsSupport.box(130, 0, 20), c = EaselArrangeTestsSupport.box(500, 0, 60)
        let board = EaselArrangeTestsSupport.document([c, a, b])
        let result = EaselArrange.distributed(board, ids: [a.id, b.id, c.id], along: .horizontal)
        guard let fa = EaselArrangeTestsSupport.frame(result, a.id), let fb = EaselArrangeTestsSupport.frame(result, b.id), let fc = EaselArrangeTestsSupport.frame(result, c.id) else {
            Issue.record("Distribute returns every object")
            return
        }
        let gap1 = fb.x - (fa.x + fa.width), gap2 = fc.x - (fb.x + fb.width)
        #expect(EaselArrangeTestsSupport.near(gap1, gap2) && EaselArrangeTestsSupport.near(gap1, 190), "Distribute leaves equal gaps between neighbours")
        #expect(fa.x == 0 && fc.x == 500, "The outermost objects stay where they are")
        #expect(EaselArrange.distributed(board, ids: [a.id, b.id], along: .horizontal) == nil, "Distributing needs three objects")
        let tall = EaselArrangeTestsSupport.document([EaselArrangeTestsSupport.box(0, 0, 10, 10), EaselArrangeTestsSupport.box(0, 15, 10, 50), EaselArrangeTestsSupport.box(0, 300, 10, 10)])
        let ids = Set(tall.items.map(\.id))
        let vertical = EaselArrange.distributed(tall, ids: ids, along: .vertical)
        let ys = vertical?.items.map(\.frame.y) ?? []
        #expect(ys.count == 3 && EaselArrangeTestsSupport.near(ys[1], 130), "Vertical distribution spaces rows evenly")
    }

    @Test func tidyUpStartsTheGridAtTheSelectionsCorner() {
        let a = EaselArrangeTestsSupport.box(0, 0), b = EaselArrangeTestsSupport.box(300, 10), c = EaselArrangeTestsSupport.box(10, 300), d = EaselArrangeTestsSupport.box(320, 290)
        let board = EaselArrangeTestsSupport.document([d, c, b, a])
        let tidy = EaselArrange.tidied(board, ids: [a.id, b.id, c.id, d.id])
        #expect(EaselArrangeTestsSupport.frame(tidy, a.id).map { $0.x == 0 && $0.y == 0 } == true, "Tidy up starts the grid at the selection's corner")
        #expect(EaselArrangeTestsSupport.frame(tidy, b.id).map { $0.x == 124 && $0.y == 0 } == true, "Tidy up keeps the row order and spaces cells evenly")
        #expect(EaselArrangeTestsSupport.frame(tidy, c.id).map { $0.x == 0 && $0.y == 124 } == true, "Tidy up starts a new row for the next row of objects")
        #expect(EaselArrangeTestsSupport.frame(tidy, d.id).map { $0.x == 124 && $0.y == 124 } == true, "Tidy up fills the grid in reading order")
        let pile = EaselArrangeTestsSupport.document((0..<9).map { EaselArrangeTestsSupport.box(Double($0) * 5, Double($0) * 3) })
        let piled = EaselArrange.tidied(pile, ids: Set(pile.items.map(\.id)))
        let xs = Set(piled?.items.map(\.frame.x) ?? []), ys = Set(piled?.items.map(\.frame.y) ?? [])
        #expect(xs.count == 3 && ys.count == 3, "A messy pile tidies into a square grid")
        let arrow = EaselArrangeTestsSupport.box(600, 600, 10, 10, kind: .arrow)
        #expect(!EaselArrange.canTidy([a.id, b.id, arrow.id], in: EaselArrangeTestsSupport.document([a, b, arrow])), "Connectors don't count towards Tidy up")
        #expect(EaselArrange.canTidy([a.id, b.id, c.id], in: board), "Three stickies can be tidied")
    }

    @Test func bringToFrontPutsTheSelectionOnTop() {
        let a = EaselArrangeTestsSupport.box(0, 0, z: 1), b = EaselArrangeTestsSupport.box(50, 50, z: 2), c = EaselArrangeTestsSupport.box(500, 500, z: 3), d = EaselArrangeTestsSupport.box(60, 60, z: 4)
        let board = EaselArrangeTestsSupport.document([a, b, c, d])
        func order(_ document: EaselDocument?) -> [UUID] { document.map { EaselArrange.paintOrder($0).map(\.id) } ?? [] }
        #expect(order(EaselArrange.layered(board, ids: [a.id], .front)) == [b.id, c.id, d.id, a.id], "Bring to Front puts the selection on top")
        #expect(order(EaselArrange.layered(board, ids: [d.id], .back)) == [d.id, a.id, b.id, c.id], "Send to Back puts the selection at the bottom")
        #expect(order(EaselArrange.layered(board, ids: [a.id], .forward)) == [b.id, a.id, c.id, d.id], "Bring Forward steps over the next overlapping object")
        #expect(order(EaselArrange.layered(board, ids: [b.id], .forward)) == [a.id, c.id, d.id, b.id], "Bring Forward skips objects it doesn't touch")
        #expect(EaselArrange.layered(board, ids: [c.id], .forward) == nil, "Nothing overlapping above means nothing changes")
        #expect(order(EaselArrange.layered(board, ids: [d.id], .backward)) == [a.id, d.id, b.id, c.id], "Send Backward steps under the next overlapping object")
        let renumbered = EaselArrange.layered(board, ids: [a.id], .front)
        #expect(renumbered.map { Set($0.items.map(\.zIndex)).count == 4 } == true, "Layer moves leave every object a distinct order")
        let huge = EaselArrangeTestsSupport.document([EaselArrangeTestsSupport.box(0, 0, z: Int.max), EaselArrangeTestsSupport.box(10, 10, z: Int.max - 1), EaselArrangeTestsSupport.box(20, 20, z: Int.min)])
        let overflow = EaselArrange.layered(huge, ids: [huge.items[2].id], .front)
        #expect(overflow.map { EaselArrange.paintOrder($0).last?.id == huge.items[2].id } == true, "Extreme orders renumber instead of overflowing")
        var locked = EaselArrangeTestsSupport.box(0, 0, z: 9); locked.locked = true
        #expect(EaselArrange.layered(EaselArrangeTestsSupport.document([a, locked]), ids: [locked.id], .back) == nil, "Locked objects keep their place in the stack")
        var g1 = EaselArrangeTestsSupport.box(0, 0, z: 1), g2 = EaselArrangeTestsSupport.box(10, 10, z: 3)
        let group = UUID(); g1.groupID = group; g2.groupID = group
        let between = EaselArrangeTestsSupport.box(5, 5, z: 2), top = EaselArrangeTestsSupport.box(20, 20, z: 4)
        let groupBoard = EaselArrangeTestsSupport.document([g1, g2, between, top])
        #expect(order(EaselArrange.layered(groupBoard, ids: [g1.id, g2.id], .front)) == [between.id, top.id, g1.id, g2.id], "A group moves through the stack together and keeps its own order")
        var stuck = EaselArrangeTestsSupport.box(55, 55, 10, 10, kind: .freehand, z: 3)
        stuck.points = [EaselPoint(x: 0, y: 0), EaselPoint(x: 10, y: 10)]
        stuck.attachedTo = b.id
        let stuckBoard = EaselArrangeTestsSupport.document([a, b, stuck, c, EaselArrangeTestsSupport.box(60, 60, z: 5)])
        let raised = order(EaselArrange.layered(stuckBoard, ids: [b.id], .front))
        #expect(raised.suffix(2) == [b.id, stuck.id], "Things stuck on an object come along to the front and stay on top of it")
    }
}
