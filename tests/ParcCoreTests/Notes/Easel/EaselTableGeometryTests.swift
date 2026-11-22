import Foundation
import Testing
@testable import ParcCore

struct EaselTableGeometryTests {
    @Test
    func columnsStopAtTheMinimumWidth() {
        var table = EaselTable.blank(columns: 2, rows: 2, columnWidth: 100, rowHeight: 40)
        #expect(table.setWidth(10, column: 0) && table.columnWidths[0] == EaselTable.minimumColumnWidth, "Columns stop at the minimum width")
    }

    @Test
    func rowsStopAtTheirContentHeight() {
        var table = EaselTable.blank(columns: 2, rows: 2, columnWidth: 100, rowHeight: 40)
        #expect(table.setHeight(10, row: 0, minimum: 50) && table.rowHeights[0] == 50, "Rows stop at their content")
    }

    @Test
    func invalidColumnWidthsAreRefused() {
        var table = EaselTable.blank(columns: 2, rows: 2, columnWidth: 100, rowHeight: 40)
        #expect(!table.setWidth(.nan, column: 0) && !table.setWidth(100, column: 9), "Bad widths are refused")
    }

    @Test
    func scalingColumnsRespectsProportionAndMinimumWidth() {
        var table = EaselTable.blank(columns: 2, rows: 2, columnWidth: 100, rowHeight: 40)
        table.columnWidths = [100, 300]
        table.scaleColumns(toWidth: 200)
        #expect(table.columnWidths == [50, 150], "Resizing scales columns proportionally")
        table.scaleColumns(toWidth: 20)
        #expect(table.columnWidths.allSatisfy { $0 >= EaselTable.minimumColumnWidth }, "Scaling keeps the minimum width")
    }

    @Test
    func scalingRowsRespectsTheirContentHeight() {
        var table = EaselTable.blank(columns: 2, rows: 2, columnWidth: 100, rowHeight: 40)
        table.rowHeights = [40, 40]
        table.scaleRows(toHeight: 40, minimums: [36, 0])
        #expect(table.rowHeights[0] == 36 && table.rowHeights[1] == EaselTable.minimumRowHeight, "Rows shrink only to their content")
    }

    @Test
    func fittingRowsGrowsThemToTheirText() {
        var table = EaselTable.blank(columns: 2, rows: 2, columnWidth: 100, rowHeight: 40)
        table.rowHeights = [40, 40]
        table.scaleRows(toHeight: 40, minimums: [36, 0])
        table.fitRows(minimums: [90, 10])
        #expect(table.rowHeights[0] == 90 && table.rowHeights[1] == EaselTable.minimumRowHeight, "Rows grow with their text")
    }

    @Test
    func aNewGridMatchesTheObjectFrame() {
        let item = EaselTableGeometry.item(columns: 2, rows: 2, frame: EaselRect(x: 5, y: 6, width: 200, height: 80), zIndex: 3)
        #expect(item.kind == .table && item.frame == EaselRect(x: 5, y: 6, width: 200, height: 80) && item.table?.columnWidths == [100, 100], "New table items match their frame")
    }

    @Test
    func fittingAResizedTableScalesColumnsAndRespectsMinimumHeight() {
        var item = EaselTableGeometry.item(columns: 2, rows: 2, frame: EaselRect(x: 5, y: 6, width: 200, height: 80), zIndex: 3)
        item.frame.width = 400
        item.frame.height = 20
        let fitted = EaselTableGeometry.fitted(item)
        #expect(fitted.table?.columnWidths == [200, 200] && fitted.frame.width == 400, "A wider frame scales the columns")
        #expect(fitted.frame.height == 2 * EaselTable.minimumRowHeight && fitted.table?.height == fitted.frame.height, "Shrinking stops at the minimum height")
    }

    @Test
    func clickingMakesACenteredThreeByThreeTable() {
        let click = EaselTableGeometry.placement(from: EaselPoint(x: 300, y: 300), to: nil)
        #expect(click.columns == 3 && click.rows == 3, "A click makes a 3 by 3 table")
        #expect(abs(click.frame.x + click.frame.width / 2 - 300) < 0.001 && abs(click.frame.y + click.frame.height / 2 - 300) < 0.001, "Clicked tables centre on the click")
    }

    @Test
    func draggingChoosesTableDimensionsAndDirection() {
        let drag = EaselTableGeometry.placement(from: EaselPoint(x: 100, y: 100), to: EaselPoint(x: 100 + EaselTable.defaultColumnWidth * 3.5, y: 100 + EaselTable.defaultRowHeight * 1.5))
        #expect(drag.columns == 4 && drag.rows == 2 && drag.frame.x == 100 && drag.frame.y == 100, "Dragging picks columns and rows")
        let back = EaselTableGeometry.placement(from: EaselPoint(x: 500, y: 500), to: EaselPoint(x: 500 - EaselTable.defaultColumnWidth * 1.2, y: 480))
        #expect(back.columns == 2 && back.rows == 1 && back.frame.x + back.frame.width == 500, "Dragging up and left grows that way")
    }

    @Test
    func aLongDragCapsTableDimensions() {
        let far = EaselTableGeometry.placement(from: EaselPoint(x: 0, y: 0), to: EaselPoint(x: 100_000, y: 100_000))
        #expect(far.columns == 12 && far.rows == 24, "Dragged tables stay a sensible size")
    }

    @Test
    func cellEdgesFollowTheFrameAndScale() {
        var table = EaselTableTestsSupport.filled([["a", "b", "c"], ["d", "e", "f"]])
        table.columnWidths = [100, 50, 100]
        table.rowHeights = [40, 60]
        let grid = EaselTableLayout(table: table, frame: EaselRect(x: 10, y: 20, width: 250, height: 100))
        #expect(grid.columnEdges == [10, 110, 160, 260] && grid.rowEdges == [20, 60, 120], "Edges add up from the frame")
        let scaled = EaselTableLayout(table: table, frame: EaselRect(x: 0, y: 0, width: 500, height: 200))
        #expect(scaled.columnEdges == [0, 200, 300, 500], "A stretched frame stretches the grid")
    }

    @Test
    func cellHitTestingResolvesThePointOrClampsAnOutsideDrag() {
        var table = EaselTableTestsSupport.filled([["a", "b", "c"], ["d", "e", "f"]])
        table.columnWidths = [100, 50, 100]
        table.rowHeights = [40, 60]
        let grid = EaselTableLayout(table: table, frame: EaselRect(x: 10, y: 20, width: 250, height: 100))
        #expect(grid.cell(at: EaselPoint(x: 120, y: 70)) == EaselTableTestsSupport.cell(1, 1) && grid.cell(at: EaselPoint(x: 9, y: 70)) == nil, "Points find their cell")
        #expect(grid.clampedCell(at: EaselPoint(x: 900, y: -5)) == EaselTableTestsSupport.cell(0, 2), "Drags past the edge clamp to the last cell")
    }

    @Test
    func cellRectanglesFollowTheGrid() {
        var table = EaselTableTestsSupport.filled([["a", "b", "c"], ["d", "e", "f"]])
        table.columnWidths = [100, 50, 100]
        table.rowHeights = [40, 60]
        let grid = EaselTableLayout(table: table, frame: EaselRect(x: 10, y: 20, width: 250, height: 100))
        #expect(grid.rect(of: EaselTableTestsSupport.cell(1, 2), in: table) == EaselRect(x: 160, y: 60, width: 100, height: 60), "Cells have rectangles")
    }

    @Test
    func borderHitTestingFindsTheNearestGridEdge() {
        var table = EaselTableTestsSupport.filled([["a", "b", "c"], ["d", "e", "f"]])
        table.columnWidths = [100, 50, 100]
        table.rowHeights = [40, 60]
        let grid = EaselTableLayout(table: table, frame: EaselRect(x: 10, y: 20, width: 250, height: 100))
        #expect(grid.columnBorder(near: EaselPoint(x: 111, y: 30), tolerance: 3, in: table) == 0, "Borders are found near the pointer")
        #expect(grid.rowBorder(near: EaselPoint(x: 50, y: 58), tolerance: 3, in: table) == 0 && grid.rowBorder(near: EaselPoint(x: 50, y: 90), tolerance: 3, in: table) == nil, "Rows borders too")
    }

    @Test
    func gridLinesIncludeOneSegmentPerInternalBorder() {
        var table = EaselTableTestsSupport.filled([["a", "b", "c"], ["d", "e", "f"]])
        table.columnWidths = [100, 50, 100]
        table.rowHeights = [40, 60]
        let grid = EaselTableLayout(table: table, frame: EaselRect(x: 10, y: 20, width: 250, height: 100))
        #expect(grid.borderSegments(in: table).count == 3, "Two column borders and one row border")
    }

    @Test
    func mergesHideTheirInnerBorderAndSpanColumns() {
        var table = EaselTableTestsSupport.filled([["a", "b", "c"], ["d", "e", "f"]])
        table.columnWidths = [100, 50, 100]
        table.rowHeights = [40, 60]
        table.merges = [EaselTableMerge(row: 0, column: 0, rowSpan: 1, columnSpan: 2)]
        table.cells[0][1] = EaselTableCell()
        let merged = EaselTableLayout(table: table, frame: EaselRect(x: 10, y: 20, width: 250, height: 100))
        #expect(merged.columnBorder(near: EaselPoint(x: 110, y: 30), tolerance: 3, in: table) == nil, "Borders inside a merge can't be grabbed")
        #expect(merged.columnBorder(near: EaselPoint(x: 110, y: 90), tolerance: 3, in: table) == 0, "The same border is grabbable below the merge")
        let segments = merged.borderSegments(in: table)
        #expect(segments.contains { $0.start == EaselPoint(x: 110, y: 60) && $0.end == EaselPoint(x: 110, y: 120) }, "Merged cells hide their inner border")
        #expect(merged.rect(of: EaselTableTestsSupport.cell(0, 1), in: table) == EaselRect(x: 10, y: 20, width: 150, height: 40), "Merged cells span their columns")
    }

    @Test
    func dropIndicesLandBetweenColumns() {
        var table = EaselTableTestsSupport.filled([["a", "b", "c"], ["d", "e", "f"]])
        table.columnWidths = [100, 50, 100]
        table.rowHeights = [40, 60]
        let grid = EaselTableLayout(table: table, frame: EaselRect(x: 10, y: 20, width: 250, height: 100))
        #expect(grid.dropIndex(for: 255, edges: grid.columnEdges, moving: 0...0) == 2 && grid.dropIndex(for: 15, edges: grid.columnEdges, moving: 2...2) == 0, "Drops land between columns")
    }

    @Test
    func cellEdgesUseHalfOpenIntervals() {
        var table = EaselTableTestsSupport.filled([["a", "b", "c"], ["d", "e", "f"]])
        table.columnWidths = [100, 50, 100]
        table.rowHeights = [40, 60]
        let grid = EaselTableLayout(table: table, frame: EaselRect(x: 10, y: 20, width: 250, height: 100))
        #expect(EaselTableLayout.index(of: 260, in: grid.columnEdges) == nil && EaselTableLayout.index(of: 259.9, in: grid.columnEdges) == 2, "Edges are half open")
    }
}
