import AppKit

struct EaselMenuRow {
    var id: String
    var title: String
    var symbol: String?
    var icon: NoteIcon?
    var shortcut: String?
    var isEnabled: Bool
    var isDestructive: Bool
    var isChecked: Bool
    var separatorBefore: Bool
    var children: [EaselMenuRow]
    var perform: (() -> Void)?

    init(id: String, title: String, symbol: String? = nil, icon: NoteIcon? = nil, shortcut: String? = nil, isEnabled: Bool = true,
         isDestructive: Bool = false, isChecked: Bool = false, separatorBefore: Bool = false,
         children: [EaselMenuRow] = [], perform: (() -> Void)? = nil) {
        self.id = id; self.title = title; self.symbol = symbol; self.icon = icon; self.shortcut = shortcut
        self.isEnabled = isEnabled; self.isDestructive = isDestructive; self.isChecked = isChecked
        self.separatorBefore = separatorBefore; self.children = children; self.perform = perform
    }
}

struct EaselMenuContext {
    enum Target: Equatable { case canvas, object, objects }
    let target: Target
    let items: [EaselItem]
    let point: EaselPoint
}

@MainActor
protocol EaselCanvasMenuSlots {
    func modeMenuRows(_ context: EaselMenuContext) -> [EaselMenuRow]?
    func sectionMenuRows(_ context: EaselMenuContext) -> [EaselMenuRow]
    func shapeMenuRows(_ context: EaselMenuContext) -> [EaselMenuRow]
    func transformMenuRows(_ context: EaselMenuContext) -> [EaselMenuRow]
    func textMenuRows(_ context: EaselMenuContext) -> [EaselMenuRow]
    func linkMenuRows(_ context: EaselMenuContext) -> [EaselMenuRow]
    func styleMenuRows(_ context: EaselMenuContext) -> [EaselMenuRow]
    func connectorMenuRows(_ context: EaselMenuContext) -> [EaselMenuRow]
    func mediaMenuRows(_ context: EaselMenuContext) -> [EaselMenuRow]
    func tableMenuRows(_ context: EaselMenuContext) -> [EaselMenuRow]
    func codeMenuRows(_ context: EaselMenuContext) -> [EaselMenuRow]
    func drawingMenuRows(_ context: EaselMenuContext) -> [EaselMenuRow]
    func stampMenuRows(_ context: EaselMenuContext) -> [EaselMenuRow]
    func zoomMenuRows(_ context: EaselMenuContext) -> [EaselMenuRow]
    func boardMenuRows(_ context: EaselMenuContext) -> [EaselMenuRow]
}

extension EaselCanvasMenuSlots {
    func modeMenuRows(_ context: EaselMenuContext) -> [EaselMenuRow]? { nil }
    func sectionMenuRows(_ context: EaselMenuContext) -> [EaselMenuRow] { [] }
    func shapeMenuRows(_ context: EaselMenuContext) -> [EaselMenuRow] { [] }
    func transformMenuRows(_ context: EaselMenuContext) -> [EaselMenuRow] { [] }
    func textMenuRows(_ context: EaselMenuContext) -> [EaselMenuRow] { [] }
    func linkMenuRows(_ context: EaselMenuContext) -> [EaselMenuRow] { [] }
    func styleMenuRows(_ context: EaselMenuContext) -> [EaselMenuRow] { [] }
    func connectorMenuRows(_ context: EaselMenuContext) -> [EaselMenuRow] { [] }
    func mediaMenuRows(_ context: EaselMenuContext) -> [EaselMenuRow] { [] }
    func tableMenuRows(_ context: EaselMenuContext) -> [EaselMenuRow] { [] }
    func codeMenuRows(_ context: EaselMenuContext) -> [EaselMenuRow] { [] }
    func drawingMenuRows(_ context: EaselMenuContext) -> [EaselMenuRow] { [] }
    func stampMenuRows(_ context: EaselMenuContext) -> [EaselMenuRow] { [] }
    func zoomMenuRows(_ context: EaselMenuContext) -> [EaselMenuRow] { [] }
    func boardMenuRows(_ context: EaselMenuContext) -> [EaselMenuRow] { [] }
}

extension EaselCanvasView: EaselCanvasMenuSlots {}

@MainActor
final class EaselCanvasMenuPresenter {
    private var popover: NotePagePopover?
    private var submenu: NotePagePopover?

    var isOpen: Bool { popover?.isOpen == true }

    func close(animated: Bool = true) {
        submenu?.close(animated: animated)
        popover?.close(animated: animated)
    }

    func present(_ rows: [EaselMenuRow], in host: NSView, anchor: NSRect, origin: NoteMenuList.Origin, label: String) {
        close(animated: false)
        let list = NoteMenuList(items: Self.items(rows))
        list.minimumWidth = 220
        list.maximumHeight = 560
        list.setAccessibilityLabel(label)
        list.prepare(origin: origin)
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
        if origin == .keyboard { list.moveHighlight(by: 1) }
    }

    private func activate(_ row: EaselMenuRow, from list: NoteMenuList, host: NSView) {
        guard row.isEnabled else { return }
        if !row.children.isEmpty { openSubmenu(row, from: list, host: host); return }
        close()
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
            self.close()
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

    static func items(_ rows: [EaselMenuRow]) -> [NoteMenuList.Item] {
        rows.enumerated().map { index, row in
            var item = NoteMenuList.Item(id: row.id, title: row.title, icon: row.icon ?? row.symbol.map { .symbol($0) }, shortcut: row.shortcut)
            item.isEnabled = row.isEnabled && (row.perform != nil || !row.children.isEmpty)
            item.isDestructive = row.isDestructive
            item.isChecked = row.isChecked
            item.hasSubmenu = !row.children.isEmpty
            item.separatorBefore = index > 0 && row.separatorBefore
            return item
        }
    }

    static func flattened(_ sections: [[EaselMenuRow]]) -> [EaselMenuRow] {
        var result: [EaselMenuRow] = []
        for section in sections where !section.isEmpty {
            for (index, row) in section.enumerated() {
                var placed = row
                placed.separatorBefore = index == 0 ? !result.isEmpty : row.separatorBefore
                result.append(placed)
            }
        }
        return result
    }
}

extension EaselCanvasView {
    var menuHost: NSView { enclosingScrollView?.superview ?? superview ?? self }

    func presentMenu(_ sections: [[EaselMenuRow]], anchor: NSRect, origin: NoteMenuList.Origin, label: String) {
        let rows = EaselCanvasMenuPresenter.flattened(sections)
        guard !rows.isEmpty, window != nil else { return }
        let presenter = arrangeState.menu ?? EaselCanvasMenuPresenter()
        arrangeState.menu = presenter
        let host = menuHost
        presenter.present(rows, in: host, anchor: host.convert(anchor, from: self), origin: origin, label: label)
    }

    func guardedMenuAction(_ action: @escaping (EaselCanvasView) -> Void) -> () -> Void {
        let captured = selection
        return { [weak self, weak owner = window] in
            guard let self, let owner, self.window === owner, self.selection == captured,
                  !self.session.isClosed, !self.session.isDeleted else { return }
            action(self)
        }
    }

    func presentUnlockMenu(for item: EaselItem) {
        let id = item.id
        let unlockIDs = item.groupID.map { EaselArrange.members(of: $0, in: session.document) } ?? [id]
        let unlock = EaselMenuRow(id: "unlock", title: unlockIDs.count > 1 ? "Unlock Group" : "Unlock", symbol: "lock.open",
                                  shortcut: "⇧⌘L", perform: guardedMenuAction { canvas in
            guard canvas.setLock(false, ids: unlockIDs) else { return }
            canvas.selection = unlockIDs.intersection(Set(canvas.session.document.items.map(\.id)))
        })
        presentMenu([[unlock]], anchor: lockBadgeRect(for: item), origin: NSApp.currentEvent?.type == .keyDown ? .keyboard : .pointer,
                    label: "Locked object")
    }
}
