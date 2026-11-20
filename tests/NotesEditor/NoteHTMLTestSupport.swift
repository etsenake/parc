import Foundation

enum NoteHTMLCheck {
    static var failures = 0

    static func expect(_ value: Bool, _ message: String, file: StaticString = #file, line: UInt = #line) {
        guard !value else { return }
        failures += 1
        FileHandle.standardError.write(Data("\(file):\(line): \(message)\n".utf8))
    }

    static func finish(_ name: String) {
        if failures > 0 { failTest("\(name): \(failures) expectation(s) failed") }
        print("\(name) passed")
    }

    static func outline(_ blocks: [NoteBlock], depth: Int = 0) -> String {
        blocks.map { block in
            var line = String(repeating: "  ", count: depth) + block.kind.rawValue
            if block.kind == .heading { line += String(block.props.level) }
            if block.kind == .todo { line += block.props.checked ? "[x]" : "[ ]" }
            if !block.text.isEmpty { line += " " + block.text.plainText.debugDescription }
            if let source = block.props.source { line += " src=" + source }
            if let table = block.props.table { line += " table=" + table.rows.map { $0.map(\.plainText) }.description }
            if let color = block.color { line += " color=" + NoteHTMLColor.token(color) }
            return ([line] + (block.children.isEmpty ? [] : [outline(block.children, depth: depth + 1)])).joined(separator: "\n")
        }.joined(separator: "\n")
    }

    static func range(of word: String, in text: NoteText) -> Range<Int>? {
        let found = (text.string as NSString).range(of: word)
        guard found.location != NSNotFound else { return nil }
        return found.location..<(found.location + found.length)
    }

    static func marks(of word: String, in text: NoteText) -> NoteMarks? {
        guard let bounds = range(of: word, in: text) else { return nil }
        let runs = text.runs(in: bounds)
        guard let first = runs.first, runs.allSatisfy({ $0.marks == first.marks }) else { return nil }
        return first.marks
    }

    static func same(_ lhs: [NoteBlock], _ rhs: [NoteBlock], path: String = "") -> [String] {
        guard lhs.count == rhs.count else { return ["\(path): \(lhs.count) blocks vs \(rhs.count)"] }
        var problems: [String] = []
        for (index, (left, right)) in zip(lhs, rhs).enumerated() {
            let here = "\(path)/\(index):\(left.kind.rawValue)"
            if left.kind != right.kind { problems.append("\(here): kind \(right.kind)") }
            if left.text != right.text { problems.append("\(here): text \(left.text) vs \(right.text)") }
            if left.props != right.props { problems.append("\(here): props \(left.props) vs \(right.props)") }
            if left.color != right.color { problems.append("\(here): color \(String(describing: left.color)) vs \(String(describing: right.color))") }
            problems += same(left.children, right.children, path: here)
        }
        return problems
    }
}
