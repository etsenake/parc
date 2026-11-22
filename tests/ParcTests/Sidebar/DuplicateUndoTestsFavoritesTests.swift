import AppKit
import Testing
@testable import Parc
@testable import ParcCore
@testable import ParcSidebar

@MainActor
struct DuplicateUndoTestsFavoritesTests {
    private typealias Dup = DuplicateUndoTestsSupport.Dup

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
