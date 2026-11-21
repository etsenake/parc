import Foundation
import Testing
@testable import ParcCore

@MainActor struct NoteTableSpanTests {
    func cell(_ row: Int, _ column: Int) -> NoteTableCell { NoteTableCell(row: row, column: column) }

    func grid(_ rows: [[String]]) -> NoteTable {
        NoteTable(rows: rows.map { $0.map { NoteText($0) } })
    }

    func strings(_ table: NoteTable) -> [[String]] {
        table.rows.map { $0.map(\.string) }
    }

    func page(_ table: NoteTable) -> NotePage {
        var props = NoteBlockProps()
        props.table = table
        return NotePage(blocks: [NoteBlock(.table, props: props)])
    }

    @Test func a22BlockCanMerge() {
        var table = grid([["a", "b", "c"], ["d", "e", "f"], ["g", "h", "i"]])
        #expect(table.canMerge(rows: 0...1, columns: 0...1), "a 2×2 block can merge")
        #expect(!table.canMerge(rows: 1...1, columns: 1...1), "one cell can't merge")
        let hoisted26 = table.mergeCells(rows: 0...1, columns: 0...1)
        #expect(hoisted26, "merge")
        #expect(strings(table) == [["a", "", "c"], ["", "", "f"], ["g", "h", "i"]], "a merge keeps the top-left content: \(strings(table))")
        #expect(table.merges == [NoteTableMerge(row: 0, column: 0, rowSpan: 2, columnSpan: 2)], "one merge recorded")
        #expect(table.anchor(of: cell(1, 1)) == cell(0, 0) && table.isCovered(cell(1, 0)) && !table.isCovered(cell(0, 0)), "anchors")
        #expect(!table.canMerge(rows: 0...0, columns: 0...0), "an existing merge can't merge again")
        let grown = table.expanded(rows: 1...1, columns: 1...2)
        #expect(grown.rows == 0...1 && grown.columns == 0...2, "a range touching a merge grows to cover it")
        #expect(table.visibleCells.count == 6, "covered cells drop out of reading order")
        let hoisted34 = table.mergeCells(rows: 1...2, columns: 1...2)
        #expect(hoisted34, "merging over an existing merge absorbs it")
        #expect(table.merges == [NoteTableMerge(row: 0, column: 0, rowSpan: 3, columnSpan: 3)] && strings(table)[0][0] == "a", "absorbed into one big merge: \(table.merges)")
        let hoisted36 = table.unmergeCells(rows: 2...2, columns: 2...2)
        #expect(hoisted36, "unmerge from any covered cell")
        #expect(table.merges.isEmpty && strings(table) == [["a", "", ""], ["", "", ""], ["", "", ""]], "unmerged cells come back empty")
        let hoisted38 = !table.unmergeCells(rows: 0...2, columns: 0...2)
        #expect(hoisted38, "nothing left to unmerge")
    }

    @Test func textLandingInACoveredCellDissolvesTheMerge() {
        var typed = grid([["a", "b"], ["c", "d"]])
        typed.mergeCells(rows: 0...0, columns: 0...1)
        typed.rows[0][1] = NoteText("typed")
        typed.normalize()
        #expect(typed.merges.isEmpty && strings(typed)[0] == ["a", "typed"], "text landing in a covered cell dissolves the merge")
    }

    @Test func aRowInsertedInsideAMergeStretchesIt() {
        var table = grid([["a", "b", "c"], ["d", "e", "f"], ["g", "h", "i"], ["j", "k", "l"]])
        table.mergeCells(rows: 1...2, columns: 0...1)
        table.insertRow(at: 2)
        #expect(table.merges == [NoteTableMerge(row: 1, column: 0, rowSpan: 3, columnSpan: 2)], "a row inserted inside a merge stretches it")
        table.insertRow(at: 0)
        #expect(table.merges.first?.row == 2, "a row above pushes the merge down")
        table.insertRow(at: 5)
        #expect(table.merges.first?.rowSpan == 3, "a row right below leaves it alone")
        let hoisted58 = table.deleteRow(at: 2)
        #expect(hoisted58, "delete the merge's top row")
        #expect(table.merges == [NoteTableMerge(row: 2, column: 0, rowSpan: 2, columnSpan: 2)] && table.rows[2][0].string == "d", "the top-left content moves down with the merge: \(strings(table))")
        let hoisted60 = table.deleteRow(at: 3)
        #expect(hoisted60, "delete inside")
        #expect(table.merges.first?.rowSpan == 1 && table.merges.first?.columnSpan == 2, "merge shrinks")
    }

    @Test func columnInsertedInsideStretches() {
        var columns = grid([["a", "b", "c", "d"], ["e", "f", "g", "h"]])
        columns.mergeCells(rows: 0...1, columns: 1...2)
        columns.insertColumn(at: 2)
        #expect(columns.merges == [NoteTableMerge(row: 0, column: 1, rowSpan: 2, columnSpan: 3)], "column inserted inside stretches")
        columns.deleteColumn(at: 1)
        #expect(columns.merges == [NoteTableMerge(row: 0, column: 1, rowSpan: 2, columnSpan: 2)] && columns.rows[0][1].string == "b", "deleting the anchor column carries the content: \(strings(columns))")
        columns.moveColumn(from: 3, to: 0)
        #expect(columns.merges == [NoteTableMerge(row: 0, column: 2, rowSpan: 2, columnSpan: 2)] && columns.rows[0][2].string == "b", "moving a column past the merge shifts it")
        columns.moveColumn(from: 2, to: 3)
        #expect(columns.merges.first?.column == 2 && columns.rows[0][2].string == "b" && columns.rows[0][3].isEmpty, "swapping inside the merge keeps the content on top: \(strings(columns))")
        columns.moveColumn(from: 0, to: 2)
        #expect(columns.merges.isEmpty, "a column dropped into the middle splits the merge")

        var duplicate = grid([["a", "b", "c"], ["d", "e", "f"]])
        duplicate.mergeCells(rows: 0...0, columns: 0...1)
        duplicate.duplicateRow(at: 0)
        #expect(duplicate.merges.count == 2 && duplicate.merges.contains(NoteTableMerge(row: 1, column: 0, rowSpan: 1, columnSpan: 2)), "duplicating a row copies its sideways merges")
        var tall = grid([["a", "b"], ["c", "d"], ["e", "f"]])
        tall.mergeCells(rows: 0...1, columns: 0...0)
        tall.duplicateRow(at: 0)
        #expect(tall.merges == [NoteTableMerge(row: 0, column: 0, rowSpan: 3, columnSpan: 1)] && tall.rows[1][0].isEmpty, "duplicating inside a tall merge stretches it without hidden text: \(strings(tall))")
        var moved = grid([["a", "b"], ["c", "d"], ["e", "f"]])
        moved.mergeCells(rows: 0...0, columns: 0...1)
        moved.moveRow(from: 0, to: 2)
        #expect(moved.merges == [NoteTableMerge(row: 2, column: 0, rowSpan: 1, columnSpan: 2)] && moved.rows[2][0].string == "a", "a sideways merge rides along with its row")
    }

    @Test func colors() {
        var table = grid([["a", "b", "c"], ["d", "e", "f"], ["g", "h", "i"]])
        table.setColor(.background(.blue), rows: 0...2, columns: 1...1)
        #expect(table.uniformColor(column: 1) == .background(.blue), "a whole coloured column")
        table.insertRow(at: 3)
        #expect(table.color(at: cell(3, 1)) == .background(.blue) && table.color(at: cell(3, 0)) == nil, "new rows pick up a column's colour")
        table.setColor(.text(.red), rows: 1...1, columns: 0...2)
        table.insertColumn(at: 3)
        #expect(table.color(at: cell(1, 3)) == .text(.red) && table.color(at: cell(0, 3)) == nil, "new columns pick up a row's colour")
        table.mergeCells(rows: 1...2, columns: 0...1)
        #expect(table.cellColors[cell(2, 1)] == nil && table.color(at: cell(2, 1)) == .text(.red), "covered cells show the anchor's colour")
        table.setColor(.background(.yellow), rows: 2...2, columns: 1...1)
        #expect(table.color(at: cell(1, 0)) == .background(.yellow) && table.cellColors.keys.filter({ table.isCovered($0) }).isEmpty, "colouring part of a merge colours the whole merge")
        #expect(table.commonColor(rows: 1...2, columns: 0...1) == .some(.background(.yellow)), "common colour of a merge")
        #expect(table.commonColor(rows: 0...0, columns: 0...1) == .none, "mixed colours")
        table.duplicateRow(at: 0)
        #expect(table.color(at: cell(1, 1)) == .background(.blue), "duplicates keep their colours")
    }

    @Test func filling() {
        var table = grid([["a", "b", "c"], ["d", "e", "f"], ["g", "h", "i"]])
        table.setColor(.background(.green), rows: 0...0, columns: 0...0)
        let hoisted114 = table.fill(.down, rows: 0...2, columns: 0...1)
        #expect(hoisted114, "fill down")
        #expect(strings(table) == [["a", "b", "c"], ["a", "b", "f"], ["a", "b", "i"]], "fill down copies the first row: \(strings(table))")
        #expect(table.color(at: cell(2, 0)) == .background(.green), "fill brings the colour along")
        let hoisted117 = table.fill(.right, rows: 0...1, columns: 0...2)
        #expect(hoisted117, "fill right")
        #expect(strings(table)[0] == ["a", "a", "a"] && strings(table)[1] == ["a", "a", "a"], "fill right copies the first column")
        var single = grid([["x", "y"], ["", ""]])
        let hoisted120 = single.fill(.down, rows: 1...1, columns: 0...1)
        #expect(hoisted120, "a one-row selection fills from the row above")
        #expect(strings(single)[1] == ["x", "y"], "like a spreadsheet")
        var top = grid([["x", "y"]])
        let hoisted123 = !top.fill(.down, rows: 0...0, columns: 0...1)
        #expect(hoisted123, "nothing above the first row")
        var merged = grid([["a", "b", "c"], ["d", "e", "f"], ["g", "h", "i"]])
        merged.mergeCells(rows: 0...0, columns: 0...1)
        merged.fill(.down, rows: 0...2, columns: 0...2)
        #expect(strings(merged) == [["a", "", "c"], ["a", "a", "c"], ["a", "a", "c"]] && merged.merges.count == 1, "a merged source fills every cell under it: \(strings(merged))")
    }

    @Test func slicing() {
        var table = grid([["a", "b", "c"], ["d", "e", "f"], ["g", "h", "i"]])
        table.mergeCells(rows: 1...2, columns: 1...2)
        table.setColor(.text(.purple), rows: 1...1, columns: 1...1)
        let slice = table.slice(rows: 1...2, columns: 0...2)
        #expect(slice.merges == [NoteTableMerge(row: 0, column: 1, rowSpan: 2, columnSpan: 2)] && slice.color(at: cell(1, 2)) == .text(.purple), "slices keep merges and colours")
        var target = NoteTable.empty(rows: 2, columns: 2)
        let area = target.paste(slice, at: cell(1, 0))
        #expect(area.rows == 1...2 && area.columns == 0...2 && target.rowCount == 3 && target.columnCount == 3, "paste grows the table")
        #expect(target.merges == [NoteTableMerge(row: 1, column: 1, rowSpan: 2, columnSpan: 2)] && target.rows[1][1].string == "e", "paste recreates the merge")
        var overlap = grid([["a", "b"], ["c", "d"]])
        overlap.mergeCells(rows: 0...1, columns: 0...1)
        overlap.paste(grid([["x", "y"]]), at: cell(1, 0))
        #expect(overlap.merges.isEmpty && strings(overlap) == [["a", ""], ["x", "y"]], "pasting over part of a merge splits it")
    }

    @Test func resizing() {
        var table = grid([["a", "b", ""], ["c", "", ""], ["", "", ""]])
        #expect(table.trailingEmptyRows == 1 && table.trailingEmptyColumns == 1, "trailing empties")
        let hoisted149 = table.resize(rows: 5, columns: 4)
        #expect(hoisted149, "grow")
        #expect(table.rowCount == 5 && table.columnCount == 4, "grown")
        let hoisted151 = table.resize(rows: 1, columns: 1)
        #expect(hoisted151, "shrink")
        #expect(table.rowCount == 2 && table.columnCount == 2, "shrinking stops at content: \(table.rowCount)×\(table.columnCount)")
        var merged = grid([["a", ""], ["", ""], ["", ""]])
        merged.mergeCells(rows: 1...2, columns: 0...0)
        merged.rows[0][0] = NoteText()
        #expect(merged.trailingEmptyRows == 0, "a merge isn't empty")
        var blank = NoteTable.empty(rows: 3, columns: 3)
        blank.resize(rows: 0, columns: 0)
        #expect(blank.rowCount == 1 && blank.columnCount == 1, "at least one cell stays")
    }

    @Test func references() {
        #expect(NoteTableReference.columnName(0) == "A" && NoteTableReference.columnName(25) == "Z" && NoteTableReference.columnName(26) == "AA"
               && NoteTableReference.columnName(701) == "ZZ" && NoteTableReference.columnName(702) == "AAA", "column names")
        for index in [0, 1, 25, 26, 51, 52, 701, 702, 5000] {
            #expect(NoteTableReference.columnIndex(NoteTableReference.columnName(index)) == index, "column name round trip \(index)")
        }
        let range = NoteTableReference.range("C4:A2", rowCount: 10, columnCount: 10)
        #expect(range?.rows == 1...3 && range?.columns == 0...2, "corners in any order")
        #expect(NoteTableReference.range("B:C", rowCount: 4, columnCount: 5)?.rows == 0...3, "whole columns")
        #expect(NoteTableReference.range("2:3", rowCount: 4, columnCount: 5)?.columns == 0...4, "whole rows")
        #expect(NoteTableReference.range("b2", rowCount: 4, columnCount: 5)?.columns == 1...1, "lowercase is fine")
        #expect(NoteTableReference.range("Z9", rowCount: 4, columnCount: 5) == nil, "off the table")
        #expect(NoteTableReference.range("A1:B", rowCount: 4, columnCount: 5) == nil && NoteTableReference.range("", rowCount: 4, columnCount: 5) == nil
               && NoteTableReference.range("A0", rowCount: 4, columnCount: 5) == nil && NoteTableReference.range("1", rowCount: 4, columnCount: 5) == nil, "nonsense is ignored")
        #expect(NoteTableReference.range("C2:E9", rowCount: 4, columnCount: 4)?.columns == 2...3, "ranges clip to the table")
    }

    @Test func markdown() {
        var table = grid([["Name", "Q1", "Q2"], ["Ada", "3", "4"], ["Alan", "", "5"], ["Total", "", ""]])
        table.mergeCells(rows: 0...0, columns: 1...2)
        table.mergeCells(rows: 2...3, columns: 0...0)
        table.setColor(.background(.gray), rows: 0...3, columns: 0...0)
        table.setColor(.text(.red), rows: 1...1, columns: 1...2)
        table.setColor(.background(.blue), rows: 3...3, columns: 1...2)
        let text = NoteMarkdown.serialize(page(table))
        let lines = text.components(separatedBy: "\n")
        #expect(lines.first == "| Name | Q1  |     |", "merged-away cells stay empty in the pipe table: \(text)")
        #expect(lines.contains("| Ada  | 3   | 4   |") && lines.contains("|      |     | 5   |") == false, "rows read normally: \(text)")
        #expect(text.contains("<!-- parc merge=\"B1:C1,A3:A4\" colors=\"A:A=gray_background,4:4=blue_background,B2:C2=red\" -->"), "merges and colours ride in the parc comment: \(text)")
        let back = NoteMarkdown.parse(text).blocks.first?.props.table
        #expect(back == table, "lossless round trip: \(String(describing: back?.merges)) \(String(describing: back?.cellColors))")
        #expect(NoteMarkdown.serialize(NoteMarkdown.parse(text)) == text, "byte-stable second save")

        let edited = "| a | b |\n| - | - |\n| c | typed |\n<!-- parc merge=\"A2:B2\" -->\n"
        let handEdited = NoteMarkdown.parse(edited).blocks.first?.props.table
        #expect(handEdited?.merges.isEmpty == true && handEdited?.rows[1][1].string == "typed", "text typed into a merged-away cell wins")
        let sloppy = "| a | b |\n| - | - |\n| c |  |\n<!-- parc merge=\"A2:B2, Q9:Z99, nonsense\" colors=\"b1=RED,zz9=blue,A1=nope\" -->\n"
        let forgiving = NoteMarkdown.parse(sloppy).blocks.first?.props.table
        #expect(forgiving?.merges == [NoteTableMerge(row: 1, column: 0, rowSpan: 1, columnSpan: 2)]
               && forgiving?.cellColors == [cell(0, 1): .text(.red)], "bad references are skipped, good ones kept")

        var lone = grid([["x", "y"]])
        lone.setColor(.background(.pink), rows: 0...0, columns: 0...1)
        let loneText = NoteMarkdown.serialize(page(lone))
        #expect(loneText.contains("colors=\"1:1=pink_background\""), "a whole coloured row is written as a row: \(loneText)")
        #expect(NoteMarkdown.parse(loneText).blocks.first?.props.table == lone, "and reads back")
    }

    @Test func html() {
        var table = grid([["Name", "Q1", "Q2"], ["Ada", "3", "4"], ["Alan", "", "5"]])
        table.mergeCells(rows: 0...0, columns: 1...2)
        table.mergeCells(rows: 1...2, columns: 0...0)
        table.setColor(.background(.blue), rows: 1...1, columns: 1...1)
        let fragment = NotePageHTML.fragment(page(table).blocks)
        #expect(fragment.contains("<th scope=\"col\" colspan=\"2\""), "colspan in the header: \(fragment)")
        #expect(fragment.contains("<td rowspan=\"2\""), "rowspan in the body: \(fragment)")
        #expect(fragment.components(separatedBy: "<td").count - 1 == 5 && fragment.components(separatedBy: "<th ").count - 1 == 2, "covered cells aren't written")
        #expect(fragment.contains("data-color=\"blue_background\""), "cell colours: \(fragment)")
        let document = NotePageHTML.document(page(table), title: "Spans", assets: { _ in nil }, embedImages: false)
        #expect(document.contains("class=\"block-color-blue_background\""), "cell colours become classes in documents")
        var tall = grid([["a", "b"], ["", "c"]])
        tall.mergeCells(rows: 0...1, columns: 0...0)
        let split = NotePageHTML.fragment(page(tall).blocks)
        #expect(!split.contains("<thead>") && split.contains("rowspan=\"2\""), "a merge leaving the header row keeps one body: \(split)")

        let imported = NoteHTMLReader.blocks(from: fragment, baseURL: nil).first { $0.kind == .table }?.props.table
        #expect(imported?.merges == table.merges && imported?.cellColors == table.cellColors && imported.map(strings) == strings(table), "HTML with spans reads back: \(String(describing: imported?.merges))")
        let sheet = "<table><tr><td rowspan=\"2\">A</td><td>B</td><td>C</td></tr><tr><td colspan=\"2\">D</td></tr><tr><td>E</td><td>F</td><td>G</td></tr></table>"
        let spreadsheet = NoteHTMLReader.blocks(from: sheet, baseURL: nil).first { $0.kind == .table }?.props.table
        #expect(spreadsheet.map(strings) == [["A", "B", "C"], ["", "D", ""], ["E", "F", "G"]], "rowspans keep columns lined up")
        #expect(spreadsheet?.merges == [NoteTableMerge(row: 0, column: 0, rowSpan: 2, columnSpan: 1), NoteTableMerge(row: 1, column: 1, rowSpan: 1, columnSpan: 2)], "and become merges: \(String(describing: spreadsheet?.merges))")
    }

    @Test func session() throws {
        let session = NotePageSession(page: page(grid([["a", "b", "c"], ["d", "e", "f"], ["g", "h", "i"]])))
        let id = try #require(session.page.blocks.first?.id, "no table")
        session.setSelection(.cells(table: id, anchor: cell(0, 0), head: cell(1, 1)))
        #expect(session.mergeTableCells(id, rows: 0...1, columns: 0...1), "session merge")
        #expect(session.selection == .cells(table: id, anchor: cell(0, 0), head: cell(0, 0)), "the merged cell stays selected")
        session.undo()
        #expect(session.page.blocks.first?.props.table?.merges.isEmpty == true && session.page.blocks.first?.props.table?.rows[1][1].string == "e", "undo brings the hidden text back")
        session.redo()
        let fragment = session.fragment(of: .cells(table: id, anchor: cell(1, 1), head: cell(2, 2)))
        #expect(fragment.first?.props.table?.rowCount == 3 && fragment.first?.props.table?.merges.count == 1, "copy grows to whole merges")
        #expect(session.fillTableCells(id, .down, rows: 0...2, columns: 2...2), "session fill")
        #expect(session.page.blocks.first?.props.table?.rows[2][2].string == "c", "filled")
        #expect(session.setTableCellColor(id, .background(.red), rows: 0...0, columns: 2...2), "session colour")
        #expect(session.resizeTable(id, rows: 5, columns: 4), "session resize")
        #expect(session.page.blocks.first?.props.table?.rowCount == 5, "resized")
        #expect(session.unmergeTableCells(id, rows: 1...1, columns: 1...1), "session unmerge")
        #expect(session.page.blocks.first?.props.table?.merges.isEmpty == true, "unmerged")
    }
}
