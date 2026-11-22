import Foundation
import Testing
@testable import ParcCore

@MainActor
struct BrowserStoreArchiveEaselTests {
    @Test static func easelAddressesRoundTripTheirCanonicalOpaqueID() {
        let id = UUID()
        let canonical = InternalPage.easel(id).urlString
        #expect(canonical == "parc://easel/" + id.uuidString.lowercased(), "Easel routes must use a canonical opaque document ID")
        #expect(InternalPage(urlString: canonical) == .easel(id), "The internal route must round-trip its typed identity")
    }

    @Test static func appDocumentsAndWebRowsUseTheirOwnFallbackSymbols() {
        #expect(InternalPage.easel(UUID()).sidebarFallbackSymbol == InternalPage.easelFallbackSymbol
                   && InternalPage.note(URL(fileURLWithPath: NSTemporaryDirectory() + "Parc Notes/" + UUID().uuidString + ".md")).sidebarFallbackSymbol == InternalPage.noteFallbackSymbol
                   && InternalPage.sidebarFallbackSymbol(urlString: "https://example.org") == "globe", "Easel and Note rows keep distinct still glyphs; web rows keep the globe fallback")
    }

    @Test static func newDocumentCommandsUseTheSameMarksAsDocumentRows() {
        #expect(CommandBarCommandPresentation.symbol(forCommandID: "createEasel:") == InternalPage.easelFallbackSymbol
                   && CommandBarCommandPresentation.symbol(forCommandID: "createNote:") == InternalPage.noteFallbackSymbol, "New Easel and New Note commands show the same Library marks as their rows")
    }

    @Test static func ordinaryWebNavigationCannotOpenAPastedEaselRoute() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let canonical = InternalPage.easel(UUID()).urlString
            let store = try BrowserStore(directory: directory)
            let tabID = store.open("https://example.org")
            let before = store.state
            store.navigate(tabID, input: canonical)
            #expect(store.state == before, "A pasted internal route must not mutate a web tab through ordinary navigation")
        }
    }

    @Test(arguments: [
        "parc://easel/not-a-uuid",
        "parc://easel/062e60fe-32d4-4d1b-8568-088b9d608bd3/more",
        "parc://easel/062e60fe-32d4-4d1b-8568-088b9d608bd3?profile=other",
        "parc://easel/062e60fe-32d4-4d1b-8568-088b9d608bd3#fragment",
        "parc://user@easel/062e60fe-32d4-4d1b-8568-088b9d608bd3",
        "parc://easel:88/062e60fe-32d4-4d1b-8568-088b9d608bd3",
        "parc://other/062e60fe-32d4-4d1b-8568-088b9d608bd3",
        "https://easel/062e60fe-32d4-4d1b-8568-088b9d608bd3",
    ])
    nonisolated static func invalidDocumentAddressesHaveNoInternalDestination(_ address: String) {
        #expect(InternalPage(urlString: address) == nil)
    }

    @Test(arguments: [
        "parc://easel/062e60fe-32d4-4d1b-8568-088b9d608bd3",
        "PARC://easel/062e60fe-32d4-4d1b-8568-088b9d608bd3",
        "parc://easel/not-a-uuid",
    ])
    nonisolated static func browserNavigationDoesNotOpenPrivateDocumentAddresses(_ address: String) {
        #expect(NavigationInput.resolve(address) == nil)
    }

    private static func withEasel(_ body: (URL, BrowserStore, UUID, UUID) throws -> Void) throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory, now: { Date(timeIntervalSince1970: 1_800_000_000) })
            let documentID = UUID()
            _ = store.open("https://already.example")
            let tabID = try #require(store.openEasel(id: documentID, title: "Research"))
            try body(directory, store, documentID, tabID)
        }
    }

    @Test static func aNewEaselOpensAtTheTopOfTodayWithItsSavedTitleAndAddress() throws {
        try withEasel { _, store, documentID, tabID in
            let originalSpace = store.activeSpaceID
            let created = try BrowserStoreTestsSupport.tab(tabID, in: store)
            #expect(created.kind == .today && created.title == "Research" && created.savedTitle == "Research", "A new Easel is a Today tab with its saved title")
            #expect(SidebarHierarchy.children(in: .init(spaceID: originalSpace, folderID: nil, section: .today),
                                                 state: store.state).first == .tab(tabID), "A new Easel enters at the top of Today")
            #expect(created.url == InternalPage.easel(documentID).urlString && created.savedURL == created.url, "The Easel tab must save the typed internal destination")
            #expect(store.state.history.isEmpty, "Opening an Easel must not create a fabricated web history entry")
        }
    }

    @Test static func reopeningAnEaselSelectsItsExistingTabAndSpace() throws {
        try withEasel { _, store, documentID, tabID in
            let originalSpace = store.activeSpaceID
            store.createSpace(name: "Other")
            let again = store.openEasel(id: documentID, title: "Research")
            #expect(again == tabID && store.activeSpaceID == originalSpace && store.state.tabs.count == 2, "Opening the same profile's Easel again must select its existing tab and Space")
        }
    }

    @Test static func renamingAnOpenEaselUpdatesItsLiveAndSavedTitles() throws {
        try withEasel { _, store, documentID, tabID in
            let profileID = store.activeSpace.profileID
            store.updateEaselTitle(id: documentID, profileID: profileID, title: "Renamed board")
            let record = try BrowserStoreTestsSupport.tab(tabID, in: store)
            #expect(record.title == "Renamed board" && record.savedTitle == "Renamed board", "Document renaming must update both live and saved titles")
        }
    }

    @Test static func renamingASavedEaselKeepsTheLiveWebTitle() throws {
        try withEasel { _, store, documentID, tabID in
            let profileID = store.activeSpace.profileID
            store.setKind(tabID, .pinned)
            store.updateTab(tabID, title: "A web page", url: "https://example.org/reference")
            store.updateEaselTitle(id: documentID, profileID: profileID, title: "Latest board name")
            let record = try BrowserStoreTestsSupport.tab(tabID, in: store)
            #expect(record.title == "A web page" && record.savedTitle == "Latest board name", "Renaming a saved Easel must not overwrite the title of a web page currently occupying that tab")
        }
    }

    @Test static func closingAPinnedEaselThatNavigatedAwayResetsItsSavedDocument() throws {
        try withEasel { _, store, documentID, tabID in
            let profileID = store.activeSpace.profileID
            let created = try BrowserStoreTestsSupport.tab(tabID, in: store)
            store.setKind(tabID, .pinned)
            store.updateTab(tabID, title: "A web page", url: "https://example.org/reference")
            store.updateEaselTitle(id: documentID, profileID: profileID, title: "Latest board name")
            store.closeTab(tabID)
            #expect(try BrowserStoreTestsSupport.tab(tabID, in: store).url == created.savedURL && (try BrowserStoreTestsSupport.tab(tabID, in: store)).title == "Latest board name"
                       && (try BrowserStoreTestsSupport.tab(tabID, in: store)).archivedAt == nil && (try BrowserStoreTestsSupport.tab(tabID, in: store)).kind == .pinned, "Closing a pinned Easel that navigated away resets to the saved document")
        }
    }

    @Test static func closingAPinnedEaselUnloadsItInPlace() throws {
        try withEasel { _, store, _, tabID in
            let created = try BrowserStoreTestsSupport.tab(tabID, in: store)
            store.setKind(tabID, .pinned)
            store.closeTab(tabID)
            #expect(try BrowserStoreTestsSupport.tab(tabID, in: store).archivedAt == nil && (try BrowserStoreTestsSupport.tab(tabID, in: store)).kind == .pinned
                       && (try BrowserStoreTestsSupport.tab(tabID, in: store)).url == created.savedURL, "Closing a pinned Easel that is showing the document unloads it in place, like a deselect")
        }
    }

    @Test static func reopeningAPinnedEaselSelectsTheSameTab() throws {
        try withEasel { _, store, documentID, tabID in
            store.setKind(tabID, .pinned)
            store.closeTab(tabID)
            let opened = store.openEasel(id: documentID, title: "Latest board name")
            let record = try BrowserStoreTestsSupport.tab(tabID, in: store)
            #expect(opened == tabID && record.kind == .pinned, "Opening it again selects the same pinned tab")
        }
    }

    @Test static func anEaselCanBePinnedIntoAFolder() throws {
        try withEasel { _, store, _, tabID in
            store.setKind(tabID, .pinned)
            let folder = store.createFolder(name: "Boards")
            store.moveTab(tabID, toSpace: store.activeSpaceID, folderID: folder)
            let record = try BrowserStoreTestsSupport.tab(tabID, in: store)
            #expect(record.folderID == folder && record.kind == .pinned, "An Easel can be pinned into a folder")
        }
    }

    @Test static func closingAFolderPinnedEaselKeepsItsFolder() throws {
        try withEasel { _, store, _, tabID in
            store.setKind(tabID, .pinned)
            let folder = store.createFolder(name: "Boards")
            store.moveTab(tabID, toSpace: store.activeSpaceID, folderID: folder)
            store.closeTab(tabID)
            let record = try BrowserStoreTestsSupport.tab(tabID, in: store)
            #expect(record.archivedAt == nil && record.kind == .pinned
                       && record.folderID == folder, "Closing a folder-pinned Easel keeps it in its folder")
        }
    }

    @Test static func closingATodayEaselArchivesIt() throws {
        try withEasel { _, store, _, tabID in
            store.closeTab(tabID)
            let record = try BrowserStoreTestsSupport.tab(tabID, in: store)
            #expect(record.archivedAt != nil, "Closing a Today Easel archives it")
        }
    }

    @Test static func reopeningAnArchivedEaselRestoresItToToday() throws {
        try withEasel { _, store, documentID, tabID in
            store.closeTab(tabID)
            store.openEasel(id: documentID, title: "Latest board name")
            let record = try BrowserStoreTestsSupport.tab(tabID, in: store)
            #expect(record.kind == .today && record.archivedAt == nil, "Library reopen restores the archived Easel as Today")
        }
    }

    @Test static func anEaselAndWebSplitSurvivesRestart() throws {
        try withEasel { directory, store, _, tabID in
            let web = store.open("https://example.org/alongside")
            try BrowserStoreTestsSupport.savedSplit(store, [tabID, web], in: .init(spaceID: store.activeSpaceID, folderID: nil, section: .pinned))
            store.selectTab(tabID)
            store.setSplitLayout(orientation: .vertical, widthFactors: [1, 2])
            try store.save()
            let reopened = try BrowserStore(directory: directory)
            #expect(reopened.state == store.state, "A split containing a native Easel and real web tab must persist without a separate window model")
        }
    }

    @Test static func closingAPinnedEaselPaneUnloadsItLikeAnyPinnedTab() throws {
        try withEasel { directory, store, _, tabID in
            let web = store.open("https://example.org/alongside")
            try BrowserStoreTestsSupport.savedSplit(store, [tabID, web], in: .init(spaceID: store.activeSpaceID, folderID: nil, section: .pinned))
            store.selectTab(tabID)
            store.setSplitLayout(orientation: .vertical, widthFactors: [1, 2])
            try store.save()
            let reopened = try BrowserStore(directory: directory)
            reopened.closeTab(tabID)
            #expect(try BrowserStoreTestsSupport.tab(tabID, in: reopened).archivedAt == nil && (try BrowserStoreTestsSupport.tab(tabID, in: reopened)).kind == .pinned, "Closing a pinned Easel pane unloads it like any pinned tab")
        }
    }

    @Test static func reopeningAnUnloadedPinnedEaselPaneSelectsItsExistingTab() throws {
        try withEasel { directory, store, documentID, tabID in
            let web = store.open("https://example.org/alongside")
            try BrowserStoreTestsSupport.savedSplit(store, [tabID, web], in: .init(spaceID: store.activeSpaceID, folderID: nil, section: .pinned))
            store.selectTab(tabID)
            store.setSplitLayout(orientation: .vertical, widthFactors: [1, 2])
            try store.save()
            let reopened = try BrowserStore(directory: directory)
            reopened.closeTab(tabID)
            #expect(try reopened.openEasel(id: documentID, title: "Latest board name") == tabID
                       && (try BrowserStoreTestsSupport.tab(tabID, in: reopened)).kind == .pinned, "Opening it again selects its existing pinned tab")
        }
    }

    @Test static func easelProfileDirectoriesAndIdentity() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let documentID = UUID()
            let firstProfile = store.activeSpace.profileID
            let firstID = store.openEasel(id: documentID, title: "Personal")!
            let firstPath = store.activeEaselsDirectory
            #expect(firstPath == URL(fileURLWithPath: store.profilePath(for: (try BrowserStoreTestsSupport.tab(firstID, in: store))), isDirectory: true).appendingPathComponent("Easels", isDirectory: true), "Easel storage must live under the same explicit browser profile path")
            let secondSpace = store.createSpace(name: "Work")
            let secondProfile = store.createProfile(name: "Work")
            store.assignProfile(secondProfile, toSpace: secondSpace)
            let secondID = store.openEasel(id: documentID, title: "Work board")!
            #expect(firstID != secondID && store.activeEaselsDirectory != firstPath, "Matching document UUIDs in distinct profiles must remain separate tabs and directories")
            #expect(store.activeEaselsDirectory == store.easelsDirectory(for: secondProfile), "The active Easel directory must follow the active Space's profile")
            store.updateEaselTitle(id: documentID, profileID: secondProfile, title: "Changed work board")
            #expect(try BrowserStoreTestsSupport.tab(firstID, in: store).savedTitle == "Personal" && (try BrowserStoreTestsSupport.tab(secondID, in: store)).savedTitle == "Changed work board", "A document's title notification must not rename another profile's same-ID document")
            let before = store.state
            store.updateEaselTitle(id: documentID, profileID: firstProfile, title: "  ")
            #expect(store.state == before, "An empty native title must not erase the pinned destination name")
            #expect(!FileManager.default.fileExists(atPath: firstPath.path), "Path resolution and tab creation must not silently create or copy document files")
        }
    }
}
