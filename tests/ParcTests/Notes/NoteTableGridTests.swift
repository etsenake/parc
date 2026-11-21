import Foundation
import Testing
@testable import Parc
@testable import ParcCore

@MainActor
struct NoteTableGridTests {
    func cell(_ row: Int, _ column: Int) -> NoteTableCell { NoteTableCell(row: row, column: column) }

    @Test func unsetWidthsShareTheSpaceEvenly() { #expect(NoteTableMetrics.resolvedWidths([nil, nil, nil], available: 720) == [240, 240, 240]) }

    @Test func unsetWidthsShareWhatFixedOnesLeave() { #expect(NoteTableMetrics.resolvedWidths([200, nil, nil], available: 720) == [200, 260, 260]) }

    @Test func crowdedTablesKeepAReadableSharedWidthAndScroll() {
        #expect(NoteTableMetrics.resolvedWidths(Array(repeating: nil, count: 8), available: 720).allSatisfy { $0 == NoteTableMetrics.minimumSharedWidth })
    }

    @Test func fixedWidthsRespectTheMinimum() {
        #expect(NoteTableMetrics.resolvedWidths([10, 300], available: 720) == [NoteTableMetrics.minimumColumnWidth, 300])
    }

    @Test func allFixedTablesKeepTheirOwnWidth() { #expect(NoteTableMetrics.resolvedWidths([120, 130], available: 720) == [120, 130]) }

    @Test func noColumnsNoWidths() { #expect(NoteTableMetrics.resolvedWidths([], available: 720).isEmpty) }

    @Test func aFocusedCellFromARowUndoJustRemovedIsDroppedLiveOnesStay() {
        let kept = NoteTableMetrics.keptCells(rows: 58...59, columns: 0...2, also: [cell(60, 1), cell(3, 0)], rowCount: 60, columnCount: 3)
        #expect(!kept.contains(cell(60, 1)))
        #expect(kept.contains(cell(3, 0)))
        #expect(kept.contains(cell(59, 2)))
    }

    @Test func staleVisibleRowsPastTheEndKeepNothing() {
        #expect(NoteTableMetrics.keptCells(rows: 70...80, columns: 0...2, also: [], rowCount: 60, columnCount: 3).isEmpty)
    }

    @Test func vanishedColumnsAndNegativeCellsAreIgnored() {
        #expect(NoteTableMetrics.keptCells(rows: 0...1, columns: 5...6, also: [cell(0, -1)], rowCount: 2, columnCount: 3).isEmpty)
    }

    @Test func sharedColumnsFillTheWidthExactlyTheLastTakingTheSparePoints() {
        let thirds = NoteTableMetrics.resolvedWidths([nil, nil, nil], available: 700)
        #expect(thirds == [233, 233, 234])
        #expect(thirds.reduce(0, +) == 700)
    }

    @Test func aFractionalWidthFillsToTheEdge() {
        #expect(NoteTableMetrics.resolvedWidths([nil, 120, nil], available: 700.5).reduce(0, +) == 700.5)
    }

    @Test func resizingMovesOnlyTheDraggedColumn() { #expect(NoteTableMetrics.resized([100, 100], column: 0, by: 37.4) == [137, 100]) }

    @Test func resizingStopsAtTheMinimum() {
        #expect(NoteTableMetrics.resized([100, 100], column: 1, by: -500) == [100, NoteTableMetrics.minimumColumnWidth])
    }

    @Test func edgesAccumulate() { #expect(NoteTableMetrics.edges([10, 20, 30]) == [0, 10, 30, 60]) }

    @Test func storedWidthsRoundAndClamp() {
        var table = NoteTable.empty(rows: 2, columns: 3)
        NoteTableTransforms.setWidths([150.4, 20, nil], in: &table)
        #expect(table.columnWidths == [150, NoteTableMetrics.minimumColumnWidth, nil])
    }

    func tab(_ from: NoteTableCell, backward: Bool) -> NoteTableDestination { NoteTableNavigation.tab(from: from, rows: 2, columns: 3, backward: backward) }
    func step(_ from: NoteTableCell, _ direction: NoteTableDirection) -> NoteTableDestination { NoteTableNavigation.step(from: from, direction, rows: 2, columns: 3) }

    @Test func tabMovesRight() { #expect(tab(cell(0, 0), backward: false) == .cell(cell(0, 1))) }

    @Test func tabWrapsToTheNextRow() { #expect(tab(cell(0, 2), backward: false) == .cell(cell(1, 0))) }

    @Test func tabInTheLastCellAddsARow() { #expect(tab(cell(1, 2), backward: false) == .appendRow) }

    @Test func shiftTabWrapsBack() { #expect(tab(cell(1, 0), backward: true) == .cell(cell(0, 2))) }

    @Test func shiftTabStopsAtTheFirstCell() { #expect(tab(cell(0, 0), backward: true) == .stay) }

    @Test func upFromTheTopRowLeavesTheTable() { #expect(step(cell(0, 1), .up) == .exitBefore) }

    @Test func upKeepsTheColumn() { #expect(step(cell(1, 1), .up) == .cell(cell(0, 1))) }

    @Test func downFromTheLastRowLeavesTheTable() { #expect(step(cell(1, 1), .down) == .exitAfter) }

    @Test func leftWrapsToThePreviousRow() { #expect(step(cell(1, 0), .left) == .cell(cell(0, 2))) }

    @Test func leftFromTheFirstCellLeaves() { #expect(step(cell(0, 0), .left) == .exitBefore) }

    @Test func rightWrapsToTheNextRow() { #expect(step(cell(0, 2), .right) == .cell(cell(1, 0))) }

    @Test func rightFromTheLastCellLeaves() { #expect(step(cell(1, 2), .right) == .exitAfter) }

    @Test func returnMovesDownACell() { #expect(NoteTableNavigation.returnKey(from: cell(0, 2), rows: 2) == .cell(cell(1, 2))) }

    @Test func returnOnTheLastRowLeaves() { #expect(NoteTableNavigation.returnKey(from: cell(1, 2), rows: 2) == .exitAfter) }

    @Test func extendingClampsAtTheTop() { #expect(NoteTableNavigation.moved(cell(0, 0), .up, rows: 2, columns: 3) == cell(0, 0)) }

    @Test func extendingMovesTheHead() { #expect(NoteTableNavigation.moved(cell(1, 1), .right, rows: 2, columns: 3) == cell(1, 2)) }

    @Test func extendingClampsAtTheEdge() { #expect(NoteTableNavigation.moved(cell(1, 2), .right, rows: 2, columns: 3) == cell(1, 2)) }

    let rect = NoteTableRect(NoteTableCell(row: 2, column: 3), NoteTableCell(row: 0, column: 1))

    @Test func anchorAndHeadNormalizeIntoARectangle() {
        #expect(rect.rows == 0...2)
        #expect(rect.columns == 1...3)
    }

    @Test func rectangleCorners() {
        #expect(rect.topLeft == cell(0, 1))
        #expect(rect.bottomRight == cell(2, 3))
    }

    @Test func containment() {
        #expect(rect.contains(cell(1, 2)))
        #expect(!rect.contains(cell(1, 0)))
        #expect(!rect.contains(cell(3, 2)))
    }

    @Test func cellsRunRowMajor() {
        #expect(rect.cells.count == 9)
        #expect(rect.cells.first == cell(0, 1))
        #expect(rect.cells.last == cell(2, 3))
    }

    @Test func aSingleCell() { #expect(NoteTableRect(cell(1, 1), cell(1, 1)).isSingleCell) }

    @Test func clampingTrimsToTheTable() { #expect(rect.clamped(rows: 2, columns: 3) == NoteTableRect(rows: 0...1, columns: 1...2)) }

    @Test func clampingARectangleOffTheTableDropsIt() { #expect(rect.clamped(rows: 2, columns: 1) == nil) }

    @Test func insertShiftsRowsBelow() {
        let insert = NoteTableChange.insertRows(at: 1, count: 2)
        #expect(insert.newRow(for: 0) == 0)
        #expect(insert.newRow(for: 1) == 3)
    }

    @Test func insertedRowsHaveNoSource() {
        let insert = NoteTableChange.insertRows(at: 1, count: 2)
        #expect(insert.oldRow(for: 1) == nil)
        #expect(insert.oldRow(for: 2) == nil)
        #expect(insert.oldRow(for: 3) == 1)
    }

    @Test func deleteDropsAndShifts() {
        let delete = NoteTableChange.deleteRows(at: 1, count: 1)
        #expect(delete.newRow(for: 1) == nil)
        #expect(delete.newRow(for: 2) == 1)
        #expect(delete.oldRow(for: 1) == 2)
    }

    @Test func moveDown() {
        let move = NoteTableChange.moveRow(from: 0, to: 2)
        #expect([0, 1, 2, 3].map { move.newRow(for: $0) } == [2, 0, 1, 3])
    }

    @Test(arguments: 0..<4) func aRowMoveRoundTrips(row: Int) {
        let move = NoteTableChange.moveRow(from: 0, to: 2)
        #expect(move.oldRow(for: move.newRow(for: row)!) == row)
    }

    @Test func moveLeft() {
        let move = NoteTableChange.moveColumn(from: 3, to: 1)
        #expect([3, 1, 2, 0].map { move.newColumn(for: $0) } == [1, 2, 3, 0])
    }

    @Test func cellsFollowTheirColumn() { #expect(NoteTableChange.moveColumn(from: 3, to: 1).newCell(for: cell(4, 3)) == cell(4, 1)) }

    @Test func deletedCellsVanish() { #expect(NoteTableChange.deleteColumns(at: 0, count: 1).newCell(for: cell(0, 0)) == nil) }

    @Test func rowOrColumn() {
        #expect(!NoteTableChange.moveColumn(from: 3, to: 1).isRowChange)
        #expect(NoteTableChange.moveRow(from: 0, to: 2).isRowChange)
    }

    func labelled() -> NoteTable {
        var table = NoteTable(rows: [["a", "b"], ["c", "d"]])
        table.alignments = [.center, nil]
        table.columnWidths = [120, nil]
        return table
    }

    func strings(_ table: NoteTable) -> [[String]] { table.rows.map { $0.map(\.string) } }

    @Test func insertRow() {
        var table = labelled()
        NoteTableTransforms.apply(.insertRows(at: 1, count: 1), to: &table)
        #expect(strings(table) == [["a", "b"], ["", ""], ["c", "d"]])
    }

    @Test func moveRow() {
        var table = labelled()
        NoteTableTransforms.apply(.insertRows(at: 1, count: 1), to: &table)
        NoteTableTransforms.apply(.moveRow(from: 0, to: 2), to: &table)
        #expect(strings(table) == [["", ""], ["c", "d"], ["a", "b"]])
    }

    @Test func deleteRow() {
        var table = labelled()
        NoteTableTransforms.apply(.deleteRows(at: 0, count: 1), to: &table)
        #expect(table.rowCount == 1)
        #expect(table.rows[0][0].string == "c")
    }

    @Test func insertColumnKeepsAlignmentsAndWidthsLinedUp() {
        var table = labelled()
        NoteTableTransforms.apply(.insertColumns(at: 1, count: 1), to: &table)
        #expect(table.rows[0].map(\.string) == ["a", "", "b"])
        #expect(table.alignments == [.center, nil, nil])
        #expect(table.columnWidths == [120, nil, nil])
    }

    @Test func moveColumnCarriesItsAlignmentAndWidth() {
        var table = labelled()
        NoteTableTransforms.apply(.moveColumn(from: 0, to: 1), to: &table)
        #expect(table.rows[0].map(\.string) == ["b", "a"])
        #expect(table.alignments == [nil, .center])
        #expect(table.columnWidths == [nil, 120])
    }

    @Test func duplicateColumn() {
        var table = labelled()
        table.duplicateColumn(at: 0)
        #expect(table.rows[1].map(\.string) == ["c", "c", "d"])
        #expect(table.columnWidths.count == 3)
        #expect(table.alignments[1] == .center)
    }

    @Test func deleteColumns() {
        var table = labelled()
        table.duplicateColumn(at: 0)
        NoteTableTransforms.apply(.deleteColumns(at: 0, count: 2), to: &table)
        #expect(table.rows[0].map(\.string) == ["b"])
        #expect(table.alignments == [nil])
    }

    @Test func duplicateRow() {
        var table = labelled()
        table.duplicateRow(at: 0)
        #expect(table.rowCount == 3)
        #expect(table.rows[1] == table.rows[0])
    }

    @Test func theLastRowAndColumnStay() {
        var single = NoteTable(rows: [["only"]])
        NoteTableTransforms.apply(.deleteRows(at: 0, count: 1), to: &single)
        NoteTableTransforms.apply(.deleteColumns(at: 0, count: 1), to: &single)
        #expect(single.rowCount == 1)
        #expect(single.columnCount == 1)
        #expect(single.rows[0][0].string == "only")
    }

    @Test func clearOnlyTheRectangle() {
        var table = labelled()
        NoteTableTransforms.clear(NoteTableRect(cell(0, 0), cell(1, 0)), in: &table)
        #expect(table.rows[0][0].isEmpty)
        #expect(table.rows[1][0].isEmpty)
        #expect(table.rows[0][1].string == "b")
        #expect(NoteTableTransforms.isEmpty(NoteTableRect(cell(0, 0), cell(1, 0)), of: table))
    }

    @Test func leftAlignmentIsTheDefault() {
        var table = labelled()
        table.setAlignment(.right, at: 1)
        table.setAlignment(nil, at: 0)
        #expect(table.alignments == [nil, .right])
    }

    func sessionWithTable() -> (NotePageSession, NoteBlockID) {
        var props = NoteBlockProps()
        props.table = labelled()
        let session = NotePageSession(page: NotePage(blocks: [NoteBlock(.table, props: props)]))
        return (session, session.page.blocks[0].id)
    }

    @Test func transformsRunThroughTheSession() {
        let (session, id) = sessionWithTable()
        session.updateTable(id) { NoteTableTransforms.apply(.insertRows(at: 0, count: 1), to: &$0) }
        #expect(session.page.blocks[0].props.table?.rowCount == 3)
    }

    @Test func andUndo() {
        let (session, id) = sessionWithTable()
        session.updateTable(id) { NoteTableTransforms.apply(.insertRows(at: 0, count: 1), to: &$0) }
        session.undo()
        #expect(session.page.blocks[0].props.table?.rowCount == 2)
    }

    let sizes: [Double] = [100, 50, 80]

    @Test(arguments: [(0.0, 0), (120, 1), (229, 2)] as [(Double, Int)])
    func indexAtPosition(position: Double, index: Int) { #expect(NoteTableMetrics.index(at: position, sizes: sizes) == index) }

    @Test func pastTheEndThereIsNoIndex() { #expect(NoteTableMetrics.index(at: 230, sizes: sizes) == nil) }

    @Test(arguments: [(-5.0, 0), (999, 2)] as [(Double, Int)])
    func clampedIndex(position: Double, index: Int) { #expect(NoteTableMetrics.clampedIndex(at: position, sizes: sizes) == index) }

    @Test(arguments: [(102.0, 0), (230, 2)] as [(Double, Int)])
    func nearABorder(position: Double, border: Int) { #expect(NoteTableMetrics.boundary(near: position, sizes: sizes, tolerance: 4) == border) }

    @Test(arguments: [125.0, 2]) func awayFromBordersAndTheOuterLeftEdgeThereIsNoBoundary(position: Double) {
        #expect(NoteTableMetrics.boundary(near: position, sizes: sizes, tolerance: 4) == nil)
    }

    @Test(arguments: [(10.0, 2, 0), (140, 0, 1), (20, 0, 0), (500, 0, 2)] as [(Double, Int, Int)])
    func dropIndex(position: Double, moving: Int, expected: Int) {
        #expect(NoteTableMetrics.dropIndex(for: position, sizes: sizes, moving: moving) == expected)
    }

    @Test func theVisibleRangeSpansPartialRows() { #expect(NoteTableMetrics.visibleRange(from: 90, to: 160, sizes: sizes) == 0...2) }

    @Test func theVisibleRangeIsExclusiveAtTheFarEdge() { #expect(NoteTableMetrics.visibleRange(from: 100, to: 150, sizes: sizes) == 1...1) }

    @Test func nothingIsVisiblePastTheEnd() { #expect(NoteTableMetrics.visibleRange(from: 300, to: 400, sizes: sizes) == nil) }
}
