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

extension ResultNavigationTests {
    @Test @MainActor func arrowKeysReachTheKeyHandlerBeforeTheTable() throws {
        let table = CommandResultsTable()
        var seen: [UInt16] = []
        table.onKey = { event in seen.append(event.keyCode); return true }
        for code: UInt16 in [126, 125] {
            let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code))
            table.keyDown(with: event)
        }
        #expect(seen == [126, 125])
    }

    @Test @MainActor func selectingARowLeavesTheFieldEditingAndTheRowVisible() throws {
        let window = CommandBarTestSupport.borderlessWindow(width: 400, height: 180)
        let field = NSTextField(frame: NSRect(x: 0, y: 150, width: 400, height: 30))
        let table = CommandResultsTable(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        table.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("result")))
        table.rowHeight = 50
        table.headerView = nil
        let rows = Rows(count: 6)
        table.dataSource = rows
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 150))
        scroll.documentView = table
        window.contentView?.addSubview(scroll)
        window.contentView?.addSubview(field)
        field.stringValue = "space"
        try #require(window.makeFirstResponder(field))
        let editor = try #require(field.currentEditor())
        table.reloadData()
        let row = try #require(table.keyboardSelectionRow(moving: -1, wrapping: true))
        table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        table.scrollRowToVisible(row)
        #expect(table.selectedRow == 5)
        #expect(window.firstResponder === editor)
        #expect(table.rows(in: table.visibleRect).contains(5))
        withExtendedLifetime(rows) {}
    }

    @Test(arguments: [true, false])
    @MainActor func eachRowIsReachedOnceBeforeTheListWraps(downward: Bool) {
        _ = NSApplication.shared
        let table = CommandResultsTable()
        let rows = Rows(count: 6)
        table.dataSource = rows
        table.reloadData()
        var visited: [Int] = []
        for _ in 0..<7 {
            guard let next = table.keyboardSelectionRow(moving: downward ? 1 : -1, wrapping: true) else { break }
            table.selectRowIndexes(IndexSet(integer: next), byExtendingSelection: false)
            visited.append(next)
        }
        #expect(visited == (downward ? [0, 1, 2, 3, 4, 5, 0] : [5, 4, 3, 2, 1, 0, 5]))
        withExtendedLifetime(rows) {}
    }
}
