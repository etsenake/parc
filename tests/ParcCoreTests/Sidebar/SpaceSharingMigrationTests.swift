import Foundation
import Testing
@testable import ParcCore

extension SpaceSharingTestsSupport {
    @MainActor
    struct SpaceSharingMigrationTests {
        struct Upgrade {
            let folder: Folder
            let store: BrowserStore
            let work: BrowserProfile
            let leaving: BrowserProfile
            let shared: BrowserProfile
            let s1: BrowserSpace
            let s2: BrowserSpace
            let theme: SpaceTheme
            let elsewhere: UUID
            let made: [BrowserSpace]

            @MainActor init() throws {
                folder = try Folder()
                var state = BrowserState.initial()
                state.spaceSharingVersion = 0
                state.spaces[0].autoArchiveHours = nil
                var theme = state.spaces[0].theme
                theme.noise = 0.4
                state.spaces[0].theme = theme
                self.theme = theme
                work = BrowserProfile(id: UUID(), name: "Work", autoArchiveHours: AutoArchiveInterval.sevenDays.rawValue)
                leaving = BrowserProfile(id: UUID(), name: "Leaving")
                shared = BrowserProfile(id: UUID(), name: "Shared", autoArchiveHours: AutoArchiveInterval.thirtyDays.rawValue)
                state.profiles += [work, leaving, shared]
                state.profileRemovals = [ProfileRemovalRecord(id: UUID(), profileID: leaving.id, profileName: leaving.name)]
                s1 = BrowserSpace(id: UUID(), name: "One", symbol: "circle", color: "B9B5D4", profileID: shared.id)
                s2 = BrowserSpace(id: UUID(), name: "Two", symbol: "circle", color: "B9B5D4", profileID: shared.id)
                state.spaces += [s1, s2]
                elsewhere = UUID()
                let routes = LinkRoutingState(rules: [
                    LinkRoute(destination: .profile(work.id)), LinkRoute(destination: .profile(shared.id)),
                    LinkRoute(destination: .profile(leaving.id)), LinkRoute(destination: .space(elsewhere)),
                    LinkRoute(destination: .mostRecent)])
                try JSONEncoder().encode(routes).write(to: folder.url.appendingPathComponent("link-routing.json"))
                try folder.write(state)
                store = try folder.store()
                let workID = work.id
                made = store.state.spaces.filter { $0.profileID == workID }
            }
        }

        @Test func anUnusedProfileGetsItsOwnNamedSpace() throws {
            let upgrade = try Upgrade()
            #expect(upgrade.made.count == 1)
            #expect(upgrade.made[0].name == "Work")
            #expect(upgrade.made[0].symbol == "circle.fill")
        }

        @Test func aNewSpaceCopiesThemeAndProfileArchiveInterval() throws {
            let upgrade = try Upgrade()
            #expect(upgrade.made[0].theme == upgrade.theme)
            #expect(upgrade.made[0].autoArchiveHours == upgrade.work.autoArchiveHours)
        }

        @Test func aPendingRemovalGetsNoSpace() throws {
            let upgrade = try Upgrade()
            #expect(!upgrade.store.state.spaces.contains { $0.profileID == upgrade.leaving.id })
        }

        @Test func sharingSpacesKeepSharing() throws {
            let upgrade = try Upgrade()
            #expect(upgrade.store.state.spaces.filter { $0.profileID == upgrade.shared.id }.map(\.id) == [upgrade.s1.id, upgrade.s2.id])
        }

        @Test func spacesSeedTheArchiveIntervalFromTheirProfile() throws {
            let upgrade = try Upgrade()
            #expect(upgrade.store.state.spaces.first { $0.id == upgrade.s1.id }?.autoArchiveHours == upgrade.shared.autoArchiveHours)
            #expect(upgrade.store.state.spaces[0].autoArchiveHours == AutoArchiveInterval.twelveHours.rawValue)
        }

        @Test func theUpgradeDeletesNothingAndRecordsItsVersion() throws {
            let upgrade = try Upgrade()
            #expect(upgrade.store.state.spaceSharingVersion == SpaceSharing.version)
            #expect(upgrade.store.state.profiles.count == 4)
            #expect(upgrade.store.state.profilesWithoutSpaces.isEmpty)
        }

        @Test func profileRoutesConvertToTheFirstSpaceOrMostRecentAndPersist() throws {
            let upgrade = try Upgrade()
            let destinations = upgrade.store.linkRouting.state.rules.map(\.destination)
            #expect(destinations == [.space(upgrade.made[0].id), .space(upgrade.s1.id), .mostRecent, .space(upgrade.elsewhere), .mostRecent])
            #expect(LinkRoutingStore(directory: upgrade.folder.url).state.rules.map(\.destination) == destinations)
        }

        @Test func theSharingUpgradePersistsItsChanges() throws {
            let upgrade = try Upgrade()
            let reloaded = try upgrade.folder.store()
            #expect(reloaded.state == upgrade.store.state)
        }

        @Test func runningTheSharingUpgradeAgainLeavesTheStateAlone() throws {
            let upgrade = try Upgrade()
            let reloaded = try upgrade.folder.store()
            var again = reloaded.state
            let upgradedAgain = again.upgradeSpaceSharing()
            #expect(!upgradedAgain)
            #expect(again == reloaded.state)
        }
    }
}
