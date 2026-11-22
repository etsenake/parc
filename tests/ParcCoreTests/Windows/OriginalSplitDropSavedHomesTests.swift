import Foundation
import Testing
@testable import ParcCore

struct OriginalSplitDropSavedHomesTests {
    private typealias Fixture = OriginalSplitDropTestsSupport.Fixture

    @MainActor @Test func draggingAnOriginalIntoASavedPaneFormsAGroupOfTheOriginalIdentities() throws {
        let f = try Fixture()
        let proposed = try #require(f.propose(f.pinned()))
        #expect(proposed.selectedTabIDs == [f.a, f.b])
        #expect(proposed.splitLayouts.count == 1)
    }

    @MainActor @Test func theLivePageKeepsItsRequestAndProvenanceAndMovesToToday() throws {
        let f = try Fixture()
        let pinned = f.pinned()
        let proposed = try #require(f.propose(pinned))
        let live = try #require(proposed.tabs.first { $0.id == f.a })
        #expect(live.url == pinned.tabs[f.aIndex].url)
        #expect(live.title == "Live")
        #expect(live.referrerID == f.b)
        #expect(live.kind == .today)
    }

    @MainActor @Test func theSavedHomeUsesTheSavedAddressAndTitle() throws {
        let f = try Fixture()
        let pinned = f.pinned()
        let proposed = try #require(f.propose(pinned))
        let copy = try #require(proposed.tabs.first { $0.id == f.home })
        #expect(copy.url == pinned.tabs[f.aIndex].savedURL)
        #expect(copy.title == pinned.tabs[f.aIndex].savedTitle)
        #expect(copy.customTitle == "Authored")
    }

    @MainActor @Test func theSavedHomeOwnsAFreshCreationReceipt() throws {
        let f = try Fixture()
        let proposed = try #require(f.propose(f.pinned()))
        let copy = try #require(proposed.tabs.first { $0.id == f.home })
        #expect(copy.referrerID == nil)
        #expect(copy.activeTabBeforeCreationID == f.a)
        #expect(copy.createdAt == f.now)
    }

    @MainActor @Test func theSavedHomeReplacesTheOriginalInItsSidebarSlot() throws {
        let f = try Fixture()
        let proposed = try #require(f.propose(f.pinned()))
        #expect(SidebarHierarchy.children(in: f.pinnedLocation, state: proposed) == [.tab(f.c), .tab(f.home)])
    }

    @MainActor @Test func theExistingOrdinaryTabAnchorsTheNewGroup() throws {
        let f = try Fixture()
        let pinned = f.pinned()
        let proposed = try #require(f.propose(pinned))
        #expect(proposed.splitLayouts[0].sidebarAnchorID == f.b)
        #expect(proposed.tabs[f.bIndex].url == pinned.tabs[f.bIndex].url)
    }

    @MainActor @Test func aMissingHomeRefuses() throws {
        let f = try Fixture()
        #expect(f.propose(f.pinned(), homes: [:]) == nil)
    }

    @MainActor @Test func aHomeCollidingWithTheOriginalRefuses() throws {
        let f = try Fixture()
        #expect(f.propose(f.pinned(), homes: [f.a: f.a]) == nil)
    }

    @MainActor @Test func centerReplacementLeavesTheSavedItemIntact() throws {
        let f = try Fixture()
        let pinned = f.pinned()
        let replaced = try #require(f.propose(pinned, target: .replace(0), homes: [:]))
        #expect(replaced.selectedTabIDs == [f.b])
        #expect(replaced.tabs.first { $0.id == f.a } == pinned.tabs[f.aIndex])
        #expect(replaced.tabs.count == pinned.tabs.count)
        #expect(replaced.splitLayouts.isEmpty)
    }

    @MainActor @Test func groupingTwoSavedItemsKeepsAHomeForEach() throws {
        let f = try Fixture()
        var both = f.pinned()
        both.tabs[f.bIndex].kind = .pinned
        let paired = try #require(f.propose(both, homes: [f.a: f.home, f.b: f.bHome]))
        #expect(paired.tabs.count == both.tabs.count + 2)
        #expect(paired.tabs.filter { [f.a, f.b].contains($0.id) }.allSatisfy { $0.kind == .today })
    }

    @MainActor @Test func twoHomesCannotShareAnIdentity() throws {
        let f = try Fixture()
        var both = f.pinned()
        both.tabs[f.bIndex].kind = .pinned
        #expect(f.propose(both, homes: [f.a: f.home, f.b: f.home]) == nil)
    }

    @MainActor private func sourceGroup(_ f: Fixture) -> (BrowserState, BrowserSplitLayout) {
        var state = f.original
        state.selectedTabIDs = [f.b]
        var old = BrowserSplitLayout(spaceID: f.space, tabIDs: [f.a, f.c], orientation: .vertical, widthFactors: [0.3, 0.7])
        old.customTitle = "Original"
        old.customIcon = .emoji("🌙")
        old.sidebarAnchorID = f.a
        state.splitLayouts = [old]
        state.sidebarItemOrder[f.pinnedLocation.key] = [.tab(f.a)]
        return (state, old)
    }

    @MainActor @Test func draggingAChildOutOfAGroupReplacesItWithItsHomeAndMovesTheAnchor() throws {
        let f = try Fixture()
        let (state, old) = sourceGroup(f)
        let moved = try #require(f.propose(state, source: f.a))
        let kept = try #require(moved.splitLayouts.first { $0.id == old.id })
        #expect(kept.tabIDs == [f.home, f.c])
        #expect(kept.sidebarAnchorID == f.home)
    }

    @MainActor @Test func theSourceGroupKeepsItsGeometryAndAppearance() throws {
        let f = try Fixture()
        let (state, old) = sourceGroup(f)
        let moved = try #require(f.propose(state, source: f.a))
        let kept = try #require(moved.splitLayouts.first { $0.id == old.id })
        #expect(kept.widthFactors == old.widthFactors)
        #expect(kept.orientation == old.orientation)
        #expect(kept.customTitle == old.customTitle)
        #expect(kept.customIcon == old.customIcon)
    }

    @MainActor @Test func theOriginalChildEntersTheDestinationWithoutAClone() throws {
        let f = try Fixture()
        let (state, old) = sourceGroup(f)
        let moved = try #require(f.propose(state, source: f.a))
        #expect(moved.splitLayouts.first { $0.id != old.id }?.tabIDs == [f.b, f.a])
    }

    @MainActor @Test func theSourceGroupKeepsItsSidebarSlot() throws {
        let f = try Fixture()
        let (state, old) = sourceGroup(f)
        let moved = try #require(f.propose(state, source: f.a))
        #expect(SidebarHierarchy.children(in: f.pinnedLocation, state: moved) == [.split(old.id)])
    }

    @MainActor @Test func aMemberIsNotItsOwnDropSource() throws {
        let f = try Fixture()
        let grouped = try #require(f.propose(f.pinned()))
        #expect(f.propose(grouped, source: f.b, target: .insert(0), layout: grouped.splitLayouts[0], homes: [:]) == nil)
    }

    @MainActor @Test func aCrossProfileOriginalRefuses() throws {
        let f = try Fixture()
        var invalid = f.pinned()
        invalid.tabs[f.bIndex].profileID = UUID()
        #expect(f.propose(invalid) == nil)
    }

    @MainActor @Test func aMissingSavedParentRefuses() throws {
        let f = try Fixture()
        var invalid = f.pinned()
        invalid.tabs[f.aIndex].folderID = UUID()
        #expect(f.propose(invalid) == nil)
    }

    @MainActor @Test func anArchivedSourceRefuses() throws {
        let f = try Fixture()
        var invalid = f.pinned()
        invalid.tabs[f.bIndex].archivedAt = f.now
        #expect(f.propose(invalid) == nil)
    }

    @MainActor @Test func aStaleIndexRefuses() throws {
        let f = try Fixture()
        #expect(f.propose(f.pinned(), target: .insert(5)) == nil)
    }
}
