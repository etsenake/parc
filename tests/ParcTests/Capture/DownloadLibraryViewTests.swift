import AppKit
import Testing
@testable import Parc
@testable import ParcCore
@testable import ParcLibrary

struct DownloadLibraryViewTests {
    @MainActor private final class MarkedEditor: NSTextView {
        override func hasMarkedText() -> Bool { true }
    }

    @MainActor private final class Fixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store: BrowserStore
        let window: NSWindow
        let view: DownloadLibraryView
        let table: DownloadLibraryTable
        let search: NSTextField
        var actions: [(String, DownloadLibraryAction)] = []

        init(files: Bool = true) throws {
            _ = NSApplication.shared
            store = try BrowserStore(directory: directory)
            let profile = try #require(store.state.profiles.first?.id)
            let path = store.independentEngineProfilePath(for: profile)
            if files {
                for (id, name) in [("a", "first.pdf"), ("b", "second.pdf")] {
                    store.recordDownload(Self.record(id, name: name, path: path))
                }
            }
            view = DownloadLibraryView(store: store, ownerValid: { true })
            window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 460, height: 460),
                              styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = view
            view.frame = CGRect(x: 0, y: 0, width: 460, height: 460)
            view.layoutSubtreeIfNeeded()
            table = try #require(Self.descendants(view).compactMap { $0 as? DownloadLibraryTable }.first)
            search = try #require(Self.descendants(view).compactMap { $0 as? NSTextField }.first {
                $0.accessibilityLabel() == "Search Downloads"
            })
            view.onAction = { [weak self] item, action in
                guard let id = item.nativeID else { return false }
                self?.actions.append((id, action))
                return true
            }
        }

        func teardown() {
            view.invalidate()
            store.flushPendingWrites()
            try? FileManager.default.removeItem(at: directory)
        }

        private static func record(_ id: String, name: String, path: String, identity: String? = nil,
                                   open: Bool = true) -> [String: Any] {
            ["id": id, "profilePath": path, "name": name, "status": "completed", "available": true,
             "itemIdentity": identity ?? id + "-current", "canOpen": open, "canCopyFile": true, "canRemove": true,
             "sourceURL": "https://example.test/" + id, "startedAt": id == "a" ? 1_000 : 900]
        }

        func publish(_ id: String = "a", name: String = "first.pdf", identity: String? = nil, open: Bool = true) throws {
            let profile = try #require(store.state.profiles.first?.id)
            store.recordDownload(Self.record(id, name: name, path: store.independentEngineProfilePath(for: profile),
                                             identity: identity, open: open))
            view.setLoading(count: 0, message: nil)
        }

        func select(_ row: Int = 1) {
            table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }

        func filter(_ query: String) {
            search.stringValue = query
            view.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: search))
        }

        func menu(_ title: String) throws -> NSMenuItem {
            let menu = try #require(table.makeMenu?())
            return try #require(menu.items.first { $0.title == title })
        }

        func invoke(_ item: NSMenuItem) throws {
            let action = try #require(item.action)
            _ = NSApplication.shared.sendAction(action, to: item.target, from: item)
        }

        func hasText(_ text: String) -> Bool {
            Self.descendants(view).contains {
                ($0 as? NSTextField)?.stringValue.contains(text) == true && !$0.isHiddenOrHasHiddenAncestor
            }
        }

        func cell(_ row: Int = 1) throws -> NSView {
            try #require(table.view(atColumn: 0, row: row, makeIfNecessary: true))
        }

        func drainStoreDelivery() async {
            await withCheckedContinuation { continuation in
                RunLoop.main.perform(inModes: [.default]) { continuation.resume() }
            }
        }

        func publishProgress(_ bytes: Int) throws {
            let profile = try #require(store.state.profiles.first?.id)
            var update = Self.record("a", name: "first.pdf", path: store.independentEngineProfilePath(for: profile))
            update["status"] = "downloading"
            update["receivedBytes"] = bytes
            update["totalBytes"] = 1_000_000
            update["canPause"] = true
            store.recordDownload(update)
        }

        private static func descendants(_ view: NSView) -> [NSView] {
            view.subviews.flatMap { [$0] + descendants($0) }
        }
    }

    @MainActor @Test func sameIdentityRefreshPreservesTheSelectedRow() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        fixture.select()
        try fixture.publish(name: "renamed.pdf")
        #expect(fixture.table.selectedRowIndexes == IndexSet(integer: 1))
    }

    @MainActor @Test func aReplacementIncarnationClearsTheNativeSelection() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        fixture.select()
        try fixture.publish(identity: "replacement")
        #expect(fixture.table.selectedRowIndexes.isEmpty)
    }

    @MainActor @Test func retainedOpenUsesTheStillCurrentDownload() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        fixture.select()
        let open = try fixture.menu("Open")
        try fixture.publish(name: "renamed.pdf")
        try fixture.invoke(open)
        #expect(fixture.actions.count == 1)
        #expect(fixture.actions.first?.0 == "a" && fixture.actions.first?.1 == .open)
    }

    enum MenuInvalidation: CaseIterable, Sendable { case replacement, selection, search, category }

    @MainActor @Test(arguments: MenuInvalidation.allCases)
    func aStaleItemMenuCannotDispatch(_ reason: MenuInvalidation) throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        fixture.select()
        let open = try fixture.menu("Open")
        switch reason {
        case .replacement: try fixture.publish(identity: "replacement")
        case .selection: fixture.select(2)
        case .search: fixture.filter("first")
        case .category: fixture.view.invalidate()
        }
        try fixture.invoke(open)
        #expect(fixture.actions.isEmpty)
    }

    @MainActor @Test func aBusyOriginalDisablesOpenUntilItsOperationFinishes() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        fixture.select()
        let original = try #require(fixture.store.state.downloads.first { $0.nativeID == "a" })
        fixture.view.setOperation(original, message: "Moving to Trash…")
        #expect(try !fixture.menu("Open").isEnabled)
        fixture.view.setOperation(original, message: nil)
        #expect(try fixture.menu("Open").isEnabled)
    }

    @MainActor @Test func openCapabilityUsesTheOriginalManagerValue() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        try fixture.publish(open: false)
        fixture.select()
        #expect(try !fixture.menu("Open").isEnabled)
    }

    @MainActor @Test func theTableRemainsASingleItemCursor() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        #expect(!fixture.table.allowsMultipleSelection)
    }

    @MainActor @Test func returnConfirmsSelectionWithoutOpeningTheFile() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        fixture.filter("first")
        fixture.table.onConfirmSelection?()
        #expect(fixture.table.selectedRowIndexes == IndexSet(integer: 1))
        #expect(fixture.actions.isEmpty)
    }

    @MainActor @Test func searchReturnPreservesInputMethodComposition() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        let handled = fixture.view.control(fixture.search, textView: MarkedEditor(),
            doCommandBy: #selector(NSResponder.insertNewline(_:)))
        #expect(!handled)
        #expect(fixture.table.selectedRowIndexes.isEmpty)
    }

    @MainActor @Test func searchReturnMovesFocusToTheNativeTable() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        let handled = fixture.view.control(fixture.search, textView: NSTextView(),
            doCommandBy: #selector(NSResponder.insertNewline(_:)))
        #expect(handled)
        #expect(fixture.window.firstResponder === fixture.table)
        #expect(fixture.actions.isEmpty)
    }

    @MainActor @Test func emptySearchResultsCannotManufactureASelection() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        fixture.filter("unmatched")
        fixture.table.onConfirmSelection?()
        #expect(fixture.table.selectedRowIndexes.isEmpty)
        #expect(fixture.hasText("No downloads match this search."))
    }

    @MainActor @Test func aSearchCanMatchTheOriginalSourceURL() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        fixture.filter("example.test/b")
        #expect(fixture.table.numberOfRows == 2)
        fixture.select()
        let open = try fixture.menu("Open")
        try fixture.invoke(open)
        #expect(fixture.actions.first?.0 == "b")
    }

    @MainActor @Test(arguments: [("Hide from Parc", DownloadLibraryAction.remove), ("Move to Trash", .trash)])
    func originalFileCommandsPassThroughToTheOwnedAction(_ title: String, _ action: DownloadLibraryAction) throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        fixture.select()
        let command = try fixture.menu(title)
        #expect(command.isEnabled)
        try fixture.invoke(command)
        #expect(fixture.window.attachedSheet == nil)
        #expect(fixture.actions.first?.0 == "a" && fixture.actions.first?.1 == action)
    }

    @MainActor @Test func theEmptyListCanShowALoadingStatus() throws {
        let fixture = try Fixture(files: false)
        defer { fixture.teardown() }
        fixture.view.setLoading(count: 1, message: nil)
        #expect(fixture.hasText("Loading downloads…"))
    }

    @MainActor @Test func aLoadFailureExposesTheRetryControl() throws {
        let fixture = try Fixture(files: false)
        defer { fixture.teardown() }
        fixture.view.setLoading(count: 0, message: "Try loading again")
        #expect(fixture.hasText("Try loading again"))
    }
    @MainActor @Test func unrelatedTabMetadataLeavesTheVisibleDownloadsCellAndSelectionAlone() async throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        fixture.select()
        let cell = try fixture.cell()
        let tab = fixture.store.open("https://example.test/tab")
        fixture.store.updateTab(tab, title: "Changed tab title")
        await fixture.drainStoreDelivery()
        #expect(try fixture.cell() === cell)
        #expect(fixture.table.selectedRowIndexes == IndexSet(integer: 1))
    }

    @MainActor @Test func aLiveProgressPublicationKeepsTheCellWhileUpdatingItsAccessibilityText() async throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        try fixture.publishProgress(250_000)
        await fixture.drainStoreDelivery()
        fixture.select()
        let cell = try fixture.cell()
        let earlier = cell.accessibilityLabel()
        try fixture.publishProgress(500_000)
        await fixture.drainStoreDelivery()
        #expect(try fixture.cell() === cell)
        #expect(cell.accessibilityLabel() != earlier)
        #expect(fixture.table.selectedRowIndexes == IndexSet(integer: 1))
    }

    @MainActor @Test func theFilesProviderPublishesOnlyTheSelectedOriginalURL() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        fixture.select()
        let url = fixture.directory.appendingPathComponent("first.pdf")
        fixture.view.fileURL = { _ in url }
        let writing = fixture.view.tableView(fixture.table, pasteboardWriterForRow: 1)
        let item = try #require(writing as? NSPasteboardItem)
        #expect(item.string(forType: .fileURL) == url.absoluteString)
    }

    @MainActor @Test func changingSelectionRevokesThePendingFileOffer() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        fixture.select()
        let url = fixture.directory.appendingPathComponent("first.pdf")
        fixture.view.fileURL = { _ in url }
        let writing = fixture.view.tableView(fixture.table, pasteboardWriterForRow: 1)
        let item = try #require(writing as? NSPasteboardItem)
        fixture.select(2)
        #expect(item.string(forType: .fileURL) == nil)
    }

    @MainActor @Test func selectingADownloadRowDoesNotMakeADateHeadingDraggable() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        fixture.select()
        #expect(fixture.view.tableView(fixture.table, pasteboardWriterForRow: 0) == nil)
    }

}

struct DownloadRowPresentationTests {
    private func item(_ status: BrowserDownloadStatus = .completed) -> BrowserDownload {
        var item = BrowserDownload(id: "original", name: "Original Photo.PNG", path: "/owned/Original Photo.PNG",
            receivedBytes: 50, totalBytes: 100, status: status)
        item.sourceURL = "https://source.test/page"
        return item
    }

    @MainActor @Test func theDisplayNameNeverChangesTheOriginalFilePath() {
        let original = item()
        #expect(DownloadRowArtwork.title(for: original) == "original photo.png")
        #expect(original.path == "/owned/Original Photo.PNG")
    }

    @MainActor @Test func theCompletedFileNamesItsKindAndOriginalDomain() {
        #expect(DownloadRowSubtitle.text(for: item()) == "Image from source.test")
    }

    @MainActor @Test func aMovedFileShowsAnEmptyIconAndItsMissingState() {
        var original = item()
        original.fileMissing = true
        #expect(DownloadRowArtwork.kind(for: original) == .emptyFavicon)
        #expect(DownloadRowArtwork.dimsTitle(original))
        #expect(DownloadRowSubtitle.text(for: original) == "File deleted or moved")
    }

    @MainActor @Test func aSecurityReviewUsesTheOriginalWarningAndArtwork() {
        var original = item()
        original.requiresReview = true
        original.statusText = "Review this transfer"
        #expect(DownloadRowArtwork.kind(for: original) == .security)
        #expect(DownloadRowSubtitle.text(for: original) == "Review this transfer")
    }

    @MainActor @Test func openingWhenFinishedDisplaysTheLivePercentage() {
        var original = item(.downloading)
        original.openWhenComplete = true
        #expect(DownloadRowSubtitle.text(for: original) == "Opening… (50%)")
    }
}

struct DownloadFileActivationTests {
    @Test(arguments: [("image.png", true), ("paper.pdf", true), ("video.mov", true), ("file.zip", false), ("notes.txt", false)])
    func onlyReadableMediaAndPDFsOpenInTheInlinePreview(_ name: String, _ shouldPreview: Bool) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent(name)
        try Data([0]).write(to: file)
        #expect(DownloadFileActivation.inspect(file) == (shouldPreview ? .preview : .open))
    }

    @Test func aMissingPreviewableFileCannotOpen() {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        #expect(DownloadFileActivation.inspect(file) == .unavailable)
    }

    @Test func aRemoteAddressIsNeverAnInlineFile() {
        #expect(DownloadFileActivation.inspect(URL(string: "https://example.test/image.png")!) == .unavailable)
    }
}
