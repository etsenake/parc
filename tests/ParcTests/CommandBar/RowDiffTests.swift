import AppKit
import Testing
@testable import Parc

struct RowDiffTests {
    typealias Row = CommandBarRowDiff.Row

    static func rows(_ values: [(String, String)]) -> [Row] { values.map { Row(id: $0.0, content: $0.1) } }

    @Test func unchangedKeysAndContentChangeNothing() {
        let same = Self.rows([("a", "1"), ("b", "2")])
        #expect(CommandBarRowDiff(old: same, new: same).isEmpty)
    }

    @Test func aRowArrivingBetweenKeptRowsIsOneInsertion() {
        let diff = CommandBarRowDiff(old: Self.rows([("a", "1"), ("c", "3")]), new: Self.rows([("a", "1"), ("b", "2"), ("c", "3")]))
        #expect(diff.insertions == IndexSet(integer: 1))
        #expect(diff.removals.isEmpty)
        #expect(diff.changed.isEmpty)
    }

    @Test func aDifferentKeyAtAPositionIsARemovalAndAnInsertion() {
        let diff = CommandBarRowDiff(old: Self.rows([("a", "1"), ("b", "2"), ("c", "3")]), new: Self.rows([("a", "1"), ("x", "9"), ("c", "4")]))
        #expect(diff.removals == IndexSet(integer: 1))
        #expect(diff.insertions == IndexSet(integer: 1))
    }

    @Test func aKeptKeyWhoseContentChangedReloadsAtItsNewIndex() {
        let diff = CommandBarRowDiff(old: Self.rows([("a", "1"), ("b", "2"), ("c", "3")]), new: Self.rows([("a", "1"), ("x", "9"), ("c", "4")]))
        #expect(diff.changed == IndexSet(integer: 2))
    }

    @Test func clearingRemovesEveryRow() {
        #expect(CommandBarRowDiff(old: Self.rows([("a", "1")]), new: []).removals == IndexSet(integer: 0))
    }

    @Test func theSameKeyAtTheHighlightedIndexKeepsIt() {
        #expect(CommandBarRowDiff.keepsSelection(at: 1, old: ["a", "b"], new: ["a", "b", "c"]))
    }

    @Test func aMovedRowReturnsTheHighlightToTheTop() {
        #expect(!CommandBarRowDiff.keepsSelection(at: 1, old: ["a", "b"], new: ["a", "x", "b"]))
    }

    @Test func aVanishedIndexReturnsTheHighlightToTheTop() {
        #expect(!CommandBarRowDiff.keepsSelection(at: 2, old: ["a", "b", "c"], new: ["a", "b"]))
    }

    @Test func searchKeysUseTheTerms() {
        #expect(CommandBarRowDiff.searchKey("New Earth ") == CommandBarRowDiff.searchKey("new earth"))
    }

    @Test func aSearchURLCarriesTheTypedTextWhichIsWhySearchRowsKeyOnTerms() {
        let google = { (typed: String) in URL(string: "https://www.google.com/search?q=new+earth&oq=\(typed)")! }
        #expect(CommandBarRowDiff.pageKey(google("new+e")) != CommandBarRowDiff.pageKey(google("new+ea")))
    }

    @Test func pageKeysDropSchemeWwwAndABareTrailingSlash() {
        #expect(CommandBarRowDiff.pageKey(URL(string: "https://www.youtube.com/")!) == CommandBarRowDiff.pageKey(URL(string: "http://youtube.com")!))
    }

    @Test func pageKeysKeepTheQuery() {
        #expect(CommandBarRowDiff.pageKey(URL(string: "https://a.com/x?y=1")!) != CommandBarRowDiff.pageKey(URL(string: "https://a.com/x?y=2")!))
    }

    @Test func otherSchemesStayDistinct() {
        #expect(CommandBarRowDiff.pageKey(URL(string: "parc://settings")!) != CommandBarRowDiff.pageKey(URL(string: "https://settings")!))
    }
}

@MainActor
struct RowDiffTableTests {
    typealias Row = CommandBarRowDiff.Row

    final class Rows: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var titles: [String] = []
        var cellsMade = 0
        func numberOfRows(in tableView: NSTableView) -> Int { titles.count }
        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            cellsMade += 1
            return NSTextField(labelWithString: titles[row])
        }
    }

    @MainActor struct Fixture {
        let data = Rows()
        let table = NSTableView(frame: NSRect(x: 0, y: 0, width: 300, height: 250))
        let window: NSWindow
        let initial = RowDiffTests.rows([("command:New Easel", "New Easel"), ("native:search:new e", "new e"), ("native:search:new earth", "new earth")])
        let grown = RowDiffTests.rows([("command:New Easel", "New Easel"), ("native:search:new ea", "new ea"),
                                       ("native:search:new earth", "new earth"), ("native:search:new east", "new east")])
        let keptView: NSTableRowView?
        let firstView: NSTableRowView?

        init() {
            CommandBarTestSupport.prepareAppKit()
            table.addTableColumn(NSTableColumn(identifier: .init("row")))
            table.rowHeight = 50
            table.dataSource = data
            table.delegate = data
            window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 250), styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView?.addSubview(table)
            data.titles = initial.map(\.content)
            table.reloadData()
            table.layoutSubtreeIfNeeded()
            keptView = table.rowView(atRow: 2, makeIfNecessary: true)
            firstView = table.rowView(atRow: 0, makeIfNecessary: true)
            data.cellsMade = 0
        }

        func applyGrown() {
            data.titles = grown.map(\.content)
            table.apply(CommandBarRowDiff(old: initial, new: grown))
            table.layoutSubtreeIfNeeded()
        }
    }

    @Test func theTableHoldsTheNewRows() {
        let fixture = Fixture()
        fixture.applyGrown()
        #expect(fixture.table.numberOfRows == 4)
    }

    @Test func aKeptFirstRowKeepsItsView() {
        let fixture = Fixture()
        fixture.applyGrown()
        #expect(fixture.table.rowView(atRow: 0, makeIfNecessary: false) === fixture.firstView)
    }

    @Test func aKeptSuggestionKeepsItsViewAndPosition() {
        let fixture = Fixture()
        fixture.applyGrown()
        #expect(fixture.table.rowView(atRow: 2, makeIfNecessary: false) === fixture.keptView)
    }

    @Test func onlyTheTwoNewRowsGetNewCells() {
        let fixture = Fixture()
        fixture.applyGrown()
        #expect(fixture.data.cellsMade == 2)
    }

    @Test func rowsReadInTheNewOrder() {
        let fixture = Fixture()
        fixture.applyGrown()
        let titles = (0..<4).compactMap { (fixture.table.view(atColumn: 0, row: $0, makeIfNecessary: true) as? NSTextField)?.stringValue }
        #expect(titles == ["New Easel", "new ea", "new earth", "new east"])
    }

    @Test func changedContentReloadsThatCellInsideItsKeptRow() {
        let fixture = Fixture()
        fixture.applyGrown()
        fixture.data.cellsMade = 0
        let renamed = RowDiffTests.rows([("command:New Easel", "New Easel ⌃⇧E"), ("native:search:new ea", "new ea"),
                                         ("native:search:new earth", "new earth"), ("native:search:new east", "new east")])
        fixture.data.titles = renamed.map(\.content)
        fixture.table.apply(CommandBarRowDiff(old: fixture.grown, new: renamed))
        fixture.table.layoutSubtreeIfNeeded()
        #expect(fixture.data.cellsMade == 1)
        #expect(fixture.table.rowView(atRow: 0, makeIfNecessary: false) === fixture.firstView)
    }
}
