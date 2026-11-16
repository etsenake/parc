import AppKit

@MainActor
struct SidebarOutlineEntry {
    let key: AnyHashable
    let content: NSView?
    var make: (() -> NSView)?
    let row: SidebarChromeLayout.TablistRow
    var level = 0
    var disclosedBy: AnyHashable?
    var expanded: Bool?
    var toggle: (() -> Void)?
    var isItem = false
    var expandableWithoutChildren = false

    static func item(_ item: SidebarItemReference, content: NSView, depth: Int, in folder: UUID?) -> Self {
        Self(key: item, content: content, row: .item, level: depth,
             disclosedBy: folder.map { SidebarItemReference.folder($0) }, isItem: true)
    }

    static func folder(_ id: UUID, content: NSView, depth: Int, in parent: UUID?,
                       expanded: Bool, toggle: @escaping () -> Void) -> Self {
        Self(key: SidebarItemReference.folder(id), content: content, row: .item, level: depth,
             disclosedBy: parent.map { SidebarItemReference.folder($0) }, expanded: expanded, toggle: toggle, isItem: true)
    }

    static func item(_ item: SidebarItemReference, depth: Int, in folder: UUID?, make: @escaping () -> NSView) -> Self {
        Self(key: item, content: nil, make: make, row: .item, level: depth,
             disclosedBy: folder.map { SidebarItemReference.folder($0) }, isItem: true)
    }

    static func folder(_ id: UUID, depth: Int, in parent: UUID?, expanded: Bool, toggle: @escaping () -> Void,
                       make: @escaping () -> NSView) -> Self {
        Self(key: SidebarItemReference.folder(id), content: nil, make: make, row: .item, level: depth,
             disclosedBy: parent.map { SidebarItemReference.folder($0) }, expanded: expanded, toggle: toggle, isItem: true)
    }

    static func pinnedHeader(_ key: AnyHashable) -> Self {
        Self(key: key, content: nil, row: SidebarChromeLayout.TablistSlot.pinnedHeader.row, expandableWithoutChildren: true)
    }

    static func pinnedHeader(_ key: AnyHashable, content: NSView, expanded: Bool, toggle: @escaping () -> Void) -> Self {
        Self(key: key, content: content, row: SidebarChromeLayout.TablistSlot.pinnedSectionHeader.row,
             expanded: expanded, toggle: toggle)
    }
}

@MainActor
final class SidebarOutlineView: NSView {
    override var isFlipped: Bool { true }
    let orientation = NSUserInterfaceLayoutOrientation.vertical
    let spacing: CGFloat = 0
    let edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: SidebarChromeLayout.tablistBottomInset, right: 0)
    private(set) var arrangedSubviews: [NSView] = []
    override init(frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityIdentifier("sidebarAllTabList")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    deinit { if let clipObservers { for observer in clipObservers { NotificationCenter.default.removeObserver(observer) } } }
    weak var focusOwner: NSView?
    private(set) var rows: [SidebarOutlineRow] = []
    private var rowsByKey: [AnyHashable: SidebarOutlineRow] = [:]
    private var selectedKeys: Set<AnyHashable> = []
    private lazy var column = SidebarOutlineColumn(outline: self)
    var releaseContent: ((AnyHashable, NSView) -> Void)?
    var contentLeftWindow: ((NSView) -> Void)?
    var keepsContent: ((AnyHashable) -> Bool)?
    var preparesRowsInLayout = true
    private(set) var builtViews = 0
    private(set) var hasUnbuiltRows = false
    private var animatingKeys: Set<AnyHashable> = []
    private var animationGeneration = 0
    private weak var observedClip: NSClipView?
    private var clipObservers: [NSObjectProtocol]?

    var contentHeight: CGFloat {
        let shown = arrangedSubviews.compactMap { $0.isHidden ? nil : $0 as? SidebarOutlineRow }
        return shown.reduce(edgeInsets.top + edgeInsets.bottom) { $0 + $1.rowHeight }
            + spacing * CGFloat(max(0, shown.count - 1))
    }

    override var fittingSize: NSSize { NSSize(width: frame.width, height: contentHeight) }
    override func setFrameSize(_ newSize: NSSize) {
        let widthChanged = newSize.width != frame.width
        super.setFrameSize(newSize)
        if widthChanged { needsLayout = true }
    }

    override func layout() {
        super.layout()
        placeRows()
        updateRows(budget: preparesRowsInLayout ? .max : 0)
    }

    private func placeRows() {
        var y = edgeInsets.top
        let width = max(0, bounds.width - edgeInsets.left - edgeInsets.right)
        for case let row as SidebarOutlineRow in arrangedSubviews where !row.isHidden {
            let frame = NSRect(x: edgeInsets.left, y: y, width: width, height: row.rowHeight)
            if row.frame != frame { row.frame = frame }
            y += row.rowHeight + spacing
        }
    }

    var contents: [NSView] { arrangedSubviews.compactMap { ($0 as? SidebarOutlineRow)?.cell.content } }

    @discardableResult
    func reload(_ entries: [SidebarOutlineEntry], budget: Int = .max) -> Bool {
        let previousKeys = rows.map(\.key)
        var previousExpanded: [AnyHashable: Bool] = [:]
        for row in rows { if let expanded = row.expanded { previousExpanded[row.key] = expanded } }
        var arranged: [SidebarOutlineRow] = []
        var keptRows: [AnyHashable: SidebarOutlineRow] = [:]
        for entry in entries {
            let reused = keptRows[entry.key] == nil ? rowsByKey[entry.key] ?? spareRows.removeValue(forKey: entry.key) : nil
            let row = reused ?? SidebarOutlineRow(key: entry.key, outline: self)
            if keptRows[entry.key] == nil { keptRows[entry.key] = row }
            row.configure(entry)
            arranged.append(row)
        }
        let kept = Set(arranged.map(ObjectIdentifier.init))
        for case let row as SidebarOutlineRow in arrangedSubviews where !kept.contains(ObjectIdentifier(row)) {
            row.removeFromSuperview()
            row.outline = nil
            if row.make != nil, let content = row.cell.content { row.cell.setContent(nil); releaseContent?(row.key, content) }
        }
        arrangedSubviews = arranged
        rowsByKey = keptRows
        spareRows.removeAll()
        rows = arranged.filter { !$0.isHidden }
        var folders: [AnyHashable: SidebarOutlineRow] = [:]
        for (index, row) in rows.enumerated() {
            row.index = index; row.disclosedRows = []
            if row.expanded != nil { folders[row.key] = row }
        }
        for row in rows {
            row.disclosingRow = row.disclosedByKey.flatMap { folders[$0] }
            row.disclosingRow?.disclosedRows.append(row)
        }
        for row in rows { row.selected = selectedKeys.contains(row.key) }
        placeRows()
        needsLayout = true
        let done = updateRows(budget: budget)
        let ordered = arrangedSubviews.filter { $0.superview === self }
        if subviews.count != ordered.count || zip(subviews, ordered).contains(where: { $0 !== $1 }) { subviews = ordered }
        if rows.map(\.key) != previousKeys { NSAccessibility.post(element: self, notification: .rowCountChanged) }
        for row in rows {
            guard let expanded = row.expanded, let previous = previousExpanded[row.key], previous != expanded else { continue }
            NSAccessibility.post(element: row, notification: expanded ? .rowExpanded : .rowCollapsed)
        }
        return done
    }

    private var spareRows: [AnyHashable: SidebarOutlineRow] = [:]
    func prepareReload(_ entries: ArraySlice<SidebarOutlineEntry>) {
        for entry in entries where rowsByKey[entry.key] == nil && spareRows[entry.key] == nil {
            spareRows[entry.key] = SidebarOutlineRow(key: entry.key, outline: self)
        }
    }

    @discardableResult
    func prepareRows(budget: Int) -> Bool { updateRows(budget: budget) }

    private var visibleArea: NSRect? {
        guard let clip = enclosingScrollView?.contentView else { return nil }
        return convert(clip.bounds, from: clip)
    }
    private static func area(_ visible: NSRect, beyond screens: CGFloat) -> NSRect {
        visible.insetBy(dx: 0, dy: -max(60, visible.height * screens))
    }

    @discardableResult
    private func updateRows(budget: Int) -> Bool {
        observeClip()
        let visible = visibleArea
        let near = visible.map { Self.area($0, beyond: 0.5) }
        let kept = visible.map { Self.area($0, beyond: 1.5) }
        var remaining = budget, done = true
        func prepare(_ row: SidebarOutlineRow) {
            if row.cell.content == nil || row.contentStale {
                guard remaining > 0 else { done = false; return }
                remaining -= 1
                build(row)
            }
            attach(row)
        }
        var later: [SidebarOutlineRow] = []
        for case let row as SidebarOutlineRow in arrangedSubviews {
            guard row.make != nil else {
                attach(row)
                continue
            }
            let held = animatingKeys.contains(row.key) || (row.cell.content != nil && keepsContent?(row.key) == true)
            if !row.isHidden, near.map({ $0.intersects(row.frame) }) ?? true {
                if visible.map({ $0.intersects(row.frame) }) ?? true { prepare(row) } else { later.append(row) }
                continue
            }
            if held {
                if row.contentStale { build(row) }
                continue
            }
            if row.superview === self {
                row.removeFromSuperview()
                if let content = row.cell.content { contentLeftWindow?(content) }
            }
            if let content = row.cell.content, row.contentStale || !(kept.map { $0.intersects(row.frame) } ?? true) {
                row.cell.setContent(nil); row.contentStale = false
                releaseContent?(row.key, content)
            }
        }
        for row in later { prepare(row) }
        hasUnbuiltRows = !done
        return done
    }

    private func attach(_ row: SidebarOutlineRow) {
        guard row.superview !== self else { return }
        guard let index = arrangedSubviews.firstIndex(where: { $0 === row }),
              let below = arrangedSubviews[..<index].last(where: { $0.superview === self }) else {
            addSubview(row, positioned: .below, relativeTo: nil)
            return
        }
        addSubview(row, positioned: .above, relativeTo: below)
    }

    private func build(_ row: SidebarOutlineRow) {
        guard let make = row.make else { return }
        let previous = row.cell.content
        let view = make()
        builtViews += 1
        row.contentStale = false
        if let previous, previous !== view { row.cell.setContent(nil); releaseContent?(row.key, previous) }
        row.cell.setContent(view)
        row.needsLayout = true
    }

    func content(for key: AnyHashable, building: Bool = false) -> NSView? {
        guard let row = rowsByKey[key] else { return nil }
        if building, !row.isHidden, row.make != nil {
            if row.cell.content == nil || row.contentStale { build(row) }
            attach(row)
            row.layoutSubtreeIfNeeded()
        }
        return row.cell.content
    }

    func itemFrame(for key: AnyHashable) -> NSRect? {
        guard let row = rowsByKey[key], !row.isHidden else { return nil }
        if needsLayout { placeRows() }
        return row.contentFrame
    }

    func scrollRowToVisible(_ key: AnyHashable, inset: CGFloat = 0, wholeRow: Bool = false, animated: Bool = true) {
        if needsLayout { placeRows() }
        let rowFrame = wholeRow ? rowsByKey[key].flatMap { $0.isHidden ? nil : $0.frame } : itemFrame(for: key)
        guard let frame = rowFrame, let scroll = enclosingScrollView else { return }
        let clip = scroll.contentView
        let target = convert(frame.insetBy(dx: 0, dy: -inset), to: clip)
        var bounds = clip.bounds
        if target.minY < bounds.minY { bounds.origin.y = target.minY }
        else if target.maxY > bounds.maxY { bounds.origin.y = min(target.minY, target.maxY - bounds.height) }
        let origin = clip.constrainBoundsRect(bounds).origin
        guard origin != clip.bounds.origin else { return }
        guard animated, window != nil else { clip.scroll(to: origin); scroll.reflectScrolledClipView(clip); return }
        NSAnimationContext.runAnimationGroup { context in
            context.allowsImplicitAnimation = true
            clip.scroll(to: origin)
            scroll.reflectScrolledClipView(clip)
        }
    }

    private func observeClip() {
        let clip = enclosingScrollView?.contentView
        guard clip !== observedClip else { return }
        for observer in clipObservers ?? [] { NotificationCenter.default.removeObserver(observer) }
        clipObservers = nil; observedClip = clip
        guard let clip else { return }
        clip.postsBoundsChangedNotifications = true
        clip.postsFrameChangedNotifications = true
        clipObservers = [NSView.boundsDidChangeNotification, NSView.frameDidChangeNotification].map { name in
            NotificationCenter.default.addObserver(forName: name, object: clip, queue: nil) { [weak self] _ in
                MainActor.assumeIsolated { self?.clipMoved() }
            }
        }
    }
    private func clipMoved() {
        guard !arrangedSubviews.isEmpty else { return }
        if needsLayout { placeRows() }
        updateRows(budget: preparesRowsInLayout ? .max : 0)
    }
    override func viewDidMoveToSuperview() { super.viewDidMoveToSuperview(); observeClip() }

    func removeLastRow() -> Bool {
        if let row = subviews.last {
            row.removeFromSuperview()
            return true
        }
        arrangedSubviews.removeAll(); rows.removeAll(); rowsByKey.removeAll()
        return false
    }

    func rowFrames() -> [AnyHashable: NSRect] {
        if needsLayout { placeRows() }
        var frames: [AnyHashable: NSRect] = [:]
        for row in rows where frames[row.key] == nil { frames[row.key] = row.frame }
        return frames
    }

    func animateDisclosure(from previous: [AnyHashable: NSRect], duration: CFTimeInterval = 0.25, fadesAppearing: Bool = false) {
        guard window != nil, !previous.isEmpty, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        if let visible = visibleArea {
            var held: [SidebarOutlineRow] = []
            for row in rows where row.make != nil {
                guard let old = previous[row.key], old.intersects(visible), !row.frame.intersects(Self.area(visible, beyond: 0.5)) else { continue }
                if row.cell.content == nil || row.contentStale { build(row) }
                attach(row)
                held.append(row)
            }
            if !held.isEmpty {
                animationGeneration += 1
                let generation = animationGeneration
                animatingKeys.formUnion(held.map(\.key))
                DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
                    MainActor.assumeIsolated {
                        guard let self, self.animationGeneration == generation else { return }
                        self.animatingKeys = []
                        self.updateRows(budget: self.preparesRowsInLayout ? .max : 0)
                    }
                }
            }
        }
        layoutSubtreeIfNeeded()
        let timing = CAMediaTimingFunction(name: .easeInEaseOut)
        for row in rows where row.superview === self {
            row.wantsLayer = true
            guard let layer = row.layer else { continue }
            if let old = previous[row.key] {
                let delta = old.minY - row.frame.minY
                guard abs(delta) > 0.5 else { continue }
                let slide = CABasicAnimation(keyPath: "transform.translation.y")
                slide.fromValue = delta; slide.toValue = 0
                slide.isAdditive = true; slide.duration = duration; slide.timingFunction = timing
                layer.add(slide, forKey: "parc.disclosure.slide")
            } else if row.disclosingRow != nil || fadesAppearing {
                let fade = CABasicAnimation(keyPath: "opacity")
                fade.fromValue = 0; fade.toValue = 1
                fade.duration = duration; fade.timingFunction = timing
                layer.add(fade, forKey: "parc.disclosure.fade")
            }
        }
    }

    func select(_ items: [SidebarItemReference], single: SidebarItemReference?, active: SidebarItemReference?) {
        select(Set((items + [single, active].compactMap { $0 }).map(AnyHashable.init)))
    }

    private func select(_ keys: Set<AnyHashable>) {
        let selected = keys.intersection(rows.map(\.key))
        for row in rows { row.selected = selected.contains(row.key) }
        guard selected != selectedKeys else { return }
        selectedKeys = selected
        NSAccessibility.post(element: self, notification: .selectedRowsChanged)
    }

    fileprivate func buildForAccessibility(_ row: SidebarOutlineRow) {
        guard row.superview == nil, row.make != nil, !row.isHidden else { return }
        _ = content(for: row.key, building: true)
    }

    override func isAccessibilityElement() -> Bool { !isHidden }
    override func accessibilityRole() -> NSAccessibility.Role? { .outline }
    override func accessibilityChildren() -> [Any]? { rows + [column] }
    override func accessibilityRows() -> [Any]? { rows }
    override func accessibilityVisibleRows() -> [Any]? { rows.filter { visibleRect.intersects($0.frame) } }
    override func accessibilitySelectedRows() -> [Any]? { rows.filter(\.selected) }
    override func accessibilityColumns() -> [Any]? { [column] }
    override func accessibilityVisibleColumns() -> [Any]? { [column] }
    override func isAccessibilityFocused() -> Bool {
        guard let focusOwner, focusOwner.canBecomeKeyView, let window = focusOwner.window,
              window.firstResponder === focusOwner else { return false }
        return !isHiddenOrHasHiddenAncestor && rows.contains(where: \.isItem)
    }
}

@MainActor
final class SidebarOutlineRow: NSView {
    let key: AnyHashable
    let cell = SidebarOutlineCell()
    fileprivate(set) var index = 0
    fileprivate(set) var level = 0
    fileprivate(set) var expanded: Bool?
    fileprivate(set) var selected = false
    fileprivate(set) var isItem = false
    fileprivate var disclosedByKey: AnyHashable?
    fileprivate weak var disclosingRow: SidebarOutlineRow?
    fileprivate var disclosedRows: [SidebarOutlineRow] = []
    private var toggle: (() -> Void)?
    private var disclosesNothing = false
    private var cellHeight: CGFloat = 0
    fileprivate private(set) var rowHeight: CGFloat = 0
    private var lastConfigureFingerprint: SidebarOutlineConfigureFingerprint?
    fileprivate var make: (() -> NSView)?
    fileprivate var contentStale = false
    fileprivate weak var outline: SidebarOutlineView?
    override var isFlipped: Bool { true }

    fileprivate init(key: AnyHashable, outline: SidebarOutlineView) {
        self.key = key
        self.outline = outline
        super.init(frame: .zero)
        clipsToBounds = false
        cell.autoresizingMask = [.width, .height]
        addSubview(cell)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    fileprivate func configure(_ entry: SidebarOutlineEntry) {
        let nextHeight = entry.row.cellHeight
        let nextSpan = entry.row.viewSpan
        let nextHidden = entry.content?.isHidden ?? false
        let nextDisclosesNothing = entry.expandableWithoutChildren
        let nextExpanded = entry.expanded ?? (nextDisclosesNothing ? false : nil)
        let fingerprint = SidebarOutlineConfigureFingerprint(
            contentIdentity: entry.content.map(ObjectIdentifier.init),
            cellHeight: nextHeight,
            spanMinY: nextSpan?.minY,
            spanHeight: nextSpan?.height,
            level: entry.level,
            isHidden: nextHidden,
            expanded: nextExpanded,
            isItem: entry.isItem,
            disclosesNothing: nextDisclosesNothing,
            disclosedByKey: entry.disclosedBy
        )
        if let content = entry.content, content.superview !== cell { lastConfigureFingerprint = nil }
        make = entry.make
        if make != nil, cell.content != nil { contentStale = true }
        if SidebarOutlineConfigureSkip.shouldSkip(previous: lastConfigureFingerprint, next: fingerprint) {
            toggle = entry.toggle
            return
        }
        cellHeight = nextHeight
        if rowHeight != cellHeight + SidebarChromeLayout.tablistIntercellSpacing {
            rowHeight = cellHeight + SidebarChromeLayout.tablistIntercellSpacing
            superview?.needsLayout = true
        }
        cell.span = nextSpan
        if make == nil { cell.setContent(entry.content) }
        if isHidden != nextHidden { isHidden = nextHidden; superview?.needsLayout = true }
        level = entry.level; disclosedByKey = entry.disclosedBy; isItem = entry.isItem
        disclosesNothing = nextDisclosesNothing
        expanded = nextExpanded; toggle = entry.toggle
        needsLayout = true
        lastConfigureFingerprint = fingerprint
    }

    override func layout() {
        super.layout()
        let indent = CGFloat(level) * SidebarChromeLayout.tablistIndentation
        cell.frame = NSRect(x: indent, y: 0, width: max(0, bounds.width - indent), height: cellHeight)
        cell.layoutContent()
    }

    fileprivate var contentFrame: NSRect {
        let indent = CGFloat(level) * SidebarChromeLayout.tablistIndentation
        let span = cell.span ?? SidebarChromeLayout.TablistSpan(minY: 0, height: cellHeight)
        return NSRect(x: frame.minX + indent, y: frame.minY + span.minY, width: max(0, frame.width - indent), height: span.height)
    }

    override func accessibilityParent() -> Any? { superview == nil ? outline : super.accessibilityParent() }
    override func accessibilityFrame() -> NSRect {
        guard superview == nil, let outline, outline.window != nil else { return super.accessibilityFrame() }
        return NSAccessibility.screenRect(fromView: outline, rect: frame)
    }
    override func accessibilityChildren() -> [Any]? {
        outline?.buildForAccessibility(self)
        return super.accessibilityChildren()
    }
    override func setAccessibilityFocused(_ focused: Bool) {
        if focused, let outline, !outline.visibleRect.intersects(frame) || superview == nil {
            outline.scrollRowToVisible(key, wholeRow: true, animated: false)
        }
        super.setAccessibilityFocused(focused)
    }

    override func isAccessibilityElement() -> Bool { !isHidden }
    override func accessibilityRole() -> NSAccessibility.Role? { .row }
    override func accessibilitySubrole() -> NSAccessibility.Subrole? { .outlineRow }
    override func accessibilityIndex() -> Int { index }
    override func accessibilityDisclosureLevel() -> Int { level }
    override func isAccessibilityDisclosed() -> Bool { expanded == true }
    override func setAccessibilityDisclosed(_ disclosed: Bool) {
        guard let expanded, disclosed != expanded else { return }
        toggle?()
    }
    override func accessibilityDisclosedRows() -> Any? { disclosedRows }
    override func accessibilityDisclosedByRow() -> Any? { disclosingRow }
    override func isAccessibilitySelected() -> Bool { selected }
    override func isAccessibilitySelectorAllowed(_ selector: Selector) -> Bool {
        switch selector {
        case #selector(setAccessibilityDisclosed(_:)): return expanded != nil && (toggle != nil || disclosesNothing)
        case #selector(setAccessibilitySelected(_:)): return false
        case #selector(setAccessibilityFocused(_:)): return !isHidden
        default: return super.isAccessibilitySelectorAllowed(selector)
        }
    }
}

@MainActor
final class SidebarOutlineCell: NSView {
    private(set) var content: NSView?
    fileprivate var span: SidebarChromeLayout.TablistSpan?
    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        clipsToBounds = false
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    fileprivate func setContent(_ view: NSView?) {
        guard view !== content || (view != nil && view?.superview !== self) else { return }
        if content?.superview === self { content?.removeFromSuperview() }
        content = view
        guard let view else { return }
        view.translatesAutoresizingMaskIntoConstraints = true
        view.autoresizingMask = [.width, .height]
        addSubview(view)
    }

    fileprivate func layoutContent() {
        let span = span ?? SidebarChromeLayout.TablistSpan(minY: 0, height: bounds.height)
        content?.frame = NSRect(x: 0, y: span.minY, width: bounds.width, height: span.height)
    }

    override func layout() { super.layout(); layoutContent() }

    private var row: SidebarOutlineRow? { superview as? SidebarOutlineRow }
    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .cell }
    override func accessibilityRowIndexRange() -> NSRange { NSRange(location: row?.index ?? 0, length: 1) }
    override func accessibilityColumnIndexRange() -> NSRange { NSRange(location: 0, length: 1) }
    override func isAccessibilitySelected() -> Bool { row?.selected ?? false }
}

@MainActor
private final class SidebarOutlineColumn: NSAccessibilityElement {
    private weak var outline: SidebarOutlineView?
    init(outline: SidebarOutlineView) { self.outline = outline; super.init() }
    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .column }
    override func accessibilityParent() -> Any? { outline }
    override func accessibilityIndex() -> Int { 0 }
    override func accessibilityRows() -> [Any]? { outline?.accessibilityRows() }
    override func accessibilityVisibleRows() -> [Any]? { outline?.accessibilityVisibleRows() }
    override func accessibilityFrame() -> NSRect {
        guard let outline, outline.window != nil else { return .zero }
        return NSAccessibility.screenRect(fromView: outline, rect: outline.visibleRect)
    }
}
