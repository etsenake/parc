import Foundation

struct NoteTableMerge: Hashable, Codable {
    var row: Int
    var column: Int
    var rowSpan: Int
    var columnSpan: Int

    init(row: Int, column: Int, rowSpan: Int, columnSpan: Int) {
        self.row = row
        self.column = column
        self.rowSpan = rowSpan
        self.columnSpan = columnSpan
    }

    init(rows: ClosedRange<Int>, columns: ClosedRange<Int>) {
        self.init(row: rows.lowerBound, column: columns.lowerBound, rowSpan: rows.count, columnSpan: columns.count)
    }

    var anchor: NoteTableCell { NoteTableCell(row: row, column: column) }
    var lastRow: Int { row + max(1, rowSpan) - 1 }
    var lastColumn: Int { column + max(1, columnSpan) - 1 }
    var rows: ClosedRange<Int> { row...lastRow }
    var columns: ClosedRange<Int> { column...lastColumn }
    var cellCount: Int { rowSpan * columnSpan }

    var cells: [NoteTableCell] {
        rows.flatMap { row in columns.map { NoteTableCell(row: row, column: $0) } }
    }

    func contains(_ cell: NoteTableCell) -> Bool {
        rows.contains(cell.row) && columns.contains(cell.column)
    }

    func intersects(rows other: ClosedRange<Int>, columns otherColumns: ClosedRange<Int>) -> Bool {
        rows.overlaps(other) && columns.overlaps(otherColumns)
    }
}

enum NoteTableFill: Hashable {
    case down, right
}

extension NoteTable {
    func merge(containing cell: NoteTableCell) -> NoteTableMerge? {
        merges.first { $0.contains(cell) }
    }

    func anchor(of cell: NoteTableCell) -> NoteTableCell {
        merge(containing: cell)?.anchor ?? cell
    }

    func isCovered(_ cell: NoteTableCell) -> Bool {
        guard let merge = merge(containing: cell) else { return false }
        return merge.anchor != cell
    }

    func span(of cell: NoteTableCell) -> NoteTableMerge {
        merge(containing: cell) ?? NoteTableMerge(row: cell.row, column: cell.column, rowSpan: 1, columnSpan: 1)
    }

    var visibleCells: [NoteTableCell] {
        var result: [NoteTableCell] = []
        let covered = coveredCells
        for row in 0..<rowCount {
            for column in 0..<columnCount {
                let cell = NoteTableCell(row: row, column: column)
                if !covered.contains(cell) { result.append(cell) }
            }
        }
        return result
    }

    var coveredCells: Set<NoteTableCell> {
        var result = Set<NoteTableCell>()
        for merge in merges {
            for cell in merge.cells where cell != merge.anchor { result.insert(cell) }
        }
        return result
    }

    func expanded(rows rowRange: ClosedRange<Int>, columns columnRange: ClosedRange<Int>) -> (rows: ClosedRange<Int>, columns: ClosedRange<Int>) {
        var rowsOut = rowRange, columnsOut = columnRange
        var changed = !merges.isEmpty
        while changed {
            changed = false
            for merge in merges where merge.intersects(rows: rowsOut, columns: columnsOut) {
                let nextRows = min(rowsOut.lowerBound, merge.row)...max(rowsOut.upperBound, merge.lastRow)
                let nextColumns = min(columnsOut.lowerBound, merge.column)...max(columnsOut.upperBound, merge.lastColumn)
                if nextRows != rowsOut || nextColumns != columnsOut {
                    rowsOut = nextRows
                    columnsOut = nextColumns
                    changed = true
                }
            }
        }
        return (rowsOut, columnsOut)
    }

    func canMerge(rows rowRange: ClosedRange<Int>, columns columnRange: ClosedRange<Int>) -> Bool {
        guard rowRange.lowerBound >= 0, columnRange.lowerBound >= 0, rowRange.upperBound < rowCount,
              columnRange.upperBound < columnCount else { return false }
        let area = expanded(rows: rowRange, columns: columnRange)
        guard area.rows.count * area.columns.count > 1 else { return false }
        return !merges.contains { $0.rows == area.rows && $0.columns == area.columns }
    }

    func hasMerges(intersecting rowRange: ClosedRange<Int>, columns columnRange: ClosedRange<Int>) -> Bool {
        merges.contains { $0.intersects(rows: rowRange, columns: columnRange) }
    }

    @discardableResult
    mutating func mergeCells(rows rowRange: ClosedRange<Int>, columns columnRange: ClosedRange<Int>) -> Bool {
        normalize()
        guard canMerge(rows: rowRange, columns: columnRange) else { return false }
        let area = expanded(rows: rowRange, columns: columnRange)
        merges.removeAll { $0.intersects(rows: area.rows, columns: area.columns) }
        let merged = NoteTableMerge(rows: area.rows, columns: area.columns)
        for cell in merged.cells where cell != merged.anchor {
            rows[cell.row][cell.column] = NoteText()
            cellColors[cell] = nil
        }
        merges.append(merged)
        normalize()
        return true
    }

    @discardableResult
    mutating func unmergeCells(rows rowRange: ClosedRange<Int>, columns columnRange: ClosedRange<Int>) -> Bool {
        let before = merges.count
        merges.removeAll { $0.intersects(rows: rowRange, columns: columnRange) }
        return merges.count != before
    }

    func color(at cell: NoteTableCell) -> NoteColorStyle? {
        cellColors[anchor(of: cell)]
    }

    @discardableResult
    mutating func setColor(_ style: NoteColorStyle?, rows rowRange: ClosedRange<Int>, columns columnRange: ClosedRange<Int>) -> Bool {
        normalize()
        let before = cellColors
        let area = expanded(rows: rowRange, columns: columnRange)
        for row in area.rows where row >= 0 && row < rowCount {
            for column in area.columns where column >= 0 && column < columnCount {
                let cell = NoteTableCell(row: row, column: column)
                cellColors[cell] = isCovered(cell) ? nil : style
            }
        }
        return cellColors != before
    }

    func commonColor(rows rowRange: ClosedRange<Int>, columns columnRange: ClosedRange<Int>) -> NoteColorStyle?? {
        var result: NoteColorStyle??
        for row in rowRange where row >= 0 && row < rowCount {
            for column in columnRange where column >= 0 && column < columnCount {
                let cell = NoteTableCell(row: row, column: column)
                guard !isCovered(cell) else { continue }
                let style = cellColors[cell]
                if let known = result, known != style { return .none }
                result = .some(style)
            }
        }
        if let result { return result }
        return .some(nil)
    }

    func uniformColor(column: Int) -> NoteColorStyle? {
        uniformColor((0..<rowCount).map { NoteTableCell(row: $0, column: column) }, minimum: 2)
    }

    func uniformColor(row: Int) -> NoteColorStyle? {
        uniformColor((0..<columnCount).map { NoteTableCell(row: row, column: $0) }, minimum: 2)
    }

    private func uniformColor(_ cells: [NoteTableCell], minimum: Int) -> NoteColorStyle? {
        guard cells.count >= minimum else { return nil }
        var found: NoteColorStyle?
        for cell in cells where !isCovered(cell) {
            guard let style = cellColors[cell], found == nil || found == style else { return nil }
            found = style
        }
        return found
    }

    @discardableResult
    mutating func fill(_ direction: NoteTableFill, rows rowRange: ClosedRange<Int>, columns columnRange: ClosedRange<Int>) -> Bool {
        normalize()
        guard rowRange.lowerBound >= 0, columnRange.lowerBound >= 0, rowRange.upperBound < rowCount, columnRange.upperBound < columnCount else { return false }
        let before = self
        switch direction {
        case .down:
            let source = rowRange.count > 1 ? rowRange.lowerBound : rowRange.lowerBound - 1
            guard source >= 0 else { return false }
            for row in rowRange where row != source {
                for column in columnRange { copyCell(from: NoteTableCell(row: source, column: column), to: NoteTableCell(row: row, column: column)) }
            }
        case .right:
            let source = columnRange.count > 1 ? columnRange.lowerBound : columnRange.lowerBound - 1
            guard source >= 0 else { return false }
            for column in columnRange where column != source {
                for row in rowRange { copyCell(from: NoteTableCell(row: row, column: source), to: NoteTableCell(row: row, column: column)) }
            }
        }
        normalize()
        return self != before
    }

    private mutating func copyCell(from source: NoteTableCell, to target: NoteTableCell) {
        guard !isCovered(target) else { return }
        let origin = anchor(of: source)
        guard origin != target, !span(of: origin).contains(target) else { return }
        rows[target.row][target.column] = rows[origin.row][origin.column]
        cellColors[target] = cellColors[origin]
    }

    func slice(rows rowRange: ClosedRange<Int>, columns columnRange: ClosedRange<Int>) -> NoteTable {
        let lastRow = max(0, rowCount - 1), lastColumn = max(0, columnCount - 1)
        let rowsIn = min(max(0, rowRange.lowerBound), lastRow)...min(max(0, rowRange.upperBound), lastRow)
        let columnsIn = min(max(0, columnRange.lowerBound), lastColumn)...min(max(0, columnRange.upperBound), lastColumn)
        var result = NoteTable(rows: rowsIn.map { row in columnsIn.map { cell(row, $0) ?? NoteText() } },
                               headerRow: headerRow && rowsIn.lowerBound == 0, headerColumn: headerColumn && columnsIn.lowerBound == 0)
        result.alignments = columnsIn.map { alignments.indices.contains($0) ? alignments[$0] : nil }
        result.columnWidths = columnsIn.map { columnWidths.indices.contains($0) ? columnWidths[$0] : nil }
        result.merges = merges.compactMap { merge in
            guard rowsIn.contains(merge.row), columnsIn.contains(merge.column) else { return nil }
            return NoteTableMerge(row: merge.row - rowsIn.lowerBound, column: merge.column - columnsIn.lowerBound,
                                  rowSpan: min(merge.lastRow, rowsIn.upperBound) - merge.row + 1,
                                  columnSpan: min(merge.lastColumn, columnsIn.upperBound) - merge.column + 1)
        }
        for (cell, style) in cellColors where rowsIn.contains(cell.row) && columnsIn.contains(cell.column) {
            result.cellColors[NoteTableCell(row: cell.row - rowsIn.lowerBound, column: cell.column - columnsIn.lowerBound)] = style
        }
        result.normalize()
        return result
    }

    @discardableResult
    mutating func paste(_ source: NoteTable, at origin: NoteTableCell) -> (rows: ClosedRange<Int>, columns: ClosedRange<Int>) {
        normalize()
        var source = source
        source.normalize()
        let top = max(0, origin.row), left = max(0, origin.column)
        let rowRange = top...(top + source.rowCount - 1), columnRange = left...(left + source.columnCount - 1)
        if columnRange.upperBound >= columnCount { insertColumns(at: columnCount, count: columnRange.upperBound - columnCount + 1) }
        if rowRange.upperBound >= rowCount { insertRows(at: rowCount, count: rowRange.upperBound - rowCount + 1) }
        merges.removeAll { $0.intersects(rows: rowRange, columns: columnRange) }
        for row in 0..<source.rowCount {
            for column in 0..<source.columnCount {
                let target = NoteTableCell(row: top + row, column: left + column)
                rows[target.row][target.column] = source.rows[row][column]
                cellColors[target] = source.cellColors[NoteTableCell(row: row, column: column)]
            }
        }
        merges += source.merges.map { NoteTableMerge(row: $0.row + top, column: $0.column + left, rowSpan: $0.rowSpan, columnSpan: $0.columnSpan) }
        normalize()
        return (rowRange, columnRange)
    }

    func isRowEmpty(_ row: Int) -> Bool {
        guard rows.indices.contains(row) else { return false }
        return rows[row].allSatisfy(\.isEmpty) && !merges.contains { $0.rows.contains(row) }
    }

    func isColumnEmpty(_ column: Int) -> Bool {
        guard column >= 0, column < columnCount else { return false }
        return rows.allSatisfy { !$0.indices.contains(column) || $0[column].isEmpty } && !merges.contains { $0.columns.contains(column) }
    }

    var trailingEmptyRows: Int {
        var count = 0
        while count < rowCount - 1, isRowEmpty(rowCount - 1 - count) { count += 1 }
        return count
    }

    var trailingEmptyColumns: Int {
        var count = 0
        while count < columnCount - 1, isColumnEmpty(columnCount - 1 - count) { count += 1 }
        return count
    }

    @discardableResult
    mutating func resize(rows targetRows: Int, columns targetColumns: Int) -> Bool {
        normalize()
        let before = self
        let minimumRows = rowCount - trailingEmptyRows, minimumColumns = columnCount - trailingEmptyColumns
        let rowGoal = max(max(1, minimumRows), targetRows), columnGoal = max(max(1, minimumColumns), targetColumns)
        if columnGoal > columnCount { insertColumns(at: columnCount, count: columnGoal - columnCount) }
        if columnGoal < columnCount { removeColumns(columnGoal..<columnCount) }
        if rowGoal > rowCount { insertRows(at: rowCount, count: rowGoal - rowCount) }
        if rowGoal < rowCount { removeRows(rowGoal..<rowCount) }
        return self != before
    }

    mutating func normalizeSpans() {
        let rowLimit = rows.count, columnLimit = columnCount
        if !cellColors.isEmpty, cellColors.keys.contains(where: { $0.row < 0 || $0.column < 0 || $0.row >= rowLimit || $0.column >= columnLimit }) {
            cellColors = cellColors.filter { $0.key.row >= 0 && $0.key.column >= 0 && $0.key.row < rowLimit && $0.key.column < columnLimit }
        }
        guard !merges.isEmpty else { return }
        var occupied = Set<NoteTableCell>()
        var kept: [NoteTableMerge] = []
        for merge in merges.sorted(by: { ($0.row, $0.column) < ($1.row, $1.column) }) {
            guard merge.row >= 0, merge.column >= 0, merge.row < rowLimit, merge.column < columnLimit else { continue }
            var clipped = merge
            clipped.rowSpan = min(max(1, merge.rowSpan), rowLimit - merge.row)
            clipped.columnSpan = min(max(1, merge.columnSpan), columnLimit - merge.column)
            guard clipped.cellCount > 1 else { continue }
            let cells = clipped.cells
            guard cells.allSatisfy({ !occupied.contains($0) }),
                  cells.allSatisfy({ $0 == clipped.anchor || rows[$0.row][$0.column].isEmpty }) else { continue }
            occupied.formUnion(cells)
            kept.append(clipped)
        }
        if kept != merges { merges = kept }
        if !cellColors.isEmpty {
            for merge in kept {
                for cell in merge.cells where cell != merge.anchor && cellColors[cell] != nil { cellColors[cell] = nil }
            }
        }
    }

    mutating func insertRows(at index: Int, count: Int, copying source: Int? = nil) {
        normalize()
        guard count > 0 else { return }
        let position = min(max(0, index), rowCount)
        let columns = columnCount
        let template = source.flatMap { rows.indices.contains($0) ? $0 : nil }
        let inherited: [NoteColorStyle?] = (0..<columns).map { template == nil ? uniformColor(column: $0) : nil }
        let fresh = template.map { rows[$0] } ?? Array(repeating: NoteText(), count: columns)
        rows.insert(contentsOf: Array(repeating: fresh, count: count), at: position)
        var colors: [NoteTableCell: NoteColorStyle] = [:]
        for (cell, style) in cellColors {
            colors[NoteTableCell(row: cell.row >= position ? cell.row + count : cell.row, column: cell.column)] = style
        }
        for offset in 0..<count {
            for column in 0..<columns {
                let target = NoteTableCell(row: position + offset, column: column)
                if let template { colors[target] = cellColors[NoteTableCell(row: template, column: column)] } else { colors[target] = inherited[column] }
            }
        }
        cellColors = colors
        var updated: [NoteTableMerge] = []
        for var merge in merges {
            let copies = template != nil && merge.rowSpan == 1 && merge.row == template
            if position <= merge.row { merge.row += count } else if position <= merge.lastRow { merge.rowSpan += count }
            updated.append(merge)
            if copies {
                for offset in 0..<count {
                    updated.append(NoteTableMerge(row: position + offset, column: merge.column, rowSpan: 1, columnSpan: merge.columnSpan))
                }
            }
        }
        merges = updated
        clearCovered(rows: position..<(position + count), columns: 0..<columns)
        normalize()
    }

    @discardableResult
    mutating func removeRows(_ range: Range<Int>) -> Bool {
        normalize()
        let lower = max(0, range.lowerBound), upper = min(rowCount, range.upperBound)
        guard lower < upper, upper - lower < rowCount else { return false }
        let count = upper - lower
        for merge in merges where merge.row >= lower && merge.row < upper && merge.lastRow >= upper {
            rows[upper][merge.column] = rows[merge.row][merge.column]
            cellColors[NoteTableCell(row: upper, column: merge.column)] = cellColors[merge.anchor]
        }
        rows.removeSubrange(lower..<upper)
        var colors: [NoteTableCell: NoteColorStyle] = [:]
        for (cell, style) in cellColors where cell.row < lower || cell.row >= upper {
            colors[NoteTableCell(row: cell.row >= upper ? cell.row - count : cell.row, column: cell.column)] = style
        }
        cellColors = colors
        merges = merges.compactMap { merge in
            let kept = merge.rows.filter { $0 < lower || $0 >= upper }.count
            guard kept > 0 else { return nil }
            var next = merge
            next.row = merge.row < lower ? merge.row : (merge.row >= upper ? merge.row - count : lower)
            next.rowSpan = kept
            return next
        }
        normalize()
        return true
    }

    mutating func reorderRows(_ newIndex: (Int) -> Int) {
        normalize()
        var reordered = rows
        for (old, row) in rows.enumerated() { reordered[newIndex(old)] = row }
        rows = reordered
        var colors: [NoteTableCell: NoteColorStyle] = [:]
        for (cell, style) in cellColors { colors[NoteTableCell(row: newIndex(cell.row), column: cell.column)] = style }
        cellColors = colors
        var kept: [NoteTableMerge] = []
        for merge in merges {
            let mapped = merge.rows.map(newIndex)
            guard let low = mapped.min(), let high = mapped.max(), high - low + 1 == merge.rowSpan else { continue }
            let anchorRow = newIndex(merge.row)
            if anchorRow != low { moveContent(from: NoteTableCell(row: anchorRow, column: merge.column), to: NoteTableCell(row: low, column: merge.column)) }
            var next = merge
            next.row = low
            kept.append(next)
        }
        merges = kept
        normalize()
    }

    mutating func insertColumns(at index: Int, count: Int, copying source: Int? = nil) {
        normalize()
        guard count > 0 else { return }
        let position = min(max(0, index), columnCount)
        let template = source.flatMap { $0 >= 0 && $0 < columnCount ? $0 : nil }
        let inherited: [NoteColorStyle?] = (0..<rowCount).map { template == nil ? uniformColor(row: $0) : nil }
        for row in rows.indices {
            let value = template.map { rows[row][$0] } ?? NoteText()
            rows[row].insert(contentsOf: Array(repeating: value, count: count), at: position)
        }
        alignments.insert(contentsOf: Array(repeating: template.flatMap { alignments[$0] }, count: count), at: position)
        columnWidths.insert(contentsOf: Array(repeating: template.flatMap { columnWidths[$0] }, count: count), at: position)
        var colors: [NoteTableCell: NoteColorStyle] = [:]
        for (cell, style) in cellColors {
            colors[NoteTableCell(row: cell.row, column: cell.column >= position ? cell.column + count : cell.column)] = style
        }
        for offset in 0..<count {
            for row in rows.indices {
                let target = NoteTableCell(row: row, column: position + offset)
                if let template { colors[target] = cellColors[NoteTableCell(row: row, column: template)] } else { colors[target] = inherited[row] }
            }
        }
        cellColors = colors
        var updated: [NoteTableMerge] = []
        for var merge in merges {
            let copies = template != nil && merge.columnSpan == 1 && merge.column == template
            if position <= merge.column { merge.column += count } else if position <= merge.lastColumn { merge.columnSpan += count }
            updated.append(merge)
            if copies {
                for offset in 0..<count {
                    updated.append(NoteTableMerge(row: merge.row, column: position + offset, rowSpan: merge.rowSpan, columnSpan: 1))
                }
            }
        }
        merges = updated
        clearCovered(rows: 0..<rowCount, columns: position..<(position + count))
        normalize()
    }

    @discardableResult
    mutating func removeColumns(_ range: Range<Int>) -> Bool {
        normalize()
        let lower = max(0, range.lowerBound), upper = min(columnCount, range.upperBound)
        guard lower < upper, upper - lower < columnCount else { return false }
        let count = upper - lower
        for merge in merges where merge.column >= lower && merge.column < upper && merge.lastColumn >= upper {
            rows[merge.row][upper] = rows[merge.row][merge.column]
            cellColors[NoteTableCell(row: merge.row, column: upper)] = cellColors[merge.anchor]
        }
        for row in rows.indices { rows[row].removeSubrange(lower..<upper) }
        alignments.removeSubrange(lower..<upper)
        columnWidths.removeSubrange(lower..<upper)
        var colors: [NoteTableCell: NoteColorStyle] = [:]
        for (cell, style) in cellColors where cell.column < lower || cell.column >= upper {
            colors[NoteTableCell(row: cell.row, column: cell.column >= upper ? cell.column - count : cell.column)] = style
        }
        cellColors = colors
        merges = merges.compactMap { merge in
            let kept = merge.columns.filter { $0 < lower || $0 >= upper }.count
            guard kept > 0 else { return nil }
            var next = merge
            next.column = merge.column < lower ? merge.column : (merge.column >= upper ? merge.column - count : lower)
            next.columnSpan = kept
            return next
        }
        normalize()
        return true
    }

    mutating func reorderColumns(_ newIndex: (Int) -> Int) {
        normalize()
        let columns = columnCount
        for row in rows.indices {
            var reordered = rows[row]
            for (old, value) in rows[row].enumerated() { reordered[newIndex(old)] = value }
            rows[row] = reordered
        }
        var nextAlignments = alignments, nextWidths = columnWidths
        for old in 0..<columns {
            nextAlignments[newIndex(old)] = alignments[old]
            nextWidths[newIndex(old)] = columnWidths[old]
        }
        alignments = nextAlignments
        columnWidths = nextWidths
        var colors: [NoteTableCell: NoteColorStyle] = [:]
        for (cell, style) in cellColors { colors[NoteTableCell(row: cell.row, column: newIndex(cell.column))] = style }
        cellColors = colors
        var kept: [NoteTableMerge] = []
        for merge in merges {
            let mapped = merge.columns.map(newIndex)
            guard let low = mapped.min(), let high = mapped.max(), high - low + 1 == merge.columnSpan else { continue }
            let anchorColumn = newIndex(merge.column)
            if anchorColumn != low { moveContent(from: NoteTableCell(row: merge.row, column: anchorColumn), to: NoteTableCell(row: merge.row, column: low)) }
            var next = merge
            next.column = low
            kept.append(next)
        }
        merges = kept
        normalize()
    }

    private mutating func moveContent(from source: NoteTableCell, to target: NoteTableCell) {
        rows[target.row][target.column] = rows[source.row][source.column]
        rows[source.row][source.column] = NoteText()
        cellColors[target] = cellColors[source]
        cellColors[source] = nil
    }

    private mutating func clearCovered(rows rowRange: Range<Int>, columns columnRange: Range<Int>) {
        guard !merges.isEmpty else { return }
        for merge in merges {
            for cell in merge.cells where cell != merge.anchor && rowRange.contains(cell.row) && columnRange.contains(cell.column) {
                guard rows.indices.contains(cell.row), rows[cell.row].indices.contains(cell.column) else { continue }
                rows[cell.row][cell.column] = NoteText()
                cellColors[cell] = nil
            }
        }
    }
}

enum NoteTableReference {
    static func columnName(_ index: Int) -> String {
        var value = max(0, index) + 1
        var letters: [Character] = []
        while value > 0 {
            let remainder = (value - 1) % 26
            letters.append(Character(UnicodeScalar(UInt8(65 + remainder))))
            value = (value - 1) / 26
        }
        return String(letters.reversed())
    }

    static func columnIndex<S: StringProtocol>(_ name: S) -> Int? {
        guard !name.isEmpty, name.count <= 3 else { return nil }
        var value = 0
        for scalar in name.unicodeScalars {
            let code = Int(scalar.value)
            let letter: Int
            if code >= 65 && code <= 90 { letter = code - 64 } else if code >= 97 && code <= 122 { letter = code - 96 } else { return nil }
            value = value * 26 + letter
        }
        return value - 1
    }

    static func cellName(_ cell: NoteTableCell) -> String {
        columnName(cell.column) + String(cell.row + 1)
    }

    static func rangeName(rows: ClosedRange<Int>, columns: ClosedRange<Int>) -> String {
        let start = cellName(NoteTableCell(row: rows.lowerBound, column: columns.lowerBound))
        if rows.count == 1 && columns.count == 1 { return start }
        return start + ":" + cellName(NoteTableCell(row: rows.upperBound, column: columns.upperBound))
    }

    static func columnsName(_ columns: ClosedRange<Int>) -> String {
        columnName(columns.lowerBound) + ":" + columnName(columns.upperBound)
    }

    static func rowsName(_ rows: ClosedRange<Int>) -> String {
        String(rows.lowerBound + 1) + ":" + String(rows.upperBound + 1)
    }

    private enum Part {
        case cell(NoteTableCell)
        case column(Int)
        case row(Int)
    }

    private static func part<S: StringProtocol>(_ text: S) -> Part? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let letters = trimmed.prefix(while: { $0.isASCII && $0.isLetter })
        let digits = trimmed.dropFirst(letters.count)
        guard digits.allSatisfy({ $0.isASCII && $0.isNumber }), digits.count <= 6 else { return nil }
        if letters.isEmpty {
            guard let number = Int(digits), number >= 1 else { return nil }
            return .row(number - 1)
        }
        guard let column = columnIndex(letters) else { return nil }
        if digits.isEmpty { return .column(column) }
        guard let number = Int(digits), number >= 1 else { return nil }
        return .cell(NoteTableCell(row: number - 1, column: column))
    }

    static func range<S: StringProtocol>(_ text: S, rowCount: Int, columnCount: Int) -> (rows: ClosedRange<Int>, columns: ClosedRange<Int>)? {
        guard rowCount > 0, columnCount > 0 else { return nil }
        let pieces = text.split(separator: ":", omittingEmptySubsequences: false)
        guard pieces.count == 1 || pieces.count == 2, let first = part(pieces[0]) else { return nil }
        let second = pieces.count == 2 ? part(pieces[1]) : first
        guard let second else { return nil }
        let rows: ClosedRange<Int>, columns: ClosedRange<Int>
        switch (first, second) {
        case (.cell(let a), .cell(let b)):
            rows = min(a.row, b.row)...max(a.row, b.row)
            columns = min(a.column, b.column)...max(a.column, b.column)
        case (.column(let a), .column(let b)) where pieces.count == 2:
            rows = 0...(rowCount - 1)
            columns = min(a, b)...max(a, b)
        case (.row(let a), .row(let b)) where pieces.count == 2:
            rows = min(a, b)...max(a, b)
            columns = 0...(columnCount - 1)
        default:
            return nil
        }
        guard rows.lowerBound < rowCount, columns.lowerBound < columnCount else { return nil }
        return (rows.clamped(to: 0...(rowCount - 1)), columns.clamped(to: 0...(columnCount - 1)))
    }
}

extension NoteTable {
    var mergeAttribute: String? {
        guard !merges.isEmpty else { return nil }
        return merges.map { NoteTableReference.rangeName(rows: $0.rows, columns: $0.columns) }.joined(separator: ",")
    }

    var colorsAttribute: String? {
        guard !cellColors.isEmpty else { return nil }
        let covered = coveredCells
        var done = Set<NoteTableCell>()
        var items: [String] = []
        let columnStyles = (0..<columnCount).map { uniformColor(column: $0) }
        var column = 0
        while column < columnCount {
            guard let style = columnStyles[column] else { column += 1; continue }
            var end = column
            while end + 1 < columnCount, columnStyles[end + 1] == style { end += 1 }
            items.append(NoteTableReference.columnsName(column...end) + "=" + NoteMDColor.name(style))
            for index in column...end { for row in 0..<rowCount { done.insert(NoteTableCell(row: row, column: index)) } }
            column = end + 1
        }
        func finished(_ row: Int) -> Bool { (0..<columnCount).allSatisfy { done.contains(NoteTableCell(row: row, column: $0)) } }
        let rowStyles = (0..<rowCount).map { uniformColor(row: $0) }
        var row = 0
        while row < rowCount {
            guard let style = rowStyles[row], !finished(row) else { row += 1; continue }
            var end = row
            while end + 1 < rowCount, rowStyles[end + 1] == style, !finished(end + 1) { end += 1 }
            items.append(NoteTableReference.rowsName(row...end) + "=" + NoteMDColor.name(style))
            for index in row...end { for column in 0..<columnCount { done.insert(NoteTableCell(row: index, column: column)) } }
            row = end + 1
        }
        for row in 0..<rowCount {
            var column = 0
            while column < columnCount {
                let cell = NoteTableCell(row: row, column: column)
                guard !done.contains(cell), !covered.contains(cell), let style = cellColors[cell] else { column += 1; continue }
                var end = column
                while end + 1 < columnCount {
                    let next = NoteTableCell(row: row, column: end + 1)
                    guard !done.contains(next), !covered.contains(next), cellColors[next] == style else { break }
                    end += 1
                }
                items.append(NoteTableReference.rangeName(rows: row...row, columns: column...end) + "=" + NoteMDColor.name(style))
                column = end + 1
            }
        }
        return items.isEmpty ? nil : items.joined(separator: ",")
    }

    mutating func applyMergeAttribute(_ value: String) {
        normalize()
        for item in value.split(separator: ",") {
            guard let range = NoteTableReference.range(item, rowCount: rowCount, columnCount: columnCount),
                  range.rows.count * range.columns.count > 1 else { continue }
            merges.append(NoteTableMerge(rows: range.rows, columns: range.columns))
        }
        normalize()
    }

    mutating func applyColorsAttribute(_ value: String) {
        normalize()
        for item in value.split(separator: ",") {
            guard let equals = item.lastIndex(of: "="),
                  let style = NoteMDColor.style(item[item.index(after: equals)...].trimmingCharacters(in: .whitespaces)),
                  let range = NoteTableReference.range(item[..<equals], rowCount: rowCount, columnCount: columnCount) else { continue }
            for row in range.rows { for column in range.columns { cellColors[NoteTableCell(row: row, column: column)] = style } }
        }
        normalize()
    }
}
