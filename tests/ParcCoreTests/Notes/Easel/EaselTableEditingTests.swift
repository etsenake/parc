import Foundation
import Testing
@testable import ParcCore

struct EaselTableEditingTests {
    @Test
    func insertedRowsAreBlankAndInheritColumnFill() {
        var table = EaselTableTestsSupport.filled([["a", "b"], ["c", "d"]])
        table.cells[0][1].fill = "#D8E9F3"
        table.cells[1][1].fill = "#D8E9F3"
        let didInsertRow = table.insertRows(at: 1)
        #expect(didInsertRow, "Rows insert")
        #expect(table.rowCount == 3 && table.cells[1].allSatisfy { $0.text.isEmpty } && table.cells[2][0].text == "c", "New rows are empty and push others down")
        #expect(table.cells[1][1].fill == "#D8E9F3" && table.cells[1][0].fill == nil, "A fully coloured column colours its new cell")
    }

    @Test
    func insertingAColumnKeepsItsWidth() {
        var table = EaselTableTestsSupport.filled([["a", "b"], ["c", "d"]])
        table.cells[0][1].fill = "#D8E9F3"
        table.cells[1][1].fill = "#D8E9F3"
        let didInsertColumn = table.insertColumns(at: 0, width: 90)
        #expect(didInsertColumn, "Columns insert")
        #expect(table.columnCount == 3 && table.columnWidths[0] == 90 && table.cells[0][1].text == "a", "New columns are empty and keep their width")
    }

    @Test
    func deletingRowsKeepsTheLastRow() {
        var table = EaselTableTestsSupport.filled([["a", "b"], ["c", "d"]])
        table.cells[0][1].fill = "#D8E9F3"
        table.cells[1][1].fill = "#D8E9F3"
        _ = table.insertRows(at: 1)
        _ = table.insertColumns(at: 0, width: 90)
        #expect(table.removeRows(1...1) && table.rowCount == 2 && table.cells[1][1].text == "c", "Rows delete")
        let keptLastRow = !table.removeRows(0...1)
        #expect(keptLastRow, "The last row can't be deleted")
    }

    @Test
    func deletingColumnsKeepsTheLastColumn() {
        var table = EaselTableTestsSupport.filled([["a", "b"], ["c", "d"]])
        table.cells[0][1].fill = "#D8E9F3"
        table.cells[1][1].fill = "#D8E9F3"
        _ = table.insertColumns(at: 0, width: 90)
        #expect(table.removeColumns(0...0) && table.columnCount == 2, "Columns delete")
        let keptLastColumn = !table.removeColumns(0...1)
        #expect(keptLastColumn, "The last column can't be deleted")
    }

    @Test
    func tableGrowthStopsAtTenThousandCells() {
        var full = EaselTable.blank(columns: 100, rows: 100)
        #expect(!full.insertRows(at: 0) && !full.insertColumns(at: 0), "Full tables refuse more")
        var wide = EaselTable.blank(columns: 100, rows: 99)
        #expect(wide.insertRows(at: 99) && !wide.insertRows(at: 0), "Cell limit allows exactly 10,000")
    }

    @Test
    func insertingAColumnInsideAMergeWidensIt() {
        var merged = EaselTableTestsSupport.filled([["a", "", "c"], ["d", "e", "f"]])
        merged.merges = [EaselTableMerge(row: 0, column: 0, rowSpan: 1, columnSpan: 2)]
        let didInsertInsideMerge = merged.insertColumns(at: 1)
        #expect(didInsertInsideMerge, "Inserting inside a merge works")
        #expect(merged.merges == [EaselTableMerge(row: 0, column: 0, rowSpan: 1, columnSpan: 3)], "Merges grow around inserted columns")
        #expect(merged.cells[0][1].isBlank && merged.cells[0][2].isBlank && (try? merged.validate()) != nil, "Cells under a merge stay blank")
    }

    @Test
    func deletingAMergedColumnKeepsTheAnchorText() {
        var merged = EaselTableTestsSupport.filled([["a", "", "c"], ["d", "e", "f"]])
        merged.merges = [EaselTableMerge(row: 0, column: 0, rowSpan: 1, columnSpan: 2)]
        _ = merged.insertColumns(at: 1)
        let didRemoveAnchorColumn = merged.removeColumns(0...0)
        #expect(didRemoveAnchorColumn, "Deleting a merge's anchor column works")
        #expect(merged.merges == [EaselTableMerge(row: 0, column: 0, rowSpan: 1, columnSpan: 2)] && merged.cells[0][0].text == "a", "The merge keeps its text")
        #expect(merged.removeColumns(0...0) && merged.merges.isEmpty && merged.cells[0][0].text == "a", "A merge shrunk to one cell disappears")
    }

    @Test
    func rowsCanDuplicateOnlyWholeMerges() {
        var cut = EaselTableTestsSupport.filled([["a", "x"], ["b", "y"], ["", "z"]])
        cut.merges = [EaselTableMerge(row: 1, column: 0, rowSpan: 2, columnSpan: 1)]
        #expect(!cut.duplicateRows(1...1) && !cut.duplicateRows(0...1), "Duplicating half a merged block is refused")
        #expect(cut.duplicateRows(1...2) && cut.merges.count == 2 && (try? cut.validate()) != nil, "Duplicating whole merged rows copies the merge")
    }

    @Test
    func columnsCanDuplicateOnlyWholeMerges() {
        var across = EaselTableTestsSupport.filled([["a", "", "c"]])
        across.merges = [EaselTableMerge(row: 0, column: 0, rowSpan: 1, columnSpan: 2)]
        #expect(!across.duplicateColumns(1...1) && across.duplicateColumns(0...1) && (try? across.validate()) != nil, "Columns duplicate only whole merges")
    }

    @Test
    func duplicatedRowsLandBelowTheOriginal() {
        var copy = EaselTableTestsSupport.filled([["a", "b"], ["c", "d"]])
        #expect(copy.duplicateRows(0...0) && copy.rowCount == 3 && copy.cells[1][0].text == "a" && copy.cells[2][0].text == "c", "Rows duplicate below")
    }

    @Test
    func duplicatedColumnsLandToTheRight() {
        var copy = EaselTableTestsSupport.filled([["a", "b"], ["c", "d"]])
        #expect(copy.duplicateColumns(1...1) && copy.columnCount == 3 && copy.cells[0][2].text == "b", "Columns duplicate to the right")
    }

    @Test
    func singleRowsAndBlocksMoveToTheirDestination() {
        var table = EaselTableTestsSupport.filled([["1"], ["2"], ["3"], ["4"]])
        let didMoveRow = table.moveRows(0...0, to: 2)
        #expect(didMoveRow, "Rows move")
        #expect(table.cells.map { $0[0].text } == ["2", "3", "1", "4"], "Row order follows the move")
        #expect(table.moveRows(2...3, to: 0) && table.cells.map { $0[0].text } == ["1", "4", "2", "3"], "Blocks of rows move together")
    }

    @Test
    func noOpAndOutOfRangeRowMovesAreRefused() {
        var table = EaselTableTestsSupport.filled([["1"], ["2"], ["3"], ["4"]])
        _ = table.moveRows(0...0, to: 2)
        #expect(table.moveRows(2...3, to: 0) && table.cells.map { $0[0].text } == ["1", "4", "2", "3"], "Blocks of rows move together")
        #expect(!table.moveRows(0...0, to: 0) && !table.moveRows(0...1, to: 3), "No-op and out-of-range moves are refused")
    }

    @Test
    func columnsMoveWithTheirWidths() {
        var columns = EaselTableTestsSupport.filled([["a", "b", "c"]])
        columns.columnWidths = [10, 20, 30].map { $0 * 5 }
        #expect(columns.moveColumns(2...2, to: 0) && columns.cells[0].map(\.text) == ["c", "a", "b"] && columns.columnWidths == [150, 50, 100], "Columns move with their widths")
    }

    @Test
    func mergesMoveWithTheirRows() {
        var merged = EaselTableTestsSupport.filled([["a", ""], ["c", "d"], ["e", "f"]])
        merged.merges = [EaselTableMerge(row: 0, column: 0, rowSpan: 1, columnSpan: 2)]
        #expect(merged.moveRows(0...0, to: 2) && merged.merges == [EaselTableMerge(row: 2, column: 0, rowSpan: 1, columnSpan: 2)], "Merges travel with their row")
    }

    @Test
    func aRowCannotMoveInsideAMergedBlock() {
        var split = EaselTableTestsSupport.filled([["a", "x"], ["", "y"], ["c", "z"]])
        split.merges = [EaselTableMerge(row: 0, column: 0, rowSpan: 2, columnSpan: 1)]
        #expect(!split.moveRows(2...2, to: 1) && split.merges.count == 1 && split.cells[2][0].text == "c", "A move into a merged block is refused")
    }

    @Test
    func optionMovesHopAcrossMergedRows() {
        var block = EaselTableTestsSupport.filled([["0"], ["1"], ["2"], ["3"], [""]])
        block.merges = [EaselTableMerge(row: 3, column: 0, rowSpan: 2, columnSpan: 1)]
        #expect(!block.keepsMerges(moving: 2...2, to: 3, along: .rows), "Landing inside rows 4–5 would split their merge")
        #expect(block.destination(moving: 2...2, by: 1, along: .rows) == 4, "Option-Down hops over the whole merged block")
        #expect(block.moveRows(2...2, to: 4) && block.merges == [EaselTableMerge(row: 2, column: 0, rowSpan: 2, columnSpan: 1)]
               && block.cells.map { $0[0].text } == ["0", "1", "3", "", "2"], "Moving past a merge keeps it whole")
        #expect(block.destination(moving: 4...4, by: -1, along: .rows) == 2, "Option-Up hops back over it")
    }

    @Test
    func keyboardMovesStopAtTheTableEdge() {
        var block = EaselTableTestsSupport.filled([["0"], ["1"], ["2"], ["3"], [""]])
        block.merges = [EaselTableMerge(row: 3, column: 0, rowSpan: 2, columnSpan: 1)]
        #expect(block.moveRows(2...2, to: 4) && block.merges == [EaselTableMerge(row: 2, column: 0, rowSpan: 2, columnSpan: 1)]
               && block.cells.map { $0[0].text } == ["0", "1", "3", "", "2"], "Moving past a merge keeps it whole")
        #expect(block.destination(moving: 1...1, by: -1, along: .rows) == 0 && block.destination(moving: 0...0, by: -1, along: .rows) == nil, "Moves stop at the edge")
    }

    @Test
    func aPartialMergeCannotMoveOnItsOwn() {
        var block = EaselTableTestsSupport.filled([["0"], ["1"], ["2"], ["3"], [""]])
        block.merges = [EaselTableMerge(row: 3, column: 0, rowSpan: 2, columnSpan: 1)]
        #expect(block.moveRows(2...2, to: 4) && block.merges == [EaselTableMerge(row: 2, column: 0, rowSpan: 2, columnSpan: 1)]
               && block.cells.map { $0[0].text } == ["0", "1", "3", "", "2"], "Moving past a merge keeps it whole")
        #expect(block.destination(moving: 2...2, by: -1, along: .rows) == nil, "Half a merged block never moves on its own")
        #expect(!block.moveRows(2...2, to: 0) && !block.keepsMerges(moving: 3...3, to: 0, along: .rows), "A block can't cut a merge in half")
    }

    @Test
    func aDragSnapsToADestinationThatKeepsMergesWhole() {
        var block = EaselTableTestsSupport.filled([["0"], ["1"], ["2"], ["3"], [""]])
        block.merges = [EaselTableMerge(row: 3, column: 0, rowSpan: 2, columnSpan: 1)]
        #expect(block.moveRows(2...2, to: 4) && block.merges == [EaselTableMerge(row: 2, column: 0, rowSpan: 2, columnSpan: 1)]
               && block.cells.map { $0[0].text } == ["0", "1", "3", "", "2"], "Moving past a merge keeps it whole")
        let snapped = block.nearestDestination(moving: 4...4, to: 3, along: .rows)
        #expect(snapped != 3 && (snapped == 4 || block.keepsMerges(moving: 4...4, to: snapped, along: .rows)), "Drags inside a merge snap to a safe spot")
        #expect(block.nearestDestination(moving: 0...0, to: 3, along: .rows) == 3, "Drags that keep merges whole land where dropped")
    }

    @Test
    func columnsCanMovePastAnIntactMerge() {
        var sideways = EaselTableTestsSupport.filled([["a", "b", "", "d"]])
        sideways.merges = [EaselTableMerge(row: 0, column: 1, rowSpan: 1, columnSpan: 2)]
        #expect(sideways.destination(moving: 0...0, by: 1, along: .columns) == 2, "Columns hop over merged blocks too")
        #expect(!sideways.moveColumns(0...0, to: 1) && sideways.moveColumns(0...0, to: 2) && sideways.cells[0].map(\.text) == ["b", "", "a", "d"]
               && sideways.merges == [EaselTableMerge(row: 0, column: 0, rowSpan: 1, columnSpan: 2)], "Column moves keep merges whole")
    }

    @Test
    func tabWrapsOrStopsAtTheGridBoundary() {
        let table = EaselTableTestsSupport.filled([["a", "b", "c"], ["d", "e", "f"]])
        #expect(table.tab(from: EaselTableTestsSupport.cell(0, 2), backward: false) == .cell(EaselTableTestsSupport.cell(1, 0)), "Tab wraps to the next row")
        #expect(table.tab(from: EaselTableTestsSupport.cell(1, 2), backward: false) == .appendRow, "Tab in the last cell adds a row")
        #expect(table.tab(from: EaselTableTestsSupport.cell(0, 0), backward: true) == .none, "Shift-Tab stops at the first cell")
    }

    @Test
    func tabStopsOnlyAtMergeAnchors() {
        var table = EaselTableTestsSupport.filled([["a", "b", "c"], ["d", "e", "f"]])
        table.merges = [EaselTableMerge(row: 0, column: 1, rowSpan: 2, columnSpan: 1)]
        table.cells[1][1] = EaselTableCell()
        #expect(table.tab(from: EaselTableTestsSupport.cell(0, 0), backward: false) == .cell(EaselTableTestsSupport.cell(0, 1)), "Tab enters a merged cell")
        #expect(table.tab(from: EaselTableTestsSupport.cell(1, 0), backward: false) == .cell(EaselTableTestsSupport.cell(1, 2)), "Tab skips covered cells")
    }

    @Test
    func arrowKeysEnterAMergeAndLeaveOnTheFarSide() {
        var table = EaselTableTestsSupport.filled([["a", "b", "c"], ["d", "e", "f"]])
        table.merges = [EaselTableMerge(row: 0, column: 1, rowSpan: 2, columnSpan: 1)]
        table.cells[1][1] = EaselTableCell()
        #expect(table.tab(from: EaselTableTestsSupport.cell(0, 0), backward: false) == .cell(EaselTableTestsSupport.cell(0, 1)), "Tab enters a merged cell")
        #expect(table.tab(from: EaselTableTestsSupport.cell(1, 0), backward: false) == .cell(EaselTableTestsSupport.cell(1, 2)), "Tab skips covered cells")
        #expect(table.step(from: EaselTableTestsSupport.cell(1, 0), .right) == EaselTableTestsSupport.cell(0, 1), "Arrows land on a merge's anchor")
        #expect(table.step(from: EaselTableTestsSupport.cell(0, 1), .right) == EaselTableTestsSupport.cell(0, 2), "Arrows leave a merge on the far side")
    }

    @Test
    func arrowMovementAndExtensionStayInsideTheGrid() {
        var table = EaselTableTestsSupport.filled([["a", "b", "c"], ["d", "e", "f"]])
        table.merges = [EaselTableMerge(row: 0, column: 1, rowSpan: 2, columnSpan: 1)]
        table.cells[1][1] = EaselTableCell()
        #expect(table.step(from: EaselTableTestsSupport.cell(0, 0), .up) == EaselTableTestsSupport.cell(0, 0) && table.step(from: EaselTableTestsSupport.cell(1, 2), .right) == EaselTableTestsSupport.cell(1, 2), "Arrows stop at the edges")
        #expect(table.extended(EaselTableTestsSupport.cell(1, 2), .down) == EaselTableTestsSupport.cell(1, 2) && table.extended(EaselTableTestsSupport.cell(0, 0), .right) == EaselTableTestsSupport.cell(0, 1), "Shift-arrows grow within bounds")
    }

    @Test
    func pastingExpandsTheGridAndReportsThePastedRange() {
        var table = EaselTableTestsSupport.filled([["a", "b"], ["c", "d"]])
        let source = EaselTableTestsSupport.filled([["1", "2", "3"], ["4", "5", "6"]])
        let area = table.paste(source, at: EaselTableTestsSupport.cell(1, 1))
        #expect(area == EaselTableRange(rows: 1...2, columns: 1...3), "Pasting reports where it landed")
        #expect(table.rowCount == 3 && table.columnCount == 4 && table.cells[2][3].text == "6" && table.cells[0][0].text == "a", "Pasting grows the table")
        #expect(table.columnWidths[3] == table.columnWidths[1], "Grown columns copy the last width")
    }

    @Test
    func pastingOneValueFillsEverySelectedCell() {
        var fill = EaselTableTestsSupport.filled([["a", "b"], ["c", "d"]])
        let one = EaselTableTestsSupport.filled([["x"]])
        #expect(fill.paste(one, at: EaselTableTestsSupport.cell(0, 0), filling: fill.all) == fill.all && fill.cells.allSatisfy { $0.allSatisfy { $0.text == "x" } }, "One value fills every selected cell")
    }

    @Test
    func pastingPlainTextKeepsTheCellFill() {
        var keep = EaselTableTestsSupport.filled([["a"]])
        keep.cells[0][0].fill = "#F9DEDC"
        _ = keep.paste(EaselTableTestsSupport.filled([["z"]]), at: EaselTableTestsSupport.cell(0, 0))
        #expect(keep.cells[0][0].text == "z" && keep.cells[0][0].fill == "#F9DEDC", "Plain pastes keep cell colours")
    }

    @Test
    func pastingCopiesMergesIntoTheNewRange() {
        var withMerge = EaselTable.blank(columns: 3, rows: 1)
        var mergedSource = EaselTableTestsSupport.filled([["m", ""]])
        mergedSource.merges = [EaselTableMerge(row: 0, column: 0, rowSpan: 1, columnSpan: 2)]
        _ = withMerge.paste(mergedSource, at: EaselTableTestsSupport.cell(0, 1))
        #expect(withMerge.merges == [EaselTableMerge(row: 0, column: 1, rowSpan: 1, columnSpan: 2)] && (try? withMerge.validate()) != nil, "Pasted merges come along")
    }

    @Test
    func pastingRespectsTheCellLimit() {
        var capped = EaselTable.blank(columns: 1, rows: 1)
        _ = capped.paste(EaselTable.blank(columns: 100, rows: 100), at: EaselTableTestsSupport.cell(0, 0))
        #expect(capped.rowCount * capped.columnCount <= EaselTable.maximumCells && (try? capped.validate()) != nil, "Pasting never breaks the limits")
    }

    @Test
    func slicingCopiesOnlyTheSelectedBlock() {
        let slice = EaselTableTestsSupport.filled([["a", "b", "c"], ["d", "e", "f"]]).slice(EaselTableRange(EaselTableTestsSupport.cell(0, 1), EaselTableTestsSupport.cell(1, 2)))
        #expect(slice?.cells.map { $0.map(\.text) } == [["b", "c"], ["e", "f"]], "Slices copy a block of cells")
    }

}
