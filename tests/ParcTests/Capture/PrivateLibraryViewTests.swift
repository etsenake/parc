import AppKit
import Testing
@testable import Parc
@testable import ParcCore

struct PrivateLibraryViewTests {
    @MainActor private final class Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store: BrowserStore
        let profile: UUID
        let path: String
        let privateDirectory: URL
        let privateStore: BrowserStore
        let privateID: UUID
        var record: [String: Any]

        init() throws {
            _ = NSApplication.shared
            store = try BrowserStore(directory: root.appendingPathComponent("regular", isDirectory: true))
            profile = store.state.profiles[0].id
            path = store.independentEngineProfilePath(for: profile)
            privateDirectory = root.appendingPathComponent("never-created-private", isDirectory: true)
            privateStore = BrowserStore(privateParentProfileID: profile, engineProfilePath: path, directory: privateDirectory,
                                        settings: store.state.settings)
            privateID = privateStore.activeSpace.profileID
            record = ["id": "private-original", "profilePath": path, "offTheRecord": true, "name": "Private fixture.pdf",
                      "path": "/not-opened/private.pdf", "status": "completed", "available": true, "itemIdentity": "private-lease-1",
                      "canOpen": true, "canCopyFile": true, "canRemove": true, "startedAt": 1000]
        }

        func teardown() {
            store.flushPendingWrites()
            try? FileManager.default.removeItem(at: root)
        }

        static func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
    }

    @MainActor @Test func theRegularCatalogRejectsOffTheRecordPublication() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        fixture.store.recordDownload(fixture.record)
        #expect(!fixture.store.state.downloads.contains { $0.nativeID == "private-original" })
    }

    @MainActor @Test func thePrivateEndpointCannotPopulateARegularStore() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        fixture.store.recordPrivateDownload(fixture.record)
        #expect(!fixture.store.state.downloads.contains { $0.nativeID == "private-original" })
    }

    @MainActor @Test func originalPrivateManagerDataIsNamespacedToTheMemoryOnlyWindowProfile() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        fixture.privateStore.recordPrivateDownload(fixture.record)
        #expect(fixture.privateStore.state.downloads.count == 1 && fixture.privateStore.state.downloads[0].profileID == fixture.privateID)
    }

    @MainActor @Test func privatePublicationRefusesADifferentOriginalParentPath() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        fixture.privateStore.recordPrivateDownload(fixture.record)
        var foreign = fixture.record
        foreign["profilePath"] = fixture.path + "-other"
        foreign["id"] = "foreign"
        fixture.privateStore.recordPrivateDownload(foreign)
        #expect(fixture.privateStore.state.downloads.count == 1)
    }

    @MainActor @Test func thePrivateEndpointRefusesNormalManagerData() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        fixture.privateStore.recordPrivateDownload(fixture.record)
        var regular = fixture.record
        regular["offTheRecord"] = false
        regular["id"] = "regular"
        fixture.privateStore.recordPrivateDownload(regular)
        #expect(fixture.privateStore.state.downloads.count == 1)
    }

    @MainActor private func privateRail(_ fixture: Fixture) -> (LibraryView, NSWindow) {
        fixture.privateStore.recordPrivateDownload(fixture.record)
        let rail = LibraryView(store: fixture.privateStore, kind: .documents, profileID: fixture.privateID,
                               spaceManager: SpaceManagerView(frame: .zero), files: IsolatedNoteFiles.make(), reduceMotion: { true })
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 512, height: 590), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = rail
        rail.palette = ThemeChromePalette(theme: SpaceTheme(), isDark: true)
        rail.layoutSubtreeIfNeeded()
        return (rail, window)
    }

    @MainActor @Test func thePrivateRailNeverInstantiatesPersistentMediaOrDocumentCatalogs() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        let (rail, window) = privateRail(fixture)
        defer { window.contentView = nil }
        #expect(!Fixture.descendants(rail).contains { $0 is CaptureLibraryView || $0 is DocumentsLibraryView })
    }

    @MainActor @Test func theOriginalDownloadsEntryStaysVisibleInThePrivateRailWhileOtherCategoriesStayHidden() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        let (rail, window) = privateRail(fixture)
        defer { window.contentView = nil }
        let buttons = Fixture.descendants(rail).compactMap { $0 as? NSButton }
        #expect(buttons.first { $0.title == "Downloads" }?.isHidden == false)
        #expect(buttons.filter { ["Media", "Easels & Notes", "Archived Tabs", "Spaces"].contains($0.title) }.allSatisfy { $0.isHidden })
    }

    @MainActor private func openMenu(_ rail: LibraryView, _ title: String) throws -> (DownloadLibraryTable, NSMenuItem) {
        let table = try #require(Fixture.descendants(rail).compactMap { $0 as? DownloadLibraryTable }.first)
        table.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
        return (table, try #require(table.makeMenu?()?.items.first { $0.title == title }))
    }

    @MainActor @Test func aPrivateLibraryActionPreservesTheOriginalMemoryProfileAndItem() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        let (rail, window) = privateRail(fixture)
        defer { window.contentView = nil }
        var actions: [DownloadLibraryIdentity] = []
        rail.onDownloadAction = { item, _ in actions.append(DownloadLibraryIdentity(item)); return true }
        let (_, open) = try openMenu(rail, "Open")
        _ = NSApplication.shared.sendAction(open.action!, to: open.target, from: open)
        #expect(actions.count == 1 && actions[0].profile == fixture.privateID)
    }

    @MainActor @Test func destroyingThePrivateContextExpiresTheRetainedActionOfferAndSelection() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        let (rail, window) = privateRail(fixture)
        defer { window.contentView = nil }
        var actions = 0
        rail.onDownloadAction = { _, _ in actions += 1; return true }
        rail.downloadFileURL = { _ in fixture.privateDirectory.appendingPathComponent("private.pdf") }
        let (table, open) = try openMenu(rail, "Open")
        let view = try #require(Fixture.descendants(rail).compactMap { $0 as? DownloadLibraryView }.first)
        let drag = try #require(view.tableView(table, pasteboardWriterForRow: 1) as? NSPasteboardItem)
        fixture.privateStore.clearPrivateDownloads()
        rail.setDownloadsLoading(count: 0, message: nil)
        _ = NSApplication.shared.sendAction(open.action!, to: open.target, from: open)
        #expect(actions == 0 && drag.string(forType: .fileURL) == nil && table.selectedRowIndexes.isEmpty)
    }

    @MainActor @Test func privateHideDispatchesDirectlyThroughItsOriginalManager() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        let (rail, window) = privateRail(fixture)
        defer { window.contentView = nil }
        var actions: [DownloadLibraryIdentity] = []
        rail.onDownloadAction = { item, _ in actions.append(DownloadLibraryIdentity(item)); return true }
        let (_, hide) = try openMenu(rail, "Hide from Parc")
        _ = NSApplication.shared.sendAction(hide.action!, to: hide.target, from: hide)
        #expect(window.attachedSheet == nil && actions.last?.guid == "private-original")
    }

    @MainActor @Test func privateRowsLayoutAndSaveCreateNoPersistentDirectories() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        let (_, window) = privateRail(fixture)
        window.contentView = nil
        fixture.privateStore.clearPrivateDownloads()
        try fixture.privateStore.save()
        #expect(window.attachedSheet == nil && !FileManager.default.fileExists(atPath: fixture.privateDirectory.path))
    }

    @MainActor @Test func privateTeardownCannotClearTheOrdinaryCatalogOrLeakRows() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        fixture.store.recordDownload(["id": "ordinary", "profilePath": fixture.path, "name": "ordinary", "status": "completed",
            "available": true, "itemIdentity": "ordinary", "startedAt": 1000])
        let (_, window) = privateRail(fixture)
        window.contentView = nil
        let count = fixture.store.state.downloads.count
        fixture.store.clearPrivateDownloads()
        #expect(fixture.store.state.downloads.count == count)
        #expect(!fixture.store.state.downloads.contains { $0.nativeID == "private-original" })
    }

    @MainActor private final class Merged {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store: BrowserStore
        let profile: UUID
        let path: String
        var record: [String: Any]

        init() throws {
            _ = NSApplication.shared
            store = try BrowserStore(directory: root.appendingPathComponent("merged", isDirectory: true))
            profile = store.activeSpace.profileID
            path = store.independentEngineProfilePath(for: profile)
            record = ["id": "same-guid", "profilePath": path, "offTheRecord": false, "name": "Ordinary fixture.pdf",
                      "path": "/not-opened/ordinary.pdf", "status": "completed", "available": true,
                      "itemIdentity": "same-incarnation", "canOpen": true, "canCopyFile": true, "canRemove": true, "startedAt": 1000]
            store.recordDownload(record)
            record["offTheRecord"] = true
            record["name"] = "Alpha private fixture.pdf"
            record["path"] = "/not-opened/secret-alpha.pdf"
            record["sourceURL"] = "https://example.invalid/private-secret"
            store.recordTransientDownload(record, contextID: "alpha")
            record["name"] = "Beta private fixture.pdf"
            store.recordTransientDownload(record, contextID: "beta")
        }

        func teardown() {
            store.flushPendingWrites()
            try? FileManager.default.removeItem(at: root)
        }
    }

    @MainActor @Test func theSharedProjectionMergesNormalAndBothOriginalOffTheRecordContextsWithoutDurableInsertion() throws {
        let merged = try Merged()
        defer { merged.teardown() }
        #expect(merged.store.downloadItems.count == 3 && merged.store.state.downloads.count == 1)
        #expect(Set(merged.store.downloadItems.map(\.id)).count == 3)
    }

    @MainActor @Test func theDurableStateContainsNoPrivateAddressPathOrTitle() throws {
        let merged = try Merged()
        defer { merged.teardown() }
        let text = String(decoding: try JSONEncoder().encode(merged.store.state), as: UTF8.self)
        #expect(!text.contains("private-secret") && !text.contains("secret-alpha") && !text.contains("Alpha private"))
    }

    @MainActor @Test func reopeningTheRealStoreKeepsOnlyOrdinaryManagerHistory() throws {
        let merged = try Merged()
        defer { merged.teardown() }
        try merged.store.save()
        let reopened = try BrowserStore(directory: merged.root.appendingPathComponent("merged", isDirectory: true))
        #expect(reopened.downloadItems.count == 1 && reopened.transientDownloads.isEmpty)
    }

    @MainActor @Test func authoritativePrivateReconciliationRemovesOnlyThatManagersTransientRecords() throws {
        let merged = try Merged()
        defer { merged.teardown() }
        merged.store.retireTransientDownloads(contextID: "alpha")
        merged.store.reconcileTransientDownloads(contextID: "beta", nativeIDs: [])
        #expect(merged.store.transientDownloads.isEmpty && merged.store.state.downloads.count == 1)
    }

    @MainActor @Test func aManagerRemovalWithdrawsTheOriginalPrivateRow() throws {
        let merged = try Merged()
        defer { merged.teardown() }
        var record = merged.record
        record["removed"] = false
        merged.store.recordTransientDownload(record, contextID: "gamma")
        record["removed"] = true
        merged.store.recordTransientDownload(record, contextID: "gamma")
        #expect(!merged.store.transientDownloads.contains { $0.privateContextID == "gamma" })
    }

    @MainActor private func presentations(_ merged: Merged) throws -> (windows: [NSWindow], views: [DownloadLibraryView], dir: URL, rail: LibraryView) {
        let privateDir = merged.root.appendingPathComponent("never-created-merged-private", isDirectory: true)
        let privateStore = BrowserStore(privateParentProfileID: merged.profile, engineProfilePath: merged.path, directory: privateDir,
                                        settings: merged.store.state.settings)
        let rail = LibraryView(store: privateStore, kind: .downloads, profileID: privateStore.activeSpace.profileID,
                               spaceManager: SpaceManagerView(frame: .zero),
                               downloadStore: merged.store, files: IsolatedNoteFiles.make(), reduceMotion: { true })
        let privateWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 512, height: 590), styleMask: [.titled], backing: .buffered, defer: false)
        privateWindow.isReleasedWhenClosed = false
        privateWindow.contentView = rail
        let regular = DownloadLibraryView(store: merged.store, ownerValid: { true })
        let regularWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 512, height: 590), styleMask: [.titled], backing: .buffered, defer: false)
        regularWindow.isReleasedWhenClosed = false
        regularWindow.contentView = regular
        let privateView = try #require(Fixture.descendants(rail).compactMap { $0 as? DownloadLibraryView }.first)
        return ([privateWindow, regularWindow], [regular, privateView], privateDir, rail)
    }

    @MainActor @Test func bothPhysicalWindowPresentationsContainNormalAndPrivateRowsUnderOneDate() throws {
        let merged = try Merged()
        defer { merged.teardown() }
        let (windows, views, _, _) = try presentations(merged)
        defer { windows.forEach { $0.contentView = nil } }
        for view in views {
            let table = try #require(Fixture.descendants(view).compactMap { $0 as? DownloadLibraryTable }.first)
            #expect(view.numberOfRows(in: table) == 4)
        }
    }

    @MainActor @Test func bothActualViewsDispatchTheSameOriginalPrivateContextLease() throws {
        let merged = try Merged()
        defer { merged.teardown() }
        let (windows, views, _, rail) = try presentations(merged)
        defer { windows.forEach { $0.contentView = nil } }
        var actions: [DownloadLibraryIdentity] = []
        views[0].onAction = { item, _ in actions.append(DownloadLibraryIdentity(item)); return true }
        rail.onDownloadAction = { item, _ in actions.append(DownloadLibraryIdentity(item)); return true }
        let alpha = try #require(merged.store.transientDownloads.first { $0.privateContextID == "alpha" })
        for view in views {
            let table = try #require(Fixture.descendants(view).compactMap { $0 as? DownloadLibraryTable }.first)
            let search = try #require(Fixture.descendants(view).compactMap { $0 as? NSTextField }.first { $0.accessibilityLabel() == "Search Downloads" })
            search.stringValue = "Alpha private"
            view.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
            table.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
            let open = try #require(table.makeMenu?()?.items.first { $0.title == "Open" })
            _ = NSApplication.shared.sendAction(open.action!, to: open.target, from: open)
            let hide = try #require(table.makeMenu?()?.items.first { $0.title == "Hide from Parc" })
            _ = NSApplication.shared.sendAction(hide.action!, to: hide.target, from: hide)
            #expect(view.window?.attachedSheet == nil)
        }
        #expect(actions.count == 4 && actions.allSatisfy { $0 == DownloadLibraryIdentity(alpha) })
    }

    @MainActor @Test func retiringTheOriginalContextClearsSelectionAndStopsRetainedMenusAndFileOffers() throws {
        let merged = try Merged()
        defer { merged.teardown() }
        let (windows, views, _, rail) = try presentations(merged)
        defer { windows.forEach { $0.contentView = nil } }
        var actions = 0
        views[0].onAction = { _, _ in actions += 1; return true }
        rail.onDownloadAction = { _, _ in actions += 1; return true }
        var held: [NSMenuItem] = []
        var drags: [NSPasteboardItem] = []
        for view in views {
            let table = try #require(Fixture.descendants(view).compactMap { $0 as? DownloadLibraryTable }.first)
            let search = try #require(Fixture.descendants(view).compactMap { $0 as? NSTextField }.first { $0.accessibilityLabel() == "Search Downloads" })
            search.stringValue = "Alpha private"
            view.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
            table.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
            held.append(try #require(table.makeMenu?()?.items.first { $0.title == "Open" }))
            view.fileURL = { _ in merged.root.appendingPathComponent("not-opened-alpha.pdf") }
            drags.append(try #require(view.tableView(table, pasteboardWriterForRow: 1) as? NSPasteboardItem))
        }
        merged.store.retireTransientDownloads(contextID: "alpha")
        for view in views {
            view.setLoading(count: 0, message: nil)
            let table = try #require(Fixture.descendants(view).compactMap { $0 as? DownloadLibraryTable }.first)
            #expect(table.selectedRowIndexes.isEmpty)
        }
        for item in held { _ = NSApplication.shared.sendAction(item.action!, to: item.target, from: item) }
        #expect(actions == 0 && drags.allSatisfy { $0.string(forType: .fileURL) == nil })
        #expect(merged.store.downloadItems.count == 2 && merged.store.state.downloads.count == 1)
    }

    @MainActor @Test func mergedPrivateDownloadsCreateNoPersistentCatalogsOrWindowState() throws {
        let merged = try Merged()
        defer { merged.teardown() }
        let (windows, _, directory, _) = try presentations(merged)
        windows.forEach { $0.contentView = nil }
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }

    @MainActor private func mediaRail(_ fixture: Fixture, valid: @escaping () -> Bool) -> LibraryView {
        let media = ExternalMediaLibrary(directory: fixture.store.capturesDirectory(for: fixture.profile),
                                         preferencesAreEphemeral: true, systemFolders: { [] })
        let context = LibraryView.PrivateMediaContext(store: fixture.store, profileID: fixture.profile, media: media, isValid: valid)
        return LibraryView(store: fixture.privateStore, kind: .downloads, profileID: fixture.privateID,
                           spaceManager: SpaceManagerView(frame: .zero), downloadStore: fixture.store,
                           privateMediaContext: context, files: IsolatedNoteFiles.make(), reduceMotion: { true })
    }

    @MainActor @Test func privateDownloadsDoesNotEagerlyInitializeMedia() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        let rail = mediaRail(fixture, valid: { true })
        #expect(!Fixture.descendants(rail).contains { $0 is CaptureLibraryView })
    }

    @MainActor @Test func privateMediaCreatesTheExplicitParentCatalogOnlyOnSelection() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        let rail = mediaRail(fixture, valid: { true })
        rail.show(.captures)
        #expect(rail.kind == .captures && Fixture.descendants(rail).contains { $0 is CaptureLibraryView })
    }

    @MainActor @Test func mediaHasNoHeaderFolderButtonAndExposesTheWindowOwnedFolderPreferencesToAccessibility() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        let rail = mediaRail(fixture, valid: { true })
        rail.show(.captures)
        let media = try #require(Fixture.descendants(rail).compactMap { $0 as? CaptureLibraryView }.first)
        #expect(!Fixture.descendants(media).compactMap { $0 as? NSButton }.contains { $0.title == "Folders…" })
        let grid = Fixture.descendants(media).compactMap { $0 as? NSCollectionView }.first
        #expect(grid?.accessibilityCustomActions()?.contains { $0.name == "Manage Media Folders" } == true)
    }

    @MainActor @Test func privateMediaAndDownloadsShareTheVisibleRailWhileOtherCategoriesStayHidden() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        let rail = mediaRail(fixture, valid: { true })
        let buttons = Fixture.descendants(rail).compactMap { $0 as? NSButton }
        #expect(buttons.first { $0.title == "Media" }?.isHidden == false && buttons.first { $0.title == "Downloads" }?.isHidden == false)
        #expect(buttons.filter { ["Easels & Notes", "Archived Tabs", "Spaces"].contains($0.title) }.allSatisfy { $0.isHidden })
    }

    @MainActor @Test func privateMediaCreatesNoPrivateProfileDirectory() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        let rail = mediaRail(fixture, valid: { true })
        rail.show(.captures)
        #expect(!FileManager.default.fileExists(atPath: fixture.privateDirectory.path))
    }

    @MainActor @Test func anInvalidPrivateMediaContextFallsThroughToDownloadsOnStorePublish() async throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        var valid = true
        let rail = mediaRail(fixture, valid: { valid })
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 512, height: 590), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = rail
        defer { window.contentView = nil }
        rail.show(.captures)
        let media = try #require(Fixture.descendants(rail).compactMap { $0 as? CaptureLibraryView }.first)
        valid = false
        _ = fixture.privateStore.open("https://private-media-invalid.example.invalid")
        await withCheckedContinuation { continuation in RunLoop.main.perform(inModes: [.default]) { continuation.resume() } }
        #expect(media.isHidden)
        #expect(Fixture.descendants(rail).compactMap { $0 as? DownloadLibraryView }.contains { !$0.isHidden })
    }

    @MainActor @Test func aRetiredParentContextCannotReopenMedia() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        var valid = true
        let rail = mediaRail(fixture, valid: { valid })
        rail.show(.captures)
        valid = false
        rail.show(.downloads)
        rail.show(.captures)
        #expect(rail.kind == .downloads)
    }
}
