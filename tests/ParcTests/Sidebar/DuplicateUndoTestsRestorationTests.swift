import AppKit
import Testing
@testable import Parc
@testable import ParcCore

@MainActor
struct DuplicateUndoTestsRestorationTests {
    private typealias Dup = DuplicateUndoTestsSupport.Dup

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
}
