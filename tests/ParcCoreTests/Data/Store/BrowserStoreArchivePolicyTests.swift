import Foundation
import Testing
@testable import ParcCore

@MainActor
struct BrowserStoreArchivePolicyTests {
    @Test static func aNewProfileDefaultsToTwelveHours() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let firstProfile = store.activeSpace.profileID
            #expect(store.autoArchiveInterval(for: firstProfile) == .twelveHours, "New profiles must use the 12-hour Today default")
        }
    }

    @Test static func newProfilesInheritTheSharedArchivePolicyThroughAssignmentAndSettingsEdits() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let firstProfile = store.activeSpace.profileID
            let firstSpace = store.activeSpaceID
            store.setAutoArchiveInterval(.twentyFourHours, for: firstProfile)
            let secondProfile = store.createProfile(name: "Second")
            store.assignProfile(secondProfile, toSpace: firstSpace)
            store.updateSettings { $0.sidebarWidth = 260; $0.searchEngine = "https://www.bing.com/search?q=" }
            #expect(store.autoArchiveInterval(for: secondProfile) == .twentyFourHours, "A new Profile inherits the chosen shared default; assignment and unrelated preferences preserve it")
            #expect(store.autoArchiveInterval(for: firstProfile) == .twentyFourHours, "Unrelated settings must preserve the original profile's policy too")
        }
    }

    @Test static func spacesInTheSameProfileShareItsArchivePolicy() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let firstProfile = store.activeSpace.profileID
            let firstSpace = store.activeSpaceID
            store.setAutoArchiveInterval(.twentyFourHours, for: firstProfile)
            let secondProfile = store.createProfile(name: "Second")
            store.assignProfile(secondProfile, toSpace: firstSpace)
            _ = store.createSpace(name: "Shared profile")
            store.setAutoArchiveInterval(.sevenDays, for: secondProfile)
            store.selectSpace(firstSpace)
            #expect(store.autoArchiveInterval(for: store.activeSpace.profileID) == .sevenDays, "All Spaces assigned to one profile must share its archive choice")
        }
    }

    @Test static func changingAnotherProfilesArchivePolicyKeepsTheActiveProfilesPolicy() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let firstProfile = store.activeSpace.profileID
            let firstSpace = store.activeSpaceID
            store.setAutoArchiveInterval(.twentyFourHours, for: firstProfile)
            let secondProfile = store.createProfile(name: "Second")
            store.assignProfile(secondProfile, toSpace: firstSpace)
            let secondSpace = store.createSpace(name: "Shared profile")
            store.setAutoArchiveInterval(.sevenDays, for: secondProfile)
            store.selectSpace(firstSpace)
            store.assignProfile(firstProfile, toSpace: secondSpace)
            store.setAutoArchiveInterval(.thirtyDays, for: firstProfile)
            #expect(store.activeSpaceID == firstSpace && store.autoArchiveInterval(for: secondProfile) == .sevenDays, "Updating an explicitly displayed profile must not depend on whichever Space became active")
        }
    }

    @Test static func anUnknownProfileCannotChangeTheArchivePolicy() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let expected = store.state
            #expect(!store.setAutoArchiveInterval(.never, for: UUID()) && store.state == expected, "A stale or unknown profile target must not change another profile")
        }
    }

    @Test static func independentArchivePoliciesSurviveRestart() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let firstProfile = store.activeSpace.profileID
            let firstSpace = store.activeSpaceID
            store.setAutoArchiveInterval(.twentyFourHours, for: firstProfile)
            let secondProfile = store.createProfile(name: "Second")
            store.assignProfile(secondProfile, toSpace: firstSpace)
            let secondSpace = store.createSpace(name: "Shared profile")
            store.setAutoArchiveInterval(.sevenDays, for: secondProfile)
            store.selectSpace(firstSpace)
            store.assignProfile(firstProfile, toSpace: secondSpace)
            store.setAutoArchiveInterval(.thirtyDays, for: firstProfile)
            let expected = store.state
            try store.save()
            let reopened = try BrowserStore(directory: directory)
            #expect(reopened.state == expected, "Independent per-profile archive policies must survive restart")
        }
    }

    @Test static func legacyArchivePolicyMirrorIsIgnored() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let profile = store.activeSpace.profileID
            store.setAutoArchiveInterval(.sixHours, for: profile)
            try store.save()
            let file = directory.appendingPathComponent("session.json")
            var json = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
            var settings = json["settings"] as! [String: Any]
            settings["autoArchiveHours"] = 720
            json["settings"] = settings
            try JSONSerialization.data(withJSONObject: json).write(to: file)
            let reopened = try BrowserStore(directory: directory)
            #expect(reopened.autoArchiveInterval(for: profile) == .sixHours, "Legacy profile policy must remain authoritative over a stale global mirror")
            reopened.updateSettings { $0.sidebarWidth = 280 }
            #expect(reopened.autoArchiveInterval(for: profile) == .sixHours, "Changing general settings after migration must preserve a hidden older duration")
            try reopened.save()
            let saved = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
            #expect((saved["settings"] as! [String: Any])["autoArchiveHours"] == nil, "New saves must remove the redundant global policy field")
            #expect(AutoArchiveInterval.settingsChoices == [.twelveHours, .twentyFourHours, .sevenDays, .thirtyDays], "Normal Settings choices must match the archive menu, excluding hidden and debug cases")
            #expect(AutoArchiveInterval.never.seconds == nil && AutoArchiveInterval.twentyFourHours.seconds == 86400, "Never must be no threshold, and a day must be exactly 86400 seconds")
        }
    }

    @Test(arguments: [AutoArchiveInterval.never, .oneHour, .sixHours])
    static func aSupportedLegacyArchiveIntervalSurvivesReload(_ interval: AutoArchiveInterval) throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let profile = store.activeSpace.profileID
            store.setAutoArchiveInterval(interval, for: profile)
            try store.save()

            let reopened = try BrowserStore(directory: directory)

            #expect(reopened.autoArchiveInterval(for: profile) == interval)
        }
    }

    @Test(arguments: [-1.0, 2.0, 20.0 / 3600, 999.0])
    static func invalidArchivePoliciesPreserveSession(hours: Double) throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            try store.save()
            let file = directory.appendingPathComponent("session.json")
            let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
            var state = store.state
            state.profiles[0].autoArchiveHours = hours
            let bytes = try encoder.encode(state)
            try bytes.write(to: file)
            var rejected = false
            do { _ = try BrowserStore(directory: directory) } catch { rejected = true }
            #expect(rejected, "Invalid or debug-only persisted policies must not become accidental Never or arbitrary timers")
            #expect(try Data(contentsOf: file) == bytes, "Rejecting an invalid archive policy must preserve the existing session file")
        }
    }

    @Test static func archiveStartMigrationAndStrictBoundary() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            var now = Date(timeIntervalSince1970: 1_800_000_000)
            let store = try BrowserStore(directory: directory, now: { now })
            let old = store.open("https://old.example")
            let selected = store.open("https://selected.example")
            try store.save()
            let file = directory.appendingPathComponent("session.json")
            var json = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
            json.removeValue(forKey: "autoArchiveStartedAt")
            var tabs = json["tabs"] as! [[String: Any]]
            for index in tabs.indices { tabs[index].removeValue(forKey: "isUnread") }
            json["tabs"] = tabs
            try JSONSerialization.data(withJSONObject: json).write(to: file)
            now.addTimeInterval(100 * 86400)
            let migrated = try BrowserStore(directory: directory, now: { now })
            #expect(migrated.state.autoArchiveStartedAt == nil && migrated.state.tabs.allSatisfy { !$0.isUnread }, "Older Parc sessions must migrate absent start to unset and previously selected tabs to read")
            #expect(migrated.archiveExpiredTabs().isEmpty && migrated.state.autoArchiveStartedAt == now, "The first archive run must initialize the global start gate without immediately closing old tabs")
            let started = now
            try migrated.save()
            now.addTimeInterval(12 * 3600)
            let reopened = try BrowserStore(directory: directory, now: { now })
            #expect(reopened.state.autoArchiveStartedAt == started, "Restart must preserve, not reset, the global archive start")
            #expect(reopened.archiveExpiredTabs().isEmpty, "The start gate uses strict greater-than, not equality")
            now.addTimeInterval(1)
            #expect(reopened.archiveExpiredTabs() == [old], "A read inactive tab older than both gates must expire after the boundary")
            #expect(try BrowserStoreTestsSupport.tab(selected, in: reopened).archivedAt == nil, "The existing selected-item exemption must remain intact")
            let startAfter = reopened.state.autoArchiveStartedAt
            reopened.refreshVisibleTabs([selected])
            reopened.archiveExpiredTabs()
            #expect(reopened.state.autoArchiveStartedAt == startAfter, "Activity and later sweeps must not reset the persisted start gate")
        }
    }
}
