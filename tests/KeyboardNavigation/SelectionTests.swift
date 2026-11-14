import Foundation

@main struct SelectionTests {
    static func main() {
        var checks = 0
        func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
            checks += 1; precondition(condition(), message)
        }
        var state = BrowserState.initial()
        let space = state.activeSpaceID, profile = state.profiles[0].id
        func tab(_ name: String, _ kind: TabKind = .today, folder: UUID? = nil) -> BrowserTab {
            .init(id: UUID(), spaceID: space, profileID: profile, url: "https://example.invalid/\(name)", title: name,
                  kind: kind, folderID: folder, createdAt: .distantPast, lastAccessed: .distantPast,
                  archivedAt: nil, savedURL: "", savedTitle: "")
        }
        let expanded = BrowserFolder(id: UUID(), spaceID: space, name: "Expanded", parentID: nil)
        let nested = BrowserFolder(id: UUID(), spaceID: space, name: "Nested", parentID: expanded.id)
        let collapsed = BrowserFolder(id: UUID(), spaceID: space, name: "Collapsed", parentID: nil, isExpanded: false)
        let favorite = tab("favorite", .favorite), pinned = tab("pinned", .pinned)
        let folderTab = tab("folder", .pinned, folder: expanded.id), nestedTab = tab("nested", .pinned, folder: nested.id)
        let hidden = tab("hidden", .pinned, folder: collapsed.id), today = tab("today")
        var archived = tab("archived"); archived.archivedAt = Date()
        var foreign = tab("foreign"); foreign.profileID = UUID()
        state.tabs = [today, favorite, pinned, folderTab, nestedTab, hidden, archived, foreign]
        state.folders = [expanded, nested, collapsed]
        func items(_ selection: [UUID] = [], unavailable: Set<UUID> = []) -> [RecentTabOrder.Item] {
            PositionalTabNavigation.items(state: state, spaceID: space, selected: selection, focused: selection.last,
                                          available: { !unavailable.contains($0) })
        }
        let ordered = items()
        expect(ordered.flatMap(\.tabIDs) == [favorite.id, pinned.id, folderTab.id, nestedTab.id, today.id], "Sidebar sections, expansion and profile/archive filtering")
        expect(PositionalTabNavigation.destination(ordered, selected: [today.id], forward: true)?.tabIDs == [favorite.id], "Forward wraps")
        expect(PositionalTabNavigation.destination(ordered, selected: [favorite.id], forward: false)?.tabIDs == [today.id], "Backward wraps")
        expect(PositionalTabNavigation.destination(ordered, selected: [hidden.id], forward: true)?.tabIDs == [favorite.id], "Missing selection starts at first")
        expect(PositionalTabNavigation.destination(ordered, selected: [], forward: false)?.tabIDs == [today.id], "Missing reverse selection starts at last")
        expect(PositionalTabNavigation.destination([], selected: [], forward: true) == nil, "Empty list")
        expect(!items(unavailable: [pinned.id]).flatMap(\.tabIDs).contains(pinned.id), "Native owner unavailable")
        let withoutFavorites = PositionalTabNavigation.items(state: state, spaceID: space, selected: [], focused: nil,
                                                             includeFavorites: false, available: { _ in true })
        expect(withoutFavorites.flatMap(\.tabIDs) == [pinned.id, folderTab.id, nestedTab.id, today.id], "Excluded Favorites leave the ordering")
        expect(NumberedTarget.destination(ordered, number: 1, ninthItemEnabled: false)?.tabIDs == [favorite.id], "Item 1 starts with Favorites")
        expect(NumberedTarget.destination(withoutFavorites, number: 1, ninthItemEnabled: false)?.tabIDs == [pinned.id], "Item 1 after Favorites")
        expect(NumberedTarget.destination(ordered, number: 6, ninthItemEnabled: false) == nil, "Past the end selects nothing")
        expect(NumberedTarget.destination(ordered, number: 9, ninthItemEnabled: false)?.tabIDs == [today.id], "Item 9 is the last item")
        expect(NumberedTarget.destination(ordered, number: 9, ninthItemEnabled: true) == nil, "Ninth-item setting indexes the ninth")
        expect(NumberedTarget.destination(ordered, number: 0, ninthItemEnabled: false) == nil
               && NumberedTarget.destination(ordered, number: 10, ninthItemEnabled: false) == nil, "Only tags 1…9")
        expect(NumberedTarget.itemNumber("item9") == 9 && NumberedTarget.itemNumber("item10") == nil
               && NumberedTarget.itemNumber("item01") == nil && NumberedTarget.spaceNumber("space3") == 3
               && NumberedTarget.spaceNumber("space10") == 10 && NumberedTarget.spaceNumber("space0") == nil, "Space binding IDs")
        expect(NumberedTarget.description(for: "item2", excludeFavorites: false, ninthItemEnabled: false)
               == "Jumps to the second item in your Sidebar, starting with your Favorites at the top.", "Including description")
        expect(NumberedTarget.description(for: "item9", excludeFavorites: true, ninthItemEnabled: false)
               == "Jumps to the last item at the bottom of your Sidebar.", "Last-item description")
        expect(NumberedTarget.description(for: "item9", excludeFavorites: true, ninthItemEnabled: true)
               == "Jumps to the ninth item in your Sidebar, after your Favorites at the top.", "Ninth-item description")
        expect(NumberedTarget.description(for: "space1", excludeFavorites: false, ninthItemEnabled: false)
               == "Jumps over to your 1st Space without needing to swipe.", "Space description")
        state.splitLayouts = [.init(spaceID: space, tabIDs: [pinned.id, today.id], orientation: .vertical, widthFactors: [0.4, 0.6])]
        let grouped = items([pinned.id, today.id])
        expect(grouped.count == 4, "Split is one positional item")
        expect(grouped[1].tabIDs == [pinned.id, today.id], "Split occupies first constituent position")
        expect(grouped[1].focusedTabID == today.id && grouped[1].orientation == .vertical, "Split focus and orientation")
        expect(!items(unavailable: [today.id]).flatMap(\.tabIDs).contains(pinned.id), "Unavailable split is not broken into a different selection")
        state.splitLayouts[0].sidebarAnchorID = today.id
        expect(items().last?.tabIDs == [pinned.id, today.id], "Typed group is placed at its stable sidebar anchor")
        state.splitLayouts[0].sidebarAnchorID = pinned.id
        state.folders[0].isExpanded = false
        expect(!items().flatMap(\.tabIDs).contains(nestedTab.id), "Collapsed ancestor hides descendants")

        state.folders[0].isExpanded = true
        let root = SidebarContainerLocation(spaceID: space, folderID: nil, section: .pinned)
        state.sidebarItemOrder[root.key] = [.folder(expanded.id), .tab(pinned.id), .folder(collapsed.id)]
        expect(items().first?.tabIDs == [favorite.id], "Favorites remain outside the same-Space folder order")
        expect(items().dropFirst().first?.tabIDs == [folderTab.id], "Keyboard traversal follows mixed folder-before-tab order")
        state.sidebarItemOrder[SidebarContainerLocation(spaceID: space, folderID: expanded.id, section: .pinned).key] = [.folder(nested.id), .tab(folderTab.id)]
        expect(items().dropFirst().first?.tabIDs == [nestedTab.id], "Nested folder-before-tab order is traversed recursively")
        let copied = FolderLinks.links(in: state, target: .init(folderID: expanded.id, spaceID: space, profileID: profile))
        expect(copied?.map(\.tabID) == [nestedTab.id, folderTab.id], "Copy All Links follows exact mixed child order")
        state.folders[0].isExpanded = false
        expect(FolderLinks.links(in: state, target: .init(folderID: expanded.id, spaceID: space, profileID: profile)) == copied, "Collapsed disclosure does not change copied order")
        state.folders[0].isExpanded = true
        state.splitLayouts = [.init(spaceID: space, tabIDs: [folderTab.id, today.id], widthFactors: [0.5, 0.5])]
        expect(FolderLinks.links(in: state, target: .init(folderID: expanded.id, spaceID: space, profileID: profile))?.map(\.tabID) == [nestedTab.id, folderTab.id, today.id], "Folder owns its anchored split as one ordered original-child container")
        state.splitLayouts = []
        expect(items().dropFirst().prefix(3).flatMap(\.tabIDs) == [nestedTab.id, folderTab.id, pinned.id], "Separating a split retains the anchor's established mixed slot")

        func item(_ tab: BrowserTab, spaceID: UUID? = nil) -> RecentTabOrder.Item {
            .init(tabIDs: [tab.id], focusedTabID: tab.id, spaceID: spaceID ?? space, profileID: profile, orientation: .horizontal)
        }
        let a = item(favorite), b = item(pinned), c = item(today), d = item(folderTab)
        var history = TabSelectionHistory()
        expect(history.destination(in: space, forward: false, available: { _ in true }) == nil, "No fabricated initial history")
        [a,b,c].forEach { history.record($0) }
        expect(history.destination(in: space, forward: true, available: { _ in true }) == nil, "History does not wrap forward")
        expect(history.move(in: space, forward: false, available: { _ in true })?.id == b.id, "History goes backward")
        history.record(b)
        expect(history.destination(in: space, forward: true, available: { _ in true })?.id == c.id, "Selection callback does not append duplicate or truncate forward")
        expect(history.move(in: space, forward: false, available: { _ in true })?.id == a.id, "History reaches first")
        expect(history.move(in: space, forward: false, available: { _ in true }) == nil, "History does not wrap backward")
        expect(history.move(in: space, forward: true, available: { $0.id != b.id })?.id == c.id, "Missing/closed item skipped")
        _ = history.move(in: space, forward: false, available: { _ in true })
        history.record(d)
        expect(history.destination(in: space, forward: true, available: { _ in true }) == nil, "New selection truncates forward branch")
        expect(history.move(in: space, forward: false, available: { _ in true })?.id == b.id, "Branch keeps prior entries")
        let otherSpace = UUID(); history.record(item(today, spaceID: otherSpace)); history.record(item(folderTab, spaceID: otherSpace))
        expect(history.destination(in: otherSpace, forward: false, available: { _ in true })?.id == c.id, "Space owns independent stack")
        expect(history.destination(in: space, forward: false, available: { _ in true })?.id == a.id, "Other Space leaves original cursor")
        let rollback = history
        _ = history.move(in: space, forward: false, available: { _ in true })
        history = rollback
        expect(history.destination(in: space, forward: true, available: { _ in true })?.id == d.id, "Refused native selection can restore cursor")
        print("PASS: \(checks) tab-selection assertions")
    }
}
