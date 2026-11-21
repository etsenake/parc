import Foundation
import Testing
@testable import ParcCore

@MainActor struct PageSmokeTests {
    @Test func piecesBuildSpansAndTypingBeforeBoldStaysPlain() {
        var bold = NoteMarks.plain
        bold.bold = true
        var text = NoteText(pieces: [("Hello ", .plain), ("world", bold)])
        #expect(text.length == 11 && text.spans.count == 2, "pieces build two spans")
        text.insert("big ", at: 6)
        #expect(text.string == "Hello big world", "insert keeps text")
        #expect(text.marks(at: 6).bold == false, "typing before a bold run stays plain")
    }

    @Test func splitAndMergeUndoAndRedo() throws {
        let first = NoteBlock.paragraph("One two")
        let session = NotePageSession(page: NotePage(blocks: [first]))
        let fresh = try #require(session.splitBlock(at: NotePosition(first.id, 3)))
        #expect(session.page.blocks.count == 2 && session.page.blocks[0].text.string == "One"
               && session.page.blocks[1].text.string == " two", "split divides the text")
        #expect(session.selection.caret == NotePosition(fresh, 0), "split moves the caret to the new block")
        session.mergeBackward(fresh)
        #expect(session.page.blocks.count == 1 && session.page.blocks[0].text.string == "One two", "merge joins them back")
        session.undo()
        #expect(session.page.blocks.count == 2, "undo restores the split")
        session.redo()
        #expect(session.page.blocks.count == 1, "redo merges again")
    }

    @Test func indentAndOutdentMoveAListItemUnderItsNeighbour() {
        let item = NoteBlock(.bulletedItem, text: "a")
        let child = NoteBlock(.bulletedItem, text: "b")
        let list = NotePageSession(page: NotePage(blocks: [item, child]))
        #expect(list.indent([child.id]), "indent nests under a list item")
        #expect(list.page.blocks.count == 1 && list.page.blocks[0].children.first?.id == child.id, "child moved under parent")
        #expect(list.outdent([child.id]), "outdent lifts it back")
        #expect(list.page.blocks.count == 2, "back to siblings")
    }
}
