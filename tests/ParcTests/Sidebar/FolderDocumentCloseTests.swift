import AppKit
import Testing
@testable import Parc
@testable import ParcCore
@testable import ParcSidebar

@MainActor
struct FolderDocumentCloseTests {
    private func files(_ directory: URL) throws -> [String: Data] {
        var result: [String: Data] = [:]
        for case let url as URL in FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey])!
            where try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true {
            result[url.path.replacingOccurrences(of: directory.path, with: "")] = try Data(contentsOf: url)
        }
        return result
    }

    @MainActor private final class Mixed {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("parc-folder-documents-" + UUID().uuidString)
        let profile = BrowserProfile(id: UUID(), name: "Original")
        let space: BrowserSpace
        let away: BrowserSpace
        let folder: BrowserFolder
        let nested: BrowserFolder
        let empty: BrowserFolder
        let dataDirectory: URL
        let notesFolder: URL
        let noteURL: URL
        let noteOriginal = Data("Original note\n".utf8)
        let easels: EaselStore
        let easel: EaselSession
        let asset: String
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a3uoAAAAASUVORK5CYII=")!
        let n: BrowserTab
        let e: BrowserTab
        let w: BrowserTab
        let alias: BrowserTab
        let easelAlias: BrowserTab
        let split: BrowserSplitLayout
        let sessionURL: URL
        let store: BrowserStore
        let initial: BrowserState
        let originalData: [String: Data]
        let target: FolderRemovalTarget
        let documents: [UUID: SidebarDocumentReference]
        var requested: Set<UUID> = []
        var authorize: (() -> Bool)?
        var finish: ((Bool) -> Void)?
        var calls = 0
        var result: Result<Bool, Error>?
        var record: FolderDeletionUndo?
        var selection: FolderRemovalSelection!

        init() throws {
            let space = BrowserSpace(id: UUID(), name: "Here", symbol: "circle", color: "ABCDEF", profileID: profile.id)
            let away = BrowserSpace(id: UUID(), name: "Away", symbol: "circle", color: "ABCDEF", profileID: profile.id)
            let folder = BrowserFolder(id: UUID(), spaceID: space.id, name: "Mixed", isExpanded: false)
            let nested = BrowserFolder(id: UUID(), spaceID: space.id, name: "Nested", parentID: folder.id)
            let empty = BrowserFolder(id: UUID(), spaceID: space.id, name: "Empty", parentID: nested.id)
            self.space = space
            self.away = away
            self.folder = folder
            self.nested = nested
            self.empty = empty
            dataDirectory = root.appendingPathComponent("Profiles/" + profile.id.uuidString)
            notesFolder = root.appendingPathComponent("Parc Notes")
            try FileManager.default.createDirectory(at: notesFolder, withIntermediateDirectories: true)
            noteURL = notesFolder.appendingPathComponent("Shared.md")
            try noteOriginal.write(to: noteURL)
            easels = try EaselStore(directory: dataDirectory.appendingPathComponent("Easels"))
            easel = try easels.create(title: "Shared Easel")
            asset = try easel.importPNG(png)
            let image = EaselItem(kind: .image, frame: .init(x: 1, y: 2, width: 30, height: 40), assetID: asset)
            try easel.perform("Original image") { $0.items = [image] }
            let profileID = profile.id
            func tab(_ title: String, _ url: String) -> BrowserTab {
                BrowserTab(id: UUID(), spaceID: space.id, profileID: profileID, url: url, title: title, kind: .pinned, folderID: nested.id,
                           createdAt: Date(timeIntervalSince1970: 10), lastAccessed: Date(timeIntervalSince1970: 10), savedURL: url, savedTitle: title)
            }
            n = tab("Note", InternalPage.note(noteURL).urlString)
            e = tab("Easel", InternalPage.easel(easel.document.id).urlString)
            w = tab("Web", "https://original.invalid/")
            var alias = n
            alias.id = UUID(); alias.spaceID = away.id; alias.folderID = nil
            var easelAlias = e
            easelAlias.id = UUID(); easelAlias.spaceID = away.id; easelAlias.folderID = nil
            self.alias = alias
            self.easelAlias = easelAlias
            split = BrowserSplitLayout(sidebarAnchorID: n.id, customTitle: "Original mixed split", spaceID: space.id,
                                       tabIDs: [n.id, w.id, e.id], orientation: .vertical, widthFactors: [0.2, 0.3, 0.5])
            var state = BrowserState(profiles: [profile], spaces: [space, away], activeSpaceID: space.id)
            state.tabs = [n, w, e, alias, easelAlias]
            state.folders = [folder, nested, empty]
            state.splitLayouts = [split]
            state.selectedTabIDs = split.tabIDs
            state.selectionBySpace = [space.id.uuidString: split.tabIDs]
            sessionURL = root.appendingPathComponent("session.json")
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(state).write(to: sessionURL)
            store = try BrowserStore(directory: root, now: { Date(timeIntervalSince1970: 1_900_000_000) })
            initial = store.state
            originalData = try Self.files(dataDirectory)
            target = FolderRemovalTarget(folderID: folder.id, spaceID: space.id, profileID: profile.id, state: initial)!
            let noteURL = self.noteURL
            let noteAvailable: @MainActor () throws -> Void = {
                guard FileManager.default.fileExists(atPath: noteURL.path) else { throw CocoaError(.fileNoSuchFile) }
            }
            let easels = self.easels
            let easelID = easel.document.id
            documents = [n.id: SidebarDocumentReference(page: .note(noteURL), profileID: profile.id, validate: noteAvailable),
                         e.id: SidebarDocumentReference(page: .easel(easelID), profileID: profile.id) { try easels.validateReference(easelID) }]
            store.requestPageRetirement = { [weak self] ids, admission, done in
                self?.requested = ids
                self?.authorize = admission
                self?.finish = done
                self?.calls += 1
            }
            selection = FolderRemovalSelection.resolve(target: target, state: initial, selected: split.tabIDs, focused: e.id, available: { _ in true })!
        }

        deinit { try? FileManager.default.removeItem(at: root) }

        static func files(_ directory: URL) throws -> [String: Data] {
            var result: [String: Data] = [:]
            for case let url as URL in FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey])!
                where try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true {
                result[url.path.replacingOccurrences(of: directory.path, with: "")] = try Data(contentsOf: url)
            }
            return result
        }

        func remove() {
            result = nil
            store.deleteFolder(target, selection: selection, documents: documents, shouldCommit: { true }, didCommit: { [weak self] in self?.record = $0 }) { [weak self] in
                self?.result = $0
            }
        }

        func closed() -> Mixed {
            remove()
            _ = authorize?()
            finish?(true)
            return self
        }

        func undoEntry() -> (FolderUndoManager, FolderUndoOperation) {
            let manager = FolderUndoManager()
            let operation = FolderUndoOperation(record!)
            let store = self.store
            let entry = FolderUndoManager.Entry(name: record!.actionName,
                isValid: { direction in direction == .undo ? store.canUndoFolderDeletion(operation.record) : operation.record.redoTarget(in: store.state) != nil },
                isAvailable: { _ in operation.record.documentsAreAvailable },
                perform: { direction, done in
                    if direction == .undo { done((try? store.undoFolderDeletion(operation.record, shouldCommit: { true })) == true) }
                    else if let redo = operation.record.redoTarget(in: store.state) {
                        store.deleteFolder(redo, documents: operation.record.documentReferences, shouldCommit: { true }, didCommit: { operation.record = $0 }) { done((try? $0.get()) == true) }
                    } else { done(false) }
                })
            _ = manager.append(entry)
            return (manager, operation)
        }
    }

    @Test func theMixedSubtreeRetainsTheCompleteOriginalTypedSplit() throws {
        let m = try Mixed()
        #expect(m.target.tabs.count == 3)
        #expect(m.target.groups == [m.split])
    }

    @Test func internalURLsAloneCannotAuthorizeDocumentReferences() throws {
        let m = try Mixed()
        #expect(!SidebarDocumentReference.validates(m.target.tabs, references: [:]))
    }

    @Test func theExactOriginalProfileIsRequired() throws {
        let m = try Mixed()
        var wrong = m.documents
        wrong[m.n.id] = SidebarDocumentReference(page: .note(m.noteURL), profileID: UUID(), validate: { })
        #expect(!SidebarDocumentReference.validates(m.target.tabs, references: wrong))
    }

    @Test func anOrdinaryPageCannotAcquireATypedCapability() throws {
        let m = try Mixed()
        var wrong = m.documents
        wrong[m.w.id] = m.documents[m.n.id]
        #expect(!SidebarDocumentReference.validates(m.target.tabs, references: wrong))
    }

    @Test func aMissingCapabilityRefusesBeforeAnyNativeRetirement() throws {
        let m = try Mixed()
        var result: Result<Bool, Error>?
        m.store.deleteFolder(m.target, shouldCommit: { true }) { result = $0 }
        #expect(try result?.get() == false)
        #expect(m.calls == 0)
        #expect(m.store.state == m.initial)
    }

    @Test func theWholeOriginalSetAwaitsAGenuineCloseCallback() throws {
        let m = try Mixed()
        m.remove()
        #expect(m.requested == Set(m.split.tabIDs))
        #expect(m.result == nil)
        #expect(m.store.state == m.initial)
    }

    @Test func aCloseRefusalPreservesTheHierarchyReferencesAndAllDocumentBytes() throws {
        let m = try Mixed()
        m.remove()
        m.finish?(false)
        #expect(try m.result?.get() == false)
        #expect(m.store.state == m.initial)
        #expect(try Mixed.files(m.dataDirectory) == m.originalData)
    }

    @Test func theOriginalDocumentBecomesUnavailableDuringConsent() throws {
        let m = try Mixed()
        m.remove()
        let moved = m.notesFolder.appendingPathComponent("Moved away.md")
        try FileManager.default.moveItem(at: m.noteURL, to: moved)
        #expect(m.authorize?() == false)
    }

    @Test func anExpiredTypedCapabilityCannotPublishOrRegisterUndo() throws {
        let m = try Mixed()
        m.remove()
        let moved = m.notesFolder.appendingPathComponent("Moved away.md")
        try FileManager.default.moveItem(at: m.noteURL, to: moved)
        m.finish?(false)
        try FileManager.default.moveItem(at: moved, to: m.noteURL)
        #expect(m.store.state == m.initial)
        #expect(m.record == nil)
    }

    @Test func recoveredOriginalOwnersAuthorizeTheActualClose() throws {
        let m = try Mixed()
        m.remove()
        #expect(m.authorize?() == true)
    }

    @Test func anApprovedDeleteRemovesTheExactCompleteTree() throws {
        let m = try Mixed().closed()
        #expect(try m.result?.get() == true)
        #expect(m.store.state.folders.isEmpty)
    }

    @Test func onlyOriginalSubtreeAliasesAreArchived() throws {
        let m = try Mixed().closed()
        #expect(m.store.state.tabs.filter { $0.archivedAt != nil }.map(\.id) == [m.n.id, m.w.id, m.e.id])
    }

    @Test func aliasesInAnotherSpaceRemainUntouched() throws {
        let m = try Mixed().closed()
        #expect(m.store.state.tabs.first { $0.id == m.alias.id } == m.alias)
        #expect(m.store.state.tabs.first { $0.id == m.easelAlias.id } == m.easelAlias)
    }

    @Test func deleteWritesNoNoteOrEaselContentOrAsset() throws {
        let m = try Mixed().closed()
        #expect(try Mixed.files(m.dataDirectory) == m.originalData)
        #expect(try Data(contentsOf: m.noteURL) == m.noteOriginal)
    }

    @Test func undoRetainsFocusExactSplitGeometryAndEmptyDescendants() throws {
        let m = try Mixed().closed()
        let undo = try #require(m.record)
        #expect(undo.focusedTabID == m.e.id)
        #expect(undo.groups == [m.split])
        #expect(undo.folders.map(\.id).contains(m.empty.id))
    }

    @Test func exactTypedUndoIsAdmitted() throws {
        let m = try Mixed().closed()
        let undo = try #require(m.record)
        #expect(undo.documentsAreAvailable)
        #expect(m.store.canUndoFolderDeletion(undo))
    }

    @Test func sharedDocumentsRetainOriginalIdentityAfterAliasArchive() throws {
        let m = try Mixed().closed()
        #expect(FileManager.default.fileExists(atPath: m.noteURL.path))
        let loaded = try m.easels.load(m.easel.document.id)
        #expect(loaded === m.easel)
    }

    @Test func theRealNativeUndoStackAcceptsACommittedMixedClose() throws {
        let m = try Mixed().closed()
        let (manager, _) = m.undoEntry()
        #expect(manager.canUndo)
    }

    @Test func aMissingAssetDisablesButDoesNotPruneAStructurallyValidUndo() throws {
        let m = try Mixed().closed()
        let (manager, _) = m.undoEntry()
        try FileManager.default.removeItem(at: try m.easel.assetURL(m.asset))
        #expect(!manager.canUndo)
        #expect(m.store.canUndoFolderDeletion(m.record!))
    }

    @Test func directUndoAlsoRefusesMissingOriginalContent() throws {
        let m = try Mixed().closed()
        let archived = m.store.state
        try FileManager.default.removeItem(at: try m.easel.assetURL(m.asset))
        #expect(try !m.store.undoFolderDeletion(m.record!, shouldCommit: { true }))
        #expect(m.store.state == archived)
    }

    @Test func aRecoveredOriginalFileRestoresRetryEligibility() throws {
        let m = try Mixed().closed()
        let (manager, _) = m.undoEntry()
        let assetURL = try m.easel.assetURL(m.asset)
        try FileManager.default.removeItem(at: assetURL)
        try m.png.write(to: assetURL)
        #expect(manager.canUndo)
    }

    @Test func aRealDurableUndoFailurePreservesTheStackAndExactArchiveState() throws {
        let m = try Mixed().closed()
        let archived = m.store.state
        let (manager, _) = m.undoEntry()
        try FileManager.default.removeItem(at: m.sessionURL)
        try FileManager.default.createDirectory(at: m.sessionURL, withIntermediateDirectories: false)
        manager.undo()
        #expect(manager.canUndo)
        #expect(!manager.canRedo)
        #expect(m.store.state == archived)
    }

    private func undone(_ m: Mixed) throws -> (FolderUndoManager, BrowserState) {
        let archived = m.store.state
        let (manager, _) = m.undoEntry()
        manager.undo()
        return (manager, archived)
    }

    @Test func oneCommittedMixedUndoAdvancesTheNativeStack() throws {
        let m = try Mixed().closed()
        let (manager, _) = try undone(m)
        #expect(manager.canRedo)
        #expect(!manager.canUndo)
    }

    @Test func originalAliasAndWholeSplitIdentitiesReturnWithoutURLReplay() throws {
        let m = try Mixed().closed()
        _ = try undone(m)
        #expect(m.target.tabs.allSatisfy { original in m.store.state.tabs.contains(original) })
        #expect(m.store.state.splitLayouts.contains(m.split))
    }

    @Test func theTreeReturnsButTheStoreDoesNotStealAnotherWindowsFocus() throws {
        let m = try Mixed().closed()
        let (_, archived) = try undone(m)
        #expect(m.store.state.folders == m.initial.folders)
        #expect(m.store.state.selectedTabIDs == archived.selectedTabIDs)
    }

    @Test func undoPreservesSharedEditsAndExactAssetBytes() throws {
        let m = try Mixed().closed()
        try Data("Edited through surviving alias\n".utf8).write(to: m.noteURL)
        try m.easel.perform("Shared image edit") { $0.items[0].frame.x = 17 }
        let changedData = try Mixed.files(m.dataDirectory)
        _ = try undone(m)
        #expect(try Mixed.files(m.dataDirectory) == changedData)
        #expect(try String(contentsOf: m.noteURL, encoding: .utf8) == "Edited through surviving alias\n")
        #expect(m.easel.document.items[0].frame.x == 17)
    }

    @Test func redoReentersTheActualWholeSetConsent() throws {
        let m = try Mixed().closed()
        let (manager, _) = try undone(m)
        let before = m.calls
        manager.redo()
        #expect(manager.isBusy)
        #expect(m.calls == before + 1)
        #expect(m.requested == Set(m.split.tabIDs))
    }

    @Test func aRedoRefusalRemainsRetryable() throws {
        let m = try Mixed().closed()
        let (manager, _) = try undone(m)
        let beforeRedo = m.store.state
        manager.redo()
        m.finish?(false)
        #expect(manager.canRedo)
        #expect(m.store.state == beforeRedo)
    }

    @Test func redoRevalidatesTypedOriginalContent() throws {
        let m = try Mixed().closed()
        let (manager, _) = try undone(m)
        manager.redo()
        #expect(m.authorize?() == true)
    }

    @Test func anAcceptedRedoArchivesTheSameOriginalAliases() throws {
        let m = try Mixed().closed()
        let (manager, _) = try undone(m)
        manager.redo()
        _ = m.authorize?()
        m.finish?(true)
        #expect(manager.canUndo)
        #expect(m.store.state.tabs.filter { $0.archivedAt != nil }.count == 3)
    }

    @Test func actualLibraryDocumentDeletionInvalidatesTheOldAliasUndo() throws {
        let m = try Mixed().closed()
        let (manager, _) = m.undoEntry()
        let undo = m.record!
        m.store.requestPageRetirement = { _, admission, done in done(admission()) }
        var deletedError: Error?
        let noteURL = m.noteURL
        m.store.deleteLocalDocument(.note(noteURL), profileID: m.profile.id, ownerValid: { true }, deleteDocument: {
            try FileManager.default.removeItem(at: noteURL)
        }, completion: { deletedError = $0 })
        #expect(deletedError == nil)
        #expect(!undo.documentsAreAvailable)
        #expect(!m.store.canUndoFolderDeletion(undo))
        #expect(!manager.canUndo)
        #expect(try !m.store.undoFolderDeletion(undo, shouldCommit: { true }))
    }

    @Test func anUnrelatedEaselAndItsOriginalImageRemainAfterNoteDeletion() throws {
        let m = try Mixed().closed()
        m.store.requestPageRetirement = { _, admission, done in done(admission()) }
        let noteURL = m.noteURL
        m.store.deleteLocalDocument(.note(noteURL), profileID: m.profile.id, ownerValid: { true }, deleteDocument: {
            try FileManager.default.removeItem(at: noteURL)
        }, completion: { _ in })
        #expect(try Data(contentsOf: try m.easel.assetURL(m.asset)) == m.png)
        let loaded = try m.easels.load(m.easel.document.id)
        #expect(loaded === m.easel)
    }
}
