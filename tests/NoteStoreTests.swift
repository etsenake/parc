import Foundation
import Combine

@main @MainActor
struct NoteStoreTests {
    static var assertions = 0
    static func expect(_ value: @autoclosure () throws -> Bool, _ message: String) throws {
        assertions += 1; if try !value() { throw NSError(domain: message, code: 1) }
    }
    static func rejects(_ message: String, _ body: () throws -> Void) throws {
        assertions += 1
        do { try body() } catch { return }
        throw NSError(domain: "Expected rejection: " + message, code: 1)
    }
    static func body(_ original: NoteBody, text: String) -> NoteBody {
        var result = original; result.text = text
        result.richText = .init(runs: text.isEmpty ? [] : [.init(location: 0, length: text.utf16.count,
            attributes: .init(font: .init(name: "Helvetica", size: 15), ink: "#252525FF", underline: 1, link: "https://example.test/"))])
        return result
    }
    /// The document writer's work while `body` runs. Its encodes are reads of an
    /// observed title off the main thread; its atomic replaces each remove one
    /// `.write-` temporary, a file only the writer touches.
    struct Writes { var encodes: Int; var replaces: Int; var offMain: Bool }
    static func writes(in directory: URL, _ body: () throws -> Void) throws -> Writes {
        var calls: [FileOperation] = []
        let reads = try ObservedString.reads { calls = try FileOperations.during(directory, body) }
        let temporaries = calls.filter { $0.fileName.hasPrefix(".write-") }
        return Writes(encodes: ObservedString.backgroundEncodes(reads), replaces: Set(temporaries.map(\.path)).count,
                      offMain: !temporaries.isEmpty && !temporaries.contains(where: \.onMainThread))
    }
    static func main() throws {
        FileOperations.install()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-notes-model-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let notes = try NoteStore(directory: directory, now: { Date(timeIntervalSince1970: 42) }, diskSaveDelay: 0)
        let session = try notes.create(), initial = session.document
        try expect(try notes.load(initial.id) === session, "Document sessions share exact live identity")
        try expect(initial.body.id != initial.id && initial.revision == 0, "Stable document and body identities are distinct")
        try expect(try notes.list().map(\.id) == [initial.id], "Created document is durably listed")
        let richBody = body(initial.body, text: "A 👩🏽‍💻 note\nsecond paragraph")
        try session.updateBody(richBody, replacing: initial.body)
        try session.updateTitle("Local title", replacing: initial.title)
        try expect(session.document.body == richBody && session.document.revision == 2, "Title edits preserve original Unicode rich body")
        try expect(try NoteStore(directory: directory, diskSaveDelay: 0).load(initial.id).document == session.document, "Full document round-trips after reopening")
        try expect(session.document.createdAt == initial.createdAt, "Editing preserves creation time")
        try rejects("stale title") { try session.updateTitle("Stale", replacing: initial.title) }
        try rejects("stale body") { try session.updateBody(body(initial.body, text: "Stale"), replacing: initial.body) }
        try rejects("body identity replacement") { var changed = richBody; changed.id = UUID(); try session.updateBody(changed, replacing: richBody) }
        try expect(session.document.title == "Local title" && session.document.body == richBody, "Rejected edits preserve saved content")
        let old = session.document
        try rejects("oversized title") { try session.updateTitle(String(repeating: "x", count: 4097), replacing: old.title) }
        try expect(session.document == old, "Invalid edit does not publish a revision")
        var invalid = richBody; invalid.richText.runs[0].length -= 1
        try rejects("incomplete rich range") { try session.updateBody(invalid, replacing: richBody) }
        try rejects("stale deletion") { try notes.delete(initial.id, expectedRevision: 0) }
        var pairedBody = body(richBody, text: "Transferred suffix\nBody")
        try rejects("paired stale title") { try session.updateTitleAndBody(title: "Prefix", body: pairedBody, replacingTitle: initial.title, body: richBody) }
        try rejects("paired stale body") { try session.updateTitleAndBody(title: "Prefix", body: pairedBody, replacingTitle: old.title, body: initial.body) }
        pairedBody.id = UUID()
        try rejects("paired replacement identity") { try session.updateTitleAndBody(title: "Prefix", body: pairedBody, replacingTitle: old.title, body: richBody) }
        pairedBody.id = richBody.id
        try expect(session.document == old, "Rejected paired changes preserve both fields and revision")
        try session.updateTitleAndBody(title: "Prefix", body: pairedBody, replacingTitle: old.title, body: richBody)
        try expect(session.document.revision == old.revision + 1 && session.document.title == "Prefix" && session.document.body == pairedBody, "Valid paired boundary commits both fields in one revision")
        try expect(try NoteStore(directory: directory, diskSaveDelay: 0).load(initial.id).document == session.document, "Paired save round-trips together")
        try session.updateTitleAndBody(title: old.title, body: old.body, replacingTitle: "Prefix", body: pairedBody)
        let afterPaired = session.document
        let other = try NoteStore(directory: directory.appendingPathComponent("other-profile"), diskSaveDelay: 0).create()
        try expect(other.document.id != initial.id, "Separate profile has independent document identity")
        let savedPath = directory.appendingPathComponent(initial.id.uuidString.lowercased() + ".json")
        let bytes = try Data(contentsOf: savedPath)
        try FileManager.default.removeItem(at: savedPath); try FileManager.default.createDirectory(at: savedPath, withIntermediateDirectories: false)
        try rejects("disk destination replaced") { try session.updateTitle("Cannot save", replacing: afterPaired.title) }
        try expect(session.document == afterPaired, "Actual disk failure keeps the previously published document")
        try rejects("paired disk failure") { try session.updateTitleAndBody(title: "Prefix", body: pairedBody, replacingTitle: afterPaired.title, body: afterPaired.body) }
        try expect(session.document == afterPaired, "Paired disk failure cannot publish just one field")
        try FileManager.default.removeItem(at: savedPath); try bytes.write(to: savedPath)
        try notes.delete(initial.id, expectedRevision: session.document.revision)
        try expect(session.document.deleted, "Live peers receive durable tombstone")
        try expect(session.document.title.isEmpty && session.document.body.text.isEmpty && session.document.body.richText.runs.isEmpty, "Tombstone clears title/body content while retaining stale-identity protection")
        try expect(try notes.list().isEmpty, "Deleted note disappears from Library")
        try rejects("reopen deleted") { _ = try NoteStore(directory: directory, diskSaveDelay: 0).load(initial.id) }
        try rejects("mutate deleted peer") { try session.updateTitle("Resurrect", replacing: session.document.title) }
        try expect(try NoteStore(directory: directory.appendingPathComponent("other-profile"), diskSaveDelay: 0).list().count == 1, "Deletion preserves other profile data")
        let symlink = directory.appendingPathComponent("linked")
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: directory)
        try rejects("symbolic directory") { _ = try NoteStore(directory: symlink, diskSaveDelay: 0) }
        let delayDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-notes-delay-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: delayDirectory) }
        let delayed = try NoteStore(directory: delayDirectory, now: { Date(timeIntervalSince1970: 99) }, diskSaveDelay: 60)
        let live = try delayed.create()
        let createdTitle = live.document.title
        try live.updateTitle("Delayed title", replacing: createdTitle)
        try expect(live.document.title == "Delayed title" && live.hasDelayedDiskSave, "In-memory title publishes before the recovered delayed disk save")
        let delayedPath = delayDirectory.appendingPathComponent(live.document.id.uuidString.lowercased() + ".json")
        let stale = try JSONDecoder().decode(NoteDocument.self, from: Data(contentsOf: delayedPath))
        try expect(stale.title == createdTitle, "Disk still has the immediately persisted create until flush")
        try expect(try delayed.list().first?.title == "Delayed title", "Library list uses the live session during the delay")
        try live.updateTitle(ObservedString.text("Latest delayed title"), replacing: "Delayed title")
        try delayed.flushDelayedDiskSave(live.document.id)
        let flushed = try JSONDecoder().decode(NoteDocument.self, from: Data(contentsOf: delayedPath))
        try expect(flushed.title == "Latest delayed title" && !live.hasDelayedDiskSave, "A later edit cancels the earlier delayed save and flush writes the latest document")
        try expect(try NoteStore(directory: delayDirectory, diskSaveDelay: 0).load(live.document.id).document.title == "Latest delayed title", "Flushed delayed save round-trips from disk")
        let published = live.document
        try rejects("oversized delayed title") { try live.updateTitle(String(repeating: "x", count: 4097), replacing: published.title) }
        try expect(live.document == published && !live.hasDelayedDiskSave, "Invalid delayed edit does not publish a revision or schedule disk")
        try delayed.validateReference(live.document.id)
        var libraryReloads = 0
        let library = delayed.changes.sink { libraryReloads += 1 }
        defer { library.cancel() }
        let bodyTyping = try writes(in: delayDirectory) {
            try live.updateBody(body(published.body, text: "typed body"), replacing: published.body)
        }
        try expect(libraryReloads == 0, "Body-only in-memory publication does not reload the documents library")
        try expect(bodyTyping.encodes == 0 && bodyTyping.replaces == 0 && live.hasDelayedDiskSave, "Delayed body persist does not JSON-encode on the typing path")
        let bodyFlush = try writes(in: delayDirectory) { try delayed.flushDelayedDiskSave(live.document.id) }
        try expect(bodyFlush.encodes == 1 && bodyFlush.replaces == 1 && !live.hasDelayedDiskSave, "Disk persist encodes the document once")
        try expect(libraryReloads == 1, "Completed disk persist notifies the library")
        libraryReloads = 0
        let titleTyping = try writes(in: delayDirectory) {
            try live.updateTitle(ObservedString.text("Library title while typing"), replacing: live.document.title)
        }
        try expect(libraryReloads == 1 && titleTyping.encodes == 0 && titleTyping.replaces == 0, "Title publication updates the library without encoding on the keystroke")
        let titleFlush = try writes(in: delayDirectory) { try delayed.flushDelayedDiskSave(live.document.id) }
        try expect(titleFlush.encodes == 1 && titleFlush.replaces == 1 && libraryReloads == 1, "Title disk persist encodes once without a second library reload")
        let failDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-notes-fail-" + UUID().uuidString)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: failDirectory.path)
            try? FileManager.default.removeItem(at: failDirectory)
        }
        let failing = try NoteStore(directory: failDirectory, now: { Date(timeIntervalSince1970: 100) }, diskSaveDelay: 60)
        let failingSession = try failing.create()
        try failingSession.updateTitle("Unwritable", replacing: failingSession.document.title)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: failDirectory.path)
        try rejects("flush while directory is not writable") { try failing.flushDelayedDiskSave(failingSession.document.id) }
        try expect(failingSession.diskSaveError != nil && failingSession.document.title == "Unwritable", "Flush persist failure keeps the in-memory document and records the disk error")
        try failing.validateReference(failingSession.document.id)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: failDirectory.path)
        try failing.flushDelayedDiskSave(failingSession.document.id)
        try expect(failingSession.diskSaveError == nil && !failingSession.hasDelayedDiskSave, "Retry flush persists after storage recovers")
        let asyncDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-notes-async-" + UUID().uuidString)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: asyncDirectory.path)
            try? FileManager.default.removeItem(at: asyncDirectory)
        }
        let asyncStore = try NoteStore(directory: asyncDirectory, diskSaveDelay: 0.05)
        let asyncSession = try asyncStore.create()
        try asyncSession.updateTitle("Async fail", replacing: asyncSession.document.title)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: asyncDirectory.path)
        let deadline = Date().addingTimeInterval(1)
        while asyncSession.diskSaveError == nil && Date() < deadline {
            _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        try expect(asyncSession.diskSaveError != nil && !asyncSession.hasDelayedDiskSave && asyncSession.document.title == "Async fail", "Delayed persist failure keeps the in-memory document and reports the disk error")
        try asyncStore.validateReference(asyncSession.document.id)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: asyncDirectory.path)
        try asyncStore.flushDelayedDiskSave(asyncSession.document.id)
        try expect(asyncSession.diskSaveError == nil, "Retry flush after delayed persist failure writes the live document")
        let dropDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-notes-drop-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dropDirectory) }
        let dropStore = try NoteStore(directory: dropDirectory, now: { Date(timeIntervalSince1970: 101) }, diskSaveDelay: 60)
        let dropID: UUID
        do {
            let transient = try dropStore.create()
            dropID = transient.document.id
            let created = transient.document.title
            try transient.updateTitle("Library rename", replacing: created)
            try dropStore.validateReference(dropID)
        }
        try expect(try dropStore.list().first?.title == "Library rename", "Library list keeps a delayed document after the editor session dies")
        try dropStore.flushAllDelayedDiskSaves()
        try expect(try NoteStore(directory: dropDirectory, diskSaveDelay: 0).load(dropID).document.title == "Library rename", "Quit/export flush writes delayed saves that had no live editor")

        let offDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-notes-off-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: offDirectory) }
        let offStore = try NoteStore(directory: offDirectory, now: { Date(timeIntervalSince1970: 102) }, diskSaveDelay: 0)
        // The created note's title is a native literal, so only its replace shows;
        // every later revision carries an observed title.
        var created: NoteSession?
        let create = try writes(in: offDirectory) { created = try offStore.create() }
        let offSession = created!
        try expect(create.replaces == 1 && create.offMain, "Create writes once through the document writer, off the calling/MainActor stack")
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let createExpected = try encoder.encode(offSession.document)
        let offPath = offDirectory.appendingPathComponent(offSession.document.id.uuidString.lowercased() + ".json")
        try expect(try Data(contentsOf: offPath) == createExpected, "Persisted JSON bytes match sortedKeys encoder output exactly")

        let titled = try writes(in: offDirectory) {
            try offSession.updateTitle(ObservedString.text("Observed title"), replacing: offSession.document.title)
        }
        try expect(titled.encodes == 1 && titled.replaces == 1 && titled.offMain,
                   "Immediate title persist encodes and replaces once off the calling stack")
        let bodyEdit = try writes(in: offDirectory) {
            try offSession.updateBody(body(offSession.document.body, text: "off-main body"), replacing: offSession.document.body)
        }
        try expect(bodyEdit.encodes == 1 && bodyEdit.offMain, "Immediate body persist encodes once off the calling stack")
        try expect(bodyEdit.replaces == 1, "Body edit atomically replaces")
        let offBodyExpected = try encoder.encode(offSession.document)
        try expect(try Data(contentsOf: offPath) == offBodyExpected, "Body persist keeps sortedKeys identity with the live document")

        let bytesAfterOffBody = try Data(contentsOf: offPath)
        let identical = try writes(in: offDirectory) {
            try offStore.persist(offSession.document)
            try offStore.persist(offSession.document)
        }
        try expect(identical.encodes == 2, "Repeated identical persists may still encode in the writer")
        try expect(identical.replaces == 0, "Repeated identical persists do not replace the durable file")
        try expect(try Data(contentsOf: offPath) == bytesAfterOffBody,
                   "Skipped identical-byte persists leave the exact on-disk bytes")

        let distinct = try writes(in: offDirectory) {
            try offSession.updateTitle(ObservedString.text("Distinct title"), replacing: offSession.document.title)
        }
        try expect(distinct.encodes == 1 && distinct.replaces == 1 && distinct.offMain,
                   "A distinct revision encodes and atomically replaces")
        let offTitleExpected = try encoder.encode(offSession.document)
        try expect(try Data(contentsOf: offPath) == offTitleExpected,
                   "Distinct persist keeps sortedKeys identity")

        let bytesAfterOffTitle = try Data(contentsOf: offPath)
        let unchanged = try writes(in: offDirectory) { try offStore.persist(offSession.document) }
        try expect(unchanged.replaces == 0 && (try Data(contentsOf: offPath)) == bytesAfterOffTitle,
                   "Persist of an unchanged document after an edit skips replace")

        print("NoteStore: \(assertions) assertions passed")
    }
}
