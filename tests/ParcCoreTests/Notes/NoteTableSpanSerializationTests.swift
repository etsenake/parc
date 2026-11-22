import Foundation
import Testing
@testable import ParcCore

struct NoteTableSpanSerializationTests {
    @Test func pipeTablesLeaveCoveredCellsEmptyAndRoundTripTheirMetadata() {
        var table = NoteTableSpanTestsSupport.grid([["Name", "Q1", "Q2"], ["Ada", "3", "4"], ["Alan", "", "5"], ["Total", "", ""]])
        table.mergeCells(rows: 0...0, columns: 1...2)
        table.mergeCells(rows: 2...3, columns: 0...0)
        table.setColor(.background(.gray), rows: 0...3, columns: 0...0)
        table.setColor(.text(.red), rows: 1...1, columns: 1...2)
        table.setColor(.background(.blue), rows: 3...3, columns: 1...2)
        let text = NoteMarkdown.serialize(NoteTableSpanTestsSupport.page(table))
        let lines = text.components(separatedBy: "\n")
        #expect(lines.first == "| Name | Q1  |     |", "merged-away cells stay empty in the pipe table: \(text)")
        #expect(lines.contains("| Ada  | 3   | 4   |") && lines.contains("|      |     | 5   |") == false, "rows read normally: \(text)")
        #expect(text.contains("<!-- parc merge=\"B1:C1,A3:A4\" colors=\"A:A=gray_background,4:4=blue_background,B2:C2=red\" -->"), "merges and colours ride in the parc comment: \(text)")
        let back = NoteMarkdown.parse(text).blocks.first?.props.table
        #expect(back == table, "lossless round trip: \(String(describing: back?.merges)) \(String(describing: back?.cellColors))")
        #expect(NoteMarkdown.serialize(NoteMarkdown.parse(text)) == text, "byte-stable second save")
    }

    @Test func markdownTextInACoveredCellOverridesTheMerge() {
        let edited = "| a | b |\n| - | - |\n| c | typed |\n<!-- parc merge=\"A2:B2\" -->\n"
        let handEdited = NoteMarkdown.parse(edited).blocks.first?.props.table
        #expect(handEdited?.merges.isEmpty == true && handEdited?.rows[1][1].string == "typed", "text typed into a merged-away cell wins")
    }

    @Test func markdownSkipsBadTableReferencesAndKeepsValidOnes() {
        let sloppy = "| a | b |\n| - | - |\n| c |  |\n<!-- parc merge=\"A2:B2, Q9:Z99, nonsense\" colors=\"b1=RED,zz9=blue,A1=nope\" -->\n"
        let forgiving = NoteMarkdown.parse(sloppy).blocks.first?.props.table
        #expect(forgiving?.merges == [NoteTableMerge(row: 1, column: 0, rowSpan: 1, columnSpan: 2)]
               && forgiving?.cellColors == [NoteTableSpanTestsSupport.cell(0, 1): .text(.red)], "bad references are skipped, good ones kept")
    }

    @Test func markdownWritesAColoredRowAsARowReference() {
        var lone = NoteTableSpanTestsSupport.grid([["x", "y"]])
        lone.setColor(.background(.pink), rows: 0...0, columns: 0...1)
        let loneText = NoteMarkdown.serialize(NoteTableSpanTestsSupport.page(lone))
        #expect(loneText.contains("colors=\"1:1=pink_background\""), "a whole coloured row is written as a row: \(loneText)")
        #expect(NoteMarkdown.parse(loneText).blocks.first?.props.table == lone, "and reads back")
    }

    @Test func htmlUsesHeaderAndBodySpansAndSkipsCoveredCells() {
        var table = NoteTableSpanTestsSupport.grid([["Name", "Q1", "Q2"], ["Ada", "3", "4"], ["Alan", "", "5"]])
        table.mergeCells(rows: 0...0, columns: 1...2)
        table.mergeCells(rows: 1...2, columns: 0...0)
        table.setColor(.background(.blue), rows: 1...1, columns: 1...1)
        let fragment = NotePageHTML.fragment(NoteTableSpanTestsSupport.page(table).blocks)
        #expect(fragment.contains("<th scope=\"col\" colspan=\"2\""), "colspan in the header: \(fragment)")
        #expect(fragment.contains("<td rowspan=\"2\""), "rowspan in the body: \(fragment)")
        #expect(fragment.components(separatedBy: "<td").count - 1 == 5 && fragment.components(separatedBy: "<th ").count - 1 == 2, "covered cells aren't written")
        #expect(fragment.contains("data-color=\"blue_background\""), "cell colours: \(fragment)")
    }

    @Test func htmlDocumentsExportCellColorsAsClasses() {
        var table = NoteTableSpanTestsSupport.grid([["Name", "Q1", "Q2"], ["Ada", "3", "4"], ["Alan", "", "5"]])
        table.mergeCells(rows: 0...0, columns: 1...2)
        table.mergeCells(rows: 1...2, columns: 0...0)
        table.setColor(.background(.blue), rows: 1...1, columns: 1...1)
        let document = NotePageHTML.document(NoteTableSpanTestsSupport.page(table), title: "Spans", assets: { _ in nil }, embedImages: false)
        #expect(document.contains("class=\"block-color-blue_background\""), "cell colours become classes in documents")
    }

    @Test func aRowspanFromTheHeaderKeepsOneTableBody() {
        var tall = NoteTableSpanTestsSupport.grid([["a", "b"], ["", "c"]])
        tall.mergeCells(rows: 0...1, columns: 0...0)
        let split = NotePageHTML.fragment(NoteTableSpanTestsSupport.page(tall).blocks)
        #expect(!split.contains("<thead>") && split.contains("rowspan=\"2\""), "a merge leaving the header row keeps one body: \(split)")
    }

    @Test func htmlRoundTripsCellTextSpansAndColors() {
        var table = NoteTableSpanTestsSupport.grid([["Name", "Q1", "Q2"], ["Ada", "3", "4"], ["Alan", "", "5"]])
        table.mergeCells(rows: 0...0, columns: 1...2)
        table.mergeCells(rows: 1...2, columns: 0...0)
        table.setColor(.background(.blue), rows: 1...1, columns: 1...1)
        let fragment = NotePageHTML.fragment(NoteTableSpanTestsSupport.page(table).blocks)
        let imported = NoteHTMLReader.blocks(from: fragment, baseURL: nil).first { $0.kind == .table }?.props.table
        #expect(imported?.merges == table.merges && imported?.cellColors == table.cellColors && imported.map(NoteTableSpanTestsSupport.strings) == NoteTableSpanTestsSupport.strings(table), "HTML with spans reads back: \(String(describing: imported?.merges))")
    }

    @Test func htmlImportKeepsColumnsAlignedAcrossRowspans() {
        let sheet = "<table><tr><td rowspan=\"2\">A</td><td>B</td><td>C</td></tr><tr><td colspan=\"2\">D</td></tr><tr><td>E</td><td>F</td><td>G</td></tr></table>"
        let spreadsheet = NoteHTMLReader.blocks(from: sheet, baseURL: nil).first { $0.kind == .table }?.props.table
        #expect(spreadsheet.map(NoteTableSpanTestsSupport.strings) == [["A", "B", "C"], ["", "D", ""], ["E", "F", "G"]], "rowspans keep columns lined up")
        #expect(spreadsheet?.merges == [NoteTableMerge(row: 0, column: 0, rowSpan: 2, columnSpan: 1), NoteTableMerge(row: 1, column: 1, rowSpan: 1, columnSpan: 2)], "and become merges: \(String(describing: spreadsheet?.merges))")
    }
}
