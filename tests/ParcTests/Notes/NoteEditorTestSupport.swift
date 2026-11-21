import Foundation
import Testing
@testable import Parc
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

@MainActor
enum NoteEditorFixtures {
    static func useMathFont() {
        let url = Bundle.module.url(forResource: "STIXTwoMath-Regular", withExtension: "otf", subdirectory: "Fixtures")!
        NoteMathRenderer.useFont(at: url)
    }
}

enum NoteEditorBlocks {
    static func marks(_ configure: (inout NoteMarks) -> Void) -> NoteMarks {
        var value = NoteMarks.plain
        configure(&value)
        return value
    }

    static var bold: NoteMarks { marks { $0.bold = true } }
    static var italic: NoteMarks { marks { $0.italic = true } }

    static func block(_ kind: NoteBlockKind, _ text: String = "", _ children: [NoteBlock] = [],
                      _ configure: (inout NoteBlockProps) -> Void = { _ in }) -> NoteBlock {
        var props = NoteBlockProps()
        configure(&props)
        return NoteBlock(kind, text: NoteText(text), props: props, children: children)
    }

    static func para(_ text: String = "") -> NoteBlock { block(.paragraph, text) }
    static func bullet(_ text: String = "", _ children: [NoteBlock] = []) -> NoteBlock { block(.bulletedItem, text, children) }
    static func numbered(_ text: String = "", start: Int? = nil, _ children: [NoteBlock] = []) -> NoteBlock {
        block(.numberedItem, text, children) { $0.listStart = start }
    }
    static func todo(_ text: String = "", checked: Bool = false, _ children: [NoteBlock] = []) -> NoteBlock {
        block(.todo, text, children) { $0.checked = checked }
    }
}
