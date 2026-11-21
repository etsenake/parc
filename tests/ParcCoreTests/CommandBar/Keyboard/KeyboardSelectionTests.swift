import Foundation
import Testing
@testable import ParcCore

struct KeyboardSelectionTests {
    final class Fixture {
        var state: BrowserState
        let space: UUID
        let profile: UUID
        let expanded: BrowserFolder
        let nested: BrowserFolder
        let collapsed: BrowserFolder
        let favorite: BrowserTab
        let pinned: BrowserTab
        let folderTab: BrowserTab
        let nestedTab: BrowserTab
        let hidden: BrowserTab
        let today: BrowserTab

        init() {
            let start = BrowserState.initial()
            state = start
            let space = start.activeSpaceID, profile = start.profiles[0].id
            self.space = space
            self.profile = profile
            func tab(_ name: String, _ kind: TabKind = .today, folder: UUID? = nil) -> BrowserTab {
                .init(id: UUID(), spaceID: space, profileID: profile, url: "https://example.invalid/\(name)", title: name,
                      kind: kind, folderID: folder, createdAt: .distantPast, lastAccessed: .distantPast,
                      archivedAt: nil, savedURL: "", savedTitle: "")
            }
            expanded = BrowserFolder(id: UUID(), spaceID: space, name: "Expanded", parentID: nil)
            nested = BrowserFolder(id: UUID(), spaceID: space, name: "Nested", parentID: expanded.id)
            collapsed = BrowserFolder(id: UUID(), spaceID: space, name: "Collapsed", parentID: nil, isExpanded: false)
            favorite = tab("favorite", .favorite)
            pinned = tab("pinned", .pinned)
            folderTab = tab("folder", .pinned, folder: expanded.id)
            nestedTab = tab("nested", .pinned, folder: nested.id)
            hidden = tab("hidden", .pinned, folder: collapsed.id)
            today = tab("today")
            var archived = tab("archived")
            archived.archivedAt = Date()
            var foreign = tab("foreign")
            foreign.profileID = UUID()
            state.tabs = [today, favorite, pinned, folderTab, nestedTab, hidden, archived, foreign]
            state.folders = [expanded, nested, collapsed]
        }

        func items(_ selection: [UUID] = [], unavailable: Set<UUID> = []) -> [RecentTabOrder.Item] {
            PositionalTabNavigation.items(state: state, spaceID: space, selected: selection, focused: selection.last,
                                          available: { !unavailable.contains($0) })
        }

        func item(_ tab: BrowserTab, spaceID: UUID? = nil) -> RecentTabOrder.Item {
            .init(tabIDs: [tab.id], focusedTabID: tab.id, spaceID: spaceID ?? space, profileID: profile, orientation: .horizontal)
        }

        func splitPinnedAndToday() {
            state.splitLayouts = [.init(spaceID: space, tabIDs: [pinned.id, today.id], orientation: .vertical, widthFactors: [0.4, 0.6])]
        }

        func mixedFolderOrder() {
            let root = SidebarContainerLocation(spaceID: space, folderID: nil, section: .pinned)
            state.sidebarItemOrder[root.key] = [.folder(expanded.id), .tab(pinned.id), .folder(collapsed.id)]
        }

        func nestedFolderOrder() {
            mixedFolderOrder()
            state.sidebarItemOrder[SidebarContainerLocation(spaceID: space, folderID: expanded.id, section: .pinned).key] =
                [.folder(nested.id), .tab(folderTab.id)]
        }

        func copyTarget() -> FolderLinkTarget { .init(folderID: expanded.id, spaceID: space, profileID: profile) }
    }

    @Test func sidebarSectionsExpansionAndProfileArchiveFilteringOrderTheItems() {
        let f = Fixture()
        #expect(f.items().flatMap(\.tabIDs) == [f.favorite.id, f.pinned.id, f.folderTab.id, f.nestedTab.id, f.today.id])
    }

    @Test func forwardWraps() {
        let f = Fixture()
        #expect(PositionalTabNavigation.destination(f.items(), selected: [f.today.id], forward: true)?.tabIDs == [f.favorite.id])
    }

    @Test func backwardWraps() {
        let f = Fixture()
        #expect(PositionalTabNavigation.destination(f.items(), selected: [f.favorite.id], forward: false)?.tabIDs == [f.today.id])
    }

    @Test func aMissingSelectionStartsAtTheFirst() {
        let f = Fixture()
        #expect(PositionalTabNavigation.destination(f.items(), selected: [f.hidden.id], forward: true)?.tabIDs == [f.favorite.id])
    }

    @Test func aMissingReverseSelectionStartsAtTheLast() {
        let f = Fixture()
        #expect(PositionalTabNavigation.destination(f.items(), selected: [], forward: false)?.tabIDs == [f.today.id])
    }

    @Test func anEmptyListHasNoDestination() {
        #expect(PositionalTabNavigation.destination([], selected: [], forward: true) == nil)
    }

    @Test func aTabWhoseNativeOwnerIsUnavailableIsLeftOut() {
        let f = Fixture()
        #expect(!f.items(unavailable: [f.pinned.id]).flatMap(\.tabIDs).contains(f.pinned.id))
    }

    @Test func excludedFavoritesLeaveTheOrdering() {
        let f = Fixture()
        let withoutFavorites = PositionalTabNavigation.items(state: f.state, spaceID: f.space, selected: [], focused: nil,
                                                             includeFavorites: false, available: { _ in true })
        #expect(withoutFavorites.flatMap(\.tabIDs) == [f.pinned.id, f.folderTab.id, f.nestedTab.id, f.today.id])
    }

    @Test func itemOneStartsWithFavorites() {
        let f = Fixture()
        #expect(NumberedTarget.destination(f.items(), number: 1, ninthItemEnabled: false)?.tabIDs == [f.favorite.id])
    }

    @Test func itemOneComesAfterFavoritesWhenTheyAreExcluded() {
        let f = Fixture()
        let withoutFavorites = PositionalTabNavigation.items(state: f.state, spaceID: f.space, selected: [], focused: nil,
                                                             includeFavorites: false, available: { _ in true })
        #expect(NumberedTarget.destination(withoutFavorites, number: 1, ninthItemEnabled: false)?.tabIDs == [f.pinned.id])
    }

    @Test func pastTheEndSelectsNothing() {
        let f = Fixture()
        #expect(NumberedTarget.destination(f.items(), number: 6, ninthItemEnabled: false) == nil)
    }

    @Test func itemNineIsTheLastItem() {
        let f = Fixture()
        #expect(NumberedTarget.destination(f.items(), number: 9, ninthItemEnabled: false)?.tabIDs == [f.today.id])
    }

    @Test func theNinthItemSettingIndexesTheNinth() {
        let f = Fixture()
        #expect(NumberedTarget.destination(f.items(), number: 9, ninthItemEnabled: true) == nil)
    }

    @Test func onlyTagsOneThroughNineJump() {
        let f = Fixture()
        #expect(NumberedTarget.destination(f.items(), number: 0, ninthItemEnabled: false) == nil)
        #expect(NumberedTarget.destination(f.items(), number: 10, ninthItemEnabled: false) == nil)
    }

    @Test func bindingIDsParseToTheirNumbers() {
        #expect(NumberedTarget.itemNumber("item9") == 9)
        #expect(NumberedTarget.itemNumber("item10") == nil)
        #expect(NumberedTarget.itemNumber("item01") == nil)
        #expect(NumberedTarget.spaceNumber("space3") == 3)
        #expect(NumberedTarget.spaceNumber("space10") == 10)
        #expect(NumberedTarget.spaceNumber("space0") == nil)
    }

    @Test func descriptionsExplainTheJump() {
        #expect(NumberedTarget.description(for: "item2", excludeFavorites: false, ninthItemEnabled: false)
                == "Jumps to the second item in your Sidebar, starting with your Favorites at the top.")
        #expect(NumberedTarget.description(for: "item9", excludeFavorites: true, ninthItemEnabled: false)
                == "Jumps to the last item at the bottom of your Sidebar.")
        #expect(NumberedTarget.description(for: "item9", excludeFavorites: true, ninthItemEnabled: true)
                == "Jumps to the ninth item in your Sidebar, after your Favorites at the top.")
        #expect(NumberedTarget.description(for: "space1", excludeFavorites: false, ninthItemEnabled: false)
                == "Jumps over to your 1st Space without needing to swipe.")
    }

    @Test func aSplitIsOnePositionalItemOccupyingItsFirstConstituentPosition() {
        let f = Fixture()
        f.splitPinnedAndToday()
        let grouped = f.items([f.pinned.id, f.today.id])
        #expect(grouped.count == 4)
        #expect(grouped[1].tabIDs == [f.pinned.id, f.today.id])
    }

    @Test func aSplitKeepsItsFocusAndOrientation() {
        let f = Fixture()
        f.splitPinnedAndToday()
        let grouped = f.items([f.pinned.id, f.today.id])
        #expect(grouped[1].focusedTabID == f.today.id)
        #expect(grouped[1].orientation == .vertical)
    }

    @Test func anUnavailableSplitIsNotBrokenIntoADifferentSelection() {
        let f = Fixture()
        f.splitPinnedAndToday()
        #expect(!f.items(unavailable: [f.today.id]).flatMap(\.tabIDs).contains(f.pinned.id))
    }

    @Test func aTypedGroupIsPlacedAtItsStableSidebarAnchor() {
        let f = Fixture()
        f.splitPinnedAndToday()
        f.state.splitLayouts[0].sidebarAnchorID = f.today.id
        #expect(f.items().last?.tabIDs == [f.pinned.id, f.today.id])
    }

    @Test func aCollapsedAncestorHidesDescendants() {
        let f = Fixture()
        f.state.folders[0].isExpanded = false
        #expect(!f.items().flatMap(\.tabIDs).contains(f.nestedTab.id))
    }

    @Test func favoritesStayOutsideTheSameSpaceFolderOrder() {
        let f = Fixture()
        f.mixedFolderOrder()
        #expect(f.items().first?.tabIDs == [f.favorite.id])
    }

    @Test func keyboardTraversalFollowsMixedFolderBeforeTabOrder() {
        let f = Fixture()
        f.mixedFolderOrder()
        #expect(f.items().dropFirst().first?.tabIDs == [f.folderTab.id])
    }

    @Test func nestedFolderBeforeTabOrderIsTraversedRecursively() {
        let f = Fixture()
        f.nestedFolderOrder()
        #expect(f.items().dropFirst().first?.tabIDs == [f.nestedTab.id])
    }

    @Test func copyAllLinksFollowsTheExactMixedChildOrder() {
        let f = Fixture()
        f.nestedFolderOrder()
        #expect(FolderLinks.links(in: f.state, target: f.copyTarget())?.map(\.tabID) == [f.nestedTab.id, f.folderTab.id])
    }

    @Test func aCollapsedDisclosureDoesNotChangeTheCopiedOrder() {
        let f = Fixture()
        f.nestedFolderOrder()
        let copied = FolderLinks.links(in: f.state, target: f.copyTarget())
        f.state.folders[0].isExpanded = false
        #expect(FolderLinks.links(in: f.state, target: f.copyTarget()) == copied)
    }

    @Test func aFolderOwnsItsAnchoredSplitAsOneOrderedOriginalChildContainer() {
        let f = Fixture()
        f.nestedFolderOrder()
        f.state.splitLayouts = [.init(spaceID: f.space, tabIDs: [f.folderTab.id, f.today.id], widthFactors: [0.5, 0.5])]
        #expect(FolderLinks.links(in: f.state, target: f.copyTarget())?.map(\.tabID) == [f.nestedTab.id, f.folderTab.id, f.today.id])
    }

    @Test func separatingASplitRetainsTheAnchorsEstablishedMixedSlot() {
        let f = Fixture()
        f.nestedFolderOrder()
        f.state.splitLayouts = []
        #expect(f.items().dropFirst().prefix(3).flatMap(\.tabIDs) == [f.nestedTab.id, f.folderTab.id, f.pinned.id])
    }

    struct History {
        let f = Fixture()
        let space: UUID
        let a: RecentTabOrder.Item, b: RecentTabOrder.Item, c: RecentTabOrder.Item, d: RecentTabOrder.Item
        let otherSpace = UUID()
        let anyItem: (RecentTabOrder.Item) -> Bool = { _ in true }

        init() {
            space = f.space
            a = f.item(f.favorite)
            b = f.item(f.pinned)
            c = f.item(f.today)
            d = f.item(f.folderTab)
        }

        func back(_ history: inout TabSelectionHistory) -> RecentTabOrder.Item? {
            history.move(in: space, forward: false, available: anyItem)
        }

        func recorded() -> TabSelectionHistory {
            var history = TabSelectionHistory()
            [a, b, c].forEach { history.record($0) }
            return history
        }

        func backedUpAndReselected() -> TabSelectionHistory {
            var history = recorded()
            _ = back(&history)
            history.record(b)
            return history
        }

        func atFirst() -> TabSelectionHistory {
            var history = backedUpAndReselected()
            _ = back(&history)
            return history
        }

        func branched() -> TabSelectionHistory {
            var history = atFirst()
            _ = history.move(in: space, forward: true, available: { $0.id != b.id })
            _ = back(&history)
            history.record(d)
            return history
        }

        func withOtherSpace() -> TabSelectionHistory {
            var history = branched()
            _ = back(&history)
            history.record(f.item(f.today, spaceID: otherSpace))
            history.record(f.item(f.folderTab, spaceID: otherSpace))
            return history
        }
    }

    @Test func thereIsNoFabricatedInitialHistory() {
        let h = History()
        #expect(TabSelectionHistory().destination(in: h.space, forward: false, available: h.anyItem) == nil)
    }

    @Test func historyDoesNotWrapForward() {
        let h = History()
        #expect(h.recorded().destination(in: h.space, forward: true, available: h.anyItem) == nil)
    }

    @Test func historyGoesBackward() {
        let h = History()
        var history = h.recorded()
        #expect(h.back(&history)?.id == h.b.id)
    }

    @Test func theSelectionCallbackDoesNotAppendADuplicateOrTruncateForward() {
        let h = History()
        #expect(h.backedUpAndReselected().destination(in: h.space, forward: true, available: h.anyItem)?.id == h.c.id)
    }

    @Test func historyReachesTheFirst() {
        let h = History()
        var history = h.backedUpAndReselected()
        #expect(h.back(&history)?.id == h.a.id)
    }

    @Test func historyDoesNotWrapBackward() {
        let h = History()
        var history = h.atFirst()
        #expect(h.back(&history) == nil)
    }

    @Test func aMissingOrClosedItemIsSkipped() {
        let h = History()
        var history = h.atFirst()
        #expect(history.move(in: h.space, forward: true, available: { $0.id != h.b.id })?.id == h.c.id)
    }

    @Test func aNewSelectionTruncatesTheForwardBranch() {
        let h = History()
        #expect(h.branched().destination(in: h.space, forward: true, available: h.anyItem) == nil)
    }

    @Test func aBranchKeepsPriorEntries() {
        let h = History()
        var history = h.branched()
        #expect(h.back(&history)?.id == h.b.id)
    }

    @Test func eachSpaceOwnsAnIndependentStack() {
        let h = History()
        #expect(h.withOtherSpace().destination(in: h.otherSpace, forward: false, available: h.anyItem)?.id == h.c.id)
    }

    @Test func anotherSpaceLeavesTheOriginalCursor() {
        let h = History()
        #expect(h.withOtherSpace().destination(in: h.space, forward: false, available: h.anyItem)?.id == h.a.id)
    }

    @Test func aRefusedNativeSelectionCanRestoreTheCursor() {
        let h = History()
        var history = h.withOtherSpace()
        let rollback = history
        _ = h.back(&history)
        history = rollback
        #expect(history.destination(in: h.space, forward: true, available: h.anyItem)?.id == h.d.id)
    }
}
