import Foundation
import Testing
@testable import ParcCore

struct BrowserStoreSplitMigrationTests {
    private struct LegacyMixedSplit {
        let now: Date
        let state: BrowserState
        let fav: BrowserTab
        let pin: BrowserTab
        let space: UUID
        let other: BrowserSpace
        let folder: BrowserFolder
        let trayKey: String
        let todayGroup: BrowserSplitLayout
        let stray: BrowserTab
        let favoriteAnchored: BrowserSplitLayout
        let x: BrowserTab
        let newer: BrowserSplitLayout
    }

    private static func seedLegacyMixedSplit(in directory: URL) throws -> LegacyMixedSplit {
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

        return LegacyMixedSplit(now: now, state: state, fav: fav,
                                   pin: pin, space: space, other: other,
                                   folder: folder, trayKey: trayKey, todayGroup: todayGroup,
                                   stray: stray, favoriteAnchored: favoriteAnchored, x: x,
                                   newer: newer)
    }

    @Test @MainActor static func migratingLegacyMixedSplitsNormalizesTheirContainersAndSavedHomes() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let fixture = try seedLegacyMixedSplit(in: directory)
            let now = fixture.now
            let state = fixture.state
            let fav = fixture.fav
            let pin = fixture.pin
            let space = fixture.space
            let other = fixture.other
            let folder = fixture.folder
            let trayKey = fixture.trayKey
            let todayGroup = fixture.todayGroup
            let stray = fixture.stray
            let favoriteAnchored = fixture.favoriteAnchored
            let x = fixture.x
            let newer = fixture.newer
            let store = try BrowserStore(directory: directory, now: { now })
            let originals = Set(state.tabs.map(\.id))
            #expect(originals.isSubset(of: Set(store.state.tabs.filter { $0.archivedAt == nil }.map(\.id))), "Migration keeps every original page live")
            let favHome = try BrowserStoreTestsSupport.expectHome(of: fav.id, in: store, savedURL: "https://fav.example")
            let pinHome = try BrowserStoreTestsSupport.expectHome(of: pin.id, in: store, savedURL: "https://pin.example")
            #expect(try BrowserStoreTestsSupport.tab(fav.id, in: store).kind == .today && (try BrowserStoreTestsSupport.tab(pin.id, in: store)).kind == .today
                       && (try BrowserStoreTestsSupport.tab(pin.id, in: store)).folderID == nil, "Children of a Today-anchored group enter Today")
            #expect(store.state.sidebarItemOrder[trayKey]?.first == .tab(favHome.id)
                       && store.state.sidebarItemOrder[space.uuidString + ":" + folder.id.uuidString] == [.tab(pinHome.id)], "Each saved child keeps a fresh home in its exact former slot")
            #expect(store.state.selectionBySpace[other.id.uuidString] == [favHome.id], "Another Space's remembered Favorite follows the saved home")
            #expect(store.activeSplitLayout?.id == todayGroup.id && store.activeSplitLayout?.tabIDs == todayGroup.tabIDs, "The Today group keeps its identity, order and selection")
            #expect(try BrowserStoreTestsSupport.tab(stray.id, in: store).kind == .favorite
                       && store.state.splitLayouts.contains { $0.id == favoriteAnchored.id && $0.tabIDs == favoriteAnchored.tabIDs }, "A Favorite-anchored group stays in the tray and its Today child joins topApps")
            let favoritePairs = store.state.splitLayouts.filter { $0.tabIDs.contains(x.id) }
            #expect(favoritePairs.count == 1 && favoritePairs[0].id == newer.id && favoritePairs[0].widthFactors == newer.widthFactors, "Per-Space copies of the same Favorites become one Profile-wide split")
            #expect(store.state.splitLayouts.allSatisfy { group in
                guard let box = SplitMembership.container(of: group, in: store.state) else { return false }
                return group.tabIDs.allSatisfy { id in store.state.tabs.first { $0.id == id }.map { SplitMembership.conforms($0, to: box) } ?? false }
            }, "Every group's children share their split's container")
        }
    }

    @Test @MainActor static func normalizedLegacyMixedSplitsPersistAcrossRestart() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let now = try seedLegacyMixedSplit(in: directory).now
            let store = try BrowserStore(directory: directory, now: { now })
            let migrated = store.state
            let again = try BrowserStore(directory: directory, now: { now })
            #expect(again.state == migrated, "The migrated form is persisted and stable on the next restart")
        }
    }

    private struct LegacySharedFavorite {
        let now: Date
        let favoriteSplit: BrowserSplitLayout
        let shared: BrowserTab
        let partner: BrowserTab
        let mixed: BrowserSplitLayout
        let t1: BrowserTab
        let t2: BrowserTab
        let roaming: BrowserTab
        let trayFromSecond: SidebarContainerLocation
        let rootsBefore: Int
    }

    private static func seedLegacySharedFavorite(in directory: URL) throws -> LegacySharedFavorite {
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

        return LegacySharedFavorite(now: now, favoriteSplit: favoriteSplit, shared: shared,
                                   partner: partner, mixed: mixed, t1: t1,
                                   t2: t2, roaming: roaming, trayFromSecond: trayFromSecond,
                                   rootsBefore: rootsBefore)
    }

    @Test @MainActor static func migratingSharedFavoritesKeepsTheTraySplitAndRepairsTheOtherSplit() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let fixture = try seedLegacySharedFavorite(in: directory)
            let now = fixture.now
            let favoriteSplit = fixture.favoriteSplit
            let shared = fixture.shared
            let partner = fixture.partner
            let mixed = fixture.mixed
            let t1 = fixture.t1
            let t2 = fixture.t2
            let roaming = fixture.roaming
            let trayFromSecond = fixture.trayFromSecond
            let rootsBefore = fixture.rootsBefore
            let store = try BrowserStore(directory: directory, now: { now })
            #expect(store.state.splitLayouts.first { $0.id == favoriteSplit.id }?.tabIDs == [shared.id, partner.id], "The Favorites-container split keeps the shared Favorite")
            let kept = store.state.splitLayouts.first { $0.id == mixed.id }
            #expect(kept?.tabIDs == [t1.id, t2.id] && kept?.customTitle == "Kept title", "The other split keeps its own children, layout and title")
            #expect(try BrowserStoreTestsSupport.tab(shared.id, in: store).kind == .favorite, "The shared Favorite stays a Favorite")
            let roamingHome = try BrowserStoreTestsSupport.expectHome(of: roaming.id, in: store, savedURL: "https://roaming.example")
            #expect(try store.state.selectedTabIDs == [roamingHome.id] && (try BrowserStoreTestsSupport.tab(roaming.id, in: store)).kind == .today, "The active selection in another Space follows the moved Favorite's home")
            let rootsAfter = SidebarHierarchy.children(in: trayFromSecond, state: store.state).count
            #expect(rootsBefore == 12 && rootsAfter == rootsBefore, "Migration adds no Favorites root past twelve")
        }
    }

    @Test @MainActor static func resolvedSharedFavoritesStayStableAcrossRestart() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let now = try seedLegacySharedFavorite(in: directory).now
            let store = try BrowserStore(directory: directory, now: { now })
            let again = try BrowserStore(directory: directory, now: { now })
            #expect(again.state == store.state, "The resolved form is persisted and stable")
        }
    }
}
