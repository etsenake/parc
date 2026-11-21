import Foundation
import Testing
@testable import ParcCore

@MainActor
struct PinnedSectionModelTests {
    let state: BrowserState
    let space: BrowserSpace
    let profile: UUID
    let other: BrowserSpace
    let work: BrowserFolder, inner: BrowserFolder
    let mail: BrowserTab, calendar: BrowserTab, docs: BrowserTab, deep: BrowserTab, left: BrowserTab, right: BrowserTab
    let news: BrowserTab, weather: BrowserTab, elsewhere: BrowserTab
    let split: BrowserSplitLayout
    let root: SidebarContainerLocation

    init() {
        var state = BrowserState.initial()
        space = state.spaces[0]
        profile = space.profileID
        let spaceID = space.id, profileID = profile
        other = BrowserSpace(id: UUID(), name: "Other", symbol: "circle", color: "#808080", profileID: profileID)
        state.spaces.append(other)
        work = BrowserFolder(id: UUID(), spaceID: spaceID, name: "Work", parentID: nil, isExpanded: true)
        inner = BrowserFolder(id: UUID(), spaceID: spaceID, name: "Inner", parentID: work.id, isExpanded: false)
        let otherID = other.id
        func tab(_ name: String, _ kind: TabKind, _ parent: UUID? = nil, in space: UUID? = nil) -> BrowserTab {
            .init(id: UUID(), spaceID: space ?? spaceID, profileID: profileID, url: "https://example.invalid/" + name,
                  title: name, kind: kind, folderID: parent, createdAt: .distantPast, lastAccessed: .distantPast,
                  savedURL: "https://example.invalid/" + name, savedTitle: name)
        }
        mail = tab("Mail", .pinned); calendar = tab("Calendar", .pinned); docs = tab("Docs", .pinned, work.id)
        deep = tab("Deep", .pinned, inner.id); left = tab("Left", .pinned); right = tab("Right", .pinned)
        news = tab("News", .today); weather = tab("Weather", .today); elsewhere = tab("Elsewhere", .today, in: otherID)
        split = BrowserSplitLayout(id: UUID(), sidebarAnchorID: left.id, spaceID: spaceID,
                                   tabIDs: [left.id, right.id], widthFactors: [0.5, 0.5], stacks: nil)
        state.tabs = [mail, calendar, docs, deep, left, right, news, weather, elsewhere]
        state.folders = [work, inner]
        state.splitLayouts = [split]
        root = SidebarContainerLocation(spaceID: spaceID, folderID: nil, section: .pinned)
        state.sidebarItemOrder[root.key] = [.tab(mail.id), .folder(work.id), .split(split.id), .tab(calendar.id)]
        state.sidebarItemOrder[SidebarContainerLocation(spaceID: spaceID, folderID: work.id, section: .pinned).key] = [.folder(inner.id), .tab(docs.id)]
        state.selectedTabIDs = [news.id]
        self.state = state
    }

    func active(_ id: UUID?) -> SidebarItemReference? { PinnedSectionCollapse.activeItem(state: state, spaceID: space.id, tabID: id) }
    func peek(_ id: UUID?) -> [SidebarItemReference] { PinnedSectionCollapse.peek(state: state, spaceID: space.id, active: active(id)) }

    @Test func everySpaceFoldsOnItsOwnAndAnEmptySpaceNeverShowsAsFolded() throws {
        #expect(!PinnedSectionCollapse.isFolded(state: state, spaceID: space.id), "every Pinned section starts open")
        var folded = state
        folded.spaces[0].pinnedCollapsed = true
        #expect(PinnedSectionCollapse.isFolded(state: folded, spaceID: space.id) && !PinnedSectionCollapse.isFolded(state: folded, spaceID: other.id),
              "each Space folds on its own")
        #expect(folded.spaces[0] != state.spaces[0], "folding changes the Space, so every window showing it hears about it")
        folded.spaces[1].pinnedCollapsed = true
        #expect(!PinnedSectionCollapse.isFolded(state: folded, spaceID: other.id), "a Space with nothing pinned never shows as folded")
    }

    @Test func aFoldedSpaceSavesItsFoldAndOlderOrGarbledSpacesLoadOpen() throws {
        var folded = state
        folded.spaces[0].pinnedCollapsed = true
        let encodedSpace = try JSONEncoder().encode(folded.spaces[0])
        let reloadedSpace = try JSONDecoder().decode(BrowserSpace.self, from: encodedSpace)
        #expect(reloadedSpace.pinnedCollapsed, "a folded Space saves its fold")
        let openSpace = try JSONEncoder().encode(state.spaces[0])
        #expect(!String(decoding: openSpace, as: UTF8.self).contains("pinnedCollapsed"), "an open Space writes nothing extra")
        let legacy = try JSONDecoder().decode(BrowserSpace.self, from: openSpace)
        #expect(!legacy.pinnedCollapsed && legacy == state.spaces[0], "older Spaces load with Pinned open")
        var garbledObject = try JSONSerialization.jsonObject(with: encodedSpace) as! [String: Any]
        garbledObject["pinnedCollapsed"] = "nope"
        let garbled = try JSONDecoder().decode(BrowserSpace.self, from: try JSONSerialization.data(withJSONObject: garbledObject))
        #expect(!garbled.pinnedCollapsed && garbled.id == space.id && garbled.profileID == profile, "an unreadable fold leaves the Space intact")
    }

    @Test func theStoreFoldsAndUnfoldsDurablyAndTidiesFoldsLeftOnEmptiedSpaces() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-pinned-section-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(state).write(to: directory.appendingPathComponent("session.json"))
        let store = try BrowserStore(directory: directory)
        let before = store.state
        let committed = try store.setPinnedSectionCollapsed(true, spaceID: space.id)
        #expect(committed && PinnedSectionCollapse.isFolded(state: store.state, spaceID: space.id), "folding commits to the Space")
        #expect(store.state.tabs == before.tabs && store.state.folders == before.folders && store.state.selectedTabIDs == before.selectedTabIDs,
              "folding touches nothing but the fold")
        let relaunched = try BrowserStore(directory: directory)
        #expect(PinnedSectionCollapse.isFolded(state: relaunched.state, spaceID: space.id), "the fold survives relaunch")
        let unchanged = store.state
        let again = try store.setPinnedSectionCollapsed(true, spaceID: space.id)
        #expect(again && store.state == unchanged, "folding twice is harmless")
        let empty = try store.setPinnedSectionCollapsed(true, spaceID: other.id)
        #expect(!empty && !store.state.spaces[1].pinnedCollapsed, "an empty Pinned can't be folded")
        let unknown = try store.setPinnedSectionCollapsed(true, spaceID: UUID())
        #expect(!unknown, "an unknown Space is refused")
        #expect(!PinnedSectionCollapse.isEmpty(state: state, spaceID: space.id) && !PinnedSectionCollapse.isEmpty(state: state, spaceID: other.id)
              && PinnedSectionCollapse.isEmpty(state: { var bare = state; bare.tabs = []; bare.folders = []; bare.splitLayouts = []; return bare }(), spaceID: other.id),
              "a Space is empty only with nothing pinned and nothing in Today")
        var emptied = store.state
        emptied.tabs.removeAll { $0.spaceID == space.id && $0.kind == .pinned }
        emptied.folders.removeAll { $0.spaceID == space.id }
        emptied.splitLayouts = []
        #expect(!PinnedSectionCollapse.isFolded(state: emptied, spaceID: space.id) && emptied.spaces[0].pinnedCollapsed,
              "a folded Space that empties shows no fold even before its flag is tidied away")
        let opened = try store.setPinnedSectionCollapsed(false, spaceID: space.id)
        var stale = state
        stale.spaces[0].pinnedCollapsed = true
        stale.tabs.removeAll { $0.spaceID == space.id && $0.kind == .pinned }
        stale.folders = []; stale.splitLayouts = []
        let staleDirectory = directory.appendingPathComponent("stale")
        try FileManager.default.createDirectory(at: staleDirectory, withIntermediateDirectories: true)
        try encoder.encode(stale).write(to: staleDirectory.appendingPathComponent("session.json"))
        let staleStore = try BrowserStore(directory: staleDirectory)
        #expect(staleStore.state.spaces[0].pinnedCollapsed, "a fold left on an emptied Space loads as saved")
        staleStore.clearEmptyPinnedFolds()
        #expect(!staleStore.state.spaces[0].pinnedCollapsed, "tidying clears the fold of a Space with nothing pinned")
        let staleReloaded = try BrowserStore(directory: staleDirectory)
        #expect(!staleReloaded.state.spaces[0].pinnedCollapsed, "the tidied fold stays cleared after relaunch")
        let foldedStore = try BrowserStore(directory: directory)
        let foldedBefore = foldedStore.state
        foldedStore.clearEmptyPinnedFolds()
        #expect(foldedStore.state == foldedBefore, "tidying leaves Spaces that still have pinned items alone")
        let reopened = try BrowserStore(directory: directory)
        #expect(opened && !PinnedSectionCollapse.isFolded(state: reopened.state, spaceID: space.id), "unfolding is saved too")
    }

    @Test func onlyThePinnedItemHoldingTheActiveTabPeeksOutOfAFoldedSection() throws {
        #expect(peek(news.id).isEmpty, "a Today tab never peeks out of Pinned")
        #expect(peek(nil).isEmpty, "no active tab, nothing peeks")
        #expect(peek(mail.id) == [.tab(mail.id)], "a top-level pinned tab peeks by itself")
        #expect(peek(right.id) == [.split(split.id)], "a pinned split peeks as its whole row")
        #expect(peek(docs.id) == [.folder(work.id), .tab(docs.id)], "a tab in a pinned folder peeks with its folder")
        #expect(peek(deep.id) == [.folder(work.id), .folder(inner.id), .tab(deep.id)], "nested folders peek as a path")
        #expect(peek(elsewhere.id).isEmpty, "another Space's tab never peeks here")
    }

    @Test func theFoldedSummaryCountsEveryPinnedTabAndShowsAtMostFourIcons() throws {
        let summary = PinnedSectionCollapse.summary(state: state, spaceID: space.id)
        #expect(summary.count == 6, "the count covers every pinned tab, inside folders and splits too")
        #expect(summary.tabs.map(\.id) == [mail.id, deep.id, docs.id, left.id], "icons follow sidebar order into folders")
        #expect(summary.tabs.count == PinnedSectionCollapse.Summary.shownIcons && summary.hidden == 2,
              "the stack shows at most four icons and counts the rest")
        #expect(PinnedSectionCollapse.summary(state: state, spaceID: other.id) == .init(tabs: [], count: 0), "an empty Pinned summarises to nothing")
        var archived = state
        archived.tabs[0].archivedAt = .distantPast
        #expect(PinnedSectionCollapse.summary(state: archived, spaceID: space.id).count == 5, "archived tabs are not counted")
    }

    @Test func aDropOnTheFoldedHeaderLandsAtTheTopOfPinned() throws {
        let drop = PinnedSectionCollapse.headerDrop(state: state, spaceID: space.id, moving: [.tab(news.id)])
        #expect(drop.destination == root && drop.before == .tab(mail.id), "a drop on the header lands at the top of Pinned")
        #expect(PinnedSectionCollapse.headerDrop(state: state, spaceID: space.id, moving: [.tab(mail.id)]).before == .folder(work.id),
              "moving the first pinned item onto the header keeps it first")
        let snapshot = SidebarHierarchySnapshot(state: state, spaceID: space.id, profileID: profile)!
        let moved = SidebarHierarchy.moving([.tab(news.id)], to: drop.destination, before: drop.before, expected: snapshot, state: state)!
        #expect(SidebarHierarchy.children(in: root, state: moved).first == .tab(news.id), "the dropped Today tab becomes the first pinned item")
        #expect(PinnedSectionCollapse.summary(state: moved, spaceID: space.id).count == 7, "the folded count grows with the drop")
        #expect(PinnedSectionCollapse.summary(state: moved, spaceID: space.id).tabs.first?.id == news.id, "the dropped tab leads the icon stack")
        var activeMoved = moved; activeMoved.selectedTabIDs = [news.id]
        #expect(PinnedSectionCollapse.peek(state: activeMoved, spaceID: space.id,
                                          active: PinnedSectionCollapse.activeItem(state: activeMoved, spaceID: space.id, tabID: news.id)) == [.tab(news.id)],
              "dropping the active tab onto a folded Pinned keeps it peeking")
        let emptyDrop = PinnedSectionCollapse.headerDrop(state: state, spaceID: other.id, moving: [.tab(elsewhere.id)])
        #expect(emptyDrop.before == nil, "a drop into an empty Pinned appends")
    }

    @Test func keyboardNavigationFollowsTheFoldAndItsPeeks() throws {
        func keyboard(_ pinnedPeek: [SidebarItemReference]?) -> [SidebarItemReference] {
            SidebarKeyboardNavigation.items(state: state, spaceID: space.id, selected: state.selectedTabIDs, focused: state.selectedTabIDs.first,
                                            pinnedPeek: pinnedPeek, available: { _ in true }).map(\.reference)
        }
        #expect(keyboard(nil) == [.tab(mail.id), .folder(work.id), .folder(inner.id), .tab(docs.id), .split(split.id), .tab(calendar.id),
                                .tab(news.id), .tab(weather.id)], "expanded Pinned keeps the full keyboard order")
        #expect(keyboard([]) == [.tab(news.id), .tab(weather.id)], "folded Pinned leaves only Today for the arrow keys")
        #expect(keyboard(peek(docs.id)) == [.folder(work.id), .tab(docs.id), .tab(news.id), .tab(weather.id)],
              "the peeking tab and its folder stay reachable from the keyboard")
        #expect(keyboard(peek(deep.id)) == [.folder(work.id), .folder(inner.id), .tab(deep.id), .tab(news.id), .tab(weather.id)],
              "a peek through a closed folder stays reachable")
        let folderPeek = SidebarKeyboardNavigation.items(state: state, spaceID: space.id, selected: state.selectedTabIDs,
                                                         focused: state.selectedTabIDs.first, peeks: [inner.id: [.tab(deep.id)]],
                                                         available: { _ in true }).map(\.reference)
        #expect(folderPeek.contains(.tab(deep.id)), "a tab peeking out of a closed folder is reachable from the keyboard too")
        let positional = PositionalTabNavigation.items(state: state, spaceID: space.id, selected: state.selectedTabIDs,
                                                       focused: news.id, available: { _ in true })
        #expect(positional.first?.tabIDs == [mail.id], "number shortcuts keep counting pinned tabs whatever the window shows")
    }

    @Test func theCommandBarFindsThePinnedCommandsWithTheirGlyphs() throws {
        #expect(CommandBarMenuItemInfo.searchText(forMenuCommand: "togglePinnedSection:").contains("Pinned"),
              "the command bar finds the Pinned toggle")
        #expect(!CommandBarMenuItemInfo.searchText(forMenuCommand: "togglePinnedSection:").lowercased().contains("expand")
              && !CommandBarMenuItemInfo.searchText(forMenuCommand: "togglePinnedSection:").lowercased().contains("collapse"),
              "the toggle's opposite phrase comes only from its live title")
        #expect(CommandBarMenuItemInfo.searchText(forMenuCommand: "toggleCollapsedPinnedIcons:").contains("Pinned Icons"),
              "the command bar finds the icon toggle")
        #expect(CommandBarCommandPresentation.symbol(forCommandID: "togglePinnedSection:") == "pin"
              && CommandBarCommandPresentation.symbol(forCommandID: "toggleCollapsedPinnedIcons:") == "eye.slash",
              "both commands carry their own glyphs")

    }
}
