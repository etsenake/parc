import Foundation
import Testing
@testable import ParcCore

struct EaselStorePersistenceTests {
    private final class ReplacementLog {
        struct Write {
            let data: Data
            let isOnMainThread: Bool
        }

        var writes: [Write] = []

        func replace(_ data: Data, at url: URL) throws {
            try data.write(to: url, options: .atomic)
            writes.append(Write(data: data, isOnMainThread: Thread.isMainThread))
        }
    }

    @MainActor
    private func withStore(_ run: (EaselStore, ReplacementLog) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let log = ReplacementLog()
        let store = try EaselStore(directory: directory, now: { Date(timeIntervalSince1970: 2_000) },
                                   replaceDocument: log.replace)
        try run(store, log)
    }

    @MainActor @Test
    func creatingABoardWritesOffTheCallingThread() throws {
        try withStore { store, log in
            _ = try store.create()
            let write = try #require(log.writes.first)
            #expect(!write.isOnMainThread)
        }
    }

    @MainActor @Test
    func editingABoardWritesOffTheCallingThread() throws {
        try withStore { store, log in
            let session = try store.create()
            log.writes.removeAll()
            try session.perform("Rename") { $0.title = "Updated" }
            let write = try #require(log.writes.first)
            #expect(!write.isOnMainThread)
        }
    }

    @MainActor @Test
    func savingTheSameBoardSkipsReplacement() throws {
        try withStore { store, log in
            let session = try store.create()
            log.writes.removeAll()
            try session.save()
            #expect(log.writes.isEmpty)
        }
    }

    @MainActor @Test
    func editingABoardReplacesItWithSortedJSON() throws {
        try withStore { store, log in
            let session = try store.create()
            log.writes.removeAll()
            try session.perform("Rename") { $0.title = "Updated" }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            #expect(log.writes.map(\.data) == [try encoder.encode(session.document)])
        }
    }

    @MainActor @Test(arguments: [false, true])
    func undoAndRedoWriteOffTheCallingThread(_ redo: Bool) throws {
        try withStore { store, log in
            let session = try store.create()
            try session.perform("Rename") { $0.title = "Updated" }
            if redo { try session.undo() }
            log.writes.removeAll()
            if redo { try session.redo() } else { try session.undo() }
            let write = try #require(log.writes.first)
            #expect(!write.isOnMainThread)
        }
    }
}
