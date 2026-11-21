import Foundation

package struct EaselTableGrid: Equatable {
    package var cells: [[String]]
    package var merges: [EaselTableMerge] = []
    package var truncated = false

    package var rowCount: Int { cells.count }
    package var columnCount: Int { cells.map(\.count).max() ?? 0 }

    package init(cells: [[String]], merges: [EaselTableMerge] = [], truncated: Bool = false) {
        self.cells = cells
        self.merges = merges
        self.truncated = truncated
    }
}

package enum EaselTableData {
    package static let maximumInputCharacters = 4_000_000
    package static let maximumParsedRows = 10_000

    package static func delimited(_ text: String, separator: Character) -> EaselTableGrid {
        var rows: [[String]] = [], row: [String] = [], field = ""
        var quoted = false, fieldStarted = false
        let characters = Array(text.prefix(maximumInputCharacters))
        var truncated = characters.count == maximumInputCharacters && text.count > maximumInputCharacters
        var index = 0
        while index < characters.count, rows.count < maximumParsedRows {
            let character = characters[index]
            if quoted {
                if character == "\"" {
                    if index + 1 < characters.count, characters[index + 1] == "\"" {
                        field.append("\"")
                        index += 2
                        continue
                    }
                    quoted = false
                } else {
                    field.append(character)
                }
            } else if character == "\"", !fieldStarted {
                quoted = true
                fieldStarted = true
            } else if character == separator {
                row.append(field)
                field = ""
                fieldStarted = false
            } else if character == "\n" || character == "\r" || character == "\r\n" {
                row.append(field)
                rows.append(row)
                row = []
                field = ""
                fieldStarted = false
            } else {
                field.append(character)
                fieldStarted = true
            }
            index += 1
        }
        if rows.count < maximumParsedRows, fieldStarted || !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        } else if index < characters.count {
            truncated = true
        }
        return EaselTableGrid(cells: rows, truncated: truncated)
    }

    package static func readsHTMLTable(plainText: String?, intoCells: Bool) -> Bool {
        intoCells || plainText == nil || plainText?.contains("\t") == true
    }

    package static func spreadsheetText(_ text: String) -> EaselTableGrid? {
        guard text.contains("\t") else { return nil }
        let grid = delimited(text, separator: "\t")
        guard let first = grid.cells.first?.count, first >= 2, grid.cells.allSatisfy({ $0.count == first }) else { return nil }
        return grid
    }

    package static func csv(_ text: String) -> EaselTableGrid? {
        let grid = delimited(text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text, separator: ",")
        guard grid.rowCount > 0, grid.columnCount > 0 else { return nil }
        return grid
    }

    package static func html(_ html: String) -> EaselTableGrid? {
        let scalars = Array(html.unicodeScalars.prefix(maximumInputCharacters))
        let clippedInput = scalars.count == maximumInputCharacters && html.unicodeScalars.count > maximumInputCharacters
        var rows: [[(text: String, rowSpan: Int, columnSpan: Int)]] = []
        var row: [(text: String, rowSpan: Int, columnSpan: Int)]?
        var cell: (text: String.UnicodeScalarView, rowSpan: Int, columnSpan: Int)?
        var depth = 0, skipping: String?, index = 0
        func finishCell() {
            guard let open = cell else { return }
            if row == nil { row = [] }
            row?.append((normalizedCellText(String(open.text)), open.rowSpan, open.columnSpan))
            cell = nil
        }
        func finishRow() {
            finishCell()
            if let open = row { rows.append(open) }
            row = nil
        }
        while index < scalars.count, rows.count < maximumParsedRows {
            let scalar = scalars[index]
            guard scalar == "<" else {
                if depth > 0, skipping == nil, cell != nil { cell?.text.append(scalar) }
                index += 1
                continue
            }
            if index + 3 < scalars.count, scalars[index + 1] == "!", scalars[index + 2] == "-", scalars[index + 3] == "-" {
                var end = index + 4
                while end + 2 < scalars.count, !(scalars[end] == "-" && scalars[end + 1] == "-" && scalars[end + 2] == ">") { end += 1 }
                index = end + 3
                continue
            }
            var end = index + 1
            var quote: Unicode.Scalar?
            while end < scalars.count {
                let next = scalars[end]
                if let open = quote {
                    if next == open { quote = nil }
                } else if next == "\"" || next == "'" {
                    quote = next
                } else if next == ">" {
                    break
                }
                end += 1
            }
            let tag = String(String.UnicodeScalarView(scalars[(index + 1)..<min(end, scalars.count)]))
            index = end + 1
            let closing = tag.hasPrefix("/")
            let body = closing ? tag.dropFirst() : Substring(tag)
            let name = body.prefix { $0.isLetter || $0.isNumber }.lowercased()
            if let skip = skipping {
                if closing, name == skip { skipping = nil }
                continue
            }
            switch name {
            case "style", "script", "title", "head":
                if !closing, !tag.hasSuffix("/") { skipping = name }
            case "table":
                if closing {
                    if depth == 1 { finishRow() }
                    depth = max(0, depth - 1)
                    if depth == 0, !rows.isEmpty { index = scalars.count }
                } else {
                    depth += 1
                }
            case "tr" where depth == 1:
                finishRow()
                if !closing { row = [] }
            case "td", "th":
                guard depth == 1 else { continue }
                finishCell()
                if !closing {
                    cell = (String.UnicodeScalarView(), span("rowspan", in: body), span("colspan", in: body))
                }
            case "br":
                if depth > 0, cell != nil { cell?.text.append("\u{2028}") }
            case "p", "div", "li":
                if depth > 0, closing, let open = cell, !open.text.isEmpty { cell?.text.append("\u{2028}") }
            default:
                break
            }
        }
        finishRow()
        guard var grid = layout(rows) else { return nil }
        if clippedInput { grid.truncated = true }
        return grid
    }

    private static func span(_ name: String, in tag: Substring) -> Int {
        let lowered = tag.lowercased()
        guard let range = lowered.range(of: name) else { return 1 }
        var digits = ""
        var started = false
        for character in lowered[range.upperBound...] {
            if character.isNumber { digits.append(character); started = true }
            else if started || !(character == "=" || character == "\"" || character == "'" || character == " ") { break }
        }
        return min(EaselTable.maximumRows, max(1, Int(digits) ?? 1))
    }

    private static func layout(_ rows: [[(text: String, rowSpan: Int, columnSpan: Int)]]) -> EaselTableGrid? {
        guard !rows.isEmpty else { return nil }
        var placed: [EaselTableCoordinate: String] = [:]
        var occupied = Set<EaselTableCoordinate>()
        var merges: [EaselTableMerge] = []
        var width = 0, height = 0, truncated = rows.count > EaselTable.maximumRows
        for (rowIndex, row) in rows.enumerated() where rowIndex < EaselTable.maximumRows {
            var column = 0
            for cell in row {
                while occupied.contains(EaselTableCoordinate(row: rowIndex, column: column)) { column += 1 }
                guard column < EaselTable.maximumColumns else { truncated = true; break }
                let rowSpan = min(cell.rowSpan, EaselTable.maximumRows - rowIndex)
                let columnSpan = min(cell.columnSpan, EaselTable.maximumColumns - column)
                if rowSpan < cell.rowSpan || columnSpan < cell.columnSpan { truncated = true }
                placed[EaselTableCoordinate(row: rowIndex, column: column)] = cell.text
                for r in rowIndex..<(rowIndex + rowSpan) {
                    for c in column..<(column + columnSpan) { occupied.insert(EaselTableCoordinate(row: r, column: c)) }
                }
                if rowSpan > 1 || columnSpan > 1 {
                    merges.append(EaselTableMerge(row: rowIndex, column: column, rowSpan: rowSpan, columnSpan: columnSpan))
                }
                width = max(width, column + columnSpan)
                height = max(height, rowIndex + rowSpan)
                column += columnSpan
            }
            height = max(height, rowIndex + 1)
        }
        guard width > 0, height > 0 else { return nil }
        let cells = (0..<height).map { row in (0..<width).map { placed[EaselTableCoordinate(row: row, column: $0)] ?? "" } }
        return EaselTableGrid(cells: cells, merges: merges, truncated: truncated)
    }

    package static func normalizedCellText(_ raw: String) -> String {
        let text = decodeEntities(raw)
        var collapsed = ""
        var pendingSpace = false
        for scalar in text.unicodeScalars {
            if scalar == "\u{2028}" {
                while collapsed.hasSuffix(" ") { collapsed.removeLast() }
                collapsed.append("\n")
                pendingSpace = false
            } else if scalar == " " || scalar == "\t" || scalar == "\n" || scalar == "\r" || scalar == "\u{00A0}" {
                pendingSpace = !collapsed.isEmpty && !collapsed.hasSuffix("\n")
            } else {
                if pendingSpace { collapsed.append(" ") }
                pendingSpace = false
                collapsed.unicodeScalars.append(scalar)
            }
        }
        let kept: (Character) -> Bool = { $0 != "\n" && $0 != " " }
        guard let start = collapsed.firstIndex(where: kept), let end = collapsed.lastIndex(where: kept) else { return "" }
        return String(collapsed[start...end])
    }

    private static let entities: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": "\u{00A0}", "ndash": "\u{2013}", "mdash": "\u{2014}",
        "hellip": "\u{2026}", "lsquo": "\u{2018}", "rsquo": "\u{2019}", "ldquo": "\u{201C}", "rdquo": "\u{201D}", "euro": "\u{20AC}",
        "pound": "\u{00A3}", "yen": "\u{00A5}", "copy": "\u{00A9}", "reg": "\u{00AE}", "trade": "\u{2122}", "deg": "\u{00B0}",
        "times": "\u{00D7}", "divide": "\u{00F7}", "middot": "\u{00B7}", "bull": "\u{2022}",
    ]

    package static func decodeEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var result = ""
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            guard character == "&", let semicolon = text[index...].prefix(12).firstIndex(of: ";") else {
                result.append(character)
                index = text.index(after: index)
                continue
            }
            let name = String(text[text.index(after: index)..<semicolon])
            var decoded: String?
            if name.hasPrefix("#x") || name.hasPrefix("#X") {
                decoded = UInt32(name.dropFirst(2), radix: 16).flatMap(Unicode.Scalar.init).map { String(Character($0)) }
            } else if name.hasPrefix("#") {
                decoded = UInt32(name.dropFirst()).flatMap(Unicode.Scalar.init).map { String(Character($0)) }
            } else {
                decoded = entities[name.lowercased()]
            }
            if let decoded {
                result += decoded
                index = text.index(after: semicolon)
            } else {
                result.append(character)
                index = text.index(after: index)
            }
        }
        return result
    }

    package static func table(from grid: EaselTableGrid) -> EaselTable? { imported(grid)?.table }

    package static func imported(_ grid: EaselTableGrid, limit: Int = EaselTable.maximumPastedCells) -> (table: EaselTable, trimmed: Bool)? {
        let width = min(EaselTable.maximumColumns, grid.columnCount, max(1, limit))
        guard width > 0, grid.rowCount > 0 else { return nil }
        let height = min(grid.rowCount, EaselTable.maximumRows, max(1, min(limit, EaselTable.maximumCells) / width))
        var trimmed = grid.truncated || width < grid.columnCount || height < grid.rowCount
        var table = EaselTable.blank(columns: width, rows: height)
        var bytes = 0
        for row in 0..<table.rowCount {
            for column in 0..<table.columnCount {
                guard grid.cells.indices.contains(row), grid.cells[row].indices.contains(column) else { continue }
                let original = grid.cells[row][column]
                let text = clipped(original, bytes: min(EaselTable.maximumCellBytes, EaselTable.maximumTextBytes - bytes))
                if text.utf8.count < original.utf8.count { trimmed = true }
                bytes += text.utf8.count
                table.cells[row][column].text = text
            }
        }
        var occupied = Set<EaselTableCoordinate>()
        for merge in grid.merges where merge.row < table.rowCount && merge.column < table.columnCount {
            let clippedMerge = EaselTableMerge(row: merge.row, column: merge.column,
                                               rowSpan: min(merge.rowSpan, table.rowCount - merge.row),
                                               columnSpan: min(merge.columnSpan, table.columnCount - merge.column))
            let cells = clippedMerge.range.cells
            guard clippedMerge.rowSpan > 1 || clippedMerge.columnSpan > 1, cells.allSatisfy({ !occupied.contains($0) }) else { continue }
            occupied.formUnion(cells)
            for cell in cells where cell != clippedMerge.anchor { table.cells[cell.row][cell.column] = EaselTableCell() }
            table.merges.append(clippedMerge)
        }
        return (table, trimmed)
    }

    package static func clipped(_ text: String, bytes limit: Int) -> String {
        guard text.utf8.count > limit else { return text }
        var result = ""
        var used = 0
        for character in text {
            let size = String(character).utf8.count
            guard used + size <= limit else { break }
            result.append(character)
            used += size
        }
        return result
    }

    package static func csv(_ table: EaselTable, range: EaselTableRange? = nil) -> String {
        delimitedText(table, range: range, separator: ",", lineEnding: "\r\n")
    }

    package static func tsv(_ table: EaselTable, range: EaselTableRange? = nil) -> String {
        delimitedText(table, range: range, separator: "\t", lineEnding: "\n")
    }

    private static func delimitedText(_ table: EaselTable, range: EaselTableRange?, separator: Character, lineEnding: String) -> String {
        guard let area = (range ?? table.all).clampedArea(in: table) else { return "" }
        return area.rows.map { row in
            area.columns.map { column -> String in
                let cell = EaselTableCoordinate(row: row, column: column)
                return field(table.isCovered(cell) ? "" : (table.cell(cell).map { EaselRichText.readable($0.text, rich: $0.richText) } ?? ""), separator: separator)
            }.joined(separator: String(separator))
        }.joined(separator: lineEnding) + lineEnding
    }

    package static func field(_ raw: String, separator: Character) -> String {
        let text = raw.replacingOccurrences(of: "\u{FFFC}", with: "")
        guard text.contains(where: { $0 == separator || $0 == "\"" || $0.isNewline }) else { return text }
        return "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    package static func html(_ table: EaselTable, range: EaselTableRange? = nil) -> String {
        guard let area = (range ?? table.all).clampedArea(in: table) else { return "" }
        var result = "<meta charset=\"utf-8\"><table>"
        for row in area.rows {
            result += "<tr>"
            for column in area.columns {
                let cell = EaselTableCoordinate(row: row, column: column)
                guard !table.isCovered(cell), let value = table.cell(cell) else { continue }
                var attributes = ""
                if let merge = table.merge(containing: cell) {
                    let span = merge.range
                    let rows = min(span.rows.upperBound, area.rows.upperBound) - row + 1
                    let columns = min(span.columns.upperBound, area.columns.upperBound) - column + 1
                    if rows > 1 { attributes += " rowspan=\"\(rows)\"" }
                    if columns > 1 { attributes += " colspan=\"\(columns)\"" }
                }
                if let fill = value.fill { attributes += " style=\"background-color:" + fill + "\"" }
                let text = EaselVectorExport.escape(EaselRichText.readable(value.text, rich: value.richText))
                    .replacingOccurrences(of: "\n", with: "<br>")
                result += "<td" + attributes + ">" + text + "</td>"
            }
            result += "</tr>"
        }
        return result + "</table>"
    }
}

extension EaselTableRange {
    package func clampedArea(in table: EaselTable) -> EaselTableRange? {
        table.clamped(self)
    }
}
