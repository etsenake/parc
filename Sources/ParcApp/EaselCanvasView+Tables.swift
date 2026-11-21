import AppKit
import UniformTypeIdentifiers

enum EaselTableHover: Equatable {
    case columnGrip(Int), rowGrip(Int), addColumn, addRow, insertColumn(Int), insertRow(Int), columnBorder(Int), rowBorder(Int)
}

enum EaselTableDrag: Equatable {
    case cells(EaselTableCoordinate)
    case columnBorder(Int)
    case rowBorder(Int)
    case columns(ClosedRange<Int>, destination: Int)
    case rows(ClosedRange<Int>, destination: Int)
}

@MainActor
final class EaselTableCellText {
    let text: String
    let rich: EaselRichText?
    let style: EaselTextStyle
    let color: String
    let width: CGFloat
    let adapts: Bool
    let layout: EaselTextLayout.Layout

    init(_ cell: EaselTableCell, style: EaselTextStyle, color: String, width: CGFloat, adapts: Bool, layout: EaselTextLayout.Layout) {
        text = cell.text
        rich = cell.richText
        self.style = style
        self.color = color
        self.width = width
        self.adapts = adapts
        self.layout = layout
    }

    func matches(_ cell: EaselTableCell, style: EaselTextStyle, color: String, width: CGFloat, adapts: Bool) -> Bool {
        text == cell.text && rich == cell.richText && self.style == style && self.color == color && self.width == width && self.adapts == adapts
    }
}

struct EaselTableCanvasState {
    var tableID: UUID?
    var anchor: EaselTableCoordinate?
    var head: EaselTableCoordinate?
    var editingCell: EaselTableCoordinate?
    var hoverTable: UUID?
    var hover: EaselTableHover?
    var hoverCell: EaselTableCoordinate?
    var drag: EaselTableDrag?
    var dragTable: UUID?
    var dragOrigin = NSPoint.zero
    var original: EaselItem?
    var preview: EaselItem?
    var pendingTable: UUID?
    var pendingCell: EaselTableCoordinate?
    var placement: (start: NSPoint, end: NSPoint)?
    var textCache: [UUID: [EaselTableCoordinate: EaselTableCellText]] = [:]
    var emptyHeights: [String: CGFloat] = [:]

    mutating func select(_ id: UUID, anchor: EaselTableCoordinate, head: EaselTableCoordinate? = nil) {
        tableID = id
        self.anchor = anchor
        self.head = head ?? anchor
    }

    mutating func clearCells() {
        anchor = nil
        head = nil
        pendingTable = nil
        pendingCell = nil
    }
}

@MainActor
enum EaselTableMetrics {
    static let cornerRadius: CGFloat = CGFloat(EaselVectorExport.tableCornerRadius)
    static let cellPadding: CGFloat = 5
    static let gripLength: CGFloat = 20
    static let gripThickness: CGFloat = 12
    static let band: CGFloat = 14
    static let barThickness: CGFloat = 12
    static let barGap: CGFloat = 3
    static let markerRadius: CGFloat = 8
    static let borderTolerance: CGFloat = 4
    static let cornerClearance: CGFloat = 12
    static let clipboardType = NSPasteboard.PasteboardType("org.parc.easel-table.v1")
    static let csvType = NSPasteboard.PasteboardType("public.comma-separated-values-text")
}

private extension NSRect {
    init(_ rect: EaselRect) { self.init(x: rect.x, y: rect.y, width: rect.width, height: rect.height) }
}

private extension EaselPoint {
    init(_ point: NSPoint) { self.init(x: Double(point.x), y: Double(point.y)) }
}

@MainActor
final class EaselTableNotice: NSObject {
    static let action = NSSelectorFromString("showEaselTableNotice:")
    let label: String
    let detail: String?
    init(label: String, detail: String? = nil) { self.label = label; self.detail = detail }
}

@MainActor
private final class EaselTableMenuToken: NSObject {
    let table: UUID
    let fill: String?
    init(table: UUID, fill: String? = nil) { self.table = table; self.fill = fill }
}

extension EaselCanvasView {
    var selectedTable: EaselItem? {
        guard selection.count == 1, let id = selection.first,
              let item = items.first(where: { $0.id == id }), item.kind == .table, item.table != nil else { return nil }
        return item
    }

    var tableCellSelection: (item: EaselItem, table: EaselTable, range: EaselTableRange, head: EaselTableCoordinate)? {
        guard let item = selectedTable, item.id == tableState.tableID, let table = item.table,
              let anchor = tableState.anchor, let head = tableState.head, table.contains(anchor), table.contains(head) else { return nil }
        return (item, table, table.expanded(EaselTableRange(anchor, head)), head)
    }

    var editingTable: EaselItem? {
        guard editor != nil, let id = editingID, tableState.editingCell != nil else { return nil }
        return session.document.items.first { $0.id == id && $0.kind == .table }
    }

    var isEditingTableCell: Bool { editingTable != nil }

    func tableSelectionDidChange() {
        if let id = tableState.tableID, selection != [id] {
            tableState.clearCells()
            tableState.tableID = nil
            invalidateTableChrome(id)
        }
        if let id = tableState.hoverTable, selection != [id] {
            tableState.hoverTable = nil
            tableState.hover = nil
            tableState.hoverCell = nil
            invalidateTableChrome(id)
        }
    }

    func tablePreview(_ displayed: [EaselItem]) -> [EaselItem] {
        guard let preview = tableState.preview else { return displayed }
        return displayed.map { $0.id == preview.id ? preview : $0 }
    }

    func cancelTableInteraction() {
        cancelTablePlacement()
        let id = tableState.dragTable ?? tableState.preview?.id
        tableState.drag = nil
        tableState.dragTable = nil
        tableState.original = nil
        let hadPreview = tableState.preview != nil
        tableState.preview = nil
        if let id { invalidateTableChrome(id) }
        if hadPreview { invalidateIncrementalDisplay(layout: true) }
    }

    private func tableItem(_ id: UUID) -> EaselItem? {
        session.document.items.first { $0.id == id && $0.kind == .table && $0.table != nil }
    }

    func tableAttributed(_ item: EaselItem, _ cell: EaselTableCell, width: CGFloat) -> NSAttributedString {
        let value = EaselRichTextCodec.attributed(cell.text, richText: cell.richText, style: item.resolvedTextStyle, color: item.color)
        EaselTextAttachments.bind(value, width: max(1, width - 20))
        return adaptsInk ? EaselInk.adapting(value) : value
    }

    func tableCellText(_ item: EaselItem, _ cell: EaselTableCoordinate, _ value: EaselTableCell, width: CGFloat) -> EaselTableCellText {
        let style = item.resolvedTextStyle
        if let cached = tableState.textCache[item.id]?[cell], cached.matches(value, style: style, color: item.color, width: width, adapts: adaptsInk) {
            return cached
        }
        let source = value.text.isEmpty ? EaselTableCell(text: " ") : value
        let entry = EaselTableCellText(value, style: style, color: item.color, width: width, adapts: adaptsInk,
                                       layout: EaselTextLayout.Layout(tableAttributed(item, source, width: width), width: width))
        tableState.textCache[item.id, default: [:]][cell] = entry
        return entry
    }

    func tableContentHeight(_ item: EaselItem, _ cell: EaselTableCoordinate, _ value: EaselTableCell, width: CGFloat) -> Double {
        guard value.text.isEmpty else {
            return Double(tableCellText(item, cell, value, width: width).layout.height + 2 * EaselTableMetrics.cellPadding)
        }
        let style = item.resolvedTextStyle
        let key = style.family.rawValue + "|" + style.size.rawValue + "|" + String(Double(width))
        if let height = tableState.emptyHeights[key] { return Double(height + 2 * EaselTableMetrics.cellPadding) }
        let height = EaselTextLayout.Layout(EaselTextAppearance.attributed(" ", style: style, color: item.color), width: width).height
        if tableState.emptyHeights.count > 256 { tableState.emptyHeights.removeAll() }
        tableState.emptyHeights[key] = height
        return Double(height + 2 * EaselTableMetrics.cellPadding)
    }

    func tableSpans(_ table: EaselTable) -> [EaselTableCoordinate: EaselTableRange] {
        Dictionary(table.merges.map { ($0.anchor, $0.range) }, uniquingKeysWith: { first, _ in first })
    }

    func tableRowMinimums(_ item: EaselItem, _ table: EaselTable) -> [Double] {
        var minimums = [Double](repeating: EaselTable.minimumRowHeight, count: table.rowCount)
        var spanned: [(range: EaselTableRange, height: Double)] = []
        let spans = tableSpans(table)
        for cell in table.visibleCells {
            guard let value = table.cell(cell) else { continue }
            let span = spans[cell] ?? EaselTableRange(cell)
            let width = span.columns.reduce(0.0) { $0 + (table.columnWidths.indices.contains($1) ? table.columnWidths[$1] : 0) }
            let height = tableContentHeight(item, cell, value, width: CGFloat(width))
            if span.rows.count == 1 { minimums[cell.row] = max(minimums[cell.row], height) }
            else { spanned.append((span, height)) }
        }
        for entry in spanned where entry.range.rows.upperBound < table.rowCount {
            let available = entry.range.rows.reduce(0.0) { $0 + max(minimums[$1], table.rowHeights[$1]) }
            guard entry.height > available else { continue }
            let last = entry.range.rows.upperBound
            minimums[last] = max(minimums[last], table.rowHeights[last]) + entry.height - available
        }
        return minimums
    }

    func normalizedTable(_ item: EaselItem, _ table: EaselTable, hugging rows: Set<Int> = [], previous: EaselTable? = nil) -> EaselItem {
        var table = table
        var probe = item
        probe.table = table
        let minimums = tableRowMinimums(probe, table)
        if let previous, !rows.isEmpty {
            var old = item
            old.table = previous
            let before = tableRowMinimums(old, previous)
            for row in rows where table.rowHeights.indices.contains(row) && previous.rowHeights.indices.contains(row) && before.indices.contains(row)
                && previous.rowHeights[row] <= before[row] + 0.5 {
                table.rowHeights[row] = min(EaselTable.maximumLength, max(EaselTable.minimumRowHeight, minimums[row]))
            }
        }
        table.fitRows(minimums: minimums)
        var next = item
        next.table = table
        next.frame.width = table.width
        next.frame.height = table.height
        return next
    }

    func fittedTables(_ document: EaselDocument, ids: Set<UUID>) -> EaselDocument {
        var next = document
        for index in next.items.indices where ids.contains(next.items[index].id) && next.items[index].kind == .table {
            let item = next.items[index]
            guard var table = item.table, abs(table.width - item.frame.width) > 0.01 || abs(table.height - item.frame.height) > 0.01 else { continue }
            table.scaleColumns(toWidth: item.frame.width)
            var probe = item
            probe.table = table
            table.scaleRows(toHeight: item.frame.height, minimums: tableRowMinimums(probe, table))
            next.items[index].table = table
            next.items[index].frame.width = table.width
            next.items[index].frame.height = table.height
        }
        return next
    }

    @discardableResult
    func commitTable(_ name: String, _ id: UUID, coalescing group: UUID? = nil, hugging rows: Set<Int> = [],
                     _ change: (inout EaselTable) -> Bool) -> Bool {
        guard !session.isClosed, !session.isDeleted, let index = session.document.items.firstIndex(where: { $0.id == id }),
              session.document.items[index].kind == .table, !session.document.items[index].isLocked,
              let original = session.document.items[index].table else { return false }
        var table = original
        guard change(&table), table != original else { return false }
        let next = normalizedTable(session.document.items[index], table, hugging: rows, previous: original)
        let ids = Set(session.document.items.map(\.id))
        tableState.textCache = tableState.textCache.filter { ids.contains($0.key) }
        return commit(name, coalescing: group) { document in
            guard let position = document.items.firstIndex(where: { $0.id == id }) else { return }
            let previous = document
            document.items[position] = next
            if previous.items[position].frame != next.frame {
                document = EaselDependents.settle(document, previous: previous, moved: [id])
            }
        }
    }

    func drawTable(_ item: EaselItem, showsEditor: Bool) {
        guard let table = item.table else { return }
        let frame = rect(item)
        guard frame.width > 0, frame.height > 0 else { return }
        let grid = EaselTableLayout(table: table, frame: item.frame)
        let clip = NSGraphicsContext.current?.cgContext.boundingBoxOfClipPath ?? frame
        let radius = EaselTableMetrics.cornerRadius
        let shape = NSBezierPath(roundedRect: frame, xRadius: radius, yRadius: radius)
        EaselAppearance.cardFill.setFill()
        shape.fill()
        NSGraphicsContext.saveGraphicsState()
        shape.addClip()
        let visible = table.visibleCells, spans = tableSpans(table)
        for cell in visible {
            guard let fill = table.cell(cell)?.fill, let box = grid.rect(spans[cell] ?? EaselTableRange(cell)) else { continue }
            let r = NSRect(box)
            guard r.intersects(clip) else { continue }
            EaselInk.color(fill, adaptive: adaptsInk, role: .fill).setFill()
            r.fill()
        }
        let lines = NSBezierPath()
        for segment in grid.borderSegments(in: table) {
            lines.move(to: NSPoint(x: segment.start.x, y: segment.start.y))
            lines.line(to: NSPoint(x: segment.end.x, y: segment.end.y))
        }
        lines.lineWidth = 1
        EaselAppearance.cardStroke.setStroke()
        lines.stroke()
        let editing = showsEditor && editor != nil && editingID == item.id ? tableState.editingCell : nil
        for cell in visible where cell != editing {
            guard let value = table.cell(cell), !value.text.isEmpty, let box = grid.rect(spans[cell] ?? EaselTableRange(cell)) else { continue }
            let r = NSRect(box)
            guard r.intersects(clip) else { continue }
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(rect: r).addClip()
            tableCellText(item, cell, value, width: r.width).layout.draw(at: NSPoint(x: r.minX, y: r.minY + EaselTableMetrics.cellPadding),
                                                                          style: item.resolvedTextStyle)
            NSGraphicsContext.restoreGraphicsState()
        }
        NSGraphicsContext.restoreGraphicsState()
        let outline = NSBezierPath(roundedRect: frame.insetBy(dx: 0.5, dy: 0.5), xRadius: radius - 0.5, yRadius: radius - 0.5)
        outline.lineWidth = 1
        EaselAppearance.cardStroke.setStroke()
        outline.stroke()
        if let cache = tableState.textCache[item.id], cache.count > table.rowCount * table.columnCount {
            tableState.textCache[item.id] = cache.filter { table.contains($0.key) }
        }
    }

    private func tableChromeBounds(_ item: EaselItem) -> NSRect {
        let scale = CGFloat(canvasScale)
        let pad = (EaselTableMetrics.band + EaselTableMetrics.barGap + EaselTableMetrics.barThickness + 8) / max(scale, 0.2)
        return rect(item).insetBy(dx: -pad, dy: -pad)
    }

    func invalidateTableChrome(_ id: UUID?) {
        guard let id, let item = items.first(where: { $0.id == id }) else { return }
        let area = tableChromeBounds(item)
        setNeedsDisplay(area)
        if usesObjectSurfaces { decoration.setNeedsDisplay(area) }
    }

    private func tableBands(_ item: EaselItem) -> (top: NSRect, left: NSRect, right: NSRect, bottom: NSRect) {
        let f = rect(item), scale = CGFloat(max(canvasScale, 0.2))
        let band = EaselTableMetrics.band / scale, clearance = EaselTableMetrics.cornerClearance / scale
        let gap = EaselTableMetrics.barGap / scale, thick = EaselTableMetrics.barThickness / scale
        let top = NSRect(x: f.minX + clearance, y: f.minY - band, width: max(0, f.width - 2 * clearance), height: band * 1.5)
        let left = NSRect(x: f.minX - band, y: f.minY + clearance, width: band * 1.5, height: max(0, f.height - 2 * clearance))
        let right = NSRect(x: f.maxX + gap, y: f.minY, width: thick, height: max(0, f.height - clearance))
        let bottom = NSRect(x: f.minX, y: f.maxY + gap, width: max(0, f.width - clearance), height: thick)
        return (top, left, right, bottom)
    }

    func tableHit(at point: NSPoint, item: EaselItem) -> EaselTableHover? {
        guard let table = item.table else { return nil }
        let grid = EaselTableLayout(table: table, frame: item.frame), scale = CGFloat(max(canvasScale, 0.2))
        let bands = tableBands(item), p = EaselPoint(point)
        if bands.right.contains(point) { return .addColumn }
        if bands.bottom.contains(point) { return .addRow }
        let marker = Double(EaselTableMetrics.markerRadius / scale)
        if bands.top.contains(point) {
            if table.columnCount > 1, let edge = grid.insertionIndex(near: p.x, edges: Array(grid.columnEdges.dropFirst().dropLast()), tolerance: marker) {
                return .insertColumn(edge + 1)
            }
            return EaselTableLayout.index(of: p.x, in: grid.columnEdges).map(EaselTableHover.columnGrip)
        }
        if bands.left.contains(point) {
            if table.rowCount > 1, let edge = grid.insertionIndex(near: p.y, edges: Array(grid.rowEdges.dropFirst().dropLast()), tolerance: marker) {
                return .insertRow(edge + 1)
            }
            return EaselTableLayout.index(of: p.y, in: grid.rowEdges).map(EaselTableHover.rowGrip)
        }
        guard rect(item).contains(point) else { return nil }
        let tolerance = Double(EaselTableMetrics.borderTolerance / scale)
        if let border = grid.columnBorder(near: p, tolerance: tolerance, in: table) { return .columnBorder(border) }
        if let border = grid.rowBorder(near: p, tolerance: tolerance, in: table) { return .rowBorder(border) }
        return nil
    }

    func updateTableHover(at point: NSPoint?) {
        var nextTable: UUID?, nextHover: EaselTableHover?, nextCell: EaselTableCoordinate?
        if let point, !drawing, tableState.drag == nil, marqueeRect == nil, !hidesPassiveAnnotations,
           let item = selectedTable, !item.isLocked, let table = item.table {
            nextHover = tableHit(at: point, item: item)
            nextCell = EaselTableLayout(table: table, frame: item.frame).cell(at: EaselPoint(point)).map(table.anchor)
            if nextHover != nil || nextCell != nil || tableChromeBounds(item).contains(point) { nextTable = item.id }
        }
        guard nextTable != tableState.hoverTable || nextHover != tableState.hover || nextCell != tableState.hoverCell else { return }
        let previous = tableState.hoverTable
        tableState.hoverTable = nextTable
        tableState.hover = nextHover
        tableState.hoverCell = nextCell
        invalidateTableChrome(previous)
        if nextTable != previous { invalidateTableChrome(nextTable) }
    }

    func addTableCursorRects() {
        guard !drawing, let item = selectedTable, !item.isLocked, let table = item.table else { return }
        let bands = tableBands(item), scale = CGFloat(max(canvasScale, 0.2))
        for band in [bands.top, bands.left, bands.right, bands.bottom] where !band.isEmpty { addCursorRect(band, cursor: .pointingHand) }
        let grid = EaselTableLayout(table: table, frame: item.frame), f = rect(item)
        let tolerance = EaselTableMetrics.borderTolerance / scale, inset = EaselTableMetrics.band / scale / 2
        for segment in grid.borderSegments(in: table) {
            if segment.start.x == segment.end.x {
                let top = max(CGFloat(segment.start.y), f.minY + inset)
                guard CGFloat(segment.end.y) > top else { continue }
                addCursorRect(NSRect(x: CGFloat(segment.start.x) - tolerance, y: top, width: 2 * tolerance, height: CGFloat(segment.end.y) - top),
                              cursor: .resizeLeftRight)
            } else {
                let left = max(CGFloat(segment.start.x), f.minX + inset)
                guard CGFloat(segment.end.x) > left else { continue }
                addCursorRect(NSRect(x: left, y: CGFloat(segment.start.y) - tolerance, width: CGFloat(segment.end.x) - left, height: 2 * tolerance),
                              cursor: .resizeUpDown)
            }
        }
    }

    func drawTableDecorations(in dirtyRect: NSRect) {
        if let placement = tableState.placement { drawTablePlacement(placement, in: dirtyRect) }
        guard !drawing, marqueeRect == nil, !hidesPassiveAnnotations || tableState.drag != nil,
              let item = selectedTable, let table = item.table else { return }
        guard tableChromeBounds(item).intersects(dirtyRect) else { return }
        let grid = EaselTableLayout(table: table, frame: item.frame), scale = CGFloat(max(canvasScale, 0.2)), f = rect(item)
        let accent = EaselAppearance.selection
        if let selected = tableCellSelection, let box = grid.rect(selected.range) {
            let r = NSRect(box)
            if !selected.range.isSingleCell {
                NoteTheme.blockSelection.setFill()
                r.fill()
            }
            let outline = NSBezierPath(rect: r.insetBy(dx: 1 / scale, dy: 1 / scale))
            outline.lineWidth = 2 / scale
            accent.setStroke()
            outline.stroke()
        }
        if let drag = tableState.drag {
            drawTableDrag(drag, grid: grid, frame: f, scale: scale)
            return
        }
        guard !item.isLocked, tableState.hoverTable == item.id || tableCellSelection != nil else { return }
        let bands = tableBands(item)
        let wholeColumns = tableSelectedColumns(), wholeRows = tableSelectedRows()
        var gripColumns = Set<Int>(), gripRows = Set<Int>()
        if let cell = tableState.hoverCell { gripColumns.insert(cell.column); gripRows.insert(cell.row) }
        if case .columnGrip(let column)? = tableState.hover { gripColumns.insert(column) }
        if case .rowGrip(let row)? = tableState.hover { gripRows.insert(row) }
        if let columns = wholeColumns { gripColumns.formUnion(columns) }
        if let rows = wholeRows { gripRows.formUnion(rows) }
        for column in gripColumns where column < grid.columnCount {
            let center = NSPoint(x: (grid.columnEdges[column] + grid.columnEdges[column + 1]) / 2, y: Double(f.minY))
            let size = NSSize(width: EaselTableMetrics.gripLength / scale, height: EaselTableMetrics.gripThickness / scale)
            drawTableGrip(NSRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height),
                          vertical: false, active: wholeColumns?.contains(column) == true, hovered: tableState.hover == .columnGrip(column), scale: scale)
        }
        for row in gripRows where row < grid.rowCount {
            let center = NSPoint(x: Double(f.minX), y: (grid.rowEdges[row] + grid.rowEdges[row + 1]) / 2)
            let size = NSSize(width: EaselTableMetrics.gripThickness / scale, height: EaselTableMetrics.gripLength / scale)
            drawTableGrip(NSRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height),
                          vertical: true, active: wholeRows?.contains(row) == true, hovered: tableState.hover == .rowGrip(row), scale: scale)
        }
        if tableState.hoverTable == item.id {
            drawTableAddBar(bands.right, hovered: tableState.hover == .addColumn, scale: scale)
            drawTableAddBar(bands.bottom, hovered: tableState.hover == .addRow, scale: scale)
        }
        switch tableState.hover {
        case .insertColumn(let index)?:
            let x = CGFloat(grid.columnEdges[min(index, grid.columnCount)])
            drawTableInsertMarker(at: NSPoint(x: x, y: f.minY), line: NSRect(x: x - 1 / scale, y: f.minY, width: 2 / scale, height: f.height), scale: scale)
        case .insertRow(let index)?:
            let y = CGFloat(grid.rowEdges[min(index, grid.rowCount)])
            drawTableInsertMarker(at: NSPoint(x: f.minX, y: y), line: NSRect(x: f.minX, y: y - 1 / scale, width: f.width, height: 2 / scale), scale: scale)
        case .columnBorder(let index)?:
            let x = CGFloat(grid.columnEdges[index + 1])
            NoteTheme.dropIndicatorFallback.setFill()
            NSRect(x: x - 1 / scale, y: f.minY, width: 2 / scale, height: f.height).fill()
        case .rowBorder(let index)?:
            let y = CGFloat(grid.rowEdges[index + 1])
            NoteTheme.dropIndicatorFallback.setFill()
            NSRect(x: f.minX, y: y - 1 / scale, width: f.width, height: 2 / scale).fill()
        default:
            break
        }
    }

    private func drawTableDrag(_ drag: EaselTableDrag, grid: EaselTableLayout, frame f: NSRect, scale: CGFloat) {
        let accent = EaselAppearance.selection
        switch drag {
        case .columnBorder(let index):
            guard index + 1 < grid.columnEdges.count else { return }
            NoteTheme.dropIndicatorFallback.setFill()
            NSRect(x: CGFloat(grid.columnEdges[index + 1]) - 1 / scale, y: f.minY, width: 2 / scale, height: f.height).fill()
        case .rowBorder(let index):
            guard index + 1 < grid.rowEdges.count else { return }
            NoteTheme.dropIndicatorFallback.setFill()
            NSRect(x: f.minX, y: CGFloat(grid.rowEdges[index + 1]) - 1 / scale, width: f.width, height: 2 / scale).fill()
        case .columns(let block, let destination):
            guard block.upperBound < grid.columnCount else { return }
            NoteTheme.blockSelection.setFill()
            NSRect(x: CGFloat(grid.columnEdges[block.lowerBound]), y: f.minY,
                   width: CGFloat(grid.columnEdges[block.upperBound + 1] - grid.columnEdges[block.lowerBound]), height: f.height).fill()
            let remaining = (0..<grid.columnCount).filter { !block.contains($0) }
            let x = destination < remaining.count ? grid.columnEdges[remaining[destination]] : grid.columnEdges[grid.columnCount]
            accent.setFill()
            NSRect(x: CGFloat(x) - 1.5 / scale, y: f.minY - 4 / scale, width: 3 / scale, height: f.height + 8 / scale).fill()
        case .rows(let block, let destination):
            guard block.upperBound < grid.rowCount else { return }
            NoteTheme.blockSelection.setFill()
            NSRect(x: f.minX, y: CGFloat(grid.rowEdges[block.lowerBound]), width: f.width,
                   height: CGFloat(grid.rowEdges[block.upperBound + 1] - grid.rowEdges[block.lowerBound])).fill()
            let remaining = (0..<grid.rowCount).filter { !block.contains($0) }
            let y = destination < remaining.count ? grid.rowEdges[remaining[destination]] : grid.rowEdges[grid.rowCount]
            accent.setFill()
            NSRect(x: f.minX - 4 / scale, y: CGFloat(y) - 1.5 / scale, width: f.width + 8 / scale, height: 3 / scale).fill()
        case .cells:
            break
        }
    }

    private func drawTableGrip(_ r: NSRect, vertical: Bool, active: Bool, hovered: Bool, scale: CGFloat) {
        let plate = NSBezierPath(roundedRect: r, xRadius: 4 / scale, yRadius: 4 / scale)
        (active ? EaselAppearance.selection : NoteTheme.menuFill).setFill()
        plate.fill()
        if hovered && !active {
            NoteTheme.hoverFill.setFill()
            plate.fill()
        }
        plate.lineWidth = 1 / scale
        (active ? EaselAppearance.selection : NoteTheme.menuHairline).setStroke()
        plate.stroke()
        (active ? NSColor.white : hovered ? NoteTheme.secondaryInk : NoteTheme.handleInk).setFill()
        let dot = 2 / scale, gap = 2 / scale
        let columns = vertical ? 2 : 3, rows = vertical ? 3 : 2
        let width = CGFloat(columns) * dot + CGFloat(columns - 1) * gap, height = CGFloat(rows) * dot + CGFloat(rows - 1) * gap
        for row in 0..<rows {
            for column in 0..<columns {
                NSBezierPath(ovalIn: NSRect(x: r.midX - width / 2 + CGFloat(column) * (dot + gap),
                                            y: r.midY - height / 2 + CGFloat(row) * (dot + gap), width: dot, height: dot)).fill()
            }
        }
    }

    private func drawTableAddBar(_ r: NSRect, hovered: Bool, scale: CGFloat) {
        guard !r.isEmpty else { return }
        let plate = NSBezierPath(roundedRect: r, xRadius: 4 / scale, yRadius: 4 / scale)
        (hovered ? NoteTheme.pressedFill : NoteTheme.hoverFill).setFill()
        plate.fill()
        (hovered ? NoteTheme.secondaryInk : NoteTheme.handleInk).setStroke()
        let arm = 4.5 / scale, center = NSPoint(x: r.midX, y: r.midY)
        let plus = NSBezierPath()
        plus.move(to: NSPoint(x: center.x - arm, y: center.y))
        plus.line(to: NSPoint(x: center.x + arm, y: center.y))
        plus.move(to: NSPoint(x: center.x, y: center.y - arm))
        plus.line(to: NSPoint(x: center.x, y: center.y + arm))
        plus.lineWidth = 1.5 / scale
        plus.lineCapStyle = .round
        plus.stroke()
    }

    private func drawTableInsertMarker(at point: NSPoint, line: NSRect, scale: CGFloat) {
        EaselAppearance.selection.setFill()
        line.fill()
        let radius = EaselTableMetrics.markerRadius / scale
        NSBezierPath(ovalIn: NSRect(x: point.x - radius, y: point.y - radius, width: 2 * radius, height: 2 * radius)).fill()
        NSColor.white.setStroke()
        let arm = 3.5 / scale
        let plus = NSBezierPath()
        plus.move(to: NSPoint(x: point.x - arm, y: point.y))
        plus.line(to: NSPoint(x: point.x + arm, y: point.y))
        plus.move(to: NSPoint(x: point.x, y: point.y - arm))
        plus.line(to: NSPoint(x: point.x, y: point.y + arm))
        plus.lineWidth = 1.5 / scale
        plus.lineCapStyle = .round
        plus.stroke()
    }

    private func drawTablePlacement(_ placement: (start: NSPoint, end: NSPoint), in dirtyRect: NSRect) {
        let layout = EaselTableGeometry.placement(from: EaselPoint(placement.start), to: EaselPoint(placement.end))
        let r = NSRect(layout.frame), scale = CGFloat(max(canvasScale, 0.2))
        guard r.insetBy(dx: -80 / scale, dy: -60 / scale).intersects(dirtyRect) else { return }
        let accent = EaselAppearance.selection
        let shape = NSBezierPath(roundedRect: r, xRadius: EaselTableMetrics.cornerRadius, yRadius: EaselTableMetrics.cornerRadius)
        EaselAppearance.cardFill.withAlphaComponent(0.7).setFill()
        shape.fill()
        let lines = NSBezierPath()
        for column in 1..<max(1, layout.columns) {
            let x = r.minX + r.width * CGFloat(column) / CGFloat(layout.columns)
            lines.move(to: NSPoint(x: x, y: r.minY)); lines.line(to: NSPoint(x: x, y: r.maxY))
        }
        for row in 1..<max(1, layout.rows) {
            let y = r.minY + r.height * CGFloat(row) / CGFloat(layout.rows)
            lines.move(to: NSPoint(x: r.minX, y: y)); lines.line(to: NSPoint(x: r.maxX, y: y))
        }
        lines.lineWidth = 1 / scale
        accent.withAlphaComponent(0.45).setStroke()
        lines.stroke()
        shape.lineWidth = 2 / scale
        accent.setStroke()
        shape.stroke()
        let label = "\(layout.columns) × \(layout.rows)" as NSString
        let attributes: [NSAttributedString.Key: Any] = [.font: NoteTheme.nunitoBold(12 / scale), .foregroundColor: NoteTheme.menuInk]
        let size = label.size(withAttributes: attributes)
        let pill = NSRect(x: r.maxX - size.width - 14 / scale, y: r.maxY + 6 / scale, width: size.width + 14 / scale, height: size.height + 6 / scale)
        let plate = NSBezierPath(roundedRect: pill, xRadius: pill.height / 2, yRadius: pill.height / 2)
        NoteTheme.menuFill.setFill()
        plate.fill()
        plate.lineWidth = 1 / scale
        NoteTheme.menuHairline.setStroke()
        plate.stroke()
        label.draw(at: NSPoint(x: pill.minX + 7 / scale, y: pill.minY + 3 / scale), withAttributes: attributes)
    }

    func tablePlacementMoved(from start: NSPoint, to end: NSPoint) {
        let old = tableState.placement
        tableState.placement = (start, end)
        invalidateTablePlacement(old)
        invalidateTablePlacement(tableState.placement)
    }

    func cancelTablePlacement() {
        guard let old = tableState.placement else { return }
        tableState.placement = nil
        invalidateTablePlacement(old)
    }

    private func invalidateTablePlacement(_ placement: (start: NSPoint, end: NSPoint)?) {
        guard let placement else { return }
        let layout = EaselTableGeometry.placement(from: EaselPoint(placement.start), to: EaselPoint(placement.end))
        let scale = CGFloat(max(canvasScale, 0.2))
        let area = NSRect(layout.frame).insetBy(dx: -90 / scale, dy: -70 / scale)
        setNeedsDisplay(area)
        if usesObjectSurfaces { decoration.setNeedsDisplay(area) }
    }

    @discardableResult
    func placeTable(from start: NSPoint, to end: NSPoint?) -> Bool {
        cancelTablePlacement()
        cancelPointerInteraction()
        guard !session.isClosed, !session.isDeleted, finishEditing() else { return false }
        let layout = EaselTableGeometry.placement(from: EaselPoint(start), to: end.map(EaselPoint.init))
        return addTable(EaselTableGeometry.item(columns: layout.columns, rows: layout.rows, frame: layout.frame,
                                                zIndex: (session.document.items.map(\.zIndex).max() ?? 0) + 1), name: "Add table")
    }

    @discardableResult
    func insertTable(columns: Int = EaselTable.defaultColumns, rows: Int = EaselTable.defaultRows) -> Bool {
        cancelPointerInteraction()
        guard !session.isClosed, !session.isDeleted, finishEditing() else { return false }
        let width = Double(columns) * EaselTable.defaultColumnWidth, height = Double(rows) * EaselTable.defaultRowHeight
        let frame = EaselRect(x: max(30, Double(visibleRect.midX) - width / 2), y: max(0, Double(visibleRect.minY) + 90), width: width, height: height)
        return addTable(EaselTableGeometry.item(columns: columns, rows: rows, frame: frame,
                                                zIndex: (session.document.items.map(\.zIndex).max() ?? 0) + 1), name: "Add table")
    }

    @discardableResult
    private func addTable(_ item: EaselItem, name: String, selectFirstCell: Bool = true) -> Bool {
        guard let table = item.table else { return false }
        let placed = normalizedTable(item, table)
        drawing = false
        guard commit(name, { $0.items.append(placed) }) else { return false }
        selection = [placed.id]
        if selectFirstCell { tableState.select(placed.id, anchor: EaselTableCoordinate(row: 0, column: 0)) }
        window?.makeFirstResponder(self)
        invalidateIncrementalDisplay(layout: true)
        return true
    }

    private func beginTableInteraction() -> Bool {
        hoveredObjectID = nil
        motion.cancel()
        cancelPointerInteraction()
        cancelTableInteraction()
        guard finishEditing() else { return false }
        window?.makeFirstResponder(self)
        return true
    }

    func selectTableCells(_ id: UUID, anchor: EaselTableCoordinate, head: EaselTableCoordinate? = nil) {
        guard let item = items.first(where: { $0.id == id }), let table = item.table, table.contains(anchor) else { return }
        if selection != [id] { selection = [id] }
        let previous = tableState.anchor.map { ($0, tableState.head ?? $0) }
        tableState.select(id, anchor: anchor, head: head.map { table.contains($0) ? $0 : anchor })
        invalidateTableChrome(id)
        invalidateIncrementalDisplay()
        if previous.map({ $0.0 != tableState.anchor || $0.1 != tableState.head }) ?? true {
            announceTableSelection(item, table)
        }
    }

    private func announceTableSelection(_ item: EaselItem, _ table: EaselTable) {
        guard let anchor = tableState.anchor, let head = tableState.head else { return }
        let range = table.expanded(EaselTableRange(anchor, head))
        let message: String
        if range.isSingleCell || table.span(of: anchor) == range {
            let text = table.cell(table.anchor(of: anchor))?.text ?? ""
            let name = EaselTable.cellName(table.anchor(of: anchor))
            message = name.prefix(1).uppercased() + name.dropFirst() + (text.isEmpty ? ", empty" : ", " + String(text.prefix(200)))
        } else {
            message = "\(range.cellCount) cells selected"
        }
        NSAccessibility.post(element: self, notification: .announcementRequested,
                             userInfo: [.announcement: message, .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }

    func tableSelectedColumns() -> ClosedRange<Int>? {
        guard let selected = tableCellSelection, selected.range.rows == selected.table.all.rows else { return nil }
        return selected.range.columns
    }

    func tableSelectedRows() -> ClosedRange<Int>? {
        guard let selected = tableCellSelection, selected.range.columns == selected.table.all.columns else { return nil }
        return selected.range.rows
    }

    func tableMouseDown(with event: NSEvent) -> Bool {
        guard !drawing, !session.isClosed, !session.isDeleted, event.type == .leftMouseDown else { return false }
        let point = convert(event.locationInWindow, from: nil)
        let modifiers = event.modifierFlags.intersection([.shift, .command, .option, .control])
        let wasEditing = editingTable.flatMap { item in tableState.editingCell.map { (id: item.id, cell: $0) } }
        if let item = selectedTable, !item.isLocked, let part = tableHit(at: point, item: item) {
            guard beginTableInteraction() else { return true }
            guard let current = items.first(where: { $0.id == item.id }) else { return true }
            handleTablePart(part, item: current, modifiers: modifiers, point: point)
            return true
        }
        guard let hit = object(at: point), hit.kind == .table, !hit.isLocked, let table = hit.table,
              let raw = EaselTableLayout(table: table, frame: hit.frame).cell(at: EaselPoint(point)) else { return false }
        let cell = table.anchor(of: raw)
        if event.clickCount >= 2, modifiers.isEmpty {
            guard beginTableInteraction() else { return true }
            if let current = items.first(where: { $0.id == hit.id }) { beginEditingTableCell(current, cell: cell, at: point) }
            return true
        }
        guard selection == [hit.id] else { return false }
        if let editing = wasEditing, editing.id == hit.id, modifiers.isEmpty {
            guard beginTableInteraction() else { return true }
            if let current = items.first(where: { $0.id == hit.id }) { beginEditingTableCell(current, cell: cell, at: point) }
            return true
        }
        if let selected = tableCellSelection, selected.item.id == hit.id {
            guard beginTableInteraction() else { return true }
            if modifiers == [.shift] || modifiers == [.command] {
                selectTableCells(hit.id, anchor: tableState.anchor ?? cell, head: cell)
                tableState.drag = .cells(tableState.anchor ?? cell)
                tableState.dragTable = hit.id
                return true
            }
            if modifiers.isEmpty, selected.range == table.span(of: cell) {
                if let current = items.first(where: { $0.id == hit.id }) { beginEditingTableCell(current, cell: cell, at: point) }
                return true
            }
            selectTableCells(hit.id, anchor: cell)
            tableState.drag = .cells(cell)
            tableState.dragTable = hit.id
            return true
        }
        if modifiers.isEmpty {
            tableState.pendingTable = hit.id
            tableState.pendingCell = cell
        }
        return false
    }

    private func handleTablePart(_ part: EaselTableHover, item: EaselItem, modifiers: NSEvent.ModifierFlags, point: NSPoint) {
        guard let table = item.table else { return }
        switch part {
        case .addColumn: insertTableColumns(item.id, at: table.columnCount)
        case .addRow: insertTableRows(item.id, at: table.rowCount)
        case .insertColumn(let index): insertTableColumns(item.id, at: index)
        case .insertRow(let index): insertTableRows(item.id, at: index)
        case .columnGrip(let column):
            var block = column...column
            if modifiers.contains(.shift), let current = tableSelectedColumns() {
                block = min(current.lowerBound, column)...max(current.upperBound, column)
            } else if let current = tableSelectedColumns(), current.contains(column) {
                block = current
            }
            selectTableCells(item.id, anchor: EaselTableCoordinate(row: 0, column: block.lowerBound),
                             head: EaselTableCoordinate(row: table.rowCount - 1, column: block.upperBound))
            guard table.expanded(EaselTableRange(rows: table.all.rows, columns: block)).columns == block else { return }
            tableState.drag = .columns(block, destination: block.lowerBound)
            tableState.dragTable = item.id
            tableState.dragOrigin = point
        case .rowGrip(let row):
            var block = row...row
            if modifiers.contains(.shift), let current = tableSelectedRows() {
                block = min(current.lowerBound, row)...max(current.upperBound, row)
            } else if let current = tableSelectedRows(), current.contains(row) {
                block = current
            }
            selectTableCells(item.id, anchor: EaselTableCoordinate(row: block.lowerBound, column: 0),
                             head: EaselTableCoordinate(row: block.upperBound, column: table.columnCount - 1))
            guard table.expanded(EaselTableRange(rows: block, columns: table.all.columns)).rows == block else { return }
            tableState.drag = .rows(block, destination: block.lowerBound)
            tableState.dragTable = item.id
            tableState.dragOrigin = point
        case .columnBorder(let column):
            tableState.drag = .columnBorder(column)
            tableState.dragTable = item.id
            tableState.dragOrigin = point
            tableState.original = item
        case .rowBorder(let row):
            tableState.drag = .rowBorder(row)
            tableState.dragTable = item.id
            tableState.dragOrigin = point
            tableState.original = item
        }
        invalidateTableChrome(item.id)
    }

    func tableMouseDragged(with event: NSEvent) -> Bool {
        guard let drag = tableState.drag, let id = tableState.dragTable else { return false }
        guard selection == [id], let item = tableItem(id), let table = item.table,
              tableState.original.map({ $0 == item }) ?? true else { cancelTableInteraction(); return true }
        let point = convert(event.locationInWindow, from: nil)
        let grid = EaselTableLayout(table: table, frame: item.frame)
        switch drag {
        case .cells(let anchor):
            if let cell = grid.clampedCell(at: EaselPoint(point)), cell != tableState.head {
                selectTableCells(id, anchor: anchor, head: cell)
            }
        case .columnBorder(let column):
            var next = table
            let scale = table.width > 0 ? item.frame.width / table.width : 1
            next.setWidth(table.columnWidths[column] + Double(point.x - tableState.dragOrigin.x) / max(scale, 0.01), column: column)
            var preview = item
            preview.table = next
            preview.frame.width = next.width
            tableState.preview = preview
        case .rowBorder(let row):
            var next = table
            let scale = table.height > 0 ? item.frame.height / table.height : 1
            let minimum = tableRowMinimums(item, table)
            next.setHeight(table.rowHeights[row] + Double(point.y - tableState.dragOrigin.y) / max(scale, 0.01), row: row,
                           minimum: minimum.indices.contains(row) ? minimum[row] : EaselTable.minimumRowHeight)
            var preview = item
            preview.table = next
            preview.frame.height = next.height
            tableState.preview = preview
        case .columns(let block, let destination):
            let next = table.nearestDestination(moving: block, to: grid.dropIndex(for: Double(point.x), edges: grid.columnEdges, moving: block), along: .columns)
            if next != destination { tableState.drag = .columns(block, destination: next) }
        case .rows(let block, let destination):
            let next = table.nearestDestination(moving: block, to: grid.dropIndex(for: Double(point.y), edges: grid.rowEdges, moving: block), along: .rows)
            if next != destination { tableState.drag = .rows(block, destination: next) }
        }
        autoscroll(with: event)
        invalidateTableChrome(id)
        invalidateIncrementalDisplay(layout: true)
        return true
    }

    func tableMouseUp(with event: NSEvent) -> Bool {
        if let pending = tableState.pendingTable, let cell = tableState.pendingCell {
            tableState.pendingTable = nil
            tableState.pendingCell = nil
            if dragDistance <= 3, selection == [pending], tableItem(pending)?.table?.contains(cell) == true {
                selectTableCells(pending, anchor: cell)
            }
            return false
        }
        guard let drag = tableState.drag, let id = tableState.dragTable else { return false }
        let preview = tableState.preview?.table
        cancelTableInteraction()
        switch drag {
        case .cells:
            break
        case .columnBorder:
            if let preview { commitTable("Resize Column", id) { table in table.columnWidths = preview.columnWidths; return true } }
        case .rowBorder:
            if let preview { commitTable("Resize Row", id) { table in table.rowHeights = preview.rowHeights; return true } }
        case .columns(let block, let destination):
            guard destination != block.lowerBound, commitTable(block.count == 1 ? "Move Column" : "Move Columns", id, { $0.moveColumns(block, to: destination) }),
                  let table = tableItem(id)?.table else { break }
            selectTableCells(id, anchor: EaselTableCoordinate(row: 0, column: destination),
                             head: EaselTableCoordinate(row: table.rowCount - 1, column: destination + block.count - 1))
        case .rows(let block, let destination):
            guard destination != block.lowerBound, commitTable(block.count == 1 ? "Move Row" : "Move Rows", id, { $0.moveRows(block, to: destination) }),
                  let table = tableItem(id)?.table else { break }
            selectTableCells(id, anchor: EaselTableCoordinate(row: destination, column: 0),
                             head: EaselTableCoordinate(row: destination + block.count - 1, column: table.columnCount - 1))
        }
        window?.invalidateCursorRects(for: self)
        return true
    }

    func tableCellEditorFrame(_ item: EaselItem, _ cell: EaselTableCoordinate) -> NSRect? {
        guard let table = item.table, let box = EaselTableLayout(table: table, frame: item.frame).rect(of: cell, in: table) else { return nil }
        let r = NSRect(box), padding = EaselTableMetrics.cellPadding
        return NSRect(x: r.minX, y: r.minY + padding, width: r.width, height: max(1, r.height - 2 * padding))
    }

    func beginEditingTableCell(_ item: EaselItem, cell requested: EaselTableCoordinate, at point: NSPoint? = nil, selectingAll: Bool = false) {
        guard let table = item.table, table.contains(requested), !item.isLocked, !session.isClosed, !session.isDeleted else { return }
        let cell = table.anchor(of: requested)
        guard finishEditing(), let current = tableItem(item.id), let frame = tableCellEditorFrame(current, cell) else { return }
        if selection != [current.id] { selection = [current.id] }
        tableState.select(current.id, anchor: cell)
        tableState.editingCell = cell
        editingID = current.id
        textUndoGroup = UUID()
        let text = EaselStyledTextView(frame: frame)
        text.drawsBackground = false; text.isRichText = true; text.importsGraphics = false; text.allowsUndo = true
        text.isVerticallyResizable = true; text.isHorizontallyResizable = false
        text.isContinuousSpellCheckingEnabled = true
        text.textContainer?.widthTracksTextView = true
        text.usesEaselObjectLayout = true
        text.onObjectLayoutChanged = { [weak self] in self?.invalidateIncrementalDisplay(layout: true) }
        text.textContainer?.lineFragmentPadding = EaselTextLayout.fragmentPadding
        text.textContainerInset = EaselTextLayout.inset
        text.delegate = self
        text.adaptsInk = adaptsInk
        if adaptsInk { text.caretColor = NoteTheme.caret; text.selectedTextAttributes = [.backgroundColor: NoteTheme.selection] }
        text.setAccessibilityLabel("Table cell, " + EaselTable.cellName(cell))
        addSubview(text)
        editor = text
        keyboardStructureChanged()
        text.onClipboardError = { [weak self] in self?.onError?($0) }
        text.onUndoDocument = { [weak self] in self?.undo(nil) }
        text.onRedoDocument = { [weak self] in self?.redo(nil) }
        text.canUndoDocument = { [weak self] in self?.session.canUndo == true }
        text.canRedoDocument = { [weak self] in self?.session.canRedo == true }
        updateTableCellEditor(current)
        guard editor === text else { return }
        if window?.makeFirstResponder(text) == true {
            let length = (text.string as NSString).length
            if selectingAll {
                text.selectAll(nil)
            } else if let point {
                let index = text.characterIndexForInsertion(at: text.convert(point, from: self))
                text.setSelectedRange(NSRange(location: min(max(0, index), length), length: 0))
            } else {
                text.setSelectedRange(NSRange(location: length, length: 0))
            }
        }
        invalidateTableChrome(current.id)
        invalidateIncrementalDisplay(layout: true)
        refreshTextControls()
    }

    func updateTableCellEditor(_ item: EaselItem) {
        guard let text = editor else { return }
        guard let table = item.table, let cell = tableState.editingCell, table.contains(cell), !table.isCovered(cell),
              let value = table.cell(cell), let frame = tableCellEditorFrame(item, cell) else {
            DispatchQueue.main.async { [weak self, weak text] in
                guard let self, let text, self.editor === text else { return }
                self.finishEditing()
            }
            return
        }
        if text.hasMarkedText() {
            guard let previous = editingTextSnapshot, previous.text != value.text || previous.rich != value.richText else { return }
            text.inputContext?.discardMarkedText()
            text.unmarkText()
        }
        editingTextSnapshot = (value.text, value.richText)
        synchronizingEditor = true
        defer { synchronizingEditor = false }
        let selected = text.selectedRanges
        let target = tableAttributed(item, value, width: frame.width)
        EaselTextAttachments.bind(target, container: text.textContainer)
        let current = try? EaselRichTextCodec.snapshot(text.attributedString())
        let desired = try? EaselRichTextCodec.snapshot(target)
        if !text.hasLoadedDocument || text.string != value.text || current != desired {
            text.retire()
            text.textStorage?.setAttributedString(target)
            text.resetEditingHistory()
            if target.length == 0 {
                text.typingAttributes = [.font: EaselTextAppearance.font(item.resolvedTextStyle), .foregroundColor: color(item.color)]
            }
        }
        text.hasLoadedDocument = true
        text.objectStyle = item.resolvedTextStyle
        text.objectColor = item.color
        text.frame = frame
        let length = (text.string as NSString).length
        text.selectedRanges = selected.map { value in
            let range = value.rangeValue, start = min(range.location, length)
            return NSValue(range: NSRange(location: start, length: min(range.length, length - start)))
        }
    }

    func tableCellTextDidChange(_ notification: Notification) -> Bool {
        guard let cell = tableState.editingCell, let id = editingID, let text = editor,
              notification.object as? EaselStyledTextView === text, let item = tableItem(id) else { return false }
        guard !synchronizingEditor, !text.hasMarkedText(), let table = item.table, let value = table.cell(cell) else { return true }
        if let previous = editingTextSnapshot, value.text != previous.text || value.richText != previous.rich {
            updateTableCellEditor(item)
            return true
        }
        let payload: EaselStyledText
        do { payload = try EaselStyledText.capture(text.attributedString(), style: text.objectStyle, color: text.objectColor) }
        catch { onError?(error); updateTableCellEditor(item); return true }
        guard payload.text.utf8.count <= EaselTable.maximumCellBytes else {
            onError?(EaselStoreError.tooLarge)
            updateTableCellEditor(item)
            return true
        }
        let saved = commitTable("Edit cell", id, coalescing: textUndoGroup, hugging: Set(table.span(of: cell).rows)) { table in
            table.update(cell) { $0.text = payload.text; $0.richText = payload.richText }
        }
        if saved || (payload.text == value.text && payload.richText == value.richText) {
            editingTextSnapshot = (payload.text, payload.richText)
        } else if let current = tableItem(id) {
            updateTableCellEditor(current)
        }
        return true
    }

    func tableTextCommand(_ textView: NSTextView, _ selector: Selector) -> Bool {
        guard textView === editor, let text = editor, let item = editingTable, let cell = tableState.editingCell else { return false }
        switch selector {
        case #selector(NSResponder.cancelOperation(_:)):
            leaveTableCell(item.id, cell)
            return true
        case #selector(NSResponder.insertTab(_:)), #selector(NSResponder.insertBacktab(_:)):
            let backward = selector == #selector(NSResponder.insertBacktab(_:))
            if let kind = text.paragraphKind(), kind == .bullets || kind == .numbers, text.canChangeListIndent(outdent: backward) { return false }
            moveTableEditing(item.id, from: cell, backward: backward)
            return true
        case #selector(NSResponder.insertNewline(_:)), Selector(("noop:")):
            guard let event = NSApp.currentEvent, event.type == .keyDown, event.keyCode == 36 || event.keyCode == 76,
                  event.modifierFlags.contains(.command) else { return false }
            leaveTableCell(item.id, cell)
            return true
        default:
            return false
        }
    }

    private func leaveTableCell(_ id: UUID, _ cell: EaselTableCoordinate) {
        guard finishEditing() else { return }
        window?.makeFirstResponder(self)
        if tableItem(id)?.table?.contains(cell) == true { selectTableCells(id, anchor: cell) }
    }

    private func moveTableEditing(_ id: UUID, from cell: EaselTableCoordinate, backward: Bool) {
        guard finishEditing(), let item = tableItem(id), let table = item.table else { return }
        switch table.tab(from: cell, backward: backward) {
        case .cell(let next):
            beginEditingTableCell(item, cell: next, selectingAll: true)
        case .appendRow:
            if commitTable("Add Row", id, { $0.insertRows(at: $0.rowCount) }), let grown = tableItem(id), let rows = grown.table?.rowCount {
                beginEditingTableCell(grown, cell: EaselTableCoordinate(row: rows - 1, column: 0))
            } else {
                beginEditingTableCell(item, cell: cell)
            }
        case .none:
            beginEditingTableCell(item, cell: cell)
        }
    }

    func activateTable(_ item: EaselItem) -> Bool {
        guard let table = item.table, !item.isLocked else { return false }
        let cell = tableCellSelection.map { $0.head } ?? EaselTableCoordinate(row: 0, column: 0)
        beginEditingTableCell(item, cell: table.contains(cell) ? cell : EaselTableCoordinate(row: 0, column: 0))
        return editor != nil && editingID == item.id
    }

    func tableKeyDown(with event: NSEvent) -> Bool {
        guard let selected = tableCellSelection, !selected.item.isLocked else { return false }
        let id = selected.item.id, table = selected.table, head = selected.head
        let flags = event.modifierFlags.intersection([.command, .control, .option, .shift])
        if flags.contains(.option), flags.isDisjoint(with: [.command, .control]), tableOptionKey(event.keyCode, shift: flags.contains(.shift), selected: selected) {
            return true
        }
        switch event.keyCode {
        case 53:
            tableState.clearCells()
            invalidateTableChrome(id)
            invalidateIncrementalDisplay()
            return true
        case 48:
            guard flags.isSubset(of: [.shift]) else { return false }
            switch table.tab(from: head, backward: flags.contains(.shift)) {
            case .cell(let next): selectTableCells(id, anchor: next)
            case .appendRow:
                if commitTable("Add Row", id, { $0.insertRows(at: $0.rowCount) }), let rows = tableItem(id)?.table?.rowCount {
                    selectTableCells(id, anchor: EaselTableCoordinate(row: rows - 1, column: 0))
                }
            case .none: break
            }
            return true
        case 36, 76:
            guard flags.isEmpty else { return false }
            beginEditingTableCell(selected.item, cell: table.anchor(of: tableState.anchor ?? head))
            return true
        case 51, 117:
            guard flags.isSubset(of: [.shift]) else { return false }
            commitTable("Clear Contents", id, hugging: Set(selected.range.rows)) { $0.clearText(selected.range) }
            return true
        case 123, 124, 125, 126:
            let directions: [UInt16: EaselTableDirection] = [123: .left, 124: .right, 125: .down, 126: .up]
            let direction = directions[event.keyCode] ?? .down
            if flags == [.shift] {
                selectTableCells(id, anchor: tableState.anchor ?? head, head: table.extended(head, direction))
            } else if flags.isEmpty {
                selectTableCells(id, anchor: table.step(from: head, direction))
            } else {
                return false
            }
            return true
        default:
            break
        }
        let printable: (String) -> Bool = { text in
            !text.isEmpty && text != " " && text.unicodeScalars.allSatisfy { !CharacterSet.controlCharacters.contains($0) && !(0xF700...0xF8FF).contains($0.value) }
        }
        let typed = event.characters ?? ""
        guard flags.isDisjoint(with: [.command, .control]), printable(typed) || (typed.isEmpty && printable(event.charactersIgnoringModifiers ?? "")) else { return false }
        beginEditingTableCell(selected.item, cell: table.anchor(of: tableState.anchor ?? head), selectingAll: true)
        guard let text = editor, editingID == id else { return true }
        text.keyDown(with: event)
        return true
    }

    private func tableOptionKey(_ keyCode: UInt16, shift: Bool,
                                selected: (item: EaselItem, table: EaselTable, range: EaselTableRange, head: EaselTableCoordinate)) -> Bool {
        let id = selected.item.id, table = selected.table, range = selected.range
        switch keyCode {
        case 36, 76:
            if shift { insertTableColumns(id, at: range.columns.upperBound + 1) } else { insertTableRows(id, at: range.rows.upperBound + 1) }
        case 125, 126:
            guard let destination = table.destination(moving: range.rows, by: keyCode == 126 ? -1 : 1, along: .rows) else { NSSound.beep(); return true }
            if commitTable(range.rows.count == 1 ? "Move Row" : "Move Rows", id, { $0.moveRows(range.rows, to: destination) }) {
                selectTableCells(id, anchor: EaselTableCoordinate(row: destination, column: range.columns.lowerBound),
                                 head: EaselTableCoordinate(row: destination + range.rows.count - 1, column: range.columns.upperBound))
            }
        case 123, 124:
            guard let destination = table.destination(moving: range.columns, by: keyCode == 123 ? -1 : 1, along: .columns) else { NSSound.beep(); return true }
            if commitTable(range.columns.count == 1 ? "Move Column" : "Move Columns", id, { $0.moveColumns(range.columns, to: destination) }) {
                selectTableCells(id, anchor: EaselTableCoordinate(row: range.rows.lowerBound, column: destination),
                                 head: EaselTableCoordinate(row: range.rows.upperBound, column: destination + range.columns.count - 1))
            }
        case 30, 33:
            let delta = keyCode == 30 ? 10.0 : -10.0
            if shift {
                let minimums = tableRowMinimums(selected.item, table)
                commitTable("Resize Row", id) { table in
                    var changed = false
                    for row in range.rows {
                        changed = table.setHeight(table.rowHeights[row] + delta, row: row,
                                                  minimum: minimums.indices.contains(row) ? minimums[row] : EaselTable.minimumRowHeight) || changed
                    }
                    return changed
                }
            } else {
                commitTable("Resize Column", id) { table in
                    var changed = false
                    for column in range.columns { changed = table.setWidth(table.columnWidths[column] + delta, column: column) || changed }
                    return changed
                }
            }
        case 49:
            if shift {
                selectTableCells(id, anchor: EaselTableCoordinate(row: 0, column: range.columns.lowerBound),
                                 head: EaselTableCoordinate(row: table.rowCount - 1, column: range.columns.upperBound))
            } else {
                selectTableCells(id, anchor: EaselTableCoordinate(row: range.rows.lowerBound, column: 0),
                                 head: EaselTableCoordinate(row: range.rows.upperBound, column: table.columnCount - 1))
            }
        default:
            return false
        }
        return true
    }

    func insertTableColumns(_ id: UUID, at index: Int, count: Int = 1) {
        guard let table = tableItem(id)?.table else { return }
        let width = table.columnWidths.indices.contains(index - 1) ? table.columnWidths[index - 1] : (table.columnWidths.first ?? EaselTable.defaultColumnWidth)
        guard commitTable(count == 1 ? "Add Column" : "Add Columns", id, { $0.insertColumns(at: index, count: count, width: width) }) else {
            if table.columnCount + count > EaselTable.maximumColumns || table.rowCount * (table.columnCount + count) > EaselTable.maximumCells {
                NSSound.beep()
            }
            return
        }
        selectTableCells(id, anchor: EaselTableCoordinate(row: 0, column: min(index, table.columnCount)))
    }

    func insertTableRows(_ id: UUID, at index: Int, count: Int = 1) {
        guard let table = tableItem(id)?.table else { return }
        guard commitTable(count == 1 ? "Add Row" : "Add Rows", id, { $0.insertRows(at: index, count: count) }) else {
            if table.rowCount + count > EaselTable.maximumRows || (table.rowCount + count) * table.columnCount > EaselTable.maximumCells {
                NSSound.beep()
            }
            return
        }
        selectTableCells(id, anchor: EaselTableCoordinate(row: min(index, table.rowCount), column: 0))
    }

    func mergeTableCells() {
        guard let selected = tableCellSelection, selected.table.canMerge(selected.range) else { return }
        let filled = selected.range.cells.compactMap { cell -> EaselTableCell? in
            guard !selected.table.isCovered(cell), let value = selected.table.cell(cell),
                  !value.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return value
        }
        var content: EaselTableCell?
        if filled.count == 1, let only = filled.first {
            content = EaselTableCell(text: only.text, richText: only.richText)
        } else if filled.count > 1 {
            let style = selected.item.resolvedTextStyle
            let joined = NSMutableAttributedString()
            for (index, value) in filled.enumerated() {
                let part = EaselRichTextCodec.attributed(value.text, richText: value.richText, style: style, color: selected.item.color)
                if index > 0 { joined.append(NSAttributedString(string: "\n", attributes: part.attributes(at: 0, effectiveRange: nil))) }
                joined.append(part)
            }
            if let payload = try? EaselStyledText.capture(joined, style: style, color: selected.item.color),
               payload.text.utf8.count <= EaselTable.maximumCellBytes {
                content = EaselTableCell(text: payload.text, richText: payload.richText)
            } else {
                content = EaselTableCell(text: EaselTableData.clipped(selected.table.joinedText(selected.range), bytes: EaselTable.maximumCellBytes))
            }
        }
        var merged: EaselTableMerge?
        guard commitTable("Merge Cells", selected.item.id, hugging: Set(selected.range.rows), { table in
            merged = table.merge(selected.range, content: content)
            return merged != nil
        }), let merged else { return }
        selectTableCells(selected.item.id, anchor: merged.anchor)
    }

    func unmergeTableCells() {
        guard let selected = tableCellSelection, selected.table.hasMerges(in: selected.range) else { return }
        commitTable("Unmerge Cells", selected.item.id) { $0.unmerge(selected.range) }
    }

    func clearTableCells() {
        guard let selected = tableCellSelection else { return }
        commitTable("Clear Contents", selected.item.id, hugging: Set(selected.range.rows)) { $0.clearText(selected.range) }
    }

    func setTableCellFill(_ fill: String?) {
        guard let selected = tableCellSelection else {
            guard let item = selectedTable, let table = item.table else { return }
            commitTable("Color", item.id) { $0.setFill(fill, in: table.all) }
            return
        }
        commitTable("Color", selected.item.id) { $0.setFill(fill, in: selected.range) }
    }

    var tableSelectionFill: String?? {
        if let selected = tableCellSelection { return selected.table.commonFill(selected.range) }
        guard let table = selectedTable?.table else { return nil }
        return table.commonFill(table.all)
    }

    func deleteTableRows() {
        guard let selected = tableCellSelection, selected.range.rows.count < selected.table.rowCount else { return }
        let rows = selected.range.rows
        guard commitTable(rows.count == 1 ? "Delete Row" : "Delete Rows", selected.item.id, { $0.removeRows(rows) }),
              let table = tableItem(selected.item.id)?.table else { return }
        selectTableCells(selected.item.id, anchor: EaselTableCoordinate(row: min(rows.lowerBound, table.rowCount - 1), column: selected.range.columns.lowerBound))
    }

    func deleteTableColumns() {
        guard let selected = tableCellSelection, selected.range.columns.count < selected.table.columnCount else { return }
        let columns = selected.range.columns
        guard commitTable(columns.count == 1 ? "Delete Column" : "Delete Columns", selected.item.id, { $0.removeColumns(columns) }),
              let table = tableItem(selected.item.id)?.table else { return }
        selectTableCells(selected.item.id, anchor: EaselTableCoordinate(row: selected.range.rows.lowerBound, column: min(columns.lowerBound, table.columnCount - 1)))
    }

    func duplicateTableRows() {
        guard let rows = tableSelectedRows(), let selected = tableCellSelection else { return }
        guard commitTable(rows.count == 1 ? "Duplicate Row" : "Duplicate Rows", selected.item.id, { $0.duplicateRows(rows) }) else { return }
        selectTableCells(selected.item.id, anchor: EaselTableCoordinate(row: rows.upperBound + 1, column: 0),
                         head: EaselTableCoordinate(row: rows.upperBound + rows.count, column: selected.table.columnCount - 1))
    }

    @discardableResult
    func duplicateTableRowsOrColumns() -> Bool {
        let rows = tableSelectedRows(), columns = tableSelectedColumns()
        if rows != nil, columns == nil { duplicateTableRows(); return true }
        if columns != nil, rows == nil { duplicateTableColumns(); return true }
        return false
    }

    func duplicateTableColumns() {
        guard let columns = tableSelectedColumns(), let selected = tableCellSelection else { return }
        guard commitTable(columns.count == 1 ? "Duplicate Column" : "Duplicate Columns", selected.item.id, { $0.duplicateColumns(columns) }) else { return }
        selectTableCells(selected.item.id, anchor: EaselTableCoordinate(row: 0, column: columns.upperBound + 1),
                         head: EaselTableCoordinate(row: selected.table.rowCount - 1, column: columns.upperBound + columns.count))
    }

    func tableSource(from pasteboard: NSPasteboard, intoCells: Bool) -> (table: EaselTable, measured: Bool, trimmed: Bool)? {
        if let data = pasteboard.data(forType: EaselTableMetrics.clipboardType), data.count <= EaselStore.maximumDocumentBytes,
           let table = try? JSONDecoder().decode(EaselTable.self, from: data), (try? table.validate()) != nil {
            return (table, true, false)
        }
        let limit = intoCells ? EaselTable.maximumCells : EaselTable.maximumPastedCells
        let styled = pasteboard.availableType(from: [EaselStyledText.pasteboardType, EaselStyledText.previousPasteboardType,
                                                     EaselStyledText.legacyPasteboardType]) != nil
        if !styled {
            let plain = pasteboard.string(forType: .string)
            let html = pasteboard.string(forType: .html) ?? pasteboard.data(forType: .html).flatMap { String(data: $0, encoding: .utf8) }
            if let html, EaselTableData.readsHTMLTable(plainText: plain, intoCells: intoCells),
               html.utf8.count <= EaselTableData.maximumInputCharacters, let grid = EaselTableData.html(html),
               intoCells || grid.rowCount * grid.columnCount >= 2, let imported = EaselTableData.imported(grid, limit: limit) {
                return (imported.table, false, imported.trimmed)
            }
            if let plain, let grid = EaselTableData.spreadsheetText(plain), let imported = EaselTableData.imported(grid, limit: limit) {
                return (imported.table, false, imported.trimmed)
            }
            if let data = pasteboard.data(forType: EaselTableMetrics.csvType), data.count <= EaselTableData.maximumInputCharacters,
               let text = String(data: data, encoding: .utf8), let grid = EaselTableData.csv(text),
               let imported = EaselTableData.imported(grid, limit: limit) {
                return (imported.table, false, imported.trimmed)
            }
            if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
               urls.count == 1, let url = urls.first, ["csv", "tsv"].contains(url.pathExtension.lowercased()),
               let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]), values.isRegularFile == true,
               (values.fileSize ?? Int.max) <= EaselTableData.maximumInputCharacters,
               let data = try? Data(contentsOf: url), let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) {
                let grid: EaselTableGrid? = url.pathExtension.lowercased() == "tsv" ? EaselTableData.delimited(text, separator: "\t") : EaselTableData.csv(text)
                if let grid, let imported = EaselTableData.imported(grid, limit: limit) { return (imported.table, false, imported.trimmed) }
            }
        }
        guard intoCells else { return nil }
        if let styledText = try? EaselStyledText.read(from: pasteboard) {
            var table = EaselTable.blank(columns: 1, rows: 1)
            let fits = styledText.text.utf8.count <= EaselTable.maximumCellBytes
            table.cells[0][0] = EaselTableCell(text: EaselTableData.clipped(styledText.text, bytes: EaselTable.maximumCellBytes),
                                               richText: fits ? styledText.richText : nil)
            return (table, false, !fits)
        }
        if let plain = try? EaselStyledText.plainText(from: pasteboard) {
            var table = EaselTable.blank(columns: 1, rows: 1)
            table.cells[0][0].text = EaselTableData.clipped(plain, bytes: EaselTable.maximumCellBytes)
            return (table, false, table.cells[0][0].text.utf8.count < plain.utf8.count)
        }
        return nil
    }

    func presentTableNotice(_ label: String, detail: String? = nil) {
        guard let controller = window?.windowController, controller.responds(to: EaselTableNotice.action) else { return }
        _ = controller.perform(EaselTableNotice.action, with: EaselTableNotice(label: label, detail: detail))
    }

    private func announceTableTrim(_ detail: String) {
        presentTableNotice("Kept what fits", detail: detail)
        NSAccessibility.post(element: self, notification: .announcementRequested,
                             userInfo: [.announcement: "Kept what fits. " + detail, .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }

    func readTablePasteboard(_ pasteboard: NSPasteboard) -> Bool {
        if let selected = tableCellSelection, editor == nil, !selected.item.isLocked,
           let source = tableSource(from: pasteboard, intoCells: true) {
            var placed: EaselTableRange?
            let filling = selected.range.isSingleCell ? nil : selected.range
            if commitTable("Paste Cells", selected.item.id, hugging: Set(selected.table.all.rows), { table in
                placed = table.paste(source.table, at: selected.range.topLeft, filling: filling)
                return placed != nil
            }), let placed {
                selectTableCells(selected.item.id, anchor: placed.topLeft,
                                 head: EaselTableCoordinate(row: placed.rows.upperBound, column: placed.columns.upperBound))
                if source.trimmed || placed.rows.count < source.table.rowCount || placed.columns.count < source.table.columnCount {
                    announceTableTrim("Tables hold up to 100 rows, 100 columns and 10,000 cells.")
                }
            }
            return true
        }
        guard fixedCanvasSize == nil, let source = tableSource(from: pasteboard, intoCells: false) else { return false }
        cancelPointerInteraction()
        guard finishEditing() else { return true }
        var table = source.table
        if !source.measured { measureTableColumns(&table) }
        let frame = EaselRect(x: max(30, Double(visibleRect.midX) - table.width / 2), y: max(0, Double(visibleRect.minY) + 70),
                              width: table.width, height: table.height)
        var item = EaselItem(kind: .table, frame: frame, zIndex: (session.document.items.map(\.zIndex).max() ?? 0) + 1)
        item.table = table
        guard addTable(item, name: "Paste table", selectFirstCell: false) else { return false }
        if source.trimmed { announceTableTrim("A pasted table keeps up to 500 cells and 100 columns.") }
        return true
    }

    private func measureTableColumns(_ table: inout EaselTable) {
        let font = EaselTextAppearance.font(EaselTextStyle())
        for column in 0..<table.columnCount {
            var widest: CGFloat = 0
            for row in 0..<table.rowCount {
                let cell = EaselTableCoordinate(row: row, column: column)
                guard !table.isCovered(cell), table.span(of: cell).columns.count == 1, let text = table.cell(cell)?.text, !text.isEmpty else { continue }
                for line in text.split(separator: "\n").prefix(20) {
                    widest = max(widest, (String(line.prefix(200)) as NSString).size(withAttributes: [.font: font]).width)
                }
            }
            table.columnWidths[column] = min(320, max(96, Double(ceil(widest)) + 24))
        }
    }

    func copyTableCells() -> Bool {
        guard editor == nil, let item = selectedTable, let table = item.table else { return false }
        let range = tableCellSelection?.range ?? table.all
        guard let slice = table.slice(range), let data = try? JSONEncoder().encode(slice), data.count <= EaselStore.maximumDocumentBytes else { return true }
        let board = NSPasteboard.general
        board.clearContents()
        let entry = NSPasteboardItem()
        entry.setData(data, forType: EaselTableMetrics.clipboardType)
        entry.setString(EaselTableData.html(slice), forType: .html)
        entry.setString(EaselTableData.tsv(slice), forType: .string)
        if !board.writeObjects([entry]) { onError?(CocoaError(.fileWriteUnknown)) }
        return true
    }

    func exportTableCSV() {
        guard let item = selectedTable, let table = item.table, let window, window.attachedSheet == nil else { return }
        let range = tableCellSelection.flatMap { $0.range.isSingleCell ? nil : $0.range }
        let csv = "\u{FEFF}" + EaselTableData.csv(table, range: range)
        let panel = NSSavePanel()
        panel.title = "Export Table"
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = EaselVectorExport.exportFileName(session.document.title, fileExtension: "csv")
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let destination = panel.url else { return }
            MainActor.assumeIsolated {
                do {
                    try Data(csv.utf8).write(to: destination, options: .atomic)
                    self?.presentTableNotice("Exported \(destination.lastPathComponent)")
                } catch {
                    self?.onError?(error)
                }
            }
        }
    }

    func convertTableToStickies() {
        guard let item = selectedTable, !item.isLocked else { return }
        cancelPointerInteraction()
        guard finishEditing() else { return }
        var stickies = EaselTableGeometry.stickies(from: item, fill: { fill in
            guard let fill else { return nil }
            if let color = EaselPalette.color(for: fill, role: .fill), let sticky = EaselPalette.hex(color, role: .sticky) { return sticky }
            return fill
        }, textHeight: { EaselStickyText.height($0) })
        guard !stickies.isEmpty else { NSSound.beep(); return }
        let base = (session.document.items.map(\.zIndex).max() ?? 0) + 1
        for index in stickies.indices { stickies[index].zIndex = base + index }
        guard commit("Convert to stickies", { document in
            document = EaselDependents.removing([item.id], from: document)
            document.items.append(contentsOf: stickies)
        }) else { return }
        selection = Set(stickies.map(\.id))
    }

    private func targetTableCell(at point: NSPoint) {
        guard editor == nil, let item = selectedTable, !item.isLocked, let table = item.table,
              let cell = EaselTableLayout(table: table, frame: item.frame).cell(at: EaselPoint(point)).map(table.anchor) else { return }
        if let selected = tableCellSelection, selected.range.contains(cell) { return }
        selectTableCells(item.id, anchor: cell)
    }

    func addTableMenuItems(to menu: NSMenu) {
        if let event = NSApp.currentEvent, event.window === window, [.rightMouseDown, .leftMouseDown].contains(event.type) {
            targetTableCell(at: convert(event.locationInWindow, from: nil))
        }
        guard let item = selectedTable, item.table != nil else { return }
        let token = EaselTableMenuToken(table: item.id)
        func add(_ title: String, _ action: Selector, to target: NSMenu = menu, token value: EaselTableMenuToken? = nil) {
            let row = NSMenuItem(title: title, action: action, keyEquivalent: "")
            row.target = self
            row.representedObject = value ?? token
            target.addItem(row)
        }
        menu.addItem(.separator())
        if let selected = tableCellSelection {
            add("Insert Row Above", #selector(tableInsertRowAbove(_:)))
            add("Insert Row Below", #selector(tableInsertRowBelow(_:)))
            add("Insert Column Left", #selector(tableInsertColumnLeft(_:)))
            add("Insert Column Right", #selector(tableInsertColumnRight(_:)))
            if tableSelectedRows() != nil { add(selected.range.rows.count == 1 ? "Duplicate Row" : "Duplicate Rows", #selector(tableDuplicateRows(_:))) }
            if tableSelectedColumns() != nil { add(selected.range.columns.count == 1 ? "Duplicate Column" : "Duplicate Columns", #selector(tableDuplicateColumns(_:))) }
            menu.addItem(.separator())
            if selected.table.hasMerges(in: selected.range) { add("Unmerge Cells", #selector(tableUnmergeCells(_:))) }
            else { add("Merge Cells", #selector(tableMergeCells(_:))) }
            add("Clear Contents", #selector(tableClearContents(_:)))
        } else {
            add("Add Row", #selector(tableAddRow(_:)))
            add("Add Column", #selector(tableAddColumn(_:)))
            menu.addItem(.separator())
        }
        let colors = NSMenu(title: "Color")
        let dark = NoteTheme.isDark(effectiveAppearance)
        add("Default", #selector(tableSetFill(_:)), to: colors, token: EaselTableMenuToken(table: item.id))
        for color in EaselPalette.colors(for: .fill) {
            guard let hex = EaselPalette.hex(color, role: .fill) else { continue }
            add(color.title(dark: dark), #selector(tableSetFill(_:)), to: colors, token: EaselTableMenuToken(table: item.id, fill: hex))
            colors.items.last?.showImage(tableSwatch(EaselInk.color(hex, adaptive: adaptsInk, role: .fill)))
        }
        let current = tableSelectionFill
        for row in colors.items {
            let fill = (row.representedObject as? EaselTableMenuToken)?.fill
            if let current, current == fill { row.state = .on }
        }
        let colorItem = NSMenuItem(title: "Color", action: nil, keyEquivalent: "")
        colorItem.submenu = colors
        menu.addItem(colorItem)
        if let selected = tableCellSelection {
            menu.addItem(.separator())
            add(selected.range.rows.count == 1 ? "Delete Row" : "Delete Rows", #selector(tableDeleteRows(_:)))
            add(selected.range.columns.count == 1 ? "Delete Column" : "Delete Columns", #selector(tableDeleteColumns(_:)))
        }
        menu.addItem(.separator())
        add("Export Table as CSV…", #selector(tableExportCSV(_:)))
        add("Convert to Stickies", #selector(tableConvertToStickies(_:)))
    }

    private func tableSwatch(_ color: NSColor) -> NSImage {
        NSImage(size: NSSize(width: 12, height: 12), flipped: false) { bounds in
            let dot = NSBezierPath(ovalIn: bounds.insetBy(dx: 0.5, dy: 0.5))
            color.setFill()
            dot.fill()
            NoteTheme.menuHairline.setStroke()
            dot.lineWidth = 1
            dot.stroke()
            return true
        }
    }

    private func tableMenuTarget(_ sender: Any?) -> EaselItem? {
        guard let token = (sender as? NSMenuItem)?.representedObject as? EaselTableMenuToken else { return selectedTable }
        guard let item = selectedTable, item.id == token.table else { return nil }
        return item
    }

    func validateTableMenuItem(_ menuItem: NSMenuItem) -> Bool? {
        guard let action = menuItem.action else { return nil }
        if let command = TextFormatCommand(menuItem), let valid = tableFormatAvailable(command) {
            if let emphasis = Self.tableEmphasis(command) { menuItem.state = tableCellsHaveEmphasis(emphasis) ? .on : .off }
            return valid
        }
        if action == #selector(copy(_:)), editor == nil, selectedTable != nil { return true }
        let tableActions: [Selector] = [#selector(tableInsertRowAbove(_:)), #selector(tableInsertRowBelow(_:)), #selector(tableInsertColumnLeft(_:)),
            #selector(tableInsertColumnRight(_:)), #selector(tableMergeCells(_:)), #selector(tableUnmergeCells(_:)), #selector(tableClearContents(_:)),
            #selector(tableDeleteRows(_:)), #selector(tableDeleteColumns(_:)), #selector(tableDuplicateRows(_:)), #selector(tableDuplicateColumns(_:)),
            #selector(tableSetFill(_:)), #selector(tableAddRow(_:)), #selector(tableAddColumn(_:)), #selector(tableExportCSV(_:)),
            #selector(tableConvertToStickies(_:))]
        guard tableActions.contains(action) else { return nil }
        guard let item = tableMenuTarget(menuItem), let table = item.table else { return false }
        let locked = item.isLocked
        let selected = tableCellSelection
        switch action {
        case #selector(tableMergeCells(_:)): return !locked && selected.map { $0.table.canMerge($0.range) } == true
        case #selector(tableUnmergeCells(_:)): return !locked && selected.map { $0.table.hasMerges(in: $0.range) } == true
        case #selector(tableClearContents(_:)):
            return !locked && selected.map { range in range.range.cells.contains { !(table.cell($0)?.text.isEmpty ?? true) } } == true
        case #selector(tableDeleteRows(_:)): return !locked && selected.map { $0.range.rows.count < table.rowCount } == true
        case #selector(tableDeleteColumns(_:)): return !locked && selected.map { $0.range.columns.count < table.columnCount } == true
        case #selector(tableInsertRowAbove(_:)), #selector(tableInsertRowBelow(_:)), #selector(tableAddRow(_:)):
            return !locked && table.rowCount < EaselTable.maximumRows && (table.rowCount + 1) * table.columnCount <= EaselTable.maximumCells
        case #selector(tableInsertColumnLeft(_:)), #selector(tableInsertColumnRight(_:)), #selector(tableAddColumn(_:)):
            return !locked && table.columnCount < EaselTable.maximumColumns && table.rowCount * (table.columnCount + 1) <= EaselTable.maximumCells
        case #selector(tableExportCSV(_:)): return window?.attachedSheet == nil
        case #selector(tableConvertToStickies(_:)): return !locked && table.visibleCells.contains { !(table.cell($0)?.text.isEmpty ?? true) }
        default: return !locked
        }
    }

    @objc func tableInsertRowAbove(_ sender: Any?) {
        guard let selected = tableCellSelection, tableMenuTarget(sender)?.id == selected.item.id else { return }
        insertTableRows(selected.item.id, at: selected.range.rows.lowerBound)
    }

    @objc func tableInsertRowBelow(_ sender: Any?) {
        guard let selected = tableCellSelection, tableMenuTarget(sender)?.id == selected.item.id else { return }
        insertTableRows(selected.item.id, at: selected.range.rows.upperBound + 1)
    }

    @objc func tableInsertColumnLeft(_ sender: Any?) {
        guard let selected = tableCellSelection, tableMenuTarget(sender)?.id == selected.item.id else { return }
        insertTableColumns(selected.item.id, at: selected.range.columns.lowerBound)
    }

    @objc func tableInsertColumnRight(_ sender: Any?) {
        guard let selected = tableCellSelection, tableMenuTarget(sender)?.id == selected.item.id else { return }
        insertTableColumns(selected.item.id, at: selected.range.columns.upperBound + 1)
    }

    @objc func tableAddRow(_ sender: Any?) {
        guard let item = tableMenuTarget(sender), let table = item.table else { return }
        insertTableRows(item.id, at: table.rowCount)
    }

    @objc func tableAddColumn(_ sender: Any?) {
        guard let item = tableMenuTarget(sender), let table = item.table else { return }
        insertTableColumns(item.id, at: table.columnCount)
    }

    @objc func tableMergeCells(_ sender: Any?) { if tableMenuTarget(sender) != nil { mergeTableCells() } }
    @objc func tableUnmergeCells(_ sender: Any?) { if tableMenuTarget(sender) != nil { unmergeTableCells() } }
    @objc func tableClearContents(_ sender: Any?) { if tableMenuTarget(sender) != nil { clearTableCells() } }
    @objc func tableDeleteRows(_ sender: Any?) { if tableMenuTarget(sender) != nil { deleteTableRows() } }
    @objc func tableDeleteColumns(_ sender: Any?) { if tableMenuTarget(sender) != nil { deleteTableColumns() } }
    @objc func tableDuplicateRows(_ sender: Any?) { if tableMenuTarget(sender) != nil { duplicateTableRows() } }
    @objc func tableDuplicateColumns(_ sender: Any?) { if tableMenuTarget(sender) != nil { duplicateTableColumns() } }
    @objc func tableExportCSV(_ sender: Any?) { if tableMenuTarget(sender) != nil { exportTableCSV() } }
    @objc func tableConvertToStickies(_ sender: Any?) { if tableMenuTarget(sender) != nil { convertTableToStickies() } }

    @objc func tableSetFill(_ sender: Any?) {
        guard tableMenuTarget(sender) != nil, let token = (sender as? NSMenuItem)?.representedObject as? EaselTableMenuToken else { return }
        setTableCellFill(token.fill)
    }
}


extension EaselCanvasView {
    func cutTableCells() -> Bool {
        guard editor == nil, let selected = tableCellSelection, !selected.item.isLocked else { return false }
        guard copyTableCells() else { return false }
        commitTable("Cut Cells", selected.item.id, hugging: Set(selected.range.rows)) { $0.clearText(selected.range) }
        return true
    }

    private var tableFormattingTarget: (item: EaselItem, range: EaselTableRange)? {
        guard editor == nil else { return nil }
        if let selected = tableCellSelection, !selected.item.isLocked { return (selected.item, selected.range) }
        guard let item = selectedTable, !item.isLocked, let table = item.table else { return nil }
        return (item, table.all)
    }

    @discardableResult
    private func formatTableCells(_ name: String, _ change: (NSMutableAttributedString) -> Void) -> Bool {
        guard let target = tableFormattingTarget else { return false }
        let style = target.item.resolvedTextStyle, color = target.item.color
        return commitTable(name, target.item.id, hugging: Set(target.range.rows)) { table in
            var changed = false
            for cell in table.expanded(target.range).cells where !table.isCovered(cell) {
                guard let value = table.cell(cell), !value.text.isEmpty else { continue }
                let attributed = NSMutableAttributedString(attributedString: EaselRichTextCodec.attributed(value.text, richText: value.richText, style: style, color: color))
                change(attributed)
                guard let payload = try? EaselStyledText.capture(attributed, style: style, color: color), payload.richText != value.richText else { continue }
                table.update(cell) { $0.richText = payload.richText }
                changed = true
            }
            return changed
        }
    }

    func tableCellsHaveEmphasis(_ emphasis: EaselStyledTextView.Emphasis) -> Bool {
        guard let target = tableFormattingTarget, let table = target.item.table else { return false }
        var found = false
        for cell in table.expanded(target.range).cells where !table.isCovered(cell) {
            guard let value = table.cell(cell), !value.text.isEmpty else { continue }
            let attributed = EaselRichTextCodec.attributed(value.text, richText: value.richText, style: target.item.resolvedTextStyle, color: target.item.color)
            var all = true
            attributed.enumerateAttributes(in: NSRange(location: 0, length: attributed.length)) { attributes, _, stop in
                let traits = (attributes[.font] as? NSFont)?.fontDescriptor.symbolicTraits ?? []
                let on: Bool
                switch emphasis {
                case .bold: on = traits.contains(.bold)
                case .italic: on = traits.contains(.italic)
                case .underline: on = (attributes[.underlineStyle] as? Int ?? 0) != 0
                case .strikethrough: on = (attributes[.strikethroughStyle] as? Int ?? 0) != 0
                }
                if !on { all = false; stop.pointee = true }
            }
            guard all else { return false }
            found = true
        }
        return found
    }

    @discardableResult
    func toggleTableCellsEmphasis(_ emphasis: EaselStyledTextView.Emphasis) -> Bool {
        let enabled = !tableCellsHaveEmphasis(emphasis)
        return formatTableCells(emphasis.rawValue.capitalized) { value in
            let range = NSRange(location: 0, length: value.length)
            switch emphasis {
            case .bold, .italic:
                let trait: NSFontTraitMask = emphasis == .bold ? .boldFontMask : .italicFontMask
                value.enumerateAttribute(.font, in: range) { font, part, _ in
                    guard let font = font as? NSFont else { return }
                    let next = enabled ? NSFontManager.shared.convert(font, toHaveTrait: trait) : NSFontManager.shared.convert(font, toNotHaveTrait: trait)
                    value.addAttribute(.font, value: next, range: part)
                }
            case .underline:
                if enabled { value.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range) }
                else { value.removeAttribute(.underlineStyle, range: range) }
            case .strikethrough:
                if enabled { value.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range) }
                else { value.removeAttribute(.strikethroughStyle, range: range) }
            }
        }
    }

    static func tableEmphasis(_ command: TextFormatCommand) -> EaselStyledTextView.Emphasis? {
        switch command {
        case .bold: return .bold
        case .italic: return .italic
        case .underline: return .underline
        case .strikethrough: return .strikethrough
        default: return nil
        }
    }

    func tableFormatAvailable(_ command: TextFormatCommand) -> Bool? {
        guard editor == nil, tableFormattingTarget != nil else { return nil }
        switch command {
        case .bold, .italic, .underline, .strikethrough, .bigger, .smaller: return true
        default: return false
        }
    }

    func performTableFormat(_ command: TextFormatCommand) -> Bool {
        guard tableFormatAvailable(command) == true else { return false }
        if let emphasis = Self.tableEmphasis(command) { toggleTableCellsEmphasis(emphasis); return true }
        resizeTableCellsText(by: command == .bigger ? 1 : -1)
        return true
    }

    @discardableResult
    func resizeTableCellsText(by delta: Int) -> Bool {
        guard tableCellSelection != nil, let target = tableFormattingTarget else {
            return setTableTextStyle { $0.size = $0.size.shifted(by: delta) }
        }
        let base = target.item.resolvedTextStyle
        return formatTableCells(delta > 0 ? "Bigger Text" : "Smaller Text") { value in
            value.enumerateAttribute(.font, in: NSRange(location: 0, length: value.length)) { font, part, _ in
                guard let font = font as? NSFont else { return }
                var style = EaselTextAppearance.paletteStyle(font)
                    ?? EaselTextStyle(family: EaselTextAppearance.paletteFamily(font) ?? base.family, size: .body)
                style.size = style.size.shifted(by: delta)
                guard let next = try? EaselTextAppearance.font(style, preservingEmphasisFrom: font) else { return }
                value.addAttribute(.font, value: next, range: part)
            }
        }
    }

    @discardableResult
    func setTableCellsAlignment(_ alignment: NSTextAlignment) -> Bool {
        if isEditingTableCell, let text = editor {
            guard !text.hasMarkedText() else { return false }
            switch alignment {
            case .center: text.alignCenter(nil)
            case .right: text.alignRight(nil)
            default: text.alignLeft(nil)
            }
            return true
        }
        return formatTableCells("Align text") { value in
            let range = NSRange(location: 0, length: value.length)
            var parts: [(NSRange, NSParagraphStyle?)] = []
            value.enumerateAttribute(.paragraphStyle, in: range) { style, part, _ in parts.append((part, style as? NSParagraphStyle)) }
            for (part, style) in parts {
                let next = (style?.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
                next.alignment = alignment
                value.addAttribute(.paragraphStyle, value: next, range: part)
            }
        }
    }

    @discardableResult
    func setTableCellsTextColor(_ hex: String) -> Bool {
        guard EaselTable.isHex(hex) else { return false }
        if tableCellSelection == nil, let item = selectedTable, !item.isLocked, editor == nil,
           let index = session.document.items.firstIndex(where: { $0.id == item.id }), var table = item.table {
            for row in table.cells.indices {
                for column in table.cells[row].indices {
                    guard var rich = table.cells[row][column].richText else { continue }
                    for run in rich.runs.indices {
                        rich.runs[run].attributes.ink = hex + "FF"
                        rich.runs[run].attributes.semanticInk = nil
                    }
                    table.cells[row][column].richText = rich
                }
            }
            var updated = session.document.items[index]
            updated.color = hex
            updated.table = table
            guard updated != session.document.items[index] else { return false }
            return commit("Change color") { document in
                guard let position = document.items.firstIndex(where: { $0.id == item.id }) else { return }
                document.items[position] = updated
            }
        }
        let ink = EaselRichTextCodec.color(hex + "FF")
        return formatTableCells("Change color") { value in
            value.addAttribute(.foregroundColor, value: ink, range: NSRange(location: 0, length: value.length))
        }
    }

    @discardableResult
    func setTableTextStyle(preservingSize: Bool = false, _ mutation: (inout EaselTextStyle) -> Void) -> Bool {
        guard editor == nil, let item = selectedTable, !item.isLocked, let table = item.table,
              let index = session.document.items.firstIndex(where: { $0.id == item.id }) else { return false }
        let original = session.document.items[index]
        var style = original.resolvedTextStyle
        mutation(&style)
        var converted = table
        for row in converted.cells.indices {
            for column in converted.cells[row].indices {
                guard var rich = converted.cells[row][column].richText else { continue }
                for run in rich.runs.indices {
                    let old = EaselRichTextCodec.font(rich.runs[run].attributes.font)
                    guard var next = try? EaselTextAppearance.font(style, preservingEmphasisFrom: old) else { continue }
                    if preservingSize, rich.runs[run].attributes.paragraph?.heading != nil { next = NSFontManager.shared.convert(next, toSize: old.pointSize) }
                    rich.runs[run].attributes.font = EaselRichTextCodec.snapshotFont(next)
                }
                converted.cells[row][column].richText = rich
            }
        }
        var updated = original
        updated.textStyle = style
        let before = tableRowMinimums(original, table)
        var probe = updated
        probe.table = converted
        let after = tableRowMinimums(probe, converted)
        for row in converted.rowHeights.indices where before.indices.contains(row) && after.indices.contains(row) && table.rowHeights[row] <= before[row] + 0.5 {
            converted.rowHeights[row] = min(EaselTable.maximumLength, max(EaselTable.minimumRowHeight, after[row]))
        }
        converted.fitRows(minimums: after)
        updated.table = converted
        updated.frame.width = converted.width
        updated.frame.height = converted.height
        guard updated != original else { return false }
        return commit("Style text") { document in
            guard let position = document.items.firstIndex(where: { $0.id == item.id }) else { return }
            document.items[position] = updated
        }
    }
}

extension EaselCanvasView {
    func tableMenuRows(_ context: EaselMenuContext) -> [EaselMenuRow] {
        guard context.items.count == 1, let first = context.items.first, first.kind == .table, selectedTable?.id == first.id else { return [] }
        targetTableCell(at: NSPoint(x: context.point.x, y: context.point.y))
        guard let item = selectedTable, item.id == first.id, let table = item.table else { return [] }
        let id = item.id, locked = item.isLocked
        let canAddRow = !locked && table.rowCount < EaselTable.maximumRows && (table.rowCount + 1) * table.columnCount <= EaselTable.maximumCells
        let canAddColumn = !locked && table.columnCount < EaselTable.maximumColumns && table.rowCount * (table.columnCount + 1) <= EaselTable.maximumCells
        var rows: [EaselMenuRow] = []
        let current = tableSelectionFill
        let dark = NoteTheme.isDark(effectiveAppearance)
        var colors = [EaselMenuRow(id: "table.color.default", title: "Default", isChecked: current == .some(nil),
                                   perform: guardedMenuAction { $0.setTableCellFill(nil) })]
        for color in EaselPalette.colors(for: .fill) {
            guard let hex = EaselPalette.hex(color, role: .fill) else { continue }
            colors.append(EaselMenuRow(id: "table.color." + color.id, title: color.title(dark: dark), isChecked: current == .some(hex),
                                       perform: guardedMenuAction { $0.setTableCellFill(hex) }))
        }
        if let selected = tableCellSelection {
            let range = selected.range
            rows.append(EaselMenuRow(id: "table.rowAbove", title: "Insert Row Above", symbol: "arrow.up.to.line", isEnabled: canAddRow, separatorBefore: true,
                                     perform: guardedMenuAction { $0.insertTableRows(id, at: range.rows.lowerBound) }))
            rows.append(EaselMenuRow(id: "table.rowBelow", title: "Insert Row Below", symbol: "arrow.down.to.line", isEnabled: canAddRow,
                                     perform: guardedMenuAction { $0.insertTableRows(id, at: range.rows.upperBound + 1) }))
            rows.append(EaselMenuRow(id: "table.columnLeft", title: "Insert Column Left", symbol: "arrow.left.to.line", isEnabled: canAddColumn,
                                     perform: guardedMenuAction { $0.insertTableColumns(id, at: range.columns.lowerBound) }))
            rows.append(EaselMenuRow(id: "table.columnRight", title: "Insert Column Right", symbol: "arrow.right.to.line", isEnabled: canAddColumn,
                                     perform: guardedMenuAction { $0.insertTableColumns(id, at: range.columns.upperBound + 1) }))
            if tableSelectedRows() != nil, tableSelectedColumns() == nil {
                rows.append(EaselMenuRow(id: "table.duplicateRows", title: range.rows.count == 1 ? "Duplicate Row" : "Duplicate Rows",
                                         symbol: "plus.square.on.square", isEnabled: !locked, perform: guardedMenuAction { $0.duplicateTableRows() }))
            } else if tableSelectedColumns() != nil, tableSelectedRows() == nil {
                rows.append(EaselMenuRow(id: "table.duplicateColumns", title: range.columns.count == 1 ? "Duplicate Column" : "Duplicate Columns",
                                         symbol: "plus.square.on.square", isEnabled: !locked, perform: guardedMenuAction { $0.duplicateTableColumns() }))
            }
            if table.hasMerges(in: range) {
                rows.append(EaselMenuRow(id: "table.unmerge", title: "Unmerge Cells", symbol: "arrow.left.and.line.vertical.and.arrow.right",
                                         isEnabled: !locked, separatorBefore: true, perform: guardedMenuAction { $0.unmergeTableCells() }))
            } else {
                rows.append(EaselMenuRow(id: "table.merge", title: "Merge Cells", symbol: "arrow.right.and.line.vertical.and.arrow.left",
                                         isEnabled: !locked && table.canMerge(range), separatorBefore: true, perform: guardedMenuAction { $0.mergeTableCells() }))
            }
            rows.append(EaselMenuRow(id: "table.clear", title: "Clear Contents", symbol: "eraser",
                                     isEnabled: !locked && range.cells.contains { !(table.cell($0)?.text.isEmpty ?? true) },
                                     perform: guardedMenuAction { $0.clearTableCells() }))
            rows.append(EaselMenuRow(id: "table.color", title: "Color", symbol: "paintpalette", isEnabled: !locked, children: colors))
            rows.append(EaselMenuRow(id: "table.deleteRows", title: range.rows.count == 1 ? "Delete Row" : "Delete Rows", symbol: "trash",
                                     isEnabled: !locked && range.rows.count < table.rowCount, isDestructive: true, separatorBefore: true,
                                     perform: guardedMenuAction { $0.deleteTableRows() }))
            rows.append(EaselMenuRow(id: "table.deleteColumns", title: range.columns.count == 1 ? "Delete Column" : "Delete Columns", symbol: "trash",
                                     isEnabled: !locked && range.columns.count < table.columnCount, isDestructive: true,
                                     perform: guardedMenuAction { $0.deleteTableColumns() }))
        } else {
            rows.append(EaselMenuRow(id: "table.addRow", title: "Add Row", symbol: "plus", isEnabled: canAddRow, separatorBefore: true,
                                     perform: guardedMenuAction { canvas in canvas.insertTableRows(id, at: canvas.tableItem(id)?.table?.rowCount ?? table.rowCount) }))
            rows.append(EaselMenuRow(id: "table.addColumn", title: "Add Column", symbol: "plus", isEnabled: canAddColumn,
                                     perform: guardedMenuAction { canvas in canvas.insertTableColumns(id, at: canvas.tableItem(id)?.table?.columnCount ?? table.columnCount) }))
            rows.append(EaselMenuRow(id: "table.color", title: "Color", symbol: "paintpalette", isEnabled: !locked, children: colors))
        }
        rows.append(EaselMenuRow(id: "table.csv", title: "Export Table as CSV…", symbol: "tablecells", isEnabled: window?.attachedSheet == nil,
                                 separatorBefore: true, perform: guardedMenuAction { $0.exportTableCSV() }))
        rows.append(EaselMenuRow(id: "table.stickies", title: "Convert to Stickies", symbol: "note.text",
                                 isEnabled: !locked && table.visibleCells.contains { !(table.cell($0)?.text.isEmpty ?? true) },
                                 perform: guardedMenuAction { $0.convertTableToStickies() }))
        return rows
    }
}
