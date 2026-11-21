import Foundation
import Testing
@testable import ParcCore

struct EaselTableTests {
    func cell(_ row: Int, _ column: Int) -> EaselTableCoordinate { EaselTableCoordinate(row: row, column: column) }

    func filled(_ rows: [[String]]) -> EaselTable {
        var table = EaselTable.blank(columns: rows.first?.count ?? 1, rows: rows.count)
        for (r, row) in rows.enumerated() { for (c, text) in row.enumerated() { table.cells[r][c].text = text } }
        return table
    }

    func rejects(_ table: EaselTable, _ message: String) {
        do { try table.validate(); Issue.record(Comment(rawValue: message)) } catch {}
    }

    @Test func shapeAndLimits() {
        let table = EaselTable.blank(columns: 3, rows: 3)
        #expect(table.rowCount == 3 && table.columnCount == 3 && table.cells.allSatisfy { $0.count == 3 }, "A new table is 3 by 3")
        #expect(table.width == 3 * EaselTable.defaultColumnWidth && table.height == 3 * EaselTable.defaultRowHeight, "Sizes add up")
        let huge = EaselTable.blank(columns: 500, rows: 500)
        #expect(huge.columnCount == 100 && huge.rowCount == 100 && huge.rowCount * huge.columnCount <= EaselTable.maximumCells, "Tables stop at 100 by 100")
        #expect((try? huge.validate()) != nil, "The largest table is valid")
        let tiny = EaselTable.blank(columns: 0, rows: -4)
        #expect(tiny.columnCount == 1 && tiny.rowCount == 1, "A table always keeps one cell")
        #expect(table.accessibilitySummary == "3 columns, 3 rows, empty", "VoiceOver hears the table's shape")
        #expect(filled([["a", ""]]).accessibilitySummary == "2 columns, 1 row, 1 filled", "VoiceOver hears how much is filled")
    }

    @Test func tablesWithoutMergesLeaveTheFieldOut() {
        var table = filled([["Name", "Age"], ["Ada", ""]])
        table.cells[1][1].fill = "#FAE7D5"
        let data = try! JSONEncoder().encode(table)
        let json = String(data: data, encoding: .utf8)!
        #expect(!json.contains("merges"), "Tables without merges leave the field out")
        #expect(json.contains("{\"fill\":\"#FAE7D5\"}"), "A coloured empty cell saves only its fill")
        #expect(String(data: try! JSONEncoder().encode(EaselTableCell()), encoding: .utf8) == "{}", "Empty cells save as empty objects")
        #expect(!json.contains("\"text\":\"\""), "Empty text is left out")
        let decoded = try! JSONDecoder().decode(EaselTable.self, from: data)
        #expect(decoded == table, "Tables round trip")
        var merged = table
        merged.merges = [EaselTableMerge(row: 0, column: 0, rowSpan: 1, columnSpan: 2)]
        merged.cells[0][1] = EaselTableCell()
        let again = try! JSONDecoder().decode(EaselTable.self, from: JSONEncoder().encode(merged))
        #expect(again.merges == merged.merges, "Merges round trip")
        let old = "{\"id\":\"\(UUID().uuidString)\",\"kind\":\"text\",\"frame\":{\"x\":0,\"y\":0,\"width\":10,\"height\":10},\"zIndex\":0,\"text\":\"Hi\",\"color\":\"#252525\",\"points\":[]}"
        let item = try! JSONDecoder().decode(EaselItem.self, from: Data(old.utf8))
        #expect(item.table == nil, "Objects saved before tables still open")
        let encoded = String(data: try! JSONEncoder().encode(item), encoding: .utf8)!
        #expect(!encoded.contains("table"), "Objects without a table never write one")
        #expect(EaselItemKind(rawValue: "table") == .table && !EaselItemKind.table.holdsText, "Tables are their own kind and keep text in cells")
    }

    @Test func aPlainTableIsValid() {
        var table = filled([["a", "b"], ["c", "d"]])
        #expect((try? table.validate()) != nil, "A plain table is valid")
        var ragged = table
        ragged.cells[1].removeLast()
        rejects(ragged, "Ragged rows are refused")
        var wrongHeights = table
        wrongHeights.rowHeights.append(30)
        rejects(wrongHeights, "Row heights must match the rows")
        var badWidth = table
        badWidth.columnWidths[0] = .infinity
        rejects(badWidth, "Infinite widths are refused")
        var badFill = table
        badFill.cells[0][0].fill = "orange"
        rejects(badFill, "Fills must be hex")
        var long = table
        long.cells[0][0].text = String(repeating: "x", count: EaselTable.maximumCellBytes + 1)
        rejects(long, "Huge cells are refused")
        var rich = table
        rich.cells[0][0].richText = EaselRichText(runs: [])
        rejects(rich, "Rich text must cover its cell")
        table.merges = [EaselTableMerge(row: 0, column: 0, rowSpan: 2, columnSpan: 1)]
        rejects(table, "Merged-away cells cannot hide text")
        table.cells[1][0] = EaselTableCell()
        #expect((try? table.validate()) != nil, "A clean merge is valid")
        var overlap = table
        overlap.cells[1][1] = EaselTableCell()
        overlap.merges.append(EaselTableMerge(row: 1, column: 0, rowSpan: 1, columnSpan: 2))
        rejects(overlap, "Overlapping merges are refused")
        var single = table
        single.merges = [EaselTableMerge(row: 0, column: 0, rowSpan: 1, columnSpan: 1)]
        rejects(single, "One-cell merges are refused")
        for merge in [EaselTableMerge(row: Int.max, column: 0, rowSpan: Int.max, columnSpan: 2),
                      EaselTableMerge(row: 0, column: -1, rowSpan: 2, columnSpan: 2),
                      EaselTableMerge(row: 0, column: 0, rowSpan: 0, columnSpan: Int.max)] {
            var broken = table
            broken.merges = [merge]
            rejects(broken, "Out-of-range merges are refused without crashing")
        }
        var tooMany = EaselTable.blank(columns: 100, rows: 100)
        tooMany.rowHeights.append(36)
        tooMany.cells.append(Array(repeating: EaselTableCell(), count: 100))
        rejects(tooMany, "More than 10,000 cells are refused")
    }

    @Test @MainActor func aDocumentWithATableSaves() {
        let date = Date(timeIntervalSinceReferenceDate: 1000)
        var document = EaselDocument(id: UUID(), title: "Board", createdAt: date, modifiedAt: date)
        var good = EaselTableGeometry.item(columns: 2, rows: 2, frame: EaselRect(x: 10, y: 10, width: 200, height: 80), zIndex: 1)
        good.table?.cells[0][0].text = "Hi"
        document.items = [good]
        #expect((try? EaselSession(inMemory: document, assets: [:])) != nil, "A document with a table saves")
        var missing = good
        missing.table = nil
        document.items = [missing]
        #expect((try? EaselSession(inMemory: document, assets: [:])) == nil, "A table object needs its grid")
        var stray = EaselItem(kind: .rectangle, frame: EaselRect(x: 0, y: 0, width: 20, height: 20))
        stray.table = EaselTable.blank(columns: 1, rows: 1)
        document.items = [stray]
        #expect((try? EaselSession(inMemory: document, assets: [:])) == nil, "Only tables carry a grid")
        var rich = good
        rich.richText = EaselRichText(runs: [])
        document.items = [rich]
        #expect((try? EaselSession(inMemory: document, assets: [:])) == nil, "Tables keep text in cells, not on the object")
    }

    @Test func rowsAndColumns() {
        var table = filled([["a", "b"], ["c", "d"]])
        table.cells[0][1].fill = "#D8E9F3"
        table.cells[1][1].fill = "#D8E9F3"
        let hoisted125 = table.insertRows(at: 1)
        #expect(hoisted125, "Rows insert")
        #expect(table.rowCount == 3 && table.cells[1].allSatisfy { $0.text.isEmpty } && table.cells[2][0].text == "c", "New rows are empty and push others down")
        #expect(table.cells[1][1].fill == "#D8E9F3" && table.cells[1][0].fill == nil, "A fully coloured column colours its new cell")
        let hoisted128 = table.insertColumns(at: 0, width: 90)
        #expect(hoisted128, "Columns insert")
        #expect(table.columnCount == 3 && table.columnWidths[0] == 90 && table.cells[0][1].text == "a", "New columns are empty and keep their width")
        #expect(table.removeRows(1...1) && table.rowCount == 2 && table.cells[1][1].text == "c", "Rows delete")
        let hoisted131 = !table.removeRows(0...1)
        #expect(hoisted131, "The last row can't be deleted")
        #expect(table.removeColumns(0...0) && table.columnCount == 2, "Columns delete")
        let hoisted133 = !table.removeColumns(0...1)
        #expect(hoisted133, "The last column can't be deleted")
        var full = EaselTable.blank(columns: 100, rows: 100)
        #expect(!full.insertRows(at: 0) && !full.insertColumns(at: 0), "Full tables refuse more")
        var wide = EaselTable.blank(columns: 100, rows: 99)
        #expect(wide.insertRows(at: 99) && !wide.insertRows(at: 0), "Cell limit allows exactly 10,000")
        var merged = filled([["a", "", "c"], ["d", "e", "f"]])
        merged.merges = [EaselTableMerge(row: 0, column: 0, rowSpan: 1, columnSpan: 2)]
        let hoisted140 = merged.insertColumns(at: 1)
        #expect(hoisted140, "Inserting inside a merge works")
        #expect(merged.merges == [EaselTableMerge(row: 0, column: 0, rowSpan: 1, columnSpan: 3)], "Merges grow around inserted columns")
        #expect(merged.cells[0][1].isBlank && merged.cells[0][2].isBlank && (try? merged.validate()) != nil, "Cells under a merge stay blank")
        let hoisted143 = merged.removeColumns(0...0)
        #expect(hoisted143, "Deleting a merge's anchor column works")
        #expect(merged.merges == [EaselTableMerge(row: 0, column: 0, rowSpan: 1, columnSpan: 2)] && merged.cells[0][0].text == "a", "The merge keeps its text")
        #expect(merged.removeColumns(0...0) && merged.merges.isEmpty && merged.cells[0][0].text == "a", "A merge shrunk to one cell disappears")
        var cut = filled([["a", "x"], ["b", "y"], ["", "z"]])
        cut.merges = [EaselTableMerge(row: 1, column: 0, rowSpan: 2, columnSpan: 1)]
        #expect(!cut.duplicateRows(1...1) && !cut.duplicateRows(0...1), "Duplicating half a merged block is refused")
        #expect(cut.duplicateRows(1...2) && cut.merges.count == 2 && (try? cut.validate()) != nil, "Duplicating whole merged rows copies the merge")
        var across = filled([["a", "", "c"]])
        across.merges = [EaselTableMerge(row: 0, column: 0, rowSpan: 1, columnSpan: 2)]
        #expect(!across.duplicateColumns(1...1) && across.duplicateColumns(0...1) && (try? across.validate()) != nil, "Columns duplicate only whole merges")
        var copy = filled([["a", "b"], ["c", "d"]])
        #expect(copy.duplicateRows(0...0) && copy.rowCount == 3 && copy.cells[1][0].text == "a" && copy.cells[2][0].text == "c", "Rows duplicate below")
        #expect(copy.duplicateColumns(1...1) && copy.columnCount == 3 && copy.cells[0][2].text == "b", "Columns duplicate to the right")
    }

    @Test func rowsMove() {
        var table = filled([["1"], ["2"], ["3"], ["4"]])
        let hoisted160 = table.moveRows(0...0, to: 2)
        #expect(hoisted160, "Rows move")
        #expect(table.cells.map { $0[0].text } == ["2", "3", "1", "4"], "Row order follows the move")
        #expect(table.moveRows(2...3, to: 0) && table.cells.map { $0[0].text } == ["1", "4", "2", "3"], "Blocks of rows move together")
        #expect(!table.moveRows(0...0, to: 0) && !table.moveRows(0...1, to: 3), "No-op and out-of-range moves are refused")
        var columns = filled([["a", "b", "c"]])
        columns.columnWidths = [10, 20, 30].map { $0 * 5 }
        #expect(columns.moveColumns(2...2, to: 0) && columns.cells[0].map(\.text) == ["c", "a", "b"] && columns.columnWidths == [150, 50, 100], "Columns move with their widths")
        var merged = filled([["a", ""], ["c", "d"], ["e", "f"]])
        merged.merges = [EaselTableMerge(row: 0, column: 0, rowSpan: 1, columnSpan: 2)]
        #expect(merged.moveRows(0...0, to: 2) && merged.merges == [EaselTableMerge(row: 2, column: 0, rowSpan: 1, columnSpan: 2)], "Merges travel with their row")
        var split = filled([["a", "x"], ["", "y"], ["c", "z"]])
        split.merges = [EaselTableMerge(row: 0, column: 0, rowSpan: 2, columnSpan: 1)]
        #expect(!split.moveRows(2...2, to: 1) && split.merges.count == 1 && split.cells[2][0].text == "c", "A move into a merged block is refused")
        var block = filled([["0"], ["1"], ["2"], ["3"], [""]])
        block.merges = [EaselTableMerge(row: 3, column: 0, rowSpan: 2, columnSpan: 1)]
        #expect(!block.keepsMerges(moving: 2...2, to: 3, along: .rows), "Landing inside rows 4–5 would split their merge")
        #expect(block.destination(moving: 2...2, by: 1, along: .rows) == 4, "Option-Down hops over the whole merged block")
        #expect(block.moveRows(2...2, to: 4) && block.merges == [EaselTableMerge(row: 2, column: 0, rowSpan: 2, columnSpan: 1)]
               && block.cells.map { $0[0].text } == ["0", "1", "3", "", "2"], "Moving past a merge keeps it whole")
        #expect(block.destination(moving: 4...4, by: -1, along: .rows) == 2, "Option-Up hops back over it")
        #expect(block.destination(moving: 1...1, by: -1, along: .rows) == 0 && block.destination(moving: 0...0, by: -1, along: .rows) == nil, "Moves stop at the edge")
        #expect(block.destination(moving: 2...2, by: -1, along: .rows) == nil, "Half a merged block never moves on its own")
        #expect(!block.moveRows(2...2, to: 0) && !block.keepsMerges(moving: 3...3, to: 0, along: .rows), "A block can't cut a merge in half")
        let snapped = block.nearestDestination(moving: 4...4, to: 3, along: .rows)
        #expect(snapped != 3 && (snapped == 4 || block.keepsMerges(moving: 4...4, to: snapped, along: .rows)), "Drags inside a merge snap to a safe spot")
        #expect(block.nearestDestination(moving: 0...0, to: 3, along: .rows) == 3, "Drags that keep merges whole land where dropped")
        var sideways = filled([["a", "b", "", "d"]])
        sideways.merges = [EaselTableMerge(row: 0, column: 1, rowSpan: 1, columnSpan: 2)]
        #expect(sideways.destination(moving: 0...0, by: 1, along: .columns) == 2, "Columns hop over merged blocks too")
        #expect(!sideways.moveColumns(0...0, to: 1) && sideways.moveColumns(0...0, to: 2) && sideways.cells[0].map(\.text) == ["b", "", "a", "d"]
               && sideways.merges == [EaselTableMerge(row: 0, column: 0, rowSpan: 1, columnSpan: 2)], "Column moves keep merges whole")
    }

    @Test func mergingNeedsTwoOrMoreCells() {
        var table = filled([["a", "b", "c"], ["d", "e", "f"]])
        let range = EaselTableRange(cell(0, 0), cell(1, 1))
        #expect(table.canMerge(range) && !table.canMerge(EaselTableRange(cell(0, 0))), "Merging needs two or more cells")
        #expect(table.joinedText(range) == "a\nb\nd\ne", "Merged text joins in reading order")
        table.cells[0][0].fill = "#FAF0D8"
        let merge = table.merge(range, content: EaselTableCell(text: "a\nb\nd\ne"))
        #expect(merge == EaselTableMerge(row: 0, column: 0, rowSpan: 2, columnSpan: 2), "Merge covers the range")
        #expect(table.cells[0][0].text == "a\nb\nd\ne" && table.cells[0][0].fill == "#FAF0D8", "The merged cell keeps everything and the first fill")
        #expect(table.cells[0][1].isBlank && table.cells[1][1].isBlank && (try? table.validate()) != nil, "Covered cells empty out")
        #expect(table.isCovered(cell(1, 1)) && table.anchor(of: cell(1, 1)) == cell(0, 0), "Covered cells point at their anchor")
        #expect(table.expanded(EaselTableRange(cell(1, 1), cell(1, 2))) == EaselTableRange(cell(0, 0), cell(1, 2)), "Selections grow to whole merges")
        #expect(!table.canMerge(range), "The same merge can't happen twice")
        #expect(table.canMerge(EaselTableRange(cell(1, 1), cell(1, 2))), "Merging into a merge grows it")
        #expect(table.merge(EaselTableRange(cell(1, 1), cell(1, 2))) == EaselTableMerge(row: 0, column: 0, rowSpan: 2, columnSpan: 3), "Merges absorb neighbours")
        #expect(table.unmerge(EaselTableRange(cell(1, 2))) && table.merges.isEmpty && table.cells[0][0].text == "a\nb\nd\ne", "Unmerge keeps the text in the first cell")
        let hoisted209 = table.setFill("#DCEBE2", in: EaselTableRange(cell(0, 0), cell(0, 1)))
        #expect(hoisted209, "Cells take a fill")
        #expect(table.commonFill(EaselTableRange(cell(0, 0), cell(0, 1))) == .some("#DCEBE2"), "A shared fill reads back")
        #expect(table.commonFill(EaselTableRange(cell(0, 0), cell(1, 0))) == .none, "Mixed fills read as mixed")
        let hoisted212 = !table.setFill("blue", in: table.all)
        #expect(hoisted212, "Bad fills are refused")
        #expect(table.clearText(table.all) && table.cells.allSatisfy { $0.allSatisfy { $0.text.isEmpty } } && table.cells[0][0].fill == "#DCEBE2", "Clearing keeps fills")
        let hoisted214 = !table.clearText(table.all)
        #expect(hoisted214, "Clearing an empty table changes nothing")
    }

    @Test func tabWrapsToTheNextRow() {
        var table = filled([["a", "b", "c"], ["d", "e", "f"]])
        #expect(table.tab(from: cell(0, 2), backward: false) == .cell(cell(1, 0)), "Tab wraps to the next row")
        #expect(table.tab(from: cell(1, 2), backward: false) == .appendRow, "Tab in the last cell adds a row")
        #expect(table.tab(from: cell(0, 0), backward: true) == .none, "Shift-Tab stops at the first cell")
        table.merges = [EaselTableMerge(row: 0, column: 1, rowSpan: 2, columnSpan: 1)]
        table.cells[1][1] = EaselTableCell()
        #expect(table.tab(from: cell(0, 0), backward: false) == .cell(cell(0, 1)), "Tab enters a merged cell")
        #expect(table.tab(from: cell(1, 0), backward: false) == .cell(cell(1, 2)), "Tab skips covered cells")
        #expect(table.step(from: cell(1, 0), .right) == cell(0, 1), "Arrows land on a merge's anchor")
        #expect(table.step(from: cell(0, 1), .right) == cell(0, 2), "Arrows leave a merge on the far side")
        #expect(table.step(from: cell(0, 0), .up) == cell(0, 0) && table.step(from: cell(1, 2), .right) == cell(1, 2), "Arrows stop at the edges")
        #expect(table.extended(cell(1, 2), .down) == cell(1, 2) && table.extended(cell(0, 0), .right) == cell(0, 1), "Shift-arrows grow within bounds")
    }

    @Test func pastingReportsWhereItLanded() {
        var table = filled([["a", "b"], ["c", "d"]])
        let source = filled([["1", "2", "3"], ["4", "5", "6"]])
        let area = table.paste(source, at: cell(1, 1))
        #expect(area == EaselTableRange(rows: 1...2, columns: 1...3), "Pasting reports where it landed")
        #expect(table.rowCount == 3 && table.columnCount == 4 && table.cells[2][3].text == "6" && table.cells[0][0].text == "a", "Pasting grows the table")
        #expect(table.columnWidths[3] == table.columnWidths[1], "Grown columns copy the last width")
        var fill = filled([["a", "b"], ["c", "d"]])
        let one = filled([["x"]])
        #expect(fill.paste(one, at: cell(0, 0), filling: fill.all) == fill.all && fill.cells.allSatisfy { $0.allSatisfy { $0.text == "x" } }, "One value fills every selected cell")
        var keep = filled([["a"]])
        keep.cells[0][0].fill = "#F9DEDC"
        _ = keep.paste(filled([["z"]]), at: cell(0, 0))
        #expect(keep.cells[0][0].text == "z" && keep.cells[0][0].fill == "#F9DEDC", "Plain pastes keep cell colours")
        var withMerge = EaselTable.blank(columns: 3, rows: 1)
        var mergedSource = filled([["m", ""]])
        mergedSource.merges = [EaselTableMerge(row: 0, column: 0, rowSpan: 1, columnSpan: 2)]
        _ = withMerge.paste(mergedSource, at: cell(0, 1))
        #expect(withMerge.merges == [EaselTableMerge(row: 0, column: 1, rowSpan: 1, columnSpan: 2)] && (try? withMerge.validate()) != nil, "Pasted merges come along")
        var capped = EaselTable.blank(columns: 1, rows: 1)
        _ = capped.paste(EaselTable.blank(columns: 100, rows: 100), at: cell(0, 0))
        #expect(capped.rowCount * capped.columnCount <= EaselTable.maximumCells && (try? capped.validate()) != nil, "Pasting never breaks the limits")
        let slice = filled([["a", "b", "c"], ["d", "e", "f"]]).slice(EaselTableRange(cell(0, 1), cell(1, 2)))
        #expect(slice?.cells.map { $0.map(\.text) } == [["b", "c"], ["e", "f"]], "Slices copy a block of cells")
    }

    @Test func columnsStopAtTheMinimumWidth() {
        var table = EaselTable.blank(columns: 2, rows: 2, columnWidth: 100, rowHeight: 40)
        #expect(table.setWidth(10, column: 0) && table.columnWidths[0] == EaselTable.minimumColumnWidth, "Columns stop at the minimum width")
        #expect(table.setHeight(10, row: 0, minimum: 50) && table.rowHeights[0] == 50, "Rows stop at their content")
        #expect(!table.setWidth(.nan, column: 0) && !table.setWidth(100, column: 9), "Bad widths are refused")
        table.columnWidths = [100, 300]
        table.scaleColumns(toWidth: 200)
        #expect(table.columnWidths == [50, 150], "Resizing scales columns proportionally")
        table.scaleColumns(toWidth: 20)
        #expect(table.columnWidths.allSatisfy { $0 >= EaselTable.minimumColumnWidth }, "Scaling keeps the minimum width")
        table.rowHeights = [40, 40]
        table.scaleRows(toHeight: 40, minimums: [36, 0])
        #expect(table.rowHeights[0] == 36 && table.rowHeights[1] == EaselTable.minimumRowHeight, "Rows shrink only to their content")
        table.fitRows(minimums: [90, 10])
        #expect(table.rowHeights[0] == 90 && table.rowHeights[1] == EaselTable.minimumRowHeight, "Rows grow with their text")
        var item = EaselTableGeometry.item(columns: 2, rows: 2, frame: EaselRect(x: 5, y: 6, width: 200, height: 80), zIndex: 3)
        #expect(item.kind == .table && item.frame == EaselRect(x: 5, y: 6, width: 200, height: 80) && item.table?.columnWidths == [100, 100], "New table items match their frame")
        item.frame.width = 400
        item.frame.height = 20
        let fitted = EaselTableGeometry.fitted(item)
        #expect(fitted.table?.columnWidths == [200, 200] && fitted.frame.width == 400, "A wider frame scales the columns")
        #expect(fitted.frame.height == 2 * EaselTable.minimumRowHeight && fitted.table?.height == fitted.frame.height, "Shrinking stops at the minimum height")
        let click = EaselTableGeometry.placement(from: EaselPoint(x: 300, y: 300), to: nil)
        #expect(click.columns == 3 && click.rows == 3, "A click makes a 3 by 3 table")
        #expect(abs(click.frame.x + click.frame.width / 2 - 300) < 0.001 && abs(click.frame.y + click.frame.height / 2 - 300) < 0.001, "Clicked tables centre on the click")
        let drag = EaselTableGeometry.placement(from: EaselPoint(x: 100, y: 100), to: EaselPoint(x: 100 + EaselTable.defaultColumnWidth * 3.5, y: 100 + EaselTable.defaultRowHeight * 1.5))
        #expect(drag.columns == 4 && drag.rows == 2 && drag.frame.x == 100 && drag.frame.y == 100, "Dragging picks columns and rows")
        let back = EaselTableGeometry.placement(from: EaselPoint(x: 500, y: 500), to: EaselPoint(x: 500 - EaselTable.defaultColumnWidth * 1.2, y: 480))
        #expect(back.columns == 2 && back.rows == 1 && back.frame.x + back.frame.width == 500, "Dragging up and left grows that way")
        let far = EaselTableGeometry.placement(from: EaselPoint(x: 0, y: 0), to: EaselPoint(x: 100_000, y: 100_000))
        #expect(far.columns == 12 && far.rows == 24, "Dragged tables stay a sensible size")
    }

    @Test func edgesAddUpFromTheFrame() {
        var table = filled([["a", "b", "c"], ["d", "e", "f"]])
        table.columnWidths = [100, 50, 100]
        table.rowHeights = [40, 60]
        let grid = EaselTableLayout(table: table, frame: EaselRect(x: 10, y: 20, width: 250, height: 100))
        #expect(grid.columnEdges == [10, 110, 160, 260] && grid.rowEdges == [20, 60, 120], "Edges add up from the frame")
        #expect(grid.cell(at: EaselPoint(x: 120, y: 70)) == cell(1, 1) && grid.cell(at: EaselPoint(x: 9, y: 70)) == nil, "Points find their cell")
        #expect(grid.clampedCell(at: EaselPoint(x: 900, y: -5)) == cell(0, 2), "Drags past the edge clamp to the last cell")
        #expect(grid.rect(of: cell(1, 2), in: table) == EaselRect(x: 160, y: 60, width: 100, height: 60), "Cells have rectangles")
        let scaled = EaselTableLayout(table: table, frame: EaselRect(x: 0, y: 0, width: 500, height: 200))
        #expect(scaled.columnEdges == [0, 200, 300, 500], "A stretched frame stretches the grid")
        #expect(grid.columnBorder(near: EaselPoint(x: 111, y: 30), tolerance: 3, in: table) == 0, "Borders are found near the pointer")
        #expect(grid.rowBorder(near: EaselPoint(x: 50, y: 58), tolerance: 3, in: table) == 0 && grid.rowBorder(near: EaselPoint(x: 50, y: 90), tolerance: 3, in: table) == nil, "Rows borders too")
        #expect(grid.borderSegments(in: table).count == 3, "Two column borders and one row border")
        table.merges = [EaselTableMerge(row: 0, column: 0, rowSpan: 1, columnSpan: 2)]
        table.cells[0][1] = EaselTableCell()
        let merged = EaselTableLayout(table: table, frame: EaselRect(x: 10, y: 20, width: 250, height: 100))
        #expect(merged.columnBorder(near: EaselPoint(x: 110, y: 30), tolerance: 3, in: table) == nil, "Borders inside a merge can't be grabbed")
        #expect(merged.columnBorder(near: EaselPoint(x: 110, y: 90), tolerance: 3, in: table) == 0, "The same border is grabbable below the merge")
        let segments = merged.borderSegments(in: table)
        #expect(segments.contains { $0.start == EaselPoint(x: 110, y: 60) && $0.end == EaselPoint(x: 110, y: 120) }, "Merged cells hide their inner border")
        #expect(merged.rect(of: cell(0, 1), in: table) == EaselRect(x: 10, y: 20, width: 150, height: 40), "Merged cells span their columns")
        #expect(grid.dropIndex(for: 255, edges: grid.columnEdges, moving: 0...0) == 2 && grid.dropIndex(for: 15, edges: grid.columnEdges, moving: 2...2) == 0, "Drops land between columns")
        #expect(EaselTableLayout.index(of: 260, in: grid.columnEdges) == nil && EaselTableLayout.index(of: 259.9, in: grid.columnEdges) == 2, "Edges are half open")
    }

    @Test func csvHandlesQuotesCommasNewlinesAndCRLF() {
        let quoted = EaselTableData.delimited("a,\"b,c\",\"say \"\"hi\"\"\"\r\n\"multi\nline\",x,\r\n", separator: ",")
        #expect(quoted.cells == [["a", "b,c", "say \"hi\""], ["multi\nline", "x", ""]], "CSV handles quotes, commas, newlines and CRLF")
        #expect(EaselTableData.delimited("", separator: ",").cells.isEmpty, "Empty text has no rows")
        #expect(EaselTableData.delimited("solo", separator: ",").cells == [["solo"]], "One value is one cell")
        let sheet = EaselTableData.spreadsheetText("Name\tAge\nAda\t36\n")
        #expect(sheet?.cells == [["Name", "Age"], ["Ada", "36"]], "Spreadsheet text becomes a grid")
        #expect(EaselTableData.spreadsheetText("Name\tAge\nAda") == nil, "Ragged tab text stays text")
        #expect(EaselTableData.spreadsheetText("just words\nmore words") == nil, "Text without tabs stays text")
        #expect(EaselTableData.spreadsheetText("\tindented\n\t\tcode\n") == nil, "Indented code stays text")
        #expect(EaselTableData.spreadsheetText("a\t\"two\nlines\"\nb\tc")?.cells == [["a", "two\nlines"], ["b", "c"]], "Quoted cells keep their line breaks")
        #expect(EaselTableData.csv("\u{FEFF}x,y")?.cells == [["x", "y"]], "A byte order mark is skipped")
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
        #expect(EaselTableData.html("<p>No table here</p>") == nil, "HTML without a table is not a table")
        let table = grid.flatMap(EaselTableData.table(from:))
        #expect(table?.rowCount == 3 && table?.columnCount == 3 && table?.merges.count == 2 && (try? table?.validate()) != nil, "Imported grids become valid tables")
        let big = EaselTableGrid(cells: Array(repeating: Array(repeating: "x", count: 7), count: 400))
        let capped = EaselTableData.imported(big)
        #expect(capped?.table.columnCount == 7 && capped?.table.rowCount == 71 && capped?.trimmed == true, "New tables keep the first 500 cells and say so")
        let roomy = EaselTableData.imported(big, limit: EaselTable.maximumCells)
        #expect(roomy?.table.rowCount == 100 && roomy?.trimmed == true, "Pasting into a table can go up to the 100-row limit and says what stayed behind")
        let small = EaselTableData.imported(EaselTableGrid(cells: [["a", "b"], ["c", "d"]]))
        #expect(small?.trimmed == false, "Small pastes are kept whole")
        let wide = EaselTableData.imported(EaselTableGrid(cells: [Array(repeating: "y", count: 300)]), limit: EaselTable.maximumCells)
        #expect(wide?.table.columnCount == 100 && wide?.trimmed == true, "Imports keep the first 100 columns and say so")
        let long = EaselTableData.imported(EaselTableGrid(cells: [[String(repeating: "z", count: EaselTable.maximumCellBytes + 10), "ok"]]))
        #expect(long?.table.cells[0][0].text.utf8.count == EaselTable.maximumCellBytes && long?.trimmed == true, "Overlong cells are clipped and reported")
        let lines = String(repeating: "a\tb\n", count: EaselTableData.maximumParsedRows + 5)
        #expect(EaselTableData.delimited(lines, separator: "\t").truncated && !EaselTableData.delimited("a\tb\n", separator: "\t").truncated, "Parsing notes when it stops early")
        let tall = "<table>" + String(repeating: "<tr><td>r</td></tr>", count: 120) + "</table>"
        #expect(EaselTableData.html(tall)?.rowCount == 100 && EaselTableData.html(tall)?.truncated == true, "HTML tables stop at 100 rows and say so")
        #expect(EaselTableData.readsHTMLTable(plainText: nil, intoCells: false) && EaselTableData.readsHTMLTable(plainText: "a\tb", intoCells: false), "Spreadsheet copies read their HTML table")
        #expect(!EaselTableData.readsHTMLTable(plainText: "Hi Ada,\nthe newsletter", intoCells: false), "Mail and web pages with layout tables stay text")
        #expect(EaselTableData.readsHTMLTable(plainText: "words", intoCells: true), "Pasting into cells always reads HTML tables")
        #expect(EaselTableData.decodeEntities("&bogus; &amp;amp; &#65;") == "&bogus; &amp; A", "Entities decode once and unknown ones stay")
        #expect(EaselTableData.clipped("héllo", bytes: 2) == "h", "Clipping never splits a character")
    }

    @Test func csvQuotesWhatItMust() {
        var table = filled([["Name", "Note"], ["Ada", "said \"hi\", then\nleft"]])
        #expect(EaselTableData.csv(table) == "Name,Note\r\nAda,\"said \"\"hi\"\", then\nleft\"\r\n", "CSV quotes what it must")
        #expect(EaselTableData.tsv(table, range: EaselTableRange(cell(0, 0), cell(1, 0))) == "Name\nAda\n", "TSV exports a chosen range")
        let reparsed = EaselTableData.csv(EaselTableData.csv(table))
        #expect(reparsed?.cells == table.cells.map { $0.map(\.text) }, "CSV round trips")
        table.merges = [EaselTableMerge(row: 0, column: 0, rowSpan: 1, columnSpan: 2)]
        table.cells[0][1] = EaselTableCell()
        table.cells[1][0].fill = "#FAE7D5"
        let html = EaselTableData.html(table)
        #expect(html.contains("colspan=\"2\"") && html.contains("background-color:#FAE7D5") && html.contains("<br>"), "HTML copies spans, fills and breaks")
        let back = EaselTableData.html(html)
        #expect(back?.merges == table.merges && back?.cells[1][1] == "said \"hi\", then\nleft", "Our HTML reads back")
        var item = EaselTableGeometry.item(columns: 2, rows: 2, frame: EaselRect(x: 0, y: 0, width: 200, height: 72), zIndex: 1)
        item.table = table
        let svg = EaselVectorExport.element(item, art: EaselVectorArt())
        #expect(svg.contains("easel-table") && svg.contains("clipPath") && svg.contains("<path d=\"M"), "Tables export as SVG with a grid")
        #expect(svg.contains(EaselVectorExport.paint("#FAE7D5", role: .fill)), "Cell fills export with their light and dark palette colours")
        #expect(svg.contains("var(--easel-card)") && svg.contains("var(--easel-card-line)"), "Table chrome follows light and dark")
    }

    @Test func eachFilledCellBecomesASticky() {
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
        var tall = item
        tall.table?.cells[0][1].text = "Long"
        let rows = EaselTableGeometry.stickies(from: tall, fill: { _ in nil }, textHeight: { $0.text == "Long" ? 400 : 0 })
        let second = rows.first { $0.text == "Other" }
        let first = rows.first { $0.text == "Long" }
        #expect(second.map { $0.frame.y } == first.map { $0.frame.y + $0.frame.height + 24 }, "Each row clears its tallest sticky")
    }
}
