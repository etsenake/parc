import Combine
import Foundation

@main @MainActor struct EmptyStateDismissalTests {
    static var count = 0
    static func check(_ value: @autoclosure () throws -> Bool, _ message: String) rethrows {
        count += 1
        guard try value() else { fatalError("SidebarFavoritesEmptyState dismissal: \(message)") }
    }
    static func main() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("parc-empty-state-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("session.json")

        let store = try BrowserStore(directory: directory)
        let first = store.activeSpace.profileID
        let second = store.createProfile(name: "Work")
        check(!store.state.settings.favoritesEmptyStateDismissed(for: first)
              && !store.state.settings.favoritesEmptyStateDismissed(for: second), "a new profile shows the empty state")

        var published = 0
        let subscription = store.statePublisher.dropFirst().sink { _ in published += 1 }
        store.dismissFavoritesEmptyState(profileID: first)
        check(store.state.settings.topAppsEmptyStateDismissedForProfiles == [first] && published > 0,
              "Dismiss records its profile in the app-wide list")
        check(!store.state.settings.favoritesEmptyStateDismissed(for: second), "other profiles keep their empty state")
        let updates = published
        store.dismissFavoritesEmptyState(profileID: first)
        check(published == updates && store.state.settings.topAppsEmptyStateDismissedForProfiles == [first],
              "a second dismissal changes nothing")
        store.dismissFavoritesEmptyState(profileID: UUID())
        check(published == updates, "an unknown profile is not recorded")
        subscription.cancel()
        try store.save()

        let relaunched = try BrowserStore(directory: directory)
        check(relaunched.state.settings.favoritesEmptyStateDismissed(for: first)
              && !relaunched.state.settings.favoritesEmptyStateDismissed(for: second), "the dismissal survives a relaunch")

        var json = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
        var settings = json["settings"] as! [String: Any]
        check(settings["topAppsEmptyStateDismissedForProfiles"] as? [String] == [first.uuidString], "the session stores the topAppsEmptyStateDismissedForProfiles key")
        settings.removeValue(forKey: "topAppsEmptyStateDismissedForProfiles")
        json["settings"] = settings
        try JSONSerialization.data(withJSONObject: json).write(to: file)
        let older = try BrowserStore(directory: directory)
        check(older.state.settings.topAppsEmptyStateDismissedForProfiles == nil
              && !older.state.settings.favoritesEmptyStateDismissed(for: first), "an older session shows the empty state")
        print("SidebarFavoritesEmptyState dismissal: \(count) assertions passed")
    }
}
