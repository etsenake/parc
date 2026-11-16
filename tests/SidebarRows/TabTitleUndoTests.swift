import AppKit
import Combine

@main @MainActor struct TabTitleUndoTests {
    static var count = 0
    static func expect(_ value: @autoclosure () throws -> Bool, _ message: String) throws {
        count += 1
        if try !value() { throw NSError(domain: message, code: count) }
    }
    static func main() { exitOnFailure(runChecks) }
    static func runChecks() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-tab-title-undo-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try BrowserStore(directory: directory)
        let id = store.openResolvedURL(URL(string: "https://original.test/anchor")!)
        store.updateTab(id, title: "Original page")
        let profile = store.activeSpace.profileID
        func tab() -> BrowserTab { store.state.tabs.first { $0.id == id }! }
        let owner = FolderUndoManager(), otherWindow = FolderUndoManager()
        var available = true, errors = 0, publications = 0
        let observation = store.statePublisher.dropFirst().sink { _ in publications += 1 }
        func record(_ title: String, in manager: FolderUndoManager) throws -> SidebarTabTitleChange? {
            guard let change = try store.saveSidebarTitle(tab(), title: title) else { return nil }
            try expect(manager.appendTabTitleChange(change, store: store, available: { available }, onError: { _ in errors += 1 }), "Successful original tab change enters the window stack")
            return change
        }
        let first = try record("  Research\n", in: owner)!
        try expect(first.tabID == id && first.profileID == profile && first.previousTitle == nil && first.title == "Research", "Original ID/profile and trimmed optional title are captured")
        try expect(owner.undoMenuItemTitle == "Undo Rename Item" && !otherWindow.canUndo, "Native action naming and per-window chronology")
        let pending = owner.command(.undo)!
        available = false
        try expect(!owner.canPerform(pending) && !owner.canUndo, "Window/profile context loss blocks a captured command")
        available = true
        try expect(owner.canPerform(pending), "Temporary context loss does not discard the inverse")
        store.updateTab(id, title: "New live title", url: "https://original.test/next")
        let current = store.state, countBefore = publications
        owner.undo()
        try expect(tab().customTitle == nil && SidebarTabTitle.display(tab()) == "New live title", "Today Undo reveals the actual current fallback")
        var expected = current; expected.tabs[expected.tabs.firstIndex { $0.id == id }!].customTitle = nil
        try expect(store.state == expected, "Only the manual title changes; destination, history, selection and access state are identical")
        try expect(publications == countBefore + 1, "Durable inverse publishes exactly once to shared observers")
        try expect(owner.redoMenuItemTitle == "Redo Rename Item" && !owner.canPerform(pending), "Menu revision follows successful commit")
        owner.redo()
        try expect(tab().customTitle == "Research", "Redo reapplies original manual name")
        try expect(try BrowserStore(directory: directory).state.tabs.first { $0.id == id }?.customTitle == "Research", "Name inverse is durable")
        _ = try record("Planning", in: owner)
        owner.undo(); owner.undo()
        try expect(tab().customTitle == nil, "Consecutive changes Undo in order")
        owner.redo(); owner.redo()
        try expect(tab().customTitle == "Planning", "Consecutive changes Redo in order")
        _ = try record(" \n", in: owner)
        try expect(tab().customTitle == nil, "Empty edit removes only custom override")
        owner.undo()
        try expect(tab().customTitle == "Planning", "Undo clearing restores previous optional name")
        try expect(try record("Planning", in: owner) == nil && owner.canRedo, "Equal or unchanged edit preserves Redo")
        _ = try record("Other window", in: otherWindow)
        try expect(!owner.canRedo && otherWindow.canUndo, "Competing shared rename invalidates stale inverse")
        otherWindow.undo()
        try expect(tab().customTitle == "Planning" && !owner.canRedo, "Shared observer sees inverse without resurrecting discarded history")
        owner.removeAllActions(); otherWindow.removeAllActions()
        _ = try record("Saved name", in: owner)
        store.setKind(id, .pinned)
        let savedURL = tab().savedURL, savedTitle = tab().savedTitle
        store.updateTab(id, title: "Away title", url: "https://original.test/away")
        let destination = store.createSpace(name: "Destination")
        store.moveTab(id, toSpace: destination)
        owner.undo()
        try expect(tab().customTitle == "Planning" && tab().kind == .pinned && tab().spaceID == destination, "Inverse follows same original ID after pin and same-profile move")
        try expect(tab().savedURL == savedURL && tab().savedTitle == savedTitle && tab().url == "https://original.test/away", "Pinned saved destination and live page remain independent")
        owner.redo(); store.setKind(id, .favorite)
        owner.undo()
        try expect(tab().kind == .favorite && tab().customTitle == "Planning", "Prior original-tab inverse survives Favorite membership without a Favorite editor")
        owner.redo(); store.setKind(id, .pinned)
        let sibling = store.openResolvedURL(URL(string: "https://sibling.test")!)
        store.setKind(sibling, .pinned); store.setSplit([id, sibling])
        let group = store.state.splitLayouts.first { $0.tabIDs.contains(id) }!
        let edit = SidebarSplitTitleEdit(group: group, profileID: profile, state: store.state)!
        let splitChange = try store.saveSidebarSplitTitle(edit, title: "Group")!
        _ = owner.appendSplitTitleChange(splitChange, store: store, available: { available }, onError: { _ in errors += 1 })
        owner.undo(); owner.undo()
        try expect(store.state.splitLayouts.first!.customTitle == nil && tab().customTitle == "Planning", "Original container and child title changes share chronology without substituting identities")
        owner.redo(); owner.redo()
        try expect(store.state.splitLayouts.first!.customTitle == "Group" && tab().customTitle == "Saved name", "Mixed original names Redo independently")
        owner.removeAllActions()
        _ = try record("Retirement", in: owner)
        var finish: ((Bool) -> Void)?
        store.requestPageRetirement = { _, _, completion in finish = completion }
        store.closeTab(id)
        try expect(!owner.canUndo, "Native retirement reservation blocks inverse")
        finish?(false)
        try expect(owner.canUndo, "Refused beforeunload restores original inverse availability")
        store.requestPageRetirement = nil
        let beforeFailure = store.state
        try FileManager.default.removeItem(at: directory); try Data().write(to: directory)
        owner.undo()
        try expect(store.state == beforeFailure && errors == 1 && owner.canUndo && !owner.canRedo, "Actual write failure retains shared state and retryable stack")
        try FileManager.default.removeItem(at: directory); try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        owner.undo()
        try expect(tab().customTitle == "Saved name" && owner.canRedo, "Retry publishes original inverse")
        let redoCommand = owner.command(.redo)!
        owner.redo(); store.setKind(id, .today); store.closeTab(id)
        try expect(tab().archivedAt != nil && !owner.canUndo && !owner.canPerform(redoCommand), "Archived original cannot be renamed or reopened by inverse")
        store.deleteArchivedTabs([id])
        try expect(!store.state.tabs.contains { $0.id == id } && !owner.canUndo, "Deleted original is not recreated")
        owner.removeAllActions()
        try expect(owner.undoMenuItemTitle == "Undo", "Window teardown clears name chronology")
        let privatePath = directory.appendingPathComponent("never-created")
        let privateStore = BrowserStore(privateParentProfileID: profile, engineProfilePath: "/not-opened", directory: privatePath, settings: store.state.settings)
        let privateID = privateStore.openResolvedURL(URL(string: "https://private.test")!)
        let privateTab = privateStore.state.tabs.first { $0.id == privateID }!
        let privateChange = try privateStore.saveSidebarTitle(privateTab, title: "Private")!
        let privateUndo = FolderUndoManager()
        _ = privateUndo.appendTabTitleChange(privateChange, store: privateStore, available: { true }, onError: { _ in errors += 1 })
        privateUndo.undo()
        try expect(privateStore.state.tabs.first!.customTitle == nil, "Actual memory-only owner Undo")
        privateUndo.redo()
        try expect(privateStore.state.tabs.first!.customTitle == "Private" && !FileManager.default.fileExists(atPath: privatePath.path), "Private Redo writes no profile/model files")
        var changed = privateStore.state; changed.profiles.removeAll()
        try expect(privateChange.target(in: changed, undo: true) == nil, "Retired profile invalidates original capability")
        changed = privateStore.state; changed.tabs[0].id = UUID()
        try expect(privateChange.target(in: changed, undo: true) == nil, "Matching title on replacement is not original tab")
        changed = privateStore.state; changed.tabs[0].profileID = UUID()
        try expect(privateChange.target(in: changed, undo: true) == nil, "Cross-profile reassignment refuses inverse")
        var released: BrowserStore? = BrowserStore(privateParentProfileID: profile, engineProfilePath: "/not-opened", directory: privatePath, settings: store.state.settings)
        let releasedID = released!.openResolvedURL(URL(string: "https://released.test")!)
        let releasedChange = try released!.saveSidebarTitle(released!.state.tabs.first { $0.id == releasedID }!, title: "Name")!
        let detached = FolderUndoManager()
        _ = detached.appendTabTitleChange(releasedChange, store: released!, available: { true }, onError: { _ in errors += 1 })
        let survivingStore = { [weak released] in released }; released = nil
        try expect(survivingStore() == nil && !detached.canUndo, "Stack never retains a closed private/model owner")
        withExtendedLifetime(observation) {}
        print("TabTitleUndoTests: \(count) assertions passed")
    }
}
