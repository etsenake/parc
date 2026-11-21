import AppKit

@MainActor
final class EaselPageSwitcherButton: PointingHandButton {
    static let maximumWidth: CGFloat = 200
    private var pointerInside = false
    private var hoverTracking: NSTrackingArea?

    var pageName = EaselPages.firstPageName {
        didSet {
            guard pageName != oldValue else { return }
            setAccessibilityValue(pageName)
            invalidateIntrinsicContentSize()
            needsDisplay = true
            EaselControlSurface.crossfade(self, pops: 0.97)
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isBordered = false
        focusRingType = .exterior
        title = ""
        setButtonType(.momentaryChange)
        wantsLayer = true
        NoteAnimation.observeReduceMotion(self) { [weak self] in
            guard let self else { return }
            NoteAnimation.settle(self)
            EaselControlSurface.apply(self, hovered: false, pressed: false, casts: false)
        }
        setAccessibilityRole(.popUpButton)
        setAccessibilityLabel("Pages")
        setAccessibilityValue(pageName)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private var titleAttributes: [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        return [.font: NoteTheme.chromeFont(13), .paragraphStyle: paragraph]
    }

    override var intrinsicContentSize: NSSize {
        let text = ceil((pageName as NSString).size(withAttributes: titleAttributes).width)
        return NSSize(width: min(Self.maximumWidth, 10 + text + 6 + 9 + 9), height: NoteTheme.toolbarButtonSize.height)
    }

    override func updateTrackingAreas() {
        if let hoverTracking { removeTrackingArea(hoverTracking) }
        let tracking = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(tracking)
        hoverTracking = tracking
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) { hoverChanged(true) }
    override func mouseExited(with event: NSEvent) { hoverChanged(false) }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); pointerInside = false; needsDisplay = true }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
    override var state: NSControl.StateValue { didSet { needsDisplay = true } }

    private func hoverChanged(_ inside: Bool) {
        guard inside != pointerInside else { return }
        pointerInside = inside
        needsDisplay = true
        EaselControlSurface.crossfade(self, duration: NoteAnimation.hoverDuration, pops: nil)
    }

    override func highlight(_ flag: Bool) {
        let released = !flag && isHighlighted
        super.highlight(flag)
        needsDisplay = true
        EaselControlSurface.apply(self, hovered: false, pressed: flag, released: released, casts: false)
    }

    override func draw(_ dirtyRect: NSRect) {
        let radius = NoteTheme.controlRadius
        let fill: NSColor? = !isEnabled ? nil : state != .off ? NoteTheme.checkedFill
            : isHighlighted ? NoteTheme.pressedFill : pointerInside ? NoteTheme.hoverFill : nil
        if let fill {
            fill.setFill()
            NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()
        }
        let ink = (state != .off ? NoteTheme.checkedInk : isHighlighted || pointerInside ? NoteTheme.menuInk : NoteTheme.menuSecondaryInk)
            .withAlphaComponent(isEnabled ? 1 : NoteTheme.disabledOpacity)
        var attributes = titleAttributes
        attributes[.foregroundColor] = ink
        let height = (pageName as NSString).size(withAttributes: attributes).height
        let chevronBox = NSRect(x: bounds.maxX - 9 - 9, y: 0, width: 9, height: bounds.height)
        (pageName as NSString).draw(with: NSRect(x: 10, y: ((bounds.height - height) / 2).rounded(), width: max(0, chevronBox.minX - 16),
                                                 height: height),
                                    options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: attributes)
        if let chevron = NoteIconRenderer.symbol("chevron.down", pointSize: 9.5, weight: .bold) {
            NoteIconRenderer.drawTemplate(chevron, centeredIn: chevronBox, tint: ink)
        }
    }

    override func drawFocusRingMask() {
        NSBezierPath(roundedRect: bounds, xRadius: NoteTheme.controlRadius, yRadius: NoteTheme.controlRadius).fill()
    }
    override var focusRingMaskBounds: NSRect { bounds }
}

@MainActor
final class EaselPageSwitcher {
    struct Row: Equatable {
        var id: UUID?
        var name: String
        var isDivider: Bool
        var isCurrent: Bool
        var objectCount: Int
    }

    struct Actions {
        var select: (UUID?) -> Void = { _ in }
        var add: () -> Void = {}
        var addDivider: () -> Void = {}
        var rename: (UUID?, String) -> Bool = { _, _ in false }
        var move: (UUID?, Int) -> Void = { _, _ in }
        var duplicate: (UUID?) -> Void = { _ in }
        var delete: (UUID?) -> Void = { _ in }
        var copyLink: (UUID?) -> Void = { _ in }
    }

    static func rows(for document: EaselDocument, current: UUID?) -> [Row] {
        guard let pages = document.pages else {
            return [Row(id: nil, name: EaselPages.firstPageName, isDivider: false, isCurrent: true, objectCount: document.items.count)]
        }
        let shown = EaselPages.resolvedPage(current, in: document)
        return pages.map { page in
            Row(id: page.id, name: page.name, isDivider: EaselPages.isDivider(page, in: document), isCurrent: page.id == shown,
                objectCount: EaselPages.itemCount(on: page.id, in: document))
        }
    }

    var actions = Actions()
    var onClose: (() -> Void)?
    private var popover: NotePagePopover?
    private weak var list: EaselPageListView?

    var isOpen: Bool { popover?.isOpen == true }

    func toggle(from button: NSButton, in host: NSView, rows: [Row]) {
        if isOpen { close(); return }
        present(from: button, in: host, rows: rows, origin: NSApp.currentEvent?.type == .keyDown ? .keyboard : .pointer)
    }

    func present(from button: NSButton, in host: NSView, rows: [Row], origin: NoteMenuList.Origin) {
        close(animated: false)
        let view = EaselPageListView(rows: rows, switcher: self)
        let popover = NotePagePopover(content: view)
        popover.exempt(button)
        popover.onKeyDown = { [weak view] event in view?.handleKeyDown(event) ?? false }
        popover.onClose = { [weak self, weak button] in
            self?.popover = nil
            self?.list = nil
            button?.state = .off
            self?.onClose?()
        }
        self.popover = popover
        list = view
        button.state = .on
        popover.present(in: host, anchor: host.convert(button.bounds, from: button), edge: .below, alignment: .leading)
        view.prepare(keyboard: origin == .keyboard)
    }

    func update(rows: [Row]) { list?.update(rows: rows) }

    func close(animated: Bool = true) { popover?.close(animated: animated) }

    fileprivate var popoverForChildren: NotePagePopover? { popover }
}

@MainActor
final class EaselPageListView: NSView, NoteFloatingPanelContent, NSTextFieldDelegate {
    enum Entry: Equatable {
        case page(EaselPageSwitcher.Row)
        case add
        case addDivider

        var row: EaselPageSwitcher.Row? {
            if case .page(let row) = self { return row }
            return nil
        }
    }

    enum RowKey: Hashable {
        case page(UUID?)
        case add
        case addDivider
    }

    static let width: CGFloat = 264
    static let dividerHeight: CGFloat = 18
    static let maximumListHeight: CGFloat = 420

    var preferredSizeDidChange: (() -> Void)?
    private weak var switcher: EaselPageSwitcher?
    private(set) var rows: [EaselPageSwitcher.Row]
    private var entries: [Entry] = []
    private var frames: [NSRect] = []
    private var highlighted: Int?
    private var highlightFromPointer = false
    private var pressed: Int?
    private var pressPoint: NSPoint?
    private var dragging: Int?
    private var dropIndex: Int?
    private var renaming: Int?
    private let field = NSTextField()
    private let plate = NSView()
    private let marker = EaselPageMarkerView()
    private var rowViews: [RowKey: EaselPageRowView] = [:]
    private let scroll = NSScrollView()
    private let document = EaselPageListDocumentView()
    private var rowMenu: NotePagePopover?
    private var tracking: NSTrackingArea?
    private var accessibilityRows: [EaselPageAccessibilityRow] = []

    init(rows: [EaselPageSwitcher.Row], switcher: EaselPageSwitcher) {
        self.rows = rows
        self.switcher = switcher
        super.init(frame: NSRect(x: 0, y: 0, width: Self.width, height: 120))
        wantsLayer = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.horizontalScrollElasticity = .none
        scroll.contentView.drawsBackground = false
        scroll.automaticallyAdjustsContentInsets = false
        document.list = self
        document.wantsLayer = true
        plate.wantsLayer = true
        plate.layer?.cornerRadius = NoteTheme.menuHighlightRadius
        plate.layer?.cornerCurve = .continuous
        plate.layer?.opacity = 0
        document.addSubview(plate)
        scroll.documentView = document
        addSubview(scroll)
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = NoteTheme.menuTitleFont()
        field.textColor = NoteTheme.menuInk
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        field.cell?.lineBreakMode = .byClipping
        field.delegate = self
        field.isHidden = true
        field.setAccessibilityLabel("Page name")
        document.addSubview(field)
        marker.isHidden = true
        document.addSubview(marker)
        setAccessibilityElement(true)
        setAccessibilityRole(.list)
        setAccessibilityLabel("Pages")
        rebuild()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
    override var fittingSize: NSSize { NSSize(width: Self.width, height: min(contentHeight, Self.maximumListHeight)) }
    override var intrinsicContentSize: NSSize { fittingSize }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private var contentHeight: CGFloat { (frames.last?.maxY ?? 0) + NoteTheme.menuInset }
    private var canReorder: Bool { rows.count > 1 && rows.allSatisfy { $0.id != nil } }

    fileprivate var placed: [(entry: Entry, frame: NSRect, index: Int)] {
        entries.indices.compactMap { frames.indices.contains($0) ? (entries[$0], frames[$0], $0) : nil }
    }
    fileprivate var highlightIndex: Int? { highlighted }
    fileprivate var renamingIndex: Int? { renaming }
    fileprivate var dropLineY: CGFloat? {
        guard dragging != nil, let dropIndex else { return nil }
        let pageFrames = entries.indices.filter { entries[$0].row != nil && frames.indices.contains($0) }.map { frames[$0] }
        guard !pageFrames.isEmpty else { return nil }
        return dropIndex < pageFrames.count ? pageFrames[dropIndex].minY : pageFrames[pageFrames.count - 1].maxY
    }

    func prepare(keyboard: Bool) {
        let current = entries.firstIndex { $0.row?.isCurrent == true }
        highlightFromPointer = false
        setHighlight(keyboard ? current ?? firstEnabled() : nil, animated: false)
        if let current { reveal(current) }
    }

    func update(rows newRows: [EaselPageSwitcher.Row]) {
        guard newRows != rows else { return }
        let keep = highlighted.flatMap { entries.indices.contains($0) ? entries[$0] : nil }
        let keepID = keep?.row?.id
        rows = newRows
        if let renaming, entries.indices.contains(renaming), let id = entries[renaming].row?.id,
           !newRows.contains(where: { $0.id == id }) { endRename(commit: false) }
        rebuild()
        if let keep {
            let index = entries.firstIndex { entry in
                if let keepID { return entry.row?.id == keepID }
                return entry == keep
            }
            setHighlight(index, animated: false)
        }
    }

    private func rebuild() {
        entries = rows.map { .page($0) } + [.add, .addDivider]
        var y = NoteTheme.menuInset
        let width = Self.width - NoteTheme.menuInset * 2
        frames = entries.enumerated().map { offset, entry in
            if case .add = entry { y += NoteTheme.menuSeparatorSlot }
            let height = entry.row?.isDivider == true ? Self.dividerHeight : NoteTheme.menuRowHeight
            defer { y += height }
            return NSRect(x: NoteTheme.menuInset, y: y, width: width, height: height)
        }
        document.frame = NSRect(x: 0, y: 0, width: Self.width, height: contentHeight)
        needsLayout = true
        let animated = window != nil && !rowViews.isEmpty
        reconcileRows(animated: animated)
        placeMarker(animated: animated)
        redrawRows()
        window?.invalidateCursorRects(for: document)
        rebuildAccessibility()
        preferredSizeDidChange?()
    }

    private func key(of entry: Entry) -> RowKey {
        switch entry {
        case .page(let row): return .page(row.id)
        case .add: return .add
        case .addDivider: return .addDivider
        }
    }

    private func rowViewFrame(_ index: Int) -> NSRect {
        let frame = frames[index]
        let extra = EaselPageRowView.topExtra(for: entries[index])
        return NSRect(x: 0, y: frame.minY - extra, width: Self.width, height: frame.height + extra)
    }

    private func reconcileRows(animated: Bool) {
        var seen = Set<RowKey>()
        for index in entries.indices where frames.indices.contains(index) {
            let entry = entries[index]
            let rowKey = key(of: entry)
            seen.insert(rowKey)
            let target = rowViewFrame(index)
            if let view = rowViews[rowKey] {
                let becameCurrent = view.entry.row?.isCurrent != entry.row?.isCurrent
                view.configure(entry: entry, index: index, itemFrame: frames[index])
                if becameCurrent, animated { EaselControlSurface.crossfade(view, duration: NoteAnimation.hoverDuration, pops: nil) }
                if view.frame != target {
                    if animated { NoteAnimation.slide(view, to: target, spring: .reorder) } else { view.frame = target }
                }
            } else {
                let view = EaselPageRowView(list: self, entry: entry, index: index, itemFrame: frames[index])
                view.frame = target
                document.addSubview(view, positioned: .below, relativeTo: field)
                rowViews[rowKey] = view
                if animated { NoteAnimation.insert(view) }
            }
        }
        for (rowKey, view) in rowViews where !seen.contains(rowKey) {
            rowViews[rowKey] = nil
            if animated {
                NoteAnimation.remove(view) { [weak view] in view?.removeFromSuperview() }
            } else {
                view.removeFromSuperview()
            }
        }
    }

    private func placeMarker(animated: Bool) {
        guard let index = entries.firstIndex(where: { $0.row?.isCurrent == true && $0.row?.isDivider == false }),
              frames.indices.contains(index) else {
            marker.isHidden = true
            return
        }
        let target = NSRect(x: frames[index].minX + 8, y: (frames[index].midY - 10).rounded(), width: 20, height: 20)
        if marker.isHidden {
            marker.isHidden = false
            marker.frame = target
            if animated { NoteAnimation.insert(marker) }
            return
        }
        guard marker.frame != target else { return }
        guard animated else {
            marker.frame = target
            return
        }
        NoteAnimation.slide(marker, to: target, spring: .pill)
        NoteAnimation.pop(marker, from: 0.7, spring: .pill)
    }

    fileprivate func redrawRows() {
        document.needsDisplay = true
        for view in rowViews.values { view.needsDisplay = true }
    }

    override func layout() {
        super.layout()
        scroll.frame = bounds
        document.frame = NSRect(x: 0, y: 0, width: bounds.width, height: max(contentHeight, bounds.height))
        if let highlighted, frames.indices.contains(highlighted) {
            NoteAnimation.withoutAnimation { plate.frame = frames[highlighted] }
        }
        if let renaming, frames.indices.contains(renaming) { field.frame = fieldFrame(for: frames[renaming]) }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshPlate()
        field.textColor = NoteTheme.menuInk
        redrawRows()
    }

    private func firstEnabled() -> Int? { entries.indices.first { isEnabled($0) } }

    private func isEnabled(_ index: Int) -> Bool {
        guard entries.indices.contains(index) else { return false }
        switch entries[index] {
        case .page: return true
        case .add, .addDivider: return rows.count < EaselPage.maximumCount
        }
    }

    fileprivate func entryIndex(at point: NSPoint) -> Int? {
        frames.indices.first { frames[$0].contains(point) }
    }

    fileprivate func moreButtonFrame(for index: Int) -> NSRect? {
        guard frames.indices.contains(index), entries[index].row != nil else { return nil }
        let frame = frames[index]
        return NSRect(x: frame.maxX - 30, y: frame.midY - 12, width: 24, height: 24)
    }

    fileprivate func showsMoreButton(_ index: Int) -> Bool { index == highlighted && renaming != index && dragging == nil }

    private func setHighlight(_ index: Int?, animated: Bool) {
        let target = index.flatMap { isEnabled($0) ? $0 : nil }
        guard target != highlighted else { return }
        let previous = highlighted
        highlighted = target
        refreshPlate()
        if let layer = plate.layer {
            let animate = animated && !NoteAnimation.reduceMotion
            if let target, frames.indices.contains(target) {
                if previous == nil || layer.opacity == 0 || !animate {
                    NoteAnimation.settle(layer, keys: [NoteAnimation.positionKey, NoteAnimation.boundsKey])
                    NoteAnimation.withoutAnimation { plate.frame = frames[target] }
                } else {
                    NoteAnimation.slide(plate, to: frames[target], spring: .highlight)
                }
                if animate {
                    NoteAnimation.spring(layer, "opacity", to: Float(1), spring: .highlight, key: NoteAnimation.fadeKey)
                } else {
                    NoteAnimation.settle(layer, keys: [NoteAnimation.fadeKey])
                    NoteAnimation.withoutAnimation { layer.opacity = 1 }
                }
            } else if animate {
                NoteAnimation.spring(layer, "opacity", to: Float(0), spring: .highlight, key: NoteAnimation.fadeKey)
            } else {
                NoteAnimation.settle(layer, keys: [NoteAnimation.fadeKey])
                NoteAnimation.withoutAnimation { layer.opacity = 0 }
            }
        }
        if let target, !highlightFromPointer { reveal(target) }
        redrawRows()
        updateAccessibilitySelection()
    }

    private func refreshPlate() {
        let color = pressed != nil && pressed == highlighted ? NoteTheme.menuPressed : NoteTheme.menuHighlight
        NoteAnimation.withoutAnimation { plate.layer?.backgroundColor = NoteTheme.resolved(color, in: self) }
    }

    private func reveal(_ index: Int) {
        guard frames.indices.contains(index) else { return }
        let clip = scroll.contentView
        var origin = clip.bounds.origin
        let height = clip.bounds.height
        guard height > 0 else { return }
        let padded = frames[index].insetBy(dx: 0, dy: -NoteTheme.menuInset)
        if padded.minY < origin.y { origin.y = max(0, padded.minY) }
        else if padded.maxY > origin.y + height { origin.y = min(contentHeight - height, padded.maxY - height) }
        guard origin != clip.bounds.origin else { return }
        clip.scroll(to: origin)
        scroll.reflectScrolledClipView(clip)
    }

    @discardableResult
    private func moveHighlight(by delta: Int) -> Bool {
        let enabled = entries.indices.filter(isEnabled)
        guard !enabled.isEmpty else { return false }
        let position = highlighted.flatMap { enabled.firstIndex(of: $0) } ?? (delta > 0 ? -1 : enabled.count)
        highlightFromPointer = false
        setHighlight(enabled[((position + delta) % enabled.count + enabled.count) % enabled.count], animated: true)
        return true
    }

    private func pageIndex(of entry: Int) -> Int? {
        guard entries.indices.contains(entry), entries[entry].row != nil else { return nil }
        return entries[..<entry].filter { $0.row != nil }.count
    }

    @discardableResult
    fileprivate func activate(_ index: Int) -> Bool {
        guard switcher != nil, isEnabled(index) else { return false }
        switch entries[index] {
        case .page(let row):
            guard !row.isDivider else { return presentRowMenu(for: index) }
            switcher?.actions.select(row.id)
            switcher?.close()
        case .add:
            switcher?.actions.add()
            focusOnCurrent(rename: true)
        case .addDivider:
            switcher?.actions.addDivider()
        }
        return true
    }

    private func focusOnCurrent(rename: Bool) {
        guard let index = entries.firstIndex(where: { $0.row?.isCurrent == true }) else { return }
        highlightFromPointer = false
        setHighlight(index, animated: false)
        if rename { beginRename(index) }
    }

    private func move(_ index: Int, by delta: Int) -> Bool {
        guard switcher != nil else { return false }
        guard canReorder, let position = pageIndex(of: index), let row = entries[index].row else { return false }
        let target = position + delta
        guard rows.indices.contains(target) else { return true }
        switcher?.actions.move(row.id, target)
        if let moved = entries.firstIndex(where: { $0.row?.id == row.id }) { setHighlight(moved, animated: true) }
        return true
    }

    private func duplicate(_ index: Int) -> Bool {
        guard switcher != nil else { return false }
        guard let row = entries[index].row, !row.isDivider, rows.count < EaselPage.maximumCount else { return false }
        switcher?.actions.duplicate(row.id)
        focusOnCurrent(rename: false)
        return true
    }

    private func delete(_ index: Int) -> Bool {
        guard switcher != nil else { return false }
        guard let row = entries[index].row, canDelete(row) else { return false }
        switcher?.actions.delete(row.id)
        return true
    }

    private func canDelete(_ row: EaselPageSwitcher.Row) -> Bool {
        guard rows.count > 1 else { return false }
        return row.isDivider || rows.contains { !$0.isDivider && $0.id != row.id }
    }

    func handleKeyDown(_ event: NSEvent) -> Bool {
        if renaming != nil {
            if event.keyCode == 53 { endRename(commit: false); return true }
            return false
        }
        if rowMenu?.isOpen == true { return false }
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        let entry = highlighted
        switch (event.keyCode, modifiers) {
        case (126, []): return moveHighlight(by: -1)
        case (125, []): return moveHighlight(by: 1)
        case (126, [.option]): return entry.map { move($0, by: -1) } ?? false
        case (125, [.option]): return entry.map { move($0, by: 1) } ?? false
        case (115, []): highlightFromPointer = false; setHighlight(firstEnabled(), animated: true); return true
        case (119, []): highlightFromPointer = false; setHighlight(entries.indices.last(where: isEnabled), animated: true); return true
        case (36, []), (76, []), (49, []): return entry.map(activate) ?? false
        case (36, [.shift]), (76, [.shift]):
            guard let entry, entries[entry].row?.isDivider == false else { return false }
            beginRename(entry)
            return true
        case (124, []): return entry.map(presentRowMenu) ?? false
        case (2, [.command]): return entry.map(duplicate) ?? false
        case (51, []), (117, []): return entry.map(delete) ?? false
        case (53, _):
            switcher?.close()
            return true
        default: return false
        }
    }

    private func fieldFrame(for frame: NSRect) -> NSRect {
        let height = ceil(NoteTheme.menuTitleFont().ascender - NoteTheme.menuTitleFont().descender) + 4
        return NSRect(x: frame.minX + 36, y: (frame.midY - height / 2).rounded(), width: frame.width - 36 - 10, height: height)
    }

    fileprivate func beginRename(_ index: Int) {
        guard switcher != nil else { return }
        guard entries.indices.contains(index), let row = entries[index].row, !row.isDivider else { return }
        rowMenu?.close(animated: false)
        renaming = index
        field.stringValue = row.name
        field.frame = fieldFrame(for: frames[index])
        field.isHidden = false
        window?.makeFirstResponder(field)
        field.currentEditor()?.selectAll(nil)
        redrawRows()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil, renaming != nil { endRename(commit: true) }
        super.viewWillMove(toWindow: newWindow)
    }

    private func endRename(commit: Bool) {
        guard let index = renaming else { return }
        renaming = nil
        let value = field.stringValue
        field.isHidden = true
        if window?.firstResponder === field.currentEditor() || window?.firstResponder === field { window?.makeFirstResponder(self) }
        if commit, entries.indices.contains(index), let row = entries[index].row, value != row.name {
            if switcher?.actions.rename(row.id, value) != true { NSSound.beep() }
        }
        redrawRows()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)), #selector(NSResponder.insertTab(_:)):
            endRename(commit: true)
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            endRename(commit: false)
            return true
        default:
            return false
        }
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        if renaming != nil { endRename(commit: true) }
    }

    func controlTextDidChange(_ obj: Notification) {
        if field.stringValue.count > EaselPage.maximumNameLength {
            field.stringValue = String(field.stringValue.prefix(EaselPage.maximumNameLength))
        }
    }

    fileprivate func rowMenuItems(for row: EaselPageSwitcher.Row) -> [NoteMenuList.Item] {
        let position = rows.firstIndex { $0.id == row.id } ?? 0
        var items: [NoteMenuList.Item] = []
        if !row.isDivider {
            items.append(.init(id: "rename", title: "Rename", icon: .symbol("pencil"), shortcut: "⇧↩"))
            items.append(.init(id: "duplicate", title: "Duplicate", icon: .symbol("plus.square.on.square"), shortcut: "⌘D",
                               isEnabled: rows.count < EaselPage.maximumCount))
            items.append(.init(id: "link", title: "Copy Link to Page", icon: .symbol("link")))
        }
        var up = NoteMenuList.Item(id: "up", title: "Move Up", icon: .symbol("arrow.up"), shortcut: "⌥↑",
                                   isEnabled: canReorder && position > 0)
        up.separatorBefore = !items.isEmpty
        items.append(up)
        items.append(.init(id: "down", title: "Move Down", icon: .symbol("arrow.down"), shortcut: "⌥↓",
                           isEnabled: canReorder && position < rows.count - 1))
        var delete = NoteMenuList.Item(id: "delete", title: row.isDivider ? "Delete Divider" : row.objectCount > 0 ? "Delete Page…" : "Delete Page",
                                       icon: .symbol("trash"), shortcut: "⌫", isEnabled: canDelete(row), isDestructive: true)
        delete.separatorBefore = true
        items.append(delete)
        return items
    }

    @discardableResult
    fileprivate func presentRowMenu(for index: Int) -> Bool {
        guard frames.indices.contains(index), let row = entries[index].row, let parent = switcher?.popoverForChildren, parent.isOpen else {
            return false
        }
        rowMenu?.close(animated: false)
        let list = NoteMenuList(items: rowMenuItems(for: row))
        list.minimumWidth = 200
        let child = NotePagePopover(content: list, parent: parent)
        list.onActivate = { [weak self, weak child] item in
            guard let self else { return }
            child?.close(animated: false)
            guard let current = self.entries.firstIndex(where: { $0.row?.id == row.id }) else { return }
            switch item.id {
            case "rename": self.beginRename(current)
            case "duplicate": _ = self.duplicate(current)
            case "link": self.switcher?.actions.copyLink(row.id); self.switcher?.close()
            case "up": _ = self.move(current, by: -1)
            case "down": _ = self.move(current, by: 1)
            case "delete": _ = self.delete(current)
            default: break
            }
        }
        list.onCancel = { [weak child] in child?.close() }
        list.onCollapse = { [weak child] in child?.close() }
        child.onKeyDown = { [weak list] event in list?.handleKeyDown(event) ?? false }
        child.onClose = { [weak self] in self?.rowMenu = nil }
        rowMenu = child
        let host = parent.panel
        let rowFrame = host.convert(frames[index], from: document)
        child.present(in: host.superview ?? host, anchor: (host.superview ?? host).convert(rowFrame, from: host), edge: .trailing)
        if NSApp.currentEvent?.type == .keyDown { list.prepare(origin: .keyboard); list.moveHighlight(by: 1) }
        return true
    }

    fileprivate func pointerMoved(to point: NSPoint) {
        guard dragging == nil, renaming == nil || entryIndex(at: point) != renaming else { return }
        guard let index = entryIndex(at: point), isEnabled(index) else { return }
        highlightFromPointer = true
        setHighlight(index, animated: true)
    }

    fileprivate func pointerExited() {
        guard highlightFromPointer, pressed == nil, rowMenu?.isOpen != true else { return }
        setHighlight(nil, animated: true)
    }

    fileprivate func pointerDown(at point: NSPoint, clickCount: Int) {
        if renaming != nil, entryIndex(at: point) != renaming { endRename(commit: true) }
        guard let index = entryIndex(at: point), isEnabled(index) else { pressed = nil; return }
        if let more = moreButtonFrame(for: index), more.contains(point), showsMoreButton(index) {
            presentRowMenu(for: index)
            return
        }
        if clickCount == 2, entries[index].row?.isDivider == false {
            pressed = nil
            beginRename(index)
            return
        }
        pressed = index
        pressPoint = point
        highlightFromPointer = true
        setHighlight(index, animated: true)
        refreshPlate()
    }

    fileprivate func pointerDragged(to point: NSPoint) {
        guard let pressed, let start = pressPoint else { return }
        if dragging == nil {
            guard canReorder, entries[pressed].row != nil, hypot(point.x - start.x, point.y - start.y) > 4 else { return }
            dragging = pressed
            NSCursor.closedHand.set()
        }
        let pageFrames = entries.indices.filter { entries[$0].row != nil }.map { frames[$0] }
        dropIndex = pageFrames.firstIndex { point.y < $0.midY } ?? pageFrames.count
        document.autoscroll(with: NSApp.currentEvent ?? NSEvent())
        redrawRows()
    }

    fileprivate func pointerUp(at point: NSPoint) {
        defer {
            pressed = nil
            pressPoint = nil
            dragging = nil
            dropIndex = nil
            refreshPlate()
            redrawRows()
            window?.invalidateCursorRects(for: document)
        }
        if let source = dragging, let dropIndex, let from = pageIndex(of: source), let row = entries[source].row {
            let target = dropIndex > from ? dropIndex - 1 : dropIndex
            if target != from { switcher?.actions.move(row.id, target) }
            return
        }
        guard let pressed, entryIndex(at: point) == pressed else { return }
        activate(pressed)
    }

    fileprivate func rightClick(at point: NSPoint) {
        guard let index = entryIndex(at: point), entries[index].row != nil else { return }
        highlightFromPointer = true
        setHighlight(index, animated: true)
        presentRowMenu(for: index)
    }

    private func rebuildAccessibility() {
        accessibilityRows = entries.indices.map { index in
            let element = EaselPageAccessibilityRow()
            element.list = self
            element.index = index
            element.setAccessibilityParent(self)
            switch entries[index] {
            case .page(let row):
                if row.isDivider {
                    element.setAccessibilityRole(.button)
                    element.setAccessibilityLabel("Divider")
                } else {
                    element.setAccessibilityRole(.button)
                    element.setAccessibilityLabel(row.name)
                    let count = "\(row.objectCount) object\(row.objectCount == 1 ? "" : "s")"
                    element.setAccessibilityValue(row.isCurrent ? "Current page, \(count)" : count)
                }
                element.setAccessibilityCustomActions(customActions(for: index, row: row))
            case .add:
                element.setAccessibilityRole(.button)
                element.setAccessibilityLabel("New Page")
                element.setAccessibilityEnabled(isEnabled(index))
            case .addDivider:
                element.setAccessibilityRole(.button)
                element.setAccessibilityLabel("New Divider")
                element.setAccessibilityEnabled(isEnabled(index))
            }
            return element
        }
        setAccessibilityChildren(accessibilityRows)
        updateAccessibilitySelection()
    }

    private func customActions(for index: Int, row: EaselPageSwitcher.Row) -> [NSAccessibilityCustomAction] {
        rowMenuItems(for: row).filter(\.isEnabled).map { item in
            NSAccessibilityCustomAction(name: item.title.replacingOccurrences(of: "…", with: "")) { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, let current = self.entries.firstIndex(where: { $0.row?.id == row.id }) else { return false }
                    switch item.id {
                    case "rename": self.beginRename(current); return true
                    case "duplicate": return self.duplicate(current)
                    case "link": self.switcher?.actions.copyLink(row.id); return true
                    case "up": return self.move(current, by: -1)
                    case "down": return self.move(current, by: 1)
                    case "delete": return self.delete(current)
                    default: return false
                    }
                }
            }
        }
    }

    private func updateAccessibilitySelection() {
        for row in accessibilityRows { row.setAccessibilitySelected(row.index == highlighted) }
        let selected = accessibilityRows.filter { $0.index == highlighted }
        setAccessibilitySelectedChildren(selected)
        if !selected.isEmpty { NSAccessibility.post(element: self, notification: .selectedChildrenChanged) }
    }

    fileprivate func accessibilityFrame(for index: Int) -> NSRect {
        guard frames.indices.contains(index), let window = document.window else { return .zero }
        return window.convertToScreen(document.convert(frames[index], to: nil))
    }

    fileprivate func enabled(_ index: Int) -> Bool { isEnabled(index) }
    fileprivate var draggedIndex: Int? { dragging }
}

@MainActor
private final class EaselPageAccessibilityRow: NSAccessibilityElement {
    weak var list: EaselPageListView?
    var index = 0

    override func accessibilityFrame() -> NSRect {
        MainActor.assumeIsolated { list?.accessibilityFrame(for: index) ?? .zero }
    }

    override func accessibilityPerformPress() -> Bool {
        MainActor.assumeIsolated { list?.activate(index) ?? false }
    }
}

@MainActor
private final class EaselPageListDocumentView: NSView {
    weak var list: EaselPageListView?
    private var tracking: NSTrackingArea?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(area)
        tracking = area
    }

    private func local(_ event: NSEvent) -> NSPoint { convert(event.locationInWindow, from: nil) }
    override func mouseMoved(with event: NSEvent) { list?.pointerMoved(to: local(event)) }
    override func mouseEntered(with event: NSEvent) { list?.pointerMoved(to: local(event)) }
    override func mouseExited(with event: NSEvent) { list?.pointerExited() }
    override func mouseDown(with event: NSEvent) { list?.pointerDown(at: local(event), clickCount: event.clickCount) }
    override func mouseDragged(with event: NSEvent) { list?.pointerDragged(to: local(event)) }
    override func mouseUp(with event: NSEvent) { list?.pointerUp(at: local(event)) }
    override func rightMouseDown(with event: NSEvent) { list?.rightClick(at: local(event)) }

    override func resetCursorRects() {
        guard let list else { return }
        for placed in list.placed where list.enabled(placed.index) { addCursorRect(placed.frame, cursor: .pointingHand) }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let list, let y = list.dropLineY else { return }
        NoteTheme.checkedInk.setFill()
        NSBezierPath(roundedRect: NSRect(x: NoteTheme.menuInset + 4, y: y - 1, width: bounds.width - NoteTheme.menuInset * 2 - 8, height: 2),
                     xRadius: 1, yRadius: 1).fill()
    }
}

@MainActor
private final class EaselPageMarkerView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }

    override func draw(_ dirtyRect: NSRect) {
        guard let check = NoteIconRenderer.symbol("checkmark", pointSize: 11.5, weight: .bold) else { return }
        NoteIconRenderer.drawTemplate(check, centeredIn: bounds, tint: NoteTheme.checkedInk)
    }
}

@MainActor
private final class EaselPageRowView: NSView {
    private(set) var entry: EaselPageListView.Entry
    private(set) var index: Int
    private var itemFrame: NSRect
    private weak var list: EaselPageListView?

    static func topExtra(for entry: EaselPageListView.Entry) -> CGFloat {
        if case .add = entry { return NoteTheme.menuSeparatorSlot }
        return 0
    }

    init(list: EaselPageListView, entry: EaselPageListView.Entry, index: Int, itemFrame: NSRect) {
        self.list = list
        self.entry = entry
        self.index = index
        self.itemFrame = itemFrame
        super.init(frame: .zero)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }

    func configure(entry: EaselPageListView.Entry, index: Int, itemFrame: NSRect) {
        self.entry = entry
        self.index = index
        self.itemFrame = itemFrame
        needsDisplay = true
    }

    private var local: NSRect {
        NSRect(x: itemFrame.minX, y: Self.topExtra(for: entry), width: itemFrame.width, height: itemFrame.height)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let list else { return }
        let frame = local
        NSGraphicsContext.saveGraphicsState()
        if !list.enabled(index) { NSGraphicsContext.current?.cgContext.setAlpha(NoteTheme.disabledRowOpacity) }
        if index == list.draggedIndex { NSGraphicsContext.current?.cgContext.setAlpha(0.4) }
        switch entry {
        case .page(let row) where row.isDivider: drawSeparator(at: frame.midY, frame: frame)
        case .page(let row): drawPage(row, in: frame, list: list)
        case .add:
            drawSeparator(at: frame.minY - NoteTheme.menuSeparatorSlot / 2, frame: frame)
            drawAction("New Page", symbol: "plus", in: frame)
        case .addDivider: drawAction("New Divider", symbol: "minus", in: frame)
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    private func titleAttributes(_ ink: NSColor) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        return [.font: NoteTheme.menuTitleFont(), .foregroundColor: ink, .paragraphStyle: paragraph]
    }

    private func drawPage(_ row: EaselPageSwitcher.Row, in frame: NSRect, list: EaselPageListView) {
        let box = NSRect(x: frame.minX + 8, y: (frame.midY - 10).rounded(), width: 20, height: 20)
        if !row.isCurrent {
            NoteIconRenderer.draw(.symbol("doc"), in: box, tint: NoteTheme.menuSecondaryInk, pointSize: 13,
                                  weight: NoteIconRenderer.symbolWeight(for: NoteTheme.menuTitleFont()))
        }
        var right = frame.maxX - 10
        if list.showsMoreButton(index), let documentMore = list.moreButtonFrame(for: index) {
            let more = documentMore.offsetBy(dx: -self.frame.minX, dy: -self.frame.minY)
            NoteTheme.hoverFill.setFill()
            NSBezierPath(roundedRect: more, xRadius: NoteTheme.controlRadius, yRadius: NoteTheme.controlRadius).fill()
            if let glyph = NoteIconRenderer.symbol("ellipsis", pointSize: 11, weight: .bold) {
                NoteIconRenderer.drawTemplate(glyph, centeredIn: more, tint: NoteTheme.menuSecondaryInk)
            }
            right = more.minX - 6
        } else if row.objectCount > 0 {
            let count = NSAttributedString(string: "\(row.objectCount)", attributes: [.font: NoteTheme.menuSubtitleFont(),
                                                                                    .foregroundColor: NoteTheme.menuTertiaryInk])
            let size = count.size()
            count.draw(at: NSPoint(x: right - ceil(size.width), y: (frame.midY - size.height / 2).rounded()))
            right -= ceil(size.width) + 8
        }
        guard list.renamingIndex != index else { return }
        let font = NoteTheme.menuTitleFont()
        let height = ceil(font.ascender - font.descender)
        (row.name as NSString).draw(with: NSRect(x: box.maxX + 8, y: (frame.midY - height / 2).rounded(), width: max(0, right - box.maxX - 8),
                                                 height: height),
                                    options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                                    attributes: titleAttributes(row.isCurrent ? NoteTheme.checkedInk : NoteTheme.menuInk))
    }

    private func drawSeparator(at y: CGFloat, frame: NSRect) {
        NoteTheme.menuSeparator.setFill()
        let scale = window?.backingScaleFactor ?? 2
        let thickness = 1 / scale * (scale >= 2 ? 2 : 1)
        NSRect(x: frame.minX + 4, y: y - thickness / 2, width: frame.width - 8, height: thickness).fill()
    }

    private func drawAction(_ title: String, symbol: String, in frame: NSRect) {
        let box = NSRect(x: frame.minX + 8, y: (frame.midY - 10).rounded(), width: 20, height: 20)
        NoteIconRenderer.draw(.symbol(symbol), in: box, tint: NoteTheme.menuSecondaryInk, pointSize: 13,
                              weight: NoteIconRenderer.symbolWeight(for: NoteTheme.menuTitleFont()))
        let font = NoteTheme.menuTitleFont()
        let height = ceil(font.ascender - font.descender)
        (title as NSString).draw(with: NSRect(x: box.maxX + 8, y: (frame.midY - height / 2).rounded(), width: frame.width - box.maxX - 18,
                                              height: height),
                                 options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: titleAttributes(NoteTheme.menuInk))
    }
}

@MainActor
extension EaselEditorViewController {
    func configurePageSwitcher(in chrome: NSStackView, height: CGFloat) {
        pageButton.target = self
        pageButton.action = #selector(showPageSwitcher(_:))
        pageButton.toolTip = "Pages · Page Up and Page Down switch pages"
        pageButton.heightAnchor.constraint(equalToConstant: height).isActive = true
        chrome.addArrangedSubview(pageButton)
        canvas.installPageFollowing()
        canvas.pageState.onPageChange = { [weak self] in self?.refreshPages() }
        var actions = EaselPageSwitcher.Actions()
        actions.select = { [weak self] page in self?.canvas.showPage(page) }
        actions.add = { [weak self] in self?.canvas.addPage() }
        actions.addDivider = { [weak self] in self?.canvas.addPageDivider() }
        actions.rename = { [weak self] page, name in self?.canvas.renamePage(page, to: name) ?? false }
        actions.move = { [weak self] page, index in self?.canvas.movePage(page, to: index) }
        actions.duplicate = { [weak self] page in self?.canvas.duplicatePage(page) }
        actions.delete = { [weak self] page in self?.canvas.deletePage(page) }
        actions.copyLink = { [weak self] page in self?.canvas.copyLink(toPage: page) }
        canvas.pageState.onCopyPageLink = { [weak self] page in self?.copyPageLink(page) }
        pageSwitcher.actions = actions
        pageSwitcher.onClose = { [weak self] in
            guard let self, let window = self.view.window, window.firstResponder == nil || window.firstResponder === window else { return }
            window.makeFirstResponder(self.canvas)
        }
        refreshPages()
    }

    func refreshPages() {
        guard isViewLoaded else { return }
        pageButton.pageName = canvas.currentPageName
        if pageButton.intrinsicContentSize.width != pageButton.frame.width { view.needsLayout = true }
        pageSwitcher.update(rows: canvas.pageRows)
        find.pageChanged()
    }

    @objc func showPageSwitcher(_ sender: NSButton) {
        guard !session.isClosed, view.window?.attachedSheet == nil else { return }
        pageSwitcher.toggle(from: sender, in: view, rows: canvas.pageRows)
    }

    func copyPageLink(_ page: UUID?) {
        let id = session.document.id
        let string = page.map { EaselPageAddress.urlString(easel: id, page: $0) } ?? InternalPage.easel(id).urlString
        guard !session.isClosed, let url = URL(string: string) else { NSSound.beep(); return }
        let board = NSPasteboard.general
        board.clearContents()
        board.writeObjects([url as NSURL])
        board.setString(url.absoluteString, forType: .string)
        (view.window?.windowController as? BrowserWindowController)?.showToast(.copiedLinks([url]))
    }
}

@MainActor
extension EaselCanvasView {
    var pageRows: [EaselPageSwitcher.Row] { EaselPageSwitcher.rows(for: session.fullDocument, current: session.page) }
}

@MainActor
extension BrowserWindowController {
    func revealEaselPage(_ page: UUID, in easel: UUID, attempt: Int = 0) {
        if let editor = currentEaselEditor, editor.session.document.id == easel, editor.isViewLoaded, editor.view.window != nil {
            if editor.session.document.pages?.contains(where: { $0.id == page }) == true {
                editor.canvas.showPage(page)
            } else {
                editor.showExportToast(.standard("That page isn’t on this Easel anymore"))
            }
            return
        }
        guard attempt < 12 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            MainActor.assumeIsolated { self?.revealEaselPage(page, in: easel, attempt: attempt + 1) }
        }
    }
}
