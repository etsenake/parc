import AppKit

/// An item view exposed as TAB22 exposes a web row: one AX button described as
/// "Tab", titled by the page.
@MainActor final class TabItem: NSView {
    init(_ title: String) {
        super.init(frame: .zero)
        setAccessibilityElement(true); setAccessibilityRole(.button)
        setAccessibilityRoleDescription("Tab"); setAccessibilityTitle(title)
    }
    required init?(coder: NSCoder) { fatalError() }
}

/// A folder view exposed as SidebarFolderRow is: a disclosure triangle whose
/// press toggles the folder.
@MainActor final class FolderItem: NSView {
    var toggles = 0
    init(_ name: String, expanded: Bool) {
        super.init(frame: .zero)
        setAccessibilityElement(true); setAccessibilityRole(.disclosureTriangle)
        setAccessibilityLabel(name); setAccessibilityValue(expanded ? 1 : 0)
    }
    required init?(coder: NSCoder) { fatalError() }
    func activate() { toggles += 1 }
}

/// A split exposed as SidebarSplitGroupView is: a group of its tab buttons.
@MainActor final class SplitItem: NSView {
    let tabs = [TabItem("Left"), TabItem("Right")]
    init() {
        super.init(frame: .zero)
        tabs.forEach(addSubview)
        setAccessibilityElement(true); setAccessibilityRole(.group); setAccessibilityLabel("Split View, 2 tabs")
    }
    required init?(coder: NSCoder) { fatalError() }
    override func layout() {
        super.layout()
        for (index, tab) in tabs.enumerated() { tab.frame = NSRect(x: CGFloat(index) * bounds.width / 2, y: 0, width: bounds.width / 2, height: bounds.height) }
    }
}

/// A list stop like SidebarView, whose canBecomeKeyView needs the sidebar presented.
@MainActor final class FocusOwner: NSView {
    var isPresented = true
    override var acceptsFirstResponder: Bool { true }
    override var canBecomeKeyView: Bool { super.canBecomeKeyView && isPresented }
}

enum Control: Hashable { case header, divider, heading, newTab }

@main @MainActor struct SidebarOutlineTests {
    static var count = 0
    static func check(_ value: @autoclosure () -> Bool, _ message: String) {
        count += 1
        guard value() else { fatalError("SidebarOutline: \(message)") }
    }
    static func same(_ lhs: Any?, _ rhs: AnyObject?) -> Bool { (lhs as AnyObject?) === rhs }
    static func frame(_ view: NSView) -> NSRect { NSAccessibility.screenRect(fromView: view, rect: view.bounds) }
    static func close(_ a: NSRect, _ b: NSRect) -> Bool {
        abs(a.minX - b.minX) < 0.5 && abs(a.minY - b.minY) < 0.5 && abs(a.width - b.width) < 0.5 && abs(a.height - b.height) < 0.5
    }

    static func main() {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: -10_000, y: -10_000, width: 240, height: 200),
                              styleMask: [.titled], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        let root = FocusOwner(frame: NSRect(x: 0, y: 0, width: 240, height: 200))
        window.contentView = root
        let scroll = NSScrollView(frame: NSRect(x: 8, y: 0, width: 224, height: 200))
        root.addSubview(scroll)
        // Configured as SidebarView configures its list: the outline sets
        //
        let outline = SidebarOutlineView()
        outline.focusOwner = root
        scroll.documentView = outline
        check(outline.orientation == .vertical && outline.spacing == 0 && outline.edgeInsets.top == 0
              && outline.edgeInsets.bottom == SidebarChromeLayout.tablistBottomInset, "rows abut and the outline ends with the bottom inset")

        // Items are keyed by their SidebarItemReference, as SidebarView keys them.
        let pinnedID = SidebarItemReference.tab(UUID()), childID = SidebarItemReference.tab(UUID())
        let splitID = SidebarItemReference.split(UUID()), todayID = SidebarItemReference.tab(UUID())
        let workID = UUID(), archiveID = UUID()
        let workKey = AnyHashable(SidebarItemReference.folder(workID)), archiveKey = AnyHashable(SidebarItemReference.folder(archiveID))
        let pinned = TabItem("Pinned"), folder = FolderItem("Work", expanded: true), child = TabItem("Child")
        let subfolder = FolderItem("Archive", expanded: false), split = SplitItem(), today = TabItem("Today")
        // SidebarView's divider cell holds its line and Clear.
        let divider = NSBox(); divider.boxType = .separator
        let clear = ActionButton("↓ Clear")
        let dividerCell = NSView(); dividerCell.addSubview(divider); dividerCell.addSubview(clear)
        let newTab = ActionButton("New Tab", symbol: "plus")

        // The entry helpers SidebarView.render builds its items with: key,
        // row, level and disclosing folder; a folder's state and toggle.
        let tabEntry = SidebarOutlineEntry.item(childID, content: child, depth: 2, in: archiveID)
        check(tabEntry.key == AnyHashable(childID) && tabEntry.isItem && tabEntry.row == .item, "a tab entry is an item row keyed by its reference")
        check(tabEntry.level == 2, "a tab entry's folder depth is its level")
        check(tabEntry.disclosedBy == archiveKey && tabEntry.expanded == nil && tabEntry.toggle == nil,
              "a tab entry is disclosed by its folder's row and discloses nothing")
        let rootEntry = SidebarOutlineEntry.item(splitID, content: split, depth: 0, in: nil)
        check(rootEntry.isItem && rootEntry.level == 0 && rootEntry.disclosedBy == nil,
              "a root Split View entry has no level and no disclosing row")
        var toggled = 0
        let folderEntry = SidebarOutlineEntry.folder(archiveID, content: subfolder, depth: 1, in: workID, expanded: false, toggle: { toggled += 1 })
        check(folderEntry.key == archiveKey && folderEntry.isItem && folderEntry.row == .item, "a folder entry is an item row keyed by its folder")
        check(folderEntry.level == 1 && folderEntry.disclosedBy == workKey, "a folder entry is placed as a tab is")
        folderEntry.toggle?()
        check(folderEntry.expanded == false && toggled == 1, "a folder entry carries its expanded state and toggle")
        let controlEntry = SidebarOutlineEntry(key: Control.newTab, content: newTab, row: .item)
        check(!controlEntry.isItem && controlEntry.level == 0 && controlEntry.disclosedBy == nil, "a list control's entry is no item")

        // The list's own rows take their tablist slots' rows, as SidebarView's do.
        typealias Slot = SidebarChromeLayout.TablistSlot
        let header = SidebarOutlineEntry.pinnedHeader(Control.header)
        check(header.key == AnyHashable(Control.header) && header.content == nil && header.row == Slot.pinnedHeader.row && !header.isItem,
              "the pinned header entry is an empty control row in its slot")
        check(header.expandableWithoutChildren && header.expanded == nil && header.toggle == nil && header.level == 0 && header.disclosedBy == nil,
              "the pinned header entry is an expandable item with no children and no toggle")
        check(!tabEntry.expandableWithoutChildren && !folderEntry.expandableWithoutChildren && !controlEntry.expandableWithoutChildren,
              "only the pinned header is expandable without children")
        let dividerEntry = SidebarOutlineEntry(key: Control.divider, content: dividerCell, row: Slot.sectionDivider.row)
        let newTabEntry = SidebarOutlineEntry(key: Control.newTab, content: newTab, row: Slot.newTab.row)
        func entries(folderExpanded: Bool = true, pinned pinnedView: NSView = pinned) -> [SidebarOutlineEntry] {
            var list: [SidebarOutlineEntry] = [
                header,
                .item(pinnedID, content: pinnedView, depth: 0, in: nil),
                .folder(workID, content: folder, depth: 0, in: nil, expanded: folderExpanded, toggle: { folder.activate() })]
            if folderExpanded {
                list += [.item(childID, content: child, depth: 1, in: workID),
                         .folder(archiveID, content: subfolder, depth: 1, in: workID, expanded: false, toggle: { subfolder.activate() })]
            }
            return list + [.item(splitID, content: split, depth: 0, in: nil), dividerEntry, newTabEntry,
                           .item(todayID, content: today, depth: 0, in: nil)]
        }
        func layout() {
            // SidebarView sizes the list from contentHeight; it must be Auto Layout's fitting height.
            check(abs(outline.contentHeight - outline.fittingSize.height) < 0.001,
                  "the summed row heights are the outline's fitting height (\(outline.contentHeight) vs \(outline.fittingSize.height))")
            outline.frame = NSRect(x: 0, y: 0, width: scroll.contentSize.width, height: max(0, outline.contentHeight))
            outline.layoutSubtreeIfNeeded()
        }
        outline.reload(entries()); layout()

        // The outline: AppKit's AXOutline lists its rows, then one column.
        check(outline.isAccessibilityElement() && outline.accessibilityRole() == .outline, "the list is an AXOutline")
        //
        // which AX clients read as AXIdentifier only.
        check(outline.accessibilityIdentifier() == "sidebarAllTabList", "the outline's AXIdentifier is the sidebarAllTabList")
        check(outline.accessibilityLabel() == nil && outline.accessibilityTitle() == nil, "the outline has no AXDescription or AXTitle")
        let rows = outline.rows
        check(rows.count == 9, "one row per entry, the empty pinned header included (\(rows.count))")
        check(rows.map(\.key) == [Control.header, pinnedID, workKey, childID, archiveKey, splitID, Control.divider, Control.newTab, todayID]
              as [AnyHashable], "rows keep the entries' visual order")
        let children = outline.accessibilityChildren() ?? []
        check(children.count == rows.count + 1 && zip(children, rows).allSatisfy { same($0, $1) }, "children are the rows, then the column")
        let column = children.last as? NSAccessibilityElement
        check(column?.accessibilityRole() == .column && same(column?.accessibilityParent(), outline) && column?.accessibilityIndex() == 0,
              "the last child is the outline's one column")
        check((column?.accessibilityRows() ?? []).count == rows.count, "the column spans every row")
        check((outline.accessibilityRows() ?? []).count == rows.count && zip(outline.accessibilityRows() ?? [], rows).allSatisfy { same($0, $1) },
              "AXRows are exactly the row elements")
        check((outline.accessibilityColumns() ?? []).count == 1 && same(outline.accessibilityColumns()?.first, column), "one AXColumns entry")
        check(same(outline.accessibilityParent(), scroll), "the outline sits in the list's scroll area")

        // Rows and cells: AXRow / AXOutlineRow → AXCell → the entry's own element.
        for (index, row) in rows.enumerated() {
            check(row.isAccessibilityElement() && row.accessibilityRole() == .row && row.accessibilitySubrole() == .outlineRow,
                  "row \(index) is an AXRow / AXOutlineRow")
            check(row.accessibilityIndex() == index, "row \(index) AXIndex counts visible rows")
            check(same(row.accessibilityParent(), outline), "row \(index)'s parent is the outline")
            let rowChildren = row.accessibilityChildren() ?? []
            check(rowChildren.count == 1 && same(rowChildren.first, row.cell), "row \(index) holds one cell")
            check(row.cell.accessibilityRole() == .cell && same(row.cell.accessibilityParent(), row), "row \(index)'s cell is an AXCell under it")
            check(row.cell.accessibilityRowIndexRange() == NSRange(location: index, length: 1)
                  && row.cell.accessibilityColumnIndexRange() == NSRange(location: 0, length: 1), "cell \(index) index ranges")
            check(close(row.accessibilityFrame(), frame(row)) && abs(row.accessibilityFrame().width - frame(outline).width) < 0.5,
                  "row \(index) spans the outline in screen coordinates")
            // TablistOutlineView's cell: 16 points in per level, the intercell gap below.
            let indent = CGFloat(row.accessibilityDisclosureLevel()) * SidebarChromeLayout.tablistIndentation
            check(close(row.cell.frame, NSRect(x: indent, y: 0, width: row.bounds.width - indent, height: row.bounds.height - 1)),
                  "cell \(index) is its row's cell")
        }
        let byKey = Dictionary(uniqueKeysWithValues: rows.map { ($0.key, $0) })
        func cellChildren(_ key: AnyHashable) -> [Any] { byKey[key]?.cell.accessibilityChildren() ?? [] }
        for (key, item) in [(pinnedID, pinned), (workKey, folder), (childID, child), (archiveKey, subfolder), (splitID, split), (todayID, today)] as [(AnyHashable, NSView)] {
            let elements = cellChildren(key)
            check(elements.count == 1 && same(elements.first, item), "\(key)'s cell holds the item element itself")
            check(same(item.accessibilityParent(), byKey[key]?.cell), "\(key)'s element names the cell as its parent")
        }
        let newTabCell = cellChildren(Control.newTab)
        check(newTabCell.count == 1 && same(newTabCell.first, newTab.cell) && same(newTab.cell?.accessibilityParent(), byKey[Control.newTab]?.cell),
              "a control's row cell holds the control's exposed cell")
        check(cellChildren(Control.header).isEmpty, "the pinned header's row is an empty row")
        let dividerChildren = cellChildren(Control.divider)
        check(dividerChildren.count == 1 && same(dividerChildren.first, clear.cell), "Clear sits in the divider's row divider cell")

        //
        let workRow = byKey[workKey]!, archiveRow = byKey[archiveKey]!, childRow = byKey[childID]!, dividerRow = byKey[Control.divider]!
        let pinnedRow = byKey[pinnedID]!, splitRow = byKey[splitID]!, todayRow = byKey[todayID]!, newTabRow = byKey[Control.newTab]!
        func inRow(_ view: NSView, _ row: SidebarOutlineRow) -> NSRect { row.convert(view.bounds, from: view) }
        let rowWidth = outline.bounds.width
        check(close(inRow(pinned, pinnedRow), NSRect(x: 0, y: 2, width: rowWidth, height: 36)), "an item is its visible row, centred in its 40-point cell")
        check(close(inRow(child, childRow), NSRect(x: 16, y: 2, width: rowWidth - 16, height: 36)), "a folder child is indented 16 points")
        check(close(inRow(subfolder, archiveRow), NSRect(x: 16, y: 2, width: rowWidth - 16, height: 36)), "a subfolder is indented 16 points")
        check(close(inRow(newTab, newTabRow), NSRect(x: 0, y: 2, width: rowWidth, height: 36)),
              "New Tab takes an item's whole visible row cell does")
        check(close(inRow(dividerCell, dividerRow), NSRect(x: 0, y: 0, width: rowWidth, height: 24)), "the divider fills its 24-point cell")
        check(rows.map { $0.frame.height } == [3, 41, 41, 41, 41, 41, 25, 41, 41], "each row is its cell and the 1-point gap below it")
        check(zip(rows, rows.dropFirst()).allSatisfy { $0.frame.maxY == $1.frame.minY } && rows.first?.frame.minY == 0
              && outline.frame.height == (rows.last?.frame.maxY ?? 0) + SidebarChromeLayout.tablistBottomInset,
              "rows abut from the top and the outline ends 120 points below the last")
        scroll.frame.size.width = 184; layout()
        check(abs(childRow.frame.width - outline.bounds.width) < 0.5 && abs(child.frame.width - (childRow.frame.width - 16)) < 0.5
              && abs(newTab.frame.width - newTabRow.frame.width) < 0.5, "a narrower list keeps every row's insets")
        scroll.frame.size.width = 224; layout()

        // Disclosure: AppKit's folder attributes, with links both ways.
        check(workRow.isAccessibilityDisclosed() && workRow.accessibilityDisclosureLevel() == 0, "an expanded folder discloses at level 0")
        let disclosed = (workRow.accessibilityDisclosedRows() as? [Any]) ?? []
        check(disclosed.count == 2 && same(disclosed[0], childRow) && same(disclosed[1], archiveRow), "a folder discloses its direct child rows")
        check(same(childRow.accessibilityDisclosedByRow(), workRow) && childRow.accessibilityDisclosureLevel() == 1, "a child row is disclosed by its folder")
        check(!archiveRow.isAccessibilityDisclosed() && ((archiveRow.accessibilityDisclosedRows() as? [Any]) ?? []).isEmpty
              && same(archiveRow.accessibilityDisclosedByRow(), workRow) && archiveRow.accessibilityDisclosureLevel() == 1,
              "a collapsed subfolder discloses nothing and is disclosed by its parent")
        check(pinnedRow.accessibilityDisclosedByRow() == nil && !pinnedRow.isAccessibilityDisclosed() && pinnedRow.accessibilityDisclosureLevel() == 0,
              "a root tab row has no disclosure")
        check(workRow.isAccessibilitySelectorAllowed(#selector(NSView.setAccessibilityDisclosed(_:))), "a folder row takes AXDisclosing")
        check(!pinnedRow.isAccessibilitySelectorAllowed(#selector(NSView.setAccessibilityDisclosed(_:))), "a tab row does not")
        check(!workRow.isAccessibilitySelectorAllowed(#selector(NSView.setAccessibilitySelected(_:))), "selection stays with the items' actions")
        // The pinned header: an expandable item with no children, listed
        // collapsed, whose pinned items are its siblings.
        let headerRow = byKey[Control.header]!
        check(!headerRow.isAccessibilityDisclosed() && headerRow.accessibilityDisclosureLevel() == 0
              && ((headerRow.accessibilityDisclosedRows() as? [Any]) ?? []).isEmpty && headerRow.accessibilityDisclosedByRow() == nil,
              "the pinned header row is collapsed at level 0 and discloses nothing")
        check(headerRow.isAccessibilitySelectorAllowed(#selector(NSView.setAccessibilityDisclosed(_:))), "the pinned header row takes AXDisclosing")
        check(rows.allSatisfy { !same($0.accessibilityDisclosedByRow(), headerRow) } && pinnedRow.accessibilityDisclosureLevel() == 0,
              "the pinned items are the header's siblings")

        // Selected rows: the multi-selection or single selection plus the active
        // item, filtered to visible rows.
        func selectedRows() -> [Any] { outline.accessibilitySelectedRows() ?? [] }
        outline.select([pinnedID, todayID], single: nil, active: nil)
        check(selectedRows().count == 2 && same(selectedRows()[0], pinnedRow) && same(selectedRows()[1], todayRow), "AXSelectedRows are the multi-selection")
        check(pinnedRow.isAccessibilitySelected() && pinnedRow.cell.isAccessibilitySelected() && !workRow.isAccessibilitySelected(),
              "rows and cells report selection")
        outline.select([pinnedID, todayID], single: nil, active: splitID)
        check(selectedRows().count == 3 && same(selectedRows()[1], splitRow), "the active item's row joins a multi-selection")
        outline.select([], single: childID, active: splitID)
        check(selectedRows().count == 2 && same(selectedRows()[0], childRow) && same(selectedRows()[1], splitRow), "a single selection plus the active item")
        outline.select([], single: nil, active: todayID)
        check(selectedRows().count == 1 && same(selectedRows()[0], todayRow), "with no selection the active item's row is selected")
        outline.select([pinnedID, .tab(UUID())], single: nil, active: .folder(UUID()))
        check(selectedRows().count == 1 && same(selectedRows()[0], pinnedRow), "items without a visible row are not selected")

        // Setting AXDisclosing runs the folder's toggle, only on a change, and
        // leaves the selected rows alone.
        workRow.setAccessibilityDisclosed(true)
        check(folder.toggles == 0, "setting the current disclosure does nothing")
        workRow.setAccessibilityDisclosed(false)
        check(folder.toggles == 1, "collapsing the folder row runs the folder's toggle once")
        pinnedRow.setAccessibilityDisclosed(true)
        check(folder.toggles == 1 && subfolder.toggles == 0, "a tab row ignores AXDisclosing")
        // Expanding the pinned header leaves it collapsed, as AppKit's outline
        // leaves an expandable item without children (inert probe).
        headerRow.setAccessibilityDisclosed(true)
        check(!headerRow.isAccessibilityDisclosed() && ((headerRow.accessibilityDisclosedRows() as? [Any]) ?? []).isEmpty,
              "the pinned header row stays collapsed with no rows to disclose")
        check(outline.rows.count == rows.count && zip(outline.rows, rows).allSatisfy { $0 === $1 } && folder.toggles == 1 && subfolder.toggles == 0,
              "expanding the pinned header adds no rows and runs no toggle")
        check(selectedRows().count == 1 && pinnedRow.isAccessibilitySelected(), "AXDisclosing keeps the selected rows")

        // Visible rows follow the scroll position.
        let visible = outline.accessibilityVisibleRows() ?? []
        check(!visible.isEmpty && visible.count < rows.count && same(visible.first, rows.first), "only rows inside the visible area are AXVisibleRows")
        scroll.contentView.scroll(to: NSPoint(x: 0, y: outline.frame.height - scroll.contentView.bounds.height))
        scroll.reflectScrolledClipView(scroll.contentView)
        let scrolled = outline.accessibilityVisibleRows() ?? []
        check(same(scrolled.last, rows.last) && !scrolled.contains { same($0, rows.first) }, "scrolling moves the visible rows")

        // No element is exposed twice: walk the outline's subtree.
        var seen: [ObjectIdentifier: Int] = [:]
        func walk(_ element: Any) {
            guard let object = element as? NSObject else { return }
            seen[ObjectIdentifier(object), default: 0] += 1
            let children = (object as? NSView)?.accessibilityChildren() ?? (object as? NSCell)?.accessibilityChildren()
                ?? (object as? NSAccessibilityElement)?.accessibilityChildren() ?? []
            for child in children { walk(child) }
        }
        walk(outline)
        for item in [pinned, folder, child, subfolder, split, today] + split.tabs as [NSView] {
            check(seen[ObjectIdentifier(item)] == 1, "\(item.accessibilityTitle() ?? item.accessibilityLabel() ?? "item") is exposed exactly once")
        }
        check(seen.values.allSatisfy { $0 == 1 }, "no element appears twice in the outline")
        check(seen[ObjectIdentifier(clear.cell!)] == 1, "Clear is exposed once, in the divider's row")
        check(outline.contents.count == 8 && outline.contents.first === pinned && outline.contents.last === today,
              "contents keep every entry's view; the pinned header has none")

        // Rebuilds keep row elements by key; collapsing drops the child rows.
        let rebuilt = TabItem("Pinned")
        outline.reload(entries(folderExpanded: false, pinned: rebuilt)); layout()
        let collapsed = outline.rows
        check(collapsed.count == 7 && collapsed[1] === pinnedRow && collapsed[2] === workRow, "rows survive a rebuild under the same key")
        check(collapsed[0] === headerRow && !headerRow.isAccessibilityDisclosed()
              && headerRow.isAccessibilitySelectorAllowed(#selector(NSView.setAccessibilityDisclosed(_:))),
              "the pinned header row survives a rebuild, collapsed and settable")
        headerRow.setAccessibilityDisclosed(false)
        check(!headerRow.isAccessibilityDisclosed() && outline.rows.count == 7, "collapsing the pinned header changes nothing")
        check(same(collapsed[1].cell.accessibilityChildren()?.first, rebuilt) && pinned.superview == nil, "a kept row's cell takes the new element")
        check(childRow.superview == nil && archiveRow.superview == nil && child.window == nil, "rows that left the list leave the window with their elements")
        check(!workRow.isAccessibilityDisclosed() && ((workRow.accessibilityDisclosedRows() as? [Any]) ?? []).isEmpty, "the collapsed folder discloses nothing")
        check(collapsed.enumerated().allSatisfy { $0.element.accessibilityIndex() == $0.offset }, "indices follow the rebuilt order")
        check(selectedRows().count == 1 && pinnedRow.isAccessibilitySelected(), "selection carries over to kept rows")
        outline.select([], single: nil, active: nil)
        check(selectedRows().isEmpty && !collapsed[1].isAccessibilitySelected(), "clearing the selection clears every row")

        // A hidden entry keeps a hidden row that is no element and takes no space.
        let heading = NSTextField(labelWithString: "Incognito Tabs"); heading.isHidden = true
        outline.reload([header, .init(key: Control.heading, content: heading, row: Slot.privateHeading.row), newTabEntry]); layout()
        let hiddenRow = outline.arrangedSubviews.first { ($0 as? SidebarOutlineRow)?.key == AnyHashable(Control.heading) }
        check(outline.rows.count == 2 && hiddenRow?.isAccessibilityElement() == false && outline.rows[1].frame.minY == 3,
              "a hidden entry's row is no element and takes no space")

        // A repeated key still gets its own row.
        outline.reload([.item(pinnedID, content: TabItem("A"), depth: 0, in: nil), .item(pinnedID, content: TabItem("B"), depth: 0, in: nil)]); layout()
        check(outline.rows.count == 2 && outline.rows[0] !== outline.rows[1], "duplicate keys never share a row")

        // Focus: the list's keyboard stop stands for the outline while it could
        // be tabbed to: shown, with an item row to move through.
        check(!outline.isAccessibilityFocused(), "the outline is not focused while its stop is not first responder")
        window.makeFirstResponder(root)
        check(window.firstResponder === root && outline.isAccessibilityFocused(), "the stop's focus is the outline's")
        root.isPresented = false
        check(window.firstResponder === root && !outline.isAccessibilityFocused(),
              "a stop that cannot become key, as a hidden sidebar's unhidden off-screen, never focuses the outline")
        root.isPresented = true
        scroll.isHidden = true
        check(!outline.isAccessibilityFocused(), "a hidden list is never focused")
        scroll.isHidden = false
        // A Space with no items still has its header and New Tab rows.
        outline.reload([header, newTabEntry]); layout()
        check(window.firstResponder === root && outline.rows.count == 2 && !outline.isAccessibilityFocused(), "a list of controls only is never focused")
        outline.reload([]); layout()
        check(!outline.isAccessibilityFocused() && outline.rows.isEmpty, "an empty list is never focused")
        check((outline.accessibilityChildren() ?? []).count == 1, "an empty outline keeps only its column")

        window.close()
        stockHeader()
        print("SidebarOutline: \(count) checks passed")
    }

    ///
    /// no children, read and set through the attribute API remote clients use.
    static func stockHeader() {
        let window = NSWindow(contentRect: NSRect(x: -10_000, y: -10_000, width: 300, height: 200),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
        let stock = NSOutlineView(), column = NSTableColumn(identifier: .init("item"))
        stock.addTableColumn(column); stock.outlineTableColumn = column
        let source = StockSource(); stock.dataSource = source; stock.delegate = source
        scroll.documentView = stock; window.contentView = scroll
        stock.reloadData(); stock.layoutSubtreeIfNeeded()
        // The legacy attribute methods, sent as AXUIElement requests arrive.
        typealias Get = @convention(c) (NSObject, Selector, NSString) -> Unmanaged<AnyObject>?
        typealias Settable = @convention(c) (NSObject, Selector, NSString) -> Bool
        typealias Put = @convention(c) (NSObject, Selector, AnyObject, NSString) -> Void
        func send<T>(_ object: NSObject, _ name: String, as type: T.Type) -> T {
            let selector = NSSelectorFromString(name)
            return unsafeBitCast(object.method(for: selector), to: type)
        }
        let rows = (stock.perform(NSSelectorFromString("accessibilityRows"))?.takeUnretainedValue() as? NSArray)?.compactMap { $0 as? NSObject } ?? []
        func value(_ row: NSObject, _ name: String) -> Any? {
            send(row, "accessibilityAttributeValue:", as: Get.self)(row, NSSelectorFromString("accessibilityAttributeValue:"), name as NSString)?
                .takeUnretainedValue()
        }
        func settable(_ row: NSObject) -> Bool {
            send(row, "accessibilityIsAttributeSettable:", as: Settable.self)(row, NSSelectorFromString("accessibilityIsAttributeSettable:"), "AXDisclosing")
        }
        check(rows.count == 2 && (value(rows[0], "AXDisclosing") as? Bool) == false && settable(rows[0])
              && ((value(rows[0], "AXDisclosedRows") as? [Any]) ?? [0]).isEmpty && !settable(rows[1]),
              "AppKit lists the childless expandable header collapsed, AXDisclosing settable, and a tab row not settable")
        send(rows[0], "accessibilitySetValue:forAttribute:", as: Put.self)(rows[0], NSSelectorFromString("accessibilitySetValue:forAttribute:"),
                                                                         NSNumber(value: true), "AXDisclosing")
        check(source.asked > 0 && !stock.isItemExpanded(StockSource.header) && stock.numberOfRows == 2
              && (value(rows[0], "AXDisclosing") as? Bool) == false,
              "setting AXDisclosing asks the delegate and leaves the childless header collapsed")
        window.close()
    }
}

///
/// children) and a pinned tab, its sibling.
@MainActor final class StockSource: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate {
    static let header = "header" as NSString, tab = "tab" as NSString
    var asked = 0
    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int { item == nil ? 2 : 0 }
    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any { index == 0 ? Self.header : Self.tab }
    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool { (item as? NSString) == Self.header }
    func outlineView(_ outlineView: NSOutlineView, shouldExpandItem item: Any) -> Bool { asked += 1; return true }
    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? { NSView() }
}
