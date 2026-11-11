import AppKit

final class CommandResultsTable: NSTableView {
    var onKey: ((NSEvent) -> Bool)?

    func fit(in scroll: NSScrollView, rowCount: Int) {
        guard let column = tableColumns.first else { return }
        let height = CGFloat(rowCount) * rowHeight
        column.width = scroll.contentSize.width
        frame = NSRect(x: 0, y: 0, width: scroll.contentSize.width, height: height)
        scroll.layoutSubtreeIfNeeded()
        let extraWidth = max(0, frame.width - column.width)
        column.width = max(0, scroll.contentSize.width - extraWidth)
        let origin = scroll.contentView.bounds.origin
        if origin.x != 0 {
            scroll.contentView.setBoundsOrigin(NSPoint(x: 0, y: origin.y))
            scroll.reflectScrolledClipView(scroll.contentView)
        }
    }

    func keyboardSelectionRow(moving delta: Int, wrapping: Bool) -> Int? {
        guard numberOfRows > 0, delta == -1 || delta == 1 else { return nil }
        let last = numberOfRows - 1
        if delta > 0 {
            return selectedRow >= last ? (wrapping ? 0 : last) : max(0, selectedRow + 1)
        }
        return selectedRow <= 0 ? (wrapping ? last : 0) : min(last, selectedRow - 1)
    }
    override func keyDown(with event: NSEvent) { if onKey?(event) != true { super.keyDown(with: event) } }
}
