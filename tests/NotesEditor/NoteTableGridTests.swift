import Foundation

@main @MainActor
struct NoteTableGridTests {
    static func expect(_ value: Bool, _ message: String) {
        if !value { failTest(message) }
    }

    static func main() {
        widths()
        navigation()
        rectangles()
        changes()
        transforms()
        hitTesting()
        print("NoteTableGridTests passed")
    }

    static func cell(_ row: Int, _ column: Int) -> NoteTableCell { NoteTableCell(row: row, column: column) }

    static func widths() {
        expect(NoteTableMetrics.resolvedWidths([nil, nil, nil], available: 720) == [240, 240, 240], "unset widths share the space evenly")
        expect(NoteTableMetrics.resolvedWidths([200, nil, nil], available: 720) == [200, 260, 260], "unset widths share what fixed ones leave")
        expect(NoteTableMetrics.resolvedWidths([nil, nil, nil, nil, nil, nil, nil, nil], available: 720).allSatisfy { $0 == NoteTableMetrics.minimumSharedWidth },
               "crowded tables keep a readable shared width and scroll instead")
        expect(NoteTableMetrics.resolvedWidths([10, 300], available: 720) == [NoteTableMetrics.minimumColumnWidth, 300], "fixed widths respect the minimum")
        expect(NoteTableMetrics.resolvedWidths([120, 130], available: 720) == [120, 130], "all-fixed tables keep their own width")
        expect(NoteTableMetrics.resolvedWidths([], available: 720).isEmpty, "no columns, no widths")
        let thirds = NoteTableMetrics.resolvedWidths([nil, nil, nil], available: 700)
        expect(thirds == [233, 233, 234] && thirds.reduce(0, +) == 700, "shared columns fill the width exactly, the last takes the spare points")
        expect(NoteTableMetrics.resolvedWidths([nil, 120, nil], available: 700.5).reduce(0, +) == 700.5, "even a fractional width fills to the edge")
        expect(NoteTableMetrics.resized([100, 100], column: 0, by: 37.4) == [137, 100], "resizing moves only the dragged column")
        expect(NoteTableMetrics.resized([100, 100], column: 1, by: -500) == [100, NoteTableMetrics.minimumColumnWidth], "resizing stops at the minimum")
        expect(NoteTableMetrics.edges([10, 20, 30]) == [0, 10, 30, 60], "edges accumulate")
        var table = NoteTable.empty(rows: 2, columns: 3)
        NoteTableTransforms.setWidths([150.4, 20, nil], in: &table)
        expect(table.columnWidths == [150, NoteTableMetrics.minimumColumnWidth, nil], "stored widths round and clamp")
    }

    static func navigation() {
        expect(NoteTableNavigation.tab(from: cell(0, 0), rows: 2, columns: 3, backward: false) == .cell(cell(0, 1)), "tab moves right")
        expect(NoteTableNavigation.tab(from: cell(0, 2), rows: 2, columns: 3, backward: false) == .cell(cell(1, 0)), "tab wraps to the next row")
        expect(NoteTableNavigation.tab(from: cell(1, 2), rows: 2, columns: 3, backward: false) == .appendRow, "tab in the last cell adds a row")
        expect(NoteTableNavigation.tab(from: cell(1, 0), rows: 2, columns: 3, backward: true) == .cell(cell(0, 2)), "shift-tab wraps back")
        expect(NoteTableNavigation.tab(from: cell(0, 0), rows: 2, columns: 3, backward: true) == .stay, "shift-tab stops at the first cell")
        expect(NoteTableNavigation.step(from: cell(0, 1), .up, rows: 2, columns: 3) == .exitBefore, "up from the top row leaves the table")
        expect(NoteTableNavigation.step(from: cell(1, 1), .up, rows: 2, columns: 3) == .cell(cell(0, 1)), "up keeps the column")
        expect(NoteTableNavigation.step(from: cell(1, 1), .down, rows: 2, columns: 3) == .exitAfter, "down from the last row leaves the table")
        expect(NoteTableNavigation.step(from: cell(1, 0), .left, rows: 2, columns: 3) == .cell(cell(0, 2)), "left wraps to the previous row")
        expect(NoteTableNavigation.step(from: cell(0, 0), .left, rows: 2, columns: 3) == .exitBefore, "left from the first cell leaves")
        expect(NoteTableNavigation.step(from: cell(0, 2), .right, rows: 2, columns: 3) == .cell(cell(1, 0)), "right wraps to the next row")
        expect(NoteTableNavigation.step(from: cell(1, 2), .right, rows: 2, columns: 3) == .exitAfter, "right from the last cell leaves")
        expect(NoteTableNavigation.returnKey(from: cell(0, 2), rows: 2) == .cell(cell(1, 2)), "return moves down a cell")
        expect(NoteTableNavigation.returnKey(from: cell(1, 2), rows: 2) == .exitAfter, "return on the last row leaves")
        expect(NoteTableNavigation.moved(cell(0, 0), .up, rows: 2, columns: 3) == cell(0, 0), "extending clamps at the top")
        expect(NoteTableNavigation.moved(cell(1, 1), .right, rows: 2, columns: 3) == cell(1, 2), "extending moves the head")
        expect(NoteTableNavigation.moved(cell(1, 2), .right, rows: 2, columns: 3) == cell(1, 2), "extending clamps at the edge")
    }

    static func rectangles() {
        let rect = NoteTableRect(cell(2, 3), cell(0, 1))
        expect(rect.rows == 0...2 && rect.columns == 1...3, "anchor and head normalize into a rectangle")
        expect(rect.topLeft == cell(0, 1) && rect.bottomRight == cell(2, 3), "corners")
        expect(rect.contains(cell(1, 2)) && !rect.contains(cell(1, 0)) && !rect.contains(cell(3, 2)), "containment")
        expect(rect.cells.count == 9 && rect.cells.first == cell(0, 1) && rect.cells.last == cell(2, 3), "cells run row-major")
        expect(NoteTableRect(cell(1, 1), cell(1, 1)).isSingleCell, "single cell")
        expect(rect.clamped(rows: 2, columns: 3) == NoteTableRect(rows: 0...1, columns: 1...2), "clamping trims to the table")
        expect(rect.clamped(rows: 2, columns: 1) == nil, "clamping a rectangle off the table drops it")
    }

    static func changes() {
        let insert = NoteTableChange.insertRows(at: 1, count: 2)
        expect(insert.newRow(for: 0) == 0 && insert.newRow(for: 1) == 3, "insert shifts rows below")
        expect(insert.oldRow(for: 1) == nil && insert.oldRow(for: 2) == nil && insert.oldRow(for: 3) == 1, "inserted rows have no source")
        let delete = NoteTableChange.deleteRows(at: 1, count: 1)
        expect(delete.newRow(for: 1) == nil && delete.newRow(for: 2) == 1, "delete drops and shifts")
        expect(delete.oldRow(for: 1) == 2, "delete maps back")
        let move = NoteTableChange.moveRow(from: 0, to: 2)
        expect(move.newRow(for: 0) == 2 && move.newRow(for: 1) == 0 && move.newRow(for: 2) == 1 && move.newRow(for: 3) == 3, "move down")
        for row in 0..<4 { expect(move.oldRow(for: move.newRow(for: row)!) == row, "move round trips") }
        let up = NoteTableChange.moveColumn(from: 3, to: 1)
        expect(up.newColumn(for: 3) == 1 && up.newColumn(for: 1) == 2 && up.newColumn(for: 2) == 3 && up.newColumn(for: 0) == 0, "move left")
        expect(up.newCell(for: cell(4, 3)) == cell(4, 1), "cells follow their column")
        expect(NoteTableChange.deleteColumns(at: 0, count: 1).newCell(for: cell(0, 0)) == nil, "deleted cells vanish")
        expect(!up.isRowChange && move.isRowChange, "row or column")
    }

    static func transforms() {
        var table = NoteTable(rows: [["a", "b"], ["c", "d"]])
        table.alignments = [.center, nil]
        table.columnWidths = [120, nil]
        NoteTableTransforms.apply(.insertRows(at: 1, count: 1), to: &table)
        expect(table.rows.map { $0.map(\.string) } == [["a", "b"], ["", ""], ["c", "d"]], "insert row")
        NoteTableTransforms.apply(.moveRow(from: 0, to: 2), to: &table)
        expect(table.rows.map { $0.map(\.string) } == [["", ""], ["c", "d"], ["a", "b"]], "move row")
        NoteTableTransforms.apply(.deleteRows(at: 0, count: 1), to: &table)
        expect(table.rowCount == 2 && table.rows[0][0].string == "c", "delete row")
        NoteTableTransforms.apply(.insertColumns(at: 1, count: 1), to: &table)
        expect(table.rows[0].map(\.string) == ["c", "", "d"] && table.alignments == [.center, nil, nil]
               && table.columnWidths == [120, nil, nil], "insert column keeps alignments and widths lined up")
        NoteTableTransforms.apply(.moveColumn(from: 0, to: 2), to: &table)
        expect(table.rows[0].map(\.string) == ["", "d", "c"] && table.alignments == [nil, nil, .center]
               && table.columnWidths == [nil, nil, 120], "move column carries its alignment and width")
        table.duplicateColumn(at: 2)
        expect(table.rows[1].map(\.string) == ["", "b", "a", "a"] && table.columnWidths.count == 4 && table.alignments[3] == .center, "duplicate column")
        NoteTableTransforms.apply(.deleteColumns(at: 0, count: 2), to: &table)
        expect(table.rows[0].map(\.string) == ["c", "c"] && table.alignments == [.center, .center], "delete columns")
        table.duplicateRow(at: 0)
        expect(table.rowCount == 3 && table.rows[1] == table.rows[0], "duplicate row")
        var single = NoteTable(rows: [["only"]])
        NoteTableTransforms.apply(.deleteRows(at: 0, count: 1), to: &single)
        NoteTableTransforms.apply(.deleteColumns(at: 0, count: 1), to: &single)
        expect(single.rowCount == 1 && single.columnCount == 1 && single.rows[0][0].string == "only", "the last row and column stay")
        NoteTableTransforms.clear(NoteTableRect(cell(0, 0), cell(1, 0)), in: &table)
        expect(table.rows[0][0].isEmpty && table.rows[1][0].isEmpty && table.rows[2][0].string == "a" && table.rows[0][1].string == "c", "clear only the rectangle")
        expect(NoteTableTransforms.isEmpty(NoteTableRect(cell(0, 0), cell(1, 0)), of: table), "cleared rectangle is empty")
        table.setAlignment(.right, at: 1)
        table.setAlignment(nil, at: 0)
        expect(table.alignments == [nil, .right], "left alignment is the default")
        let session = NotePageSession(page: NotePage(blocks: [NoteBlock(.table, props: { var props = NoteBlockProps(); props.table = table; return props }())]))
        let id = session.page.blocks[0].id
        session.updateTable(id) { NoteTableTransforms.apply(.insertRows(at: 0, count: 1), to: &$0) }
        expect(session.page.blocks[0].props.table?.rowCount == 4, "transforms run through the session")
        session.undo()
        expect(session.page.blocks[0].props.table?.rowCount == 3, "and undo")
    }

    static func hitTesting() {
        let sizes: [Double] = [100, 50, 80]
        expect(NoteTableMetrics.index(at: 0, sizes: sizes) == 0 && NoteTableMetrics.index(at: 120, sizes: sizes) == 1
               && NoteTableMetrics.index(at: 229, sizes: sizes) == 2 && NoteTableMetrics.index(at: 230, sizes: sizes) == nil, "index at position")
        expect(NoteTableMetrics.clampedIndex(at: -5, sizes: sizes) == 0 && NoteTableMetrics.clampedIndex(at: 999, sizes: sizes) == 2, "clamped index")
        expect(NoteTableMetrics.boundary(near: 102, sizes: sizes, tolerance: 4) == 0, "near the first border")
        expect(NoteTableMetrics.boundary(near: 230, sizes: sizes, tolerance: 4) == 2, "near the last border")
        expect(NoteTableMetrics.boundary(near: 125, sizes: sizes, tolerance: 4) == nil, "away from borders")
        expect(NoteTableMetrics.boundary(near: 2, sizes: sizes, tolerance: 4) == nil, "the outer left edge is not a resize border")
        expect(NoteTableMetrics.dropIndex(for: 10, sizes: sizes, moving: 2) == 0, "drop at the start")
        expect(NoteTableMetrics.dropIndex(for: 140, sizes: sizes, moving: 0) == 1, "drop past the next row's middle")
        expect(NoteTableMetrics.dropIndex(for: 20, sizes: sizes, moving: 0) == 0, "drop near home stays home")
        expect(NoteTableMetrics.dropIndex(for: 500, sizes: sizes, moving: 0) == 2, "drop at the end")
        expect(NoteTableMetrics.visibleRange(from: 90, to: 160, sizes: sizes) == 0...2, "visible range spans partial rows")
        expect(NoteTableMetrics.visibleRange(from: 100, to: 150, sizes: sizes) == 1...1, "visible range is exclusive at the far edge")
        expect(NoteTableMetrics.visibleRange(from: 300, to: 400, sizes: sizes) == nil, "nothing visible past the end")
    }
}
