import Foundation
import Testing
@testable import ParcCore

@MainActor struct PageEditingTextAndSelectionTests: NoteFixtures {
    @Test func duplicatingBlocksCopiesTheirChildrenAndSelectsTheCopies() {
        let session = makeSession([bullet("a", [bullet("a1")]), para("b")])
        let copies = session.duplicateBlocks([session.id("a"), session.id("a1")])
        expectOutline(session.page, "ul a\n  ul a1\nul a\n  ul a1\np b", "duplicate copies the block with its children right after")
        #expect(session.selection == .blocks(copies), "the copies are selected")
        #expect(Set(session.page.documentOrder()).count == 5, "every copy gets fresh ids")
    }

    @Test func deletingBlocksPutsTheCaretAtTheEndOfThePreviousBlock() {
        let removal = makeSession([para("keep"), image(), bullet("x", [bullet("y")]), para("tail")])
        removal.deleteBlocks([removal.page.blocks[1].id, removal.id("x")])
        expectOutline(removal.page, "p keep\np tail", "deleting removes blocks with their children")
        #expect(removal.selection == .caret(NotePosition(removal.id("keep"), 4)), "the caret lands at the end of the block above")
    }

    @Test func deletingTheFirstBlockSelectsTheNextBlock() {
        let leading = makeSession([para("gone"), image()])
        leading.deleteBlocks([leading.id("gone")])
        #expect(leading.selection == .blocks([leading.page.blocks[0].id]), "with nothing above, the next block is selected")
    }

    @Test func deletingEveryBlockLeavesOneEmptyLine() {
        let all = makeSession([para("one"), para("two")])
        all.deleteBlocks(all.page.blocks.map(\.id))
        expectOutline(all.page, "p", "deleting everything leaves one empty line")
        #expect(all.selection == .caret(NotePosition(all.page.blocks[0].id, 0)), "with the caret in it")
    }

    @Test func undoRestoresTheBlocksAfterDeletingEverything() {
        let all = makeSession([para("one"), para("two")])
        all.deleteBlocks(all.page.blocks.map(\.id))
        all.undo()
        expectOutline(all.page, "p one\np two", "and one undo brings it all back")
    }

    @Test func deletingTheLastBlockInAColumnFoldsTheLayoutAway() {
        let columnsPage = makeSession([columns([[para("x")], [para("y")]]), para("z")])
        columnsPage.deleteBlocks([columnsPage.id("y")])
        expectOutline(columnsPage.page, "p x\np z", "deleting the last block of a column folds the columns away")
    }

    @Test func typingOverABlockSelectionReplacesItWithText() {
        let typed = makeSession([para("a"), image(), para("c")])
        typed.setSelection(.blocks([typed.page.blocks[1].id]))
        typed.insertText(NoteText("Z"))
        expectOutline(typed.page, "p a\np Z\np c", "typing over selected blocks replaces them with a text line")
        #expect(typed.selection == .caret(NotePosition(typed.id("Z"), 1)), "the caret follows the typed letter")
    }

    @Test func aCaretColorsTheWholeBlock() {
        let session = makeSession([para("Hello world"), divider(), para("Other")])
        let hello = session.id("Hello world")
        session.setSelection(.caret(NotePosition(hello, 3)))
        session.setColor(.background(.yellow))
        #expect(session.page.block(hello)!.color == .background(.yellow), "with just a caret, the block gets the colour")
    }

    @Test func aTextSelectionColorsOnlyItsLettersAndKeepsTheBlockColor() {
        let session = makeSession([para("Hello world"), divider(), para("Other")])
        let hello = session.id("Hello world")
        session.setSelection(.caret(NotePosition(hello, 3)))
        session.setColor(.background(.yellow))
        session.setSelection(.text(anchor: NotePosition(hello, 0), head: NotePosition(hello, 5)))
        session.setColor(.text(.red))
        let text = session.page.block(hello)!.text
        #expect(text.marks(at: 0).color == .text(.red) && text.marks(at: 6).color == nil, "a text selection colours just those letters")
        #expect(session.page.block(hello)!.color == .background(.yellow), "the block colour stays")
    }

    @Test func coloringSelectedBlocksSkipsDividers() {
        let session = makeSession([para("Hello world"), divider(), para("Other")])
        let rule = session.page.blocks[1].id
        session.setColor(.text(.blue), in: .blocks([rule, session.id("Other")]))
        #expect(session.page.block(rule)!.color == nil, "dividers don't take colour")
        #expect(session.page.block(session.id("Other"))!.color == .text(.blue), "selected blocks take the colour")
    }

    @Test func choosingDefaultClearsTheBlockColor() {
        let session = makeSession([para("Hello world"), divider(), para("Other")])
        let hello = session.id("Hello world")
        session.setSelection(.caret(NotePosition(hello, 3)))
        session.setColor(.background(.yellow))
        session.setColor(nil, in: .blocks([hello]))
        #expect(session.page.block(hello)!.color == nil, "Default clears the block colour")
    }

    @Test func removingALinkAtTheCaretClearsTheWholeLink() {
        let linked = makeSession([NoteBlock(.paragraph, text: NoteText(pieces: [("see ", .plain), ("the site", marks { $0.link = "https://a" }), (" now", .plain)]))])
        let linkedID = linked.page.blocks[0].id
        linked.setSelection(.caret(NotePosition(linkedID, 6)))
        linked.setLink(nil)
        #expect(linked.page.blocks[0].text.runs().allSatisfy { $0.marks.link == nil }, "removing a link at a caret clears the whole link")
    }

    @Test func linkingASelectionMarksOnlyItsRange() {
        let linked = makeSession([NoteBlock(.paragraph, text: NoteText(pieces: [("see ", .plain), ("the site", marks { $0.link = "https://a" }), (" now", .plain)]))])
        let linkedID = linked.page.blocks[0].id
        linked.setSelection(.caret(NotePosition(linkedID, 6)))
        linked.setLink(nil)
        linked.setSelection(.text(anchor: NotePosition(linkedID, 0), head: NotePosition(linkedID, 3)))
        linked.setLink("https://b")
        #expect(linked.page.blocks[0].text.linkRange(at: 1) == 0..<3, "linking a selection marks just that range")
    }

    @Test func typingOverSelectedCellsReplacesTheirContentsInOneUndoStep() {
        let grid = makeSession([table([["a", "b"], ["c", "d"]])])
        let gridID = grid.page.blocks[0].id
        grid.setSelection(.cells(table: gridID, anchor: NoteTableCell(row: 1, column: 1), head: NoteTableCell(row: 0, column: 0)))
        grid.insertText(NoteText("z"))
        expectOutline(grid.page, "table z|/|", "typing over selected cells clears them and types into the first")
        #expect(grid.selection == .caret(NotePosition(gridID, 1, field: .cell(row: 0, column: 0))), "the caret follows the typing")
        #expect(grid.undoDepth == 1, "and it's one step")
    }

    @Test func closingAToggleMovesTheCaretFromItsChildToItsTitle() {
        let session = makeSession([toggle("Fold", expanded: true, [para("inside")]), todo("a"), todo("b", checked: true)])
        let fold = session.id("Fold")
        session.setSelection(.caret(NotePosition(session.id("inside"), 2)))
        session.toggleExpanded(fold)
        #expect(session.page.block(fold)!.isCollapsed, "the toggle closes")
        #expect(session.selection == .caret(NotePosition(fold, 4)), "a caret inside a closing toggle moves to its title")
    }

    @Test func expandAllOpensAClosedToggle() {
        let session = makeSession([toggle("Fold", expanded: true, [para("inside")]), todo("a"), todo("b", checked: true)])
        let fold = session.id("Fold")
        session.setSelection(.caret(NotePosition(session.id("inside"), 2)))
        session.toggleExpanded(fold)
        session.setAllToggles(expanded: true)
        #expect(!session.page.block(fold)!.isCollapsed, "expand all opens it")
    }

    @Test func togglingMixedTasksChecksThemAll() {
        let session = makeSession([toggle("Fold", expanded: true, [para("inside")]), todo("a"), todo("b", checked: true)])
        session.toggleChecked([session.id("a"), session.id("b")])
        #expect(session.page.blocks[1].props.checked && session.page.blocks[2].props.checked, "mixed to-dos all get checked")
    }

    @Test func togglingCheckedTasksUnchecksThemAll() {
        let session = makeSession([toggle("Fold", expanded: true, [para("inside")]), todo("a"), todo("b", checked: true)])
        session.toggleChecked([session.id("a"), session.id("b")])
        session.toggleChecked([session.id("a"), session.id("b")])
        #expect(!session.page.blocks[1].props.checked && !session.page.blocks[2].props.checked, "then all get unchecked")
    }

    @Test func enterOnASelectedClosedToggleOpensIt() {
        let session = makeSession([toggle("Fold", expanded: true, [para("inside")]), todo("a"), todo("b", checked: true)])
        let fold = session.id("Fold")
        session.setSelection(.blocks([fold]))
        session.toggleExpanded(fold)
        session.insertBlockBreak()
        #expect(!session.page.block(fold)!.isCollapsed, "Enter on selected closed toggles opens them")
    }
}
