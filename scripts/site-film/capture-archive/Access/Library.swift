extension LibraryView {
    func harnessIcons(_ images: [URL: NSImage]) {
        icons = images; resolvedIcons = Set(images.keys); table.reloadData()
    }
    func harnessHover(_ title: String?) {
        table.layoutSubtreeIfNeeded()
        for row in 0..<table.numberOfRows {
            guard let view = table.rowView(atRow: row, makeIfNecessary: true) as? LibraryRowView else { continue }
            let cell = view.subviews.compactMap { $0 as? LibraryItemView }.first
            view.hovered = title != nil && cell?.harnessTitle == title
        }
        table.layoutSubtreeIfNeeded()
    }
    func harnessRowFrame(_ title: String) -> NSRect? {
        table.layoutSubtreeIfNeeded()
        for row in 0..<table.numberOfRows {
            guard let view = table.rowView(atRow: row, makeIfNecessary: true) else { continue }
            if let cell = view.subviews.compactMap({ $0 as? LibraryItemView }).first, cell.harnessTitle == title {
                return convert(view.bounds, from: view)
            }
        }
        return nil
    }
    func harnessPutBackFrame(_ title: String) -> NSRect? {
        for row in 0..<table.numberOfRows {
            guard let view = table.rowView(atRow: row, makeIfNecessary: true),
                  let cell = view.subviews.compactMap({ $0 as? LibraryItemView }).first, cell.harnessTitle == title else { continue }
            return convert(cell.harnessPutBack.bounds, from: cell.harnessPutBack)
        }
        return nil
    }
    var harnessRowCount: Int { table.numberOfRows }
}

extension LibraryItemView {
    var harnessTitle: String { title.stringValue }
    var harnessPutBack: NSView { putBackButton }
}
