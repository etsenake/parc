import Foundation
import Testing
@testable import Parc
@testable import ParcCore

@MainActor
struct NoteTableClipboardTests {
    func cell(_ row: Int, _ column: Int) -> NoteTableCell { NoteTableCell(row: row, column: column) }

    @Test func tsvWithATrailingNewline() { #expect(NoteTableClipboard.grid(fromDelimited: "a\tb\nc\td\n") == [["a", "b"], ["c", "d"]]) }

    @Test func tsvWithWindowsLineEndings() { #expect(NoteTableClipboard.grid(fromDelimited: "a\tb\r\nc\td") == [["a", "b"], ["c", "d"]]) }

    @Test func raggedSpreadsheetRowsPadOut() {
        #expect(NoteTableClipboard.grid(fromDelimited: "a\tb\tc\nd", fromSpreadsheet: true) == [["a", "b", "c"], ["d", "", ""]])
    }

    @Test(arguments: [
        "a\tb\tc\nd", "func f() {\n\treturn 1\n}", "\tlet a = 1\n\tlet b = 2", "\tindented", "Hello, world",
        "Dear Ada,\nThanks, really, for everything.", "just words", "line one\nline two", "",
    ])
    func textThatIsNotTabularIsNotAGrid(text: String) { #expect(NoteTableClipboard.grid(fromDelimited: text) == nil) }

    @Test func anUnmatchedQuoteIsJustACharacterAndDoesNotSwallowTheRest() {
        #expect(NoteTableClipboard.grid(fromDelimited: "\"unfinished\tb\nc\td") == [["\"unfinished", "b"], ["c", "d"]])
    }

    @Test func aQuoteWithNoPartnerAnywhereTurnsLiteral() {
        #expect(NoteTableClipboard.parse("a,\"b\nc,d", separator: ",") == [["a", "\"b"], ["c", "d"]])
    }

    @Test func aSingleTabSeparatedLineIsTabular() { #expect(NoteTableClipboard.grid(fromDelimited: "one\ttwo") == [["one", "two"]]) }

    @Test func quotedTsvCellsKeepTheirLineBreaks() {
        #expect(NoteTableClipboard.grid(fromDelimited: "\"line one\nline two\"\tb\nc\td") == [["line one\nline two", "b"], ["c", "d"]])
    }

    @Test func doubledQuotesUnescape() { #expect(NoteTableClipboard.grid(fromDelimited: "\"say \"\"hi\"\"\"\tx") == [["say \"hi\"", "x"]]) }

    @Test func csvParses() {
        #expect(NoteTableClipboard.grid(fromDelimited: "name,age\nAda,36\nAlan,41") == [["name", "age"], ["Ada", "36"], ["Alan", "41"]])
    }

    @Test func csvQuotedCommas() { #expect(NoteTableClipboard.grid(fromDelimited: "a,\"b, c\"\nd,e") == [["a", "b, c"], ["d", "e"]]) }

    @Test func emptyFieldsSurvive() { #expect(NoteTableClipboard.parse("a,,b", separator: ",") == [["a", "", "b"]]) }

    let htmlTable = "<table><tr><th>Name</th><th>Score</th></tr><tr><td><b>Ada</b></td><td>36</td></tr></table>"

    @Test func anHTMLTablePastesAsAGrid() {
        #expect(NoteTableClipboard.grid(fromHTML: htmlTable)?.map { $0.map(\.string) } == [["Name", "Score"], ["Ada", "36"]])
    }

    @Test func anHTMLTableKeepsItsFormatting() {
        #expect(NoteTableClipboard.grid(fromHTML: htmlTable)?[1][0].marks(at: 0).bold == true)
    }

    @Test func htmlWithoutATableIsNotAGrid() { #expect(NoteTableClipboard.grid(fromHTML: "<p>Hello <b>there</b></p>") == nil) }

    var bold: NoteMarks { NoteEditorBlocks.bold }

    var sampleRows: [[NoteText]] {
        var linked = NoteMarks.plain
        linked.link = "https://parc.example/?a=1&b=2"
        return [[NoteText("Name", marks: bold), "Notes"], [NoteText(pieces: [("see ", .plain), ("site", linked)]), "tab\there"], ["a < b", "two\nlines"]]
    }

    @Test func tsvQuotesAwkwardCells() {
        #expect(NoteTableClipboard.tsv(sampleRows) == "Name\tNotes\nsee site\t\"tab\there\"\na < b\t\"two\nlines\"")
    }

    @Test func tsvRoundTrips() {
        #expect(NoteTableClipboard.grid(fromDelimited: NoteTableClipboard.tsv(sampleRows)) == sampleRows.map { $0.map(\.plainText) })
    }

    var sampleHTML: String { NoteTableClipboard.html(sampleRows, headerRow: true, headerColumn: false, alignments: [nil, .center]) }

    @Test func htmlHeaderRow() {
        #expect(sampleHTML.hasPrefix("<table><thead><tr><th><strong>Name</strong></th><th style=\"text-align: center\">Notes</th></tr></thead><tbody>"))
    }

    @Test func htmlLinksEscape() { #expect(sampleHTML.contains("<a href=\"https://parc.example/?a=1&amp;b=2\">site</a>")) }

    @Test func htmlEscapesTextAndBreaksLines() {
        #expect(sampleHTML.contains("<td>a &lt; b</td>"))
        #expect(sampleHTML.contains("two<br>lines"))
    }

    @Test func htmlClosesTheBody() { #expect(sampleHTML.hasSuffix("</tr></tbody></table>")) }

    @Test func htmlHeaderColumn() {
        #expect(NoteTableClipboard.html([["x", "y"]], headerRow: false, headerColumn: true, alignments: [])
                == "<table><tbody><tr><th>x</th><td>y</td></tr></tbody></table>")
    }

    var source: NoteTable {
        var table = NoteTable(rows: [["a|b", "c", "z"], ["d", "e\nf", "y"]], headerRow: true, headerColumn: true)
        table.normalize()
        table.alignments = [.right, nil, .center]
        table.columnWidths = [nil, 210, 90]
        return table
    }

    @Test func copiedMarkdownIsExactlyWhatTheNoteFileWouldSay() {
        let table = source
        var props = NoteBlockProps()
        props.table = table
        let whole = NoteTableClipboard.slice(NoteTableRect(cell(0, 0), cell(1, 2)), of: table)
        #expect(NoteTableClipboard.markdown(whole)
                == NoteMarkdown.serialize(NotePage(blocks: [NoteBlock(.table, props: props)])).trimmingCharacters(in: .newlines))
    }

    @Test func aSliceKeepsBreaksAlignmentAndWidths() {
        let part = NoteTableClipboard.markdown(NoteTableClipboard.slice(NoteTableRect(cell(1, 1), cell(1, 2)), of: source))
        #expect(part == "| e<br>f | y   |\n| ------ | :-: |\n<!-- parc no-header-row widths=\"210,90\" -->")
    }

    @Test func aSliceReadsStraightBackIntoATable() {
        let part = NoteTableClipboard.markdown(NoteTableClipboard.slice(NoteTableRect(cell(1, 1), cell(1, 2)), of: source))
        let back = NoteMarkdown.parse(part).blocks.first?.props.table
        #expect(back?.rows.first?.map(\.string) == ["e\nf", "y"])
        #expect(back?.columnWidths == [210, 90])
        #expect(back?.headerRow == false)
    }

    @Test func aTopLeftSliceKeepsTheHeaders() {
        let corner = NoteTableClipboard.slice(NoteTableRect(cell(0, 0), cell(0, 0)), of: source)
        #expect(corner.headerRow)
        #expect(corner.headerColumn)
        #expect(corner.alignments == [.right])
    }

    func pastedTable() -> (NoteTable, NoteTableRect?) {
        var table = NoteTable.empty(rows: 2, columns: 2)
        let grid = NoteTableClipboard.cells(from: [["1", "2", "3"], ["4", "5", "6"]])
        let pasted = NoteTableTransforms.paste(grid, into: &table, at: cell(1, 1))
        return (table, pasted)
    }

    @Test func pasteReportsTheFilledRectangle() { #expect(pastedTable().1 == NoteTableRect(cell(1, 1), cell(2, 3))) }

    @Test func pasteGrowsRowsAndColumns() {
        let table = pastedTable().0
        #expect(table.rowCount == 3)
        #expect(table.columnCount == 4)
    }

    @Test func pasteLandsAtTheCaretCell() {
        let table = pastedTable().0
        #expect(table.rows[1].map(\.string) == ["", "1", "2", "3"])
        #expect(table.rows[2].map(\.string) == ["", "4", "5", "6"])
    }

    @Test func growthKeepsColumnMetadataAligned() {
        let table = pastedTable().0
        #expect(table.alignments.count == 4)
        #expect(table.columnWidths.count == 4)
    }

    func filled() -> (NoteTable, NoteTableRect?) {
        var fill = NoteTable.empty(rows: 3, columns: 3)
        let rect = NoteTableTransforms.paste([["x"]], into: &fill, at: cell(0, 0), filling: NoteTableRect(cell(0, 0), cell(1, 1)))
        return (fill, rect)
    }

    @Test func aSingleValueFillsTheSelection() { #expect(filled().1 == NoteTableRect(cell(0, 0), cell(1, 1))) }

    @Test func fillStaysInside() {
        let fill = filled().0
        #expect(fill.rows[0][0].string == "x")
        #expect(fill.rows[1][1].string == "x")
        #expect(fill.rows[2][2].isEmpty)
        #expect(fill.rowCount == 3)
    }

    @Test func aRangePasteStartsAtTheSelectionsCorner() {
        var start = NoteTable.empty(rows: 3, columns: 3)
        NoteTableTransforms.paste([["a", "b"]], into: &start, at: cell(2, 2), filling: NoteTableRect(cell(1, 0), cell(2, 1)))
        #expect(start.rows[1][0].string == "a")
        #expect(start.rows[1][1].string == "b")
        #expect(start.columnCount == 3)
    }

    func ragged() -> NoteTable {
        var table = NoteTable.empty(rows: 1, columns: 1)
        NoteTableTransforms.paste([["a", "b"], ["c"]], into: &table, at: cell(0, 0))
        return table
    }

    @Test func raggedPastesPadWithEmptyCells() { #expect(ragged().rows.map { $0.map(\.string) } == [["a", "b"], ["c", ""]]) }

    @Test func nothingToPaste() {
        var table = ragged()
        #expect(NoteTableTransforms.paste([], into: &table, at: cell(0, 0)) == nil)
    }

    @Test func aSliceReturnsItsCells() {
        #expect(NoteTableTransforms.slice(NoteTableRect(cell(0, 1), cell(1, 1)), of: ragged()).map { $0.map(\.string) } == [["b"], [""]])
    }
}
