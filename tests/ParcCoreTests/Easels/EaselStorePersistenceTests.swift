import Foundation
import Testing
@testable import ParcCore

@MainActor @Suite(.serialized) struct EaselStorePersistenceTests {
    func withDirectory(_ body: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-easel-persist-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(directory)
    }

    let frame = EaselRect(x: 20, y: 30, width: 120, height: 80)

    nonisolated static func file(_ directory: URL, _ id: UUID) -> URL {
        directory.appendingPathComponent("documents/" + id.uuidString.lowercased() + ".json")
    }

    func file(_ directory: URL, _ id: UUID) -> URL { Self.file(directory, id) }

    struct Writes {
        let directory: URL
        let calls: [FileOperation]
        let encodes: Int
        func temporaries(_ id: UUID) -> [FileOperation] {
            let documents = EaselStorePersistenceTests.file(directory, id).deletingLastPathComponent().standardizedFileURL.path
            return calls.filter { $0.fileName.hasPrefix(".write-") && ($0.path as NSString).deletingLastPathComponent == documents }
        }
        func replaces(_ id: UUID) -> Int { Set(temporaries(id).map(\.path)).count }
        func offMain(_ id: UUID) -> Bool { !temporaries(id).contains(where: \.onMainThread) }
    }
    func writes(in directory: URL, _ body: () throws -> Void) throws -> Writes {
        EaselFileOperations.install()
        var calls: [FileOperation] = []
        let reads = try EaselObservedString.reads { calls = try EaselFileOperations.during(directory, body) }
        return Writes(directory: directory, calls: calls, encodes: EaselObservedString.backgroundEncodes(reads))
    }

    @Test func persistingEncodesOffTheCallingThread() throws {
        try withDirectory { directory in
            let store = try EaselStore(directory: directory, now: { Date(timeIntervalSince1970: 2_000) })
            var created: EaselSession?
            let create = try writes(in: directory) { created = try store.create(title: EaselObservedString.text("Off-thread board")) }
            let session = created!
            #expect(create.encodes == 1, "Create encodes once through the document writer")
            #expect(create.replaces(session.document.id) == 1 && create.offMain(session.document.id), "Create encode is off the calling thread")

            let edit = try writes(in: directory) {
                try session.perform("Canvas edit") {
                    $0.items = [EaselItem(kind: .text, frame: frame, text: "Stroke"),
                                EaselItem(kind: .freehand, frame: frame,
                                          points: [.init(x: 0, y: 0), .init(x: 10, y: 20), .init(x: 30, y: 5)])]
                }
            }
            #expect(edit.encodes == 1, "Each canvas persist encodes once")
            #expect(edit.replaces(session.document.id) == 1 && edit.offMain(session.document.id),
                   "Canvas persist encode is off the calling/MainActor stack")

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let expected = try encoder.encode(session.document)
            let onDisk = try Data(contentsOf: file(directory, session.document.id))
            #expect(onDisk == expected, "Persisted JSON bytes match sortedKeys encoder output exactly")

            let undo = try writes(in: directory) {
                try session.perform("Rename") { $0.title = EaselObservedString.text("Renamed board") }
                try session.undo()
                try session.redo()
            }
            #expect(undo.encodes == 3 && undo.replaces(session.document.id) == 3 && undo.offMain(session.document.id),
                   "Undo/redo encode off the calling thread")
            let afterRedo = try Data(contentsOf: file(directory, session.document.id))
            let redoExpected = try encoder.encode(session.document)
            #expect(afterRedo == redoExpected, "Undo/redo keep sortedKeys identity with the live document")

            let bytesBeforeSave = try Data(contentsOf: file(directory, session.document.id))
            let save = try writes(in: directory) { try session.save() }
            #expect(save.encodes == 1, "Explicit save still encodes off the calling thread")
            #expect(save.replaces(session.document.id) == 0,
                   "Explicit save of unchanged sortedKeys bytes skips atomic replace")
            let afterSave = try Data(contentsOf: file(directory, session.document.id))
            let saveExpected = try encoder.encode(session.document)
            #expect(afterSave == saveExpected && afterSave == bytesBeforeSave,
                   "Identical-byte save leaves durable sortedKeys payload unchanged")

            let reopened = try EaselStore(directory: directory).load(session.document.id)
            #expect(reopened.document == session.document, "Off-thread persist round-trips the exact document")
        }
    }

    @Test func savingIdenticalBytesSkipsTheAtomicReplace() throws {
        try withDirectory { directory in
            let store = try EaselStore(directory: directory, now: { Date(timeIntervalSince1970: 3_000) })
            var created: EaselSession?
            let create = try writes(in: directory) { created = try store.create(title: EaselObservedString.text("Skip board")) }
            let session = created!
            #expect(create.encodes == 1 && create.replaces(session.document.id) == 1,
                   "Create encodes and atomically replaces once")

            let bytesAfterCreate = try Data(contentsOf: file(directory, session.document.id))
            let saves = try writes(in: directory) {
                try session.save()
                try session.save()
            }
            #expect(saves.encodes == 2,
                   "Repeated identical saves may still encode off-thread")
            #expect(saves.replaces(session.document.id) == 0,
                   "Repeated identical saves do not replace the durable file")
            #expect(try! Data(contentsOf: file(directory, session.document.id)) == bytesAfterCreate,
                   "Skipped saves leave the exact on-disk bytes")

            let realEdit = try writes(in: directory) {
                try session.perform("Real edit") {
                    $0.items = [EaselItem(kind: .text, frame: frame, text: "Changed")]
                }
            }
            #expect(realEdit.encodes == 1 && realEdit.replaces(session.document.id) == 1,
                   "A real edit encodes and atomically replaces")
            let afterEdit = try Data(contentsOf: file(directory, session.document.id))
            #expect(afterEdit != bytesAfterCreate, "Real edit changes durable sortedKeys bytes")
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let editExpected = try encoder.encode(session.document)
            #expect(afterEdit == editExpected,
                   "Real edit bytes stay sortedKeys-identical to the live document")

            let bytesAfterEdit = afterEdit
            let unchanged = try writes(in: directory) { try session.save() }
            #expect(unchanged.replaces(session.document.id) == 0
                       && (try! Data(contentsOf: file(directory, session.document.id))) == bytesAfterEdit,
                   "Save after an edit with no further mutation skips replace")

            let rename = try writes(in: directory) {
                try session.perform("Second edit") { $0.title = EaselObservedString.text("Skip board renamed") }
            }
            #expect(rename.replaces(session.document.id) == 1,
                   "A later distinct document still atomically replaces")
            let renamedExpected = try encoder.encode(session.document)
            #expect(try! Data(contentsOf: file(directory, session.document.id)) == renamedExpected,
                   "Distinct persist keeps sortedKeys identity")
        }
    }
}
