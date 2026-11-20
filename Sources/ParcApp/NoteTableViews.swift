import AppKit

struct NoteTableCellStyle: Hashable {
    var font: NotePageFont = .standard
    var small = false
    var header = false
    var alignment: NoteAlignment?
}

@MainActor
enum NoteTableStyle {
    static let border = NoteTheme.tableBorder
    static let headerFill = NoteTheme.tableHeaderFill
    static let selectionFill = NoteTheme.blockSelection
    static let selectionStroke = NoteTheme.adaptive("Table.SelectionStroke", light: NoteTheme.rgb(0x2702C2, 0.7), dark: NoteTheme.rgb(0x9380E0, 0.85))
    static let menuTint = NoteTheme.adaptive("Table.MenuTint", light: NoteTheme.rgb(0x2702C2, 0.06), dark: NoteTheme.rgb(0x9380E0, 0.12))
    static let resizeLine = NoteTheme.dropIndicatorFallback
    static let gripFill = NoteTheme.menuFill
    static let gripStroke = NoteTheme.menuHairline
    static let gripInk = NoteTheme.handleInk
    static let gripActiveInk = NoteTheme.secondaryInk
    static let barFill = NoteTheme.hoverFill
    static let barPressedFill = NoteTheme.pressedFill
    static let barInk = NoteTheme.handleInk
    static let ghostFill = NoteTheme.menuFill

    static let topInset: CGFloat = 10
    static let bottomInset: CGFloat = 4
    static let barThickness: CGFloat = 16
    static let barGap: CGFloat = 4
    static let horizontalPadding: CGFloat = 10
    static let verticalPadding: CGFloat = 7
    static let editorEdgeGap: CGFloat = 3
    static let resizeTolerance: CGFloat = 3
    static let cornerRadius: CGFloat = NoteTheme.blockRadius
    static let rowGripSize = NSSize(width: 12, height: 20)
    static let columnGripSize = NSSize(width: 20, height: 12)
    static let fadeWidth: CGFloat = 28
    static let virtualizationThreshold = 150
    static let gripTooltip = "Drag to move, click for options"

    static func presentation(_ style: NoteTableCellStyle) -> NoteTextPresentation {
        NoteTextPresentation(role: style.header ? .tableHeader : .tableCell, pageFont: style.font, small: style.small,
                             alignment: textAlignment(style.alignment))
    }

    static func textAlignment(_ alignment: NoteAlignment?) -> NSTextAlignment {
        switch alignment {
        case .center: return .center
        case .right: return .right
        case .left, nil: return .natural
        }
    }
}

@MainActor
final class NoteTableCellTextView: NoteTextView {
    weak var table: NoteTableBlockView?
    var cell = NoteTableCell(row: 0, column: 0)
    private(set) var cellStyle = NoteTableCellStyle()
    private(set) var isTrackingPointer = false
    private var isConfigured = false

    var isHeaderCell: Bool { cellStyle.header }

    func configure(_ style: NoteTableCellStyle) {
        guard !isConfigured || style != cellStyle else { return }
        isConfigured = true
        cellStyle = style
        presentation = NoteTableStyle.presentation(style)
    }

    override func keyDown(with event: NSEvent) {
        if !hasMarkedText(), let table, table.handleCellKey(event, in: self) { return }
        super.keyDown(with: event)
    }

    override func mouseDown(with event: NSEvent) {
        guard let table else { super.mouseDown(with: event); return }
        if table.handleCellMouseDown(event, in: self) { return }
        isTrackingPointer = true
        super.mouseDown(with: event)
        isTrackingPointer = false
        table.pointerSelectionEnded(in: self)
    }

    override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting flag: Bool) {
        if isTrackingPointer, let table, let window,
           table.pointerSelectionMoved(in: self, to: window.mouseLocationOutsideOfEventStream, finished: !flag) {
            let anchor = selectedOffsets.lowerBound
            super.setSelectedRanges([NSValue(range: NSRange(location: anchor, length: 0))], affinity: affinity, stillSelecting: flag)
            return
        }
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: flag)
    }

    override func paste(_ sender: Any?) {
        if let table, table.pasteIntoCell(self) { return }
        super.paste(sender)
    }

    override func isAccessibilityElement() -> Bool { true }

    override func accessibilityLabel() -> String? {
        let position = String(format: "Row %d, column %d", cell.row + 1, cell.column + 1)
        return isHeaderCell ? "Header, " + position.lowercased() : position
    }
}

@MainActor
final class NoteTableCellHost: NoteTextHost {
    let blockID: NoteBlockID
    var field: NoteTextField
    let cellView: NoteTableCellTextView

    init(blockID: NoteBlockID, cell: NoteTableCell, view: NoteTableCellTextView) {
        self.blockID = blockID
        field = .cell(row: cell.row, column: cell.column)
        cellView = view
    }

    var textView: NoteTextView { cellView }

    var cell: NoteTableCell {
        get { cellView.cell }
        set {
            cellView.cell = newValue
            field = .cell(row: newValue.row, column: newValue.column)
        }
    }
}

@MainActor
final class NoteTableScrollView: NSScrollView {
    private var forwardsGesture = false
    private let fadeMask = CAGradientLayer()
    var onScroll: (() -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        drawsBackground = false
        hasVerticalScroller = false
        hasHorizontalScroller = true
        autohidesScrollers = true
        scrollerStyle = .overlay
        horizontalScrollElasticity = .allowed
        verticalScrollElasticity = .none
        usesPredominantAxisScrolling = true
        contentView.postsBoundsChangedNotifications = true
        wantsLayer = true
        fadeMask.startPoint = CGPoint(x: 0, y: 0.5)
        fadeMask.endPoint = CGPoint(x: 1, y: 0.5)
        NotificationCenter.default.addObserver(self, selector: #selector(clipBoundsChanged), name: NSView.boundsDidChangeNotification,
                                               object: contentView)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    var horizontalOffset: CGFloat { contentView.bounds.minX }

    var overflows: Bool { (documentView?.frame.width ?? 0) > bounds.width + 0.5 }

    override func scrollWheel(with event: NSEvent) {
        if event.phase == .began || (event.phase == [] && event.momentumPhase == []) {
            forwardsGesture = !overflows || abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX)
        }
        if forwardsGesture { nextResponder?.scrollWheel(with: event) } else { super.scrollWheel(with: event) }
    }

    @objc private func clipBoundsChanged() {
        updateFade()
        onScroll?()
    }

    func updateFade() {
        let width = bounds.width
        guard overflows, width > 0, let document = documentView else {
            if layer?.mask != nil { layer?.mask = nil }
            return
        }
        let offset = horizontalOffset
        let remaining = document.frame.width - offset - width
        let fade = min(NoteTableStyle.fadeWidth / width, 0.3)
        let opaque = NSColor.black.cgColor, clear = NSColor.black.withAlphaComponent(0).cgColor
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fadeMask.frame = bounds
        fadeMask.colors = [offset > 0.5 ? clear : opaque, opaque, opaque, remaining > 0.5 ? clear : opaque]
        fadeMask.locations = [0, NSNumber(value: Double(fade)), NSNumber(value: Double(1 - fade)), 1]
        if layer?.mask !== fadeMask { layer?.mask = fadeMask }
        CATransaction.commit()
    }

    func scrollHorizontally(toReveal rect: NSRect) {
        let visible = contentView.bounds
        var x = visible.minX
        if rect.minX < visible.minX { x = rect.minX - 8 } else if rect.maxX > visible.maxX { x = rect.maxX - visible.width + 8 }
        let limit = max(0, (documentView?.frame.width ?? 0) - visible.width)
        x = min(max(0, x), limit)
        guard abs(x - visible.minX) > 0.5 else { return }
        contentView.scroll(to: NSPoint(x: x, y: 0))
        reflectScrolledClipView(contentView)
    }
}

@MainActor
final class NoteTableDocumentView: NSView {
    override var isFlipped: Bool { true }
}

@MainActor
final class NoteTableSurfaceView: NSView, NSMenuItemValidation {
    weak var table: NoteTableBlockView?
    var resizeBoundaries: [NSRect] = [] { didSet { if oldValue != resizeBoundaries { window?.invalidateCursorRects(for: self) } } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = NoteTableStyle.cornerRadius
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    override var acceptsFirstResponder: Bool { table?.hasCellRange == true }

    override func resetCursorRects() {
        for rect in resizeBoundaries { addCursorRect(rect, cursor: .resizeLeftRight) }
    }

    override func mouseDown(with event: NSEvent) {
        if table?.handleSurfaceMouseDown(event) != true { super.mouseDown(with: event) }
    }

    override func keyDown(with event: NSEvent) {
        if table?.handleRangeKey(event) != true { super.keyDown(with: event) }
    }

    @objc func copy(_ sender: Any?) { table?.copyRange(cut: false) }
    @objc func cut(_ sender: Any?) { table?.copyRange(cut: true) }
    @objc func paste(_ sender: Any?) { table?.pasteIntoRange() }
    @objc func delete(_ sender: Any?) { table?.clearRange() }
    @objc override func selectAll(_ sender: Any?) { table?.selectWholeTable() }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        guard let table, table.hasCellRange else { return false }
        switch item.action {
        case #selector(copy(_:)), #selector(selectAll(_:)): return true
        case #selector(cut(_:)), #selector(paste(_:)), #selector(delete(_:)): return !table.isReadOnly
        default: return false
        }
    }
}

@MainActor
final class NoteTableRuleView: NSView {
    var color: NSColor = NoteTableStyle.border { didSet { needsDisplay = true } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        color.setFill()
        bounds.fill()
    }
}

@MainActor
final class NoteTableFillView: NSView {
    var tableBounds: NSRect = .zero { didSet { needsDisplay = true } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        let clip = tableBounds.offsetBy(dx: -frame.minX, dy: -frame.minY)
        NSBezierPath(roundedRect: clip, xRadius: NoteTableStyle.cornerRadius, yRadius: NoteTableStyle.cornerRadius).addClip()
        NoteTableStyle.headerFill.setFill()
        bounds.fill()
    }
}

@MainActor
final class NoteTableFrameView: NSView {
    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        let line = 1 / (window?.backingScaleFactor ?? 2)
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: line / 2, dy: line / 2),
                                xRadius: NoteTableStyle.cornerRadius - line / 2, yRadius: NoteTableStyle.cornerRadius - line / 2)
        path.lineWidth = line
        NoteTableStyle.border.setStroke()
        path.stroke()
    }
}

@MainActor
final class NoteTableSelectionView: NSView {
    enum Style { case selection, menu }
    var highlight: NSRect? { didSet { if oldValue != highlight { needsDisplay = true } } }
    var style: Style = .selection { didSet { needsDisplay = true } }

    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        guard let highlight else { return }
        switch style {
        case .menu:
            NoteTableStyle.menuTint.setFill()
            highlight.fill()
        case .selection:
            NoteTableStyle.selectionFill.setFill()
            highlight.fill()
            let path = NSBezierPath(roundedRect: highlight.insetBy(dx: 0.75, dy: 0.75), xRadius: 2, yRadius: 2)
            path.lineWidth = 1.5
            NoteTableStyle.selectionStroke.setStroke()
            path.stroke()
        }
    }
}

@MainActor
final class NoteTableGripView: NSView {
    enum Axis { case row, column }
    let axis: Axis
    var index = 0
    var onPress: ((NoteTableGripView, NSEvent) -> Void)?
    var onAccessibilityPress: ((NoteTableGripView) -> Void)?
    var isActive = false { didSet { if oldValue != isActive { needsDisplay = true } } }
    private var isHovered = false { didSet { if oldValue != isHovered { needsDisplay = true } } }
    private var hoverArea: NSTrackingArea?

    init(axis: Axis) {
        self.axis = axis
        super.init(frame: NSRect(origin: .zero, size: axis == .row ? NoteTableStyle.rowGripSize : NoteTableStyle.columnGripSize))
        wantsLayer = true
        parcTooltip = TooltipConfiguration(NoteTableStyle.gripTooltip)
        setAccessibilityHelp(NoteTableStyle.gripTooltip)
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.08
        layer?.shadowRadius = 2
        layer?.shadowOffset = CGSize(width: 0, height: -1)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    override func updateTrackingAreas() {
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .cursorUpdate, .activeInKeyWindow], owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverArea = area
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false }
    override func cursorUpdate(with event: NSEvent) { NSCursor.pointingHand.set() }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        NoteTableMotion.press(self, pressed: true)
        onPress?(self, event)
        NoteTableMotion.press(self, pressed: false)
    }

    override func draw(_ dirtyRect: NSRect) {
        let plate = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: plate, xRadius: 4, yRadius: 4)
        NoteTableStyle.gripFill.setFill()
        path.fill()
        if isHovered || isActive {
            NoteTheme.hoverFill.setFill()
            path.fill()
        }
        path.lineWidth = 1 / (window?.backingScaleFactor ?? 2)
        NoteTableStyle.gripStroke.setStroke()
        path.stroke()
        (isHovered || isActive ? NoteTableStyle.gripActiveInk : NoteTableStyle.gripInk).setFill()
        let dot: CGFloat = 2, gap: CGFloat = 2
        let columns = axis == .row ? 2 : 3, rows = axis == .row ? 3 : 2
        let width = CGFloat(columns) * dot + CGFloat(columns - 1) * gap
        let height = CGFloat(rows) * dot + CGFloat(rows - 1) * gap
        let origin = NSPoint(x: bounds.midX - width / 2, y: bounds.midY - height / 2)
        for row in 0..<rows {
            for column in 0..<columns {
                let rect = NSRect(x: origin.x + CGFloat(column) * (dot + gap), y: origin.y + CGFloat(row) * (dot + gap), width: dot, height: dot)
                NSBezierPath(ovalIn: rect).fill()
            }
        }
    }

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .button }
    override func accessibilityLabel() -> String? {
        axis == .row ? "Row \(index + 1) options" : "Column \(index + 1) options"
    }
    override func accessibilityPerformPress() -> Bool {
        onAccessibilityPress?(self)
        return true
    }
}

@MainActor
final class NoteTableAddBar: NSView {
    enum Axis { case row, column }
    let axis: Axis
    var onAdd: (() -> Void)?
    var onHoverChange: ((Bool) -> Void)?
    private var isHovered = false { didSet { if oldValue != isHovered { needsDisplay = true } } }
    private var isPressed = false { didSet { if oldValue != isPressed { needsDisplay = true } } }
    private var hoverArea: NSTrackingArea?

    init(axis: Axis) {
        self.axis = axis
        super.init(frame: .zero)
        wantsLayer = true
        parcTooltip = TooltipConfiguration(axis == .row ? "Click to add a row" : "Click to add a column")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    override func updateTrackingAreas() {
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .cursorUpdate, .activeInKeyWindow], owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverArea = area
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        onHoverChange?(true)
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        onHoverChange?(false)
    }

    override func cursorUpdate(with event: NSEvent) {
        if alphaValue > 0.01 { NSCursor.pointingHand.set() } else { super.cursorUpdate(with: event) }
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        isPressed = true
        NoteTableMotion.press(self, pressed: true, scale: 0.985)
        var inside = true
        window?.trackEvents(matching: [.leftMouseDragged, .leftMouseUp], timeout: .infinity, mode: .eventTracking) { next, stop in
            guard let next else { stop.pointee = true; return }
            inside = bounds.contains(convert(next.locationInWindow, from: nil))
            isPressed = inside
            if next.type == .leftMouseUp { stop.pointee = true }
        }
        isPressed = false
        NoteTableMotion.press(self, pressed: false, scale: 0.985)
        if inside { onAdd?() }
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds, xRadius: 4, yRadius: 4)
        if isPressed { NoteTableStyle.barPressedFill.setFill(); path.fill() } else if isHovered { NoteTableStyle.barFill.setFill(); path.fill() }
        let ink = isHovered ? NoteTheme.secondaryInk : NoteTableStyle.barInk
        ink.setStroke()
        let center = NSPoint(x: bounds.midX, y: bounds.midY), arm: CGFloat = 4.5
        let plus = NSBezierPath()
        plus.move(to: NSPoint(x: center.x - arm, y: center.y))
        plus.line(to: NSPoint(x: center.x + arm, y: center.y))
        plus.move(to: NSPoint(x: center.x, y: center.y - arm))
        plus.line(to: NSPoint(x: center.x, y: center.y + arm))
        plus.lineWidth = 1.5
        plus.lineCapStyle = .round
        plus.stroke()
    }

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .button }
    override func accessibilityLabel() -> String? { axis == .row ? "Add a row" : "Add a column" }
    override func accessibilityPerformPress() -> Bool {
        onAdd?()
        return true
    }
}
