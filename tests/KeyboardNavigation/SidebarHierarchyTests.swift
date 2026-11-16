import Foundation

@main @MainActor struct SidebarHierarchyTests {
    static func main() { exitOnFailure(runChecks) }
    static func runChecks() throws {
        var count = 0
        func check(_ value: @autoclosure () -> Bool, _ message: String) {
            count += 1; precondition(value(), message)
        }
        var state = BrowserState.initial()
        let space = state.spaces[0], profile = space.profileID
        let outer = BrowserFolder(id: UUID(), spaceID: space.id, name: "Outer", parentID: nil, isExpanded: true)
        let inner = BrowserFolder(id: UUID(), spaceID: space.id, name: "Inner", parentID: outer.id, isExpanded: false)
        let empty = BrowserFolder(id: UUID(), spaceID: space.id, name: "Empty", parentID: nil, isExpanded: false)
        func tab(_ name: String, _ kind: TabKind, _ parent: UUID? = nil) -> BrowserTab {
            .init(id: UUID(), spaceID: space.id, profileID: profile, url: "https://example.invalid/" + name,
                title: name, kind: kind, folderID: parent, createdAt: .distantPast, lastAccessed: .distantPast,
                savedURL: "https://example.invalid/" + name, savedTitle: name)
        }
        let favorite = tab("Favorite", .favorite), a = tab("A", .pinned, outer.id), b = tab("B", .pinned, outer.id)
        let hidden = tab("Hidden", .pinned, inner.id), today = tab("Today", .today)
        let group = BrowserSplitLayout(id: UUID(), sidebarAnchorID: b.id, spaceID: space.id,
            tabIDs: [a.id, b.id], orientation: .vertical, widthFactors: [0.35, 0.65])
        state.tabs = [favorite, a, b, hidden, today]; state.folders = [outer, inner, empty]
        state.splitLayouts = [group]; state.selectedTabIDs = group.tabIDs
        state.selectionBySpace[space.id.uuidString] = group.tabIDs
        state.sidebarItemOrder[SidebarContainerLocation(spaceID: space.id, folderID: nil, section: .pinned).key] = [.folder(outer.id), .folder(empty.id)]
        state.sidebarItemOrder[SidebarContainerLocation(spaceID: space.id, folderID: outer.id, section: .pinned).key] = [.folder(inner.id), .split(group.id)]
        func items(_ unavailable: Set<UUID> = []) -> [SidebarKeyboardNavigation.Item] {
            SidebarKeyboardNavigation.items(state: state, spaceID: space.id, selected: group.tabIDs,
                focused: b.id, available: { !unavailable.contains($0) })
        }
        let expected: [SidebarItemReference] = [.tab(favorite.id), .folder(outer.id), .folder(inner.id), .split(group.id), .folder(empty.id), .tab(today.id)]
        let entries = items()
        check(entries.map(\.reference) == expected, "Mixed displayed order includes ordinary and empty folders")
        check(entries.first { $0.reference == .folder(inner.id) }?.selection == nil, "Folder highlight cannot select a page")
        check(entries.first { $0.reference == .folder(inner.id) }?.folder == inner, "Folder commit captures original disclosure")
        let split = entries.first { $0.reference == .split(group.id) }!
        check(split.selection?.tabIDs == group.tabIDs, "Whole split owns one target")
        check(split.selection?.focusedTabID == b.id, "Original focused pane retained")
        check(split.selection?.orientation == .vertical, "Original split orientation retained")
        check(!entries.contains { $0.reference == .tab(a.id) || $0.reference == .tab(b.id) }, "No split-child duplicate keyboard rows")
        check(!entries.contains { $0.reference == .tab(hidden.id) }, "Collapsed ancestor hides children")
        check(items([b.id]).allSatisfy { $0.reference != .split(group.id) }, "Unavailable member excludes the complete split")
        check(items([b.id]).contains { $0.reference == .folder(outer.id) }, "Folder disclosure does not require opening its children")
        var cursor = SidebarKeyboardCursor(highlightedID: entries[2].id)
        let before = state
        cursor.move(1, in: entries.map(\.id))
        check(cursor.highlightedID == split.id && state == before, "Arrow movement is independent from active page/state")
        cursor.move(1, in: entries.map(\.id))
        check(cursor.highlightedID == entries[4].id, "Whole split consumes one arrow step")
        state.folders[0].isExpanded = false
        check(items().map(\.reference) == [.tab(favorite.id), .folder(outer.id), .folder(empty.id), .tab(today.id)], "Collapsing omits all descendants while retaining folder")
        cursor = SidebarKeyboardCursor(highlightedID: split.id)
        cursor.reconcile(items().map(\.id))
        check(cursor.highlightedID == nil, "Removed descendant cannot retarget a later row")
        state.folders[0].isExpanded = true; state.folders[1].isExpanded = true
        check(items().contains { $0.reference == .tab(hidden.id) }, "Expanding enters actual child identities")
        let positional = PositionalTabNavigation.items(state: state, spaceID: space.id, selected: group.tabIDs, focused: b.id, available: { _ in true })
        check(positional.count == 4, "Positional tab commands still omit folder rows")
        state.folders[1].isExpanded = false
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-sidebar-keyboard-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("session.json")
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(state).write(to: file)
        let store = try BrowserStore(directory: directory)
        let original = store.state
        let committed = try store.setFolderExpanded(true, expected: inner, profileID: profile)
        check(committed, "Return expansion commits")
        check(store.state.selectedTabIDs == original.selectedTabIDs && store.state.activeSpaceID == original.activeSpaceID, "Disclosure preserves page and Space selection")
        check(store.state.tabs == original.tabs && store.state.splitLayouts == original.splitLayouts, "Disclosure preserves original records and split geometry")
        let loaded = try BrowserStore(directory: directory)
        check(loaded.state.folders.first { $0.id == inner.id }?.isExpanded == true, "Disclosure is durable before publication")
        let stale = try store.setFolderExpanded(false, expected: inner, profileID: profile)
        check(!stale && store.state.folders.first { $0.id == inner.id }?.isExpanded == true, "Stale disclosure token cannot reverse a newer action")
        var current = inner; current.isExpanded = true
        let refused = try store.setFolderExpanded(false, expected: current, profileID: UUID())
        check(!refused, "Foreign profile cannot mutate disclosure")
        let collapsed = try store.setFolderExpanded(false, expected: current, profileID: profile)
        check(collapsed && store.state.folders.first { $0.id == inner.id }?.isExpanded == false, "Second Return collapses exact folder")
        let emptyCommitted = try store.setFolderExpanded(true, expected: empty, profileID: profile)
        check(emptyCommitted, "Empty folder uses the same actual disclosure transaction")
        let prior = store.state
        try FileManager.default.removeItem(at: file)
        try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
        do { _ = try store.setFolderExpanded(true, expected: inner, profileID: profile); preconditionFailure("Expected save failure") }
        catch { count += 1 }
        check(store.state == prior, "Failed save cannot publish disclosure or any browser-state change")
        let privateStore = BrowserStore(privateParentProfileID: profile, engineProfilePath: "/unused-original-context",
            directory: directory.appendingPathComponent("must-not-exist"), settings: state.settings)
        let privateRefused = try privateStore.setFolderExpanded(true, expected: inner, profileID: profile)
        check(!privateRefused && !FileManager.default.fileExists(atPath: privateStore.directory.path), "Ephemeral owner never writes normal folder state")
        print("PASS: \(count) sidebar hierarchy keyboard assertions")
    }
}
