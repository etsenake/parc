import Foundation
import Testing
@testable import ParcCore

extension SpaceSharingTestsSupport {
    @MainActor
    struct SpaceSharingArchiveIntervalTests {
        @Test func archiveIntervalsArePerSpace() throws {
            let archive = try Archive()
            #expect(archive.store.autoArchiveInterval(forSpace: archive.first.id) == .twelveHours)
            #expect(archive.store.autoArchiveInterval(forSpace: archive.second.id) == .sevenDays)
        }

        @Test func theArchiveSweepFollowsEachSpacesOwnInterval() throws {
            let archive = try Archive()
            #expect(archive.store.archiveExpiredTabs() == [archive.a.id])
        }

        @Test func settingOneSpacesIntervalLeavesOthersAndTheProfileAlone() throws {
            let archive = try Archive()
            #expect(try archive.store.setAutoArchiveInterval(.thirtyDays, forSpace: archive.first.id))
            #expect(archive.store.autoArchiveInterval(forSpace: archive.first.id) == .thirtyDays)
            #expect(archive.store.autoArchiveInterval(forSpace: archive.second.id) == .sevenDays)
            #expect(archive.store.state.profiles[0].autoArchiveHours == AutoArchiveInterval.twelveHours.rawValue)
        }

        @Test func changingASpaceArchiveIntervalPersistsIt() throws {
            let archive = try Archive()
            _ = try archive.store.setAutoArchiveInterval(.thirtyDays, forSpace: archive.first.id)
            #expect(try archive.folder.store().autoArchiveInterval(forSpace: archive.first.id) == .thirtyDays)
        }

        @Test func anUnchangedSpaceArchiveIntervalWritesNothing() throws {
            let archive = try Archive()
            _ = try archive.store.setAutoArchiveInterval(.thirtyDays, forSpace: archive.first.id)
            #expect(try !archive.store.setAutoArchiveInterval(.thirtyDays, forSpace: archive.first.id))
        }

        @Test func aNewSpaceInheritsTheCreatingSpacesInterval() throws {
            let archive = try Archive()
            _ = try archive.store.setAutoArchiveInterval(.thirtyDays, forSpace: archive.first.id)
            let created = archive.store.createSpace(name: "New")
            #expect(archive.store.autoArchiveInterval(forSpace: created) == .thirtyDays)
        }

        @Test func aProfileSettingReachesItsSpaces() throws {
            let archive = try Archive()
            _ = try archive.store.changeAutoArchiveInterval(.oneHour, for: archive.first.profileID)
            #expect(archive.store.state.spaces.allSatisfy { $0.autoArchiveHours == AutoArchiveInterval.oneHour.rawValue })
        }

        @Test func aMissingOrInvalidIntervalDecodesAsNil() throws {
            let archive = try Archive()
            var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(archive.second)) as? [String: Any])
            json.removeValue(forKey: "autoArchiveHours")
            #expect(try JSONDecoder().decode(BrowserSpace.self, from: JSONSerialization.data(withJSONObject: json)).autoArchiveHours == nil)
            json["autoArchiveHours"] = 5
            #expect(try JSONDecoder().decode(BrowserSpace.self, from: JSONSerialization.data(withJSONObject: json)).autoArchiveHours == nil)
        }
    }
}
