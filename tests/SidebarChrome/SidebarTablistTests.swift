import AppKit

/// Inert AppKit checks of the tablist, without a window. An NSOutlineView set
///
///
/// SidebarChromeLayout.tablist and for the rows, cells and views of the
/// production SidebarOutlineView, the sidebar list; the production
/// adoptTablistScroller runs on a scroll view holding that outline.

/// TablistOutlineView: AppKit's cell 18 points left and 18 wider, no outline
/// cell, and the bottom inset added to every frame size.
private final class TablistOutline: NSOutlineView {
    override func frameOfCell(atColumn column: Int, row: Int) -> NSRect {
        let frame = super.frameOfCell(atColumn: column, row: row)
        return NSRect(x: frame.minX - 18, y: frame.minY, width: frame.width + 18, height: frame.height)
    }
    override func frameOfOutlineCell(atRow row: Int) -> NSRect { .zero }
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(NSSize(width: newSize.width, height: newSize.height + SidebarChromeLayout.tablistBottomInset))
    }
}

private final class Node: NSObject {
    let height: CGFloat
    let children: [Node]
    init(_ height: CGFloat, _ children: [Node] = []) { self.height = height; self.children = children }
}

///
private final class Source: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate {
    let root: [Node]
    init(_ root: [Node]) { self.root = root }
    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int { ((item as? Node)?.children ?? root).count }
    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any { ((item as? Node)?.children ?? root)[index] }
    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool { !((item as? Node)?.children.isEmpty ?? true) }
    func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat { (item as? Node)?.height ?? 1 }
    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? { NSView() }
}

@main struct SidebarTablistTests {
    typealias L = SidebarChromeLayout
    static var count = 0
    static func check(_ value: @autoclosure () -> Bool, _ message: String) {
        count += 1
        guard value() else { fatalError("SidebarTablist: \(message)") }
    }
    static let width: CGFloat = 212
    static func close(_ a: NSRect, _ b: NSRect) -> Bool {
        abs(a.minX - b.minX) < 0.001 && abs(a.minY - b.minY) < 0.001 && abs(a.width - b.width) < 0.001 && abs(a.height - b.height) < 0.001
    }

    /// TablistView's outline setup: plain style, no header, 16 per level, the
    /// 5-point base row height and (0, 1) intercell spacing.
    @MainActor fileprivate static func outline(_ nodes: [Node]) -> (TablistOutline, Source) {
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

    /// The sidebar list: one outline row per row at its level, with a view
    /// in every non-gap cell.
    @MainActor fileprivate static func list(_ rows: [L.TablistRow], levels: [Int]? = nil) -> (SidebarOutlineView, [NSView?]) {
        let list = SidebarOutlineView(frame: NSRect(x: 0, y: 0, width: width, height: 10))
        let views: [NSView?] = rows.map { row in if case .gap = row { nil } else { NSView() } }
        list.reload(rows.indices.map { SidebarOutlineEntry(key: $0, content: views[$0], row: rows[$0], level: levels?[$0] ?? 0) })
        return (list, views)
    }

    @MainActor static func main() {
        _ = NSApplication.shared
        // Every sequence of up to four rows, plus the production slot orders.
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
        for rows in sequences {
            let model = L.tablist(rows)
            let (reference, source) = outline(rows.map { row in
                switch row {
                case .item: return Node(L.tablistCellHeight)
                case .accessory(let height), .gap(let height): return Node(height)
                }
            })
            check(source.root.count == reference.numberOfRows, "one outline row per row in \(rows)")
            check(reference.frame.height == model.height, "AppKit's \(reference.frame.height) is the model's height for \(rows)")
            let (list, views) = self.list(rows)
            list.frame.size.height = list.fittingSize.height
            list.layoutSubtreeIfNeeded()
            check(abs(list.frame.height - reference.frame.height) < 0.001, "list height \(list.frame.height) for \(rows)")
            check(list.rows.count == rows.count, "one outline row per row in \(rows)")
            for (index, (row, span)) in zip(rows, model.views).enumerated() {
                let cell = reference.frameOfCell(atColumn: 0, row: index)
                check(cell.minX == 0 && cell.width == width, "cells span the outline for \(rows)")
                check(reference.rect(ofRow: index).height == cell.height + L.tablistIntercellSpacing, "the intercell gap below each cell")
                check(row.cellHeight == cell.height, "\(row)'s cell is AppKit's \(cell)")
                check(close(list.rows[index].frame, reference.rect(ofRow: index)), "outline row \(list.rows[index].frame) is AppKit's row for \(rows)")
                check(close(list.convert(list.rows[index].cell.bounds, from: list.rows[index].cell), cell), "outline cell \(index) is AppKit's for \(rows)")
                switch row {
                case .item:
                    // CellSelectionStateView centres the visible row in the cell.
                    check(span == L.TablistSpan(minY: cell.minY + (cell.height - L.tablistVisibleRowHeight) / 2,
                                                height: L.tablistVisibleRowHeight), "item \(index) centred in \(cell) for \(rows)")
                case .accessory:
                    check(span == L.TablistSpan(minY: cell.minY, height: cell.height), "accessory \(index) fills \(cell) for \(rows)")
                case .gap:
                    check(span == nil && views[index] == nil, "gap \(index) has no view for \(rows)")
                }
                guard let view = views[index], let span else { continue }
                let frame = list.convert(view.bounds, from: view)
                check(abs(frame.minY - span.minY) < 0.001 && abs(frame.height - span.height) < 0.001, "\(frame) on \(span) for \(rows)")
                check(frame.minX == 0 && frame.width == width, "views span the list for \(rows)")
            }
        }

        // Levels: with the outline cell gone and the cell moved 18 left, a
        // level-n cell starts at 16n and keeps the trailing edge, as the
        // outline's cell for a depth-n row does.
        let (tree, _) = outline([Node(40, [Node(40, [Node(40)]), Node(40)]), Node(24), Node(40)])
        let levels = (0..<tree.numberOfRows).map { tree.level(forRow: $0) }
        check(levels == [0, 1, 2, 1, 0, 0], "expanded tree")
        let (leveled, leveledViews) = list([.item, .item, .item, .item, .accessory(height: L.sectionDividerHeight), .item], levels: levels)
        leveled.frame.size.height = leveled.fittingSize.height
        leveled.layoutSubtreeIfNeeded()
        for row in 0..<tree.numberOfRows {
            let cell = tree.frameOfCell(atColumn: 0, row: row)
            check(cell.minX == CGFloat(levels[row]) * L.tablistIndentation && cell.maxX == width, "level cell \(cell)")
            check(close(leveled.convert(leveled.rows[row].cell.bounds, from: leveled.rows[row].cell), cell), "outline level cell \(row)")
            if let view = leveledViews[row] {
                let frame = leveled.convert(view.bounds, from: view)
                check(frame.minX == cell.minX && frame.maxX == width, "a level-\(levels[row]) view starts with its cell")
            }
        }

        // TablistView's scroll view with the production scroller. Six pinned
        // rows and New Tab fit a 400-point clip (290) but not with the 120-point
        // inset (410).
        let rows = L.tablistSlots(pinnedItems: 6, todayItems: 0, isPrivate: false).map(\.row)
        func scrolled(style: NSScroller.Style?, clip: CGFloat) -> (NSScrollView, NSView) {
            let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: width, height: clip))
            scroll.drawsBackground = false; scroll.adoptTablistScroller()
            if let style { scroll.scrollerStyle = style }
            let (list, _) = self.list(rows)
            scroll.documentView = list
            for _ in 0..<3 {
                list.frame = NSRect(x: 0, y: 0, width: scroll.contentSize.width, height: list.fittingSize.height)
                list.layoutSubtreeIfNeeded(); scroll.tile()
            }
            return (scroll, list)
        }
        check(L.tablist(rows).height == 410, "the overflowing list")
        let (fresh, _) = scrolled(style: nil, clip: 400)
        check(fresh.verticalScroller is SidebarTablistScroller && fresh.verticalScroller?.controlSize == .small
              && fresh.hasVerticalScroller && fresh.autohidesScrollers, "the small NoBackgroundScroller")
        // AppKit gives the scroll view the system's style, not the class's.
        check(fresh.scrollerStyle == NSScroller.preferredScrollerStyle, "system scroller style")
        check(SidebarTablistScroller.isCompatibleWithOverlayScrollers && SidebarTablistScroller.preferredScrollerStyle == .overlay,
              "overlay-compatible and preferring overlay")
        let (overlay, overlayList) = scrolled(style: .overlay, clip: 400)
        check(overlay.scrollerStyle == .overlay && overlay.contentSize.width == width && overlayList.frame.width == width,
              "overlay scrollers keep the list's width")
        let (legacy, legacyList) = scrolled(style: .legacy, clip: 400)
        check(legacy.verticalScroller?.isHidden == false && legacy.verticalScroller?.frame.width == 8, "the 8-point legacy scroller")
        check(legacy.contentSize.width == width - 8 && legacyList.frame.width == width - 8, "legacy scrollers take the 8 points")
        let (fits, fitsList) = scrolled(style: .legacy, clip: 440)
        check(fits.verticalScroller?.isHidden == true && fitsList.frame.width == width, "a list that fits with its inset keeps its width")

        // No knob slot: drawKnobSlot leaves a bitmap transparent, where a
        // legacy NSScroller paints its track.
        func slotAlpha(_ scroller: NSScroller) -> Int {
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
        let tablistScroller = SidebarTablistScroller(); tablistScroller.scrollerStyle = .legacy
        let plainScroller = NSScroller(); plainScroller.scrollerStyle = .legacy
        check(slotAlpha(tablistScroller) == 0, "no knob slot")
        check(slotAlpha(plainScroller) > 0, "AppKit's legacy slot is painted")
        print("SidebarTablist: \(count) assertions passed (system scroller style \(NSScroller.preferredScrollerStyle == .legacy ? "legacy" : "overlay"))")
    }
}
