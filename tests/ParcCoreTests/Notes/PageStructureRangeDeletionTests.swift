import Foundation
import Testing
@testable import ParcCore

@MainActor struct PageStructureRangeDeletionTests: NoteFixtures {
    @Test func deletingIntoANestedItemKeepsItsChildrenAndPutsTheCaretAtTheJoin() {
        let nested = makeSession([para("Start"), bullet("list", [bullet("child", [bullet("grand")]), bullet("sibling")]), para("after")])
        nested.setSelection(.text(anchor: NotePosition(nested.id("Start"), 2), head: NotePosition(nested.id("child"), 3)))
        nested.deleteSelection()
        expectOutline(nested.page, "p Stld\n  ul grand\nul sibling\np after", "deleting into a nested item keeps what follows in order, children nested")
        #expect(nested.selection == .caret(NotePosition(nested.id("Stld"), 2)), "caret at the join")
    }

    @Test func theStartBlockAdoptsTheEndBlocksChildrenAfterDeletion() {
        let adopt = makeSession([bullet("one"), bullet("two", [bullet("kid")])])
        adopt.setSelection(.text(anchor: NotePosition(adopt.id("one"), 1), head: NotePosition(adopt.id("two"), 1)))
        adopt.deleteSelection()
        expectOutline(adopt.page, "ul owo\n  ul kid", "the start block adopts the end block's children")
    }

    @Test func deletingFromAParentIntoItsChildKeepsTheOtherChildren() {
        let parent = makeSession([bullet("parent", [bullet("first"), bullet("second")])])
        parent.setSelection(.text(anchor: NotePosition(parent.id("parent"), 3), head: NotePosition(parent.id("first"), 2)))
        parent.deleteSelection()
        expectOutline(parent.page, "ul parrst\n  ul second", "deleting from a parent into its child keeps the other children")
    }

    @Test func deletingAcrossMediaDividersAndClosedTogglesRemovesThem() {
        let mixed = makeSession([para("abc"), image(), toggle("fold", expanded: false, [para("secret")]), divider(), para("xyz")])
        mixed.setSelection(.text(anchor: NotePosition(mixed.id("abc"), 1), head: NotePosition(mixed.id("xyz"), 2)))
        mixed.deleteSelection()
        expectOutline(mixed.page, "p az", "media, dividers and closed toggles in the middle go away entirely")
    }

    @Test func deletingARangeRemovesEveryInteriorBlockAndItsDescendants() {
        let everyKind = makeSession([para("abc"), table([["t"]]), block(.bookmark) { $0.source = "https://b" },
                                     block(.embed) { $0.source = "https://e" }, divider(), image(), code("let x"),
                                     bullet("mid", [bullet("mid child", [bullet("deeper")])]), para("xyz"), para("untouched")])
        everyKind.setSelection(.text(anchor: NotePosition(everyKind.id("abc"), 1), head: NotePosition(everyKind.id("xyz"), 2)))
        everyKind.deleteSelection()
        expectOutline(everyKind.page, "p az\np untouched", "every block strictly between the ends goes, text or not, with all its descendants")
    }

    @Test func oneUndoRestoresEveryBlockRemovedByARangeDeletion() {
        let everyKind = makeSession([para("abc"), table([["t"]]), block(.bookmark) { $0.source = "https://b" },
                                     block(.embed) { $0.source = "https://e" }, divider(), image(), code("let x"),
                                     bullet("mid", [bullet("mid child", [bullet("deeper")])]), para("xyz"), para("untouched")])
        everyKind.setSelection(.text(anchor: NotePosition(everyKind.id("abc"), 1), head: NotePosition(everyKind.id("xyz"), 2)))
        everyKind.deleteSelection()
        everyKind.undo()
        #expect(everyKind.page.blocks.count == 10, "and one undo brings every one of them back")
    }

    @Test func deletingAcrossAClosedToggleRemovesItsHiddenChildren() {
        let closedStart = makeSession([toggle("Fold", expanded: false, [para("hidden"), bullet("also hidden")]), para("after"), para("kept")])
        let foldSelection = NotePageSelection.text(anchor: NotePosition(closedStart.id("Fold"), 2), head: NotePosition(closedStart.id("after"), 3))
        closedStart.setSelection(foldSelection)
        closedStart.deleteSelection()
        expectOutline(closedStart.page, "toggle- Foer\np kept", "a closed toggle's hidden insides sit between the ends, so they go too")
    }

    @Test func copyingAcrossAClosedToggleIncludesItsHiddenChildren() {
        let closedStart = makeSession([toggle("Fold", expanded: false, [para("hidden"), bullet("also hidden")]), para("after"), para("kept")])
        let foldSelection = NotePageSelection.text(anchor: NotePosition(closedStart.id("Fold"), 2), head: NotePosition(closedStart.id("after"), 3))
        let copied = closedStart.fragment(of: foldSelection)
        #expect(outline(copied) == "toggle- ld\n  p hidden\n  ul also hidden\np aft", "matching exactly what a copy of that selection holds")
    }

    @Test func deletingAcrossColumnsKeepsTheColumnStructure() {
        let columnsPage = makeSession([columns([[para("left"), para("l2")], [para("right"), para("r2")]])])
        columnsPage.setSelection(.text(anchor: NotePosition(columnsPage.id("l2"), 1), head: NotePosition(columnsPage.id("right"), 2)))
        columnsPage.deleteSelection()
        expectOutline(columnsPage.page, "columns\n  column\n    p left\n    p lght\n  column\n    p r2", "deleting across columns keeps the column structure")
    }

    @Test func textMergedIntoCodeTurnsPlain() {
        let toCode = makeSession([code("let"), NoteBlock(.paragraph, text: NoteText(pieces: [("bold", boldMarks)]))])
        toCode.setSelection(.text(anchor: NotePosition(toCode.id("let"), 3), head: NotePosition(toCode.id("bold"), 1)))
        toCode.deleteSelection()
        #expect(toCode.page.blocks.count == 1 && toCode.page.blocks[0].text.string == "letold" && toCode.page.blocks[0].text.isPlain, "text merged into code turns plain")
    }

    @Test func deletingFromACaptionToBodyTextTrimsBothEndsWithoutMerging() {
        let fields = makeSession([image(caption: "caption"), para("body")])
        let picture = fields.page.blocks[0].id
        fields.setSelection(.text(anchor: NotePosition(picture, 3, field: .caption), head: NotePosition(fields.id("body"), 2)))
        fields.deleteSelection()
        expectOutline(fields.page, "image [cap]\np dy", "a selection from a caption trims both ends without merging")
    }
}
