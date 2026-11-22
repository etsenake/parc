import AppKit
import Testing
@testable import Parc
@testable import ParcCore

@MainActor
struct SidebarOutlineTestsGeometryTests {
    private typealias Support = SidebarOutlineTestsSupport
    private typealias Control = Support.Control
    private typealias Listing = Support.Listing

    private func close(_ a: NSRect, _ b: NSRect) -> Bool {
        abs(a.minX - b.minX) < 0.5 && abs(a.minY - b.minY) < 0.5 && abs(a.width - b.width) < 0.5 && abs(a.height - b.height) < 0.5
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
        #expect(zip(children, l.rows).allSatisfy { Support.same($0, $1) })
    }

    @Test func theLastChildIsTheOutlinesOneColumn() {
        let l = Listing()
        let column = l.outline.accessibilityChildren()?.last as? NSAccessibilityElement
        #expect(column?.accessibilityRole() == .column)
        #expect(Support.same(column?.accessibilityParent(), l.outline))
        #expect(column?.accessibilityIndex() == 0)
        #expect((column?.accessibilityRows() ?? []).count == l.rows.count)
    }

    @Test func axRowsAreExactlyTheRowElementsAndThereIsOneColumn() {
        let l = Listing()
        #expect((l.outline.accessibilityRows() ?? []).count == l.rows.count)
        #expect(zip(l.outline.accessibilityRows() ?? [], l.rows).allSatisfy { Support.same($0, $1) })
        #expect((l.outline.accessibilityColumns() ?? []).count == 1)
    }

    @Test func theOutlineSitsInTheListsScrollArea() {
        let l = Listing()
        #expect(Support.same(l.outline.accessibilityParent(), l.scroll))
    }

    @Test(arguments: 0..<9)
    func eachRowIsAnAXRowOutlineRowCountedByVisibleIndexUnderTheOutline(index: Int) {
        let l = Listing()
        let row = l.rows[index]
        #expect(row.isAccessibilityElement())
        #expect(row.accessibilityRole() == .row)
        #expect(row.accessibilitySubrole() == .outlineRow)
        #expect(row.accessibilityIndex() == index)
        #expect(Support.same(row.accessibilityParent(), l.outline))
    }

    @Test(arguments: 0..<9)
    func eachRowHoldsOneCellWithItsIndexRanges(index: Int) {
        let l = Listing()
        let row = l.rows[index]
        let rowChildren = row.accessibilityChildren() ?? []
        #expect(rowChildren.count == 1)
        #expect(Support.same(rowChildren.first, row.cell))
        #expect(row.cell.accessibilityRole() == .cell)
        #expect(Support.same(row.cell.accessibilityParent(), row))
        #expect(row.cell.accessibilityRowIndexRange() == NSRange(location: index, length: 1))
        #expect(row.cell.accessibilityColumnIndexRange() == NSRange(location: 0, length: 1))
    }

    @Test(arguments: 0..<9)
    func eachRowSpansTheOutlineInScreenCoordinates(index: Int) {
        let l = Listing()
        let row = l.rows[index]
        #expect(close(row.accessibilityFrame(), Support.frame(row)))
        #expect(abs(row.accessibilityFrame().width - Support.frame(l.outline).width) < 0.5)
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
            #expect(Support.same(elements.first, item))
            #expect(Support.same(item.accessibilityParent(), l.byKey[key]?.cell))
        }
    }

    @Test func aControlsRowCellHoldsTheControlsExposedCell() {
        let l = Listing()
        let cell = l.cellChildren(Control.newTab)
        #expect(cell.count == 1)
        #expect(Support.same(cell.first, l.newTab.cell))
        #expect(Support.same(l.newTab.cell?.accessibilityParent(), l.byKey[Control.newTab]?.cell))
    }

    @Test func thePinnedHeadersRowIsAnEmptyRow() {
        #expect(Listing().cellChildren(Control.header).isEmpty)
    }

    @Test func clearSitsInTheDividersRow() {
        let l = Listing()
        let children = l.cellChildren(Control.divider)
        #expect(children.count == 1)
        #expect(Support.same(children.first, l.clear.cell))
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
}
