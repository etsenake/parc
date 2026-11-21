import Foundation
import Testing
@testable import ParcCore

@Suite(.serialized)
enum NoteEditorProcessWide {}

@MainActor
final class NoteEditorManualClock: NoteFileClock {
    private struct Pending {
        let id: Int
        let due: Date
        let action: @MainActor () -> Void
    }

    var now = Date(timeIntervalSince1970: 1_800_000_000)
    private var pending: [Pending] = []
    private var counter = 0

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

final class NoteEditorTemporaryFolder {
    let url: URL

    init(_ label: String) throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("parc-\(label)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(at: url) }

    @discardableResult
    func write(_ text: String, to name: String) throws -> URL {
        let file = url.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: file)
        return file
    }
}
