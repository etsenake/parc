import Foundation
import Testing
@testable import ParcCore

struct SessionBackupWritingTests {
    private typealias Support = SessionBackupTestsSupport

    @MainActor
    private static func withFirstBackup(_ body: (URL, BrowserStore, Support.Clock) throws -> Void) throws {
        try Support.withDirectory { directory in
            let clock = Support.Clock(Support.base)
            let store = try Support.backingStore(directory, clock)
            _ = store.openResolvedURL(URL(string: "https://first.test/")!)
            store.recordDownload(["id": 7, "name": "file.zip", "path": "/tmp/file.zip", "sourceURL": "https://download.test/file.zip"])
            try Support.flush(store)
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
            #expect(try Support.texts(directory)[0].contains(Support.escaped("https://first.test/")), "The backup holds the open tab")
            #expect(!(try Support.texts(directory)[0].contains("download.test")), "No download address reaches a backup")
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
            clock.now = Support.base.addingTimeInterval(600)
            _ = store.openResolvedURL(URL(string: "https://second.test/")!)
            try Support.flush(store)
            #expect(SessionBackups.list(in: directory).count == 1, "Saves within the hour don't add copies")
            clock.now = Support.base.addingTimeInterval(3_700)
            _ = store.openResolvedURL(URL(string: "https://third.test/")!)
            try Support.flush(store)
            #expect(SessionBackups.list(in: directory).count == 2, "The first save after an hour adds a copy")
            #expect(try Support.texts(directory)[0].contains(Support.escaped("https://third.test/")), "The new copy is the current sidebar")
        }
    }

    @Test
    @MainActor
    static func unchangedSidebarsAreNotBackedUpAgain() throws {
        try withFirstBackup { directory, store, clock in
            clock.now = Support.base.addingTimeInterval(9_000)
            try Support.flush(store)
            #expect(SessionBackups.list(in: directory).count == 1, "An unchanged sidebar isn't copied again")
        }
    }

    @MainActor
    private static func withSavedSidebar(_ body: (URL, Support.Clock) throws -> Void) throws {
        try Support.withDirectory { directory in
            let plain = try BrowserStore(directory: directory)
            _ = plain.openResolvedURL(URL(string: "https://launch.test/")!)
            try plain.save()
            try body(directory, Support.Clock(Support.base))
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
            try Support.flush(try Support.backingStore(directory, clock))
            #expect(try Support.texts(directory).first?.contains(Support.escaped("https://launch.test/")) == true, "A sidebar that loaded and validated is backed up at launch")
        }
    }

    @Test
    @MainActor
    static func relaunchBackupsFollowHourlyCadence() throws {
        try withSavedSidebar { directory, clock in
            try Support.flush(try Support.backingStore(directory, clock))
            let changed = try BrowserStore(directory: directory)
            _ = changed.openResolvedURL(URL(string: "https://changed.test/")!)
            try changed.save()
            clock.now = Support.base.addingTimeInterval(600)
            try Support.flush(try Support.backingStore(directory, clock))
            #expect(SessionBackups.list(in: directory).count == 1, "Relaunching within the hour adds no copy")
            clock.now = Support.base.addingTimeInterval(3_700)
            try Support.flush(try Support.backingStore(directory, clock))
            #expect(SessionBackups.list(in: directory).count == 2, "Relaunching after an hour copies the changed sidebar")
        }
    }

    @Test
    static func invalidStatesAreNotBackedUp() throws {
        try Support.withDirectory { directory in
            var invalid = BrowserState.initial()
            let space = invalid.spaces[0]
            invalid.tabs = [BrowserTab(id: UUID(), spaceID: UUID(), profileID: space.profileID, url: "https://x.test/",
                                       title: "x", kind: .today, createdAt: Support.base, lastAccessed: Support.base,
                                       savedURL: "https://x.test/", savedTitle: "x")]
            let backups = SessionBackups(directory: directory, calendar: Support.utc)
            var refused = false
            do { try backups.backUp(invalid, at: Support.base) } catch { refused = true }
            #expect(refused, "A state that fails validation is refused")
            backups.backUpIfDue(invalid, at: Support.base)
            #expect(!FileManager.default.fileExists(atPath: SessionBackups.folder(in: directory).path), "No copy of it is written")
        }
    }

    @Test @MainActor static func anUnreadableSessionReportsASessionFileError() throws {
        try Support.withDirectory { directory in
            try Data("{\"broken\":".utf8).write(to: directory.appendingPathComponent("session.json"))
            var unreadable = false
            do { _ = try Support.backingStore(directory, Support.Clock(Support.base)) } catch is SessionFileUnreadable { unreadable = true }
            #expect(unreadable, "An unreadable main file is reported as such")
        }
    }

    @Test @MainActor static func anUnreadableSessionDoesNotCreateABackup() throws {
        try Support.withDirectory { directory in
            try Data("{\"broken\":".utf8).write(to: directory.appendingPathComponent("session.json"))
            do { _ = try Support.backingStore(directory, Support.Clock(Support.base)) }
            catch is SessionFileUnreadable {}
            #expect(SessionBackups.list(in: directory).isEmpty, "An unreadable main file is never backed up")
        }
    }
}
