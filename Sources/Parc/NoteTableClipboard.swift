import Foundation
import ParcCore

enum NoteTableClipboard {
    static func grid(fromDelimited text: String, fromSpreadsheet: Bool = false) -> [[String]]? {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let trimmed = normalized.hasSuffix("\n") ? String(normalized.dropLast()) : normalized
        guard !trimmed.isEmpty else { return nil }
        if trimmed.contains("\t") {
            let rows = parse(trimmed, separator: "\t")
            guard rows.count > 1 || (rows.first?.count ?? 0) > 1 else { return nil }
            if !fromSpreadsheet {
                guard Set(rows.map(\.count)).count == 1, !rows.allSatisfy({ $0.first?.isEmpty ?? true }) else { return nil }
            }
            return padded(rows)
        }
        guard trimmed.contains(","), trimmed.contains("\n") else { return nil }
        let rows = parse(trimmed, separator: ",")
        let widths = Set(rows.filter { !($0.count == 1 && $0[0].isEmpty) }.map(\.count))
        guard rows.count > 1, widths.count == 1, let width = widths.first, width > 1 else { return nil }
        return padded(rows)
    }

    static func parse(_ text: String, separator: Character) -> [[String]] {
        let characters = Array(text)
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var atFieldStart = true
        var index = 0
        while index < characters.count {
            let character = characters[index]
            if character == "\"", atFieldStart, let close = closingQuote(in: characters, after: index) {
                var position = index + 1
                while position < close {
                    field.append(characters[position])
                    position += characters[position] == "\"" ? 2 : 1
                }
                index = close + 1
                atFieldStart = false
                continue
            }
            if character == separator {
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
            index += 1
        }
        row.append(field)
        rows.append(row)
        return rows
    }

    private static func closingQuote(in characters: [Character], after opening: Int) -> Int? {
        var index = opening + 1
        while index < characters.count {
            if characters[index] == "\"" {
                if index + 1 < characters.count, characters[index + 1] == "\"" { index += 2; continue }
                return index
            }
            index += 1
        }
        return nil
    }

    static func grid(fromHTML html: String) -> [[NoteText]]? {
        guard html.range(of: "<table", options: .caseInsensitive) != nil,
              let table = NoteHTMLReader.blocks(from: html, baseURL: nil).first(where: { $0.kind == .table })?.props.table,
              table.rowCount * table.columnCount > 1 else { return nil }
        return table.rows
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
        var table = NoteTable(rows: rows.isEmpty ? [[NoteText()]] : rows, headerRow: headerRow, headerColumn: headerColumn)
        for (index, alignment) in alignments.enumerated() where table.alignments.indices.contains(index) { table.alignments[index] = alignment }
        return html(table)
    }

    static func html(_ source: NoteTable) -> String {
        var table = source
        table.normalize()
        let covered = table.coveredCells
        func cell(_ position: NoteTableCell) -> String {
            let header = (table.headerRow && position.row == 0) || (table.headerColumn && position.column == 0)
            let tag = header ? "th" : "td"
            var attributes = ""
            let span = table.span(of: position)
            if span.columnSpan > 1 { attributes += " colspan=\"\(span.columnSpan)\"" }
            if span.rowSpan > 1 { attributes += " rowspan=\"\(span.rowSpan)\"" }
            var styles: [String] = []
            if let alignment = table.alignments[position.column] { styles.append("text-align: \(alignment.rawValue)") }
            if let color = table.cellColors[position] {
                let palette = NotePageHTMLStyle.palette[color.color] ?? NotePageHTMLStyle.palette[.gray]!
                attributes += " data-color=\"\(NoteMDColor.name(color))\""
                styles.append(color.isBackground ? "background-color: #\(palette.background)" : "color: #\(palette.text)")
            }
            if !styles.isEmpty { attributes += " style=\"" + styles.joined(separator: "; ") + "\"" }
            return "<\(tag)\(attributes)>\(inlineHTML(table.rows[position.row][position.column]))</\(tag)>"
        }
        func line(_ row: Int) -> String {
            "<tr>" + (0..<table.columnCount).compactMap { column -> String? in
                let position = NoteTableCell(row: row, column: column)
                return covered.contains(position) ? nil : cell(position)
            }.joined() + "</tr>"
        }
        var result = "<table>"
        var first = 0
        if table.headerRow, !table.merges.contains(where: { $0.row == 0 && $0.rowSpan > 1 }) {
            result += "<thead>" + line(0) + "</thead>"
            first = 1
        }
        if first < table.rowCount { result += "<tbody>" + (first..<table.rowCount).map(line).joined() + "</tbody>" }
        return result + "</table>"
    }

    static func slice(_ rect: NoteTableRect, of table: NoteTable) -> NoteTable {
        table.slice(rows: rect.rows, columns: rect.columns)
    }

    static func markdown(_ table: NoteTable) -> String {
        var props = NoteBlockProps()
        props.table = table
        return NoteMarkdown.serialize(NotePage(blocks: [NoteBlock(.table, props: props)])).trimmingCharacters(in: .newlines)
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
