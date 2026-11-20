import Foundation

@MainActor
final class ManualNoteClock: NoteFileClock {
    private struct Pending {
        let id: Int
        let due: Date
        let action: @MainActor () -> Void
    }

    var now = Date(timeIntervalSince1970: 1_800_000_000)
    private var pending: [Pending] = []
    private var counter = 0

    var hasPending: Bool { !pending.isEmpty }

    func schedule(after delay: TimeInterval, _ action: @escaping @MainActor () -> Void) -> NoteFileTimer {
        counter += 1
        let id = counter
        pending.append(Pending(id: id, due: now.addingTimeInterval(max(0, delay)), action: action))
        return NoteFileTimer { [weak self] in self?.pending.removeAll { $0.id == id } }
    }

    func advance(_ seconds: TimeInterval) {
        let end = now.addingTimeInterval(seconds)
        while let next = pending.filter({ $0.due <= end }).min(by: { $0.due < $1.due || ($0.due == $1.due && $0.id < $1.id) }) {
            pending.removeAll { $0.id == next.id }
            now = max(now, next.due)
            next.action()
        }
        now = end
    }
}

func expect(_ value: @autoclosure () -> Bool, _ message: String, file: StaticString = #file, line: UInt = #line) {
    if !value() { failTest(message, file: file, line: line) }
}

func expectEqual<Value: Equatable>(_ actual: Value, _ expected: Value, _ message: String,
                                   file: StaticString = #file, line: UInt = #line) {
    if actual != expected { failTest("\(message): got \(String(reflecting: actual)), expected \(String(reflecting: expected))", file: file, line: line) }
}

func expectThrows<Failure: Error & Equatable>(_ expected: Failure, _ message: String, file: StaticString = #file, line: UInt = #line,
                                              _ body: () throws -> Void) {
    do {
        try body()
        failTest("\(message): nothing was thrown", file: file, line: line)
    } catch let error as Failure {
        if error != expected { failTest("\(message): threw \(error), expected \(expected)", file: file, line: line) }
    } catch {
        failTest("\(message): threw \(error), expected \(expected)", file: file, line: line)
    }
}

final class LockedBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value?

    var value: Value? { lock.withLock { stored } }

    func set(_ value: Value?) { lock.withLock { stored = value } }
}

enum NoteFileTestSupport {
    static func isPresented(_ url: URL) -> Bool {
        NSFileCoordinator.filePresenters.contains { presenter in
            presenter.presentedItemURL.map { NoteFilePaths.sameItem($0, url) } ?? false
        }
    }

    static func makeFolder(_ label: String) -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("parc-\(label)-\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return NoteFilePaths.canonical(folder)
    }

    static func remove(_ folder: URL) {
        try? FileManager.default.removeItem(at: folder)
    }

    @discardableResult
    static func write(_ text: String, to url: URL) -> URL {
        write(Data(text.utf8), to: url)
    }

    @discardableResult
    static func write(_ data: Data, to url: URL) -> URL {
        try! FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try! data.write(to: url)
        return url
    }

    static func read(_ url: URL) -> String {
        String(decoding: (try? Data(contentsOf: url)) ?? Data(), as: UTF8.self)
    }

    static func bytes(_ url: URL) -> [UInt8] {
        [UInt8]((try? Data(contentsOf: url)) ?? Data())
    }

    static func setModified(_ url: URL, _ date: Date) {
        try! FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
    }

    static func modified(_ url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }

    static func inode(_ url: URL) -> UInt64 {
        var info = stat()
        return stat(url.path, &info) == 0 ? UInt64(info.st_ino) : 0
    }

    @MainActor
    static func spin(timeout: TimeInterval, until condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline { return false }
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        return true
    }
}
