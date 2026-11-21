import Foundation
import ObjectiveC

struct FileOperation {
    let name: String
    let path: String
    let onMainThread: Bool
    let time: TimeInterval
    var fileName: String { (path as NSString).lastPathComponent }
}

enum EaselFileOperations {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var installed = false
    nonisolated(unsafe) private static var watched: [String] = []
    nonisolated(unsafe) private static var log: [FileOperation] = []
    static func install() {
        guard !installed else { return }
        installed = true
        for (original, replacement) in [
            (#selector(FileManager.fileExists(atPath:)), #selector(FileManager.easelObserved_fileExists(atPath:))),
            (#selector(FileManager.createFile(atPath:contents:attributes:)),
             #selector(FileManager.easelObserved_createFile(atPath:contents:attributes:))),
            (#selector(FileManager.removeItem(at:)), #selector(FileManager.easelObserved_removeItem(at:))),
        ] {
            guard let originalMethod = class_getInstanceMethod(FileManager.self, original),
                  let replacementMethod = class_getInstanceMethod(FileManager.self, replacement) else {
                return
            }
            method_exchangeImplementations(originalMethod, replacementMethod)
        }
    }
    static func during(_ directory: URL, _ body: () throws -> Void) rethrows -> [FileOperation] {
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
    @objc dynamic func easelObserved_fileExists(atPath path: String) -> Bool {
        EaselFileOperations.note("fileExists", path)
        return easelObserved_fileExists(atPath: path)
    }
    @objc dynamic func easelObserved_createFile(atPath path: String, contents: Data?,
                                           attributes: [FileAttributeKey: Any]?) -> Bool {
        EaselFileOperations.note("createFile", path)
        return easelObserved_createFile(atPath: path, contents: contents, attributes: attributes)
    }
    @objc dynamic func easelObserved_removeItem(at url: URL) throws {
        EaselFileOperations.note("removeItem", url.path)
        try easelObserved_removeItem(at: url)
    }
}

final class EaselObservedString: NSString {
    struct Read {
        let name: String
        let onMainThread: Bool
    }
    private static let lock = NSLock()
    nonisolated(unsafe) private static var log: [Read]?
    private var storage: NSString = ""
    static func text(_ value: String) -> String {
        let string = EaselObservedString()
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
