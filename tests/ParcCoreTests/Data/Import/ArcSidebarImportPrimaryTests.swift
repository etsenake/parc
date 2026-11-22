import CoreGraphics
import Foundation
import Testing
@testable import ParcCore

struct ArcSidebarImportPrimaryTests {
    private typealias Support = ArcSidebarImportTestsSupport

    @MainActor
    @Test func aPrimaryProfilesSpacesJoinTheOpenedProfile() throws {
        try Support.withCustomPrimary { custom in
            let projects = try #require(custom.state.profiles.first { $0.name == "Side Projects" })
            let spaces = Array(custom.state.spaces.dropFirst(custom.before.spaces.count))
            #expect(spaces.map(\.title) == ["Side", "Side Projects"]
                    && spaces.map(\.profileID) == [custom.openedID, projects.id])
            #expect(custom.result[Support.profileOne]?.profileID == custom.openedID
                    && custom.result[Support.profileTwo]?.profileID == projects.id && custom.result[.standard] == nil)
        }
    }

    @MainActor
    @Test func aParcProfileNamedLikeThePrimaryIsLeftAloneAndTheOpenedProfileKeepsItsName() throws {
        try Support.withCustomPrimary { custom in
            #expect(custom.state.profiles.count == custom.before.profiles.count + 1
                    && !custom.state.spaces.contains { $0.profileID == custom.namesake }
                    && custom.state.profiles.first { $0.id == custom.openedID }?.name
                        == custom.before.profiles.first { $0.id == custom.openedID }?.name)
        }
    }

    @MainActor
    @Test func favoritesFollowTheirOwnArcProfile() throws {
        try Support.withCustomPrimary { custom in
            let projects = try #require(custom.state.profiles.first { $0.name == "Side Projects" })
            #expect(custom.state.tabs.filter { $0.kind == .favorite && $0.profileID == projects.id }.map(\.savedURL)
                    == ["https://calendar.example.test/"]
                    && !custom.state.tabs.contains { $0.kind == .favorite && $0.profileID == custom.openedID })
        }
    }
}
