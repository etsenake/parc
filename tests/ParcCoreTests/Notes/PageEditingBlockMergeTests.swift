import Foundation
import Testing
@testable import ParcCore

@MainActor struct PageEditingBlockMergeTests: NoteFixtures {
    @Test func backspaceTurnsANestedListItemIntoTextInPlace() {
        let session = makeSession([bullet("a", [bullet("b")])])
        let b = session.id("b")
        session.mergeBackward(b)
        expectOutline(session.page, "ul a\n  p b", "the first Backspace turns the item into text in place")
        #expect(session.selection == .caret(NotePosition(b, 0)), "the caret stays at the start")
    }

    @Test func backspaceOutdentsATextLineUnderAListItem() {
        let session = makeSession([bullet("a", [bullet("b")])])
        let b = session.id("b")
        session.mergeBackward(b)
        session.mergeBackward(b)
        expectOutline(session.page, "ul a\np b", "the second Backspace outdents")
    }

    @Test func backspaceMergesAnOutdentedLineIntoTheItemAbove() {
        let session = makeSession([bullet("a", [bullet("b")])])
        let b = session.id("b")
        session.mergeBackward(b)
        session.mergeBackward(b)
        session.mergeBackward(b)
        expectOutline(session.page, "ul ab", "the third Backspace merges into the line above")
        #expect(session.selection == .caret(NotePosition(session.id("ab"), 1)), "the caret sits at the join")
    }

    @Test func backspaceAtAHeadingStartTurnsItIntoText() {
        let heading = makeSession([para("x"), NoteBlock.heading(1, "Head")])
        heading.mergeBackward(heading.id("Head"))
        expectOutline(heading.page, "p x\np Head", "Backspace turns headings into text first")
    }

    @Test func mergingKeepsBothSidesMarks() {
        let styled = makeSession([NoteBlock(.paragraph, text: NoteText(pieces: [("bold", boldMarks)])), para("plain")])
        styled.mergeBackward(styled.id("plain"))
        let merged = styled.page.blocks[0].text
        #expect(merged.string == "boldplain" && merged.marks(at: 0).bold && !merged.marks(at: 4).bold, "merging keeps both sides' marks")
    }

    @Test func backspaceOutdentsAToggleChildAndAdoptsTheFollowingLines() {
        let middle = makeSession([toggle("T", expanded: true, [para("one"), para("two")])])
        middle.mergeBackward(middle.id("one"))
        expectOutline(middle.page, "toggle T\np one\n  p two", "a nested line outdents first and adopts the lines after it")
    }

    @Test func backspaceMergesAnOutdentedToggleChildAndKeepsItsChildren() {
        let middle = makeSession([toggle("T", expanded: true, [para("one"), para("two")])])
        middle.mergeBackward(middle.id("one"))
        middle.mergeBackward(middle.id("one"))
        expectOutline(middle.page, "toggle Tone\n  p two", "then merges, and its children stay nested")
    }

    @Test func backspaceOutdentsALineUnderText() {
        let underText = makeSession([block(.paragraph, "lead", [para("kid")])])
        underText.mergeBackward(underText.id("kid"))
        expectOutline(underText.page, "p lead\np kid", "Backspace outdents a line nested under text")
    }

    @Test func backspaceMergesAnOutdentedLineIntoTheParagraphAbove() {
        let underText = makeSession([block(.paragraph, "lead", [para("kid")])])
        underText.mergeBackward(underText.id("kid"))
        underText.mergeBackward(underText.id("kid"))
        expectOutline(underText.page, "p leadkid", "then merges it into the line above")
    }

    @Test func backspaceAtTheVeryStartDoesNothing() {
        let first = makeSession([para("Only")])
        #expect(!first.mergeBackward(first.id("Only")), "Backspace at the very start does nothing")
    }

    @Test func backspaceAtTheStartOfNonemptyCodeDoesNothing() {
        let codeBlocks = makeSession([para("x"), code("body"), code()])
        #expect(!codeBlocks.mergeBackward(codeBlocks.id("body")), "non-empty code ignores Backspace at its start")
    }

    @Test func backspaceTurnsAnEmptyCodeBlockIntoText() {
        let codeBlocks = makeSession([para("x"), code("body"), code()])
        codeBlocks.mergeBackward(codeBlocks.page.blocks[2].id)
        expectOutline(codeBlocks.page, "p x\ncode body\np", "an empty code block turns into text")
    }

    @Test func backspaceNeverMergesAcrossColumns() {
        let columnsPage = makeSession([columns([[para("left")], [para("right")]])])
        #expect(!columnsPage.mergeBackward(columnsPage.id("right")), "Backspace never merges across columns")
        expectOutline(columnsPage.page, "columns\n  column\n    p left\n  column\n    p right")
    }

    @Test func mergingIntoAClosedToggleJoinsItsTitle() {
        let collapsed = makeSession([toggle("Fold", expanded: false, [para("hidden")]), para("after")])
        collapsed.mergeBackward(collapsed.id("after"))
        expectOutline(collapsed.page, "toggle- Foldafter\n  p hidden", "merging into a closed toggle joins its title, not a hidden child")
        #expect(collapsed.selection == .caret(NotePosition(collapsed.id("Foldafter"), 4)), "the caret sits at the join in the title")
    }

    @Test func backspaceAfterMediaSelectsIt() {
        let session = makeSession([image(), para("text"), divider(), para()])
        let picture = session.page.blocks[0].id
        session.mergeBackward(session.id("text"))
        #expect(session.selection == .blocks([picture]), "Backspace after media selects it")
        expectOutline(session.page, "image\np text\ndivider\np")
    }

    @Test func backspaceRemovesAnEmptyLineAfterADivider() {
        let session = makeSession([image(), para("text"), divider(), para()])
        let rule = session.page.blocks[2].id
        session.mergeBackward(session.page.blocks[3].id)
        expectOutline(session.page, "image\np text\ndivider", "an empty line after a divider goes away")
        #expect(session.selection == .blocks([rule]), "and the divider is selected")
    }

    @Test func forwardDeleteJoinsTheNextBlockAtTheCaret() {
        let session = makeSession([para("Join"), heading(1, "Heading")])
        session.mergeForward(session.id("Join"))
        expectOutline(session.page, "p JoinHeading", "Delete at the end pulls the next block's text up")
        #expect(session.selection == .caret(NotePosition(session.page.blocks[0].id, 4)), "caret at the join")
    }

    @Test func deleteInAnEmptyBlockPreservesTheNextBlocksType() {
        let empty = makeSession([para(), heading(1, "Keep")])
        empty.mergeForward(empty.page.blocks[0].id)
        expectOutline(empty.page, "h1 Keep", "Delete in an empty line removes it so the next block keeps its type")
        #expect(empty.selection == .caret(NotePosition(empty.id("Keep"), 0)), "caret at the start of the next block")
    }

    @Test func deleteMergesAFirstChildAndLiftsItsChildren() {
        let nested = makeSession([bullet("A", [bullet("B", [bullet("B1")]), bullet("C")])])
        nested.mergeForward(nested.id("A"))
        expectOutline(nested.page, "ul AB\n  ul B1\n  ul C", "merging a first child lifts its children into its place")
    }

    @Test func deleteBeforeADividerSelectsIt() {
        let divided = makeSession([para("x"), divider(), para(), divider()])
        let firstRule = divided.page.blocks[1].id
        divided.mergeForward(divided.id("x"))
        #expect(divided.selection == .blocks([firstRule]), "Delete before a divider selects it")
    }

    @Test func deleteRemovesAnEmptyLineBeforeADivider() {
        let divided = makeSession([para("x"), divider(), para(), divider()])
        let secondRule = divided.page.blocks[3].id
        divided.mergeForward(divided.page.blocks[2].id)
        expectOutline(divided.page, "p x\ndivider\ndivider", "an empty line before a divider disappears")
        #expect(divided.selection == .blocks([secondRule]), "and the divider is selected")
    }

    @Test func textMergedIntoCodeTurnsPlain() {
        let codePage = makeSession([code("a = 1"), NoteBlock(.paragraph, text: NoteText(pieces: [("b", boldMarks)]))])
        codePage.mergeForward(codePage.id("a = 1"))
        #expect(codePage.page.blocks[0].text.isPlain && codePage.page.blocks[0].text.string == "a = 1b", "text merged into code turns plain")
    }

    @Test func forwardDeleteDoesNotMergeAcrossColumns() {
        let columnsPage = makeSession([columns([[para("left")], [para("right")]])])
        columnsPage.mergeForward(columnsPage.id("left"))
        expectOutline(columnsPage.page, "columns\n  column\n    p left\n  column\n    p right", "Delete never merges across columns")
    }

    @Test func backspaceRemovesAWholeEmojiWithItsSkinTone() {
        let session = makeSession([para("a👍🏽b")])
        let id = session.page.blocks[0].id
        session.setSelection(.caret(NotePosition(id, 5)))
        session.deleteBackward()
        #expect(session.page.blocks[0].text.string == "ab", "Backspace removes a whole emoji with its skin tone")
        #expect(session.selection == .caret(NotePosition(id, 1)), "caret steps back over it")
    }

    @Test func deleteRemovesTheCharacterAfterTheCaret() {
        let session = makeSession([para("a👍🏽b")])
        let id = session.page.blocks[0].id
        session.setSelection(.caret(NotePosition(id, 5)))
        session.deleteBackward()
        session.deleteForward()
        #expect(session.page.blocks[0].text.string == "a", "Delete removes the next character")
    }

    @Test func backspaceInAnEmptyCaptionSelectsTheMediaBlock() {
        let caption = makeSession([image(caption: "")])
        let picture = caption.page.blocks[0].id
        caption.addCaption(to: picture)
        caption.deleteBackward()
        #expect(caption.selection == .blocks([picture]), "Backspace in an empty caption steps out to the block")
    }
}
