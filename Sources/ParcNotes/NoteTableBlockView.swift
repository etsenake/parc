import AppKit
import Combine
import ParcCore

struct NoteTableGeometry: Equatable {
    private(set) var columnWidths: [CGFloat]
    private(set) var rowHeights: [CGFloat]
    private(set) var columnEdges: [CGFloat]
    private(set) var rowEdges: [CGFloat]

    init(columnWidths: [CGFloat] = [], rowHeights: [CGFloat] = []) {
        self.columnWidths = columnWidths
        self.rowHeights = rowHeights
        columnEdges = NoteTableMetrics.edges(columnWidths.map(Double.init)).map { CGFloat($0) }
        rowEdges = NoteTableMetrics.edges(rowHeights.map(Double.init)).map { CGFloat($0) }
    }

    var width: CGFloat { columnEdges.last ?? 0 }
    var height: CGFloat { rowEdges.last ?? 0 }
    var rowCount: Int { rowHeights.count }
    var columnCount: Int { columnWidths.count }

    func contains(_ cell: NoteTableCell) -> Bool {
        rowHeights.indices.contains(cell.row) && columnWidths.indices.contains(cell.column)
    }

    func cellRect(_ cell: NoteTableCell) -> NSRect {
        guard contains(cell) else { return .zero }
        return NSRect(x: columnEdges[cell.column], y: rowEdges[cell.row], width: columnWidths[cell.column], height: rowHeights[cell.row])
    }

    func rowRect(_ row: Int) -> NSRect {
        guard rowHeights.indices.contains(row) else { return .zero }
        return NSRect(x: 0, y: rowEdges[row], width: width, height: rowHeights[row])
    }

    func columnRect(_ column: Int) -> NSRect {
        guard columnWidths.indices.contains(column) else { return .zero }
        return NSRect(x: columnEdges[column], y: 0, width: columnWidths[column], height: height)
    }

    func rect(_ range: NoteTableRect) -> NSRect {
        guard let clamped = range.clamped(rows: rowCount, columns: columnCount) else { return .zero }
        return cellRect(clamped.topLeft).union(cellRect(clamped.bottomRight))
    }

    func cell(at point: NSPoint, clamped: Bool) -> NoteTableCell? {
        guard rowCount > 0, columnCount > 0 else { return nil }
        if clamped {
            return NoteTableCell(row: NoteTableMetrics.clampedIndex(at: Double(point.y), sizes: rowHeights.map(Double.init)),
                                 column: NoteTableMetrics.clampedIndex(at: Double(point.x), sizes: columnWidths.map(Double.init)))
        }
        guard let row = NoteTableMetrics.index(at: Double(point.y), sizes: rowHeights.map(Double.init)),
              let column = NoteTableMetrics.index(at: Double(point.x), sizes: columnWidths.map(Double.init)) else { return nil }
        return NoteTableCell(row: row, column: column)
    }

    func reorderedRows(_ order: [Int]) -> NoteTableGeometry {
        NoteTableGeometry(columnWidths: columnWidths, rowHeights: order.map { rowHeights[$0] })
    }

    func reorderedColumns(_ order: [Int]) -> NoteTableGeometry {
        NoteTableGeometry(columnWidths: order.map { columnWidths[$0] }, rowHeights: rowHeights)
    }
}

@MainActor
final class NoteTableBlockView: NoteBlockView {
    enum Axis { case row, column }

    private struct MeasureKey: Hashable {
        var text: NoteText
        var width: Int
        var style: NoteTableCellStyle
    }

    private struct Drag {
        var axis: Axis
        var source: Int
        var target: Int
        var start: NSPoint
        var ghostOrigin: NSPoint
        var ghost: NoteTableGhostView
    }

    private enum Placement {
        case start, end
        case offsets(Range<Int>)
        case x(CGFloat, firstLine: Bool)
    }

    static let cellsPasteboardType = NSPasteboard.PasteboardType("com.parcbrowser.notes.table-cells")
    static let markdownPasteboardType = NSPasteboard.PasteboardType("net.daringfireball.markdown")

    private let scrollView = NoteTableScrollView(frame: .zero)
    private let documentView = NoteTableDocumentView()
    private let surface = NoteTableSurfaceView(frame: .zero)
    private let frameView = NoteTableFrameView()
    private let selectionView = NoteTableSelectionView()
    private let resizeIndicator = NoteTableRuleView(frame: .zero)
    private let addRowBar = NoteTableAddBar(axis: .row)
    private let addColumnBar = NoteTableAddBar(axis: .column)
    private let rowGrip = NoteTableGripView(axis: .row)
    private let columnGrip = NoteTableGripView(axis: .column)
    private let cellMenuButton = NoteTableCellMenuButton(frame: .zero)
    private let cornerHandle = NoteTableCornerHandle(frame: .zero)
    private var rowRules: [NoteTableRuleView] = []
    private var columnRules: [NoteTableRuleView] = []
    private var hosts: [NoteTableCell: NoteTableCellHost] = [:]
    private var pool: [NoteTableCellTextView] = []
    private var pinnedCells: Set<NoteTableCell> = []
    private var heightCache: [MeasureKey: CGFloat] = [:]
    private var outsideClickMonitor: Any?
    private lazy var stamp: NoteTableCellTextView = {
        let view = NoteTableCellTextView()
        view.textContainerInset = .zero
        view.textContainer?.widthTracksTextView = false
        return view
    }()
    private(set) var geometry = NoteTableGeometry()
    private var geometryWidth: CGFloat = -1
    private var geometrySource: NoteTable?
    private var liveWidths: [CGFloat]?
    private var resizingColumn: Int?
    private var hoveredBoundary: Int?
    private var pendingChange: NoteTableChange?
    private var motionGeometry: NoteTableGeometry?
    private var motionSnapshot: (image: NSImage, rect: NSRect)?
    private var pointerRange: (anchor: NoteTableCell, head: NoteTableCell)?
    private var drag: Drag?
    private var settlingDrag: (axis: Axis, index: Int)?
    private var hoverCell: NoteTableCell?
    private var isHovering = false
    private var menuPanel: NoteFloatingPanel?
    private var menuList: NoteMenuList?
    private var menuTarget: (axis: Axis, index: Int)?
    private var cellMenuTarget: NoteTableRect?
    private var previewTable: NoteTable?
    private var isCornerDragging = false
    private var pendingSpanFrames: [NoteTableCell: NSRect]?
    private var pendingSpanGhost: (image: NSImage, rect: NSRect)?
    private var subscription: AnyCancellable?
    private var trackingArea: NSTrackingArea?
    private var pageScrollObserver: NSObjectProtocol?

    override init(block: NoteBlock, editor: NotePageEditor?) {
        super.init(block: block, editor: editor)
        buildViews()
        subscription = editor?.session.changes.sink { [weak self] _ in self?.syncSelection() }
        NoteAnimation.observeReduceMotion(self) { [weak self] in self?.settleMotion() }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    var table: NoteTable {
        var value = previewTable ?? block.props.table ?? NoteTable.empty()
        value.normalize()
        return value
    }

    private var pageSettings: NotePageSettings { editor?.session.page.settings ?? NotePageSettings() }

    private func buildViews() {
        if #available(macOS 14, *) { clipsToBounds = false }
        scrollView.documentView = documentView
        scrollView.onScroll = { [weak self] in self?.scrollDidChange() }
        addSubview(scrollView)
        documentView.addSubview(surface)
        surface.table = self
        surface.addSubview(frameView)
        surface.addSubview(selectionView)
        resizeIndicator.color = NoteTableStyle.resizeLine
        resizeIndicator.isHidden = true
        surface.addSubview(resizeIndicator)
        documentView.addSubview(columnGrip)
        documentView.addSubview(cellMenuButton)
        addSubview(addRowBar)
        addSubview(addColumnBar)
        addSubview(cornerHandle)
        addSubview(rowGrip)
        for bar in [addRowBar, addColumnBar, cornerHandle] as [NSView] { bar.alphaValue = 0 }
        cellMenuButton.alphaValue = 0
        cellMenuButton.isHidden = true
        cellMenuButton.onPress = { [weak self] in self?.openCellMenu() }
        cornerHandle.onPress = { [weak self] event in self?.cornerPressed(event) }
        cornerHandle.onAccessibilityPress = { [weak self] in self?.growByOne() }
        for grip in [rowGrip, columnGrip] {
            grip.alphaValue = 0
            grip.isHidden = true
            grip.onPress = { [weak self] grip, event in self?.gripPressed(grip, event: event) }
            grip.onAccessibilityPress = { [weak self] grip in self?.openMenu(for: grip) }
        }
        addRowBar.onAdd = { [weak self] in self?.appendRow() }
        addColumnBar.onAdd = { [weak self] in self?.appendColumn() }
        addColumnBar.onHoverChange = { [weak self] hovering in if !hovering { self?.pointerLeftColumnBar() } }
    }

    override func update(_ block: NoteBlock) {
        let focused = focusedHost()?.cell
        super.update(block)
        if menuPanel != nil, pendingChange == nil { dismissMenu() }
        guard superview != nil else {
            geometrySource = nil
            return
        }
        reloadContent()
        restoreFocus(previous: focused)
        syncSelection()
    }

    override func measureHeight(width: CGFloat) -> CGFloat {
        let measured = makeGeometry(width: width)
        return NoteTableStyle.topInset + measured.height + NoteTableStyle.barGap + NoteTableStyle.barThickness + NoteTableStyle.bottomInset
    }

    override var handleAnchorY: CGFloat { NoteTableStyle.topInset + min(geometry.rowHeights.first ?? 30, 40) / 2 }

    override var textHosts: [NoteTextHost] {
        hosts.keys.sorted { ($0.row, $0.column) < ($1.row, $1.column) }.compactMap { hosts[$0] }
    }

    override func textHost(for field: NoteTextField) -> NoteTextHost? {
        guard case .cell(let row, let column) = field else { return nil }
        return materialize(NoteTableCell(row: row, column: column))
    }

    override func focus(at offset: Int?, field: NoteTextField = .body) -> Bool {
        var cell = NoteTableCell(row: 0, column: 0)
        if case .cell(let row, let column) = field { cell = NoteTableCell(row: row, column: column) }
        let current = table
        cell.row = min(max(0, cell.row), current.rowCount - 1)
        cell.column = min(max(0, cell.column), current.columnCount - 1)
        return focusCell(cell, placement: offset.map { .offsets($0..<$0) } ?? .end)
    }

    override func readOnlyDidChange() {
        for host in hosts.values { host.cellView.isEditable = !isReadOnly }
        if isReadOnly { hideHoverChrome(animated: false) }
        layoutCellMenuButton()
    }

    override func themeDidChange() {
        super.themeDidChange()
        for view in surface.subviews { view.needsDisplay = true }
        for view in [rowGrip, columnGrip, addRowBar, addColumnBar, cellMenuButton, cornerHandle] as [NSView] { view.needsDisplay = true }
        for host in hosts.values { host.cellView.backdrop.needsDisplay = true }
    }

    override func setFrameSize(_ newSize: NSSize) {
        let changed = newSize != frame.size
        super.setFrameSize(newSize)
        if changed { needsLayout = true }
    }

    override func layout() {
        super.layout()
        if abs(bounds.width - geometryWidth) > 0.5 || geometrySource != table { reloadContent() } else { layoutChrome(); layoutCells() }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let pageScrollObserver { NotificationCenter.default.removeObserver(pageScrollObserver) }
        pageScrollObserver = nil
        guard window != nil, let clip = enclosingScrollView?.contentView else { return }
        clip.postsBoundsChangedNotifications = true
        pageScrollObserver = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: clip, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isVirtualizing else { return }
                self.layoutCells()
            }
        }
        needsLayout = true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        for grip in [rowGrip, columnGrip] where !grip.isHidden && grip.alphaValue > 0.01 {
            if grip.convert(grip.bounds, to: self).contains(local) { return grip }
        }
        if addColumnBar.alphaValue > 0.01, !addColumnBar.isHidden, addColumnBar.frame.contains(local) { return addColumnBar }
        if cornerHandle.alphaValue > 0.01, !cornerHandle.isHidden, cornerHandle.frame.contains(local) { return cornerHandle }
        return super.hitTest(point)
    }

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .group }
    override func accessibilityLabel() -> String? {
        let current = table
        return "Table, \(current.rowCount) \(current.rowCount == 1 ? "row" : "rows"), \(current.columnCount) \(current.columnCount == 1 ? "column" : "columns")"
    }

    private func cellStyle(_ cell: NoteTableCell, in table: NoteTable) -> NoteTableCellStyle {
        let settings = pageSettings
        return NoteTableCellStyle(font: settings.font, small: settings.smallText, header: isHeader(cell, in: table),
                                  alignment: table.alignments.indices.contains(cell.column) ? table.alignments[cell.column] : nil,
                                  color: table.color(at: cell))
    }

    private func isHeader(_ cell: NoteTableCell, in table: NoteTable) -> Bool {
        (table.headerRow && cell.row == 0) || (table.headerColumn && cell.column == 0)
    }

    private func measuredTextHeight(_ text: NoteText, width: CGFloat, style: NoteTableCellStyle) -> CGFloat {
        stamp.configure(style)
        stamp.frame = NSRect(x: 0, y: 0, width: width, height: 100)
        stamp.textContainer?.containerSize = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        stamp.apply(text, selection: nil)
        return stamp.contentHeight()
    }

    private func cellHeight(_ text: NoteText, columnWidth: CGFloat, style: NoteTableCellStyle) -> CGFloat {
        var measured = style
        measured.alignment = nil
        measured.color = nil
        let textWidth = max(8, columnWidth - NoteTableStyle.horizontalPadding * 2)
        let key = MeasureKey(text: text, width: Int(textWidth.rounded()), style: measured)
        if let cached = heightCache[key] { return cached }
        if heightCache.count > 4000 { heightCache.removeAll(keepingCapacity: true) }
        let height = measuredTextHeight(text, width: textWidth, style: measured) + NoteTableStyle.verticalPadding * 2
        heightCache[key] = height
        return height
    }

    private func makeGeometry(width: CGFloat) -> NoteTableGeometry {
        let current = table
        let available = max(0, width)
        let widths = liveWidths ?? NoteTableMetrics.resolvedWidths(current.columnWidths, available: Double(available)).map { CGFloat($0) }
        let edges = NoteTableMetrics.edges(widths.map(Double.init)).map { CGFloat($0) }
        let covered = current.coveredCells
        var heights = Array(repeating: CGFloat(0), count: current.rowCount)
        var tall: [(span: NoteTableMerge, height: CGFloat)] = []
        for (rowIndex, row) in current.rows.enumerated() {
            for (column, text) in row.enumerated() where column < widths.count {
                let cell = NoteTableCell(row: rowIndex, column: column)
                guard !covered.contains(cell) else { continue }
                let span = current.merges.isEmpty ? NoteTableMerge(row: rowIndex, column: column, rowSpan: 1, columnSpan: 1) : current.span(of: cell)
                let last = min(span.lastColumn, widths.count - 1)
                let height = cellHeight(text, columnWidth: edges[last + 1] - edges[column], style: cellStyle(cell, in: current))
                if span.rowSpan > 1 { tall.append((span, height)) } else { heights[rowIndex] = max(heights[rowIndex], height) }
            }
        }
        if heights.contains(0) {
            let settings = pageSettings
            let empty = cellHeight(NoteText(), columnWidth: widths.first ?? 100, style: NoteTableCellStyle(font: settings.font, small: settings.smallText))
            for index in heights.indices where heights[index] == 0 { heights[index] = empty }
        }
        for entry in tall {
            let rows = entry.span.row...min(entry.span.lastRow, heights.count - 1)
            let total = rows.reduce(CGFloat(0)) { $0 + heights[$1] }
            if total < entry.height { heights[rows.upperBound] += entry.height - total }
        }
        return NoteTableGeometry(columnWidths: widths, rowHeights: heights)
    }

    private var displayGeometry: NoteTableGeometry {
        guard let drag else { return geometry }
        let order = visualOrder(drag)
        return drag.axis == .row ? geometry.reorderedRows(order) : geometry.reorderedColumns(order)
    }

    private func visualOrder(_ drag: Drag) -> [Int] {
        var order = Array(0..<(drag.axis == .row ? geometry.rowCount : geometry.columnCount))
        order.remove(at: drag.source)
        order.insert(drag.source, at: drag.target)
        return order
    }

    private func displayRect(_ cell: NoteTableCell, in current: NoteTable) -> NSRect {
        guard !current.merges.isEmpty else { return displayCellRect(cell) }
        let span = current.span(of: cell)
        let first = displayCellRect(span.anchor)
        guard span.cellCount > 1 else { return first }
        return first.union(displayCellRect(NoteTableCell(row: span.lastRow, column: span.lastColumn)))
    }

    private func spanRect(_ cell: NoteTableCell, in current: NoteTable) -> NSRect {
        let span = current.span(of: current.anchor(of: cell))
        return geometry.rect(NoteTableRect(rows: span.rows, columns: span.columns))
    }

    private func displayCellRect(_ cell: NoteTableCell) -> NSRect {
        guard let drag else { return geometry.cellRect(cell) }
        let order = visualOrder(drag)
        let shown = displayGeometry
        switch drag.axis {
        case .row: return shown.cellRect(NoteTableCell(row: order.firstIndex(of: cell.row) ?? cell.row, column: cell.column))
        case .column: return shown.cellRect(NoteTableCell(row: cell.row, column: order.firstIndex(of: cell.column) ?? cell.column))
        }
    }

    private func editorFrame(_ rect: NSRect) -> NSRect {
        NSRect(x: rect.minX + NoteTableStyle.editorEdgeGap, y: rect.minY,
               width: max(1, rect.width - NoteTableStyle.editorEdgeGap * 2), height: rect.height)
    }

    private var hairline: CGFloat { 1 / (window?.backingScaleFactor ?? 2) }

    private var isVirtualizing: Bool {
        window != nil && table.rowCount * table.columnCount > NoteTableStyle.virtualizationThreshold
    }

    private func reloadContent() {
        let previous = geometry
        geometry = makeGeometry(width: bounds.width)
        geometryWidth = bounds.width
        geometrySource = table
        revalidateGrips()
        layoutChrome()
        layoutCells()
        if let change = pendingChange {
            runMotion(change, from: motionGeometry ?? previous)
            pendingChange = nil
            motionGeometry = nil
            motionSnapshot = nil
        }
        if let frames = pendingSpanFrames {
            runSpanMotion(frames, ghost: pendingSpanGhost)
            pendingSpanFrames = nil
            pendingSpanGhost = nil
        }
    }

    private func layoutChrome() {
        let shown = displayGeometry
        let tableHeight = shown.height, tableWidth = shown.width
        let documentWidth = max(bounds.width, tableWidth)
        let scrollHeight = NoteTableStyle.topInset + tableHeight + 1
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        scrollView.frame = NSRect(x: 0, y: 0, width: bounds.width, height: scrollHeight)
        documentView.frame = NSRect(x: 0, y: 0, width: documentWidth, height: scrollHeight)
        surface.frame = NSRect(x: 0, y: NoteTableStyle.topInset, width: tableWidth, height: tableHeight)
        frameView.frame = surface.bounds
        selectionView.frame = surface.bounds
        addColumnBar.frame = NSRect(x: columnBarX(tableWidth: tableWidth), y: NoteTableStyle.topInset,
                                    width: NoteTableStyle.barThickness, height: tableHeight)
        let visibleTable = max(0, min(tableWidth - scrollView.horizontalOffset, bounds.width))
        addRowBar.frame = NSRect(x: 0, y: NoteTableStyle.topInset + tableHeight + NoteTableStyle.barGap,
                                 width: visibleTable, height: NoteTableStyle.barThickness)
        cornerHandle.frame = NSRect(x: columnBarX(tableWidth: tableWidth), y: addRowBar.frame.minY,
                                    width: NoteTableStyle.barThickness, height: NoteTableStyle.barThickness)
        layoutRules(shown, merges: table.merges)
        surface.resizeBoundaries = isReadOnly ? [] : shown.columnEdges.dropFirst().map {
            NSRect(x: $0 - NoteTableStyle.resizeTolerance, y: 0, width: NoteTableStyle.resizeTolerance * 2, height: tableHeight)
        }
        if let column = resizingColumn ?? hoveredBoundary, shown.columnEdges.indices.contains(column + 1) {
            resizeIndicator.isHidden = false
            resizeIndicator.frame = NSRect(x: min(shown.columnEdges[column + 1], tableWidth) - 1, y: 0, width: 2, height: tableHeight)
        } else {
            resizeIndicator.isHidden = true
        }
        layoutGrips(shown)
        CATransaction.commit()
        scrollView.updateFade()
        syncSelection()
    }

    private func columnBarX(tableWidth: CGFloat) -> CGFloat {
        max(0, min(tableWidth - scrollView.horizontalOffset, bounds.width)) + NoteTableStyle.barGap
    }

    private func layoutRules(_ shown: NoteTableGeometry, merges: [NoteTableMerge]) {
        let line = hairline
        func sync(_ rules: inout [NoteTableRuleView], count: Int) {
            while rules.count > count { rules.removeLast().removeFromSuperview() }
            while rules.count < count {
                let rule = NoteTableRuleView(frame: .zero)
                surface.addSubview(rule, positioned: .below, relativeTo: frameView)
                rules.append(rule)
            }
        }
        sync(&rowRules, count: max(0, shown.rowCount - 1))
        sync(&columnRules, count: max(0, shown.columnCount - 1))
        for (index, rule) in rowRules.enumerated() {
            rule.frame = surface.backingAlignedRect(NSRect(x: 0, y: shown.rowEdges[index + 1] - line / 2, width: shown.width, height: line),
                                                    options: .alignAllEdgesNearest)
            rule.gaps = merges.compactMap { merge in
                guard merge.row <= index, merge.lastRow >= index + 1, merge.lastColumn + 1 < shown.columnEdges.count else { return nil }
                return shown.columnEdges[merge.column]...shown.columnEdges[merge.lastColumn + 1]
            }
        }
        for (index, rule) in columnRules.enumerated() {
            rule.frame = surface.backingAlignedRect(NSRect(x: shown.columnEdges[index + 1] - line / 2, y: 0, width: line, height: shown.height),
                                                    options: .alignAllEdgesNearest)
            rule.gaps = merges.compactMap { merge in
                guard merge.column <= index, merge.lastColumn >= index + 1, merge.lastRow + 1 < shown.rowEdges.count else { return nil }
                return shown.rowEdges[merge.row]...shown.rowEdges[merge.lastRow + 1]
            }
        }
    }

    private func revalidateGrips() {
        let current = table
        if let cell = hoverCell, cell.row >= current.rowCount || cell.column >= current.columnCount { hoverCell = nil }
        if let target = menuTarget, target.index >= (target.axis == .row ? current.rowCount : current.columnCount) { dismissMenu() }
        for grip in [rowGrip, columnGrip] where grip.index >= (grip.axis == .row ? current.rowCount : current.columnCount) {
            grip.index = 0
            NoteAnimation.withoutAnimation { grip.alphaValue = 0 }
            grip.isHidden = true
        }
        if let drag, max(drag.source, drag.target) >= (drag.axis == .row ? geometry.rowCount : geometry.columnCount) { abandonDrag() }
    }

    private func abandonDrag() {
        guard let abandoned = drag else { return }
        drag = nil
        for host in hosts.values {
            NoteTableMotion.settle(host.cellView)
            NoteTableMotion.settle(host.cellView.backdrop)
        }
        for rule in rowRules + columnRules { NoteTableMotion.settle(rule) }
        NoteTableMotion.fadeOutAndRemove(abandoned.ghost)
    }

    private func commitComposition() {
        guard let host = focusedHost(), host.cellView.hasMarkedText() else { return }
        host.cellView.unmarkText()
        host.cellView.inputContext?.discardMarkedText()
        editor?.textDidChange(in: host)
    }

    private func layoutGrips(_ shown: NoteTableGeometry) {
        if let cell = hoverCell, shown.contains(cell) || menuTarget != nil {
            let row = menuTarget?.axis == .row ? menuTarget!.index : cell.row
            let column = menuTarget?.axis == .column ? menuTarget!.index : cell.column
            if shown.rowHeights.indices.contains(row) {
                let rect = shown.rowRect(row)
                rowGrip.index = row
                rowGrip.frame = NSRect(x: -NoteTableStyle.rowGripSize.width / 2,
                                       y: NoteTableStyle.topInset + rect.midY - NoteTableStyle.rowGripSize.height / 2,
                                       size: NoteTableStyle.rowGripSize)
            }
            if shown.columnWidths.indices.contains(column) {
                let rect = shown.columnRect(column)
                columnGrip.index = column
                columnGrip.frame = NSRect(x: rect.midX - NoteTableStyle.columnGripSize.width / 2,
                                          y: NoteTableStyle.topInset - NoteTableStyle.columnGripSize.height / 2,
                                          size: NoteTableStyle.columnGripSize)
            }
        }
    }

    private func wantedCells() -> Set<NoteTableCell> {
        let current = table
        if !isVirtualizing { return Set(current.visibleCells) }
        let visible = convert(visibleRect, to: surface)
        let clip = documentView.convert(scrollView.contentView.bounds, to: surface)
        let shown = displayGeometry
        let rows = NoteTableMetrics.visibleRange(from: Double(visible.minY), to: Double(visible.maxY), sizes: shown.rowHeights.map(Double.init))
        let columns = NoteTableMetrics.visibleRange(from: Double(clip.minX), to: Double(clip.maxX), sizes: shown.columnWidths.map(Double.init))
        let extra = Array(pinnedCells) + (focusedHost().map { [$0.cell] } ?? [])
        let kept = NoteTableMetrics.keptCells(rows: rows, columns: columns, also: extra, rowCount: current.rowCount, columnCount: current.columnCount)
        return current.merges.isEmpty ? kept : Set(kept.map { current.anchor(of: $0) })
    }

    private func layoutCells() {
        let current = table
        let wanted = wantedCells()
        let focused = focusedHost()
        for (cell, host) in hosts where !wanted.contains(cell)
            && (host !== focused || cell.row >= current.rowCount || cell.column >= current.columnCount || current.isCovered(cell)) {
            recycle(host)
            hosts[cell] = nil
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for cell in wanted {
            let host = hosts[cell] ?? makeHost(cell)
            bind(host, cell: cell, table: current)
        }
        CATransaction.commit()
    }

    private func makeHost(_ cell: NoteTableCell) -> NoteTableCellHost {
        let view = pool.popLast() ?? NoteTableCellTextView()
        view.table = self
        view.editor = editor
        view.isEditable = !isReadOnly
        view.isSelectable = true
        view.alphaValue = 1
        view.textContainerInset = NSSize(width: NoteTableStyle.horizontalPadding - NoteTableStyle.editorEdgeGap, height: NoteTableStyle.verticalPadding)
        view.textContainer?.widthTracksTextView = true
        view.textContainer?.containerSize = NSSize(width: 100, height: CGFloat.greatestFiniteMagnitude)
        let host = NoteTableCellHost(blockID: blockID, cell: cell, view: view)
        view.host = host
        view.backdrop.alphaValue = 1
        surface.addSubview(view.backdrop, positioned: .below, relativeTo: nil)
        surface.addSubview(view, positioned: .below, relativeTo: frameView)
        hosts[cell] = host
        return host
    }

    private func recycle(_ host: NoteTableCellHost) {
        let view = host.cellView
        NoteTableMotion.settle(view)
        NoteTableMotion.settle(view.backdrop)
        view.backdrop.removeFromSuperview()
        view.removeFromSuperview()
        view.host = nil
        if pool.count < 24 { pool.append(view) }
    }

    private func bind(_ host: NoteTableCellHost, cell: NoteTableCell, table current: NoteTable) {
        guard current.rows.indices.contains(cell.row), current.rows[cell.row].indices.contains(cell.column) else { return }
        host.cell = cell
        let view = host.cellView
        view.configure(cellStyle(cell, in: current))
        let text = current.rows[cell.row][cell.column]
        if view.noteText != text, !view.hasMarkedText() { view.apply(text, selection: nil) }
        let full = displayRect(cell, in: current)
        let frame = editorFrame(full)
        if view.frame != frame { view.frame = frame }
        if view.backdrop.frame != full { view.backdrop.frame = full }
        view.backdrop.fill = backdropFill(cell, in: current)
        let hidden = (drag.map { $0.axis == .row ? $0.source == cell.row : $0.source == cell.column } ?? false)
            || (settlingDrag.map { $0.axis == .row ? $0.index == cell.row : $0.index == cell.column } ?? false)
        view.alphaValue = hidden ? 0 : 1
        view.backdrop.alphaValue = hidden ? 0 : 1
    }

    private func backdropFill(_ cell: NoteTableCell, in current: NoteTable) -> NSColor? {
        if let color = current.color(at: cell), color.isBackground { return NoteTheme.color(color) }
        return isHeader(cell, in: current) ? NoteTableStyle.headerFill : nil
    }

    @discardableResult
    private func materialize(_ requested: NoteTableCell) -> NoteTableCellHost? {
        let current = table
        let cell = current.anchor(of: requested)
        guard cell.row >= 0, cell.column >= 0, cell.row < current.rowCount, cell.column < current.columnCount else { return nil }
        if let host = hosts[cell] { return host }
        if pinnedCells.count > 32 { pinnedCells.removeAll() }
        pinnedCells.insert(cell)
        if geometrySource != current { reloadContent() }
        let host = hosts[cell] ?? makeHost(cell)
        bind(host, cell: cell, table: current)
        return host
    }

    private func focusedHost() -> NoteTableCellHost? {
        guard let responder = window?.firstResponder as? NoteTableCellTextView, responder.table === self else { return nil }
        return hosts.values.first { $0.cellView === responder }
    }

    private func restoreFocus(previous: NoteTableCell?) {
        guard previous != nil, let editor, case .text(let anchor, let head) = editor.session.selection, head.block == blockID,
              case .cell(let row, let column) = head.field else { return }
        let cell = NoteTableCell(row: row, column: column)
        guard let host = materialize(cell) else { return }
        let lower = min(anchor.offset, head.offset), upper = max(anchor.offset, head.offset)
        if window?.firstResponder !== host.cellView { _ = window?.makeFirstResponder(host.cellView) }
        if host.cellView.selectedOffsets != lower..<upper, !host.cellView.hasMarkedText() { host.cellView.selectedOffsets = lower..<upper }
    }

    @discardableResult
    private func focusCell(_ cell: NoteTableCell, placement: Placement) -> Bool {
        guard let host = materialize(cell) else { return false }
        let view = host.cellView
        let length = view.noteText.length
        let range: Range<Int>
        switch placement {
        case .start: range = 0..<0
        case .end: range = length..<length
        case .offsets(let offsets): range = offsets.clamped(to: 0..<(length + 1))
        case .x(let x, let firstLine):
            let local = view.convert(NSPoint(x: x, y: 0), from: surface).x
            let offset = view.offset(nearestX: local, onFirstLine: firstLine)
            range = offset..<offset
        }
        revealCell(cell)
        if let window { _ = window.makeFirstResponder(view) }
        view.selectedOffsets = range
        editor?.textSelectionDidChange(in: host)
        return true
    }

    private func revealCell(_ cell: NoteTableCell) {
        let rect = spanRect(cell, in: table)
        scrollView.scrollHorizontally(toReveal: surface.convert(rect, to: documentView))
        scrollToVisible(convert(rect, from: surface).insetBy(dx: 0, dy: -12))
    }

    var hasCellRange: Bool { cellRange != nil }

    private var cellRangeEnds: (anchor: NoteTableCell, head: NoteTableCell)? {
        guard case .cells(let id, let anchor, let head) = editor?.session.selection, id == blockID else { return nil }
        return (anchor, head)
    }

    private var cellRange: NoteTableRect? {
        cellRangeEnds.flatMap { expandedRect($0.anchor, $0.head) }
    }

    private func expandedRect(_ anchor: NoteTableCell, _ head: NoteTableCell) -> NoteTableRect? {
        let current = table
        guard let clamped = NoteTableRect(anchor, head).clamped(rows: current.rowCount, columns: current.columnCount) else { return nil }
        let area = current.expanded(rows: clamped.rows, columns: clamped.columns)
        return NoteTableRect(rows: area.rows, columns: area.columns)
    }

    private func syncSelection() {
        defer { layoutCellMenuButton() }
        if let pointerRange, let rect = expandedRect(pointerRange.anchor, pointerRange.head) {
            selectionView.style = .selection
            selectionView.highlight = displayGeometry.rect(rect)
        } else if let range = cellRange {
            selectionView.style = .selection
            selectionView.highlight = displayGeometry.rect(range)
        } else if let menuTarget {
            selectionView.style = .menu
            selectionView.highlight = menuTarget.axis == .row ? geometry.rowRect(menuTarget.index) : geometry.columnRect(menuTarget.index)
        } else {
            selectionView.highlight = nil
        }
    }

    private func setRange(anchor: NoteTableCell, head: NoteTableCell) {
        guard let editor else { return }
        let current = table
        let clampedHead = NoteTableCell(row: min(max(0, head.row), current.rowCount - 1), column: min(max(0, head.column), current.columnCount - 1))
        editor.session.setSelection(.cells(table: blockID, anchor: anchor, head: clampedHead))
        if let window, window.firstResponder !== surface { _ = window.makeFirstResponder(surface) }
        revealCell(clampedHead)
        syncSelection()
    }

    func selectWholeTable() {
        let current = table
        let all = NoteTableRect(NoteTableCell(row: 0, column: 0), NoteTableCell(row: current.rowCount - 1, column: current.columnCount - 1))
        if cellRange == all { selectTableBlock(); return }
        setRange(anchor: all.topLeft, head: all.bottomRight)
    }

    private func selectTableBlock() {
        guard let editor else { return }
        dismissMenu()
        editor.selection.select(.blocks([blockID]))
    }

    private func move(from host: NoteTableCellHost, to destination: NoteTableDestination, placement: Placement) {
        switch destination {
        case .cell(let cell): focusCell(cell, placement: placement)
        case .appendRow: appendRow(focusColumn: 0)
        case .exitBefore: exitTable(forward: false)
        case .exitAfter: exitTable(forward: true)
        case .stay: break
        }
    }

    private func exitTable(forward: Bool) {
        guard let editor else { return }
        let page = editor.session.page
        let order = page.flattened().map(\.id)
        guard let index = order.firstIndex(of: blockID) else { return }
        let candidates = forward ? Array(order[(index + 1)...]) : Array(order[..<index].reversed())
        let target = candidates.first { id in
            guard let kind = page.block(id)?.kind, !page.isAncestor(blockID, of: id) else { return false }
            return kind != .columns && kind != .column
        }
        if let target, let next = page.block(target) {
            if next.kind.hasRichText || next.kind.hasPlainText {
                editor.selection.select(.caret(NotePosition(target, forward ? 0 : next.text.length)))
            } else {
                editor.selection.select(.blocks([target]))
            }
        } else if forward, !isReadOnly {
            let paragraph = NoteBlock.paragraph()
            let position = NotePosition(paragraph.id, 0)
            editor.session.insertBlocks([paragraph], .after(blockID), select: .caret(position))
            editor.focus(position)
        }
    }

    func handleCellKey(_ event: NSEvent, in view: NoteTableCellTextView) -> Bool {
        if menuPanel != nil, handleMenuKey(event) { return true }
        guard let editor, let host = view.host as? NoteTableCellHost else { return false }
        if editor.slashMenu.handleKey(event) || editor.formatBar.handleKey(event) { return true }
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let current = table
        let cell = host.cell
        let selection = view.selectedOffsets
        let length = view.noteText.length
        switch event.keyCode {
        case 48:
            guard flags.isSubset(of: [.shift]) else { return false }
            move(from: host, to: NoteTableNavigation.tab(from: cell, in: current, backward: flags.contains(.shift)), placement: .end)
            return true
        case 36, 76:
            if flags == [.shift] {
                if !isReadOnly { view.insertNewlineIgnoringFieldEditor(nil) }
                return true
            }
            guard flags.isEmpty else { return false }
            move(from: host, to: NoteTableNavigation.step(from: cell, .down, in: current), placement: .end)
            return true
        case 53:
            guard flags.isEmpty else { return false }
            commitComposition()
            setRange(anchor: cell, head: cell)
            return true
        case 51:
            return flags.isSubset(of: [.option, .command]) && selection == 0..<0
        case 117:
            return flags.isEmpty && selection.isEmpty && selection.lowerBound == length
        case 123, 124, 125, 126:
            let direction: NoteTableDirection = [123: .left, 124: .right, 125: .down, 126: .up][event.keyCode]!
            if flags == [.shift] {
                let exhausted: Bool
                switch direction {
                case .up, .left: exhausted = selection.lowerBound == 0
                case .down, .right: exhausted = selection.upperBound == length
                }
                guard exhausted else { return false }
                setRange(anchor: cell, head: NoteTableNavigation.extended(cell, anchor: cell, direction, in: current))
                return true
            }
            guard flags.isEmpty else { return false }
            let atEdge: Bool
            switch direction {
            case .up: atEdge = view.isOnFirstLine(selection.lowerBound)
            case .down: atEdge = view.isOnLastLine(selection.upperBound)
            case .left: atEdge = selection.isEmpty && selection.lowerBound == 0
            case .right: atEdge = selection.isEmpty && selection.upperBound == length
            }
            guard atEdge else { return false }
            let caret = surface.convert(view.caretRect(at: direction == .down ? selection.upperBound : selection.lowerBound), from: view)
            let x = caret.midX
            let lane: Int?
            switch direction {
            case .up, .down: lane = geometry.cell(at: NSPoint(x: x, y: 0), clamped: true)?.column
            case .left, .right: lane = geometry.cell(at: NSPoint(x: 0, y: caret.midY), clamped: true)?.row
            }
            let placement: Placement
            switch direction {
            case .up: placement = .x(x, firstLine: false)
            case .down: placement = .x(x, firstLine: true)
            case .left: placement = .end
            case .right: placement = .start
            }
            move(from: host, to: NoteTableNavigation.step(from: cell, direction, in: current, lane: lane), placement: placement)
            return true
        default:
            return false
        }
    }

    func handleRangeKey(_ event: NSEvent) -> Bool {
        if menuPanel != nil, handleMenuKey(event) { return true }
        guard let ends = cellRangeEnds else { return false }
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let current = table
        switch event.keyCode {
        case 123, 124, 125, 126:
            guard flags.isSubset(of: [.shift]) else { return false }
            let direction: NoteTableDirection = [123: .left, 124: .right, 125: .down, 126: .up][event.keyCode]!
            if flags.contains(.shift) {
                setRange(anchor: ends.anchor, head: NoteTableNavigation.extended(ends.head, anchor: ends.anchor, direction, in: current))
            } else if case .cell(let next) = NoteTableNavigation.step(from: ends.head, direction, in: current) {
                setRange(anchor: next, head: next)
            }
            return true
        case 48:
            guard flags.isSubset(of: [.shift]) else { return false }
            switch NoteTableNavigation.tab(from: ends.head, in: current, backward: flags.contains(.shift)) {
            case .cell(let cell): focusCell(cell, placement: .end)
            case .appendRow: appendRow(focusColumn: 0)
            default: focusCell(ends.head, placement: .end)
            }
            return true
        case 36, 76:
            guard flags.isEmpty else { return false }
            focusCell(ends.head, placement: .end)
            return true
        case 53:
            selectTableBlock()
            return true
        case 51, 117:
            clearRange()
            return true
        default:
            guard !isReadOnly, flags.isSubset(of: [.shift]), let characters = event.characters, !characters.isEmpty,
                  characters.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) && $0.value < 0xF700 }),
                  focusCell(ends.head, placement: .end), let host = materialize(ends.head) else { return false }
            host.cellView.selectedOffsets = 0..<host.cellView.noteText.length
            host.cellView.keyDown(with: event)
            return true
        }
    }

    func handleCellMouseDown(_ event: NSEvent, in view: NoteTableCellTextView) -> Bool {
        dismissMenu()
        pointerRange = nil
        guard event.modifierFlags.contains(.shift), event.clickCount == 1 else { return false }
        let anchor = cellRangeEnds?.anchor ?? focusedHost()?.cell
        guard let anchor, anchor != view.cell else { return false }
        setRange(anchor: anchor, head: view.cell)
        return true
    }

    func pointerSelectionMoved(in view: NoteTableCellTextView, to windowPoint: NSPoint, finished: Bool) -> Bool {
        let point = surface.convert(windowPoint, from: nil)
        guard let target = geometry.cell(at: point, clamped: true) else { return pointerRange != nil }
        if table.anchor(of: target) == view.cell {
            if pointerRange != nil { pointerRange = nil; syncSelection() }
            return false
        }
        pointerRange = (view.cell, target)
        scrollView.scrollHorizontally(toReveal: surface.convert(geometry.cellRect(target), to: documentView))
        syncSelection()
        return true
    }

    func pointerSelectionEnded(in view: NoteTableCellTextView) {
        guard let range = pointerRange else { return }
        pointerRange = nil
        setRange(anchor: range.anchor, head: range.head)
    }

    func handleSurfaceMouseDown(_ event: NSEvent) -> Bool {
        dismissMenu()
        let point = surface.convert(event.locationInWindow, from: nil)
        if !isReadOnly, let column = NoteTableMetrics.boundary(near: Double(point.x), sizes: geometry.columnWidths.map(Double.init),
                                                             tolerance: Double(NoteTableStyle.resizeTolerance)) {
            trackResize(column: column, event: event)
            return true
        }
        guard let cell = geometry.cell(at: point, clamped: true), let host = materialize(cell) else { return false }
        if let window { _ = window.makeFirstResponder(host.cellView) }
        host.cellView.mouseDown(with: event)
        return true
    }

    private func trackResize(column: Int, event: NSEvent) {
        guard let window else { return }
        let startX = surface.convert(event.locationInWindow, from: nil).x
        let base = geometry.columnWidths.map(Double.init)
        resizingColumn = column
        hideHoverChrome(animated: true)
        layoutCellMenuButton()
        var widths = base
        window.trackEvents(matching: [.leftMouseDragged, .leftMouseUp], timeout: .infinity, mode: .eventTracking) { next, stop in
            guard let next else { stop.pointee = true; return }
            let x = surface.convert(next.locationInWindow, from: nil).x
            widths = NoteTableMetrics.resized(base, column: column, by: Double(x - startX))
            liveWidths = widths.map { CGFloat($0) }
            reloadContent()
            invalidateCanvasLayout()
            NSCursor.resizeLeftRight.set()
            if next.type == .leftMouseUp { stop.pointee = true }
        }
        resizingColumn = nil
        liveWidths = nil
        defer { layoutCellMenuButton() }
        if widths != base, let editor, !isReadOnly {
            var resized = table
            NoteTableTransforms.setWidths(widths.map { Optional($0) }, in: &resized)
            editor.session.setTableColumnWidths(blockID, resized.columnWidths, name: "Resize Column")
        } else {
            reloadContent()
        }
        invalidateCanvasLayout()
    }

    private func invalidateCanvasLayout() {
        editor?.canvas.blockHeightDidChange(blockID)
    }

    override func updateTrackingAreas() {
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
        super.updateTrackingAreas()
    }

    func isResizeBoundary(atWindowPoint point: NSPoint) -> Bool {
        let local = surface.convert(point, from: nil)
        return surface.resizeBoundaries.contains { $0.contains(local) }
    }

    override func mouseEntered(with event: NSEvent) { pointerMoved(event) }
    override func mouseMoved(with event: NSEvent) { pointerMoved(event) }

    override func mouseExited(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if [rowGrip, columnGrip].contains(where: { !$0.isHidden && $0.frame(in: self).insetBy(dx: -4, dy: -4).contains(point) }) { return }
        if isHovering, addColumnBar.frame.union(cornerHandle.frame).insetBy(dx: -NoteTableStyle.barGap - 2, dy: -4).contains(point) { return }
        hideHoverChrome(animated: true)
    }

    private func pointerLeftColumnBar() {
        guard let window, isHovering else { return }
        let point = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        if !bounds.contains(point) { hideHoverChrome(animated: true) }
    }

    private func pointerMoved(_ event: NSEvent) {
        guard !isReadOnly, drag == nil, resizingColumn == nil, !isCornerDragging else { return }
        guard NoteFloatingPanel.allowsHover(for: self, at: event.locationInWindow) else {
            if isHovering { hideHoverChrome(animated: true) }
            return
        }
        if !isHovering {
            isHovering = true
            for bar in [addRowBar, addColumnBar, cornerHandle] as [NSView] { NoteAnimation.fade(bar, visible: true, duration: 0.12) }
        }
        let point = surface.convert(event.locationInWindow, from: nil)
        let shown = geometry
        let inside = point.x >= -NoteTableStyle.rowGripSize.width && point.x <= shown.width
            && point.y >= -NoteTableStyle.topInset && point.y <= shown.height
        let boundary = point.y >= 0 && point.y <= shown.height
            ? NoteTableMetrics.boundary(near: Double(point.x), sizes: shown.columnWidths.map(Double.init), tolerance: Double(NoteTableStyle.resizeTolerance))
            : nil
        if boundary != hoveredBoundary {
            hoveredBoundary = boundary
            layoutChrome()
        }
        guard inside, let cell = shown.cell(at: point, clamped: true) else {
            if menuTarget == nil { setGripsVisible(false) }
            return
        }
        if cell != hoverCell {
            hoverCell = cell
            layoutGrips(shown)
        }
        setGripsVisible(true)
    }

    private func setGripsVisible(_ visible: Bool) {
        for grip in [rowGrip, columnGrip] {
            let shouldShow = visible || (menuTarget.map { ($0.axis == .row) == (grip.axis == .row) } ?? false)
            if shouldShow, grip.isHidden {
                grip.isHidden = false
                NoteAnimation.fade(grip, visible: true, duration: 0.1)
            } else if !shouldShow, !grip.isHidden, grip.alphaValue > 0 {
                NoteAnimation.fade(grip, visible: false, duration: 0.1) { [weak grip, weak self] in
                    guard let grip, let self, self.menuTarget == nil, grip.alphaValue == 0 else { return }
                    grip.isHidden = true
                }
            }
        }
    }

    private func hideHoverChrome(animated: Bool) {
        isHovering = false
        hoveredBoundary = nil
        if menuTarget == nil { hoverCell = nil }
        setGripsVisible(false)
        for bar in [addRowBar, addColumnBar, cornerHandle] as [NSView] where !(bar === cornerHandle && isCornerDragging) {
            if animated { NoteAnimation.fade(bar, visible: false, duration: 0.12) } else { bar.alphaValue = 0 }
        }
        resizeIndicator.isHidden = resizingColumn == nil
    }

    private func scrollDidChange() {
        let shown = displayGeometry
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        addRowBar.frame.size.width = max(0, min(shown.width - scrollView.horizontalOffset, bounds.width))
        addColumnBar.frame.origin.x = columnBarX(tableWidth: shown.width)
        cornerHandle.frame.origin.x = columnBarX(tableWidth: shown.width)
        CATransaction.commit()
        if isVirtualizing { layoutCells() }
    }

    private func gripPressed(_ grip: NoteTableGripView, event: NSEvent) {
        commitComposition()
        guard let window else { openMenu(for: grip); return }
        let axis: Axis = grip.axis == .row ? .row : .column
        let index = grip.index
        let start = event.locationInWindow
        var dragging = false
        var openMenuAfter = false
        window.trackEvents(matching: [.leftMouseDragged, .leftMouseUp], timeout: .infinity, mode: .eventTracking) { next, stop in
            guard let next else { stop.pointee = true; return }
            if next.type == .leftMouseUp {
                stop.pointee = true
                if dragging { endDrag() } else { openMenuAfter = true }
                return
            }
            let distance = hypot(next.locationInWindow.x - start.x, next.locationInWindow.y - start.y)
            if !dragging, distance > 3, !isReadOnly { dragging = beginDrag(axis: axis, index: index, event: event) }
            if dragging { moveDrag(next) }
        }
        if openMenuAfter { openMenu(for: grip) }
    }

    private func beginDrag(axis: Axis, index: Int, event: NSEvent) -> Bool {
        let count = axis == .row ? geometry.rowCount : geometry.columnCount
        guard count > 1, index < count else { return false }
        dismissMenu()
        let rect = axis == .row ? geometry.rowRect(index) : geometry.columnRect(index)
        guard let image = NoteTableMotion.snapshot(of: surface, rect: rect) else { return false }
        let frame = surface.convert(rect, to: documentView)
        let ghost = NoteTableGhostView(image: image, frame: frame)
        documentView.addSubview(ghost)
        ghost.lift(true)
        drag = Drag(axis: axis, source: index, target: index, start: documentView.convert(event.locationInWindow, from: nil),
                    ghostOrigin: frame.origin, ghost: ghost)
        hideHoverChrome(animated: true)
        layoutCells()
        layoutCellMenuButton()
        return true
    }

    private func moveDrag(_ event: NSEvent) {
        guard var current = drag else { return }
        let point = documentView.convert(event.locationInWindow, from: nil)
        let ghost = current.ghost
        let surfaceFrame = surface.frame
        var origin = current.ghostOrigin
        if current.axis == .row {
            origin.y = min(max(current.ghostOrigin.y + point.y - current.start.y, surfaceFrame.minY - 8), surfaceFrame.maxY - ghost.frame.height + 8)
        } else {
            origin.x = min(max(current.ghostOrigin.x + point.x - current.start.x, surfaceFrame.minX - 8), surfaceFrame.maxX - ghost.frame.width + 8)
            let local = scrollView.convert(event.locationInWindow, from: nil).x
            if local < 24 { scrollView.scrollHorizontally(toReveal: NSRect(x: scrollView.horizontalOffset - 16, y: 0, width: 1, height: 1)) }
            if local > scrollView.bounds.width - 24 {
                scrollView.scrollHorizontally(toReveal: NSRect(x: scrollView.horizontalOffset + scrollView.bounds.width + 16, y: 0, width: 1, height: 1))
            }
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        ghost.setFrameOrigin(origin)
        CATransaction.commit()
        let center = current.axis == .row ? ghost.frame.midY - surfaceFrame.minY : ghost.frame.midX - surfaceFrame.minX
        let sizes = (current.axis == .row ? geometry.rowHeights : geometry.columnWidths).map(Double.init)
        let target = NoteTableMetrics.dropIndex(for: Double(center), sizes: sizes, moving: current.source)
        guard target != current.target else { return }
        let before = Dictionary(uniqueKeysWithValues: hosts.map { entry in
            (entry.key, (entry.value.cellView.frame, NoteTableMotion.presentedOffset(entry.value.cellView),
                         entry.value.cellView.backdrop.frame, NoteTableMotion.presentedOffset(entry.value.cellView.backdrop)))
        })
        let rulesBefore = (rowRules + columnRules).map { ($0, $0.frame, NoteTableMotion.presentedOffset($0)) }
        current.target = target
        drag = current
        layoutChrome()
        layoutCells()
        for (cell, host) in hosts {
            guard let old = before[cell] else { continue }
            NoteTableMotion.slide(host.cellView, from: old.0, offset: old.1)
            NoteTableMotion.slide(host.cellView.backdrop, from: old.2, offset: old.3)
        }
        for (rule, frame, offset) in rulesBefore where rule.superview != nil { NoteTableMotion.slide(rule, from: frame, offset: offset) }
    }

    private func endDrag() {
        guard let finished = drag else { return }
        for host in hosts.values {
            NoteTableMotion.settle(host.cellView)
            NoteTableMotion.settle(host.cellView.backdrop)
        }
        for rule in rowRules + columnRules { NoteTableMotion.settle(rule) }
        let ghost = finished.ghost
        let slot = finished.axis == .row ? displayGeometry.rowRect(finished.target) : displayGeometry.columnRect(finished.target)
        settlingDrag = (finished.axis, finished.target)
        drag = nil
        if finished.target != finished.source, let session = editor?.session, !isReadOnly {
            if finished.axis == .row {
                session.moveTableRow(blockID, from: finished.source, to: finished.target, kind: .text)
            } else {
                session.moveTableColumn(blockID, from: finished.source, to: finished.target, kind: .text)
            }
        } else {
            reloadContent()
        }
        let destination = surface.convert(slot, to: documentView)
        let from = ghost.frame
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self, weak ghost] in
            MainActor.assumeIsolated {
                ghost?.removeFromSuperview()
                self?.settlingDrag = nil
                self?.layoutCells()
                self?.layoutCellMenuButton()
            }
        }
        ghost.frame = destination
        if NoteTableMotion.reduceMotion {
            NoteTableMotion.fadeOutAndRemove(ghost)
        } else {
            NoteTableMotion.slide(ghost, from: from, spring: .settle)
            ghost.lift(false)
        }
        CATransaction.commit()
    }

    private func commit(_ name: String, change: NoteTableChange? = nil, selection: NotePageSelection? = nil,
                        _ transform: @escaping (inout NoteTable) -> Void) {
        guard let editor, !isReadOnly else { return }
        if let change { prepareMotion(change) }
        let id = blockID
        editor.session.edit(name, kind: change == nil ? .text : .structure, affected: [id], selection: selection) { page in
            page.update(id) { block in
                var value = block.props.table ?? NoteTable.empty()
                transform(&value)
                value.normalize()
                block.props.table = value
            }
        }
        pendingChange = nil
        motionGeometry = nil
        motionSnapshot = nil
    }

    private func prepareMotion(_ change: NoteTableChange) {
        pendingChange = change
        motionGeometry = geometry
        motionSnapshot = nil
        switch change {
        case .deleteRows(let at, let count):
            let rect = geometry.rowRect(at).union(geometry.rowRect(at + count - 1))
            if let image = NoteTableMotion.snapshot(of: surface, rect: rect) { motionSnapshot = (image, rect) }
        case .deleteColumns(let at, let count):
            let rect = geometry.columnRect(at).union(geometry.columnRect(at + count - 1))
            if let image = NoteTableMotion.snapshot(of: surface, rect: rect) { motionSnapshot = (image, rect) }
        default:
            break
        }
    }

    private func runMotion(_ change: NoteTableChange, from old: NoteTableGeometry) {
        guard window != nil else { return }
        let current = table
        for (cell, host) in hosts {
            let view = host.cellView
            let span = current.span(of: cell)
            if let row = change.oldRow(for: cell.row), let column = change.oldColumn(for: cell.column),
               old.contains(NoteTableCell(row: row, column: column)) {
                let previous = old.rect(NoteTableRect(rows: row...(row + span.rowSpan - 1), columns: column...(column + span.columnSpan - 1)))
                NoteTableMotion.slide(view, from: editorFrame(previous))
                NoteTableMotion.slide(view.backdrop, from: previous)
                NoteTableMotion.resize(view.backdrop, from: previous.size)
            } else {
                NoteTableMotion.fadeIn(view, delay: 0.04)
                NoteTableMotion.fadeIn(view.backdrop)
            }
        }
        for (index, rule) in rowRules.enumerated() {
            if let source = change.oldRow(for: index), source + 1 < old.rowCount {
                NoteTableMotion.slide(rule, from: NSRect(x: 0, y: old.rowEdges[source + 1], width: old.width, height: rule.frame.height))
                NoteTableMotion.resize(rule, from: NSSize(width: old.width, height: rule.frame.height))
            } else {
                NoteTableMotion.fadeIn(rule)
            }
        }
        for (index, rule) in columnRules.enumerated() {
            if let source = change.oldColumn(for: index), source + 1 < old.columnCount {
                NoteTableMotion.slide(rule, from: NSRect(x: old.columnEdges[source + 1], y: 0, width: rule.frame.width, height: old.height))
                NoteTableMotion.resize(rule, from: NSSize(width: rule.frame.width, height: old.height))
            } else {
                NoteTableMotion.fadeIn(rule)
            }
        }
        for view in [surface, frameView, selectionView] as [NSView] {
            NoteTableMotion.resize(view, from: NSSize(width: old.width, height: old.height))
        }
        NoteTableMotion.slide(cornerHandle, from: NSRect(x: columnBarX(tableWidth: old.width), y: NoteTableStyle.topInset + old.height + NoteTableStyle.barGap,
                                                         width: cornerHandle.frame.width, height: cornerHandle.frame.height))
        let barShift = NSRect(x: addRowBar.frame.minX, y: NoteTableStyle.topInset + old.height + NoteTableStyle.barGap,
                              width: addRowBar.frame.width, height: addRowBar.frame.height)
        NoteTableMotion.slide(addRowBar, from: barShift)
        NoteTableMotion.slide(addColumnBar, from: NSRect(x: columnBarX(tableWidth: old.width), y: addColumnBar.frame.minY,
                                                         width: addColumnBar.frame.width, height: old.height))
        NoteTableMotion.resize(addColumnBar, from: NSSize(width: addColumnBar.frame.width, height: old.height))
        if let snapshot = motionSnapshot {
            let ghost = NoteTableSnapshotView(image: snapshot.image, frame: snapshot.rect)
            surface.addSubview(ghost, positioned: .below, relativeTo: frameView)
            NoteTableMotion.fadeOutAndRemove(ghost)
        }
    }

    private func settleMotion() {
        NoteTableMotion.settle(self)
    }

    private func run(_ change: NoteTableChange?, focus: NoteTableCell? = nil,
                     _ operation: (NotePageSession, NoteBlockID, NotePageSelection?) -> Bool) {
        guard let editor, !isReadOnly else { return }
        if let change { prepareMotion(change) }
        let select = focus.map { NotePageSelection.caret(NotePosition(blockID, 0, field: .cell(row: $0.row, column: $0.column))) }
        _ = operation(editor.session, blockID, select)
        pendingChange = nil
        motionGeometry = nil
        motionSnapshot = nil
        if let focus { focusCell(focus, placement: .start) }
    }

    func appendRow(focusColumn: Int? = nil) {
        let index = table.rowCount
        run(.insertRows(at: index, count: 1), focus: focusColumn.map { NoteTableCell(row: index, column: $0) }) { session, id, select in
            session.insertTableRow(id, at: index, name: "Add Row", select: select)
        }
    }

    func appendColumn() {
        let index = table.columnCount
        run(.insertColumns(at: index, count: 1)) { session, id, _ in session.insertTableColumn(id, at: index, name: "Add Column") }
    }

    private func growByOne() {
        guard let editor, !isReadOnly else { return }
        let current = table
        prepareMotion(.insertRows(at: current.rowCount, count: 1))
        editor.session.resizeTable(blockID, rows: current.rowCount + 1, columns: current.columnCount + 1)
        pendingChange = nil
        motionGeometry = nil
        motionSnapshot = nil
    }

    private func cornerPressed(_ event: NSEvent) {
        guard let window, let editor, !isReadOnly else { return }
        commitComposition()
        dismissMenu()
        let base = table
        let start = event.locationInWindow
        let settings = pageSettings
        let rowStep = max(20, cellHeight(NoteText(), columnWidth: geometry.columnWidths.last ?? 100,
                                         style: NoteTableCellStyle(font: settings.font, small: settings.smallText)))
        let columnStep = NoteTableStyle.cornerColumnStep
        let fewestRows = base.rowCount - base.trailingEmptyRows, fewestColumns = base.columnCount - base.trailingEmptyColumns
        var shown = (rows: base.rowCount, columns: base.columnCount)
        isCornerDragging = true
        cornerHandle.isActive = true
        hideHoverChrome(animated: true)
        layoutCellMenuButton()
        window.trackEvents(matching: [.leftMouseDragged, .leftMouseUp], timeout: .infinity, mode: .eventTracking) { next, stop in
            guard let next else { stop.pointee = true; return }
            let across = next.locationInWindow.x - start.x, down = start.y - next.locationInWindow.y
            let rows = min(base.rowCount + 200, max(fewestRows, base.rowCount + Int((down / rowStep).rounded())))
            let columns = min(base.columnCount + 50, max(fewestColumns, base.columnCount + Int((across / columnStep).rounded())))
            if rows != shown.rows || columns != shown.columns {
                previewResize(base, from: shown, to: (rows, columns))
                shown = (rows, columns)
            }
            if next.type == .leftMouseUp { stop.pointee = true }
        }
        isCornerDragging = false
        cornerHandle.isActive = false
        previewTable = nil
        if shown.rows != base.rowCount || shown.columns != base.columnCount {
            editor.session.resizeTable(blockID, rows: shown.rows, columns: shown.columns)
        } else {
            reloadContent()
        }
        invalidateCanvasLayout()
        layoutCellMenuButton()
    }

    private func previewResize(_ base: NoteTable, from old: (rows: Int, columns: Int), to new: (rows: Int, columns: Int)) {
        var next = base
        next.resize(rows: new.rows, columns: new.columns)
        if new.rows != old.rows {
            prepareMotion(new.rows > old.rows ? .insertRows(at: old.rows, count: new.rows - old.rows) : .deleteRows(at: new.rows, count: old.rows - new.rows))
        } else if new.columns != old.columns {
            prepareMotion(new.columns > old.columns ? .insertColumns(at: old.columns, count: new.columns - old.columns)
                          : .deleteColumns(at: new.columns, count: old.columns - new.columns))
        }
        previewTable = next
        reloadContent()
        pendingChange = nil
        motionGeometry = nil
        motionSnapshot = nil
        invalidateCanvasLayout()
    }

    func insertRow(at index: Int) {
        run(.insertRows(at: index, count: 1)) { session, id, _ in session.insertTableRow(id, at: index) }
    }

    func insertColumn(at index: Int) {
        run(.insertColumns(at: index, count: 1)) { session, id, _ in session.insertTableColumn(id, at: index) }
    }

    func duplicate(_ axis: Axis, at index: Int) {
        let change: NoteTableChange = axis == .row ? .insertRows(at: index + 1, count: 1) : .insertColumns(at: index + 1, count: 1)
        run(change) { session, id, _ in
            axis == .row ? session.duplicateTableRow(id, at: index) : session.duplicateTableColumn(id, at: index)
        }
    }

    func delete(_ axis: Axis, at index: Int) {
        let current = table
        guard (axis == .row ? current.rowCount : current.columnCount) > 1 else { return }
        let change: NoteTableChange = axis == .row ? .deleteRows(at: index, count: 1) : .deleteColumns(at: index, count: 1)
        run(change) { session, id, _ in
            axis == .row ? session.deleteTableRow(id, at: index) : session.deleteTableColumn(id, at: index)
        }
    }

    func move(_ axis: Axis, from index: Int, to target: Int) {
        let current = table
        let count = axis == .row ? current.rowCount : current.columnCount
        guard index != target, (0..<count).contains(index), (0..<count).contains(target) else { return }
        let change: NoteTableChange = axis == .row ? .moveRow(from: index, to: target) : .moveColumn(from: index, to: target)
        run(change) { session, id, _ in
            axis == .row ? session.moveTableRow(id, from: index, to: target) : session.moveTableColumn(id, from: index, to: target)
        }
    }

    func clear(_ rect: NoteTableRect, name: String = "Clear Cells") {
        commit(name) { NoteTableTransforms.clear(rect, in: &$0) }
    }

    func clearRange() {
        guard let rect = cellRange, !isReadOnly else { return }
        clear(rect)
    }

    func copyRange(cut: Bool) {
        guard let rect = cellRange?.clamped(rows: table.rowCount, columns: table.columnCount) else { return }
        write(rect, to: .general)
        if cut, !isReadOnly { clear(rect, name: "Cut Cells") }
    }

    func write(_ rect: NoteTableRect, to pasteboard: NSPasteboard) {
        let current = table
        let rows = NoteTableTransforms.slice(rect, of: current)
        let sliced = NoteTableClipboard.slice(rect, of: current)
        let tsv = NoteTableClipboard.tsv(rows)
        pasteboard.clearContents()
        pasteboard.declareTypes([Self.cellsPasteboardType, .string, .tabularText, .html, Self.markdownPasteboardType], owner: nil)
        if let data = try? JSONEncoder().encode(sliced) { pasteboard.setData(data, forType: Self.cellsPasteboardType) }
        pasteboard.setString(tsv, forType: .string)
        pasteboard.setString(tsv, forType: .tabularText)
        pasteboard.setString(NoteTableClipboard.html(sliced), forType: .html)
        pasteboard.setString(NoteTableClipboard.markdown(sliced), forType: Self.markdownPasteboardType)
    }

    static func tableSlice(from pasteboard: NSPasteboard) -> NoteTable? {
        guard let data = pasteboard.data(forType: cellsPasteboardType), var slice = try? JSONDecoder().decode(NoteTable.self, from: data) else { return nil }
        slice.normalize()
        return slice
    }

    static func grid(from pasteboard: NSPasteboard) -> [[NoteText]]? {
        if let slice = tableSlice(from: pasteboard) { return slice.rows }
        if let data = pasteboard.data(forType: cellsPasteboardType), let rows = try? JSONDecoder().decode([[NoteText]].self, from: data), !rows.isEmpty {
            return rows
        }
        if let text = pasteboard.string(forType: .tabularText), let grid = NoteTableClipboard.grid(fromDelimited: text, fromSpreadsheet: true) {
            return NoteTableClipboard.cells(from: grid)
        }
        if let html = pasteboard.string(forType: .html), let rows = NoteTableClipboard.grid(fromHTML: html) { return rows }
        if let text = pasteboard.string(forType: .string), let grid = NoteTableClipboard.grid(fromDelimited: text) {
            return NoteTableClipboard.cells(from: grid)
        }
        return nil
    }

    func pasteIntoCell(_ view: NoteTableCellTextView) -> Bool {
        guard !isReadOnly else { return false }
        if let slice = Self.tableSlice(from: .general), slice.rowCount * slice.columnCount > 1 {
            paste(slice, at: view.cell)
            return true
        }
        guard let grid = Self.grid(from: .general), grid.count * (grid.map(\.count).max() ?? 0) > 1 else { return false }
        paste(grid, at: view.cell, filling: nil)
        return true
    }

    func pasteIntoRange() {
        guard !isReadOnly, let rect = cellRange else { return }
        let pasteboard = NSPasteboard.general
        if let slice = Self.tableSlice(from: pasteboard), slice.rowCount * slice.columnCount > 1 {
            paste(slice, at: rect.topLeft)
            return
        }
        guard let grid = Self.grid(from: pasteboard) ?? pasteboard.string(forType: .string).map({ [[NoteText($0.trimmingCharacters(in: .newlines))]] }) else { return }
        paste(grid, at: rect.topLeft, filling: rect)
    }

    func paste(_ grid: [[NoteText]], at origin: NoteTableCell, filling target: NoteTableRect?) {
        let current = table
        var next = current
        guard let filled = NoteTableTransforms.paste(grid, into: &next, at: origin, filling: target) else { return }
        var change: NoteTableChange?
        if next.rowCount > current.rowCount, next.columnCount == current.columnCount {
            change = .insertRows(at: current.rowCount, count: next.rowCount - current.rowCount)
        } else if next.columnCount > current.columnCount, next.rowCount == current.rowCount {
            change = .insertColumns(at: current.columnCount, count: next.columnCount - current.columnCount)
        }
        commit("Paste Cells", change: change, selection: .cells(table: blockID, anchor: filled.topLeft, head: filled.bottomRight)) { table in
            NoteTableTransforms.paste(grid, into: &table, at: origin, filling: target)
        }
        if let window, window.firstResponder !== surface { _ = window.makeFirstResponder(surface) }
        syncSelection()
    }

    private func paste(_ slice: NoteTable, at origin: NoteTableCell) {
        let current = table
        var next = current
        let area = next.paste(slice, at: origin)
        var change: NoteTableChange?
        if next.rowCount > current.rowCount, next.columnCount == current.columnCount {
            change = .insertRows(at: current.rowCount, count: next.rowCount - current.rowCount)
        } else if next.columnCount > current.columnCount, next.rowCount == current.rowCount {
            change = .insertColumns(at: current.columnCount, count: next.columnCount - current.columnCount)
        }
        let selection = NotePageSelection.cells(table: blockID, anchor: NoteTableCell(row: area.rows.lowerBound, column: area.columns.lowerBound),
                                                head: NoteTableCell(row: area.rows.upperBound, column: area.columns.upperBound))
        commit("Paste Cells", change: change, selection: selection) { table in table.paste(slice, at: origin) }
        if let window, window.firstResponder !== surface { _ = window.makeFirstResponder(surface) }
        syncSelection()
    }

    func handleRangeKeyEquivalent(_ event: NSEvent) -> Bool {
        guard cellRange != nil, event.modifierFlags.intersection([.command, .option, .control, .shift]) == .command,
              let key = event.charactersIgnoringModifiers?.lowercased() else { return false }
        switch key {
        case "d": fillRange(.down)
        case "r": fillRange(.right)
        default: return false
        }
        return true
    }

    func fillRange(_ direction: NoteTableFill) {
        guard let rect = cellRange, let editor else { return }
        guard !isReadOnly, editor.session.fillTableCells(blockID, direction, rows: rect.rows, columns: rect.columns) else {
            NSSound.beep()
            return
        }
        flash(rect)
    }

    private func flash(_ rect: NoteTableRect) {
        guard window != nil else { return }
        for (cell, host) in hosts where rect.contains(cell) { NoteTableMotion.fadeIn(host.cellView) }
    }

    private func spanEdit(_ rect: NoteTableRect, _ operation: () -> Void) {
        pendingSpanFrames = Dictionary(uniqueKeysWithValues: hosts.map { ($0.key, $0.value.cellView.backdrop.frame) })
        let area = geometry.rect(rect)
        pendingSpanGhost = NoteTableMotion.snapshot(of: surface, rect: area).map { (image: $0, rect: area) }
        operation()
        pendingSpanFrames = nil
        pendingSpanGhost = nil
    }

    private func runSpanMotion(_ frames: [NoteTableCell: NSRect], ghost: (image: NSImage, rect: NSRect)?) {
        guard window != nil else { return }
        for (cell, host) in hosts {
            let view = host.cellView
            guard let old = frames[cell] else {
                NoteTableMotion.fadeIn(view, delay: 0.04)
                NoteTableMotion.fadeIn(view.backdrop)
                continue
            }
            guard old != view.backdrop.frame else { continue }
            NoteTableMotion.slide(view.backdrop, from: old, spring: .settle)
            NoteTableMotion.resize(view.backdrop, from: old.size, spring: .settle)
            NoteTableMotion.slide(view, from: editorFrame(old), spring: .settle)
        }
        if let ghost {
            let snapshot = NoteTableSnapshotView(image: ghost.image, frame: ghost.rect)
            surface.addSubview(snapshot, positioned: .below, relativeTo: frameView)
            NoteTableMotion.fadeOutAndRemove(snapshot)
        }
    }

    func mergeCells(_ rect: NoteTableRect) {
        guard let editor, !isReadOnly else { return }
        spanEdit(rect) { _ = editor.session.mergeTableCells(blockID, rows: rect.rows, columns: rect.columns) }
        if let window, window.firstResponder !== surface { _ = window.makeFirstResponder(surface) }
        syncSelection()
    }

    func unmergeCells(_ rect: NoteTableRect) {
        guard let editor, !isReadOnly else { return }
        spanEdit(rect) { _ = editor.session.unmergeTableCells(blockID, rows: rect.rows, columns: rect.columns) }
        if let window, window.firstResponder !== surface { _ = window.makeFirstResponder(surface) }
        syncSelection()
    }

    func setColor(_ style: NoteColorStyle?, in rect: NoteTableRect) {
        guard let editor, !isReadOnly else { return }
        if editor.session.setTableCellColor(blockID, style, rows: rect.rows, columns: rect.columns), let style { NoteColorRecents.record(style) }
    }

    private func setHeader(_ axis: Axis, _ enabled: Bool) {
        run(nil) { session, id, _ in
            axis == .row ? session.setTableHeaderRow(id, enabled) : session.setTableHeaderColumn(id, enabled)
        }
    }

    private func setAlignment(_ alignment: NoteAlignment, column: Int) {
        run(nil) { session, id, _ in session.setTableColumnAlignment(id, column: column, alignment == .left ? nil : alignment) }
    }

    private func menuItems(axis: Axis, index: Int) -> [NoteMenuList.Item] {
        let current = table
        let count = axis == .row ? current.rowCount : current.columnCount
        let rect = axis == .row ? NoteTableRect(rows: index...index, columns: 0...(current.columnCount - 1))
            : NoteTableRect(rows: 0...(current.rowCount - 1), columns: index...index)
        var items: [NoteMenuList.Item] = []
        if index == 0 {
            items.append(NoteMenuList.Item(id: "header", title: axis == .row ? "Header Row" : "Header Column",
                                           icon: .symbol(axis == .row ? "rectangle.topthird.inset.filled" : "rectangle.leftthird.inset.filled"),
                                           isChecked: axis == .row ? current.headerRow : current.headerColumn))
        }
        if axis == .row {
            items.append(NoteMenuList.Item(id: "insertBefore", title: "Insert Above", icon: .symbol("arrow.up.to.line"), separatorBefore: index == 0))
            items.append(NoteMenuList.Item(id: "insertAfter", title: "Insert Below", icon: .symbol("arrow.down.to.line")))
        } else {
            items.append(NoteMenuList.Item(id: "insertBefore", title: "Insert Left", icon: .symbol("arrow.left.to.line"), separatorBefore: index == 0))
            items.append(NoteMenuList.Item(id: "insertAfter", title: "Insert Right", icon: .symbol("arrow.right.to.line")))
            let alignment = current.alignments[index] ?? .left
            for (value, title, symbol) in [(NoteAlignment.left, "Align Left", "text.alignleft"), (.center, "Align Center", "text.aligncenter"),
                                           (.right, "Align Right", "text.alignright")] {
                items.append(NoteMenuList.Item(id: "align." + value.rawValue, title: title, icon: .symbol(symbol), isChecked: alignment == value,
                                               separatorBefore: value == .left))
            }
        }
        items.append(NoteMenuList.Item(id: "color", title: "Color", icon: .symbol("paintpalette"), hasSubmenu: true, separatorBefore: true))
        items.append(NoteMenuList.Item(id: "duplicate", title: "Duplicate", icon: .symbol("plus.square.on.square")))
        items.append(NoteMenuList.Item(id: "moveBefore", title: axis == .row ? "Move Up" : "Move Left",
                                       icon: .symbol(axis == .row ? "arrow.up" : "arrow.left"), isEnabled: index > 0))
        items.append(NoteMenuList.Item(id: "moveAfter", title: axis == .row ? "Move Down" : "Move Right",
                                       icon: .symbol(axis == .row ? "arrow.down" : "arrow.right"), isEnabled: index + 1 < count))
        items.append(NoteMenuList.Item(id: "clear", title: "Clear Contents", icon: .symbol("eraser"), isEnabled: !NoteTableTransforms.isEmpty(rect, of: current),
                                       separatorBefore: true))
        items.append(NoteMenuList.Item(id: "delete", title: axis == .row ? "Delete Row" : "Delete Column", icon: .symbol("trash"),
                                       isEnabled: count > 1, isDestructive: true))
        return items
    }

    private func performMenuItem(_ id: String, axis: Axis, index: Int) {
        let current = table
        guard index >= 0, index < (axis == .row ? current.rowCount : current.columnCount) else { return }
        switch id {
        case "header": setHeader(axis, !(axis == .row ? current.headerRow : current.headerColumn))
        case "insertBefore": axis == .row ? insertRow(at: index) : insertColumn(at: index)
        case "insertAfter": axis == .row ? insertRow(at: index + 1) : insertColumn(at: index + 1)
        case "duplicate": duplicate(axis, at: index)
        case "moveBefore": move(axis, from: index, to: index - 1)
        case "moveAfter": move(axis, from: index, to: index + 1)
        case "clear":
            clear(axis == .row ? NoteTableRect(rows: index...index, columns: 0...(current.columnCount - 1))
                : NoteTableRect(rows: 0...(current.rowCount - 1), columns: index...index), name: "Clear Contents")
        case "delete": delete(axis, at: index)
        case "color":
            let rect = axis == .row ? NoteTableRect(rows: index...index, columns: 0...(current.columnCount - 1))
                : NoteTableRect(rows: 0...(current.rowCount - 1), columns: index...index)
            let grip = axis == .row ? rowGrip : columnGrip
            openColorMenu(for: rect, anchor: grip, highlight: (axis: axis, index: index))
        default:
            if id.hasPrefix("align."), let alignment = NoteAlignment(rawValue: String(id.dropFirst(6))) { setAlignment(alignment, column: index) }
        }
    }

    private func openMenu(for grip: NoteTableGripView) {
        guard editor != nil, !isReadOnly else { return }
        commitComposition()
        dismissMenu()
        let axis: Axis = grip.axis == .row ? .row : .column
        let index = grip.index
        guard index >= 0, index < (axis == .row ? table.rowCount : table.columnCount) else {
            revalidateGrips()
            return
        }
        let list = NoteMenuList()
        list.items = menuItems(axis: axis, index: index)
        list.onActivate = { [weak self] item in
            self?.dismissMenu()
            self?.performMenuItem(item.id, axis: axis, index: index)
        }
        list.onCancel = { [weak self] in self?.dismissMenu() }
        menuTarget = (axis, index)
        grip.isActive = true
        setGripsVisible(true)
        presentMenu(list, from: grip)
    }

    private func presentMenu(_ list: NoteMenuList, from control: NSView) {
        guard let editor else { return }
        let panel = NoteFloatingPanel(content: list)
        panel.onDismiss = { [weak self, weak panel] in
            guard let self, let panel, self.menuPanel === panel else { return }
            self.menuDidClose()
        }
        menuPanel = panel
        menuList = list
        let host = editor.canvas.overlayView
        let anchor = control.convert(control.bounds, to: host)
        if focusedHost() == nil, let window, window.firstResponder !== surface, cellRange == nil {
            _ = window.makeFirstResponder(self)
        }
        panel.present(in: host, anchor: anchor, edge: .below)
        outsideClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            MainActor.assumeIsolated { self?.menuSawClick(event) }
            return event
        }
        syncSelection()
    }

    private var focusedCellRect: NoteTableRect? {
        guard let editor, case .text(let anchor, let head) = editor.session.selection, head.block == blockID, anchor.block == blockID,
              anchor.field == head.field, case .cell(let row, let column) = head.field else { return nil }
        let current = table
        guard row >= 0, column >= 0, row < current.rowCount, column < current.columnCount else { return nil }
        let span = current.span(of: current.anchor(of: NoteTableCell(row: row, column: column)))
        return NoteTableRect(rows: span.rows, columns: span.columns)
    }

    private func layoutCellMenuButton() {
        let busy = isReadOnly || drag != nil || resizingColumn != nil || pointerRange != nil || isCornerDragging || menuTarget != nil
        let target = cellMenuTarget ?? (busy ? nil : (cellRange ?? (focusedHost() != nil ? focusedCellRect : nil)))
        guard let target else {
            if !cellMenuButton.isHidden, cellMenuButton.alphaValue > 0 {
                NoteAnimation.fade(cellMenuButton, visible: false, duration: 0.1) { [weak self] in
                    guard let self, self.cellMenuButton.alphaValue == 0 else { return }
                    self.cellMenuButton.isHidden = true
                }
            }
            return
        }
        let rect = displayGeometry.rect(target)
        let size = NoteTableStyle.cellMenuButtonSize
        let lane = min(rect.height, 34)
        let frame = NSRect(x: max(rect.minX + 2, rect.maxX - size.width - 5), y: NoteTableStyle.topInset + rect.minY + (lane - size.height) / 2,
                           width: size.width, height: size.height)
        let wasHidden = cellMenuButton.isHidden || cellMenuButton.alphaValue < 0.01
        if cellMenuButton.frame != frame {
            let previous = cellMenuButton.frame
            NoteAnimation.withoutAnimation { cellMenuButton.frame = frame }
            if !wasHidden { NoteTableMotion.slide(cellMenuButton, from: previous, spring: .settle) }
        }
        if wasHidden {
            cellMenuButton.isHidden = false
            NoteAnimation.fade(cellMenuButton, visible: true, duration: 0.12)
        }
    }

    private func openCellMenu() {
        guard editor != nil, !isReadOnly, let target = cellMenuTarget ?? cellRange ?? focusedCellRect else { return }
        commitComposition()
        dismissMenu()
        let current = table
        let list = NoteMenuList()
        list.minimumWidth = 200
        list.items = [
            NoteMenuList.Item(id: "cell.color", title: "Color", icon: .symbol("paintpalette"), hasSubmenu: true),
            NoteMenuList.Item(id: "cell.merge", title: "Merge Cells", icon: .symbol("arrow.right.and.line.vertical.and.arrow.left"),
                              isEnabled: current.canMerge(rows: target.rows, columns: target.columns), separatorBefore: true),
            NoteMenuList.Item(id: "cell.unmerge", title: "Unmerge Cells", icon: .symbol("arrow.left.and.line.vertical.and.arrow.right"),
                              isEnabled: current.hasMerges(intersecting: target.rows, columns: target.columns)),
            NoteMenuList.Item(id: "cell.clear", title: "Clear Contents", icon: .symbol("eraser"),
                              isEnabled: !NoteTableTransforms.isEmpty(target, of: current), separatorBefore: true),
        ]
        list.onActivate = { [weak self] item in
            guard let self else { return }
            self.dismissMenu()
            switch item.id {
            case "cell.color": self.openColorMenu(for: target, anchor: self.cellMenuButton, highlight: nil)
            case "cell.merge": self.mergeCells(target)
            case "cell.unmerge": self.unmergeCells(target)
            case "cell.clear": self.clear(target, name: "Clear Contents")
            default: break
            }
        }
        list.onCancel = { [weak self] in self?.dismissMenu() }
        cellMenuTarget = target
        cellMenuButton.isActive = true
        presentMenu(list, from: cellMenuButton)
    }

    private func openColorMenu(for target: NoteTableRect, anchor control: NSView, highlight: (axis: Axis, index: Int)?) {
        guard editor != nil, !isReadOnly else { return }
        dismissMenu()
        let entries = NoteBlockMenuModel.colorEntries(current: table.commonColor(rows: target.rows, columns: target.columns))
        let list = NoteMenuList()
        list.minimumWidth = 200
        list.maximumHeight = 360
        list.items = entries.map { NoteMenuList.Item($0) }
        list.onActivate = { [weak self] item in
            guard let self else { return }
            self.dismissMenu()
            guard case .color(let style)? = entries.first(where: { $0.id == item.id })?.action else { return }
            self.setColor(style, in: target)
        }
        list.onCancel = { [weak self] in self?.dismissMenu() }
        if let highlight {
            menuTarget = highlight
            (highlight.axis == .row ? rowGrip : columnGrip).isActive = true
            setGripsVisible(true)
        } else {
            cellMenuTarget = target
            cellMenuButton.isActive = true
        }
        presentMenu(list, from: control)
        if let checked = list.items.first(where: \.isChecked) { list.highlight(id: checked.id, animated: false) }
    }

    private func menuSawClick(_ event: NSEvent) {
        guard let panel = menuPanel, event.window === panel.window else { return }
        if !panel.bounds.contains(panel.convert(event.locationInWindow, from: nil)) { dismissMenu() }
    }

    override var acceptsFirstResponder: Bool { menuPanel != nil }

    override func keyDown(with event: NSEvent) {
        if menuPanel != nil, handleMenuKey(event) { return }
        super.keyDown(with: event)
    }

    private func handleMenuKey(_ event: NSEvent) -> Bool {
        guard let menuList else { return false }
        if menuList.handleKeyDown(event) { return true }
        if event.keyCode == 49, menuList.highlightedIndex != nil { return menuList.activateHighlighted() }
        return false
    }

    private func dismissMenu() {
        guard let panel = menuPanel else { return }
        menuPanel = nil
        panel.dismiss(animated: true)
        menuDidClose()
    }

    private func menuDidClose() {
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        outsideClickMonitor = nil
        menuPanel = nil
        menuList = nil
        menuTarget = nil
        cellMenuTarget = nil
        cellMenuButton.isActive = false
        rowGrip.isActive = false
        columnGrip.isActive = false
        syncSelection()
        if !isHovering { setGripsVisible(false) }
    }

    var tableMenuItems: [NoteMenuList.Item] { Self.tableMenuItems(for: block) }

    @discardableResult
    func performTableMenuItem(_ item: NoteMenuList.Item) -> Bool {
        guard let editor else { return false }
        return Self.performTableMenuItem(item.id, on: blockID, session: editor.session)
    }

    static func tableMenuItems(for block: NoteBlock) -> [NoteMenuList.Item] {
        let table = block.props.table ?? NoteTable.empty()
        return [
            NoteMenuList.Item(id: "table.headerRow", title: "Header Row", icon: .symbol("rectangle.topthird.inset.filled"), isChecked: table.headerRow),
            NoteMenuList.Item(id: "table.headerColumn", title: "Header Column", icon: .symbol("rectangle.leftthird.inset.filled"),
                              isChecked: table.headerColumn),
            NoteMenuList.Item(id: "table.fitWidth", title: "Fit to Width", icon: .symbol("arrow.left.and.right"),
                              isEnabled: table.columnWidths.contains { $0 != nil }),
        ]
    }

    @discardableResult
    static func performTableMenuItem(_ id: String, on blockID: NoteBlockID, session: NotePageSession) -> Bool {
        guard let table = session.page.block(blockID)?.props.table else { return false }
        switch id {
        case "table.headerRow": return session.setTableHeaderRow(blockID, !table.headerRow)
        case "table.headerColumn": return session.setTableHeaderColumn(blockID, !table.headerColumn)
        case "table.fitWidth": return session.setTableColumnWidths(blockID, [], name: "Fit to Width")
        default: return false
        }
    }
}

private extension NSView {
    func frame(in view: NSView) -> NSRect { superview.map { view.convert(frame, from: $0) } ?? frame }
}

private extension NSRect {
    init(x: CGFloat, y: CGFloat, size: NSSize) { self.init(origin: NSPoint(x: x, y: y), size: size) }
}
