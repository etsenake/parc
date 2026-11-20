import Foundation

enum MarkdownCheck {
    static let fixedID = NoteBlockID(UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)))
    static var failures = 0

    static func anonymized(_ blocks: [NoteBlock]) -> [NoteBlock] {
        blocks.map { block in
            var copy = block
            copy.id = fixedID
            copy.children = anonymized(block.children)
            return copy
        }
    }

    static func anonymized(_ page: NotePage) -> NotePage {
        NotePage(settings: page.settings, blocks: anonymized(page.blocks))
    }

    static func same(_ left: NotePage, _ right: NotePage) -> Bool {
        anonymized(left) == anonymized(right)
    }

    static func expect(_ condition: Bool, _ message: @autoclosure () -> String, file: StaticString = #file, line: UInt = #line) {
        if !condition { report(message(), file: file, line: line) }
    }

    static func report(_ message: String, file: StaticString, line: UInt) {
        failures += 1
        FileHandle.standardError.write(Data("\(file):\(line): \(message)\n\n".utf8))
    }

    static func finish(_ name: String) {
        if failures > 0 { failTest("\(name): \(failures) failures") }
        print("\(name) passed")
    }

    static func describe(_ blocks: [NoteBlock], depth: Int = 0) -> String {
        var lines: [String] = []
        for block in blocks {
            let pad = String(repeating: "  ", count: depth)
            var line = "\(pad)\(block.kind.rawValue) \(String(reflecting: block.text.string))"
            let runs = block.text.runs().filter { !$0.marks.isPlain }
            if !runs.isEmpty { line += " marks=" + runs.map { "\($0.range):\(describe($0.marks))" }.joined(separator: ",") }
            if block.props != NoteBlockProps() { line += " props=\(describe(block.props))" }
            if let color = block.color { line += " color=\(color)" }
            lines.append(line)
            if !block.children.isEmpty { lines.append(describe(block.children, depth: depth + 1)) }
        }
        return lines.joined(separator: "\n")
    }

    static func describe(_ marks: NoteMarks) -> String {
        var parts: [String] = []
        if marks.bold { parts.append("b") }
        if marks.italic { parts.append("i") }
        if marks.underline { parts.append("u") }
        if marks.strikethrough { parts.append("s") }
        if marks.code { parts.append("c") }
        if let link = marks.link { parts.append("link(\(link))") }
        if let color = marks.color { parts.append("\(color)") }
        if let atom = marks.atom { parts.append("atom(\(atom))") }
        return parts.joined(separator: "+")
    }

    static func describe(_ props: NoteBlockProps) -> String {
        let empty = NoteBlockProps()
        var parts: [String] = []
        if props.level != empty.level { parts.append("level=\(props.level)") }
        if props.toggleable { parts.append("toggleable") }
        if !props.expanded { parts.append("collapsed") }
        if props.checked { parts.append("checked") }
        if let value = props.listStart { parts.append("start=\(value)") }
        if let value = props.bulletMarker { parts.append("bullet=\(value)") }
        if let value = props.orderedDelimiter { parts.append("delimiter=\(value)") }
        if props.looseList { parts.append("loose") }
        if let value = props.icon { parts.append("icon=\(value)") }
        if let value = props.alert { parts.append("alert=\(value)") }
        if !props.language.isEmpty { parts.append("language=\(props.language)") }
        if props.wrap { parts.append("wrap") }
        if let value = props.fence { parts.append("fence=\(String(reflecting: value))") }
        if let value = props.info { parts.append("info=\(value)") }
        if let value = props.source { parts.append("source=\(value)") }
        if let value = props.alt { parts.append("alt=\(value)") }
        if let value = props.width { parts.append("width=\(value)") }
        if props.alignment != .center { parts.append("align=\(props.alignment)") }
        if !props.caption.isEmpty { parts.append("caption=\(String(reflecting: props.caption.string))") }
        if let value = props.bookmark { parts.append("bookmark=\(value)") }
        if let value = props.table { parts.append("table=\(value.rows.map { $0.map(\.string) }) align=\(value.alignments) header=\(value.headerRow)/\(value.headerColumn) widths=\(value.columnWidths)") }
        if let value = props.target { parts.append("target=\(value)") }
        if let value = props.anchor { parts.append("anchor=\(value)") }
        return parts.joined(separator: " ")
    }

    static func checkModelRoundTrip(_ page: NotePage, _ label: String, file: StaticString = #file, line: UInt = #line) {
        let markdown = NoteMarkdown.serialize(page)
        let reparsed = NoteMarkdown.parse(markdown)
        if !same(page, reparsed) {
            report("""
            \(label): model did not survive a round trip
            --- markdown
            \(markdown)--- expected
            \(describe(page.blocks))
            \(page.settings)
            --- got
            \(describe(reparsed.blocks))
            \(reparsed.settings)
            """, file: file, line: line)
        }
    }

    static func checkExact(_ source: String, _ label: String, file: StaticString = #file, line: UInt = #line) {
        let page = NoteMarkdown.parse(source)
        let output = NoteMarkdown.serialize(page)
        if output != source {
            report("""
            \(label): serialize(parse(x)) changed the text
            --- source
            \(source)--- output
            \(output)--- model
            \(describe(page.blocks))
            """, file: file, line: line)
        }
        checkModelRoundTrip(page, label, file: file, line: line)
    }

    static func checkStable(_ source: String, _ label: String, file: StaticString = #file, line: UInt = #line) {
        let page = NoteMarkdown.parse(source)
        let first = NoteMarkdown.serialize(page)
        let reparsed = NoteMarkdown.parse(first)
        if !same(page, reparsed) {
            report("""
            \(label): meaning changed after one save
            --- source
            \(source)--- saved
            \(first)--- model
            \(describe(page.blocks))
            --- reparsed
            \(describe(reparsed.blocks))
            """, file: file, line: line)
        }
        let second = NoteMarkdown.serialize(reparsed)
        if second != first {
            report("\(label): a second save changed the text again\n--- first\n\(first)--- second\n\(second)", file: file, line: line)
        }
    }
}
