import Foundation

@main @MainActor
struct SidebarWindowMoveTests {
    static var count = 0
    static func check(_ value: @autoclosure () throws -> Bool, _ message: String) throws {
        count += 1; if try !value() { throw NSError(domain: message, code: 1) }
    }
    static func main() { exitOnFailure(runChecks) }
    static func runChecks() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-window-move-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let profile = BrowserProfile(id: UUID(), name: "Original")
        let otherProfile = BrowserProfile(id: UUID(), name: "Other")
        let source = BrowserSpace(id: UUID(), name: "Source", symbol: "circle", color: "AABBCC", profileID: profile.id)
        let target = BrowserSpace(id: UUID(), name: "Target", symbol: "circle", color: "AABBCC", profileID: profile.id)
        let foreign = BrowserSpace(id: UUID(), name: "Foreign", symbol: "circle", color: "AABBCC", profileID: otherProfile.id)
        let folder = BrowserFolder(id: UUID(), spaceID: source.id, name: "Folder", isExpanded: false)
        let child = BrowserFolder(id: UUID(), spaceID: source.id, name: "Child", parentID: folder.id, isExpanded: true)
        let empty = BrowserFolder(id: UUID(), spaceID: source.id, name: "Empty")
        let destinationFolder = BrowserFolder(id: UUID(), spaceID: target.id, name: "Destination")
        func tab(_ title: String, parent: UUID? = nil, url: String? = nil) -> BrowserTab {
            let url = url ?? "https://original.invalid/" + title
            return BrowserTab(id: UUID(), spaceID: source.id, profileID: profile.id, url: url, title: title,
                kind: .pinned, folderID: parent, createdAt: Date(timeIntervalSince1970: 1), lastAccessed: Date(timeIntervalSince1970: 1), savedURL: url, savedTitle: title)
        }
        let notes = try NoteStore.sharedStore(directory: directory.appendingPathComponent("Notes"), diskSaveDelay: 0)
        let easels = try EaselStore(directory: directory.appendingPathComponent("Easels"))
        let note = try notes.create(), easel = try easels.create(title: "Original")
        let n = tab("Note", parent: child.id, url: InternalPage.note(note.document.id).urlString)
        var e = tab("Easel", url: InternalPage.easel(easel.document.id).urlString)
        e.kind = .today
        let web = tab("Web", parent: folder.id), keep = tab("Keep")
        let split = BrowserSplitLayout(sidebarAnchorID: n.id, customTitle: "Original split", spaceID: source.id,
            tabIDs: [n.id,e.id], orientation: .vertical, widthFactors: [0.3,0.7])
        var state = BrowserState(profiles: [profile,otherProfile], spaces: [source,target,foreign], activeSpaceID: source.id)
        state.tabs = [n,e,web,keep]; state.folders = [folder,child,empty,destinationFolder]; state.splitLayouts = [split]
        state.selectedTabIDs = split.tabIDs; state.selectionBySpace[source.id.uuidString] = split.tabIDs
        let top = SidebarContainerLocation(spaceID: source.id, folderID: nil, section: .pinned)
        state.sidebarItemOrder[top.key] = [.folder(folder.id),.tab(keep.id),.folder(empty.id)]
        let nested = SidebarContainerLocation(spaceID: source.id, folderID: folder.id, section: .pinned)
        state.sidebarItemOrder[nested.key] = [.tab(web.id),.folder(child.id)]
        let location = SidebarContainerLocation(spaceID: target.id, folderID: destinationFolder.id, section: .pinned)
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let file = directory.appendingPathComponent("session.json"); try encoder.encode(state).write(to: file)
        let store = try BrowserStore(directory: directory)
        let initial = store.state
        let proposal = SidebarWindowMove(items: [.folder(folder.id),.folder(child.id),.split(split.id),.folder(empty.id)],
            sourceSpaceID: source.id, profileID: profile.id, to: location, before: nil, state: initial)
        try check(proposal != nil, "A whole ordinary mixed-placement split is admitted through its original folder")
        let move = proposal!
        try check(move.roots == [.folder(folder.id),.folder(empty.id)], "Ancestor de-dup preserves ordered roots")
        try check(move.tabIDs == [web.id,n.id,e.id], "Original hierarchical order includes complete split once")
        try check(SidebarWindowMove(items: [.tab(n.id)], sourceSpaceID: source.id, profileID: profile.id, to: location, before: nil, state: initial) == nil, "Partial split refuses")
        let wrong = SidebarContainerLocation(spaceID: foreign.id, folderID: nil, section: .pinned)
        try check(SidebarWindowMove(items: [.folder(folder.id)], sourceSpaceID: source.id, profileID: profile.id, to: wrong, before: nil, state: initial) == nil, "Cross-profile refuses")
        let cycle = SidebarContainerLocation(spaceID: source.id, folderID: child.id, section: .pinned)
        try check(SidebarWindowMove(items: [.folder(folder.id)], sourceSpaceID: source.id, profileID: profile.id, to: cycle, before: nil, state: initial) == nil, "No descendant cycle")
        let rootMove = SidebarWindowMove(items: [.split(split.id)], sourceSpaceID: source.id, profileID: profile.id,
            to: location, before: nil, state: initial)!
        let migrated = initial.tabs.first { $0.id == e.id }!
        try check(migrated.kind == .pinned && migrated.folderID == child.id && migrated.url == e.url,
                  "Restored mixed child enters its split anchor's folder")
        try check(rootMove.tabIDs == split.tabIDs && rootMove.collection.tabs == [n,migrated], "Root receipt retains every original child in pane order")
        let rootAfter = rootMove.applying(to: initial)!
        try check(split.tabIDs.allSatisfy { id in rootAfter.tabs.contains { $0.id == id && $0.spaceID == target.id && $0.kind == .pinned && $0.folderID == destinationFolder.id } }, "Explicit destination normalizes every root child without foreign folder references")
        try check(rootAfter.folders == initial.folders, "Unselected original folders are not relocated")
        let sameSpace = SidebarWindowMove(items: [.split(split.id)], sourceSpaceID: source.id, profileID: profile.id,
            to: top, before: .folder(folder.id), state: initial)!
        let sameAfter = sameSpace.applying(to: initial)!
        try check(split.tabIDs.allSatisfy { id in sameAfter.tabs.contains { $0.id == id && $0.spaceID == source.id && $0.kind == .pinned && $0.folderID == nil } }, "A second physical window in the same Space uses the actual explicit container")
        try check(sameAfter.splitLayouts == initial.splitLayouts, "Same-Space physical move preserves the whole original split record")
        var invalid = initial
        invalid.tabs[1].kind = .favorite
        try check(SidebarMoveCollection(items: [.split(split.id)], spaceID: source.id, profileID: profile.id, state: invalid) == nil, "Ordinary and Favorite mixed group remains excluded")
        invalid = initial; invalid.tabs[1].profileID = otherProfile.id
        try check(SidebarMoveCollection(items: [.split(split.id)], spaceID: source.id, profileID: profile.id, state: invalid) == nil, "A foreign-profile child cannot enter the collection")
        invalid = initial; invalid.tabs[1].spaceID = target.id
        try check(SidebarMoveCollection(items: [.split(split.id)], spaceID: source.id, profileID: profile.id, state: invalid) == nil, "An already-relocated child invalidates whole-group admission")
        invalid = initial; invalid.tabs[1].archivedAt = Date()
        try check(SidebarMoveCollection(items: [.split(split.id)], spaceID: source.id, profileID: profile.id, state: invalid) == nil, "An archived child cannot be omitted from a purported whole-group transfer")
        invalid = initial; invalid.splitLayouts[0].tabIDs.reverse()
        try check(rootMove.applying(to: invalid) == nil, "Original pane order is part of the immutable receipt")
        invalid = initial; invalid.tabs[1].folderID = folder.id
        try check(rootMove.applying(to: invalid) == nil, "Changing a non-anchor original placement expires the receipt")
        invalid = initial; invalid.splitLayouts[0].widthFactors = [0.5,0.5]
        try check(rootMove.applying(to: invalid) == nil, "Original divider geometry is bound by the collection receipt")
        invalid = initial; invalid.splitLayouts[0].tabIDs = [n.id,n.id]
        try check(SidebarMoveCollection(items: [.split(split.id)], spaceID: source.id, profileID: profile.id, state: invalid) == nil, "Duplicate child identities remain invalid")
        var changed = initial; changed.folders[3].name = "Changed"
        try check(move.applying(to: changed) == nil, "Destination snapshot expires")
        changed = initial; changed.tabs[0].url = "https://changed.invalid"
        try check(move.applying(to: changed) == nil, "Exact original records captured")
        let priorBytes = try Data(contentsOf: file)
        try FileManager.default.removeItem(at: file); try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
        do { _ = try store.commitSidebarWindowMove(move); preconditionFailure("Expected save failure") } catch {}
        try check(store.state == initial, "Failed real save publishes nothing")
        try FileManager.default.removeItem(at: file); try priorBytes.write(to: file)
        try check(try store.commitSidebarWindowMove(move), "Complete durable move")
        let after = store.state
        try check(Set(after.tabs.map(\.id)) == Set(initial.tabs.map(\.id)) && after.tabs.count == initial.tabs.count, "No tab clone or URL replay")
        try check(after.tabs.first { $0.id == n.id }?.url == n.url && after.tabs.first { $0.id == e.id }?.url == e.url, "Typed document identity unchanged")
        try check(try notes.load(note.document.id) === note && easels.load(easel.document.id) === easel, "Original local shared sessions survive")
        try check(after.tabs.filter { split.tabIDs.contains($0.id) }.allSatisfy { $0.folderID == child.id && $0.kind == .pinned && $0.spaceID == target.id }, "Nested split descendants adopt the moved original anchor container")
        try check(after.folders.first { $0.id == folder.id }?.parentID == destinationFolder.id, "Original folder adopts exact parent")
        try check(after.folders.first { $0.id == child.id }?.parentID == folder.id, "Nested parent identity preserved")
        try check(after.folders.first { $0.id == empty.id }?.spaceID == target.id, "Empty original folder participates")
        var expectedSplit = split; expectedSplit.spaceID = target.id
        try check(after.splitLayouts == [expectedSplit], "Whole split identity, order and geometry preserved")
        try check(SidebarHierarchy.children(in: location, state: after) == [.folder(folder.id),.folder(empty.id)], "Original root order at target")
        try check(after.tabs.first { $0.id == keep.id } == keep, "Unrelated tab unchanged")
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        try check(try decoder.decode(BrowserState.self, from: Data(contentsOf: file)) == after, "One coherent durable snapshot stored")
        let reloaded = try BrowserStore(directory: directory).state
        try check(reloaded.folders == after.folders && reloaded.splitLayouts == after.splitLayouts && reloaded.tabs == after.tabs, "All original identities durably reload")
        try check(try !store.commitSidebarWindowMove(move), "Stale move cannot replay")
        let same = SidebarWindowMove(items: [.tab(keep.id)], sourceSpaceID: source.id, profileID: profile.id,
            to: top, before: nil, state: after)!
        try check(same.applying(to: after) != nil, "Same-Space physical transfer has valid model proposal")

        let ownership = NativePageOwnership(), a = UUID(), b = UUID(), c = UUID()
        try check(ownership.claim(n.id, owner: a, page: "n"), "Original live claim")
        try check(ownership.claim(e.id, owner: a), "Original local claim")
        try check(ownership.reserveCollection([n.id,n.id], from: a, to: b) == nil, "Duplicate reservation IDs refuse")
        try check(ownership.reserveCollection([n.id], from: c, to: b) == nil, "Foreign original owner refuses")
        let reservation = ownership.reserveCollection([n.id,e.id,web.id], from: a, to: b)!
        try check(ownership.isCurrent(reservation), "All original claims captured")
        try check(!ownership.claim(web.id, owner: c), "No third-window materialization during transfer")
        try check(ownership.reserveTransfer(n.id, page: "n", from: a, to: c) == nil, "Single transfer cannot interleave")
        try check(ownership.reserveCollection([web.id], from: a, to: c) == nil, "Collections cannot overlap")
        try check(ownership.finishCollection(reservation, moved: false), "Rollback releases all reservations")
        try check(ownership.claimSnapshot(n.id).owner == a && ownership.claimSnapshot(web.id).owner == nil, "Rollback retains original claims")
        let moved = ownership.reserveCollection([n.id,e.id,web.id], from: a, to: b)!
        try check(ownership.finishCollection(moved, moved: true), "Collection publishes atomically")
        try check([n.id,e.id,web.id].allSatisfy { ownership.claimSnapshot($0).owner == b }, "All model IDs follow destination")
        try check(ownership.claimSnapshot(n.id).pages == ["n"], "Actual native page identity retained")
        try check(!ownership.finishCollection(moved, moved: true), "One-shot completion")
        let closing = ownership.reserveCollection([n.id,e.id], from: b, to: a)!
        ownership.release(n.id, owner: b)
        try check(!ownership.isCurrent(closing) && ownership.isCurrent(closing, closed: [n.id]), "Real close needs explicit accounting")
        try check(ownership.finishCollection(closing, moved: true, closed: [n.id]), "Confirmed closed original does not strand other originals")
        try check(ownership.claimSnapshot(n.id).owner == nil && ownership.claimSnapshot(e.id).owner == a, "No closed-page ownership fabricated")
        let emptyTransfer = ownership.reserveCollection([], from: a, to: b)!
        try check(ownership.isCurrent(emptyTransfer) && ownership.finishCollection(emptyTransfer, moved: true), "Empty folder owns real one-shot window transaction")
        try check(!ownership.finishCollection(emptyTransfer, moved: true), "Empty folder completion cannot replay")
        print("\(count) original collection move assertions passed")
    }
}
