import CoreGraphics
import Foundation
import Testing
@testable import ParcCore
@testable import ParcNotes

@MainActor
struct NoteSelectionModelTestsOrderingAndHighlights {
    private typealias Block = NoteSelectionModelTestsSupport.Layout.Block

    private func navigator(_ blocks: [Block]) -> (NoteSelectionNavigator, NoteSelectionModelTestsSupport.Layout) {
        let layout = NoteSelectionModelTestsSupport.Layout(blocks)
        return (NoteSelectionNavigator(items: layout.items), layout)
    }

    private let a = Block(text: "first"), b = Block(text: "second")

    @Test func anEarlierBlockPrecedes() {
        let (nav, _) = navigator([a, b])
        #expect(nav.precedes(NotePosition(a.id, 4), NotePosition(b.id, 0)))
    }

    @Test func aLaterBlockFollows() {
        let (nav, _) = navigator([a, b])
        #expect(!nav.precedes(NotePosition(b.id, 0), NotePosition(a.id, 4)))
    }

    @Test func theSameBlockComparesOffsets() {
        let (nav, _) = navigator([a, b])
        #expect(nav.precedes(NotePosition(a.id, 1), NotePosition(a.id, 2)))
    }

    @Test func orderedSwapsBackwardEnds() {
        let (nav, _) = navigator([a, b])
        let ends = nav.ordered(NotePosition(b.id, 2), NotePosition(a.id, 3))
        #expect(ends.start == NotePosition(a.id, 3))
        #expect(ends.end == NotePosition(b.id, 2))
    }

    @Test func theBodyComesBeforeTheCaptionWhateverTheOffsets() {
        let (nav, _) = navigator([a, b])
        let caption = NotePosition(a.id, 0, field: .caption), body = NotePosition(a.id, 4)
        #expect(nav.precedes(body, caption))
        #expect(!nav.precedes(caption, body))
    }

    @Test func cellsRunRowByRow() {
        let (nav, _) = navigator([a, b])
        let cell = NotePosition(a.id, 9, field: .cell(row: 0, column: 1)), later = NotePosition(a.id, 0, field: .cell(row: 1, column: 0))
        #expect(nav.precedes(cell, later))
    }

    @Test func cellsComeBeforeTheCaption() {
        let (nav, _) = navigator([a, b])
        let later = NotePosition(a.id, 0, field: .cell(row: 1, column: 0))
        #expect(nav.precedes(later, NotePosition(a.id, 0, field: .caption)))
    }

    @Test func orderingASameBlockSpanLooksAtTheFieldFirst() {
        let (nav, _) = navigator([a, b])
        #expect(nav.ordered(NotePosition(a.id, 0, field: .caption), NotePosition(a.id, 4)).start == NotePosition(a.id, 4))
    }

    @MainActor private struct MarkBlocks {
        let a = Block(text: "hello there"), image = Block(role: .object), divider = Block(role: .decoration)
        let b = Block(text: "middle"), c = Block(text: "the end")
        var all: [Block] { [a, image, b, divider, c] }
    }

    private func marksAcross() -> (MarkBlocks, [NoteBlockID: NoteSelectionMark]) {
        let blocks = MarkBlocks()
        let (nav, layout) = navigator(blocks.all)
        return (blocks, nav.marks(from: NotePosition(blocks.c.id, 3), to: NotePosition(blocks.a.id, 6)) { layout.length(of: NotePosition($0, 0)) })
    }

    @Test func theAnchorBlockHighlightsItsTail() {
        let (blocks, marks) = marksAcross()
        #expect(marks[blocks.a.id] == .text(6..<11))
    }

    @Test func objectsInTheMiddleGetTheWash() {
        let (blocks, marks) = marksAcross()
        #expect(marks[blocks.image.id] == .wash)
        #expect(marks[blocks.divider.id] == .wash)
    }

    @Test func middleTextIsFullyHighlighted() {
        let (blocks, marks) = marksAcross()
        #expect(marks[blocks.b.id] == .text(0..<6))
    }

    @Test func theHeadBlockHighlightsItsStart() {
        let (blocks, marks) = marksAcross()
        #expect(marks[blocks.c.id] == .text(0..<3))
    }

    @Test func highlightsNameTheirField() {
        let (blocks, marks) = marksAcross()
        #expect(marks[blocks.a.id]?.highlight?.field == .body)
    }

    @Test func aSingleBlockRangeIsOrdered() {
        let blocks = MarkBlocks()
        let (nav, _) = navigator(blocks.all)
        #expect(nav.marks(from: NotePosition(blocks.b.id, 4), to: NotePosition(blocks.b.id, 1)) { _ in 0 } == [blocks.b.id: .text(1..<4)])
    }

    @Test func aCaretDrawsNothing() {
        let blocks = MarkBlocks()
        let (nav, _) = navigator(blocks.all)
        #expect(nav.marks(from: NotePosition(blocks.b.id, 2), to: NotePosition(blocks.b.id, 2)) { _ in 0 }.isEmpty)
    }

    @Test func theAnchorKeepsItsLineEnd() {
        let blocks = MarkBlocks()
        let (nav, layout) = navigator(blocks.all)
        let touching = nav.marks(from: NotePosition(blocks.a.id, 11), to: NotePosition(blocks.c.id, 0)) { layout.length(of: NotePosition($0, 0)) }
        #expect(touching[blocks.a.id] == .text(11..<11))
    }

    @Test func touchingTheHeadBlockAtItsStartDrawsNothing() {
        let blocks = MarkBlocks()
        let (nav, layout) = navigator(blocks.all)
        let touching = nav.marks(from: NotePosition(blocks.a.id, 11), to: NotePosition(blocks.c.id, 0)) { layout.length(of: NotePosition($0, 0)) }
        #expect(touching[blocks.c.id] == nil)
    }

    @Test func coveredBlocksAreListed() {
        let blocks = MarkBlocks()
        let (nav, _) = navigator(blocks.all)
        #expect(nav.covered(from: NotePosition(blocks.a.id, 2), to: NotePosition(blocks.b.id, 1)) == [blocks.a.id, blocks.image.id, blocks.b.id])
    }

    @Test func aSpanAcrossTwoFieldsOfOneBlockWashesIt() {
        let blocks = MarkBlocks()
        let (nav, _) = navigator(blocks.all)
        #expect(nav.marks(from: NotePosition(blocks.b.id, 4, field: .caption), to: NotePosition(blocks.b.id, 1)) { _ in 6 } == [blocks.b.id: .wash])
    }

    @Test func aCaptionSpanPaintsTheCaption() {
        let blocks = MarkBlocks()
        let (nav, _) = navigator(blocks.all)
        let marks = nav.marks(from: NotePosition(blocks.b.id, 5, field: .caption), to: NotePosition(blocks.b.id, 2, field: .caption)) { _ in 6 }
        #expect(marks == [blocks.b.id: .field(.caption, 2..<5)])
        #expect(marks[blocks.b.id]?.highlight?.field == .caption)
    }

    @Test func aCaptionStartNeverPaintsItsOffsetsOntoTheBody() {
        let blocks = MarkBlocks()
        let (nav, layout) = navigator(blocks.all)
        let marks = nav.marks(from: NotePosition(blocks.a.id, 3, field: .caption), to: NotePosition(blocks.b.id, 2)) { layout.length(of: NotePosition($0, 0)) }
        #expect(marks[blocks.a.id] == .wash)
        #expect(marks[blocks.b.id] == .text(0..<2))
    }
}
