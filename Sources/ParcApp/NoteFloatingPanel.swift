import AppKit

enum NoteIcon: Hashable {
    case symbol(String)
    case glyph(String)
    case emoji(String)
    case image(URL)
    case noteMark
    case easelMark

    static func feather(_ code: UInt32) -> NoteIcon {
        .glyph(Unicode.Scalar(code).map { String(Character($0)) } ?? "")
    }

    static let featherImage = feather(0xE981)
    static let featherLink = feather(0xE98A)
    static let featherSmile = feather(0xE9DE)
}

@MainActor
protocol NoteFloatingPanelContent: AnyObject {
    var preferredSizeDidChange: (() -> Void)? { get set }
}

@MainActor
private final class NoteFloatingPanelClip: NSView {
    override var isFlipped: Bool { true }
}

@MainActor
class NoteFloatingPanel: NSView {
    enum Edge { case below, above, trailing, leading }
    enum Alignment { case leading, center, trailing }

    static let didChangePresentationNotification = Notification.Name("Parc.NoteFloatingPanel.didChangePresentation")
    static let minimumVisibleHeight: CGFloat = 96

    let contentView: NSView
    var onDismiss: (() -> Void)?
    private(set) var isPresented = false
    private(set) var resolvedEdge: Edge = .below
    private(set) var preferredEdge: Edge = .below
    private(set) var anchor: NSRect = .zero
    var alignment: Alignment = .leading
    var gap: CGFloat = NoteTheme.menuGap
    var margin: CGFloat = NoteTheme.menuScreenMargin
    var maximumHeight: CGFloat?
    var sideAlignmentOffset: CGFloat = NoteTheme.menuInset
    var contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0) { didSet { needsLayout = true } }
    var cornerRadius: CGFloat = NoteTheme.menuRadius { didSet { refreshChrome() } }
    var fill: NSColor = NoteTheme.menuFill { didSet { refreshChrome() } }
    var hairline: NSColor = NoteTheme.menuHairline { didSet { refreshChrome() } }

    private let clip = NoteFloatingPanelClip()
    private var reduceMotionObserved = false

    init(content: NSView) {
        contentView = content
        let size = Self.naturalSize(of: content)
        super.init(frame: NSRect(origin: .zero, size: size))
        wantsLayer = true
        layer?.masksToBounds = false
        clip.wantsLayer = true
        clip.layer?.masksToBounds = true
        clip.layer?.cornerCurve = .continuous
        clip.frame = bounds
        addSubview(clip)
        clip.addSubview(content)
        content.frame = NSRect(origin: .zero, size: size)
        setAccessibilityElement(false)
        refreshChrome()
        (content as? NoteFloatingPanelContent)?.preferredSizeDidChange = { [weak self] in
            self?.contentSizeDidChange(animated: true)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    static func naturalSize(of content: NSView) -> NSSize {
        let fitting = content.fittingSize
        return fitting.width > 0 && fitting.height > 0 ? fitting : content.frame.size
    }

    var preferredSize: NSSize {
        let size = Self.naturalSize(of: contentView)
        return NSSize(width: ceil(size.width + contentInsets.left + contentInsets.right),
                      height: ceil(size.height + contentInsets.top + contentInsets.bottom))
    }

    var scaleOrigin: NSPoint {
        let local = convertAnchorToLocal()
        let inset = min(cornerRadius + 8, bounds.width / 2)
        let verticalInset = min(cornerRadius + 8, bounds.height / 2)
        switch resolvedEdge {
        case .below: return NSPoint(x: min(max(local.midX, inset), bounds.width - inset), y: 0)
        case .above: return NSPoint(x: min(max(local.midX, inset), bounds.width - inset), y: bounds.height)
        case .trailing: return NSPoint(x: 0, y: min(max(local.midY, verticalInset), bounds.height - verticalInset))
        case .leading: return NSPoint(x: bounds.width, y: min(max(local.midY, verticalInset), bounds.height - verticalInset))
        }
    }

    private func convertAnchorToLocal() -> NSRect {
        guard let host = superview else { return .zero }
        return convert(anchor, from: host)
    }

    func present(in host: NSView, anchor: NSRect, edge: Edge = .below, animated: Bool = true) {
        observeReduceMotionIfNeeded()
        let wasPresented = isPresented && superview === host
        if superview !== host {
            removeFromSuperview()
            host.addSubview(self)
        } else if let topmost = host.subviews.last, topmost !== self {
            host.addSubview(self, positioned: .above, relativeTo: nil)
        }
        isPresented = true
        NoteAnimation.cancelHUD(self)
        reposition(anchor: anchor, edge: edge, animated: false)
        if animated && !wasPresented {
            NoteAnimation.presentHUD(self, about: scaleOrigin)
        }
        NotificationCenter.default.post(name: Self.didChangePresentationNotification, object: self)
        window?.refreshCursorUnderPointer()
    }

    func reposition(anchor: NSRect, edge: Edge = .below, animated: Bool = true) {
        self.anchor = anchor
        preferredEdge = edge
        relayout(animated: animated)
    }

    func contentSizeDidChange(animated: Bool = true) {
        guard superview != nil else {
            setFrameSize(preferredSize)
            layoutChrome()
            return
        }
        relayout(animated: animated, keepingEdge: isPresented)
    }

    func dismiss(animated: Bool = true, completion: (() -> Void)? = nil) {
        guard isPresented else {
            if superview == nil { completion?() }
            return
        }
        isPresented = false
        let finish = { [weak self] in
            guard let self else { completion?(); return }
            guard !self.isPresented else { completion?(); return }
            NoteAnimation.settle(self)
            let window = self.window
            self.removeFromSuperview()
            window?.refreshCursorUnderPointer()
            NoteAnimation.withoutAnimation { self.layer?.opacity = 1 }
            NotificationCenter.default.post(name: Self.didChangePresentationNotification, object: self)
            self.onDismiss?()
            completion?()
        }
        guard animated, window != nil || superview?.layer != nil else { finish(); return }
        NoteAnimation.dismissHUD(self, about: scaleOrigin, completion: finish)
    }

    private func relayout(animated: Bool, keepingEdge: Bool = false) {
        guard let host = superview else { return }
        let size = preferredSize
        let clipped = host.visibleRect.intersection(host.bounds)
        let visible = Self.topDown(clipped.isEmpty ? host.bounds : clipped, in: host)
        let anchorTopDown = Self.topDown(anchor, in: host)
        let placement = Self.placement(anchor: anchorTopDown, size: size, preferred: keepingEdge ? resolvedEdge : preferredEdge,
                                       alignment: alignment,
                                       gap: gap, margin: margin, visible: visible,
                                       maximumHeight: maximumHeight, sideOffset: sideAlignmentOffset)
        resolvedEdge = placement.edge
        let target = Self.topDown(placement.frame, in: host).integral
        let moved = target != frame
        let glide = animated && isPresented && frame.size != .zero && !NoteAnimation.reduceMotion && target != frame
        if glide {
            NoteAnimation.slide(self, to: target, spring: .glide)
            NoteAnimation.slide(clip, to: NSRect(origin: .zero, size: target.size), spring: .glide)
            animateShadowPath(spring: .glide)
        } else {
            NoteAnimation.withoutAnimation { frame = target }
            if let layer { NoteAnimation.settle(layer, keys: [NoteAnimation.positionKey, NoteAnimation.boundsKey]) }
        }
        layoutChrome()
        if moved, isPresented { window?.refreshCursorUnderPointer() }
    }

    override func layout() {
        super.layout()
        layoutChrome()
    }

    private func layoutChrome() {
        NoteAnimation.withoutAnimation {
            clip.frame = bounds
            contentView.frame = NSRect(x: contentInsets.left, y: contentInsets.top,
                                       width: max(0, bounds.width - contentInsets.left - contentInsets.right),
                                       height: max(0, bounds.height - contentInsets.top - contentInsets.bottom))
            layer?.shadowPath = CGPath(roundedRect: bounds, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
        }
    }

    private func animateShadowPath(spring: NoteSpring) {
        guard let layer else { return }
        let from = layer.presentation()?.shadowPath ?? layer.shadowPath
        let to = CGPath(roundedRect: NSRect(origin: .zero, size: frame.size), cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
        NoteAnimation.withoutAnimation { layer.shadowPath = to }
        guard let from else { return }
        _ = NoteAnimation.run(NoteAnimation.spring("shadowPath", spring, from: from, to: to), on: layer, key: NoteAnimation.shadowPathKey)
    }

    static func topDown(_ rect: NSRect, in host: NSView) -> NSRect {
        guard !host.isFlipped else { return rect }
        return NSRect(x: rect.minX, y: host.bounds.height - rect.maxY, width: rect.width, height: rect.height)
    }

    static func placement(anchor: NSRect, size: NSSize, preferred: Edge, alignment: Alignment = .leading,
                          gap: CGFloat = NoteTheme.menuGap, margin: CGFloat = NoteTheme.menuScreenMargin,
                          visible: NSRect, maximumHeight: CGFloat? = nil,
                          sideOffset: CGFloat = NoteTheme.menuInset) -> (frame: NSRect, edge: Edge) {
        let bounds = visible.insetBy(dx: margin, dy: margin)
        var width = min(size.width, max(0, bounds.width))
        if width <= 0 { width = size.width }
        var height = min(size.height, maximumHeight ?? .greatestFiniteMagnitude)
        var edge = preferred
        var x: CGFloat
        var y: CGFloat
        switch preferred {
        case .below, .above:
            let below = bounds.maxY - (anchor.maxY + gap)
            let above = (anchor.minY - gap) - bounds.minY
            if preferred == .below, height > below, above > below { edge = .above }
            if preferred == .above, height > above, below > above { edge = .below }
            let room = edge == .below ? below : above
            height = max(min(height, room), min(height, minimumVisibleHeight))
            y = edge == .below ? anchor.maxY + gap : anchor.minY - gap - height
            switch alignment {
            case .leading: x = anchor.minX
            case .center: x = anchor.midX - width / 2
            case .trailing: x = anchor.maxX - width
            }
            x = min(max(x, bounds.minX), max(bounds.minX, bounds.maxX - width))
        case .trailing, .leading:
            let right = bounds.maxX - (anchor.maxX + gap)
            let left = (anchor.minX - gap) - bounds.minX
            if preferred == .trailing, width > right, left > right { edge = .leading }
            if preferred == .leading, width > left, right > left { edge = .trailing }
            x = edge == .trailing ? anchor.maxX + gap : anchor.minX - gap - width
            height = min(height, max(minimumVisibleHeight, bounds.height))
            y = anchor.minY - sideOffset
            y = min(max(y, bounds.minY), max(bounds.minY, bounds.maxY - height))
        }
        return (NSRect(x: x, y: y, width: width, height: height), edge)
    }

    private func refreshChrome() {
        guard let layer else { return }
        let dark = NoteTheme.isDark(effectiveAppearance)
        let scale = window?.backingScaleFactor ?? 2
        NoteAnimation.withoutAnimation {
            clip.layer?.cornerRadius = cornerRadius
            clip.layer?.backgroundColor = NoteTheme.resolved(fill, in: self)
            clip.layer?.borderColor = NoteTheme.resolved(hairline, in: self)
            clip.layer?.borderWidth = 1 / scale
            layer.shadowColor = NSColor.black.cgColor
            layer.shadowOpacity = dark ? 0.32 : 0.12
            layer.shadowRadius = 7
            layer.shadowOffset = CGSize(width: 0, height: isFlipped ? 2 : -2)
            layer.shadowPath = CGPath(roundedRect: bounds, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshChrome()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        refreshChrome()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        refreshChrome()
    }

    private func observeReduceMotionIfNeeded() {
        guard !reduceMotionObserved else { return }
        reduceMotionObserved = true
        NoteAnimation.observeReduceMotion(self) { [weak self] in
            guard let self else { return }
            NoteAnimation.settle(self)
            if !self.isPresented, self.superview != nil { self.removeFromSuperview() }
        }
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {}
    override func mouseDragged(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {}
    override func rightMouseDown(with event: NSEvent) {}
    override func otherMouseDown(with event: NSEvent) {}
    override func mouseMoved(with event: NSEvent) {}

    override func cursorUpdate(with event: NSEvent) {
        if !applyNoteCursor(.arrow, for: event) { super.cursorUpdate(with: event) }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas where area.owner === self { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.cursorUpdate, .activeInKeyWindow, .inVisibleRect], owner: self))
    }

    static func allowsHover(for view: NSView, at windowPoint: NSPoint) -> Bool {
        guard let content = view.window?.contentView else { return true }
        guard view.isTopmost(atWindowPoint: windowPoint) else { return false }
        guard let hit = content.hitTest(content.superview?.convert(windowPoint, from: nil) ?? windowPoint),
              let cover = sequence(first: hit, next: \.superview).first(where: { $0 is NoteFloatingPanel })
        else { return true }
        return view.isDescendant(of: cover)
    }
}

@MainActor
final class NoteMenuList: NSView, NoteFloatingPanelContent {
    struct Item: Hashable {
        var id: String
        var title: String
        var subtitle: String?
        var icon: NoteIcon?
        var shortcut: String?
        var section: String?
        var isChecked = false
        var isEnabled = true
        var isDestructive = false
        var hasSubmenu = false
        var keywords: [String] = []
        var separatorBefore = false
        var iconTint: NSColor?
        var iconFill: NSColor?
        var accessibilityLabel: String?
        var iconDecoration: NoteIconDecoration = []
    }

    enum Origin { case pointer, keyboard }
    enum RowStyle { case compact, detailed }

    fileprivate enum Row {
        case header(String)
        case separator
        case item(Int)
        case empty
    }

    fileprivate struct Placed {
        var row: Row
        var frame: NSRect
    }

    var items: [Item] = [] {
        didSet {
            rebuild(resetHighlight: true)
        }
    }
    var highlightedIndex: Int? {
        get { highlighted }
        set { setHighlight(newValue, animated: true, notify: false, reveal: true) }
    }
    var onActivate: ((Item) -> Void)?
    var onHighlight: ((Item?) -> Void)?
    var onCancel: (() -> Void)?
    var onCollapse: (() -> Void)?
    var preferredSizeDidChange: (() -> Void)?

    var origin: Origin = .pointer
    var rowStyle: RowStyle = .compact { didSet { rebuild(resetHighlight: false) } }
    var fixedWidth: CGFloat? { didSet { rebuild(resetHighlight: false) } }
    var minimumWidth: CGFloat = 220 { didSet { rebuild(resetHighlight: false) } }
    var maximumWidth: CGFloat = 360 { didSet { rebuild(resetHighlight: false) } }
    var maximumHeight: CGFloat = 384 { didSet { rebuild(resetHighlight: false) } }
    var noResultsTitle = "No matches. Try another word?" { didSet { documentView.needsDisplay = true } }
    var filtersOnTyping = false
    var takesKeyboardFocus = false
    var spaceFocus: NSColor? { didSet { refreshPlateColor() } }
    var filterText = "" {
        didSet {
            guard filterText != oldValue else { return }
            rebuild(resetHighlight: true)
        }
    }

    private var highlighted: Int?
    private var highlightFromPointer = false
    private var pressedIndex: Int?
    private var placed: [Placed] = []
    private var visibleIndices: [Int] = []
    private var contentSize = NSSize(width: 260, height: 8)
    private var lastPointer: NSPoint?
    private var accessibilityRows: [NoteMenuAccessibilityRow] = []
    private let scrollView = NSScrollView()
    fileprivate let documentView = NoteMenuDocumentView()
    private let plate = NSView()

    init(items: [Item] = []) {
        self.items = items
        super.init(frame: NSRect(x: 0, y: 0, width: 260, height: 8))
        wantsLayer = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.horizontalScrollElasticity = .none
        scrollView.contentView.drawsBackground = false
        scrollView.automaticallyAdjustsContentInsets = false
        documentView.list = self
        documentView.wantsLayer = true
        plate.wantsLayer = true
        plate.layer?.cornerRadius = NoteTheme.menuHighlightRadius
        plate.layer?.cornerCurve = .continuous
        plate.layer?.opacity = 0
        plate.setAccessibilityElement(false)
        let container = NoteMenuContainerView()
        container.addSubview(plate)
        container.addSubview(documentView)
        container.wantsLayer = true
        scrollView.documentView = container
        addSubview(scrollView)
        setAccessibilityElement(true)
        setAccessibilityRole(.menu)
        rebuild(resetHighlight: true)
        NoteAnimation.observeReduceMotion(self) { [weak self] in
            guard let self else { return }
            NoteAnimation.settle(self)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
    override var intrinsicContentSize: NSSize {
        NSSize(width: contentSize.width, height: min(contentSize.height, maximumHeight))
    }
    override var fittingSize: NSSize { intrinsicContentSize }
    override var acceptsFirstResponder: Bool { takesKeyboardFocus }

    var visibleItems: [Item] { visibleIndices.map { items[$0] } }
    var highlightedItem: Item? { highlighted.flatMap { items.indices.contains($0) ? items[$0] : nil } }
    var hasKeyboardHighlight: Bool { highlightedItem != nil && !highlightFromPointer }

    func prepare(origin: Origin) {
        self.origin = origin
        pressedIndex = nil
        highlightFromPointer = false
        setHighlight(origin == .keyboard ? firstEnabledVisible() : nil, animated: false, notify: false, reveal: true)
    }

    func setItems(_ newItems: [Item], keepingHighlight: Bool) {
        let keep = keepingHighlight ? highlightedItem?.id : nil
        items = newItems
        if let keep, let index = items.firstIndex(where: { $0.id == keep }), visibleIndices.contains(index) {
            setHighlight(index, animated: false, notify: false, reveal: true)
        }
    }

    func highlight(id: String, animated: Bool = true) {
        setHighlight(items.firstIndex { $0.id == id }, animated: animated, notify: false, reveal: true)
    }

    @discardableResult
    func moveHighlight(by delta: Int) -> Bool {
        let enabled = visibleIndices.filter { items[$0].isEnabled }
        guard !enabled.isEmpty else { return false }
        let position = highlighted.flatMap { enabled.firstIndex(of: $0) } ?? (delta > 0 ? -1 : enabled.count)
        let next = enabled[((position + delta) % enabled.count + enabled.count) % enabled.count]
        highlightFromPointer = false
        setHighlight(next, animated: true, notify: true, reveal: true)
        return true
    }

    func moveHighlightToEnd(_ last: Bool) {
        let enabled = visibleIndices.filter { items[$0].isEnabled }
        guard let target = last ? enabled.last : enabled.first else { return }
        highlightFromPointer = false
        setHighlight(target, animated: true, notify: true, reveal: true)
    }

    @discardableResult
    func activateHighlighted() -> Bool {
        guard let index = highlighted, items.indices.contains(index), items[index].isEnabled,
              visibleIndices.contains(index) else { return false }
        onActivate?(items[index])
        return true
    }

    @discardableResult
    func handleKeyDown(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .control, .option])
        switch event.keyCode {
        case 126: return modifiers.isEmpty ? moveHighlight(by: -1) : false
        case 125: return modifiers.isEmpty ? moveHighlight(by: 1) : false
        case 36, 76: return activateHighlighted()
        case 53:
            guard let onCancel else { return false }
            onCancel()
            return true
        case 124:
            guard let item = highlightedItem, item.hasSubmenu else { return false }
            return activateHighlighted()
        case 123:
            guard let onCollapse else { return false }
            onCollapse()
            return true
        case 115: moveHighlightToEnd(false); return true
        case 119: moveHighlightToEnd(true); return true
        case 116: return moveHighlight(by: -max(1, pageStep()))
        case 121: return moveHighlight(by: max(1, pageStep()))
        case 51:
            guard filtersOnTyping, !filterText.isEmpty else { return false }
            filterText.removeLast()
            return true
        default:
            guard filtersOnTyping, modifiers.isEmpty, let characters = event.characters, !characters.isEmpty,
                  characters.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) && $0.value < 0xF700 })
            else { return false }
            filterText += characters
            return true
        }
    }

    @discardableResult
    func handle(command selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.moveUp(_:)): return moveHighlight(by: -1)
        case #selector(NSResponder.moveDown(_:)): return moveHighlight(by: 1)
        case #selector(NSResponder.insertNewline(_:)), #selector(NSResponder.insertLineBreak(_:)),
             #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)):
            return activateHighlighted()
        case #selector(NSResponder.cancelOperation(_:)):
            guard let onCancel else { return false }
            onCancel()
            return true
        case #selector(NSResponder.moveRight(_:)):
            guard let item = highlightedItem, item.hasSubmenu else { return false }
            return activateHighlighted()
        case #selector(NSResponder.moveLeft(_:)):
            guard let onCollapse else { return false }
            onCollapse()
            return true
        case #selector(NSResponder.moveToBeginningOfDocument(_:)), #selector(NSResponder.scrollToBeginningOfDocument(_:)):
            moveHighlightToEnd(false)
            return true
        case #selector(NSResponder.moveToEndOfDocument(_:)), #selector(NSResponder.scrollToEndOfDocument(_:)):
            moveHighlightToEnd(true)
            return true
        case #selector(NSResponder.pageUp(_:)), #selector(NSResponder.scrollPageUp(_:)):
            return moveHighlight(by: -max(1, pageStep()))
        case #selector(NSResponder.pageDown(_:)), #selector(NSResponder.scrollPageDown(_:)):
            return moveHighlight(by: max(1, pageStep()))
        default:
            return false
        }
    }

    override func keyDown(with event: NSEvent) {
        if !handleKeyDown(event) { super.keyDown(with: event) }
    }

    static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespaces)
    }

    static func score(_ item: Item, query: String) -> Int? {
        let needle = normalized(query)
        guard !needle.isEmpty else { return 0 }
        let title = normalized(item.title)
        if title.hasPrefix(needle) { return 0 }
        let words = title.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        if words.contains(where: { $0.hasPrefix(needle) }) { return 1 }
        let compact = needle.replacingOccurrences(of: " ", with: "")
        if title.replacingOccurrences(of: " ", with: "").hasPrefix(compact) { return 1 }
        for keyword in item.keywords.map(normalized) {
            if keyword.hasPrefix(needle) { return 2 }
            if keyword.split(separator: " ").contains(where: { $0.hasPrefix(needle) }) { return 3 }
        }
        if title.contains(needle) { return 4 }
        if let subtitle = item.subtitle.map(normalized), subtitle.contains(needle) { return 5 }
        return nil
    }

    static func matches(_ item: Item, query: String) -> Bool { score(item, query: query) != nil }

    static func filter(_ items: [Item], query: String) -> [Item] {
        guard !normalized(query).isEmpty else { return items }
        var scored: [(offset: Int, score: Int, item: Item)] = []
        for (offset, item) in items.enumerated() {
            if let score = score(item, query: query) { scored.append((offset, score, item)) }
        }
        scored.sort { $0.score != $1.score ? $0.score < $1.score : $0.offset < $1.offset }
        return scored.map(\.item)
    }

    private func filteredIndices() -> [Int] {
        guard !Self.normalized(filterText).isEmpty else { return Array(items.indices) }
        var scored: [(index: Int, score: Int)] = []
        for index in items.indices {
            if let score = Self.score(items[index], query: filterText) { scored.append((index, score)) }
        }
        scored.sort { $0.score != $1.score ? $0.score < $1.score : $0.index < $1.index }
        return scored.map(\.index)
    }

    private func firstEnabledVisible() -> Int? {
        visibleIndices.first { items[$0].isEnabled }
    }

    private func pageStep() -> Int {
        Int((scrollView.contentView.bounds.height / rowHeight).rounded(.down)) - 1
    }

    var rowHeight: CGFloat { rowStyle == .detailed ? NoteTheme.menuDetailedRowHeight : NoteTheme.menuRowHeight }

    private var hasIcons: Bool { visibleIndices.contains { items[$0].icon != nil } }

    private func rebuild(resetHighlight: Bool) {
        let previousSize = intrinsicContentSize
        visibleIndices = filteredIndices()
        let filtering = !Self.normalized(filterText).isEmpty
        let inset = NoteTheme.menuInset
        var y = inset
        var rows: [Placed] = []
        var lastSection: String?
        for (position, index) in visibleIndices.enumerated() {
            let item = items[index]
            if !filtering {
                if let section = item.section, section != lastSection {
                    if position > 0 {
                        rows.append(Placed(row: .separator, frame: NSRect(x: 0, y: y, width: 0, height: NoteTheme.menuSeparatorSlot)))
                        y += NoteTheme.menuSeparatorSlot
                    }
                    rows.append(Placed(row: .header(section), frame: NSRect(x: 0, y: y, width: 0, height: NoteTheme.menuHeaderHeight)))
                    y += NoteTheme.menuHeaderHeight
                } else if item.separatorBefore, position > 0 {
                    rows.append(Placed(row: .separator, frame: NSRect(x: 0, y: y, width: 0, height: NoteTheme.menuSeparatorSlot)))
                    y += NoteTheme.menuSeparatorSlot
                }
                lastSection = item.section ?? lastSection
            }
            rows.append(Placed(row: .item(index), frame: NSRect(x: 0, y: y, width: 0, height: rowHeight)))
            y += rowHeight
        }
        if visibleIndices.isEmpty {
            rows.append(Placed(row: .empty, frame: NSRect(x: 0, y: y, width: 0, height: NoteTheme.menuRowHeight)))
            y += NoteTheme.menuRowHeight
        }
        y += inset
        let width = fixedWidth ?? min(maximumWidth, max(minimumWidth, naturalWidth(rows)))
        for index in rows.indices {
            rows[index].frame.origin.x = inset
            rows[index].frame.size.width = width - inset * 2
        }
        placed = rows
        contentSize = NSSize(width: ceil(width), height: ceil(y))
        if resetHighlight {
            highlightFromPointer = false
            pressedIndex = nil
            highlighted = nil
            let target = origin == .keyboard ? firstEnabledVisible() : nil
            setHighlight(target, animated: false, notify: false, reveal: true, force: true)
        } else if let current = highlighted, !visibleIndices.contains(current) {
            setHighlight(nil, animated: false, notify: false, reveal: false)
        }
        rebuildAccessibility()
        invalidateIntrinsicContentSize()
        needsLayout = true
        documentView.needsDisplay = true
        if intrinsicContentSize != previousSize { preferredSizeDidChange?() }
        documentView.refreshPointerCursor()
    }

    private func naturalWidth(_ rows: [Placed]) -> CGFloat {
        let titleFont = NoteTheme.menuTitleFont()
        let subtitleFont = NoteTheme.menuSubtitleFont()
        var widest: CGFloat = 0
        let iconColumn: CGFloat = hasIcons ? (rowStyle == .detailed ? 30 + 12 : 20 + 10) : 0
        for index in visibleIndices {
            let item = items[index]
            var width = 10 + iconColumn + ceil(NSAttributedString(string: item.title, attributes: [.font: titleFont]).size().width)
            if rowStyle == .compact, let subtitle = item.subtitle, !subtitle.isEmpty {
                width += 6 + min(140, ceil(NSAttributedString(string: subtitle, attributes: [.font: subtitleFont]).size().width))
            }
            width += accessoryWidth(for: item) + 12
            widest = max(widest, width)
        }
        for row in rows {
            if case .header(let title) = row.row {
                widest = max(widest, 20 + NSAttributedString(string: title, attributes: [.font: NoteTheme.menuHeaderFont()]).size().width)
            }
        }
        return ceil(widest + NoteTheme.menuInset * 2)
    }

    fileprivate func accessoryWidth(for item: Item) -> CGFloat {
        var width: CGFloat = 0
        if let shortcut = item.shortcut, !shortcut.isEmpty { width += NoteKeycapRenderer.size(for: shortcut).width + 10 }
        if item.isChecked { width += 14 + 6 }
        if item.hasSubmenu { width += 9 + 4 }
        return width
    }

    override func layout() {
        super.layout()
        NoteAnimation.withoutAnimation {
            scrollView.frame = bounds
            let documentHeight = max(contentSize.height, bounds.height)
            scrollView.documentView?.frame = NSRect(x: 0, y: 0, width: bounds.width, height: documentHeight)
            documentView.frame = NSRect(x: 0, y: 0, width: bounds.width, height: documentHeight)
            for index in placed.indices { placed[index].frame.size.width = bounds.width - NoteTheme.menuInset * 2 }
            scrollView.verticalScrollElasticity = contentSize.height > bounds.height + 0.5 ? .automatic : .none
            if let highlighted, let frame = frame(forItem: highlighted) { plate.frame = frame }
        }
        if let highlighted { scrollToReveal(highlighted) }
        documentView.needsDisplay = true
    }

    fileprivate var placedRows: [Placed] { placed }
    fileprivate var highlightedRow: Int? { highlighted }
    fileprivate var pressedRow: Int? { pressedIndex }
    fileprivate var showsIconColumn: Bool { hasIcons }

    func rowFrame(forItemID id: String) -> NSRect? {
        layoutSubtreeIfNeeded()
        guard let index = items.firstIndex(where: { $0.id == id }), visibleIndices.contains(index),
              let frame = frame(forItem: index) else { return nil }
        return convert(frame, from: documentView)
    }

    var highlightedRowFrame: NSRect? {
        highlightedItem.flatMap { rowFrame(forItemID: $0.id) }
    }

    fileprivate func frame(forItem index: Int) -> NSRect? {
        for row in placed { if case .item(let candidate) = row.row, candidate == index { return row.frame } }
        return nil
    }

    fileprivate func item(at point: NSPoint) -> Int? {
        for row in placed where row.frame.contains(point) {
            if case .item(let index) = row.row { return index }
        }
        return nil
    }

    private func setHighlight(_ index: Int?, animated: Bool, notify: Bool, reveal: Bool, force: Bool = false) {
        let target = index.flatMap { items.indices.contains($0) && items[$0].isEnabled && visibleIndices.contains($0) ? $0 : nil }
        guard force || target != highlighted else { return }
        let previous = highlighted
        highlighted = target
        movePlate(from: previous, to: target, animated: animated)
        if reveal, let target { scrollToReveal(target) }
        documentView.needsDisplay = true
        updateAccessibilitySelection()
        if notify { onHighlight?(highlightedItem) }
    }

    private func movePlate(from previous: Int?, to target: Int?, animated: Bool) {
        refreshPlateColor()
        guard let layer = plate.layer else { return }
        let shouldAnimate = animated && !NoteAnimation.reduceMotion
        if let target, let frame = frame(forItem: target) {
            if previous == nil || layer.opacity == 0 || !shouldAnimate {
                NoteAnimation.settle(layer, keys: [NoteAnimation.positionKey, NoteAnimation.boundsKey])
                NoteAnimation.withoutAnimation { plate.frame = frame }
            } else {
                NoteAnimation.slide(plate, to: frame, spring: .highlight)
            }
            if shouldAnimate {
                NoteAnimation.spring(layer, "opacity", to: Float(1), spring: .highlight, key: NoteAnimation.fadeKey)
            } else {
                NoteAnimation.settle(layer, keys: [NoteAnimation.fadeKey])
                NoteAnimation.withoutAnimation { layer.opacity = 1 }
            }
        } else if shouldAnimate {
            NoteAnimation.spring(layer, "opacity", to: Float(0), spring: .highlight, key: NoteAnimation.fadeKey)
        } else {
            NoteAnimation.settle(layer, keys: [NoteAnimation.fadeKey])
            NoteAnimation.withoutAnimation { layer.opacity = 0 }
        }
    }

    private func refreshPlateColor() {
        let destructive = highlightedItem?.isDestructive == true
        let color: NSColor
        if pressedIndex != nil && pressedIndex == highlighted {
            color = destructive ? NoteTheme.destructiveHighlight : NoteTheme.menuPressed
        } else {
            color = destructive ? NoteTheme.destructiveHighlight : NoteTheme.menuHighlight(spaceFocus: spaceFocus)
        }
        NoteAnimation.withoutAnimation { plate.layer?.backgroundColor = NoteTheme.resolved(color, in: self) }
    }

    private func scrollToReveal(_ index: Int) {
        guard let frame = frame(forItem: index) else { return }
        let clip = scrollView.contentView
        var origin = clip.bounds.origin
        let visibleHeight = clip.bounds.height
        guard visibleHeight > 0 else { return }
        let padded = frame.insetBy(dx: 0, dy: -NoteTheme.menuInset)
        if padded.minY < origin.y { origin.y = max(0, padded.minY) }
        else if padded.maxY > origin.y + visibleHeight { origin.y = min(contentSize.height - visibleHeight, padded.maxY - visibleHeight) }
        guard origin != clip.bounds.origin else { return }
        clip.scroll(to: origin)
        scrollView.reflectScrolledClipView(clip)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshPlateColor()
        documentView.needsDisplay = true
    }

    fileprivate func pointerMoved(to point: NSPoint, windowPoint: NSPoint) {
        guard NoteFloatingPanel.allowsHover(for: documentView, at: windowPoint) else { return }
        if let lastPointer, lastPointer == windowPoint { return }
        lastPointer = windowPoint
        guard let index = item(at: point), items[index].isEnabled else { return }
        highlightFromPointer = true
        setHighlight(index, animated: true, notify: true, reveal: false)
    }

    fileprivate func pointerExited() {
        lastPointer = nil
        guard highlightFromPointer, pressedIndex == nil else { return }
        if let item = highlightedItem, item.hasSubmenu { return }
        highlightFromPointer = false
        setHighlight(origin == .keyboard ? highlighted : nil, animated: true, notify: true, reveal: false)
    }

    fileprivate func pointerDown(at point: NSPoint) {
        guard let index = item(at: point), items[index].isEnabled else { pressedIndex = nil; return }
        pressedIndex = index
        highlightFromPointer = true
        setHighlight(index, animated: true, notify: true, reveal: false)
        refreshPlateColor()
    }

    fileprivate func pointerDragged(to point: NSPoint) {
        guard let pressed = pressedIndex else { return }
        let inside = item(at: point) == pressed
        setHighlight(inside ? pressed : nil, animated: true, notify: false, reveal: false)
        refreshPlateColor()
    }

    fileprivate func pointerUp(at point: NSPoint) {
        defer { pressedIndex = nil; refreshPlateColor() }
        guard let pressed = pressedIndex, item(at: point) == pressed, items[pressed].isEnabled else { return }
        onActivate?(items[pressed])
    }

    private func rebuildAccessibility() {
        accessibilityRows = visibleIndices.map { index in
            let element = NoteMenuAccessibilityRow()
            element.list = self
            element.index = index
            let item = items[index]
            element.setAccessibilityRole(.menuItem)
            element.setAccessibilityLabel(item.accessibilityLabel ?? [item.title, item.subtitle].compactMap { $0 }.joined(separator: ", "))
            element.setAccessibilityEnabled(item.isEnabled)
            element.setAccessibilityParent(self)
            if let shortcut = item.shortcut, !shortcut.isEmpty { element.setAccessibilityHelp(NoteKeycapLabel.spoken(shortcut)) }
            if item.isChecked { element.setAccessibilityValue("checked") }
            return element
        }
        setAccessibilityChildren(accessibilityRows)
        setAccessibilityLabel(visibleIndices.isEmpty ? noResultsTitle : nil)
        updateAccessibilitySelection()
    }

    private func updateAccessibilitySelection() {
        for row in accessibilityRows { row.setAccessibilitySelected(row.index == highlighted) }
        let selected = accessibilityRows.filter { $0.index == highlighted }
        setAccessibilitySelectedChildren(selected)
        if !selected.isEmpty { NSAccessibility.post(element: self, notification: .selectedChildrenChanged) }
    }

    fileprivate func accessibilityFrame(for index: Int) -> NSRect {
        guard let frame = frame(forItem: index), let window = documentView.window else { return .zero }
        return window.convertToScreen(documentView.convert(frame, to: nil))
    }

    fileprivate func accessibilityActivate(_ index: Int) -> Bool {
        guard items.indices.contains(index), items[index].isEnabled else { return false }
        onActivate?(items[index])
        return true
    }
}

@MainActor
private final class NoteMenuContainerView: NSView {
    override var isFlipped: Bool { true }
}

@MainActor
private final class NoteMenuAccessibilityRow: NSAccessibilityElement {
    weak var list: NoteMenuList?
    var index = 0

    override func accessibilityFrame() -> NSRect {
        MainActor.assumeIsolated { list?.accessibilityFrame(for: index) ?? .zero }
    }

    override func accessibilityPerformPress() -> Bool {
        MainActor.assumeIsolated { list?.accessibilityActivate(index) ?? false }
    }
}

@MainActor
final class NoteMenuDocumentView: NSView {
    fileprivate weak var list: NoteMenuList?
    private var tracking: NSTrackingArea?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect, .cursorUpdate],
                                  owner: self)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseMoved(with event: NSEvent) {
        applyNoteCursor(pointerCursor(at: convert(event.locationInWindow, from: nil)), for: event)
        list?.pointerMoved(to: convert(event.locationInWindow, from: nil), windowPoint: event.locationInWindow)
    }

    override func mouseEntered(with event: NSEvent) {
        applyNoteCursor(pointerCursor(at: convert(event.locationInWindow, from: nil)), for: event)
        list?.pointerMoved(to: convert(event.locationInWindow, from: nil), windowPoint: event.locationInWindow)
    }

    override func scrollWheel(with event: NSEvent) {
        super.scrollWheel(with: event)
        refreshPointerCursor()
    }

    override func mouseExited(with event: NSEvent) { list?.pointerExited() }
    override func mouseDown(with event: NSEvent) { list?.pointerDown(at: convert(event.locationInWindow, from: nil)) }
    override func mouseDragged(with event: NSEvent) { list?.pointerDragged(to: convert(event.locationInWindow, from: nil)) }
    override func mouseUp(with event: NSEvent) { list?.pointerUp(at: convert(event.locationInWindow, from: nil)) }
    override func rightMouseDown(with event: NSEvent) {}

    override func cursorUpdate(with event: NSEvent) {
        if !applyNoteCursor(pointerCursor(at: convert(event.locationInWindow, from: nil)), for: event) { super.cursorUpdate(with: event) }
    }

    private func pointerCursor(at point: NSPoint) -> NSCursor {
        guard let list, let index = list.item(at: point), list.items[index].isEnabled else { return .arrow }
        return .pointingHand
    }

    fileprivate func refreshPointerCursor() {
        guard let window, window.isKeyWindow else { return }
        let point = window.mouseLocationOutsideOfEventStream
        guard ownsPointer(atWindowPoint: point) else { return }
        pointerCursor(at: convert(point, from: nil)).set()
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let list else { return }
        for row in list.placedRows where row.frame.intersects(dirtyRect) {
            switch row.row {
            case .header(let title): drawHeader(title, in: row.frame)
            case .separator: drawSeparator(in: row.frame)
            case .item(let index): drawItem(list.items[index], in: row.frame, list: list)
            case .empty: drawEmpty(list.noResultsTitle, in: row.frame)
            }
        }
    }

    private func drawHeader(_ title: String, in frame: NSRect) {
        let font = NoteTheme.menuHeaderFont()
        let text = NSAttributedString(string: title, attributes: [.font: font, .foregroundColor: NoteTheme.menuTertiaryInk,
                                                                   .kern: 0.2])
        let height = ceil(font.ascender - font.descender)
        text.draw(with: NSRect(x: frame.minX + 10, y: frame.maxY - height - 5, width: frame.width - 20, height: height),
                  options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
    }

    private func drawSeparator(in frame: NSRect) {
        NoteTheme.menuSeparator.setFill()
        let scale = window?.backingScaleFactor ?? 2
        let thickness = 1 / scale * (scale >= 2 ? 2 : 1)
        NSRect(x: frame.minX + 4, y: (frame.midY - thickness / 2), width: frame.width - 8, height: thickness).fill()
    }

    private func drawEmpty(_ title: String, in frame: NSRect) {
        let font = NoteTheme.nunitoRegular(NoteTheme.menuTitleSize)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let text = NSAttributedString(string: title, attributes: [.font: font, .foregroundColor: NoteTheme.menuTertiaryInk,
                                                                   .paragraphStyle: paragraph])
        let height = ceil(font.ascender - font.descender)
        text.draw(with: NSRect(x: frame.minX + 10, y: (frame.midY - height / 2).rounded(), width: frame.width - 20, height: height),
                  options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
    }

    private func drawItem(_ item: NoteMenuList.Item, in frame: NSRect, list: NoteMenuList) {
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        if !item.isEnabled {
            NSGraphicsContext.current?.cgContext.setAlpha(NoteTheme.disabledRowOpacity)
        }
        let detailed = list.rowStyle == .detailed
        let ink = item.isDestructive ? NoteTheme.destructiveInk : NoteTheme.menuInk
        let iconInk = item.iconTint ?? (item.isDestructive ? NoteTheme.destructiveInk : NoteTheme.menuSecondaryInk)
        var x = frame.minX + 10
        if list.showsIconColumn {
            let side: CGFloat = detailed ? 30 : 20
            let box = NSRect(x: frame.minX + 8, y: (frame.midY - side / 2).rounded(), width: side, height: side)
            if detailed || item.iconFill != nil {
                let path = NSBezierPath(roundedRect: box, xRadius: detailed ? 6 : 4, yRadius: detailed ? 6 : 4)
                (item.iconFill ?? NoteTheme.menuFill).setFill()
                path.fill()
                if detailed && item.iconFill == nil {
                    NoteTheme.menuHairline.setStroke()
                    path.lineWidth = 1 / (window?.backingScaleFactor ?? 2)
                    path.stroke()
                }
            }
            if let icon = item.icon {
                NoteIconRenderer.draw(icon, in: box, tint: iconInk, pointSize: detailed ? 17 : 14,
                                      weight: NoteIconRenderer.symbolWeight(for: NoteTheme.menuTitleFont()),
                                      decoration: item.iconDecoration)
            }
            x = box.maxX + (detailed ? 12 : 10)
        }
        var right = frame.maxX - 10
        if item.hasSubmenu {
            if let chevron = NoteIconRenderer.symbol("chevron.right", pointSize: 9.5, weight: .bold) {
                let box = NSRect(x: right - 9, y: frame.minY, width: 9, height: frame.height)
                NoteIconRenderer.drawTemplate(chevron, centeredIn: box, tint: NoteTheme.menuTertiaryInk)
            }
            right -= 9 + 4
        }
        if item.isChecked {
            if let check = NoteIconRenderer.symbol("checkmark", pointSize: 11.5, weight: .bold) {
                let box = NSRect(x: right - 14, y: frame.minY, width: 14, height: frame.height)
                NoteIconRenderer.drawTemplate(check, centeredIn: box, tint: NoteTheme.checkedInk)
            }
            right -= 14 + 6
        }
        if let shortcut = item.shortcut, !shortcut.isEmpty {
            let size = NoteKeycapRenderer.size(for: shortcut)
            NoteKeycapRenderer.draw(shortcut, in: NSRect(x: right - size.width, y: frame.minY, width: size.width, height: frame.height))
            right -= size.width + 10
        }
        let titleFont = NoteTheme.menuTitleFont()
        let subtitleFont = NoteTheme.menuSubtitleFont()
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let title = NSAttributedString(string: item.title, attributes: [.font: titleFont, .foregroundColor: ink, .paragraphStyle: paragraph])
        let titleHeight = ceil(titleFont.ascender - titleFont.descender)
        let available = max(0, right - x)
        if detailed, let subtitle = item.subtitle, !subtitle.isEmpty {
            let subtitleHeight = ceil(subtitleFont.ascender - subtitleFont.descender)
            let top = (frame.midY - (titleHeight + subtitleHeight - 2) / 2).rounded()
            title.draw(with: NSRect(x: x, y: top, width: available, height: titleHeight), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
            NSAttributedString(string: subtitle, attributes: [.font: subtitleFont, .foregroundColor: NoteTheme.menuSecondaryInk, .paragraphStyle: paragraph])
                .draw(with: NSRect(x: x, y: top + titleHeight - 2, width: available, height: subtitleHeight),
                      options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
            return
        }
        let titleWidth = min(available, ceil(title.size().width))
        let top = (frame.midY - titleHeight / 2).rounded()
        title.draw(with: NSRect(x: x, y: top, width: titleWidth, height: titleHeight), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
        if let subtitle = item.subtitle, !subtitle.isEmpty, available - titleWidth > 30 {
            let subtitleHeight = ceil(subtitleFont.ascender - subtitleFont.descender)
            let baselineShift = (titleFont.ascender - subtitleFont.ascender).rounded()
            NSAttributedString(string: subtitle, attributes: [.font: subtitleFont, .foregroundColor: NoteTheme.menuTertiaryInk, .paragraphStyle: paragraph])
                .draw(with: NSRect(x: x + titleWidth + 6, y: top + baselineShift, width: available - titleWidth - 6, height: subtitleHeight),
                      options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
        }
    }
}
