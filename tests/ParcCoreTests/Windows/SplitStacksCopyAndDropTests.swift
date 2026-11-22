import Foundation
import Testing
@testable import ParcCore

struct SplitStacksCopyAndDropTests {
    private typealias Fixture = SplitStacksTestsSupport.Fixture

    @MainActor private final class Copies {
        let f: Fixture
        let urls: [UUID: String]

        init() throws {
            f = try Fixture("copies")
            urls = Dictionary(uniqueKeysWithValues: f.ids.map { ($0, "https://copy.test/" + $0.uuidString) })
        }
    }

    @MainActor @Test func duplicateCarriesTheStacksOntoFreshPaneIdentities() throws {
        let s = try Copies()
        let duplicate = SidebarDuplicateTarget(items: [.split(s.f.layout.id)], spaceID: s.f.space.id, profileID: s.f.profile.id, state: s.f.store.state)!
        let copied = try #require(try s.f.store.duplicateSidebarItems(duplicate, destinations: s.urls))
        let copy = s.f.store.state.splitLayouts.first { $0.id != s.f.layout.id }
        #expect(copy?.stacks == s.f.layout.stacks)
        #expect(copy?.tabIDs == copied.tabIDs)
        #expect(Set(copied.tabIDs).isDisjoint(with: s.f.ids))
    }

    @MainActor @Test func optionDragCopiesCarryTheStacks() throws {
        let s = try Copies()
        let duplicate = SidebarDuplicateTarget(items: [.split(s.f.layout.id)], spaceID: s.f.space.id, profileID: s.f.profile.id, state: s.f.store.state)!
        _ = try s.f.store.duplicateSidebarItems(duplicate, destinations: s.urls)
        let today = SidebarContainerLocation(spaceID: s.f.space.id, folderID: nil, section: .today)
        let target = SidebarItemsCopy(items: [.split(s.f.layout.id)], spaceID: s.f.space.id, profileID: s.f.profile.id, state: s.f.store.state)!
        let result = try s.f.store.copySidebarItems(target, to: today, before: nil, destinations: s.urls)
        #expect(result != nil)
        #expect(s.f.store.state.splitLayouts.filter { $0.stacks == s.f.layout.stacks }.count == 3)
    }

    @MainActor @Test func pinToFolderCopiesCarryTheStacksOntoFreshIDs() throws {
        let profile = BrowserProfile(id: UUID(), name: "Profile")
        let space = BrowserSpace(id: UUID(), name: "Source", symbol: "circle", color: "000000", profileID: profile.id)
        let folder = BrowserFolder(id: UUID(), spaceID: space.id, name: "Destination", isExpanded: false)
        let ids = [UUID(), UUID(), UUID()]
        let layout = SplitStacksTestsSupport.stacked(ids, space: space.id, sizes: [2, 1], slots: [0.4, 0.6], stacks: [[0.3, 0.7], [1]])
        var state = BrowserState(profiles: [profile], spaces: [space], activeSpaceID: space.id)
        state.folders = [folder]
        state.tabs = SplitStacksTestsSupport.tabs(ids, space: space.id, profile: profile.id, kind: .pinned, url: "https://p.test", title: "P")
        state.splitLayouts = [layout]
        let source = CommandBarFolderMoveSource(items: [.split(layout.id)], spaceID: space.id, profileID: profile.id, state: state)!
        let move = CommandBarFolderMove.snapshot(source: source, state: state).first { $0.folder.folderID == folder.id }!
        let commandCopy = CommandBarFolderCopy(move: move, destinations: Dictionary(uniqueKeysWithValues: ids.map { ($0, "https://c.test") }),
                                               state: state, now: Date())!
        #expect(commandCopy.groups.count == 1)
        #expect(commandCopy.groups[0].stacks == layout.stacks)
        #expect(Set(commandCopy.groups[0].tabIDs).isDisjoint(with: ids))
    }

    @MainActor private func favoriteSplit(_ f: Fixture) throws -> (favoriteID: UUID, request: FavoriteSplitRequest) {
        let favoriteID = f.store.open("https://favorite.test/", kind: .favorite)
        f.store.setSplit(f.ids)
        let favorite = f.store.state.tabs.first { $0.id == favoriteID }!
        let request = try #require(FavoriteSplitRequest(favorite: favorite, spaceID: f.space.id, selection: f.ids, focusedID: f.b,
                                                        state: f.store.state, homeIDs: [favoriteID: UUID()]))
        return (favoriteID, request)
    }

    @MainActor @Test func aFavoriteJoinsAfterTheFocusedPanesWholeSlot() throws {
        let f = try Fixture("favorite")
        let s = try favoriteSplit(f)
        #expect(s.request.paneIDs == [f.a, f.b, f.c, s.favoriteID])
    }

    @MainActor @Test func aFavoriteJoinsTheStackedSplitAndKeepsTheStackIntact() throws {
        let f = try Fixture("favorite")
        let s = try favoriteSplit(f)
        #expect(try f.store.commitFavoriteSplit(s.request) == s.favoriteID)
        let layout = f.store.activeSplitLayout
        #expect(layout?.tabIDs == [f.a, f.b, f.c, s.favoriteID])
        #expect(layout?.stacks?.slotSizes == [1, 2, 1])
        #expect(SplitStacksTestsSupport.close(layout!.stacks!.stackFactors[1], [0.25, 0.75]))
    }

    @MainActor @Test func openInSplitViewStillRefusesAtFourPanes() throws {
        let f = try Fixture("favorite")
        let s = try favoriteSplit(f)
        _ = try f.store.commitFavoriteSplit(s.request)
        #expect(!f.store.insertCommandBarSplit(after: f.b, expectedSelection: f.store.state.selectedTabIDs, tabID: UUID(), newURL: URL(string: "https://pane.test/")))
    }

    @MainActor @Test func commandBarHomesSeeTheMainRowInsertion() throws {
        let f = try Fixture("command-bar")
        #expect(f.store.commandBarSplitHomes(after: f.b, expectedSelection: f.ids, tabID: UUID(), isNew: true) == [])
    }

    @MainActor @Test func openInSplitViewAddsAMainRowSlotAfterTheFocusedPanesStack() throws {
        let f = try Fixture("command-bar")
        let pane = UUID()
        #expect(f.store.insertCommandBarSplit(after: f.b, expectedSelection: f.ids, tabID: pane, newURL: URL(string: "https://pane.test/")))
        #expect(f.store.state.selectedTabIDs == [f.a, f.b, f.c, pane])
        #expect(f.store.activeSplitLayout?.stacks?.slotSizes == [1, 2, 1])
    }

    @MainActor private func withOther(_ f: Fixture) -> (other: UUID, layout: BrowserSplitLayout) {
        let other = f.store.open("https://other.test/")
        f.store.setSplit(f.ids)
        return (other, f.store.activeSplitLayout!)
    }

    @MainActor @Test func aMainRowDropInsideAStackRefuses() throws {
        let f = try Fixture("drops")
        let s = withOther(f)
        #expect(!f.store.dropTabIntoSplit(s.other, expectedSelection: f.ids, expectedLayout: s.layout, target: .insert(2), orientation: .horizontal))
    }

    @MainActor @Test func aDropCannotFlipAStackedSplit() throws {
        let f = try Fixture("drops")
        let s = withOther(f)
        #expect(!f.store.dropTabIntoSplit(s.other, expectedSelection: f.ids, expectedLayout: s.layout, target: .insert(1), orientation: .vertical))
    }

    @MainActor @Test func replacingAStackedPaneKeepsItsSlotStackPositionAndWeights() throws {
        let f = try Fixture("drops")
        let s = withOther(f)
        let replaced = SplitDropTransaction.make(source: s.other, selection: f.ids, layout: s.layout, target: .replace(2),
                                                 orientation: .horizontal, spaceID: f.space.id)
        #expect(replaced?.tabIDs == [f.a, f.b, s.other])
        #expect(replaced?.stacks == s.layout.stacks)
        #expect(replaced?.id == s.layout.id)
    }

    @MainActor @Test func aMainRowDropAtASlotEdgeCommitsAWholeSlot() throws {
        let f = try Fixture("drops")
        let s = withOther(f)
        #expect(f.store.dropTabIntoSplit(s.other, expectedSelection: f.ids, expectedLayout: s.layout, target: .insert(1), orientation: .horizontal))
        #expect(f.store.state.selectedTabIDs == [f.a, s.other, f.b, f.c])
        #expect(f.store.activeSplitLayout?.stacks?.slotSizes == [1, 1, 2])
    }

    @MainActor @Test func aPerpendicularDropStacksTheDroppedTabAbovethePane() throws {
        let f = try Fixture("stack-drop")
        let s = withOther(f)
        #expect(f.store.dropTabIntoSplit(s.other, expectedSelection: f.ids, expectedLayout: s.layout, target: .stack(0, after: false), orientation: .vertical))
        #expect(f.store.state.selectedTabIDs == [s.other, f.a, f.b, f.c])
        #expect(f.store.activeSplitLayout?.stacks?.slotSizes == [2, 2])
        #expect(f.store.activeSplitLayout?.orientation == .horizontal)
    }

    @MainActor @Test func anExternalLinkDropCanStack() throws {
        let f = try Fixture("external")
        let tab = UUID()
        #expect(try f.store.dropExternalURLIntoSplit(URL(string: "https://link.test/")!, tabID: tab, spaceID: f.space.id,
            profileID: f.profile.id, expectedSelection: f.ids, expectedLayout: f.store.activeSplitLayout!,
            target: .stack(2, after: true), orientation: .horizontal, creation: nil))
        #expect(f.store.state.selectedTabIDs == [f.a, f.b, f.c, tab])
        #expect(f.store.activeSplitLayout?.stacks?.slotSizes == [1, 3])
    }
}
