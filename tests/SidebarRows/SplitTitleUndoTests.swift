import AppKit
import Combine

@main @MainActor struct SplitTitleUndoTests {
    static var count = 0
    static func expect(_ value: @autoclosure () throws -> Bool, _ message: String) throws {
        count += 1
        if try !value() { throw NSError(domain: message, code: count) }
    }
    static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-split-undo-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try BrowserStore(directory: directory)
        let a = store.openResolvedURL(URL(string: "https://one.test")!), b = store.openResolvedURL(URL(string: "https://two.test")!)
        store.setSplit([a, b])
        let profile = store.activeSpace.profileID, groupID = store.state.splitLayouts.first!.id
        func target() -> SidebarSplitTitleEdit {
            let group = store.state.splitLayouts.first { $0.id == groupID }!
            return SidebarSplitTitleEdit(group: group, profileID: profile, state: store.state)!
        }
        let original = store.state
        let owner = FolderUndoManager(), otherWindow = FolderUndoManager()
        var available = true, errors = 0, publications = 0
        let observation = store.statePublisher.dropFirst().sink { _ in publications += 1 }
        func record(_ text: String, in manager: FolderUndoManager) throws -> SidebarSplitTitleChange? {
            guard let change = try store.saveSidebarSplitTitle(target(), title: text) else { return nil }
            try expect(manager.appendSplitTitleChange(change, store: store, available: { available }, onError: { _ in errors += 1 }), "Committed original container registers")
            return change
        }
        let first = try record("Research", in: owner)!
        try expect(first.containerID == groupID && first.profileID == profile, "Original container/profile are captured")
        try expect(owner.undoMenuItemTitle == "Undo Rename Item" && !otherWindow.canUndo, "Window-local native label; shared state is not duplicated into another window's stack")
        let command = owner.command(.undo)!
        available = false
        try expect(!owner.canPerform(command) && !owner.canUndo, "Transient window gate refuses stale menu dispatch")
        available = true
        try expect(owner.canPerform(command), "Cancelled interruption preserves original command")
        try expect(store.setSplitLayout(orientation: .vertical, widthFactors: [1, 3]), "Original geometry can change")
        store.updateTab(a, title: "Live", url: "https://one.test/next")
        let current = store.state, beforeUndoPublications = publications
        owner.undo()
        try expect(store.state.splitLayouts.first!.customTitle == nil && owner.canRedo, "Undo restores original absence, not a child title")
        try expect(publications == beforeUndoPublications + 1, "Atomic inverse publishes once to every shared observer")
        try expect(store.state.tabs == current.tabs && store.state.selectedTabIDs == current.selectedTabIDs && store.state.history == current.history, "Page objects, live destination, focus and history are untouched")
        try expect(store.state.splitLayouts.first!.orientation == .vertical && store.state.splitLayouts.first!.widthFactors == current.splitLayouts.first!.widthFactors, "Undo never reinstates stale geometry")
        try expect(owner.redoMenuItemTitle == "Redo Rename Item" && !owner.canPerform(command), "Redo label and exact command revision advance together")
        owner.redo()
        try expect(store.state.splitLayouts.first!.customTitle == "Research", "Redo reapplies original name")
        try expect(try BrowserStore(directory: directory).state.splitLayouts.first!.customTitle == "Research", "Successful inverse is durable")
        _ = try record("Planning", in: owner)
        owner.undo(); owner.undo()
        try expect(store.state.splitLayouts.first!.customTitle == nil, "Consecutive rename changes undo in chronology")
        owner.redo(); owner.redo()
        try expect(store.state.splitLayouts.first!.customTitle == "Planning", "Consecutive rename Redo retains chronology")
        owner.undo()
        try expect(try record("Research", in: owner) == nil && owner.canRedo, "Same-value edit leaves Redo intact")
        try expect(owner.canRedo, "No registration occurs for cancellation")
        _ = try record("Shared window", in: otherWindow)
        try expect(!owner.canRedo && otherWindow.canUndo, "A competing shared name invalidates the older inverse")
        otherWindow.undo()
        try expect(store.state.splitLayouts.first!.customTitle == "Research" && !owner.canRedo, "Other-window inverse updates shared label without reviving discarded history")
        owner.removeAllActions(); otherWindow.removeAllActions()
        _ = try record("Retirement", in: owner)
        var finish: ((Bool) -> Void)?
        store.requestPageRetirement = { _, _, done in finish = done }
        store.closeTab(a)
        try expect(!owner.canUndo && store.canApplySplitTitleChange(first, undo: true) == false, "Native retirement reservation blocks name inverse")
        finish?(false)
        try expect(owner.canUndo, "Cancelled retirement restores original inverse availability")
        store.requestPageRetirement = nil
        let beforeFailure = store.state
        try FileManager.default.removeItem(at: directory); try Data().write(to: directory)
        owner.undo()
        try expect(store.state == beforeFailure && errors == 1 && owner.canUndo && !owner.canRedo, "Failed durable Undo retains state and retryable stack")
        try FileManager.default.removeItem(at: directory); try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        owner.undo()
        try expect(owner.canRedo && store.state.splitLayouts.first!.customTitle == "Research", "Retry commits the same inverse")
        owner.redo(); store.closeTab(a)
        try expect(!owner.canUndo && !owner.canRedo, "Deleted/dissolved original container cannot be renamed or recreated")
        try expect(store.state.tabs.first { $0.id == b }?.customTitle == original.tabs.first { $0.id == b }?.customTitle, "Remaining child is never substituted")
        owner.removeAllActions()
        try expect(owner.undoMenuItemTitle == "Undo" && !owner.canUndo, "Window closure drops name history")
        let privatePath = directory.appendingPathComponent("uncreated-private")
        let privateStore = BrowserStore(privateParentProfileID: profile, engineProfilePath: "/not-opened", directory: privatePath, settings: store.state.settings)
        let pa = privateStore.openResolvedURL(URL(string: "https://private-one.test")!), pb = privateStore.openResolvedURL(URL(string: "https://private-two.test")!)
        privateStore.setSplit([pa, pb])
        let privateTarget = SidebarSplitTitleEdit.current(state: privateStore.state, spaceID: privateStore.activeSpaceID, profileID: privateStore.activeSpace.profileID, selectedTabIDs: [pa, pb])!
        let privateChange = try privateStore.saveSidebarSplitTitle(privateTarget, title: "Private")!
        let privateUndo = FolderUndoManager()
        try expect(privateUndo.appendSplitTitleChange(privateChange, store: privateStore, available: { true }, onError: { _ in errors += 1 }), "Private original store supports the same stack")
        privateUndo.undo(); try expect(privateStore.state.splitLayouts.first!.customTitle == nil, "Private Undo is real")
        privateUndo.redo(); try expect(privateStore.state.splitLayouts.first!.customTitle == "Private", "Private Redo is real")
        try expect(!FileManager.default.fileExists(atPath: privatePath.path), "Private name history writes no model/profile files")
        var changed = privateStore.state
        changed.profiles.removeAll()
        try expect(privateChange.target(in: changed, undo: true) == nil, "Retired profile invalidates original capability")
        changed = privateStore.state; changed.splitLayouts[0].id = UUID()
        try expect(privateChange.target(in: changed, undo: true) == nil, "Replacement with identical title/children is not original container")
        changed = privateStore.state; changed.spaces[0].profileID = UUID()
        try expect(privateChange.target(in: changed, undo: true) == nil, "Changed profile ownership refuses inverse")
        changed = privateStore.state; changed.splitLayouts[0].tabIDs.reverse()
        try expect(privateChange.target(in: changed, undo: true) != nil, "Original container keeps title Undo after child reorder")
        let newSpace = BrowserSpace(id: UUID(), name: "Destination", symbol: "circle", color: "B9B5D4", profileID: privateChange.profileID)
        changed = privateStore.state; changed.spaces.append(newSpace); changed.splitLayouts[0].spaceID = newSpace.id
        for i in changed.tabs.indices { changed.tabs[i].spaceID = newSpace.id }
        try expect(privateChange.target(in: changed, undo: true)?.spaceID == newSpace.id, "Same-profile cross-Space relocation retains original title capability")
        let mixed = FolderUndoManager(); var closed = true
        _ = mixed.append(.init(name: "Archive Tab", isValid: { _ in true }, isAvailable: { _ in true }, perform: { direction, done in closed = direction == .redo; done(true) }))
        _ = mixed.appendSplitTitleChange(privateChange, store: privateStore, available: { true }, onError: { _ in errors += 1 })
        mixed.undo(); try expect(closed && mixed.undoMenuItemTitle == "Undo Archive Tab", "Rename is undone before preceding close on the same stack")
        mixed.undo(); try expect(!closed && mixed.redoMenuItemTitle == "Redo Archive Tab", "Original close remains next in chronology")
        mixed.redo(); mixed.redo()
        try expect(closed && privateStore.state.splitLayouts.first!.customTitle == "Private", "Mixed Redo restores actions in original order")
        withExtendedLifetime(observation) {}
        print("SplitTitleUndoTests: \(count) assertions passed")
    }
}
