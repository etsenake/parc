import Foundation

package struct EaselTableCoordinate: Hashable {
    package var row: Int
    package var column: Int

    package init(row: Int, column: Int) {
        self.row = row
        self.column = column
    }
}

package struct EaselTableRange: Hashable {
    package var rows: ClosedRange<Int>
    package var columns: ClosedRange<Int>

    package init(rows: ClosedRange<Int>, columns: ClosedRange<Int>) {
        self.rows = rows
        self.columns = columns
    }

    package init(_ cell: EaselTableCoordinate) {
        rows = cell.row...cell.row
        columns = cell.column...cell.column
    }

    package init(_ anchor: EaselTableCoordinate, _ head: EaselTableCoordinate) {
        rows = min(anchor.row, head.row)...max(anchor.row, head.row)
        columns = min(anchor.column, head.column)...max(anchor.column, head.column)
    }

    package var topLeft: EaselTableCoordinate { EaselTableCoordinate(row: rows.lowerBound, column: columns.lowerBound) }
    package var cellCount: Int { rows.count * columns.count }
    package var isSingleCell: Bool { rows.count == 1 && columns.count == 1 }

    package func contains(_ cell: EaselTableCoordinate) -> Bool { rows.contains(cell.row) && columns.contains(cell.column) }
    package func intersects(_ other: EaselTableRange) -> Bool { rows.overlaps(other.rows) && columns.overlaps(other.columns) }
    package var cells: [EaselTableCoordinate] { rows.flatMap { row in columns.map { EaselTableCoordinate(row: row, column: $0) } } }
}

package struct EaselTableMerge: Codable, Hashable {
    package var row: Int
    package var column: Int
    package var rowSpan: Int
    package var columnSpan: Int

    package init(row: Int, column: Int, rowSpan: Int, columnSpan: Int) {
        self.row = row
        self.column = column
        self.rowSpan = rowSpan
        self.columnSpan = columnSpan
    }

    package init(_ range: EaselTableRange) {
        self.init(row: range.rows.lowerBound, column: range.columns.lowerBound,
                  rowSpan: range.rows.count, columnSpan: range.columns.count)
    }

    package var anchor: EaselTableCoordinate { EaselTableCoordinate(row: row, column: column) }
    package var range: EaselTableRange {
        EaselTableRange(rows: row...(row + max(1, rowSpan) - 1), columns: column...(column + max(1, columnSpan) - 1))
    }
}

package struct EaselTableCell: Codable, Equatable {
    package var text: String
    package var richText: EaselRichText?
    package var fill: String?

    package init(text: String = "", richText: EaselRichText? = nil, fill: String? = nil) {
        self.text = text
        self.richText = richText
        self.fill = fill
    }

    package var isBlank: Bool { text.isEmpty && richText == nil && fill == nil }

    private enum CodingKeys: String, CodingKey { case text, richText, fill }

    package init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
        richText = try container.decodeIfPresent(EaselRichText.self, forKey: .richText)
        fill = try container.decodeIfPresent(String.self, forKey: .fill)
    }

    package func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if !text.isEmpty { try container.encode(text, forKey: .text) }
        try container.encodeIfPresent(richText, forKey: .richText)
        try container.encodeIfPresent(fill, forKey: .fill)
    }
}

package enum EaselTableStep: Equatable {
    case cell(EaselTableCoordinate)
    case appendRow
    case none
}

package enum EaselTableDirection: CaseIterable {
    case up, down, left, right
}

package enum EaselTableAxis {
    case rows, columns
}

package struct EaselTable: Codable, Equatable {
    package static let maximumRows = 100
    package static let maximumColumns = 100
    package static let maximumCells = 10_000
    package static let maximumPastedCells = 500
    package static let maximumCellBytes = 65_536
    package static let maximumTextBytes = 1_048_576
    package static let minimumColumnWidth = 48.0
    package static let minimumRowHeight = 24.0
    package static let maximumLength = 8_000.0
    package static let defaultColumnWidth = 140.0
    package static let defaultRowHeight = 36.0
    package static let defaultColumns = 3
    package static let defaultRows = 3

    package var columnWidths: [Double]
    package var rowHeights: [Double]
    package var cells: [[EaselTableCell]]
    package var merges: [EaselTableMerge]

    package init(columnWidths: [Double], rowHeights: [Double], cells: [[EaselTableCell]]? = nil, merges: [EaselTableMerge] = []) {
        self.columnWidths = columnWidths
        self.rowHeights = rowHeights
        self.cells = cells ?? Array(repeating: Array(repeating: EaselTableCell(), count: columnWidths.count), count: rowHeights.count)
        self.merges = merges
    }

    private enum CodingKeys: String, CodingKey { case columnWidths, rowHeights, cells, merges }

    package init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        columnWidths = try container.decode([Double].self, forKey: .columnWidths)
        rowHeights = try container.decode([Double].self, forKey: .rowHeights)
        cells = try container.decode([[EaselTableCell]].self, forKey: .cells)
        merges = try container.decodeIfPresent([EaselTableMerge].self, forKey: .merges) ?? []
    }

    package func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(columnWidths, forKey: .columnWidths)
        try container.encode(rowHeights, forKey: .rowHeights)
        try container.encode(cells, forKey: .cells)
        if !merges.isEmpty { try container.encode(merges, forKey: .merges) }
    }

    package static func blank(columns: Int, rows: Int, columnWidth: Double = defaultColumnWidth,
                      rowHeight: Double = defaultRowHeight) -> EaselTable {
        let columnCount = min(max(1, columns), maximumColumns)
        let rowCount = min(max(1, rows), maximumRows, maximumCells / columnCount)
        return EaselTable(columnWidths: Array(repeating: columnWidth, count: columnCount),
                          rowHeights: Array(repeating: rowHeight, count: rowCount))
    }

    package var rowCount: Int { rowHeights.count }
    package var columnCount: Int { columnWidths.count }
    package var width: Double { columnWidths.reduce(0, +) }
    package var height: Double { rowHeights.reduce(0, +) }
    package var all: EaselTableRange { EaselTableRange(rows: 0...max(0, rowCount - 1), columns: 0...max(0, columnCount - 1)) }

    package static func isHex(_ value: String) -> Bool {
        let scalars = Array(value.unicodeScalars)
        return scalars.count == 7 && scalars[0] == "#" && scalars.dropFirst().allSatisfy {
            ("0"..."9").contains($0) || ("a"..."f").contains($0) || ("A"..."F").contains($0)
        }
    }

    package func validate() throws {
        let rowCount = rowHeights.count, columnCount = columnWidths.count
        guard (1...Self.maximumRows).contains(rowCount), (1...Self.maximumColumns).contains(columnCount),
              rowCount * columnCount <= Self.maximumCells, cells.count == rowCount,
              cells.allSatisfy({ $0.count == columnCount }),
              (columnWidths + rowHeights).allSatisfy({ $0.isFinite && $0 >= 1 && $0 <= Self.maximumLength }),
              merges.count <= Self.maximumCells else { throw EaselStoreError.invalidDocument("table grid") }
        var bytes = 0
        for row in cells {
            for cell in row {
                let size = cell.text.utf8.count
                bytes += size
                guard size <= Self.maximumCellBytes, cell.fill.map(Self.isHex) != false else {
                    throw EaselStoreError.invalidDocument("table cell")
                }
                try cell.richText?.validate(text: cell.text)
            }
        }
        guard bytes <= Self.maximumTextBytes else { throw EaselStoreError.tableTooLarge }
        var covered = Set<EaselTableCoordinate>()
        for merge in merges {
            guard merge.row >= 0, merge.row < rowCount, merge.column >= 0, merge.column < columnCount,
                  merge.rowSpan >= 1, merge.rowSpan <= rowCount - merge.row,
                  merge.columnSpan >= 1, merge.columnSpan <= columnCount - merge.column,
                  merge.rowSpan > 1 || merge.columnSpan > 1 else { throw EaselStoreError.invalidDocument("table merge") }
            for cell in merge.range.cells {
                guard covered.insert(cell).inserted else { throw EaselStoreError.invalidDocument("overlapping table merges") }
                if cell != merge.anchor, !cells[cell.row][cell.column].isBlank {
                    throw EaselStoreError.invalidDocument("content hidden under a table merge")
                }
            }
        }
    }

    package func contains(_ cell: EaselTableCoordinate) -> Bool {
        cell.row >= 0 && cell.row < rowCount && cell.column >= 0 && cell.column < columnCount
    }

    package func cell(_ cell: EaselTableCoordinate) -> EaselTableCell? {
        guard contains(cell), cells.indices.contains(cell.row), cells[cell.row].indices.contains(cell.column) else { return nil }
        return cells[cell.row][cell.column]
    }

    @discardableResult
    package mutating func update(_ cell: EaselTableCoordinate, _ change: (inout EaselTableCell) -> Void) -> Bool {
        guard contains(cell), cells.indices.contains(cell.row), cells[cell.row].indices.contains(cell.column) else { return false }
        change(&cells[cell.row][cell.column])
        return true
    }

    package func merge(containing cell: EaselTableCoordinate) -> EaselTableMerge? {
        merges.first { $0.range.contains(cell) }
    }

    package func anchor(of cell: EaselTableCoordinate) -> EaselTableCoordinate {
        merge(containing: cell)?.anchor ?? cell
    }

    package func span(of cell: EaselTableCoordinate) -> EaselTableRange {
        merge(containing: cell)?.range ?? EaselTableRange(cell)
    }

    package func isCovered(_ cell: EaselTableCoordinate) -> Bool {
        guard let merge = merge(containing: cell) else { return false }
        return merge.anchor != cell
    }

    package var coveredCells: Set<EaselTableCoordinate> {
        var result = Set<EaselTableCoordinate>()
        for merge in merges {
            for cell in merge.range.cells where cell != merge.anchor { result.insert(cell) }
        }
        return result
    }

    package var visibleCells: [EaselTableCoordinate] {
        let covered = coveredCells
        return all.cells.filter { !covered.contains($0) }
    }

    package func clamped(_ range: EaselTableRange) -> EaselTableRange? {
        guard rowCount > 0, columnCount > 0, range.rows.lowerBound < rowCount, range.columns.lowerBound < columnCount,
              range.rows.upperBound >= 0, range.columns.upperBound >= 0 else { return nil }
        return EaselTableRange(rows: max(0, range.rows.lowerBound)...min(range.rows.upperBound, rowCount - 1),
                               columns: max(0, range.columns.lowerBound)...min(range.columns.upperBound, columnCount - 1))
    }

    package func expanded(_ range: EaselTableRange) -> EaselTableRange {
        var result = range
        var changed = !merges.isEmpty
        while changed {
            changed = false
            for merge in merges where merge.range.intersects(result) {
                let area = merge.range
                let next = EaselTableRange(rows: min(result.rows.lowerBound, area.rows.lowerBound)...max(result.rows.upperBound, area.rows.upperBound),
                                           columns: min(result.columns.lowerBound, area.columns.lowerBound)...max(result.columns.upperBound, area.columns.upperBound))
                if next != result { result = next; changed = true }
            }
        }
        return result
    }

    private func uniformFill(_ cells: [EaselTableCoordinate]) -> String? {
        guard cells.count >= 2 else { return nil }
        var found: String?
        for cell in cells where !isCovered(cell) {
            guard let fill = self.cell(cell)?.fill, found == nil || found == fill else { return nil }
            found = fill
        }
        return found
    }

    private mutating func clearCovered() {
        for merge in merges {
            for cell in merge.range.cells where cell != merge.anchor && contains(cell) {
                cells[cell.row][cell.column] = EaselTableCell()
            }
        }
    }

    @discardableResult
    package mutating func insertRows(at index: Int, count: Int = 1, height: Double = defaultRowHeight) -> Bool {
        let position = min(max(0, index), rowCount)
        guard count > 0, rowCount + count <= Self.maximumRows, (rowCount + count) * columnCount <= Self.maximumCells,
              height.isFinite else { return false }
        let fresh = (0..<columnCount).map { column in
            EaselTableCell(fill: uniformFill((0..<rowCount).map { EaselTableCoordinate(row: $0, column: column) }))
        }
        cells.insert(contentsOf: Array(repeating: fresh, count: count), at: position)
        rowHeights.insert(contentsOf: Array(repeating: min(Self.maximumLength, max(Self.minimumRowHeight, height)), count: count), at: position)
        merges = merges.map { merge in
            var next = merge
            if position <= merge.row { next.row += count } else if position <= merge.range.rows.upperBound { next.rowSpan += count }
            return next
        }
        clearCovered()
        return true
    }

    @discardableResult
    package mutating func insertColumns(at index: Int, count: Int = 1, width: Double = defaultColumnWidth) -> Bool {
        let position = min(max(0, index), columnCount)
        guard count > 0, columnCount + count <= Self.maximumColumns, rowCount * (columnCount + count) <= Self.maximumCells,
              width.isFinite else { return false }
        let inherited = (0..<rowCount).map { row in
            uniformFill((0..<columnCount).map { EaselTableCoordinate(row: row, column: $0) })
        }
        for row in cells.indices {
            cells[row].insert(contentsOf: Array(repeating: EaselTableCell(fill: inherited[row]), count: count), at: position)
        }
        columnWidths.insert(contentsOf: Array(repeating: min(Self.maximumLength, max(Self.minimumColumnWidth, width)), count: count), at: position)
        merges = merges.map { merge in
            var next = merge
            if position <= merge.column { next.column += count } else if position <= merge.range.columns.upperBound { next.columnSpan += count }
            return next
        }
        clearCovered()
        return true
    }

    @discardableResult
    package mutating func removeRows(_ range: ClosedRange<Int>) -> Bool {
        let lower = max(0, range.lowerBound), upper = min(rowCount - 1, range.upperBound)
        guard lower <= upper, upper - lower + 1 < rowCount else { return false }
        let count = upper - lower + 1
        for merge in merges where merge.row >= lower && merge.row <= upper && merge.range.rows.upperBound > upper {
            cells[upper + 1][merge.column] = cells[merge.row][merge.column]
        }
        cells.removeSubrange(lower...upper)
        rowHeights.removeSubrange(lower...upper)
        merges = merges.compactMap { merge in
            let kept = merge.range.rows.filter { $0 < lower || $0 > upper }.count
            guard kept > 0 else { return nil }
            var next = merge
            next.row = merge.row < lower ? merge.row : (merge.row > upper ? merge.row - count : lower)
            next.rowSpan = kept
            return next.rowSpan > 1 || next.columnSpan > 1 ? next : nil
        }
        return true
    }

    @discardableResult
    package mutating func removeColumns(_ range: ClosedRange<Int>) -> Bool {
        let lower = max(0, range.lowerBound), upper = min(columnCount - 1, range.upperBound)
        guard lower <= upper, upper - lower + 1 < columnCount else { return false }
        let count = upper - lower + 1
        for merge in merges where merge.column >= lower && merge.column <= upper && merge.range.columns.upperBound > upper {
            cells[merge.row][upper + 1] = cells[merge.row][merge.column]
        }
        for row in cells.indices { cells[row].removeSubrange(lower...upper) }
        columnWidths.removeSubrange(lower...upper)
        merges = merges.compactMap { merge in
            let kept = merge.range.columns.filter { $0 < lower || $0 > upper }.count
            guard kept > 0 else { return nil }
            var next = merge
            next.column = merge.column < lower ? merge.column : (merge.column > upper ? merge.column - count : lower)
            next.columnSpan = kept
            return next.rowSpan > 1 || next.columnSpan > 1 ? next : nil
        }
        return true
    }

    private static func order(count: Int, moving block: ClosedRange<Int>, to destination: Int) -> [Int]? {
        guard block.lowerBound >= 0, block.upperBound < count, destination >= 0, destination <= count - block.count else { return nil }
        var rest = Array(0..<count).filter { !block.contains($0) }
        rest.insert(contentsOf: Array(block), at: destination)
        return rest
    }

    private func span(of merge: EaselTableMerge, along axis: EaselTableAxis) -> ClosedRange<Int> {
        axis == .rows ? merge.range.rows : merge.range.columns
    }

    package func keepsMerges(moving block: ClosedRange<Int>, to destination: Int, along axis: EaselTableAxis) -> Bool {
        let count = axis == .rows ? rowCount : columnCount
        guard let order = Self.order(count: count, moving: block, to: destination) else { return false }
        var position = [Int](repeating: 0, count: count)
        for (new, old) in order.enumerated() { position[old] = new }
        return merges.allSatisfy { merge in
            let lines = span(of: merge, along: axis)
            if lines.overlaps(block), !(block.contains(lines.lowerBound) && block.contains(lines.upperBound)) { return false }
            let mapped = lines.map { position[$0] }
            guard let low = mapped.min(), let high = mapped.max() else { return false }
            return high - low + 1 == lines.count && position[lines.lowerBound] == low
        }
    }

    package func destination(moving block: ClosedRange<Int>, by step: Int, along axis: EaselTableAxis) -> Int? {
        let count = axis == .rows ? rowCount : columnCount
        guard step != 0 else { return nil }
        var candidate = block.lowerBound + step
        while candidate >= 0, candidate <= count - block.count {
            if keepsMerges(moving: block, to: candidate, along: axis) { return candidate }
            candidate += step > 0 ? 1 : -1
        }
        return nil
    }

    package func nearestDestination(moving block: ClosedRange<Int>, to desired: Int, along axis: EaselTableAxis) -> Int {
        let count = axis == .rows ? rowCount : columnCount
        let limit = count - block.count
        guard limit >= 0 else { return block.lowerBound }
        let target = min(max(0, desired), limit)
        for distance in 0...limit {
            for candidate in [target - distance, target + distance] where candidate >= 0 && candidate <= limit {
                if candidate == block.lowerBound || keepsMerges(moving: block, to: candidate, along: axis) { return candidate }
            }
        }
        return block.lowerBound
    }

    @discardableResult
    package mutating func moveRows(_ block: ClosedRange<Int>, to destination: Int) -> Bool {
        guard keepsMerges(moving: block, to: destination, along: .rows),
              let order = Self.order(count: rowCount, moving: block, to: destination), order != Array(0..<rowCount) else { return false }
        var position = [Int](repeating: 0, count: rowCount)
        for (new, old) in order.enumerated() { position[old] = new }
        cells = order.map { cells[$0] }
        rowHeights = order.map { rowHeights[$0] }
        merges = merges.compactMap { merge in
            let mapped = merge.range.rows.map { position[$0] }
            guard let low = mapped.min(), let high = mapped.max(), high - low + 1 == merge.rowSpan, position[merge.row] == low else { return nil }
            var next = merge
            next.row = low
            return next
        }
        return true
    }

    @discardableResult
    package mutating func moveColumns(_ block: ClosedRange<Int>, to destination: Int) -> Bool {
        guard keepsMerges(moving: block, to: destination, along: .columns),
              let order = Self.order(count: columnCount, moving: block, to: destination), order != Array(0..<columnCount) else { return false }
        var position = [Int](repeating: 0, count: columnCount)
        for (new, old) in order.enumerated() { position[old] = new }
        cells = cells.map { row in order.map { row[$0] } }
        columnWidths = order.map { columnWidths[$0] }
        merges = merges.compactMap { merge in
            let mapped = merge.range.columns.map { position[$0] }
            guard let low = mapped.min(), let high = mapped.max(), high - low + 1 == merge.columnSpan, position[merge.column] == low else { return nil }
            var next = merge
            next.column = low
            return next
        }
        return true
    }

    @discardableResult
    package mutating func duplicateRows(_ block: ClosedRange<Int>) -> Bool {
        guard block.lowerBound >= 0, block.upperBound < rowCount,
              expanded(EaselTableRange(rows: block, columns: all.columns)).rows == block else { return false }
        let copies = Array(cells[block]), heights = Array(rowHeights[block])
        let copiedMerges = merges.filter { block.contains($0.row) && block.contains($0.range.rows.upperBound) }
        guard insertRows(at: block.upperBound + 1, count: block.count) else { return false }
        for (offset, row) in copies.enumerated() {
            cells[block.upperBound + 1 + offset] = row
            rowHeights[block.upperBound + 1 + offset] = heights[offset]
        }
        merges += copiedMerges.map { EaselTableMerge(row: $0.row + block.count, column: $0.column, rowSpan: $0.rowSpan, columnSpan: $0.columnSpan) }
        clearCovered()
        return true
    }

    @discardableResult
    package mutating func duplicateColumns(_ block: ClosedRange<Int>) -> Bool {
        guard block.lowerBound >= 0, block.upperBound < columnCount,
              expanded(EaselTableRange(rows: all.rows, columns: block)).columns == block else { return false }
        let copies = cells.map { Array($0[block]) }, widths = Array(columnWidths[block])
        let copiedMerges = merges.filter { block.contains($0.column) && block.contains($0.range.columns.upperBound) }
        guard insertColumns(at: block.upperBound + 1, count: block.count) else { return false }
        for row in cells.indices {
            for offset in 0..<block.count { cells[row][block.upperBound + 1 + offset] = copies[row][offset] }
        }
        for offset in 0..<block.count { columnWidths[block.upperBound + 1 + offset] = widths[offset] }
        merges += copiedMerges.map { EaselTableMerge(row: $0.row, column: $0.column + block.count, rowSpan: $0.rowSpan, columnSpan: $0.columnSpan) }
        clearCovered()
        return true
    }

    package func canMerge(_ range: EaselTableRange) -> Bool {
        guard clamped(range) == range else { return false }
        let area = expanded(range)
        return area.cellCount > 1 && !merges.contains { $0.range == area }
    }

    package func hasMerges(in range: EaselTableRange) -> Bool {
        merges.contains { $0.range.intersects(range) }
    }

    package func joinedText(_ range: EaselTableRange) -> String {
        expanded(range).cells.compactMap { cell in
            guard !isCovered(cell), let text = self.cell(cell)?.text,
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return text
        }.joined(separator: "\n")
    }

    @discardableResult
    package mutating func merge(_ range: EaselTableRange, content: EaselTableCell? = nil) -> EaselTableMerge? {
        guard canMerge(range) else { return nil }
        let area = expanded(range)
        let merged = EaselTableMerge(area)
        let fill = cells[merged.row][merged.column].fill
        merges.removeAll { $0.range.intersects(area) }
        for cell in area.cells where cell != merged.anchor { cells[cell.row][cell.column] = EaselTableCell() }
        if var content {
            content.fill = fill
            cells[merged.row][merged.column] = content
        }
        merges.append(merged)
        return merged
    }

    @discardableResult
    package mutating func unmerge(_ range: EaselTableRange) -> Bool {
        let before = merges.count
        merges.removeAll { $0.range.intersects(range) }
        return merges.count != before
    }

    @discardableResult
    package mutating func clearText(_ range: EaselTableRange) -> Bool {
        var changed = false
        for cell in expanded(range).cells where contains(cell) {
            guard !cells[cell.row][cell.column].text.isEmpty || cells[cell.row][cell.column].richText != nil else { continue }
            cells[cell.row][cell.column].text = ""
            cells[cell.row][cell.column].richText = nil
            changed = true
        }
        return changed
    }

    @discardableResult
    package mutating func setFill(_ fill: String?, in range: EaselTableRange) -> Bool {
        guard fill.map(Self.isHex) != false else { return false }
        var changed = false
        for cell in expanded(range).cells where contains(cell) && !isCovered(cell) && cells[cell.row][cell.column].fill != fill {
            cells[cell.row][cell.column].fill = fill
            changed = true
        }
        return changed
    }

    package func commonFill(_ range: EaselTableRange) -> String?? {
        var result: String??
        for cell in expanded(range).cells where contains(cell) && !isCovered(cell) {
            let fill = cells[cell.row][cell.column].fill
            if let known = result, known != fill { return .none }
            result = .some(fill)
        }
        return result ?? .some(nil)
    }

    @discardableResult
    package mutating func setWidth(_ width: Double, column: Int) -> Bool {
        guard columnWidths.indices.contains(column), width.isFinite else { return false }
        let value = min(Self.maximumLength, max(Self.minimumColumnWidth, width))
        guard value != columnWidths[column] else { return false }
        columnWidths[column] = value
        return true
    }

    @discardableResult
    package mutating func setHeight(_ height: Double, row: Int, minimum: Double = minimumRowHeight) -> Bool {
        guard rowHeights.indices.contains(row), height.isFinite else { return false }
        let value = min(Self.maximumLength, max(Self.minimumRowHeight, minimum.isFinite ? minimum : 0, height))
        guard value != rowHeights[row] else { return false }
        rowHeights[row] = value
        return true
    }

    package mutating func scaleColumns(toWidth target: Double) {
        let total = width
        guard target.isFinite, target > 0, total > 0 else { return }
        columnWidths = columnWidths.map { min(Self.maximumLength, max(Self.minimumColumnWidth, $0 * target / total)) }
    }

    package mutating func scaleRows(toHeight target: Double, minimums: [Double] = []) {
        let total = height
        guard target.isFinite, target > 0, total > 0 else { return }
        rowHeights = rowHeights.indices.map { index in
            let floor = minimums.indices.contains(index) && minimums[index].isFinite ? minimums[index] : 0
            return min(Self.maximumLength, max(Self.minimumRowHeight, floor, rowHeights[index] * target / total))
        }
    }

    package mutating func fitRows(minimums: [Double]) {
        for index in rowHeights.indices where minimums.indices.contains(index) && minimums[index].isFinite {
            rowHeights[index] = min(Self.maximumLength, max(Self.minimumRowHeight, rowHeights[index], minimums[index]))
        }
    }

    package func tab(from cell: EaselTableCoordinate, backward: Bool) -> EaselTableStep {
        let order = visibleCells
        guard let index = order.firstIndex(of: anchor(of: cell)) else { return .none }
        if backward { return index > 0 ? .cell(order[index - 1]) : .none }
        return index + 1 < order.count ? .cell(order[index + 1]) : .appendRow
    }

    package func step(from cell: EaselTableCoordinate, _ direction: EaselTableDirection) -> EaselTableCoordinate {
        guard contains(cell) else { return anchor(of: EaselTableCoordinate(row: 0, column: 0)) }
        let span = self.span(of: cell)
        let lane = (row: min(max(cell.row, span.rows.lowerBound), span.rows.upperBound),
                    column: min(max(cell.column, span.columns.lowerBound), span.columns.upperBound))
        switch direction {
        case .up:
            guard span.rows.lowerBound > 0 else { return anchor(of: cell) }
            return anchor(of: EaselTableCoordinate(row: span.rows.lowerBound - 1, column: lane.column))
        case .down:
            guard span.rows.upperBound + 1 < rowCount else { return anchor(of: cell) }
            return anchor(of: EaselTableCoordinate(row: span.rows.upperBound + 1, column: lane.column))
        case .left:
            guard span.columns.lowerBound > 0 else { return anchor(of: cell) }
            return anchor(of: EaselTableCoordinate(row: lane.row, column: span.columns.lowerBound - 1))
        case .right:
            guard span.columns.upperBound + 1 < columnCount else { return anchor(of: cell) }
            return anchor(of: EaselTableCoordinate(row: lane.row, column: span.columns.upperBound + 1))
        }
    }

    package func extended(_ head: EaselTableCoordinate, _ direction: EaselTableDirection) -> EaselTableCoordinate {
        var next = head
        switch direction {
        case .up: next.row -= 1
        case .down: next.row += 1
        case .left: next.column -= 1
        case .right: next.column += 1
        }
        next.row = min(max(0, next.row), max(0, rowCount - 1))
        next.column = min(max(0, next.column), max(0, columnCount - 1))
        return next
    }

    package func slice(_ range: EaselTableRange) -> EaselTable? {
        guard let area = clamped(range).map(expanded) else { return nil }
        var result = EaselTable(columnWidths: Array(columnWidths[area.columns]), rowHeights: Array(rowHeights[area.rows]),
                                cells: area.rows.map { Array(cells[$0][area.columns]) })
        result.merges = merges.compactMap { merge in
            guard area.contains(merge.anchor), area.contains(EaselTableCoordinate(row: merge.range.rows.upperBound, column: merge.range.columns.upperBound)) else { return nil }
            return EaselTableMerge(row: merge.row - area.rows.lowerBound, column: merge.column - area.columns.lowerBound,
                                   rowSpan: merge.rowSpan, columnSpan: merge.columnSpan)
        }
        return result
    }

    @discardableResult
    package mutating func paste(_ source: EaselTable, at origin: EaselTableCoordinate, filling target: EaselTableRange? = nil) -> EaselTableRange? {
        guard contains(origin), source.rowCount > 0, source.columnCount > 0 else { return nil }
        if source.rowCount == 1, source.columnCount == 1, let target, let area = clamped(target), !area.isSingleCell {
            let value = source.cells[0][0]
            for cell in area.cells where !isCovered(cell) {
                cells[cell.row][cell.column].text = value.text
                cells[cell.row][cell.column].richText = value.richText
                if let fill = value.fill { cells[cell.row][cell.column].fill = fill }
            }
            return area
        }
        let start = target.flatMap(clamped)?.topLeft ?? origin
        let neededColumns = min(Self.maximumColumns, max(columnCount, start.column + source.columnCount))
        let neededRows = min(Self.maximumRows, max(rowCount, start.row + source.rowCount), Self.maximumCells / max(1, neededColumns))
        if neededColumns > columnCount {
            let width = columnWidths.last ?? Self.defaultColumnWidth
            guard insertColumns(at: columnCount, count: neededColumns - columnCount, width: width) else { return nil }
        }
        if neededRows > rowCount {
            guard insertRows(at: rowCount, count: neededRows - rowCount) else { return nil }
        }
        guard start.row < rowCount, start.column < columnCount else { return nil }
        let area = EaselTableRange(rows: start.row...min(rowCount - 1, start.row + source.rowCount - 1),
                                   columns: start.column...min(columnCount - 1, start.column + source.columnCount - 1))
        unmerge(area)
        for cell in area.cells {
            let value = source.cells[cell.row - start.row][cell.column - start.column]
            cells[cell.row][cell.column].text = value.text
            cells[cell.row][cell.column].richText = value.richText
            if let fill = value.fill { cells[cell.row][cell.column].fill = fill }
        }
        for merge in source.merges {
            let placed = EaselTableMerge(row: merge.row + start.row, column: merge.column + start.column,
                                         rowSpan: merge.rowSpan, columnSpan: merge.columnSpan)
            guard area.contains(placed.anchor),
                  area.contains(EaselTableCoordinate(row: placed.range.rows.upperBound, column: placed.range.columns.upperBound)),
                  !merges.contains(where: { $0.range.intersects(placed.range) }) else { continue }
            merges.append(placed)
        }
        clearCovered()
        return area
    }
}

extension EaselTable {
    package var accessibilitySummary: String {
        let columns = columnCount == 1 ? "1 column" : "\(columnCount) columns"
        let rows = rowCount == 1 ? "1 row" : "\(rowCount) rows"
        let filled = visibleCells.filter { !(cell($0)?.text.isEmpty ?? true) }.count
        return columns + ", " + rows + (filled == 0 ? ", empty" : ", \(filled) filled")
    }

    package static func cellName(_ cell: EaselTableCoordinate) -> String {
        "row \(cell.row + 1), column \(cell.column + 1)"
    }
}
