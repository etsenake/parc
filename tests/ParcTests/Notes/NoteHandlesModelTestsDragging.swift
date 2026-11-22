import Foundation
import Testing
@testable import ParcCore
@testable import ParcNotes

struct NoteHandlesModelTestsDragging {
    private func pageWithCopy() -> (NotePage, NoteBlock, NoteBlock) {
        let a = NoteBlock.paragraph("a"), b = NoteBlock.paragraph("b")
        var page = NotePage(blocks: [a, b])
        page.place([.paragraph("copy")], beside: b.id, side: .left)
        return (page, a, b)
    }

    @Test func droppingBesideABlockMakesColumnsInItsPlace() {
        let (page, _, _) = pageWithCopy()
        #expect(page.blocks.count == 2)
        #expect(page.blocks[1].kind == .columns)
    }

    @Test func theLeftSidePutsTheCopyFirst() {
        #expect(pageWithCopy().0.blocks[1].children.map { $0.children.map(\.text.string) } == [["copy"], ["b"]])
    }

    @Test func besideAColumnBlockAddsAColumnNextToIt() {
        var (page, _, b) = pageWithCopy()
        let row = page.blocks[1].id
        page.update(row) { columns in for index in columns.children.indices { columns.children[index].props.width = 0.5 } }
        page.place([.paragraph("third")], beside: b.id, side: .right)
        let columns = page.block(row)!.children
        #expect(columns.map { $0.children.map(\.text.string) } == [["copy"], ["b"], ["third"]])
        #expect(columns.allSatisfy { $0.props.width == nil })
    }

    @Test func fiveColumnsIsTheLimit() {
        var full = NotePage(blocks: [NoteBlock(.columns, children: (0..<5).map { NoteBlock(.column, children: [NoteBlock.paragraph(NoteText("\($0)"))]) })])
        let before = full
        full.place([NoteBlock.paragraph("six")], beside: full.blocks[0].children[2].children[0].id, side: .right)
        #expect(full == before)
    }

    @Test func placingNothingChangesNothing() {
        let a = NoteBlock.paragraph("a")
        var page = NotePage(blocks: [a])
        page.place([], beside: a.id, side: .right)
        #expect(page.blocks == [a])
    }

    private struct Dragging {
        let a = NoteBlock.paragraph("a"), c = NoteBlock(.bulletedItem, text: "c")
        let b: NoteBlock
        let d = NoteBlock.paragraph("d")
        let left = NoteBlock(.column, children: [NoteBlock.paragraph("l")])
        let page: NotePage

        init() {
            b = NoteBlock(.bulletedItem, text: "b", children: [c])
            let right = NoteBlock(.column, children: [NoteBlock.paragraph("r")])
            page = NotePage(blocks: [a, b, d, NoteBlock(.columns, children: [left, right])])
        }
    }

    private let drag = Dragging()

    @Test func anUnselectedBlockDragsAlone() {
        #expect(NoteDragPlan.draggedBlocks(grabbing: drag.d.id, selection: .none, page: drag.page) == [drag.d.id])
    }

    @Test func aSelectionDragsInDocumentOrder() {
        #expect(NoteDragPlan.draggedBlocks(grabbing: drag.d.id, selection: .blocks([drag.d.id, drag.a.id]), page: drag.page) == [drag.a.id, drag.d.id])
    }

    @Test func grabbingOutsideTheSelectionDragsJustThatBlock() {
        #expect(NoteDragPlan.draggedBlocks(grabbing: drag.a.id, selection: .blocks([drag.b.id]), page: drag.page) == [drag.a.id])
    }

    @Test func childrenTravelWithTheirSelectedParent() {
        #expect(NoteDragPlan.draggedBlocks(grabbing: drag.c.id, selection: .blocks([drag.b.id, drag.c.id, drag.a.id]), page: drag.page) == [drag.a.id, drag.b.id])
    }

    @Test func aBareColumnCannotBeDragged() {
        #expect(NoteDragPlan.draggedBlocks(grabbing: drag.left.id, selection: .none, page: drag.page).isEmpty)
    }

    @Test func missingBlocksDragNothing() {
        #expect(NoteDragPlan.draggedBlocks(grabbing: NoteBlockID(), selection: .none, page: drag.page).isEmpty)
    }

    @Test func dimmingCoversVisibleChildren() {
        #expect(NoteDragPlan.affectedBlocks([drag.b.id], page: drag.page) == [drag.b.id, drag.c.id])
    }

    @Test func droppingBesideAnotherBlockIsFine() {
        #expect(NoteDragPlan.canDrop([drag.b.id], onto: drag.d.id, page: drag.page))
    }

    @Test func aBlockCannotBeDroppedIntoItself() {
        #expect(!NoteDragPlan.canDrop([drag.b.id], onto: drag.c.id, page: drag.page))
    }

    @Test func aBlockCannotBeDroppedOntoItself() {
        #expect(!NoteDragPlan.canDrop([drag.b.id], onto: drag.b.id, page: drag.page))
    }

    @Test func aWobbleIsStillAClick() {
        #expect(!NoteDragPlan.crossesThreshold(from: .zero, to: CGPoint(x: 2, y: 2)))
    }

    @Test func aRealMoveStartsADrag() {
        #expect(NoteDragPlan.crossesThreshold(from: .zero, to: CGPoint(x: 3, y: 3)))
    }

    private var closedToggle: NoteBlock {
        var toggle = NoteBlock(.toggle, text: "t")
        toggle.props.expanded = false
        return toggle
    }

    @Test func aToggleWaitsBeforeOpening() {
        #expect(!NoteDragPlan.shouldExpand(closedToggle, hoveredSince: 10, now: 10.5))
    }

    @Test func aClosedToggleOpensAfterSixTenthsOfASecond() {
        #expect(NoteDragPlan.shouldExpand(closedToggle, hoveredSince: 10, now: 10.6))
    }

    @Test func onlyTogglesOpen() {
        #expect(!NoteDragPlan.shouldExpand(drag.a, hoveredSince: 10, now: 20))
    }

    @Test func noHoverNoOpening() {
        #expect(!NoteDragPlan.shouldExpand(closedToggle, hoveredSince: nil, now: 20))
    }

    @Test func copiesKeepDocumentOrder() {
        let copies = NoteDragPlan.copies(of: [drag.d.id, drag.b.id, drag.c.id], in: drag.page)
        #expect(copies.map(\.text.string) == ["b", "d"])
    }

    @Test func copiesGetFreshIDs() {
        let copies = NoteDragPlan.copies(of: [drag.d.id, drag.b.id, drag.c.id], in: drag.page)
        #expect(copies.allSatisfy { $0.id != drag.b.id && $0.id != drag.d.id })
    }

    @Test func copiedChildrenAreFreshToo() {
        let copies = NoteDragPlan.copies(of: [drag.d.id, drag.b.id, drag.c.id], in: drag.page)
        #expect(copies[0].children.first?.id != drag.c.id)
        #expect(copies[0].children.first?.text.string == "c")
    }

    @Test func theGhostKeepsTheGrabOffset() {
        #expect(NoteDragPlan.ghostOrigin(pointer: CGPoint(x: 100, y: 80), grabOffset: CGPoint(x: 10, y: 5)) == CGPoint(x: 90, y: 75))
    }
}
