import Combine
import Foundation
import Testing
@testable import ParcCore

extension BrowserStoreTests {
    @Test static func splitLayoutValidation() throws {
        try withDirectory { directory in
            let store = try BrowserStore(directory: directory, now: { Date(timeIntervalSince1970: 1_800_000_000) })
            let first = store.open("https://one.example")
            let second = store.open("https://two.example")
            #expect(!store.setSplitLayout(orientation: .vertical, widthFactors: [1, 1]), "A single selected tab must not accept split geometry")
            store.setSplit([first, second])
            #expect(store.setSplitLayout(orientation: .vertical, widthFactors: [2, 6]), "A valid layout must accept positive relative weights")
            try expectFactors(store.activeSplitLayout?.widthFactors, [0.25, 0.75], "Weights must normalize to a unit sum")
            let expected = store.state
            for weights in [[Double](), [1], [1, 1, 1], [0, 1], [-1, 2], [.nan, 1], [.infinity, 1], [Double.leastNonzeroMagnitude, Double.greatestFiniteMagnitude]] {
                #expect(!store.setSplitLayout(orientation: .horizontal, widthFactors: weights), "Invalid, mismatched or unrepresentable weights must be rejected")
                #expect(store.state == expected, "Rejected geometry must not mutate selection or persisted layouts")
            }
            #expect(store.setSplitLayout(orientation: .horizontal,
                widthFactors: [Double.greatestFiniteMagnitude, Double.greatestFiniteMagnitude]), "Normalization must not overflow when large valid weights have a non-finite raw sum")
            try expectFactors(store.activeSplitLayout?.widthFactors, [0.5, 0.5], "Large equal weights must remain equal")
            store.selectTab(first)
            #expect(store.state.selectedTabIDs == [first, second], "Selecting a typed child retains the whole split")
            store.closeSplit()
            #expect(store.activeSplitLayout == nil, "A dissolved split leaves one normal page")
        }
    }

    @Test static func savedSplitLayoutsAcrossSpacesAndRestart() throws {
        try withDirectory { directory in
            let store = try BrowserStore(directory: directory, now: { Date(timeIntervalSince1970: 1_800_000_000) })
            let firstSpace = store.activeSpaceID
            let profile = store.activeSpace.profileID
            let first = store.open("https://one.example")
            let second = store.open("https://two.example")
            let third = store.open("https://three.example")
            let fourth = store.open("https://four.example")
            store.setSplit([first, second])
            store.setSplitLayout(orientation: .vertical, widthFactors: [1, 3])
            let original = store.activeSplitLayout
            store.selectTab(third)
            store.setSplit([third, fourth])
            store.setSplitLayout(orientation: .horizontal, widthFactors: [3, 2])
            store.setSplit([first, second])
            #expect(store.activeSplitLayout == original, "Revisiting an ordered pane group must restore its own geometry")
            store.updateTab(first, title: "Changed page", url: "https://one.example/next")
            #expect(store.activeSplitLayout == original, "Navigation and title updates must not drift divider proportions")
            let tray = SidebarContainerLocation(spaceID: firstSpace, folderID: nil, section: .favorite, profileID: profile)
            let snapshot = SidebarHierarchySnapshot(state: store.state, spaceID: firstSpace, profileID: profile, includesFavorites: true)!
            #expect(try store.moveSidebarItem(.split(original!.id), to: tray, before: nil, expected: snapshot), "A whole split moves into Favorites")
            #expect(try tab(first, in: store).kind == .favorite && tab(second, in: store).kind == .favorite, "Every child enters the Favorites container with its split")
            let secondSpace = store.createSpace(name: "Second")
            store.selectTab(first)
            #expect(store.activeSplitLayout?.id == original?.id && store.state.selectedTabIDs == [first, second], "Another Space of the Profile shows the same Favorite split")
            store.setSplitLayout(orientation: .horizontal, widthFactors: [4, 1])
            let other = store.activeSplitLayout
            #expect(other?.id == original?.id, "Resizing from another Space edits the one Favorite split")
            store.selectSpace(firstSpace)
            #expect(store.activeSplitLayout == other, "A Favorite split has one Profile-wide layout in every Space")
            #expect(store.state.splitLayouts.filter { $0.tabIDs.contains(first) }.count == 1, "The same Favorites form one split, not one per Space")
            try store.save()
            let reopened = try BrowserStore(directory: directory, now: { Date(timeIntervalSince1970: 1_800_000_000) })
            #expect(reopened.state == store.state, "All stored split layouts and selected panes must survive a restart")
            reopened.selectSpace(secondSpace)
            #expect(reopened.activeSplitLayout == other, "Restoring another Space shows the Favorite split's one layout")
            reopened.selectSpace(firstSpace)
            reopened.setSplit([third, fourth])
            try expectFactors(reopened.activeSplitLayout?.widthFactors, [0.6, 0.4], "A second saved group in one Space must survive restart")
            #expect(reopened.activeSplitLayout?.orientation == .horizontal, "Orientation belongs to the split, not the most recently displayed Space")
        }
    }

    @Test static func closingSplitAnchorKeepsSlot() throws {
        try withDirectory { directory in
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

            store.closeTab(a)
            let kept = store.state.splitLayouts.first { $0.id == trio.id }
            #expect(kept?.tabIDs == [b, c] && kept?.sidebarAnchorID == b, "The next pane takes over a split that isn't shown")
            #expect(today() == [.tab(top), .split(trio.id), .tab(middle), .split(shown.id), .tab(bottom)], "Closing the anchor pane of a split that isn't shown keeps the split in its slot")
            store.closeTab(b)
            #expect(!store.state.splitLayouts.contains { $0.id == trio.id }
                       && today() == [.tab(top), .tab(c), .tab(middle), .split(shown.id), .tab(bottom)], "Dissolving a split that isn't shown leaves its last pane in the split's slot")

            store.closeTab(d)
            let displayed = store.state.splitLayouts.first { $0.id == shown.id }
            #expect(displayed?.tabIDs == [e, f] && displayed?.sidebarAnchorID == e && store.state.selectedTabIDs == [e, f], "The shown split loses its anchor pane and stays shown")
            #expect(today() == [.tab(top), .tab(c), .tab(middle), .split(shown.id), .tab(bottom)], "Closing the anchor pane of the shown split keeps the split in its slot")
        }
    }

    @Test static func splitMembershipContainers() throws {
        try withDirectory { directory in
            let store = try BrowserStore(directory: directory, now: { Date(timeIntervalSince1970: 1_800_000_000) })
            let space = store.activeSpaceID, profile = store.activeSpace.profileID
            let todayBox = SidebarContainerLocation(spaceID: space, folderID: nil, section: .today)
            let tray = SidebarContainerLocation(spaceID: space, folderID: nil, section: .favorite, profileID: profile)
            @MainActor func today() -> [SidebarItemReference] { SidebarHierarchy.children(in: todayBox, state: store.state) }
            @MainActor func trayItems() -> [SidebarItemReference] { SidebarHierarchy.children(in: tray, state: store.state) }
            let folder = store.createFolder(name: "Saved")
            let folderBox = SidebarContainerLocation(spaceID: space, folderID: folder, section: .pinned)
            let favorite = store.open("https://fav.example", kind: .favorite)
            let pinned = store.open("https://pin.example", kind: .pinned)
            store.moveTab(pinned, toSpace: space, folderID: folder)
            let t1 = store.open("https://t1.example"), t2 = store.open("https://t2.example")
            #expect(today() == [.tab(t2), .tab(t1)], "Created Today tabs enter at the top")

            store.selectTab(pinned); store.selectTab(t1, extendingSplit: true)
            var group = store.activeSplitLayout!
            let pinnedHome = try expectHome(of: pinned, in: store, savedURL: "https://pin.example")
            #expect(group.tabIDs == [pinned, t1] && group.sidebarAnchorID == t1, "New split anchors at its first ordinary member")
            #expect(today() == [.tab(t2), .split(group.id)], "The new split takes the ordinary member's Today slot")
            #expect(SidebarHierarchy.children(in: folderBox, state: store.state) == [.tab(pinnedHome.id)]
                       && pinnedHome.folderID == folder, "The pinned slot keeps a fresh home in its folder")
            #expect(try tab(pinned, in: store).kind == .today && tab(pinned, in: store).folderID == nil, "The pinned original enters the Today container with its split")
            store.selectTab(favorite, extendingSplit: true)
            group = store.activeSplitLayout!
            let favoriteHome = try expectHome(of: favorite, in: store, savedURL: "https://fav.example")
            #expect(group.tabIDs == [pinned, t1, favorite] && trayItems() == [.tab(favoriteHome.id)], "A Favorite added to a Today split leaves its tray home")
            #expect(try tab(favorite, in: store).kind == .today && today() == [.tab(t2), .split(group.id)], "The Favorite original joins the existing Today container; the split keeps its slot")

            #expect(store.separateTabFromSplit(t1, expected: group, focusedID: pinned), "Separate the anchor")
            group = store.state.splitLayouts.first { $0.id == group.id }!
            #expect(group.sidebarAnchorID == pinned && today() == [.tab(t2), .split(group.id), .tab(t1)], "A departing anchor keeps the split's slot; the child follows the split")
            #expect(store.separateTabFromSplit(favorite, expected: group, focusedID: pinned), "Separate to dissolve")
            #expect(store.activeSplitLayout == nil && today() == [.tab(t2), .tab(pinned), .tab(favorite), .tab(t1)], "Dissolving puts every child at the split's slot in child order")

            let g1 = store.open("https://g1.example", kind: .favorite), g2 = store.open("https://g2.example", kind: .favorite)
            store.selectTab(g1); store.selectTab(g2, extendingSplit: true)
            let saved = store.activeSplitLayout!
            let g1Home = try expectHome(of: g1, in: store, savedURL: "https://g1.example")
            let g2Home = try expectHome(of: g2, in: store, savedURL: "https://g2.example")
            #expect(today().first == .split(saved.id) && trayItems() == [.tab(favoriteHome.id), .tab(g1Home.id), .tab(g2Home.id)], "Two Favorites form a Today split at the top while the tray keeps both homes")
            store.closeTab(g1)
            #expect(today().first == .tab(g2) && store.activeSplitLayout == nil, "Closing a pane dissolves the split into its slot with the survivor")

            let u1 = store.open("https://u1.example"), u2 = store.open("https://u2.example")
            let favoriteSplit = try savedSplit(store, [u1, u2], in: tray)
            store.selectTab(u1)
            let t3 = store.open("https://t3.example")
            store.selectTab(u1); store.selectTab(t3, extendingSplit: true)
            #expect(try store.activeSplitLayout?.id == favoriteSplit.id && store.activeSplitLayout?.tabIDs == [u1, u2, t3]
                       && (try tab(t3, in: store)).kind == .favorite, "A Today page added to a Favorite split joins topApps")
            #expect(!trayItems().contains(.tab(t3)) && trayItems().filter { $0 == .split(favoriteSplit.id) }.count == 1, "The Favorite split stays one tray item")
            let q = store.open("https://q.example", kind: .pinned)
            store.selectTab(u1)
            let current = store.state.selectedTabIDs
            #expect(store.insertCommandBarSplit(after: t3, expectedSelection: current, tabID: q), "A pinned command-bar result joins the Favorite split")
            let qHome = try expectHome(of: q, in: store, savedURL: "https://q.example")
            #expect(try qHome.kind == .pinned && (try tab(q, in: store)).kind == .favorite && store.state.selectedTabIDs == current + [q], "The pinned result leaves its home and its original enters topApps")
            let secondSpace = store.createSpace(name: "Second")
            store.selectTab(u1)
            #expect(store.activeSpaceID == secondSpace && store.state.selectedTabIDs == current + [q], "The Favorite split with its new members appears in every Space")
            let favoriteGroup = store.activeSplitLayout!
            #expect(store.separateTabFromSplit(q, expected: favoriteGroup, focusedID: u1), "Separate from a Favorite split")
            let trayNow = SidebarHierarchy.children(in: .init(spaceID: secondSpace, folderID: nil, section: .favorite, profileID: profile), state: store.state)
            #expect(try trayNow.firstIndex(of: .split(favoriteGroup.id)).map { $0 + 1 } == trayNow.firstIndex(of: .tab(q))
                       && (try tab(q, in: store)).kind == .favorite, "The separated child is a Favorite right after the split tile")
            store.selectSpace(space)

            let v1 = store.open("https://v1.example"), v2 = store.open("https://v2.example")
            let pinnedSplit = try savedSplit(store, [v1, v2], in: folderBox)
            store.selectTab(v1)
            let t4 = store.open("https://t4.example")
            store.selectTab(v1)
            #expect(store.dropTabIntoSplit(t4, expectedSelection: [v1, v2], expectedLayout: store.activeSplitLayout,
                target: .insert(2), orientation: pinnedSplit.orientation), "Drop a Today tab into a pinned split")
            #expect(try tab(t4, in: store).kind == .pinned && tab(t4, in: store).folderID == folder
                       && store.activeSplitLayout?.tabIDs == [v1, v2, t4], "The dropped tab enters the pinned split's folder")

            try store.save()
            let reopened = try BrowserStore(directory: directory, now: { Date(timeIntervalSince1970: 1_800_000_000) })
            #expect(reopened.state == store.state, "Container membership and slots survive restart")
        }
    }

    @Test static func splitMembershipRoutes() throws {
        try withDirectory { directory in
            let store = try BrowserStore(directory: directory, now: { Date(timeIntervalSince1970: 1_800_000_000) })
            let space = store.activeSpaceID, profile = store.activeSpace.profileID
            let pinnedRoot = SidebarContainerLocation(spaceID: space, folderID: nil, section: .pinned)
            let todayBox = SidebarContainerLocation(spaceID: space, folderID: nil, section: .today)

            let documentID = URL(fileURLWithPath: NSTemporaryDirectory() + "Parc Notes/" + UUID().uuidString + ".md")
            let note = store.openNote(url: documentID, title: "Note")!
            store.selectTab(note)
            let todayJoin = UUID()
            #expect(store.commandBarSplitHomes(after: note, expectedSelection: [note], tabID: todayJoin, isNew: true)?.isEmpty == true, "A Today Note does not leave a pinned home beside a new URL")
            store.setKind(note, .pinned)
            let newID = UUID()
            let noteHomes = store.commandBarSplitHomes(after: note, expectedSelection: [note], tabID: newID, isNew: true)!
            #expect(noteHomes.map(\.id) == [note], "The displayed pinned Note needs a home even beside a new URL")
            #expect(SplitMembership.homePlan(noteHomes) { _ in nil } == nil, "A typed home without a live document refuses")
            let reference = SidebarDocumentReference(page: .note(documentID), profileID: profile) { }
            let plan = SplitMembership.homePlan(noteHomes) { _ in [note: reference] }!
            #expect(Set(plan.ids.keys) == [note] && plan.documents.count == 1, "The plan fixes one validated Note home")
            #expect(store.insertCommandBarSplit(after: note, expectedSelection: [note], tabID: newID,
                newURL: URL(string: "https://new.example")!, savedHomeIDs: plan.ids, documents: plan.documents), "A lone Note pane splits with a new URL")
            let noteHome = store.state.tabs.first { $0.id == plan.ids[note] }!
            #expect(try noteHome.kind == .pinned && noteHome.savedURL == InternalPage.note(documentID).urlString
                       && (try tab(note, in: store)).kind == .today, "The Note joins Today and its alias home stays pinned")

            let p = store.open("https://p.example", kind: .pinned), q = store.open("https://q.example", kind: .pinned)
            let t = store.open("https://t.example")
            _ = store.setWindowPresentation(spaceID: space, selectedTabIDs: [p])
            #expect(store.splitExtensionHomes(q).map(\.id) == [p, q], "Window A's single pinned page also needs a home")
            _ = store.setWindowPresentation(spaceID: space, selectedTabIDs: [t])
            #expect(store.splitExtensionHomes(q).map(\.id) == [q], "Window B plans from its own synchronized selection")

            let a = store.open("https://a.example"), b = store.open("https://b.example")
            store.selectTab(a); store.selectTab(b, extendingSplit: true)
            let pair = store.activeSplitLayout!
            store.setKind(b, .pinned)
            #expect(try tab(a, in: store).kind == .pinned && tab(b, in: store).kind == .pinned
                       && SidebarHierarchy.children(in: pinnedRoot, state: store.state).contains(.split(pair.id)), "Pinning a split pane pins its whole split")
            store.setKind(a, .today)
            #expect(try tab(a, in: store).kind == .today && tab(b, in: store).kind == .today
                       && SidebarHierarchy.children(in: todayBox, state: store.state).contains(.split(pair.id)), "Unpinning a split pane unpins its whole split")

            let w1 = store.open("https://w1.example", kind: .pinned), w2 = store.open("https://w2.example")
            _ = store.setWindowPresentation(spaceID: space, selectedTabIDs: [w1, w2],
                splitLayout: BrowserSplitLayout(spaceID: space, tabIDs: [w1, w2], widthFactors: [0.5, 0.5]))
            let reformed = store.state.splitLayouts.first { $0.tabIDs == [w1, w2] }
            #expect(try reformed != nil && (try tab(w1, in: store)).kind == .today
                       && store.state.tabs.contains { $0.kind == .pinned && $0.savedURL == "https://w1.example" && $0.id != w1 }, "A window's own split re-forms through the membership owner")

            let x1 = store.open("https://x1.example"), x2 = store.open("https://x2.example"), x3 = store.open("https://x3.example")
            let pinnedSplit = try savedSplit(store, [x1, x2, x3], in: pinnedRoot)
            store.selectTab(x1)
            store.closeTab(x2)
            let afterClose = SidebarHierarchy.children(in: pinnedRoot, state: store.state)
            #expect(try store.state.splitLayouts.first { $0.id == pinnedSplit.id }?.tabIDs == [x1, x3]
                       && (try tab(x2, in: store)).kind == .pinned && (try tab(x2, in: store)).archivedAt == nil
                       && afterClose.firstIndex(of: .split(pinnedSplit.id)).map { $0 + 1 } == afterClose.firstIndex(of: .tab(x2)), "A closed pinned pane stays saved and follows its split")

            let f1 = store.open("https://f1.example"), f2 = store.open("https://f2.example"), f3 = store.open("https://f3.example")
            let tray = SidebarContainerLocation(spaceID: space, folderID: nil, section: .favorite, profileID: profile)
            let favoriteSplit = try savedSplit(store, [f1, f2, f3], in: tray)
            let second = store.createSpace(name: "Second")
            store.selectTab(f1)
            #expect(store.activeSpaceID == second && store.activeSplitLayout?.id == favoriteSplit.id, "The Favorite split shows in Space 2")
            store.closeTab(f2)
            let trayFromSecond = SidebarHierarchy.children(in: .init(spaceID: second, folderID: nil, section: .favorite, profileID: profile), state: store.state)
            #expect(store.state.splitLayouts.first { $0.id == favoriteSplit.id }?.tabIDs == [f1, f3]
                       && trayFromSecond.firstIndex(of: .split(favoriteSplit.id)).map { $0 + 1 } == trayFromSecond.firstIndex(of: .tab(f2)), "Closing a Favorite split pane from another Space removes it from the one split")
            store.selectSpace(space)
            let other = store.createProfile(name: "Other")
            var relocatedNote = false
            store.relocateLocalDocuments = { _, _, _, _ in relocatedNote = true; return {} }
            store.assignProfile(other, toSpace: space)
            #expect(try !relocatedNote && (try tab(note, in: store)).profileID == other && (try tab(noteHome.id, in: store)).profileID == other, "Profile assignment carries the Note and its alias along while the note file stays put")
            let kept = store.state.splitLayouts.first { $0.id == favoriteSplit.id }
            #expect(kept?.spaceID == second && kept?.tabIDs == [f1, f3], "A Favorite split survives its storing Space changing Profile")
        }
    }

    @Test static func legacyMixedSplitContainerMigration() throws {
        try withDirectory { directory in
            let now = Date(timeIntervalSince1970: 1_800_000_000)
            var state = BrowserState.initial()
            let space = state.activeSpaceID, profile = state.profiles[0].id
            let other = BrowserSpace(id: UUID(), name: "Other", symbol: "circle.fill", color: "B9B5D4", profileID: profile)
            state.spaces.append(other)
            let folder = BrowserFolder(id: UUID(), spaceID: space, name: "Saved")
            state.folders = [folder]
            func make(_ kind: TabKind, _ name: String, folder: UUID? = nil, in spaceID: UUID? = nil) -> BrowserTab {
                BrowserTab(id: UUID(), spaceID: spaceID ?? space, profileID: profile, url: "https://\(name).example/now",
                    title: name, kind: kind, folderID: folder, createdAt: now, lastAccessed: now,
                    savedURL: "https://\(name).example", savedTitle: name)
            }
            let today = make(.today, "today"), fav = make(.favorite, "fav"), pin = make(.pinned, "pin", folder: folder.id)
            let anchorFavorite = make(.favorite, "anchor"), stray = make(.today, "stray")
            let x = make(.favorite, "x"), y = make(.favorite, "y")
            state.tabs = [today, fav, pin, anchorFavorite, stray, x, y]
            let trayKey = "favorites:" + profile.uuidString
            state.sidebarItemOrder[trayKey] = [.tab(fav.id), .tab(anchorFavorite.id), .tab(x.id)]
            state.sidebarItemOrder[space.uuidString + ":" + folder.id.uuidString] = [.tab(pin.id)]
            let todayGroup = BrowserSplitLayout(spaceID: space, tabIDs: [today.id, fav.id, pin.id], widthFactors: [0.2, 0.3, 0.5])
            let favoriteAnchored = BrowserSplitLayout(spaceID: space, tabIDs: [anchorFavorite.id, stray.id], widthFactors: [0.5, 0.5])
            let older = BrowserSplitLayout(spaceID: other.id, tabIDs: [x.id, y.id], orientation: .vertical, widthFactors: [0.4, 0.6])
            let newer = BrowserSplitLayout(spaceID: space, tabIDs: [x.id, y.id], widthFactors: [0.7, 0.3])
            state.splitLayouts = [todayGroup, favoriteAnchored, older, newer]
            state.selectedTabIDs = todayGroup.tabIDs
            state.selectionBySpace[other.id.uuidString] = [fav.id]
            state.settings.restoreSession = true
            let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(state).write(to: directory.appendingPathComponent("session.json"))

            let store = try BrowserStore(directory: directory, now: { now })
            let originals = Set(state.tabs.map(\.id))
            #expect(originals.isSubset(of: Set(store.state.tabs.filter { $0.archivedAt == nil }.map(\.id))), "Migration keeps every original page live")
            let favHome = try expectHome(of: fav.id, in: store, savedURL: "https://fav.example")
            let pinHome = try expectHome(of: pin.id, in: store, savedURL: "https://pin.example")
            #expect(try tab(fav.id, in: store).kind == .today && tab(pin.id, in: store).kind == .today
                       && tab(pin.id, in: store).folderID == nil, "Children of a Today-anchored group enter Today")
            #expect(store.state.sidebarItemOrder[trayKey]?.first == .tab(favHome.id)
                       && store.state.sidebarItemOrder[space.uuidString + ":" + folder.id.uuidString] == [.tab(pinHome.id)], "Each saved child keeps a fresh home in its exact former slot")
            #expect(store.state.selectionBySpace[other.id.uuidString] == [favHome.id], "Another Space's remembered Favorite follows the saved home")
            #expect(store.activeSplitLayout?.id == todayGroup.id && store.activeSplitLayout?.tabIDs == todayGroup.tabIDs, "The Today group keeps its identity, order and selection")
            #expect(try tab(stray.id, in: store).kind == .favorite
                       && store.state.splitLayouts.contains { $0.id == favoriteAnchored.id && $0.tabIDs == favoriteAnchored.tabIDs }, "A Favorite-anchored group stays in the tray and its Today child joins topApps")
            let favoritePairs = store.state.splitLayouts.filter { $0.tabIDs.contains(x.id) }
            #expect(favoritePairs.count == 1 && favoritePairs[0].id == newer.id && favoritePairs[0].widthFactors == newer.widthFactors, "Per-Space copies of the same Favorites become one Profile-wide split")
            #expect(store.state.splitLayouts.allSatisfy { group in
                guard let box = SplitMembership.container(of: group, in: store.state) else { return false }
                return group.tabIDs.allSatisfy { id in store.state.tabs.first { $0.id == id }.map { SplitMembership.conforms($0, to: box) } ?? false }
            }, "Every group's children share their split's container")
            let migrated = store.state
            let again = try BrowserStore(directory: directory, now: { now })
            #expect(again.state == migrated, "The migrated form is persisted and stable on the next restart")
        }
    }

    @Test static func legacySharedFavoriteMigration() throws {
        try withDirectory { directory in
            let now = Date(timeIntervalSince1970: 1_800_000_000)
            var state = BrowserState.initial()
            let first = state.activeSpaceID, profile = state.profiles[0].id
            let second = BrowserSpace(id: UUID(), name: "Second", symbol: "circle.fill", color: "B9B5D4", profileID: profile)
            state.spaces.append(second)
            func make(_ kind: TabKind, _ name: String, in spaceID: UUID) -> BrowserTab {
                BrowserTab(id: UUID(), spaceID: spaceID, profileID: profile, url: "https://\(name).example", title: name,
                    kind: kind, createdAt: now, lastAccessed: now, savedURL: "https://\(name).example", savedTitle: name)
            }
            let shared = make(.favorite, "shared", in: first), partner = make(.favorite, "partner", in: second.id)
            let t1 = make(.today, "t1", in: first), t2 = make(.today, "t2", in: first)
            let roaming = make(.favorite, "roaming", in: first), t3 = make(.today, "t3", in: first)
            let fillers = (0..<10).map { make(.favorite, "filler\($0)", in: first) }
            state.tabs = [shared, partner, t1, t2, roaming, t3] + fillers
            let mixed = BrowserSplitLayout(customTitle: "Kept title", spaceID: first, tabIDs: [t1.id, shared.id, t2.id], widthFactors: [0.2, 0.3, 0.5])
            let favoriteSplit = BrowserSplitLayout(spaceID: second.id, tabIDs: [shared.id, partner.id], widthFactors: [0.5, 0.5])
            let roamingSplit = BrowserSplitLayout(spaceID: first, tabIDs: [t3.id, roaming.id], widthFactors: [0.5, 0.5])
            state.splitLayouts = [favoriteSplit, mixed, roamingSplit]
            state.selectionBySpace[first.uuidString] = mixed.tabIDs
            state.activeSpaceID = second.id; state.selectedTabIDs = [roaming.id]
            state.settings.restoreSession = true
            let trayFromSecond = SidebarContainerLocation(spaceID: second.id, folderID: nil, section: .favorite, profileID: profile)
            let rootsBefore = SidebarHierarchy.children(in: trayFromSecond, state: state).count
            let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(state).write(to: directory.appendingPathComponent("session.json"))

            let store = try BrowserStore(directory: directory, now: { now })
            #expect(store.state.splitLayouts.first { $0.id == favoriteSplit.id }?.tabIDs == [shared.id, partner.id], "The Favorites-container split keeps the shared Favorite")
            let kept = store.state.splitLayouts.first { $0.id == mixed.id }
            #expect(kept?.tabIDs == [t1.id, t2.id] && kept?.customTitle == "Kept title", "The other split keeps its own children, layout and title")
            #expect(try tab(shared.id, in: store).kind == .favorite, "The shared Favorite stays a Favorite")
            let roamingHome = try expectHome(of: roaming.id, in: store, savedURL: "https://roaming.example")
            #expect(try store.state.selectedTabIDs == [roamingHome.id] && (try tab(roaming.id, in: store)).kind == .today, "The active selection in another Space follows the moved Favorite's home")
            let rootsAfter = SidebarHierarchy.children(in: trayFromSecond, state: store.state).count
            #expect(rootsBefore == 12 && rootsAfter == rootsBefore, "Migration adds no Favorites root past twelve")
            let again = try BrowserStore(directory: directory, now: { now })
            #expect(again.state == store.state, "The resolved form is persisted and stable")
        }
    }

    @Test static func splitPaneChangesPreserveSurvivors() throws {
        try withDirectory { directory in
            let store = try BrowserStore(directory: directory, now: { Date(timeIntervalSince1970: 1_800_000_000) })
            let first = store.open("https://one.example", kind: .pinned)
            let second = store.open("https://two.example", kind: .pinned)
            let third = store.open("https://three.example")
            let replacement = store.open("https://replacement.example")
            store.setSplit([first, third])
            store.setSplitLayout(orientation: .horizontal, widthFactors: [4, 1])
            store.setSplit([first, second, third])
            store.setSplitLayout(orientation: .vertical, widthFactors: [1, 2, 3])
            let firstHome = try expectHome(of: first, in: store, savedURL: "https://one.example")
            let secondHome = try expectHome(of: second, in: store, savedURL: "https://two.example")
            #expect(SidebarHierarchy.children(in: .init(spaceID: store.activeSpaceID, folderID: nil, section: .pinned),
                                                 state: store.state) == [.tab(firstHome.id), .tab(secondHome.id)], "Each pinned member that joins keeps a fresh home in its own slot")
            store.setSplit([first, replacement, third])
            try expectFactors(store.activeSplitLayout?.widthFactors, [1.0/6, 2.0/6, 3.0/6],
                              "Replacing a pane's tab must preserve its position and divider sizes")
            #expect(store.activeSplitLayout?.orientation == .vertical, "Replacing a pane must preserve orientation")
            store.setSplit([first, second, third])
            let originalGroup = store.activeSplitLayout!
            #expect(store.separateTabFromSplit(second, expected: originalGroup, focusedID: first), "Separating a different pane preserves the original focus")
            try expectFactors(store.activeSplitLayout?.widthFactors, [0.25, 0.75], "Separating a pane must proportionally expand surviving panes, replacing any older geometry for the surviving group")
            #expect(store.activeSplitLayout?.orientation == .vertical, "The visible split must win when its surviving group already has an older saved layout")
            #expect(try tab(second, in: store).archivedAt == nil, "Separating a page must leave its tab alive")
            store.selectTab(second, extendingSplit: true)
            #expect(store.activeSplitLayout?.tabIDs == [first, third, second], "Adding a pane must append it to the current saved split")
            store.setSplitLayout(orientation: .vertical, widthFactors: [1, 3, 2])
            store.closeTab(second)
            try expectFactors(store.activeSplitLayout?.widthFactors, [0.25, 0.75], "Closing a pane must resize survivors")
            #expect(try tab(second, in: store).archivedAt != nil && tab(secondHome.id, in: store).archivedAt == nil, "The joined original archives as a Today pane while its saved home keeps the bookmark")
            store.closeTab(third)
            #expect(store.state.selectedTabIDs == [first] && store.activeSplitLayout == nil, "Closing the penultimate pane must leave one normal page")
            #expect(store.state.splitLayouts.allSatisfy { !$0.tabIDs.contains(third) }, "Archived tabs must be removed from every saved layout")
            store.setSplit([first, replacement])
            store.closeSplit()
            #expect(!store.state.splitLayouts.contains { $0.spaceID == store.activeSpaceID && $0.tabIDs == [first, replacement] }, "Closing a split must dissolve its saved layout without closing its pages")
            #expect(try tab(replacement, in: store).archivedAt == nil, "Dissolving a split must preserve its other page")
        }
    }

    @Test static func splitLayoutMembershipCleanup() throws {
        try withDirectory { directory in
            let store = try BrowserStore(directory: directory, now: { Date(timeIntervalSince1970: 1_800_000_000) })
            let firstSpace = store.activeSpaceID
            let first = store.open("https://one.example")
            let second = store.open("https://two.example")
            let favorite = store.open("https://favorite.example", kind: .favorite)
            store.setSplit([first, second, favorite])
            store.setSplitLayout(orientation: .vertical, widthFactors: [1, 2, 3])
            let favoriteHome = try expectHome(of: favorite, in: store, savedURL: "https://favorite.example")
            #expect(try tab(favorite, in: store).kind == .today && favoriteHome.kind == .favorite, "A Favorite joining a new split enters Today; its fresh home keeps the tray slot")
            let otherSpace = store.createSpace(name: "Other")
            store.moveTab(second, toSpace: otherSpace)
            store.selectSpace(firstSpace)
            #expect(store.state.selectedTabIDs == [first, favorite], "Space restoration must drop a moved pane")
            try expectFactors(store.activeSplitLayout?.widthFactors, [0.25, 0.75], "A moved pane must be removed from its former split's saved geometry")
            let profile = store.createProfile(name: "Separate")
            store.assignProfile(profile, toSpace: firstSpace)
            #expect(try store.state.splitLayouts.map(\.tabIDs) == [[first, favorite]]
                       && (try tab(first, in: store)).profileID == profile && (try tab(favorite, in: store)).profileID == profile, "The joined original is an ordinary page of the split and follows its Space's Profile")
            #expect(try tab(favoriteHome.id, in: store).profileID != profile, "The Favorite's saved home stays in its own Profile's tray")
            try store.save()
            _ = try BrowserStore(directory: directory, now: { Date(timeIntervalSince1970: 1_800_000_000) })
        }
    }

    @Test static func legacySplitLayoutMigration() throws {
        try withDirectory { directory in
            let store = try BrowserStore(directory: directory, now: { Date(timeIntervalSince1970: 1_800_000_000) })
            let firstSpace = store.activeSpaceID
            let first = store.open("https://one.example")
            let second = store.open("https://two.example")
            store.setSplit([first, second])
            let secondSpace = store.createSpace(name: "Other")
            let third = store.open("https://three.example")
            let fourth = store.open("https://four.example")
            store.setSplit([third, fourth])
            try store.save()
            let file = directory.appendingPathComponent("session.json")
            var json = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
            json.removeValue(forKey: "splitLayouts")
            json["splitWidthFactors"] = [2, 6]
            json["splitIsVertical"] = false
            try JSONSerialization.data(withJSONObject: json).write(to: file)
            let reopened = try BrowserStore(directory: directory, now: { Date(timeIntervalSince1970: 1_800_000_000) })
            #expect(reopened.activeSpaceID == secondSpace && reopened.activeSplitLayout?.orientation == .horizontal, "Legacy sessions must keep their actual previous side-by-side presentation")
            try expectFactors(reopened.activeSplitLayout?.widthFactors, [0.25, 0.75], "Legacy active weights must migrate into the active pane group")
            reopened.selectSpace(firstSpace)
            try expectFactors(reopened.activeSplitLayout?.widthFactors, [0.5, 0.5], "Older inactive split selections must migrate with equal sizes")
            try reopened.save()
            let saved = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
            #expect(saved["splitLayouts"] != nil && saved["splitWidthFactors"] == nil && saved["splitIsVertical"] == nil, "A migrated save must replace unused globals with per-split records")
            let again = try BrowserStore(directory: directory, now: { Date(timeIntervalSince1970: 1_800_000_000) })
            #expect(again.state == reopened.state, "Split migration must be idempotent")
        }
    }

    @Test static func legacyStaleSplitSelectionMigration() throws {
        try withDirectory { directory in
            let store = try BrowserStore(directory: directory, now: { Date(timeIntervalSince1970: 1_800_000_000) })
            let originalSpace = store.activeSpaceID
            let first = store.open("https://one.example")
            let second = store.open("https://two.example")
            let third = store.open("https://three.example")
            store.setSplit([first, second, third])
            let otherSpace = store.createSpace(name: "Other")
            store.moveTab(first, toSpace: otherSpace)
            store.closeTab(second)
            try store.save()
            let file = directory.appendingPathComponent("session.json")
            var json = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
            json.removeValue(forKey: "splitLayouts")
            json["splitWidthFactors"] = []
            json["splitIsVertical"] = false
            try JSONSerialization.data(withJSONObject: json).write(to: file)
            let reopened = try BrowserStore(directory: directory)
            reopened.selectSpace(originalSpace)
            #expect(reopened.state.selectedTabIDs == [third] && reopened.activeSplitLayout == nil, "Legacy inactive selections containing moved or archived tabs must migrate without rejecting an otherwise valid session")
            try reopened.save()
            _ = try BrowserStore(directory: directory)
        }
    }

    @Test static func invalidPersistedSplitsArePreserved() throws {
        try withDirectory { directory in
            let store = try BrowserStore(directory: directory, now: { Date(timeIntervalSince1970: 1_800_000_000) })
            let first = store.open("https://one.example")
            let second = store.open("https://two.example")
            store.setSplit([first, second])
            try store.save()
            let good = store.state
            let base = good.splitLayouts[0]
            var cases: [[BrowserSplitLayout]] = []
            var invalid = base; invalid.widthFactors = [0, 1]; cases.append([invalid])
            invalid = base; invalid.widthFactors = [1]; cases.append([invalid])
            invalid = base; invalid.widthFactors = [2, 3]; cases.append([invalid])
            invalid = base; invalid.tabIDs = [first, first]; cases.append([invalid])
            invalid = base; invalid.tabIDs = [first, UUID()]; cases.append([invalid])
            invalid = base; invalid.spaceID = UUID(); cases.append([invalid])
            cases.append([base, base])
            let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
            let file = directory.appendingPathComponent("session.json")
            for layouts in cases {
                var damaged = good; damaged.splitLayouts = layouts
                let bytes = try encoder.encode(damaged)
                try bytes.write(to: file)
                var rejected = false
                do { _ = try BrowserStore(directory: directory, now: { Date(timeIntervalSince1970: 1_800_000_000) }) } catch { rejected = true }
                #expect(rejected, "Invalid saved split membership or geometry must reject the session")
                #expect(try Data(contentsOf: file) == bytes, "Rejecting a malformed split must preserve the session for recovery")
            }
        }
    }
}
