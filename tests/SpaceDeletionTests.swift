import Foundation

/// File-backed model and explicit retirement callbacks. No browser or real data.
@main @MainActor struct SpaceDeletionTests {
    static var count = 0
    static func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        count += 1
        if try !condition() { throw NSError(domain: message, code: count) }
    }
    static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-space-delete-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        var initial = BrowserState.initial()
        let source = initial.spaces[0], profile = source.profileID
        let otherProfile = BrowserProfile(id: UUID(), name: "Other")
        var other = BrowserSpace(id: UUID(), name: "Other", symbol: "circle.fill", color: "AACCEE", profileID: otherProfile.id)
        other.updateDisplayName(position: 1)
        initial.profiles.append(otherProfile); initial.spaces.append(other)
        let folder = BrowserFolder(id: UUID(), spaceID: source.id, name: "Saved")
        initial.folders.append(folder)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        func tab(_ kind: TabKind, _ folderID: UUID? = nil, _ url: String = "https://example.test") -> BrowserTab {
            BrowserTab(id: UUID(), spaceID: source.id, profileID: profile, url: url, title: url,
                kind: kind, folderID: folderID, createdAt: now, lastAccessed: now, savedURL: url, savedTitle: url)
        }
        let saved = tab(.pinned, folder.id), today = tab(.today), favorite1 = tab(.favorite), favorite2 = tab(.favorite)
        let page = InternalPage.note(UUID()), note = tab(.pinned, folder.id, page.urlString)
        initial.tabs = [saved, today, favorite1, favorite2, note]
        let favorites = BrowserSplitLayout(sidebarAnchorID: favorite1.id, spaceID: source.id,
            tabIDs: [favorite1.id, favorite2.id], widthFactors: [0.4, 0.6])
        initial.splitLayouts = [favorites]
        initial.selectedTabIDs = [today.id]; initial.selectionBySpace[source.id.uuidString] = [today.id]
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(initial).write(to: directory.appendingPathComponent("session.json"))
        let store = try BrowserStore(directory: directory)
        var documentAvailable = true
        let references = [note.id: SidebarDocumentReference(page: page, profileID: profile, validate: {
            if !documentAvailable { throw CocoaError(.fileNoSuchFile) }
        })]
        var requests: [(Set<UUID>, () -> Bool, (Bool) -> Void)] = []
        store.requestPageRetirement = { requests.append(($0, $1, $2)) }
        var record: SpaceDeletionUndo?, completed: Bool?, failure: Error?
        func remove(_ target: SpaceDeletionTarget, documents: [UUID: SidebarDocumentReference] = references) {
            completed = nil; failure = nil
            store.deleteSpace(target, documents: documents, shouldCommit: { true }, didCommit: { record = $0 }) {
                switch $0 { case .success(let value): completed = value; case .failure(let error): failure = error }
            }
        }
        let target = SpaceDeletionTarget(spaceID: source.id, state: store.state)!
        remove(target, documents: [:])
        try expect(completed == false && requests.isEmpty, "typed document capability required before close")
        remove(target)
        try expect(requests.count == 1 && requests[0].0 == [saved.id, today.id, note.id], "only original nonfavorite contents retire")
        try expect(completed == nil && store.state.spaces.count == 2, "no mutation before consent")
        requests.removeFirst().2(false)
        try expect(completed == false && store.state.spaces.count == 2, "refusal preserves whole Space")
        remove(target)
        try expect(requests[0].1(), "original retirement admitted")
        requests.removeFirst().2(true)
        try expect(completed == true && failure == nil && record != nil, "one durable deletion commits")
        let undo = record!
        try expect(store.state.spaces.map(\.id) == [other.id] && store.state.folders.isEmpty, "only original Space and folders removed")
        try expect(store.state.tabs.filter { target.tabIDs.contains($0.id) }.allSatisfy { $0.archivedAt != nil && $0.archiveProvenance?.spaceID == source.id }, "archive retains original provenance")
        try expect(store.state.tabs.filter { $0.kind == .favorite }.allSatisfy { $0.archivedAt == nil && $0.profileID == profile }, "profile Favorites are retained")
        try expect(store.state.splitLayouts.first?.id == favorites.id && store.state.splitLayouts.first?.widthFactors == [0.4, 0.6], "favorite split remains intact without an assigned Space")
        let reload = try BrowserStore(directory: directory)
        try expect(reload.state.splitLayouts.first?.id == favorites.id, "retained favorite split survives persistence and normalization")
        try expect(SpaceDeletionTarget(spaceID: other.id, state: store.state) == nil, "last Space cannot be deleted")
        var parked = store.state
        let third = BrowserSpace(id: UUID(), name: "Third", symbol: "circle", color: "AABBCC", profileID: otherProfile.id)
        parked.spaces.append(third)
        let parkedTarget = SpaceDeletionTarget(spaceID: other.id, state: parked)
        try expect(parkedTarget != nil, "foreign Profile Favorite anchor does not prevent subsequent deletion")
        let parkedDeletion = parkedTarget.flatMap { SpaceDeletionUndo.make(target: $0, state: parked, now: now, documents: [:]) }
        try expect(parkedDeletion?.1.splitLayouts.first?.spaceID == third.id, "subsequent deletion preserves parked Favorite split")
        documentAvailable = false
        try expect(try !store.undoSpaceDeletion(undo, shouldCommit: { true }), "missing document disables Undo without consuming history")
        documentAvailable = true
        store.updateTab(favorite1.id, title: "Live favorite title")
        try expect(try store.undoSpaceDeletion(undo, shouldCommit: { true }), "exact afterimages restore original Space")
        try expect(store.state.spaces.map(\.id) == [source.id, other.id] && store.state.folders == [folder], "Space position and folder restored")
        try expect(store.state.tabs.first { $0.id == favorite1.id }?.title == "Live favorite title", "Undo does not rewind live Favorites")
        try expect(store.state.tabs.first { $0.id == note.id }?.savedURL == page.urlString, "typed alias retains document identity")
        try expect(store.state.splitLayouts.first?.spaceID == source.id, "original Favorite storage anchor restored")
        try expect(undo.redoTarget(in: store.state) != nil, "Redo binds original membership")
        store.selectSpace(source.id)
        _ = store.openResolvedURL(URL(string: "https://new.test")!)
        try expect(undo.redoTarget(in: store.state) == nil, "new child invalidates destructive Redo")
        let originalOrder = store.state.spaces.map(\.id)
        try expect(try store.reorderSpace(other.id, before: source.id, expectedOrder: originalOrder), "original ordered Space move saves")
        try expect(try !store.reorderSpace(source.id, before: other.id, expectedOrder: originalOrder), "stale order refuses")
        try conversionChecks(initial: initial, directory: directory.appendingPathComponent("conversion"), references: references)
        try assignmentChecks(initial: initial, directory: directory.appendingPathComponent("assignment"))
        try renameChecks(initial: initial, directory: directory.appendingPathComponent("rename"))
        let diskTarget = SpaceDeletionTarget(spaceID: source.id, state: store.state)!
        let beforeFailure = store.state
        remove(diskTarget)
        try expect(requests[0].1(), "second original deletion admitted")
        try FileManager.default.removeItem(at: directory)
        try Data().write(to: directory)
        requests.removeFirst().2(true)
        try expect(failure != nil && store.state == beforeFailure, "disk failure publishes no partial deletion")
        do { _ = try store.createProfilePersisted(name: "Not saved"); throw NSError(domain: "creation unexpectedly saved", code: -1) }
        catch { try expect(store.state == beforeFailure, "failed Profile creation publishes no new identity") }
        print("SpaceDeletion: \(count) assertions passed")
    }
    static func renameChecks(initial: BrowserState, directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let file = directory.appendingPathComponent("session.json")
        try encoder.encode(initial).write(to: file)
        let store = try BrowserStore(directory: directory)
        let expected = initial.folders[0], profile = initial.spaces[0].profileID
        try expect(try store.renameFolder(expected, profileID: profile, name: "Renamed"), "original folder rename saves")
        try expect(try BrowserStore(directory: directory).state.folders[0].name == "Renamed", "folder rename is immediately durable")
        try expect(try !store.renameFolder(expected, profileID: profile, name: "Stale"), "concurrent rename refuses stale name")
        let current = store.state.folders[0]
        var moved = current; moved.spaceID = initial.spaces[1].id
        try expect(try !store.renameFolder(moved, profileID: initial.spaces[1].profileID, name: "Stale"), "moved folder refuses original Space")
        var reparented = current; reparented.parentID = UUID()
        try expect(try !store.renameFolder(reparented, profileID: profile, name: "Stale"), "reparented folder refuses stale placement")
        try expect(try !store.renameFolder(current, profileID: initial.profiles.last!.id, name: "Stale"), "reassigned Profile refuses original target")
        store.toggleFolder(current.id)
        try expect(try store.renameFolder(current, profileID: profile, name: "Disclosure kept"), "independent disclosure does not invalidate name")
        try expect(store.state.folders[0].isExpanded != current.isExpanded, "rename preserves independent disclosure")
        let before = store.state
        try FileManager.default.removeItem(at: directory); try Data().write(to: directory)
        var failed = false
        do { _ = try store.renameFolder(before.folders[0], profileID: profile, name: "Not saved") } catch { failed = true }
        try expect(failed && store.state == before, "folder rename write failure preserves published state")
    }
    static func conversionChecks(initial: BrowserState, directory: URL, references: [UUID: SidebarDocumentReference]) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var state = initial
        let source = state.spaces[0], destinationID = state.spaces[1].id
        state.spaces[1].profileID = source.profileID
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(state).write(to: directory.appendingPathComponent("session.json"))
        let store = try BrowserStore(directory: directory)
        let conversion = SpaceFolderConversion(source: source.id, destination: destinationID, state: store.state, documents: references)!
        let ordinary = state.tabs.filter { $0.kind != .favorite }, today = ordinary.first { $0.kind == .today }!
        var retirement = false
        store.requestPageRetirement = { _, _, _ in retirement = true }
        let undo = try store.convertSpaceToFolder(conversion)!
        try expect(!retirement, "same Profile conversion retains physical page owners")
        try expect(store.state.spaces.count == 1 && store.state.spaces[0].id == destinationID, "conversion removes only original Space")
        try expect(store.state.folders.contains { $0.id == conversion.folderID && $0.name == source.name && $0.parentID == nil }, "source title becomes root folder")
        try expect(store.state.folders.contains { $0.id == conversion.todayFolderID && $0.name == "Today" && $0.parentID == conversion.folderID }, "Today becomes a nested folder")
        try expect(store.state.tabs.filter { conversion.tabIDs.contains($0.id) }.allSatisfy { $0.spaceID == destinationID && $0.kind == .pinned && $0.archivedAt == nil }, "all original ordinary IDs remain live and pinned")
        try expect(store.state.tabs.first { $0.id == today.id }?.folderID == conversion.todayFolderID, "Today placement preserved separately")
        try expect(store.state.tabs.filter { $0.kind == .favorite }.map(\.id) == state.tabs.filter { $0.kind == .favorite }.map(\.id), "conversion leaves Profile Favorites out of folder")
        let loaded = try BrowserStore(directory: directory)
        try expect(loaded.state.folders == store.state.folders && loaded.state.tabs == store.state.tabs, "conversion survives session normalization")
        store.updateTab(today.id, title: "New live title")
        try expect(try store.undoSpaceFolderConversion(undo), "original conversion can Undo")
        try expect(store.state.folders == state.folders && store.state.spaces.map(\.id) == state.spaces.map(\.id), "Undo restores source position and tree")
        try expect(store.state.tabs.first { $0.id == today.id }?.title == "New live title" && store.state.tabs.first { $0.id == today.id }?.kind == .today, "Undo restores placement without rewinding navigation")
        let redo = undo.redo(in: store.state)!
        let redone = try store.convertSpaceToFolder(redo)!
        let root = store.state.folders.first { $0.id == conversion.folderID }!
        _ = try store.createFolder(name: "Added later", in: store.state.spaces[0], parent: root)
        try expect(redone.restoring(in: store.state) == nil, "new descendant invalidates destructive Undo")
        var stale = state; stale.spaces[1].profileID = UUID()
        try expect(conversion.applying(to: stale) == nil, "changed destination Profile refuses conversion")
        let cross = SpaceFolderConversion(source: source.id, destination: destinationID, state: initial, documents: references)!
        try expect(cross.crossesProfiles && cross.applying(to: initial)?.0.tabs.filter { cross.tabIDs.contains($0.id) }.allSatisfy { $0.profileID == initial.spaces[1].profileID } == true, "cross Profile proposal changes original records together")
        try expect(cross.applying(to: initial)?.1.restoring(in: cross.applying(to: initial)!.0) == nil, "cross Profile move cannot bypass irreversible move policy through Undo")
    }

    static func assignmentChecks(initial: BrowserState, directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(initial).write(to: directory.appendingPathComponent("session.json"))
        let store = try BrowserStore(directory: directory)
        let source = initial.spaces[0], destination = initial.spaces[1].profileID
        var requests: [(() -> Bool, (Bool) -> Void)] = [], result: Result<Bool, Error>?
        var moves = 0, rollbacks = 0, ownerValid = true
        store.requestPageRetirement = { _, valid, done in requests.append((valid, done)) }
        store.assignProfile(destination, toSpace: source.id, completion: { result = $0 })
        try expect(try result?.get() == false && requests.isEmpty, "assignment refuses typed storage without a relocation owner")
        store.relocateLocalDocuments = { ids, pages, from, to in
            moves += 1
            try expect(!ids.isEmpty && pages.count == 1 && from == source.profileID && to == destination, "assignment hands exact document and Profiles to relocation owner")
            try expect(store.state.spaces.first { $0.id == source.id }?.profileID == source.profileID, "document relocation precedes Profile publication")
            return { rollbacks += 1 }
        }
        result = nil
        store.assignProfile(destination, toSpace: source.id, shouldCommit: { ownerValid }) { result = $0 }
        try expect(result == nil && moves == 0 && requests.count == 1, "assignment waits for native retirement")
        ownerValid = false
        try expect(!requests[0].0(), "original window loss refuses assignment during retirement")
        requests.removeFirst().1(false)
        try expect(try result?.get() == false && moves == 0 && store.state == initial, "refused assignment retains all original data")
        ownerValid = true; result = nil
        store.assignProfile(destination, toSpace: source.id, shouldCommit: { ownerValid }) { result = $0 }
        try expect(requests[0].0(), "original assignment remains eligible")
        requests.removeFirst().1(true)
        try expect(try result?.get() == true && moves == 1 && rollbacks == 0, "assignment commits after actual native and document owners")
        try expect(store.state.tabs.filter { $0.kind != .favorite }.allSatisfy { $0.profileID == destination }, "ordinary aliases move to destination Profile")
        try expect(store.state.tabs.filter { $0.kind == .favorite }.allSatisfy { $0.profileID == source.profileID }, "original Profile retains Favorites")
        let reload = try BrowserStore(directory: directory)
        try expect(reload.state.splitLayouts.map(\.id) == initial.splitLayouts.map(\.id), "unused Profile Favorite split persists after assignment")
    }

}
