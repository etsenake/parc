import AppKit
import Testing
@testable import Parc

struct DownloadLibraryPointerTests {
    @MainActor private final class Rows: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        func numberOfRows(in tableView: NSTableView) -> Int { 3 }
        func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
            "Download \(row)"
        }
    }

    @MainActor private final class Fixture {
        private let rows = Rows()
        let table = DownloadLibraryTable(frame: CGRect(x: 0, y: 0, width: 320, height: 180))
        var selectedAtCommit: [Int] = []
        var committed: [Int] = []

        init() {
            table.addTableColumn(NSTableColumn(identifier: .init("download")))
            table.delegate = rows
            table.dataSource = rows
            table.reloadData()
            table.prepareClick = { [weak self] row in
                { [weak self] in
                    guard let self else { return }
                    selectedAtCommit.append(table.selectedRow)
                    committed.append(row)
                }
            }
        }

        func press(row: Int = 1, count: Int = 1, flags: NSEvent.ModifierFlags = [],
                   type: NSEvent.EventType = .leftMouseDown) throws -> NSEvent {
            let point = table.convert(CGPoint(x: 80, y: table.rect(ofRow: row).midY), to: nil)
            return try #require(NSEvent.mouseEvent(with: type, location: point, modifierFlags: flags, timestamp: 0,
                windowNumber: 0, context: nil, eventNumber: 0, clickCount: count, pressure: 1))
        }
    }

    @MainActor @Test func anUnownedActionCannotManufactureAClick() {
        let fixture = Fixture()
        fixture.table.activateOriginalClick()
        #expect(fixture.committed.isEmpty)
    }

    @MainActor @Test func theOriginalClickCommitsOnceAfterTrackingChoosesTheRow() throws {
        let fixture = Fixture()
        fixture.table.trackOriginalClick(try fixture.press()) {
            #expect(fixture.committed.isEmpty)
            fixture.table.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
            fixture.table.activateOriginalClick()
            fixture.table.activateOriginalClick()
        }
        #expect(fixture.committed == [1] && fixture.selectedAtCommit == [1])
    }

    @MainActor @Test func endingTrackingRetiresAnUnconsumedOriginalClick() throws {
        let fixture = Fixture()
        fixture.table.trackOriginalClick(try fixture.press()) {}
        fixture.table.activateOriginalClick()
        #expect(fixture.committed.isEmpty)
    }

    @MainActor @Test(arguments: [(1, NSEvent.ModifierFlags.shift), (2, NSEvent.ModifierFlags())])
    func anOrdinaryClickActionIgnoresModifiedAndRepeatedPresses(_ count: Int, _ flags: NSEvent.ModifierFlags) throws {
        let fixture = Fixture()
        fixture.table.trackOriginalClick(try fixture.press(count: count, flags: flags)) {
            fixture.table.activateOriginalClick()
        }
        #expect(fixture.committed.isEmpty)
    }

    @MainActor @Test func ownerRetirementCancelsTheTrackedClick() throws {
        let fixture = Fixture()
        fixture.table.trackOriginalClick(try fixture.press()) {
            fixture.table.retireOriginalClick()
            fixture.table.activateOriginalClick()
        }
        #expect(fixture.committed.isEmpty)
    }

    @MainActor @Test func openingTheContextMenuCancelsTheTrackedClick() throws {
        let fixture = Fixture()
        let context = try fixture.press(type: .rightMouseDown)
        fixture.table.trackOriginalClick(try fixture.press()) {
            _ = fixture.table.menu(for: context)
            fixture.table.activateOriginalClick()
        }
        #expect(fixture.committed.isEmpty)
    }
}
