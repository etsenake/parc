import Foundation

@main @MainActor struct SidebarAnnouncementTests {
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
        let unnamed = BrowserFolder(id: UUID(), spaceID: space.id, name: "", parentID: nil, isExpanded: false)
        func tab(_ name: String, _ kind: TabKind, _ parent: UUID? = nil) -> BrowserTab {
            .init(id: UUID(), spaceID: space.id, profileID: profile, url: "https://example.invalid/" + name,
                title: name, kind: kind, folderID: parent, createdAt: .distantPast, lastAccessed: .distantPast,
                savedURL: "https://example.invalid/" + name, savedTitle: name)
        }
        let favorite = tab("Favorite", .favorite), a = tab("Alpha", .pinned, outer.id), b = tab("Beta", .pinned, outer.id)
        let hidden = tab("Hidden", .pinned, inner.id), left = tab("Left", .today), right = tab("Right", .today)
        var renamed = tab("Original", .today); renamed.customTitle = "Renamed"
        var blank = tab("", .today); blank.url = "about:blank"; blank.savedURL = ""; blank.savedTitle = ""
        let pair = BrowserSplitLayout(sidebarAnchorID: b.id, spaceID: space.id, tabIDs: [a.id, b.id],
            orientation: .vertical, widthFactors: [0.5, 0.5])
        let research = BrowserSplitLayout(sidebarAnchorID: left.id, customTitle: "Research", spaceID: space.id,
            tabIDs: [left.id, right.id], widthFactors: [0.5, 0.5])
        state.tabs = [favorite, a, b, hidden, left, right, renamed, blank]
        state.folders = [outer, inner, unnamed]
        state.splitLayouts = [pair, research]; state.selectedTabIDs = [renamed.id]
        state.selectionBySpace[space.id.uuidString] = [renamed.id]
        state.sidebarItemOrder[SidebarContainerLocation(spaceID: space.id, folderID: nil, section: .pinned).key] = [.folder(outer.id), .folder(unnamed.id)]
        state.sidebarItemOrder[SidebarContainerLocation(spaceID: space.id, folderID: outer.id, section: .pinned).key] = [.folder(inner.id), .split(pair.id)]
        state.sidebarItemOrder[SidebarContainerLocation(spaceID: space.id, folderID: nil, section: .today).key] = [.tab(left.id), .tab(renamed.id), .tab(blank.id)]
        func items(_ current: BrowserState, closed: Set<UUID> = []) -> [SidebarKeyboardNavigation.Item] {
            SidebarKeyboardNavigation.items(state: current, spaceID: space.id, selected: [renamed.id],
                focused: renamed.id, available: { !closed.contains($0) })
        }
        let names = ["Favorite", "Outer, folder, expanded", "Inner, folder, collapsed", "Alpha, Beta, Split View",
                     "Folder, collapsed", "Research, Split View, 2 tabs", "Renamed", "New tab"]
        check(items(state).compactMap { SidebarKeyboardAnnouncement.text($0, state: state) } == names,
              "Every highlightable item speaks the name the sidebar shows, folders with their state and splits with their pages")
        var iconOnly = state; iconOnly.splitLayouts[0].customIcon = .symbol("star")
        check(items(iconOnly).first { $0.reference == .split(pair.id) }.flatMap { SidebarKeyboardAnnouncement.text($0, state: iconOnly) }
              == "Split View, 2 tabs", "A split showing only its icon speaks what its row says, not its page titles")

        let entered = items(state).first { $0.selection?.tabIDs == [renamed.id] }
        var cursor = SidebarKeyboardCursor(highlightedID: entered?.id)
        check(SidebarKeyboardAnnouncement.highlight(cursor, in: items(state), state: state) == "Renamed",
              "Entering the mode speaks the item highlighted at the start")
        check(SidebarKeyboardAnnouncement.highlight(SidebarKeyboardCursor(highlightedID: nil), in: items(state), state: state) == nil
              && SidebarKeyboardAnnouncement.highlight(nil, in: items(state), state: state) == nil,
              "Entering without a highlighted item asks for no announcement")

        var requests: [String] = []
        func press(_ delta: Int, in current: BrowserState, closed: Set<UUID> = []) {
            requests.append(SidebarKeyboardAnnouncement.move(delta, cursor: &cursor, in: items(current, closed: closed), state: current))
        }
        press(1, in: state)
        check(requests == ["New tab"], "Down asks for exactly one announcement, naming the next item")
        press(1, in: state)
        check(requests.last == SidebarKeyboardAnnouncement.endOfList && cursor.highlightedID == nil && requests.count == 2,
              "Stepping past the last item asks for one end-of-list announcement")
        for expected in names {
            let before = requests.count
            press(1, in: state)
            check(requests.count == before + 1 && requests.last == expected, "Down re-enters at the top and walks every item: \(expected)")
        }
        press(1, in: state)
        for expected in names.reversed() {
            let before = requests.count
            press(-1, in: state)
            check(requests.count == before + 1 && requests.last == expected, "Up re-enters at the bottom and walks back: \(expected)")
        }
        press(-1, in: state)
        check(requests.last == SidebarKeyboardAnnouncement.topOfList && cursor.highlightedID == nil,
              "Stepping past the first item asks for one top-of-list announcement")
        check(requests.count == 2 + names.count + 1 + names.count + 1, "Every arrow press asked for exactly one announcement")

        cursor = SidebarKeyboardCursor(highlightedID: items(state).first { $0.reference == .tab(favorite.id) }?.id)
        var refreshed = state
        refreshed.tabs[0].savedTitle = "Favorite, loaded"; refreshed.tabs[0].title = "Favorite, loaded"
        cursor.reconcile(items(refreshed).map(\.id))
        cursor.reconcile(items(refreshed, closed: [right.id]).map(\.id))
        check(cursor.highlightedID == items(state).first?.id,
              "A page finishing loading, a title change or a background tab closing keeps the highlight where the user left it")
        press(1, in: refreshed)
        press(-1, in: refreshed)
        check(requests.suffix(2) == ["Outer, folder, expanded", "Favorite, loaded"],
              "The next arrow press speaks the refreshed title, so nothing was lost by staying quiet")
        cursor = SidebarKeyboardCursor(highlightedID: items(state).first { $0.reference == .tab(blank.id) }?.id)
        var closing = state; closing.tabs.removeAll { $0.id == blank.id }
        cursor.reconcile(items(closing).map(\.id))
        check(cursor.highlightedID == nil, "A highlighted tab closing in the background clears the highlight")
        press(-1, in: closing)
        check(requests.last == "Renamed", "Up after that removal speaks the new last item")

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-sidebar-announcement-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(state).write(to: directory.appendingPathComponent("session.json"))
        let store = try BrowserStore(directory: directory)
        cursor = SidebarKeyboardCursor(highlightedID: items(store.state).first { $0.reference == .folder(inner.id) }?.id)
        guard let folder = items(store.state).first(where: { $0.id == cursor.highlightedID })?.folder else {
            preconditionFailure("The collapsed folder is highlightable")
        }
        let expanded = try store.setFolderExpanded(!folder.isExpanded, expected: folder, profileID: profile)
        check(expanded, "Return opens the folder")
        cursor.reconcile(items(store.state).map(\.id))
        check(SidebarKeyboardAnnouncement.highlight(cursor, in: items(store.state), state: store.state) == "Inner, folder, expanded",
              "After Return opens a folder its new state is spoken")
        guard let opened = items(store.state).first(where: { $0.id == cursor.highlightedID })?.folder else {
            preconditionFailure("The opened folder stays highlighted")
        }
        let collapsed = try store.setFolderExpanded(!opened.isExpanded, expected: opened, profileID: profile)
        check(collapsed, "Return closes the folder")
        check(SidebarKeyboardAnnouncement.highlight(cursor, in: items(store.state), state: store.state) == "Inner, folder, collapsed",
              "After Return closes a folder its new state is spoken")

        var empty = SidebarKeyboardCursor(highlightedID: nil)
        check(SidebarKeyboardAnnouncement.move(1, cursor: &empty, in: [], state: state) == SidebarKeyboardAnnouncement.emptyList
              && SidebarKeyboardAnnouncement.move(-1, cursor: &empty, in: [], state: state) == SidebarKeyboardAnnouncement.emptyList,
              "Arrows in an empty sidebar still answer, once per press")
        let stale = SidebarKeyboardNavigation.Item(reference: .tab(UUID()), selection: nil, folder: nil)
        var lost = SidebarKeyboardCursor(highlightedID: nil)
        check(SidebarKeyboardAnnouncement.move(1, cursor: &lost, in: [stale], state: state) == SidebarKeyboardAnnouncement.unnamedItem,
              "A highlighted row without a readable name never claims the list ended")
        print("PASS: \(count) sidebar-announcement assertions")
    }
}
