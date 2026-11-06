import Foundation
import Combine

@main struct FavoriteSplitTests {
    @MainActor static func main() throws {
        var checks = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            precondition(condition(), message); checks += 1
        }
        let now = Date(timeIntervalSince1970: 1000)
        var state = BrowserState.initial()
        let space = state.activeSpaceID, profile = state.profiles[0].id
        func tab(_ kind: TabKind, _ name: String) -> BrowserTab {
            BrowserTab(id: UUID(), spaceID: space, profileID: profile,
                url: "https://example.test/" + name, title: name, kind: kind,
                createdAt: now, lastAccessed: now, savedURL: "https://example.test/" + name, savedTitle: name)
        }
        var favorite = tab(.favorite, "home")
        favorite.customTitle = "My app"
        let first = tab(.today, "first"), second = tab(.today, "second"), fourth = tab(.today, "fourth")
        state.tabs = [favorite, first, second, fourth]
        state.selectedTabIDs = [first.id]
        func request(_ snapshot: BrowserState, focus: UUID, url: String? = nil, id: UUID = UUID(),
                     target: BrowserTab? = nil, homes: [UUID: UUID] = [:]) -> FavoriteSplitRequest? {
            FavoriteSplitRequest(favorite: snapshot.tabs.first { $0.id == (target ?? favorite).id }!,
                spaceID: space, selection: snapshot.selectedTabIDs, focusedID: focus,
                state: snapshot, duplicateURL: url, duplicateTitle: "Live title", newID: id, homeIDs: homes)
        }
        //
        //
        //
        //
        let trayHome = UUID()
        check(request(state, focus: first.id)!.savedHomeSources(in: state).map(\.id) == [favorite.id],
              "The released Favorite needs a saved home")
        check(request(state, focus: first.id)!.applying(to: state, retiring: [], now: now) == nil,
              "A saved member is never moved without its fixed home identity")
        let original = request(state, focus: first.id, homes: [favorite.id: trayHome])!
        let opened = original.applying(to: state, retiring: [], now: now.addingTimeInterval(1))!
        check(opened.selectedTabIDs == [first.id, favorite.id], "Original follows focus")
        let joined = opened.tabs.first { $0.id == favorite.id }!, home = opened.tabs.first { $0.id == trayHome }!
        check(joined.kind == .today && joined.spaceID == space && joined.savedURL == favorite.savedURL,
              "The original Favorite ID joins the Today split with its page")
        check(home.kind == .favorite && home.savedURL == favorite.savedURL && home.customTitle == favorite.customTitle
              && home.url == favorite.savedURL, "The tray keeps a fresh home at the saved page and custom title")
        let trayLocation = SidebarContainerLocation(spaceID: space, folderID: nil, section: .favorite, profileID: profile)
        check(SidebarHierarchy.children(in: trayLocation, state: opened) == [.tab(trayHome)], "The home holds the tray slot")
        check(opened.history == state.history && opened.recentlyClosedIDs == state.recentlyClosedIDs, "No fabricated history or Undo")
        check(opened.splitLayouts.count == 1 && opened.splitLayouts[0].sidebarAnchorID == first.id,
              "One genuine Today split anchored at its ordinary member")
        check(opened.selectionBySpace[space.uuidString] == opened.selectedTabIDs, "Return selection preserved")
        var split = state
        let group = BrowserSplitLayout(customTitle: "Existing group", spaceID: space,
            tabIDs: [first.id, second.id], orientation: .vertical, widthFactors: [0.3, 0.7])
        split.splitLayouts = [group]; split.selectedTabIDs = group.tabIDs
        let inserted = request(split, focus: first.id, homes: [favorite.id: trayHome])!.applying(to: split, retiring: [], now: now)!
        check(inserted.selectedTabIDs == [first.id, favorite.id, second.id], "Insertion is after focused pane, not append")
        check(inserted.splitLayouts[0].id == group.id && inserted.splitLayouts[0].customTitle == group.customTitle,
              "Existing container identity and title survive")
        check(inserted.splitLayouts[0].orientation == .vertical, "Existing orientation survives")
        check(abs(inserted.splitLayouts[0].widthFactors.reduce(0, +) - 1) < 0.00001, "Weights remain normalized")
        check(inserted.tabs.first { $0.id == favorite.id }?.kind == .today && inserted.tabs.contains { $0.id == trayHome },
              "Joining an existing Today split also leaves the tray home")

        // A Favorite split is one topApps item: its members stay Favorites.
        let partner = tab(.favorite, "partner")
        var already = state
        already.tabs.append(partner)
        let favoriteGroup = BrowserSplitLayout(spaceID: space, tabIDs: [favorite.id, partner.id], widthFactors: [0.5, 0.5])
        already.splitLayouts = [favoriteGroup]; already.selectedTabIDs = favoriteGroup.tabIDs
        let focusExisting = request(already, focus: partner.id)!
        check(focusExisting.targetID == favorite.id, "Already-visible target requests original focus")
        check(focusExisting.applying(to: already, retiring: [], now: now)!.splitLayouts == already.splitLayouts,
              "No duplicate group when target is already visible")
        let newID = UUID()
        let dup = request(already, focus: favorite.id, url: "https://example.test/current", id: newID)!
        check(dup.savedHomeSources(in: already).isEmpty, "The duplicate is the item being added; members stay")
        let duplicated = dup.applying(to: already, retiring: [], now: now)!
        let copy = duplicated.tabs.first { $0.id == newID }!
        check(duplicated.selectedTabIDs == [favorite.id, newID, partner.id], "Focused Favorite creates adjacent copy")
        check(copy.kind == .favorite && copy.folderID == nil && copy.profileID == profile,
              "The copy enters the displayed Favorite split's container")
        check(copy.url == "https://example.test/current" && copy.savedURL == copy.url, "Live destination copied without reset")
        check(copy.title == "Live title" && copy.customTitle == nil, "Away-home live title replaces saved custom title")
        check(duplicated.tabs.first { $0.id == favorite.id } == already.tabs.first { $0.id == favorite.id },
              "Original focused Favorite record remains unchanged")
        check(duplicated.splitLayouts.map(\.id) == [favoriteGroup.id], "The Favorite split keeps its one identity")
        // A lone focused Favorite: the duplicate and the Favorite form a new
        // Today split; the Favorite leaves its tray home.
        var lone = state; lone.selectedTabIDs = [favorite.id]
        let loneID = UUID(), loneHome = UUID()
        let loneRequest = request(lone, focus: favorite.id, url: "https://example.test/current", id: loneID, homes: [favorite.id: loneHome])!
        check(loneRequest.savedHomeSources(in: lone).map(\.id) == [favorite.id], "Only the displayed Favorite needs a home")
        let loneSplit = loneRequest.applying(to: lone, retiring: [], now: now)!
        check(loneSplit.selectedTabIDs == [favorite.id, loneID] && loneSplit.tabs.first { $0.id == loneID }?.kind == .today
              && loneSplit.tabs.first { $0.id == favorite.id }?.kind == .today && loneSplit.tabs.contains { $0.id == loneHome && $0.kind == .favorite },
              "A new split from a lone Favorite is a Today split and the tray keeps a fresh home")
        check(loneSplit.splitLayouts.first?.sidebarAnchorID == loneID
              && SidebarHierarchy.children(in: .init(spaceID: space, folderID: nil, section: .today), state: loneSplit).first == .split(loneSplit.splitLayouts[0].id),
              "The new split follows the duplicate at the top of Today")
        let homeCopy = request(already, focus: favorite.id, url: favorite.savedURL)!
            .applying(to: already, retiring: [], now: now)!.tabs.last!
        check(homeCopy.customTitle == favorite.customTitle && homeCopy.savedTitle == favorite.savedTitle,
              "At-home copy retains saved presentation")
        let equivalentURL = "http://WWW.Example.test/HOME/?utm_source=Mail#section"
        let equivalentCopy = request(already, focus: favorite.id, url: equivalentURL)!
            .applying(to: already, retiring: [], now: now)!.tabs.last!
        check(equivalentCopy.customTitle == favorite.customTitle && equivalentCopy.savedTitle == favorite.savedTitle,
              "Equivalent-home copy retains original saved/custom presentation")
        check(equivalentCopy.url == equivalentURL && equivalentCopy.savedURL == equivalentURL,
              "Comparison does not normalize the copied navigation destination")
        let queryCopy = request(already, focus: favorite.id, url: favorite.savedURL + "?view=other")!
            .applying(to: already, retiring: [], now: now)!.tabs.last!
        check(queryCopy.customTitle == nil && queryCopy.title == "Live title", "Meaningful query remains away-home")
        check(request(already, focus: favorite.id) == nil, "No invented URL for duplicate")
        check(request(already, focus: favorite.id, url: "parc://note/" + UUID().uuidString) == nil, "No local document surrogate")
        check(request(already, focus: favorite.id, url: favorite.url, id: first.id) == nil, "Fresh identity required")
        check(original.applying(to: state, retiring: [favorite.id], now: now) == nil, "Retiring target refused")
        check(original.applying(to: state, retiring: [first.id], now: now) == nil, "Retiring pane refused")
        check(original.applying(to: state, retiring: [trayHome], now: now) == nil, "Retiring home identity refused")
        var stale = state; stale.selectedTabIDs = [second.id]
        check(original.applying(to: stale, retiring: [], now: now) == nil, "Intervening selection wins")
        stale = state; stale.tabs[0].savedURL += "/changed"
        check(original.applying(to: stale, retiring: [], now: now) == nil, "Original item edit invalidates captured request")
        stale = state; stale.spaces[0].profileID = UUID()
        check(original.applying(to: stale, retiring: [], now: now) == nil, "Profile replacement refused")
        stale = state; stale.profileRemovals = [ProfileRemovalRecord(id: UUID(), profileID: profile, profileName: "Default")]
        check(original.applying(to: stale, retiring: [], now: now) == nil, "Durably staged profile retirement blocks split")
        stale = state; stale.profiles.removeAll()
        check(original.applying(to: stale, retiring: [], now: now) == nil, "Removed profile cannot be recreated")
        stale = state; stale.tabs.removeAll { $0.id == favorite.id }
        check(original.applying(to: stale, retiring: [], now: now) == nil, "Deletion cannot recreate old original")
        stale = state; stale.splitLayouts.append(group)
        check(original.applying(to: stale, retiring: [], now: now) == nil, "Changed container ownership refused")
        var full = state; full.selectedTabIDs = [first.id, second.id, fourth.id, favorite.id]
        full.splitLayouts = [BrowserSplitLayout(spaceID: space, tabIDs: full.selectedTabIDs, widthFactors: [0.25,0.25,0.25,0.25])]
        check(request(full, focus: favorite.id, url: favorite.url) == nil, "No fifth pane or implicit replacement")
        check(request(full, focus: first.id) != nil, "Existing pane focus remains possible at capacity")
        let other = tab(.today, "other")
        var oldGroups = state; oldGroups.tabs.append(other)
        let old = BrowserSplitLayout(spaceID: space, tabIDs: [second.id, other.id, fourth.id], widthFactors: [0.2,0.3,0.5])
        oldGroups.splitLayouts = [old]
        let relocated = request(oldGroups, focus: first.id, target: oldGroups.tabs.first { $0.id == favorite.id }, homes: [favorite.id: trayHome])!
            .applying(to: oldGroups, retiring: [], now: now)!
        check(relocated.splitLayouts.first { $0.id == old.id } == old, "An unrelated split is untouched")
        check(relocated.splitLayouts.flatMap(\.tabIDs).filter { $0 == favorite.id }.count == 1, "No overlapping membership")

        // Actual BrowserStore transaction: failed durable save must not publish
        // the copied item or selection. All paths are disposable and isolated.
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("FavoriteSplit-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        already.settings.restoreSession = true
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(already).write(to: directory.appendingPathComponent("session.json"))
        let store = try BrowserStore(directory: directory, now: { now })
        let savedRequest = request(store.state, focus: favorite.id, url: favorite.url)!
        let committedID = try store.commitFavoriteSplit(savedRequest)
        check(committedID == savedRequest.targetID, "Store commits actual copy")
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let disk = try decoder.decode(BrowserState.self, from: Data(contentsOf: directory.appendingPathComponent("session.json")))
        check(disk == store.state, "Published transaction equals durable session")
        let failedRequest = request(store.state, focus: favorite.id, url: favorite.url)!
        let beforeFailure = store.state
        try FileManager.default.removeItem(at: directory)
        try Data("blocked".utf8).write(to: directory)
        var rejected = false
        do { _ = try store.commitFavoriteSplit(failedRequest) } catch { rejected = true }
        check(rejected && store.state == beforeFailure, "Write failure leaves identity and selection untouched")
        check(store.persistenceError != nil, "Write failure remains visible to owner")

        let a = UUID(), b = UUID(), c = UUID(), d = UUID(), target = UUID()
        func route(_ selection: [UUID], _ focus: UUID?, _ id: UUID = target) -> FavoriteOptionRoute {
            FavoriteOptionRoute(favoriteID: id, selection: selection, focusedID: focus)
        }
        check(route([], nil) == .present, "No presentation: selection presents the Favorite itself")
        check(route([a], nil) == .present && route([a], b) == .present, "No focused pane to follow presents the Favorite")
        check(route([a], a) == .split && route([a, b, c], b) == .split, "Below capacity a new pane follows focus")
        check(route([a, target], a) == .split, "An existing pane receives focus")
        check(route([a, b, c, target], a) == .split, "An existing pane receives focus at capacity")
        check(route([target], target) == .split && route([a, b, target], target) == .split,
              "The focused Favorite is duplicated below capacity")
        check(route([a, b, c, target], target) == .unchanged, "The focused Favorite at capacity is not duplicated")
        check(route([a, b, c, d], b) == .paneLimit, "A fifth pane is refused")
        print("\(checks) Favorite split model/persistence assertions passed (no browser)")
    }
}
