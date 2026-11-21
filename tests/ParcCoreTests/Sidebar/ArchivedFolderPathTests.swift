import Foundation
import Testing
@testable import ParcCore

@MainActor
struct ArchivedFolderPathTests {
    struct Failure: Error, CustomStringConvertible { let description: String }

    @MainActor final class Fixture {
        let directory: URL
        let profile: BrowserProfile
        let space: BrowserSpace
        let other: BrowserSpace
        let work: BrowserFolder
        let inner: BrowserFolder
        let p0: UUID, p1: UUID, w1: UUID, w2: UUID, i1: UUID, i2: UUID
        let notePage: InternalPage

        var pinned: SidebarContainerLocation { .init(spaceID: space.id, folderID: nil, section: .pinned) }
        var workContents: SidebarContainerLocation { .init(spaceID: space.id, folderID: work.id, section: .pinned) }
        var innerContents: SidebarContainerLocation { .init(spaceID: space.id, folderID: inner.id, section: .pinned) }

        init(archivedNote: Bool = false) throws {
            directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("parc-archived-folder-paths-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                                                    attributes: [.posixPermissions: 0o700])
            profile = BrowserProfile(id: UUID(), name: "Original")
            space = BrowserSpace(id: UUID(), name: "Here", symbol: "circle", color: "ABCDEF", profileID: profile.id)
            other = BrowserSpace(id: UUID(), name: "There", symbol: "circle", color: "123456", profileID: profile.id)
            var work = BrowserFolder(id: UUID(), spaceID: space.id, name: "Work")
            work.customIcon = .icon(.bag)
            self.work = work
            var inner = BrowserFolder(id: UUID(), spaceID: space.id, name: "Inner", parentID: work.id)
            inner.isExpanded = false
            self.inner = inner
            let spaceID = space.id, profileID = profile.id
            func tab(_ title: String, folder: UUID?) -> BrowserTab {
                let url = "https://\(title.lowercased()).example/"
                return .init(id: UUID(), spaceID: spaceID, profileID: profileID, url: url, title: title,
                             kind: .pinned, folderID: folder, createdAt: Date(timeIntervalSince1970: 10),
                             lastAccessed: Date(timeIntervalSince1970: 10), savedURL: url, savedTitle: title)
            }
            let p0 = tab("Before", folder: nil), p1 = tab("After", folder: nil)
            let w1 = tab("WorkFirst", folder: work.id), w2 = tab("WorkLast", folder: work.id)
            let i1 = tab("InnerFirst", folder: inner.id)
            var i2 = tab("InnerLast", folder: inner.id)
            notePage = InternalPage.note(URL(fileURLWithPath: NSTemporaryDirectory() + "Parc Notes/" + UUID().uuidString + ".md"))
            if archivedNote {
                i2.url = notePage.urlString
                i2.savedURL = notePage.urlString
                i2.archivedAt = Date(timeIntervalSince1970: 1_800_000_000)
                i2.archiveProvenance = ArchiveProvenance(reason: .manual, spaceID: space.id, spaceName: space.name)
            }
            self.p0 = p0.id; self.p1 = p1.id; self.w1 = w1.id; self.w2 = w2.id; self.i1 = i1.id; self.i2 = i2.id
            var state = BrowserState(profiles: [profile], spaces: [space, other], activeSpaceID: space.id)
            state.folders = [work, inner]
            state.tabs = [p0, p1, w1, w2, i1, i2]
            state.sidebarItemOrder[pinned.key] = [.tab(p0.id), .folder(work.id), .tab(p1.id)]
            state.sidebarItemOrder[workContents.key] = [.tab(w1.id), .folder(inner.id), .tab(w2.id)]
            state.sidebarItemOrder[innerContents.key] = [.tab(i1.id), .tab(i2.id)]
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(state).write(to: directory.appendingPathComponent("session.json"))
        }

        deinit { try? FileManager.default.removeItem(at: directory) }

        func store() throws -> BrowserStore {
            try BrowserStore(directory: directory, now: { Date(timeIntervalSince1970: 1_900_000_000) })
        }

        @discardableResult
        func delete(_ items: [SidebarItemReference], in store: BrowserStore) throws -> FolderDeletionUndo {
            let target = try #require(FolderRemovalTarget(items: items, spaceID: space.id, profileID: profile.id, state: store.state))
            var record: FolderDeletionUndo?, result: Result<Bool, Error>?
            store.deleteFolder(target, shouldCommit: { true }, didCommit: { record = $0 }) { result = $0 }
            #expect(try result?.get() == true)
            return try #require(record)
        }

        func putBack(_ id: UUID, in store: BrowserStore, to space: UUID? = nil) throws {
            let destination: ArchiveRestoreDestination = space.map { .putBack(currentSpaceID: $0, requestedSpaceID: $0) }
                ?? .previousSpace(fallbackSpaceID: self.space.id)
            #expect(store.restoreArchivedTab(id, profileID: profile.id, destination: destination) == [id])
        }

        func tab(_ id: UUID, _ store: BrowserStore) throws -> BrowserTab {
            try #require(store.state.tab(id))
        }

        func folderCount(_ id: UUID, _ store: BrowserStore) -> Int { store.state.folders.filter { $0.id == id }.count }
    }

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

    @Test func malformedPathsAreRejected() throws {
        let f = try Fixture()
        let store = try f.store()
        try f.delete([.folder(f.work.id)], in: store)
        var cyclic = try #require(try f.tab(f.i1, store).archiveProvenance?.folderPath)
        cyclic.parentID = f.work.id
        #expect(!cyclic.isValid)
        #expect(!ArchivedFolderPath(parentID: nil, folders: [], siblings: []).isValid)
    }

    struct OlderProvenance: Decodable, Equatable {
        var reason: ArchiveReason
        var spaceID: UUID
        var spaceName: String
        var groupID: UUID?
        var split: BrowserSplitLayout?
    }

    @MainActor struct Saved {
        let url: URL
        let json: [String: Any]
        let tabs: [[String: Any]]

        init(_ f: Fixture) throws {
            let store = try f.store()
            try f.delete([.folder(f.work.id)], in: store)
            try store.save()
            url = f.directory.appendingPathComponent("session.json")
            json = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
            tabs = try #require(json["tabs"] as? [[String: Any]])
        }

        func rewrite(_ transform: (inout [String: Any]) -> Void) throws {
            var copy = json
            copy["tabs"] = tabs.map { record -> [String: Any] in
                guard var provenance = record["archiveProvenance"] as? [String: Any] else { return record }
                var changed = record
                transform(&provenance)
                changed["archiveProvenance"] = provenance
                return changed
            }
            try JSONSerialization.data(withJSONObject: copy).write(to: url)
        }
    }

    @Test func olderDecodingReadsANewerRecordAndIgnoresThePath() throws {
        let f = try Fixture()
        let saved = try Saved(f)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var olderReads = 0
        for record in saved.tabs {
            guard let provenance = record["archiveProvenance"] as? [String: Any], provenance["folderPath"] != nil else { continue }
            let bytes = try JSONSerialization.data(withJSONObject: provenance)
            let older = try decoder.decode(OlderProvenance.self, from: bytes)
            let current = try decoder.decode(ArchiveProvenance.self, from: bytes)
            #expect(older == OlderProvenance(reason: current.reason, spaceID: current.spaceID, spaceName: current.spaceName,
                                             groupID: current.groupID, split: current.split))
            #expect(record["folderID"] == nil)
            olderReads += 1
        }
        #expect(olderReads == 4)
    }

    @Test func savedDataWithoutPathsLoadsCleanlyAndRestoresAtTopLevel() throws {
        let f = try Fixture()
        let saved = try Saved(f)
        try saved.rewrite { _ = $0.removeValue(forKey: "folderPath") }
        let older = try f.store()
        #expect(older.state.tabs.filter { $0.archivedAt != nil }.count == 4)
        #expect(older.state.tabs.allSatisfy { $0.archiveProvenance?.folderPath == nil })
        try f.putBack(f.w1, in: older)
        #expect(older.state.folders.isEmpty)
        #expect(try f.tab(f.w1, older).folderID == nil)
    }

    @Test func anUnreadablePathIsDroppedWithoutLosingTheRecord() throws {
        let f = try Fixture()
        let saved = try Saved(f)
        try saved.rewrite { $0["folderPath"] = ["future": [1, 2, 3]] }
        let future = try f.store()
        #expect(future.state.tabs.filter { $0.archivedAt != nil }.count == 4)
        #expect(future.state.tabs.allSatisfy { $0.archiveProvenance?.folderPath == nil && ($0.archivedAt == nil || $0.archiveProvenance?.reason == .manual) })
    }

    @Test func anUnknownIconOrMissingExpansionKeepsTheRestOfThePath() throws {
        let f = try Fixture()
        let saved = try Saved(f)
        try saved.rewrite { provenance in
            guard var path = provenance["folderPath"] as? [String: Any], var folders = path["folders"] as? [[String: Any]] else { return }
            folders[0]["customIcon"] = ["icon": ["_0": "noSuchIcon"]]
            folders[0].removeValue(forKey: "isExpanded")
            path["folders"] = folders
            provenance["folderPath"] = path
        }
        let tolerant = try f.store()
        let path = try f.tab(f.w1, tolerant).archiveProvenance?.folderPath
        #expect(path?.folders.first?.customIcon == nil)
        #expect(path?.folders.first?.isExpanded == true)
        #expect(path?.folders.first?.name == "Work")
    }

    @Test func deletingAnArchivedRecordRemovesItWithItsPathAndPutBackClearsThePath() throws {
        let f = try Fixture()
        let store = try f.store()
        try f.delete([.folder(f.work.id)], in: store)
        store.deleteArchivedTabs([f.w1], profileID: f.profile.id)
        #expect(store.state.tab(f.w1) == nil)
        try f.putBack(f.w2, in: store)
        #expect(try f.tab(f.w2, store).archiveProvenance == nil)
    }

    @Test func clearArchiveLeavesNoRecordedFolderPathOrDeletedFolderNameInSavedData() throws {
        let f = try Fixture()
        let store = try f.store()
        try f.delete([.folder(f.work.id)], in: store)
        store.clearArchive(profileID: f.profile.id)
        try store.save()
        let saved = try String(contentsOf: f.directory.appendingPathComponent("session.json"), encoding: .utf8)
        #expect(store.state.tabs.allSatisfy { $0.archivedAt == nil })
        #expect(!saved.contains("folderPath"))
        #expect(!saved.contains("Inner"))
    }

    @Test func aSidebarBackupCarriesTheRecordedFolderPathAndReadsItBackIntact() throws {
        let f = try Fixture()
        var seconds: TimeInterval = 1_900_000_000
        let store = try BrowserStore(directory: f.directory, now: { seconds += 7_200; return Date(timeIntervalSince1970: seconds) },
                                     keepsBackups: true)
        try f.delete([.folder(f.work.id)], in: store)
        try store.save()
        let newest = try #require(SessionBackups.restorable(in: f.directory).first)
        let restored = try BrowserStore.savedSession(from: newest.data)
        #expect(restored.tabs.first { $0.id == f.i1 }?.archiveProvenance?.folderPath == (try f.tab(f.i1, store)).archiveProvenance?.folderPath)
    }

    @Test func clearArchiveLeavesNoSidebarBackupHoldingARecordedFolderPath() throws {
        let f = try Fixture()
        var seconds: TimeInterval = 1_900_000_000
        let store = try BrowserStore(directory: f.directory, now: { seconds += 7_200; return Date(timeIntervalSince1970: seconds) },
                                     keepsBackups: true)
        try f.delete([.folder(f.work.id)], in: store)
        try store.save()
        store.clearArchive(profileID: f.profile.id)
        try store.save()
        let remaining = try SessionBackups.list(in: f.directory).map { try String(contentsOf: $0.url, encoding: .utf8) }
        #expect(!remaining.isEmpty)
        #expect(remaining.allSatisfy { !$0.contains("folderPath") && !$0.contains("Inner") })
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
