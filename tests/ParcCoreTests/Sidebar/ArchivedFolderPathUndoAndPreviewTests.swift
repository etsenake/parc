import Foundation
import Testing
@testable import ParcCore

extension ArchivedFolderPathTestsSupport {
    @MainActor
    struct ArchivedFolderPathUndoAndPreviewTests {
        typealias Retirement = (ids: Set<UUID>, gate: () -> Bool, done: (Bool) -> Void)

        final class Retirements { var list: [Retirement] = [] }

        func deleteWhileRetiring(_ store: BrowserStore, _ f: Fixture, pending: Retirements) throws {
            let target = try #require(FolderRemovalTarget(items: [.folder(f.work.id)], spaceID: f.space.id, profileID: f.profile.id, state: store.state))
            var result: Result<Bool, Error>?
            store.deleteFolder(target, shouldCommit: { true }) { result = $0 }
            #expect(pending.list.count == 2)
            #expect(pending.list[1].gate())
            pending.list[1].done(true)
            #expect(try result?.get() == true)
        }

        @Test func undoIsAvailableRightAfterDeletionAndReturnsAnOlderArchivedTabToItsExactEarlierRecord() throws {
            let f = try Fixture()
            let store = try f.store()
            try f.delete([.tab(f.i2)], in: store)
            let olderArchive = try f.tab(f.i2, store)
            let undo = try f.delete([.folder(f.work.id)], in: store)
            #expect(store.canUndoFolderDeletion(undo))
            #expect(try store.undoFolderDeletion(undo, shouldCommit: { true }))
            #expect(try f.tab(f.i2, store) == olderArchive)
            #expect(store.state.folders.count == 2)
            #expect(SidebarHierarchy.children(in: f.innerContents, state: store.state) == [.tab(f.i1)])
        }

        @Test func undoRefusesOncePutBackHasRebuiltTheFolderAndChangesNothing() throws {
            let f = try Fixture()
            let store = try f.store()
            let undo = try f.delete([.folder(f.work.id)], in: store)
            try f.putBack(f.i1, in: store)
            let rebuilt = store.state
            #expect(!store.canUndoFolderDeletion(undo))
            #expect(try !store.undoFolderDeletion(undo, shouldCommit: { true }))
            #expect(store.state == rebuilt)
            #expect(f.folderCount(f.work.id, store) == 1)
            #expect(f.folderCount(f.inner.id, store) == 1)
        }

        @Test func puttingBackAnOlderArchivedTabThatRebuildsTheFolderAlsoRetiresUndo() throws {
            let f = try Fixture()
            let store = try f.store()
            try f.delete([.tab(f.i2)], in: store)
            let undo = try f.delete([.folder(f.work.id)], in: store)
            try f.putBack(f.i2, in: store)
            #expect(!store.canUndoFolderDeletion(undo))
            #expect(f.folderCount(f.work.id, store) == 1)
            #expect(try !store.undoFolderDeletion(undo, shouldCommit: { true }))
            #expect(store.state.folders.count == 2)
        }

        @Test func undoWaitsWhileADeletedTabIsOpenInAnArchivePreviewAndWorksOnceItCloses() throws {
            let f = try Fixture()
            let store = try f.store()
            let undo = try f.delete([.folder(f.work.id)], in: store)
            let lease = try #require(store.acquireArchivePreview(id: f.w1, profileID: f.profile.id))
            let archived = store.state
            #expect(try !store.undoFolderDeletion(undo, shouldCommit: { true }))
            #expect(store.state == archived)
            #expect(store.archivePreviewIsValid(lease))
            store.releaseArchivePreview(lease)
            #expect(try store.undoFolderDeletion(undo, shouldCommit: { true }))
            #expect(store.state.folders.count == 2)
        }

        @Test func aPreviewedOlderArchiveGainsExactlyTheSamePathAsOneWithoutAPreview() throws {
            let f = try Fixture()
            let store = try f.store()
            try f.delete([.tab(f.i1)], in: store)
            try f.delete([.tab(f.i2)], in: store)
            let lease = try #require(store.acquireArchivePreview(id: f.i2, profileID: f.profile.id))
            try f.delete([.folder(f.work.id)], in: store)
            let plain = try f.tab(f.i1, store), previewed = try f.tab(f.i2, store)
            #expect(plain.folderID == nil)
            #expect(plain.archiveProvenance?.folderPath?.parentID == nil)
            #expect(plain.archiveProvenance?.folderPath?.folders.map(\.id) == [f.work.id, f.inner.id])
            #expect(previewed.folderID == nil)
            #expect(previewed.archiveProvenance?.folderPath == plain.archiveProvenance?.folderPath)
            #expect(store.archivePreviewIsValid(lease))
        }

        @Test func onlyFolderPlacementIsIgnoredWhenComparingArchivedEntries() throws {
            let f = try Fixture()
            let store = try f.store()
            try f.delete([.tab(f.i2)], in: store)
            let previewed = try f.tab(f.i2, store)
            var moved = previewed
            moved.folderID = f.inner.id
            moved.archiveProvenance?.folderPath = nil
            var rearchived = previewed
            rearchived.archivedAt = Date(timeIntervalSince1970: 2_000_000_000)
            var regrouped = previewed
            regrouped.archiveProvenance?.groupID = UUID()
            #expect(moved.withoutFolderPlacement == previewed.withoutFolderPlacement)
            #expect(rearchived.withoutFolderPlacement != previewed.withoutFolderPlacement)
            #expect(regrouped.withoutFolderPlacement != previewed.withoutFolderPlacement)
        }

        @Test func puttingAPreviewBackLandsInTheRebuiltFolderBesideItsSibling() throws {
            let f = try Fixture()
            let store = try f.store()
            try f.delete([.tab(f.i1)], in: store)
            try f.delete([.tab(f.i2)], in: store)
            let lease = try #require(store.acquireArchivePreview(id: f.i2, profileID: f.profile.id))
            try f.delete([.folder(f.work.id)], in: store)
            try f.putBack(f.i1, in: store)
            #expect(store.restoreArchivePreview(lease, destination: .previousSpace(fallbackSpaceID: f.space.id)) == [f.i2])
            #expect(try f.tab(f.i2, store).folderID == f.inner.id)
            #expect(store.state.folders.count == 2)
        }

        @Test func deletingAParentExtendsAPreviewedTabsEarlierPathTheSameWayAndPutBackRebuildsBothLevels() throws {
            let f = try Fixture()
            let store = try f.store()
            try f.delete([.folder(f.inner.id)], in: store)
            let lease = try #require(store.acquireArchivePreview(id: f.i1, profileID: f.profile.id))
            try f.delete([.folder(f.work.id)], in: store)
            let previewed = try f.tab(f.i1, store), plain = try f.tab(f.i2, store)
            #expect(previewed.archiveProvenance?.folderPath?.folders.map(\.id) == [f.work.id, f.inner.id])
            #expect(previewed.archiveProvenance?.folderPath?.parentID == nil)
            #expect(previewed.archiveProvenance?.folderPath?.folders == plain.archiveProvenance?.folderPath?.folders)
            #expect(store.restoreArchivePreview(lease, destination: .previousSpace(fallbackSpaceID: f.space.id)) == [f.i1])
            #expect(store.state.folders.first { $0.id == f.inner.id }?.parentID == f.work.id)
            #expect(store.state.folders.first { $0.id == f.work.id }?.parentID == nil)
        }

        @Test func undoRestoresTheTreeWhileAnOlderArchiveIsPreviewedAndKeepsThePreviewValid() throws {
            let f = try Fixture()
            let store = try f.store()
            try f.delete([.tab(f.i2)], in: store)
            let olderArchive = try f.tab(f.i2, store)
            let undo = try f.delete([.folder(f.work.id)], in: store)
            let lease = try #require(store.acquireArchivePreview(id: f.i2, profileID: f.profile.id))
            #expect(try store.undoFolderDeletion(undo, shouldCommit: { true }))
            #expect(try f.tab(f.i2, store) == olderArchive)
            #expect(store.archivePreviewIsValid(lease))
            #expect(store.restoreArchivePreview(lease, destination: .previousSpace(fallbackSpaceID: f.space.id)) == [f.i2])
            #expect(try f.tab(f.i2, store).folderID == f.inner.id)
            #expect(store.state.folders.count == 2)
        }

        @Test(arguments: [true, false])
        func folderDeletionExtendsATabThatIsBeingDeletedFromArchive(completes: Bool) throws {
            let f = try Fixture()
            let store = try f.store()
            try f.delete([.tab(f.i2)], in: store)
            let pending = Retirements()
            store.requestPageRetirement = { ids, gate, done in pending.list.append((ids, gate, done)) }
            store.deleteArchivedTabs([f.i2], profileID: f.profile.id)
            #expect(pending.list.count == 1)
            #expect(pending.list[0].ids == [f.i2])
            try deleteWhileRetiring(store, f, pending: pending)
            #expect(try f.tab(f.i2, store).folderID == nil)
            #expect(try f.tab(f.i2, store).archiveProvenance?.folderPath?.folders.map(\.id) == [f.work.id, f.inner.id])
            if completes {
                #expect(pending.list[0].gate())
                pending.list[0].done(true)
                #expect(store.state.tab(f.i2) == nil)
            } else {
                pending.list[0].done(false)
                store.requestPageRetirement = nil
                try f.putBack(f.i2, in: store)
                #expect(try f.tab(f.i2, store).folderID == f.inner.id)
                #expect(store.state.folders.count == 2)
            }
        }

        @Test func folderDeletionExtendsAnArchivedAliasWhoseDocumentIsBeingDeleted() throws {
            let f = try Fixture(archivedNote: true)
            let store = try f.store()
            let pending = Retirements()
            var finished: Error?? = .none, removedDocument = false
            store.requestPageRetirement = { ids, gate, done in pending.list.append((ids, gate, done)) }
            store.deleteLocalDocument(f.notePage, profileID: f.profile.id, ownerValid: { true },
                                      deleteDocument: { removedDocument = true }, completion: { finished = .some($0) })
            #expect(pending.list.count == 1)
            #expect(pending.list[0].ids == [f.i2])
            try deleteWhileRetiring(store, f, pending: pending)
            #expect(try f.tab(f.i2, store).archiveProvenance?.folderPath?.folders.map(\.id) == [f.work.id, f.inner.id])
            #expect(pending.list[0].gate())
            pending.list[0].done(true)
            #expect(removedDocument)
            #expect(store.state.tab(f.i2) == nil)
            #expect(finished.map { $0 == nil } == true)
        }
    }
}
