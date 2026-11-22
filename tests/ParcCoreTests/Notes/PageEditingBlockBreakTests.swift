import Foundation
import Testing
@testable import ParcCore

@MainActor struct PageEditingBlockBreakTests: NoteFixtures {
    struct ContinuedList: Sendable, CustomTestStringConvertible {
        let testDescription: String
        let kind: NoteBlockKind
        let text: String
        let checked: Bool
        let expected: String
    }

    private nonisolated static let continuedLists = [
        ContinuedList(testDescription: "checked task", kind: .todo, text: "Done", checked: true, expected: "done Done\ntodo"),
        ContinuedList(testDescription: "numbered item", kind: .numberedItem, text: "One", checked: false, expected: "ol One\nol"),
        ContinuedList(testDescription: "bulleted item", kind: .bulletedItem, text: "Dot", checked: false, expected: "ul Dot\nul"),
    ]

    @Test func enterSplitsParagraphTextAndKeepsFormatting() {
        let session = makeSession([NoteBlock(.paragraph, text: NoteText(pieces: [("Hello ", .plain), ("world", boldMarks)]))])
        let first = session.page.blocks[0].id
        let fresh = session.splitBlock(at: NotePosition(first, 8))!
        expectOutline(session.page, "p Hello wo\np rld")
        #expect(session.page.block(fresh)!.text.marks(at: 0).bold, "the split tail keeps its bold")
        #expect(session.selection == .caret(NotePosition(fresh, 0)), "caret lands at the start of the new block")
    }

    @Test func enterAtTheEndOfAHeadingCreatesAParagraph() {
        let session = makeSession([heading(2, "Title")])
        session.splitBlock(at: NotePosition(session.page.blocks[0].id, 5))
        expectOutline(session.page, "h2 Title\np")
    }

    @Test func enterInsideAHeadingMovesItsTailIntoAParagraph() {
        let session = makeSession([heading(1, "Split me")])
        session.splitBlock(at: NotePosition(session.page.blocks[0].id, 5))
        expectOutline(session.page, "h1 Split\np  me")
    }

    @Test(arguments: continuedLists) func enterContinuesAListWithAnUncheckedNewItem(_ example: ContinuedList) {
        var props = NoteBlockProps()
        props.checked = example.checked
        let session = makeSession([NoteBlock(example.kind, text: NoteText(example.text), props: props)])
        let item = session.page.blocks[0]
        session.splitBlock(at: NotePosition(item.id, item.text.length))
        expectOutline(session.page, example.expected)
    }

    @Test func splittingColoredTextKeepsColorOnTheTail() {
        let coloured = makeSession([NoteBlock(.paragraph, text: "Redden", color: .background(.red))])
        let colouredID = coloured.page.blocks[0].id
        let tail = coloured.splitBlock(at: NotePosition(colouredID, 3))!
        #expect(coloured.page.block(tail)!.color == .background(.red), "a mid-block split keeps the colour on both halves")
    }

    @Test func enterAtTheEndOfColoredTextStartsAnUncoloredLine() {
        let coloured = makeSession([NoteBlock(.paragraph, text: "Redden", color: .background(.red))])
        let colouredID = coloured.page.blocks[0].id
        let tail = coloured.splitBlock(at: NotePosition(colouredID, 3))!
        let end = coloured.splitBlock(at: NotePosition(tail, 3))!
        #expect(coloured.page.block(end)!.color == nil, "a fresh empty line after a coloured block starts plain")
    }

    @Test func enterAtTheEndOfAParentOpensItsFirstChild() {
        let parent = makeSession([bullet("Parent", [bullet("Child")])])
        parent.splitBlock(at: NotePosition(parent.id("Parent"), 6))
        expectOutline(parent.page, "ul Parent\n  ul\n  ul Child", "Enter at the end of a parent opens a first child")
    }

    @Test func enterTurnsAnEmptyTopLevelItemIntoText() {
        let top = makeSession([bullet("a"), bullet()])
        let empty = top.page.blocks[1].id
        top.setSelection(.caret(NotePosition(empty, 0)))
        #expect(top.splitBlock(at: NotePosition(empty, 0)) == empty, "Enter on an empty item reports the same block")
        expectOutline(top.page, "ul a\np", "an empty top-level list item turns into text")
    }

    @Test func enterOutdentsAnEmptyListItemUnderText() {
        let underText = makeSession([block(.paragraph, "lead", [bullet()])])
        underText.splitBlock(at: NotePosition(underText.page.blocks[0].children[0].id, 0))
        expectOutline(underText.page, "p lead\nul", "an empty item nested under text outdents first")
    }

    @Test func enterAtTheEndOfAHeadingWithChildrenOpensItsFirstChild() {
        let textParent = makeSession([block(.heading, "Head", [para("kid")]) { $0.level = 2 }])
        textParent.splitBlock(at: NotePosition(textParent.id("Head"), 4))
        expectOutline(textParent.page, "h2 Head\n  p\n  p kid", "Enter at the end of a heading with children opens a first child")
    }

    @Test func enterOutdentsAnEmptyNestedItemAndAdoptsTheFollowingItems() {
        let nested = makeSession([bullet("a", [bullet("b"), bullet(), bullet("c")])])
        let blank = nested.page.blocks[0].children[1].id
        nested.splitBlock(at: NotePosition(blank, 0))
        expectOutline(nested.page, "ul a\n  ul b\nul\n  ul c", "the first Enter outdents a nested empty item and adopts what follows")
        #expect(nested.selection == .caret(NotePosition(blank, 0)), "the caret stays in the outdented item")
    }

    @Test func enterOnAnEmptyItemWithChildrenOpensItsFirstChild() {
        let nested = makeSession([bullet("a", [bullet("b"), bullet(), bullet("c")])])
        let blank = nested.page.blocks[0].children[1].id
        nested.splitBlock(at: NotePosition(blank, 0))
        nested.splitBlock(at: NotePosition(blank, 0))
        expectOutline(nested.page, "ul a\n  ul b\nul\n  ul\n  ul c", "an empty item with children opens a first child instead of converting")
    }

    @Test func enterTurnsAnEmptyListItemInACalloutIntoText() {
        let inCallout = makeSession([callout("Note", [bullet("x"), bullet()])])
        inCallout.splitBlock(at: NotePosition(inCallout.page.blocks[0].children[1].id, 0))
        expectOutline(inCallout.page, "callout Note\n  ul x\n  p", "an empty item inside a callout turns into text in place")
    }

    @Test(arguments: [NoteBlockKind.toggle, .quote]) func enterTurnsAnEmptyToggleOrQuoteIntoText(_ kind: NoteBlockKind) {
        let session = makeSession([NoteBlock(kind)])
        session.splitBlock(at: NotePosition(session.page.blocks[0].id, 0))
        expectOutline(session.page, "p")
    }

    @Test func enterCreatesALineAfterAnEmptyParagraph() {
        let session = makeSession([para()])
        session.splitBlock(at: NotePosition(session.page.blocks[0].id, 0))
        expectOutline(session.page, "p\np")
    }

    @Test func enterCreatesALineAfterAnEmptyHeading() {
        let session = makeSession([heading(1)])
        session.splitBlock(at: NotePosition(session.page.blocks[0].id, 0))
        expectOutline(session.page, "h1\np")
    }

    @Test func enterAtAListStartTransfersItsStartingNumber() {
        let session = makeSession([numbered("First", start: 5), numbered("Second")])
        let first = session.id("First")
        let above = session.splitBlock(at: NotePosition(first, 0))!
        expectOutline(session.page, "ol@5\nol First\nol Second", "Enter at the start inserts an item above and hands it the list start")
        #expect(session.selection == .caret(NotePosition(first, 0)), "the caret stays with the text")
        #expect(session.page.numberLabel(for: above) == "5.", "the new first item keeps the run's number")
        #expect(session.page.numberLabel(for: first) == "6.", "the old first item counts on")
    }

    @Test func enterAtTheStartOfAHeadingInsertsTextAbove() {
        let session = makeSession([heading(1, "Big")])
        session.splitBlock(at: NotePosition(session.page.blocks[0].id, 0))
        expectOutline(session.page, "p\nh1 Big")
    }

    @Test func enterAtTheStartOfAToggleInsertsAToggleAbove() {
        let session = makeSession([toggle("Fold", expanded: true, [para("inside")])])
        session.splitBlock(at: NotePosition(session.page.blocks[0].id, 0))
        expectOutline(session.page, "toggle\ntoggle Fold\n  p inside")
    }

    @Test func enterAtTheEndOfAnOpenToggleCreatesItsFirstChild() {
        let session = makeSession([toggle("Open", expanded: true, [para("kid")])])
        session.splitBlock(at: NotePosition(session.page.blocks[0].id, 4))
        expectOutline(session.page, "toggle Open\n  p\n  p kid")
    }

    @Test func enterAtTheEndOfAClosedToggleCreatesAClosedSibling() throws {
        let session = makeSession([toggle("Shut", expanded: false, [para("hidden")])])
        let inserted = try #require(session.splitBlock(at: NotePosition(session.page.blocks[0].id, 4)))
        expectOutline(session.page, "toggle- Shut\n  p hidden\ntoggle-")
        #expect(session.page.block(inserted)!.isCollapsed, "the sibling toggle starts closed like its neighbour")
    }

    @Test func enterAtTheEndOfAnOpenToggleHeadingCreatesItsFirstChild() {
        let session = makeSession([toggleHeading(2, "Section", expanded: true)])
        session.splitBlock(at: NotePosition(session.page.blocks[0].id, 7))
        expectOutline(session.page, "th2 Section\n  p")
    }

    @Test func enterAtTheEndOfAClosedToggleHeadingCreatesTextBelow() {
        let session = makeSession([toggleHeading(2, "Closed", expanded: false, [para("x")])])
        session.splitBlock(at: NotePosition(session.page.blocks[0].id, 6))
        expectOutline(session.page, "th2- Closed\n  p x\np")
    }

    @Test func enterInsideACalloutMovesItsTailToAChild() {
        let session = makeSession([callout("Tip")])
        session.splitBlock(at: NotePosition(session.page.blocks[0].id, 1))
        expectOutline(session.page, "callout T\n  p ip")
    }

    @Test func enterInAnEmptyCalloutCreatesTextInsideIt() {
        let session = makeSession([callout()])
        session.splitBlock(at: NotePosition(session.page.blocks[0].id, 0))
        expectOutline(session.page, "callout\n  p")
    }

    @Test func enterAfterAQuoteContinuesAsText() {
        let session = makeSession([quote("Said")])
        session.splitBlock(at: NotePosition(session.page.blocks[0].id, 4))
        expectOutline(session.page, "quote Said\np")
    }

    @Test func enterInACaptionOpensALineBelowTheMedia() {
        let session = makeSession([image(caption: "A cat"), code("let x = 1")])
        let picture = session.page.blocks[0].id
        let fresh = session.splitBlock(at: NotePosition(picture, 2, field: .caption))!
        expectOutline(session.page, "image [A cat]\np\ncode let x = 1", "Enter in a caption opens a line below the media")
        #expect(session.selection == .caret(NotePosition(fresh, 0)), "the caret moves to the new line")
    }

    @Test func codeKeepsEnterForItself() {
        let session = makeSession([code("let x = 1")])
        #expect(session.splitBlock(at: NotePosition(session.id("let x = 1"), 3)) == nil, "code keeps Enter for itself")
    }

    @Test func enterReplacesTheSelectionWithABlockBreak() {
        let range = makeSession([para("Hello there"), para("General")])
        range.setSelection(.text(anchor: NotePosition(range.id("Hello there"), 5), head: NotePosition(range.id("General"), 3)))
        range.insertBlockBreak()
        expectOutline(range.page, "p Hello\np eral", "Enter over a selection deletes it and splits")
    }

    @Test func undoRestoresTheTextReplacedByEnter() {
        let range = makeSession([para("Hello there"), para("General")])
        range.setSelection(.text(anchor: NotePosition(range.id("Hello there"), 5), head: NotePosition(range.id("General"), 3)))
        range.insertBlockBreak()
        range.undo()
        expectOutline(range.page, "p Hello there\np General", "one undo puts the selection back")
    }
}
