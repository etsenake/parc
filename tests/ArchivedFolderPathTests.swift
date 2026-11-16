import Foundation

@main
@MainActor
struct ArchivedFolderPathTests {
    struct Failure: Error, CustomStringConvertible { let description: String }

    static var checks = 0

    static func check(_ condition: @autoclosure () throws -> Bool, _ message: String,
                      file: StaticString = #filePath, line: UInt = #line) throws {
        checks += 1
        if try !condition() { throw Failure(description: "\(file):\(line): \(message)") }
    }

    @MainActor struct Fixture {
        let directory: URL
        let profile: BrowserProfile
        let space: BrowserSpace
        let other: BrowserSpace
        let work: BrowserFolder
        let inner: BrowserFolder
        let p0: UUID, p1: UUID, w1: UUID, w2: UUID, i1: UUID, i2: UUID

        var pinned: SidebarContainerLocation { .init(spaceID: space.id, folderID: nil, section: .pinned) }
        var workContents: SidebarContainerLocation { .init(spaceID: space.id, folderID: work.id, section: .pinned) }
        var innerContents: SidebarContainerLocation { .init(spaceID: space.id, folderID: inner.id, section: .pinned) }

        func store() throws -> BrowserStore { try BrowserStore(directory: directory, now: { Date(timeIntervalSince1970: 1_900_000_000) }) }
    }

    static func withFixture(_ body: (Fixture) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("parc-archived-folder-paths-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        let profile = BrowserProfile(id: UUID(), name: "Original")
        let space = BrowserSpace(id: UUID(), name: "Here", symbol: "circle", color: "ABCDEF", profileID: profile.id)
        let other = BrowserSpace(id: UUID(), name: "There", symbol: "circle", color: "123456", profileID: profile.id)
        var work = BrowserFolder(id: UUID(), spaceID: space.id, name: "Work")
        work.customIcon = .icon(.bag)
        var inner = BrowserFolder(id: UUID(), spaceID: space.id, name: "Inner", parentID: work.id)
        inner.isExpanded = false
        func tab(_ title: String, folder: UUID?) -> BrowserTab {
            let url = "https://\(title.lowercased()).example/"
            return .init(id: UUID(), spaceID: space.id, profileID: profile.id, url: url, title: title,
                         kind: .pinned, folderID: folder, createdAt: Date(timeIntervalSince1970: 10),
                         lastAccessed: Date(timeIntervalSince1970: 10), savedURL: url, savedTitle: title)
        }
        let p0 = tab("Before", folder: nil), p1 = tab("After", folder: nil)
        let w1 = tab("WorkFirst", folder: work.id), w2 = tab("WorkLast", folder: work.id)
        let i1 = tab("InnerFirst", folder: inner.id), i2 = tab("InnerLast", folder: inner.id)
        var state = BrowserState(profiles: [profile], spaces: [space, other], activeSpaceID: space.id)
        state.folders = [work, inner]
        state.tabs = [p0, p1, w1, w2, i1, i2]
        let fixture = Fixture(directory: directory, profile: profile, space: space, other: other, work: work, inner: inner,
                              p0: p0.id, p1: p1.id, w1: w1.id, w2: w2.id, i1: i1.id, i2: i2.id)
        state.sidebarItemOrder[fixture.pinned.key] = [.tab(p0.id), .folder(work.id), .tab(p1.id)]
        state.sidebarItemOrder[fixture.workContents.key] = [.tab(w1.id), .folder(inner.id), .tab(w2.id)]
        state.sidebarItemOrder[fixture.innerContents.key] = [.tab(i1.id), .tab(i2.id)]
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(state).write(to: directory.appendingPathComponent("session.json"))
        try body(fixture)
    }

    @discardableResult
    static func delete(_ items: [SidebarItemReference], in store: BrowserStore, _ f: Fixture) throws -> FolderDeletionUndo {
        guard let target = FolderRemovalTarget(items: items, spaceID: f.space.id, profileID: f.profile.id, state: store.state) else {
            throw Failure(description: "Deletion target was refused")
        }
        var record: FolderDeletionUndo?, result: Result<Bool, Error>?
        store.deleteFolder(target, shouldCommit: { true }, didCommit: { record = $0 }) { result = $0 }
        guard (try result?.get()) == true, let record else { throw Failure(description: "Deletion did not commit") }
        return record
    }

    static func putBack(_ id: UUID, in store: BrowserStore, _ f: Fixture, to space: UUID? = nil) throws {
        let destination: ArchiveRestoreDestination = space.map { .putBack(currentSpaceID: $0, requestedSpaceID: $0) }
            ?? .previousSpace(fallbackSpaceID: f.space.id)
        try check(store.restoreArchivedTab(id, profileID: f.profile.id, destination: destination) == [id], "Put Back restores the archived tab")
    }

    static func tab(_ id: UUID, _ store: BrowserStore) throws -> BrowserTab {
        guard let tab = store.state.tab(id) else { throw Failure(description: "Missing tab \(id)") }
        return tab
    }

    static func folderCount(_ id: UUID, _ store: BrowserStore) -> Int { store.state.folders.filter { $0.id == id }.count }

    static func main() { exitOnFailure(runChecks) }

    static func runChecks() throws {
        try testNestedDeleteRebuildsTree()
        try testExistingAndPartialFolders()
        try testNestedDeletesAndOlderArchive()
        try testOtherDestinationsAndConflicts()
        try testSavedDataCompatibility()
        try testClearingRemovesPaths()
        try testBackupsCarryAndForgetPaths()
        try testUndoAfterPutBack()
        print("ArchivedFolderPathTests passed \(checks) checks")
    }

    static func testNestedDeleteRebuildsTree() throws {
        try withFixture { f in
            let store = try f.store()
            try delete([.folder(f.work.id)], in: store, f)
            try check(store.state.folders.isEmpty, "Deleting the outer folder removes both folders")
            let w1 = try tab(f.w1, store), i1 = try tab(f.i1, store)
            try check(w1.folderID == nil && i1.folderID == nil, "Archived tabs never point at a missing folder")
            let workRecord = ArchivedFolder(id: f.work.id, name: "Work", isExpanded: true, customIcon: .icon(.bag),
                                            siblings: [.tab(f.p0), .folder(f.work.id), .tab(f.p1)])
            let innerRecord = ArchivedFolder(id: f.inner.id, name: "Inner", isExpanded: false, customIcon: nil,
                                             siblings: [.tab(f.w1), .folder(f.inner.id), .tab(f.w2)])
            try check(w1.archiveProvenance?.folderPath == ArchivedFolderPath(parentID: nil, folders: [workRecord],
                      siblings: [.tab(f.w1), .folder(f.inner.id), .tab(f.w2)]), "A direct child records its folder, icon and position")
            try check(i1.archiveProvenance?.folderPath == ArchivedFolderPath(parentID: nil, folders: [workRecord, innerRecord],
                      siblings: [.tab(f.i1), .tab(f.i2)]), "A nested child records every ancestor, outermost first")
            let reloaded = try f.store()
            try check(reloaded.state.tabs == store.state.tabs, "The folder path survives saving and reloading")
            try putBack(f.i2, in: reloaded, f)
            let work = reloaded.state.folders.first { $0.id == f.work.id }, inner = reloaded.state.folders.first { $0.id == f.inner.id }
            try check(work?.name == "Work" && work?.customIcon == .icon(.bag) && work?.parentID == nil && work?.isExpanded == true
                      && work?.spaceID == f.space.id, "Put Back rebuilds the outer folder with its identity, name and icon")
            try check(inner?.name == "Inner" && inner?.parentID == f.work.id && inner?.isExpanded == false, "The nested folder returns inside it, still collapsed")
            try check(try tab(f.i2, reloaded).folderID == f.inner.id && tab(f.i2, reloaded).archiveProvenance == nil, "The tab lands inside the rebuilt folder")
            try check(SidebarHierarchy.children(in: f.pinned, state: reloaded.state) == [.tab(f.p0), .folder(f.work.id), .tab(f.p1)],
                      "The rebuilt folder takes its original place in Pinned")
            try putBack(f.w2, in: reloaded, f)
            try putBack(f.i1, in: reloaded, f)
            try putBack(f.w1, in: reloaded, f)
            try check(folderCount(f.work.id, reloaded) == 1 && folderCount(f.inner.id, reloaded) == 1 && reloaded.state.folders.count == 2,
                      "Siblings reuse the rebuilt folders instead of duplicating them")
            try check(SidebarHierarchy.children(in: f.workContents, state: reloaded.state) == [.tab(f.w1), .folder(f.inner.id), .tab(f.w2)],
                      "Siblings return in their original order regardless of Put Back order")
            try check(SidebarHierarchy.children(in: f.innerContents, state: reloaded.state) == [.tab(f.i1), .tab(f.i2)],
                      "Nested siblings return in their original order")
            try reloaded.save()
            let again = try f.store()
            try check(again.state.folders == reloaded.state.folders && again.state.tabs == reloaded.state.tabs, "The rebuilt tree persists")
        }
    }

    static func testExistingAndPartialFolders() throws {
        try withFixture { f in
            let store = try f.store()
            try delete([.folder(f.inner.id)], in: store, f)
            try check(try tab(f.i1, store).archiveProvenance?.folderPath?.parentID == f.work.id, "A nested delete records its surviving parent")
            try putBack(f.i2, in: store, f)
            try check(store.state.folders.first { $0.id == f.inner.id }?.parentID == f.work.id, "The deleted folder returns inside its surviving parent")
            try check(SidebarHierarchy.children(in: f.workContents, state: store.state) == [.tab(f.w1), .folder(f.inner.id), .tab(f.w2)],
                      "It returns between its original neighbors")
            store.renameFolder(f.inner.id, name: "Renamed")
            try putBack(f.i1, in: store, f)
            try check(store.state.folders.first { $0.id == f.inner.id }?.name == "Renamed" && folderCount(f.inner.id, store) == 1,
                      "An existing folder with the original identity is reused as it is now")
            try check(SidebarHierarchy.children(in: f.innerContents, state: store.state) == [.tab(f.i1), .tab(f.i2)], "Reused folder keeps original order")
        }
        try withFixture { f in
            let store = try f.store()
            try delete([.folder(f.work.id)], in: store, f)
            try putBack(f.w2, in: store, f)
            try check(store.state.folders.map(\.id) == [f.work.id], "A partial restore rebuilds only folders on the tab's own path")
            try putBack(f.i1, in: store, f)
            try check(SidebarHierarchy.children(in: f.workContents, state: store.state) == [.folder(f.inner.id), .tab(f.w2)],
                      "A later nested folder slots in before its returned sibling")
            try delete([.folder(f.work.id)], in: store, f)
            try check(store.state.folders.isEmpty, "The rebuilt tree can be deleted again")
            try check(try tab(f.i2, store).archiveProvenance?.folderPath?.folders.map(\.id) == [f.work.id, f.inner.id],
                      "A tab still archived from the first delete keeps its own path")
            for id in [f.i2, f.w1, f.i1, f.w2] { try putBack(id, in: store, f) }
            try check(folderCount(f.work.id, store) == 1 && folderCount(f.inner.id, store) == 1 && store.state.folders.count == 2,
                      "Records from both deletes share one rebuilt tree")
            try check(SidebarHierarchy.children(in: f.workContents, state: store.state) == [.tab(f.w1), .folder(f.inner.id), .tab(f.w2)]
                      && SidebarHierarchy.children(in: f.innerContents, state: store.state) == [.tab(f.i1), .tab(f.i2)],
                      "Both deletes' records land in original order")
        }
    }

    static func testNestedDeletesAndOlderArchive() throws {
        try withFixture { f in
            let store = try f.store()
            try delete([.tab(f.i2)], in: store, f)
            try check(try tab(f.i2, store).folderID == f.inner.id && tab(f.i2, store).archiveProvenance?.folderPath == nil,
                      "Archiving a tab from a live folder keeps the folder link")
            try delete([.folder(f.inner.id)], in: store, f)
            try check(try tab(f.i2, store).folderID == nil && tab(f.i2, store).archiveProvenance?.folderPath?.folders.map(\.id) == [f.inner.id],
                      "Deleting the folder turns an older archive's link into a recorded path")
            try delete([.folder(f.work.id)], in: store, f)
            for id in [f.i1, f.i2] {
                let path = try tab(id, store).archiveProvenance?.folderPath
                try check(path?.parentID == nil && path?.folders.map(\.id) == [f.work.id, f.inner.id] && path?.folders[0].name == "Work",
                          "A later delete of the parent extends earlier paths with its own folder")
            }
            try putBack(f.i2, in: store, f)
            try check(store.state.folders.first { $0.id == f.inner.id }?.parentID == f.work.id
                      && store.state.folders.first { $0.id == f.work.id }?.parentID == nil, "Put Back rebuilds both levels of a twice-deleted tree")
            try putBack(f.w1, in: store, f)
            try putBack(f.i1, in: store, f)
            try check(store.state.folders.count == 2 && SidebarHierarchy.children(in: f.workContents, state: store.state) == [.tab(f.w1), .folder(f.inner.id)],
                      "Tabs from separate deletes share the rebuilt folders")
            try check(SidebarHierarchy.children(in: f.innerContents, state: store.state) == [.tab(f.i1), .tab(f.i2)],
                      "An older archived tab comes back after the folder's recorded children")
        }
    }

    static func testOtherDestinationsAndConflicts() throws {
        try withFixture { f in
            let store = try f.store()
            try delete([.folder(f.work.id)], in: store, f)
            try putBack(f.i1, in: store, f, to: f.other.id)
            try check(store.state.folders.isEmpty && (try tab(f.i1, store)).folderID == nil && (try tab(f.i1, store)).spaceID == f.other.id,
                      "Putting back into another Space restores at top level without rebuilding folders")
        }
        try withFixture { f in
            let store = try f.store()
            try delete([.folder(f.work.id)], in: store, f)
            let path = try tab(f.i1, store).archiveProvenance!.folderPath!
            var state = store.state
            state.folders.append(BrowserFolder(id: f.inner.id, spaceID: f.other.id, name: "Elsewhere"))
            let resolved = path.rebuilding(in: &state, spaceID: f.space.id)
            try check(resolved == f.work.id && state.folders.filter { $0.id == f.inner.id }.count == 1,
                      "A folder identity already used in another Space stops the rebuild instead of duplicating it")
            var cyclic = path; cyclic.parentID = f.work.id
            try check(!cyclic.isValid && !ArchivedFolderPath(parentID: nil, folders: [], siblings: []).isValid, "Malformed paths are rejected")
        }
    }

    struct OlderProvenance: Decodable, Equatable {
        var reason: ArchiveReason
        var spaceID: UUID
        var spaceName: String
        var groupID: UUID?
        var split: BrowserSplitLayout?
    }

    static func testSavedDataCompatibility() throws {
        try withFixture { f in
            let store = try f.store()
            try delete([.folder(f.work.id)], in: store, f)
            try store.save()
            let url = f.directory.appendingPathComponent("session.json")
            let newer = try Data(contentsOf: url)
            let json = try JSONSerialization.jsonObject(with: newer) as! [String: Any]
            let tabs = json["tabs"] as! [[String: Any]]
            let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
            var olderReads = 0
            for record in tabs {
                guard let provenance = record["archiveProvenance"] as? [String: Any], provenance["folderPath"] != nil else { continue }
                let bytes = try JSONSerialization.data(withJSONObject: provenance)
                let older = try decoder.decode(OlderProvenance.self, from: bytes)
                let current = try decoder.decode(ArchiveProvenance.self, from: bytes)
                try check(older == OlderProvenance(reason: current.reason, spaceID: current.spaceID, spaceName: current.spaceName,
                                                   groupID: current.groupID, split: current.split), "Older decoding reads a newer record and ignores the path")
                try check(record["folderID"] == nil, "A newer archived record never names a deleted folder older validation would reject")
                olderReads += 1
            }
            try check(olderReads == 4, "Every archived tab in the deleted tree carries a path")
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
            try rewrite { _ = $0.removeValue(forKey: "folderPath") }
            let older = try f.store()
            try check(older.state.tabs.filter { $0.archivedAt != nil }.count == 4
                      && older.state.tabs.allSatisfy { $0.archiveProvenance?.folderPath == nil }, "Saved data without paths loads cleanly")
            try putBack(f.w1, in: older, f)
            try check(older.state.folders.isEmpty && (try tab(f.w1, older)).folderID == nil, "A record without a path restores at top level as before")
            try rewrite { $0["folderPath"] = ["future": [1, 2, 3]] }
            let future = try f.store()
            try check(future.state.tabs.filter { $0.archivedAt != nil }.count == 4
                      && future.state.tabs.allSatisfy { $0.archiveProvenance?.folderPath == nil && ($0.archivedAt == nil || $0.archiveProvenance?.reason == .manual) },
                      "An unreadable path is dropped without losing the record")
            try rewrite { provenance in
                guard var path = provenance["folderPath"] as? [String: Any], var folders = path["folders"] as? [[String: Any]] else { return }
                folders[0]["customIcon"] = ["icon": ["_0": "noSuchIcon"]]
                folders[0].removeValue(forKey: "isExpanded")
                path["folders"] = folders
                provenance["folderPath"] = path
            }
            let tolerant = try f.store()
            let path = try tab(f.w1, tolerant).archiveProvenance?.folderPath
            try check(path?.folders.first?.customIcon == nil && path?.folders.first?.isExpanded == true && path?.folders.first?.name == "Work",
                      "An unknown icon or missing expansion keeps the rest of the path")
        }
    }

    static func testClearingRemovesPaths() throws {
        try withFixture { f in
            let store = try f.store()
            try delete([.folder(f.work.id)], in: store, f)
            store.deleteArchivedTabs([f.w1], profileID: f.profile.id)
            try check(store.state.tab(f.w1) == nil, "Deleting an archived record removes it with its path")
            try putBack(f.w2, in: store, f)
            try check(try tab(f.w2, store).archiveProvenance == nil, "Put Back clears the path from the restored tab")
            store.clearArchive(profileID: f.profile.id)
            try store.save()
            let saved = try String(contentsOf: f.directory.appendingPathComponent("session.json"), encoding: .utf8)
            try check(store.state.tabs.allSatisfy { $0.archivedAt == nil } && !saved.contains("folderPath") && !saved.contains("Inner"),
                      "Clear Archive leaves no recorded folder path or deleted folder name in saved data")
        }
    }

    static func testBackupsCarryAndForgetPaths() throws {
        try withFixture { f in
            var seconds: TimeInterval = 1_900_000_000
            let store = try BrowserStore(directory: f.directory, now: { seconds += 7_200; return Date(timeIntervalSince1970: seconds) },
                                         keepsBackups: true)
            try delete([.folder(f.work.id)], in: store, f)
            try store.save()
            guard let newest = SessionBackups.restorable(in: f.directory).first else { throw Failure(description: "No sidebar backup was written") }
            let restored = try BrowserStore.savedSession(from: newest.data)
            try check(restored.tabs.first { $0.id == f.i1 }?.archiveProvenance?.folderPath == (try tab(f.i1, store)).archiveProvenance?.folderPath,
                      "A sidebar backup carries the recorded folder path and reads it back intact")
            store.clearArchive(profileID: f.profile.id)
            try store.save()
            let remaining = try SessionBackups.list(in: f.directory).map { try String(contentsOf: $0.url, encoding: .utf8) }
            try check(!remaining.isEmpty && remaining.allSatisfy { !$0.contains("folderPath") && !$0.contains("Inner") },
                      "Clear Archive leaves no sidebar backup holding a recorded folder path")
        }
    }

    static func testUndoAfterPutBack() throws {
        try withFixture { f in
            let store = try f.store()
            try delete([.tab(f.i2)], in: store, f)
            let olderArchive = try tab(f.i2, store)
            let undo = try delete([.folder(f.work.id)], in: store, f)
            try check(store.canUndoFolderDeletion(undo), "Undo is available right after deletion")
            try check(try store.undoFolderDeletion(undo, shouldCommit: { true }), "Undo restores the deleted tree")
            try check(try tab(f.i2, store) == olderArchive, "Undo returns an older archived tab to its exact earlier record")
            try check(store.state.folders.count == 2 && SidebarHierarchy.children(in: f.innerContents, state: store.state) == [.tab(f.i1)],
                      "Undo restores the original folders once")
        }
        try withFixture { f in
            let store = try f.store()
            let undo = try delete([.folder(f.work.id)], in: store, f)
            try putBack(f.i1, in: store, f)
            let rebuilt = store.state
            try check(!store.canUndoFolderDeletion(undo), "Undo refuses once Put Back has rebuilt the folder")
            try check(try !store.undoFolderDeletion(undo, shouldCommit: { true }) && store.state == rebuilt, "Refused Undo changes nothing")
            try check(folderCount(f.work.id, store) == 1 && folderCount(f.inner.id, store) == 1, "No second copy of the folder appears")
        }
        try withFixture { f in
            let store = try f.store()
            try delete([.tab(f.i2)], in: store, f)
            let undo = try delete([.folder(f.work.id)], in: store, f)
            try putBack(f.i2, in: store, f)
            try check(!store.canUndoFolderDeletion(undo) && folderCount(f.work.id, store) == 1,
                      "Putting back an older archived tab that rebuilds the folder also retires Undo")
            try check(try !store.undoFolderDeletion(undo, shouldCommit: { true }) && store.state.folders.count == 2, "Undo cannot duplicate the rebuilt tree")
        }
        try withFixture { f in
            let store = try f.store()
            try delete([.tab(f.i2)], in: store, f)
            let olderArchive = try tab(f.i2, store)
            guard let lease = store.acquireArchivePreview(id: f.i2, profileID: f.profile.id) else { throw Failure(description: "Preview lease refused") }
            try delete([.folder(f.work.id)], in: store, f)
            try check(try tab(f.i2, store).archiveProvenance == olderArchive.archiveProvenance && store.archivePreviewIsValid(lease),
                      "Deletion leaves a previewed older archive's record alone so its preview stays valid")
            store.releaseArchivePreview(lease)
        }
        try withFixture { f in
            let store = try f.store()
            try delete([.tab(f.i2)], in: store, f)
            let undo = try delete([.folder(f.work.id)], in: store, f)
            let recorded = try tab(f.i2, store)
            guard let lease = store.acquireArchivePreview(id: f.i2, profileID: f.profile.id) else { throw Failure(description: "Preview lease refused") }
            try check(try store.undoFolderDeletion(undo, shouldCommit: { true }), "Undo still restores the tree while an older archive is previewed")
            try check(try tab(f.i2, store) == recorded && store.archivePreviewIsValid(lease), "Undo leaves the previewed record and its path untouched")
            try check(store.restoreArchivePreview(lease, destination: .previousSpace(fallbackSpaceID: f.space.id)) == [f.i2]
                      && (try tab(f.i2, store)).folderID == f.inner.id && store.state.folders.count == 2,
                      "Putting the preview back reuses the restored folder")
        }
        try withFixture { f in
            let store = try f.store()
            let undo = try delete([.folder(f.work.id)], in: store, f)
            guard let lease = store.acquireArchivePreview(id: f.w1, profileID: f.profile.id) else { throw Failure(description: "Preview lease refused") }
            let archived = store.state
            try check(try !store.undoFolderDeletion(undo, shouldCommit: { true }) && store.state == archived && store.archivePreviewIsValid(lease),
                      "Undo waits while one of the deleted tabs is open in an archive preview")
            store.releaseArchivePreview(lease)
            try check(try store.undoFolderDeletion(undo, shouldCommit: { true }) && store.state.folders.count == 2, "Undo works once the preview closes")
        }
        try withFixture { f in
            let store = try f.store()
            try delete([.tab(f.i2)], in: store, f)
            var pending: [(ids: Set<UUID>, gate: () -> Bool, done: (Bool) -> Void)] = []
            store.requestPageRetirement = { ids, gate, done in pending.append((ids, gate, done)) }
            store.deleteArchivedTabs([f.i2], profileID: f.profile.id)
            try check(pending.count == 1 && pending[0].ids == [f.i2], "Archive deletion waits on retirement")
            var result: Result<Bool, Error>?
            let target = FolderRemovalTarget(items: [.folder(f.work.id)], spaceID: f.space.id, profileID: f.profile.id, state: store.state)!
            store.deleteFolder(target, shouldCommit: { true }) { result = $0 }
            try check((try result?.get()) == false && pending.count == 1 && store.state.folders.count == 2,
                      "Folder deletion refuses while an archived tab linked to it is being deleted from Archive")
            try check(pending[0].gate(), "The pending archive deletion is still current")
            pending[0].done(true)
            try check(store.state.tab(f.i2) == nil, "The pending archive deletion still completes")
        }
    }
}
