import Foundation
import Testing
@testable import ParcCore

struct ExternalSplitDropFavoritesTests {
    private typealias Fixture = ExternalSplitDropTestsSupport.Fixture

    @MainActor @Test func aStandaloneFavoriteFormsASplitInTheCurrentSpaceKeepingItsID() throws {
        let f = try Fixture()
        let split = try #require(f.favoriteProposal(f.favorite(), .insert(1)))
        #expect(split.selectedTabIDs == [f.a, f.urlID])
        #expect(split.splitLayouts.first?.spaceID == f.space)
    }

    @MainActor @Test func theFavoriteLivePageKeepsItsAddressTitleAndReferrer() throws {
        let f = try Fixture()
        let favorite = f.favorite()
        let original = favorite.tabs[f.aIndex]
        let split = try #require(f.favoriteProposal(favorite, .insert(1)))
        let live = try #require(split.tabs.first { $0.id == f.a })
        #expect(live.kind == .today)
        #expect(live.spaceID == f.space)
        #expect(live.url == original.url)
        #expect(live.title == original.title)
        #expect(live.referrerID == f.b)
    }

    @MainActor @Test func theFavoriteSavedHomeKeepsItsProfileSpaceAndSavedPage() throws {
        let f = try Fixture()
        let favorite = f.favorite()
        let original = favorite.tabs[f.aIndex]
        let split = try #require(f.favoriteProposal(favorite, .insert(1)))
        let home = try #require(split.tabs.first { $0.id == f.homeID })
        #expect(home.kind == .favorite)
        #expect(home.spaceID == f.homeSpace)
        #expect(home.profileID == f.profile)
        #expect(home.url == original.savedURL)
        #expect(home.title == original.savedTitle)
    }

    @MainActor @Test func theFavoriteSavedHomeKeepsItsTitleOverrideAndFreshCreationReceipt() throws {
        let f = try Fixture()
        let favorite = f.favorite()
        let original = favorite.tabs[f.aIndex]
        let split = try #require(f.favoriteProposal(favorite, .insert(1)))
        let home = try #require(split.tabs.first { $0.id == f.homeID })
        #expect(home.customTitle == original.customTitle)
        #expect(home.savedURL == original.savedURL)
        #expect(home.referrerID == nil)
        #expect(home.activeTabBeforeCreationID == f.a)
    }

    @MainActor @Test func theSavedHomeTakesTheFavoriteTraySlot() throws {
        let f = try Fixture()
        let split = try #require(f.favoriteProposal(f.favorite(), .insert(1)))
        #expect(SidebarHierarchy.children(in: f.tray, state: split) == [.tab(f.b), .tab(f.homeID)])
    }

    @MainActor @Test func returningToTheHomeSpaceFollowsTheSavedHome() throws {
        let f = try Fixture()
        let split = try #require(f.favoriteProposal(f.favorite(), .insert(1)))
        #expect(split.selectionBySpace[f.homeSpace.uuidString] == [f.homeID])
    }

    @MainActor @Test func retryingAFavoriteDropKeepsTheFixedIdentities() throws {
        let f = try Fixture()
        let favorite = f.favorite()
        let first = try #require(f.favoriteProposal(favorite, .insert(1)))
        #expect(f.favoriteProposal(favorite, .insert(1))?.tabs == first.tabs)
    }

    enum HomeIdentity: String, CaseIterable, Sendable, CustomTestStringConvertible {
        case missing = "Missing identity"
        case original = "Original tab identity"
        case newLink = "New link identity"

        var testDescription: String { rawValue }
    }

    @MainActor @Test(arguments: HomeIdentity.allCases)
    func aMissingOrCollidingHomeIdentityRefusesTheDrop(_ kind: HomeIdentity) throws {
        let f = try Fixture()
        let proposal: BrowserState?
        switch kind {
        case .missing: proposal = f.favoriteProposal(f.favorite(), .insert(1), useHome: false)
        case .original: proposal = f.favoriteProposal(f.favorite(), .insert(1), home: f.a)
        case .newLink: proposal = f.favoriteProposal(f.favorite(), .insert(1), home: f.urlID)
        }
        #expect(proposal == nil)
    }

    @MainActor @Test func replacingASingleFavoriteLeavesItUntouchedWithoutACopy() throws {
        let f = try Fixture()
        let favorite = f.favorite()
        let center = try #require(f.favoriteProposal(favorite, .replace(0), useHome: false))
        #expect(center.tabs.first { $0.id == f.a } == favorite.tabs[f.aIndex])
        #expect(!center.tabs.contains { $0.id == f.homeID })
    }

    @MainActor @Test func replacingASingleFavoriteChoosesOnlyTheNewPage() throws {
        let f = try Fixture()
        let center = try #require(f.favoriteProposal(f.favorite(), .replace(0), useHome: false))
        #expect(center.selectedTabIDs == [f.urlID])
        #expect(center.splitLayouts.isEmpty)
    }

    @MainActor @Test func aFavoriteGroupTakesAFavoriteChildInTheHomeSpace() throws {
        let f = try Fixture()
        let (state, trayGroup) = f.favoriteGroupState()
        let added = try #require(f.favoriteProposal(state, .insert(1), trayGroup))
        let child = added.tabs.first { $0.id == f.urlID }
        #expect(child?.kind == .favorite)
        #expect(child?.spaceID == f.homeSpace)
    }

    @MainActor @Test func aFavoriteGroupKeepsItsIdentityAppearanceAndChildOrder() throws {
        let f = try Fixture()
        let (state, trayGroup) = f.favoriteGroupState()
        let added = try #require(f.favoriteProposal(state, .insert(1), trayGroup))
        #expect(added.splitLayouts[0].id == trayGroup.id)
        #expect(added.splitLayouts[0].customTitle == trayGroup.customTitle)
        #expect(added.splitLayouts[0].customIcon == trayGroup.customIcon)
        #expect(added.splitLayouts[0].tabIDs == [f.a, f.urlID, f.b])
    }

    @MainActor @Test func aFavoriteGroupNeverDuplicatesItsOriginalChildren() throws {
        let f = try Fixture()
        let (state, trayGroup) = f.favoriteGroupState()
        let added = try #require(f.favoriteProposal(state, .insert(1), trayGroup))
        #expect(!added.tabs.contains { $0.id == f.homeID })
        #expect(SidebarHierarchy.children(in: f.tray, state: added) == [.split(trayGroup.id)])
    }

    @MainActor @Test func replacingInAFavoriteGroupKeepsTheDisplacedFavoriteAndGeometry() throws {
        let f = try Fixture()
        let (state, trayGroup) = f.favoriteGroupState()
        let replaced = try #require(f.favoriteProposal(state, .replace(0), trayGroup))
        #expect(replaced.tabs.first { $0.id == f.a } == state.tabs[f.aIndex])
        #expect(replaced.splitLayouts[0].widthFactors == trayGroup.widthFactors)
    }

    @MainActor @Test func theReplacedAnchorKeepsTheGroupTraySlotBeforeTheDisplacedFavorite() throws {
        let f = try Fixture()
        let (state, trayGroup) = f.favoriteGroupState()
        let replaced = try #require(f.favoriteProposal(state, .replace(0), trayGroup))
        #expect(SidebarHierarchy.children(in: f.tray, state: replaced) == [.split(trayGroup.id), .tab(f.a)])
    }

    @MainActor @Test func aThirteenthFavoriteRootIsRefused() throws {
        let f = try Fixture()
        let (state, trayGroup) = f.favoriteGroupState()
        let capped = f.cappedFavorites(state)
        #expect(SidebarHierarchy.children(in: f.tray, state: capped).count == 12)
        #expect(f.favoriteProposal(capped, .replace(0), trayGroup) == nil)
    }

    @MainActor @Test func insertingIntoAFavoriteGroupDoesNotConsumeATrayRoot() throws {
        let f = try Fixture()
        let (state, trayGroup) = f.favoriteGroupState()
        #expect(f.favoriteProposal(f.cappedFavorites(state), .insert(1), trayGroup) != nil)
    }

    @MainActor @Test func aMixedFavoriteAndTodayGroupRefusesWithoutConversion() throws {
        let f = try Fixture()
        let (state, trayGroup) = f.favoriteGroupState()
        var mixed = state
        mixed.tabs[f.bIndex].kind = .today
        mixed.tabs[f.bIndex].spaceID = f.space
        #expect(f.favoriteProposal(mixed, .insert(1), trayGroup) == nil)
    }
}
