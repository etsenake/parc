import Combine
import Foundation
import Testing
@testable import ParcCore

@MainActor
struct FavoritesEmptyStateDismissalTests {
    @MainActor final class Fixture {
        let directory: URL
        let file: URL
        let store: BrowserStore
        let first: UUID
        let second: UUID

        init() throws {
            directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("parc-empty-state-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
            file = directory.appendingPathComponent("session.json")
            store = try BrowserStore(directory: directory)
            first = store.activeSpace.profileID
            second = store.createProfile(name: "Work")
        }

        deinit { try? FileManager.default.removeItem(at: directory) }
    }

    @Test func aNewProfileShowsTheEmptyState() throws {
        let f = try Fixture()
        #expect(!f.store.state.settings.favoritesEmptyStateDismissed(for: f.first))
        #expect(!f.store.state.settings.favoritesEmptyStateDismissed(for: f.second))
    }

    @Test func dismissRecordsItsProfileInTheAppWideListAndOtherProfilesKeepTheirEmptyState() throws {
        let f = try Fixture()
        var published = 0
        let subscription = f.store.statePublisher.dropFirst().sink { _ in published += 1 }
        f.store.dismissFavoritesEmptyState(profileID: f.first)
        #expect(f.store.state.settings.topAppsEmptyStateDismissedForProfiles == [f.first])
        #expect(published > 0)
        #expect(!f.store.state.settings.favoritesEmptyStateDismissed(for: f.second))
        subscription.cancel()
    }

    @Test func aSecondDismissalChangesNothingAndAnUnknownProfileIsNotRecorded() throws {
        let f = try Fixture()
        f.store.dismissFavoritesEmptyState(profileID: f.first)
        var published = 0
        let subscription = f.store.statePublisher.dropFirst().sink { _ in published += 1 }
        f.store.dismissFavoritesEmptyState(profileID: f.first)
        #expect(published == 0)
        #expect(f.store.state.settings.topAppsEmptyStateDismissedForProfiles == [f.first])
        f.store.dismissFavoritesEmptyState(profileID: UUID())
        #expect(published == 0)
        subscription.cancel()
    }

    @Test func theDismissalSurvivesARelaunchAndTheSessionStoresItsKey() throws {
        let f = try Fixture()
        f.store.dismissFavoritesEmptyState(profileID: f.first)
        try f.store.save()
        let relaunched = try BrowserStore(directory: f.directory)
        #expect(relaunched.state.settings.favoritesEmptyStateDismissed(for: f.first))
        #expect(!relaunched.state.settings.favoritesEmptyStateDismissed(for: f.second))
        let json = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: f.file)) as? [String: Any])
        let settings = try #require(json["settings"] as? [String: Any])
        #expect(settings["topAppsEmptyStateDismissedForProfiles"] as? [String] == [f.first.uuidString])
    }

    @Test func anOlderSessionShowsTheEmptyState() throws {
        let f = try Fixture()
        f.store.dismissFavoritesEmptyState(profileID: f.first)
        try f.store.save()
        var json = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: f.file)) as? [String: Any])
        var settings = try #require(json["settings"] as? [String: Any])
        settings.removeValue(forKey: "topAppsEmptyStateDismissedForProfiles")
        json["settings"] = settings
        try JSONSerialization.data(withJSONObject: json).write(to: f.file)
        let older = try BrowserStore(directory: f.directory)
        #expect(older.state.settings.topAppsEmptyStateDismissedForProfiles == nil)
        #expect(!older.state.settings.favoritesEmptyStateDismissed(for: f.first))
    }
}
