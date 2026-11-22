import Foundation
import Testing
@testable import ParcCore

struct BrowserStoreSplitSavedHomeTests {
    @Test @MainActor static func todaySplitsUseTheirFirstPanesAsSidebarAnchors() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory, now: { Date(timeIntervalSince1970: 1_800_000_000) })
            let todayBox = SidebarContainerLocation(spaceID: store.activeSpaceID, folderID: nil, section: .today)
            @MainActor func today() -> [SidebarItemReference] { SidebarHierarchy.children(in: todayBox, state: store.state) }
            let bottom = store.open("https://bottom.example")
            let f = store.open("https://f.example"), e = store.open("https://e.example"), d = store.open("https://d.example")
            let middle = store.open("https://middle.example")
            let c = store.open("https://c.example"), b = store.open("https://b.example"), a = store.open("https://a.example")
            let top = store.open("https://top.example")
            store.selectTab(a); store.selectTab(b, extendingSplit: true); store.selectTab(c, extendingSplit: true)
            let trio = store.activeSplitLayout!
            store.selectTab(d); store.selectTab(e, extendingSplit: true); store.selectTab(f, extendingSplit: true)
            let shown = store.activeSplitLayout!
            #expect(trio.sidebarAnchorID == a && shown.sidebarAnchorID == d
                       && today() == [.tab(top), .split(trio.id), .tab(middle), .split(shown.id), .tab(bottom)], "Two three-pane splits sit between tabs, each filed under its first pane")
        }
    }

    @Test @MainActor static func closingAnInactiveSplitsAnchorKeepsItsSidebarSlot() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory, now: { Date(timeIntervalSince1970: 1_800_000_000) })
            let todayBox = SidebarContainerLocation(spaceID: store.activeSpaceID, folderID: nil, section: .today)
            @MainActor func today() -> [SidebarItemReference] { SidebarHierarchy.children(in: todayBox, state: store.state) }
            let bottom = store.open("https://bottom.example")
            let f = store.open("https://f.example"), e = store.open("https://e.example"), d = store.open("https://d.example")
            let middle = store.open("https://middle.example")
            let c = store.open("https://c.example"), b = store.open("https://b.example"), a = store.open("https://a.example")
            let top = store.open("https://top.example")
            store.selectTab(a); store.selectTab(b, extendingSplit: true); store.selectTab(c, extendingSplit: true)
            let trio = store.activeSplitLayout!
            store.selectTab(d); store.selectTab(e, extendingSplit: true); store.selectTab(f, extendingSplit: true)
            let shown = store.activeSplitLayout!

            store.closeTab(a)
            let kept = store.state.splitLayouts.first { $0.id == trio.id }
            #expect(kept?.tabIDs == [b, c] && kept?.sidebarAnchorID == b, "The next pane takes over a split that isn't shown")
            #expect(today() == [.tab(top), .split(trio.id), .tab(middle), .split(shown.id), .tab(bottom)], "Closing the anchor pane of a split that isn't shown keeps the split in its slot")
        }
    }

    @Test @MainActor static func dissolvingAnInactiveSplitLeavesTheSurvivorInItsSlot() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory, now: { Date(timeIntervalSince1970: 1_800_000_000) })
            let todayBox = SidebarContainerLocation(spaceID: store.activeSpaceID, folderID: nil, section: .today)
            @MainActor func today() -> [SidebarItemReference] { SidebarHierarchy.children(in: todayBox, state: store.state) }
            let bottom = store.open("https://bottom.example")
            let f = store.open("https://f.example"), e = store.open("https://e.example"), d = store.open("https://d.example")
            let middle = store.open("https://middle.example")
            let c = store.open("https://c.example"), b = store.open("https://b.example"), a = store.open("https://a.example")
            let top = store.open("https://top.example")
            store.selectTab(a); store.selectTab(b, extendingSplit: true); store.selectTab(c, extendingSplit: true)
            let trio = store.activeSplitLayout!
            store.selectTab(d); store.selectTab(e, extendingSplit: true); store.selectTab(f, extendingSplit: true)
            let shown = store.activeSplitLayout!

            store.closeTab(a)
            let kept = store.state.splitLayouts.first { $0.id == trio.id }
            try #require(kept?.tabIDs == [b, c] && kept?.sidebarAnchorID == b, "The next pane takes over a split that isn't shown")
            try #require(today() == [.tab(top), .split(trio.id), .tab(middle), .split(shown.id), .tab(bottom)], "Closing the anchor pane of a split that isn't shown keeps the split in its slot")
            store.closeTab(b)
            #expect(!store.state.splitLayouts.contains { $0.id == trio.id }
                       && today() == [.tab(top), .tab(c), .tab(middle), .split(shown.id), .tab(bottom)], "Dissolving a split that isn't shown leaves its last pane in the split's slot")
        }
    }

    @Test @MainActor static func closingTheActiveSplitsAnchorKeepsItSelectedInItsSlot() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory, now: { Date(timeIntervalSince1970: 1_800_000_000) })
            let todayBox = SidebarContainerLocation(spaceID: store.activeSpaceID, folderID: nil, section: .today)
            @MainActor func today() -> [SidebarItemReference] { SidebarHierarchy.children(in: todayBox, state: store.state) }
            let bottom = store.open("https://bottom.example")
            let f = store.open("https://f.example"), e = store.open("https://e.example"), d = store.open("https://d.example")
            let middle = store.open("https://middle.example")
            let c = store.open("https://c.example"), b = store.open("https://b.example"), a = store.open("https://a.example")
            let top = store.open("https://top.example")
            store.selectTab(a); store.selectTab(b, extendingSplit: true); store.selectTab(c, extendingSplit: true)
            let trio = store.activeSplitLayout!
            store.selectTab(d); store.selectTab(e, extendingSplit: true); store.selectTab(f, extendingSplit: true)
            let shown = store.activeSplitLayout!

            store.closeTab(a)
            let kept = store.state.splitLayouts.first { $0.id == trio.id }
            try #require(kept?.tabIDs == [b, c] && kept?.sidebarAnchorID == b, "The next pane takes over a split that isn't shown")
            try #require(today() == [.tab(top), .split(trio.id), .tab(middle), .split(shown.id), .tab(bottom)], "Closing the anchor pane of a split that isn't shown keeps the split in its slot")
            store.closeTab(b)
            try #require(!store.state.splitLayouts.contains { $0.id == trio.id }
                       && today() == [.tab(top), .tab(c), .tab(middle), .split(shown.id), .tab(bottom)], "Dissolving a split that isn't shown leaves its last pane in the split's slot")

            store.closeTab(d)
            let displayed = store.state.splitLayouts.first { $0.id == shown.id }
            #expect(displayed?.tabIDs == [e, f] && displayed?.sidebarAnchorID == e && store.state.selectedTabIDs == [e, f], "The shown split loses its anchor pane and stays shown")
            #expect(today() == [.tab(top), .tab(c), .tab(middle), .split(shown.id), .tab(bottom)], "Closing the anchor pane of the shown split keeps the split in its slot")
        }
    }

    @Test @MainActor static func newTodayTabsEnterAtTheTopOfTheSidebar() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory, now: { Date(timeIntervalSince1970: 1_800_000_000) })
            let space = store.activeSpaceID
            let todayBox = SidebarContainerLocation(spaceID: space, folderID: nil, section: .today)
            @MainActor func today() -> [SidebarItemReference] { SidebarHierarchy.children(in: todayBox, state: store.state) }
            let t1 = store.open("https://t1.example"), t2 = store.open("https://t2.example")
            #expect(today() == [.tab(t2), .tab(t1)], "Created Today tabs enter at the top")
        }
    }

    @Test @MainActor static func aPinnedPageJoiningATodaySplitKeepsAFreshHomeInItsFolder() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory, now: { Date(timeIntervalSince1970: 1_800_000_000) })
            let space = store.activeSpaceID
            let todayBox = SidebarContainerLocation(spaceID: space, folderID: nil, section: .today)
            @MainActor func today() -> [SidebarItemReference] { SidebarHierarchy.children(in: todayBox, state: store.state) }
            let folder = store.createFolder(name: "Saved")
            let folderBox = SidebarContainerLocation(spaceID: space, folderID: folder, section: .pinned)
            let pinned = store.open("https://pin.example", kind: .pinned)
            store.moveTab(pinned, toSpace: space, folderID: folder)
            let t1 = store.open("https://t1.example"), t2 = store.open("https://t2.example")
            store.selectTab(pinned); store.selectTab(t1, extendingSplit: true)
            let group = store.activeSplitLayout!
            let pinnedHome = try BrowserStoreTestsSupport.expectHome(of: pinned, in: store, savedURL: "https://pin.example")
            #expect(group.tabIDs == [pinned, t1] && group.sidebarAnchorID == t1, "New split anchors at its first ordinary member")
            #expect(today() == [.tab(t2), .split(group.id)], "The new split takes the ordinary member's Today slot")
            #expect(SidebarHierarchy.children(in: folderBox, state: store.state) == [.tab(pinnedHome.id)]
                       && pinnedHome.folderID == folder, "The pinned slot keeps a fresh home in its folder")
            #expect(try BrowserStoreTestsSupport.tab(pinned, in: store).kind == .today && (try BrowserStoreTestsSupport.tab(pinned, in: store)).folderID == nil, "The pinned original enters the Today container with its split")
        }
    }

    @Test @MainActor static func aFavoriteJoiningATodaySplitKeepsItsOriginalTraySlot() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory, now: { Date(timeIntervalSince1970: 1_800_000_000) })
            let space = store.activeSpaceID, profile = store.activeSpace.profileID
            let todayBox = SidebarContainerLocation(spaceID: space, folderID: nil, section: .today)
            let tray = SidebarContainerLocation(spaceID: space, folderID: nil, section: .favorite, profileID: profile)
            @MainActor func today() -> [SidebarItemReference] { SidebarHierarchy.children(in: todayBox, state: store.state) }
            @MainActor func trayItems() -> [SidebarItemReference] { SidebarHierarchy.children(in: tray, state: store.state) }
            let favorite = store.open("https://fav.example", kind: .favorite)
            let pinned = store.open("https://pin.example")
            let t1 = store.open("https://t1.example"), t2 = store.open("https://t2.example")
            store.selectTab(pinned); store.selectTab(t1, extendingSplit: true)
            store.selectTab(favorite, extendingSplit: true)
            let group = store.activeSplitLayout!
            let favoriteHome = try BrowserStoreTestsSupport.expectHome(of: favorite, in: store, savedURL: "https://fav.example")
            #expect(group.tabIDs == [pinned, t1, favorite] && trayItems() == [.tab(favoriteHome.id)], "A Favorite added to a Today split leaves its tray home")
            #expect(try BrowserStoreTestsSupport.tab(favorite, in: store).kind == .today && today() == [.tab(t2), .split(group.id)], "The Favorite original joins the existing Today container; the split keeps its slot")
        }
    }

    @Test @MainActor static func separatingTheAnchorLeavesTheSplitInItsOriginalSlot() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory, now: { Date(timeIntervalSince1970: 1_800_000_000) })
            let space = store.activeSpaceID
            let todayBox = SidebarContainerLocation(spaceID: space, folderID: nil, section: .today)
            @MainActor func today() -> [SidebarItemReference] { SidebarHierarchy.children(in: todayBox, state: store.state) }
            let pinned = store.open("https://pin.example", kind: .pinned)
            let favorite = store.open("https://fav.example", kind: .favorite)
            let t1 = store.open("https://t1.example"), t2 = store.open("https://t2.example")
            store.selectTab(pinned)
            store.selectTab(t1, extendingSplit: true)
            store.selectTab(favorite, extendingSplit: true)
            var group = try #require(store.activeSplitLayout)
            #expect(store.separateTabFromSplit(t1, expected: group, focusedID: pinned), "Separate the anchor")
            group = store.state.splitLayouts.first { $0.id == group.id }!
            #expect(group.sidebarAnchorID == pinned && today() == [.tab(t2), .split(group.id), .tab(t1)], "A departing anchor keeps the split's slot; the child follows the split")
        }
    }

    @Test @MainActor static func dissolvingASplitPlacesItsChildrenInPaneOrder() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory, now: { Date(timeIntervalSince1970: 1_800_000_000) })
            let space = store.activeSpaceID
            let todayBox = SidebarContainerLocation(spaceID: space, folderID: nil, section: .today)
            @MainActor func today() -> [SidebarItemReference] { SidebarHierarchy.children(in: todayBox, state: store.state) }
            let pinned = store.open("https://pin.example", kind: .pinned)
            let favorite = store.open("https://fav.example", kind: .favorite)
            let t1 = store.open("https://t1.example"), t2 = store.open("https://t2.example")
            store.selectTab(pinned)
            store.selectTab(t1, extendingSplit: true)
            store.selectTab(favorite, extendingSplit: true)
            var group = try #require(store.activeSplitLayout)
            try #require(store.separateTabFromSplit(t1, expected: group, focusedID: pinned), "Separate the anchor")
            group = store.state.splitLayouts.first { $0.id == group.id }!
            try #require(group.sidebarAnchorID == pinned && today() == [.tab(t2), .split(group.id), .tab(t1)], "A departing anchor keeps the split's slot; the child follows the split")
            #expect(store.separateTabFromSplit(favorite, expected: group, focusedID: pinned), "Separate to dissolve")
            #expect(store.activeSplitLayout == nil && today() == [.tab(t2), .tab(pinned), .tab(favorite), .tab(t1)], "Dissolving puts every child at the split's slot in child order")
        }
    }

    @Test @MainActor static func splittingTwoFavoritesLeavesBothSavedHomesInTheTray() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory, now: { Date(timeIntervalSince1970: 1_800_000_000) })
            let space = store.activeSpaceID, profile = store.activeSpace.profileID
            let todayBox = SidebarContainerLocation(spaceID: space, folderID: nil, section: .today)
            let tray = SidebarContainerLocation(spaceID: space, folderID: nil, section: .favorite, profileID: profile)
            @MainActor func today() -> [SidebarItemReference] { SidebarHierarchy.children(in: todayBox, state: store.state) }
            @MainActor func trayItems() -> [SidebarItemReference] { SidebarHierarchy.children(in: tray, state: store.state) }
            let g1 = store.open("https://g1.example", kind: .favorite), g2 = store.open("https://g2.example", kind: .favorite)
            store.selectTab(g1); store.selectTab(g2, extendingSplit: true)
            let saved = store.activeSplitLayout!
            let g1Home = try BrowserStoreTestsSupport.expectHome(of: g1, in: store, savedURL: "https://g1.example")
            let g2Home = try BrowserStoreTestsSupport.expectHome(of: g2, in: store, savedURL: "https://g2.example")
            #expect(today().first == .split(saved.id) && trayItems() == [.tab(g1Home.id), .tab(g2Home.id)], "Two Favorites form a Today split at the top while the tray keeps both homes")
        }
    }

    @Test @MainActor static func closingOneOfTwoFavoriteOriginalsLeavesTheSurvivorInTheSplitSlot() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory, now: { Date(timeIntervalSince1970: 1_800_000_000) })
            let space = store.activeSpaceID, profile = store.activeSpace.profileID
            let todayBox = SidebarContainerLocation(spaceID: space, folderID: nil, section: .today)
            let tray = SidebarContainerLocation(spaceID: space, folderID: nil, section: .favorite, profileID: profile)
            @MainActor func today() -> [SidebarItemReference] { SidebarHierarchy.children(in: todayBox, state: store.state) }
            @MainActor func trayItems() -> [SidebarItemReference] { SidebarHierarchy.children(in: tray, state: store.state) }
            let g1 = store.open("https://g1.example", kind: .favorite), g2 = store.open("https://g2.example", kind: .favorite)
            store.selectTab(g1); store.selectTab(g2, extendingSplit: true)
            let saved = store.activeSplitLayout!
            let g1Home = try BrowserStoreTestsSupport.expectHome(of: g1, in: store, savedURL: "https://g1.example")
            let g2Home = try BrowserStoreTestsSupport.expectHome(of: g2, in: store, savedURL: "https://g2.example")
            try #require(today().first == .split(saved.id) && trayItems() == [.tab(g1Home.id), .tab(g2Home.id)], "Two Favorites form a Today split at the top while the tray keeps both homes")
            store.closeTab(g1)
            #expect(today().first == .tab(g2) && store.activeSplitLayout == nil, "Closing a pane dissolves the split into its slot with the survivor")
        }
    }

    @Test @MainActor static func aTodayPageJoiningAFavoriteSplitIsNotASeparateTrayItem() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory, now: { Date(timeIntervalSince1970: 1_800_000_000) })
            let space = store.activeSpaceID, profile = store.activeSpace.profileID
            let tray = SidebarContainerLocation(spaceID: space, folderID: nil, section: .favorite, profileID: profile)
            @MainActor func trayItems() -> [SidebarItemReference] { SidebarHierarchy.children(in: tray, state: store.state) }
            let u1 = store.open("https://u1.example"), u2 = store.open("https://u2.example")
            let favoriteSplit = try BrowserStoreTestsSupport.savedSplit(store, [u1, u2], in: tray)
            store.selectTab(u1)
            let t3 = store.open("https://t3.example")
            store.selectTab(u1); store.selectTab(t3, extendingSplit: true)
            #expect(try store.activeSplitLayout?.id == favoriteSplit.id && store.activeSplitLayout?.tabIDs == [u1, u2, t3]
                       && (try BrowserStoreTestsSupport.tab(t3, in: store)).kind == .favorite, "A Today page added to a Favorite split joins topApps")
            #expect(!trayItems().contains(.tab(t3)) && trayItems().filter { $0 == .split(favoriteSplit.id) }.count == 1, "The Favorite split stays one tray item")
        }
    }

    @Test @MainActor static func pinnedCommandBarResultsKeepTheirHomesWhenJoiningAFavoriteSplit() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory, now: { Date(timeIntervalSince1970: 1_800_000_000) })
            let space = store.activeSpaceID, profile = store.activeSpace.profileID
            let tray = SidebarContainerLocation(spaceID: space, folderID: nil, section: .favorite, profileID: profile)
            let u1 = store.open("https://u1.example"), u2 = store.open("https://u2.example")
            _ = try BrowserStoreTestsSupport.savedSplit(store, [u1, u2], in: tray)
            store.selectTab(u1)
            let t3 = store.open("https://t3.example")
            store.selectTab(u1); store.selectTab(t3, extendingSplit: true)
            let q = store.open("https://q.example", kind: .pinned)
            store.selectTab(u1)
            let current = store.state.selectedTabIDs
            #expect(store.insertCommandBarSplit(after: t3, expectedSelection: current, tabID: q), "A pinned command-bar result joins the Favorite split")
            let qHome = try BrowserStoreTestsSupport.expectHome(of: q, in: store, savedURL: "https://q.example")
            #expect(try qHome.kind == .pinned && (try BrowserStoreTestsSupport.tab(q, in: store)).kind == .favorite && store.state.selectedTabIDs == current + [q], "The pinned result leaves its home and its original enters topApps")
            let secondSpace = store.createSpace(name: "Second")
            store.selectTab(u1)
            #expect(store.activeSpaceID == secondSpace && store.state.selectedTabIDs == current + [q], "The Favorite split with its new members appears in every Space")
        }
    }

    @Test @MainActor static func separatingAFavoritePaneKeepsItNextToTheSplitInTheTray() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory, now: { Date(timeIntervalSince1970: 1_800_000_000) })
            let space = store.activeSpaceID, profile = store.activeSpace.profileID
            let tray = SidebarContainerLocation(spaceID: space, folderID: nil, section: .favorite, profileID: profile)
            let u1 = store.open("https://u1.example"), u2 = store.open("https://u2.example")
            _ = try BrowserStoreTestsSupport.savedSplit(store, [u1, u2], in: tray)
            store.selectTab(u1)
            let t3 = store.open("https://t3.example")
            store.selectTab(u1); store.selectTab(t3, extendingSplit: true)
            let q = store.open("https://q.example", kind: .pinned)
            store.selectTab(u1)
            let current = store.state.selectedTabIDs
            try #require(store.insertCommandBarSplit(after: t3, expectedSelection: current, tabID: q), "A pinned command-bar result joins the Favorite split")
            let secondSpace = store.createSpace(name: "Second")
            store.selectTab(u1)
            let favoriteGroup = store.activeSplitLayout!
            #expect(store.separateTabFromSplit(q, expected: favoriteGroup, focusedID: u1), "Separate from a Favorite split")
            let trayNow = SidebarHierarchy.children(in: .init(spaceID: secondSpace, folderID: nil, section: .favorite, profileID: profile), state: store.state)
            #expect(try trayNow.firstIndex(of: .split(favoriteGroup.id)).map { $0 + 1 } == trayNow.firstIndex(of: .tab(q))
                       && (try BrowserStoreTestsSupport.tab(q, in: store)).kind == .favorite, "The separated child is a Favorite right after the split tile")
        }
    }
}
