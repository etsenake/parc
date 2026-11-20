import Foundation

struct NoteTableRect: Hashable {
    var rows: ClosedRange<Int>
    var columns: ClosedRange<Int>

    init(_ anchor: NoteTableCell, _ head: NoteTableCell) {
        rows = min(anchor.row, head.row)...max(anchor.row, head.row)
        columns = min(anchor.column, head.column)...max(anchor.column, head.column)
    }

    init(rows: ClosedRange<Int>, columns: ClosedRange<Int>) {
        self.rows = rows
        self.columns = columns
    }

    var topLeft: NoteTableCell { NoteTableCell(row: rows.lowerBound, column: columns.lowerBound) }
    var bottomRight: NoteTableCell { NoteTableCell(row: rows.upperBound, column: columns.upperBound) }
    var rowCount: Int { rows.count }
    var columnCount: Int { columns.count }
    var isSingleCell: Bool { rows.count == 1 && columns.count == 1 }

    func contains(_ cell: NoteTableCell) -> Bool {
        rows.contains(cell.row) && columns.contains(cell.column)
    }

    var cells: [NoteTableCell] {
        rows.flatMap { row in columns.map { NoteTableCell(row: row, column: $0) } }
    }

    func clamped(rows rowCount: Int, columns columnCount: Int) -> NoteTableRect? {
        guard rowCount > 0, columnCount > 0, rows.lowerBound < rowCount, columns.lowerBound < columnCount else { return nil }
        return NoteTableRect(rows: max(0, rows.lowerBound)...min(rows.upperBound, rowCount - 1),
                             columns: max(0, columns.lowerBound)...min(columns.upperBound, columnCount - 1))
    }
}

enum NoteTableDirection: Hashable {
    case up, down, left, right
}

enum NoteTableDestination: Hashable {
    case cell(NoteTableCell)
    case appendRow
    case exitBefore
    case exitAfter
    case stay
}

enum NoteTableNavigation {
    static func tab(from cell: NoteTableCell, rows: Int, columns: Int, backward: Bool) -> NoteTableDestination {
        guard rows > 0, columns > 0 else { return .stay }
        let index = cell.row * columns + cell.column
        if backward {
            guard index > 0 else { return .stay }
            return .cell(NoteTableCell(row: (index - 1) / columns, column: (index - 1) % columns))
        }
        guard index + 1 < rows * columns else { return .appendRow }
        return .cell(NoteTableCell(row: (index + 1) / columns, column: (index + 1) % columns))
    }

    static func step(from cell: NoteTableCell, _ direction: NoteTableDirection, rows: Int, columns: Int) -> NoteTableDestination {
        guard rows > 0, columns > 0 else { return .stay }
        switch direction {
        case .up:
            return cell.row > 0 ? .cell(NoteTableCell(row: cell.row - 1, column: cell.column)) : .exitBefore
        case .down:
            return cell.row + 1 < rows ? .cell(NoteTableCell(row: cell.row + 1, column: cell.column)) : .exitAfter
        case .left:
            if cell.column > 0 { return .cell(NoteTableCell(row: cell.row, column: cell.column - 1)) }
            return cell.row > 0 ? .cell(NoteTableCell(row: cell.row - 1, column: columns - 1)) : .exitBefore
        case .right:
            if cell.column + 1 < columns { return .cell(NoteTableCell(row: cell.row, column: cell.column + 1)) }
            return cell.row + 1 < rows ? .cell(NoteTableCell(row: cell.row + 1, column: 0)) : .exitAfter
        }
    }

    static func returnKey(from cell: NoteTableCell, rows: Int) -> NoteTableDestination {
        cell.row + 1 < rows ? .cell(NoteTableCell(row: cell.row + 1, column: cell.column)) : .exitAfter
    }

    static func moved(_ cell: NoteTableCell, _ direction: NoteTableDirection, rows: Int, columns: Int) -> NoteTableCell {
        var next = cell
        switch direction {
        case .up: next.row -= 1
        case .down: next.row += 1
        case .left: next.column -= 1
        case .right: next.column += 1
        }
        next.row = min(max(0, next.row), max(0, rows - 1))
        next.column = min(max(0, next.column), max(0, columns - 1))
        return next
    }
}

enum NoteTableChange: Hashable {
    case insertRows(at: Int, count: Int)
    case deleteRows(at: Int, count: Int)
    case moveRow(from: Int, to: Int)
    case insertColumns(at: Int, count: Int)
    case deleteColumns(at: Int, count: Int)
    case moveColumn(from: Int, to: Int)

    var isRowChange: Bool {
        switch self {
        case .insertRows, .deleteRows, .moveRow: return true
        default: return false
        }
    }

    func newRow(for old: Int) -> Int? {
        switch self {
        case .insertRows(let at, let count): return old >= at ? old + count : old
        case .deleteRows(let at, let count):
            if old < at { return old }
            return old >= at + count ? old - count : nil
        case .moveRow(let from, let to): return Self.moved(old, from: from, to: to)
        default: return old
        }
    }

    func newColumn(for old: Int) -> Int? {
        switch self {
        case .insertColumns(let at, let count): return old >= at ? old + count : old
        case .deleteColumns(let at, let count):
            if old < at { return old }
            return old >= at + count ? old - count : nil
        case .moveColumn(let from, let to): return Self.moved(old, from: from, to: to)
        default: return old
        }
    }

    func oldRow(for new: Int) -> Int? {
        switch self {
        case .insertRows(let at, let count):
            if new < at { return new }
            return new >= at + count ? new - count : nil
        case .deleteRows(let at, let count): return new >= at ? new + count : new
        case .moveRow(let from, let to): return Self.moved(new, from: to, to: from)
        default: return new
        }
    }

    func oldColumn(for new: Int) -> Int? {
        switch self {
        case .insertColumns(let at, let count):
            if new < at { return new }
            return new >= at + count ? new - count : nil
        case .deleteColumns(let at, let count): return new >= at ? new + count : new
        case .moveColumn(let from, let to): return Self.moved(new, from: to, to: from)
        default: return new
        }
    }

    func newCell(for old: NoteTableCell) -> NoteTableCell? {
        guard let row = newRow(for: old.row), let column = newColumn(for: old.column) else { return nil }
        return NoteTableCell(row: row, column: column)
    }

    private static func moved(_ index: Int, from: Int, to: Int) -> Int {
        if index == from { return to }
        if from < to, index > from, index <= to { return index - 1 }
        if to < from, index >= to, index < from { return index + 1 }
        return index
    }
}

enum NoteTableTransforms {
    static func apply(_ change: NoteTableChange, to table: inout NoteTable) {
        table.normalize()
        let columns = table.columnCount
        switch change {
        case .insertRows(let at, let count):
            let index = min(max(0, at), table.rowCount)
            table.rows.insert(contentsOf: Array(repeating: Array(repeating: NoteText(), count: columns), count: max(0, count)), at: index)
        case .deleteRows(let at, let count):
            let lower = min(max(0, at), table.rowCount), upper = min(table.rowCount, lower + max(0, count))
            guard upper - lower < table.rowCount else { return }
            table.rows.removeSubrange(lower..<upper)
        case .moveRow(let from, let to):
            guard table.rows.indices.contains(from), table.rows.indices.contains(to), from != to else { return }
            let row = table.rows.remove(at: from)
            table.rows.insert(row, at: to)
        case .insertColumns(let at, let count):
            let index = min(max(0, at), columns), amount = max(0, count)
            for row in table.rows.indices {
                table.rows[row].insert(contentsOf: Array(repeating: NoteText(), count: amount), at: index)
            }
            table.alignments.insert(contentsOf: Array(repeating: nil, count: amount), at: index)
            table.columnWidths.insert(contentsOf: Array(repeating: nil, count: amount), at: index)
        case .deleteColumns(let at, let count):
            let lower = min(max(0, at), columns), upper = min(columns, lower + max(0, count))
            guard upper - lower < columns else { return }
            for row in table.rows.indices { table.rows[row].removeSubrange(lower..<upper) }
            table.alignments.removeSubrange(lower..<upper)
            table.columnWidths.removeSubrange(lower..<upper)
        case .moveColumn(let from, let to):
            guard (0..<columns).contains(from), (0..<columns).contains(to), from != to else { return }
            for row in table.rows.indices {
                let cell = table.rows[row].remove(at: from)
                table.rows[row].insert(cell, at: to)
            }
            let alignment = table.alignments.remove(at: from)
            table.alignments.insert(alignment, at: to)
            let width = table.columnWidths.remove(at: from)
            table.columnWidths.insert(width, at: to)
        }
        table.normalize()
    }

    static func clear(_ rect: NoteTableRect, in table: inout NoteTable) {
        for row in rect.rows where table.rows.indices.contains(row) {
            for column in rect.columns where table.rows[row].indices.contains(column) { table.rows[row][column] = NoteText() }
        }
    }

    static func setWidths(_ widths: [Double?], in table: inout NoteTable) {
        table.normalize()
        for index in table.columnWidths.indices {
            table.columnWidths[index] = index < widths.count ? widths[index].map { max(NoteTableMetrics.minimumColumnWidth, $0.rounded()) } : nil
        }
    }

    static func grow(_ table: inout NoteTable, rows: Int, columns: Int) {
        table.normalize()
        if columns > table.columnCount { apply(.insertColumns(at: table.columnCount, count: columns - table.columnCount), to: &table) }
        if rows > table.rowCount { apply(.insertRows(at: table.rowCount, count: rows - table.rowCount), to: &table) }
    }

    @discardableResult
    static func paste(_ grid: [[NoteText]], into table: inout NoteTable, at origin: NoteTableCell,
                      filling target: NoteTableRect? = nil) -> NoteTableRect? {
        let height = grid.count, width = grid.map(\.count).max() ?? 0
        guard height > 0, width > 0 else { return nil }
        let start = target?.topLeft ?? origin
        if height == 1, width == 1, let target, !target.isSingleCell {
            for cell in target.cells where table.rows.indices.contains(cell.row) && table.rows[cell.row].indices.contains(cell.column) {
                table.rows[cell.row][cell.column] = grid[0][0]
            }
            return target
        }
        grow(&table, rows: start.row + height, columns: start.column + width)
        for (rowOffset, row) in grid.enumerated() {
            for column in 0..<width {
                table.rows[start.row + rowOffset][start.column + column] = column < row.count ? row[column] : NoteText()
            }
        }
        return NoteTableRect(rows: start.row...(start.row + height - 1), columns: start.column...(start.column + width - 1))
    }

    static func slice(_ rect: NoteTableRect, of table: NoteTable) -> [[NoteText]] {
        rect.rows.compactMap { row in
            table.rows.indices.contains(row)
                ? rect.columns.map { table.rows[row].indices.contains($0) ? table.rows[row][$0] : NoteText() }
                : nil
        }
    }

    static func isEmpty(_ rect: NoteTableRect, of table: NoteTable) -> Bool {
        slice(rect, of: table).allSatisfy { $0.allSatisfy(\.isEmpty) }
    }
}

enum NoteTableMetrics {
    static let minimumColumnWidth: Double = 48
    static let minimumSharedWidth: Double = 104
    static let defaultFixedWidth: Double = 160

    static func resolvedWidths(_ widths: [Double?], available: Double) -> [Double] {
        guard let lastUnset = widths.lastIndex(where: { $0 == nil }) else { return widths.map { max(minimumColumnWidth, $0 ?? 0) } }
        let fixed = widths.compactMap { $0.map { max(minimumColumnWidth, $0) } }
        let unset = widths.count - fixed.count
        let room = available - fixed.reduce(0, +)
        let share = max(minimumSharedWidth, room / Double(unset)).rounded(.down)
        let last = max(share, room - share * Double(unset - 1))
        return widths.enumerated().map { index, width in
            if let width { return max(minimumColumnWidth, width) }
            return index == lastUnset ? last : share
        }
    }

    static func resized(_ widths: [Double], column: Int, by delta: Double) -> [Double] {
        guard widths.indices.contains(column) else { return widths }
        var next = widths
        next[column] = max(minimumColumnWidth, (widths[column] + delta).rounded())
        return next
    }

    static func edges(_ sizes: [Double]) -> [Double] {
        var result = [0.0]
        for size in sizes { result.append(result[result.count - 1] + size) }
        return result
    }

    static func index(at position: Double, sizes: [Double]) -> Int? {
        guard !sizes.isEmpty, position >= 0 else { return nil }
        var edge = 0.0
        for (index, size) in sizes.enumerated() {
            edge += size
            if position < edge { return index }
        }
        return nil
    }

    static func clampedIndex(at position: Double, sizes: [Double]) -> Int {
        guard !sizes.isEmpty else { return 0 }
        if position < 0 { return 0 }
        return index(at: position, sizes: sizes) ?? sizes.count - 1
    }

    static func boundary(near position: Double, sizes: [Double], tolerance: Double) -> Int? {
        let all = edges(sizes)
        var best: (index: Int, distance: Double)?
        for index in 1..<all.count {
            let distance = abs(all[index] - position)
            if distance <= tolerance, distance < (best?.distance ?? .infinity) { best = (index - 1, distance) }
        }
        return best?.index
    }

    static func dropIndex(for position: Double, sizes: [Double], moving source: Int) -> Int {
        guard sizes.indices.contains(source) else { return 0 }
        let all = edges(sizes)
        return sizes.indices.filter { $0 != source && position > all[$0] + sizes[$0] / 2 }.count
    }

    static func keptCells(rows: ClosedRange<Int>?, columns: ClosedRange<Int>?, also extra: some Sequence<NoteTableCell>,
                          rowCount: Int, columnCount: Int) -> Set<NoteTableCell> {
        var result = Set<NoteTableCell>()
        guard rowCount > 0, columnCount > 0 else { return result }
        if let rows, let columns {
            let top = max(0, rows.lowerBound - 1), bottom = min(rowCount - 1, rows.upperBound + 1)
            let left = max(0, columns.lowerBound - 1), right = min(columnCount - 1, columns.upperBound + 1)
            if top <= bottom, left <= right {
                for row in top...bottom { for column in left...right { result.insert(NoteTableCell(row: row, column: column)) } }
            }
        }
        for cell in extra where cell.row >= 0 && cell.column >= 0 && cell.row < rowCount && cell.column < columnCount { result.insert(cell) }
        return result
    }

    static func visibleRange(from lower: Double, to upper: Double, sizes: [Double]) -> ClosedRange<Int>? {
        guard !sizes.isEmpty, upper > lower else { return nil }
        let all = edges(sizes)
        guard lower < all[all.count - 1], upper > 0 else { return nil }
        let first = clampedIndex(at: lower, sizes: sizes)
        let last = clampedIndex(at: max(lower, upper - 0.001), sizes: sizes)
        return first...last
    }
}
