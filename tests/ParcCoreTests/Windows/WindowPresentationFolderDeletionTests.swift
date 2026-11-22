import Foundation
import Testing
@testable import ParcCore

@MainActor
struct WindowPresentationFolderDeletionTests {
    private typealias World = WindowPresentationTestsSupport.World
    private typealias StoreFixture = WindowPresentationTestsSupport.StoreFixture

    @MainActor private struct Deletion {
        let w = World()
        var state: BrowserState
        let removal: FolderRemovalSelection
        var origin: WindowPresentation
        var peer: WindowPresentation

        init() {
            state = w.shared
            state.tabs = [w.a, w.b, w.c, w.pin]
            state.activeSpaceID = w.firstSpace.id
            state.selectedTabIDs = [w.a.id]
            state.selectionBySpace[w.firstSpace.id.uuidString] = [w.a.id]
            origin = WindowPresentation(state: state, ready: true)
            peer = WindowPresentation(state: state, ready: true)
            removal = FolderRemovalSelection(spaceID: w.firstSpace.id, profileID: w.firstSpace.profileID,
                original: [w.a.id], originalFocus: w.a.id, tabIDs: [w.c.id], focusedTabID: w.c.id)
            state.tabs[state.tabs.firstIndex { $0.id == w.a.id }!].archivedAt = Date()
            state.selectedTabIDs = [w.c.id]
            origin.reconcile(state) { _ in true }
            peer.reconcile(state) { _ in true }
        }
    }

    @Test func theOriginalWindowAcceptsItsCompletedCloseDecisionAndAnotherWindowNeverAdoptsIt() {
        var d = Deletion()
        let finished = d.origin.finishFolderRemoval(d.removal, state: d.state, available: { _ in true })
        #expect(finished)
        #expect(d.origin.selectedTabIDs == [d.w.c.id] && d.origin.preferredFocusedTabID == d.w.c.id)
        #expect(d.peer.selectedTabIDs.isEmpty)
    }

    @Test func aNewerSpaceChoiceRejectsDelayedFolderFocus() {
        let d = Deletion()
        var moved = d.peer
        moved.selectSpace(d.w.otherSpace.id, state: d.state) { _ in true }
        let movedFinished = moved.finishFolderRemoval(d.removal, state: d.state, available: { _ in true })
        #expect(!movedFinished)
    }

    @Test func anAcquiredReplacementRejectsDelayedFolderFocus() {
        let d = Deletion()
        var transferred = d.peer
        let id = d.w.c.id
        let transferFinished = transferred.finishFolderRemoval(d.removal, state: d.state, available: { $0 != id })
        #expect(!transferFinished)
    }

    @Test func aNewerSelectionInTheOriginalWindowWinsOverDelayedCompletion() {
        let d = Deletion()
        var newer = d.peer
        _ = newer.selectExistingTab(d.w.pin.id, state: d.state) { _ in true }
        let finished = newer.finishFolderRemoval(d.removal, state: d.state, available: { _ in true })
        #expect(!finished && newer.selectedTabIDs == [d.w.pin.id])
    }

    @Test func aChangedDestinationProfileInvalidatesTheOldDecision() {
        var d = Deletion()
        var retired = d.state
        retired.spaces[retired.spaces.firstIndex { $0.id == d.w.firstSpace.id }!].profileID = d.w.otherProfile.id
        let finished = d.peer.finishFolderRemoval(d.removal, state: retired, available: { _ in true })
        #expect(!finished)
    }

    private func undoSplitDeletion() throws -> (
        fixture: StoreFixture, origin: WindowPresentation, peer: WindowPresentation,
        undo: FolderDeletionUndo, folder: UUID, space: UUID, profile: UUID, first: UUID, second: UUID
    ) {
        let s = try StoreFixture()
        let store = s.store
        let folder = store.createFolder(name: "Undo source")
        let undoA = store.open("https://undo-a.test")
        let undoB = store.open("https://undo-b.test")
        let space = store.activeSpaceID, profile = store.activeSpace.profileID
        store.selectTab(undoA)
        store.selectTab(undoB, extendingSplit: true)
        let group = try #require(store.activeSplitLayout)
        _ = try store.moveSidebarItem(.split(group.id), to: .init(spaceID: space, folderID: folder, section: .pinned), before: nil,
                                      expected: SidebarHierarchySnapshot(state: store.state, spaceID: space, profileID: profile)!)
        store.selectTab(undoA)
        _ = store.setSplitLayout(orientation: .vertical, widthFactors: [0.3, 0.7])
        let target = try #require(FolderRemovalTarget(folderID: folder, spaceID: space, profileID: profile, state: store.state))
        let selection = try #require(FolderRemovalSelection.resolve(target: target, state: store.state,
            selected: [undoA, undoB], focused: undoB, available: { _ in true }))
        var origin = WindowPresentation(state: store.state, ready: true)
        var peer = WindowPresentation(state: store.state, ready: true)
        var record: FolderDeletionUndo?
        store.deleteFolder(target, selection: selection, shouldCommit: { true }, didCommit: { record = $0 }) { _ in }
        origin.reconcile(store.state) { _ in true }
        peer.reconcile(store.state) { _ in true }
        let undo = try #require(record)
        let restored = try store.undoFolderDeletion(undo, shouldCommit: { true })
        try #require(restored)
        return (s, origin, peer, undo, folder, space, profile, undoA, undoB)
    }

    @Test func undoingAFolderDeletionSucceedsInTheStore() throws {
        _ = try undoSplitDeletion()
    }

    @Test func aPeerWindowKeepsItsEmptySelectionAfterUndo() throws {
        let restored = try undoSplitDeletion()
        var peer = restored.peer
        peer.reconcile(restored.fixture.store.state) { _ in true }
        #expect(peer.selectedTabIDs.isEmpty)
    }

    @Test func aMissingPaneBlocksRestoringTheDeletedSplitToTheOriginalWindow() throws {
        let restored = try undoSplitDeletion()
        var origin = restored.origin
        let blocked = origin.finishFolderUndo(restored.undo, state: restored.fixture.store.state, available: { $0 != restored.first })
        #expect(!blocked)
    }

    @Test func undoRestoresTheOriginalWindowsSplitGeometryAndFocus() throws {
        let restored = try undoSplitDeletion()
        var origin = restored.origin
        let state = restored.fixture.store.state
        _ = origin.finishFolderUndo(restored.undo, state: state, available: { $0 != restored.first })
        let finished = origin.finishFolderUndo(restored.undo, state: state, available: { _ in true })
        #expect(finished)
        #expect(origin.selectedTabIDs == [restored.first, restored.second] && origin.preferredFocusedTabID == restored.second)
        #expect(origin.splitLayout?.orientation == .vertical && origin.splitLayout?.widthFactors == [0.3, 0.7])
    }

    @Test func undoCannotRestoreTheSplitToAPeerWindow() throws {
        let restored = try undoSplitDeletion()
        let store = restored.fixture.store
        var peer = restored.peer
        peer.reconcile(store.state) { _ in true }
        var origin = restored.origin
        _ = origin.finishFolderUndo(restored.undo, state: store.state, available: { $0 != restored.first })
        _ = origin.finishFolderUndo(restored.undo, state: store.state, available: { _ in true })
        let target = try #require(FolderRemovalTarget(folderID: restored.folder, spaceID: restored.space,
                                                     profileID: restored.profile, state: store.state))
        var record: FolderDeletionUndo?
        store.deleteFolder(target, shouldCommit: { true }, didCommit: { record = $0 }) { _ in }
        let secondUndo = try #require(record)
        _ = try store.undoFolderDeletion(secondUndo, shouldCommit: { true })
        let background = peer.finishFolderUndo(secondUndo, state: store.state, available: { _ in true })
        #expect(!background)
    }
}
