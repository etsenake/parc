import Foundation

enum NoteTableClipboard {
    static func grid(fromDelimited text: String) -> [[String]]? {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let trimmed = normalized.hasSuffix("\n") ? String(normalized.dropLast()) : normalized
        guard !trimmed.isEmpty else { return nil }
        if trimmed.contains("\t") {
            let rows = parse(trimmed, separator: "\t")
            return rows.count > 1 || (rows.first?.count ?? 0) > 1 ? padded(rows) : nil
        }
        guard trimmed.contains(","), trimmed.contains("\n") else { return nil }
        let rows = parse(trimmed, separator: ",")
        let widths = Set(rows.filter { !($0.count == 1 && $0[0].isEmpty) }.map(\.count))
        guard rows.count > 1, widths.count == 1, let width = widths.first, width > 1 else { return nil }
        return padded(rows)
    }

    static func parse(_ text: String, separator: Character) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var quoted = false
        var atFieldStart = true
        var characters = text.makeIterator()
        var pending: Character?
        while let character = pending ?? characters.next() {
            pending = nil
            if quoted {
                if character == "\"" {
                    if let next = characters.next() {
                        if next == "\"" { field.append("\"") } else { quoted = false; pending = next }
                    } else {
                        quoted = false
                    }
                } else {
                    field.append(character)
                }
                continue
            }
            if character == "\"", atFieldStart {
                quoted = true
                atFieldStart = false
            } else if character == separator {
                row.append(field)
                field = ""
                atFieldStart = true
            } else if character == "\n" {
                row.append(field)
                rows.append(row)
                row = []
                field = ""
                atFieldStart = true
            } else {
                field.append(character)
                atFieldStart = false
            }
        }
        row.append(field)
        rows.append(row)
        return rows
    }

    static func cells(from grid: [[String]]) -> [[NoteText]] {
        grid.map { $0.map { NoteText($0) } }
    }

    static func tsv(_ rows: [[NoteText]]) -> String {
        rows.map { row in row.map { quotedTSVField($0.plainText) }.joined(separator: "\t") }.joined(separator: "\n")
    }

    static func plainLines(_ rows: [[NoteText]]) -> String {
        rows.map { row in row.map(\.plainText).joined(separator: " ") }.joined(separator: "\n")
    }

    static func html(_ rows: [[NoteText]], headerRow: Bool, headerColumn: Bool, alignments: [NoteAlignment?]) -> String {
        func line(_ row: [NoteText], header: Bool) -> String {
            var result = "<tr>"
            for (column, cell) in row.enumerated() {
                let tag = header || (column == 0 && headerColumn) ? "th" : "td"
                let style = column < alignments.count ? alignments[column].map { " style=\"text-align: \($0.rawValue)\"" } ?? "" : ""
                result += "<\(tag)\(style)>\(inlineHTML(cell))</\(tag)>"
            }
            return result + "</tr>"
        }
        var result = "<table>"
        var body = rows[...]
        if headerRow, let first = rows.first {
            result += "<thead>" + line(first, header: true) + "</thead>"
            body = rows.dropFirst()
        }
        if !body.isEmpty { result += "<tbody>" + body.map { line($0, header: false) }.joined() + "</tbody>" }
        return result + "</table>"
    }

    static func markdown(_ rows: [[NoteText]], headerRow: Bool, headerColumn: Bool, alignments: [NoteAlignment?]) -> String {
        var table = NoteTable(rows: rows, headerRow: headerRow, headerColumn: headerColumn)
        for index in table.alignments.indices where index < alignments.count { table.alignments[index] = alignments[index] }
        var props = NoteBlockProps()
        props.table = table
        let serialized = NoteMarkdown.serialize(NotePage(blocks: [NoteBlock(.table, props: props)]))
        let trimmed = serialized.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.contains("|") ? trimmed : fallbackMarkdown(rows, alignments: alignments)
    }

    static func fallbackMarkdown(_ rows: [[NoteText]], alignments: [NoteAlignment?]) -> String {
        guard let first = rows.first else { return "" }
        func line(_ cells: [String]) -> String { "| " + cells.joined(separator: " | ") + " |" }
        func escaped(_ text: NoteText) -> String {
            text.plainText.replacingOccurrences(of: "|", with: "\\|").replacingOccurrences(of: "\n", with: "<br>")
        }
        let rule = first.indices.map { index -> String in
            switch index < alignments.count ? alignments[index] : nil {
            case .left: return ":---"
            case .center: return ":---:"
            case .right: return "---:"
            case nil: return "---"
            }
        }
        return ([line(first.map(escaped)), line(rule)] + rows.dropFirst().map { line($0.map(escaped)) }).joined(separator: "\n")
    }

    static func inlineHTML(_ text: NoteText) -> String {
        var result = ""
        let source = text.string as NSString
        for run in text.runs() {
            var piece: String
            if let atom = run.marks.atom {
                piece = escapeHTML(atom.fallbackText)
                if case .link(let url, _) = atom { piece = "<a href=\"\(escapeHTML(url))\">\(piece)</a>" }
            } else {
                piece = escapeHTML(source.substring(with: NSRange(location: run.range.lowerBound, length: run.range.count)))
                    .replacingOccurrences(of: "\n", with: "<br>")
            }
            let marks = run.marks
            if marks.code { piece = "<code>\(piece)</code>" }
            if marks.bold { piece = "<strong>\(piece)</strong>" }
            if marks.italic { piece = "<em>\(piece)</em>" }
            if marks.underline { piece = "<u>\(piece)</u>" }
            if marks.strikethrough { piece = "<s>\(piece)</s>" }
            if let link = marks.link { piece = "<a href=\"\(escapeHTML(link))\">\(piece)</a>" }
            result += piece
        }
        return result
    }

    static func escapeHTML(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static func quotedTSVField(_ value: String) -> String {
        guard value.contains("\t") || value.contains("\n") || value.contains("\"") else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private static func padded(_ rows: [[String]]) -> [[String]] {
        let width = rows.map(\.count).max() ?? 0
        return rows.map { $0 + Array(repeating: "", count: width - $0.count) }
    }
}
