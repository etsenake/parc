import AppKit

@main @MainActor
struct SidebarPluralRemovalTests {
    static var count = 0
    static func check(_ value: @autoclosure () throws -> Bool, _ message: String) throws {
        count += 1; if try !value() { throw NSError(domain: message, code: 1) }
    }
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("parc-plural-removal-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let profile = BrowserProfile(id: UUID(), name: "Original")
        let space = BrowserSpace(id: UUID(), name: "Here", symbol: "circle", color: "ABCDEF", profileID: profile.id)
        let folder = BrowserFolder(id: UUID(), spaceID: space.id, name: "First")
        let nested = BrowserFolder(id: UUID(), spaceID: space.id, name: "Nested", parentID: folder.id)
        let second = BrowserFolder(id: UUID(), spaceID: space.id, name: "Second")
        let empty = BrowserFolder(id: UUID(), spaceID: space.id, name: "Empty")
        let remaining = BrowserFolder(id: UUID(), spaceID: space.id, name: "Keep")
        let notes = try NoteStore.sharedStore(directory: root.appendingPathComponent("Notes"), diskSaveDelay: 0)
        let note = try notes.create()
        try note.updateTitle("Shared", replacing: note.document.title)
        let noteFile = notes.directory.appendingPathComponent(note.document.id.uuidString.lowercased() + ".json")
        let noteBytes = try Data(contentsOf: noteFile)
        func tab(_ title: String, folder: UUID?, kind: TabKind = .pinned, url: String = "https://original.invalid/") -> BrowserTab {
            .init(id: UUID(), spaceID: space.id, profileID: profile.id, url: url, title: title,
                kind: kind, folderID: folder, createdAt: Date(timeIntervalSince1970: 10),
                lastAccessed: Date(timeIntervalSince1970: 10), savedURL: url, savedTitle: title)
        }
        let n = tab("Note", folder: nested.id, url: InternalPage.note(note.document.id).urlString)
        let w = tab("Web", folder: nested.id)
        let b = tab("Second child", folder: second.id)
        let loose = tab("Loose pinned", folder: remaining.id)
        let today = tab("Today", folder: nil, kind: .today)
        let keep = tab("Survivor", folder: nil)
        let alias = tab("Surviving alias", folder: nil, url: InternalPage.note(note.document.id).urlString)
        let split = BrowserSplitLayout(sidebarAnchorID: n.id, customTitle: "Mixed", spaceID: space.id,
            tabIDs: [n.id,w.id], orientation: .vertical, widthFactors: [0.3,0.7])
        var oldArchived = tab("Earlier archive", folder: nested.id); oldArchived.archivedAt = Date(timeIntervalSince1970: 20)
        var state = BrowserState(profiles: [profile], spaces: [space], activeSpaceID: space.id)
        state.folders = [folder,nested,second,empty,remaining]
        state.tabs = [n,w,b,loose,today,keep,alias,oldArchived]; state.splitLayouts = [split]
        let pinned = SidebarContainerLocation(spaceID: space.id, folderID: nil, section: .pinned)
        state.sidebarItemOrder[pinned.key] = [.tab(keep.id),.folder(folder.id),.folder(second.id),.folder(empty.id),.folder(remaining.id),.tab(alias.id)]
        state.selectedTabIDs = split.tabIDs; state.selectionBySpace[space.id.uuidString] = split.tabIDs
        let sessionURL = root.appendingPathComponent("session.json")
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(state).write(to: sessionURL)
        let store = try BrowserStore(directory: root, now: { Date(timeIntervalSince1970: 1_900_000_000) })
        let initial = store.state
        let proposed: [SidebarItemReference] = [.folder(folder.id),.folder(nested.id),.split(split.id),.folder(second.id),.folder(empty.id),.tab(loose.id),.tab(today.id)]
        let target = FolderRemovalTarget(items: proposed, spaceID: space.id, profileID: profile.id, state: initial)!
        try check(target.roots == [.folder(folder.id),.folder(second.id),.folder(empty.id),.tab(loose.id),.tab(today.id)], "Ancestor roots suppress selected nested folder and split exactly once")
        try check(Set(target.tabs.map(\.id)) == Set([n.id,w.id,b.id,loose.id,today.id]) && target.tabs.count == 5, "Captured original pages are unique across mixed roots")
        try check(target.groups == [split] && target.folderIDs.count == 4, "Whole split geometry and empty descendants are retained")
        try check(FolderRemovalTarget(items: [.tab(n.id)], spaceID: space.id, profileID: profile.id, state: initial) == nil, "Cannot target a hidden pane separately from its whole split")
        try check(FolderRemovalTarget(items: [.folder(folder.id),.folder(folder.id)], spaceID: space.id, profileID: profile.id, state: initial) == nil, "Duplicate root input is refused")
        try check(FolderRemovalTarget(items: proposed, spaceID: space.id, profileID: UUID(), state: initial) == nil, "Wrong original profile refused")
        var foreign = initial; foreign.tabs[0].profileID = UUID()
        try check(FolderRemovalTarget(items: proposed, spaceID: space.id, profileID: profile.id, state: foreign) == nil, "Foreign descendant cannot partially participate")
        var malformed = initial; malformed.tabs[0].kind = .today
        try check(FolderRemovalTarget(items: proposed, spaceID: space.id, profileID: profile.id, state: malformed) == nil, "Folder descendants retain the saved-kind invariant")
        let docs = [n.id: SidebarDocumentReference(page: .note(note.document.id), profileID: profile.id) { try notes.validateReference(note.document.id) }]
        let selection = FolderRemovalSelection.resolve(target: target, state: initial, selected: split.tabIDs, focused: w.id, available: { _ in true })!
        try check(!selection.tabIDs.isEmpty && Set(selection.tabIDs).isDisjoint(with: target.tabs.map(\.id)), "Next focus excludes every removed root")
        var authorize: (() -> Bool)?, finish: ((Bool) -> Void)?, requested = Set<UUID>(), admissions = 0
        store.requestPageRetirement = { ids, canCommit, done in requested = ids; authorize = canCommit; finish = done; admissions += 1 }
        var result: Result<Bool,Error>?, undo: FolderDeletionUndo?, originalSelection = true
        func remove(_ t: FolderRemovalTarget) {
            result = nil
            store.deleteFolder(t, documents: docs, shouldCommit: { originalSelection }, didCommit: { undo = $0 }) { result = $0 }
        }
        remove(target)
        try check(requested == Set(target.tabs.map(\.id)) && admissions == 1 && result == nil && store.state == initial, "One complete set reaches the consent boundary without model mutation")
        originalSelection = false
        try check(authorize?() == false, "Original selection changed while awaiting consent")
        finish?(false); originalSelection = true
        try check((try result?.get()) == false && undo == nil && store.state == initial, "Refusal leaves every root unchanged and creates no Undo")
        remove(target); finish?(false)
        try check(store.state == initial && undo == nil, "Any native beforeunload refusal cancels the whole collection")
        remove(target)
        try Data("invalid".utf8).write(to: noteFile)
        try check(authorize?() == false, "Typed reference loss invalidates all roots during native consent")
        finish?(false); try noteBytes.write(to: noteFile)
        try check(store.state == initial, "Typed refusal archives no unrelated web root")
        remove(target)
        try check(authorize?() == true, "Original owners remain eligible")
        let bytes = try Data(contentsOf: sessionURL)
        try FileManager.default.removeItem(at: sessionURL); try FileManager.default.createDirectory(at: sessionURL, withIntermediateDirectories: false)
        finish?(true)
        if case .failure? = result {} else { throw NSError(domain: "Expected atomic save failure", code: 1) }
        try check(store.state == initial && undo == nil, "Failed disk commit leaves all original roots and no Undo entry")
        try FileManager.default.removeItem(at: sessionURL); try bytes.write(to: sessionURL)
        remove(target); try check(authorize?() == true, "Retry admits exact original snapshot"); finish?(true)
        let record = undo!, archived = store.state
        try check((try result?.get()) == true && archived.folders == [remaining], "One successful transaction removes only captured folder records")
        try check(archived.tabs.filter { target.tabs.map(\.id).contains($0.id) }.allSatisfy { $0.archivedAt != nil }, "Original Today, pinned, typed and split records all archived")
        try check(archived.tabs.first { $0.id == keep.id } == keep && archived.tabs.first { $0.id == alias.id } == alias, "Unselected page and document alias untouched")
        try check(archived.tabs.first { $0.id == oldArchived.id }?.folderID == nil, "Earlier archive safely detached from deleted folder")
        try check(try Data(contentsOf: noteFile) == noteBytes && notes.load(note.document.id) === note, "No document write or session clone")
        try check(record.roots == target.roots && record.locations.count == 3 && record.groups == [split], "Undo retains roots across three original containers")
        var independent = archived
        let inserted = tab("Inserted later", folder: nil)
        independent.tabs.append(inserted)
        independent.sidebarItemOrder[pinned.key, default: []].insert(.tab(inserted.id), at: 0)
        let independentURL = root.appendingPathComponent("independent")
        try FileManager.default.createDirectory(at: independentURL, withIntermediateDirectories: true)
        try encoder.encode(independent).write(to: independentURL.appendingPathComponent("session.json"))
        let concurrentStore = try BrowserStore(directory: independentURL)
        try check(try concurrentStore.undoFolderDeletion(record, shouldCommit: { true }), "Undo tolerates an unrelated surviving sibling insertion")
        try check(concurrentStore.state.tabs.contains(inserted), "Undo never rolls back unrelated records")
        let concurrentOrder = SidebarHierarchy.children(in: pinned, state: concurrentStore.state)
        try check(concurrentOrder.first == .tab(inserted.id) && concurrentOrder.filter { $0 != .tab(inserted.id) } == SidebarHierarchy.children(in: pinned, state: initial), "Each original root uses surviving local anchors")
        let manager = FolderUndoManager(), operation = FolderUndoOperation(record)
        _ = manager.append(.init(name: record.actionName,
            isValid: { $0 == .undo ? store.canUndoFolderDeletion(operation.record) : operation.record.redoTarget(in: store.state) != nil },
            isAvailable: { _ in operation.record.documentsAreAvailable },
            perform: { direction, done in
                if direction == .undo { done((try? store.undoFolderDeletion(operation.record, shouldCommit: { true })) == true) }
                else if let redo = operation.record.redoTarget(in: store.state) {
                    store.deleteFolder(redo, documents: operation.record.documentReferences, shouldCommit: { true }, didCommit: { operation.record = $0 }) { done((try? $0.get()) == true) }
                } else { done(false) }
            }))
        try check(manager.canUndo && manager.undoActionName == "Archive Tabs", "One actual Undo group names the whole collection")
        manager.undo()
        try check(store.state.folders.sorted { $0.id.uuidString < $1.id.uuidString } == initial.folders.sorted { $0.id.uuidString < $1.id.uuidString }, "Undo restores exact original folder IDs")
        try check(store.state.tabs == initial.tabs && store.state.splitLayouts == initial.splitLayouts, "Undo restores original records and split shape")
        try check(SidebarHierarchy.children(in: pinned, state: store.state) == SidebarHierarchy.children(in: pinned, state: initial), "Undo restores original mixed sibling order")
        try check(store.state.tabs.first { $0.id == oldArchived.id } == oldArchived, "Unchanged earlier archive recovers its original folder reference")
        try check(manager.canRedo && !manager.canUndo, "Whole group moves to native Redo stack")
        manager.redo(); try check(manager.isBusy && store.state.tabs == initial.tabs, "Redo waits for fresh actual page consent")
        finish?(false)
        try check(manager.canRedo && store.state.tabs == initial.tabs, "Redo refusal preserves retry and all originals")
        manager.redo(); try check(authorize?() == true, "Redo captures current genuine owners"); finish?(true)
        try check(manager.canUndo && !manager.canRedo && store.state.folders == [remaining], "Redo commits one group after consent")
        manager.undo()
        var changed = store.state
        changed.tabs.append(tab("New child", folder: second.id))
        try encoder.encode(changed).write(to: sessionURL)
        let other = try BrowserStore(directory: root)
        try check(record.redoTarget(in: other.state) == nil, "Redo never expands to a newly inserted child")
        var moved = store.state; moved.tabs[moved.tabs.firstIndex { $0.id == loose.id }!].folderID = nil
        try check(record.redoTarget(in: moved) == nil, "Reparented original invalidates whole Redo")
        var repinned = store.state; repinned.tabs[repinned.tabs.firstIndex { $0.id == today.id }!].kind = .pinned
        try check(record.redoTarget(in: repinned) == nil, "Changed root section invalidates Redo ownership")
        let noFolders = FolderRemovalTarget(items: [.tab(today.id),.tab(keep.id)], spaceID: space.id, profileID: profile.id, state: store.state)!
        try check(noFolders.folderIDs.isEmpty && noFolders.tabs.count == 2, "Explicit tab-only archive uses the same collection owner")
        print("\(count) plural removal assertions passed")
    }
}
