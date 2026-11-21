import Foundation
import Testing
@testable import ParcCore

struct FolderActionTests {
    typealias Action = CommandBarFolderAction

    struct Fixture {
        let profile = BrowserProfile(id: UUID(), name: "Personal")
        let foreign = BrowserProfile(id: UUID(), name: "Work")
        let first: BrowserSpace
        let second: BrowserSpace
        let root: BrowserFolder
        let nested: BrowserFolder
        let duplicate: BrowserFolder
        let state: BrowserState

        init() {
            first = BrowserSpace(id: UUID(), name: "Home", symbol: "house", color: "ABCDEF", profileID: profile.id)
            second = BrowserSpace(id: UUID(), name: "Research", symbol: "circle", color: "ABCDEF", profileID: profile.id)
            let other = BrowserSpace(id: UUID(), name: "Other", symbol: "circle", color: "ABCDEF", profileID: foreign.id)
            root = BrowserFolder(id: UUID(), spaceID: first.id, name: "Projects", isExpanded: false)
            nested = BrowserFolder(id: UUID(), spaceID: first.id, name: "Café", parentID: root.id, isExpanded: false)
            duplicate = BrowserFolder(id: UUID(), spaceID: second.id, name: "Café", isExpanded: false)
            let hidden = BrowserFolder(id: UUID(), spaceID: other.id, name: "Other profile")
            let empty = BrowserFolder(id: UUID(), spaceID: first.id, name: "  ")
            var state = BrowserState(profiles: [profile, foreign], spaces: [first, second, other], activeSpaceID: first.id)
            state.folders = [root, nested, duplicate, hidden, empty]
            state.tabs = [BrowserTab(id: UUID(), spaceID: first.id, profileID: profile.id,
                url: "https://example.test", title: "Original", kind: .pinned, folderID: nested.id,
                createdAt: Date(timeIntervalSince1970: 1), lastAccessed: Date(timeIntervalSince1970: 1),
                savedURL: "https://example.test", savedTitle: "Original")]
            self.state = state
        }

        func snapshot(_ state: BrowserState? = nil) -> [Action] {
            Action.snapshot(state: state ?? self.state, profileID: profile.id)
        }

        var original: Action { snapshot()[1] }
    }

    @Test func namedOrdinaryFoldersFollowSpaceAndTreeOrderIncludingCollapsedDescendants() {
        let fixture = Fixture()
        #expect(fixture.snapshot().map(\.folderID) == [fixture.root.id, fixture.nested.id, fixture.duplicate.id])
    }

    @Test func identicalNamesExposeTheirSpaceAndAncestorPath() {
        let actions = Fixture().snapshot()
        #expect(actions[1].detail == "Home › Projects")
        #expect(actions[2].detail == "Research")
    }

    @Test func duplicateNamesHaveDistinctIdentities() {
        #expect(Set(Fixture().snapshot().map(\.id)).count == 3)
    }

    @Test func theOpenPrefixMatchesDestinationsIgnoringAccents() {
        let fixture = Fixture()
        #expect(Action.matching(fixture.snapshot(), query: "open cafe").map(\.folderID) == [fixture.nested.id, fixture.duplicate.id])
    }

    @Test func theActualPathDisambiguatesTheDestination() {
        let fixture = Fixture()
        #expect(Action.matching(fixture.snapshot(), query: "cafe home projects").map(\.folderID) == [fixture.nested.id])
    }

    @Test func folderDiscoveryIsSearchable() {
        #expect(Action.matching(Fixture().snapshot(), query: "folder").count == 3)
    }

    @Test(arguments: ["", "> projects", "https://cafe.test"])
    func queriesThatAreNotFolderCommandsMatchNothing(query: String) {
        #expect(Action.matching(Fixture().snapshot(), query: query).isEmpty)
    }

    @Test func aNewSourceProfileCannotReuseTheOriginalRow() {
        let fixture = Fixture()
        #expect(!fixture.original.isCurrent(in: fixture.state, profileID: fixture.foreign.id))
    }

    @Test func renamingPreservesTheOriginalFolderIdentity() {
        let fixture = Fixture()
        var renamed = fixture.state
        renamed.folders[1].name = "Renamed"
        #expect(fixture.original.isCurrent(in: renamed, profileID: fixture.profile.id))
    }

    @Test func aProviderRefreshCarriesTheNewTitleWithoutRetargeting() {
        let fixture = Fixture()
        var renamed = fixture.state
        renamed.folders[1].name = "Renamed"
        let updated = fixture.snapshot(renamed)[1]
        #expect(updated.id == fixture.original.id)
        #expect(updated.name == "Renamed")
    }

    @Test func changingTheParentPathExpiresTheChosenCommand() {
        let fixture = Fixture()
        var moved = fixture.state
        moved.folders[1].parentID = nil
        #expect(!fixture.original.isCurrent(in: moved, profileID: fixture.profile.id))
    }

    @Test func reparentedRowsCannotInheritAnExplicitSelection() {
        let fixture = Fixture()
        var moved = fixture.state
        moved.folders[1].parentID = nil
        #expect(fixture.snapshot(moved).first { $0.folderID == fixture.nested.id }?.id != fixture.original.id)
    }

    @Test func aCrossSpaceMoveInvalidatesTheOldTreeTarget() {
        let fixture = Fixture()
        var moved = fixture.state
        moved.folders[1].spaceID = fixture.second.id
        #expect(!fixture.original.isCurrent(in: moved, profileID: fixture.profile.id))
    }

    @Test func removalCannotFallThroughToASameNameFolder() {
        let fixture = Fixture()
        var removed = fixture.state
        removed.folders.removeAll { $0.id == fixture.nested.id }
        #expect(!fixture.original.isCurrent(in: removed, profileID: fixture.profile.id))
    }

    @Test func aRetiredProfileExposesNoDestination() {
        let fixture = Fixture()
        var removed = fixture.state
        removed.profiles.removeAll { $0.id == fixture.profile.id }
        #expect(fixture.snapshot(removed).isEmpty)
    }

    @Test func cyclesNeverBecomeActionableTargets() {
        let fixture = Fixture()
        var cyclic = fixture.state
        cyclic.folders[0].parentID = fixture.nested.id
        #expect(fixture.snapshot(cyclic).map(\.folderID) == [fixture.duplicate.id])
    }

    @Test func revealExpandsTheOriginalFolderAndItsAncestors() throws {
        let fixture = Fixture()
        let revealed = try #require(fixture.original.reveal.applying(to: fixture.state))
        #expect(revealed.folders[0].isExpanded)
        #expect(revealed.folders[1].isExpanded)
    }

    @Test func revealLeavesUnrelatedFolderDisclosureIntact() throws {
        let fixture = Fixture()
        let revealed = try #require(fixture.original.reveal.applying(to: fixture.state))
        #expect(!revealed.folders[2].isExpanded)
    }

    @Test func revealingAnEmptyFolderExpandsOnlyItsAncestors() throws {
        let fixture = Fixture()
        var emptyState = fixture.state
        emptyState.tabs = []
        let action = fixture.snapshot(emptyState)[1]
        let revealed = try #require(action.reveal.applying(to: emptyState))
        #expect(revealed.folders[0].isExpanded)
        #expect(!revealed.folders[1].isExpanded)
    }

    @Test func revealOnlyChangesFolderDisclosure() throws {
        let fixture = Fixture()
        var restored = try #require(fixture.original.reveal.applying(to: fixture.state))
        restored.folders = fixture.state.folders
        #expect(restored == fixture.state)
    }

    @Test func revealRejectsChangedDestinationOwnership() {
        let fixture = Fixture()
        var moved = fixture.state
        moved.folders[1].parentID = nil
        #expect(fixture.original.reveal.applying(to: moved) == nil)
    }
}
