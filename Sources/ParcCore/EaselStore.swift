import Foundation
import Combine
import Darwin

enum EaselItemKind: String, Codable, CaseIterable {
    case text, image, rectangle, circle, arrow, freehand, webCard, browser, link
}

struct EaselPoint: Codable, Equatable {
    var x: Double
    var y: Double
}

struct EaselRect: Codable, Equatable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double
}

struct EaselCaptureLayout: Codable, Equatable {
    var viewport: EaselPoint
    var scroll: EaselPoint
    var region: EaselRect

    var isValid: Bool {
        [viewport.x, viewport.y, scroll.x, scroll.y, region.x, region.y, region.width, region.height]
            .allSatisfy { $0.isFinite && abs($0) <= 1_000_000 }
            && viewport.x >= 1 && viewport.y >= 1 && viewport.x <= 16_384 && viewport.y <= 16_384
            && region.x >= 0 && region.y >= 0 && region.width > 0 && region.height > 0
            && region.x + region.width <= viewport.x + 1 && region.y + region.height <= viewport.y + 1
    }
}

struct EaselTextStyle: Codable, Equatable {
    enum Family: String, Codable, CaseIterable { case mono, fancy, hip, clean }
    enum Size: String, Codable, CaseIterable {
        case body, h2, h1, h0, ultra
        var index: Int { Self.allCases.firstIndex(of: self)! }
        func shifted(by delta: Int) -> Size { Self.allCases[min(4, max(0, index + delta))] }
    }
    enum Fill: String, Codable { case none, contentHugging }
    var fill: Fill?
    var resolvedFill: Fill { fill ?? .none }
    var family: Family = .clean
    var size: Size = .body
    var pointSize: Double {
        switch family {
        case .mono, .clean: return [15, 24, 44, 60, 80][size.index]
        case .fancy: return [16, 28, 48, 60, 80][size.index]
        case .hip: return [18, 21, 44, 60, 80][size.index]
        }
    }
}

struct EaselItem: Codable, Identifiable, Equatable {
    var id = UUID()
    var kind: EaselItemKind
    var frame: EaselRect
    var zIndex: Int = 0
    var movedToFrontAt: Date?
    var text: String = ""
    var textStyle: EaselTextStyle?
    var richText: EaselRichText?
    var resolvedTextStyle: EaselTextStyle { textStyle ?? EaselTextStyle() }
    var url: String?
    var assetID: String?
    var color: String = "#252525"
    var points: [EaselPoint] = []
    var capturedAt: Date?
    var captureLayout: EaselCaptureLayout?
    var liveCapture: Bool?
    var ownsEmbeddedPage: Bool { kind == .browser || (kind == .webCard && captureLayout != nil && liveCapture == true) }
}

struct EaselDocument: Codable, Identifiable, Equatable {
    static let currentVersion = 1
    var version: Int = currentVersion
    var id: UUID
    var title: String
    var createdAt: Date
    var modifiedAt: Date
    var items: [EaselItem] = []
}

struct EaselSummary: Identifiable, Equatable {
    var id: UUID
    var title: String
    var modifiedAt: Date
    var itemCount: Int
}

enum EaselStoreError: Error, LocalizedError {
    case invalidDocument(String), unsupportedVersion(Int), unsafePath, invalidImage, tooLarge
    case missingDocument, deletedDocument, closedDocument, browserInUse

    var errorDescription: String? {
        switch self {
        case .invalidDocument(let reason): return "The Easel is invalid: \(reason)."
        case .unsupportedVersion(let version): return "This Easel uses unsupported format version \(version)."
        case .unsafePath: return "The Easel storage path is unsafe."
        case .invalidImage: return "The image could not be imported."
        case .tooLarge: return "The Easel or image exceeds the local storage limit."
        case .missingDocument: return "The Easel does not exist."
        case .deletedDocument: return "This Easel was deleted."
        case .closedDocument: return "This Easel editor is closed. Reopen the Easel to edit it."
        case .browserInUse: return "Finish closing the embedded webpage before changing this Easel."
        }
    }
}

@MainActor
final class EaselStore {
    static let maximumAssetBytes = 30 * 1024 * 1024
    static let maximumDocumentBytes = 8 * 1024 * 1024
    let directory: URL
    private let now: () -> Date
    private var sessions: [UUID: WeakSession] = [:]
    var documentsDirectory: URL { directory.appendingPathComponent("documents", isDirectory: true) }
    private var assetsDirectory: URL { directory.appendingPathComponent("assets", isDirectory: true) }
    private let documentWriter = EaselDocumentWriter()

    init(directory: URL, now: @escaping () -> Date = Date.init) throws {
        self.directory = directory.standardizedFileURL
        self.now = now
        guard self.directory.isFileURL else { throw EaselStoreError.unsafePath }
        try FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
        try ensureDirectory(self.directory)
        for child in [documentsDirectory, assetsDirectory] {
            if !FileManager.default.fileExists(atPath: child.path) {
                try FileManager.default.createDirectory(at: child, withIntermediateDirectories: false)
            }
            try ensureDirectory(child)
        }
    }

    func list() throws -> [EaselSummary] {
        try checkDirectories()
        return try FileManager.default.contentsOfDirectory(at: documentsDirectory,
                    includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
            .filter { $0.pathExtension == "json" }
            .compactMap { url in
                guard let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent),
                      let document = try? read(id) else { return nil }
                return EaselSummary(id: id, title: document.title,
                                    modifiedAt: document.modifiedAt, itemCount: document.items.count)
            }
            .sorted { $0.modifiedAt == $1.modifiedAt ? $0.id.uuidString < $1.id.uuidString : $0.modifiedAt > $1.modifiedAt }
    }

    func create(title: String = "Untitled Easel") throws -> EaselSession {
        let date = now()
        let document = EaselDocument(id: UUID(), title: title, createdAt: date, modifiedAt: date)
        try persist(document)
        return session(document)
    }

    func load(_ id: UUID) throws -> EaselSession {
        if let session = sessions[id]?.value { return session }
        return session(try read(id))
    }

    func validateReference(_ id: UUID) throws {
        let saved = try read(id)
        if let live = sessions[id]?.value, live.document != saved {
            throw EaselStoreError.invalidDocument("the shared document changed outside its session")
        }
    }
    func delete(_ id: UUID) throws {
        try checkDirectories()
        let url = documentURL(id)
        try ensureRegularFile(url)
        try sessions[id]?.value?.validateReplacement(nil)
        try FileManager.default.removeItem(at: url)
        documentWriter.forget(url)
        syncDirectory(documentsDirectory)
        sessions.removeValue(forKey: id)?.value?.markDeleted()
    }

    fileprivate func timestamp() -> Date { now() }

    fileprivate func persist(_ document: EaselDocument, wait: Bool = true) throws {
        try checkDirectories()
        try validate(document)
        let url = documentURL(document.id)
        let maximumBytes = Self.maximumDocumentBytes
        if wait {
            var caught: Error?
            documentWriter.write(document, to: url, maximumBytes: maximumBytes, wait: true) { caught = $0 }
            if let caught { throw caught }
            return
        }
        documentWriter.write(document, to: url, maximumBytes: maximumBytes, wait: false) { _ in }
    }

    fileprivate func importPNG(_ data: Data) throws -> String {
        guard data.count <= Self.maximumAssetBytes else { throw EaselStoreError.tooLarge }
        guard data.count >= 24, data.starts(with: [137, 80, 78, 71, 13, 10, 26, 10]),
              Array(data[12..<16]) == Array("IHDR".utf8) else { throw EaselStoreError.invalidImage }
        try checkDirectories()
        let id = UUID().uuidString.lowercased() + ".png"
        try atomicWrite(data, to: assetsDirectory.appendingPathComponent(id))
        return id
    }

    fileprivate func assetURL(_ id: String) throws -> URL {
        guard id == id.lowercased(), id.hasSuffix(".png"),
              UUID(uuidString: String(id.dropLast(4))) != nil,
              id.count == 40 else { throw EaselStoreError.unsafePath }
        try checkDirectories()
        let url = assetsDirectory.appendingPathComponent(id)
        try ensureRegularFile(url, maximumBytes: Self.maximumAssetBytes)
        return url
    }

    func relocate(_ id: UUID, to destination: EaselStore) throws -> [String] {
        guard destination !== self, sessions[id]?.value == nil, destination.sessions[id]?.value == nil else {
            throw EaselStoreError.invalidDocument("the document is open")
        }
        let document = try read(id)
        try destination.checkDirectories()
        let target = destination.documentURL(id)
        guard !FileManager.default.fileExists(atPath: target.path) else {
            throw EaselStoreError.invalidDocument("the destination already has this document")
        }
        var copied: [String] = []
        do {
            for asset in Set(document.items.compactMap(\.assetID)).sorted() {
                let url = destination.assetsDirectory.appendingPathComponent(asset)
                let original = try Data(contentsOf: assetURL(asset))
                if FileManager.default.fileExists(atPath: url.path) {
                    guard try Data(contentsOf: destination.assetURL(asset)) == original else {
                        throw EaselStoreError.invalidDocument("a destination asset has different contents")
                    }
                    continue
                }
                try destination.atomicWrite(original, to: url)
                copied.append(asset)
            }
            guard Darwin.rename(documentURL(id).path, target.path) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
            documentWriter.forget(documentURL(id))
        } catch {
            destination.removeAssets(copied)
            throw error
        }
        syncDirectory(documentsDirectory); destination.syncDirectory(destination.documentsDirectory)
        sessions.removeValue(forKey: id); destination.sessions.removeValue(forKey: id)
        return copied
    }

    func retireSessionForRelocation(_ id: UUID) throws {
        guard let current = sessions[id]?.value else { return }
        try current.validateReplacement(nil)
        guard current.document == (try read(id)) else {
            throw EaselStoreError.invalidDocument("the shared document changed outside its session")
        }
        sessions.removeValue(forKey: id)
        current.markClosed()
    }

    func removeAssets(_ ids: [String]) {
        for asset in ids { try? FileManager.default.removeItem(at: assetsDirectory.appendingPathComponent(asset)) }
        if !ids.isEmpty { syncDirectory(assetsDirectory) }
    }

    private func session(_ document: EaselDocument) -> EaselSession {
        let value = EaselSession(store: self, document: document)
        sessions[document.id] = WeakSession(value)
        return value
    }

    private func read(_ id: UUID) throws -> EaselDocument {
        try checkDirectories()
        let url = documentURL(id)
        guard FileManager.default.fileExists(atPath: url.path) else { throw EaselStoreError.missingDocument }
        try ensureRegularFile(url, maximumBytes: Self.maximumDocumentBytes)
        let document = Self.repairingDuplicateIDs(try JSONDecoder().decode(EaselDocument.self, from: Data(contentsOf: url)))
        guard document.id == id else { throw EaselStoreError.invalidDocument("document ID does not match its file") }
        try validate(document)
        return document
    }

    static func repairingDuplicateIDs(_ document: EaselDocument) -> EaselDocument {
        let taken = Set(document.items.map(\.id))
        guard taken.count != document.items.count else { return document }
        var next = document, seen = Set<UUID>()
        for index in next.items.indices {
            let base = next.items[index].id
            var id = base, salt: UInt32 = 0
            while seen.contains(id) || (id != base && taken.contains(id)) {
                salt &+= 1
                var raw = base.uuid
                withUnsafeMutableBytes(of: &raw) { bytes in
                    withUnsafeBytes(of: salt.bigEndian) { for (offset, byte) in $0.enumerated() { bytes[12 + offset] ^= byte } }
                }
                id = UUID(uuid: raw)
            }
            seen.insert(id)
            next.items[index].id = id
        }
        return next
    }

    private func validate(_ document: EaselDocument) throws {
        try Self.validate(document) { _ = try self.assetURL($0) }
    }

    fileprivate static func validate(_ document: EaselDocument, asset: (String) throws -> Void) throws {
        guard document.version == EaselDocument.currentVersion else { throw EaselStoreError.unsupportedVersion(document.version) }
        guard document.title.utf8.count <= 4096,
              !document.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              document.createdAt.timeIntervalSinceReferenceDate.isFinite,
              document.modifiedAt.timeIntervalSinceReferenceDate.isFinite,
              document.items.count <= 10_000 else { throw EaselStoreError.invalidDocument("document metadata") }
        guard Set(document.items.map(\.id)).count == document.items.count else { throw EaselStoreError.invalidDocument("duplicate object ID") }
        for item in document.items {
            let r = item.frame
            guard [r.x, r.y, r.width, r.height].allSatisfy({ $0.isFinite && abs($0) <= 1_000_000 }),
                  r.width >= 1, r.height >= 1,
                  item.points.count <= 100_000,
                  item.points.allSatisfy({ $0.x.isFinite && $0.y.isFinite && abs($0.x) <= 1_000_000 && abs($0.y) <= 1_000_000 }),
                  item.text.utf8.count <= 1_048_576,
                  item.color.range(of: "^#[0-9A-Fa-f]{6}$", options: .regularExpression) != nil,
                  item.movedToFrontAt?.timeIntervalSinceReferenceDate.isFinite != false,
                  item.capturedAt?.timeIntervalSinceReferenceDate.isFinite != false else {
                throw EaselStoreError.invalidDocument("object geometry or appearance")
            }
            if let richText = item.richText {
                guard item.kind == .text else { throw EaselStoreError.invalidDocument("rich text on a non-text object") }
                try richText.validate(text: item.text)
            }
            if let id = item.assetID { try asset(id) }
            if let layout = item.captureLayout {
                guard item.kind == .webCard, item.assetID != nil, layout.isValid else {
                    throw EaselStoreError.invalidDocument("captured webpage geometry")
                }
            }
            if item.liveCapture == true && (item.kind != .webCard || item.captureLayout == nil) {
                throw EaselStoreError.invalidDocument("live capture has no original geometry")
            }
            if let rawURL = item.url {
                guard rawURL.utf8.count <= 16_384, let url = URL(string: rawURL),
                      ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
                      let host = url.host, !host.isEmpty else { throw EaselStoreError.invalidDocument("card URL") }
            }
            if item.kind == .image && item.assetID == nil { throw EaselStoreError.invalidDocument("image has no asset") }
            if [.link, .webCard, .browser].contains(item.kind) && item.url == nil { throw EaselStoreError.invalidDocument("card has no URL") }
            if [.arrow, .freehand].contains(item.kind) && item.points.count < 2 { throw EaselStoreError.invalidDocument("drawing has fewer than two points") }
        }
    }

    private func documentURL(_ id: UUID) -> URL {
        documentsDirectory.appendingPathComponent(id.uuidString.lowercased() + ".json")
    }

    private func checkDirectories() throws {
        try ensureDirectory(directory)
        try ensureDirectory(documentsDirectory)
        try ensureDirectory(assetsDirectory)
    }

    private func ensureDirectory(_ url: URL) throws {
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else { throw EaselStoreError.unsafePath }
    }

    private func ensureRegularFile(_ url: URL, maximumBytes: Int? = nil) throws {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else { throw EaselStoreError.unsafePath }
        if let maximumBytes, (values.fileSize ?? Int.max) > maximumBytes { throw EaselStoreError.tooLarge }
    }

    private func atomicWrite(_ data: Data, to destination: URL) throws {
        try EaselAtomicFile.write(data, to: destination)
    }

    private func syncDirectory(_ url: URL) {
        EaselAtomicFile.syncDirectory(url)
    }

    private final class WeakSession {
        weak var value: EaselSession?
        init(_ value: EaselSession) { self.value = value }
    }
}

private enum EaselAtomicFile {
    static func write(_ data: Data, to destination: URL) throws {
        if FileManager.default.fileExists(atPath: destination.path) {
            let values = try destination.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true else {
                throw EaselStoreError.unsafePath
            }
        }
        let temporary = destination.deletingLastPathComponent()
            .appendingPathComponent(".write-" + UUID().uuidString)
        let fd = Darwin.open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { Darwin.close(fd); try? FileManager.default.removeItem(at: temporary) }
        try data.withUnsafeBytes { buffer in
            var written = 0
            while written < buffer.count {
                let count = Darwin.write(fd, buffer.baseAddress!.advanced(by: written), buffer.count - written)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
                written += count
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

private final class EaselDocumentWriter: @unchecked Sendable {
    private let queue = DispatchQueue(label: "org.parc.easel-save", qos: .utility)
    private var lastWrittenBytes: [String: Data] = [:]

    func write(_ document: EaselDocument, to url: URL, maximumBytes: Int, wait: Bool,
               completion: @escaping (Error?) -> Void) {
        let work = {
            do {
                try self.encodeAndReplace(document, to: url, maximumBytes: maximumBytes)
                completion(nil)
            } catch {
                completion(error)
            }
        }
        if wait {
            let group = DispatchGroup()
            group.enter()
            queue.async {
                work()
                group.leave()
            }
            group.wait()
        } else {
            queue.async(execute: work)
        }
    }

    func forget(_ url: URL) {
        let group = DispatchGroup()
        group.enter()
        queue.async {
            self.lastWrittenBytes.removeValue(forKey: url.path)
            group.leave()
        }
        group.wait()
    }

    private func encodeAndReplace(_ document: EaselDocument, to url: URL, maximumBytes: Int) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(document)
        guard data.count <= maximumBytes else { throw EaselStoreError.tooLarge }
        let key = url.path
        if lastWrittenBytes[key] == data {
            return
        }
        try EaselAtomicFile.write(data, to: url)
        lastWrittenBytes[key] = data
    }
}

@MainActor
final class EaselSession: ObservableObject {
    @Published private(set) var document: EaselDocument
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false
    private let store: EaselStore?
    private var memoryAssets: [String: Data] = [:]
    private static let maximumMemoryAssetBytes = 256 * 1024 * 1024
    private var undoStack: [EaselDocument] = []
    private var redoStack: [EaselDocument] = []
    private var deleted = false
    private var closed = false
    var isClosed: Bool { closed }
    var isDeleted: Bool { deleted }
    private var lastUndoGroup: UUID?
    private var replacementGuards: [UUID: (EaselDocument?) -> Bool] = [:]
    var undoDestination: EaselDocument? { undoStack.last }
    var redoDestination: EaselDocument? { redoStack.last }
    func observeReplacement(_ guardChange: @escaping (EaselDocument?) -> Bool) -> UUID {
        let token = UUID(); replacementGuards[token] = guardChange; return token
    }
    func removeReplacementObserver(_ token: UUID) { replacementGuards.removeValue(forKey: token) }
    fileprivate func validateReplacement(_ next: EaselDocument?) throws {
        guard replacementGuards.values.allSatisfy({ $0(next) }) else { throw EaselStoreError.browserInUse }
    }

    fileprivate init(store: EaselStore, document: EaselDocument) {
        self.store = store
        self.document = document
    }

    init(inMemory document: EaselDocument, assets: [String: Data]) throws {
        store = nil; self.document = document; memoryAssets = assets
        try persist(document)
    }

    var inMemoryAssets: [String: Data] { memoryAssets }
    private func persist(_ document: EaselDocument) throws {
        try requireWritable()
        if let store { try store.persist(document); return }
        guard memoryAssets.values.reduce(0, { $0 + $1.count }) <= Self.maximumMemoryAssetBytes else { throw EaselStoreError.tooLarge }
        try EaselStore.validate(document) { id in
            guard self.memoryAssets[id] != nil else { throw EaselStoreError.invalidImage }
        }
        guard try JSONEncoder().encode(document).count <= EaselStore.maximumDocumentBytes else { throw EaselStoreError.tooLarge }
    }

    func assetData(_ id: String) throws -> Data {
        if let store { return try Data(contentsOf: store.assetURL(id)) }
        guard let data = memoryAssets[id] else { throw EaselStoreError.invalidImage }
        return data
    }

    func perform(_ name: String, coalescing group: UUID? = nil, _ mutation: (inout EaselDocument) throws -> Void) throws {
        try requireWritable()
        var next = document
        try mutation(&next)
        guard next.id == document.id, next.createdAt == document.createdAt else {
            throw EaselStoreError.invalidDocument("immutable document identity")
        }
        guard next != document else { return }
        next.modifiedAt = (store?.timestamp() ?? Date())
        try validateReplacement(next)
        try persist(next)
        if group == nil || lastUndoGroup != group { undoStack.append(document) }
        lastUndoGroup = group
        trimUndo()
        redoStack.removeAll()
        document = next
        updateHistoryState()
    }

    private var recordingBrowserURL: (id: UUID, from: String, to: String)?
    func isRecordingBrowserNavigation(_ id: UUID, from: String, to: String) -> Bool {
        guard let change = recordingBrowserURL else { return false }
        return change.id == id && change.from == from && change.to == to
    }
    @discardableResult
    func recordBrowserNavigation(_ url: URL, itemID: UUID, expectedURL: String) throws -> Bool {
        try requireWritable()
        guard recordingBrowserURL == nil, ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              let host = url.host, !host.isEmpty, url.user == nil, url.password == nil,
              let index = document.items.firstIndex(where: { $0.id == itemID && $0.kind == .browser && $0.url == expectedURL }) else { return false }
        let value = url.absoluteString
        guard value != expectedURL else { return true }
        var next = document; next.items[index].url = value; next.modifiedAt = (store?.timestamp() ?? Date())
        recordingBrowserURL = (itemID, expectedURL, value)
        defer { recordingBrowserURL = nil }
        try validateReplacement(next)
        try persist(next)
        func refresh(_ snapshot: inout EaselDocument) {
            if let i = snapshot.items.firstIndex(where: { $0.id == itemID && $0.kind == .browser && $0.url == expectedURL }) {
                snapshot.items[i].url = value
            }
        }
        for i in undoStack.indices { refresh(&undoStack[i]) }
        for i in redoStack.indices { refresh(&redoStack[i]) }
        document = next
        return true
    }

    func undo() throws {
        lastUndoGroup = nil
        try requireWritable()
        guard var previous = undoStack.last else { return }
        previous.modifiedAt = (store?.timestamp() ?? Date())
        try validateReplacement(previous)
        try persist(previous)
        undoStack.removeLast()
        redoStack.append(document)
        document = previous
        updateHistoryState()
    }

    func redo() throws {
        lastUndoGroup = nil
        try requireWritable()
        guard var next = redoStack.last else { return }
        next.modifiedAt = (store?.timestamp() ?? Date())
        try validateReplacement(next)
        try persist(next)
        redoStack.removeLast()
        undoStack.append(document)
        trimUndo()
        document = next
        updateHistoryState()
    }

    func save() throws {
        try requireWritable()
        try persist(document)
    }

    func importPNG(_ data: Data) throws -> String {
        try requireWritable()
        if let store { return try store.importPNG(data) }
        guard data.count <= EaselStore.maximumAssetBytes,
              data.count >= 24, data.starts(with: [137, 80, 78, 71, 13, 10, 26, 10]),
              Array(data[12..<16]) == Array("IHDR".utf8) else { throw EaselStoreError.invalidImage }
        guard memoryAssets.values.reduce(data.count, { $0 + $1.count }) <= Self.maximumMemoryAssetBytes else { throw EaselStoreError.tooLarge }
        let id = UUID().uuidString.lowercased() + ".png"; memoryAssets[id] = data
        return id
    }

    func assetURL(_ assetID: String) throws -> URL {
        guard let store else { throw EaselStoreError.unsafePath }
        return try store.assetURL(assetID)
    }

    private func requireWritable() throws {
        guard !deleted else { throw EaselStoreError.deletedDocument }
        guard !closed else { throw EaselStoreError.closedDocument }
    }

    fileprivate func markClosed() {
        closed = true
        undoStack.removeAll(); redoStack.removeAll(); lastUndoGroup = nil
        updateHistoryState()
    }

    fileprivate func markDeleted() {
        deleted = true
        undoStack.removeAll()
        redoStack.removeAll()
        updateHistoryState()
    }

    private func trimUndo() {
        while undoStack.count > 50 { undoStack.removeFirst() }
        var retainedBytes = 0
        for index in undoStack.indices.reversed() {
            retainedBytes += (try? JSONEncoder().encode(undoStack[index]).count) ?? EaselStore.maximumDocumentBytes
            if retainedBytes > 32 * 1024 * 1024 {
                undoStack.removeFirst(index + 1)
                break
            }
        }
    }

    private func updateHistoryState() {
        canUndo = !undoStack.isEmpty
        canRedo = !redoStack.isEmpty
    }
}
