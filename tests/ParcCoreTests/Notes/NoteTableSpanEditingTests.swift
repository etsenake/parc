import Foundation
import Testing
@testable import ParcCore

struct NoteTableSpanEditingTests {
    @Test func aColoredColumnReportsItsUniformColor() {
        var table = NoteTableSpanTestsSupport.grid([["a", "b", "c"], ["d", "e", "f"], ["g", "h", "i"]])
        table.setColor(.background(.blue), rows: 0...2, columns: 1...1)
        #expect(table.uniformColor(column: 1) == .background(.blue), "a whole coloured column")
    }

    @Test func newRowsInheritTheColumnColor() {
        var table = NoteTableSpanTestsSupport.grid([["a", "b", "c"], ["d", "e", "f"], ["g", "h", "i"]])
        table.setColor(.background(.blue), rows: 0...2, columns: 1...1)
        table.insertRow(at: 3)
        #expect(table.color(at: NoteTableSpanTestsSupport.cell(3, 1)) == .background(.blue) && table.color(at: NoteTableSpanTestsSupport.cell(3, 0)) == nil, "new rows pick up a column's colour")
    }

    @Test func newColumnsInheritTheRowColor() {
        var table = NoteTableSpanTestsSupport.grid([["a", "b", "c"], ["d", "e", "f"], ["g", "h", "i"]])
        table.setColor(.text(.red), rows: 1...1, columns: 0...2)
        table.insertColumn(at: 3)
        #expect(table.color(at: NoteTableSpanTestsSupport.cell(1, 3)) == .text(.red) && table.color(at: NoteTableSpanTestsSupport.cell(0, 3)) == nil, "new columns pick up a row's colour")
    }

    @Test func coveredCellsDisplayTheAnchorColor() {
        var table = NoteTableSpanTestsSupport.grid([["a", "b", "c"], ["d", "e", "f"], ["g", "h", "i"]])
        table.setColor(.text(.red), rows: 1...1, columns: 0...2)
        table.mergeCells(rows: 1...2, columns: 0...1)
        #expect(table.cellColors[NoteTableSpanTestsSupport.cell(2, 1)] == nil && table.color(at: NoteTableSpanTestsSupport.cell(2, 1)) == .text(.red), "covered cells show the anchor's colour")
    }

    @Test func coloringPartOfAMergeColorsOnlyItsAnchor() {
        var table = NoteTableSpanTestsSupport.grid([["a", "b", "c"], ["d", "e", "f"], ["g", "h", "i"]])
        table.setColor(.text(.red), rows: 1...1, columns: 0...2)
        table.mergeCells(rows: 1...2, columns: 0...1)
        table.setColor(.background(.yellow), rows: 2...2, columns: 1...1)
        #expect(table.color(at: NoteTableSpanTestsSupport.cell(1, 0)) == .background(.yellow) && table.cellColors.keys.filter({ table.isCovered($0) }).isEmpty, "colouring part of a merge colours the whole merge")
    }

    @Test func aMergedRangeReportsItsCommonColor() {
        var table = NoteTableSpanTestsSupport.grid([["a", "b", "c"], ["d", "e", "f"], ["g", "h", "i"]])
        table.mergeCells(rows: 1...2, columns: 0...1)
        table.setColor(.background(.yellow), rows: 2...2, columns: 1...1)
        #expect(table.commonColor(rows: 1...2, columns: 0...1) == .some(.background(.yellow)), "common colour of a merge")
    }

    @Test func aRangeWithMixedColorsHasNoCommonColor() {
        var table = NoteTableSpanTestsSupport.grid([["a", "b", "c"], ["d", "e", "f"], ["g", "h", "i"]])
        table.setColor(.background(.blue), rows: 0...2, columns: 1...1)
        #expect(table.commonColor(rows: 0...0, columns: 0...1) == .none, "mixed colours")
    }

    @Test func duplicatingARowPreservesItsColors() {
        var table = NoteTableSpanTestsSupport.grid([["a", "b", "c"], ["d", "e", "f"], ["g", "h", "i"]])
        table.setColor(.background(.blue), rows: 0...2, columns: 1...1)
        table.duplicateRow(at: 0)
        #expect(table.color(at: NoteTableSpanTestsSupport.cell(1, 1)) == .background(.blue), "duplicates keep their colours")
    }

    @Test func fillingDownCopiesTheFirstRowAndItsColor() {
        var table = NoteTableSpanTestsSupport.grid([["a", "b", "c"], ["d", "e", "f"], ["g", "h", "i"]])
        table.setColor(.background(.green), rows: 0...0, columns: 0...0)
        let filled = table.fill(.down, rows: 0...2, columns: 0...1)
        #expect(filled, "fill down")
        #expect(NoteTableSpanTestsSupport.strings(table) == [["a", "b", "c"], ["a", "b", "f"], ["a", "b", "i"]], "fill down copies the first row: \(NoteTableSpanTestsSupport.strings(table))")
        #expect(table.color(at: NoteTableSpanTestsSupport.cell(2, 0)) == .background(.green), "fill brings the colour along")
    }

    @Test func fillingRightCopiesTheFirstColumn() {
        var table = NoteTableSpanTestsSupport.grid([["a", "b", "c"], ["d", "e", "f"], ["g", "h", "i"]])
        table.setColor(.background(.green), rows: 0...0, columns: 0...0)
        _ = table.fill(.down, rows: 0...2, columns: 0...1)
        let filled = table.fill(.right, rows: 0...1, columns: 0...2)
        #expect(filled, "fill right")
        #expect(NoteTableSpanTestsSupport.strings(table)[0] == ["a", "a", "a"] && NoteTableSpanTestsSupport.strings(table)[1] == ["a", "a", "a"], "fill right copies the first column")
    }

    @Test func fillingASingleRowCopiesTheRowAbove() {
        var single = NoteTableSpanTestsSupport.grid([["x", "y"], ["", ""]])
        let filled = single.fill(.down, rows: 1...1, columns: 0...1)
        #expect(filled, "a one-row selection fills from the row above")
        #expect(NoteTableSpanTestsSupport.strings(single)[1] == ["x", "y"], "like a spreadsheet")
    }

    @Test func fillingTheFirstRowFromAboveDoesNothing() {
        var top = NoteTableSpanTestsSupport.grid([["x", "y"]])
        let fillWasRefused = !top.fill(.down, rows: 0...0, columns: 0...1)
        #expect(fillWasRefused, "nothing above the first row")
    }

    @Test func fillingDownFromAMergeCopiesTheAnchorIntoEachCell() {
        var merged = NoteTableSpanTestsSupport.grid([["a", "b", "c"], ["d", "e", "f"], ["g", "h", "i"]])
        merged.mergeCells(rows: 0...0, columns: 0...1)
        merged.fill(.down, rows: 0...2, columns: 0...2)
        #expect(NoteTableSpanTestsSupport.strings(merged) == [["a", "", "c"], ["a", "a", "c"], ["a", "a", "c"]] && merged.merges.count == 1, "a merged source fills every cell under it: \(NoteTableSpanTestsSupport.strings(merged))")
    }

    @Test func aTableSliceKeepsMergesAndColors() {
        var table = NoteTableSpanTestsSupport.grid([["a", "b", "c"], ["d", "e", "f"], ["g", "h", "i"]])
        table.mergeCells(rows: 1...2, columns: 1...2)
        table.setColor(.text(.purple), rows: 1...1, columns: 1...1)
        let slice = table.slice(rows: 1...2, columns: 0...2)
        #expect(slice.merges == [NoteTableMerge(row: 0, column: 1, rowSpan: 2, columnSpan: 2)] && slice.color(at: NoteTableSpanTestsSupport.cell(1, 2)) == .text(.purple), "slices keep merges and colours")
    }

    @Test func pastingATableSliceExpandsTheTableAndRecreatesItsMerge() {
        var table = NoteTableSpanTestsSupport.grid([["a", "b", "c"], ["d", "e", "f"], ["g", "h", "i"]])
        table.mergeCells(rows: 1...2, columns: 1...2)
        table.setColor(.text(.purple), rows: 1...1, columns: 1...1)
        let slice = table.slice(rows: 1...2, columns: 0...2)
        var target = NoteTable.empty(rows: 2, columns: 2)
        let area = target.paste(slice, at: NoteTableSpanTestsSupport.cell(1, 0))
        #expect(area.rows == 1...2 && area.columns == 0...2 && target.rowCount == 3 && target.columnCount == 3, "paste grows the table")
        #expect(target.merges == [NoteTableMerge(row: 1, column: 1, rowSpan: 2, columnSpan: 2)] && target.rows[1][1].string == "e", "paste recreates the merge")
    }

    @Test func pastingOverPartOfAMergeSplitsIt() {
        var overlap = NoteTableSpanTestsSupport.grid([["a", "b"], ["c", "d"]])
        overlap.mergeCells(rows: 0...1, columns: 0...1)
        overlap.paste(NoteTableSpanTestsSupport.grid([["x", "y"]]), at: NoteTableSpanTestsSupport.cell(1, 0))
        #expect(overlap.merges.isEmpty && NoteTableSpanTestsSupport.strings(overlap) == [["a", ""], ["x", "y"]], "pasting over part of a merge splits it")
    }

    @Test func trailingEmptyRowsAndColumnsAreCounted() {
        let table = NoteTableSpanTestsSupport.grid([["a", "b", ""], ["c", "", ""], ["", "", ""]])
        #expect(table.trailingEmptyRows == 1 && table.trailingEmptyColumns == 1, "trailing empties")
    }

    @Test func resizingCanGrowATable() {
        var table = NoteTableSpanTestsSupport.grid([["a", "b", ""], ["c", "", ""], ["", "", ""]])
        let resized = table.resize(rows: 5, columns: 4)
        #expect(resized, "grow")
        #expect(table.rowCount == 5 && table.columnCount == 4, "grown")
    }

    @Test func shrinkingKeepsCellsThatContainContent() {
        var table = NoteTableSpanTestsSupport.grid([["a", "b", ""], ["c", "", ""], ["", "", ""]])
        _ = table.resize(rows: 5, columns: 4)
        let resized = table.resize(rows: 1, columns: 1)
        #expect(resized, "shrink")
        #expect(table.rowCount == 2 && table.columnCount == 2, "shrinking stops at content: \(table.rowCount)×\(table.columnCount)")
    }

    @Test func mergedRowsAreNotEmpty() {
        var merged = NoteTableSpanTestsSupport.grid([["a", ""], ["", ""], ["", ""]])
        merged.mergeCells(rows: 1...2, columns: 0...0)
        merged.rows[0][0] = NoteText()
        #expect(merged.trailingEmptyRows == 0, "a merge isn't empty")
    }

    @Test func resizingKeepsAtLeastOneCell() {
        var blank = NoteTable.empty(rows: 3, columns: 3)
        blank.resize(rows: 0, columns: 0)
        #expect(blank.rowCount == 1 && blank.columnCount == 1, "at least one cell stays")
    }
}
