import Foundation
import Testing
@testable import ParcCore

struct SpaceActionTests {
    typealias Action = CommandBarSpaceAction

    struct Fixture {
        let personal = BrowserProfile(id: UUID(), name: "Personal")
        let work = BrowserProfile(id: UUID(), name: "Work")
        let first: BrowserSpace
        var second: BrowserSpace
        let cafe: BrowserSpace
        let invalid: BrowserSpace

        init() {
            first = BrowserSpace(id: UUID(), name: "Research", symbol: "circle.fill", color: "ABCDEF", profileID: personal.id)
            second = BrowserSpace(id: UUID(), name: "Research", symbol: "star.fill", color: "ABCDEF", profileID: work.id)
            cafe = BrowserSpace(id: UUID(), name: "Café", symbol: "cup.and.saucer", color: "ABCDEF", profileID: personal.id)
            invalid = BrowserSpace(id: UUID(), name: "Removed profile", symbol: "circle", color: "ABCDEF", profileID: UUID())
        }

        var profiles: [BrowserProfile] { [personal, work] }

        func snapshot() -> [Action] { Action.snapshot(spaces: [first, second, cafe, invalid], profiles: profiles) }
    }

    @Test func missingProfilesNeverBecomeDestinations() {
        #expect(Fixture().snapshot().count == 3)
    }

    @Test func identicalNamesRetainDistinctIdentities() {
        #expect(Set(Fixture().snapshot().map(\.id)).count == 3)
    }

    @Test func duplicateNamesExposeTheirPosition() {
        let actions = Fixture().snapshot()
        #expect(actions[0].detail == "Space 1")
        #expect(actions[1].detail == "Space 2")
    }

    @Test func aUniqueSpaceKeepsTheCompactRow() {
        #expect(Fixture().snapshot()[2].detail.isEmpty)
    }

    @Test func aGenericSpaceQueryPreservesUserOrder() {
        let actions = Fixture().snapshot()
        #expect(Action.matching(actions, query: "space").map(\.id) == actions.map(\.id))
    }

    @Test func duplicateNamesBothMatch() {
        let fixture = Fixture()
        #expect(Action.matching(fixture.snapshot(), query: "research").map(\.spaceID) == [fixture.first.id, fixture.second.id])
    }

    @Test func wordMatchingIgnoresAccentsAndKeepsTheActualDestination() {
        let fixture = Fixture()
        #expect(Action.matching(fixture.snapshot(), query: "focus on cafe").map(\.spaceID) == [fixture.cafe.id])
    }

    @Test(arguments: ["  ", "> space", "https://space.test"])
    func queriesThatAreNotSpaceCommandsMatchNothing(query: String) {
        #expect(Action.matching(Fixture().snapshot(), query: query).isEmpty)
    }

    @Test func renamingRefreshesPresentationWithoutChangingIdentity() {
        var fixture = Fixture()
        let original = fixture.snapshot()
        fixture.second.name = "Renamed"
        let renamed = Action.snapshot(spaces: [fixture.first, fixture.second, fixture.cafe], profiles: fixture.profiles)
        #expect(renamed[1].id == original[1].id)
        #expect(renamed[1].name == "Renamed")
    }

    @Test func theOriginalTargetStaysTheSameSpaceAfterARename() {
        var fixture = Fixture()
        let original = fixture.snapshot()
        fixture.second.name = "Renamed"
        #expect(original[1].isCurrent(spaces: [fixture.first, fixture.second, fixture.cafe], profiles: fixture.profiles))
    }

    @Test func aRemovedOriginalCannotRedirectToASameNameSpace() {
        let fixture = Fixture()
        #expect(!fixture.snapshot()[1].isCurrent(spaces: [fixture.first, fixture.cafe], profiles: fixture.profiles))
    }

    @Test func aRetiredProfileInvalidatesTheOriginalTarget() {
        let fixture = Fixture()
        #expect(!fixture.snapshot()[1].isCurrent(spaces: [fixture.first, fixture.second], profiles: [fixture.personal]))
    }

    @Test func aReassignedProfileCannotSatisfyAnOldTarget() {
        var fixture = Fixture()
        let original = fixture.snapshot()
        fixture.second.profileID = fixture.personal.id
        #expect(!original[1].isCurrent(spaces: [fixture.first, fixture.second], profiles: fixture.profiles))
    }

    @Test func reassignmentChangesTheRowIdentitySoAHighlightedOldActionCanExpire() {
        var fixture = Fixture()
        let original = fixture.snapshot()
        fixture.second.profileID = fixture.personal.id
        #expect(Action.snapshot(spaces: [fixture.second], profiles: fixture.profiles)[0].id != original[1].id)
    }
}
