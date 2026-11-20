import AppKit
import Combine

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
    private let headerRowFill = NoteTableFillView(frame: .zero)
    private let headerColumnFill = NoteTableFillView(frame: .zero)
    private let frameView = NoteTableFrameView()
    private let selectionView = NoteTableSelectionView()
    private let resizeIndicator = NoteTableRuleView(frame: .zero)
    private let addRowBar = NoteTableAddBar(axis: .row)
    private let addColumnBar = NoteTableAddBar(axis: .column)
    private let rowGrip = NoteTableGripView(axis: .row)
    private let columnGrip = NoteTableGripView(axis: .column)
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
        var value = block.props.table ?? NoteTable.empty()
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
        for view in [headerRowFill, headerColumnFill] { surface.addSubview(view) }
        surface.addSubview(frameView)
        surface.addSubview(selectionView)
        resizeIndicator.color = NoteTableStyle.resizeLine
        resizeIndicator.isHidden = true
        surface.addSubview(resizeIndicator)
        documentView.addSubview(addColumnBar)
        documentView.addSubview(columnGrip)
        addSubview(addRowBar)
        addSubview(rowGrip)
        for bar in [addRowBar, addColumnBar] { bar.alphaValue = 0 }
        for grip in [rowGrip, columnGrip] {
            grip.alphaValue = 0
            grip.isHidden = true
            grip.onPress = { [weak self] grip, event in self?.gripPressed(grip, event: event) }
            grip.onAccessibilityPress = { [weak self] grip in self?.openMenu(for: grip) }
        }
        addRowBar.onAdd = { [weak self] in self?.appendRow() }
        addColumnBar.onAdd = { [weak self] in self?.appendColumn() }
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
    }

    override func themeDidChange() {
        super.themeDidChange()
        for view in surface.subviews { view.needsDisplay = true }
        for view in [rowGrip, columnGrip, addRowBar, addColumnBar] as [NSView] { view.needsDisplay = true }
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
                                  alignment: table.alignments.indices.contains(cell.column) ? table.alignments[cell.column] : nil)
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
        let available = max(0, width - NoteTableStyle.barGap - NoteTableStyle.barThickness)
        let widths = liveWidths ?? NoteTableMetrics.resolvedWidths(current.columnWidths, available: Double(available)).map { CGFloat($0) }
        let heights = current.rows.enumerated().map { rowIndex, row in
            row.enumerated().reduce(CGFloat(0)) { tallest, entry in
                guard entry.offset < widths.count else { return tallest }
                let cell = NoteTableCell(row: rowIndex, column: entry.offset)
                return max(tallest, cellHeight(entry.element, columnWidth: widths[entry.offset], style: cellStyle(cell, in: current)))
            }
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

    private func displayRect(_ cell: NoteTableCell) -> NSRect {
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
        layoutChrome()
        layoutCells()
        if let change = pendingChange {
            runMotion(change, from: motionGeometry ?? previous)
            pendingChange = nil
            motionGeometry = nil
            motionSnapshot = nil
        }
    }

    private func layoutChrome() {
        let shown = displayGeometry
        let tableHeight = shown.height, tableWidth = shown.width
        let documentWidth = max(bounds.width, tableWidth + NoteTableStyle.barGap + NoteTableStyle.barThickness)
        let scrollHeight = NoteTableStyle.topInset + tableHeight + 1
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        scrollView.frame = NSRect(x: 0, y: 0, width: bounds.width, height: scrollHeight)
        documentView.frame = NSRect(x: 0, y: 0, width: documentWidth, height: scrollHeight)
        surface.frame = NSRect(x: 0, y: NoteTableStyle.topInset, width: tableWidth, height: tableHeight)
        frameView.frame = surface.bounds
        selectionView.frame = surface.bounds
        addColumnBar.frame = NSRect(x: tableWidth + NoteTableStyle.barGap, y: NoteTableStyle.topInset,
                                    width: NoteTableStyle.barThickness, height: tableHeight)
        let visibleTable = max(0, min(tableWidth - scrollView.horizontalOffset, bounds.width))
        addRowBar.frame = NSRect(x: 0, y: NoteTableStyle.topInset + tableHeight + NoteTableStyle.barGap,
                                 width: visibleTable, height: NoteTableStyle.barThickness)
        let current = table
        headerRowFill.isHidden = !current.headerRow || shown.rowCount == 0
        headerColumnFill.isHidden = !current.headerColumn || shown.columnCount == 0
        let headerTop = current.headerRow ? (shown.rowHeights.first ?? 0) : 0
        headerRowFill.frame = NSRect(x: 0, y: 0, width: tableWidth, height: shown.rowHeights.first ?? 0)
        headerColumnFill.frame = NSRect(x: 0, y: headerTop, width: shown.columnWidths.first ?? 0, height: max(0, tableHeight - headerTop))
        headerRowFill.tableBounds = surface.bounds
        headerColumnFill.tableBounds = surface.bounds
        layoutRules(shown)
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

    private func layoutRules(_ shown: NoteTableGeometry) {
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
        }
        for (index, rule) in columnRules.enumerated() {
            rule.frame = surface.backingAlignedRect(NSRect(x: shown.columnEdges[index + 1] - line / 2, y: 0, width: line, height: shown.height),
                                                    options: .alignAllEdgesNearest)
        }
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
        var wanted = Set<NoteTableCell>()
        if !isVirtualizing {
            for row in 0..<current.rowCount { for column in 0..<current.columnCount { wanted.insert(NoteTableCell(row: row, column: column)) } }
            return wanted
        }
        let visible = convert(visibleRect, to: surface)
        let clip = documentView.convert(scrollView.contentView.bounds, to: surface)
        let shown = displayGeometry
        if let rows = NoteTableMetrics.visibleRange(from: Double(visible.minY), to: Double(visible.maxY), sizes: shown.rowHeights.map(Double.init)),
           let columns = NoteTableMetrics.visibleRange(from: Double(clip.minX), to: Double(clip.maxX), sizes: shown.columnWidths.map(Double.init)) {
            for row in max(0, rows.lowerBound - 1)...min(current.rowCount - 1, rows.upperBound + 1) {
                for column in max(0, columns.lowerBound - 1)...min(current.columnCount - 1, columns.upperBound + 1) {
                    wanted.insert(NoteTableCell(row: row, column: column))
                }
            }
        }
        if let focused = focusedHost()?.cell { wanted.insert(focused) }
        wanted.formUnion(pinnedCells.filter { $0.row < current.rowCount && $0.column < current.columnCount })
        return wanted
    }

    private func layoutCells() {
        let current = table
        let wanted = wantedCells()
        let focused = focusedHost()
        for (cell, host) in hosts where !wanted.contains(cell)
            && (host !== focused || cell.row >= current.rowCount || cell.column >= current.columnCount) {
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
        surface.addSubview(view, positioned: .below, relativeTo: frameView)
        hosts[cell] = host
        return host
    }

    private func recycle(_ host: NoteTableCellHost) {
        let view = host.cellView
        NoteTableMotion.settle(view)
        view.removeFromSuperview()
        view.host = nil
        if pool.count < 24 { pool.append(view) }
    }

    private func bind(_ host: NoteTableCellHost, cell: NoteTableCell, table current: NoteTable) {
        host.cell = cell
        let view = host.cellView
        view.configure(cellStyle(cell, in: current))
        let text = current.rows[cell.row][cell.column]
        if view.noteText != text, !view.hasMarkedText() { view.apply(text, selection: nil) }
        let frame = editorFrame(displayRect(cell))
        if view.frame != frame { view.frame = frame }
        let hidden = (drag.map { $0.axis == .row ? $0.source == cell.row : $0.source == cell.column } ?? false)
            || (settlingDrag.map { $0.axis == .row ? $0.index == cell.row : $0.index == cell.column } ?? false)
        view.alphaValue = hidden ? 0 : 1
    }

    @discardableResult
    private func materialize(_ cell: NoteTableCell) -> NoteTableCellHost? {
        let current = table
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
        let rect = geometry.cellRect(cell)
        scrollView.scrollHorizontally(toReveal: surface.convert(rect, to: documentView))
        scrollToVisible(convert(rect, from: surface).insetBy(dx: 0, dy: -12))
    }

    var hasCellRange: Bool { cellRange != nil }

    private var cellRangeEnds: (anchor: NoteTableCell, head: NoteTableCell)? {
        guard case .cells(let id, let anchor, let head) = editor?.session.selection, id == blockID else { return nil }
        return (anchor, head)
    }

    private var cellRange: NoteTableRect? {
        cellRangeEnds.map { NoteTableRect($0.anchor, $0.head) }
    }

    private func syncSelection() {
        if let pointerRange {
            selectionView.style = .selection
            selectionView.highlight = displayGeometry.rect(NoteTableRect(pointerRange.anchor, pointerRange.head))
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
            move(from: host, to: NoteTableNavigation.tab(from: cell, rows: current.rowCount, columns: current.columnCount,
                                                         backward: flags.contains(.shift)), placement: .end)
            return true
        case 36, 76:
            if flags == [.shift] {
                if !isReadOnly { view.insertNewlineIgnoringFieldEditor(nil) }
                return true
            }
            guard flags.isEmpty else { return false }
            move(from: host, to: NoteTableNavigation.returnKey(from: cell, rows: current.rowCount), placement: .end)
            return true
        case 53:
            guard flags.isEmpty else { return false }
            selectTableBlock()
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
                setRange(anchor: cell, head: NoteTableNavigation.moved(cell, direction, rows: current.rowCount, columns: current.columnCount))
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
            let x = surface.convert(view.caretRect(at: direction == .down ? selection.upperBound : selection.lowerBound), from: view).midX
            let placement: Placement
            switch direction {
            case .up: placement = .x(x, firstLine: false)
            case .down: placement = .x(x, firstLine: true)
            case .left: placement = .end
            case .right: placement = .start
            }
            move(from: host, to: NoteTableNavigation.step(from: cell, direction, rows: current.rowCount, columns: current.columnCount),
                 placement: placement)
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
            let head = NoteTableNavigation.moved(ends.head, direction, rows: current.rowCount, columns: current.columnCount)
            setRange(anchor: flags.contains(.shift) ? ends.anchor : head, head: head)
            return true
        case 48:
            guard flags.isSubset(of: [.shift]) else { return false }
            switch NoteTableNavigation.tab(from: ends.head, rows: current.rowCount, columns: current.columnCount, backward: flags.contains(.shift)) {
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
                  focusCell(ends.head, placement: .end), let host = hosts[ends.head] else { return false }
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
        if target == view.cell {
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
        if widths != base {
            commit("Resize Column") { NoteTableTransforms.setWidths(widths.map { Optional($0) }, in: &$0) }
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

    override func mouseEntered(with event: NSEvent) { pointerMoved(event) }
    override func mouseMoved(with event: NSEvent) { pointerMoved(event) }

    override func mouseExited(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if [rowGrip, columnGrip].contains(where: { !$0.isHidden && $0.frame(in: self).insetBy(dx: -4, dy: -4).contains(point) }) { return }
        hideHoverChrome(animated: true)
    }

    private func pointerMoved(_ event: NSEvent) {
        guard !isReadOnly, drag == nil, resizingColumn == nil else { return }
        if !isHovering {
            isHovering = true
            for bar in [addRowBar, addColumnBar] { NoteAnimation.fade(bar, visible: true, duration: 0.12) }
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
        for bar in [addRowBar, addColumnBar] {
            if animated { NoteAnimation.fade(bar, visible: false, duration: 0.12) } else { bar.alphaValue = 0 }
        }
        resizeIndicator.isHidden = resizingColumn == nil
    }

    private func scrollDidChange() {
        let shown = displayGeometry
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        addRowBar.frame.size.width = max(0, min(shown.width - scrollView.horizontalOffset, bounds.width))
        CATransaction.commit()
        if isVirtualizing { layoutCells() }
    }

    private func gripPressed(_ grip: NoteTableGripView, event: NSEvent) {
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
        let before = Dictionary(uniqueKeysWithValues: hosts.map { ($0.key, ($0.value.cellView.frame, NoteTableMotion.presentedOffset($0.value.cellView))) })
        let rulesBefore = (rowRules + columnRules).map { ($0, $0.frame, NoteTableMotion.presentedOffset($0)) }
        current.target = target
        drag = current
        layoutChrome()
        layoutCells()
        for (cell, host) in hosts {
            guard let old = before[cell] else { continue }
            NoteTableMotion.slide(host.cellView, from: old.0, offset: old.1)
        }
        for (rule, frame, offset) in rulesBefore where rule.superview != nil { NoteTableMotion.slide(rule, from: frame, offset: offset) }
    }

    private func endDrag() {
        guard let finished = drag else { return }
        for host in hosts.values { NoteTableMotion.settle(host.cellView) }
        for rule in rowRules + columnRules { NoteTableMotion.settle(rule) }
        let ghost = finished.ghost
        let slot = finished.axis == .row ? displayGeometry.rowRect(finished.target) : displayGeometry.columnRect(finished.target)
        settlingDrag = (finished.axis, finished.target)
        drag = nil
        if finished.target != finished.source {
            let change: NoteTableChange = finished.axis == .row ? .moveRow(from: finished.source, to: finished.target)
                : .moveColumn(from: finished.source, to: finished.target)
            commit(finished.axis == .row ? "Move Row" : "Move Column", selection: remappedSelection(change)) { NoteTableTransforms.apply(change, to: &$0) }
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

    private func remappedSelection(_ change: NoteTableChange) -> NotePageSelection? {
        guard let editor else { return nil }
        switch editor.session.selection {
        case .text(let anchor, let head):
            guard head.block == blockID, case .cell(let row, let column) = head.field else { return nil }
            let current = table
            var cell = change.newCell(for: NoteTableCell(row: row, column: column))
            if cell == nil {
                let fallbackRow = change.newRow(for: row) ?? min(row, current.rowCount - 2)
                let fallbackColumn = change.newColumn(for: column) ?? min(column, current.columnCount - 2)
                cell = NoteTableCell(row: max(0, fallbackRow), column: max(0, fallbackColumn))
                return .caret(NotePosition(blockID, 0, field: .cell(row: cell!.row, column: cell!.column)))
            }
            let field = NoteTextField.cell(row: cell!.row, column: cell!.column)
            return .text(anchor: NotePosition(blockID, anchor.offset, field: field), head: NotePosition(blockID, head.offset, field: field))
        case .cells(let id, let anchor, let head) where id == blockID:
            guard let newAnchor = change.newCell(for: anchor), let newHead = change.newCell(for: head) else { return NotePageSelection.none }
            return .cells(table: blockID, anchor: newAnchor, head: newHead)
        default:
            return nil
        }
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
        for (cell, host) in hosts {
            let view = host.cellView
            if let row = change.oldRow(for: cell.row), let column = change.oldColumn(for: cell.column),
               old.contains(NoteTableCell(row: row, column: column)) {
                NoteTableMotion.slide(view, from: editorFrame(old.cellRect(NoteTableCell(row: row, column: column))))
            } else {
                NoteTableMotion.fadeIn(view, delay: 0.04)
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
        NoteTableMotion.resize(headerRowFill, from: NSSize(width: old.width, height: old.rowHeights.first ?? 0))
        NoteTableMotion.resize(headerColumnFill, from: NSSize(width: old.columnWidths.first ?? 0, height: headerColumnFill.frame.height + old.height - geometry.height))
        let barShift = NSRect(x: addRowBar.frame.minX, y: NoteTableStyle.topInset + old.height + NoteTableStyle.barGap,
                              width: addRowBar.frame.width, height: addRowBar.frame.height)
        NoteTableMotion.slide(addRowBar, from: barShift)
        NoteTableMotion.slide(addColumnBar, from: NSRect(x: old.width + NoteTableStyle.barGap, y: addColumnBar.frame.minY,
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

    private func revealInserted(_ change: NoteTableChange, name: String, focus: NoteTableCell? = nil,
                                _ transform: @escaping (inout NoteTable) -> Void) {
        var selection = remappedSelection(change)
        if let focus { selection = .caret(NotePosition(blockID, 0, field: .cell(row: focus.row, column: focus.column))) }
        commit(name, change: change, selection: selection, transform)
        if let focus { focusCell(focus, placement: .start) }
    }

    func appendRow(focusColumn: Int? = nil) {
        let current = table
        let change = NoteTableChange.insertRows(at: current.rowCount, count: 1)
        revealInserted(change, name: "Add Row", focus: focusColumn.map { NoteTableCell(row: current.rowCount, column: $0) }) {
            NoteTableTransforms.apply(change, to: &$0)
        }
    }

    func appendColumn() {
        let change = NoteTableChange.insertColumns(at: table.columnCount, count: 1)
        revealInserted(change, name: "Add Column") { NoteTableTransforms.apply(change, to: &$0) }
    }

    func insertRow(at index: Int) {
        let change = NoteTableChange.insertRows(at: index, count: 1)
        revealInserted(change, name: "Insert Row") { NoteTableTransforms.apply(change, to: &$0) }
    }

    func insertColumn(at index: Int) {
        let change = NoteTableChange.insertColumns(at: index, count: 1)
        revealInserted(change, name: "Insert Column") { NoteTableTransforms.apply(change, to: &$0) }
    }

    func duplicate(_ axis: Axis, at index: Int) {
        let change: NoteTableChange = axis == .row ? .insertRows(at: index + 1, count: 1) : .insertColumns(at: index + 1, count: 1)
        revealInserted(change, name: axis == .row ? "Duplicate Row" : "Duplicate Column") { table in
            if axis == .row { NoteTableTransforms.duplicateRow(index, in: &table) } else { NoteTableTransforms.duplicateColumn(index, in: &table) }
        }
    }

    func delete(_ axis: Axis, at index: Int) {
        let current = table
        guard (axis == .row ? current.rowCount : current.columnCount) > 1 else { return }
        let change: NoteTableChange = axis == .row ? .deleteRows(at: index, count: 1) : .deleteColumns(at: index, count: 1)
        commit(axis == .row ? "Delete Row" : "Delete Column", change: change, selection: remappedSelection(change)) {
            NoteTableTransforms.apply(change, to: &$0)
        }
    }

    func move(_ axis: Axis, from index: Int, to target: Int) {
        let current = table
        let count = axis == .row ? current.rowCount : current.columnCount
        guard index != target, (0..<count).contains(index), (0..<count).contains(target) else { return }
        let change: NoteTableChange = axis == .row ? .moveRow(from: index, to: target) : .moveColumn(from: index, to: target)
        commit(axis == .row ? "Move Row" : "Move Column", change: change, selection: remappedSelection(change)) {
            NoteTableTransforms.apply(change, to: &$0)
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
        let headerRow = current.headerRow && rect.rows.lowerBound == 0
        let headerColumn = current.headerColumn && rect.columns.lowerBound == 0
        let alignments = rect.columns.map { current.alignments[$0] }
        let tsv = NoteTableClipboard.tsv(rows)
        pasteboard.clearContents()
        pasteboard.declareTypes([Self.cellsPasteboardType, .string, .tabularText, .html, Self.markdownPasteboardType], owner: nil)
        if let data = try? JSONEncoder().encode(rows) { pasteboard.setData(data, forType: Self.cellsPasteboardType) }
        pasteboard.setString(tsv, forType: .string)
        pasteboard.setString(tsv, forType: .tabularText)
        pasteboard.setString(NoteTableClipboard.html(rows, headerRow: headerRow, headerColumn: headerColumn, alignments: alignments), forType: .html)
        pasteboard.setString(NoteTableClipboard.markdown(rows, headerRow: headerRow, headerColumn: headerColumn, alignments: alignments),
                             forType: Self.markdownPasteboardType)
    }

    static func grid(from pasteboard: NSPasteboard) -> [[NoteText]]? {
        if let data = pasteboard.data(forType: cellsPasteboardType), let rows = try? JSONDecoder().decode([[NoteText]].self, from: data), !rows.isEmpty {
            return rows
        }
        for type in [NSPasteboard.PasteboardType.tabularText, .string] {
            if let text = pasteboard.string(forType: type), let grid = NoteTableClipboard.grid(fromDelimited: text) {
                return NoteTableClipboard.cells(from: grid)
            }
        }
        return nil
    }

    func pasteIntoCell(_ view: NoteTableCellTextView) -> Bool {
        guard !isReadOnly, let grid = Self.grid(from: .general), grid.count * (grid.map(\.count).max() ?? 0) > 1 else { return false }
        paste(grid, at: view.cell, filling: nil)
        return true
    }

    func pasteIntoRange() {
        guard !isReadOnly, let rect = cellRange else { return }
        let pasteboard = NSPasteboard.general
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

    private func setHeader(_ axis: Axis, _ enabled: Bool) {
        commit(axis == .row ? "Header Row" : "Header Column") { table in
            if axis == .row { table.headerRow = enabled } else { table.headerColumn = enabled }
        }
    }

    private func setAlignment(_ alignment: NoteAlignment, column: Int) {
        commit("Align Column") { NoteTableTransforms.setAlignment(alignment, column: column, in: &$0) }
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
        items.append(NoteMenuList.Item(id: "duplicate", title: "Duplicate", icon: .symbol("plus.square.on.square"), separatorBefore: true))
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
        default:
            if id.hasPrefix("align."), let alignment = NoteAlignment(rawValue: String(id.dropFirst(6))) { setAlignment(alignment, column: index) }
        }
    }

    private func openMenu(for grip: NoteTableGripView) {
        guard let editor, !isReadOnly else { return }
        dismissMenu()
        let axis: Axis = grip.axis == .row ? .row : .column
        let index = grip.index
        let list = NoteMenuList()
        list.items = menuItems(axis: axis, index: index)
        list.onActivate = { [weak self] item in
            self?.dismissMenu()
            self?.performMenuItem(item.id, axis: axis, index: index)
        }
        list.onCancel = { [weak self] in self?.dismissMenu() }
        let panel = NoteFloatingPanel(content: list)
        panel.onDismiss = { [weak self, weak panel] in
            guard let self, let panel, self.menuPanel === panel else { return }
            self.menuDidClose()
        }
        menuPanel = panel
        menuList = list
        menuTarget = (axis, index)
        grip.isActive = true
        setGripsVisible(true)
        let host = editor.canvas.overlayView
        let anchor = grip.convert(grip.bounds, to: host)
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
        let transform: (inout NoteTable) -> Void
        let name: String
        switch id {
        case "table.headerRow": (name, transform) = ("Header Row", { $0.headerRow.toggle() })
        case "table.headerColumn": (name, transform) = ("Header Column", { $0.headerColumn.toggle() })
        case "table.fitWidth": (name, transform) = ("Fit to Width", { NoteTableTransforms.setWidths([], in: &$0) })
        default: return false
        }
        guard session.page.block(blockID)?.props.table != nil else { return false }
        session.edit(name, kind: .text, affected: [blockID]) { page in
            page.update(blockID) { block in
                guard var table = block.props.table else { return }
                transform(&table)
                table.normalize()
                block.props.table = table
            }
        }
        return true
    }
}

private extension NSView {
    func frame(in view: NSView) -> NSRect { superview.map { view.convert(frame, from: $0) } ?? frame }
}

private extension NSRect {
    init(x: CGFloat, y: CGFloat, size: NSSize) { self.init(origin: NSPoint(x: x, y: y), size: size) }
}
