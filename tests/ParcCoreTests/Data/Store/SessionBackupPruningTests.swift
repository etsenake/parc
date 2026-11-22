import Foundation
import Testing
@testable import ParcCore

struct SessionBackupPruningTests {
    private typealias Support = SessionBackupTestsSupport

    @Test @MainActor static func forgettingAVisitKeepsOnlyBackupsThatContainCurrentOrUnrelatedURLs() throws {
        try Support.withDirectory { directory in
            let clock = Support.Clock(Support.base)
            let store = try Support.backingStore(directory, clock)
            _ = store.openResolvedURL(URL(string: "https://kept.test/")!)
            try Support.flush(store)
            clock.now = Support.base.addingTimeInterval(7_200)
            let gone = store.openResolvedURL(URL(string: "https://gone.test/")!)
            try Support.flush(store)
            #expect(SessionBackups.list(in: directory).count == 2, "Two copies exist")
            store.closeTab(gone)
            store.deleteArchivedTabs([gone])
            try Support.flush(store)
            store.forgetHistory(Support.deletion(["urls": ["https://kept.test/"], "hosts": ["kept.test"]]))
            try Support.flush(store)
            #expect(SessionBackups.list(in: directory).count == 2, "Deleting an address the sidebar still holds leaves copies that only hold it too")
            store.forgetHistory(Support.deletion(["urls": ["https://gone.test/"], "hosts": ["gone.test"]]))
            try Support.flush(store)
            #expect(try Support.texts(directory).allSatisfy { !$0.contains(Support.escaped("https://gone.test/")) }, "Deleting a visit removes every copy that still holds that address")
            #expect(try Support.texts(directory).contains { $0.contains(Support.escaped("https://kept.test/")) }, "Unrelated copies stay")
        }
    }

    @Test @MainActor static func clearingHistoryInATimeRangePrunesOnlyRecentBackups() throws {
        try Support.withDirectory { directory in
            let clock = Support.Clock(Support.base)
            let store = try Support.backingStore(directory, clock)
            _ = store.openResolvedURL(URL(string: "https://kept.test/")!)
            try Support.flush(store)
            clock.now = Support.base.addingTimeInterval(4 * 3_600)
            _ = store.openResolvedURL(URL(string: "https://later.test/")!)
            try Support.flush(store)
            let before = SessionBackups.list(in: directory)
            let begin = Support.base.addingTimeInterval(3 * 3_600)
            clock.now = Support.base.addingTimeInterval(4 * 3_600 + 60)
            store.forgetHistory(Support.deletion(["timeRange": true, "begin": begin.timeIntervalSinceReferenceDate,
                                          "end": Double.greatestFiniteMagnitude, "urls": [String]()]))
            try Support.flush(store)
            let after = SessionBackups.list(in: directory)
            #expect(before.contains { $0.date >= begin } && !after.contains { $0.date >= begin && $0.date < clock.now }, "Clearing a time range removes copies taken since it began")
            #expect(after.contains { $0.date < begin }, "Copies from before the range stay")
        }
    }

    @Test @MainActor static func clearingAllHistoryLeavesOnlyAFreshSidebarBackup() throws {
        try Support.withDirectory { directory in
            let clock = Support.Clock(Support.base)
            let store = try Support.backingStore(directory, clock)
            _ = store.openResolvedURL(URL(string: "https://kept.test/")!)
            try Support.flush(store)
            clock.now = Support.base.addingTimeInterval(4 * 3_600)
            _ = store.openResolvedURL(URL(string: "https://later.test/")!)
            try Support.flush(store)
            clock.now = Support.base.addingTimeInterval(5 * 3_600)
            store.forgetHistory(Support.deletion(["allHistory": true]))
            try Support.flush(store)
            let fresh = SessionBackups.list(in: directory)
            #expect(fresh.count == 1 && fresh[0].date == clock.now, "Clearing all history leaves only a fresh copy of today's sidebar")
            #expect(try Support.texts(directory)[0].contains(Support.escaped("https://later.test/")), "The fresh copy matches the main file")
        }
    }

    struct WriteOrderCase: Sendable, CustomTestStringConvertible {
        let testDescription: String
        let offsets: [Double]
        let start: Double
        let expected: [Double]
    }

    @Test(arguments: [
        WriteOrderCase(testDescription: "Date drops after the first affected write", offsets: [-864_000, -86_400, -691_200],
                       start: -3_600, expected: [-691_200, -86_400]),
        WriteOrderCase(testDescription: "Clock moves back across the cutoff", offsets: [-864_000, -600, -432_000],
                       start: -3_600, expected: [-432_000, -600]),
        WriteOrderCase(testDescription: "Future stamp before the clock correction", offsets: [-864_000, 31_536_000, -1_800],
                       start: -900, expected: [-1_800, 31_536_000]),
        WriteOrderCase(testDescription: "Two older writes with the same time", offsets: [-7_200, -7_200, -600],
                       start: -3_600, expected: [-600]),
    ])
    static func rangeClearsFollowWriteOrder(_ input: WriteOrderCase) {
        func written(_ offsets: [Double]) -> [SessionBackups.Backup] {
            offsets.enumerated().map { index, offset in
                let date = Support.base.addingTimeInterval(offset)
                return .init(url: Support.folder.appendingPathComponent(SessionBackups.name(for: date, sequence: index + 1)),
                             date: date, sequence: index + 1)
            }
        }
        func removed(_ offsets: [Double], since start: Double) -> [Double] {
            SessionBackups.Pruning.since(Support.base.addingTimeInterval(start)).removed(from: written(offsets))
                .map { $0.date.timeIntervalSince(Support.base) }.sorted()
        }
        #expect(removed(input.offsets, since: input.start) == input.expected)
    }

    @Test
    @MainActor
    static func historyRangeClearPrunesBackupsWrittenWithAClockSetBehind() throws {
        let day = 86_400.0
        try Support.withDirectory { directory in
            let clock = Support.Clock(Support.base.addingTimeInterval(-day))
            let store = try Support.backingStore(directory, clock)
            _ = store.openResolvedURL(URL(string: "https://before.test/")!)
            try Support.flush(store)
            clock.now = Support.base.addingTimeInterval(-8 * day)
            _ = store.openResolvedURL(URL(string: "https://behind.test/")!)
            try Support.flush(store)
            #expect(SessionBackups.list(in: directory).map(\.date) == [-8 * day, -day].map(Support.base.addingTimeInterval), "A copy is taken while the clock is set behind")
            clock.now = Support.base
            store.forgetHistory(Support.deletion(["timeRange": true, "begin": Support.base.addingTimeInterval(-3_600).timeIntervalSinceReferenceDate,
                                          "end": Double.greatestFiniteMagnitude, "urls": [String]()]))
            try Support.flush(store)
            #expect(SessionBackups.list(in: directory).map(\.date) == [Support.base], "Clearing the last hour removes the copy really taken in it, leaving only a fresh copy")
        }
    }

    @Test(arguments: [true, false], [-2_592_000.0, -257_400.0, 43_200.5, 43_201.5, 2_592_000.0])
    static func aRangeClearFollowsBackupDatesWhenTheClockIsSteady(_ sequenced: Bool, _ offset: Double) {
        let backups = Support.chronological(Support.busyDates, sequenced: sequenced)
        let start = Support.base.addingTimeInterval(offset)
        let withinRange = Set(backups.filter { $0.date.timeIntervalSince(start) > -1 }.map(\.url))

        #expect(Set(SessionBackups.Pruning.since(start).removed(from: backups).map(\.url)) == withinRange)
    }

    @Test
    static func addressPruningMatchesWholeAddresses() throws {
        try Support.withDirectory { directory in
            let single = SessionBackups.Pruning(Support.deletion(["urls": ["https://a.test/x"], "hosts": ["a.test"]]))
            let longer = Data("{\"url\" : \"https:\\/\\/a.test\\/x2\"}".utf8)
            let exact = Data("{\"url\" : \"https:\\/\\/a.test\\/x\"}".utf8)
            #expect(single?.excluding(longer) != nil, "A longer address in the sidebar isn't the deleted one")
            #expect(single?.excluding(exact) == nil, "The same address still in the sidebar keeps older copies")
            let folder = SessionBackups.folder(in: directory)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
            try longer.write(to: folder.appendingPathComponent(SessionBackups.name(for: Support.base, sequence: 1)))
            try exact.write(to: folder.appendingPathComponent(SessionBackups.name(for: Support.base.addingTimeInterval(60), sequence: 2)))
            SessionBackups.prune(single!, in: directory)
            #expect(SessionBackups.list(in: directory).map(\.date) == [Support.base], "Only the copy holding that exact address goes")
        }
    }

    @Test
    static func historyPageDeletionUsesAddressPruning() throws {
        let day = Support.base.timeIntervalSinceReferenceDate
        let page = SessionBackups.Pruning(Support.deletion(["timeRange": true, "begin": day, "end": day + 86_400,
                                                     "restrictURLs": ["https://a.test/x"], "urls": [String]()]))
        if case .addresses = page {} else { throw Support.Failure(description: "A history-page delete uses the address rule") }
    }

    @Test
    static func removedProfileIsNotExcludedFromPruningWhenItsIDRemains() throws {
        let profile = UUID()
        #expect(SessionBackups.Pruning.profile(profile).excluding(Data(profile.uuidString.utf8)) != nil, "A removed Profile prunes even if its ID lingers in the sidebar")
    }

    @Test @MainActor static func clearArchivePrunesBackups() throws {
        try Support.withDirectory { directory in
            let clock = Support.Clock(Support.base)
            let store = try Support.backingStore(directory, clock)
            let tab = store.openResolvedURL(URL(string: "https://archived.test/")!)
            try Support.flush(store)
            clock.now = Support.base.addingTimeInterval(7_200)
            store.closeTab(tab)
            try Support.flush(store)
            #expect(try Support.texts(directory).allSatisfy { $0.contains(Support.escaped("https://archived.test/")) }, "Copies hold the closed tab")
            store.clearArchive(profileID: store.activeSpace.profileID)
            try Support.flush(store)
            #expect(!store.state.tabs.contains { $0.id == tab }, "The archive is cleared")
            #expect(SessionBackups.list(in: directory).count == 1, "Only a fresh copy remains")
            #expect(try Support.texts(directory).allSatisfy { !$0.contains("archived.test") }, "No copy keeps the cleared tab")
        }
    }

    @Test @MainActor static func removingASpacesDataPrunesBackups() throws {
        try Support.withDirectory { directory in
            let clock = Support.Clock(Support.base)
            let store = try Support.backingStore(directory, clock)
            let spaceID = try store.createSpace(name: "Secret", sharing: .separate)
            let profileID = store.state.spaces.first { $0.id == spaceID }!.profileID
            store.selectSpace(spaceID)
            _ = store.openResolvedURL(URL(string: "https://space-secret.test/")!)
            try Support.flush(store)
            clock.now = Support.base.addingTimeInterval(7_200)
            let target = SpaceDeletionTarget(spaceID: spaceID, state: store.state)!
            var deleted: Bool?
            store.deleteSpace(target, documents: [:], shouldCommit: { true }, didCommit: { _ in }) {
                if case .success(let value) = $0 { deleted = value }
            }
            try Support.flush(store)
            #expect(deleted == true, "The Space is deleted")
            #expect(try Support.texts(directory).contains { $0.contains("space-secret.test") }, "A deleted Space's tabs are still in the Archive, so copies may hold them")
            let record = try store.stageRemoval(of: store.unusedProfile(profileID)!)
            clock.now = Support.base.addingTimeInterval(7_300)
            try store.finishProfileRemoval(record)
            try Support.flush(store)
            #expect(!store.state.profiles.contains { $0.id == profileID }, "The Space's data is removed")
            #expect(!SessionBackups.list(in: directory).isEmpty, "A fresh copy is kept")
            #expect(try Support.texts(directory).allSatisfy { !$0.contains("space-secret.test") && !$0.contains(profileID.uuidString) }, "No copy keeps the removed data")
        }
    }
}
