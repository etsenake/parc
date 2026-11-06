import AppKit

@main @MainActor
struct FolderMoveTests {
    static var count = 0
    static func check(_ value: @autoclosure () -> Bool, _ message: String) {
        count += 1; precondition(value(), message)
    }
    static func main() throws {
        let profile = BrowserProfile(id: UUID(), name: "Original")
        let foreign = BrowserProfile(id: UUID(), name: "Other")
        let origin = BrowserSpace(id: UUID(), name: "Origin", symbol: "circle", color: "ABCDEF", profileID: profile.id)
        let away = BrowserSpace(id: UUID(), name: "Away", symbol: "circle", color: "ABCDEF", profileID: profile.id)
        let other = BrowserSpace(id: UUID(), name: "Foreign", symbol: "circle", color: "ABCDEF", profileID: foreign.id)
        let sourceFolder = BrowserFolder(id: UUID(), spaceID: origin.id, name: "Source", isExpanded: false)
        let nested = BrowserFolder(id: UUID(), spaceID: origin.id, name: "Nested", parentID: sourceFolder.id, isExpanded: false)
        let here = BrowserFolder(id: UUID(), spaceID: origin.id, name: "Destination", isExpanded: false)
        let there = BrowserFolder(id: UUID(), spaceID: away.id, name: "Destination", isExpanded: false)
        let wrong = BrowserFolder(id: UUID(), spaceID: other.id, name: "Destination", isExpanded: false)
        func tab(_ title: String, kind: TabKind = .today, folder: UUID? = nil) -> BrowserTab {
            BrowserTab(id: UUID(), spaceID: origin.id, profileID: profile.id, url: "https://current.test/" + title,
                title: title, kind: kind, folderID: folder, createdAt: Date(timeIntervalSince1970: 100),
                lastAccessed: Date(timeIntervalSince1970: 100), savedURL: "https://home.test/" + title, savedTitle: "Home")
        }
        let first = tab("First"), last = tab("Last"), child = tab("Child", kind: .pinned, folder: nested.id)
        let favorite = tab("Favorite", kind: .favorite)
        let resident = tab("Resident", kind: .pinned, folder: here.id)
        var state = BrowserState(profiles: [profile, foreign], spaces: [origin, away, other], activeSpaceID: origin.id)
        state.folders = [sourceFolder, nested, here, there, wrong]
        state.tabs = [first, child, last, favorite, resident]
        state.selectedTabIDs = [first.id]; state.selectionBySpace = [origin.id.uuidString: [first.id]]
        func source(_ items: [SidebarItemReference], _ state: BrowserState) -> CommandBarFolderMoveSource? {
            CommandBarFolderMoveSource(items: items, spaceID: origin.id, profileID: profile.id, state: state)
        }
        func action(_ source: CommandBarFolderMoveSource, _ folderID: UUID, _ state: BrowserState) -> CommandBarFolderMove? {
            CommandBarFolderMove.snapshot(source: source, state: state).first { $0.folder.folderID == folderID }
        }
        let input = source([.tab(first.id), .tab(last.id)], state)!
        let move = action(input, here.id, state)!
        check(move.title == "Pin to", "Recovered renderer literal")
        check(CommandBarFolderMove.matching([move], query: "move destination") == [move], "Actual destination matching alias")
        check(CommandBarFolderMove.matching([move], query: "PIN TO") == [move], "Visible action matching")
        check(CommandBarFolderMove.matching([move], query: "").isEmpty, "No invented empty-query action")
        check(action(input, wrong.id, state) == nil, "No cross-Profile folder")
        check(CommandBarFolderMove.snapshot(source: input, state: state).filter { $0.folder.name == "Destination" }.map { $0.folder.detail }.count == 2, "Duplicate named original destinations retain Space context")
        let moved = move.applying(to: state)!
        check(moved.tabs.map(\.id) == state.tabs.map(\.id), "Original records, no clone")
        check(moved.tabs.filter { input.tabIDs.contains($0.id) }.allSatisfy { $0.kind == .pinned && $0.folderID == here.id }, "Today items become actual folder pins")
        check(moved.tabs[0].savedURL == first.url, "Promotion captures actual current destination")
        check(SidebarHierarchy.children(in: .init(spaceID: origin.id, folderID: here.id, section: .pinned), state: moved) == [.tab(resident.id), .tab(first.id), .tab(last.id)], "Stable collection append after existing children")
        check(moved.selectedTabIDs == state.selectedTabIDs && moved.selectionBySpace == state.selectionBySpace, "Same-Space move retains active original page")
        check(moved.folders.first { $0.id == here.id }?.isExpanded == true, "Existing folder transaction expands target")
        check(moved.tabs[1] == child && moved.tabs[3] == favorite, "Unrelated original metadata unchanged")
        check(move.applying(to: moved) == nil, "Original membership cannot be reused")
        let already = source([.tab(resident.id)], state)!
        check(action(already, here.id, state) == nil, "Original same-parent exclusion")
        let mixed = source([.tab(first.id), .tab(resident.id)], state)!
        check(action(mixed, here.id, state) == nil, "Collection with same-parent item refuses rather than reorders")
        let folderInput = source([.folder(sourceFolder.id), .tab(child.id)], state)!
        check(folderInput.roots == [.folder(sourceFolder.id)], "Ancestor owns its original subtree once")
        check(action(folderInput, sourceFolder.id, state) == nil && action(folderInput, nested.id, state) == nil, "Self/descendant cycles refused")
        let folderMove = action(folderInput, there.id, state)!
        let relocated = folderMove.applying(to: state)!
        check(relocated.folders.first { $0.id == sourceFolder.id }?.parentID == there.id, "Whole folder goes into actual destination")
        check(relocated.folders.filter { [sourceFolder.id, nested.id].contains($0.id) }.allSatisfy { $0.spaceID == away.id }, "Nested tree remains one same-Profile hierarchy")
        check(relocated.tabs.first { $0.id == child.id }?.folderID == nested.id && relocated.tabs.first { $0.id == child.id }?.savedURL == child.savedURL, "Nested original home and parent survive")
        check(relocated.folders.first { $0.id == nested.id }?.isExpanded == false, "Descendant disclosure remains original")
        let favoriteMove = action(source([.tab(favorite.id)], state)!, there.id, state)!
        let favoriteMoved = favoriteMove.applying(to: state)!.tabs.first { $0.id == favorite.id }!
        check(favoriteMoved.spaceID == away.id && favoriteMoved.kind == .pinned && favoriteMoved.folderID == there.id, "Original Favorite can become a folder pin in same Profile")
        check(favoriteMoved.savedURL == favorite.savedURL && favoriteMoved.createdAt == favorite.createdAt, "Favorite home and incarnation are retained")
        var groupState = state
        let group = BrowserSplitLayout(sidebarAnchorID: first.id, spaceID: origin.id, tabIDs: [first.id, last.id], orientation: .horizontal, widthFactors: [0.3, 0.7])
        groupState.splitLayouts = [group]
        check(source([.tab(first.id)], groupState) == nil, "Pane is not silently extracted")
        let groupInput = source([.split(group.id)], groupState)!
        let groupMoved = action(groupInput, there.id, groupState)!.applying(to: groupState)!
        check(groupMoved.splitLayouts[0].id == group.id && groupMoved.splitLayouts[0].tabIDs == group.tabIDs && groupMoved.splitLayouts[0].widthFactors == group.widthFactors, "Original whole split and proportions survive")
        check(groupMoved.splitLayouts[0].spaceID == away.id && groupMoved.tabs.filter { group.tabIDs.contains($0.id) }.allSatisfy { $0.folderID == there.id }, "Whole split membership moves together")
        var changed = state; changed.tabs[0].url = "https://redirect.test/"; changed.tabs[0].title = "Live"
        check(move.isCurrent(in: changed) && move.applying(to: changed)?.tabs[0].savedURL == "https://redirect.test/", "Live metadata allowed, no URL replay")
        changed = state; changed.tabs[0].createdAt.addTimeInterval(1)
        check(!move.isCurrent(in: changed), "Original incarnation replacement expires")
        changed = state; changed.tabs[0].archivedAt = Date()
        check(!move.isCurrent(in: changed), "Archived source expires")
        changed = state; changed.folders.removeAll { $0.id == here.id }
        check(!move.isCurrent(in: changed), "Removed destination cannot retarget by name")
        changed = state; changed.folders[2].spaceID = away.id
        check(!move.isCurrent(in: changed), "Moved destination expires")
        changed = state; changed.spaces[0].profileID = foreign.id
        check(!move.isCurrent(in: changed), "Profile ownership changes refuse")
        check(source([], state) == nil && source([.tab(first.id), .tab(first.id)], state) == nil, "Empty/duplicate source refuses")
        let emptyInput = source([.folder(here.id)], state)!
        // Empty folders still have an original container; their transaction does
        // not require a fictitious page/native lease.
        var emptyState = state; emptyState.tabs.removeAll { $0.id == resident.id }
        let empty = source([.folder(here.id)], emptyState)!
        check(empty.tabIDs.isEmpty && action(empty, there.id, emptyState)?.applying(to: emptyState)?.folders.first { $0.id == here.id }?.parentID == there.id, "Empty original folder moves without materializing a page")
        check(emptyInput.roots == [.folder(here.id)], "Nonempty folder retains one original root")
        var otherWindowState = state; otherWindowState.activeSpaceID = other.id; otherWindowState.selectedTabIDs = []
        check(move.applying(to: otherWindowState)?.tabs[0].folderID == here.id, "Captured Space does not follow shared store active window")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-folder-move-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(state).write(to: directory.appendingPathComponent("session.json"))
        let store = try BrowserStore(directory: directory)
        let storedMove = action(source([.tab(first.id)], store.state)!, there.id, store.state)!
        let committed = try store.performCommandBarFolderMove(storedMove)
        check(committed, "Real durable Store transaction accepts")
        let reopened = try BrowserStore(directory: directory)
        check(reopened.state.tabs.first { $0.id == first.id }?.folderID == there.id, "Exact folder placement survives real reload")
        check(reopened.state.tabs.first { $0.id == first.id }?.id == first.id, "Reload preserves original item")
        // A real failed write must not publish the intermediate Space relocation.
        let failed = try BrowserStore(directory: directory)
        let retry = action(source([.tab(last.id)], failed.state)!, there.id, failed.state)!
        let unchanged = failed.state
        try FileManager.default.removeItem(at: directory)
        try Data("not a directory".utf8).write(to: directory)
        var threw = false
        do { _ = try failed.performCommandBarFolderMove(retry) } catch { threw = true }
        check(threw && failed.state == unchanged, "Persistence failure publishes no partial move")
        let cell = CommandResultCell(title: move.title, detail: move.folder.detail, accessory: "↩", isTab: false,
            icon: nil, enabled: true, folderAction: move.folder)
        check(cell.accessibilityLabel()?.contains("Pin to, Destination") == true, "Actual native row names action and original destination")
        var pressed = false; cell.onPress = { pressed = true; return true }
        check(cell.accessibilityPerformPress() && pressed, "AX reaches original row callback")
        let disabled = CommandResultCell(title: move.title, detail: move.folder.detail, accessory: "", isTab: false,
            icon: nil, enabled: false, folderAction: move.folder)
        disabled.onPress = { preconditionFailure("Expired target must not activate") }
        check(!disabled.accessibilityPerformPress(), "Expired native row refuses")
        cell.frame = NSRect(x: 0, y: 0, width: 320, height: 50); cell.layoutSubtreeIfNeeded()
        check(cell.subviews.allSatisfy { $0.frame.width >= 0 && $0.frame.height >= 0 }, "Narrow native folder row remains bounded")
        print("\(count) folder-move assertions passed")
    }
}
