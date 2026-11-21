import AppKit
import Testing
@testable import Parc

struct ResultNavigationTests {
    @MainActor private final class Rows: NSObject, NSTableViewDataSource {
        var count: Int
        init(count: Int) { self.count = count }
        func numberOfRows(in tableView: NSTableView) -> Int { count }
    }

    @Test(arguments: [
        (6, 0, -1, true, 5), (6, 5, 1, true, 0), (6, 0, 1, true, 1),
        (6, -1, -1, true, 5), (6, -1, 1, true, 0), (6, 0, -1, false, 0),
        (6, 5, 1, false, 5), (1, 0, 1, true, 0), (1, 0, -1, true, 0),
        (0, -1, 1, true, nil), (0, -1, -1, true, nil), (6, 0, 0, true, nil),
        (6, 0, Int.max, true, nil),
    ] as [(Int, Int, Int, Bool, Int?)])
    @MainActor func arrowsMoveAcrossOnlyTheCurrentResults(rowCount: Int, selected: Int, delta: Int,
                                                            wraps: Bool, expected: Int?) {
        _ = NSApplication.shared
        let table = CommandResultsTable()
        let rows = Rows(count: rowCount)
        table.dataSource = rows
        table.reloadData()
        if selected >= 0 { table.selectRowIndexes(IndexSet(integer: selected), byExtendingSelection: false) }
        #expect(table.keyboardSelectionRow(moving: delta, wrapping: wraps) == expected)
    }

    @Test @MainActor func aReplacementSnapshotUsesItsOwnRowCount() {
        let table = CommandResultsTable()
        let rows = Rows(count: 6)
        table.dataSource = rows
        table.reloadData()
        table.selectRowIndexes(IndexSet(integer: 4), byExtendingSelection: false)
        rows.count = 1
        table.reloadData()
        #expect(table.keyboardSelectionRow(moving: 1, wrapping: true) == 0)
    }
}
