import AppKit
import Testing
@testable import Parc
@testable import ParcCore

@MainActor
struct SidebarPluralRemovalTests {
    @MainActor private final class World {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("parc-plural-removal-" + UUID().uuidString)
        let profile = BrowserProfile(id: UUID(), name: "Original")
        let space: BrowserSpace
        let folder: BrowserFolder
        let nested: BrowserFolder
        let second: BrowserFolder
        let empty: BrowserFolder
        let remaining: BrowserFolder
        let notesFolder: URL
        let noteFile: URL
        let noteBytes: Data
        let n: BrowserTab
        let w: BrowserTab
        let b: BrowserTab
        let loose: BrowserTab
        let today: BrowserTab
        let keep: BrowserTab
        let alias: BrowserTab
        let oldArchived: BrowserTab
        let split: BrowserSplitLayout
        let pinned: SidebarContainerLocation
        let sessionURL: URL
        let store: BrowserStore
        let initial: BrowserState
        let proposed: [SidebarItemReference]
        let target: FolderRemovalTarget
        let docs: [UUID: SidebarDocumentReference]
        let encoder = JSONEncoder()
        var authorize: (() -> Bool)?
        var finish: ((Bool) -> Void)?
        var requested = Set<UUID>()
        var admissions = 0
        var result: Result<Bool, Error>?
        var undo: FolderDeletionUndo?
        var originalSelection = true

        static func tab(_ title: String, space: BrowserSpace, profile: BrowserProfile, folder: UUID?, kind: TabKind = .pinned,
                        url: String = "https://original.invalid/") -> BrowserTab {
            .init(id: UUID(), spaceID: space.id, profileID: profile.id, url: url, title: title, kind: kind, folderID: folder,
                  createdAt: Date(timeIntervalSince1970: 10), lastAccessed: Date(timeIntervalSince1970: 10), savedURL: url, savedTitle: title)
        }

        init() throws {
            encoder.dateEncodingStrategy = .iso8601
            let space = BrowserSpace(id: UUID(), name: "Here", symbol: "circle", color: "ABCDEF", profileID: profile.id)
            self.space = space
            folder = BrowserFolder(id: UUID(), spaceID: space.id, name: "First")
            nested = BrowserFolder(id: UUID(), spaceID: space.id, name: "Nested", parentID: folder.id)
            second = BrowserFolder(id: UUID(), spaceID: space.id, name: "Second")
            empty = BrowserFolder(id: UUID(), spaceID: space.id, name: "Empty")
            remaining = BrowserFolder(id: UUID(), spaceID: space.id, name: "Keep")
            notesFolder = root.appendingPathComponent("Parc Notes")
            try FileManager.default.createDirectory(at: notesFolder, withIntermediateDirectories: true)
            noteFile = notesFolder.appendingPathComponent("Shared.md")
            try Data("Original body\n".utf8).write(to: noteFile)
            noteBytes = try Data(contentsOf: noteFile)
            let noteFile = self.noteFile
            let profile = self.profile
            n = Self.tab("Note", space: space, profile: profile, folder: nested.id, url: InternalPage.note(noteFile).urlString)
            w = Self.tab("Web", space: space, profile: profile, folder: nested.id)
            b = Self.tab("Second child", space: space, profile: profile, folder: second.id)
            loose = Self.tab("Loose pinned", space: space, profile: profile, folder: remaining.id)
            today = Self.tab("Today", space: space, profile: profile, folder: nil, kind: .today)
            keep = Self.tab("Survivor", space: space, profile: profile, folder: nil)
            alias = Self.tab("Surviving alias", space: space, profile: profile, folder: nil, url: InternalPage.note(noteFile).urlString)
            split = BrowserSplitLayout(sidebarAnchorID: n.id, customTitle: "Mixed", spaceID: space.id, tabIDs: [n.id, w.id],
                                       orientation: .vertical, widthFactors: [0.3, 0.7])
            var oldArchived = Self.tab("Earlier archive", space: space, profile: profile, folder: nested.id)
            oldArchived.archivedAt = Date(timeIntervalSince1970: 20)
            self.oldArchived = oldArchived
            var state = BrowserState(profiles: [profile], spaces: [space], activeSpaceID: space.id)
            state.folders = [folder, nested, second, empty, remaining]
            state.tabs = [n, w, b, loose, today, keep, alias, oldArchived]
            state.splitLayouts = [split]
            pinned = SidebarContainerLocation(spaceID: space.id, folderID: nil, section: .pinned)
            state.sidebarItemOrder[pinned.key] = [.tab(keep.id), .folder(folder.id), .folder(second.id), .folder(empty.id), .folder(remaining.id), .tab(alias.id)]
            state.selectedTabIDs = split.tabIDs
            state.selectionBySpace[space.id.uuidString] = split.tabIDs
            sessionURL = root.appendingPathComponent("session.json")
            try encoder.encode(state).write(to: sessionURL)
            store = try BrowserStore(directory: root, now: { Date(timeIntervalSince1970: 1_900_000_000) })
            initial = store.state
            proposed = [.folder(folder.id), .folder(nested.id), .split(split.id), .folder(second.id), .folder(empty.id), .tab(loose.id), .tab(today.id)]
            target = FolderRemovalTarget(items: proposed, spaceID: space.id, profileID: profile.id, state: initial)!
            let noteAvailable: @MainActor () throws -> Void = {
                guard FileManager.default.fileExists(atPath: noteFile.path) else { throw CocoaError(.fileNoSuchFile) }
            }
            docs = [n.id: SidebarDocumentReference(page: .note(noteFile), profileID: profile.id, validate: noteAvailable)]
            store.requestPageRetirement = { [weak self] ids, canCommit, done in
                self?.requested = ids
                self?.authorize = canCommit
                self?.finish = done
                self?.admissions += 1
            }
        }

        deinit { try? FileManager.default.removeItem(at: root) }

        func target(_ items: [SidebarItemReference], profile: UUID? = nil, state: BrowserState? = nil) -> FolderRemovalTarget? {
            FolderRemovalTarget(items: items, spaceID: space.id, profileID: profile ?? self.profile.id, state: state ?? initial)
        }

        func remove(_ t: FolderRemovalTarget? = nil) {
            result = nil
            store.deleteFolder(t ?? target, documents: docs, shouldCommit: { [weak self] in self?.originalSelection ?? false },
                               didCommit: { [weak self] in self?.undo = $0 }) { [weak self] in self?.result = $0 }
        }

        func removed() -> World {
            remove()
            _ = authorize?()
            finish?(true)
            return self
        }

        func undoManager(for record: FolderDeletionUndo) -> FolderUndoManager {
            let manager = FolderUndoManager()
            let operation = FolderUndoOperation(record)
            let store = self.store
            _ = manager.append(.init(name: record.actionName,
                isValid: { $0 == .undo ? store.canUndoFolderDeletion(operation.record) : operation.record.redoTarget(in: store.state) != nil },
                isAvailable: { _ in operation.record.documentsAreAvailable },
                perform: { direction, done in
                    if direction == .undo { done((try? store.undoFolderDeletion(operation.record, shouldCommit: { true })) == true) }
                    else if let redo = operation.record.redoTarget(in: store.state) {
                        store.deleteFolder(redo, documents: operation.record.documentReferences, shouldCommit: { true }, didCommit: { operation.record = $0 }) { done((try? $0.get()) == true) }
                    } else { done(false) }
                }))
            return manager
        }
    }

    @Test func anAncestorRootSuppressesSelectedNestedFolderAndSplitExactlyOnce() throws {
        let w = try World()
        #expect(w.target.roots == [.folder(w.folder.id), .folder(w.second.id), .folder(w.empty.id), .tab(w.loose.id), .tab(w.today.id)])
    }

    @Test func capturedOriginalPagesAreUniqueAcrossMixedRoots() throws {
        let w = try World()
        #expect(Set(w.target.tabs.map(\.id)) == Set([w.n.id, w.w.id, w.b.id, w.loose.id, w.today.id]))
        #expect(w.target.tabs.count == 5)
    }

    @Test func wholeSplitGeometryAndEmptyDescendantsAreRetained() throws {
        let w = try World()
        #expect(w.target.groups == [w.split])
        #expect(w.target.folderIDs.count == 4)
    }

    @Test func aHiddenPaneCannotBeTargetedSeparatelyFromItsWholeSplit() throws {
        let w = try World()
        #expect(w.target([.tab(w.n.id)]) == nil)
    }

    @Test func duplicateRootInputIsRefused() throws {
        let w = try World()
        #expect(w.target([.folder(w.folder.id), .folder(w.folder.id)]) == nil)
    }

    @Test func aWrongOriginalProfileIsRefused() throws {
        let w = try World()
        #expect(w.target(w.proposed, profile: UUID()) == nil)
    }

    @Test func aForeignDescendantCannotPartiallyParticipate() throws {
        let w = try World()
        var foreign = w.initial
        foreign.tabs[0].profileID = UUID()
        #expect(w.target(w.proposed, state: foreign) == nil)
    }

    @Test func folderDescendantsRetainTheSavedKindInvariant() throws {
        let w = try World()
        var malformed = w.initial
        malformed.tabs[0].kind = .today
        #expect(w.target(w.proposed, state: malformed) == nil)
    }

    @Test func nextFocusExcludesEveryRemovedRoot() throws {
        let w = try World()
        let selection = FolderRemovalSelection.resolve(target: w.target, state: w.initial, selected: w.split.tabIDs, focused: w.w.id, available: { _ in true })!
        #expect(!selection.tabIDs.isEmpty)
        #expect(Set(selection.tabIDs).isDisjoint(with: w.target.tabs.map(\.id)))
    }

    @Test func oneCompleteSetReachesTheConsentBoundaryWithoutModelMutation() throws {
        let w = try World()
        w.remove()
        #expect(w.requested == Set(w.target.tabs.map(\.id)))
        #expect(w.admissions == 1)
        #expect(w.result == nil)
        #expect(w.store.state == w.initial)
    }

    @Test func aChangedOriginalSelectionWhileAwaitingConsentRefuses() throws {
        let w = try World()
        w.remove()
        w.originalSelection = false
        #expect(w.authorize?() == false)
    }

    @Test func aRefusalLeavesEveryRootUnchangedAndCreatesNoUndo() throws {
        let w = try World()
        w.remove()
        w.originalSelection = false
        _ = w.authorize?()
        w.finish?(false)
        #expect(try w.result?.get() == false)
        #expect(w.undo == nil)
        #expect(w.store.state == w.initial)
    }

    @Test func anyNativeBeforeUnloadRefusalCancelsTheWholeCollection() throws {
        let w = try World()
        w.remove()
        w.finish?(false)
        #expect(w.store.state == w.initial)
        #expect(w.undo == nil)
    }

    @Test func typedReferenceLossInvalidatesAllRootsDuringNativeConsent() throws {
        let w = try World()
        w.remove()
        try FileManager.default.moveItem(at: w.noteFile, to: w.notesFolder.appendingPathComponent("Moved away.md"))
        #expect(w.authorize?() == false)
    }

    @Test func aTypedRefusalArchivesNoUnrelatedWebRoot() throws {
        let w = try World()
        w.remove()
        let moved = w.notesFolder.appendingPathComponent("Moved away.md")
        try FileManager.default.moveItem(at: w.noteFile, to: moved)
        _ = w.authorize?()
        w.finish?(false)
        try FileManager.default.moveItem(at: moved, to: w.noteFile)
        #expect(w.store.state == w.initial)
    }

    @Test func originalOwnersRemainEligible() throws {
        let w = try World()
        w.remove()
        #expect(w.authorize?() == true)
    }

    @Test func aFailedDiskCommitLeavesAllOriginalRootsAndNoUndoEntry() throws {
        let w = try World()
        w.remove()
        _ = w.authorize?()
        try FileManager.default.removeItem(at: w.sessionURL)
        try FileManager.default.createDirectory(at: w.sessionURL, withIntermediateDirectories: false)
        w.finish?(true)
        guard case .failure? = w.result else { Issue.record("Expected atomic save failure"); return }
        #expect(w.store.state == w.initial)
        #expect(w.undo == nil)
    }

    @Test func oneSuccessfulTransactionRemovesOnlyTheCapturedFolderRecords() throws {
        let w = try World().removed()
        #expect(try w.result?.get() == true)
        #expect(w.store.state.folders == [w.remaining])
    }

    @Test func originalTodayPinnedTypedAndSplitRecordsAreAllArchived() throws {
        let w = try World().removed()
        let ids = w.target.tabs.map(\.id)
        #expect(w.store.state.tabs.filter { ids.contains($0.id) }.allSatisfy { $0.archivedAt != nil })
    }

    @Test func anUnselectedPageAndDocumentAliasAreUntouched() throws {
        let w = try World().removed()
        #expect(w.store.state.tabs.first { $0.id == w.keep.id } == w.keep)
        #expect(w.store.state.tabs.first { $0.id == w.alias.id } == w.alias)
    }

    @Test func anEarlierArchiveIsSafelyDetachedFromTheDeletedFolder() throws {
        let w = try World().removed()
        #expect(w.store.state.tabs.first { $0.id == w.oldArchived.id }?.folderID == nil)
    }

    @Test func noDocumentWriteOrSessionCloneHappens() throws {
        let w = try World().removed()
        #expect(try Data(contentsOf: w.noteFile) == w.noteBytes)
    }

    @Test func undoRetainsRootsAcrossThreeOriginalContainers() throws {
        let w = try World().removed()
        let record = try #require(w.undo)
        #expect(record.roots == w.target.roots)
        #expect(record.locations.count == 3)
        #expect(record.groups == [w.split])
    }

    private func independentStore(_ w: World) throws -> (BrowserStore, BrowserTab) {
        var independent = w.store.state
        let inserted = World.tab("Inserted later", space: w.space, profile: w.profile, folder: nil)
        independent.tabs.append(inserted)
        independent.sidebarItemOrder[w.pinned.key, default: []].insert(.tab(inserted.id), at: 0)
        let url = w.root.appendingPathComponent("independent")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try w.encoder.encode(independent).write(to: url.appendingPathComponent("session.json"))
        return (try BrowserStore(directory: url), inserted)
    }

    @Test func undoToleratesAnUnrelatedSurvivingSiblingInsertion() throws {
        let w = try World().removed()
        let (store, _) = try independentStore(w)
        #expect(try store.undoFolderDeletion(w.undo!, shouldCommit: { true }))
    }

    @Test func undoNeverRollsBackUnrelatedRecords() throws {
        let w = try World().removed()
        let (store, inserted) = try independentStore(w)
        _ = try store.undoFolderDeletion(w.undo!, shouldCommit: { true })
        #expect(store.state.tabs.contains(inserted))
    }

    @Test func eachOriginalRootUsesSurvivingLocalAnchors() throws {
        let w = try World().removed()
        let (store, inserted) = try independentStore(w)
        _ = try store.undoFolderDeletion(w.undo!, shouldCommit: { true })
        let order = SidebarHierarchy.children(in: w.pinned, state: store.state)
        #expect(order.first == .tab(inserted.id))
        #expect(order.filter { $0 != .tab(inserted.id) } == SidebarHierarchy.children(in: w.pinned, state: w.initial))
    }

    @Test func oneActualUndoGroupNamesTheWholeCollection() throws {
        let w = try World().removed()
        let manager = w.undoManager(for: w.undo!)
        #expect(manager.canUndo)
        #expect(manager.undoActionName == "Archive Tabs")
    }

    @Test func undoRestoresExactOriginalFolderIDs() throws {
        let w = try World().removed()
        w.undoManager(for: w.undo!).undo()
        #expect(w.store.state.folders.sorted { $0.id.uuidString < $1.id.uuidString } == w.initial.folders.sorted { $0.id.uuidString < $1.id.uuidString })
    }

    @Test func undoRestoresOriginalRecordsAndSplitShape() throws {
        let w = try World().removed()
        w.undoManager(for: w.undo!).undo()
        #expect(w.store.state.tabs == w.initial.tabs)
        #expect(w.store.state.splitLayouts == w.initial.splitLayouts)
    }

    @Test func undoRestoresOriginalMixedSiblingOrder() throws {
        let w = try World().removed()
        w.undoManager(for: w.undo!).undo()
        #expect(SidebarHierarchy.children(in: w.pinned, state: w.store.state) == SidebarHierarchy.children(in: w.pinned, state: w.initial))
    }

    @Test func anUnchangedEarlierArchiveRecoversItsOriginalFolderReference() throws {
        let w = try World().removed()
        w.undoManager(for: w.undo!).undo()
        #expect(w.store.state.tabs.first { $0.id == w.oldArchived.id } == w.oldArchived)
    }

    @Test func theWholeGroupMovesToTheNativeRedoStack() throws {
        let w = try World().removed()
        let manager = w.undoManager(for: w.undo!)
        manager.undo()
        #expect(manager.canRedo)
        #expect(!manager.canUndo)
    }

    private func undone(_ w: World) -> FolderUndoManager {
        let manager = w.undoManager(for: w.undo!)
        manager.undo()
        return manager
    }

    @Test func redoWaitsForFreshActualPageConsent() throws {
        let w = try World().removed()
        let manager = undone(w)
        manager.redo()
        #expect(manager.isBusy)
        #expect(w.store.state.tabs == w.initial.tabs)
    }

    @Test func aRedoRefusalPreservesRetryAndAllOriginals() throws {
        let w = try World().removed()
        let manager = undone(w)
        manager.redo()
        w.finish?(false)
        #expect(manager.canRedo)
        #expect(w.store.state.tabs == w.initial.tabs)
    }

    @Test func redoCommitsOneGroupAfterConsent() throws {
        let w = try World().removed()
        let manager = undone(w)
        manager.redo()
        #expect(w.authorize?() == true)
        w.finish?(true)
        #expect(manager.canUndo)
        #expect(!manager.canRedo)
        #expect(w.store.state.folders == [w.remaining])
    }

    private func redone(_ w: World) -> BrowserStore {
        let manager = undone(w)
        manager.redo()
        _ = w.authorize?()
        w.finish?(true)
        manager.undo()
        return w.store
    }

    @Test func redoNeverExpandsToANewlyInsertedChild() throws {
        let w = try World().removed()
        let store = redone(w)
        var changed = store.state
        changed.tabs.append(World.tab("New child", space: w.space, profile: w.profile, folder: w.second.id))
        try w.encoder.encode(changed).write(to: w.sessionURL)
        let other = try BrowserStore(directory: w.root)
        #expect(w.undo!.redoTarget(in: other.state) == nil)
    }

    @Test func aReparentedOriginalInvalidatesTheWholeRedo() throws {
        let w = try World().removed()
        let store = redone(w)
        var moved = store.state
        moved.tabs[moved.tabs.firstIndex { $0.id == w.loose.id }!].folderID = nil
        #expect(w.undo!.redoTarget(in: moved) == nil)
    }

    @Test func aChangedRootSectionInvalidatesRedoOwnership() throws {
        let w = try World().removed()
        let store = redone(w)
        var repinned = store.state
        repinned.tabs[repinned.tabs.firstIndex { $0.id == w.today.id }!].kind = .pinned
        #expect(w.undo!.redoTarget(in: repinned) == nil)
    }

    @Test func anExplicitTabOnlyArchiveUsesTheSameCollectionOwner() throws {
        let w = try World()
        let noFolders = w.target([.tab(w.today.id), .tab(w.keep.id)])!
        #expect(noFolders.folderIDs.isEmpty)
        #expect(noFolders.tabs.count == 2)
    }
}
