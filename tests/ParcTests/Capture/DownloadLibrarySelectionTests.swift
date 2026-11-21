import AppKit
import Testing
@testable import Parc
@testable import ParcCore

struct DownloadLibrarySelectionTests {
    private let profile = UUID()

    private func item(_ name: String, identity: String? = "original") -> BrowserDownload {
        var item = BrowserDownload(id: name, name: name, path: "", receivedBytes: 10, totalBytes: 10, status: .completed)
        item.profileID = profile
        item.nativeID = name
        item.nativeIdentity = identity
        item.canOpen = true
        item.canRemove = true
        item.canCopyFile = true
        item.canToggleOpen = true
        item.sourceURL = "https://example.test/" + name
        return item
    }

    private func state(_ downloads: [BrowserDownload]) -> BrowserState {
        BrowserState(profiles: [BrowserProfile(id: profile, name: "Work")], spaces: [], activeSpaceID: UUID(), downloads: downloads)
    }

    @Test func anOriginalSelectionIsRestoredAcrossDateHeadings() {
        let first = item("first")
        let next = item("second")
        #expect(DownloadLibrarySelection.retainedRows([first], in: [nil, first, nil, next]) == IndexSet(integer: 1))
    }

    @Test func aPluralSelectionCannotBecomeAnOptionalSingleSelection() {
        let first = item("first"), second = item("second")
        #expect(DownloadLibrarySelection.retainedRows([first, second], in: [first, second]).isEmpty)
    }

    @Test func progressAndNameUpdatesPreserveSelection() {
        let first = item("first")
        var update = first
        update.receivedBytes += 1
        update.name = "New name"
        #expect(DownloadLibrarySelection.retainedRows([first], in: [update]) == IndexSet(integer: 0))
    }

    enum IdentityChange: CaseIterable, Sendable { case incarnation, managerID, profile, privateContext }

    @Test(arguments: IdentityChange.allCases)
    func anIdentityChangeCannotInheritTheOriginalSelection(_ change: IdentityChange) {
        let first = item("first")
        var replacement = first
        switch change {
        case .incarnation: replacement.nativeIdentity = "replacement"
        case .managerID: replacement.nativeID = "another-manager-ID"
        case .profile: replacement.profileID = UUID()
        case .privateContext: replacement.privateContextID = "another-context"
        }
        #expect(DownloadLibrarySelection.retainedRows([first], in: [replacement]).isEmpty)
    }

    @Test func restoredMetadataCannotSelectTheNewLiveTransfer() {
        let restored = item("first", identity: nil)
        #expect(DownloadLibrarySelection.retainedRows([restored], in: [item("first")]).isEmpty)
    }

    @Test func liveFileCapabilitiesRequireAManagerIncarnation() {
        let restored = item("first", identity: nil)
        #expect(DownloadLibrarySelection.resolve([restored], for: .open, in: state([restored])) == nil)
    }

    @Test func theOriginalEntryCanStillOpen() {
        let first = item("first")
        #expect(DownloadLibrarySelection.resolve([first], for: .open, in: state([first]))?.map(\.id) == [first.id])
    }

    @Test(arguments: [DownloadLibraryAction.open, .copyLink, .toggleOpen, .review, .remove, .trash])
    func theSingleItemMenuNeverDispatchesMultipleDownloads(_ action: DownloadLibraryAction) {
        var first = item("first"), second = item("second")
        first.canReview = true
        second.canReview = true
        #expect(DownloadLibrarySelection.resolve([first, second], for: action, in: state([first, second])) == nil)
    }

    @Test func aMissingOriginalCannotAcceptItsConfirmation() {
        let first = item("first")
        #expect(DownloadLibrarySelection.resolve([first], for: .remove, in: state([item("second")])) == nil)
    }

    @Test func aReplacementCannotAcceptAnOriginalConfirmation() {
        let first = item("first")
        let replacement = item("first", identity: "replacement")
        #expect(DownloadLibrarySelection.resolve([first], for: .remove, in: state([replacement])) == nil)
    }

    @Test func aDuplicateSnapshotCannotResolveTwice() {
        let first = item("first")
        #expect(DownloadLibrarySelection.resolve([first, first], in: [first], profiles: [profile]) == nil)
    }

    @Test func retiringTheProfileRevokesFileCommands() {
        let first = item("first")
        var state = state([first])
        state.profiles = []
        #expect(DownloadLibrarySelection.resolve([first], for: .copyFile, in: state) == nil)
    }

    @Test func copyingALinkKeepsTheOriginalSourceURL() {
        let first = item("first")
        var changed = first
        changed.sourceURL = "https://example.test/replacement"
        #expect(DownloadLibrarySelection.resolve([first], for: .copyLink, in: state([changed])) == nil)
    }

    @Test func aStaleUncheckedMenuCannotInvertTheChangedPrompt() {
        let first = item("first")
        var changed = first
        changed.openWhenComplete = true
        #expect(DownloadLibrarySelection.resolve([first], for: .toggleOpen, in: state([changed])) == nil)
    }

    @Test func trashRequiresTheCurrentFileToBeAccessible() {
        var first = item("first")
        first.canCopyFile = false
        #expect(DownloadLibrarySelection.resolve([first], for: .trash, in: state([first])) == nil)
    }

    @Test func aRealReviewCapabilityRemainsAvailable() {
        var first = item("first")
        first.canReview = true
        #expect(DownloadLibrarySelection.resolve([first], for: .review, in: state([first]))?.first?.canReview == true)
    }
}

struct DownloadLibraryTableKeyboardTests {
    @MainActor private final class Rows: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        let selectableRows = IndexSet([1, 3])
        func numberOfRows(in tableView: NSTableView) -> Int { 4 }
        func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { selectableRows.contains(row) }
        func tableView(_ tableView: NSTableView, selectionIndexesForProposedSelection rows: IndexSet) -> IndexSet {
            rows.intersection(selectableRows)
        }
    }

    @MainActor private final class Fixture {
        let table = DownloadLibraryTable(frame: CGRect(x: 0, y: 0, width: 300, height: 300))
        private let rows = Rows()
        var actions: [String] = []

        init() {
            table.addTableColumn(NSTableColumn(identifier: .init("download")))
            table.delegate = rows
            table.dataSource = rows
            table.allowsMultipleSelection = false
            table.allowsEmptySelection = true
            table.reloadData()
            table.onConfirmSelection = { [weak self] in self?.actions.append("confirm") }
            table.onPreview = { [weak self] in self?.actions.append("preview") }
            table.onCopy = { [weak self] in self?.actions.append("copy") }
            table.onDelete = { [weak self] in self?.actions.append("delete") }
            table.onSearch = { [weak self] in self?.actions.append("search") }
            table.onClose = { [weak self] in self?.actions.append("close") }
            table.onMove = { [weak self] forward in
                guard let self, let next = DownloadLibrarySelection.nextRow(
                    in: rows.selectableRows, selected: table.selectedRowIndexes, forward: forward) else { return }
                select(next)
            }
        }

        func select(_ row: Int) {
            table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }

        func key(_ code: UInt16, _ characters: String, flags: NSEvent.ModifierFlags = []) throws {
            let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags,
                timestamp: 0, windowNumber: 0, context: nil, characters: characters,
                charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code))
            table.keyDown(with: event)
        }
    }

    @MainActor @Test(arguments: [
        (nil as Int?, UInt16(126), 1),
        (1, 125, 3), (3, 125, 3), (3, 126, 1), (1, 126, 1),
    ])
    func arrowNavigationSkipsHeadingsAndStopsAtTheEdges(_ before: Int?, _ code: UInt16, _ after: Int) throws {
        let fixture = Fixture()
        if let before { fixture.select(before) }
        try fixture.key(code, code == 125 ? "\u{f701}" : "\u{f700}")
        #expect(fixture.table.selectedRowIndexes == IndexSet(integer: after))
    }

    @MainActor @Test(arguments: [(1, UInt16(125), 3), (3, UInt16(126), 1)])
    func shiftArrowMovesWithoutExtendingTheSelection(_ before: Int, _ code: UInt16, _ after: Int) throws {
        let fixture = Fixture()
        fixture.select(before)
        try fixture.key(code, code == 125 ? "\u{f701}" : "\u{f700}", flags: .shift)
        #expect(fixture.table.selectedRowIndexes == IndexSet(integer: after))
    }

    struct Shortcut: Sendable {
        let code: UInt16
        let characters: String
        let flags: NSEvent.ModifierFlags
        let action: String?

        init(_ code: UInt16, _ characters: String, _ flags: NSEvent.ModifierFlags = [], _ action: String? = nil) {
            self.code = code
            self.characters = characters
            self.flags = flags
            self.action = action
        }

        static let samples = [
            Shortcut(36, "\r", [], "confirm"), Shortcut(76, "\r", [], "confirm"),
            Shortcut(49, " ", [], "preview"), Shortcut(8, "c", .command, "copy"),
            Shortcut(3, "f", .command, "search"), Shortcut(51, "\u{7f}", [], "delete"),
            Shortcut(53, "\u{1b}", [], "close"), Shortcut(36, "\r", .command),
            Shortcut(49, " ", .option), Shortcut(51, "\u{7f}", .command),
        ]
    }

    @MainActor @Test(arguments: Shortcut.samples)
    func eachShortcutDispatchesOnlyItsOwnAction(_ shortcut: Shortcut) throws {
        let fixture = Fixture()
        fixture.select(1)
        try fixture.key(shortcut.code, shortcut.characters, flags: shortcut.flags)
        #expect(fixture.actions == (shortcut.action.map { [$0] } ?? []))
        #expect(fixture.table.selectedRowIndexes == IndexSet(integer: 1))
    }

    @MainActor @Test(arguments: [false, true])
    func responderCopyTracksCurrentSelectionCapability(_ allowed: Bool) {
        let fixture = Fixture()
        let copy = NSMenuItem(title: "Copy", action: #selector(DownloadLibraryTable.copy(_:)), keyEquivalent: "c")
        fixture.table.canCopy = { allowed }
        #expect(fixture.table.validateUserInterfaceItem(copy) == allowed)
    }

    @MainActor @Test func commandALeavesTheOneSelectedItemAlone() throws {
        let fixture = Fixture()
        fixture.select(1)
        try fixture.key(0, "a", flags: .command)
        #expect(fixture.table.selectedRowIndexes == IndexSet(integer: 1))
    }

    @MainActor @Test func selectAllIsUnavailableInTheResponderMenu() {
        let fixture = Fixture()
        let selectAll = NSMenuItem(title: "Select All", action: #selector(NSTableView.selectAll(_:)), keyEquivalent: "a")
        #expect(!fixture.table.validateUserInterfaceItem(selectAll))
    }
}
