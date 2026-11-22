import Foundation
import Testing
@testable import ParcCore

struct SessionBackupRescueTests {
    private typealias Support = SessionBackupTestsSupport

    @MainActor
    private static func seedTwoRestorableBackups(in directory: URL) throws -> BrowserState {
        let older = try BrowserStore(directory: directory)
        _ = older.openResolvedURL(URL(string: "https://older.test/")!)
        let backups = SessionBackups(directory: directory, calendar: Support.utc)
        try backups.backUp(older.state, at: Support.base)
        _ = older.openResolvedURL(URL(string: "https://newer.test/")!)
        try backups.backUp(older.state, at: Support.base.addingTimeInterval(3_600))
        return older.state
    }

    @Test @MainActor static func rescueListsOnlyUsableBackupsInNewestFirstOrder() throws {
        try Support.withDirectory { directory in
            var dangling = try seedTwoRestorableBackups(in: directory)
            let folder = SessionBackups.folder(in: directory)
            try Data("not json".utf8).write(to: folder.appendingPathComponent(SessionBackups.name(for: Support.base.addingTimeInterval(7_200), sequence: 3)))
            dangling.activeSpaceID = UUID()
            let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(dangling).write(to: folder.appendingPathComponent(SessionBackups.name(for: Support.base.addingTimeInterval(10_800), sequence: 4)))
            let candidates = SessionBackups.restorable(in: directory)
            #expect(candidates.map(\.backup.date) == [Support.base.addingTimeInterval(3_600), Support.base], "Rescue offers the newest backup that loads and validates, then older ones")
        }
    }

    @Test(arguments: [true, false]) @MainActor static func rescueCanRestoreEitherUsableBackup(_ useNewest: Bool) throws {
        try Support.withDirectory { directory in
            _ = try seedTwoRestorableBackups(in: directory)
            let candidates = SessionBackups.restorable(in: directory)
            let chosen = try #require(useNewest ? candidates.first : candidates.last)
            try Data("{\"spaces\": [".utf8).write(to: directory.appendingPathComponent("session.json"))
            _ = try SessionBackups.restore(chosen.data, in: directory, at: Support.base)
            let restored = try BrowserStore(directory: directory)
            #expect(restored.state.tabs.contains { $0.url == "https://older.test/" })
            #expect(restored.state.tabs.contains { $0.url == "https://newer.test/" } == useNewest)
        }
    }

    @Test @MainActor static func rescuesWithinTheSameSecondPreserveBothUnreadableFiles() throws {
        try Support.withDirectory { directory in
            _ = try seedTwoRestorableBackups(in: directory)
            let candidates = SessionBackups.restorable(in: directory)
            let newest = try #require(candidates.first)
            let oldest = try #require(candidates.last)
            let damaged = Data("{\"spaces\": [".utf8)
            try damaged.write(to: directory.appendingPathComponent("session.json"))
            var unreadable = false
            do { _ = try BrowserStore(directory: directory) } catch is SessionFileUnreadable { unreadable = true }
            #expect(unreadable, "The damaged file is reported as unreadable")
            let now = Support.base.addingTimeInterval(20_000)
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
        try Support.withDirectory { directory in
            let damaged = Data("{".utf8)
            try damaged.write(to: directory.appendingPathComponent("session.json"))
            #expect(SessionBackups.restorable(in: directory).isEmpty, "No backups means nothing to offer")
            let folder = SessionBackups.folder(in: directory)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
            try Data("{}".utf8).write(to: folder.appendingPathComponent(SessionBackups.name(for: Support.base, sequence: 1)))
            #expect(SessionBackups.restorable(in: directory).isEmpty, "Unreadable backups are never offered")
            var unreadable = false
            do { _ = try BrowserStore(directory: directory, keepsBackups: true) } catch is SessionFileUnreadable { unreadable = true }
            #expect(unreadable, "Startup still stops on the unreadable file")
            #expect(try Data(contentsOf: directory.appendingPathComponent("session.json")) == damaged, "The file is untouched")
            #expect(SessionBackups.list(in: directory).count == 1, "Existing backups are left as they were")
        }
    }
}
