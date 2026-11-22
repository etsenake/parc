import Foundation
import Testing
@testable import ParcCore

struct SessionBackupRetentionTests {
    private typealias Support = SessionBackupTestsSupport

    @Test
    static func retentionKeepsSixRecentAndSevenDailyCopies() throws {
        let dates = Support.busyDates
        let backups = Support.chronological(dates)
        let kept = SessionBackups.retained(backups, calendar: Support.utc)
        let newest = backups.sorted { $0.date > $1.date }
        #expect(Set(newest.prefix(6).map(\.url)).isSubset(of: kept), "The six newest copies stay")
        let mornings = (0..<7).map { Support.base.addingTimeInterval(Double(-$0 * 86_400 + 8 * 3_600)) }
        #expect(mornings.allSatisfy { date in kept.contains { Support.stamped($0) == date } }, "The first copy of each of the seven latest days stays")
        #expect(kept.count == 13, "Nothing else stays: six recent plus seven daily copies")
        let stale = Support.base.addingTimeInterval(Double(-7 * 86_400 + 8 * 3_600))
        #expect(!kept.contains { Support.stamped($0) == stale }, "An eighth day is pruned")
    }

    @Test
    static func steadyClockMakesSequenceAndTimestampRetentionAgree() throws {
        let dates = Support.busyDates
        let backups = Support.chronological(dates)
        let kept = SessionBackups.retained(backups, calendar: Support.utc)
        let newest = backups.sorted { $0.date > $1.date }
        #expect(kept == SessionBackups.retained(Support.chronological(dates, sequenced: false), calendar: Support.utc), "With a correct clock, write order keeps exactly the copies their times would")
        #expect(backups.sorted { $0.isNewer(than: $1) } == newest, "With a correct clock, the newest copy is the latest time")
    }

    @Test
    static func infrequentUseDoesNotAgeOutBackups() throws {
        let sparse = Support.chronological([-40, -25, -9, 0].map { Support.base.addingTimeInterval(Double($0 * 86_400)) })
        #expect(SessionBackups.retained(sparse, calendar: Support.utc).count == 4, "Days without use don't push older copies out")
    }

    struct BackupName: Sendable, CustomTestStringConvertible {
        let testDescription: String
        let name: String
        let sequence: Int
    }

    @Test(arguments: [
        BackupName(testDescription: "Numbered name", name: SessionBackups.name(for: Support.base, sequence: 3), sequence: 3),
        BackupName(testDescription: "Legacy timestamp-only name", name: "session-20261116T160000.json", sequence: 0),
    ])
    static func backupNamesRoundTripTheirTimestampAndSequence(_ input: BackupName) {
        let backup = SessionBackups.backup(named: input.name, in: Support.folder)
        #expect(backup?.date == Support.base && backup?.sequence == input.sequence)
    }

    @Test
    static func numberedBackupsSortAfterLegacyBackups() throws {
        let named = SessionBackups.backup(named: SessionBackups.name(for: Support.base, sequence: 3), in: Support.folder)
        let legacy = SessionBackups.backup(named: "session-20261116T160000.json", in: Support.folder)
        #expect(named.flatMap { first in legacy.map { first.isNewer(than: $0) } } == true, "Numbered copies were all taken after unnumbered ones")
    }

    @Test(arguments: ["session.json", ".backup-123.json", "session-unreadable-20261116T160000.json",
                      "session-20261116T160000-0.json", "session-20261116T160000-x.json",
                      "session-20261116T160000-9223372036854775807.json"])
    static func nonBackupNamesDoNotParse(_ name: String) throws {
        #expect(SessionBackups.backup(named: name, in: Support.folder) == nil)
    }

    @Test
    static func correctingTheClockKeepsRecentWritesAndTheFirstCopyOfTheFutureDay() throws {
        let backups = Support.backupsAfterClockCorrection
        let kept = SessionBackups.retained(backups, calendar: Support.utc)
        #expect(Set(backups.suffix(6).map(\.url)).isSubset(of: kept), "The six copies taken after the clock was fixed stay, though older copies are stamped later")
        #expect(kept.subtracting(backups.suffix(6).map(\.url)) == [backups[0].url], "Of the copies stamped ahead, only the first of that day stays")
    }

    @Test
    static func futureDatedCopiesAgeOutAfterAWeekOfNewWrites() throws {
        let backups = Support.backupsAfterClockCorrection
        var later = backups
        for day in 1...7 {
            let date = Support.base.addingTimeInterval(Double(day * 86_400))
            later.append(.init(url: Support.folder.appendingPathComponent(SessionBackups.name(for: date, sequence: later.count + 1)),
                               date: date, sequence: later.count + 1))
        }
        #expect(SessionBackups.retained(later, calendar: Support.utc).isDisjoint(with: backups.prefix(6).map(\.url)), "After a week of use the copies stamped ahead age out instead of waiting a year")
    }

    @MainActor
    private static func withClockCorrection(_ body: (URL, BrowserStore, SessionBackups, [Date]) throws -> Void) throws {
        try Support.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let writer = SessionBackups(directory: directory, calendar: Support.utc)
            let taken = [("https://before.test/", Support.base), ("https://ahead-1.test/", Support.ahead),
                         ("https://ahead-2.test/", Support.ahead.addingTimeInterval(3_600))]
            for (address, date) in taken {
                _ = store.openResolvedURL(URL(string: address)!)
                try writer.backUp(store.state, at: date)
            }
            let relaunched = SessionBackups(directory: directory, calendar: Support.utc)
            try body(directory, store, relaunched, taken.map(\.1))
            try store.save()
        }
    }

    @Test
    @MainActor
    static func aRelaunchResumesHourlyBackupsAfterClockCorrection() throws {
        try withClockCorrection { directory, store, relaunched, _ in
            _ = store.openResolvedURL(URL(string: "https://fixed.test/")!)
            relaunched.backUpIfDue(store.state, at: Support.base.addingTimeInterval(1_800))
            #expect(SessionBackups.list(in: directory).count == 4, "A copy stamped ahead doesn't hold off the next backup once the clock is fixed")
            _ = store.openResolvedURL(URL(string: "https://soon.test/")!)
            relaunched.backUpIfDue(store.state, at: Support.base.addingTimeInterval(2_400))
            #expect(SessionBackups.list(in: directory).count == 4, "The hourly pace resumes from that copy")
        }
    }

    @Test
    @MainActor
    static func copiesListInWriteOrderAfterClockCorrection() throws {
        try withClockCorrection { directory, store, relaunched, taken in
            _ = store.openResolvedURL(URL(string: "https://fixed.test/")!)
            relaunched.backUpIfDue(store.state, at: Support.base.addingTimeInterval(1_800))
            #expect(SessionBackups.list(in: directory).map(\.date)
                        == [Support.base.addingTimeInterval(1_800)] + taken.reversed(), "Copies list in the order they were taken, not by their stamps")
        }
    }

    @Test
    @MainActor
    static func rescuePrefersTheLastWriteAfterClockCorrection() throws {
        try withClockCorrection { directory, store, relaunched, _ in
            _ = store.openResolvedURL(URL(string: "https://fixed.test/")!)
            relaunched.backUpIfDue(store.state, at: Support.base.addingTimeInterval(1_800))
            let newest = SessionBackups.restorable(in: directory).first.map { String(decoding: $0.data, as: UTF8.self) }
            #expect(newest?.contains(Support.escaped("https://fixed.test/")) == true, "The rescue offers the copy taken last, not the one stamped furthest ahead")
        }
    }
}
