import Foundation
import Combine
import Darwin

// Notes is a document, not an Easel object. The linear body uses the shared
//
struct NoteBody: Codable, Equatable {
    var id = UUID()
    var text = ""
    var richText = EaselRichText(runs: [])
}
struct NoteDocument: Codable, Equatable, Identifiable {
    var version = 1
    var id = UUID()
    var revision: UInt64 = 0
    var title = "Untitled Note"
    var body = NoteBody()
    var createdAt: Date
    var modifiedAt: Date
    var deleted = false
}
enum NoteError: Error, LocalizedError {
    case invalid, missing, deleted, changed
    var errorDescription: String? {
        switch self {
        case .invalid: return "This note’s local document is invalid or unsupported."
        case .missing: return "This note could not be found on this Mac."
        case .deleted: return "This note has been deleted."
        case .changed: return "This note changed in another window. Your draft is still here; discard it to use the saved version."
        }
    }
}
@MainActor
final class NoteStore {
    static let maximumBytes = 8 * 1024 * 1024
    ///
    /// `Publisher.delay(for:tolerance:scheduler:options:)` using
    /// `DispatchQueue.SchedulerTimeType.Stride.seconds` of the Int 3 stored at
    ///
    /// Firebase `DocumentSaveLocation` remains excluded; local disk is the
    /// recovered save location.
    nonisolated static let recoveredDiskSaveDelay: TimeInterval = 3
    private static var shared: [String: NoteStore] = [:]
    static func sharedStore(directory: URL, diskSaveDelay: TimeInterval = recoveredDiskSaveDelay) throws -> NoteStore {
        let key = directory.standardizedFileURL.path
        if let store = shared[key] { return store }
        let store = try NoteStore(directory: directory, diskSaveDelay: diskSaveDelay); shared[key] = store; return store
    }
    static func flushAllSharedDelayedDiskSaves() throws {
        var first: Error?
        for store in shared.values {
            do { try store.flushAllDelayedDiskSaves() } catch { if first == nil { first = error } }
        }
        if let first { throw first }
    }
    let directory: URL
    let diskSaveDelay: TimeInterval
    let changes = PassthroughSubject<Void, Never>()
    /// Off-main sorted-keys encode + atomic replace. Publication still validates
    /// field limits on the caller; encode/write leave the MainActor stack.
    /// Identical sorted-keys bytes skip the atomic replace; distinct revisions
    /// still encode and replace in FIFO order.
    private let documentWriter = NoteDocumentWriter()
    private let now: () -> Date
    private final class WeakSession { weak var value: NoteSession?; init(_ value: NoteSession) { self.value = value } }
    private var sessions: [UUID: WeakSession] = [:]
    private struct DelayedDiskSave {
        var document: NoteDocument
        var notifyLibrary: Bool
        var work: DispatchWorkItem
    }
    private var delayedDiskSaves: [UUID: DelayedDiskSave] = [:]
    private var failedDiskSaves: [UUID: (document: NoteDocument, error: Error)] = [:]
    init(directory: URL, now: @escaping () -> Date = Date.init, diskSaveDelay: TimeInterval = recoveredDiskSaveDelay) throws {
        self.directory = directory.standardizedFileURL; self.now = now; self.diskSaveDelay = diskSaveDelay
        guard directory.isFileURL else { throw NoteError.invalid }
        try FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
        try checkDirectory()
    }
    func list() throws -> [NoteDocument] {
        try checkDirectory()
        var documents: [UUID: NoteDocument] = [:]
        for url in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) where url.pathExtension == "json" {
            guard let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent) else { throw NoteError.invalid }
            let document = try read(id)
            if !document.deleted { documents[id] = document }
        }
        for (id, pending) in delayedDiskSaves {
            if pending.document.deleted { documents.removeValue(forKey: id) }
            else { documents[id] = pending.document }
        }
        for (id, failed) in failedDiskSaves where delayedDiskSaves[id] == nil {
            if failed.document.deleted { documents.removeValue(forKey: id) }
            else { documents[id] = failed.document }
        }
        for (id, box) in sessions {
            guard let live = box.value else { continue }
            if live.document.deleted { documents.removeValue(forKey: id) }
            else { documents[id] = live.document }
        }
        return documents.values.sorted { $0.modifiedAt == $1.modifiedAt ? $0.id.uuidString < $1.id.uuidString : $0.modifiedAt > $1.modifiedAt }
    }
    func create() throws -> NoteSession {
        let document = NoteDocument(createdAt: now(), modifiedAt: now())
        try persist(document); let value = session(document); changes.send(); return value
    }
    /// A Note brought over from another browser keeps its own last edit.
    func importDocument(title: String, body: NoteBody, modifiedAt: Date) throws -> NoteDocument {
        let document = NoteDocument(title: title, body: body, createdAt: modifiedAt, modifiedAt: modifiedAt)
        try persist(document); changes.send(); return document
    }
    func load(_ id: UUID) throws -> NoteSession {
        if let value = sessions[id]?.value {
            guard !value.document.deleted else { throw NoteError.deleted }; return value
        }
        if let pending = delayedDiskSaves[id] {
            guard !pending.document.deleted else { throw NoteError.deleted }
            return session(pending.document)
        }
        if let failed = failedDiskSaves[id] {
            guard !failed.document.deleted else { throw NoteError.deleted }
            let value = session(failed.document)
            value.diskSaveError = failed.error
            return value
        }
        let document = try read(id)
        guard !document.deleted else { throw NoteError.deleted }; return session(document)
    }
    /// Sidebar aliases share this existing document and any original live draft.
    /// Validate disk and shared session identity without committing that draft.
    func validateReference(_ id: UUID) throws {
        if let live = sessions[id]?.value {
            guard !live.document.deleted else { throw NoteError.deleted }
            if delayedDiskSaves[id] != nil || live.diskSaveError != nil { return }
            let saved = try read(id)
            guard live.document == saved else { throw NoteError.changed }
            return
        }
        if delayedDiskSaves[id] != nil || failedDiskSaves[id] != nil { return }
        let saved = try read(id)
        guard !saved.deleted else { throw NoteError.deleted }
    }
    func delete(_ id: UUID, expectedRevision: UInt64) throws {
        let value = try load(id)
        guard value.document.revision == expectedRevision else { throw NoteError.changed }
        try flushDelayedDiskSave(id)
        try value.replace(persistImmediately: true) {
            $0.deleted = true; $0.title = ""; $0.body.text = ""; $0.body.richText = .init(runs: [])
        }
    }
    func hasDelayedDiskSave(_ id: UUID) -> Bool { delayedDiskSaves[id] != nil }
    func flushDelayedDiskSave(_ id: UUID) throws {
        if let pending = delayedDiskSaves.removeValue(forKey: id) {
            pending.work.cancel()
            try writeDelayed(pending.document, id: id, notifyLibrary: pending.notifyLibrary)
            return
        }
        if let failed = failedDiskSaves.removeValue(forKey: id) {
            try writeDelayed(failed.document, id: id)
            return
        }
        guard let session = sessions[id]?.value, session.diskSaveError != nil else { return }
        try writeDelayed(session.document, id: id)
    }
    func flushAllDelayedDiskSaves() throws {
        var ids = Set(delayedDiskSaves.keys)
        ids.formUnion(failedDiskSaves.keys)
        for (id, box) in sessions where box.value?.diskSaveError != nil { ids.insert(id) }
        var first: Error?
        for id in ids {
            do { try flushDelayedDiskSave(id) } catch { if first == nil { first = error } }
        }
        if let first { throw first }
    }
    private func writeDelayed(_ document: NoteDocument, id: UUID, notifyLibrary: Bool = true) throws {
        do {
            try persist(document)
            failedDiskSaves.removeValue(forKey: id)
            sessions[id]?.value?.diskSaveError = nil
            sessions[id]?.value?.diskSaveStateDidChange()
            if notifyLibrary { changes.send() }
        } catch {
            failedDiskSaves[id] = (document, error)
            sessions[id]?.value?.diskSaveError = error
            sessions[id]?.value?.diskSaveStateDidChange()
            throw error
        }
    }
    private func session(_ document: NoteDocument) -> NoteSession {
        let value = NoteSession(store: self, document: document); sessions[document.id] = WeakSession(value); return value
    }
    ///
    ///
    /// Profile's Space. Parc keeps one store per Profile: the exact file moves
    /// into the destination store. A live session or an existing destination
    /// file refuses; nothing is copied or rewritten.
    func relocate(_ id: UUID, to destination: NoteStore) throws {
        try flushDelayedDiskSave(id)
        guard destination !== self, sessions[id]?.value == nil, destination.sessions[id]?.value == nil else { throw NoteError.changed }
        _ = try read(id); try destination.checkDirectory()
        let source = path(id), target = destination.path(id)
        guard !FileManager.default.fileExists(atPath: target.path) else { throw NoteError.changed }
        guard Darwin.rename(source.path, target.path) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        documentWriter.forget(source)
        for store in [self, destination] {
            let dir = Darwin.open(store.directory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
            if dir >= 0 { _ = fsync(dir); Darwin.close(dir) }
        }
        sessions.removeValue(forKey: id); destination.sessions.removeValue(forKey: id)
        changes.send(); destination.changes.send()
    }
    /// The inter-Profile transaction already flushed and closed every editor.
    /// Revoke retained callbacks before moving the file; native consent may
    /// still retain the old editor/session until its completion returns.
    func retireSessionForRelocation(_ id: UUID) throws {
        try flushDelayedDiskSave(id)
        guard let current = sessions[id]?.value else { return }
        guard current.document == (try read(id)) else { throw NoteError.changed }
        sessions.removeValue(forKey: id)
        current.closed = true
    }
    fileprivate func scheduleDiskSave(_ document: NoteDocument, notifyLibrary: Bool, session: NoteSession) {
        delayedDiskSaves[document.id]?.work.cancel()
        failedDiskSaves.removeValue(forKey: document.id)
        let identity = document.id, revision = document.revision
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, let pending = self.delayedDiskSaves[identity],
                      pending.document.revision == revision else { return }
                self.delayedDiskSaves[identity] = nil
                let live = self.sessions[identity]?.value
                do {
                    try self.persist(pending.document)
                    self.failedDiskSaves.removeValue(forKey: identity)
                    live?.diskSaveError = nil
                    live?.diskSaveStateDidChange()
                    if pending.notifyLibrary { self.changes.send() }
                } catch {
                    self.failedDiskSaves[identity] = (pending.document, error)
                    live?.diskSaveError = error
                    live?.diskSaveStateDidChange()
                    if pending.notifyLibrary { self.changes.send() }
                }
            }
        }
        delayedDiskSaves[document.id] = DelayedDiskSave(document: document, notifyLibrary: notifyLibrary, work: work)
        session.diskSaveStateDidChange()
        DispatchQueue.main.asyncAfter(deadline: .now() + diskSaveDelay, execute: work)
    }
    fileprivate func timestamp() -> Date { now() }
    private func path(_ id: UUID) -> URL { directory.appendingPathComponent(id.uuidString.lowercased() + ".json") }
    private func checkDirectory() throws {
        let value = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard value.isDirectory == true, value.isSymbolicLink != true else { throw NoteError.invalid }
    }
    private func checkFile(_ url: URL) throws {
        let value = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard value.isRegularFile == true, value.isSymbolicLink != true,
              (value.fileSize ?? Int.max) <= Self.maximumBytes else { throw NoteError.invalid }
    }
    private func read(_ id: UUID) throws -> NoteDocument {
        try checkDirectory(); let url = path(id); try checkFile(url)
        let document = try JSONDecoder().decode(NoteDocument.self, from: Data(contentsOf: url))
        guard document.id == id else { throw NoteError.invalid }; try validate(document); return document
    }
    private func validate(_ document: NoteDocument) throws {
        guard document.version == 1, document.title.utf8.count <= 4096,
              document.body.text.utf8.count <= 1_048_576,
              document.createdAt.timeIntervalSinceReferenceDate.isFinite,
              document.modifiedAt.timeIntervalSinceReferenceDate.isFinite else { throw NoteError.invalid }
        try document.body.richText.validate(text: document.body.text)
    }
    /// In-memory publication validates field limits only. Sorted-keys encode
    /// and size check run once on the note-save queue at disk persist.
    fileprivate func validateForPublication(_ document: NoteDocument) throws {
        try validate(document)
    }
    /// Validates on the caller, then encodes sorted-keys JSON once and
    /// atomically replaces on the note-save queue. Callers that must observe
    /// the file wait for durability before publishing; encode/write leave the
    /// MainActor stack. Identical sorted-keys bytes to the last successful
    /// write for that path skip the atomic replace.
    func persist(_ document: NoteDocument) throws {
        try checkDirectory()
        let destination = path(document.id)
        try validate(document)
        var caught: Error?
        documentWriter.write(document, to: destination, maximumBytes: Self.maximumBytes) { caught = $0 }
        if let caught { throw caught }
    }
}

/// Shared O_EXCL / fsync / rename(2) replace for note JSON documents.
private enum NoteAtomicFile {
    static func write(_ data: Data, to destination: URL, maximumBytes: Int) throws {
        if FileManager.default.fileExists(atPath: destination.path) {
            let values = try destination.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true,
                  (values.fileSize ?? Int.max) <= maximumBytes else { throw NoteError.invalid }
        }
        let temporary = destination.deletingLastPathComponent()
            .appendingPathComponent(".write-" + UUID().uuidString)
        let fd = Darwin.open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { Darwin.close(fd); try? FileManager.default.removeItem(at: temporary) }
        try data.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let count = Darwin.write(fd, buffer.baseAddress!.advanced(by: offset), buffer.count - offset)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
                offset += count
            }
        }
        guard fsync(fd) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        guard Darwin.rename(temporary.path, destination.path) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        syncDirectory(destination.deletingLastPathComponent())
    }

    static func syncDirectory(_ url: URL) {
        let fd = Darwin.open(url.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        if fd >= 0 { _ = fsync(fd); Darwin.close(fd) }
    }
}

/// Off-calling-thread note document encode/replace. Bytes stay sorted-keys
/// JSON with the same `.write-*` / fsync / rename contract readers depend on.
/// Work is FIFO on one serial queue so a later persist cannot leapfrog or drop
/// an earlier durable revision. When encoded bytes equal the last successful
/// write for that path, the atomic replace is skipped (true identical-byte
/// no-op); encode of that identical document may still run off the caller.
private final class NoteDocumentWriter: @unchecked Sendable {
    private let queue = DispatchQueue(label: "org.parc.note-save", qos: .utility)
    /// Last successfully replaced sorted-keys payload per document path.
    /// Touched only on `queue`.
    private var lastWrittenBytes: [String: Data] = [:]

    func write(_ document: NoteDocument, to url: URL, maximumBytes: Int,
               completion: @escaping (Error?) -> Void) {
        // Always `async` onto the save queue. `DispatchQueue.sync` may run the
        // block inline on the calling/MainActor thread; note edits need the
        // sorted-keys encode and atomic replace off that stack even when the
        // caller must still wait for durability before publishing.
        let group = DispatchGroup()
        group.enter()
        queue.async {
            do {
                try self.encodeAndReplace(document, to: url, maximumBytes: maximumBytes)
                completion(nil)
            } catch {
                completion(error)
            }
            group.leave()
        }
        group.wait()
    }

    /// Drop the remembered payload after the on-disk file is moved so a later
    /// create/replace at the same path is not treated as identical.
    func forget(_ url: URL) {
        let group = DispatchGroup()
        group.enter()
        queue.async {
            self.lastWrittenBytes.removeValue(forKey: url.path)
            group.leave()
        }
        group.wait()
    }

    private func encodeAndReplace(_ document: NoteDocument, to url: URL, maximumBytes: Int) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(document)
        guard data.count <= maximumBytes else { throw NoteError.invalid }
        let key = url.path
        if lastWrittenBytes[key] == data {
            // Same sorted-keys JSON already durable; skip fsync/rename.
            return
        }
        try NoteAtomicFile.write(data, to: url, maximumBytes: maximumBytes)
        lastWrittenBytes[key] = data
    }
}
@MainActor
final class NoteSession {
    @Published private(set) var document: NoteDocument
    @Published private(set) var diskSaveGeneration: UInt64 = 0
    fileprivate(set) var diskSaveError: Error?
    private let store: NoteStore
    fileprivate var closed = false
    fileprivate init(store: NoteStore, document: NoteDocument) { self.store = store; self.document = document }
    var hasDelayedDiskSave: Bool { store.hasDelayedDiskSave(document.id) }
    fileprivate func diskSaveStateDidChange() { diskSaveGeneration &+= 1 }
    func flushDelayedDiskSave() throws { try store.flushDelayedDiskSave(document.id) }
    func updateTitle(_ title: String, replacing expected: String) throws {
        guard document.title == expected else { throw NoteError.changed }
        guard title != expected else { return }
        try replace { $0.title = title }
    }
    func updateBody(_ body: NoteBody, replacing expected: NoteBody) throws {
        guard document.body == expected, body.id == expected.id else { throw NoteError.changed }
        guard body != expected else { return }
        try replace { $0.body = body }
    }
    /// A title/body boundary edit is one durable document publication. The
    /// native editors still retain their independent field-local Undo managers.
    func updateTitleAndBody(title: String, body: NoteBody, replacingTitle expectedTitle: String, body expectedBody: NoteBody) throws {
        guard document.title == expectedTitle, document.body == expectedBody,
              body.id == expectedBody.id else { throw NoteError.changed }
        guard title != expectedTitle || body != expectedBody else { return }
        try replace { $0.title = title; $0.body = body }
    }
    fileprivate func replace(persistImmediately: Bool = false, _ edit: (inout NoteDocument) -> Void) throws {
        guard !document.deleted else { throw NoteError.deleted }
        guard !closed else { throw NoteError.changed }
        var next = document; edit(&next)
        guard !closed else { throw NoteError.changed }
        guard next.revision < UInt64.max else { throw NoteError.invalid }
        next.revision += 1; next.modifiedAt = store.timestamp()
        let libraryVisible = next.title != document.title || next.deleted != document.deleted
        if persistImmediately || store.diskSaveDelay <= 0 {
            try store.flushDelayedDiskSave(document.id)
            try store.persist(next)
            diskSaveError = nil
            document = next
            diskSaveStateDidChange()
            store.changes.send()
            return
        }
        try store.validateForPublication(next)
        diskSaveError = nil
        store.scheduleDiskSave(next, notifyLibrary: !libraryVisible, session: self)
        document = next
        if libraryVisible { store.changes.send() }
    }
    var displayTitle: String { document.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled Note" : document.title }
}
