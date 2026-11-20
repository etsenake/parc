import Foundation

func expect(_ condition: Bool, _ message: @autoclosure () -> String, file: StaticString = #file, line: UInt = #line) {
    if !condition { failTest(message(), file: file, line: line) }
}

func expectEqual<Value: Equatable>(_ actual: Value, _ expected: Value, _ message: @autoclosure () -> String,
                                   file: StaticString = #file, line: UInt = #line) {
    if actual != expected { failTest("\(message())\n--- expected ---\n\(expected)\n--- actual ---\n\(actual)", file: file, line: line) }
}

func block(_ kind: NoteBlockKind, _ text: String = "", _ children: [NoteBlock] = [],
           _ configure: (inout NoteBlockProps) -> Void = { _ in }) -> NoteBlock {
    var props = NoteBlockProps()
    configure(&props)
    return NoteBlock(kind, text: NoteText(text), props: props, children: children)
}

func para(_ text: String = "") -> NoteBlock { block(.paragraph, text) }
func heading(_ level: Int, _ text: String = "") -> NoteBlock { block(.heading, text) { $0.level = level } }
func toggleHeading(_ level: Int, _ text: String = "", expanded: Bool = true, _ children: [NoteBlock] = []) -> NoteBlock {
    block(.heading, text, children) { $0.level = level; $0.toggleable = true; $0.expanded = expanded }
}
func bullet(_ text: String = "", _ children: [NoteBlock] = []) -> NoteBlock { block(.bulletedItem, text, children) }
func numbered(_ text: String = "", start: Int? = nil, _ children: [NoteBlock] = []) -> NoteBlock {
    block(.numberedItem, text, children) { $0.listStart = start }
}
func todo(_ text: String = "", checked: Bool = false, _ children: [NoteBlock] = []) -> NoteBlock {
    block(.todo, text, children) { $0.checked = checked }
}
func toggle(_ text: String = "", expanded: Bool = true, _ children: [NoteBlock] = []) -> NoteBlock {
    block(.toggle, text, children) { $0.expanded = expanded }
}
func quote(_ text: String = "", _ children: [NoteBlock] = []) -> NoteBlock { block(.quote, text, children) }
func callout(_ text: String = "", _ children: [NoteBlock] = []) -> NoteBlock { block(.callout, text, children) { $0.icon = "💡" } }
func code(_ text: String = "") -> NoteBlock { block(.code, text) }
func divider() -> NoteBlock { block(.divider) }
func image(_ source: String = "a.png", caption: String = "") -> NoteBlock {
    block(.image) { $0.source = source; $0.caption = NoteText(caption) }
}
func table(_ rows: [[String]]) -> NoteBlock {
    block(.table) { $0.table = NoteTable(rows: rows.map { $0.map { NoteText($0) } }) }
}
func columns(_ groups: [[NoteBlock]]) -> NoteBlock {
    NoteBlock(.columns, children: groups.map { NoteBlock(.column, children: $0) })
}

func marks(_ configure: (inout NoteMarks) -> Void) -> NoteMarks {
    var value = NoteMarks.plain
    configure(&value)
    return value
}

let boldMarks = marks { $0.bold = true }
let italicMarks = marks { $0.italic = true }

func tag(_ block: NoteBlock) -> String {
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

func outline(_ blocks: [NoteBlock], depth: Int = 0) -> String {
    blocks.map { block -> String in
        let indent = String(repeating: "  ", count: depth)
        var line = indent + tag(block)
        let text = block.kind.hasText ? block.text.plainText : ""
        if !text.isEmpty { line += " " + text.replacingOccurrences(of: "\n", with: "⏎") }
        if let grid = block.props.table { line += " " + grid.rows.map { $0.map(\.plainText).joined(separator: "|") }.joined(separator: "/") }
        if !block.props.caption.isEmpty { line += " [" + block.props.caption.plainText + "]" }
        let nested = outline(block.children, depth: depth + 1)
        return nested.isEmpty ? line : line + "\n" + nested
    }.joined(separator: "\n")
}

func outline(_ page: NotePage) -> String { outline(page.blocks) }

func trimmed(_ value: String) -> String {
    value.split(separator: "\n", omittingEmptySubsequences: false)
        .map { line -> Substring in
            var current = Substring(line)
            while current.last == " " { current = current.dropLast() }
            return current
        }
        .joined(separator: "\n")
        .trimmingCharacters(in: .newlines)
}

func expectOutline(_ page: NotePage, _ expected: String, _ message: String = "outline", file: StaticString = #file, line: UInt = #line) {
    expectEqual(trimmed(outline(page)), trimmed(expected), message, file: file, line: line)
    verifyIndex(page, file: file, line: line)
}

func verifyIndex(_ page: NotePage, file: StaticString = #file, line: UInt = #line) {
    var expectedAll: [NoteBlockID] = []
    var expectedVisible: [NoteBlockID] = []
    func walk(_ list: [NoteBlock], path: [Int], parent: NoteBlockID?, visible: Bool) {
        for (index, block) in list.enumerated() {
            let location = path + [index]
            expectedAll.append(block.id)
            if visible { expectedVisible.append(block.id) }
            if page.path(of: block.id) != location { failTest("index path for \(tag(block)) \(block.text.plainText) is stale", file: file, line: line) }
            if page.parent(of: block.id) != parent { failTest("index parent for \(block.text.plainText) is stale", file: file, line: line) }
            if page.block(block.id) != block { failTest("index lookup for \(block.text.plainText) is stale", file: file, line: line) }
            walk(block.children, path: location, parent: block.id, visible: visible && block.showsChildren)
        }
    }
    walk(page.blocks, path: [], parent: nil, visible: true)
    if page.documentOrder() != expectedAll { failTest("index document order is stale", file: file, line: line) }
    if page.documentOrder(includingCollapsed: false) != expectedVisible { failTest("index visible order is stale", file: file, line: line) }
}

@MainActor
final class TestClock {
    var time = Date(timeIntervalSinceReferenceDate: 0)
    func advance(_ seconds: TimeInterval) { time = time.addingTimeInterval(seconds) }
}

@MainActor
func makeSession(_ blocks: [NoteBlock], clock: TestClock? = nil) -> NotePageSession {
    let session = NotePageSession(page: NotePage(blocks: blocks))
    if let clock { session.now = { clock.time } }
    else {
        let fixed = TestClock()
        session.now = { fixed.time }
    }
    return session
}

extension NotePageSession {
    func id(_ text: String) -> NoteBlockID {
        guard let found = page.allBlocks().first(where: { $0.kind.hasText && $0.text.plainText == text }) else {
            failTest("no block with text \(text)")
        }
        return found.id
    }

    func caret(_ text: String, _ offset: Int) {
        setSelection(.caret(NotePosition(id(text), offset)))
    }

    func type(_ value: String) {
        guard let caret = selection.caret, var text = page.text(of: caret) else { failTest("typing needs a caret") }
        text.insert(value, at: caret.offset)
        setText(text, of: (caret.block, caret.field),
                selection: .caret(NotePosition(caret.block, caret.offset + (value as NSString).length, field: caret.field)))
    }
}
