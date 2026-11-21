import Foundation
import ObjectiveC
import Testing

@Suite(.serialized) enum FileObservationSuites {}

struct FileOperation {
    let name: String
    let path: String
    let onMainThread: Bool
    let time: TimeInterval
    var fileName: String { (path as NSString).lastPathComponent }
}

enum FileOperations {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var installed = false
    nonisolated(unsafe) private static var watched: [String] = []
    nonisolated(unsafe) private static var log: [FileOperation] = []
    static func install() {
        guard !installed else { return }
        installed = true
        for (original, replacement) in [
            (#selector(FileManager.fileExists(atPath:)), #selector(FileManager.observed_fileExists(atPath:))),
            (#selector(FileManager.createFile(atPath:contents:attributes:)),
             #selector(FileManager.observed_createFile(atPath:contents:attributes:))),
            (#selector(FileManager.removeItem(at:)), #selector(FileManager.observed_removeItem(at:))),
        ] {
            guard let originalMethod = class_getInstanceMethod(FileManager.self, original),
                  let replacementMethod = class_getInstanceMethod(FileManager.self, replacement) else {
                Issue.record("missing \(original) on NSFileManager")
                return
            }
            method_exchangeImplementations(originalMethod, replacementMethod)
        }
    }
    static func during(_ directory: URL, _ body: () throws -> Void) rethrows -> [FileOperation] {
        if !installed { Issue.record("FileOperations.install() first") }
        let paths = [directory.standardizedFileURL.path, directory.resolvingSymlinksInPath().path]
        lock.lock(); watched = paths; log = []; lock.unlock()
        defer { lock.lock(); watched = []; lock.unlock() }
        try body()
        lock.lock(); defer { lock.unlock() }
        return log
    }
    private static func begin(_ directory: URL) {
        let paths = [directory.standardizedFileURL.path, directory.resolvingSymlinksInPath().path]
        lock.lock(); watched = paths; log = []; lock.unlock()
    }
    private static func finish() -> [FileOperation] {
        lock.lock(); defer { lock.unlock() }
        watched = []
        return log
    }
    static func during(_ directory: URL, _ body: () async throws -> Void) async rethrows -> [FileOperation] {
        if !installed { Issue.record("FileOperations.install() first") }
        begin(directory)
        do { try await body() } catch { _ = finish(); throw error }
        return finish()
    }
    fileprivate static func note(_ name: String, _ path: String) {
        let operation = FileOperation(name: name, path: path, onMainThread: Thread.isMainThread,
                                      time: ProcessInfo.processInfo.systemUptime)
        lock.lock(); defer { lock.unlock() }
        guard watched.contains(where: { path.hasPrefix($0 + "/") }) else { return }
        log.append(operation)
    }
}

extension FileManager {
    @objc dynamic func observed_fileExists(atPath path: String) -> Bool {
        FileOperations.note("fileExists", path)
        return observed_fileExists(atPath: path)
    }
    @objc dynamic func observed_createFile(atPath path: String, contents: Data?,
                                           attributes: [FileAttributeKey: Any]?) -> Bool {
        FileOperations.note("createFile", path)
        return observed_createFile(atPath: path, contents: contents, attributes: attributes)
    }
    @objc dynamic func observed_removeItem(at url: URL) throws {
        FileOperations.note("removeItem", url.path)
        try observed_removeItem(at: url)
    }
}

final class ObservedString: NSString {
    struct Read {
        let name: String
        let onMainThread: Bool
    }
    private static let lock = NSLock()
    nonisolated(unsafe) private static var log: [Read]?
    private var storage: NSString = ""
    static func text(_ value: String) -> String {
        let string = ObservedString()
        string.storage = value as NSString
        return string as String
    }
    static func reads(during body: () throws -> Void) rethrows -> [Read] {
        lock.lock(); log = []; lock.unlock()
        defer { lock.lock(); log = nil; lock.unlock() }
        try body()
        lock.lock(); defer { lock.unlock() }
        return log ?? []
    }
    static func backgroundEncodes(_ reads: [Read]) -> Int {
        reads.filter { $0.name == "getCharacters" && !$0.onMainThread }.count
    }
    private func note(_ name: String) {
        let read = Read(name: name, onMainThread: Thread.isMainThread)
        Self.lock.lock(); Self.log?.append(read); Self.lock.unlock()
    }
    override var length: Int { note("length"); return storage.length }
    override func character(at index: Int) -> unichar { note("characterAt"); return storage.character(at: index) }
    override func getCharacters(_ buffer: UnsafeMutablePointer<unichar>, range: NSRange) {
        note("getCharacters"); storage.getCharacters(buffer, range: range)
    }
    override func copy(with zone: NSZone? = nil) -> Any { self }
}
