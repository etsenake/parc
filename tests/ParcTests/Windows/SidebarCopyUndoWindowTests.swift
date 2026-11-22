import AppKit
import Testing
@testable import Parc
@testable import ParcCore
@testable import ParcSidebar

@MainActor
struct SidebarCopyUndoWindowTests {
    @MainActor private final class Fixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let sourceHost = SplitResizeCommandAvailabilityTests.Host.make()
        let destinationHost = SplitResizeCommandAvailabilityTests.Host.make()
        let store: BrowserStore
        let source: BrowserWindowController
        let destination: BrowserWindowController
        let ids: [UUID]
        let layout: BrowserSplitLayout
        let location: SidebarContainerLocation

        init() throws {
            let store = try BrowserStore(directory: directory)
            self.store = store
            store.scheduleDeferredSave = { _, _ in }
            let space = store.activeSpaceID
            let profile = store.state.spaces.first { $0.id == space }!.profileID
            let files = [directory.appendingPathComponent("One.md"), directory.appendingPathComponent("Two.md")]
            for file in files { try Data("Note".utf8).write(to: file) }
            ids = files.map { store.openResolvedURL(URL(string: InternalPage.note($0).urlString)!) }
            store.setSplit(ids)
            layout = try #require(store.activeSplitLayout)
            location = SidebarContainerLocation(spaceID: space, folderID: nil, section: .today)

            let ownership = NativePageOwnership()
            source = try BrowserWindowController(store: store, ownership: ownership, windowHost: sourceHost)
            destination = try BrowserWindowController(store: store, ownership: ownership, windowHost: destinationHost)
            destinationHost.key = false
            for owner in [source, destination] {
                owner.rendering = true
                owner.isSpaceCommandApplicationActive = { true }
                owner.canPresentSplitInteraction = { _ in true }
                owner.nativeSidebarTransferAvailable = { _ in true }
                owner.nativeFolderDuplicateContextAvailable = { _ in true }
                owner.resolveSidebarCopyDestinations = { tabs in
                    var sources = SidebarCopySources()
                    for tab in tabs {
                        guard let page = InternalPage(urlString: tab.savedURL), let url = page.noteURL else { return nil }
                        sources.destinations[tab.id] = tab.savedURL
                        sources.documents[tab.id] = SidebarDocumentReference(page: page, profileID: profile) {
                            _ = try Data(contentsOf: url)
                        }
                    }
                    return sources
                }
            }
        }

        deinit {
            MainActor.assumeIsolated { sourceHost.close(); destinationHost.close() }
            try? FileManager.default.removeItem(at: directory)
        }
    }

    @Test func aWholeSplitCopyRegistersUndoOnlyInTheReceivingWindow() throws {
        let fixture = try Fixture()
        let group = SidebarItemReference.split(fixture.layout.id)
        let session = try #require(fixture.source.prepareSidebarMove(group))
        let copy = try #require(fixture.destination.prepareSidebarCopyDrop(session, items: [group],
                                                                          to: fixture.location, before: nil))
        #expect(fixture.destination.folderUndo.command(.undo) == nil)
        try #require(session.copy(copy))

        let copies = try #require(fixture.store.state.splitLayouts.first { $0.id != fixture.layout.id })
        #expect(fixture.destination.selectedTabIDs == copies.tabIDs)
        #expect(fixture.source.folderUndo.command(.undo) == nil)
        let undo = try #require(fixture.destination.folderUndo.command(.undo))
        #expect(undo.name == "Copy")
        #expect(!fixture.source.folderUndo.perform(undo))
        try #require(fixture.destination.folderUndo.perform(undo))
        #expect(fixture.store.state.splitLayouts.contains(fixture.layout))
        #expect(fixture.store.state.tab(copies.tabIDs[0]) == nil)
        #expect(fixture.store.state.tab(copies.tabIDs[1]) == nil)
    }

    @Test func aLooseTabCopyStaysInItsSourceWindow() throws {
        let fixture = try Fixture()
        let loose = SidebarItemReference.tab(fixture.store.openResolvedURL(
            URL(string: InternalPage.note(fixture.directory.appendingPathComponent("One.md")).urlString)!))
        let session = try #require(fixture.source.prepareSidebarMove(loose))

        #expect(fixture.destination.prepareSidebarCopyDrop(session, items: [loose], to: fixture.location, before: nil) == nil)
        #expect(fixture.source.prepareSidebarCopyDrop(session, items: [loose], to: fixture.location, before: nil) != nil)
    }
}
