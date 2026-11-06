import AppKit

@main @MainActor
struct FolderCopyTests {
    static var count = 0
    static func check(_ value: @autoclosure () -> Bool, _ message: String) {
        count += 1; precondition(value(), message)
    }
    static func main() throws {
        let profile = BrowserProfile(id: UUID(), name: "Profile")
        let space = BrowserSpace(id: UUID(), name: "Source", symbol: "circle", color: "000000", profileID: profile.id)
        let away = BrowserSpace(id: UUID(), name: "Destination", symbol: "circle", color: "000000", profileID: profile.id)
        let folder = BrowserFolder(id: UUID(), spaceID: space.id, name: "Original", isExpanded: false)
        let nested = BrowserFolder(id: UUID(), spaceID: space.id, name: "Nested", parentID: folder.id, isExpanded: false)
        let destination = BrowserFolder(id: UUID(), spaceID: away.id, name: "Destination", isExpanded: false)
        func tab(_ name: String, kind: TabKind = .today, folderID: UUID? = nil) -> BrowserTab {
            var tab = BrowserTab(id: UUID(), spaceID: space.id, profileID: profile.id,
                url: "https://persisted.invalid/" + name, title: "Live " + name, kind: kind, folderID: folderID,
                createdAt: Date(timeIntervalSince1970: 100), lastAccessed: Date(timeIntervalSince1970: 100),
                savedURL: "https://saved.invalid/" + name, savedTitle: "Saved " + name)
            tab.customTitle = "Custom " + name; tab.isMuted = true
            return tab
        }
        let ordinary = tab("ordinary"), favorite = tab("favorite", kind: .favorite)
        let child = tab("child", kind: .pinned, folderID: folder.id)
        let left = tab("left", kind: .pinned, folderID: nested.id), right = tab("right", kind: .pinned, folderID: nested.id)
        let split = BrowserSplitLayout(sidebarAnchorID: left.id, customTitle: "Layout", spaceID: space.id,
            tabIDs: [left.id, right.id], orientation: .vertical, widthFactors: [0.2, 0.8])
        var state = BrowserState(profiles: [profile], spaces: [space, away], activeSpaceID: space.id)
        state.folders = [folder, nested, destination]; state.tabs = [ordinary, favorite, child, left, right]
        state.splitLayouts = [split]; state.selectedTabIDs = [ordinary.id]
        state.selectionBySpace = [space.id.uuidString: [ordinary.id]]
        let source = CommandBarFolderMoveSource(items: [.tab(ordinary.id), .tab(favorite.id), .folder(folder.id)],
            spaceID: space.id, profileID: profile.id, state: state)!
        let move = CommandBarFolderMove.snapshot(source: source, state: state).first { $0.folder.folderID == destination.id }!
        let now = Date(timeIntervalSince1970: 1000)
        let destinations = Dictionary(uniqueKeysWithValues: source.tabIDs.map { ($0, "https://materialized.invalid/" + $0.uuidString) })
        let copy = CommandBarFolderCopy(move: move, destinations: destinations, state: state, now: now)!
        let copied = copy.applying(to: state)!
        check(copy.roots.count == 3, "All original roots copied in order")
        check(copy.tabs.count == 5 && copy.folders.count == 2 && copy.groups.count == 1, "Complete nested tree and split copied")
        check(Set(copy.tabs.map(\.id)).isDisjoint(with: source.tabIDs), "New original tab identities")
        check(Set(copy.folders.map(\.id)).isDisjoint(with: state.folders.map(\.id)), "Fresh folder identities")
        check(copy.groups[0].id != split.id, "Fresh split container")
        check(copied.tabs.prefix(state.tabs.count).elementsEqual(state.tabs), "All original values unchanged")
        check(copied.folders.prefix(state.folders.count - 1).elementsEqual(state.folders.dropLast()), "Original folder content unchanged")
        check(copied.splitLayouts.first == split, "Original group unchanged")
        check(copied.selectedTabIDs == state.selectedTabIDs && copied.selectionBySpace == state.selectionBySpace, "No copied-page selection is forged")
        check(copied.activeSpaceID == state.activeSpaceID, "Original Space remains current")
        check(copy.tabs.allSatisfy { $0.profileID == profile.id && $0.spaceID == away.id && $0.kind == .pinned }, "Exact destination Profile/Space pinning")
        check(copy.tabs.allSatisfy { $0.createdAt == now && $0.lastAccessed == now && $0.isUnread }, "New creation and unread metadata")
        check(copy.tabs.allSatisfy { $0.archivedAt == nil && $0.archiveProvenance == nil }, "No original archive identity leaks")
        check(copy.tabs[0].savedURL == destinations[ordinary.id] && copy.tabs[0].url == destinations[ordinary.id], "Resolved original native URL retained")
        check(copy.tabs[0].title == ordinary.savedTitle && copy.tabs[0].customTitle == ordinary.customTitle && copy.tabs[0].isMuted, "Original saved/custom/mute presentation retained")
        check(copy.tabs[1].savedURL == destinations[favorite.id], "Favorite copy uses actual resolved destination")
        check(copy.groups[0].customTitle == split.customTitle && copy.groups[0].orientation == split.orientation && copy.groups[0].widthFactors == split.widthFactors, "Split title/orientation/proportions retained")
        check(copy.groups[0].tabIDs == Array(copy.tabs.suffix(2).map(\.id)), "Group children use exact new IDs")
        check(copy.groups[0].sidebarAnchorID == copy.tabs[3].id, "Original anchor mapped to its copied child")
        check(copy.folders[0].parentID == destination.id && copy.folders[1].parentID == copy.folders[0].id, "Nested parent map is original hierarchy")
        check(copy.folders.allSatisfy { !$0.isExpanded }, "Original nested disclosure retained")
        check(copy.tabs[2].folderID == copy.folders[0].id && copy.tabs[3].folderID == copy.folders[1].id, "Original child containers mapped")
        check(copy.openTabIDs == [copy.tabs[0].id, copy.tabs[1].id, copy.tabs[3].id, copy.tabs[4].id], "Top-level direct tabs and nested split children eager; ordinary folder child saved-only")
        check(SidebarHierarchy.children(in: .init(spaceID: away.id, folderID: destination.id, section: .pinned), state: copied) == copy.roots, "Original root order appended into target")
        check(SidebarHierarchy.children(in: .init(spaceID: away.id, folderID: copy.folders[1].id, section: .pinned), state: copied) == [.split(copy.groups[0].id)], "Stored split anchor normalizes to exact copied group")
        check(copy.applying(to: copied) == nil, "One proposal never duplicates IDs twice")
        check(CommandBarFolderCopy(move: move, destinations: [:], state: state, now: now) == nil, "No missing source URL fallback")
        var wrong = destinations; wrong[UUID()] = "https://extra.invalid"
        check(CommandBarFolderCopy(move: move, destinations: wrong, state: state, now: now) == nil, "Foreign URL token refused")
        wrong = destinations; wrong[ordinary.id] = "parc://note/" + UUID().uuidString
        check(CommandBarFolderCopy(move: move, destinations: wrong, state: state, now: now) == nil, "No typed document URL replay")
        var changed = state; changed.tabs[0].createdAt.addTimeInterval(1)
        check(copy.applying(to: changed) == nil, "Replaced original expires")
        changed = state; changed.tabs[0].url = "https://new-live.invalid/"
        check(copy.applying(to: changed) != nil, "Unrelated live navigation is not identity replacement")
        changed = state; changed.folders.removeLast()
        check(copy.applying(to: changed) == nil, "Removed original destination expires")
        changed = state; changed.tabs[2].savedURL = "parc://easel/" + UUID().uuidString
        let typedSource = CommandBarFolderMoveSource(items: [.folder(folder.id)], spaceID: space.id, profileID: profile.id, state: changed)!
        let typedMove = CommandBarFolderMove.snapshot(source: typedSource, state: changed).first { $0.folder.folderID == destination.id }!
        let typedURLs = Dictionary(uniqueKeysWithValues: typedSource.tabIDs.map { ($0, "https://unrelated.invalid") })
        check(CommandBarFolderCopy(move: typedMove, destinations: typedURLs, state: changed, now: now) == nil, "Mixed typed subtree refuses atomically even with a supplied URL")
        var many = state; many.tabs = (0..<7).map { tab("root\($0)") }; many.splitLayouts = []
        let manySource = CommandBarFolderMoveSource(items: many.tabs.map { .tab($0.id) }, spaceID: space.id, profileID: profile.id, state: many)!
        let manyMove = CommandBarFolderMove.snapshot(source: manySource, state: many).first { $0.folder.folderID == destination.id }!
        let manyURLs = Dictionary(uniqueKeysWithValues: many.tabs.map { ($0.id, $0.savedURL) })
        let manyCopy = CommandBarFolderCopy(move: manyMove, destinations: manyURLs, state: many, now: now)!
        check(manyCopy.tabs.count == 7 && manyCopy.openTabIDs == Array(manyCopy.tabs.prefix(5).map(\.id)), "Exact indexed first-five policy does not cap durable copies")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-folder-copy-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(state).write(to: directory.appendingPathComponent("session.json"))
        let store = try BrowserStore(directory: directory, now: { now })
        let storedSource = CommandBarFolderMoveSource(items: source.roots, spaceID: space.id, profileID: profile.id, state: store.state)!
        let storedMove = CommandBarFolderMove.snapshot(source: storedSource, state: store.state).first { $0.folder.folderID == destination.id }!
        let saved = try store.copyCommandBarItemsToFolder(storedMove, destinations: destinations)!
        let reopened = try BrowserStore(directory: directory)
        check(saved.tabs.allSatisfy { tab in reopened.state.tabs.contains(tab) }, "All exact copied tabs durably reload")
        check(saved.folders.allSatisfy { folder in reopened.state.folders.contains(folder) }, "All copied folder identities reload")
        check(saved.groups.allSatisfy { group in reopened.state.splitLayouts.contains(group) }, "Original copied split identity reloads")
        check(reopened.state.tabs.filter { source.tabIDs.contains($0.id) } == state.tabs, "Persisted originals survive unchanged")
        let retrySource = CommandBarFolderMoveSource(items: source.roots, spaceID: space.id, profileID: profile.id, state: store.state)!
        let retryMove = CommandBarFolderMove.snapshot(source: retrySource, state: store.state).first { $0.folder.folderID == destination.id }!
        let before = store.state
        try FileManager.default.removeItem(at: directory); try Data("not-directory".utf8).write(to: directory)
        var threw = false
        do { _ = try store.copyCommandBarItemsToFolder(retryMove, destinations: destinations) } catch { threw = true }
        check(threw && store.state == before, "Real failed write publishes no new original or copied identity")
        print("\(count) folder-copy assertions passed")
    }
}
