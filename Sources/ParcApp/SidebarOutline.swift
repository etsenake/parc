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
    /// Builds an item's view when its row nears the visible area or something
    ///
    ///
    var make: (() -> NSView)?
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

    /// `item`, with its view built on demand by `make`.
    static func item(_ item: SidebarItemReference, depth: Int, in folder: UUID?, make: @escaping () -> NSView) -> Self {
        Self(key: item, content: nil, make: make, row: .item, level: depth,
             disclosedBy: folder.map { SidebarItemReference.folder($0) }, isItem: true)
    }

    /// `folder`, with its view built on demand by `make`.
    static func folder(_ id: UUID, depth: Int, in parent: UUID?, expanded: Bool, toggle: @escaping () -> Void,
                       make: @escaping () -> NSView) -> Self {
        Self(key: SidebarItemReference.folder(id), content: nil, make: make, row: .item, level: depth,
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
///
/// near the visible area: every row keeps its place, disclosure and
/// accessibility element, and its view is built as it nears the visible
///
///
/// Every view in the window joins its layout engine, so a long list with a
/// view per row made AppKit's layout passes grow with the list.
@MainActor
final class SidebarOutlineView: NSView {
    override var isFlipped: Bool { true }
    let orientation = NSUserInterfaceLayoutOrientation.vertical
    let spacing: CGFloat = 0
    let edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: SidebarChromeLayout.tablistBottomInset, right: 0)
    /// The rows in order, hidden ones included; a hidden row takes no space.
    /// Only rows with a view near the visible area are subviews.
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
    deinit { if let clipObservers { for observer in clipObservers { NotificationCenter.default.removeObserver(observer) } } }
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
    /// An item's view the list let go of.
    var releaseContent: ((AnyHashable, NSView) -> Void)?
    /// An item's view left the window but is kept.
    var contentLeftWindow: ((NSView) -> Void)?
    /// Items whose views stay while far from the visible area (a rename, a drag).
    var keepsContent: ((AnyHashable) -> Bool)?
    /// Layout builds the views rows near the visible area lack; off, a page
    /// beside the shown one leaves that to `prepareRows`, a few per turn.
    var preparesRowsInLayout = true
    /// Views built so far, and whether rows near the visible area still lack one.
    private(set) var builtViews = 0
    private(set) var hasUnbuiltRows = false
    /// Rows a disclosure animation slides, kept until it ends.
    private var animatingKeys: Set<AnyHashable> = []
    private var animationGeneration = 0
    private weak var observedClip: NSClipView?
    private var clipObservers: [NSObjectProtocol]?

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
        placeRows()
        updateRows(budget: preparesRowsInLayout ? .max : 0)
    }

    /// Frames every shown row, with or without a view.
    private func placeRows() {
        var y = edgeInsets.top
        let width = max(0, bounds.width - edgeInsets.left - edgeInsets.right)
        for case let row as SidebarOutlineRow in arrangedSubviews where !row.isHidden {
            let frame = NSRect(x: edgeInsets.left, y: y, width: width, height: row.rowHeight)
            if row.frame != frame { row.frame = frame }
            y += row.rowHeight + spacing
        }
    }

    /// The entries' own views, top to bottom (hidden ones included), for
    /// rows that have one.
    var contents: [NSView] { arrangedSubviews.compactMap { ($0 as? SidebarOutlineRow)?.cell.content } }

    /// Replaces the list with `entries`. A row keeps its element across
    /// renders while its key stays; its cell takes the entry's new view. An
    /// item near the visible area builds its view now, at most `budget` of
    /// them (`prepareRows` builds the rest); false while some remain.
    @discardableResult
    func reload(_ entries: [SidebarOutlineEntry], budget: Int = .max) -> Bool {
        let previousKeys = rows.map(\.key)
        var previousExpanded: [AnyHashable: Bool] = [:]
        for row in rows { if let expanded = row.expanded { previousExpanded[row.key] = expanded } }
        var arranged: [SidebarOutlineRow] = []
        var keptRows: [AnyHashable: SidebarOutlineRow] = [:]
        for entry in entries {
            // A repeated key gets a row of its own rather than share one.
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
        // Rows a reload moved keep drawing in the list's order.
        let ordered = arrangedSubviews.filter { $0.superview === self }
        if subviews.count != ordered.count || zip(subviews, ordered).contains(where: { $0 !== $1 }) { subviews = ordered }
        if rows.map(\.key) != previousKeys { NSAccessibility.post(element: self, notification: .rowCountChanged) }
        for row in rows {
            guard let expanded = row.expanded, let previous = previousExpanded[row.key], previous != expanded else { continue }
            NSAccessibility.post(element: row, notification: expanded ? .rowExpanded : .rowCollapsed)
        }
        return done
    }

    /// Rows made ahead for a reload's new keys.
    private var spareRows: [AnyHashable: SidebarOutlineRow] = [:]
    /// Makes the rows a coming reload of `entries` needs that the list lacks,
    /// so a long list's reload, built ahead, spreads over several turns.
    func prepareReload(_ entries: ArraySlice<SidebarOutlineEntry>) {
        for entry in entries where rowsByKey[entry.key] == nil && spareRows[entry.key] == nil {
            spareRows[entry.key] = SidebarOutlineRow(key: entry.key, outline: self)
        }
    }

    /// Builds up to `budget` views rows near the visible area lack; true
    /// once none are left.
    @discardableResult
    func prepareRows(budget: Int) -> Bool { updateRows(budget: budget) }

    /// The list's visible part, from its scroll view's clip whether or not the
    /// page is on screen; outside a scroll view every row counts as visible.
    private var visibleArea: NSRect? {
        guard let clip = enclosingScrollView?.contentView else { return nil }
        return convert(clip.bounds, from: clip)
    }
    /// Half a screen beyond the visible area is built ahead of a scroll; views
    /// a screen and a half away are let go.
    private static func area(_ visible: NSRect, beyond screens: CGFloat) -> NSRect {
        visible.insetBy(dx: 0, dy: -max(60, visible.height * screens))
    }

    /// Gives the rows near the visible area their views, the visible ones
    /// first, building at most `budget`; takes the others out of the window
    /// and lets go of views far away. True once every near row has its view.
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

    /// Puts `row` in the window above the rows before it: drawing order
    /// follows the list's order, as the stack's did.
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

    /// The view of `key`'s row; with `building`, built now if it has none
    /// and placed in the window at its row, as NSTableView's
    /// viewAtColumn:row:makeIfNecessary: does.
    func content(for key: AnyHashable, building: Bool = false) -> NSView? {
        guard let row = rowsByKey[key] else { return nil }
        if building, !row.isHidden, row.make != nil {
            if row.cell.content == nil || row.contentStale { build(row) }
            attach(row)
            row.layoutSubtreeIfNeeded()
        }
        return row.cell.content
    }

    /// `key`'s row's view frame in the list, built or not: the cell's span
    /// past the row's indentation.
    func itemFrame(for key: AnyHashable) -> NSRect? {
        guard let row = rowsByKey[key], !row.isHidden else { return nil }
        if needsLayout { placeRows() }
        return row.contentFrame
    }

    /// Scrolls the least that shows `key`'s row's view with `inset` points
    /// around it, or with `wholeRow` its whole row as AppKit's
    ///
    /// runs scrollRowToVisible: in an animation group with implicit animation
    ///
    /// build as it goes.
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

    /// Watches the clip, so a scroll or a taller list builds the rows that
    /// come into view in the same turn.
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

    /// Takes the last row in the window out of an outline being let go;
    /// false once none are left, when the rest go at once.
    func removeLastRow() -> Bool {
        if let row = subviews.last {
            row.removeFromSuperview()
            return true
        }
        arrangedSubviews.removeAll(); rows.removeAll(); rowsByKey.removeAll()
        return false
    }

    /// Each visible row's frame by key, for `animateDisclosure(from:)`.
    func rowFrames() -> [AnyHashable: NSRect] {
        if needsLayout { placeRows() }
        var frames: [AnyHashable: NSRect] = [:]
        for row in rows where frames[row.key] == nil { frames[row.key] = row.frame }
        return frames
    }

    /// An outline's animated expand or collapse: after a reload, rows that
    /// stay slide from their `previous` frames to their new ones and rows a
    /// folder newly discloses fade in, as NSOutlineView animates a disclosure
    ///
    /// screen keep their views until the slide ends, even when it takes them
    /// out of view, and rows coming into view start from their old places
    /// off screen. Duration and curve are Parc's; Reduce Motion leaves the
    /// change in place.
    func animateDisclosure(from previous: [AnyHashable: NSRect], duration: CFTimeInterval = 0.25) {
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

    /// An accessibility client reached a row without a view: as AppKit's
    /// table makes a view for a row it is asked about, the row takes its
    /// view and its place in the window until the list next scrolls past it.
    fileprivate func buildForAccessibility(_ row: SidebarOutlineRow) {
        guard row.superview == nil, row.make != nil, !row.isHidden else { return }
        _ = content(for: row.key, building: true)
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
        return !isHiddenOrHasHiddenAncestor && rows.contains(where: \.isItem)
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
    /// Builds an item's view on demand; nil for the list's own rows.
    fileprivate var make: (() -> NSView)?
    /// The view came from an earlier build and is built again before use.
    fileprivate var contentStale = false
    fileprivate weak var outline: SidebarOutlineView?
    override var isFlipped: Bool { true }

    fileprivate init(key: AnyHashable, outline: SidebarOutlineView) {
        self.key = key
        self.outline = outline
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
        // A built view belongs to the build that made it; the new build's
        // `make` builds it again before it's used.
        make = entry.make
        if make != nil, cell.content != nil { contentStale = true }
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
        if make == nil { cell.setContent(entry.content) }
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

    /// Where the row's view sits in the list, built or not.
    fileprivate var contentFrame: NSRect {
        let indent = CGFloat(level) * SidebarChromeLayout.tablistIndentation
        let span = cell.span ?? SidebarChromeLayout.TablistSpan(minY: 0, height: cellHeight)
        return NSRect(x: frame.minX + indent, y: frame.minY + span.minY, width: max(0, frame.width - indent), height: span.height)
    }

    /// A row without a view is still the outline's row at its place in the
    /// list; asked for its children, it takes its view (`buildForAccessibility`).
    override func accessibilityParent() -> Any? { superview == nil ? outline : super.accessibilityParent() }
    override func accessibilityFrame() -> NSRect {
        guard superview == nil, let outline, outline.window != nil else { return super.accessibilityFrame() }
        return NSAccessibility.screenRect(fromView: outline, rect: frame)
    }
    override func accessibilityChildren() -> [Any]? {
        outline?.buildForAccessibility(self)
        return super.accessibilityChildren()
    }
    /// Moving the accessibility focus to a row out of view scrolls it in.
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
        case #selector(setAccessibilityFocused(_:)): return !isHidden
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
