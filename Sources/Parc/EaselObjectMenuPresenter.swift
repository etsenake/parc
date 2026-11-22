import AppKit

@MainActor
final class EaselObjectMenuPresenter: EaselCanvasMenuPresenting {
    private var popover: NotePagePopover?
    private var submenu: NotePagePopover?

    var isOpen: Bool { popover?.isOpen == true }

    func close(animated: Bool) {
        submenu?.close(animated: animated)
        popover?.close(animated: animated)
    }

    func present(_ rows: [EaselMenuRow], in host: NSView, anchor: NSRect, keyboard: Bool, label: String) {
        close(animated: false)
        let list = NoteMenuList(items: Self.items(rows))
        list.minimumWidth = 220
        list.maximumHeight = 560
        list.setAccessibilityLabel(label)
        list.prepare(origin: keyboard ? .keyboard : .pointer)
        let popover = NotePagePopover(content: list)
        popover.onKeyDown = { [weak list] event in list?.handleKeyDown(event) ?? false }
        popover.onClose = { [weak self, weak popover] in
            guard let self, self.popover === popover else { return }
            self.popover = nil
        }
        list.onActivate = { [weak self, weak list] item in
            guard let self, let list, let row = rows.first(where: { $0.id == item.id }) else { return }
            self.activate(row, from: list, host: host)
        }
        list.onCancel = { [weak popover] in popover?.close() }
        self.popover = popover
        popover.present(in: host, anchor: anchor, edge: .below, alignment: .leading)
        if keyboard { list.moveHighlight(by: 1) }
    }

    private func activate(_ row: EaselMenuRow, from list: NoteMenuList, host: NSView) {
        guard row.isEnabled else { return }
        if !row.children.isEmpty { openSubmenu(row, from: list, host: host); return }
        close(animated: true)
        row.perform?()
    }

    private func openSubmenu(_ row: EaselMenuRow, from list: NoteMenuList, host: NSView) {
        guard let popover, popover.isOpen else { return }
        submenu?.close(animated: false)
        let child = NoteMenuList(items: Self.items(row.children))
        child.minimumWidth = 200
        child.setAccessibilityLabel(row.title)
        let panel = NotePagePopover(content: child, parent: popover)
        child.onActivate = { [weak self] item in
            guard let self, let picked = row.children.first(where: { $0.id == item.id }), picked.isEnabled else { return }
            self.close(animated: true)
            picked.perform?()
        }
        child.onCancel = { [weak panel] in panel?.close() }
        child.onCollapse = { [weak panel] in panel?.close() }
        panel.onKeyDown = { [weak child] event in child?.handleKeyDown(event) ?? false }
        panel.onClose = { [weak self, weak panel] in
            guard let self, self.submenu === panel else { return }
            self.submenu = nil
        }
        submenu = panel
        let frame = popover.panel.frame
        let rowRect = Self.rowRect(of: row.id, in: list).map { host.convert($0, from: list) }
            ?? NSRect(x: frame.minX, y: frame.midY, width: frame.width, height: 30)
        panel.present(in: host, anchor: NSRect(x: frame.minX, y: rowRect.minY, width: frame.width, height: rowRect.height), edge: .trailing)
        if NSApp.currentEvent?.type == .keyDown { child.prepare(origin: .keyboard); child.moveHighlight(by: 1) }
    }

    private static func rowRect(of id: String, in list: NoteMenuList) -> NSRect? {
        let visible = list.visibleItems
        guard let index = visible.firstIndex(where: { $0.id == id }) else { return nil }
        let separators = visible.prefix(index + 1).enumerated().filter { $0.offset > 0 && $0.element.separatorBefore }.count
        let y = NoteTheme.menuInset + CGFloat(index) * list.rowHeight + CGFloat(separators) * NoteTheme.menuSeparatorSlot
        return NSRect(x: NoteTheme.menuInset, y: y, width: list.frame.width - NoteTheme.menuInset * 2, height: list.rowHeight)
    }

    private static func items(_ rows: [EaselMenuRow]) -> [NoteMenuList.Item] {
        rows.enumerated().map { index, row in
            let icon: NoteIcon? = row.glyph.map { .glyph($0) } ?? row.symbol.map { .symbol($0) }
            var item = NoteMenuList.Item(id: row.id, title: row.title, icon: icon, shortcut: row.shortcut)
            item.isEnabled = row.isEnabled && (row.perform != nil || !row.children.isEmpty)
            item.isDestructive = row.isDestructive
            item.isChecked = row.isChecked
            item.hasSubmenu = !row.children.isEmpty
            item.separatorBefore = index > 0 && row.separatorBefore
            return item
        }
    }
}
