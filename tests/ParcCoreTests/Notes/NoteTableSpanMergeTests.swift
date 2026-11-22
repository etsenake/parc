import Foundation
import Testing
@testable import ParcCore

struct NoteTableSpanMergeTests {
    @Test func aTwoByTwoRangeCanMerge() {
        let table = NoteTableSpanTestsSupport.grid([["a", "b", "c"], ["d", "e", "f"], ["g", "h", "i"]])
        #expect(table.canMerge(rows: 0...1, columns: 0...1), "a 2×2 block can merge")
    }

    @Test func oneCellCannotMerge() {
        let table = NoteTableSpanTestsSupport.grid([["a", "b", "c"], ["d", "e", "f"], ["g", "h", "i"]])
        #expect(!table.canMerge(rows: 1...1, columns: 1...1), "one cell can't merge")
    }

    @Test func mergingKeepsTheAnchorContentAndRecordsTheSpan() {
        var table = NoteTableSpanTestsSupport.grid([["a", "b", "c"], ["d", "e", "f"], ["g", "h", "i"]])
        let merged = table.mergeCells(rows: 0...1, columns: 0...1)
        #expect(merged, "merge")
        #expect(NoteTableSpanTestsSupport.strings(table) == [["a", "", "c"], ["", "", "f"], ["g", "h", "i"]], "a merge keeps the top-left content: \(NoteTableSpanTestsSupport.strings(table))")
        #expect(table.merges == [NoteTableMerge(row: 0, column: 0, rowSpan: 2, columnSpan: 2)], "one merge recorded")
    }

    @Test func coveredCellsResolveToTheirAnchor() {
        var table = NoteTableSpanTestsSupport.grid([["a", "b", "c"], ["d", "e", "f"], ["g", "h", "i"]])
        _ = table.mergeCells(rows: 0...1, columns: 0...1)
        #expect(table.anchor(of: NoteTableSpanTestsSupport.cell(1, 1)) == NoteTableSpanTestsSupport.cell(0, 0) && table.isCovered(NoteTableSpanTestsSupport.cell(1, 0)) && !table.isCovered(NoteTableSpanTestsSupport.cell(0, 0)), "anchors")
    }

    @Test func aRangeWithinAMergeCannotMergeAgain() {
        var table = NoteTableSpanTestsSupport.grid([["a", "b", "c"], ["d", "e", "f"], ["g", "h", "i"]])
        _ = table.mergeCells(rows: 0...1, columns: 0...1)
        #expect(!table.canMerge(rows: 0...0, columns: 0...0), "an existing merge can't merge again")
    }

    @Test func aRangeTouchingAMergeExpandsToIncludeIt() {
        var table = NoteTableSpanTestsSupport.grid([["a", "b", "c"], ["d", "e", "f"], ["g", "h", "i"]])
        _ = table.mergeCells(rows: 0...1, columns: 0...1)
        let grown = table.expanded(rows: 1...1, columns: 1...2)
        #expect(grown.rows == 0...1 && grown.columns == 0...2, "a range touching a merge grows to cover it")
    }

    @Test func coveredCellsAreSkippedInReadingOrder() {
        var table = NoteTableSpanTestsSupport.grid([["a", "b", "c"], ["d", "e", "f"], ["g", "h", "i"]])
        _ = table.mergeCells(rows: 0...1, columns: 0...1)
        #expect(table.visibleCells.count == 6, "covered cells drop out of reading order")
    }

    @Test func anOverlappingMergeAbsorbsTheExistingMerge() {
        var table = NoteTableSpanTestsSupport.grid([["a", "b", "c"], ["d", "e", "f"], ["g", "h", "i"]])
        _ = table.mergeCells(rows: 0...1, columns: 0...1)
        let merged = table.mergeCells(rows: 1...2, columns: 1...2)
        #expect(merged, "merging over an existing merge absorbs it")
        #expect(table.merges == [NoteTableMerge(row: 0, column: 0, rowSpan: 3, columnSpan: 3)] && NoteTableSpanTestsSupport.strings(table)[0][0] == "a", "absorbed into one big merge: \(table.merges)")
    }

    @Test func unmergingFromACoveredCellRestoresEmptyCells() {
        var table = NoteTableSpanTestsSupport.grid([["a", "b", "c"], ["d", "e", "f"], ["g", "h", "i"]])
        _ = table.mergeCells(rows: 0...1, columns: 0...1)
        _ = table.mergeCells(rows: 1...2, columns: 1...2)
        let unmerged = table.unmergeCells(rows: 2...2, columns: 2...2)
        #expect(unmerged, "unmerge from any covered cell")
        #expect(table.merges.isEmpty && NoteTableSpanTestsSupport.strings(table) == [["a", "", ""], ["", "", ""], ["", "", ""]], "unmerged cells come back empty")
    }

    @Test func unmergingWhenNoMergeExistsIsANoOp() {
        var table = NoteTableSpanTestsSupport.grid([["a", "b", "c"], ["d", "e", "f"], ["g", "h", "i"]])
        _ = table.mergeCells(rows: 0...2, columns: 0...2)
        _ = table.unmergeCells(rows: 2...2, columns: 2...2)
        let unmergeWasRefused = !table.unmergeCells(rows: 0...2, columns: 0...2)
        #expect(unmergeWasRefused, "nothing left to unmerge")
    }

    @Test func editingACoveredCellDissolvesTheMerge() {
        var typed = NoteTableSpanTestsSupport.grid([["a", "b"], ["c", "d"]])
        typed.mergeCells(rows: 0...0, columns: 0...1)
        typed.rows[0][1] = NoteText("typed")
        typed.normalize()
        #expect(typed.merges.isEmpty && NoteTableSpanTestsSupport.strings(typed)[0] == ["a", "typed"], "text landing in a covered cell dissolves the merge")
    }

    @Test func insertingARowInsideAMergeStretchesIt() {
        var table = NoteTableSpanTestsSupport.grid([["a", "b", "c"], ["d", "e", "f"], ["g", "h", "i"], ["j", "k", "l"]])
        table.mergeCells(rows: 1...2, columns: 0...1)
        table.insertRow(at: 2)
        #expect(table.merges == [NoteTableMerge(row: 1, column: 0, rowSpan: 3, columnSpan: 2)], "a row inserted inside a merge stretches it")
    }

    @Test func insertingARowAboveAMergeShiftsItDown() {
        var table = NoteTableSpanTestsSupport.grid([["a", "b", "c"], ["d", "e", "f"], ["g", "h", "i"], ["j", "k", "l"]])
        table.mergeCells(rows: 1...2, columns: 0...1)
        table.insertRow(at: 2)
        table.insertRow(at: 0)
        #expect(table.merges.first?.row == 2, "a row above pushes the merge down")
    }

    @Test func insertingARowBelowAMergeLeavesItsSpanAlone() {
        var table = NoteTableSpanTestsSupport.grid([["a", "b", "c"], ["d", "e", "f"], ["g", "h", "i"], ["j", "k", "l"]])
        table.mergeCells(rows: 1...2, columns: 0...1)
        table.insertRow(at: 2)
        table.insertRow(at: 0)
        table.insertRow(at: 5)
        #expect(table.merges.first?.rowSpan == 3, "a row right below leaves it alone")
    }

    @Test func deletingTheAnchorRowMovesItsContentIntoTheRemainingMerge() {
        var table = NoteTableSpanTestsSupport.grid([["a", "b", "c"], ["d", "e", "f"], ["g", "h", "i"], ["j", "k", "l"]])
        table.mergeCells(rows: 1...2, columns: 0...1)
        table.insertRow(at: 2)
        table.insertRow(at: 0)
        table.insertRow(at: 5)
        let deletedRow = table.deleteRow(at: 2)
        #expect(deletedRow, "delete the merge's top row")
        #expect(table.merges == [NoteTableMerge(row: 2, column: 0, rowSpan: 2, columnSpan: 2)] && table.rows[2][0].string == "d", "the top-left content moves down with the merge: \(NoteTableSpanTestsSupport.strings(table))")
    }

    @Test func deletingARowInsideAMergeShrinksIt() {
        var table = NoteTableSpanTestsSupport.grid([["a", "b", "c"], ["d", "e", "f"], ["g", "h", "i"], ["j", "k", "l"]])
        table.mergeCells(rows: 1...2, columns: 0...1)
        table.insertRow(at: 2)
        table.insertRow(at: 0)
        table.insertRow(at: 5)
        _ = table.deleteRow(at: 2)
        let deletedRow = table.deleteRow(at: 3)
        #expect(deletedRow, "delete inside")
        #expect(table.merges.first?.rowSpan == 1 && table.merges.first?.columnSpan == 2, "merge shrinks")
    }

    @Test func insertingAColumnInsideAMergeStretchesIt() {
        var columns = NoteTableSpanTestsSupport.grid([["a", "b", "c", "d"], ["e", "f", "g", "h"]])
        columns.mergeCells(rows: 0...1, columns: 1...2)
        columns.insertColumn(at: 2)
        #expect(columns.merges == [NoteTableMerge(row: 0, column: 1, rowSpan: 2, columnSpan: 3)], "column inserted inside stretches")
    }

    @Test func deletingTheAnchorColumnKeepsItsContent() {
        var columns = NoteTableSpanTestsSupport.grid([["a", "b", "c", "d"], ["e", "f", "g", "h"]])
        columns.mergeCells(rows: 0...1, columns: 1...2)
        columns.insertColumn(at: 2)
        columns.deleteColumn(at: 1)
        #expect(columns.merges == [NoteTableMerge(row: 0, column: 1, rowSpan: 2, columnSpan: 2)] && columns.rows[0][1].string == "b", "deleting the anchor column carries the content: \(NoteTableSpanTestsSupport.strings(columns))")
    }

    @Test func movingAColumnPastAMergeShiftsTheMerge() {
        var columns = NoteTableSpanTestsSupport.grid([["a", "b", "c", "d"], ["e", "f", "g", "h"]])
        columns.mergeCells(rows: 0...1, columns: 1...2)
        columns.insertColumn(at: 2)
        columns.deleteColumn(at: 1)
        columns.moveColumn(from: 3, to: 0)
        #expect(columns.merges == [NoteTableMerge(row: 0, column: 2, rowSpan: 2, columnSpan: 2)] && columns.rows[0][2].string == "b", "moving a column past the merge shifts it")
    }

    @Test func movingAColumnInsideAMergeKeepsTheAnchorContent() {
        var columns = NoteTableSpanTestsSupport.grid([["a", "b", "c", "d"], ["e", "f", "g", "h"]])
        columns.mergeCells(rows: 0...1, columns: 1...2)
        columns.insertColumn(at: 2)
        columns.deleteColumn(at: 1)
        columns.moveColumn(from: 3, to: 0)
        columns.moveColumn(from: 2, to: 3)
        #expect(columns.merges.first?.column == 2 && columns.rows[0][2].string == "b" && columns.rows[0][3].isEmpty, "swapping inside the merge keeps the content on top: \(NoteTableSpanTestsSupport.strings(columns))")
    }

    @Test func movingAColumnIntoAMergeSplitsTheMerge() {
        var columns = NoteTableSpanTestsSupport.grid([["a", "b", "c", "d"], ["e", "f", "g", "h"]])
        columns.mergeCells(rows: 0...1, columns: 1...2)
        columns.insertColumn(at: 2)
        columns.deleteColumn(at: 1)
        columns.moveColumn(from: 3, to: 0)
        columns.moveColumn(from: 2, to: 3)
        columns.moveColumn(from: 0, to: 2)
        #expect(columns.merges.isEmpty, "a column dropped into the middle splits the merge")
    }

    @Test func duplicatingARowCopiesItsHorizontalMerge() {
        var duplicate = NoteTableSpanTestsSupport.grid([["a", "b", "c"], ["d", "e", "f"]])
        duplicate.mergeCells(rows: 0...0, columns: 0...1)
        duplicate.duplicateRow(at: 0)
        #expect(duplicate.merges.count == 2 && duplicate.merges.contains(NoteTableMerge(row: 1, column: 0, rowSpan: 1, columnSpan: 2)), "duplicating a row copies its sideways merges")
    }

    @Test func duplicatingARowInsideAVerticalMergeStretchesIt() {
        var tall = NoteTableSpanTestsSupport.grid([["a", "b"], ["c", "d"], ["e", "f"]])
        tall.mergeCells(rows: 0...1, columns: 0...0)
        tall.duplicateRow(at: 0)
        #expect(tall.merges == [NoteTableMerge(row: 0, column: 0, rowSpan: 3, columnSpan: 1)] && tall.rows[1][0].isEmpty, "duplicating inside a tall merge stretches it without hidden text: \(NoteTableSpanTestsSupport.strings(tall))")
    }

    @Test func movingARowCarriesItsHorizontalMerge() {
        var moved = NoteTableSpanTestsSupport.grid([["a", "b"], ["c", "d"], ["e", "f"]])
        moved.mergeCells(rows: 0...0, columns: 0...1)
        moved.moveRow(from: 0, to: 2)
        #expect(moved.merges == [NoteTableMerge(row: 2, column: 0, rowSpan: 1, columnSpan: 2)] && moved.rows[2][0].string == "a", "a sideways merge rides along with its row")
    }
}
