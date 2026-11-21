import AppKit

@MainActor final class DownloadLibraryTable: NSTableView {
    var onConfirmSelection: (() -> Void)?, onPreview: (() -> Void)?, onClose: (() -> Void)?
    var onSearch: (() -> Void)?, onCopy: (() -> Void)?, onDelete: (() -> Void)?
    var makeMenu: (() -> NSMenu?)?
    var onMove: ((Bool) -> Void)?
    var canCopy: (() -> Bool)?
    var canDrag: ((IndexSet) -> Bool)?
    var prepareClick: ((Int) -> (() -> Void)?)?
    private var originalClick: (() -> Void)?
    override func mouseDown(with event: NSEvent) {
        trackOriginalClick(event) { super.mouseDown(with: event) }
    }

    func trackOriginalClick(_ event: NSEvent, tracking: () -> Void) {
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        originalClick = event.clickCount == 1 && modifiers.isEmpty
            ? prepareClick?(row(at: convert(event.locationInWindow, from: nil))) : nil
        defer { originalClick = nil }
        tracking()
    }
    @objc func activateOriginalClick() {
        let commit = originalClick; originalClick = nil
        commit?()
    }
    func retireOriginalClick() { originalClick = nil }
    override func canDragRows(with rowIndexes: IndexSet, at mouseDownPoint: NSPoint) -> Bool {
        canDrag?(rowIndexes) == true && super.canDragRows(with: rowIndexes, at: mouseDownPoint)
    }
    override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        if item.action == #selector(copy(_:)) { return canCopy?() == true }
        if item.action == #selector(selectAll(_:)) { return false }
        return super.validateUserInterfaceItem(item)
    }
    @objc func copy(_ sender: Any?) { onCopy?() }
    override func selectAll(_ sender: Any?) {}
    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        if modifiers == .command {
            if event.charactersIgnoringModifiers == "c" { onCopy?(); return }
            if event.charactersIgnoringModifiers == "f" { onSearch?(); return }
            if event.charactersIgnoringModifiers == "a" { selectAll(nil); return }
        }
        if modifiers.isEmpty || modifiers == .shift {
            if event.keyCode == 125 { onMove?(true); return }
            if event.keyCode == 126 { onMove?(false); return }
        }
        guard modifiers.isEmpty else { super.keyDown(with: event); return }
        switch event.keyCode {
        case 125: onMove?(true)
        case 126: onMove?(false)
        case 36, 76: onConfirmSelection?()
        case 49: onPreview?()
        case 53: onClose?()
        case 51, 117: onDelete?()
        default: super.keyDown(with: event)
        }
    }
    override func menu(for event: NSEvent) -> NSMenu? {
        retireOriginalClick()
        let row = row(at: convert(event.locationInWindow, from: nil))
        guard row >= 0, delegate?.tableView?(self, shouldSelectRow: row) != false else { return nil }
        if !selectedRowIndexes.contains(row) { selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false) }
        return makeMenu?()
    }
}
