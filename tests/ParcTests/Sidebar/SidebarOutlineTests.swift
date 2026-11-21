import AppKit
import Testing
@testable import Parc
@testable import ParcCore

private final class PressCounter { var count = 0 }

private final class TabItem: NSView {
    let counter: PressCounter
    init(_ title: String, _ counter: PressCounter = PressCounter()) {
        self.counter = counter
        super.init(frame: .zero)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityRoleDescription("Tab")
        setAccessibilityTitle(title)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func accessibilityPerformPress() -> Bool { counter.count += 1; return true }
}

private final class FolderItem: NSView {
    var toggles = 0
    let counter: PressCounter
    init(_ name: String, expanded: Bool, _ counter: PressCounter = PressCounter()) {
        self.counter = counter
        super.init(frame: .zero)
        setAccessibilityElement(true)
        setAccessibilityRole(.disclosureTriangle)
        setAccessibilityLabel(name)
        setAccessibilityValue(expanded ? 1 : 0)
    }
    required init?(coder: NSCoder) { fatalError() }
    func activate() { toggles += 1 }
    override func accessibilityPerformPress() -> Bool { counter.count += 1; activate(); return true }
}

private final class SplitItem: NSView {
    let counter: PressCounter
    let tabs: [TabItem]
    init(_ counter: PressCounter = PressCounter()) {
        self.counter = counter
        tabs = [TabItem("Left", counter), TabItem("Right", counter)]
        super.init(frame: .zero)
        tabs.forEach(addSubview)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Split View, 2 tabs")
    }
    required init?(coder: NSCoder) { fatalError() }
    override func accessibilityPerformPress() -> Bool { counter.count += 1; return true }
    override func layout() {
        super.layout()
        for (index, tab) in tabs.enumerated() { tab.frame = NSRect(x: CGFloat(index) * bounds.width / 2, y: 0, width: bounds.width / 2, height: bounds.height) }
    }
}

private final class FocusOwner: NSView {
    var isPresented = true
    override var acceptsFirstResponder: Bool { true }
    override var canBecomeKeyView: Bool { super.canBecomeKeyView && isPresented }
}

private enum Control: Hashable { case header, divider, heading, newTab }

private final class StockSource: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate {
    static let header = "header" as NSString
    static let tab = "tab" as NSString
    var asked = 0
    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int { item == nil ? 2 : 0 }
    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any { index == 0 ? Self.header : Self.tab }
    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool { (item as? NSString) == Self.header }
    func outlineView(_ outlineView: NSOutlineView, shouldExpandItem item: Any) -> Bool { asked += 1; return true }
    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? { NSView() }
}

@MainActor
struct SidebarOutlineTests {
    typealias Slot = SidebarChromeLayout.TablistSlot

    private func same(_ lhs: Any?, _ rhs: AnyObject?) -> Bool { (lhs as AnyObject?) === rhs }
    private func frame(_ view: NSView) -> NSRect { NSAccessibility.screenRect(fromView: view, rect: view.bounds) }
    private func close(_ a: NSRect, _ b: NSRect) -> Bool {
        abs(a.minX - b.minX) < 0.5 && abs(a.minY - b.minY) < 0.5 && abs(a.width - b.width) < 0.5 && abs(a.height - b.height) < 0.5
    }

    @MainActor private final class Listing {
        let window = NSWindow(contentRect: NSRect(x: -10_000, y: -10_000, width: 240, height: 200), styleMask: [.titled], backing: .buffered, defer: true)
        let root = FocusOwner(frame: NSRect(x: 0, y: 0, width: 240, height: 200))
        let scroll = NSScrollView(frame: NSRect(x: 8, y: 0, width: 224, height: 200))
        let outline = SidebarOutlineView()
        let counter = PressCounter()
        let pinnedID = SidebarItemReference.tab(UUID())
        let childID = SidebarItemReference.tab(UUID())
        let splitID = SidebarItemReference.split(UUID())
        let todayID = SidebarItemReference.tab(UUID())
        let workID = UUID()
        let archiveID = UUID()
        let pinned: TabItem
        let folder: FolderItem
        let child: TabItem
        let subfolder: FolderItem
        let split: SplitItem
        let today: TabItem
        let divider = NSBox()
        let clear = ActionButton("↓ Clear")
        let dividerCell = NSView()
        let newTab = ActionButton("New Tab", symbol: "plus")
        var workKey: AnyHashable { AnyHashable(SidebarItemReference.folder(workID)) }
        var archiveKey: AnyHashable { AnyHashable(SidebarItemReference.folder(archiveID)) }
        let header = SidebarOutlineEntry.pinnedHeader(Control.header)

        init() {
            window.isReleasedWhenClosed = false
            window.contentView = root
            root.addSubview(scroll)
            outline.focusOwner = root
            scroll.documentView = outline
            pinned = TabItem("Pinned", counter)
            folder = FolderItem("Work", expanded: true, counter)
            child = TabItem("Child", counter)
            subfolder = FolderItem("Archive", expanded: false, counter)
            split = SplitItem(counter)
            today = TabItem("Today", counter)
            divider.boxType = .separator
            dividerCell.addSubview(divider)
            dividerCell.addSubview(clear)
            reload()
        }

        deinit { MainActor.assumeIsolated { window.close() } }

        func entries(folderExpanded: Bool = true, pinned pinnedView: NSView? = nil) -> [SidebarOutlineEntry] {
            var list: [SidebarOutlineEntry] = [
                header,
                .item(pinnedID, content: pinnedView ?? pinned, depth: 0, in: nil),
                .folder(workID, content: folder, depth: 0, in: nil, expanded: folderExpanded, toggle: { [folder] in folder.activate() })]
            if folderExpanded {
                list += [.item(childID, content: child, depth: 1, in: workID),
                         .folder(archiveID, content: subfolder, depth: 1, in: workID, expanded: false, toggle: { [subfolder] in subfolder.activate() })]
            }
            return list + [.item(splitID, content: split, depth: 0, in: nil),
                           SidebarOutlineEntry(key: Control.divider, content: dividerCell, row: Slot.sectionDivider.row),
                           SidebarOutlineEntry(key: Control.newTab, content: newTab, row: Slot.newTab.row),
                           .item(todayID, content: today, depth: 0, in: nil)]
        }

        func layout() {
            outline.frame = NSRect(x: 0, y: 0, width: scroll.contentSize.width, height: max(0, outline.contentHeight))
            outline.layoutSubtreeIfNeeded()
        }

        func reload(_ list: [SidebarOutlineEntry]? = nil) {
            outline.reload(list ?? entries())
            layout()
        }

        var rows: [SidebarOutlineRow] { outline.rows }
        var byKey: [AnyHashable: SidebarOutlineRow] { Dictionary(uniqueKeysWithValues: rows.map { ($0.key, $0) }) }
        func row(_ key: AnyHashable) -> SidebarOutlineRow { byKey[key]! }
        func cellChildren(_ key: AnyHashable) -> [Any] { byKey[key]?.cell.accessibilityChildren() ?? [] }
        func selectedRows() -> [Any] { outline.accessibilitySelectedRows() ?? [] }
    }

    @Test func rowsAbutAndTheOutlineEndsWithTheBottomInset() {
        let l = Listing()
        #expect(l.outline.orientation == .vertical)
        #expect(l.outline.spacing == 0)
        #expect(l.outline.edgeInsets.top == 0)
        #expect(l.outline.edgeInsets.bottom == SidebarChromeLayout.tablistBottomInset)
    }

    @Test func aTabEntryIsAnItemRowKeyedByItsReference() {
        let l = Listing()
        let entry = SidebarOutlineEntry.item(l.childID, content: l.child, depth: 2, in: l.archiveID)
        #expect(entry.key == AnyHashable(l.childID))
        #expect(entry.isItem)
        #expect(entry.row == .item)
        #expect(entry.level == 2)
    }

    @Test func aTabEntryIsDisclosedByItsFoldersRowAndDisclosesNothing() {
        let l = Listing()
        let entry = SidebarOutlineEntry.item(l.childID, content: l.child, depth: 2, in: l.archiveID)
        #expect(entry.disclosedBy == l.archiveKey)
        #expect(entry.expanded == nil)
        #expect(entry.toggle == nil)
    }

    @Test func aRootSplitEntryHasNoLevelAndNoDisclosingRow() {
        let l = Listing()
        let entry = SidebarOutlineEntry.item(l.splitID, content: l.split, depth: 0, in: nil)
        #expect(entry.isItem)
        #expect(entry.level == 0)
        #expect(entry.disclosedBy == nil)
    }

    @Test func aFolderEntryIsAnItemRowKeyedByItsFolderAndPlacedAsATabIs() {
        let l = Listing()
        let entry = SidebarOutlineEntry.folder(l.archiveID, content: l.subfolder, depth: 1, in: l.workID, expanded: false, toggle: {})
        #expect(entry.key == l.archiveKey)
        #expect(entry.isItem)
        #expect(entry.row == .item)
        #expect(entry.level == 1)
        #expect(entry.disclosedBy == l.workKey)
    }

    @Test func aFolderEntryCarriesItsExpandedStateAndToggle() {
        let l = Listing()
        var toggled = 0
        let entry = SidebarOutlineEntry.folder(l.archiveID, content: l.subfolder, depth: 1, in: l.workID, expanded: false, toggle: { toggled += 1 })
        entry.toggle?()
        #expect(entry.expanded == false)
        #expect(toggled == 1)
    }

    @Test func aListControlsEntryIsNoItem() {
        let l = Listing()
        let entry = SidebarOutlineEntry(key: Control.newTab, content: l.newTab, row: .item)
        #expect(!entry.isItem)
        #expect(entry.level == 0)
        #expect(entry.disclosedBy == nil)
    }

    @Test func thePinnedHeaderEntryIsAnEmptyControlRowInItsSlot() {
        let l = Listing()
        #expect(l.header.key == AnyHashable(Control.header))
        #expect(l.header.content == nil)
        #expect(l.header.row == Slot.pinnedHeader.row)
        #expect(!l.header.isItem)
    }

    @Test func thePinnedHeaderEntryIsExpandableWithNoChildrenAndNoToggle() {
        let l = Listing()
        #expect(l.header.expandableWithoutChildren)
        #expect(l.header.expanded == nil)
        #expect(l.header.toggle == nil)
        #expect(l.header.level == 0)
        #expect(l.header.disclosedBy == nil)
    }

    @Test func onlyThePinnedHeaderIsExpandableWithoutChildren() {
        let l = Listing()
        let tab = SidebarOutlineEntry.item(l.childID, content: l.child, depth: 2, in: l.archiveID)
        let folder = SidebarOutlineEntry.folder(l.archiveID, content: l.subfolder, depth: 1, in: l.workID, expanded: false, toggle: {})
        let control = SidebarOutlineEntry(key: Control.newTab, content: l.newTab, row: .item)
        #expect(!tab.expandableWithoutChildren)
        #expect(!folder.expandableWithoutChildren)
        #expect(!control.expandableWithoutChildren)
    }

    @Test func theListIsAnAXOutlineWithItsIdentifier() {
        let l = Listing()
        #expect(l.outline.isAccessibilityElement())
        #expect(l.outline.accessibilityRole() == .outline)
        #expect(l.outline.accessibilityIdentifier() == "sidebarAllTabList")
        #expect(l.outline.accessibilityLabel() == nil)
        #expect(l.outline.accessibilityTitle() == nil)
    }

    @Test func summedRowHeightsAreTheOutlinesFittingHeight() {
        let l = Listing()
        #expect(abs(l.outline.contentHeight - l.outline.fittingSize.height) < 0.001)
    }

    @Test func thereIsOneRowPerEntryTheEmptyPinnedHeaderIncluded() {
        #expect(Listing().rows.count == 9)
    }

    @Test func rowsKeepTheEntriesVisualOrder() {
        let l = Listing()
        #expect(l.rows.map(\.key) == [Control.header, l.pinnedID, l.workKey, l.childID, l.archiveKey, l.splitID, Control.divider, Control.newTab, l.todayID] as [AnyHashable])
    }

    @Test func childrenAreTheRowsThenTheColumn() {
        let l = Listing()
        let children = l.outline.accessibilityChildren() ?? []
        #expect(children.count == l.rows.count + 1)
        #expect(zip(children, l.rows).allSatisfy { same($0, $1) })
    }

    @Test func theLastChildIsTheOutlinesOneColumn() {
        let l = Listing()
        let column = l.outline.accessibilityChildren()?.last as? NSAccessibilityElement
        #expect(column?.accessibilityRole() == .column)
        #expect(same(column?.accessibilityParent(), l.outline))
        #expect(column?.accessibilityIndex() == 0)
        #expect((column?.accessibilityRows() ?? []).count == l.rows.count)
    }

    @Test func axRowsAreExactlyTheRowElementsAndThereIsOneColumn() {
        let l = Listing()
        #expect((l.outline.accessibilityRows() ?? []).count == l.rows.count)
        #expect(zip(l.outline.accessibilityRows() ?? [], l.rows).allSatisfy { same($0, $1) })
        #expect((l.outline.accessibilityColumns() ?? []).count == 1)
    }

    @Test func theOutlineSitsInTheListsScrollArea() {
        let l = Listing()
        #expect(same(l.outline.accessibilityParent(), l.scroll))
    }

    @Test(arguments: 0..<9)
    func eachRowIsAnAXRowOutlineRowCountedByVisibleIndexUnderTheOutline(index: Int) {
        let l = Listing()
        let row = l.rows[index]
        #expect(row.isAccessibilityElement())
        #expect(row.accessibilityRole() == .row)
        #expect(row.accessibilitySubrole() == .outlineRow)
        #expect(row.accessibilityIndex() == index)
        #expect(same(row.accessibilityParent(), l.outline))
    }

    @Test(arguments: 0..<9)
    func eachRowHoldsOneCellWithItsIndexRanges(index: Int) {
        let l = Listing()
        let row = l.rows[index]
        let rowChildren = row.accessibilityChildren() ?? []
        #expect(rowChildren.count == 1)
        #expect(same(rowChildren.first, row.cell))
        #expect(row.cell.accessibilityRole() == .cell)
        #expect(same(row.cell.accessibilityParent(), row))
        #expect(row.cell.accessibilityRowIndexRange() == NSRange(location: index, length: 1))
        #expect(row.cell.accessibilityColumnIndexRange() == NSRange(location: 0, length: 1))
    }

    @Test(arguments: 0..<9)
    func eachRowSpansTheOutlineInScreenCoordinates(index: Int) {
        let l = Listing()
        let row = l.rows[index]
        #expect(close(row.accessibilityFrame(), frame(row)))
        #expect(abs(row.accessibilityFrame().width - frame(l.outline).width) < 0.5)
    }

    @Test(arguments: 0..<9)
    func eachCellIsItsRowsCellIndentedByDisclosureLevel(index: Int) {
        let l = Listing()
        let row = l.rows[index]
        let indent = CGFloat(row.accessibilityDisclosureLevel()) * SidebarChromeLayout.tablistIndentation
        #expect(close(row.cell.frame, NSRect(x: indent, y: 0, width: row.bounds.width - indent, height: row.bounds.height - 1)))
    }

    @Test func eachItemsCellHoldsTheItemElementItself() {
        let l = Listing()
        let pairs: [(AnyHashable, NSView)] = [(l.pinnedID, l.pinned), (l.workKey, l.folder), (l.childID, l.child), (l.archiveKey, l.subfolder),
                                              (l.splitID, l.split), (l.todayID, l.today)]
        for (key, item) in pairs {
            let elements = l.cellChildren(key)
            #expect(elements.count == 1)
            #expect(same(elements.first, item))
            #expect(same(item.accessibilityParent(), l.byKey[key]?.cell))
        }
    }

    @Test func aControlsRowCellHoldsTheControlsExposedCell() {
        let l = Listing()
        let cell = l.cellChildren(Control.newTab)
        #expect(cell.count == 1)
        #expect(same(cell.first, l.newTab.cell))
        #expect(same(l.newTab.cell?.accessibilityParent(), l.byKey[Control.newTab]?.cell))
    }

    @Test func thePinnedHeadersRowIsAnEmptyRow() {
        #expect(Listing().cellChildren(Control.header).isEmpty)
    }

    @Test func clearSitsInTheDividersRow() {
        let l = Listing()
        let children = l.cellChildren(Control.divider)
        #expect(children.count == 1)
        #expect(same(children.first, l.clear.cell))
    }

    private func inRow(_ view: NSView, _ row: SidebarOutlineRow) -> NSRect { row.convert(view.bounds, from: view) }

    @Test func anItemIsItsVisibleRowCentredInItsFortyPointCell() {
        let l = Listing()
        #expect(close(inRow(l.pinned, l.row(l.pinnedID)), NSRect(x: 0, y: 2, width: l.outline.bounds.width, height: 36)))
    }

    @Test func aFolderChildAndASubfolderAreIndentedSixteenPoints() {
        let l = Listing()
        let width = l.outline.bounds.width
        #expect(close(inRow(l.child, l.row(l.childID)), NSRect(x: 16, y: 2, width: width - 16, height: 36)))
        #expect(close(inRow(l.subfolder, l.row(l.archiveKey)), NSRect(x: 16, y: 2, width: width - 16, height: 36)))
    }

    @Test func newTabTakesAnItemsWholeVisibleRow() {
        let l = Listing()
        #expect(close(inRow(l.newTab, l.row(Control.newTab)), NSRect(x: 0, y: 2, width: l.outline.bounds.width, height: 36)))
    }

    @Test func theDividerFillsItsTwentyFourPointCell() {
        let l = Listing()
        #expect(close(inRow(l.dividerCell, l.row(Control.divider)), NSRect(x: 0, y: 0, width: l.outline.bounds.width, height: 24)))
    }

    @Test func eachRowIsItsCellAndTheOnePointGapBelowIt() {
        #expect(Listing().rows.map { $0.frame.height } == [3, 41, 41, 41, 41, 41, 25, 41, 41])
    }

    @Test func rowsAbutFromTheTopAndTheOutlineEndsBelowTheLast() {
        let l = Listing()
        #expect(zip(l.rows, l.rows.dropFirst()).allSatisfy { $0.frame.maxY == $1.frame.minY })
        #expect(l.rows.first?.frame.minY == 0)
        #expect(l.outline.frame.height == (l.rows.last?.frame.maxY ?? 0) + SidebarChromeLayout.tablistBottomInset)
    }

    @Test func aNarrowerListKeepsEveryRowsInsets() {
        let l = Listing()
        l.scroll.frame.size.width = 184
        l.layout()
        let childRow = l.row(l.childID)
        let newTabRow = l.row(Control.newTab)
        #expect(abs(childRow.frame.width - l.outline.bounds.width) < 0.5)
        #expect(abs(l.child.frame.width - (childRow.frame.width - 16)) < 0.5)
        #expect(abs(l.newTab.frame.width - newTabRow.frame.width) < 0.5)
    }

    @Test func anExpandedFolderDisclosesAtLevelZero() {
        let l = Listing()
        let work = l.row(l.workKey)
        #expect(work.isAccessibilityDisclosed())
        #expect(work.accessibilityDisclosureLevel() == 0)
    }

    @Test func aFolderDisclosesItsDirectChildRows() {
        let l = Listing()
        let disclosed = (l.row(l.workKey).accessibilityDisclosedRows() as? [Any]) ?? []
        #expect(disclosed.count == 2)
        #expect(same(disclosed[0], l.row(l.childID)))
        #expect(same(disclosed[1], l.row(l.archiveKey)))
    }

    @Test func aChildRowIsDisclosedByItsFolder() {
        let l = Listing()
        let childRow = l.row(l.childID)
        #expect(same(childRow.accessibilityDisclosedByRow(), l.row(l.workKey)))
        #expect(childRow.accessibilityDisclosureLevel() == 1)
    }

    @Test func aCollapsedSubfolderDisclosesNothingAndIsDisclosedByItsParent() {
        let l = Listing()
        let archive = l.row(l.archiveKey)
        #expect(!archive.isAccessibilityDisclosed())
        #expect(((archive.accessibilityDisclosedRows() as? [Any]) ?? []).isEmpty)
        #expect(same(archive.accessibilityDisclosedByRow(), l.row(l.workKey)))
        #expect(archive.accessibilityDisclosureLevel() == 1)
    }

    @Test func aRootTabRowHasNoDisclosure() {
        let l = Listing()
        let pinned = l.row(l.pinnedID)
        #expect(pinned.accessibilityDisclosedByRow() == nil)
        #expect(!pinned.isAccessibilityDisclosed())
        #expect(pinned.accessibilityDisclosureLevel() == 0)
    }

    @Test func aFolderRowTakesAXDisclosingAndATabRowDoesNot() {
        let l = Listing()
        let selector = #selector(NSView.setAccessibilityDisclosed(_:))
        #expect(l.row(l.workKey).isAccessibilitySelectorAllowed(selector))
        #expect(!l.row(l.pinnedID).isAccessibilitySelectorAllowed(selector))
    }

    @Test func withoutAnOwnerAccessibilityCannotSetTheSelection() {
        let l = Listing()
        #expect(!l.row(l.workKey).isAccessibilitySelectorAllowed(#selector(NSView.setAccessibilitySelected(_:))))
        #expect(!l.outline.isAccessibilitySelectorAllowed(#selector(NSView.setAccessibilitySelectedRows(_:))))
    }

    @Test func thePinnedHeaderRowIsCollapsedAtLevelZeroAndDisclosesNothing() {
        let l = Listing()
        let headerRow = l.row(Control.header)
        #expect(!headerRow.isAccessibilityDisclosed())
        #expect(headerRow.accessibilityDisclosureLevel() == 0)
        #expect(((headerRow.accessibilityDisclosedRows() as? [Any]) ?? []).isEmpty)
        #expect(headerRow.accessibilityDisclosedByRow() == nil)
        #expect(headerRow.isAccessibilitySelectorAllowed(#selector(NSView.setAccessibilityDisclosed(_:))))
    }

    @Test func thePinnedItemsAreTheHeadersSiblings() {
        let l = Listing()
        let headerRow = l.row(Control.header)
        #expect(l.rows.allSatisfy { !same($0.accessibilityDisclosedByRow(), headerRow) })
        #expect(l.row(l.pinnedID).accessibilityDisclosureLevel() == 0)
    }

    @Test func axSelectedRowsAreTheChosenRows() {
        let l = Listing()
        l.outline.select([l.pinnedID, l.todayID])
        let rows = l.selectedRows()
        #expect(rows.count == 2)
        #expect(same(rows[0], l.row(l.pinnedID)))
        #expect(same(rows[1], l.row(l.todayID)))
    }

    @Test func rowsAndCellsReportSelection() {
        let l = Listing()
        l.outline.select([l.pinnedID, l.todayID])
        #expect(l.row(l.pinnedID).isAccessibilitySelected())
        #expect(l.row(l.pinnedID).cell.isAccessibilitySelected())
        #expect(!l.row(l.workKey).isAccessibilitySelected())
    }

    @Test func itemsWithoutAVisibleRowAreNotSelected() {
        let l = Listing()
        l.outline.select([l.pinnedID, .tab(UUID()), .folder(UUID())])
        #expect(l.selectedRows().count == 1)
        #expect(same(l.selectedRows().first, l.row(l.pinnedID)))
    }

    @Test func settingTheCurrentDisclosureDoesNothing() {
        let l = Listing()
        l.row(l.workKey).setAccessibilityDisclosed(true)
        #expect(l.folder.toggles == 0)
    }

    @Test func collapsingTheFolderRowRunsTheFoldersToggleOnce() {
        let l = Listing()
        l.row(l.workKey).setAccessibilityDisclosed(false)
        #expect(l.folder.toggles == 1)
    }

    @Test func aTabRowIgnoresAXDisclosing() {
        let l = Listing()
        l.row(l.pinnedID).setAccessibilityDisclosed(true)
        #expect(l.folder.toggles == 0)
        #expect(l.subfolder.toggles == 0)
    }

    @Test func thePinnedHeaderRowStaysCollapsedWithNoRowsToDisclose() {
        let l = Listing()
        let before = l.rows
        let headerRow = l.row(Control.header)
        headerRow.setAccessibilityDisclosed(true)
        #expect(!headerRow.isAccessibilityDisclosed())
        #expect(((headerRow.accessibilityDisclosedRows() as? [Any]) ?? []).isEmpty)
        #expect(zip(l.rows, before).allSatisfy { $0 === $1 })
        #expect(l.folder.toggles == 0)
    }

    @Test func axDisclosingKeepsTheSelectedRows() {
        let l = Listing()
        l.outline.select([l.pinnedID])
        l.row(l.workKey).setAccessibilityDisclosed(false)
        #expect(l.selectedRows().count == 1)
        #expect(l.row(l.pinnedID).isAccessibilitySelected())
    }

    @Test func onlyRowsInsideTheVisibleAreaAreAXVisibleRows() {
        let l = Listing()
        let visible = l.outline.accessibilityVisibleRows() ?? []
        #expect(!visible.isEmpty)
        #expect(visible.count < l.rows.count)
        #expect(same(visible.first, l.rows.first))
    }

    @Test func scrollingMovesTheVisibleRows() {
        let l = Listing()
        l.scroll.contentView.scroll(to: NSPoint(x: 0, y: l.outline.frame.height - l.scroll.contentView.bounds.height))
        l.scroll.reflectScrolledClipView(l.scroll.contentView)
        let scrolled = l.outline.accessibilityVisibleRows() ?? []
        #expect(same(scrolled.last, l.rows.last))
        #expect(!scrolled.contains { same($0, l.rows.first) })
    }

    private func walk(_ element: Any, _ seen: inout [ObjectIdentifier: Int]) {
        guard let object = element as? NSObject else { return }
        seen[ObjectIdentifier(object), default: 0] += 1
        let children = (object as? NSView)?.accessibilityChildren() ?? (object as? NSCell)?.accessibilityChildren()
            ?? (object as? NSAccessibilityElement)?.accessibilityChildren() ?? []
        for child in children { walk(child, &seen) }
    }

    @Test func everyItemElementIsExposedExactlyOnce() {
        let l = Listing()
        var seen: [ObjectIdentifier: Int] = [:]
        walk(l.outline, &seen)
        for item in [l.pinned, l.folder, l.child, l.subfolder, l.split, l.today] + l.split.tabs as [NSView] {
            #expect(seen[ObjectIdentifier(item)] == 1)
        }
        #expect(seen.values.allSatisfy { $0 == 1 })
        #expect(seen[ObjectIdentifier(l.clear.cell!)] == 1)
    }

    @Test func contentsKeepEveryEntrysViewAndThePinnedHeaderHasNone() {
        let l = Listing()
        #expect(l.outline.contents.count == 8)
        #expect(l.outline.contents.first === l.pinned)
        #expect(l.outline.contents.last === l.today)
    }

    @Test func rowsSurviveARebuildUnderTheSameKey() {
        let l = Listing()
        let pinnedRow = l.row(l.pinnedID)
        let workRow = l.row(l.workKey)
        l.reload(l.entries(folderExpanded: false, pinned: TabItem("Pinned", l.counter)))
        #expect(l.rows.count == 7)
        #expect(l.rows[1] === pinnedRow)
        #expect(l.rows[2] === workRow)
    }

    @Test func thePinnedHeaderRowSurvivesARebuildCollapsedAndSettable() {
        let l = Listing()
        let headerRow = l.row(Control.header)
        l.reload(l.entries(folderExpanded: false))
        #expect(l.rows[0] === headerRow)
        #expect(!headerRow.isAccessibilityDisclosed())
        #expect(headerRow.isAccessibilitySelectorAllowed(#selector(NSView.setAccessibilityDisclosed(_:))))
    }

    @Test func collapsingThePinnedHeaderChangesNothing() {
        let l = Listing()
        let headerRow = l.row(Control.header)
        l.reload(l.entries(folderExpanded: false))
        headerRow.setAccessibilityDisclosed(false)
        #expect(!headerRow.isAccessibilityDisclosed())
        #expect(l.rows.count == 7)
    }

    @Test func aKeptRowsCellTakesTheNewElement() {
        let l = Listing()
        let rebuilt = TabItem("Pinned", l.counter)
        l.reload(l.entries(folderExpanded: false, pinned: rebuilt))
        #expect(same(l.rows[1].cell.accessibilityChildren()?.first, rebuilt))
        #expect(l.pinned.superview == nil)
    }

    @Test func rowsThatLeftTheListLeaveTheWindowWithTheirElements() {
        let l = Listing()
        let childRow = l.row(l.childID)
        let archiveRow = l.row(l.archiveKey)
        l.reload(l.entries(folderExpanded: false))
        #expect(childRow.superview == nil)
        #expect(archiveRow.superview == nil)
        #expect(l.child.window == nil)
    }

    @Test func theCollapsedFolderDisclosesNothing() {
        let l = Listing()
        let workRow = l.row(l.workKey)
        l.reload(l.entries(folderExpanded: false))
        #expect(!workRow.isAccessibilityDisclosed())
        #expect(((workRow.accessibilityDisclosedRows() as? [Any]) ?? []).isEmpty)
    }

    @Test func indicesFollowTheRebuiltOrder() {
        let l = Listing()
        l.reload(l.entries(folderExpanded: false))
        #expect(l.rows.enumerated().allSatisfy { $0.element.accessibilityIndex() == $0.offset })
    }

    @Test func selectionCarriesOverToKeptRows() {
        let l = Listing()
        l.outline.select([l.pinnedID])
        l.reload(l.entries(folderExpanded: false))
        #expect(l.selectedRows().count == 1)
        #expect(l.row(l.pinnedID).isAccessibilitySelected())
    }

    @Test func clearingTheSelectionClearsEveryRow() {
        let l = Listing()
        l.outline.select([l.pinnedID])
        l.outline.select([])
        #expect(l.selectedRows().isEmpty)
        #expect(!l.row(l.pinnedID).isAccessibilitySelected())
    }

    @Test func aHiddenEntrysRowIsNoElementAndTakesNoSpace() {
        let l = Listing()
        let heading = NSTextField(labelWithString: "Incognito Tabs")
        heading.isHidden = true
        l.reload([l.header, .init(key: Control.heading, content: heading, row: Slot.privateHeading.row),
                  SidebarOutlineEntry(key: Control.newTab, content: l.newTab, row: Slot.newTab.row)])
        let hiddenRow = l.outline.arrangedSubviews.first { ($0 as? SidebarOutlineRow)?.key == AnyHashable(Control.heading) }
        #expect(l.rows.count == 2)
        #expect(hiddenRow?.isAccessibilityElement() == false)
        #expect(l.rows[1].frame.minY == 3)
    }

    @Test func duplicateKeysNeverShareARow() {
        let l = Listing()
        l.reload([.item(l.pinnedID, content: TabItem("A"), depth: 0, in: nil), .item(l.pinnedID, content: TabItem("B"), depth: 0, in: nil)])
        #expect(l.rows.count == 2)
        #expect(l.rows[0] !== l.rows[1])
    }

    @Test func theOutlineIsNotFocusedWhileItsStopIsNotFirstResponder() {
        #expect(!Listing().outline.isAccessibilityFocused())
    }

    @Test func theStopsFocusIsTheOutlinesFocus() {
        let l = Listing()
        l.window.makeFirstResponder(l.root)
        #expect(l.window.firstResponder === l.root)
        #expect(l.outline.isAccessibilityFocused())
    }

    @Test func aStopThatCannotBecomeKeyNeverFocusesTheOutline() {
        let l = Listing()
        l.window.makeFirstResponder(l.root)
        l.root.isPresented = false
        #expect(l.window.firstResponder === l.root)
        #expect(!l.outline.isAccessibilityFocused())
    }

    @Test func aHiddenListIsNeverFocused() {
        let l = Listing()
        l.window.makeFirstResponder(l.root)
        l.scroll.isHidden = true
        #expect(!l.outline.isAccessibilityFocused())
    }

    @Test func aListOfControlsOnlyIsNeverFocused() {
        let l = Listing()
        l.window.makeFirstResponder(l.root)
        l.reload([l.header, SidebarOutlineEntry(key: Control.newTab, content: l.newTab, row: Slot.newTab.row)])
        #expect(l.outline.rows.count == 2)
        #expect(!l.outline.isAccessibilityFocused())
    }

    @Test func anEmptyListIsNeverFocusedAndKeepsOnlyItsColumn() {
        let l = Listing()
        l.window.makeFirstResponder(l.root)
        l.reload([])
        #expect(!l.outline.isAccessibilityFocused())
        #expect(l.outline.rows.isEmpty)
        #expect((l.outline.accessibilityChildren() ?? []).count == 1)
    }

    @MainActor private final class Long {
        let l = Listing()
        var built = 0
        var released: [AnyHashable] = []
        var rows: [SidebarOutlineRow] { l.outline.rows }

        init() {
            l.outline.releaseContent = { [weak self] key, _ in self?.released.append(key) }
            var long: [SidebarOutlineEntry] = [l.header]
            for index in 0..<60 {
                let key = SidebarItemReference.tab(UUID())
                long.append(index == 40
                    ? .folder(UUID(), depth: 0, in: nil, expanded: false, toggle: {}) { [weak self] in self?.built += 1; return FolderItem("Folder", expanded: false) }
                    : .item(key, depth: index % 2, in: nil) { [weak self] in
                        self?.built += 1
                        let item = TabItem("Row \(index)")
                        item.setAccessibilityCustomActions([NSAccessibilityCustomAction(name: "Close Tab") { true }])
                        return item
                    })
            }
            l.scroll.contentView.scroll(to: .zero)
            l.scroll.reflectScrolledClipView(l.scroll.contentView)
            l.reload(long)
        }
    }

    @Test func everyRowIsListedBuiltOrNot() {
        let long = Long()
        #expect(long.rows.count == 61)
        #expect((long.l.outline.accessibilityRows() ?? []).count == 61)
    }

    @Test func onlyRowsNearTheVisibleAreaBuildViewsAndJoinTheWindow() {
        let long = Long()
        let attached = long.rows.filter { $0.superview === long.l.outline }
        #expect(long.built > 0)
        #expect(long.built < 20)
        #expect(attached.count == long.built + 1)
    }

    @Test func aRowFarFromTheVisibleAreaHasNoView() {
        let long = Long()
        #expect(long.rows[52].superview == nil)
        #expect(long.rows[52].cell.content == nil)
    }

    @Test func aRowWithoutAViewKeepsItsIndexDepthDisclosureParentAndFrame() {
        let long = Long()
        let far = long.rows[52]
        #expect(far.accessibilityIndex() == 52)
        #expect(far.accessibilityDisclosureLevel() == 1)
        #expect(!far.isAccessibilityDisclosed())
        #expect(same(far.accessibilityParent(), long.l.outline))
        #expect(far.accessibilityFrame() != .zero)
    }

    @Test func aCollapsedFolderRowWithoutAViewIsListedCollapsedItsDisclosureSettable() {
        let long = Long()
        let folderRow = long.rows[41]
        #expect(folderRow.superview == nil)
        #expect(!folderRow.isAccessibilityDisclosed())
        #expect(folderRow.isAccessibilitySelectorAllowed(#selector(NSView.setAccessibilityDisclosed(_:))))
    }

    @Test func aRowWithoutAViewIsSelectedLikeAnyOther() {
        let long = Long()
        let far = long.rows[52]
        long.l.outline.select([far.key.base as! SidebarItemReference])
        #expect(far.isAccessibilitySelected())
        #expect((long.l.outline.accessibilitySelectedRows() ?? []).count == 1)
    }

    @Test func askedForItsChildrenARowTakesItsViewWithItsLabelAndActionsAtItsPlaceInTheWindow() {
        let long = Long()
        let far = long.rows[52]
        let content = (far.accessibilityChildren()?.first as? NSView)?.accessibilityChildren()?.first as? TabItem
        #expect(content?.accessibilityTitle() == "Row 51")
        #expect(content?.accessibilityCustomActions()?.first?.name == "Close Tab")
        #expect(far.superview === long.l.outline)
        #expect(content?.window === long.l.window)
    }

    @Test func movingTheAccessibilityFocusToARowWithoutAViewScrollsItInAndBuildsIt() {
        let long = Long()
        let farther = long.rows[58]
        #expect(farther.superview == nil)
        #expect(!long.l.scroll.contentView.bounds.intersects(farther.frame))
        farther.setAccessibilityFocused(true)
        #expect(long.l.scroll.contentView.bounds.contains(farther.frame))
        #expect(farther.superview === long.l.outline)
        #expect(farther.cell.content != nil)
    }

    @Test func rowsTheScrollLeavesFarBehindLetGoOfTheirViews() {
        let long = Long()
        long.rows[58].setAccessibilityFocused(true)
        #expect(long.released.contains(long.rows[1].key))
        #expect(long.rows[1].cell.content == nil)
        #expect(long.rows[1].superview == nil)
    }

    @MainActor private final class Stock {
        let window = NSWindow(contentRect: NSRect(x: -10_000, y: -10_000, width: 300, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
        let outline = NSOutlineView()
        let source = StockSource()
        typealias Get = @convention(c) (NSObject, Selector, NSString) -> Unmanaged<AnyObject>?
        typealias Settable = @convention(c) (NSObject, Selector, NSString) -> Bool
        typealias Put = @convention(c) (NSObject, Selector, AnyObject, NSString) -> Void

        init() {
            window.isReleasedWhenClosed = false
            let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
            let column = NSTableColumn(identifier: .init("item"))
            outline.addTableColumn(column)
            outline.outlineTableColumn = column
            outline.dataSource = source
            outline.delegate = source
            scroll.documentView = outline
            window.contentView = scroll
            outline.reloadData()
            outline.layoutSubtreeIfNeeded()
        }

        deinit { MainActor.assumeIsolated { window.close() } }

        var rows: [NSObject] {
            (outline.perform(NSSelectorFromString("accessibilityRows"))?.takeUnretainedValue() as? NSArray)?.compactMap { $0 as? NSObject } ?? []
        }

        func send<T>(_ object: NSObject, _ name: String, as type: T.Type) -> T { unsafeBitCast(object.method(for: NSSelectorFromString(name)), to: type) }

        func value(_ row: NSObject, _ name: String) -> Any? {
            send(row, "accessibilityAttributeValue:", as: Get.self)(row, NSSelectorFromString("accessibilityAttributeValue:"), name as NSString)?.takeUnretainedValue()
        }

        func settable(_ row: NSObject) -> Bool {
            send(row, "accessibilityIsAttributeSettable:", as: Settable.self)(row, NSSelectorFromString("accessibilityIsAttributeSettable:"), "AXDisclosing")
        }
    }

    @Test func appKitListsTheChildlessExpandableHeaderCollapsedWithAXDisclosingSettableAndATabRowNot() {
        let stock = Stock()
        let rows = stock.rows
        #expect(rows.count == 2)
        #expect((stock.value(rows[0], "AXDisclosing") as? Bool) == false)
        #expect(stock.settable(rows[0]))
        #expect(((stock.value(rows[0], "AXDisclosedRows") as? [Any]) ?? [0]).isEmpty)
        #expect(!stock.settable(rows[1]))
    }

    @Test func settingAXDisclosingAsksTheDelegateAndLeavesTheChildlessHeaderCollapsed() {
        let stock = Stock()
        let rows = stock.rows
        stock.send(rows[0], "accessibilitySetValue:forAttribute:", as: Stock.Put.self)(rows[0], NSSelectorFromString("accessibilitySetValue:forAttribute:"),
                                                                                          NSNumber(value: true), "AXDisclosing")
        #expect(stock.source.asked > 0)
        #expect(!stock.outline.isItemExpanded(StockSource.header))
        #expect(stock.outline.numberOfRows == 2)
        #expect((stock.value(rows[0], "AXDisclosing") as? Bool) == false)
    }
}
