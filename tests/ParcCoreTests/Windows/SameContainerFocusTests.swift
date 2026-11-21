import Foundation
import Testing
@testable import ParcCore

@MainActor
struct SameContainerFocusTests {
    struct Fixture {
        var state = BrowserState.initial()
        let space: BrowserSpace
        let profile: UUID
        let other: BrowserSpace
        let previous: BrowserTab
        let neighbor: BrowserTab
        let current: BrowserTab
        let next: BrowserTab

        init() {
            space = state.spaces[0]
            profile = space.profileID
            other = BrowserSpace(id: UUID(), name: "Other", symbol: "circle", color: "123456", profileID: space.profileID)
            state.spaces.append(other)
            previous = Self.tab(space: space.id, profile: profile)
            neighbor = Self.tab(space: space.id, profile: profile)
            current = Self.tab(space: space.id, profile: profile)
            next = Self.tab(space: space.id, profile: profile)
            state.tabs = [previous, neighbor, current, next]
            state.selectedTabIDs = [current.id]
            state.selectionBySpace[space.id.uuidString] = [current.id]
        }

        static func tab(kind: TabKind = .today, space: UUID, profile: UUID) -> BrowserTab {
            BrowserTab(id: UUID(), spaceID: space, profileID: profile,
                       url: "https://example.test/", title: "Original", kind: kind, folderID: nil,
                       createdAt: Date(timeIntervalSince1970: 1), lastAccessed: Date(timeIntervalSince1970: 1),
                       savedURL: "https://example.test/", savedTitle: "Original")
        }

        func choose(_ input: BrowserState? = nil, remembered: UUID?? = nil, removed: Set<UUID>? = nil,
                    pool: Set<UUID> = [], unavailable: Set<UUID> = []) -> FolderRemovalSelection? {
            FolderRemovalSelection.resolve(removing: removed ?? [current.id], spaceID: space.id,
                profileID: profile, state: input ?? state, selected: [current.id], focused: current.id,
                referrerPool: pool, previouslySelectedItemID: remembered ?? previous.id,
                available: { !unavailable.contains($0) })
        }

        func closeSplitPane(_ closing: BrowserTab) -> FolderRemovalSelection? {
            FolderRemovalSelection.resolve(removing: [closing.id], spaceID: space.id, profileID: profile, state: state,
                selected: [previous.id, neighbor.id, current.id], focused: closing.id, available: { _ in true })
        }

        func favoriteAcrossSpaces() -> BrowserState {
            var favorites = state
            favorites.tabs[0].spaceID = other.id
            favorites.tabs[2].kind = .favorite
            return favorites
        }
    }

    @Test func restorationDoesNotFabricateThePreviousItem() {
        let f = Fixture()
        #expect(WindowPresentation(state: f.state, ready: true).previouslySelectedItemID == nil)
    }

    @Test func aRealSelectionRecordsTheOriginalOutgoingItemAndARefreshDoesNotOverwriteIt() {
        let f = Fixture()
        var origin = WindowPresentation(state: f.state, ready: true)
        origin.recordSelectionForReturn(f.previous.id, state: f.state)
        #expect(origin.previouslySelectedItemID == f.current.id)
        origin.recordSelectionForReturn(f.previous.id, state: f.state)
        #expect(origin.previouslySelectedItemID == f.current.id)
    }

    @Test func anUnresolvedOrNilIncomingItemLeavesTheRememberedValueAlone() {
        let f = Fixture()
        var origin = WindowPresentation(state: f.state, ready: true)
        origin.recordSelectionForReturn(f.previous.id, state: f.state)
        origin.recordSelectionForReturn(UUID(), state: f.state)
        #expect(origin.previouslySelectedItemID == f.current.id)
        origin.recordSelectionForReturn(nil, state: f.state)
        #expect(origin.previouslySelectedItemID == f.current.id)
    }

    @Test func aSelectionWithNoOriginalOutgoingItemClearsThePrevious() {
        let f = Fixture()
        var origin = WindowPresentation(state: f.state, ready: true)
        origin.recordSelectionForReturn(f.previous.id, state: f.state)
        origin.recordSelectionForReturn(f.previous.id, state: f.state)
        origin.recordSelectionForReturn(UUID(), state: f.state)
        origin.recordSelectionForReturn(nil, state: f.state)
        origin.recordSelectionForReturn(f.next.id, state: f.state)
        #expect(origin.previouslySelectedItemID == nil)
    }

    @Test func anotherPhysicalWindowDoesNotAcquireSelectionHistory() {
        let f = Fixture()
        var origin = WindowPresentation(state: f.state, ready: true)
        let peer = WindowPresentation(state: f.state, ready: true)
        origin.recordSelectionForReturn(f.previous.id, state: f.state)
        #expect(peer.previouslySelectedItemID == nil)
    }

    @Test func theActualPreviousItemPrecedesTheAdjacentFallback() {
        let f = Fixture()
        #expect(f.choose()?.tabIDs == [f.previous.id])
        #expect(f.choose()?.replacementSpaceID == f.space.id)
    }

    @Test func closingTheFocusedLastPaneFocusesTheNewLastPane() {
        let f = Fixture()
        #expect(f.closeSplitPane(f.current)?.tabIDs == [f.previous.id, f.neighbor.id])
        #expect(f.closeSplitPane(f.current)?.focusedTabID == f.neighbor.id)
    }

    @Test func closingTheFocusedMiddlePaneFocusesThePaneThatTakesItsPlace() {
        let f = Fixture()
        #expect(f.closeSplitPane(f.neighbor)?.tabIDs == [f.previous.id, f.current.id])
        #expect(f.closeSplitPane(f.neighbor)?.focusedTabID == f.current.id)
    }

    @Test func noRememberedItemKeepsThePreviousNeighborFallback() {
        let f = Fixture()
        #expect(f.choose(remembered: .some(nil))?.tabIDs == [f.neighbor.id])
    }

    @Test func aMissingRememberedItemDoesNotResurrect() {
        let f = Fixture()
        #expect(f.choose(remembered: UUID())?.tabIDs == [f.neighbor.id])
    }

    @Test func theClosingItemCannotBecomeItsOwnReplacement() {
        let f = Fixture()
        #expect(f.choose(remembered: f.current.id)?.tabIDs == [f.neighbor.id])
    }

    @Test func anotherOwnersPageIsNotReclaimed() {
        let f = Fixture()
        #expect(f.choose(unavailable: [f.previous.id])?.tabIDs == [f.neighbor.id])
    }

    @Test func theWholeClosingSetExcludesRememberedItems() {
        let f = Fixture()
        #expect(f.choose(removed: [f.previous.id, f.current.id])?.tabIDs == [f.neighbor.id])
    }

    @Test func anArchivedItemCannotBeSelected() {
        var f = Fixture()
        f.state.tabs[0].archivedAt = Date()
        #expect(f.choose()?.tabIDs == [f.neighbor.id])
    }

    @Test func profileIsolationAppliesBeforeAnyReturn() {
        var f = Fixture()
        f.state.tabs[0].profileID = UUID()
        #expect(f.choose()?.tabIDs == [f.neighbor.id])
    }

    @Test func twoNormalSpaceContainersMustHaveTheSameSpaceID() {
        var f = Fixture()
        f.state.tabs[0].spaceID = f.other.id
        #expect(f.choose()?.tabIDs == [f.neighbor.id])
    }

    @Test func differentNestedFoldersAndTodayBelongToTheSameOuterSpace() {
        var f = Fixture()
        let first = BrowserFolder(id: UUID(), spaceID: f.space.id, name: "First")
        let second = BrowserFolder(id: UUID(), spaceID: f.space.id, name: "Nested", parentID: first.id)
        f.state.folders = [first, second]
        f.state.tabs[0].kind = .pinned
        f.state.tabs[0].folderID = second.id
        #expect(f.choose()?.tabIDs == [f.previous.id])
    }

    @Test func aGenuineAdjacentChildPrecedesThePreviousSelectedFallback() {
        var f = Fixture()
        f.state.tabs[1].referrerID = f.current.id
        #expect(f.choose()?.tabIDs == [f.neighbor.id])
    }

    @Test func theCreationActivePoolBranchStillWins() {
        var f = Fixture()
        f.state.tabs[2].activeTabBeforeCreationID = f.next.id
        #expect(f.choose(pool: [f.next.id])?.tabIDs == [f.next.id])
    }

    @Test func aFavoriteCanReturnToThePriorOriginalTabInAnotherSpaceOfTheSameProfile() throws {
        let f = Fixture()
        let cross = try #require(f.choose(f.favoriteAcrossSpaces()))
        #expect(cross.tabIDs == [f.previous.id] && cross.replacementSpaceID == f.other.id)
        #expect(cross.spaceID == f.space.id && cross.original == [f.current.id])
    }

    @Test func returningToAProfileWideFavoritePreservesTheCurrentSpace() {
        var f = Fixture()
        f.state.tabs[0].spaceID = f.other.id
        f.state.tabs[0].kind = .favorite
        #expect(f.choose()?.tabIDs == [f.previous.id])
        #expect(f.choose()?.replacementSpaceID == f.space.id)
    }

    @Test func twoFavoritesCompareProfileAndRetainTheCurrentSpace() {
        var f = Fixture()
        var favorites = f.favoriteAcrossSpaces()
        favorites.tabs[0].kind = .favorite
        f.state = favorites
        #expect(f.choose()?.replacementSpaceID == f.space.id)
    }

    @Test func aRemovedDestinationSpaceInvalidatesTheRememberedItem() {
        let f = Fixture()
        var missing = f.favoriteAcrossSpaces()
        missing.spaces.removeAll { $0.id == f.other.id }
        #expect(f.choose(missing)?.tabIDs != [f.previous.id])
    }

    func splitFixture() -> (Fixture, BrowserState, BrowserSplitLayout, BrowserTab) {
        let f = Fixture()
        var split = f.favoriteAcrossSpaces()
        let partner = Fixture.tab(space: f.other.id, profile: f.profile)
        split.tabs.append(partner)
        let group = BrowserSplitLayout(spaceID: f.other.id, tabIDs: [partner.id, f.previous.id],
                                       orientation: .vertical, widthFactors: [0.3, 0.7])
        split.splitLayouts = [group]
        return (f, split, group, partner)
    }

    @Test func thePreviousPaneReturnsTheOriginalWholeSplitWithItsFocusedChild() throws {
        let (f, split, group, _) = splitFixture()
        let decision = try #require(f.choose(split))
        #expect(decision.tabIDs == group.tabIDs && decision.focusedTabID == f.previous.id)
    }

    @Test func oneUnavailablePaneExcludesTheWholeSplit() {
        let (f, split, group, partner) = splitFixture()
        #expect(f.choose(split, unavailable: [partner.id])?.tabIDs != group.tabIDs)
    }

    @Test func aMalformedOriginalSplitIsNotRepairedByCloseFocus() {
        var (f, split, group, _) = splitFixture()
        split.splitLayouts[0].widthFactors = [0, 0]
        #expect(f.choose(split)?.tabIDs != group.tabIDs)
        f.state = split
    }

    @Test func theOriginalWindowAppliesTheCompleteCrossSpaceSplitReceipt() throws {
        let (f, split, group, _) = splitFixture()
        let decision = try #require(f.choose(split))
        var window = WindowPresentation(state: split, ready: true)
        window.remove(f.current.id)
        let finished = window.finishFolderRemoval(decision, state: split, available: { _ in true })
        #expect(finished)
        #expect(window.previouslySelectedItemID == f.current.id)
        #expect(window.activeSpaceID == f.other.id && window.selectedTabIDs == group.tabIDs)
        #expect(window.preferredFocusedTabID == f.previous.id && window.splitLayout?.widthFactors == [0.3, 0.7])
    }

    @Test func aNewerSelectionWinsOverADelayedCloseCompletion() throws {
        let f = Fixture()
        let favorites = f.favoriteAcrossSpaces()
        let cross = try #require(f.choose(favorites))
        var window = WindowPresentation(state: favorites, ready: true)
        _ = window.selectExistingTab(f.neighbor.id, state: favorites, available: { _ in true })
        let finished = window.finishFolderRemoval(cross, state: favorites, available: { _ in true })
        #expect(!finished)
    }

    @Test func replacementOwnershipIsRecheckedAfterUnload() throws {
        let f = Fixture()
        let favorites = f.favoriteAcrossSpaces()
        let cross = try #require(f.choose(favorites))
        var window = WindowPresentation(state: favorites, ready: true)
        let previous = f.previous.id
        let finished = window.finishFolderRemoval(cross, state: favorites, available: { $0 != previous })
        #expect(!finished)
    }

    @Test func closingTheFinalItemCommitsTheGenuineEmptySelection() throws {
        var f = Fixture()
        f.state.tabs = [f.current]
        let empty = try #require(f.choose(remembered: .some(nil)))
        var window = WindowPresentation(state: f.state, ready: true)
        window.remove(f.current.id)
        let finished = window.finishFolderRemoval(empty, state: f.state, available: { _ in true })
        #expect(finished && window.selectedTabIDs.isEmpty)
    }

    @Test func aSelectionAfterCommittedStartCannotInheritTheRetiredOutgoingItem() throws {
        var f = Fixture()
        let full = f.state
        f.state.tabs = [f.current]
        let empty = try #require(f.choose(remembered: .some(nil)))
        var window = WindowPresentation(state: f.state, ready: true)
        window.remove(f.current.id)
        _ = window.finishFolderRemoval(empty, state: f.state, available: { _ in true })
        window.recordSelectionForReturn(f.next.id, state: full)
        #expect(window.previouslySelectedItemID == nil)
    }
}
