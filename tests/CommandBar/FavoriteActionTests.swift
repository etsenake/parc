import AppKit

@main @MainActor
struct FavoriteActionTests {
    static var count = 0
    static func check(_ value: @autoclosure () -> Bool, _ message: String) {
        count += 1; precondition(value(), message)
    }
    static func main() throws {
        let profile = BrowserProfile(id: UUID(), name: "Original")
        let foreign = BrowserProfile(id: UUID(), name: "Other")
        let space = BrowserSpace(id: UUID(), name: "Origin", symbol: "circle", color: "ABCDEF", profileID: profile.id)
        let other = BrowserSpace(id: UUID(), name: "Other Space", symbol: "circle", color: "ABCDEF", profileID: profile.id)
        let folder = BrowserFolder(id: UUID(), spaceID: space.id, name: "Folder", isExpanded: false)
        func tab(_ kind: TabKind, _ title: String) -> BrowserTab {
            BrowserTab(id: UUID(), spaceID: space.id, profileID: profile.id,
                url: "https://example.test/" + title, title: title, kind: kind,
                folderID: kind == .pinned ? folder.id : nil,
                createdAt: Date(timeIntervalSince1970: 100), lastAccessed: Date(timeIntervalSince1970: 100),
                savedURL: "https://home.test/" + title, savedTitle: "Home " + title)
        }
        let first = tab(.today, "First"), second = tab(.pinned, "Second")
        let existing = tab(.favorite, "Existing"), last = tab(.today, "Last")
        var state = BrowserState(profiles: [profile, foreign], spaces: [space, other], activeSpaceID: space.id)
        state.tabs = [first, existing, second, last]; state.folders = [folder]
        state.selectedTabIDs = [first.id]; state.selectionBySpace = [space.id.uuidString: [first.id], other.id.uuidString: [existing.id]]
        func action(_ ids: [UUID], _ state: BrowserState) -> CommandBarFavoriteAction? {
            CommandBarFavoriteAction(items: ids.map(SidebarItemReference.tab), spaceID: space.id, profileID: profile.id, state: state)
        }
        let add = action([first.id, second.id], state)!
        check(add.title == "Favorite Tab" && add.operation == .favorite, "Recovered literal and operation")
        check(add.tabIDs == [first.id, second.id], "Original collection order retained")
        check(add.matches(query: "favorite") && add.matches(query: "TAB FAVOR"), "Bounded word matching")
        check(!add.matches(query: "") && !add.matches(query: "> favorite") && !add.matches(query: "unfavorite"), "No invented trigger or inverse")
        check(action([], state) == nil && action([first.id, first.id], state) == nil, "Empty/duplicate original collection refused")
        check(action([first.id, existing.id], state) == nil, "Mixed membership offers neither action")
        check(CommandBarFavoriteAction(items: [.folder(folder.id)], spaceID: space.id, profileID: profile.id, state: state) == nil, "Container does not flatten into page actions")
        let promoted = add.applying(to: state)!
        check(promoted.tabs.filter { $0.kind == .favorite }.map(\.id) == [existing.id, first.id, second.id], "Promotion appends after existing original Favorites")
        check(promoted.tabs.first { $0.id == first.id }?.savedURL == first.url, "Today snapshots actual current home")
        check(promoted.tabs.first { $0.id == second.id }?.savedURL == second.savedURL, "Existing pin home survives promotion")
        check(promoted.tabs.filter { add.tabIDs.contains($0.id) }.allSatisfy { $0.folderID == nil }, "Original folder membership cleared")
        check(promoted.selectedTabIDs == state.selectedTabIDs && promoted.selectionBySpace == state.selectionBySpace, "No page selection or return map rewriting")
        check(promoted.folders == state.folders && promoted.history == state.history, "No parent deletion, disclosure or history mutation")
        check(!add.isCurrent(in: promoted) && add.applying(to: promoted) == nil, "An accepted payload cannot repeat against changed membership")
        let remove = CommandBarFavoriteAction(items: [.tab(first.id), .tab(second.id)], spaceID: other.id, profileID: profile.id, state: promoted)!
        let demoted = remove.applying(to: promoted)!
        check(remove.title == "Unfavorite Tab" && remove.operation == .unfavorite, "Recovered inverse title")
        check(demoted.tabs.prefix(2).map(\.id) == [first.id, second.id], "Unfavorite prepends exact original collection")
        check(demoted.tabs.prefix(2).allSatisfy { $0.kind == .today && $0.spaceID == other.id && $0.folderID == nil }, "Inverse uses captured current Space unpinned destination")
        check(demoted.tabs.first { $0.id == second.id }?.savedURL == second.url, "Demotion retains established Today saved boundary")
        check(demoted.tabs.first { $0.id == existing.id } == existing && demoted.tabs.first { $0.id == last.id } == last, "Unrelated original records remain equal")
        check(demoted.selectedTabIDs == state.selectedTabIDs, "Membership transaction never navigates or closes")
        var changed = state; changed.tabs[0].title = "Live title"; changed.tabs[0].url = "https://redirect.test/"
        check(add.isCurrent(in: changed), "Live original metadata does not replace membership identity")
        check(add.applying(to: changed)?.tabs.first { $0.id == first.id }?.savedURL == "https://redirect.test/", "Real current metadata remains authoritative")
        changed = state; changed.tabs[0].createdAt.addTimeInterval(1)
        check(!add.isCurrent(in: changed), "Replaced original ID incarnation expires")
        changed = state; changed.tabs[0].spaceID = other.id
        check(!add.isCurrent(in: changed), "Original source Space cannot retarget")
        changed = state; changed.tabs[2].folderID = nil
        check(!add.isCurrent(in: changed), "Reparented original item expires")
        changed = state; changed.tabs[0].profileID = foreign.id
        check(!add.isCurrent(in: changed), "Exact original Profile retained")
        changed = state; changed.tabs[0].archivedAt = Date()
        check(!add.isCurrent(in: changed), "Archived original expires")
        changed = state; changed.tabs.removeFirst()
        check(!add.isCurrent(in: changed), "Missing source cannot fall back to current tab")
        changed = state; changed.profiles.removeAll { $0.id == profile.id }
        check(!add.isCurrent(in: changed), "Retired Profile refuses")
        changed = state; changed.spaces.removeAll { $0.id == space.id }
        check(!add.isCurrent(in: changed), "Missing destination refuses")
        changed = state
        changed.splitLayouts = [BrowserSplitLayout(spaceID: space.id, tabIDs: [first.id, last.id], orientation: .horizontal, widthFactors: [0.5, 0.5])]
        check(action([first.id], changed) == nil, "A live/persisted split pane cannot be silently extracted")
        check(CommandBarFavoriteAction(items: [.split(changed.splitLayouts[0].id)], spaceID: space.id, profileID: profile.id, state: changed) == nil, "Whole split retains separate membership owner")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-favorite-actions-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let file = directory.appendingPathComponent("session.json")
        try encoder.encode(state).write(to: file)
        let store = try BrowserStore(directory: directory)
        let storeAction = action([first.id, second.id], store.state)!
        let committed = try store.performFavoriteAction(storeAction)
        check(committed, "Actual durable store transaction succeeds")
        let reopened = try BrowserStore(directory: directory)
        check(reopened.state.tabs.filter { $0.kind == .favorite }.map(\.id) == [existing.id, first.id, second.id], "Exact order and membership survive disk reload")
        check(reopened.state.tabs.first { $0.id == second.id }?.savedURL == second.savedURL, "Pinned home survives disk reload")
        let stale = try store.performFavoriteAction(storeAction)
        check(!stale, "Real store refuses consumed membership")
        try encoder.encode(state).write(to: file)
        let failing = try BrowserStore(directory: directory); let before = failing.state
        let failedAction = action([first.id, second.id], before)!
        try FileManager.default.removeItem(at: file); try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
        var refused = false
        do { _ = try failing.performFavoriteAction(failedAction) } catch { refused = true }
        check(refused && failing.state == before, "Failed atomic write publishes no partial membership")
        _ = NSApplication.shared
        let cell = CommandResultCell(title: add.title, detail: "", accessory: "", isTab: false,
            icon: NSImage(systemSymbolName: "star.fill", accessibilityDescription: nil), enabled: true)
        var activated = 0; cell.onPress = { activated += 1; return true }
        check(cell.accessibilityLabel() == "Favorite Tab", "Native result uses recovered literal with no invented scope")
        check(cell.accessibilityPerformPress() && activated == 1, "AX reaches original action once")
        cell.setSelected(true); check(cell.isAccessibilitySelected(), "Original typed action has selected state")
        let expired = CommandResultCell(title: add.title, detail: "", accessory: "", isTab: false, icon: nil, enabled: false)
        expired.onPress = { activated += 1; return true }
        check(!expired.accessibilityPerformPress() && activated == 1, "Disabled stale row cannot retarget through AX")
        print("FavoriteActionTests: \(count) assertions passed")
    }
}
