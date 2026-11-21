import Combine
import Foundation
import Testing
@testable import ParcCore

@MainActor @Suite(.serialized)
struct BrowserStoreFileObservationTests {
    struct Failure: Error, CustomStringConvertible {
        let description: String
    }

    static func withDirectory(_ body: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("parc-model-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                                               attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(directory)
    }

    static func withDirectory(_ body: (URL) async throws -> Void) async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("parc-model-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                                               attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        try await body(directory)
    }

    static func tab(_ id: UUID, in store: BrowserStore) throws -> BrowserTab {
        guard let value = store.state.tabs.first(where: { $0.id == id }) else {
            throw Failure(description: "Expected tab \(id) to exist")
        }
        return value
    }

    static func expectValidSelection(_ store: BrowserStore) throws {
        let visible = Set(store.visibleTabs.map(\.id))
        #expect(store.state.selectedTabIDs.allSatisfy { visible.contains($0) }, "Selection must contain only visible, unarchived tabs in the active profile/Space")
        #expect(Set(store.state.selectedTabIDs).count == store.state.selectedTabIDs.count, "Split selection must not contain duplicate tabs")
    }

    @Test static func profileSettingsIdenticalBytePersistSkip() throws {
        try withDirectory { directory in
            let date = Date(timeIntervalSince1970: 1_800_000_000)
            let store = try BrowserStore(directory: directory, now: { date })
            let file = directory.appendingPathComponent("session.json")
            DataFileOperations.install()
            let tab = store.open("https://example.org/observed")
            store.updateTab(tab, title: DataObservedString.text("Observed session tab"))
            func session(_ body: () throws -> Void) throws -> (encodes: Int, replaces: Int, offMain: Bool, calls: [DataFileOperation]) {
                var calls: [DataFileOperation] = []
                let reads = try DataObservedString.reads { calls = try DataFileOperations.during(directory, body) }
                let writes = calls.filter { $0.fileName.hasPrefix(".session-") }
                let occurrences = (try? String(contentsOf: file, encoding: .utf8))
                    .map { $0.components(separatedBy: "Observed session tab").count - 1 } ?? 0
                let encodes = DataObservedString.backgroundEncodes(reads)
                return (occurrences > 0 && encodes % occurrences == 0 ? encodes / occurrences : -1,
                        Set(writes.map(\.path)).count, !writes.contains(where: \.onMainThread), calls)
            }

            let width = try session { try store.saveSidebarWidth(278) }
            #expect(width.encodes == 1 && width.replaces == 1, "A settings commit encodes and atomically replaces once")
            #expect(width.offMain, "Settings commit encodes off the calling thread")
            let afterWidth = try Data(contentsOf: file)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            var expected = store.state; expected.windows = store.windowRecords; expected.history = []
            #expect(afterWidth == (try encoder.encode(expected)), "Settings commits keep pretty-printed sorted-keys identity")

            let identical = try session {
                try store.save()
                try store.save()
            }
            let identicalChecks = identical.calls.filter { $0.name == "fileExists" && $0.fileName == "session.json" }
            #expect(identical.encodes == 2 && identicalChecks.count == 2 && !identicalChecks.contains(where: \.onMainThread), "Repeated identical saves may still encode off-thread")
            #expect(identical.replaces == 0, "Repeated identical saves do not replace the durable session")
            #expect(try Data(contentsOf: file) == afterWidth, "Skipped saves leave the exact on-disk bytes")

            let restore = try session { try store.saveRestoreSession(false) }
            #expect(restore.encodes == 1 && restore.replaces == 1 && restore.offMain, "A real settings change encodes and atomically replaces")
            let afterRestore = try Data(contentsOf: file)
            expected = store.state; expected.windows = store.windowRecords; expected.history = []
            #expect(try afterRestore != afterWidth
                           && afterRestore == (try encoder.encode(expected)), "Distinct settings keep pretty/sorted identity with the live state")

            let unchanged = try session { try store.save() }
            #expect(try unchanged.replaces == 0 && (try Data(contentsOf: file)) == afterRestore, "Save after a settings commit with no further mutation skips replace")

            let selection = try session { try store.saveSettingsSelection(pane: "Profiles", profileID: store.state.profiles[0].id) }
            #expect(selection.replaces == 1, "A later distinct settings commit still atomically replaces")
            expected = store.state; expected.windows = store.windowRecords; expected.history = []
            #expect(try Data(contentsOf: file) == (try encoder.encode(expected)), "Distinct settings commit keeps pretty/sorted identity")

            let bytesBeforeDelete = try Data(contentsOf: file)
            try FileManager.default.removeItem(at: file)
            #expect(!FileManager.default.fileExists(atPath: file.path), "Precondition: session file is absent")
            let recreate = try session { try store.save() }
            #expect(FileManager.default.fileExists(atPath: file.path) && recreate.replaces == 1, "Identical bytes still recreate a missing session file")
            #expect(try Data(contentsOf: file) == bytesBeforeDelete, "Recreated session keeps the prior pretty/sorted payload")
            let afterRecreate = try session { try store.save() }
            #expect(try afterRecreate.replaces == 0 && (try Data(contentsOf: file)) == bytesBeforeDelete, "After recreate, identical bytes skip replace while the file exists")
            let later = try session { try store.saveSidebarWidth(300) }
            expected = store.state; expected.windows = store.windowRecords; expected.history = []
            #expect(try later.replaces == 1 && (try Data(contentsOf: file)) == (try encoder.encode(expected)), "A later settings commit after recreate still atomically replaces")
        }
    }

    @Test static func sessionSavePendingScheduleCoalesce() async throws {
        try await withDirectory { directory in
            let date = Date(timeIntervalSince1970: 1_800_000_000)
            let store = try BrowserStore(directory: directory, now: { date })
            let tabID = store.open("https://example.org/coalesce")
            store.updateTab(tabID, title: "Coalesce", url: "https://example.org/coalesce/page")
            try store.save()
            let file = directory.appendingPathComponent("session.json")
            let bytesAfterSave = try Data(contentsOf: file)
            DataFileOperations.install()
            func replaces(_ calls: [DataFileOperation]) -> [DataFileOperation] {
                calls.filter { $0.name == "createFile" && $0.fileName.hasPrefix(".session-") }
            }
            func spin(until uptime: TimeInterval) async throws {
                try await Task.sleep(nanoseconds: UInt64(max(0, uptime - ProcessInfo.processInfo.systemUptime) * 1_000_000_000))
            }

            let idle = try await DataFileOperations.during(directory) {
                store.selectTab(tabID)
                store.selectTab(tabID)
                store.selectTab(tabID)
                try await Task.sleep(nanoseconds: 400_000_000)
            }
            #expect(try replaces(idle).isEmpty && (try Data(contentsOf: file)) == bytesAfterSave, "Debounced identical snapshot does not rewrite durable session bytes")

            let armedAt = ProcessInfo.processInfo.systemUptime
            var lastUnchanged = armedAt
            let edit = try await DataFileOperations.during(directory) {
                store.updateSettings { $0.sidebarWidth = 301 }
                try await spin(until: armedAt + 0.12)
                store.updateSettings { $0.sidebarWidth = 301 }
                store.selectTab(tabID)
                try await spin(until: armedAt + 0.22)
                lastUnchanged = ProcessInfo.processInfo.systemUptime
                store.selectTab(tabID)
                store.updateSettings { $0.sidebarWidth = 301 }
                try await spin(until: armedAt + 0.8)
            }
            let writes = replaces(edit)
            #expect(writes.count == 1, "Distinct debounced revision still atomically replaces once")
            let delay = (writes.first?.time ?? 0) - armedAt
            #expect(delay >= 0.25 && (writes.first?.time ?? .infinity) < lastUnchanged + 0.25, "Unchanged mutations while the debounce is pending do not reset it (\(delay) s)")
            let afterEdit = try Data(contentsOf: file)
            #expect(afterEdit != bytesAfterSave, "Distinct persist changes durable bytes")
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            var expected = store.state; expected.windows = store.windowRecords; expected.history = []
            #expect(afterEdit == (try encoder.encode(expected)), "Distinct persist keeps pretty-printed sorted-keys identity")
            let permissions = try FileManager.default.attributesOfItem(atPath: file.path)
            #expect((permissions[.posixPermissions] as? NSNumber)?.intValue == 0o600, "Coalesced path leaves owner-only permissions unchanged")
        }
    }
}
