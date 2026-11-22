import Foundation
import Testing
@testable import ParcCore

@MainActor struct PageStructureTableEditingTests: NoteFixtures {
    private func cellCaret(_ table: NoteBlockID, _ row: Int, _ column: Int, _ offset: Int = 0) -> NotePageSelection {
        .caret(NotePosition(table, offset, field: .cell(row: row, column: column)))
    }

    private func namedHeaderColumn(_ session: NotePageSession, _ id: NoteBlockID) {
        _ = session.setTableHeaderColumn(id, true)
    }

    @Test func insertingARowMovesTheCaretWithItsCell() {
        let session = makeSession([table([["a", "b"], ["c", "d"]])])
        let id = session.page.blocks[0].id
        session.setSelection(cellCaret(id, 1, 1, 1))
        session.insertTableRow(id, at: 0)
        expectOutline(session.page, "table |/a|b/c|d", "a row goes in above")
        #expect(session.selection == cellCaret(id, 2, 1, 1), "the caret follows its cell down")
    }

    @Test func insertingAColumnMovesTheCaretWithItsCell() {
        let session = makeSession([table([["a", "b"], ["c", "d"]])])
        let id = session.page.blocks[0].id
        session.setSelection(cellCaret(id, 1, 1, 1))
        session.insertTableRow(id, at: 0)
        session.insertTableColumn(id, at: 1)
        expectOutline(session.page, "table ||/a||b/c||d", "a column goes in at the index")
        #expect(session.selection == cellCaret(id, 2, 2, 1), "the caret follows its cell right")
    }

    @Test func movingARowKeepsTheCaretInTheMovedRow() {
        let session = makeSession([table([["a", "b"], ["c", "d"]])])
        let id = session.page.blocks[0].id
        session.setSelection(cellCaret(id, 1, 1, 1))
        session.insertTableRow(id, at: 0)
        session.insertTableColumn(id, at: 1)
        session.moveTableRow(id, from: 2, to: 0)
        expectOutline(session.page, "table c||d/||/a||b", "rows move")
        #expect(session.selection == cellCaret(id, 0, 2, 1), "the caret rides with the moved row")
    }

    @Test func movingAColumnKeepsTheCaretInTheMovedColumn() {
        let session = makeSession([table([["a", "b"], ["c", "d"]])])
        let id = session.page.blocks[0].id
        session.setSelection(cellCaret(id, 1, 1, 1))
        session.insertTableRow(id, at: 0)
        session.insertTableColumn(id, at: 1)
        session.moveTableRow(id, from: 2, to: 0)
        session.moveTableColumn(id, from: 2, to: 0)
        expectOutline(session.page, "table d|c|/||/b|a|", "columns move")
        #expect(session.selection == cellCaret(id, 0, 0, 1), "the caret rides with the moved column")
    }

    @Test func deletingTheCaretRowMovesItToTheReplacementRow() {
        let session = makeSession([table([["a", "b"], ["c", "d"]])])
        let id = session.page.blocks[0].id
        session.setSelection(cellCaret(id, 1, 1, 1))
        session.insertTableRow(id, at: 0)
        session.insertTableColumn(id, at: 1)
        session.moveTableRow(id, from: 2, to: 0)
        session.moveTableColumn(id, from: 2, to: 0)
        session.deleteTableRow(id, at: 0)
        expectOutline(session.page, "table ||/b|a|", "rows delete")
        #expect(session.selection == cellCaret(id, 0, 0, 0), "a caret in a deleted row moves to the row that took its place")
    }

    @Test func duplicatingARowAndColumnCopiesTheirCells() {
        let session = makeSession([table([["a", "b"], ["c", "d"]])])
        let id = session.page.blocks[0].id
        session.setSelection(cellCaret(id, 1, 1, 1))
        session.insertTableRow(id, at: 0)
        session.insertTableColumn(id, at: 1)
        session.moveTableRow(id, from: 2, to: 0)
        session.moveTableColumn(id, from: 2, to: 0)
        session.deleteTableRow(id, at: 0)
        session.duplicateTableRow(id, at: 1)
        session.duplicateTableColumn(id, at: 0)
        expectOutline(session.page, "table |||/b|b|a|/b|b|a|", "rows and columns duplicate")
    }

    @Test func deletingTheLastColumnIsRefused() {
        let session = makeSession([table([["a", "b"], ["c", "d"]])])
        let id = session.page.blocks[0].id
        session.setSelection(cellCaret(id, 1, 1, 1))
        session.insertTableRow(id, at: 0)
        session.insertTableColumn(id, at: 1)
        session.moveTableRow(id, from: 2, to: 0)
        session.moveTableColumn(id, from: 2, to: 0)
        session.deleteTableRow(id, at: 0)
        session.duplicateTableRow(id, at: 1)
        session.duplicateTableColumn(id, at: 0)
        session.deleteTableColumn(id, at: 3)
        session.deleteTableColumn(id, at: 2)
        session.deleteTableColumn(id, at: 1)
        #expect(!session.deleteTableColumn(id, at: 0), "the last column can't be deleted")
    }

    @Test func deletingTheLastRowLeavesOneEmptyCell() {
        let session = makeSession([table([["a", "b"], ["c", "d"]])])
        let id = session.page.blocks[0].id
        session.setSelection(cellCaret(id, 1, 1, 1))
        session.insertTableRow(id, at: 0)
        session.insertTableColumn(id, at: 1)
        session.moveTableRow(id, from: 2, to: 0)
        session.moveTableColumn(id, from: 2, to: 0)
        session.deleteTableRow(id, at: 0)
        session.duplicateTableRow(id, at: 1)
        session.duplicateTableColumn(id, at: 0)
        session.deleteTableColumn(id, at: 3)
        session.deleteTableColumn(id, at: 2)
        session.deleteTableColumn(id, at: 1)
        session.deleteTableRow(id, at: 2)
        session.deleteTableRow(id, at: 1)
        #expect(!session.deleteTableRow(id, at: 0), "the last row can't be deleted")
        expectOutline(session.page, "table", "one empty cell remains")
    }

    @Test func movingARowOutOfBoundsIsRefused() {
        let session = makeSession([table([["a", "b"], ["c", "d"]])])
        let id = session.page.blocks[0].id
        #expect(!session.moveTableRow(id, from: 0, to: 3), "out-of-range moves are refused")
    }

    @Test func aCellSelectionShrinksWithTheTable() {
        let cells = makeSession([table([["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"]])])
        let grid = cells.page.blocks[0].id
        cells.setSelection(.cells(table: grid, anchor: NoteTableCell(row: 0, column: 0), head: NoteTableCell(row: 2, column: 2)))
        cells.deleteTableRow(grid, at: 2)
        #expect(cells.selection == .cells(table: grid, anchor: NoteTableCell(row: 0, column: 0), head: NoteTableCell(row: 1, column: 2)), "a cell selection shrinks with the table")
    }

    @Test func deletingSelectedCellsEmptiesTheirContents() {
        let cells = makeSession([table([["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"]])])
        let grid = cells.page.blocks[0].id
        cells.setSelection(.cells(table: grid, anchor: NoteTableCell(row: 0, column: 0), head: NoteTableCell(row: 2, column: 2)))
        cells.deleteTableRow(grid, at: 2)
        cells.deleteSelection()
        expectOutline(cells.page, "table ||/||", "clearing selected cells empties them")
    }

    @Test func aTableHeaderColumnCanBeEnabled() {
        let clock = NoteTestClock()
        let session = makeSession([table([["a", "b"], ["c", "d"]])], clock: clock)
        let id = session.page.blocks[0].id
        #expect(session.setTableHeaderColumn(id, true), "header column turns on")
    }

    @Test func enablingTheHeaderColumnTwiceIsANoOp() {
        let clock = NoteTestClock()
        let session = makeSession([table([["a", "b"], ["c", "d"]])], clock: clock)
        let id = session.page.blocks[0].id
        namedHeaderColumn(session, id)
        #expect(!session.setTableHeaderColumn(id, true), "turning it on twice is a no-op")
    }

    @Test func tableHeaderFlagsCanBeSetIndependently() {
        let clock = NoteTestClock()
        let session = makeSession([table([["a", "b"], ["c", "d"]])], clock: clock)
        let id = session.page.blocks[0].id
        namedHeaderColumn(session, id)
        session.setTableHeaderRow(id, false)
        let grid = session.page.blocks[0].props.table!
        #expect(grid.headerColumn && !grid.headerRow, "header flags stick")
    }

    @Test func aColumnWidthDragUpdatesWidthInOneUndoStep() {
        let clock = NoteTestClock()
        let session = makeSession([table([["a", "b"], ["c", "d"]])], clock: clock)
        let id = session.page.blocks[0].id
        let before = session.undoDepth
        for width in stride(from: 100.0, through: 180.0, by: 20.0) {
            session.setTableColumnWidth(id, column: 1, width: width)
            clock.advance(0.05)
        }
        #expect(session.page.blocks[0].props.table?.columnWidths == [nil, 180], "the width lands where the drag ended")
        #expect(session.undoDepth == before + 1, "a width drag is one step")
    }

    @Test func tableColumnWidthsHaveAMinimum() {
        let clock = NoteTestClock()
        let session = makeSession([table([["a", "b"], ["c", "d"]])], clock: clock)
        let id = session.page.blocks[0].id
        session.setTableColumnWidth(id, column: 0, width: 2)
        #expect(session.page.blocks[0].props.table?.columnWidths[0] == NoteTable.minimumColumnWidth, "widths respect a minimum")
    }

    @Test func aMovedColumnKeepsItsWidthAndAlignment() {
        let clock = NoteTestClock()
        let session = makeSession([table([["a", "b"], ["c", "d"]])], clock: clock)
        let id = session.page.blocks[0].id
        for width in stride(from: 100.0, through: 180.0, by: 20.0) {
            session.setTableColumnWidth(id, column: 1, width: width)
            clock.advance(0.05)
        }
        session.setTableColumnWidth(id, column: 0, width: 2)
        #expect(session.page.blocks[0].props.table?.columnWidths[0] == NoteTable.minimumColumnWidth, "widths respect a minimum")
        session.setTableColumnAlignment(id, column: 0, .right)
        session.moveTableColumn(id, from: 0, to: 1)
        let moved = session.page.blocks[0].props.table!
        #expect(moved.alignments == [nil, .right] && moved.columnWidths == [180, NoteTable.minimumColumnWidth], "alignment and width travel with their column")
    }

    @Test func aligningAMissingColumnIsRefused() {
        let clock = NoteTestClock()
        let session = makeSession([table([["a", "b"], ["c", "d"]])], clock: clock)
        let id = session.page.blocks[0].id
        #expect(!session.setTableColumnAlignment(id, column: 9, .left), "missing columns are refused")
    }

    @Test func insertingARowAcceptsAnUndoNameAndCaret() {
        let named = makeSession([table([["a", "b"], ["c", "d"]])])
        let grid2 = named.page.blocks[0].id
        let landing = cellCaret(grid2, 2, 1)
        named.insertTableRow(grid2, at: 2, name: "Add Row", select: landing)
        #expect(named.undoActionName == "Add Row", "callers can name a table step")
        #expect(named.selection == landing, "and say where the caret lands")
    }

    @Test func tableEditsPublishTheAppropriateKindsOfChange() {
        let named = makeSession([table([["a", "b"], ["c", "d"]])])
        let grid2 = named.page.blocks[0].id
        var changes: [NotePageChange.Kind] = []
        let subscription = named.changes.sink { changes.append($0.kind) }
        named.setTableHeaderRow(grid2, false)
        named.setTableColumnAlignment(grid2, column: 0, .center)
        named.insertTableColumn(grid2, at: 0)
        #expect(changes == [.text, .text, .structure], "flag and alignment tweaks are light, new columns are structural")
        subscription.cancel()
    }

    @Test func tableColumnWidthsCanBeSetTogether() {
        let named = makeSession([table([["a", "b"], ["c", "d"]])])
        let grid2 = named.page.blocks[0].id
        named.insertTableColumn(grid2, at: 0)
        #expect(named.setTableColumnWidths(grid2, [120, nil, 240], name: "Resize Column"), "widths can be set all at once")
        #expect(named.page.blocks[0].props.table?.columnWidths == [120, nil, 240], "every column takes its width")
    }

    @Test func settingTheSameColumnWidthsIsANoOp() {
        let named = makeSession([table([["a", "b"], ["c", "d"]])])
        let grid2 = named.page.blocks[0].id
        named.insertTableColumn(grid2, at: 0)
        _ = named.setTableColumnWidths(grid2, [120, nil, 240], name: "Resize Column")
        #expect(!named.setTableColumnWidths(grid2, [120, nil, 240]), "setting the same widths again changes nothing")
    }

    @Test func clearingColumnWidthsFitsTheTableToThePage() {
        let named = makeSession([table([["a", "b"], ["c", "d"]])])
        let grid2 = named.page.blocks[0].id
        named.insertTableColumn(grid2, at: 0)
        _ = named.setTableColumnWidths(grid2, [120, nil, 240], name: "Resize Column")
        #expect(named.setTableColumnWidths(grid2, [], name: "Fit to Width"), "an empty list fits the table to the page")
        #expect(named.page.blocks[0].props.table?.columnWidths == [nil, nil, nil], "all widths clear")
        #expect(named.undoActionName == "Fit to Width", "with the caller's name")
    }
}
