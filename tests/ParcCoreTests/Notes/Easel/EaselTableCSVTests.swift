import Foundation
import Testing
@testable import ParcCore

struct EaselTableCSVTests {
    @Test
    func csvHandlesQuotesCommasNewlinesAndCRLF() {
        let quoted = EaselTableData.delimited("a,\"b,c\",\"say \"\"hi\"\"\"\r\n\"multi\nline\",x,\r\n", separator: ",")
        #expect(quoted.cells == [["a", "b,c", "say \"hi\""], ["multi\nline", "x", ""]], "CSV handles quotes, commas, newlines and CRLF")
    }

    @Test
    func delimitedTextKeepsItsRowsAndCells() {
        #expect(EaselTableData.delimited("", separator: ",").cells.isEmpty, "Empty text has no rows")
        #expect(EaselTableData.delimited("solo", separator: ",").cells == [["solo"]], "One value is one cell")
    }

    @Test
    func spreadsheetTextRequiresAConsistentTabSeparatedGrid() {
        let sheet = EaselTableData.spreadsheetText("Name\tAge\nAda\t36\n")
        #expect(sheet?.cells == [["Name", "Age"], ["Ada", "36"]], "Spreadsheet text becomes a grid")
        #expect(EaselTableData.spreadsheetText("Name\tAge\nAda") == nil, "Ragged tab text stays text")
        #expect(EaselTableData.spreadsheetText("just words\nmore words") == nil, "Text without tabs stays text")
        #expect(EaselTableData.spreadsheetText("\tindented\n\t\tcode\n") == nil, "Indented code stays text")
        #expect(EaselTableData.spreadsheetText("a\t\"two\nlines\"\nb\tc")?.cells == [["a", "two\nlines"], ["b", "c"]], "Quoted cells keep their line breaks")
    }

    @Test
    func csvIgnoresTheByteOrderMark() {
        #expect(EaselTableData.csv("\u{FEFF}x,y")?.cells == [["x", "y"]], "A byte order mark is skipped")
    }

    @Test
    func htmlTablesReadCellsAndSpans() {
        let html = """
        <meta charset="utf-8"><google-sheets-html-origin><style type="text/css"><!--td {border: 1px solid #cccccc;}--></style>
        <table xmlns="http://www.w3.org/1999/xhtml" cellspacing="0"><colgroup><col width="100"/></colgroup><tbody>
        <tr style="height:21px;"><td colspan="2" style="x">Q1 &amp; Q2</td><td rowspan=2>Total</td></tr>
        <tr><td>Fish&nbsp;&lt;3</td><td>two<br>lines</td></tr>
        <tr><td><p>One</p><p>Two</p></td><td>&#x1F600; &#233;</td><td></td></tr></tbody></table>
        <table><tr><td>second table ignored</td></tr></table>
        """
        let grid = EaselTableData.html(html)
        #expect(grid?.cells == [["Q1 & Q2", "", "Total"], ["Fish <3", "two\nlines", ""], ["One\nTwo", "😀 é", ""]], "HTML tables read cells, spans, breaks and entities")
        #expect(grid?.merges == [EaselTableMerge(row: 0, column: 0, rowSpan: 1, columnSpan: 2), EaselTableMerge(row: 0, column: 2, rowSpan: 2, columnSpan: 1)], "HTML spans become merges")
    }

    @Test
    func htmlWithoutATableIsRefused() {
        #expect(EaselTableData.html("<p>No table here</p>") == nil, "HTML without a table is not a table")
    }

    @Test
    func anImportedGridBecomesAValidTable() {
        let html = """
        <meta charset="utf-8"><google-sheets-html-origin><style type="text/css"><!--td {border: 1px solid #cccccc;}--></style>
        <table xmlns="http://www.w3.org/1999/xhtml" cellspacing="0"><colgroup><col width="100"/></colgroup><tbody>
        <tr style="height:21px;"><td colspan="2" style="x">Q1 &amp; Q2</td><td rowspan=2>Total</td></tr>
        <tr><td>Fish&nbsp;&lt;3</td><td>two<br>lines</td></tr>
        <tr><td><p>One</p><p>Two</p></td><td>&#x1F600; &#233;</td><td></td></tr></tbody></table>
        <table><tr><td>second table ignored</td></tr></table>
        """
        let grid = EaselTableData.html(html)
        let table = grid.flatMap(EaselTableData.table(from:))
        #expect(table?.rowCount == 3 && table?.columnCount == 3 && table?.merges.count == 2 && (try? table?.validate()) != nil, "Imported grids become valid tables")
    }

    @Test
    func tableImportsReportWhenRowsAreTrimmedToTheirCellBudget() {
        let big = EaselTableGrid(cells: Array(repeating: Array(repeating: "x", count: 7), count: 400))
        let capped = EaselTableData.imported(big)
        #expect(capped?.table.columnCount == 7 && capped?.table.rowCount == 71 && capped?.trimmed == true, "New tables keep the first 500 cells and say so")
        let roomy = EaselTableData.imported(big, limit: EaselTable.maximumCells)
        #expect(roomy?.table.rowCount == 100 && roomy?.trimmed == true, "Pasting into a table can go up to the 100-row limit and says what stayed behind")
    }

    @Test
    func smallImportsStayWhole() {
        let small = EaselTableData.imported(EaselTableGrid(cells: [["a", "b"], ["c", "d"]]))
        #expect(small?.trimmed == false, "Small pastes are kept whole")
    }

    @Test
    func importsTrimToOneHundredColumns() {
        let wide = EaselTableData.imported(EaselTableGrid(cells: [Array(repeating: "y", count: 300)]), limit: EaselTable.maximumCells)
        #expect(wide?.table.columnCount == 100 && wide?.trimmed == true, "Imports keep the first 100 columns and say so")
    }

    @Test
    func importsReportWhenLongCellTextIsClipped() {
        let long = EaselTableData.imported(EaselTableGrid(cells: [[String(repeating: "z", count: EaselTable.maximumCellBytes + 10), "ok"]]))
        #expect(long?.table.cells[0][0].text.utf8.count == EaselTable.maximumCellBytes && long?.trimmed == true, "Overlong cells are clipped and reported")
    }

    @Test
    func delimitedParsingReportsWhenItStopsEarly() {
        let lines = String(repeating: "a\tb\n", count: EaselTableData.maximumParsedRows + 5)
        #expect(EaselTableData.delimited(lines, separator: "\t").truncated && !EaselTableData.delimited("a\tb\n", separator: "\t").truncated, "Parsing notes when it stops early")
    }

    @Test
    func htmlParsingReportsWhenItStopsAtAHundredRows() {
        let tall = "<table>" + String(repeating: "<tr><td>r</td></tr>", count: 120) + "</table>"
        #expect(EaselTableData.html(tall)?.rowCount == 100 && EaselTableData.html(tall)?.truncated == true, "HTML tables stop at 100 rows and say so")
    }

    @Test
    func htmlTablePasteUsesTheClipboardContext() {
        #expect(EaselTableData.readsHTMLTable(plainText: nil, intoCells: false) && EaselTableData.readsHTMLTable(plainText: "a\tb", intoCells: false), "Spreadsheet copies read their HTML table")
        #expect(!EaselTableData.readsHTMLTable(plainText: "Hi Ada,\nthe newsletter", intoCells: false), "Mail and web pages with layout tables stay text")
        #expect(EaselTableData.readsHTMLTable(plainText: "words", intoCells: true), "Pasting into cells always reads HTML tables")
    }

    @Test
    func htmlEntitiesDecodeExactlyOnce() {
        #expect(EaselTableData.decodeEntities("&bogus; &amp;amp; &#65;") == "&bogus; &amp; A", "Entities decode once and unknown ones stay")
    }

    @Test
    func clippingNeverSplitsACharacter() {
        #expect(EaselTableData.clipped("héllo", bytes: 2) == "h", "Clipping never splits a character")
    }

    @Test
    func csvQuotesWhatItMust() {
        let table = EaselTableTestsSupport.filled([["Name", "Note"], ["Ada", "said \"hi\", then\nleft"]])
        #expect(EaselTableData.csv(table) == "Name,Note\r\nAda,\"said \"\"hi\"\", then\nleft\"\r\n", "CSV quotes what it must")
    }

    @Test
    func tabSeparatedTextExportsAChosenRange() {
        let table = EaselTableTestsSupport.filled([["Name", "Note"], ["Ada", "said \"hi\", then\nleft"]])
        #expect(EaselTableData.tsv(table, range: EaselTableRange(EaselTableTestsSupport.cell(0, 0), EaselTableTestsSupport.cell(1, 0))) == "Name\nAda\n", "TSV exports a chosen range")
    }

    @Test
    func csvRoundTrips() {
        let table = EaselTableTestsSupport.filled([["Name", "Note"], ["Ada", "said \"hi\", then\nleft"]])
        let reparsed = EaselTableData.csv(EaselTableData.csv(table))
        #expect(reparsed?.cells == table.cells.map { $0.map(\.text) }, "CSV round trips")
    }

    @Test
    func htmlCopiesSpansFillsAndLineBreaks() {
        var table = EaselTableTestsSupport.filled([["Name", "Note"], ["Ada", "said \"hi\", then\nleft"]])
        table.merges = [EaselTableMerge(row: 0, column: 0, rowSpan: 1, columnSpan: 2)]
        table.cells[0][1] = EaselTableCell()
        table.cells[1][0].fill = "#FAE7D5"
        let html = EaselTableData.html(table)
        #expect(html.contains("colspan=\"2\"") && html.contains("background-color:#FAE7D5") && html.contains("<br>"), "HTML copies spans, fills and breaks")
        let back = EaselTableData.html(html)
        #expect(back?.merges == table.merges && back?.cells[1][1] == "said \"hi\", then\nleft", "Our HTML reads back")
    }

    @Test
    func svgDrawsTheGridWithAdaptiveColours() {
        var table = EaselTableTestsSupport.filled([["Name", "Note"], ["Ada", "said \"hi\", then\nleft"]])
        table.merges = [EaselTableMerge(row: 0, column: 0, rowSpan: 1, columnSpan: 2)]
        table.cells[0][1] = EaselTableCell()
        table.cells[1][0].fill = "#FAE7D5"
        var item = EaselTableGeometry.item(columns: 2, rows: 2, frame: EaselRect(x: 0, y: 0, width: 200, height: 72), zIndex: 1)
        item.table = table
        let svg = EaselVectorExport.element(item, art: EaselVectorArt())
        #expect(svg.contains("easel-table") && svg.contains("clipPath") && svg.contains("<path d=\"M"), "Tables export as SVG with a grid")
        #expect(svg.contains(EaselVectorExport.paint("#FAE7D5", role: .fill)), "Cell fills export with their light and dark palette colours")
        #expect(svg.contains("var(--easel-card)") && svg.contains("var(--easel-card-line)"), "Table chrome follows light and dark")
    }

    @Test
    func filledCellsBecomeStickiesWithTheirLayoutPaperAndOrder() {
        var item = EaselTableGeometry.item(columns: 2, rows: 2, frame: EaselRect(x: 50, y: 60, width: 200, height: 72), zIndex: 4)
        item.table?.cells[0][0].text = "Idea"
        item.table?.cells[1][1].text = "Other"
        item.table?.cells[1][1].fill = "#DCEBE2"
        item.table?.cells[0][1].text = "   "
        let side = EaselBoardObjects.stickySide
        let notes = EaselTableGeometry.stickies(from: item, fill: { $0 == nil ? nil : "#B5D5C2" }, textHeight: { $0.text == "Other" ? 400 : 0 })
        #expect(notes.count == 2 && notes.allSatisfy { $0.kind == .sticky }, "Each filled cell becomes a sticky")
        #expect(notes[0].text == "Idea" && notes[0].frame == EaselRect(x: 50, y: 60, width: side, height: side) && notes[0].fill == nil, "Stickies keep the table's layout and default paper")
        #expect(notes[1].frame.x == 50 + side + 24 && notes[1].frame.y == 60 + side + 24 && notes[1].fill == "#B5D5C2", "Cell colours carry over")
        #expect(notes[1].frame.height > side, "Long text makes a taller sticky")
        #expect(Set(notes.map(\.id)).count == 2 && notes[1].zIndex == notes[0].zIndex + 1, "Stickies get their own IDs and stack in order")
    }

    @Test
    func rowsOfStickiesClearTheTallestStickyInThePreviousRow() {
        var item = EaselTableGeometry.item(columns: 2, rows: 2, frame: EaselRect(x: 50, y: 60, width: 200, height: 72), zIndex: 4)
        item.table?.cells[0][0].text = "Idea"
        item.table?.cells[1][1].text = "Other"
        item.table?.cells[1][1].fill = "#DCEBE2"
        item.table?.cells[0][1].text = "   "
        var tall = item
        tall.table?.cells[0][1].text = "Long"
        let rows = EaselTableGeometry.stickies(from: tall, fill: { _ in nil }, textHeight: { $0.text == "Long" ? 400 : 0 })
        let second = rows.first { $0.text == "Other" }
        let first = rows.first { $0.text == "Long" }
        #expect(second.map { $0.frame.y } == first.map { $0.frame.y + $0.frame.height + 24 }, "Each row clears its tallest sticky")
    }
}
