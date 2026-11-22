import AppKit
import Testing
@testable import Parc
@testable import ParcCore

struct LibraryArchiveRowsTests {
    @MainActor private final class KeyedWindow: NSWindow {
        var key = true
        var pointer = NSPoint.zero
        override var isKeyWindow: Bool { key }
        override var mouseLocationOutsideOfEventStream: NSPoint { pointer }
    }

    @MainActor private final class Ticker {
        var now = Date(timeIntervalSince1970: 1_900_000_000)
    }

    @MainActor private final class Fixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let ticker = Ticker()
        let store: BrowserStore
        let profile: UUID
        let space: UUID
        let groupA: UUID
        let groupB: UUID
        let other: UUID
        let view: LibraryView
        let window: KeyedWindow
        let table: NSTableView
        var owner = true
        var restored: [([UUID], UUID?)] = []

        init(hover: Bool = false) throws {
            _ = NSApplication.shared
            let ticker = ticker
            store = try BrowserStore(directory: directory, now: { ticker.now })
            profile = store.activeSpace.profileID
            space = store.activeSpaceID
            groupA = store.open("https://group-a.example.invalid")
            groupB = store.open("https://group-b.example.invalid")
            store.setSplit([groupA, groupB])
            store.closeTabs([groupA, groupB])
            ticker.now.addTimeInterval(1)
            other = store.open("https://other.example.invalid")
            store.closeTabs([other])
            if hover {
                let tab = store.open("https://hover-only.example.invalid")
                store.closeTabs([tab])
            }
            view = LibraryView(store: store, kind: .archive, profileID: profile, reduceMotion: { true })
            view.frame = NSRect(x: 0, y: 0, width: 416, height: 600)
            window = KeyedWindow(contentRect: view.frame, styleMask: .titled, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = view
            view.layoutSubtreeIfNeeded()
            table = try #require(Self.descendants(view).compactMap { $0 as? NSTableView }.first)
            view.onRestore = { [weak self] ids, space in self?.restored.append((ids, space)) }
            view.archiveOwnerValid = { [weak self] in self?.owner == true }
        }

        func teardown() {
            window.contentView = nil
            store.flushPendingWrites()
            try? FileManager.default.removeItem(at: directory)
        }

        static func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }

        func row(_ title: String) throws -> Int {
            try #require((0..<table.numberOfRows).first { row in
                guard let cell = table.view(atColumn: 0, row: row, makeIfNecessary: true) else { return false }
                return Self.descendants(cell).compactMap { $0 as? NSTextField }.contains { $0.stringValue.contains(title) }
            })
        }

        func menu(_ row: Int, in target: NSTableView? = nil, window: NSWindow? = nil) throws -> NSMenu {
            let table = target ?? self.table
            let point = table.convert(NSPoint(x: 20, y: table.rect(ofRow: row).midY), to: nil)
            let event = try #require(NSEvent.mouseEvent(with: .rightMouseDown, location: point, modifierFlags: [], timestamp: 0,
                windowNumber: (window ?? self.window).windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
            return try #require(table.menu(for: event))
        }

        func invoke(_ item: NSMenuItem) {
            _ = NSApplication.shared.sendAction(item.action!, to: item.target, from: item)
        }

        func key(_ code: UInt16, _ flags: NSEvent.ModifierFlags = []) {
            let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
                windowNumber: window.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "",
                isARepeat: false, keyCode: code)!
            table.keyDown(with: event)
        }

        func sortedRows() throws -> [Int] { [try row("group-a.example.invalid"), try row("other.example.invalid")].sorted() }

        func drain() async {
            await withCheckedContinuation { continuation in RunLoop.main.perform(inModes: [.default]) { continuation.resume() } }
        }
    }

    @MainActor @Test func theArchiveTableHasOneCursor() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        #expect(!fixture.table.allowsMultipleSelection)
    }

    @MainActor @Test func upFromNoCursorSelectsTheFirstArchivedItem() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        fixture.table.deselectAll(nil)
        fixture.key(126)
        #expect(fixture.table.selectedRowIndexes == IndexSet(integer: try fixture.sortedRows()[0]))
    }

    @MainActor @Test func shiftDownMovesTheSingleArchiveCursor() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        fixture.table.deselectAll(nil)
        fixture.key(126)
        fixture.key(125, [.shift, .function])
        #expect(fixture.table.selectedRowIndexes == IndexSet(integer: try fixture.sortedRows()[1]))
    }

    @MainActor @Test func theArchiveCursorStopsAtTheLastItem() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        fixture.table.deselectAll(nil)
        fixture.key(126)
        fixture.key(125)
        fixture.key(125)
        #expect(fixture.table.selectedRowIndexes == IndexSet(integer: try fixture.sortedRows()[1]))
    }

    @MainActor @Test func theArchiveCursorStopsAtTheFirstItem() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        fixture.table.deselectAll(nil)
        fixture.key(126)
        fixture.key(125)
        fixture.key(126, .shift)
        fixture.key(126)
        #expect(fixture.table.selectedRowIndexes == IndexSet(integer: try fixture.sortedRows()[0]))
    }

    @MainActor @Test func selectAllCannotCreateAPluralArchiveSelection() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        fixture.table.deselectAll(nil)
        fixture.key(126)
        fixture.table.selectAll(nil)
        let command = NSMenuItem(title: "Select All", action: #selector(NSTableView.selectAll(_:)), keyEquivalent: "a")
        #expect(fixture.table.selectedRowIndexes == IndexSet(integer: try fixture.sortedRows()[0]))
        #expect(!fixture.table.validateUserInterfaceItem(command))
    }

    @MainActor @Test func returningToTheArchiveRestoresSingleSelection() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        fixture.view.show(.archive)
        #expect(!fixture.table.allowsMultipleSelection)
    }

    @MainActor @Test func anArchiveRowOffersItsDirectActionsThenClearArchive() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        let menu = try fixture.menu(try fixture.row("group-a.example.invalid"))
        #expect(menu.items.map(\.title) == ["Restore", "Delete", "", "Clear Archive…"])
    }

    @MainActor @Test func openingARowMenuPreservesTheIndependentSelection() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        let other = try fixture.row("other.example.invalid")
        fixture.table.selectRowIndexes(IndexSet(integer: other), byExtendingSelection: false)
        _ = try fixture.menu(try fixture.row("group-a.example.invalid"))
        #expect(fixture.table.selectedRowIndexes == IndexSet(integer: other))
    }

    @MainActor @Test func restoreDispatchesTheInvokedGroupedRowAndItsPreviousSpace() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        let menu = try fixture.menu(try fixture.row("group-a.example.invalid"))
        fixture.invoke(menu.items[0])
        #expect(fixture.restored.count == 1 && fixture.restored[0].0 == [fixture.groupA] && fixture.restored[0].1 == fixture.space)
    }

    @MainActor @Test func aRetiredWindowOrProfileOwnerRefusesBothRetainedActions() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        let menu = try fixture.menu(try fixture.row("group-a.example.invalid"))
        fixture.owner = false
        fixture.invoke(menu.items[0])
        fixture.invoke(menu.items[1])
        #expect(fixture.restored.isEmpty && fixture.store.archivedItems(profileID: fixture.profile).count == 2)
    }

    @MainActor @Test func leavingAndReturningToTheArchivePermanentlyRefusesARetainedAction() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        let menu = try fixture.menu(try fixture.row("group-a.example.invalid"))
        fixture.view.show(.downloads)
        fixture.view.show(.archive)
        fixture.invoke(menu.items[1])
        #expect(fixture.store.archivedItems(profileID: fixture.profile).count == 2)
    }

    @MainActor @Test func movingTheViewToAnotherPhysicalWindowRefusesTheOldMenuForever() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        let menu = try fixture.menu(try fixture.row("group-a.example.invalid"))
        fixture.window.contentView = nil
        let next = NSWindow(contentRect: fixture.view.frame, styleMask: .titled, backing: .buffered, defer: false)
        next.isReleasedWhenClosed = false
        next.contentView = fixture.view
        fixture.invoke(menu.items[1])
        next.contentView = nil
        fixture.window.contentView = fixture.view
        fixture.view.layoutSubtreeIfNeeded()
        fixture.invoke(menu.items[1])
        #expect(fixture.store.archivedItems(profileID: fixture.profile).count == 2)
    }

    @MainActor @Test func aChangedGroupCannotDeleteItsSurvivingMember() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        let menu = try fixture.menu(try fixture.row("group-a.example.invalid"))
        fixture.store.deleteArchivedTabs([fixture.groupB], profileID: fixture.profile)
        fixture.invoke(menu.items[1])
        #expect(fixture.store.state.tabs.contains { $0.id == fixture.groupA && $0.archivedAt != nil })
    }

    @MainActor @Test func aRearchivedReplacementWithTheSameIDAndTimestampSurvivesTheOldAction() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        let menu = try fixture.menu(try fixture.row("other.example.invalid"))
        _ = fixture.store.restoreArchivedTab(fixture.other, profileID: fixture.profile,
                                             destination: .previousSpace(fallbackSpaceID: fixture.space))
        fixture.store.closeTabs([fixture.other])
        fixture.invoke(menu.items[1])
        #expect(fixture.store.state.tabs.contains { $0.id == fixture.other && $0.archivedAt == fixture.ticker.now })
    }

    @MainActor @Test func deleteRemovesTheWholeOriginalGroupDirectlyWithoutAConfirmationSheet() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        let menu = try fixture.menu(try fixture.row("group-a.example.invalid"))
        fixture.store.deleteArchivedTabs([fixture.other], profileID: fixture.profile)
        fixture.invoke(menu.items[1])
        #expect(fixture.window.attachedSheet == nil && fixture.store.archivedItems(profileID: fixture.profile).isEmpty)
    }

    @MainActor private func hovering() throws -> (Fixture, Int, BrowserArchivedItem) {
        let fixture = try Fixture(hover: true)
        let row = try fixture.row("hover-only.example.invalid")
        let item = try #require(fixture.store.archivedItems(profileID: fixture.profile).first {
            $0.urls.contains("https://hover-only.example.invalid")
        })
        return (fixture, row, item)
    }

    @MainActor private func hover(_ fixture: Fixture, _ row: Int) {
        let rect = fixture.table.rect(ofRow: row)
        fixture.window.pointer = fixture.table.convert(NSPoint(x: rect.midX, y: rect.midY), to: nil)
        let event = NSEvent.mouseEvent(with: .mouseMoved, location: fixture.window.pointer, modifierFlags: [], timestamp: 0,
            windowNumber: fixture.window.windowNumber, context: nil, eventNumber: 2, clickCount: 0, pressure: 0)!
        fixture.table.mouseMoved(with: event)
    }

    @MainActor private func shown(_ fixture: Fixture, _ row: Int) throws -> [NSButton] {
        let cell = try #require(fixture.table.view(atColumn: 0, row: row, makeIfNecessary: true))
        return Fixture.descendants(cell).compactMap { $0 as? NSButton }.filter { !$0.isHidden }
    }

    @MainActor @Test func voiceOverReachesPutBackAndDeleteWithoutHovering() throws {
        let (fixture, row, _) = try hovering()
        defer { fixture.teardown() }
        let cell = try #require(fixture.table.view(atColumn: 0, row: row, makeIfNecessary: true))
        #expect(cell.accessibilityCustomActions()?.map(\.name) == ["Put Back", "Delete"])
    }

    @MainActor @Test func hoveringALiveArchiveRowShowsTrashAndPutBack() throws {
        let (fixture, row, _) = try hovering()
        defer { fixture.teardown() }
        hover(fixture, row)
        #expect(Set(try shown(fixture, row).compactMap { $0.accessibilityLabel() }) == ["Delete", "Put Back"])
    }

    @MainActor @Test func aHeadingShowsNeitherTrashNorPutBack() throws {
        let (fixture, _, _) = try hovering()
        defer { fixture.teardown() }
        let heading = try #require((0..<fixture.table.numberOfRows).first { fixture.view.tableView(fixture.table, isGroupRow: $0) })
        hover(fixture, heading)
        #expect(try shown(fixture, heading).isEmpty)
    }

    @MainActor @Test func putBackDoesNothingWhenThisWindowNoLongerOwnsTheArchive() throws {
        let (fixture, row, item) = try hovering()
        defer { fixture.teardown() }
        hover(fixture, row)
        fixture.owner = false
        try #require(shown(fixture, row).first { $0.accessibilityLabel() == "Put Back" }).sendClick()
        #expect(!fixture.restored.contains { $0.0 == [item.id] })
    }

    @MainActor @Test func putBackRecordsTheLiveArchivedItemAndItsSpace() throws {
        let (fixture, row, item) = try hovering()
        defer { fixture.teardown() }
        hover(fixture, row)
        try #require(shown(fixture, row).first { $0.accessibilityLabel() == "Put Back" }).sendClick()
        #expect(fixture.restored.contains { $0.0 == [item.id] && $0.1 == fixture.space })
    }

    @MainActor @Test func trashRemovesThatLiveArchiveRecord() throws {
        let (fixture, row, item) = try hovering()
        defer { fixture.teardown() }
        hover(fixture, row)
        try #require(shown(fixture, row).first { $0.accessibilityLabel() == "Delete" }).sendClick()
        #expect(!fixture.store.archivedItems(profileID: fixture.profile).contains { $0.id == item.id })
    }

    @MainActor @Test func unrelatedLiveTabTitlesDoNotRebuildTheArchiveRows() async throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        let rows = fixture.table.numberOfRows
        let first = try #require(fixture.table.view(atColumn: 0, row: try fixture.row("group-a.example.invalid"), makeIfNecessary: true))
        let tab = fixture.store.open("https://fingerprint-live.example.invalid")
        fixture.store.updateTab(tab, title: "Unrelated archive live title")
        await fixture.drain()
        #expect(fixture.table.numberOfRows == rows)
        #expect(fixture.table.view(atColumn: 0, row: try fixture.row("group-a.example.invalid"), makeIfNecessary: true) === first)
    }

    @MainActor @Test func unrelatedLiveTabAddressPublishesDoNotRebuildTheArchiveRows() async throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        let first = try #require(fixture.table.view(atColumn: 0, row: try fixture.row("group-a.example.invalid"), makeIfNecessary: true))
        let tab = fixture.store.open("https://fingerprint-live.example.invalid")
        fixture.store.updateTab(tab, url: "https://fingerprint-live-url.example.invalid")
        await fixture.drain()
        #expect(fixture.table.view(atColumn: 0, row: try fixture.row("group-a.example.invalid"), makeIfNecessary: true) === first)
    }

    @MainActor @Test func aNewlyArchivedTabStillReloadsTheArchiveCatalog() async throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        fixture.ticker.now.addTimeInterval(1)
        let fresh = fixture.store.open("https://fingerprint-fresh.example.invalid")
        fixture.store.closeTabs([fresh])
        await fixture.drain()
        #expect(try fixture.row("fingerprint-fresh.example.invalid") >= 0)
    }
}
