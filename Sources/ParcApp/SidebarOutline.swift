import AppKit

/// One visible entry of the sidebar's item list: an item (tab, Split View or
/// folder) or one of the list's own rows (pinned header, divider with Clear,
/// New Tab, the private heading).
@MainActor
struct SidebarOutlineEntry {
    /// Identifies the entry's row across renders.
    let key: AnyHashable
    /// The entry's own view, unchanged: the row's cell holds it. The pinned
    /// header's cell is empty.
    let content: NSView?
    ///
    let row: SidebarChromeLayout.TablistRow
    /// Folder depth (AXDisclosureLevel; the cell starts 16 points in per
    /// level) and the key of the folder row that discloses this one.
    var level = 0
    var disclosedBy: AnyHashable?
    /// Folders only: the expanded state and its toggle.
    var expanded: Bool?
    var toggle: (() -> Void)?
    /// Tabs, Split Views and folders, as opposed to the list's controls.
    var isItem = false
    /// An expandable item with no children (the pinned header): its row is
    /// listed collapsed and takes AXDisclosing, which leaves it collapsed.
    var expandableWithoutChildren = false

    /// A tab's or Split View's item row, keyed by its reference. `depth` is
    /// its AXDisclosureLevel and the row of `folder`, its parent, discloses it.
    static func item(_ item: SidebarItemReference, content: NSView, depth: Int, in folder: UUID?) -> Self {
        Self(key: item, content: content, row: .item, level: depth,
             disclosedBy: folder.map { SidebarItemReference.folder($0) }, isItem: true)
    }

    /// A folder's item row, placed as `item` places a tab, with its expanded
    /// state (AXDisclosing) and the toggle that setting it runs.
    static func folder(_ id: UUID, content: NSView, depth: Int, in parent: UUID?,
                       expanded: Bool, toggle: @escaping () -> Void) -> Self {
        Self(key: SidebarItemReference.folder(id), content: content, row: .item, level: depth,
             disclosedBy: parent.map { SidebarItemReference.folder($0) }, expanded: expanded, toggle: toggle, isItem: true)
    }

    ///
    /// itself expandable for a folder and for this accessory (OutlineViewItem
    ///
    /// while the pinned items are the header's siblings, so AppKit lists the
    /// row collapsed with AXDisclosing settable (the 1.170 tree's Expand).
    /// Setting it asks the delegate, which allows it for accessories
    ///
    /// children collapsed (inert probe); the expand handlers would keep only
    ///
    static func pinnedHeader(_ key: AnyHashable) -> Self {
        Self(key: key, content: nil, row: SidebarChromeLayout.TablistSlot.pinnedHeader.row, expandableWithoutChildren: true)
    }
}

///
///
/// `NSOutlineView` and overrides no accessibility method. Its overrides are
///
///
/// `shouldCollapseAutoExpandedItemsForDeposited:`, `setFrameSize:`, drags, the
/// drop highlight and init.
/// Its rows are `SidebarTableRowView`s (NSTableRowView, no accessibility
/// override) and `TablistView` holds one lazy NSTableColumn. AppKit's own
/// outline accessibility therefore applies: rows each holding one cell (the
/// 1.170 capture), then the column (the AppKit probe;
/// docs/sidebar-accessibility.md). This list is that outline: each visible
/// entry is a row view whose cell view lays out the entry's existing element,
///
/// (SidebarChromeLayout.tablist): each is its cell plus the 1-point intercell
/// gap below it, and the outline ends with the 120-point bottom inset that
///
/// constraints, a long list's rows and all their views filled the window's
/// layout engine, which grew faster than the rows did.
@MainActor
final class SidebarOutlineView: NSView {
    override var isFlipped: Bool { true }
    let orientation = NSUserInterfaceLayoutOrientation.vertical
    let spacing: CGFloat = 0
    let edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: SidebarChromeLayout.tablistBottomInset, right: 0)
    /// The rows in order, hidden ones included; a hidden row takes no space.
    private(set) var arrangedSubviews: [NSView] = []
    override init(frame: NSRect) {
        super.init(frame: frame)
        // TablistViewController's lazy getter names the new outline
        //
        //
        // setAccessibilityIdentifier:, read by AX clients as AXIdentifier.
        setAccessibilityIdentifier("sidebarAllTabList")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    ///
    /// stop stands in for it, so while it holds focus the outline is the
    /// focused element (adaptation).
    weak var focusOwner: NSView?
    /// Visible rows in order, as AXRows.
    private(set) var rows: [SidebarOutlineRow] = []
    private var rowsByKey: [AnyHashable: SidebarOutlineRow] = [:]
    /// The selected rows' keys as last posted.
    private var selectedKeys: Set<AnyHashable> = []
    private lazy var column = SidebarOutlineColumn(outline: self)

    /// The list's fitting height: each shown row's fixed height (its cell and
    /// the intercell gap) plus the insets.
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
        var y = edgeInsets.top
        let width = max(0, bounds.width - edgeInsets.left - edgeInsets.right)
        for case let row as SidebarOutlineRow in arrangedSubviews where !row.isHidden {
            let frame = NSRect(x: edgeInsets.left, y: y, width: width, height: row.rowHeight)
            if row.frame != frame { row.frame = frame }
            y += row.rowHeight + spacing
        }
    }

    /// The entries' own views, top to bottom (hidden ones included).
    var contents: [NSView] { arrangedSubviews.compactMap { ($0 as? SidebarOutlineRow)?.cell.content } }

    /// Replaces the list with `entries`. A row keeps its element across
    /// renders while its key stays; its cell takes the entry's new view.
    func reload(_ entries: [SidebarOutlineEntry]) {
        let previousKeys = rows.map(\.key)
        var previousExpanded: [AnyHashable: Bool] = [:]
        for row in rows { if let expanded = row.expanded { previousExpanded[row.key] = expanded } }
        var arranged: [SidebarOutlineRow] = []
        var keptRows: [AnyHashable: SidebarOutlineRow] = [:]
        for entry in entries {
            // A repeated key gets a row of its own rather than share one.
            let reused = keptRows[entry.key] == nil ? rowsByKey[entry.key] : nil
            let row = reused ?? SidebarOutlineRow(key: entry.key)
            if keptRows[entry.key] == nil { keptRows[entry.key] = row }
            row.configure(entry)
            arranged.append(row)
        }
        let kept = Set(arranged.map(ObjectIdentifier.init))
        for view in arrangedSubviews where !kept.contains(ObjectIdentifier(view)) { view.removeFromSuperview() }
        let changed = arrangedSubviews.count != arranged.count || zip(arrangedSubviews, arranged).contains { $0 !== $1 }
        arrangedSubviews = arranged
        if changed {
            for row in arranged where row.superview !== self { addSubview(row) }
            needsLayout = true
        }
        // Drawing order follows the list's order, as the stack's did; prepared
        // rows a render didn't use leave.
        if subviews.count != arranged.count || zip(subviews, arranged).contains(where: { $0 !== $1 }) { subviews = arranged }
        rowsByKey = keptRows
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
        if rows.map(\.key) != previousKeys { NSAccessibility.post(element: self, notification: .rowCountChanged) }
        for row in rows {
            guard let expanded = row.expanded, let previous = previousExpanded[row.key], previous != expanded else { continue }
            NSAccessibility.post(element: row, notification: expanded ? .rowExpanded : .rowCollapsed)
        }
    }

    /// Takes out the last row of an outline being let go; false once none are left.
    func removeLastRow() -> Bool {
        guard let row = arrangedSubviews.popLast() as? SidebarOutlineRow else { return false }
        if rowsByKey[row.key] === row { rowsByKey.removeValue(forKey: row.key) }
        if rows.last === row { rows.removeLast() } else { rows.removeAll { $0 === row } }
        row.removeFromSuperview()
        return true
    }

    /// Each visible row's frame by key, for `animateDisclosure(from:)`.
    func rowFrames() -> [AnyHashable: NSRect] {
        var frames: [AnyHashable: NSRect] = [:]
        for row in rows where frames[row.key] == nil { frames[row.key] = row.frame }
        return frames
    }

    /// An outline's animated expand or collapse: after a reload, rows that
    /// stay slide from their `previous` frames to their new ones and rows a
    /// folder newly discloses fade in, as NSOutlineView animates a disclosure
    ///
    /// are Parc's; Reduce Motion leaves the change in place.
    func animateDisclosure(from previous: [AnyHashable: NSRect], duration: CFTimeInterval = 0.25) {
        guard window != nil, !previous.isEmpty, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        layoutSubtreeIfNeeded()
        let timing = CAMediaTimingFunction(name: .easeInEaseOut)
        for row in rows {
            row.wantsLayer = true
            guard let layer = row.layer else { continue }
            if let old = previous[row.key] {
                let delta = old.minY - row.frame.minY
                guard abs(delta) > 0.5 else { continue }
                let slide = CABasicAnimation(keyPath: "transform.translation.y")
                slide.fromValue = delta; slide.toValue = 0
                slide.isAdditive = true; slide.duration = duration; slide.timingFunction = timing
                layer.add(slide, forKey: "parc.disclosure.slide")
            } else if row.disclosingRow != nil {
                let fade = CABasicAnimation(keyPath: "opacity")
                fade.fromValue = 0; fade.toValue = 1
                fade.duration = duration; fade.timingFunction = timing
                layer.add(fade, forKey: "parc.disclosure.fade")
            }
        }
    }

    /// Marks the selected rows (AXSelectedRows): the sidebar's multi-selection
    ///
    ///
    ///
    /// holds this set at rest is inferred (docs/sidebar-accessibility.md).
    func select(_ items: [SidebarItemReference], single: SidebarItemReference?, active: SidebarItemReference?) {
        select(Set((items + [single, active].compactMap { $0 }).map(AnyHashable.init)))
    }

    /// Marks the visible rows of `keys` selected and posts the change.
    private func select(_ keys: Set<AnyHashable>) {
        let selected = keys.intersection(rows.map(\.key))
        for row in rows { row.selected = selected.contains(row.key) }
        guard selected != selectedKeys else { return }
        selectedKeys = selected
        NSAccessibility.post(element: self, notification: .selectedRowsChanged)
    }

    override func isAccessibilityElement() -> Bool { !isHidden }
    override func accessibilityRole() -> NSAccessibility.Role? { .outline }
    /// AppKit lists the rows, then the column.
    override func accessibilityChildren() -> [Any]? { rows + [column] }
    override func accessibilityRows() -> [Any]? { rows }
    override func accessibilityVisibleRows() -> [Any]? { rows.filter { visibleRect.intersects($0.frame) } }
    override func accessibilitySelectedRows() -> [Any]? { rows.filter(\.selected) }
    override func accessibilityColumns() -> [Any]? { [column] }
    override func accessibilityVisibleColumns() -> [Any]? { [column] }
    /// Focused only while the stop could be tabbed to: its canBecomeKeyView
    /// holds (SidebarView's needs the sidebar presented, as a hidden one waits
    /// unhidden off-screen), the list is shown and an item row gives its arrow
    /// keys something to move.
    override func isAccessibilityFocused() -> Bool {
        guard let focusOwner, focusOwner.canBecomeKeyView, let window = focusOwner.window,
              window.firstResponder === focusOwner else { return false }
        // A kept Space's page waits off the strip, out of view.
        return !isHiddenOrHasHiddenAncestor && !visibleRect.isEmpty && rows.contains(where: \.isItem)
    }
}

/// One outline row: AppKit's AXRow / AXOutlineRow with its disclosure
/// attributes. Its only child is the cell.
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
    /// An expandable row with no children: AXDisclosing is settable and
    /// changes nothing.
    private var disclosesNothing = false
    private var cellHeight: CGFloat = 0
    /// The cell and the intercell gap below it.
    fileprivate private(set) var rowHeight: CGFloat = 0
    /// Last configure apply. Identical content/size/appearance fingerprints skip
    /// setContent and needsLayout; membership/size/appearance deltas still dirty.
    private var lastConfigureFingerprint: SidebarOutlineConfigureFingerprint?
    override var isFlipped: Bool { true }

    fileprivate init(key: AnyHashable) {
        self.key = key
        super.init(frame: .zero)
        // TabCellShadowSelected paints 1 point below the 36-point visible row,
        // into this cell's 2-point padding. Clipping here flattens current
        // and hover cards, including split groups.
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
        // True no-op of setContent/needsLayout when the cell already holds this
        // content with matching size/appearance. Still refresh toggle so AX
        // disclosing keeps the entry's current closure. Membership/size/
        // appearance deltas fall through and dirty layout.
        // A view another Space's outline showed since (the one New Tab row)
        // comes back to this cell.
        if let content = entry.content, content.superview !== cell { lastConfigureFingerprint = nil }
        if SidebarOutlineConfigureSkip.shouldSkip(previous: lastConfigureFingerprint, next: fingerprint) {
            toggle = entry.toggle
            return
        }
        // AppKit's row is the cell and the intercell gap below it.
        cellHeight = nextHeight
        if rowHeight != cellHeight + SidebarChromeLayout.tablistIntercellSpacing {
            rowHeight = cellHeight + SidebarChromeLayout.tablistIntercellSpacing
            superview?.needsLayout = true
        }
        cell.span = nextSpan
        cell.setContent(entry.content)
        if isHidden != nextHidden { isHidden = nextHidden; superview?.needsLayout = true }
        level = entry.level; disclosedByKey = entry.disclosedBy; isItem = entry.isItem
        disclosesNothing = nextDisclosesNothing
        expanded = nextExpanded; toggle = entry.toggle
        needsLayout = true
        lastConfigureFingerprint = fingerprint
    }

    ///
    ///
    override func layout() {
        super.layout()
        let indent = CGFloat(level) * SidebarChromeLayout.tablistIndentation
        cell.frame = NSRect(x: indent, y: 0, width: max(0, bounds.width - indent), height: cellHeight)
        cell.layoutContent()
    }

    override func isAccessibilityElement() -> Bool { !isHidden }
    override func accessibilityRole() -> NSAccessibility.Role? { .row }
    override func accessibilitySubrole() -> NSAccessibility.Subrole? { .outlineRow }
    override func accessibilityIndex() -> Int { index }
    override func accessibilityDisclosureLevel() -> Int { level }
    override func isAccessibilityDisclosed() -> Bool { expanded == true }
    /// AppKit's outline rows take AXDisclosing; a folder row runs its entry's
    /// toggle, which expands or collapses the folder. A row without children
    /// has no toggle and stays collapsed, as AppKit's outline leaves an item
    /// without children.
    override func setAccessibilityDisclosed(_ disclosed: Bool) {
        guard let expanded, disclosed != expanded else { return }
        toggle?()
    }
    override func accessibilityDisclosedRows() -> Any? { disclosedRows }
    override func accessibilityDisclosedByRow() -> Any? { disclosingRow }
    override func isAccessibilitySelected() -> Bool { selected }
    /// Selection stays with the items' own press and custom actions.
    override func isAccessibilitySelectorAllowed(_ selector: Selector) -> Bool {
        switch selector {
        case #selector(setAccessibilityDisclosed(_:)): return expanded != nil && (toggle != nil || disclosesNothing)
        case #selector(setAccessibilitySelected(_:)): return false
        default: return super.isAccessibilitySelectorAllowed(selector)
        }
    }
}

/// The row's single cell (AXCell). It lays out the entry's view: an item's
/// visible row centred in it, any other view filling it. AppKit exposes that
/// view, or a control's cell, as its child.
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
        // Width changes between layouts follow the cell.
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

/// The outline's one column (TablistView's lazy NSTableColumn), listed after
/// the rows. It spans the list's visible area.
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
