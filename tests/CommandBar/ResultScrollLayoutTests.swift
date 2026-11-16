import AppKit

@MainActor private final class Rows: NSObject, NSTableViewDataSource {
    var count = 0
    func numberOfRows(in tableView: NSTableView) -> Int { count }
}

@main @MainActor struct ResultScrollLayoutTests {
    static func main() { exitOnFailure(runChecks) }
    static func runChecks() {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let rows = Rows()
        var checks = 0
        for style in [NSTableView.Style.automatic, .plain, .inset, .fullWidth] {
            for scrollerStyle in [NSScroller.Style.legacy, .overlay] {
                let table = CommandResultsTable(), scroll = CommandResultsScrollView()
                table.style = style
                table.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("suggestion")))
                table.headerView = nil; table.rowHeight = 50; table.intercellSpacing = .zero; table.dataSource = rows
                scroll.drawsBackground = false; scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
                scroll.hasHorizontalScroller = false; scroll.horizontalScrollElasticity = .none
                scroll.scrollerStyle = scrollerStyle; scroll.documentView = table
                for width: CGFloat in [180, 300, 520, 180] {
                    for count in [1, 25, 0] {
                        rows.count = count; table.reloadData()
                        scroll.frame = NSRect(x: 0, y: 0, width: width, height: 180)
                        table.fit(in: scroll, rowCount: count)
                        scroll.layoutSubtreeIfNeeded()
                        precondition(abs(table.frame.width - scroll.contentSize.width) < 0.01,
                                     "Table must fit its viewport, style \(style.rawValue), count \(count)")
                        precondition(scroll.contentView.bounds.origin.x == 0, "Clip must not retain a sideways offset")
                        let reserve = scrollerStyle == .legacy ? NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy) : 0
                        precondition(scroll.contentView.frame.width == width - reserve && scroll.scrollerReserve == reserve,
                                     "Permanent scroll bars keep their width reserved whatever the row count, count \(count), width \(width)")
                        checks += 3
                        if count == 25 {
                            precondition(table.frame.height > scroll.contentSize.height, "Long lists remain vertically scrollable")
                            scroll.contentView.scroll(to: NSPoint(x: 30, y: 100))
                            table.fit(in: scroll, rowCount: count)
                            scroll.layoutSubtreeIfNeeded()
                            precondition(scroll.contentView.bounds.origin.x == 0, "Fitting clears a retained sideways offset")
                            precondition(scroll.contentView.bounds.origin.y == 100, "Fitting preserves vertical scroll")
                            checks += 3
                        }
                    }
                }
            }
        }
        print("PASS: \(checks) result scroll layout assertions")
    }
}
