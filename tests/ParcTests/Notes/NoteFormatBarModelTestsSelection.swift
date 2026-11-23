import AppKit
import Testing
@testable import ParcCore
@testable import ParcNotes

@MainActor
struct NoteFormatBarModelTestsSelection {
    @MainActor private struct Page {
        let session: NotePageSession
        let first: NoteBlock
        let second: NoteBlock
        let code: NoteBlock

        init() {
            var bold = NoteMarks.plain
            bold.bold = true
            var linked = NoteMarks.plain
            linked.link = "https://parc.example"
            linked.color = .text(.red)
            first = NoteBlock.paragraph(NoteText(pieces: [("Hello ", .plain), ("bold", bold), (" world", .plain)]))
            second = NoteBlock(.heading, text: NoteText(pieces: [("Linked", linked), (" tail", .plain)]),
                               props: { var props = NoteBlockProps(); props.level = 2; return props }())
            code = NoteBlock(.code, text: "let x = 1")
            session = NotePageSession(page: NotePage(blocks: [first, second, code]))
        }

        func select(_ a: NotePosition, _ b: NotePosition) -> NoteFormatState? {
            session.setSelection(.text(anchor: a, head: b))
            return NoteFormatState.resolve(session: session, isPlainText: false, isReadOnly: false)
        }

        func inFirst(_ from: Int, _ to: Int) -> NoteFormatState? { select(NotePosition(first.id, from), NotePosition(first.id, to)) }
        func inSecond(_ from: Int, _ to: Int) -> NoteFormatState? { select(NotePosition(second.id, from), NotePosition(second.id, to)) }
    }

    @Test func aFullyBoldSelectionShowsBoldChecked() {
        #expect(Page().inFirst(6, 10)?.isActive(.bold) == true)
    }

    @Test func unusedMarksStayUnchecked() {
        #expect(Page().inFirst(6, 10)?.isActive(.italic) == false)
    }

    @Test func turnIntoNamesTheBlockType() {
        let state = Page().inFirst(6, 10)
        #expect(state?.turnIntoLabel == "Text")
        #expect(state?.turnInto == .text)
    }

    @Test func aPartlyBoldSelectionShowsBoldUnchecked() {
        #expect(Page().inFirst(0, 10)?.isActive(.bold) == false)
    }

    @Test func aBackwardsSelectionReadsTheSameMarks() {
        #expect(Page().inFirst(10, 6)?.isActive(.bold) == true)
    }

    @Test func aLinkedSelectionShowsLinkChecked() {
        let linked = Page().inSecond(0, 6)
        #expect(linked?.link == "https://parc.example")
        #expect(linked?.isActive(.link) == true)
    }

    @Test func theColourGlyphReadsTheSpanColour() {
        let linked = Page().inSecond(0, 6)
        #expect(linked?.color.text == .red)
        #expect(linked?.color.uniform == .text(.red))
    }

    @Test func headingsNameTheirLevel() {
        #expect(Page().inSecond(0, 6)?.turnIntoLabel == "Heading 2")
    }

    @Test func aHalfLinkedSelectionKeepsTheLinkToEdit() {
        let partly = Page().inSecond(3, 9)
        #expect(partly?.link == nil)
        #expect(partly?.firstLink == "https://parc.example")
    }

    @Test func mixedColoursCheckNothing() {
        let partly = Page().inSecond(3, 9)
        #expect(partly?.color.isTextMixed == true)
        #expect(partly?.color.uniform == nil)
    }

    private func across() -> (Page, NoteFormatState?) {
        let page = Page()
        return (page, page.select(NotePosition(page.first.id, 6), NotePosition(page.second.id, 3)))
    }

    @Test func crossBlockSelectionsTouchEveryBlock() {
        let (page, state) = across()
        #expect(state?.spansBlocks == true)
        #expect(state?.bodyBlocks == [page.first.id, page.second.id])
    }

    @Test func equationsNeedASingleBlock() {
        let state = across().1
        #expect(state?.isEnabled(.equation) == false)
    }

    @Test func mentionsNeedASingleBlock() {
        let state = across().1
        #expect(state?.isEnabled(.mention) == false)
    }

    @Test func mixedTypesShowTheFirstBlocksType() {
        let state = across().1
        #expect(state?.isTurnIntoUniform == false)
        #expect(state?.turnIntoLabel == "Text")
    }

    @Test func codeBlocksDropOutOfACrossBlockSelection() {
        let page = Page()
        #expect(page.select(NotePosition(page.second.id, 2), NotePosition(page.code.id, 3))?.bodyBlocks == [page.second.id])
    }

    @Test func codeBlocksNeverShowTheBar() {
        let page = Page()
        #expect(page.select(NotePosition(page.code.id, 0), NotePosition(page.code.id, 3)) == nil)
    }

    @Test func aCaretShowsNoBar() {
        #expect(Page().inFirst(3, 3) == nil)
    }

    @Test func plainTextPagesShowNoBar() {
        let page = Page()
        page.session.setSelection(.text(anchor: NotePosition(page.first.id, 0), head: NotePosition(page.first.id, 4)))
        #expect(NoteFormatState.resolve(session: page.session, isPlainText: true, isReadOnly: false) == nil)
    }

    @Test func lockedPagesShowNoBar() {
        let page = Page()
        page.session.setSelection(.text(anchor: NotePosition(page.first.id, 0), head: NotePosition(page.first.id, 4)))
        #expect(NoteFormatState.resolve(session: page.session, isPlainText: false, isReadOnly: true) == nil)
    }

    @Test func blockSelectionShowsSharedActions() {
        let page = Page()
        page.session.setSelection(.blocks([page.first.id, page.second.id]))
        let state = NoteFormatState.resolve(session: page.session, isPlainText: false, isReadOnly: false)
        #expect(state?.items.contains(.actions) == true)
        #expect(state?.bodyBlocks == [page.first.id, page.second.id])
        page.session.toggleMark(.bold, in: state?.selection)
        #expect(page.session.hasMark(.bold))
    }

    @Test func emptyBlockSelectionStillOffersActions() {
        let block = NoteBlock.paragraph(NoteText(""))
        let session = NotePageSession(page: NotePage(blocks: [block]))
        session.setSelection(.blocks([block.id]))
        let state = NoteFormatState.resolve(session: session, isPlainText: false, isReadOnly: false)
        #expect(state?.items == [.actions])
    }

    @Test func togglingAMarkIsReflectedRightAway() {
        let page = Page()
        page.session.toggleMark(.italic, in: .text(anchor: NotePosition(page.first.id, 0), head: NotePosition(page.first.id, 5)))
        #expect(page.inFirst(0, 5)?.isActive(.italic) == true)
    }

    private func selectedEquation() -> NoteFormatState? {
        let equation = NoteBlock.paragraph(NoteText.atom(.equation("e^{i\\pi}")) + NoteText(" done"))
        let math = NotePageSession(page: NotePage(blocks: [equation]))
        math.setSelection(.text(anchor: NotePosition(equation.id, 0), head: NotePosition(equation.id, 1)))
        return NoteFormatState.resolve(session: math, isPlainText: false, isReadOnly: false)
    }

    @Test func aSelectedEquationShowsEquationChecked() {
        let atom = selectedEquation()
        #expect(atom?.isActive(.equation) == true)
    }

    @Test func aSelectedEquationDisablesMention() {
        let atom = selectedEquation()
        #expect(atom?.isEnabled(.mention) == false)
    }

    @Test func selectedTextReadsEquationSources() {
        #expect(selectedEquation()?.selectedText == "e^{i\\pi}")
    }

    private func captionAndTable() -> (NotePageSession, NoteBlock, NoteBlock) {
        var props = NoteBlockProps()
        props.caption = "A fine caption"
        let image = NoteBlock(.image, props: props)
        var tableProps = NoteBlockProps()
        tableProps.table = NoteTable(rows: [["Cell one", "Two"]])
        let table = NoteBlock(.table, props: tableProps)
        return (NotePageSession(page: NotePage(blocks: [image, table])), image, table)
    }

    private func resolve(_ session: NotePageSession, _ a: NotePosition, _ b: NotePosition) -> NoteFormatState? {
        session.setSelection(.text(anchor: a, head: b))
        return NoteFormatState.resolve(session: session, isPlainText: false, isReadOnly: false)
    }

    @Test func captionsGetTheReducedSet() {
        let (session, image, _) = captionAndTable()
        let caption = resolve(session, NotePosition(image.id, 2, field: .caption), NotePosition(image.id, 6, field: .caption))
        #expect(caption?.context == .caption)
        #expect(caption?.items.contains(.turnInto) == false)
    }

    @Test func captionsKeepMarksAndLinks() {
        let (session, image, _) = captionAndTable()
        let caption = resolve(session, NotePosition(image.id, 2, field: .caption), NotePosition(image.id, 6, field: .caption))
        #expect(caption?.items.contains(.bold) == true)
        #expect(caption?.items.contains(.link) == true)
    }

    @Test func tableCellsStartAtLink() {
        let (session, _, table) = captionAndTable()
        let cell = resolve(session, NotePosition(table.id, 0, field: .cell(row: 0, column: 0)), NotePosition(table.id, 4, field: .cell(row: 0, column: 0)))
        #expect(cell?.context == .cell)
        #expect(cell?.items.first == .link)
    }
}
