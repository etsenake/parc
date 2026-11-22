import Foundation
import Testing
@testable import ParcCore

struct EaselTableModelTests {
    @Test
    func aNewGridHasTheRequestedShapeAndDefaultSizes() {
        let table = EaselTable.blank(columns: 3, rows: 3)
        #expect(table.rowCount == 3 && table.columnCount == 3 && table.cells.allSatisfy { $0.count == 3 }, "A new table is 3 by 3")
        #expect(table.width == 3 * EaselTable.defaultColumnWidth && table.height == 3 * EaselTable.defaultRowHeight, "Sizes add up")
    }

    @Test
    func newGridsClampAtOneHundredRowsAndColumns() {
        let huge = EaselTable.blank(columns: 500, rows: 500)
        #expect(huge.columnCount == 100 && huge.rowCount == 100 && huge.rowCount * huge.columnCount <= EaselTable.maximumCells, "Tables stop at 100 by 100")
        #expect((try? huge.validate()) != nil, "The largest table is valid")
    }

    @Test
    func aNewGridKeepsAtLeastOneCell() {
        let tiny = EaselTable.blank(columns: 0, rows: -4)
        #expect(tiny.columnCount == 1 && tiny.rowCount == 1, "A table always keeps one cell")
    }

    @Test
    func tableAccessibilitySummarizesItsShapeAndFilledCells() {
        let table = EaselTable.blank(columns: 3, rows: 3)
        #expect(table.accessibilitySummary == "3 columns, 3 rows, empty", "VoiceOver hears the table's shape")
        #expect(EaselTableTestsSupport.filled([["a", ""]]).accessibilitySummary == "2 columns, 1 row, 1 filled", "VoiceOver hears how much is filled")
    }

    @Test
    func tableEncodingOmitsEmptyFields() {
        var table = EaselTableTestsSupport.filled([["Name", "Age"], ["Ada", ""]])
        table.cells[1][1].fill = "#FAE7D5"
        let data = try! JSONEncoder().encode(table)
        let json = String(data: data, encoding: .utf8)!
        #expect(!json.contains("merges"), "Tables without merges leave the field out")
        #expect(json.contains("{\"fill\":\"#FAE7D5\"}"), "A coloured empty cell saves only its fill")
        #expect(String(data: try! JSONEncoder().encode(EaselTableCell()), encoding: .utf8) == "{}", "Empty cells save as empty objects")
        #expect(!json.contains("\"text\":\"\""), "Empty text is left out")
    }

    @Test
    func unmergedTablesRoundTrip() {
        var table = EaselTableTestsSupport.filled([["Name", "Age"], ["Ada", ""]])
        table.cells[1][1].fill = "#FAE7D5"
        let data = try! JSONEncoder().encode(table)
        let decoded = try! JSONDecoder().decode(EaselTable.self, from: data)
        #expect(decoded == table, "Tables round trip")
    }

    @Test
    func mergedTablesRoundTrip() {
        var table = EaselTableTestsSupport.filled([["Name", "Age"], ["Ada", ""]])
        table.cells[1][1].fill = "#FAE7D5"
        var merged = table
        merged.merges = [EaselTableMerge(row: 0, column: 0, rowSpan: 1, columnSpan: 2)]
        merged.cells[0][1] = EaselTableCell()
        let again = try! JSONDecoder().decode(EaselTable.self, from: JSONEncoder().encode(merged))
        #expect(again.merges == merged.merges, "Merges round trip")
    }

    @Test
    func objectsSavedBeforeTablesStillOpen() {
        let old = "{\"id\":\"\(UUID().uuidString)\",\"kind\":\"text\",\"frame\":{\"x\":0,\"y\":0,\"width\":10,\"height\":10},\"zIndex\":0,\"text\":\"Hi\",\"color\":\"#252525\",\"points\":[]}"
        let item = try! JSONDecoder().decode(EaselItem.self, from: Data(old.utf8))
        #expect(item.table == nil, "Objects saved before tables still open")
    }

    @Test
    func objectsWithoutTablesOmitTheField() {
        let old = "{\"id\":\"\(UUID().uuidString)\",\"kind\":\"text\",\"frame\":{\"x\":0,\"y\":0,\"width\":10,\"height\":10},\"zIndex\":0,\"text\":\"Hi\",\"color\":\"#252525\",\"points\":[]}"
        let item = try! JSONDecoder().decode(EaselItem.self, from: Data(old.utf8))
        let encoded = String(data: try! JSONEncoder().encode(item), encoding: .utf8)!
        #expect(!encoded.contains("table"), "Objects without a table never write one")
    }

    @Test
    func tablesHoldTextInCells() {
        #expect(EaselItemKind(rawValue: "table") == .table && !EaselItemKind.table.holdsText, "Tables are their own kind and keep text in cells")
    }

    private enum InvalidTable: String, CaseIterable, CustomTestStringConvertible {
        case raggedRows, extraHeight, infiniteWidth, invalidFill, oversizedCell, incompleteRichText

        var testDescription: String { rawValue }
    }

    @Test(arguments: InvalidTable.allCases)
    private func malformedTablesAreRefused(_ invalid: InvalidTable) {
        var table = EaselTableTestsSupport.filled([["a", "b"], ["c", "d"]])
        switch invalid {
        case .raggedRows: table.cells[1].removeLast()
        case .extraHeight: table.rowHeights.append(30)
        case .infiniteWidth: table.columnWidths[0] = .infinity
        case .invalidFill: table.cells[0][0].fill = "orange"
        case .oversizedCell: table.cells[0][0].text = String(repeating: "x", count: EaselTable.maximumCellBytes + 1)
        case .incompleteRichText: table.cells[0][0].richText = EaselRichText(runs: [])
        }
        EaselTableTestsSupport.rejects(table, invalid.testDescription)
    }

    @Test
    func aPlainTableIsValid() {
        let table = EaselTableTestsSupport.filled([["a", "b"], ["c", "d"]])
        #expect((try? table.validate()) != nil, "A plain table is valid")
    }

    @Test
    func aMergeCannotCoverText() {
        var table = EaselTableTestsSupport.filled([["a", "b"], ["c", "d"]])
        table.merges = [EaselTableMerge(row: 0, column: 0, rowSpan: 2, columnSpan: 1)]
        EaselTableTestsSupport.rejects(table, "Merged-away cells cannot hide text")
        table.cells[1][0] = EaselTableCell()
        #expect((try? table.validate()) != nil, "A clean merge is valid")
    }

    @Test
    func overlappingMergesAreRefused() {
        var table = EaselTableTestsSupport.filled([["a", "b"], ["", ""]])
        table.merges = [.init(row: 0, column: 0, rowSpan: 2, columnSpan: 1),
                        .init(row: 1, column: 0, rowSpan: 1, columnSpan: 2)]
        EaselTableTestsSupport.rejects(table, "Overlapping merges are refused")
    }

    @Test
    func aSingleCellCannotBeAMerge() {
        var table = EaselTableTestsSupport.filled([["a", "b"], ["", "d"]])
        table.merges = [EaselTableMerge(row: 0, column: 0, rowSpan: 1, columnSpan: 1)]
        EaselTableTestsSupport.rejects(table, "One-cell merges are refused")
    }

    private struct MergeCase: Sendable, CustomTestStringConvertible {
        let testDescription: String
        let merge: EaselTableMerge
    }

    @Test(arguments: [
        MergeCase(testDescription: "overflowing row", merge: .init(row: Int.max, column: 0, rowSpan: Int.max, columnSpan: 2)),
        MergeCase(testDescription: "negative column", merge: .init(row: 0, column: -1, rowSpan: 2, columnSpan: 2)),
        MergeCase(testDescription: "zero rows", merge: .init(row: 0, column: 0, rowSpan: 0, columnSpan: Int.max)),
    ])
    private func outOfRangeMergesAreRefusedWithoutCrashing(_ testCase: MergeCase) {
        var table = EaselTableTestsSupport.filled([["a", "b"], ["", "d"]])
        table.merges = [testCase.merge]
        EaselTableTestsSupport.rejects(table, "Out-of-range merges are refused without crashing")
    }

    @Test
    func aTableWithMoreThanTenThousandCellsIsRefused() {
        var tooMany = EaselTable.blank(columns: 100, rows: 100)
        tooMany.rowHeights.append(36)
        tooMany.cells.append(Array(repeating: EaselTableCell(), count: 100))
        EaselTableTestsSupport.rejects(tooMany, "More than 10,000 cells are refused")
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

    @Test
    func mergingNeedsTwoOrMoreCells() {
        let table = EaselTableTestsSupport.filled([["a", "b", "c"], ["d", "e", "f"]])
        let range = EaselTableRange(EaselTableTestsSupport.cell(0, 0), EaselTableTestsSupport.cell(1, 1))
        #expect(table.canMerge(range) && !table.canMerge(EaselTableRange(EaselTableTestsSupport.cell(0, 0))), "Merging needs two or more cells")
    }

    @Test
    func mergedTextJoinsInReadingOrder() {
        let table = EaselTableTestsSupport.filled([["a", "b", "c"], ["d", "e", "f"]])
        let range = EaselTableRange(EaselTableTestsSupport.cell(0, 0), EaselTableTestsSupport.cell(1, 1))
        #expect(table.joinedText(range) == "a\nb\nd\ne", "Merged text joins in reading order")
    }

    @Test
    func mergingKeepsTheAnchorFillAndClearsCoveredCells() {
        var table = EaselTableTestsSupport.filled([["a", "b", "c"], ["d", "e", "f"]])
        let range = EaselTableRange(EaselTableTestsSupport.cell(0, 0), EaselTableTestsSupport.cell(1, 1))
        table.cells[0][0].fill = "#FAF0D8"
        let merge = table.merge(range, content: EaselTableCell(text: "a\nb\nd\ne"))
        #expect(merge == EaselTableMerge(row: 0, column: 0, rowSpan: 2, columnSpan: 2), "Merge covers the range")
        #expect(table.cells[0][0].text == "a\nb\nd\ne" && table.cells[0][0].fill == "#FAF0D8", "The merged cell keeps everything and the first fill")
        #expect(table.cells[0][1].isBlank && table.cells[1][1].isBlank && (try? table.validate()) != nil, "Covered cells empty out")
    }

    @Test
    func coveredCellsPointToTheirMergeAnchor() {
        var table = EaselTableTestsSupport.filled([["a", "b", "c"], ["d", "e", "f"]])
        let range = EaselTableRange(EaselTableTestsSupport.cell(0, 0), EaselTableTestsSupport.cell(1, 1))
        table.cells[0][0].fill = "#FAF0D8"
        _ = table.merge(range, content: EaselTableCell(text: "a\nb\nd\ne"))
        #expect(table.isCovered(EaselTableTestsSupport.cell(1, 1)) && table.anchor(of: EaselTableTestsSupport.cell(1, 1)) == EaselTableTestsSupport.cell(0, 0), "Covered cells point at their anchor")
    }

    @Test
    func aSelectionExpandsToIncludeAMerge() {
        var table = EaselTableTestsSupport.filled([["a", "b", "c"], ["d", "e", "f"]])
        let range = EaselTableRange(EaselTableTestsSupport.cell(0, 0), EaselTableTestsSupport.cell(1, 1))
        table.cells[0][0].fill = "#FAF0D8"
        _ = table.merge(range, content: EaselTableCell(text: "a\nb\nd\ne"))
        #expect(table.expanded(EaselTableRange(EaselTableTestsSupport.cell(1, 1), EaselTableTestsSupport.cell(1, 2))) == EaselTableRange(EaselTableTestsSupport.cell(0, 0), EaselTableTestsSupport.cell(1, 2)), "Selections grow to whole merges")
    }

    @Test
    func anExistingMergeCannotBeIdenticalButCanGrow() {
        var table = EaselTableTestsSupport.filled([["a", "b", "c"], ["d", "e", "f"]])
        let range = EaselTableRange(EaselTableTestsSupport.cell(0, 0), EaselTableTestsSupport.cell(1, 1))
        table.cells[0][0].fill = "#FAF0D8"
        _ = table.merge(range, content: EaselTableCell(text: "a\nb\nd\ne"))
        #expect(!table.canMerge(range), "The same merge can't happen twice")
        #expect(table.canMerge(EaselTableRange(EaselTableTestsSupport.cell(1, 1), EaselTableTestsSupport.cell(1, 2))), "Merging into a merge grows it")
        #expect(table.merge(EaselTableRange(EaselTableTestsSupport.cell(1, 1), EaselTableTestsSupport.cell(1, 2))) == EaselTableMerge(row: 0, column: 0, rowSpan: 2, columnSpan: 3), "Merges absorb neighbours")
    }

    @Test
    func unmergingKeepsTheOriginalTextInTheAnchor() {
        var table = EaselTableTestsSupport.filled([["a", "b", "c"], ["d", "e", "f"]])
        let range = EaselTableRange(EaselTableTestsSupport.cell(0, 0), EaselTableTestsSupport.cell(1, 1))
        table.cells[0][0].fill = "#FAF0D8"
        _ = table.merge(range, content: EaselTableCell(text: "a\nb\nd\ne"))
        #expect(table.merge(EaselTableRange(EaselTableTestsSupport.cell(1, 1), EaselTableTestsSupport.cell(1, 2))) == EaselTableMerge(row: 0, column: 0, rowSpan: 2, columnSpan: 3), "Merges absorb neighbours")
        #expect(table.unmerge(EaselTableRange(EaselTableTestsSupport.cell(1, 2))) && table.merges.isEmpty && table.cells[0][0].text == "a\nb\nd\ne", "Unmerge keeps the text in the first cell")
    }

    @Test
    func fillsReadBackAsSharedOrMixed() {
        var table = EaselTableTestsSupport.filled([["a", "b", "c"], ["d", "e", "f"]])
        let didSetFill = table.setFill("#DCEBE2", in: EaselTableRange(EaselTableTestsSupport.cell(0, 0), EaselTableTestsSupport.cell(0, 1)))
        #expect(didSetFill, "Cells take a fill")
        #expect(table.commonFill(EaselTableRange(EaselTableTestsSupport.cell(0, 0), EaselTableTestsSupport.cell(0, 1))) == .some("#DCEBE2"), "A shared fill reads back")
        #expect(table.commonFill(EaselTableRange(EaselTableTestsSupport.cell(0, 0), EaselTableTestsSupport.cell(1, 0))) == .none, "Mixed fills read as mixed")
    }

    @Test
    func invalidCellFillsAreRefused() {
        var table = EaselTableTestsSupport.filled([["a", "b", "c"], ["d", "e", "f"]])
        let rejectedFill = !table.setFill("blue", in: table.all)
        #expect(rejectedFill, "Bad fills are refused")
    }

    @Test
    func clearingCellsRemovesTextAndKeepsFill() {
        var table = EaselTableTestsSupport.filled([["a", "b", "c"], ["d", "e", "f"]])
        _ = table.setFill("#DCEBE2", in: EaselTableRange(EaselTableTestsSupport.cell(0, 0), EaselTableTestsSupport.cell(0, 1)))
        #expect(table.clearText(table.all) && table.cells.allSatisfy { $0.allSatisfy { $0.text.isEmpty } } && table.cells[0][0].fill == "#DCEBE2", "Clearing keeps fills")
        let noTextToClear = !table.clearText(table.all)
        #expect(noTextToClear, "Clearing an empty table changes nothing")
    }
}
