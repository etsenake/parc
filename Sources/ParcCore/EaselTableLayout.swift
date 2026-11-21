import Foundation

package struct EaselTableLayout: Equatable {
    package let frame: EaselRect
    package let columnEdges: [Double]
    package let rowEdges: [Double]

    package init(table: EaselTable, frame: EaselRect) {
        self.frame = frame
        let width = table.width, height = table.height
        let scaleX = width > 0 && frame.width.isFinite ? frame.width / width : 1
        let scaleY = height > 0 && frame.height.isFinite ? frame.height / height : 1
        var x = frame.x, y = frame.y
        var columns = [x], rows = [y]
        for value in table.columnWidths { x += value * scaleX; columns.append(x) }
        for value in table.rowHeights { y += value * scaleY; rows.append(y) }
        columnEdges = columns
        rowEdges = rows
    }

    package var columnCount: Int { max(0, columnEdges.count - 1) }
    package var rowCount: Int { max(0, rowEdges.count - 1) }

    package func rect(_ range: EaselTableRange) -> EaselRect? {
        guard range.rows.lowerBound >= 0, range.columns.lowerBound >= 0,
              range.rows.upperBound < rowCount, range.columns.upperBound < columnCount else { return nil }
        let left = columnEdges[range.columns.lowerBound], right = columnEdges[range.columns.upperBound + 1]
        let top = rowEdges[range.rows.lowerBound], bottom = rowEdges[range.rows.upperBound + 1]
        return EaselRect(x: left, y: top, width: right - left, height: bottom - top)
    }

    package func rect(of cell: EaselTableCoordinate, in table: EaselTable) -> EaselRect? {
        rect(table.span(of: cell))
    }

    package func cell(at point: EaselPoint) -> EaselTableCoordinate? {
        guard let column = Self.index(of: point.x, in: columnEdges), let row = Self.index(of: point.y, in: rowEdges) else { return nil }
        return EaselTableCoordinate(row: row, column: column)
    }

    package func clampedCell(at point: EaselPoint) -> EaselTableCoordinate? {
        guard columnCount > 0, rowCount > 0, let first = columnEdges.first, let last = columnEdges.last,
              let top = rowEdges.first, let bottom = rowEdges.last else { return nil }
        let x = min(max(point.x, first), last - 0.001), y = min(max(point.y, top), bottom - 0.001)
        return cell(at: EaselPoint(x: x, y: y))
    }

    package static func index(of position: Double, in edges: [Double]) -> Int? {
        guard edges.count >= 2, position.isFinite, position >= edges[0], position < edges[edges.count - 1] else { return nil }
        var low = 0, high = edges.count - 2
        while low < high {
            let middle = (low + high + 1) / 2
            if edges[middle] <= position { low = middle } else { high = middle - 1 }
        }
        return low
    }

    package func columnBorder(near point: EaselPoint, tolerance: Double, in table: EaselTable) -> Int? {
        guard point.y >= frame.y, point.y <= frame.y + frame.height, columnEdges.count > 2 else { return nil }
        let row = Self.index(of: point.y, in: rowEdges)
        var best: (index: Int, distance: Double)?
        for index in 1..<(columnEdges.count - 1) {
            let distance = abs(columnEdges[index] - point.x)
            guard distance <= tolerance, distance < (best?.distance ?? .infinity) else { continue }
            if let row, let merge = table.merge(containing: EaselTableCoordinate(row: row, column: index - 1)),
               merge.range.columns.contains(index) { continue }
            best = (index - 1, distance)
        }
        return best?.index
    }

    package func rowBorder(near point: EaselPoint, tolerance: Double, in table: EaselTable) -> Int? {
        guard point.x >= frame.x, point.x <= frame.x + frame.width, rowEdges.count > 2 else { return nil }
        let column = Self.index(of: point.x, in: columnEdges)
        var best: (index: Int, distance: Double)?
        for index in 1..<(rowEdges.count - 1) {
            let distance = abs(rowEdges[index] - point.y)
            guard distance <= tolerance, distance < (best?.distance ?? .infinity) else { continue }
            if let column, let merge = table.merge(containing: EaselTableCoordinate(row: index - 1, column: column)),
               merge.range.rows.contains(index) { continue }
            best = (index - 1, distance)
        }
        return best?.index
    }

    package func insertionIndex(near position: Double, edges: [Double], tolerance: Double) -> Int? {
        var best: (index: Int, distance: Double)?
        for (index, edge) in edges.enumerated() {
            let distance = abs(edge - position)
            if distance <= tolerance, distance < (best?.distance ?? .infinity) { best = (index, distance) }
        }
        return best?.index
    }

    package func dropIndex(for position: Double, edges: [Double], moving block: ClosedRange<Int>) -> Int {
        let count = edges.count - 1
        guard count > 0, block.lowerBound >= 0, block.upperBound < count else { return 0 }
        var destination = 0
        for index in 0..<count where !block.contains(index) {
            if position > (edges[index] + edges[index + 1]) / 2 { destination += 1 }
        }
        return min(destination, count - block.count)
    }
}

package enum EaselTableGeometry {
    package static func fitted(_ item: EaselItem) -> EaselItem {
        guard item.kind == .table, var table = item.table, table.width > 0, table.height > 0 else { return item }
        var next = item
        if abs(table.width - item.frame.width) > 0.001 { table.scaleColumns(toWidth: item.frame.width) }
        if abs(table.height - item.frame.height) > 0.001 { table.scaleRows(toHeight: item.frame.height) }
        next.table = table
        next.frame.width = table.width
        next.frame.height = table.height
        return next
    }

    package static func placement(from start: EaselPoint, to end: EaselPoint?,
                          columnWidth: Double = EaselTable.defaultColumnWidth,
                          rowHeight: Double = EaselTable.defaultRowHeight) -> (columns: Int, rows: Int, frame: EaselRect) {
        guard let end, hypot(end.x - start.x, end.y - start.y) > EaselToolGeometry.dragThreshold else {
            let columns = EaselTable.defaultColumns, rows = EaselTable.defaultRows
            let width = Double(columns) * columnWidth, height = Double(rows) * rowHeight
            return (columns, rows, EaselRect(x: max(0, start.x - width / 2), y: max(0, start.y - height / 2), width: width, height: height))
        }
        let columns = min(12, max(1, Int((abs(end.x - start.x) / columnWidth).rounded(.up))))
        let rows = min(24, max(1, Int((abs(end.y - start.y) / rowHeight).rounded(.up))))
        let width = Double(columns) * columnWidth, height = Double(rows) * rowHeight
        let x = end.x < start.x ? start.x - width : start.x
        let y = end.y < start.y ? start.y - height : start.y
        return (columns, rows, EaselRect(x: max(0, x), y: max(0, y), width: width, height: height))
    }

    package static func item(columns: Int, rows: Int, frame: EaselRect, zIndex: Int, color: String = EaselVectorExport.automaticInk) -> EaselItem {
        let table = EaselTable.blank(columns: columns, rows: rows,
                                     columnWidth: frame.width / Double(max(1, min(columns, EaselTable.maximumColumns))),
                                     rowHeight: frame.height / Double(max(1, min(rows, EaselTable.maximumRows))))
        var item = EaselItem(kind: .table, frame: EaselRect(x: frame.x, y: frame.y, width: table.width, height: table.height),
                             zIndex: zIndex, color: color)
        item.table = table
        return item
    }

    package static func stickies(from item: EaselItem, size: Double = EaselBoardObjects.stickySide, gap: Double = 24,
                         fill: (String?) -> String?, textHeight: (EaselItem) -> Double = { _ in 0 }) -> [EaselItem] {
        guard item.kind == .table, let table = item.table else { return [] }
        var rows: [Int: [EaselItem]] = [:]
        for cell in table.visibleCells {
            guard let value = table.cell(cell), !value.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            var sticky = EaselItem(kind: .sticky,
                                   frame: EaselRect(x: item.frame.x + Double(cell.column) * (size + gap), y: item.frame.y, width: size, height: size),
                                   zIndex: item.zIndex, text: value.text, color: item.color)
            sticky.richText = value.richText
            sticky.textStyle = item.textStyle
            sticky.fill = fill(value.fill)
            rows[cell.row, default: []].append(EaselBoardObjects.fitted(sticky, textHeight: textHeight))
        }
        var result: [EaselItem] = []
        var y = item.frame.y
        for row in rows.keys.sorted() {
            let stickies = rows[row] ?? []
            for var sticky in stickies {
                sticky.frame.y = y
                sticky.zIndex = item.zIndex + result.count
                result.append(sticky)
            }
            y += (stickies.map(\.frame.height).max() ?? size) + gap
        }
        return result
    }
}

extension EaselTableLayout {
    package func borderSegments(in table: EaselTable) -> [(start: EaselPoint, end: EaselPoint)] {
        guard rowCount == table.rowCount, columnCount == table.columnCount, rowCount > 0, columnCount > 0 else { return [] }
        var owner: [EaselTableCoordinate: Int] = [:]
        for (index, merge) in table.merges.enumerated() {
            for cell in merge.range.cells { owner[cell] = index }
        }
        func joined(_ a: EaselTableCoordinate, _ b: EaselTableCoordinate) -> Bool {
            guard let first = owner[a], let second = owner[b] else { return false }
            return first == second
        }
        var segments: [(start: EaselPoint, end: EaselPoint)] = []
        for edge in 1..<max(1, columnCount) {
            let x = columnEdges[edge]
            var start: Double?
            for row in 0..<rowCount {
                if joined(EaselTableCoordinate(row: row, column: edge - 1), EaselTableCoordinate(row: row, column: edge)) {
                    if let top = start { segments.append((EaselPoint(x: x, y: top), EaselPoint(x: x, y: rowEdges[row]))); start = nil }
                } else if start == nil { start = rowEdges[row] }
            }
            if let top = start { segments.append((EaselPoint(x: x, y: top), EaselPoint(x: x, y: rowEdges[rowCount]))) }
        }
        for edge in 1..<max(1, rowCount) {
            let y = rowEdges[edge]
            var start: Double?
            for column in 0..<columnCount {
                if joined(EaselTableCoordinate(row: edge - 1, column: column), EaselTableCoordinate(row: edge, column: column)) {
                    if let left = start { segments.append((EaselPoint(x: left, y: y), EaselPoint(x: columnEdges[column], y: y))); start = nil }
                } else if start == nil { start = columnEdges[column] }
            }
            if let left = start { segments.append((EaselPoint(x: left, y: y), EaselPoint(x: columnEdges[columnCount], y: y))) }
        }
        return segments
    }
}

extension EaselVectorExport {
    package static let tableCornerRadius = 6.0

    package static func table(_ item: EaselItem, _ layout: EaselVectorText?) -> String {
        guard let model = item.table else { return "" }
        let f = item.frame, grid = EaselTableLayout(table: model, frame: f)
        func box(_ r: EaselRect) -> String {
            "x=\"" + number(r.x) + "\" y=\"" + number(r.y) + "\" width=\"" + number(r.width) + "\" height=\"" + number(r.height) + "\""
        }
        let clip = "table-" + item.id.uuidString.lowercased()
        let corner = " rx=\"" + number(tableCornerRadius) + "\" ry=\"" + number(tableCornerRadius) + "\""
        var result = "<g class=\"easel-table\"><clipPath id=\"" + clip + "\"><rect " + box(f) + corner + "/></clipPath>"
        result += "<g clip-path=\"url(#" + clip + ")\"><rect " + box(f) + " style=\"fill:var(--easel-card)\"/>"
        for cell in model.visibleCells {
            guard let fill = model.cell(cell)?.fill, let r = grid.rect(of: cell, in: model) else { continue }
            result += "<rect " + box(r) + " style=\"fill:" + paint(fill, role: .fill) + "\"/>"
        }
        let segments = grid.borderSegments(in: model)
        if !segments.isEmpty {
            let path = segments.map { "M" + number($0.start.x) + " " + number($0.start.y) + "L" + number($0.end.x) + " " + number($0.end.y) }.joined()
            result += "<path d=\"" + path + "\" style=\"fill:none;stroke:var(--easel-card-line);stroke-width:1\"/>"
        }
        result += "</g><rect " + box(f) + corner + " style=\"fill:none;stroke:var(--easel-card-line);stroke-width:1\"/>"
        return result + text(item, layout) + "</g>"
    }
}
