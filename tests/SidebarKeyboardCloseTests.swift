import AppKit

@main @MainActor
struct SidebarKeyboardCloseTests {
    static var count = 0
    static func check(_ value: @autoclosure () throws -> Bool, _ message: String) throws {
        count += 1; if try !value() { throw NSError(domain: message, code: 1) }
    }
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("parc-keyboard-close-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let profile = BrowserProfile(id: UUID(), name: "Original")
        let space = BrowserSpace(id: UUID(), name: "Here", symbol: "circle", color: "ABCDEF", profileID: profile.id)
        let folder = BrowserFolder(id: UUID(), spaceID: space.id, name: "Saved")
        let notes = try NoteStore.sharedStore(directory: root.appendingPathComponent("Notes"), diskSaveDelay: 0)
        let note = try notes.create()
        try note.updateTitle("Original", replacing: note.document.title)
        let noteFile = notes.directory.appendingPathComponent(note.document.id.uuidString.lowercased() + ".json")
        let bytes = try Data(contentsOf: noteFile)
        func tab(_ title: String, kind: TabKind, folderID: UUID? = nil, url: String = "https://original.invalid/") -> BrowserTab {
            .init(id: UUID(), spaceID: space.id, profileID: profile.id, url: url, title: title,
                kind: kind, folderID: folderID, createdAt: Date(timeIntervalSince1970: 1),
                lastAccessed: Date(timeIntervalSince1970: 2), savedURL: url, savedTitle: title)
        }
        let n = tab("Note", kind: .pinned, folderID: folder.id, url: InternalPage.note(note.document.id).urlString)
        var w = tab("Saved", kind: .pinned, folderID: folder.id)
        w.url = "https://original.invalid/away"; w.title = "Away"
        let a = tab("Today one", kind: .today), b = tab("Today two", kind: .today)
        let keep = tab("Keep", kind: .pinned)
        let alias = tab("Alias", kind: .pinned, url: n.url)
        let group = BrowserSplitLayout(sidebarAnchorID: n.id, customTitle: "Saved split", spaceID: space.id,
            tabIDs: [n.id,w.id], orientation: .vertical, widthFactors: [0.25,0.75])
        let todayGroup = BrowserSplitLayout(sidebarAnchorID: a.id, customTitle: "Today split", spaceID: space.id,
            tabIDs: [a.id,b.id], orientation: .horizontal, widthFactors: [0.6,0.4])
        var initial = BrowserState(profiles: [profile], spaces: [space], activeSpaceID: space.id)
        initial.folders = [folder]; initial.tabs = [n,w,a,b,keep,alias]
        initial.splitLayouts = [group,todayGroup]; initial.selectedTabIDs = group.tabIDs
        initial.selectionBySpace[space.id.uuidString] = group.tabIDs
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        func store(_ name: String) throws -> BrowserStore {
            let dir = root.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try encoder.encode(initial).write(to: dir.appendingPathComponent("session.json"))
            return try BrowserStore(directory: dir, now: { Date(timeIntervalSince1970: 1_900_000_000) })
        }
        initial = try store("normalized").state
        func target(_ items: [SidebarItemReference], state: BrowserState = initial) -> SidebarKeyboardCloseTarget? {
            .init(items: items, spaceID: space.id, profileID: profile.id, state: state)
        }
        let saved = target([.folder(folder.id),.split(group.id),.tab(keep.id)])!
        try check(!saved.archivesItems && !saved.requiresConfirmation, "All-saved roots use deselection, not explicit archive")
        try check(saved.items.roots == [.folder(folder.id),.tab(keep.id)], "Nested selected split is owned once by original ancestor")
        try check(saved.items.tabs.map(\.id) == [n.id,w.id,keep.id], "Saved operation binds original descendant identities")
        let mixed = target([.folder(folder.id),.split(todayGroup.id)])!
        try check(mixed.archivesItems && mixed.requiresConfirmation, "Any original Today root selects whole-collection close with folder confirmation")
        let tabOnly = target([.tab(keep.id),.split(todayGroup.id)])!
        try check(tabOnly.archivesItems && !tabOnly.requiresConfirmation, "Mixed saved/Today tabs have no extra folder warning")
        try check(target([.split(todayGroup.id)])?.archivesItems == true, "Today split uses its original sidebar container")
        try check(target([.split(group.id)])?.archivesItems == false, "Pinned split remains saved despite live navigation away")
        try check(target([.tab(n.id)]) == nil, "A hidden split child cannot be independently retired")
        try check(target([.folder(UUID()),.split(todayGroup.id)]) == nil, "Missing selected root cannot partially archive another root")
        try check(target([.tab(keep.id),.tab(keep.id)]) == nil, "Duplicate input refused")
        var changed = initial; changed.tabs[0].profileID = UUID()
        try check(target([.folder(folder.id),.split(todayGroup.id)], state: changed) == nil, "Foreign child refuses the entire original collection")
        let savedStore = try store("saved")
        var authorize: (() -> Bool)?, finish: ((Bool) -> Void)?, requested = Set<UUID>(), allowed: Bool?, current = true
        savedStore.requestPageRetirement = { ids, validate, done in requested = ids; authorize = validate; finish = done }
        let ids = Set(saved.items.tabs.map(\.id))
        savedStore.closeTabs(ids, shouldCommit: { current }) { allowed = $0 }
        try check(requested == ids && allowed == nil, "Saved close enters one actual original-page consent boundary")
        current = false
        try check(authorize?() == false, "Changed originating selection refuses saved commit")
        finish?(true)
        try check(allowed == false && savedStore.state == initial, "Late refusal preserves all saved references and live metadata")
        current = true
        savedStore.closeTabs(ids, shouldCommit: { current }) { allowed = $0 }
        try check(authorize?() == true, "Original saved owner can retry")
        finish?(true)
        try check(allowed == true && savedStore.state.tabs.allSatisfy { $0.archivedAt == nil }, "Saved close archives no tab")
        try check(savedStore.state.folders == initial.folders, "Saved close never removes folder records")
        try check(savedStore.state.splitLayouts.contains(group), "Whole saved split keeps original ID, title, ratio and order after unload")
        try check(savedStore.state.splitLayouts.contains(todayGroup), "Unselected Today split stays intact")
        try check(savedStore.state.tabs.first { $0.id == w.id }?.url == w.savedURL, "Saved content resets its current URL to the original saved destination")
        try check(savedStore.state.tabs.first { $0.id == w.id }?.title == w.savedTitle, "Saved title restores without changing saved identity")
        try savedStore.save()
        let savedDisk = try BrowserStore(directory: savedStore.directory)
        try check(savedDisk.state.splitLayouts.contains(group), "Saved split retention survives actual persistence")
        try check(savedDisk.state.tabs.first { $0.id == w.id }?.url == w.savedURL, "Persisted close result contains the real saved destination reset")
        let mixedStore = try store("mixed")
        let docs = [n.id: SidebarDocumentReference(page: .note(note.document.id), profileID: profile.id) { try notes.validateReference(note.document.id) }]
        var result: Result<Bool,Error>?, undo: FolderDeletionUndo?, admissions = 0
        mixedStore.requestPageRetirement = { ids, validate, done in requested = ids; authorize = validate; finish = done; admissions += 1 }
        mixedStore.deleteFolder(mixed.items, documents: docs, shouldCommit: { current }, didCommit: { undo = $0 }) { result = $0 }
        try check(admissions == 1 && requested == Set([n.id,w.id,a.id,b.id]) && result == nil, "Mixed keyboard path closes one whole collection, not separate saved/Today batches")
        finish?(false)
        try check((try result?.get()) == false && mixedStore.state == initial && undo == nil, "One native refusal preserves every mixed root")
        mixedStore.deleteFolder(mixed.items, documents: docs, shouldCommit: { current }, didCommit: { undo = $0 }) { result = $0 }
        try check(authorize?() == true, "Original typed references are valid at actual consent")
        finish?(true)
        try check((try result?.get()) == true && mixedStore.state.folders.isEmpty, "Mixed branch removes original ordinary folders after consent")
        try check(mixedStore.state.tabs.filter { requested.contains($0.id) }.allSatisfy { $0.archivedAt != nil }, "Mixed command archives saved, Today and typed references together")
        try check(mixedStore.state.tabs.first { $0.id == alias.id } == alias, "Unselected shared-document alias is untouched")
        try check(try Data(contentsOf: noteFile) == bytes && notes.load(note.document.id) === note, "Original Note bytes and shared session never change")
        try check(mixedStore.state.splitLayouts.isEmpty, "Archived complete groups leave no dangling live sidebar split")
        let todayIntent = ClosedItemIntent(ids: Set([a.id,b.id]), state: initial,
            spaceID: space.id, profileID: profile.id, focusedTabID: b.id)!
        var reopen = WindowClosedItems()
        reopen.record(todayIntent, in: mixedStore.state)
        let step = reopen.next(in: mixedStore.state)
        try check(step?.tabIDs == [a.id,b.id] && step?.split == todayGroup, "Keyboard archive preserves actual Today whole-split Reopen steps")
        try check(step?.focusedTabID == b.id && step?.profileID == profile.id, "Reopen keeps the originating focused pane and exact profile")
        let record = undo!
        try check(record.groups == initial.splitLayouts && record.roots == mixed.items.roots, "Undo captures complete original groups/root identities")
        try check(try mixedStore.undoFolderDeletion(record, shouldCommit: { true }), "Mixed keyboard archive restores through actual window Undo transaction")
        try check(mixedStore.state.tabs == initial.tabs && mixedStore.state.folders == initial.folders && mixedStore.state.splitLayouts == initial.splitLayouts, "Undo restores exact mixed original records and geometry")
        print("\(count) keyboard close assertions passed")
    }
}
