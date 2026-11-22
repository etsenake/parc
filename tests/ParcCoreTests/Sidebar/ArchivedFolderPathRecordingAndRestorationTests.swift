import Foundation
import Testing
@testable import ParcCore

extension ArchivedFolderPathTestsSupport {
    @MainActor
    struct ArchivedFolderPathRecordingAndRestorationTests {
        @Test func deletingTheOuterFolderRemovesBothFolders() throws {
            let f = try Fixture()
            let store = try f.store()
            try f.delete([.folder(f.work.id)], in: store)
            #expect(store.state.folders.isEmpty)
        }

        @Test func archivedTabsNeverPointAtAMissingFolder() throws {
            let f = try Fixture()
            let store = try f.store()
            try f.delete([.folder(f.work.id)], in: store)
            #expect(try f.tab(f.w1, store).folderID == nil)
            #expect(try f.tab(f.i1, store).folderID == nil)
        }

        @Test func aDirectChildRecordsItsFolderIconAndPosition() throws {
            let f = try Fixture()
            let store = try f.store()
            try f.delete([.folder(f.work.id)], in: store)
            let workRecord = ArchivedFolder(id: f.work.id, name: "Work", isExpanded: true, customIcon: .icon(.bag),
                                            siblings: [.tab(f.p0), .folder(f.work.id), .tab(f.p1)])
            #expect(try f.tab(f.w1, store).archiveProvenance?.folderPath == ArchivedFolderPath(parentID: nil, folders: [workRecord],
                    siblings: [.tab(f.w1), .folder(f.inner.id), .tab(f.w2)]))
        }

        @Test func aNestedChildRecordsEveryAncestorOutermostFirst() throws {
            let f = try Fixture()
            let store = try f.store()
            try f.delete([.folder(f.work.id)], in: store)
            let workRecord = ArchivedFolder(id: f.work.id, name: "Work", isExpanded: true, customIcon: .icon(.bag),
                                            siblings: [.tab(f.p0), .folder(f.work.id), .tab(f.p1)])
            let innerRecord = ArchivedFolder(id: f.inner.id, name: "Inner", isExpanded: false, customIcon: nil,
                                             siblings: [.tab(f.w1), .folder(f.inner.id), .tab(f.w2)])
            #expect(try f.tab(f.i1, store).archiveProvenance?.folderPath == ArchivedFolderPath(parentID: nil, folders: [workRecord, innerRecord],
                    siblings: [.tab(f.i1), .tab(f.i2)]))
        }

        @Test func theFolderPathSurvivesSavingAndReloading() throws {
            let f = try Fixture()
            let store = try f.store()
            try f.delete([.folder(f.work.id)], in: store)
            #expect(try f.store().state.tabs == store.state.tabs)
        }

        @Test func putBackRebuildsTheOuterFolderWithItsIdentityNameAndIcon() throws {
            let f = try Fixture()
            let store = try f.store()
            try f.delete([.folder(f.work.id)], in: store)
            let reloaded = try f.store()
            try f.putBack(f.i2, in: reloaded)
            let work = reloaded.state.folders.first { $0.id == f.work.id }
            #expect(work?.name == "Work")
            #expect(work?.customIcon == .icon(.bag))
            #expect(work?.parentID == nil)
            #expect(work?.isExpanded == true)
            #expect(work?.spaceID == f.space.id)
        }

        @Test func theNestedFolderReturnsInsideItStillCollapsedAndTheTabLandsInside() throws {
            let f = try Fixture()
            let store = try f.store()
            try f.delete([.folder(f.work.id)], in: store)
            let reloaded = try f.store()
            try f.putBack(f.i2, in: reloaded)
            let inner = reloaded.state.folders.first { $0.id == f.inner.id }
            #expect(inner?.name == "Inner")
            #expect(inner?.parentID == f.work.id)
            #expect(inner?.isExpanded == false)
            #expect(try f.tab(f.i2, reloaded).folderID == f.inner.id)
            #expect(try f.tab(f.i2, reloaded).archiveProvenance == nil)
        }

        @Test func theRebuiltFolderTakesItsOriginalPlaceInPinned() throws {
            let f = try Fixture()
            let store = try f.store()
            try f.delete([.folder(f.work.id)], in: store)
            let reloaded = try f.store()
            try f.putBack(f.i2, in: reloaded)
            #expect(SidebarHierarchy.children(in: f.pinned, state: reloaded.state) == [.tab(f.p0), .folder(f.work.id), .tab(f.p1)])
        }

        @Test func siblingsReuseTheRebuiltFoldersAndReturnInOriginalOrderAndPersist() throws {
            let f = try Fixture()
            let store = try f.store()
            try f.delete([.folder(f.work.id)], in: store)
            let reloaded = try f.store()
            try f.putBack(f.i2, in: reloaded)
            try f.putBack(f.w2, in: reloaded)
            try f.putBack(f.i1, in: reloaded)
            try f.putBack(f.w1, in: reloaded)
            #expect(f.folderCount(f.work.id, reloaded) == 1)
            #expect(f.folderCount(f.inner.id, reloaded) == 1)
            #expect(reloaded.state.folders.count == 2)
            #expect(SidebarHierarchy.children(in: f.workContents, state: reloaded.state) == [.tab(f.w1), .folder(f.inner.id), .tab(f.w2)])
            #expect(SidebarHierarchy.children(in: f.innerContents, state: reloaded.state) == [.tab(f.i1), .tab(f.i2)])
            try reloaded.save()
            let again = try f.store()
            #expect(again.state.folders == reloaded.state.folders)
            #expect(again.state.tabs == reloaded.state.tabs)
        }

        @Test func aNestedDeleteRecordsItsSurvivingParentAndReturnsInsideItBetweenItsNeighbors() throws {
            let f = try Fixture()
            let store = try f.store()
            try f.delete([.folder(f.inner.id)], in: store)
            #expect(try f.tab(f.i1, store).archiveProvenance?.folderPath?.parentID == f.work.id)
            try f.putBack(f.i2, in: store)
            #expect(store.state.folders.first { $0.id == f.inner.id }?.parentID == f.work.id)
            #expect(SidebarHierarchy.children(in: f.workContents, state: store.state) == [.tab(f.w1), .folder(f.inner.id), .tab(f.w2)])
        }

        @Test func anExistingFolderWithTheOriginalIdentityIsReusedAsItIsNow() throws {
            let f = try Fixture()
            let store = try f.store()
            try f.delete([.folder(f.inner.id)], in: store)
            try f.putBack(f.i2, in: store)
            store.renameFolder(f.inner.id, name: "Renamed")
            try f.putBack(f.i1, in: store)
            #expect(store.state.folders.first { $0.id == f.inner.id }?.name == "Renamed")
            #expect(f.folderCount(f.inner.id, store) == 1)
            #expect(SidebarHierarchy.children(in: f.innerContents, state: store.state) == [.tab(f.i1), .tab(f.i2)])
        }

        @Test func aPartialRestoreRebuildsOnlyFoldersOnTheTabsOwnPath() throws {
            let f = try Fixture()
            let store = try f.store()
            try f.delete([.folder(f.work.id)], in: store)
            try f.putBack(f.w2, in: store)
            #expect(store.state.folders.map(\.id) == [f.work.id])
            try f.putBack(f.i1, in: store)
            #expect(SidebarHierarchy.children(in: f.workContents, state: store.state) == [.folder(f.inner.id), .tab(f.w2)])
        }

        @Test func aRebuiltTreeCanBeDeletedAgainAndBothDeletesShareOneRebuiltTree() throws {
            let f = try Fixture()
            let store = try f.store()
            try f.delete([.folder(f.work.id)], in: store)
            try f.putBack(f.w2, in: store)
            try f.putBack(f.i1, in: store)
            try f.delete([.folder(f.work.id)], in: store)
            #expect(store.state.folders.isEmpty)
            #expect(try f.tab(f.i2, store).archiveProvenance?.folderPath?.folders.map(\.id) == [f.work.id, f.inner.id])
            for id in [f.i2, f.w1, f.i1, f.w2] { try f.putBack(id, in: store) }
            #expect(f.folderCount(f.work.id, store) == 1)
            #expect(f.folderCount(f.inner.id, store) == 1)
            #expect(store.state.folders.count == 2)
            #expect(SidebarHierarchy.children(in: f.workContents, state: store.state) == [.tab(f.w1), .folder(f.inner.id), .tab(f.w2)])
            #expect(SidebarHierarchy.children(in: f.innerContents, state: store.state) == [.tab(f.i1), .tab(f.i2)])
        }

        @Test func archivingFromALiveFolderKeepsTheFolderLinkUntilTheFolderIsDeleted() throws {
            let f = try Fixture()
            let store = try f.store()
            try f.delete([.tab(f.i2)], in: store)
            #expect(try f.tab(f.i2, store).folderID == f.inner.id)
            #expect(try f.tab(f.i2, store).archiveProvenance?.folderPath == nil)
            try f.delete([.folder(f.inner.id)], in: store)
            #expect(try f.tab(f.i2, store).folderID == nil)
            #expect(try f.tab(f.i2, store).archiveProvenance?.folderPath?.folders.map(\.id) == [f.inner.id])
        }

        @Test func aLaterDeleteOfTheParentExtendsEarlierPathsWithItsOwnFolder() throws {
            let f = try Fixture()
            let store = try f.store()
            try f.delete([.tab(f.i2)], in: store)
            try f.delete([.folder(f.inner.id)], in: store)
            try f.delete([.folder(f.work.id)], in: store)
            for id in [f.i1, f.i2] {
                let path = try f.tab(id, store).archiveProvenance?.folderPath
                #expect(path?.parentID == nil)
                #expect(path?.folders.map(\.id) == [f.work.id, f.inner.id])
                #expect(path?.folders[0].name == "Work")
            }
        }

        @Test func putBackRebuildsBothLevelsOfATwiceDeletedTreeAndTabsFromSeparateDeletesShareIt() throws {
            let f = try Fixture()
            let store = try f.store()
            try f.delete([.tab(f.i2)], in: store)
            try f.delete([.folder(f.inner.id)], in: store)
            try f.delete([.folder(f.work.id)], in: store)
            try f.putBack(f.i2, in: store)
            #expect(store.state.folders.first { $0.id == f.inner.id }?.parentID == f.work.id)
            #expect(store.state.folders.first { $0.id == f.work.id }?.parentID == nil)
            try f.putBack(f.w1, in: store)
            try f.putBack(f.i1, in: store)
            #expect(store.state.folders.count == 2)
            #expect(SidebarHierarchy.children(in: f.workContents, state: store.state) == [.tab(f.w1), .folder(f.inner.id)])
            #expect(SidebarHierarchy.children(in: f.innerContents, state: store.state) == [.tab(f.i1), .tab(f.i2)])
        }

        @Test func puttingBackIntoAnotherSpaceRestoresAtTopLevelWithoutRebuildingFolders() throws {
            let f = try Fixture()
            let store = try f.store()
            try f.delete([.folder(f.work.id)], in: store)
            try f.putBack(f.i1, in: store, to: f.other.id)
            #expect(store.state.folders.isEmpty)
            #expect(try f.tab(f.i1, store).folderID == nil)
            #expect(try f.tab(f.i1, store).spaceID == f.other.id)
        }

        @Test func aFolderIdentityAlreadyUsedInAnotherSpaceStopsTheRebuild() throws {
            let f = try Fixture()
            let store = try f.store()
            try f.delete([.folder(f.work.id)], in: store)
            let path = try #require(try f.tab(f.i1, store).archiveProvenance?.folderPath)
            var state = store.state
            state.folders.append(BrowserFolder(id: f.inner.id, spaceID: f.other.id, name: "Elsewhere"))
            let resolved = path.rebuilding(in: &state, spaceID: f.space.id)
            #expect(resolved == f.work.id)
            #expect(state.folders.filter { $0.id == f.inner.id }.count == 1)
        }
    }
}
