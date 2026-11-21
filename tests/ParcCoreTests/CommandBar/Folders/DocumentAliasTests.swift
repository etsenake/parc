import Foundation
import Testing
@testable import ParcCore

struct DocumentAliasTests {
    @MainActor final class Fixture {
        let root = CommandBarFixtures.temporaryDirectory("document-alias")
        let profile = BrowserProfile(id: UUID(), name: "Original")
        let space: BrowserSpace
        let away: BrowserSpace
        let folder: BrowserFolder
        let destination: BrowserFolder
        let profileDirectory: URL
        let notesFolder: URL
        let sessionURL: URL
        let easels: EaselStore
        let easel: EaselSession
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a3uoAAAAASUVORK5CYII=")!
        let noteURL: URL
        let noteBytes = Data("# Plans\n\n![pixel](Attachments/pixel.png)\n".utf8)
        let asset: String
        let noteTab: BrowserTab
        let easelTab: BrowserTab
        let webTab: BrowserTab
        let split: BrowserSplitLayout
        let store: BrowserStore
        let initial: BrowserState
        let originalEasel: EaselDocument
        let noteReference: SidebarDocumentReference
        let validateNote: @MainActor () throws -> Void
        let easelReference: SidebarDocumentReference
        let urls: [UUID: String]
        let references: [UUID: SidebarDocumentReference]

        deinit { try? FileManager.default.removeItem(at: root) }

        init() throws {
            space = BrowserSpace(id: UUID(), name: "Source", symbol: "circle", color: "ABCDEF", profileID: profile.id)
            away = BrowserSpace(id: UUID(), name: "Away", symbol: "circle", color: "ABCDEF", profileID: profile.id)
            folder = BrowserFolder(id: UUID(), spaceID: space.id, name: "Mixed", isExpanded: false)
            destination = BrowserFolder(id: UUID(), spaceID: away.id, name: "Destination")
            profileDirectory = root.appendingPathComponent("Profiles/" + profile.id.uuidString)
            notesFolder = root.appendingPathComponent("Parc Notes", isDirectory: true)
            sessionURL = root.appendingPathComponent("session.json")
            try FileManager.default.createDirectory(at: notesFolder.appendingPathComponent("Attachments"), withIntermediateDirectories: true)
            easels = try EaselStore(directory: profileDirectory.appendingPathComponent("Easels"))
            easel = try easels.create(title: "Original Easel")
            try png.write(to: notesFolder.appendingPathComponent("Attachments/pixel.png"))
            noteURL = InternalPage.noteFile(notesFolder.appendingPathComponent("Original Note.md"))!
            try noteBytes.write(to: noteURL)
            let inline = EaselRichText.Image(data: png, fileType: "public.png", width: 1, height: 1)
            let richText = EaselRichText(runs: [.init(location: 0, length: 1,
                attributes: .init(font: .init(name: "Helvetica", size: 15), ink: "#252525FF", image: inline))])
            asset = try easel.importPNG(png)
            let image = EaselItem(kind: .image, frame: .init(x: 5, y: 10, width: 100, height: 80), assetID: asset)
            let rich = EaselItem(kind: .text, frame: .init(x: 30, y: 50, width: 120, height: 100), text: "\u{fffc}", richText: richText)
            let browser = EaselItem(kind: .browser, frame: .init(x: 40, y: 90, width: 300, height: 200), url: "https://original.invalid/")
            try easel.perform("Original content") { $0.items = [image, rich, browser] }
            let spaceID = space.id, profileID = profile.id, folderID = folder.id
            func tab(_ title: String, _ url: String) -> BrowserTab {
                BrowserTab(id: UUID(), spaceID: spaceID, profileID: profileID, url: url, title: title,
                    kind: .pinned, folderID: folderID, createdAt: Date(timeIntervalSince1970: 10),
                    lastAccessed: Date(timeIntervalSince1970: 10), savedURL: url, savedTitle: title)
            }
            noteTab = tab("Note", InternalPage.note(noteURL).urlString)
            easelTab = tab("Easel", InternalPage.easel(easel.document.id).urlString)
            webTab = tab("Web", "https://saved.invalid/")
            split = BrowserSplitLayout(sidebarAnchorID: noteTab.id, customTitle: "Mixed split", spaceID: space.id,
                tabIDs: [noteTab.id, easelTab.id], orientation: .vertical, widthFactors: [0.3, 0.7])
            var state = BrowserState(profiles: [profile], spaces: [space, away], activeSpaceID: space.id)
            state.folders = [folder, destination]
            state.tabs = [noteTab, easelTab, webTab]
            state.splitLayouts = [split]
            state.selectedTabIDs = split.tabIDs
            state.selectionBySpace = [space.id.uuidString: split.tabIDs]
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(state).write(to: sessionURL)
            store = try BrowserStore(directory: root)
            initial = store.state
            originalEasel = easel.document
            let noteURL = self.noteURL, easels = self.easels, easelID = easel.document.id
            validateNote = {
                guard FileManager.default.fileExists(atPath: noteURL.path) else { throw CocoaError(.fileNoSuchFile) }
            }
            noteReference = SidebarDocumentReference(page: .note(noteURL), profileID: profile.id, validate: validateNote)
            easelReference = SidebarDocumentReference(page: .easel(easelID), profileID: profile.id) { try easels.validateReference(easelID) }
            urls = [noteTab.id: noteTab.savedURL, easelTab.id: easelTab.savedURL, webTab.id: "https://materialized.invalid/"]
            references = [noteTab.id: noteReference, easelTab.id: easelReference]
        }

        func files(_ directory: URL) throws -> [String: Data] {
            var result: [String: Data] = [:]
            let values = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey])!
            for case let url as URL in values where try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true {
                result[url.path.replacingOccurrences(of: directory.path, with: "")] = try Data(contentsOf: url)
            }
            return result
        }

        func duplicate() throws -> FolderDuplicateResult {
            let target = FolderDuplicateTarget(folderID: folder.id, spaceID: space.id, profileID: profile.id, state: initial)!
            return try store.duplicateFolder(target, destinations: urls, documents: references)!
        }

        func move(in state: BrowserState) -> CommandBarFolderMove {
            let source = CommandBarFolderMoveSource(items: [.folder(folder.id)], spaceID: space.id, profileID: profile.id, state: state)!
            let destinationID = destination.id
            return CommandBarFolderMove.snapshot(source: source, state: state).first { $0.folder.folderID == destinationID }!
        }

        func copyToDestination() throws -> CommandBarFolderCopy {
            try store.copyCommandBarItemsToFolder(move(in: store.state), destinations: urls, documents: references)!
        }

        func prepared() throws {
            _ = try duplicate()
            _ = try copyToDestination()
        }

        func replaceSessionWithDirectory() throws -> Data {
            let bytes = try Data(contentsOf: sessionURL)
            try FileManager.default.removeItem(at: sessionURL)
            try FileManager.default.createDirectory(at: sessionURL, withIntermediateDirectories: false)
            return bytes
        }
    }

    @Test @MainActor func originalTypedStoresValidateTheCompleteMixedSet() throws {
        let f = try Fixture()
        #expect(SidebarCopySources(destinations: f.urls, documents: f.references).validates(f.initial.tabs))
    }

    @Test @MainActor func aLocalURLAloneIsNotATypedReference() throws {
        let f = try Fixture()
        #expect(!SidebarCopySources(destinations: f.urls).validates(f.initial.tabs))
    }

    @Test @MainActor func theSameFileInAnotherProfileCannotAuthorizeAReference() throws {
        let f = try Fixture()
        var wrong = f.references
        wrong[f.noteTab.id] = SidebarDocumentReference(page: .note(f.noteURL), profileID: UUID(), validate: f.validateNote)
        #expect(!SidebarCopySources(destinations: f.urls, documents: wrong).validates(f.initial.tabs))
    }

    @Test @MainActor func aTypedDestinationCannotChangeTheDocumentOrItsKind() throws {
        let f = try Fixture()
        var wrongURLs = f.urls
        wrongURLs[f.noteTab.id] = InternalPage.easel(f.easel.document.id).urlString
        #expect(!SidebarCopySources(destinations: wrongURLs, documents: f.references).validates(f.initial.tabs))
    }

    @Test @MainActor func anOrdinaryWebItemCannotTurnIntoADocumentReference() throws {
        let f = try Fixture()
        var wrongURLs = f.urls
        wrongURLs[f.webTab.id] = f.noteTab.savedURL
        #expect(!SidebarCopySources(destinations: wrongURLs, documents: f.references).validates(f.initial.tabs))
    }

    @Test @MainActor func duplicatingGivesFreshSidebarIdentitiesForTheFullMixedTree() throws {
        let f = try Fixture()
        let result = try f.duplicate()
        let copied = result.tabIDs.compactMap { id in f.store.state.tabs.first { $0.id == id } }
        #expect(copied.count == 3)
        #expect(Set(result.tabIDs).isDisjoint(with: f.initial.tabs.map(\.id)))
    }

    @Test @MainActor func actualTypedDocumentsAndTheRealWebDestinationStaySeparate() throws {
        let f = try Fixture()
        let target = FolderDuplicateTarget(folderID: f.folder.id, spaceID: f.space.id, profileID: f.profile.id, state: f.initial)!
        let result = try f.duplicate()
        let copied = result.tabIDs.compactMap { id in f.store.state.tabs.first { $0.id == id } }
        #expect(copied.map(\.savedURL) == target.tabs.map { f.urls[$0.id]! })
    }

    @Test @MainActor func theNoteAliasPointsAtTheVeryFileOfTheOriginal() throws {
        let f = try Fixture()
        let result = try f.duplicate()
        let copied = result.tabIDs.compactMap { id in f.store.state.tabs.first { $0.id == id } }
        #expect(copied.contains { InternalPage(urlString: $0.url)?.noteURL.flatMap(InternalPage.noteFile) == f.noteURL })
    }

    @Test @MainActor func theEaselAliasRetainsTheExactDocumentID() throws {
        let f = try Fixture()
        let result = try f.duplicate()
        let copied = result.tabIDs.compactMap { id in f.store.state.tabs.first { $0.id == id } }
        #expect(copied.contains { InternalPage(urlString: $0.url)?.easelID == f.originalEasel.id })
    }

    @Test @MainActor func typedSplitChildrenNeverCreateRendererPages() throws {
        let f = try Fixture()
        #expect(try f.duplicate().openTabIDs.isEmpty)
    }

    @Test @MainActor func theAliasSplitPreservesItsActualLayout() throws {
        let f = try Fixture()
        _ = try f.duplicate()
        let copiedSplit = try #require(f.store.state.splitLayouts.first { $0.id != f.split.id })
        #expect(copiedSplit.widthFactors == f.split.widthFactors)
        #expect(copiedSplit.orientation == f.split.orientation)
    }

    @Test @MainActor func theAliasTransactionWritesNoNoteAttachmentOrAssetFiles() throws {
        let f = try Fixture()
        let originalFiles = try f.files(f.profileDirectory), originalNoteFiles = try f.files(f.notesFolder)
        _ = try f.duplicate()
        #expect(try f.files(f.profileDirectory) == originalFiles)
        #expect(try f.files(f.notesFolder) == originalNoteFiles)
    }

    @Test @MainActor func theOriginalEaselSessionAndRevisionAreUntouched() throws {
        let f = try Fixture()
        _ = try f.duplicate()
        #expect(f.easel.document == f.originalEasel)
    }

    @Test @MainActor func theOriginalSidebarRecordsAndSelectionAreUntouched() throws {
        let f = try Fixture()
        _ = try f.duplicate()
        #expect(f.store.state.tabs.prefix(f.initial.tabs.count).elementsEqual(f.initial.tabs))
        #expect(f.store.state.selectedTabIDs == f.initial.selectedTabIDs)
    }

    @Test @MainActor func everyNoteAliasSharesTheOneOriginalFile() throws {
        let f = try Fixture()
        _ = try f.duplicate()
        let aliasFiles = Set(f.store.state.tabs.compactMap { InternalPage(urlString: $0.savedURL)?.noteURL.flatMap(InternalPage.noteFile)?.path })
        #expect(aliasFiles == [f.noteURL.path])
    }

    @Test @MainActor func easelAliasesShareTheRealOriginalSession() throws {
        let f = try Fixture()
        _ = try f.duplicate()
        #expect(try f.easels.load(f.originalEasel.id) === f.easel)
    }

    @Test @MainActor func originalEditsAreWhatEveryAliasOpens() throws {
        let f = try Fixture()
        _ = try f.duplicate()
        let editedBytes = Data("# Plans, shared\n\n![pixel](Attachments/pixel.png)\n".utf8)
        try editedBytes.write(to: f.noteURL)
        try f.easel.perform("Shared change") { $0.items[0].frame.x += 10 }
        #expect(try Data(contentsOf: f.noteURL) == editedBytes)
        #expect(try f.easels.load(f.originalEasel.id).document.items[0].frame.x == 15)
    }

    @Test @MainActor func theOriginalAssetAndAttachmentBytesRemainOwned() throws {
        let f = try Fixture()
        _ = try f.duplicate()
        #expect(try Data(contentsOf: f.easel.assetURL(f.asset)) == f.png)
        #expect(try Data(contentsOf: f.notesFolder.appendingPathComponent("Attachments/pixel.png")) == f.png)
    }

    @Test @MainActor func easelContentAndEmbeddedPageObjectIDsAreSharedNotCloned() throws {
        let f = try Fixture()
        _ = try f.duplicate()
        #expect(try f.easels.load(f.originalEasel.id).document.items.map(\.id) == f.originalEasel.items.map(\.id))
    }

    @Test @MainActor func contextualFolderCopySharesTypedReferencesAndKeepsOrdinaryChildrenLazy() throws {
        let f = try Fixture()
        _ = try f.duplicate()
        let command = try f.copyToDestination()
        #expect(command.tabs.count == 3)
        #expect(command.openTabIDs.isEmpty)
    }

    @Test @MainActor func aSameProfileDestinationSpaceOwnsAllFreshRecords() throws {
        let f = try Fixture()
        _ = try f.duplicate()
        let command = try f.copyToDestination()
        #expect(command.tabs.allSatisfy { $0.spaceID == f.away.id && $0.profileID == f.profile.id })
    }

    @Test @MainActor func aliasSidebarIDsSurviveARealDiskReloadAndReadTheSameOriginalNote() throws {
        let f = try Fixture()
        _ = try f.duplicate()
        let command = try f.copyToDestination()
        let editedBytes = Data("# Plans, shared\n".utf8)
        try editedBytes.write(to: f.noteURL)
        let reloaded = try BrowserStore(directory: f.root)
        #expect(command.tabIDs.allSatisfy { id in reloaded.state.tabs.contains { $0.id == id } })
        #expect(try Data(contentsOf: f.noteURL) == editedBytes)
    }

    @Test @MainActor func aFailedSidebarSavePublishesNoAliasesAndMutatesNoDocuments() throws {
        let f = try Fixture()
        try f.prepared()
        let stable = f.store.state, stableFiles = try f.files(f.profileDirectory)
        let fresh = f.move(in: stable)
        _ = try f.replaceSessionWithDirectory()
        #expect(throws: (any Error).self) { _ = try f.store.copyCommandBarItemsToFolder(fresh, destinations: f.urls, documents: f.references) }
        #expect(f.store.state == stable)
        #expect(try f.files(f.profileDirectory) == stableFiles)
    }

    @Test @MainActor func aMissingNoteFileInvalidatesTheCapturedCapabilityAndRefusesAllMixedCopies() throws {
        let f = try Fixture()
        try f.prepared()
        let stable = f.store.state
        let fresh = f.move(in: stable)
        let movedAside = f.notesFolder.appendingPathComponent("Moved aside.md")
        try FileManager.default.moveItem(at: f.noteURL, to: movedAside)
        #expect(!f.noteReference.isCurrent())
        #expect(try f.store.copyCommandBarItemsToFolder(fresh, destinations: f.urls, documents: f.references) == nil)
        #expect(f.store.state == stable)
        try FileManager.default.moveItem(at: movedAside, to: f.noteURL)
        #expect(f.noteReference.isCurrent())
    }

    @Test @MainActor func aMissingOriginalAssetRejectsTheEaselReferenceUntilRecovered() throws {
        let f = try Fixture()
        let assetURL = try f.easel.assetURL(f.asset)
        let assetBytes = try Data(contentsOf: assetURL)
        try FileManager.default.removeItem(at: assetURL)
        #expect(!f.easelReference.isCurrent())
        try assetBytes.write(to: assetURL)
        #expect(f.easelReference.isCurrent())
    }

    @Test @MainActor func aSharedEmbeddedOwnerVetoPreservesEveryAliasOriginalDocument() throws {
        let f = try Fixture()
        let blocked = f.easel.observeReplacement { _ in false }
        #expect(throws: (any Error).self) { try f.easels.delete(f.originalEasel.id) }
        #expect(f.easelReference.isCurrent())
        f.easel.removeReplacementObserver(blocked)
    }

    struct Deletion {
        var requested: Set<UUID> = []
        var didDelete = false
        var error: Error?
    }

    @MainActor func deleteNote(_ f: Fixture, _ deletion: inout Deletion) {
        var didDelete = false, error: Error?
        let noteURL = f.noteURL
        f.store.deleteLocalDocument(.note(noteURL), profileID: f.profile.id, ownerValid: { true }, deleteDocument: {
            didDelete = true
            try FileManager.default.removeItem(at: noteURL)
        }, completion: { error = $0 })
        deletion.didDelete = didDelete
        deletion.error = error
    }

    @MainActor func noteAliasIDs(_ f: Fixture) -> Set<UUID> {
        Set(f.store.state.tabs.filter { InternalPage(urlString: $0.savedURL) == .note(f.noteURL) }.map(\.id))
    }

    @Test @MainActor func documentDeletionRetiresEveryOriginalAndCopiedAliasAcrossSpacesAndOneRefusalPreservesAll() throws {
        let f = try Fixture()
        try f.prepared()
        let noteIDs = noteAliasIDs(f)
        var requested: Set<UUID> = []
        f.store.requestPageRetirement = { ids, _, done in requested = ids; done(false) }
        let beforeDelete = f.store.state
        var deletion = Deletion()
        deleteNote(f, &deletion)
        #expect(requested == noteIDs)
        #expect(noteIDs.count == 3)
        #expect(deletion.error != nil)
        #expect(!deletion.didDelete)
        #expect(f.store.state == beforeDelete)
        #expect(f.noteReference.isCurrent())
    }

    @Test @MainActor func anAliasRemovalSaveFailureKeepsTheDocumentRetryableAndEveryModelReferenceIntact() throws {
        let f = try Fixture()
        try f.prepared()
        f.store.requestPageRetirement = { _, authorize, done in done(authorize()) }
        let beforeDelete = f.store.state
        _ = try f.replaceSessionWithDirectory()
        var deletion = Deletion()
        deleteNote(f, &deletion)
        #expect(deletion.error != nil)
        #expect(!deletion.didDelete)
        #expect(f.store.state == beforeDelete)
        #expect(f.noteReference.isCurrent())
    }

    @Test @MainActor func approvedWholeSetDeletionRemovesTheOneSharedFileAndEveryAlias() throws {
        let f = try Fixture()
        try f.prepared()
        let noteIDs = noteAliasIDs(f)
        var requested: Set<UUID> = []
        f.store.requestPageRetirement = { ids, authorize, done in requested = ids; done(authorize()) }
        var deletion = Deletion()
        deleteNote(f, &deletion)
        #expect(deletion.error == nil)
        #expect(deletion.didDelete)
        #expect(requested == noteIDs)
        #expect(f.store.state.tabs.allSatisfy { !noteIDs.contains($0.id) })
        #expect(f.store.state.tabs.filter { InternalPage(urlString: $0.savedURL)?.easelID == f.originalEasel.id }.count == 3)
        #expect(try BrowserStore(directory: f.root).state.tabs.allSatisfy { !noteIDs.contains($0.id) })
        #expect(!f.noteReference.isCurrent())
        #expect(!FileManager.default.fileExists(atPath: f.noteURL.path))
    }

    @Test @MainActor func actualEaselDeletionInvalidatesEveryAliasCapabilityAndBlocksEditsButKeepsTheAsset() throws {
        let f = try Fixture()
        let assetURL = try f.easel.assetURL(f.asset)
        try f.easels.delete(f.originalEasel.id)
        #expect(!f.easelReference.isCurrent())
        #expect(throws: (any Error).self) { try f.easel.perform("Not allowed") { $0.title = "Resurrected" } }
        #expect(try Data(contentsOf: assetURL) == f.png)
    }
}
