import AppKit
import Foundation
import Testing
@testable import Parc
@testable import ParcCore
@testable import ParcNotes
@testable import ParcEasels

struct NoteEditorRealTrashRefused: Error {}

@MainActor
enum NoteEditorFiles {
    static func make(clock: NoteFileClock, worker: NoteFileWorker = .inline) -> NoteFiles {
        IsolatedNoteFiles.make(clock: clock, worker: worker)
    }
}

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
    static let fontNames = ["Nunito-ExtraBold", "Nunito-Regular", "Nunito-Bold", "Nunito-Italic", "Nunito-BoldItalic",
                            "EBGaramond-VariableFont_wght", "SpaceMono-Regular", "SpaceMono-Bold"]

    static func makeController(file: NoteFileSession) -> NotePageViewController {
        NoteBlockViewFactory.boards = NoteEaselProvider()
        return NotePageViewController(file: file)
    }

    static func registerFonts() {
        for name in fontNames {
            let subdirectory = name == "EBGaramond-VariableFont_wght" ? nil : "Fixtures"
            if let url = Bundle.module.url(forResource: name, withExtension: "ttf", subdirectory: subdirectory) {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }
    }

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

    static func tag(_ block: NoteBlock) -> String {
        switch block.kind {
        case .paragraph: return "p"
        case .heading: return (block.props.toggleable ? "th" : "h") + String(block.props.level) + (block.isCollapsed ? "-" : "")
        case .bulletedItem: return "ul"
        case .numberedItem: return "ol" + (block.props.listStart.map { "@\($0)" } ?? "")
        case .todo: return block.props.checked ? "done" : "todo"
        case .toggle: return block.props.expanded ? "toggle" : "toggle-"
        case .equation: return "eq"
        default: return block.kind.rawValue
        }
    }

    static func outline(_ blocks: [NoteBlock], depth: Int = 0) -> String {
        blocks.map { block -> String in
            var line = String(repeating: "  ", count: depth) + tag(block)
            let text = block.kind.hasText ? block.text.plainText : ""
            if !text.isEmpty { line += " " + text.replacingOccurrences(of: "\n", with: "⏎") }
            if let grid = block.props.table { line += " " + grid.rows.map { $0.map(\.plainText).joined(separator: "|") }.joined(separator: "/") }
            if !block.props.caption.isEmpty { line += " [" + block.props.caption.plainText + "]" }
            let nested = outline(block.children, depth: depth + 1)
            return nested.isEmpty ? line : line + "\n" + nested
        }.joined(separator: "\n")
    }
}
