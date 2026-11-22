import CoreGraphics
import Foundation
import Testing
@testable import Parc
@testable import ParcCore

struct NoteCanvasLayoutTestsFlow {
    private struct Stack {
        let a = NoteBlock.paragraph("a"), b = NoteBlock.paragraph("b"), h = NoteBlock.heading(1, "h"), c = NoteBlock.paragraph("c")
    }

    private func stacked() -> (Stack, NoteCanvasLayout) {
        let stack = Stack()
        return (stack, NoteCanvasLayoutTestsSupport.layout([stack.a, stack.b, stack.h, stack.c]))
    }

    @Test func thePageColumnIs720WideAndCentred() {
        let (_, result) = stacked()
        #expect(result.columnX == 140)
        #expect(result.columnWidth == 720)
    }

    @Test func theFirstBlockSitsUnderTheHeader() {
        let (stack, result) = stacked()
        #expect(result.frame(of: stack.a.id) == CGRect(x: 140, y: 104, width: 720, height: 26))
    }

    @Test func paragraphsKeepATwoPointGap() {
        let (stack, result) = stacked()
        #expect(result.frame(of: stack.b.id)?.minY == 132)
    }

    @Test func aHeadingTakesItsOwnBreathingRoom() {
        let (stack, result) = stacked()
        #expect(result.frame(of: stack.h.id)?.minY == 170)
    }

    @Test func theBlockAfterAHeadingGetsTheHeadingsAfterSpace() {
        let (stack, result) = stacked()
        #expect(result.frame(of: stack.c.id)?.minY == 214)
    }

    @Test func contentEndsAtTheLastBlock() {
        #expect(stacked().1.contentBottom == 240)
    }

    @Test func fullWidthKeeps96PointMargins() {
        let wide = NoteCanvasLayoutTestsSupport.layout([.paragraph("a")], width: 1400, fullWidth: true)
        #expect(wide.columnWidth == 1208)
        #expect(wide.columnX == 96)
    }

    @Test func narrowPanesShrinkTheMarginsFirst() {
        let narrow = NoteCanvasLayoutTestsSupport.layout([.paragraph("a")], width: 600)
        #expect(narrow.columnWidth == 544)
        #expect(narrow.columnX == 28)
    }

    @Test func noHeaderMeansTheTopInset() {
        let block = NoteBlock.paragraph("a")
        #expect(NoteCanvasLayoutTestsSupport.layout([block], header: 0).frame(of: block.id)?.minY == NoteCanvasMetrics().topInset)
    }

    @Test func shortPagesFillTheViewport() {
        #expect(stacked().1.documentHeight(viewportHeight: 800) == 800)
    }

    @Test func longPagesGetBottomRoom() {
        #expect(stacked().1.documentHeight(viewportHeight: 100) == 400)
    }

    private struct Nest {
        let grandchild = NoteBlock(.bulletedItem, text: "grandchild")
        let middle: NoteBlock
        let parent: NoteBlock
        let after = NoteBlock.paragraph("after")

        init() {
            var child = NoteBlock(.bulletedItem, text: "child")
            child.children = [grandchild]
            middle = child
            parent = NoteBlock(.bulletedItem, text: "parent", children: [child])
        }
    }

    private func nested() -> (Nest, NoteCanvasLayout) {
        let nest = Nest()
        return (nest, NoteCanvasLayoutTestsSupport.layout([nest.parent, nest.after]))
    }

    @Test func childrenIndentByTheIndentWidth() {
        let (nest, result) = nested()
        #expect(result.frame(of: nest.middle.id)?.minX == 166)
    }

    @Test func grandchildrenIndentAgainAndKeepTheRightEdge() {
        let (nest, result) = nested()
        #expect(result.frame(of: nest.grandchild.id)?.minX == 192)
        #expect(result.frame(of: nest.grandchild.id)?.width == 668)
    }

    @Test func childrenFollowTheirParentRow() {
        let (nest, result) = nested()
        #expect(result.frame(of: nest.middle.id)?.minY == 132)
    }

    @Test func theOuterFrameWrapsTheDescendants() {
        let (nest, result) = nested()
        #expect(result.outerFrame(of: nest.parent.id)?.maxY == 186)
    }

    @Test func theNextSiblingFollowsTheSubtree() {
        let (nest, result) = nested()
        #expect(result.frame(of: nest.after.id)?.minY == 188)
    }

    @Test func hitTestingFindsTheDeepestRow() {
        let (nest, result) = nested()
        #expect(result.blockID(at: CGPoint(x: 150, y: 140)) == nest.middle.id)
    }

    @Test func rowsReachIntoTheMargins() {
        let (nest, result) = nested()
        #expect(result.blockID(at: CGPoint(x: 20, y: 110)) == nest.parent.id)
    }

    @Test func theHeaderIsNotABlock() {
        #expect(nested().1.blockID(at: CGPoint(x: 300, y: 50)) == nil)
    }

    @Test func theSpaceBelowTheLastBlockIsEmpty() {
        #expect(nested().1.blockID(at: CGPoint(x: 300, y: 600)) == nil)
    }

    @Test func theGutterSitsLeftOfTheRow() {
        let (nest, result) = nested()
        #expect(result.gutterRect(for: nest.middle.id) == CGRect(x: 120, y: 132, width: 46, height: 26))
    }

    @Test func ancestorsWalkUp() {
        let (nest, result) = nested()
        #expect(result.ancestors(of: nest.grandchild.id) == [nest.middle.id, nest.parent.id])
    }

    @Test func aMarqueePicksRowsItTouches() {
        let (nest, result) = nested()
        #expect(result.blockIDs(in: CGRect(x: 0, y: 131, width: 1000, height: 31)) == [nest.middle.id, nest.grandchild.id])
    }

    @Test func numberingCountsRunsAndRestartsAfterABreak() {
        var numbered = (1...3).map { NoteBlock(.numberedItem, text: NoteText("n\($0)")) }
        numbered[0].props.listStart = 4
        let list = NoteCanvasLayoutTestsSupport.layout(numbered + [NoteBlock.paragraph("x"), NoteBlock(.numberedItem, text: "again")])
        #expect(list.entries.compactMap(\.listOrdinal) == [4, 5, 6, 1])
    }
}
