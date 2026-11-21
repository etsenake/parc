import AppKit
import Testing
@testable import Parc

@MainActor
struct SidebarTablistTests {
    typealias L = SidebarChromeLayout

    final class TablistOutline: NSOutlineView {
        override func frameOfCell(atColumn column: Int, row: Int) -> NSRect {
            let frame = super.frameOfCell(atColumn: column, row: row)
            return NSRect(x: frame.minX - 18, y: frame.minY, width: frame.width + 18, height: frame.height)
        }
        override func frameOfOutlineCell(atRow row: Int) -> NSRect { .zero }
        override func setFrameSize(_ newSize: NSSize) {
            super.setFrameSize(NSSize(width: newSize.width, height: newSize.height + SidebarChromeLayout.tablistBottomInset))
        }
    }

    final class Node: NSObject {
        let height: CGFloat
        let children: [Node]
        init(_ height: CGFloat, _ children: [Node] = []) { self.height = height; self.children = children }
    }

    final class Source: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate {
        let root: [Node]
        init(_ root: [Node]) { self.root = root }
        func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int { ((item as? Node)?.children ?? root).count }
        func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any { ((item as? Node)?.children ?? root)[index] }
        func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool { !((item as? Node)?.children.isEmpty ?? true) }
        func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat { (item as? Node)?.height ?? 1 }
        func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? { NSView() }
    }

    static let width: CGFloat = 212

    static func close(_ a: NSRect, _ b: NSRect) -> Bool {
        abs(a.minX - b.minX) < 0.001 && abs(a.minY - b.minY) < 0.001 && abs(a.width - b.width) < 0.001 && abs(a.height - b.height) < 0.001
    }

    static func outline(_ nodes: [Node]) -> (TablistOutline, Source) {
        let source = Source(nodes)
        let outline = TablistOutline(frame: NSRect(x: 0, y: 0, width: width, height: 10))
        let column = NSTableColumn(identifier: .init("tablist")); column.width = width
        outline.addTableColumn(column); outline.outlineTableColumn = column
        outline.headerView = nil; outline.style = .plain; outline.autoresizesOutlineColumn = false
        outline.indentationPerLevel = L.tablistIndentation; outline.rowHeight = 5
        outline.intercellSpacing = NSSize(width: 0, height: L.tablistIntercellSpacing)
        outline.dataSource = source; outline.delegate = source
        outline.reloadData(); outline.expandItem(nil, expandChildren: true); outline.tile()
        return (outline, source)
    }

    static func list(_ rows: [L.TablistRow], levels: [Int]? = nil) -> (SidebarOutlineView, [NSView?]) {
        let list = SidebarOutlineView(frame: NSRect(x: 0, y: 0, width: width, height: 10))
        let views: [NSView?] = rows.map { row in if case .gap = row { nil } else { NSView() } }
        list.reload(rows.indices.map { SidebarOutlineEntry(key: $0, content: views[$0], row: rows[$0], level: levels?[$0] ?? 0) })
        return (list, views)
    }

    static let sequences: [[L.TablistRow]] = {
        let alphabet: [L.TablistRow] = [.item, .gap(height: L.pinnedHeaderHeight), .accessory(height: L.sectionDividerHeight),
                                        .accessory(height: L.unpinnedHeaderHeight)]
        var sequences: [[L.TablistRow]] = [[]]
        var frontier: [[L.TablistRow]] = [[]]
        for _ in 0..<4 {
            frontier = frontier.flatMap { prefix in alphabet.map { prefix + [$0] } }
            sequences += frontier
        }
        for pinned in 0...3 { for today in 0...3 { for isPrivate in [false, true] {
            sequences.append(L.tablistSlots(pinnedItems: isPrivate ? 0 : pinned, todayItems: today, isPrivate: isPrivate).map(\.row))
        } } }
        return sequences
    }()

    @MainActor final class Comparison {
        let rows: [L.TablistRow]
        let model: L.TablistLayout
        let reference: TablistOutline
        let source: Source
        let list: SidebarOutlineView
        let views: [NSView?]

        init(_ rows: [L.TablistRow]) {
            self.rows = rows
            model = L.tablist(rows)
            (reference, source) = SidebarTablistTests.outline(rows.map { row in
                switch row {
                case .item: return Node(L.tablistCellHeight)
                case .accessory(let height), .gap(let height): return Node(height)
                }
            })
            (list, views) = SidebarTablistTests.list(rows)
            list.frame.size.height = list.fittingSize.height
            list.layoutSubtreeIfNeeded()
        }
    }

    @Test(arguments: 0..<373)
    func appKitHasOneOutlineRowPerRowAtTheModelsHeight(_ index: Int) {
        let comparison = Comparison(Self.sequences[index])
        #expect(comparison.source.root.count == comparison.reference.numberOfRows)
        #expect(comparison.reference.frame.height == comparison.model.height)
    }

    @Test(arguments: 0..<373)
    func theListMatchesAppKitsHeightWithOneRowPerRow(_ index: Int) {
        let comparison = Comparison(Self.sequences[index])
        #expect(abs(comparison.list.frame.height - comparison.reference.frame.height) < 0.001)
        #expect(comparison.list.rows.count == comparison.rows.count)
    }

    @Test(arguments: 0..<373)
    func cellsSpanTheOutlineWithTheIntercellGapBelowEach(_ index: Int) {
        let comparison = Comparison(Self.sequences[index])
        for (row, kind) in comparison.rows.enumerated() {
            let cell = comparison.reference.frameOfCell(atColumn: 0, row: row)
            #expect(cell.minX == 0 && cell.width == Self.width)
            #expect(comparison.reference.rect(ofRow: row).height == cell.height + L.tablistIntercellSpacing)
            #expect(kind.cellHeight == cell.height)
        }
    }

    @Test(arguments: 0..<373)
    func theListsRowsAndCellsAreAppKits(_ index: Int) {
        let comparison = Comparison(Self.sequences[index])
        for row in comparison.rows.indices {
            let cell = comparison.reference.frameOfCell(atColumn: 0, row: row)
            #expect(Self.close(comparison.list.rows[row].frame, comparison.reference.rect(ofRow: row)))
            #expect(Self.close(comparison.list.convert(comparison.list.rows[row].cell.bounds, from: comparison.list.rows[row].cell), cell))
        }
    }

    @Test(arguments: 0..<373)
    func itemsCentreInTheirCellAccessoriesFillThemAndGapsHaveNoView(_ index: Int) {
        let comparison = Comparison(Self.sequences[index])
        for (row, (kind, span)) in zip(comparison.rows, comparison.model.views).enumerated() {
            let cell = comparison.reference.frameOfCell(atColumn: 0, row: row)
            switch kind {
            case .item:
                #expect(span == L.TablistSpan(minY: cell.minY + (cell.height - L.tablistVisibleRowHeight) / 2, height: L.tablistVisibleRowHeight))
            case .accessory:
                #expect(span == L.TablistSpan(minY: cell.minY, height: cell.height))
            case .gap:
                #expect(span == nil && comparison.views[row] == nil)
            }
        }
    }

    @Test(arguments: 0..<373)
    func viewsSitOnTheirSpansAcrossTheList(_ index: Int) {
        let comparison = Comparison(Self.sequences[index])
        for (row, span) in comparison.model.views.enumerated() {
            guard let view = comparison.views[row], let span else { continue }
            let frame = comparison.list.convert(view.bounds, from: view)
            #expect(abs(frame.minY - span.minY) < 0.001 && abs(frame.height - span.height) < 0.001)
            #expect(frame.minX == 0 && frame.width == Self.width)
        }
    }

    @MainActor final class Leveled {
        let tree: TablistOutline
        let levels: [Int]
        let list: SidebarOutlineView
        let views: [NSView?]

        init() {
            let tree = SidebarTablistTests.outline([Node(40, [Node(40, [Node(40)]), Node(40)]), Node(24), Node(40)]).0
            self.tree = tree
            levels = (0..<tree.numberOfRows).map { tree.level(forRow: $0) }
            (list, views) = SidebarTablistTests.list([.item, .item, .item, .item, .accessory(height: L.sectionDividerHeight), .item], levels: levels)
            list.frame.size.height = list.fittingSize.height
            list.layoutSubtreeIfNeeded()
        }
    }

    @Test func theSequencesCoverEveryShortRowStringAndEverySlotLayout() {
        #expect(Self.sequences.count == 373)
    }

    @Test func theReferenceTreeExpandsToItsLevels() {
        #expect(Leveled().levels == [0, 1, 2, 1, 0, 0])
    }

    @Test(arguments: 0..<6)
    func aLevelledCellIndentsByItsLevelAndTheListMatchesIt(_ row: Int) {
        let leveled = Leveled()
        let cell = leveled.tree.frameOfCell(atColumn: 0, row: row)
        #expect(cell.minX == CGFloat(leveled.levels[row]) * L.tablistIndentation && cell.maxX == Self.width)
        #expect(Self.close(leveled.list.convert(leveled.list.rows[row].cell.bounds, from: leveled.list.rows[row].cell), cell))
        if let view = leveled.views[row] {
            let frame = leveled.list.convert(view.bounds, from: view)
            #expect(frame.minX == cell.minX && frame.maxX == Self.width)
        }
    }

    private static let overflowing = L.tablistSlots(pinnedItems: 6, todayItems: 0, isPrivate: false).map(\.row)

    private static func scrolled(style: NSScroller.Style?, clip: CGFloat) -> (NSScrollView, NSView) {
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: width, height: clip))
        scroll.drawsBackground = false; scroll.adoptTablistScroller()
        if let style { scroll.scrollerStyle = style }
        let (list, _) = list(overflowing)
        scroll.documentView = list
        for _ in 0..<3 {
            list.frame = NSRect(x: 0, y: 0, width: scroll.contentSize.width, height: list.fittingSize.height)
            list.layoutSubtreeIfNeeded(); scroll.tile()
        }
        return (scroll, list)
    }

    @Test func sixPinnedTabsOverflowFourHundredPoints() {
        #expect(L.tablist(Self.overflowing).height == 410)
    }

    @Test func theTablistUsesTheSmallNoBackgroundScroller() {
        let (fresh, _) = Self.scrolled(style: nil, clip: 400)
        #expect(fresh.verticalScroller is SidebarTablistScroller && fresh.verticalScroller?.controlSize == .small)
        #expect(fresh.hasVerticalScroller && fresh.autohidesScrollers)
    }

    @Test func theTablistFollowsTheSystemScrollerStyle() {
        #expect(Self.scrolled(style: nil, clip: 400).0.scrollerStyle == NSScroller.preferredScrollerStyle)
    }

    @Test func theScrollerIsOverlayCompatibleAndPrefersOverlay() {
        #expect(SidebarTablistScroller.isCompatibleWithOverlayScrollers && SidebarTablistScroller.preferredScrollerStyle == .overlay)
    }

    @Test func overlayScrollersKeepTheListsWidth() {
        let (overlay, list) = Self.scrolled(style: .overlay, clip: 400)
        #expect(overlay.scrollerStyle == .overlay && overlay.contentSize.width == Self.width && list.frame.width == Self.width)
    }

    @Test func legacyScrollersTakeEightPoints() {
        let (legacy, list) = Self.scrolled(style: .legacy, clip: 400)
        #expect(legacy.verticalScroller?.isHidden == false && legacy.verticalScroller?.frame.width == 8)
        #expect(legacy.contentSize.width == Self.width - 8 && list.frame.width == Self.width - 8)
    }

    @Test func aListThatFitsWithItsInsetKeepsItsWidth() {
        let (fits, list) = Self.scrolled(style: .legacy, clip: 440)
        #expect(fits.verticalScroller?.isHidden == true && list.frame.width == Self.width)
    }

    private static func slotAlpha(_ scroller: NSScroller) -> Int {
        scroller.frame = NSRect(x: 0, y: 0, width: 15, height: 60)
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 15, pixelsHigh: 60, bitsPerSample: 8,
                                            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                            bytesPerRow: 0, bitsPerPixel: 0) else { return -1 }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        scroller.drawKnobSlot(in: scroller.bounds, highlight: false)
        NSGraphicsContext.restoreGraphicsState()
        var total = 0
        for x in 0..<15 { for y in 0..<60 { total += Int((bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) * 255) } }
        return total
    }

    @Test func theTablistScrollerPaintsNoKnobSlot() {
        let scroller = SidebarTablistScroller(); scroller.scrollerStyle = .legacy
        #expect(Self.slotAlpha(scroller) == 0)
    }

    @Test func appKitsLegacyScrollerPaintsItsSlot() {
        let scroller = NSScroller(); scroller.scrollerStyle = .legacy
        #expect(Self.slotAlpha(scroller) > 0)
    }
}
