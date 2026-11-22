import Foundation
import Testing
@testable import ParcCore

struct ExternalSplitDropPinnedTabsTests {
    private typealias Fixture = ExternalSplitDropTestsSupport.Fixture

    @MainActor @Test func aPinnedEdgeDropKeepsTheRequestedPaneOrderWithTheOriginalLiveID() throws {
        let f = try Fixture()
        let split = try #require(f.favoriteProposal(f.pinned(), .insert(0)))
        #expect(split.selectedTabIDs == [f.urlID, f.a])
        #expect(split.splitLayouts[0].tabIDs == [f.urlID, f.a])
    }

    @MainActor @Test func aPinnedLivePageMovesToTodayWithoutLosingItsAddressOrReferrer() throws {
        let f = try Fixture()
        let pinned = f.pinned()
        let original = pinned.tabs[f.aIndex]
        let split = try #require(f.favoriteProposal(pinned, .insert(0)))
        let live = try #require(split.tabs.first { $0.id == f.a })
        #expect(live.kind == .today)
        #expect(live.folderID == nil)
        #expect(live.url == original.url)
        #expect(live.referrerID == original.referrerID)
    }

    @MainActor @Test func aPinnedSavedHomeKeepsItsFolderAndSavedMetadata() throws {
        let f = try Fixture()
        let pinned = f.pinned()
        let original = pinned.tabs[f.aIndex]
        let split = try #require(f.favoriteProposal(pinned, .insert(0)))
        let home = try #require(split.tabs.first { $0.id == f.homeID })
        #expect(home.kind == .pinned)
        #expect(home.folderID == f.pinnedFolderID)
        #expect(home.spaceID == f.space)
        #expect(home.url == original.savedURL)
        #expect(home.customTitle == original.customTitle)
    }

    @MainActor @Test func aPinnedSavedHomeTakesTheExactSiblingSlot() throws {
        let f = try Fixture()
        let split = try #require(f.favoriteProposal(f.pinned(), .insert(0)))
        #expect(SidebarHierarchy.children(in: f.pinnedContainer, state: split) == [.tab(f.b), .tab(f.homeID), .folder(f.siblingFolderID)])
    }

    @MainActor @Test func aPinnedDropLeavesUnrelatedSiblingsAndFoldersIntact() throws {
        let f = try Fixture()
        let pinned = f.pinned()
        let split = try #require(f.favoriteProposal(pinned, .insert(0)))
        #expect(split.tabs.first { $0.id == f.b } == pinned.tabs[f.bIndex])
        #expect(split.folders == pinned.folders)
    }

    @MainActor @Test func replacingAPinnedPaneLeavesTheSavedItemIntact() throws {
        let f = try Fixture()
        let pinned = f.pinned()
        #expect(f.favoriteProposal(pinned, .replace(0), useHome: false)?.tabs.first { $0.id == f.a } == pinned.tabs[f.aIndex])
    }

    @MainActor @Test func aPinnedEdgeDropNeedsItsFixedSavedHomeIdentity() throws {
        let f = try Fixture()
        #expect(f.favoriteProposal(f.pinned(), .insert(0), useHome: false) == nil)
    }

    @MainActor @Test func anExistingPinnedGroupTakesTheLinkWithoutSavedHomeCopies() throws {
        let f = try Fixture()
        var state = f.pinned()
        state.selectedTabIDs = [f.a, f.b]
        state.splitLayouts = [f.group]
        let within = try #require(f.favoriteProposal(state, .insert(1), f.group))
        #expect(!within.tabs.contains { $0.id == f.homeID })
        #expect(within.splitLayouts[0].id == f.group.id)
    }

    @MainActor @Test func aMissingPinnedFolderRefusesTheWholeCreation() throws {
        let f = try Fixture()
        var state = f.pinned()
        state.folders.removeAll { $0.id == f.pinnedFolderID }
        #expect(f.favoriteProposal(state, .insert(0)) == nil)
    }

    @MainActor @Test func aFavoriteFromAnotherProfileRefuses() throws {
        let f = try Fixture()
        var state = f.favorite()
        state.tabs[f.aIndex].profileID = UUID()
        #expect(f.favoriteProposal(state, .insert(1)) == nil)
    }

    @MainActor @Test func aMissingSavedHomeSpaceRefuses() throws {
        let f = try Fixture()
        var state = f.favorite()
        state.spaces.removeAll { $0.id == f.homeSpace }
        #expect(f.favoriteProposal(state, .insert(1)) == nil)
    }
}
