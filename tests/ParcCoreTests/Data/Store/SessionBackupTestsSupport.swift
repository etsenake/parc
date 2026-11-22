import Foundation
import Testing
@testable import ParcCore

enum SessionBackupTestsSupport {
    struct Failure: Error, CustomStringConvertible { let description: String }

    final class Clock { var now: Date; init(_ now: Date) { self.now = now } }

    static let base = Date(timeIntervalSince1970: 1_794_844_800)

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

    @MainActor
    static func backingStore(_ directory: URL, _ clock: Clock) throws -> BrowserStore {
        try BrowserStore(directory: directory, now: { clock.now }, keepsBackups: true)
    }

    @MainActor
    static func flush(_ store: BrowserStore) throws { try store.save() }

    static let folder = URL(fileURLWithPath: "/backups", isDirectory: true)

    static func chronological(_ dates: [Date], sequenced: Bool = true) -> [SessionBackups.Backup] {
        dates.sorted().enumerated().map { index, date in
            .init(url: folder.appendingPathComponent(SessionBackups.name(for: date, sequence: index + 1)), date: date,
                  sequence: sequenced ? index + 1 : 0)
        }
    }

    static func stamped(_ url: URL) -> Date? { SessionBackups.backup(named: url.lastPathComponent, in: folder)?.date }

    static var busyDates: [Date] {
        (0..<10).flatMap { daysAgo in
            (8...20).map { hour in base.addingTimeInterval(Double(-daysAgo * 86_400 + hour * 3_600)) }
        }
    }

    static let ahead = base.addingTimeInterval(365 * 86_400)

    static var backupsAfterClockCorrection: [SessionBackups.Backup] {
        let wrong = (0..<6).map { ahead.addingTimeInterval(Double($0 * 3_600)) }
        let fixed = (0..<6).map { base.addingTimeInterval(Double($0 * 3_600)) }
        return (wrong + fixed).enumerated().map { index, date in
            SessionBackups.Backup(url: folder.appendingPathComponent(SessionBackups.name(for: date, sequence: index + 1)),
                                  date: date, sequence: index + 1)
        }
    }

    static func deletion(_ info: [AnyHashable: Any]) -> ChromiumHistoryDeletion { ChromiumHistoryDeletion(userInfo: info) }
}
