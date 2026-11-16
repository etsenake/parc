import AppKit

@main @MainActor struct RowDiffTests {
    final class Rows: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var titles: [String] = []
        var cellsMade = 0
        func numberOfRows(in tableView: NSTableView) -> Int { titles.count }
        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            cellsMade += 1
            return NSTextField(labelWithString: titles[row])
        }
    }
    static func main() { exitOnFailure(runChecks) }
    static func runChecks() {
        _ = NSApplication.shared
        var count = 0
        func expect(_ value: @autoclosure () -> Bool, _ message: String) {
            count += 1; precondition(value(), message)
        }
        typealias Row = CommandBarRowDiff.Row
        func rows(_ values: [(String, String)]) -> [Row] { values.map { Row(id: $0.0, content: $0.1) } }

        let same = CommandBarRowDiff(old: rows([("a", "1"), ("b", "2")]), new: rows([("a", "1"), ("b", "2")]))
        expect(same.isEmpty, "unchanged keys and content change nothing")
        let inserted = CommandBarRowDiff(old: rows([("a", "1"), ("c", "3")]), new: rows([("a", "1"), ("b", "2"), ("c", "3")]))
        expect(inserted.insertions == IndexSet(integer: 1) && inserted.removals.isEmpty && inserted.changed.isEmpty,
               "a row arriving between kept rows is one insertion")
        let replaced = CommandBarRowDiff(old: rows([("a", "1"), ("b", "2"), ("c", "3")]), new: rows([("a", "1"), ("x", "9"), ("c", "4")]))
        expect(replaced.removals == IndexSet(integer: 1) && replaced.insertions == IndexSet(integer: 1),
               "a different key at a position is a removal and an insertion")
        expect(replaced.changed == IndexSet(integer: 2), "a kept key whose content changed is reloaded at its new index")
        let emptied = CommandBarRowDiff(old: rows([("a", "1")]), new: [])
        expect(emptied.removals == IndexSet(integer: 0), "clearing removes every row")

        expect(CommandBarRowDiff.keepsSelection(at: 1, old: ["a", "b"], new: ["a", "b", "c"]), "same key at the highlighted index keeps it")
        expect(!CommandBarRowDiff.keepsSelection(at: 1, old: ["a", "b"], new: ["a", "x", "b"]), "a moved row returns the highlight to the top")
        expect(!CommandBarRowDiff.keepsSelection(at: 2, old: ["a", "b", "c"], new: ["a", "b"]), "a vanished index returns to the top")

        let google = { (typed: String) in URL(string: "https://www.google.com/search?q=new+earth&oq=\(typed)")! }
        expect(CommandBarRowDiff.searchKey("New Earth ") == CommandBarRowDiff.searchKey("new earth"), "search keys use the terms")
        expect(CommandBarRowDiff.pageKey(google("new+e")) != CommandBarRowDiff.pageKey(google("new+ea")),
               "a search URL carries the typed text, which is why search rows key on terms")
        expect(CommandBarRowDiff.pageKey(URL(string: "https://www.youtube.com/")!) == CommandBarRowDiff.pageKey(URL(string: "http://youtube.com")!),
               "page keys drop scheme, www and a bare trailing slash")
        expect(CommandBarRowDiff.pageKey(URL(string: "https://a.com/x?y=1")!) != CommandBarRowDiff.pageKey(URL(string: "https://a.com/x?y=2")!),
               "page keys keep the query")
        expect(CommandBarRowDiff.pageKey(URL(string: "parc://settings")!) != CommandBarRowDiff.pageKey(URL(string: "https://settings")!),
               "other schemes stay distinct")

        let data = Rows()
        let table = NSTableView(frame: NSRect(x: 0, y: 0, width: 300, height: 250))
        table.addTableColumn(NSTableColumn(identifier: .init("row")))
        table.rowHeight = 50; table.dataSource = data; table.delegate = data
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 250), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView?.addSubview(table)
        var presented = rows([("command:New Easel", "New Easel"), ("native:search:new e", "new e"), ("native:search:new earth", "new earth")])
        data.titles = presented.map(\.content)
        table.reloadData(); table.layoutSubtreeIfNeeded()
        let keptView = table.rowView(atRow: 2, makeIfNecessary: true)
        let firstView = table.rowView(atRow: 0, makeIfNecessary: true)
        data.cellsMade = 0
        let next = rows([("command:New Easel", "New Easel"), ("native:search:new ea", "new ea"),
                         ("native:search:new earth", "new earth"), ("native:search:new east", "new east")])
        let diff = CommandBarRowDiff(old: presented, new: next)
        presented = next; data.titles = next.map(\.content)
        table.apply(diff); table.layoutSubtreeIfNeeded()
        expect(table.numberOfRows == 4, "the table holds the new rows")
        expect(table.rowView(atRow: 0, makeIfNecessary: false) === firstView, "the kept first row keeps its view")
        expect(table.rowView(atRow: 2, makeIfNecessary: false) === keptView, "a kept suggestion keeps its view and position")
        expect(data.cellsMade == 2, "only the two new rows get new cells")
        let titles = (0..<4).compactMap { (table.view(atColumn: 0, row: $0, makeIfNecessary: true) as? NSTextField)?.stringValue }
        expect(titles == ["New Easel", "new ea", "new earth", "new east"], "rows read in the new order")

        data.cellsMade = 0
        let renamed = rows([("command:New Easel", "New Easel ⌃⇧E"), ("native:search:new ea", "new ea"),
                            ("native:search:new earth", "new earth"), ("native:search:new east", "new east")])
        data.titles = renamed.map(\.content)
        table.apply(CommandBarRowDiff(old: presented, new: renamed)); table.layoutSubtreeIfNeeded()
        expect(data.cellsMade == 1 && table.rowView(atRow: 0, makeIfNecessary: false) === firstView,
               "changed content reloads that cell inside its kept row")
        print("RowDiffTests: \(count) assertions passed")
    }
}
