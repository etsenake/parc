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

    static func main() { exitOnFailure(runChecks) }

    static func runChecks() throws {
        try testMissingMainFileOffersBackups()
        try testFreshStartsNeverAsk()
        try testUnreadableMainFileStillAsksToRestoreOrQuit()
        try testRescueWordsMissingFilesAndOddClocks()
        print("SessionBackupTests passed (\(assertions) assertions)")
    }
}
