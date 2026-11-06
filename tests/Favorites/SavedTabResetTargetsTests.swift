import Foundation

@main struct SavedTabResetTargetsTests {
    static func main() {
        var checks = 0
        func check(_ value: @autoclosure () -> Bool, _ message: String) {
            precondition(value(), message); checks += 1
        }
        let now = Date(timeIntervalSince1970: 1000)
        var state = BrowserState.initial()
        let space = state.activeSpaceID, profile = state.profiles[0].id
        let otherSpace = UUID(), otherProfile = UUID()
        state.spaces.append(.init(id: otherSpace, name: "Other", symbol: "circle", color: "AABBCC", profileID: profile))
        state.profiles.append(.init(id: otherProfile, name: "Other profile"))
        func tab(_ name: String, kind: TabKind = .pinned, folder: UUID? = nil) -> BrowserTab {
            .init(id: UUID(), spaceID: space, profileID: profile,
                  url: "https://example.test/away/" + name, title: name, kind: kind, folderID: folder,
                  createdAt: now, lastAccessed: now, savedURL: "https://example.test/home/" + name, savedTitle: name)
        }
        let open = BrowserFolder(id: UUID(), spaceID: space, name: "Open", isExpanded: true)
        let closed = BrowserFolder(id: UUID(), spaceID: space, name: "Closed", isExpanded: false)
        let nested = BrowserFolder(id: UUID(), spaceID: space, name: "Nested", parentID: open.id, isExpanded: true)
        let favorite = tab("favorite", kind: .favorite), root = tab("root"), last = tab("last")
        var siblingFavorite = tab("shared", kind: .favorite); siblingFavorite.spaceID = otherSpace
        var foreignFavorite = tab("foreign", kind: .favorite); foreignFavorite.profileID = otherProfile
        let child = tab("child", folder: open.id), deep = tab("deep", folder: nested.id)
        let hidden = tab("hidden", folder: closed.id), splitA = tab("split-a"), splitB = tab("split-b")
        let today = tab("today", kind: .today)
        var archived = tab("archived"); archived.archivedAt = now
        var home = tab("home"); home.url = home.savedURL
        var equivalent = tab("equivalent"); equivalent.url = "http://WWW.example.test/HOME/equivalent/?utm_source=x#part"
        var local = tab("local"); local.url = "parc://note/" + UUID().uuidString; local.savedURL = local.url
        var elsewhere = tab("elsewhere"); elsewhere.spaceID = otherSpace
        let split = BrowserSplitLayout(sidebarAnchorID: splitA.id, spaceID: space,
            tabIDs: [splitB.id, splitA.id], widthFactors: [0.5, 0.5])
        state.folders = [closed, nested, open]
        state.splitLayouts = [split]
        state.tabs = [hidden, last, splitA, deep, today, siblingFavorite, root, child, favorite,
                      foreignFavorite, splitB, archived, home, equivalent, local, elsewhere]
        let rootLocation = SidebarContainerLocation(spaceID: space, folderID: nil, section: .pinned)
        let openLocation = SidebarContainerLocation(spaceID: space, folderID: open.id, section: .pinned)
        state.sidebarItemOrder[rootLocation.key] = [.tab(root.id), .folder(open.id), .split(split.id), .folder(closed.id), .tab(last.id)]
        state.sidebarItemOrder[openLocation.key] = [.folder(nested.id), .tab(child.id)]
        state.selectedTabIDs = [today.id]
        func targets(_ s: BrowserState) -> [UUID] { SavedTabResetTargets.collect(in: s, spaceID: space).map(\.id) }
        let expected = [siblingFavorite.id, favorite.id, root.id, deep.id, child.id, splitB.id, splitA.id, last.id]
        check(targets(state) == expected, "Favorites then mixed visible pinned hierarchy and original split order")
        check(!targets(state).contains(hidden.id), "Collapsed folder descendants excluded")
        check(!targets(state).contains(today.id), "Today excluded even if it has a different saved URL")
        check(!targets(state).contains(foreignFavorite.id), "Foreign profile Favorite excluded")
        check(!targets(state).contains(elsewhere.id), "Other Space pinned tab excluded")
        check(!targets(state).contains(archived.id), "Archived saved tab excluded")
        check(!targets(state).contains(home.id) && !targets(state).contains(equivalent.id), "Full-URL equivalence filters unchanged targets")
        check(!targets(state).contains(local.id), "Local documents are not reset navigation targets")
        check(SavedTabResetTargets.collect(in: state, spaceID: UUID()).isEmpty, "Missing Space cannot redirect to active Space")
        let captured = SavedTabResetTargets.collect(in: state, spaceID: space)
        check(captured.map(\.savedURL) == expected.map { id in state.tabs.first { $0.id == id }!.savedURL }, "Actual saved destination remains unchanged")
        check(state.selectedTabIDs == [today.id], "Collection does not select or focus a target")
        var edited = state; edited.folders[0].isExpanded = true
        check(targets(edited) == Array(expected.dropLast()) + [hidden.id, last.id], "Disclosure inserts children at original sibling slot")
        edited = state; edited.folders[2].isExpanded = false
        check(targets(edited) == expected.filter { $0 != child.id && $0 != deep.id }, "Collapsed ancestor hides expanded descendants")
        edited = state; edited.folders[1].isExpanded = false
        check(targets(edited) == expected.filter { $0 != deep.id }, "Nested disclosure is independent")
        edited = state; edited.sidebarItemOrder[rootLocation.key] = [.tab(last.id), .tab(root.id), .folder(open.id), .split(split.id)]
        check(targets(edited) == [siblingFavorite.id, favorite.id, last.id, root.id, deep.id, child.id, splitB.id, splitA.id], "Mixed sibling reordering changes dispatch order")
        edited = state; edited.splitLayouts[0].tabIDs.reverse()
        check(targets(edited) == [siblingFavorite.id, favorite.id, root.id, deep.id, child.id, splitA.id, splitB.id, last.id], "Pane order belongs to original whole split")
        edited = state; edited.profileRemovals = [.init(id: UUID(), profileID: profile, profileName: "Default")]
        check(targets(edited).isEmpty, "Staged profile retirement invalidates the batch")
        edited = state; edited.profiles.removeAll { $0.id == profile }
        check(targets(edited).isEmpty, "Removed profile cannot be recreated")
        edited = state; edited.spaces[0].profileID = otherProfile
        check(targets(edited) == [foreignFavorite.id], "Space profile replacement never leaks old profile targets")
        edited = state; edited.tabs.removeAll { $0.id == root.id }
        check(targets(edited) == expected.filter { $0 != root.id }, "Stale stored sibling identity is ignored")
        edited = state; edited.tabs[0].url += "/new"
        check(captured.map(\.id) == expected && captured.first?.url == siblingFavorite.url, "Admitted snapshot is a value, not a late enumeration")
        edited = state; edited.splitLayouts = [.init(sidebarAnchorID: root.id, spaceID: space,
            tabIDs: [root.id, favorite.id], widthFactors: [0.5, 0.5])]
        let grouped = targets(edited)
        check(grouped.first == siblingFavorite.id && grouped.prefix(3) == [siblingFavorite.id, root.id, favorite.id], "Grouped Favorite uses visible split position, not hidden App Tray slot")
        check(grouped.filter { $0 == favorite.id }.count == 1, "An original Favorite in a split dispatches once")
        edited = state; edited.splitLayouts = [.init(sidebarAnchorID: today.id, spaceID: space,
            tabIDs: [today.id, favorite.id], widthFactors: [0.5, 0.5])]
        check(!targets(edited).contains(favorite.id), "Favorite removed from App Tray into Today split is not a visible saved root")
        print("Saved-tab reset target checks: \(checks)")
    }
}
