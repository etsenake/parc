import Foundation
import Testing
@testable import ParcCore

struct FavoriteRenameActionTests {
    typealias Action = CommandBarFavoriteRenameAction

    struct Fixture {
        let profile = BrowserProfile(id: UUID(), name: "Original")
        let foreign = BrowserProfile(id: UUID(), name: "Foreign")
        let origin: BrowserSpace
        let space: BrowserSpace
        let favorite: BrowserTab
        let ordinary: BrowserTab
        let state: BrowserState

        init() {
            origin = BrowserSpace(id: UUID(), name: "Origin", symbol: "circle", color: "ABCDEF", profileID: profile.id)
            space = BrowserSpace(id: UUID(), name: "Current", symbol: "circle", color: "ABCDEF", profileID: profile.id)
            favorite = BrowserTab(id: UUID(), spaceID: origin.id, profileID: profile.id,
                url: "https://example.test/current", title: "Current page", kind: .favorite,
                createdAt: Date(timeIntervalSince1970: 100), lastAccessed: Date(timeIntervalSince1970: 100),
                savedURL: "https://example.test/home", savedTitle: "Saved title")
            var ordinary = favorite
            ordinary.id = UUID()
            ordinary.kind = .today
            ordinary.spaceID = space.id
            self.ordinary = ordinary
            var state = BrowserState(profiles: [profile, foreign], spaces: [origin, space], activeSpaceID: origin.id)
            state.tabs = [favorite, ordinary]
            state.selectedTabIDs = [ordinary.id]
            self.state = state
        }

        func make(_ state: BrowserState? = nil, _ ids: [UUID]? = nil) -> Action? {
            Action(state: state ?? self.state, spaceID: space.id, profileID: profile.id, selectedTabIDs: ids ?? [favorite.id])
        }

        func current(_ action: Action, in state: BrowserState? = nil, _ ids: [UUID]? = nil) -> BrowserTab? {
            action.currentTab(in: state ?? self.state, spaceID: space.id, profileID: profile.id, selectedTabIDs: ids ?? [favorite.id])
        }
    }

    struct Change: Sendable, CustomTestStringConvertible {
        let name: String
        let apply: @Sendable (inout BrowserState, Fixture) -> Void
        var testDescription: String { name }
    }

    static let expiringChanges: [Change] = [
        Change(name: "another window renames the Favorite") { state, _ in state.tabs[0].customTitle = "Another window" },
        Change(name: "the saved anchor is replaced") { state, _ in state.tabs[0].savedURL = "https://example.test/new-home" },
        Change(name: "the UUID is reused by a new incarnation") { state, _ in state.tabs[0].createdAt.addTimeInterval(1) },
        Change(name: "the Favorite is unfavorited") { state, _ in state.tabs[0].kind = .pinned },
        Change(name: "the Favorite moves to a foreign profile") { state, fixture in state.tabs[0].profileID = fixture.foreign.id },
        Change(name: "the Favorite is archived") { state, _ in state.tabs[0].archivedAt = Date() },
        Change(name: "the Favorite is deleted") { state, _ in state.tabs.removeFirst() },
        Change(name: "the profile is retiring") { state, fixture in
            state.profileRemovals = [.init(id: UUID(), profileID: fixture.profile.id, profileName: fixture.profile.name)]
        },
        Change(name: "the original profile disappears") { state, fixture in state.profiles.removeAll { $0.id == fixture.profile.id } },
        Change(name: "the command space disappears") { state, fixture in state.spaces.removeAll { $0.id == fixture.space.id } },
        Change(name: "the Favorite becomes a split child") { state, fixture in
            state.splitLayouts = [.init(spaceID: fixture.space.id, tabIDs: [fixture.favorite.id, fixture.ordinary.id],
                                        orientation: .horizontal, widthFactors: [0.5, 0.5])]
        },
    ]

    @Test func theOriginalFavoriteIsProfileWideInTheCommandSpace() throws {
        let fixture = Fixture()
        let action = try #require(fixture.make())
        #expect(action.tab == fixture.favorite)
        #expect(action.spaceID == fixture.space.id)
    }

    @Test func theTitleIsTheRecoveredTypeTravelTitle() throws {
        let action = try #require(Fixture().make())
        #expect(action.title == "Rename Current Tab…")
    }

    @Test(arguments: ["rename", "CURRENT TAB", "tab ren"])
    func commandWordsMatch(query: String) throws {
        let action = try #require(Fixture().make())
        #expect(action.matches(query: query))
    }

    @Test(arguments: ["", "rename folder", "> rename"])
    func noTriggerIsFabricatedAndUnrelatedCommandsDoNotMatch(query: String) throws {
        let action = try #require(Fixture().make())
        #expect(!action.matches(query: query))
    }

    @Test func anEmptySelectionOffersNoRename() {
        #expect(Fixture().make(nil, []) == nil)
    }

    @Test func aRepeatedSelectionOffersNoRename() {
        let fixture = Fixture()
        #expect(fixture.make(nil, [fixture.favorite.id, fixture.favorite.id]) == nil)
    }

    @Test func aWholeSelectionNeverBecomesAFocusedChild() {
        let fixture = Fixture()
        #expect(fixture.make(nil, [fixture.favorite.id, fixture.ordinary.id]) == nil)
    }

    @Test func anOrdinaryRowKeepsItsInlineCommandOwner() {
        let fixture = Fixture()
        #expect(fixture.make(nil, [fixture.ordinary.id]) == nil)
    }

    @Test func aChangedWindowSelectionRefusesTheOriginalAction() throws {
        let fixture = Fixture()
        let action = try #require(fixture.make())
        #expect(fixture.current(action, [fixture.ordinary.id]) == nil)
    }

    @Test func resolvingTheTargetNeitherWritesNorFallsBackOnSelection() throws {
        let fixture = Fixture()
        let action = try #require(fixture.make())
        #expect(fixture.current(action) == fixture.favorite)
        #expect(fixture.state.selectedTabIDs == [fixture.ordinary.id])
    }

    @Test func liveMetadataAdvancesWithoutReplacingTheRenameTarget() throws {
        let fixture = Fixture()
        let action = try #require(fixture.make())
        var changed = fixture.state
        changed.tabs[0].title = "Live update"
        changed.tabs[0].url = "https://example.test/redirect"
        let current = fixture.current(action, in: changed)
        #expect(current?.url == "https://example.test/redirect")
        #expect(current?.title == "Live update")
    }

    @Test func nativeMetadataDoesNotChangeTheResultIdentity() throws {
        let fixture = Fixture()
        let action = try #require(fixture.make())
        var changed = fixture.state
        changed.tabs[0].title = "Live update"
        changed.tabs[0].url = "https://example.test/redirect"
        let changedAction = try #require(fixture.make(changed))
        #expect(action.id == changedAction.id)
    }

    @Test(arguments: expiringChanges)
    func theOriginalActionExpiresWhen(change: Change) throws {
        let fixture = Fixture()
        let action = try #require(fixture.make())
        var changed = fixture.state
        change.apply(&changed, fixture)
        #expect(fixture.current(action, in: changed) == nil)
    }

    @Test func aSpaceChangeCannotRetargetTheOriginalCommandSession() throws {
        let fixture = Fixture()
        let action = try #require(fixture.make())
        #expect(action.currentTab(in: fixture.state, spaceID: fixture.origin.id, profileID: fixture.profile.id,
                                  selectedTabIDs: [fixture.favorite.id]) == nil)
    }

    @Test func aProfileChangeCannotRetargetTheOriginalCommandSession() throws {
        let fixture = Fixture()
        let action = try #require(fixture.make())
        #expect(action.currentTab(in: fixture.state, spaceID: fixture.space.id, profileID: fixture.foreign.id,
                                  selectedTabIDs: [fixture.favorite.id]) == nil)
    }
}
