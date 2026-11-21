import Foundation
import Testing
@testable import ParcCore

struct BrowserStoreFileObservationTests {
    private final class Writes: @unchecked Sendable {
        private let lock = NSLock()
        private var events: [(data: Data, onMainThread: Bool)] = []

        var recorded: [(data: Data, onMainThread: Bool)] { lock.withLock { events } }

        var files: SessionFileOperations {
            let live = SessionFileOperations.live
            return SessionFileOperations(exists: live.exists, replace: { data, url in
                try live.replace(data, url)
                self.lock.withLock { self.events.append((data, Thread.isMainThread)) }
            })
        }
    }

    @MainActor
    private func withStore(_ body: (BrowserStore, URL, Writes) throws -> Void) throws {
        try DataFixtures.withTemporaryDirectory { directory in
            let writes = Writes()
            let date = Date(timeIntervalSince1970: 1_800_000_000)
            let store = try BrowserStore(directory: directory, now: { date }, sessionFiles: writes.files)
            try body(store, directory.appendingPathComponent("session.json"), writes)
        }
    }

    @MainActor @Test func aSettingsChangeReplacesTheSessionOffTheMainThread() throws {
        try withStore { store, file, writes in
            try store.saveSidebarWidth(278)

            let write = try #require(writes.recorded.first)
            #expect(writes.recorded.count == 1)
            #expect(!write.onMainThread)
            #expect(try Data(contentsOf: file) == write.data)
        }
    }

    @MainActor @Test func aSettingsCommitKeepsPrettyPrintedSortedSessionBytes() throws {
        try withStore { store, file, _ in
            try store.saveSidebarWidth(278)

            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            var expected = store.state
            expected.windows = store.windowRecords
            expected.history = []
            let encoded = try encoder.encode(expected)
            #expect(try Data(contentsOf: file) == encoded)
        }
    }

    @MainActor @Test func identicalSavesKeepTheExistingSessionFile() throws {
        try withStore { store, file, writes in
            try store.saveSidebarWidth(278)
            let original = try Data(contentsOf: file)

            try store.save()
            try store.save()

            #expect(writes.recorded.count == 1)
            #expect(try Data(contentsOf: file) == original)
        }
    }

    @MainActor @Test func identicalBytesRecreateAMissingSessionFile() throws {
        try withStore { store, file, writes in
            try store.saveSidebarWidth(278)
            let original = try Data(contentsOf: file)
            try FileManager.default.removeItem(at: file)

            try store.save()

            #expect(writes.recorded.count == 2)
            #expect(try Data(contentsOf: file) == original)
        }
    }

    @MainActor @Test func aChangedSettingStillWritesAfterAnIdenticalSave() throws {
        try withStore { store, file, writes in
            try store.saveSidebarWidth(278)
            try store.save()

            try store.saveRestoreSession(false)

            #expect(writes.recorded.count == 2)
            #expect(try Data(contentsOf: file) != writes.recorded.first?.data)
        }
    }

    @MainActor @Test func anUnchangedDeferredSnapshotKeepsTheExistingSessionFile() throws {
        try withStore { store, file, writes in
            let scheduler = DataFixtures.DeferredSave(store)
            let tab = store.open("https://example.org")
            try store.save()
            let original = try Data(contentsOf: file)

            store.selectTab(tab)
            scheduler.run(on: store)

            #expect(writes.recorded.count == 1)
            #expect(try Data(contentsOf: file) == original)
        }
    }

    @MainActor @Test func anUnchangedMutationKeepsTheAlreadyScheduledSave() throws {
        try withStore { store, _, writes in
            let scheduler = DataFixtures.DeferredSave(store)
            let tab = store.open("https://example.org")
            try store.save()
            scheduler.run(on: store)
            store.updateSettings { $0.sidebarWidth = 301 }
            let scheduled = try #require(scheduler.work.first)

            store.selectTab(tab)

            #expect(scheduler.work.count == 1)
            #expect(!scheduled.isCancelled)
            scheduler.run(on: store)
            #expect(writes.recorded.count == 2)
        }
    }
}
