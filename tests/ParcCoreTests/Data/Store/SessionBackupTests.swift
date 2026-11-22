import Foundation
import Testing
@testable import ParcCore

struct SessionBackupTests {
    private struct Failure: Error, CustomStringConvertible { let description: String }

    private final class Clock { var now: Date; init(_ now: Date) { self.now = now } }

    private static let base = Date(timeIntervalSince1970: 1_794_844_800)

    private static func withDirectory(_ body: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("parc-session-backups-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(directory)
    }

    private static var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private static func texts(_ directory: URL) throws -> [String] {
        try SessionBackups.list(in: directory).map { String(decoding: try Data(contentsOf: $0.url), as: UTF8.self) }
    }

    private static func escaped(_ url: String) -> String { url.replacingOccurrences(of: "/", with: "\\/") }

    @MainActor
    private static func backingStore(_ directory: URL, _ clock: Clock) throws -> BrowserStore {
        try BrowserStore(directory: directory, now: { clock.now }, keepsBackups: true)
    }

    @MainActor
    private static func flush(_ store: BrowserStore) throws { try store.save() }

    private static let folder = URL(fileURLWithPath: "/backups", isDirectory: true)

    private static func chronological(_ dates: [Date], sequenced: Bool = true) -> [SessionBackups.Backup] {
        dates.sorted().enumerated().map { index, date in
            .init(url: folder.appendingPathComponent(SessionBackups.name(for: date, sequence: index + 1)), date: date,
                  sequence: sequenced ? index + 1 : 0)
        }
    }

    private static func stamped(_ url: URL) -> Date? { SessionBackups.backup(named: url.lastPathComponent, in: folder)?.date }

    private static var busyDates: [Date] {
        (0..<10).flatMap { daysAgo in
            (8...20).map { hour in base.addingTimeInterval(Double(-daysAgo * 86_400 + hour * 3_600)) }
        }
    }

    @Test
    static func retentionKeepsSixRecentAndSevenDailyCopies() throws {
        let dates = busyDates
        let backups = chronological(dates)
        let kept = SessionBackups.retained(backups, calendar: utc)
        let newest = backups.sorted { $0.date > $1.date }
        #expect(Set(newest.prefix(6).map(\.url)).isSubset(of: kept), "The six newest copies stay")
        let mornings = (0..<7).map { base.addingTimeInterval(Double(-$0 * 86_400 + 8 * 3_600)) }
        #expect(mornings.allSatisfy { date in kept.contains { stamped($0) == date } }, "The first copy of each of the seven latest days stays")
        #expect(kept.count == 13, "Nothing else stays: six recent plus seven daily copies")
        let stale = base.addingTimeInterval(Double(-7 * 86_400 + 8 * 3_600))
        #expect(!kept.contains { stamped($0) == stale }, "An eighth day is pruned")
    }

    @Test
    static func steadyClockMakesSequenceAndTimestampRetentionAgree() throws {
        let dates = busyDates
        let backups = chronological(dates)
        let kept = SessionBackups.retained(backups, calendar: utc)
        let newest = backups.sorted { $0.date > $1.date }
        #expect(kept == SessionBackups.retained(chronological(dates, sequenced: false), calendar: utc), "With a correct clock, write order keeps exactly the copies their times would")
        #expect(backups.sorted { $0.isNewer(than: $1) } == newest, "With a correct clock, the newest copy is the latest time")
    }

    @Test
    static func infrequentUseDoesNotAgeOutBackups() throws {
        let sparse = chronological([-40, -25, -9, 0].map { base.addingTimeInterval(Double($0 * 86_400)) })
        #expect(SessionBackups.retained(sparse, calendar: utc).count == 4, "Days without use don't push older copies out")
    }

    @Test(arguments: [(SessionBackups.name(for: base, sequence: 3), 3), ("session-20261116T160000.json", 0)])
    static func backupNamesRoundTripTheirTimestampAndSequence(_ name: String, _ sequence: Int) throws {
        let backup = SessionBackups.backup(named: name, in: folder)
        #expect(backup?.date == base && backup?.sequence == sequence)
    }

    @Test
    static func numberedBackupsSortAfterLegacyBackups() throws {
        let named = SessionBackups.backup(named: SessionBackups.name(for: base, sequence: 3), in: folder)
        let legacy = SessionBackups.backup(named: "session-20261116T160000.json", in: folder)
        #expect(named.flatMap { first in legacy.map { first.isNewer(than: $0) } } == true, "Numbered copies were all taken after unnumbered ones")
    }

    @Test(arguments: ["session.json", ".backup-123.json", "session-unreadable-20261116T160000.json",
                      "session-20261116T160000-0.json", "session-20261116T160000-x.json",
                      "session-20261116T160000-9223372036854775807.json"])
    static func nonBackupNamesDoNotParse(_ name: String) throws {
        #expect(SessionBackups.backup(named: name, in: folder) == nil)
    }

    private static let ahead = base.addingTimeInterval(365 * 86_400)

    private static var backupsAfterClockCorrection: [SessionBackups.Backup] {
        let wrong = (0..<6).map { ahead.addingTimeInterval(Double($0 * 3_600)) }
        let fixed = (0..<6).map { base.addingTimeInterval(Double($0 * 3_600)) }
        return (wrong + fixed).enumerated().map { index, date in
            SessionBackups.Backup(url: folder.appendingPathComponent(SessionBackups.name(for: date, sequence: index + 1)),
                                  date: date, sequence: index + 1)
        }
    }

    @Test
    static func correctingTheClockKeepsRecentWritesAndTheFirstCopyOfTheFutureDay() throws {
        let backups = backupsAfterClockCorrection
        let kept = SessionBackups.retained(backups, calendar: utc)
        #expect(Set(backups.suffix(6).map(\.url)).isSubset(of: kept), "The six copies taken after the clock was fixed stay, though older copies are stamped later")
        #expect(kept.subtracting(backups.suffix(6).map(\.url)) == [backups[0].url], "Of the copies stamped ahead, only the first of that day stays")
    }

    @Test
    static func futureDatedCopiesAgeOutAfterAWeekOfNewWrites() throws {
        let backups = backupsAfterClockCorrection
        var later = backups
        for day in 1...7 {
            let date = base.addingTimeInterval(Double(day * 86_400))
            later.append(.init(url: folder.appendingPathComponent(SessionBackups.name(for: date, sequence: later.count + 1)),
                               date: date, sequence: later.count + 1))
        }
        #expect(SessionBackups.retained(later, calendar: utc).isDisjoint(with: backups.prefix(6).map(\.url)), "After a week of use the copies stamped ahead age out instead of waiting a year")
    }

    @MainActor
    private static func withClockCorrection(_ body: (URL, BrowserStore, SessionBackups, [Date]) throws -> Void) throws {
        try withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let writer = SessionBackups(directory: directory, calendar: utc)
            let taken = [("https://before.test/", base), ("https://ahead-1.test/", ahead),
                         ("https://ahead-2.test/", ahead.addingTimeInterval(3_600))]
            for (address, date) in taken {
                _ = store.openResolvedURL(URL(string: address)!)
                try writer.backUp(store.state, at: date)
            }
            let relaunched = SessionBackups(directory: directory, calendar: utc)
            try body(directory, store, relaunched, taken.map(\.1))
            try store.save()
        }
    }

    @Test
    @MainActor
    static func aRelaunchResumesHourlyBackupsAfterClockCorrection() throws {
        try withClockCorrection { directory, store, relaunched, _ in
            _ = store.openResolvedURL(URL(string: "https://fixed.test/")!)
            relaunched.backUpIfDue(store.state, at: base.addingTimeInterval(1_800))
            #expect(SessionBackups.list(in: directory).count == 4, "A copy stamped ahead doesn't hold off the next backup once the clock is fixed")
            _ = store.openResolvedURL(URL(string: "https://soon.test/")!)
            relaunched.backUpIfDue(store.state, at: base.addingTimeInterval(2_400))
            #expect(SessionBackups.list(in: directory).count == 4, "The hourly pace resumes from that copy")
        }
    }

    @Test
    @MainActor
    static func copiesListInWriteOrderAfterClockCorrection() throws {
        try withClockCorrection { directory, store, relaunched, taken in
            _ = store.openResolvedURL(URL(string: "https://fixed.test/")!)
            relaunched.backUpIfDue(store.state, at: base.addingTimeInterval(1_800))
            #expect(SessionBackups.list(in: directory).map(\.date)
                        == [base.addingTimeInterval(1_800)] + taken.reversed(), "Copies list in the order they were taken, not by their stamps")
        }
    }

    @Test
    @MainActor
    static func rescuePrefersTheLastWriteAfterClockCorrection() throws {
        try withClockCorrection { directory, store, relaunched, _ in
            _ = store.openResolvedURL(URL(string: "https://fixed.test/")!)
            relaunched.backUpIfDue(store.state, at: base.addingTimeInterval(1_800))
            let newest = SessionBackups.restorable(in: directory).first.map { String(decoding: $0.data, as: UTF8.self) }
            #expect(newest?.contains(escaped("https://fixed.test/")) == true, "The rescue offers the copy taken last, not the one stamped furthest ahead")
        }
    }

    @MainActor
    private static func withFirstBackup(_ body: (URL, BrowserStore, Clock) throws -> Void) throws {
        try withDirectory { directory in
            let clock = Clock(base)
            let store = try backingStore(directory, clock)
            _ = store.openResolvedURL(URL(string: "https://first.test/")!)
            store.recordDownload(["id": 7, "name": "file.zip", "path": "/tmp/file.zip", "sourceURL": "https://download.test/file.zip"])
            try flush(store)
            try body(directory, store, clock)
        }
    }

    @Test
    @MainActor
    static func theFirstSaveWritesAPrivateBackup() throws {
        try withFirstBackup { directory, _, _ in
            #expect(SessionBackups.list(in: directory).count == 1, "The first save makes a backup")
            let folder = SessionBackups.folder(in: directory)
            let folderMode = try FileManager.default.attributesOfItem(atPath: folder.path)[.posixPermissions] as? NSNumber
            let copy = try #require(SessionBackups.list(in: directory).first)
            let fileMode = try FileManager.default.attributesOfItem(atPath: copy.url.path)[.posixPermissions] as? NSNumber
            #expect(folderMode?.intValue == 0o700 && fileMode?.intValue == 0o600, "Backups are private to this account")
        }
    }

    @Test
    @MainActor
    static func backupsKeepOpenTabsButNotDownloadsOrHistory() throws {
        try withFirstBackup { directory, _, _ in
            let first = try BrowserStore.savedSession(from: Data(contentsOf: SessionBackups.list(in: directory)[0].url))
            #expect(first.downloads.isEmpty && first.history.isEmpty, "Backups hold the sidebar, not downloads or history")
            #expect(try texts(directory)[0].contains(escaped("https://first.test/")), "The backup holds the open tab")
            #expect(!(try texts(directory)[0].contains("download.test")), "No download address reaches a backup")
        }
    }

    @Test
    @MainActor
    static func theMainSessionStillKeepsDownloads() throws {
        try withFirstBackup { directory, _, _ in
            let reopened = try BrowserStore(directory: directory)
            #expect(reopened.state.downloads.count == 1, "The main file still keeps downloads")
        }
    }

    @Test
    @MainActor
    static func changedSidebarBackupsFollowHourlyCadence() throws {
        try withFirstBackup { directory, store, clock in
            clock.now = base.addingTimeInterval(600)
            _ = store.openResolvedURL(URL(string: "https://second.test/")!)
            try flush(store)
            #expect(SessionBackups.list(in: directory).count == 1, "Saves within the hour don't add copies")
            clock.now = base.addingTimeInterval(3_700)
            _ = store.openResolvedURL(URL(string: "https://third.test/")!)
            try flush(store)
            #expect(SessionBackups.list(in: directory).count == 2, "The first save after an hour adds a copy")
            #expect(try texts(directory)[0].contains(escaped("https://third.test/")), "The new copy is the current sidebar")
        }
    }

    @Test
    @MainActor
    static func unchangedSidebarsAreNotBackedUpAgain() throws {
        try withFirstBackup { directory, store, clock in
            clock.now = base.addingTimeInterval(9_000)
            try flush(store)
            #expect(SessionBackups.list(in: directory).count == 1, "An unchanged sidebar isn't copied again")
        }
    }

    @MainActor
    private static func withSavedSidebar(_ body: (URL, Clock) throws -> Void) throws {
        try withDirectory { directory in
            let plain = try BrowserStore(directory: directory)
            _ = plain.openResolvedURL(URL(string: "https://launch.test/")!)
            try plain.save()
            try body(directory, Clock(base))
        }
    }

    @Test
    @MainActor
    static func aStoreWithoutBackupsWritesNone() throws {
        try withSavedSidebar { directory, _ in
            #expect(SessionBackups.list(in: directory).isEmpty, "A store without backups writes none")
        }
    }

    @Test
    @MainActor
    static func aValidatedSidebarIsBackedUpAtLaunch() throws {
        try withSavedSidebar { directory, clock in
            try flush(try backingStore(directory, clock))
            #expect(try texts(directory).first?.contains(escaped("https://launch.test/")) == true, "A sidebar that loaded and validated is backed up at launch")
        }
    }

    @Test
    @MainActor
    static func relaunchBackupsFollowHourlyCadence() throws {
        try withSavedSidebar { directory, clock in
            try flush(try backingStore(directory, clock))
            let changed = try BrowserStore(directory: directory)
            _ = changed.openResolvedURL(URL(string: "https://changed.test/")!)
            try changed.save()
            clock.now = base.addingTimeInterval(600)
            try flush(try backingStore(directory, clock))
            #expect(SessionBackups.list(in: directory).count == 1, "Relaunching within the hour adds no copy")
            clock.now = base.addingTimeInterval(3_700)
            try flush(try backingStore(directory, clock))
            #expect(SessionBackups.list(in: directory).count == 2, "Relaunching after an hour copies the changed sidebar")
        }
    }

    @Test
    static func invalidStatesAreNotBackedUp() throws {
        try withDirectory { directory in
            var invalid = BrowserState.initial()
            let space = invalid.spaces[0]
            invalid.tabs = [BrowserTab(id: UUID(), spaceID: UUID(), profileID: space.profileID, url: "https://x.test/",
                                       title: "x", kind: .today, createdAt: base, lastAccessed: base,
                                       savedURL: "https://x.test/", savedTitle: "x")]
            let backups = SessionBackups(directory: directory, calendar: utc)
            var refused = false
            do { try backups.backUp(invalid, at: base) } catch { refused = true }
            #expect(refused, "A state that fails validation is refused")
            backups.backUpIfDue(invalid, at: base)
            #expect(!FileManager.default.fileExists(atPath: SessionBackups.folder(in: directory).path), "No copy of it is written")
        }
    }

    @Test
    @MainActor
    static func anUnreadableSessionIsReportedAndNotBackedUp() throws {
        try withDirectory { directory in
            try Data("{\"broken\":".utf8).write(to: directory.appendingPathComponent("session.json"))
            var unreadable = false
            do { _ = try backingStore(directory, Clock(base)) } catch is SessionFileUnreadable { unreadable = true }
            #expect(unreadable, "An unreadable main file is reported as such")
            #expect(SessionBackups.list(in: directory).isEmpty, "An unreadable main file is never backed up")
        }
    }

    @MainActor
    private static func seedTwoRestorableBackups(in directory: URL) throws -> BrowserState {
        let older = try BrowserStore(directory: directory)
        _ = older.openResolvedURL(URL(string: "https://older.test/")!)
        let backups = SessionBackups(directory: directory, calendar: utc)
        try backups.backUp(older.state, at: base)
        _ = older.openResolvedURL(URL(string: "https://newer.test/")!)
        try backups.backUp(older.state, at: base.addingTimeInterval(3_600))
        return older.state
    }

    @Test @MainActor static func rescueListsOnlyUsableBackupsInNewestFirstOrder() throws {
        try withDirectory { directory in
            var dangling = try seedTwoRestorableBackups(in: directory)
            let folder = SessionBackups.folder(in: directory)
            try Data("not json".utf8).write(to: folder.appendingPathComponent(SessionBackups.name(for: base.addingTimeInterval(7_200), sequence: 3)))
            dangling.activeSpaceID = UUID()
            let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(dangling).write(to: folder.appendingPathComponent(SessionBackups.name(for: base.addingTimeInterval(10_800), sequence: 4)))
            let candidates = SessionBackups.restorable(in: directory)
            #expect(candidates.map(\.backup.date) == [base.addingTimeInterval(3_600), base], "Rescue offers the newest backup that loads and validates, then older ones")
        }
    }

    @Test(arguments: [true, false]) @MainActor static func rescueCanRestoreEitherUsableBackup(_ useNewest: Bool) throws {
        try withDirectory { directory in
            _ = try seedTwoRestorableBackups(in: directory)
            let candidates = SessionBackups.restorable(in: directory)
            let chosen = try #require(useNewest ? candidates.first : candidates.last)
            try Data("{\"spaces\": [".utf8).write(to: directory.appendingPathComponent("session.json"))
            _ = try SessionBackups.restore(chosen.data, in: directory, at: base)
            let restored = try BrowserStore(directory: directory)
            #expect(restored.state.tabs.contains { $0.url == "https://older.test/" })
            #expect(restored.state.tabs.contains { $0.url == "https://newer.test/" } == useNewest)
        }
    }

    @Test @MainActor static func rescuesWithinTheSameSecondPreserveBothUnreadableFiles() throws {
        try withDirectory { directory in
            _ = try seedTwoRestorableBackups(in: directory)
            let candidates = SessionBackups.restorable(in: directory)
            let newest = try #require(candidates.first)
            let oldest = try #require(candidates.last)
            let damaged = Data("{\"spaces\": [".utf8)
            try damaged.write(to: directory.appendingPathComponent("session.json"))
            var unreadable = false
            do { _ = try BrowserStore(directory: directory) } catch is SessionFileUnreadable { unreadable = true }
            #expect(unreadable, "The damaged file is reported as unreadable")
            let now = base.addingTimeInterval(20_000)
            let aside = try SessionBackups.restore(newest.data, in: directory, at: now)
            #expect(try aside.map { try Data(contentsOf: $0) } == damaged, "The unreadable file is kept byte for byte")
            #expect(aside?.lastPathComponent.hasPrefix("session-unreadable-") == true, "It is kept under a clear name")
            try Data("garbage".utf8).write(to: directory.appendingPathComponent("session.json"))
            let second = try SessionBackups.restore(oldest.data, in: directory, at: now)
            #expect(try second != aside && second.map { try Data(contentsOf: $0) } == Data("garbage".utf8), "A second rescue in the same second keeps both unreadable files")
            #expect(try aside.map { try Data(contentsOf: $0) } == damaged, "The first kept file is untouched")
        }
    }

    @Test @MainActor static func noBackupLeavesTheFileAlone() throws {
        try withDirectory { directory in
            let damaged = Data("{".utf8)
            try damaged.write(to: directory.appendingPathComponent("session.json"))
            #expect(SessionBackups.restorable(in: directory).isEmpty, "No backups means nothing to offer")
            let folder = SessionBackups.folder(in: directory)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
            try Data("{}".utf8).write(to: folder.appendingPathComponent(SessionBackups.name(for: base, sequence: 1)))
            #expect(SessionBackups.restorable(in: directory).isEmpty, "Unreadable backups are never offered")
            var unreadable = false
            do { _ = try BrowserStore(directory: directory, keepsBackups: true) } catch is SessionFileUnreadable { unreadable = true }
            #expect(unreadable, "Startup still stops on the unreadable file")
            #expect(try Data(contentsOf: directory.appendingPathComponent("session.json")) == damaged, "The file is untouched")
            #expect(SessionBackups.list(in: directory).count == 1, "Existing backups are left as they were")
        }
    }

    private static func deletion(_ info: [AnyHashable: Any]) -> ChromiumHistoryDeletion { ChromiumHistoryDeletion(userInfo: info) }

    @Test @MainActor static func forgettingAVisitKeepsOnlyBackupsThatContainCurrentOrUnrelatedURLs() throws {
        try withDirectory { directory in
            let clock = Clock(base)
            let store = try backingStore(directory, clock)
            _ = store.openResolvedURL(URL(string: "https://kept.test/")!)
            try flush(store)
            clock.now = base.addingTimeInterval(7_200)
            let gone = store.openResolvedURL(URL(string: "https://gone.test/")!)
            try flush(store)
            #expect(SessionBackups.list(in: directory).count == 2, "Two copies exist")
            store.closeTab(gone)
            store.deleteArchivedTabs([gone])
            try flush(store)
            store.forgetHistory(deletion(["urls": ["https://kept.test/"], "hosts": ["kept.test"]]))
            try flush(store)
            #expect(SessionBackups.list(in: directory).count == 2, "Deleting an address the sidebar still holds leaves copies that only hold it too")
            store.forgetHistory(deletion(["urls": ["https://gone.test/"], "hosts": ["gone.test"]]))
            try flush(store)
            #expect(try texts(directory).allSatisfy { !$0.contains(escaped("https://gone.test/")) }, "Deleting a visit removes every copy that still holds that address")
            #expect(try texts(directory).contains { $0.contains(escaped("https://kept.test/")) }, "Unrelated copies stay")
        }
    }

    @Test @MainActor static func clearingHistoryInATimeRangePrunesOnlyRecentBackups() throws {
        try withDirectory { directory in
            let clock = Clock(base)
            let store = try backingStore(directory, clock)
            _ = store.openResolvedURL(URL(string: "https://kept.test/")!)
            try flush(store)
            clock.now = base.addingTimeInterval(4 * 3_600)
            _ = store.openResolvedURL(URL(string: "https://later.test/")!)
            try flush(store)
            let before = SessionBackups.list(in: directory)
            let begin = base.addingTimeInterval(3 * 3_600)
            clock.now = base.addingTimeInterval(4 * 3_600 + 60)
            store.forgetHistory(deletion(["timeRange": true, "begin": begin.timeIntervalSinceReferenceDate,
                                          "end": Double.greatestFiniteMagnitude, "urls": [String]()]))
            try flush(store)
            let after = SessionBackups.list(in: directory)
            #expect(before.contains { $0.date >= begin } && !after.contains { $0.date >= begin && $0.date < clock.now }, "Clearing a time range removes copies taken since it began")
            #expect(after.contains { $0.date < begin }, "Copies from before the range stay")
        }
    }

    @Test @MainActor static func clearingAllHistoryLeavesOnlyAFreshSidebarBackup() throws {
        try withDirectory { directory in
            let clock = Clock(base)
            let store = try backingStore(directory, clock)
            _ = store.openResolvedURL(URL(string: "https://kept.test/")!)
            try flush(store)
            clock.now = base.addingTimeInterval(4 * 3_600)
            _ = store.openResolvedURL(URL(string: "https://later.test/")!)
            try flush(store)
            clock.now = base.addingTimeInterval(5 * 3_600)
            store.forgetHistory(deletion(["allHistory": true]))
            try flush(store)
            let fresh = SessionBackups.list(in: directory)
            #expect(fresh.count == 1 && fresh[0].date == clock.now, "Clearing all history leaves only a fresh copy of today's sidebar")
            #expect(try texts(directory)[0].contains(escaped("https://later.test/")), "The fresh copy matches the main file")
        }
    }

    @Test(arguments: [
        ([-864_000.0, -86_400, -691_200], -3_600.0, [-691_200.0, -86_400]),
        ([-864_000.0, -600, -432_000], -3_600.0, [-432_000.0, -600]),
        ([-864_000.0, 31_536_000, -1_800], -900.0, [-1_800.0, 31_536_000]),
        ([-7_200.0, -7_200, -600], -3_600.0, [-600.0]),
    ])
    static func rangeClearsFollowWriteOrder(_ offsets: [Double], _ start: Double, _ expected: [Double]) throws {
        func written(_ offsets: [Double]) -> [SessionBackups.Backup] {
            offsets.enumerated().map { index, offset in
                let date = base.addingTimeInterval(offset)
                return .init(url: folder.appendingPathComponent(SessionBackups.name(for: date, sequence: index + 1)),
                             date: date, sequence: index + 1)
            }
        }
        func removed(_ offsets: [Double], since start: Double) -> [Double] {
            SessionBackups.Pruning.since(base.addingTimeInterval(start)).removed(from: written(offsets))
                .map { $0.date.timeIntervalSince(base) }.sorted()
        }
        #expect(removed(offsets, since: start) == expected)
    }

    @Test
    @MainActor
    static func historyRangeClearPrunesBackupsWrittenWithAClockSetBehind() throws {
        let day = 86_400.0
        try withDirectory { directory in
            let clock = Clock(base.addingTimeInterval(-day))
            let store = try backingStore(directory, clock)
            _ = store.openResolvedURL(URL(string: "https://before.test/")!)
            try flush(store)
            clock.now = base.addingTimeInterval(-8 * day)
            _ = store.openResolvedURL(URL(string: "https://behind.test/")!)
            try flush(store)
            #expect(SessionBackups.list(in: directory).map(\.date) == [-8 * day, -day].map(base.addingTimeInterval), "A copy is taken while the clock is set behind")
            clock.now = base
            store.forgetHistory(deletion(["timeRange": true, "begin": base.addingTimeInterval(-3_600).timeIntervalSinceReferenceDate,
                                          "end": Double.greatestFiniteMagnitude, "urls": [String]()]))
            try flush(store)
            #expect(SessionBackups.list(in: directory).map(\.date) == [base], "Clearing the last hour removes the copy really taken in it, leaving only a fresh copy")
        }
    }

    @Test(arguments: [true, false], [-2_592_000.0, -257_400.0, 43_200.5, 43_201.5, 2_592_000.0])
    static func aRangeClearFollowsBackupDatesWhenTheClockIsSteady(_ sequenced: Bool, _ offset: Double) {
        let backups = chronological(busyDates, sequenced: sequenced)
        let start = base.addingTimeInterval(offset)
        let withinRange = Set(backups.filter { $0.date.timeIntervalSince(start) > -1 }.map(\.url))

        #expect(Set(SessionBackups.Pruning.since(start).removed(from: backups).map(\.url)) == withinRange)
    }

    @Test
    static func addressPruningMatchesWholeAddresses() throws {
        try withDirectory { directory in
            let single = SessionBackups.Pruning(deletion(["urls": ["https://a.test/x"], "hosts": ["a.test"]]))
            let longer = Data("{\"url\" : \"https:\\/\\/a.test\\/x2\"}".utf8)
            let exact = Data("{\"url\" : \"https:\\/\\/a.test\\/x\"}".utf8)
            #expect(single?.excluding(longer) != nil, "A longer address in the sidebar isn't the deleted one")
            #expect(single?.excluding(exact) == nil, "The same address still in the sidebar keeps older copies")
            let folder = SessionBackups.folder(in: directory)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
            try longer.write(to: folder.appendingPathComponent(SessionBackups.name(for: base, sequence: 1)))
            try exact.write(to: folder.appendingPathComponent(SessionBackups.name(for: base.addingTimeInterval(60), sequence: 2)))
            SessionBackups.prune(single!, in: directory)
            #expect(SessionBackups.list(in: directory).map(\.date) == [base], "Only the copy holding that exact address goes")
        }
    }

    @Test
    static func historyPageDeletionUsesAddressPruning() throws {
        let day = base.timeIntervalSinceReferenceDate
        let page = SessionBackups.Pruning(deletion(["timeRange": true, "begin": day, "end": day + 86_400,
                                                     "restrictURLs": ["https://a.test/x"], "urls": [String]()]))
        if case .addresses = page {} else { throw Failure(description: "A history-page delete uses the address rule") }
    }

    @Test
    static func removedProfileIsNotExcludedFromPruningWhenItsIDRemains() throws {
        let profile = UUID()
        #expect(SessionBackups.Pruning.profile(profile).excluding(Data(profile.uuidString.utf8)) != nil, "A removed Profile prunes even if its ID lingers in the sidebar")
    }

    @Test @MainActor static func clearArchivePrunesBackups() throws {
        try withDirectory { directory in
            let clock = Clock(base)
            let store = try backingStore(directory, clock)
            let tab = store.openResolvedURL(URL(string: "https://archived.test/")!)
            try flush(store)
            clock.now = base.addingTimeInterval(7_200)
            store.closeTab(tab)
            try flush(store)
            #expect(try texts(directory).allSatisfy { $0.contains(escaped("https://archived.test/")) }, "Copies hold the closed tab")
            store.clearArchive(profileID: store.activeSpace.profileID)
            try flush(store)
            #expect(!store.state.tabs.contains { $0.id == tab }, "The archive is cleared")
            #expect(SessionBackups.list(in: directory).count == 1, "Only a fresh copy remains")
            #expect(try texts(directory).allSatisfy { !$0.contains("archived.test") }, "No copy keeps the cleared tab")
        }
    }

    @Test @MainActor static func removingASpacesDataPrunesBackups() throws {
        try withDirectory { directory in
            let clock = Clock(base)
            let store = try backingStore(directory, clock)
            let spaceID = try store.createSpace(name: "Secret", sharing: .separate)
            let profileID = store.state.spaces.first { $0.id == spaceID }!.profileID
            store.selectSpace(spaceID)
            _ = store.openResolvedURL(URL(string: "https://space-secret.test/")!)
            try flush(store)
            clock.now = base.addingTimeInterval(7_200)
            let target = SpaceDeletionTarget(spaceID: spaceID, state: store.state)!
            var deleted: Bool?
            store.deleteSpace(target, documents: [:], shouldCommit: { true }, didCommit: { _ in }) {
                if case .success(let value) = $0 { deleted = value }
            }
            try flush(store)
            #expect(deleted == true, "The Space is deleted")
            #expect(try texts(directory).contains { $0.contains("space-secret.test") }, "A deleted Space's tabs are still in the Archive, so copies may hold them")
            let record = try store.stageRemoval(of: store.unusedProfile(profileID)!)
            clock.now = base.addingTimeInterval(7_300)
            try store.finishProfileRemoval(record)
            try flush(store)
            #expect(!store.state.profiles.contains { $0.id == profileID }, "The Space's data is removed")
            #expect(!SessionBackups.list(in: directory).isEmpty, "A fresh copy is kept")
            #expect(try texts(directory).allSatisfy { !$0.contains("space-secret.test") && !$0.contains(profileID.uuidString) }, "No copy keeps the removed data")
        }
    }

    @Test
    @MainActor
    static func privateStoresNeverWriteBackups() throws {
        try withDirectory { directory in
            let regular = try BrowserStore(directory: directory)
            let incognito = BrowserStore(privateParentProfileID: regular.activeSpace.profileID, engineProfilePath: "/disposable",
                                         directory: directory, settings: regular.state.settings, now: { base })
            _ = incognito.openResolvedURL(URL(string: "https://private.test/")!)
            try incognito.save()
            incognito.forgetHistory(deletion(["allHistory": true]))
            #expect(!FileManager.default.fileExists(atPath: SessionBackups.folder(in: directory).path), "Private windows never write backups")
        }
    }

    @Test
    @MainActor
    static func plainStoresPruneExistingBackupsWithoutMakingNewOnes() throws {
        try withDirectory { directory in
            let clock = Clock(base)
            let keeping = try backingStore(directory, clock)
            try flush(keeping)
            #expect(SessionBackups.list(in: directory).count == 1, "A kept copy exists")
            let plain = try BrowserStore(directory: directory)
            plain.forgetHistory(deletion(["allHistory": true]))
            #expect(SessionBackups.list(in: directory).isEmpty, "Even a store that writes no backups prunes existing ones")
        }
    }
}
