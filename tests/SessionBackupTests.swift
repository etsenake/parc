import Foundation

@main @MainActor struct SessionBackupTests {
    struct Failure: Error, CustomStringConvertible { let description: String }
    final class Clock { var now: Date; init(_ now: Date) { self.now = now } }

    static var assertions = 0
    static let base = Date(timeIntervalSince1970: 1_794_844_800)

    static func expect(_ condition: @autoclosure () throws -> Bool, _ message: String, line: UInt = #line) throws {
        assertions += 1
        if try !condition() { throw Failure(description: "line \(line): \(message)") }
    }

    static func withDirectory(_ body: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("parc-session-backups-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(directory)
    }

    static var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    static func texts(_ directory: URL) throws -> [String] {
        try SessionBackups.list(in: directory).map { String(decoding: try Data(contentsOf: $0.url), as: UTF8.self) }
    }

    static func escaped(_ url: String) -> String { url.replacingOccurrences(of: "/", with: "\\/") }

    static func backingStore(_ directory: URL, _ clock: Clock) throws -> BrowserStore {
        try BrowserStore(directory: directory, now: { clock.now }, keepsBackups: true)
    }

    static func flush(_ store: BrowserStore) throws { try store.save() }

    static let folder = URL(fileURLWithPath: "/backups", isDirectory: true)

    static func chronological(_ dates: [Date], sequenced: Bool = true) -> [SessionBackups.Backup] {
        dates.sorted().enumerated().map { index, date in
            .init(url: folder.appendingPathComponent(SessionBackups.name(for: date, sequence: index + 1)), date: date,
                  sequence: sequenced ? index + 1 : 0)
        }
    }

    static func stamped(_ url: URL) -> Date? { SessionBackups.backup(named: url.lastPathComponent, in: folder)?.date }

    static func session(_ directory: URL) -> URL { directory.appendingPathComponent("session.json") }

    static func testRetentionKeepsRecentAndDailyCopies() throws {
        var dates: [Date] = []
        for day in 0..<10 {
            for hour in 8...20 { dates.append(base.addingTimeInterval(Double(-day * 86_400 + hour * 3_600))) }
        }
        let backups = chronological(dates)
        let kept = SessionBackups.retained(backups, calendar: utc)
        let newest = backups.sorted { $0.date > $1.date }
        try expect(Set(newest.prefix(6).map(\.url)).isSubset(of: kept), "The six newest copies stay")
        let mornings = (0..<7).map { base.addingTimeInterval(Double(-$0 * 86_400 + 8 * 3_600)) }
        try expect(mornings.allSatisfy { date in kept.contains { stamped($0) == date } },
                   "The first copy of each of the seven latest days stays")
        try expect(kept.count == 13, "Nothing else stays: six recent plus seven daily copies")
        let stale = base.addingTimeInterval(Double(-7 * 86_400 + 8 * 3_600))
        try expect(!kept.contains { stamped($0) == stale }, "An eighth day is pruned")
        try expect(kept == SessionBackups.retained(chronological(dates, sequenced: false), calendar: utc),
                   "With a correct clock, write order keeps exactly the copies their times would")
        try expect(backups.sorted { $0.isNewer(than: $1) } == newest, "With a correct clock, the newest copy is the latest time")
        let sparse = chronological([-40, -25, -9, 0].map { base.addingTimeInterval(Double($0 * 86_400)) })
        try expect(SessionBackups.retained(sparse, calendar: utc).count == 4, "Days without use don't push older copies out")
        let named = SessionBackups.backup(named: SessionBackups.name(for: base, sequence: 3), in: folder)
        try expect(named?.date == base && named?.sequence == 3, "Names carry their exact time and their place in line")
        let legacy = SessionBackups.backup(named: "session-20261116T160000.json", in: folder)
        try expect(legacy?.date == base && legacy?.sequence == 0, "Copies named before the numbering still count")
        try expect(named.flatMap { first in legacy.map { first.isNewer(than: $0) } } == true,
                   "Numbered copies were all taken after unnumbered ones")
        try expect(["session.json", ".backup-123.json", "session-unreadable-20261116T160000.json",
                    "session-20261116T160000-0.json", "session-20261116T160000-x.json",
                    "session-20261116T160000-9223372036854775807.json"]
                    .allSatisfy { SessionBackups.backup(named: $0, in: folder) == nil },
                   "Only backup names count as backups")
    }

    static func testClockSetAheadThenFixedKeepsWriteOrder() throws {
        let ahead = base.addingTimeInterval(365 * 86_400)
        let wrong = (0..<6).map { ahead.addingTimeInterval(Double($0 * 3_600)) }
        let fixed = (0..<6).map { base.addingTimeInterval(Double($0 * 3_600)) }
        let backups = (wrong + fixed).enumerated().map { index, date in
            SessionBackups.Backup(url: folder.appendingPathComponent(SessionBackups.name(for: date, sequence: index + 1)),
                                  date: date, sequence: index + 1)
        }
        let kept = SessionBackups.retained(backups, calendar: utc)
        try expect(Set(backups.suffix(6).map(\.url)).isSubset(of: kept),
                   "The six copies taken after the clock was fixed stay, though older copies are stamped later")
        try expect(kept.subtracting(backups.suffix(6).map(\.url)) == [backups[0].url],
                   "Of the copies stamped ahead, only the first of that day stays")
        var later = backups
        for day in 1...7 {
            let date = base.addingTimeInterval(Double(day * 86_400))
            later.append(.init(url: folder.appendingPathComponent(SessionBackups.name(for: date, sequence: later.count + 1)),
                               date: date, sequence: later.count + 1))
        }
        try expect(SessionBackups.retained(later, calendar: utc).isDisjoint(with: wrong.indices.map { backups[$0].url }),
                   "After a week of use the copies stamped ahead age out instead of waiting a year")
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
            _ = store.openResolvedURL(URL(string: "https://fixed.test/")!)
            relaunched.backUpIfDue(store.state, at: base.addingTimeInterval(1_800))
            try expect(SessionBackups.list(in: directory).count == 4,
                       "A copy stamped ahead doesn't hold off the next backup once the clock is fixed")
            _ = store.openResolvedURL(URL(string: "https://soon.test/")!)
            relaunched.backUpIfDue(store.state, at: base.addingTimeInterval(2_400))
            try expect(SessionBackups.list(in: directory).count == 4, "The hourly pace resumes from that copy")
            try expect(SessionBackups.list(in: directory).map(\.date)
                        == [base.addingTimeInterval(1_800)] + taken.map(\.1).reversed(),
                       "Copies list in the order they were taken, not by their stamps")
            let newest = SessionBackups.restorable(in: directory).first.map { String(decoding: $0.data, as: UTF8.self) }
            try expect(newest?.contains(escaped("https://fixed.test/")) == true,
                       "The rescue offers the copy taken last, not the one stamped furthest ahead")
            try store.save()
        }
    }

    static func testBackupsFollowCadenceAndSkipDownloadsAndHistory() throws {
        try withDirectory { directory in
            let clock = Clock(base)
            let store = try backingStore(directory, clock)
            _ = store.openResolvedURL(URL(string: "https://first.test/")!)
            store.recordDownload(["id": 7, "name": "file.zip", "path": "/tmp/file.zip", "sourceURL": "https://download.test/file.zip"])
            try flush(store)
            try expect(SessionBackups.list(in: directory).count == 1, "The first save makes a backup")
            let folder = SessionBackups.folder(in: directory)
            let folderMode = try FileManager.default.attributesOfItem(atPath: folder.path)[.posixPermissions] as? NSNumber
            let fileMode = try FileManager.default.attributesOfItem(atPath: SessionBackups.list(in: directory)[0].url.path)[.posixPermissions] as? NSNumber
            try expect(folderMode?.intValue == 0o700 && fileMode?.intValue == 0o600, "Backups are private to this account")
            let first = try BrowserStore.savedSession(from: Data(contentsOf: SessionBackups.list(in: directory)[0].url))
            try expect(first.downloads.isEmpty && first.history.isEmpty, "Backups hold the sidebar, not downloads or history")
            try expect(try texts(directory)[0].contains(escaped("https://first.test/")), "The backup holds the open tab")
            try expect(!(try texts(directory)[0].contains("download.test")), "No download address reaches a backup")
            clock.now = base.addingTimeInterval(600)
            _ = store.openResolvedURL(URL(string: "https://second.test/")!)
            try flush(store)
            try expect(SessionBackups.list(in: directory).count == 1, "Saves within the hour don't add copies")
            clock.now = base.addingTimeInterval(3_700)
            _ = store.openResolvedURL(URL(string: "https://third.test/")!)
            try flush(store)
            try expect(SessionBackups.list(in: directory).count == 2, "The first save after an hour adds a copy")
            try expect(try texts(directory)[0].contains(escaped("https://third.test/")), "The new copy is the current sidebar")
            clock.now = base.addingTimeInterval(9_000)
            try flush(store)
            try expect(SessionBackups.list(in: directory).count == 2, "An unchanged sidebar isn't copied again")
            try expect(try BrowserStore(directory: directory).state.downloads.count == 1, "The main file still keeps downloads")
        }
        try withDirectory { directory in
            let plain = try BrowserStore(directory: directory)
            _ = plain.openResolvedURL(URL(string: "https://launch.test/")!)
            try plain.save()
            try expect(SessionBackups.list(in: directory).isEmpty, "A store without backups writes none")
            let clock = Clock(base)
            try flush(try backingStore(directory, clock))
            try expect(try texts(directory).first?.contains(escaped("https://launch.test/")) == true,
                       "A sidebar that loaded and validated is backed up at launch")
            let changed = try BrowserStore(directory: directory)
            _ = changed.openResolvedURL(URL(string: "https://changed.test/")!)
            try changed.save()
            clock.now = base.addingTimeInterval(600)
            try flush(try backingStore(directory, clock))
            try expect(SessionBackups.list(in: directory).count == 1, "Relaunching within the hour adds no copy")
            clock.now = base.addingTimeInterval(3_700)
            try flush(try backingStore(directory, clock))
            try expect(SessionBackups.list(in: directory).count == 2, "Relaunching after an hour copies the changed sidebar")
        }
    }

    static func testOnlyValidStatesAreBackedUp() throws {
        try withDirectory { directory in
            var invalid = BrowserState.initial()
            let space = invalid.spaces[0]
            invalid.tabs = [BrowserTab(id: UUID(), spaceID: UUID(), profileID: space.profileID, url: "https://x.test/",
                                       title: "x", kind: .today, createdAt: base, lastAccessed: base,
                                       savedURL: "https://x.test/", savedTitle: "x")]
            let backups = SessionBackups(directory: directory, calendar: utc)
            var refused = false
            do { try backups.backUp(invalid, at: base) } catch { refused = true }
            try expect(refused, "A state that fails validation is refused")
            backups.backUpIfDue(invalid, at: base)
            try expect(!FileManager.default.fileExists(atPath: SessionBackups.folder(in: directory).path), "No copy of it is written")
            try Data("{\"broken\":".utf8).write(to: directory.appendingPathComponent("session.json"))
            var unreadable = false
            do { _ = try backingStore(directory, Clock(base)) } catch is SessionFileUnreadable { unreadable = true }
            try expect(unreadable, "An unreadable main file is reported as such")
            try expect(SessionBackups.list(in: directory).isEmpty, "An unreadable main file is never backed up")
        }
    }

    static func testRescueRestoresNewestGoodBackupAndKeepsUnreadableFile() throws {
        try withDirectory { directory in
            let older = try BrowserStore(directory: directory)
            _ = older.openResolvedURL(URL(string: "https://older.test/")!)
            let backups = SessionBackups(directory: directory, calendar: utc)
            try backups.backUp(older.state, at: base)
            _ = older.openResolvedURL(URL(string: "https://newer.test/")!)
            try backups.backUp(older.state, at: base.addingTimeInterval(3_600))
            let folder = SessionBackups.folder(in: directory)
            try Data("not json".utf8).write(to: folder.appendingPathComponent(SessionBackups.name(for: base.addingTimeInterval(7_200), sequence: 3)))
            var dangling = older.state
            dangling.activeSpaceID = UUID()
            let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(dangling).write(to: folder.appendingPathComponent(SessionBackups.name(for: base.addingTimeInterval(10_800), sequence: 4)))
            let candidates = SessionBackups.restorable(in: directory)
            try expect(candidates.map(\.backup.date) == [base.addingTimeInterval(3_600), base],
                       "Rescue offers the newest backup that loads and validates, then older ones")
            let damaged = Data("{\"spaces\": [".utf8)
            try damaged.write(to: directory.appendingPathComponent("session.json"))
            var unreadable = false
            do { _ = try BrowserStore(directory: directory) } catch is SessionFileUnreadable { unreadable = true }
            try expect(unreadable, "The damaged file is reported as unreadable")
            let now = base.addingTimeInterval(20_000)
            let aside = try SessionBackups.restore(candidates[0].data, in: directory, at: now)
            try expect(try aside.map { try Data(contentsOf: $0) } == damaged, "The unreadable file is kept byte for byte")
            try expect(aside?.lastPathComponent.hasPrefix("session-unreadable-") == true, "It is kept under a clear name")
            let restored = try BrowserStore(directory: directory)
            try expect(restored.state.tabs.contains { $0.url == "https://newer.test/" }, "The newest good backup is in place")
            try Data("garbage".utf8).write(to: directory.appendingPathComponent("session.json"))
            let second = try SessionBackups.restore(candidates[1].data, in: directory, at: now)
            try expect(try second != aside && second.map { try Data(contentsOf: $0) } == Data("garbage".utf8),
                       "A second rescue in the same second keeps both unreadable files")
            try expect(try aside.map { try Data(contentsOf: $0) } == damaged, "The first kept file is untouched")
            try expect(try BrowserStore(directory: directory).state.tabs.allSatisfy { $0.url != "https://newer.test/" },
                       "Falling back restores the older backup")
        }
    }

    static func testNoBackupLeavesTheFileAlone() throws {
        try withDirectory { directory in
            let damaged = Data("{".utf8)
            try damaged.write(to: directory.appendingPathComponent("session.json"))
            try expect(SessionBackups.restorable(in: directory).isEmpty, "No backups means nothing to offer")
            let folder = SessionBackups.folder(in: directory)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
            try Data("{}".utf8).write(to: folder.appendingPathComponent(SessionBackups.name(for: base, sequence: 1)))
            try expect(SessionBackups.restorable(in: directory).isEmpty, "Unreadable backups are never offered")
            var unreadable = false
            do { _ = try BrowserStore(directory: directory, keepsBackups: true) } catch is SessionFileUnreadable { unreadable = true }
            try expect(unreadable, "Startup still stops on the unreadable file")
            try expect(try Data(contentsOf: directory.appendingPathComponent("session.json")) == damaged, "The file is untouched")
            try expect(SessionBackups.list(in: directory).count == 1, "Existing backups are left as they were")
        }
    }

    static func testMissingMainFileOffersBackups() throws {
        try withDirectory { directory in
            let clock = Clock(base)
            let store = try backingStore(directory, clock)
            _ = store.openResolvedURL(URL(string: "https://kept-sidebar.test/")!)
            try flush(store)
            try FileManager.default.removeItem(at: session(directory))
            let backups = SessionBackups.list(in: directory)
            clock.now = base.addingTimeInterval(7_200)
            var offers: [SidebarRescue.Offer] = []
            let restored = try SidebarRescue.openStore(at: directory, keepsBackups: true, interactive: true,
                                                       now: { clock.now }) { offers.append($0); return true }
            try expect(offers == [.init(trouble: .missing, date: base, skippedNewer: false, now: clock.now)],
                       "A missing file with a good backup asks once, offering the newest copy")
            try expect(restored?.state.tabs.contains { $0.url == "https://kept-sidebar.test/" } == true,
                       "Restore Backup brings the sidebar back")
            try expect(!(try FileManager.default.contentsOfDirectory(atPath: directory.path)).contains { $0.hasPrefix("session-unreadable-") },
                       "With no file there is nothing to set aside")
            try restored.map(flush)
            try expect(Set(backups.map(\.url)).isSubset(of: SessionBackups.list(in: directory).map(\.url)),
                       "Restoring keeps every backup")
            try FileManager.default.removeItem(at: session(directory))
            let kept = SessionBackups.list(in: directory)
            for answer in [false, nil] as [Bool?] {
                var asked = 0
                let empty = try SidebarRescue.openStore(at: directory, keepsBackups: true, interactive: true,
                                                        now: { clock.now }) { _ in asked += 1; return answer }
                try expect(asked == 1 && empty?.state.tabs.contains { $0.url == "https://kept-sidebar.test/" } == false,
                           "Start Empty, or an alert that can't be shown, opens an empty sidebar instead of quitting")
                try expect(!FileManager.default.fileExists(atPath: session(directory).path), "Starting empty writes nothing yet")
                try expect(SessionBackups.list(in: directory) == kept, "Starting empty leaves the backups alone")
            }
        }
    }

    static func testFreshStartsNeverAsk() throws {
        var asked = 0
        let ask: (SidebarRescue.Offer) -> Bool? = { _ in asked += 1; return true }
        try withDirectory { directory in
            let fresh = try SidebarRescue.openStore(at: directory, keepsBackups: true, interactive: true, now: { base }, ask: ask)
            try expect(fresh != nil && asked == 0, "A fresh install starts without an alert")
            try expect(fresh?.state.tabs == BrowserState.initial().tabs && fresh?.state.spaces.count == BrowserState.initial().spaces.count,
                       "It starts with the usual new sidebar")
            try expect(!FileManager.default.fileExists(atPath: SessionBackups.folder(in: directory).path),
                       "No backup folder appears from opening")
        }
        try withDirectory { directory in
            let profile = directory.appendingPathComponent("Fresh Profile", isDirectory: true)
            _ = try SidebarRescue.openStore(at: profile, keepsBackups: true, interactive: true, now: { base }, ask: ask)
            try expect(asked == 0, "A folder that doesn't exist yet starts without an alert")
        }
        try withDirectory { directory in
            let clock = Clock(base)
            let store = try backingStore(directory, clock)
            try flush(store)
            _ = try SidebarRescue.openStore(at: directory, keepsBackups: true, interactive: true, now: { clock.now }, ask: ask).map(flush)
            try expect(asked == 0, "A sidebar that loads never asks, even with backups")
            try FileManager.default.removeItem(at: session(directory))
            _ = try SidebarRescue.openStore(at: directory, keepsBackups: false, interactive: true, now: { clock.now }, ask: ask)
            try expect(asked == 0, "A disposable test profile, which keeps no backups, starts empty without asking")
            _ = try SidebarRescue.openStore(at: directory, keepsBackups: true, interactive: false, now: { clock.now }, ask: ask)
            try expect(asked == 0, "A smoke run reports nothing and starts empty")
            for backup in SessionBackups.list(in: directory) { try Data("{}".utf8).write(to: backup.url) }
            let unreadable = try SidebarRescue.openStore(at: directory, keepsBackups: true, interactive: true, now: { clock.now }, ask: ask)
            try expect(unreadable != nil && asked == 0, "Backups that can't be read aren't offered for a missing file")
        }
    }

    static func testUnreadableMainFileStillAsksToRestoreOrQuit() throws {
        try withDirectory { directory in
            let clock = Clock(base)
            let store = try backingStore(directory, clock)
            _ = store.openResolvedURL(URL(string: "https://kept-sidebar.test/")!)
            try flush(store)
            let damaged = Data("{".utf8)
            try damaged.write(to: session(directory))
            var offers: [SidebarRescue.Offer] = []
            let quit = try SidebarRescue.openStore(at: directory, keepsBackups: true, interactive: true,
                                                   now: { clock.now }) { offers.append($0); return false }
            try expect(quit == nil && offers.map(\.trouble) == [.unreadable], "A damaged file still offers the rescue, and Quit quits")
            try expect(try Data(contentsOf: session(directory)) == damaged, "Quit changes nothing")
        }
    }

    static func testRescueWordsMissingFilesAndOddClocks() throws {
        let hoursAgo = base.addingTimeInterval(-7_200)
        let missing = SidebarRescue.wording(for: .init(trouble: .missing, date: hoursAgo, skippedNewer: false, now: base))
        try expect(missing.title == "Parc couldn’t find your saved sidebar" && missing.alternative == "Start Empty",
                   "A missing file has its own title and offers an empty sidebar instead of quitting")
        try expect(missing.message.contains("is missing") && !missing.message.contains("damaged")
                    && !missing.message.contains("couldn’t be read") && !missing.message.contains("unreadable"),
                   "A missing file isn't called damaged or unreadable")
        try expect(SidebarRescue.backupAge(hoursAgo, now: base).map { missing.message.contains("is from \($0).") } == true,
                   "It says how old the backup is")
        let skipped = SidebarRescue.wording(for: .init(trouble: .missing, date: hoursAgo, skippedNewer: true, now: base))
        try expect(skipped.message.contains("Newer backups couldn’t be read, so the most recent one that works is from"),
                   "Skipped copies are mentioned without blaming the missing file")
        let skippedAhead = SidebarRescue.wording(for: .init(trouble: .missing, date: base.addingTimeInterval(86_400),
                                                            skippedNewer: true, now: base))
        try expect(skippedAhead.message.contains("the most recent one that works is dated after your Mac’s current time; its age isn’t known."),
                   "A skipped-copies message with a future stamp still reads as one sentence")
        let damaged = SidebarRescue.wording(for: .init(trouble: .unreadable, date: hoursAgo, skippedNewer: true, now: base))
        try expect(damaged.title == "Parc couldn’t read your saved sidebar" && damaged.alternative == "Quit"
                    && damaged.message.contains("damaged") && damaged.message.contains("couldn’t be read either"),
                   "A damaged file keeps its wording and its Quit button")
        let ahead = base.addingTimeInterval(365 * 86_400)
        let future = SidebarRescue.wording(for: .init(trouble: .unreadable, date: ahead, skippedNewer: false, now: base))
        try expect(SidebarRescue.backupAge(ahead, now: base) == nil
                    && future.message.contains("The most recent backup is dated after your Mac’s current time; its age isn’t known."),
                   "A copy stamped in the future says its age is unknown")
        try expect(!future.message.contains("2027") && !future.message.contains("from"),
                   "It never presents a future date as how old the copy is")
        try expect(SidebarRescue.backupAge(base.addingTimeInterval(30), now: base) == "a moment ago"
                    && SidebarRescue.backupAge(base.addingTimeInterval(-30), now: base) == "a moment ago",
                   "Seconds of clock drift either way read as a moment ago")
    }

    static func deletion(_ info: [AnyHashable: Any]) -> ChromiumHistoryDeletion { ChromiumHistoryDeletion(userInfo: info) }

    static func testClearingHistoryPrunesBackups() throws {
        try withDirectory { directory in
            let clock = Clock(base)
            let store = try backingStore(directory, clock)
            _ = store.openResolvedURL(URL(string: "https://kept.test/")!)
            try flush(store)
            clock.now = base.addingTimeInterval(7_200)
            let gone = store.openResolvedURL(URL(string: "https://gone.test/")!)
            try flush(store)
            try expect(SessionBackups.list(in: directory).count == 2, "Two copies exist")
            store.closeTab(gone)
            store.deleteArchivedTabs([gone])
            try flush(store)
            store.forgetHistory(deletion(["urls": ["https://kept.test/"], "hosts": ["kept.test"]]))
            try flush(store)
            try expect(SessionBackups.list(in: directory).count == 2,
                       "Deleting an address the sidebar still holds leaves copies that only hold it too")
            store.forgetHistory(deletion(["urls": ["https://gone.test/"], "hosts": ["gone.test"]]))
            try flush(store)
            try expect(try texts(directory).allSatisfy { !$0.contains(escaped("https://gone.test/")) },
                       "Deleting a visit removes every copy that still holds that address")
            try expect(try texts(directory).contains { $0.contains(escaped("https://kept.test/")) }, "Unrelated copies stay")
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
            try expect(before.contains { $0.date >= begin } && !after.contains { $0.date >= begin && $0.date < clock.now },
                       "Clearing a time range removes copies taken since it began")
            try expect(after.contains { $0.date < begin }, "Copies from before the range stay")
            clock.now = base.addingTimeInterval(5 * 3_600)
            store.forgetHistory(deletion(["allHistory": true]))
            try flush(store)
            let fresh = SessionBackups.list(in: directory)
            try expect(fresh.count == 1 && fresh[0].date == clock.now, "Clearing all history leaves only a fresh copy of today's sidebar")
            try expect(try texts(directory)[0].contains(escaped("https://later.test/")), "The fresh copy matches the main file")
        }
    }

    static func testAddressRulesMatchWholeAddresses() throws {
        try withDirectory { directory in
            let single = SessionBackups.Pruning(deletion(["urls": ["https://a.test/x"], "hosts": ["a.test"]]))
            let longer = Data("{\"url\" : \"https:\\/\\/a.test\\/x2\"}".utf8)
            let exact = Data("{\"url\" : \"https:\\/\\/a.test\\/x\"}".utf8)
            try expect(single?.excluding(longer) != nil, "A longer address in the sidebar isn't the deleted one")
            try expect(single?.excluding(exact) == nil, "The same address still in the sidebar keeps older copies")
            let folder = SessionBackups.folder(in: directory)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
            try longer.write(to: folder.appendingPathComponent(SessionBackups.name(for: base, sequence: 1)))
            try exact.write(to: folder.appendingPathComponent(SessionBackups.name(for: base.addingTimeInterval(60), sequence: 2)))
            SessionBackups.prune(single!, in: directory)
            try expect(SessionBackups.list(in: directory).map(\.date) == [base], "Only the copy holding that exact address goes")
            let day = base.timeIntervalSinceReferenceDate
            let page = SessionBackups.Pruning(deletion(["timeRange": true, "begin": day, "end": day + 86_400,
                                                         "restrictURLs": ["https://a.test/x"], "urls": [String]()]))
            if case .addresses = page {} else { throw Failure(description: "A history-page delete uses the address rule") }
            let profile = UUID()
            try expect(SessionBackups.Pruning.profile(profile).excluding(Data(profile.uuidString.utf8)) != nil,
                       "A removed Profile prunes even if its ID lingers in the sidebar")
        }
    }

    static func testClearArchivePrunesBackups() throws {
        try withDirectory { directory in
            let clock = Clock(base)
            let store = try backingStore(directory, clock)
            let tab = store.openResolvedURL(URL(string: "https://archived.test/")!)
            try flush(store)
            clock.now = base.addingTimeInterval(7_200)
            store.closeTab(tab)
            try flush(store)
            try expect(try texts(directory).allSatisfy { $0.contains(escaped("https://archived.test/")) }, "Copies hold the closed tab")
            store.clearArchive(profileID: store.activeSpace.profileID)
            try flush(store)
            try expect(!store.state.tabs.contains { $0.id == tab }, "The archive is cleared")
            try expect(SessionBackups.list(in: directory).count == 1, "Only a fresh copy remains")
            try expect(try texts(directory).allSatisfy { !$0.contains("archived.test") }, "No copy keeps the cleared tab")
        }
    }

    static func testRemovingASpacesDataPrunesBackups() throws {
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
            try expect(deleted == true, "The Space is deleted")
            try expect(try texts(directory).contains { $0.contains("space-secret.test") },
                       "A deleted Space's tabs are still in the Archive, so copies may hold them")
            let record = try store.stageRemoval(of: store.unusedProfile(profileID)!)
            clock.now = base.addingTimeInterval(7_300)
            try store.finishProfileRemoval(record)
            try flush(store)
            try expect(!store.state.profiles.contains { $0.id == profileID }, "The Space's data is removed")
            try expect(!SessionBackups.list(in: directory).isEmpty, "A fresh copy is kept")
            try expect(try texts(directory).allSatisfy { !$0.contains("space-secret.test") && !$0.contains(profileID.uuidString) },
                       "No copy keeps the removed data")
        }
    }

    static func testPrivateAndPlainStoresNeverWriteBackups() throws {
        try withDirectory { directory in
            let regular = try BrowserStore(directory: directory)
            let incognito = BrowserStore(privateParentProfileID: regular.activeSpace.profileID, engineProfilePath: "/disposable",
                                         directory: directory, settings: regular.state.settings, now: { base })
            _ = incognito.openResolvedURL(URL(string: "https://private.test/")!)
            try incognito.save()
            incognito.forgetHistory(deletion(["allHistory": true]))
            try expect(!FileManager.default.fileExists(atPath: SessionBackups.folder(in: directory).path), "Private windows never write backups")
            let clock = Clock(base)
            let keeping = try backingStore(directory, clock)
            try flush(keeping)
            try expect(SessionBackups.list(in: directory).count == 1, "A kept copy exists")
            let plain = try BrowserStore(directory: directory)
            plain.forgetHistory(deletion(["allHistory": true]))
            try expect(SessionBackups.list(in: directory).isEmpty, "Even a store that writes no backups prunes existing ones")
        }
    }

    static func main() { exitOnFailure(runChecks) }
    static func runChecks() throws {
        try testRetentionKeepsRecentAndDailyCopies()
        try testClockSetAheadThenFixedKeepsWriteOrder()
        try testBackupsFollowCadenceAndSkipDownloadsAndHistory()
        try testOnlyValidStatesAreBackedUp()
        try testRescueRestoresNewestGoodBackupAndKeepsUnreadableFile()
        try testNoBackupLeavesTheFileAlone()
        try testMissingMainFileOffersBackups()
        try testFreshStartsNeverAsk()
        try testUnreadableMainFileStillAsksToRestoreOrQuit()
        try testRescueWordsMissingFilesAndOddClocks()
        try testClearingHistoryPrunesBackups()
        try testAddressRulesMatchWholeAddresses()
        try testClearArchivePrunesBackups()
        try testRemovingASpacesDataPrunesBackups()
        try testPrivateAndPlainStoresNeverWriteBackups()
        print("SessionBackupTests passed (\(assertions) assertions)")
    }
}
