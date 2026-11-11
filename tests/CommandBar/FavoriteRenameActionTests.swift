import AppKit

@main @MainActor struct FavoriteRenameActionTests {
    static var count = 0
    static func check(_ value: @autoclosure () -> Bool, _ message: String) {
        count += 1; precondition(value(), message)
    }
    static func main() throws {
        let profile = BrowserProfile(id: UUID(), name: "Original")
        let foreign = BrowserProfile(id: UUID(), name: "Foreign")
        let origin = BrowserSpace(id: UUID(), name: "Origin", symbol: "circle", color: "ABCDEF", profileID: profile.id)
        let space = BrowserSpace(id: UUID(), name: "Current", symbol: "circle", color: "ABCDEF", profileID: profile.id)
        let favorite = BrowserTab(id: UUID(), spaceID: origin.id, profileID: profile.id,
            url: "https://example.test/current", title: "Current page", kind: .favorite,
            createdAt: Date(timeIntervalSince1970: 100), lastAccessed: Date(timeIntervalSince1970: 100),
            savedURL: "https://example.test/home", savedTitle: "Saved title")
        var ordinary = favorite; ordinary.id = UUID(); ordinary.kind = .today; ordinary.spaceID = space.id
        var state = BrowserState(profiles: [profile, foreign], spaces: [origin, space], activeSpaceID: origin.id)
        state.tabs = [favorite, ordinary]
        state.selectedTabIDs = [ordinary.id]
        func make(_ state: BrowserState, _ ids: [UUID] = [favorite.id]) -> CommandBarFavoriteRenameAction? {
            .init(state: state, spaceID: space.id, profileID: profile.id, selectedTabIDs: ids)
        }
        let action = make(state)!
        func current(_ state: BrowserState, _ ids: [UUID] = [favorite.id]) -> BrowserTab? {
            action.currentTab(in: state, spaceID: space.id, profileID: profile.id, selectedTabIDs: ids)
        }
        check(action.tab == favorite && action.spaceID == space.id, "Original Favorite is profile-wide in actual command Space")
        check(action.title == "Rename Current Tab…", "Recovered Type Travel title")
        check(action.matches(query: "rename") && action.matches(query: "CURRENT TAB") && action.matches(query: "tab ren"), "Bounded command word matching")
        check(!action.matches(query: "") && !action.matches(query: "rename folder") && !action.matches(query: "> rename"), "No fabricated trigger or unrelated command")
        check(make(state, []) == nil && make(state, [favorite.id, favorite.id]) == nil, "No empty or repeated current selection")
        check(make(state, [favorite.id, ordinary.id]) == nil, "Whole selection never becomes focused child")
        check(make(state, [ordinary.id]) == nil, "Ordinary row retains existing inline command owner")
        check(current(state, [ordinary.id]) == nil, "Changed window selection refuses original action")
        check(current(state) == favorite && state.selectedTabIDs == [ordinary.id], "No shared-state selection write or fallback")
        var changed = state; changed.tabs[0].title = "Live update"; changed.tabs[0].url = "https://example.test/redirect"
        check(current(changed)?.url == changed.tabs[0].url && current(changed)?.title == "Live update", "Original live metadata can advance without replacing rename target")
        check(action.id == make(changed)!.id, "Native metadata does not change contextual result identity")
        changed = state; changed.tabs[0].customTitle = "Another window"
        check(current(changed) == nil, "Concurrent shared rename expires original action")
        changed = state; changed.tabs[0].savedURL = "https://example.test/new-home"
        check(current(changed) == nil, "Original saved anchor replacement expires")
        changed = state; changed.tabs[0].createdAt.addTimeInterval(1)
        check(current(changed) == nil, "Reused UUID with a new incarnation cannot rename")
        changed = state; changed.tabs[0].kind = .pinned
        check(current(changed) == nil, "Unfavorite invalidates dialog capability")
        changed = state; changed.tabs[0].profileID = foreign.id
        check(current(changed) == nil, "Foreign profile never substitutes")
        changed = state; changed.tabs[0].archivedAt = Date()
        check(current(changed) == nil, "Archive invalidates original target")
        changed = state; changed.tabs.removeFirst()
        check(current(changed) == nil, "Deleted target never falls back to other current item")
        changed = state; changed.profileRemovals = [.init(id: UUID(), profileID: profile.id, profileName: profile.name)]
        check(current(changed) == nil, "Profile retirement invalidates original action")
        changed = state; changed.profiles.removeAll { $0.id == profile.id }
        check(current(changed) == nil, "Missing original profile refuses")
        changed = state; changed.spaces.removeAll { $0.id == space.id }
        check(current(changed) == nil, "Missing original command Space refuses")
        changed = state; changed.splitLayouts = [.init(spaceID: space.id, tabIDs: [favorite.id, ordinary.id], orientation: .horizontal, widthFactors: [0.5, 0.5])]
        check(current(changed) == nil, "Reparented split child cannot use Favorite dialog capability")
        check(action.currentTab(in: state, spaceID: origin.id, profileID: profile.id, selectedTabIDs: [favorite.id]) == nil, "Space change cannot retarget original command session")
        check(action.currentTab(in: state, spaceID: space.id, profileID: foreign.id, selectedTabIDs: [favorite.id]) == nil, "Profile change cannot retarget original command session")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-rename-action-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try BrowserStore(directory: directory)
        let id = store.openResolvedURL(URL(string: "https://example.test/original")!); store.setKind(id, .favorite)
        let original = store.state.tabs.first { $0.id == id }!
        let prepared = CommandBarFavoriteRenameAction(state: store.state, spaceID: store.state.activeSpaceID,
            profileID: original.profileID, selectedTabIDs: [id])!
        let before = store.state
        let exact = prepared.currentTab(in: store.state, spaceID: store.state.activeSpaceID,
            profileID: original.profileID, selectedTabIDs: [id])!
        let change = try store.saveFavoriteTitle(exact, title: "Research 🪐")!
        var expected = before; expected.tabs[expected.tabs.firstIndex { $0.id == id }!].customTitle = "Research 🪐"
        check(store.state == expected, "Command resolution changes only original title, not page destination/selection/history")
        let undo = FolderUndoManager(); _ = undo.appendTabTitleChange(change, store: store, available: { true }, onError: { _ in })
        undo.undo(); check(store.state.tabs.first { $0.id == id }?.customTitle == nil, "Actual original-window Undo restores original title")
        undo.redo(); check(store.state.tabs.first { $0.id == id }?.customTitle == "Research 🪐", "Actual Redo preserves same Favorite identity")
        print("FavoriteRenameActionTests: \(count) assertions passed")
    }
}
