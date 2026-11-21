import AppKit
import Testing
@testable import Parc
@testable import ParcCore

@MainActor
struct DuplicateUndoTests {
    private final class Gate {
        var value = false
    }

    @MainActor private final class Dup {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("parc-duplicate-undo-" + UUID().uuidString)
        let profile = BrowserProfile(id: UUID(), name: "Original")
        let space: BrowserSpace
        let first: BrowserFolder
        let nested: BrowserFolder
        let second: BrowserFolder
        let target: BrowserFolder
        let noteFile: URL
        let noteBytes: Data
        let easels: EaselStore
        let easel: EaselSession
        let n: BrowserTab
        let w: BrowserTab
        let e: BrowserTab
        let loose: BrowserTab
        let today: BrowserTab
        let keep: BrowserTab
        let split: BrowserSplitLayout
        let pinned: SidebarContainerLocation
        let todayLocation: SidebarContainerLocation
        let secondLocation: SidebarContainerLocation
        let targetLocation: SidebarContainerLocation
        let containers: [SidebarContainerLocation]
        let store: BrowserStore
        let initial: BrowserState
        let blockedDocuments = Gate()
        var documentsBlocked: Bool {
            get { blockedDocuments.value }
            set { blockedDocuments.value = newValue }
        }
        var references: [UUID: SidebarDocumentReference] = [:]
        let copy: SidebarDuplicateResult
        let duplicated: BrowserState
        let record: SidebarCopyUndo
        let copiedIDs: Set<UUID>
        var retired: [Set<UUID>] = []
        var allowRetirement = true
        var restored: [SidebarCopyUndo] = []
        var removals = 0
        var undoUsable = true
        let manager = FolderUndoManager()
        var edited: BrowserState!
        var copiedFolderID: UUID!

        func tab(_ title: String, parent: UUID? = nil, kind: TabKind = .pinned, url: String? = nil) -> BrowserTab {
            Self.tab(title, space: space, profile: profile, parent: parent, kind: kind, url: url)
        }

        static func tab(_ title: String, space: BrowserSpace, profile: BrowserProfile, parent: UUID? = nil, kind: TabKind = .pinned, url: String? = nil) -> BrowserTab {
            let url = url ?? "https://saved.invalid/" + title
            return .init(id: UUID(), spaceID: space.id, profileID: profile.id, url: url, title: title, kind: kind, folderID: parent,
                         createdAt: Date(timeIntervalSince1970: 10), lastAccessed: Date(timeIntervalSince1970: 10), savedURL: url, savedTitle: title)
        }

        init() throws {
            let profile = self.profile
            let space = BrowserSpace(id: UUID(), name: "Here", symbol: "circle", color: "ABCDEF", profileID: profile.id)
            self.space = space
            first = BrowserFolder(id: UUID(), spaceID: space.id, name: "First")
            nested = BrowserFolder(id: UUID(), spaceID: space.id, name: "Nested", parentID: first.id, isExpanded: false)
            second = BrowserFolder(id: UUID(), spaceID: space.id, name: "Second")
            target = BrowserFolder(id: UUID(), spaceID: space.id, name: "Target")
            let notesFolder = root.appendingPathComponent("Parc Notes")
            try FileManager.default.createDirectory(at: notesFolder, withIntermediateDirectories: true)
            noteFile = notesFolder.appendingPathComponent("Original Note.md")
            try Data("Original body\n".utf8).write(to: noteFile)
            noteBytes = try Data(contentsOf: noteFile)
            easels = try EaselStore(directory: root.appendingPathComponent("Easels"))
            easel = try easels.create(title: "Shared Easel")
            let noteFile = self.noteFile
            n = Self.tab("Note", space: space, profile: profile, parent: nested.id, url: InternalPage.note(noteFile).urlString)
            w = Self.tab("Web", space: space, profile: profile, parent: nested.id)
            e = Self.tab("Easel", space: space, profile: profile, parent: second.id, url: InternalPage.easel(easel.document.id).urlString)
            loose = Self.tab("Loose", space: space, profile: profile, parent: second.id)
            today = Self.tab("Today", space: space, profile: profile, kind: .today)
            keep = Self.tab("Keep", space: space, profile: profile)
            split = BrowserSplitLayout(sidebarAnchorID: n.id, customTitle: "Mixed", spaceID: space.id, tabIDs: [n.id, w.id],
                                       orientation: .vertical, widthFactors: [0.3, 0.7])
            var state = BrowserState(profiles: [profile], spaces: [space], activeSpaceID: space.id)
            state.folders = [first, nested, second, target]
            state.tabs = [n, w, e, loose, today, keep]
            state.splitLayouts = [split]
            pinned = SidebarContainerLocation(spaceID: space.id, folderID: nil, section: .pinned)
            todayLocation = SidebarContainerLocation(spaceID: space.id, folderID: nil, section: .today)
            secondLocation = SidebarContainerLocation(spaceID: space.id, folderID: second.id, section: .pinned)
            targetLocation = SidebarContainerLocation(spaceID: space.id, folderID: target.id, section: .pinned)
            state.sidebarItemOrder[pinned.key] = [.tab(keep.id), .folder(first.id), .folder(second.id), .folder(target.id)]
            state.sidebarItemOrder[secondLocation.key] = [.tab(loose.id), .tab(e.id)]
            state.selectedTabIDs = [keep.id]
            state.selectionBySpace[space.id.uuidString] = [keep.id]
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(state).write(to: root.appendingPathComponent("session.json"))
            store = try BrowserStore(directory: root, now: { Date(timeIntervalSince1970: 1000) })
            initial = store.state
            let firstLocation = SidebarContainerLocation(spaceID: space.id, folderID: first.id, section: .pinned)
            let nestedLocation = SidebarContainerLocation(spaceID: space.id, folderID: nested.id, section: .pinned)
            containers = [pinned, todayLocation, secondLocation, targetLocation, firstLocation, nestedLocation]
            let easels = self.easels
            let easelID = easel.document.id
            let noteAvailable: @MainActor () throws -> Void = {
                guard FileManager.default.fileExists(atPath: noteFile.path) else { throw CocoaError(.fileNoSuchFile) }
            }
            let gate = blockedDocuments
            references = [n.id: SidebarDocumentReference(page: .note(noteFile), profileID: profile.id) {
                                if gate.value { throw CocoaError(.fileReadNoPermission) }
                                try noteAvailable() },
                          e.id: SidebarDocumentReference(page: .easel(easelID), profileID: profile.id) { try easels.validateReference(easelID) }]
            let items: [SidebarItemReference] = [.folder(first.id), .tab(e.id), .tab(today.id)]
            let duplicate = SidebarDuplicateTarget(items: items, spaceID: space.id, profileID: profile.id, state: initial)!
            let urls = Dictionary(uniqueKeysWithValues: duplicate.tabs.map { ($0.id, $0.savedURL) })
            copy = try store.duplicateSidebarItems(duplicate, destinations: urls, documents: references)!
            duplicated = store.state
            copiedIDs = Set(copy.tabIDs)
            record = SidebarCopyUndo(actionName: SidebarCopyUndo.duplicateName, roots: copy.roots, spaceID: space.id, profileID: profile.id,
                                     documents: Array(references.values), openTabIDs: copy.openTabIDs, state: duplicated)!
            store.requestPageRetirement = { [weak self] ids, canCommit, done in
                self?.retired.append(ids)
                done(self?.allowRetirement == true && canCommit())
            }
            let remover: (SidebarCopyUndo, FolderRemovalTarget, @escaping (SidebarCopyUndo?) -> Void) -> Void = { [weak self] record, target, done in
                guard let self else { return done(nil) }
                var refreshed: SidebarCopyUndo?
                removals += 1
                store.removeSidebarCopy(record, target: target, shouldCommit: { true }, didCommit: { refreshed = $0 }) { result in
                    done((try? result.get()) == true ? refreshed : nil)
                }
            }
            self.remover = remover
            manager.appendSidebarCopy(record, store: store, canUse: { [weak self] _, direction in direction == .redo || self?.undoUsable == true },
                                      remove: remover, didRestore: { [weak self] in self?.restored.append($0) }, onError: { _ in })
        }

        var remover: ((SidebarCopyUndo, FolderRemovalTarget, @escaping (SidebarCopyUndo?) -> Void) -> Void)!

        deinit { try? FileManager.default.removeItem(at: root) }

        func layout(_ state: BrowserState) -> [[SidebarItemReference]] { containers.map { SidebarHierarchy.children(in: $0, state: state) } }

        func edit() throws -> Dup {
            var renamed = store.state
            copiedFolderID = record.folders.first { $0.parentID == nil }!.id
            renamed.folders[renamed.folders.firstIndex { $0.id == copiedFolderID }!].name = "Renamed copy"
            let copiedWeb = record.tabs.first { $0.savedURL == w.savedURL }!.id
            renamed.tabs[renamed.tabs.firstIndex { $0.id == copiedWeb }!].url = "https://saved.invalid/Web/next"
            try store.commitProfileSettings(renamed)
            edited = store.state
            return self
        }

        func undone() throws -> Dup {
            _ = try edit()
            manager.undo()
            return self
        }

        func redone() throws -> Dup {
            _ = try undone()
            manager.redo()
            return self
        }

        func dragCopy(_ items: [SidebarItemReference], to destination: SidebarContainerLocation,
                      before: SidebarItemReference? = nil) throws -> (SidebarDuplicateResult, FolderUndoManager, SidebarCopyUndo) {
            store.requestPageRetirement = { _, canCommit, done in done(canCommit()) }
            let made = SidebarItemsCopy(items: items, spaceID: space.id, profileID: profile.id, state: store.state)!
            let sources = Dictionary(uniqueKeysWithValues: made.tabs.map { ($0.id, $0.savedURL) })
            let refs = references
            let docs = Dictionary(uniqueKeysWithValues: made.tabs.compactMap { tab -> (UUID, SidebarDocumentReference)? in
                guard let page = InternalPage(urlString: tab.savedURL) else { return nil }
                return refs.values.first { $0.page == page }.map { (tab.id, $0) }
            })
            let result = try store.copySidebarItems(made, to: destination, before: before, destinations: sources, documents: docs)!
            let record = SidebarCopyUndo(actionName: SidebarCopyUndo.dragCopyName, roots: result.roots, spaceID: space.id, profileID: profile.id,
                                         documents: Array(docs.values), openTabIDs: result.openTabIDs, state: store.state)!
            let manager = FolderUndoManager()
            manager.appendSidebarCopy(record, store: store, canUse: { _, _ in true }, remove: remover,
                                      didRestore: { [weak self] in self?.restored.append($0) }, onError: { _ in })
            return (result, manager, record)
        }
    }

    @Test func theRecordOwnsExactlyTheCopiedFoldersTabsAndWholeSplit() throws {
        let d = try Dup()
        #expect(Set(d.record.tabs.map(\.id)) == d.copiedIDs)
        #expect(d.record.folders.count == 2)
        #expect(d.record.groups.count == 1)
    }

    @Test func typedCopiesKeepTheOriginalDocumentReferences() throws {
        let d = try Dup()
        #expect(d.record.documentReferences.count == 2)
        #expect(d.record.documentsAreAvailable)
    }

    @Test func duplicateRegistersOneWindowUndoStep() throws {
        let d = try Dup()
        #expect(d.manager.canUndo)
        #expect(d.manager.undoMenuItemTitle == "Undo Duplicate")
    }

    @Test func undoWaitsWhileTheWindowCannotRetireACopy() throws {
        let d = try Dup()
        d.undoUsable = false
        #expect(!d.manager.canUndo)
    }

    @Test func declinedPageConsentLeavesEveryCopyAndTheUndoStepInPlace() throws {
        let d = try Dup().edit()
        d.allowRetirement = false
        d.manager.undo()
        #expect(d.store.state == d.edited)
        #expect(d.manager.canUndo)
        #expect(!d.manager.canRedo)
    }

    @Test func undoAsksExactlyTheCopiedPagesAndOnlyThemToClose() throws {
        let d = try Dup().edit()
        d.allowRetirement = false
        d.manager.undo()
        #expect(d.retired.last == d.copiedIDs)
    }

    @Test func undoRemovesEveryCopyAndLeavesTheOriginalTabsUntouched() throws {
        let d = try Dup().undone()
        #expect(d.store.state.tabs.allSatisfy { !d.copiedIDs.contains($0.id) })
        #expect(d.store.state.tabs == d.initial.tabs)
    }

    @Test func copiedFoldersAndSplitLeaveWhileOriginalsKeepTheirRecords() throws {
        let d = try Dup().undone()
        #expect(d.store.state.folders == d.initial.folders)
        #expect(d.store.state.splitLayouts == d.initial.splitLayouts)
    }

    @Test func everyContainerReturnsToItsPreDuplicateOrder() throws {
        let d = try Dup().undone()
        #expect(d.layout(d.store.state) == d.layout(d.initial))
    }

    @Test func undoKeepsTheWindowsSelection() throws {
        let d = try Dup().undone()
        #expect(d.store.state.selectedTabIDs == d.initial.selectedTabIDs)
        #expect(d.store.state.activeSpaceID == d.initial.activeSpaceID)
    }

    @Test func undoNeverTouchesTheSharedNoteOrEasel() throws {
        let d = try Dup().undone()
        #expect(try Data(contentsOf: d.noteFile) == d.noteBytes)
        let loaded = try d.easels.load(d.easel.document.id)
        #expect(loaded === d.easel)
    }

    @Test func undoneCopiesDoNotLandInTheArchive() throws {
        let d = try Dup().undone()
        #expect(d.store.archivedItems(profileID: d.profile.id).allSatisfy { $0.tabs.allSatisfy { !d.copiedIDs.contains($0.id) } })
    }

    @Test func undoMovesTheStepToRedo() throws {
        let d = try Dup().undone()
        #expect(d.manager.canRedo)
        #expect(d.manager.redoMenuItemTitle == "Redo Duplicate")
        #expect(!d.manager.canUndo)
    }

    @Test func theRemovalIsSaved() throws {
        let d = try Dup().undone()
        let reloaded = try BrowserStore(directory: d.root)
        #expect(reloaded.state.tabs.allSatisfy { !d.copiedIDs.contains($0.id) })
    }

    @Test func redoWaitsWhileACopiedDocumentCannotBeValidated() throws {
        let d = try Dup().undone()
        d.documentsBlocked = true
        #expect(!d.manager.canRedo)
    }

    @Test func redoReturnsWhenTheDocumentValidatesAgain() throws {
        let d = try Dup().undone()
        d.documentsBlocked = true
        d.documentsBlocked = false
        #expect(d.manager.canRedo)
    }

    @Test func redoPutsTheSameCopiesBackInTheSamePlaces() throws {
        let d = try Dup().redone()
        #expect(d.layout(d.store.state) == d.layout(d.edited))
    }

    @Test func redoRestoresTheCopiesWithTheirIdentitiesAndLaterEdits() throws {
        let d = try Dup().redone()
        #expect(d.store.state.tabs.filter { d.copiedIDs.contains($0.id) } == d.edited.tabs.filter { d.copiedIDs.contains($0.id) })
    }

    @Test func aCopyRenamedBeforeUndoComesBackRenamed() throws {
        let d = try Dup().redone()
        #expect(d.store.state.folders.first { $0.id == d.copiedFolderID }?.name == "Renamed copy")
    }

    @Test func redoRestoresTheNestedCopiedFolderAndTheCopiedSplitAsTheyWere() throws {
        let d = try Dup().redone()
        let folders = Set(d.record.folders.map(\.id))
        let groups = Set(d.record.groups.map(\.id))
        #expect(d.store.state.folders.filter { folders.contains($0.id) } == d.edited.folders.filter { folders.contains($0.id) })
        #expect(d.store.state.splitLayouts.filter { groups.contains($0.id) } == d.edited.splitLayouts.filter { groups.contains($0.id) })
        #expect(d.store.state.splitLayouts.filter { groups.contains($0.id) }.count == 1)
    }

    @Test func redoRestoresTheOrderInsideEveryCopiedFolder() throws {
        let d = try Dup().redone()
        #expect(d.record.folders.allSatisfy { folder in
            let location = SidebarContainerLocation(spaceID: d.space.id, folderID: folder.id, section: .pinned)
            return SidebarHierarchy.children(in: location, state: d.store.state) == SidebarHierarchy.children(in: location, state: d.edited)
                && !SidebarHierarchy.children(in: location, state: d.store.state).isEmpty
        })
    }

    @Test func redoHandsBackThePagesDuplicateOpened() throws {
        let d = try Dup().redone()
        #expect(d.restored.count == 1)
        #expect(d.restored[0].openTabIDs == d.copy.openTabIDs)
    }

    @Test func redoMakesTheCopyUndoableAgain() throws {
        let d = try Dup().redone()
        #expect(d.manager.canUndo)
        #expect(!d.manager.canRedo)
    }

    @Test func redoIsSaved() throws {
        let d = try Dup().redone()
        #expect(try BrowserStore(directory: d.root).state.tabs.filter { d.copiedIDs.contains($0.id) }.count == d.copiedIDs.count)
    }

    private func moveSecondAway(_ d: Dup) throws {
        let away = SidebarHierarchy.moving([.folder(d.second.id)], to: d.targetLocation, before: nil,
            expected: SidebarHierarchySnapshot(state: d.store.state, spaceID: d.space.id, profileID: d.profile.id)!, state: d.store.state)!
        try d.store.commitProfileSettings(away)
    }

    @Test func redoSkipsANeighbourThatMovedAwayAndLandsBesideTheNextSurvivor() throws {
        let d = try Dup().undone()
        try moveSecondAway(d)
        d.manager.redo()
        #expect(SidebarHierarchy.children(in: d.pinned, state: d.store.state) == [.tab(d.keep.id), .folder(d.first.id), d.copy.roots[0], .folder(d.target.id)])
    }

    @Test func movingTheNeighbourBackRestoresTheDuplicatedLayout() throws {
        let d = try Dup().undone()
        try moveSecondAway(d)
        d.manager.redo()
        let back = SidebarHierarchy.moving([.folder(d.second.id)], to: d.pinned, before: .folder(d.target.id),
            expected: SidebarHierarchySnapshot(state: d.store.state, spaceID: d.space.id, profileID: d.profile.id)!, state: d.store.state)!
        try d.store.commitProfileSettings(back)
        #expect(d.layout(d.store.state) == d.layout(d.edited))
    }

    @Test func aCopyMovedBeforeUndoRetiresTheStepInsteadOfRemovingTheMovedItem() throws {
        let d = try Dup().edit()
        var moved = d.store.state
        let copiedToday = d.record.tabs.first { $0.kind == .today }!.id
        moved.tabs[moved.tabs.firstIndex { $0.id == copiedToday }!].kind = .pinned
        try d.store.commitProfileSettings(moved)
        #expect(!d.manager.canUndo)
    }

    @Test func theRetiredStepNeverRunsInEitherDirection() throws {
        let d = try Dup().edit()
        var moved = d.store.state
        let copiedToday = d.record.tabs.first { $0.kind == .today }!.id
        moved.tabs[moved.tabs.firstIndex { $0.id == copiedToday }!].kind = .pinned
        try d.store.commitProfileSettings(moved)
        let before = d.removals
        d.manager.undo()
        d.manager.redo()
        #expect(d.store.state == moved)
        #expect(d.removals == before)
        #expect(!d.manager.canRedo)
    }

    private func folderCopy(_ d: Dup) throws -> SidebarCopyUndo {
        let unrelated = try d.store.duplicateSidebarItems(SidebarDuplicateTarget(items: [.folder(d.first.id)], spaceID: d.space.id,
            profileID: d.profile.id, state: d.store.state)!, destinations: [d.n.id: d.n.savedURL, d.w.id: d.w.savedURL], documents: [d.n.id: d.references[d.n.id]!])!
        return SidebarCopyUndo(actionName: SidebarCopyUndo.duplicateName, roots: unrelated.roots, spaceID: d.space.id, profileID: d.profile.id,
                               documents: Array(d.references.values), openTabIDs: unrelated.openTabIDs, state: d.store.state)!
    }

    @Test func aTabAddedToACopiedFolderProtectsTheFolderFromUndo() throws {
        let d = try Dup()
        let folderCopy = try folderCopy(d)
        var grown = d.store.state
        grown.tabs.append(d.tab("Added later", parent: folderCopy.folders.first { $0.parentID == nil }!.id))
        try d.store.commitProfileSettings(grown)
        #expect(folderCopy.matchingTarget(in: d.store.state) == nil)
    }

    private func selectedCopy(_ d: Dup) throws -> (SidebarCopyUndo, UUID) {
        let folderCopy = try folderCopy(d)
        let copiedSelection = folderCopy.tabs.first { InternalPage(urlString: $0.savedURL) == nil }!.id
        var focused = d.store.state
        focused.selectedTabIDs = [copiedSelection]
        focused.selectionBySpace[d.space.id.uuidString] = [copiedSelection]
        try d.store.commitProfileSettings(focused)
        return (folderCopy, copiedSelection)
    }

    @Test func undoingASelectedCopyMovesSelectionToASurvivingItem() throws {
        let d = try Dup()
        let (folderCopy, copiedSelection) = try selectedCopy(d)
        let folderTarget = folderCopy.matchingTarget(in: d.store.state)!
        let selection = FolderRemovalSelection.resolve(target: folderTarget, state: d.store.state, selected: [copiedSelection],
                                                       focused: copiedSelection, available: { _ in true })!
        var outcome: Result<Bool, Error>?
        d.store.removeSidebarCopy(folderCopy, target: folderTarget, selection: selection, shouldCommit: { true }) { outcome = $0 }
        #expect(!selection.tabIDs.isEmpty)
        #expect((try? outcome?.get()) == true)
        #expect(d.store.state.selectedTabIDs == selection.tabIDs)
        #expect(selection.tabIDs.allSatisfy { id in d.store.state.tabs.contains { $0.id == id && $0.archivedAt == nil } })
    }

    @Test func theSelectedCopyAndItsFolderAreRemoved() throws {
        let d = try Dup()
        let (folderCopy, copiedSelection) = try selectedCopy(d)
        let folderTarget = folderCopy.matchingTarget(in: d.store.state)!
        let selection = FolderRemovalSelection.resolve(target: folderTarget, state: d.store.state, selected: [copiedSelection],
                                                       focused: copiedSelection, available: { _ in true })!
        d.store.removeSidebarCopy(folderCopy, target: folderTarget, selection: selection, shouldCommit: { true }) { _ in }
        #expect(d.store.state.tabs.allSatisfy { !Set(folderCopy.tabs.map(\.id)).contains($0.id) })
    }

    private func pinToFolder(_ d: Dup) throws -> (CommandBarFolderCopy, FolderUndoManager, BrowserState) {
        let source = CommandBarFolderMoveSource(items: [.tab(d.loose.id)], spaceID: d.space.id, profileID: d.profile.id, state: d.store.state)!
        let move = CommandBarFolderMove.snapshot(source: source, state: d.store.state).first { $0.folder.folderID == d.target.id }!
        let before = d.store.state
        let pinnedCopy = try d.store.copyCommandBarItemsToFolder(move, destinations: [d.loose.id: d.loose.savedURL])!
        let record = SidebarCopyUndo(actionName: SidebarCopyUndo.folderCopyName, roots: pinnedCopy.roots, spaceID: d.space.id, profileID: d.profile.id,
                                     documents: [], openTabIDs: pinnedCopy.openTabIDs, state: d.store.state)!
        let manager = FolderUndoManager()
        manager.appendSidebarCopy(record, store: d.store, canUse: { _, _ in true }, remove: d.remover,
                                  didRestore: { _ in }, onError: { _ in })
        return (pinnedCopy, manager, before)
    }

    @Test func pinToFolderCopiesNameTheirOwnStep() throws {
        let d = try Dup()
        let (_, manager, _) = try pinToFolder(d)
        #expect(manager.undoMenuItemTitle == "Undo Copy to Folder")
    }

    @Test func undoTakesTheFolderCopyBackOutOfTheDestinationFolder() throws {
        let d = try Dup()
        let (copy, manager, before) = try pinToFolder(d)
        manager.undo()
        #expect(d.store.state.tabs.allSatisfy { !copy.tabIDs.contains($0.id) })
        #expect(d.layout(d.store.state) == d.layout(before))
    }

    @Test func redoPutsTheFolderCopyBackAtTheEndOfTheDestinationFolder() throws {
        let d = try Dup()
        let (copy, manager, _) = try pinToFolder(d)
        manager.undo()
        manager.redo()
        #expect(SidebarHierarchy.children(in: d.targetLocation, state: d.store.state) == copy.roots)
    }

    @Test func aCopyThatIsAlreadyClosingBlocksUndo() throws {
        let d = try Dup()
        let (copy, manager, _) = try pinToFolder(d)
        var retiring: ((Bool) -> Void)?
        d.store.requestPageRetirement = { _, _, done in retiring = done }
        d.store.closeTabs([copy.tabIDs[0]]) { _ in }
        #expect(!manager.canUndo)
        retiring?(false)
        #expect(manager.canUndo)
    }

    @Test func anOptionDragCopyRegistersUndoCopyAndKeepsItsEaselAliasesReferences() throws {
        let d = try Dup()
        let anchor = SidebarHierarchy.children(in: d.targetLocation, state: d.store.state).first
        let (_, manager, record) = try d.dragCopy([.tab(d.keep.id), .folder(d.second.id)], to: d.targetLocation, before: anchor)
        #expect(manager.undoMenuItemTitle == "Undo Copy")
        #expect(record.documentReferences.count == 2)
        #expect(record.documentsAreAvailable)
    }

    @Test func undoCopyRemovesTheDraggedCopiesAndLeavesTheOriginalsAndFolderUntouched() throws {
        let d = try Dup()
        let before = d.store.state
        let anchor = SidebarHierarchy.children(in: d.targetLocation, state: d.store.state).first
        let (_, manager, _) = try d.dragCopy([.tab(d.keep.id), .folder(d.second.id)], to: d.targetLocation, before: anchor)
        manager.undo()
        #expect(d.layout(d.store.state) == d.layout(before))
        #expect(d.store.state.tabs == before.tabs)
        #expect(d.store.state.folders == before.folders)
        #expect(manager.redoMenuItemTitle == "Redo Copy")
    }

    @Test func redoCopyPutsTheCopiesBackAtTheDropSpot() throws {
        let d = try Dup()
        let anchor = SidebarHierarchy.children(in: d.targetLocation, state: d.store.state).first
        let (dragged, manager, _) = try d.dragCopy([.tab(d.keep.id), .folder(d.second.id)], to: d.targetLocation, before: anchor)
        let draggedLayout = d.layout(d.store.state)
        manager.undo()
        manager.redo()
        #expect(d.layout(d.store.state) == draggedLayout)
        #expect(Array(SidebarHierarchy.children(in: d.targetLocation, state: d.store.state).prefix(2)) == dragged.roots)
    }

    @Test func copyingAndUndoingNeverTouchTheSharedDocuments() throws {
        let d = try Dup()
        let (_, manager, _) = try d.dragCopy([.tab(d.keep.id), .folder(d.second.id)], to: d.targetLocation)
        manager.undo()
        #expect(try Data(contentsOf: d.noteFile) == d.noteBytes)
        let loaded = try d.easels.load(d.easel.document.id)
        #expect(loaded === d.easel)
    }

    @Test func aWholeSplitOptionDragCopyCanBeUndone() throws {
        let d = try Dup()
        let (copy, manager, _) = try d.dragCopy([.split(d.split.id)], to: d.pinned, before: .tab(d.keep.id))
        guard case .split(let id)? = copy.roots.first else { Issue.record("split drag copy"); return }
        #expect(SidebarHierarchy.children(in: d.pinned, state: d.store.state).first == .split(id))
        #expect(manager.canUndo)
    }

    @Test func undoRemovesTheCopiedSplitWhole() throws {
        let d = try Dup()
        let before = d.store.state
        let (_, manager, _) = try d.dragCopy([.split(d.split.id)], to: d.pinned, before: .tab(d.keep.id))
        manager.undo()
        #expect(d.store.state.splitLayouts == before.splitLayouts)
        #expect(d.layout(d.store.state) == d.layout(before))
    }

    @Test func redoBringsTheCopiedSplitBackWithTheSameIdentity() throws {
        let d = try Dup()
        let (copy, manager, _) = try d.dragCopy([.split(d.split.id)], to: d.pinned, before: .tab(d.keep.id))
        guard case .split(let id)? = copy.roots.first else { Issue.record("split drag copy"); return }
        manager.undo()
        manager.redo()
        #expect(d.store.state.splitLayouts.contains { $0.id == id })
        #expect(SidebarHierarchy.children(in: d.pinned, state: d.store.state).first == .split(id))
    }

    private func withFavorite(_ d: Dup) throws -> (BrowserTab, SidebarContainerLocation) {
        var state = d.store.state
        let favorite = d.tab("Favorite", kind: .favorite)
        state.tabs.append(favorite)
        try d.store.commitProfileSettings(state)
        return (favorite, SidebarContainerLocation(spaceID: d.space.id, folderID: nil, section: .favorite, profileID: d.profile.id))
    }

    @Test func aCopyDroppedOnTheFavoritesTrayIsRecordedWithTheTray() throws {
        let d = try Dup()
        let (favorite, tray) = try withFavorite(d)
        let (copy, _, record) = try d.dragCopy([.tab(d.keep.id)], to: tray)
        #expect(record.includesFavorites)
        #expect(SidebarHierarchy.children(in: tray, state: d.store.state) == [.tab(favorite.id)] + copy.roots)
    }

    @Test func undoTakesTheCopiedFavoriteBackOutOfTheTray() throws {
        let d = try Dup()
        let (favorite, tray) = try withFavorite(d)
        let (copy, manager, _) = try d.dragCopy([.tab(d.keep.id)], to: tray)
        manager.undo()
        #expect(SidebarHierarchy.children(in: tray, state: d.store.state) == [.tab(favorite.id)])
        #expect(d.store.state.tab(copy.tabIDs[0]) == nil)
    }

    @Test func redoReturnsItToTheTray() throws {
        let d = try Dup()
        let (favorite, tray) = try withFavorite(d)
        let (copy, manager, _) = try d.dragCopy([.tab(d.keep.id)], to: tray)
        manager.undo()
        manager.redo()
        #expect(SidebarHierarchy.children(in: tray, state: d.store.state) == [.tab(favorite.id)] + copy.roots)
    }

    @Test func aFullTrayHoldsRedoBackInsteadOfOverfillingIt() throws {
        let d = try Dup()
        let (_, tray) = try withFavorite(d)
        let (_, manager, _) = try d.dragCopy([.tab(d.keep.id)], to: tray)
        manager.undo()
        var full = d.store.state
        full.tabs += (0..<11).map { d.tab("Filler\($0)", kind: .favorite) }
        try d.store.commitProfileSettings(full)
        #expect(!manager.canRedo)
    }

    @Test func aFavoriteTileCopiedIntoPinnedIsAnOrdinaryPinnedCopy() throws {
        let d = try Dup()
        let (favorite, _) = try withFavorite(d)
        let (copy, _, record) = try d.dragCopy([.tab(favorite.id)], to: d.pinned)
        #expect(!record.includesFavorites)
        #expect(d.store.state.tab(copy.tabIDs[0])?.kind == .pinned)
    }

    @Test func undoRemovesOnlyTheCopyNeverTheFavorite() throws {
        let d = try Dup()
        let (favorite, _) = try withFavorite(d)
        let (copy, manager, _) = try d.dragCopy([.tab(favorite.id)], to: d.pinned)
        manager.undo()
        #expect(d.store.state.tab(copy.tabIDs[0]) == nil)
        #expect(d.store.state.tab(favorite.id) != nil)
    }

    private func trayCopyInAnotherSpace(_ d: Dup) throws -> (SidebarDuplicateResult, SidebarCopyUndo, BrowserSpace, BrowserTab) {
        let (_, tray) = try withFavorite(d)
        var roomy = d.store.state
        let there = BrowserSpace(id: UUID(), name: "There", symbol: "circle", color: "FEDCBA", profileID: d.profile.id)
        var awayTab = d.tab("Away")
        awayTab.spaceID = there.id
        roomy.spaces.append(there)
        roomy.tabs.append(awayTab)
        try d.store.commitProfileSettings(roomy)
        let (shared, _, sharedRecord) = try d.dragCopy([.tab(d.keep.id)], to: tray)
        var elsewhere = d.store.state
        elsewhere.activeSpaceID = there.id
        elsewhere.selectedTabIDs = [shared.tabIDs[0]]
        elsewhere.selectionBySpace[there.id.uuidString] = [shared.tabIDs[0]]
        try d.store.commitProfileSettings(elsewhere)
        return (shared, sharedRecord, there, awayTab)
    }

    @Test func undoingATrayCopySelectedInAnotherSpaceHandsSelectionToThatSpacesOwnTab() throws {
        let d = try Dup()
        let (shared, record, there, awayTab) = try trayCopyInAnotherSpace(d)
        let target = record.matchingTarget(in: d.store.state)!
        let handoff = FolderRemovalSelection.resolve(target: target, state: d.store.state, spaceID: there.id,
                                                     selected: [shared.tabIDs[0]], focused: shared.tabIDs[0], available: { _ in true })
        #expect(handoff?.spaceID == there.id)
        #expect(handoff?.tabIDs == [awayTab.id])
    }

    @Test func copiesOutsideTheTrayStillResolveSelectionOnlyInTheirOwnSpace() throws {
        let d = try Dup()
        let (_, _, there, awayTab) = try trayCopyInAnotherSpace(d)
        let (_, _, dragRecord) = try d.dragCopy([.tab(d.keep.id), .folder(d.second.id)], to: d.targetLocation)
        #expect(FolderRemovalSelection.resolve(target: dragRecord.matchingTarget(in: d.store.state)!, state: d.store.state, spaceID: there.id,
                                               selected: [awayTab.id], focused: awayTab.id, available: { _ in true }) == nil)
    }

    @Test func theOtherSpaceKeepsShowingARealTabAfterTheTrayCopyIsUndone() throws {
        let d = try Dup()
        let (shared, record, there, awayTab) = try trayCopyInAnotherSpace(d)
        let target = record.matchingTarget(in: d.store.state)!
        let handoff = FolderRemovalSelection.resolve(target: target, state: d.store.state, spaceID: there.id,
                                                     selected: [shared.tabIDs[0]], focused: shared.tabIDs[0], available: { _ in true })
        var outcome: Result<Bool, Error>?
        d.store.removeSidebarCopy(record, target: target, selection: handoff, shouldCommit: { true }) { outcome = $0 }
        #expect((try? outcome?.get()) == true)
        #expect(d.store.state.tab(shared.tabIDs[0]) == nil)
        #expect(d.store.state.activeSpaceID == there.id)
        #expect(d.store.state.selectedTabIDs == [awayTab.id])
    }
}
