import Foundation
import Testing
@testable import ParcCore

struct SplitSeparateAllSeparationAndFlipTests {
    private typealias Fixture = SplitSeparateAllTestsSupport.Fixture

    private struct Placement: Equatable {
        let id: UUID
        let kind: TabKind
        let folderID: UUID?
        let url: String
    }

    @MainActor private struct Three {
        let a: UUID, b: UUID, c: UUID
        let space: UUID
        let group: BrowserSplitLayout
        let folders: [BrowserFolder]
        let archive: [UUID]
        let history: [BrowserHistoryEntry]
        let placements: [Placement]

        init(_ store: BrowserStore) {
            let a = store.open("https://one.invalid", kind: .pinned)
            let b = store.open("https://two.invalid"), c = store.open("https://three.invalid")
            let folder = store.createFolder(name: "Original")
            store.moveTab(a, toSpace: store.activeSpaceID, folderID: folder)
            store.setSplit([a, b, c])
            store.setSplitLayout(orientation: .vertical, widthFactors: [1, 2, 3])
            self.a = a; self.b = b; self.c = c
            space = store.activeSpaceID
            group = store.activeSplitLayout!
            folders = store.state.folders
            archive = store.state.recentlyClosedIDs
            history = store.state.history
            placements = Three.placements(store)
        }

        static func placements(_ store: BrowserStore) -> [Placement] {
            store.state.tabs.map { Placement(id: $0.id, kind: $0.kind, folderID: $0.folderID, url: $0.url) }
        }
    }

    @MainActor @Test func aMovedSplitSeparatesIntoItsExactSlotInPaneOrder() throws {
        let f = try Fixture()
        let sibling = f.store.open("https://sibling.invalid")
        let firstChild = f.store.open("https://first.invalid"), secondChild = f.store.open("https://second.invalid")
        _ = f.store.open("https://other-sibling.invalid")
        f.store.setSplit([secondChild, firstChild])
        let group = try #require(f.store.activeSplitLayout)
        let snapshot = try #require(SidebarHierarchySnapshot(state: f.store.state, spaceID: f.store.activeSpaceID,
            profileID: f.store.activeSpace.profileID, includesFavorites: true))
        let today = SidebarContainerLocation(spaceID: f.store.activeSpaceID, folderID: nil, section: .today)
        try #require(try f.store.moveSidebarItem(.split(group.id), to: today, before: .tab(sibling), expected: snapshot))
        let order = SidebarTodayArchive.order(in: f.store.state, spaceID: f.store.activeSpaceID)
        #expect(f.store.separateAllTabsFromSplit(expected: group, focusedID: firstChild))
        #expect(SidebarTodayArchive.order(in: f.store.state, spaceID: f.store.activeSpaceID) == order)
    }

    @MainActor @Test func aStaleMembershipReceiptRefusesWithoutMutation() throws {
        let f = try Fixture()
        let three = Three(f.store)
        let stale = BrowserSplitLayout(id: three.group.id, sidebarAnchorID: three.group.sidebarAnchorID, spaceID: three.group.spaceID,
                                       tabIDs: [three.a, three.b], orientation: three.group.orientation, widthFactors: [0.5, 0.5], stacks: nil)
        let before = f.store.state
        #expect(!f.store.separateAllTabsFromSplit(expected: stale, focusedID: three.b))
        #expect(f.store.state == before)
    }

    @MainActor @Test func theDisplayedSplitDissolvesItsContainer() throws {
        let f = try Fixture()
        let three = Three(f.store)
        #expect(f.store.separateAllTabsFromSplit(expected: three.group, focusedID: three.b))
        #expect(!f.store.state.splitLayouts.contains { $0.id == three.group.id })
    }

    @MainActor @Test func theFocusedOriginalStaysDisplayedAlone() throws {
        let f = try Fixture()
        let three = Three(f.store)
        _ = f.store.separateAllTabsFromSplit(expected: three.group, focusedID: three.b)
        #expect(f.store.state.selectedTabIDs == [three.b])
        #expect(f.store.state.selectionBySpace[three.space.uuidString] == [three.b])
    }

    @MainActor @Test func everyChildKeepsItsSavedSectionFolderAndAddress() throws {
        let f = try Fixture()
        let three = Three(f.store)
        _ = f.store.separateAllTabsFromSplit(expected: three.group, focusedID: three.b)
        #expect(Three.placements(f.store) == three.placements)
    }

    @MainActor @Test func theKeptPageIsStampedAsAccessed() throws {
        let f = try Fixture()
        let three = Three(f.store)
        _ = f.store.separateAllTabsFromSplit(expected: three.group, focusedID: three.b)
        #expect(f.store.state.tabs.first { $0.id == three.b }?.lastAccessed == f.now)
    }

    @MainActor @Test func separatingIsNotACloseArchiveOrNavigation() throws {
        let f = try Fixture()
        let three = Three(f.store)
        _ = f.store.separateAllTabsFromSplit(expected: three.group, focusedID: three.b)
        #expect(f.store.state.folders == three.folders)
        #expect(f.store.state.recentlyClosedIDs == three.archive)
        #expect(f.store.state.history == three.history)
    }

    @MainActor @Test func selectionAndDissolutionPersistTogether() throws {
        let f = try Fixture()
        let three = Three(f.store)
        _ = f.store.separateAllTabsFromSplit(expected: three.group, focusedID: three.b)
        let loaded = try f.reopened()
        #expect(loaded.state.selectedTabIDs == [three.b])
        #expect(!loaded.state.splitLayouts.contains { $0.id == three.group.id })
    }

    @MainActor @Test func aFocusOutsideTheSplitKeepsTheFirstChildDisplayed() throws {
        let f = try Fixture()
        let three = Three(f.store)
        #expect(f.store.separateAllTabsFromSplit(expected: three.group, focusedID: UUID()))
        #expect(f.store.state.selectedTabIDs == [three.a])
    }

    @MainActor @Test func aBackgroundSplitSeparates() throws {
        let f = try Fixture()
        let three = Three(f.store)
        f.store.setSplit([three.b, three.c])
        let background = try #require(f.store.activeSplitLayout)
        f.store.setSplit([three.a])
        #expect(f.store.separateAllTabsFromSplit(expected: background, focusedID: three.a))
    }

    @MainActor @Test func aBackgroundSeparationLeavesTheDisplayedSelection() throws {
        let f = try Fixture()
        let three = Three(f.store)
        f.store.setSplit([three.b, three.c])
        let background = try #require(f.store.activeSplitLayout)
        f.store.setSplit([three.a])
        _ = f.store.separateAllTabsFromSplit(expected: background, focusedID: three.a)
        #expect(f.store.state.selectedTabIDs == [three.a])
        #expect(!f.store.state.splitLayouts.contains { $0.id == background.id })
    }

    @MainActor private func flippable(_ f: Fixture) -> (Three, BrowserSplitLayout) {
        let three = Three(f.store)
        f.store.setSplit([three.b, three.c])
        f.store.setSplitLayout(orientation: .horizontal, widthFactors: [1, 3])
        return (three, f.store.activeSplitLayout!)
    }

    @MainActor @Test func theDisplayedSplitFlips() throws {
        let f = try Fixture()
        let (_, shown) = flippable(f)
        #expect(f.store.flipSplitOrientation(expected: shown))
    }

    @MainActor @Test func flippingKeepsProportionsIdentityAndSelection() throws {
        let f = try Fixture()
        let (three, shown) = flippable(f)
        _ = f.store.flipSplitOrientation(expected: shown)
        let flipped = try #require(f.store.activeSplitLayout)
        #expect(flipped.id == shown.id)
        #expect(flipped.orientation == .vertical)
        #expect(flipped.widthFactors == shown.widthFactors)
        #expect(f.store.state.selectedTabIDs == [three.b, three.c])
    }

    @MainActor @Test func aStaleFlipReceiptRefuses() throws {
        let f = try Fixture()
        let (_, shown) = flippable(f)
        _ = f.store.flipSplitOrientation(expected: shown)
        #expect(!f.store.flipSplitOrientation(expected: shown))
    }

    @MainActor @Test func aBackgroundSplitFlipsWithoutChangingTheDisplay() throws {
        let f = try Fixture()
        let (three, shown) = flippable(f)
        _ = f.store.flipSplitOrientation(expected: shown)
        let flipped = try #require(f.store.activeSplitLayout)
        f.store.setSplit([three.a])
        #expect(f.store.flipSplitOrientation(expected: flipped))
        #expect(f.store.state.selectedTabIDs == [three.a])
        #expect(f.store.state.splitLayouts.first { $0.id == flipped.id }?.orientation == .horizontal)
    }

    @MainActor @Test func aFlipPersists() throws {
        let f = try Fixture()
        let (_, shown) = flippable(f)
        _ = f.store.flipSplitOrientation(expected: shown)
        #expect(try f.reopened().state.splitLayouts.first { $0.id == shown.id }?.orientation == .vertical)
    }

    @MainActor private struct TodayOrder {
        let home: UUID, profile: UUID
        let x: UUID, y: UUID, z: UUID
        let order: [UUID]

        init(_ store: BrowserStore) {
            let home = store.activeSpaceID
            self.home = home
            profile = store.activeSpace.profileID
            x = store.open("https://x.invalid"); y = store.open("https://y.invalid"); z = store.open("https://z.invalid")
            order = SidebarTodayArchive.order(in: store.state, spaceID: home)
        }
    }

    @MainActor @Test func newTodayTabsOpenAtTheTopSoSidebarOrderDiffersFromArrayOrder() throws {
        let f = try Fixture()
        let s = TodayOrder(f.store)
        let top = try #require(s.order.firstIndex(of: s.z)), bottom = try #require(s.order.firstIndex(of: s.x))
        #expect(top < bottom)
    }

    @MainActor @Test func theCurrentTodayOrderAdmitsAnArchiveGroup() throws {
        let f = try Fixture()
        let s = TodayOrder(f.store)
        #expect(SidebarTodayArchive.admits(anchorID: s.y, order: s.order, ids: [s.x], state: f.store.state, spaceID: s.home, profileID: s.profile))
    }

    @MainActor @Test func theTabArrayOrderIsNotTheSidebarOrder() throws {
        let f = try Fixture()
        let s = TodayOrder(f.store)
        let arrayOrder = f.store.state.tabs.filter { $0.kind == .today && $0.spaceID == s.home && $0.archivedAt == nil }.map(\.id)
        #expect(!SidebarTodayArchive.admits(anchorID: s.y, order: arrayOrder, ids: [s.x], state: f.store.state, spaceID: s.home, profileID: s.profile))
    }
}
