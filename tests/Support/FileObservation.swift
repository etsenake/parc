import Foundation
import ObjectiveC

// Test-process observers for persistence work: file-manager calls and reads of
// ObjC-backed document text, each with the thread that made it. Exchanges
// NSFileManager implementations inside the test executable only.

/// One NSFileManager call on a path under the watched directory.
struct FileOperation {
    let name: String
    let path: String
    let onMainThread: Bool
    /// `ProcessInfo.systemUptime` when the call was made.
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
                preconditionFailure("missing \(original) on NSFileManager")
            }
            method_exchangeImplementations(originalMethod, replacementMethod)
        }
    }
    /// Calls on paths under `directory` made from any thread while `body` runs.
    static func during(_ directory: URL, _ body: () throws -> Void) rethrows -> [FileOperation] {
        precondition(installed, "FileOperations.install() first")
        let paths = [directory.standardizedFileURL.path, directory.resolvingSymlinksInPath().path]
        lock.lock(); watched = paths; log = []; lock.unlock()
        defer { lock.lock(); watched = []; lock.unlock() }
        try body()
        lock.lock(); defer { lock.unlock() }
        return log
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

/// An immutable ObjC-backed string, like the text AppKit controls hand to the
/// stores, that records each read with the thread making it. Swift keeps such a
/// string bridged rather than copied, so encoding a document that holds one
/// reads it through NSString on the encoding thread: one `getCharacters` call
/// per JSON encode, where equality comparisons use `characterAt` only.
final class ObservedString: NSString {
    struct Read {
        let name: String
        let onMainThread: Bool
    }
    private static let lock = NSLock()
    nonisolated(unsafe) private static var log: [Read]?
    private var storage: NSString = ""
    /// The bridged Swift string a store receives.
    static func text(_ value: String) -> String {
        let string = ObservedString()
        string.storage = value as NSString
        return string as String
    }
    /// Reads of every observed string from any thread while `body` runs.
    static func reads(during body: () throws -> Void) rethrows -> [Read] {
        lock.lock(); log = []; lock.unlock()
        defer { lock.lock(); log = nil; lock.unlock() }
        try body()
        lock.lock(); defer { lock.unlock() }
        return log ?? []
    }
    /// JSON encodes of observed text made off the main thread.
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
