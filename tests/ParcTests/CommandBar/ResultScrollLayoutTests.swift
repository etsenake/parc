import AppKit
import Testing
@testable import Parc

@MainActor
struct ResultScrollLayoutTests {
    struct Layout: Sendable, CustomTestStringConvertible {
        let style: Int
        let scroller: Int
        let width: CGFloat
        let rows: Int
        var testDescription: String { "style \(style), scroller \(scroller), width \(width), rows \(rows)" }
    }

    nonisolated static let layouts: [Layout] = [0, 1, 2, 4].flatMap { style in
        [1, 0].flatMap { scroller in
            [180, 300, 520].flatMap { width in
                [1, 25, 0].map { Layout(style: style, scroller: scroller, width: CGFloat(width), rows: $0) }
            }
        }
    }

    nonisolated static let scrollingLayouts = layouts.filter { $0.rows == 25 }

    final class Rows: NSObject, NSTableViewDataSource {
        var count = 0
        func numberOfRows(in tableView: NSTableView) -> Int { count }
    }

    @MainActor struct Fixture {
        let rows = Rows()
        let table = CommandResultsTable()
        let scroll = CommandResultsScrollView()
        let layout: Layout

        init(_ layout: Layout) {
            CommandBarTestSupport.prepareAppKit()
            self.layout = layout
            table.style = NSTableView.Style(rawValue: layout.style) ?? .automatic
            table.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("suggestion")))
            table.headerView = nil
            table.rowHeight = 50
            table.intercellSpacing = .zero
            table.dataSource = rows
            scroll.drawsBackground = false
            scroll.hasVerticalScroller = true
            scroll.autohidesScrollers = true
            scroll.hasHorizontalScroller = false
            scroll.horizontalScrollElasticity = .none
            scroll.scrollerStyle = NSScroller.Style(rawValue: layout.scroller) ?? .legacy
            scroll.documentView = table
            rows.count = layout.rows
            table.reloadData()
            scroll.frame = NSRect(x: 0, y: 0, width: layout.width, height: 180)
            table.fit(in: scroll, rowCount: layout.rows)
            scroll.layoutSubtreeIfNeeded()
        }
    }

    @Test(arguments: layouts)
    func theTableFitsItsViewport(layout: Layout) {
        let fixture = Fixture(layout)
        #expect(abs(fixture.table.frame.width - fixture.scroll.contentSize.width) < 0.01)
    }

    @Test(arguments: layouts)
    func theClipKeepsNoSidewaysOffset(layout: Layout) {
        #expect(Fixture(layout).scroll.contentView.bounds.origin.x == 0)
    }

    @Test(arguments: layouts)
    func permanentScrollBarsKeepTheirWidthReservedWhateverTheRowCount(layout: Layout) {
        let fixture = Fixture(layout)
        let legacy = fixture.scroll.scrollerStyle == .legacy
        let reserve = legacy ? NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy) : 0
        #expect(fixture.scroll.contentView.frame.width == layout.width - reserve)
        #expect(fixture.scroll.scrollerReserve == reserve)
    }

    @Test(arguments: scrollingLayouts)
    func longListsRemainVerticallyScrollable(layout: Layout) {
        let fixture = Fixture(layout)
        #expect(fixture.table.frame.height > fixture.scroll.contentSize.height)
    }

    @Test(arguments: scrollingLayouts)
    func fittingClearsARetainedSidewaysOffset(layout: Layout) {
        let fixture = Fixture(layout)
        fixture.scroll.contentView.scroll(to: NSPoint(x: 30, y: 100))
        fixture.table.fit(in: fixture.scroll, rowCount: layout.rows)
        fixture.scroll.layoutSubtreeIfNeeded()
        #expect(fixture.scroll.contentView.bounds.origin.x == 0)
    }

    @Test(arguments: scrollingLayouts)
    func fittingPreservesVerticalScroll(layout: Layout) {
        let fixture = Fixture(layout)
        fixture.scroll.contentView.scroll(to: NSPoint(x: 30, y: 100))
        fixture.table.fit(in: fixture.scroll, rowCount: layout.rows)
        fixture.scroll.layoutSubtreeIfNeeded()
        #expect(fixture.scroll.contentView.bounds.origin.y == 100)
    }
}
