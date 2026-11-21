import AppKit

struct EaselMenuRow {
    var id: String
    var title: String
    var symbol: String?
    var glyph: String?
    var shortcut: String?
    var isEnabled: Bool
    var isDestructive: Bool
    var isChecked: Bool
    var separatorBefore: Bool
    var children: [EaselMenuRow]
    var perform: (() -> Void)?

    init(id: String, title: String, symbol: String? = nil, glyph: String? = nil, shortcut: String? = nil, isEnabled: Bool = true,
         isDestructive: Bool = false, isChecked: Bool = false, separatorBefore: Bool = false,
         children: [EaselMenuRow] = [], perform: (() -> Void)? = nil) {
        self.id = id; self.title = title; self.symbol = symbol; self.glyph = glyph; self.shortcut = shortcut
        self.isEnabled = isEnabled; self.isDestructive = isDestructive; self.isChecked = isChecked
        self.separatorBefore = separatorBefore; self.children = children; self.perform = perform
    }

    @MainActor static func bridging(_ items: [NSMenuItem], prefix: String, anchors: [NSMenuItem]? = nil) -> [EaselMenuRow] {
        let keep = anchors ?? items
        var rows: [EaselMenuRow] = []
        var pendingSeparator = false
        for (index, item) in items.enumerated() where !item.isHidden {
            if item.isSeparatorItem { pendingSeparator = !rows.isEmpty; continue }
            let id = prefix + "-" + String(index)
            let enabled = (item.target as? NSMenuItemValidation)?.validateMenuItem(item) ?? item.isEnabled
            var row = EaselMenuRow(id: id, title: item.title, isEnabled: enabled, isChecked: item.state == .on,
                                   separatorBefore: pendingSeparator,
                                   children: item.submenu.map { bridging($0.items, prefix: id, anchors: keep) } ?? [])
            if let action = item.action {
                row.perform = { _ = keep; _ = NSApp.sendAction(action, to: item.target, from: item) }
            }
            pendingSeparator = false
            rows.append(row)
        }
        return rows
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

struct EaselMenuContext {
    enum Target: Equatable { case canvas, object, objects }
    let target: Target
    let items: [EaselItem]
    let point: EaselPoint
}

@MainActor
protocol EaselCanvasMenuPresenting: AnyObject {
    var isOpen: Bool { get }
    func present(_ rows: [EaselMenuRow], in host: NSView, anchor: NSRect, keyboard: Bool, label: String)
    func close(animated: Bool)
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
    func equationMenuRows(_ context: EaselMenuContext) -> [EaselMenuRow]
    func drawingMenuRows(_ context: EaselMenuContext) -> [EaselMenuRow]
    func stampMenuRows(_ context: EaselMenuContext) -> [EaselMenuRow]
    func zoomMenuRows(_ context: EaselMenuContext) -> [EaselMenuRow]
    func boardMenuRows(_ context: EaselMenuContext) -> [EaselMenuRow]
    func pageMenuRows(_ context: EaselMenuContext) -> [EaselMenuRow]
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
    func equationMenuRows(_ context: EaselMenuContext) -> [EaselMenuRow] { [] }
    func drawingMenuRows(_ context: EaselMenuContext) -> [EaselMenuRow] { [] }
    func stampMenuRows(_ context: EaselMenuContext) -> [EaselMenuRow] { [] }
    func zoomMenuRows(_ context: EaselMenuContext) -> [EaselMenuRow] { [] }
    func boardMenuRows(_ context: EaselMenuContext) -> [EaselMenuRow] { [] }
    func pageMenuRows(_ context: EaselMenuContext) -> [EaselMenuRow] { [] }
}

extension EaselCanvasView: EaselCanvasMenuSlots {}

extension EaselCanvasView {
    static var menuPresenterFactory: (@MainActor () -> EaselCanvasMenuPresenting)?

    var menuHost: NSView { selectionToolbarContainer ?? enclosingScrollView?.superview ?? superview ?? self }

    func presentMenu(_ sections: [[EaselMenuRow]], anchor: NSRect, keyboard: Bool, label: String) {
        let rows = EaselMenuRow.flattened(sections)
        guard !rows.isEmpty, window != nil, let presenter = arrangeState.menu ?? Self.menuPresenterFactory?() else { return }
        arrangeState.menu = presenter
        let host = menuHost
        presenter.present(rows, in: host, anchor: host.convert(anchor, from: self), keyboard: keyboard, label: label)
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
        let unlockIDs = item.groupID.map { EaselArrange.members(of: $0, in: session.document) } ?? [item.id]
        let unlock = EaselMenuRow(id: "unlock", title: unlockIDs.count > 1 ? "Unlock Group" : "Unlock", symbol: "lock.open",
                                  perform: guardedMenuAction { canvas in
            guard canvas.setLock(false, ids: unlockIDs) else { return }
            canvas.selection = unlockIDs.intersection(Set(canvas.session.document.items.map(\.id)))
        })
        presentMenu([[unlock]], anchor: lockBadgeRect(for: item), keyboard: NSApp.currentEvent?.type == .keyDown,
                    label: unlockIDs.count > 1 ? "Locked group" : "Locked object")
    }

    override func rightMouseDown(with event: NSEvent) {
        presentContextMenu(for: event)
    }

    func presentContextMenu(for event: NSEvent) {
        hoveredObjectID = nil
        cancelPointerInteraction()
        guard !session.isClosed, !session.isDeleted, finishEditing() else { return }
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)
        if let hit = object(at: point, includingLocked: true) {
            if !selection.contains(hit.id) {
                if let group = hit.groupID, !isInside(group: group) {
                    arrangeState.enteredGroup = nil
                    selection = EaselArrange.members(of: group, in: session.document)
                } else {
                    selection = [hit.id]
                }
            }
        } else {
            arrangeState.enteredGroup = nil
            selection = []
        }
        presentContextMenu(at: point, keyboard: false)
    }

    func presentContextMenu(at point: NSPoint, keyboard: Bool) {
        let objects = selectedObjects
        let context = EaselMenuContext(target: objects.isEmpty ? .canvas : objects.count == 1 ? .object : .objects,
                                       items: objects, point: EaselPoint(x: point.x, y: point.y))
        let sections = modeMenuRows(context).map { [$0] } ?? contextMenuSections(context)
        let label = context.target == .canvas ? "Easel" : objects.count == 1 ? "Object" : "\(objects.count) objects"
        presentMenu(sections, anchor: NSRect(x: point.x, y: point.y, width: 1, height: 1), keyboard: keyboard, label: label)
    }

    func contextMenuSections(_ context: EaselMenuContext) -> [[EaselMenuRow]] {
        func row(_ id: String, _ title: String, _ symbol: String?, _ shortcut: String? = nil, enabled: Bool = true,
                 destructive: Bool = false, _ action: @escaping (EaselCanvasView) -> Void) -> EaselMenuRow {
            EaselMenuRow(id: id, title: title, symbol: symbol, shortcut: shortcut, isEnabled: enabled, isDestructive: destructive,
                         perform: guardedMenuAction(action))
        }
        let document = session.document
        let ids = Set(context.items.map(\.id))
        let point = NSPoint(x: context.point.x, y: context.point.y)
        let pasteable = canPasteObjects
        let pastesHere = NSPasteboard.general.availableType(from: [Self.objectsPasteboardType]) != nil
        let plain = NSPasteboard.general.availableType(from: [.string, .URL, .rtfd, .rtf]) != nil
        let guides = EaselMenuRow(id: "guides", title: "Use Alignment Guides", symbol: "ruler", isChecked: alignmentGuidesEnabled,
                                  perform: guardedMenuAction { canvas in
            canvas.alignmentGuidesEnabled.toggle()
            canvas.invalidateIncrementalDisplay()
        })
        let selectAll = row("select-all", "Select All", "rectangle.dashed", "⌘A") { $0.selectAll(nil) }
        guard context.target != .canvas else {
            return [
                [row("paste-here", pastesHere ? "Paste Here" : "Paste", "doc.on.clipboard", "⌘V", enabled: pasteable) { $0.pasteHere(point) },
                 row("paste-plain", "Paste as Plain Text", "doc.plaintext", enabled: plain) { $0.pastePlainText(at: point) }],
                [selectAll] + zoomMenuRows(context) + boardMenuRows(context) + mindMapMenuRows(context) + pageMenuRows(context),
                [guides],
            ]
        }
        let removable = !removableIDs(for: ids).isEmpty
        let edit = [
            row("cut", "Cut", "scissors", "⌘X", enabled: removable) { $0.cutSelection() },
            row("copy", "Copy", "doc.on.doc", "⌘C") { $0.copySelection() },
            row("paste", "Paste", "doc.on.clipboard", "⌘V", enabled: pasteable) { $0.pasteHere(nil) },
            row("paste-plain", "Paste as Plain Text", "doc.plaintext", enabled: plain) { $0.pastePlainText(at: nil) },
            row("duplicate", "Duplicate", "plus.square.on.square", "⌘D") { $0.duplicateSelection() },
            row("delete", "Delete", "trash", "⌫", enabled: removable, destructive: true) { $0.deleteSelection() },
        ]
        var arrange = [EaselMenuRow(id: "order", title: "Order", symbol: "square.3.layers.3d",
                                    isEnabled: EaselArrange.canMoveLayer(ids, in: document),
                                    children: EaselLayerMove.allCases.map { move in
            row("layer-" + move.rawValue, move.title, move.symbol, move.shortcut) { $0.moveLayer(move) }
        })]
        if context.target == .objects {
            var children = EaselAlignment.allCases.map { alignment in
                row("align-" + alignment.rawValue, alignment.title, alignment.symbol) { $0.alignSelection(alignment) }
            }
            let distributable = EaselArrange.canDistribute(ids, in: document)
            for (index, axis) in EaselAxis.allCases.enumerated() {
                var item = row("distribute-" + axis.rawValue, axis.distributeTitle, axis.symbol, enabled: distributable) {
                    $0.distributeSelection(axis)
                }
                item.separatorBefore = index == 0
                children.append(item)
            }
            arrange.append(EaselMenuRow(id: "align", title: "Align and Distribute", symbol: "align.horizontal.left",
                                        isEnabled: EaselArrange.canAlign(ids, in: document), children: children))
            if EaselArrange.canTidy(ids, in: document) {
                arrange.append(row("tidy", "Tidy Up", "square.grid.2x2") { $0.tidyUpSelection() })
            }
        }
        if EaselArrange.canGroup(ids, in: document) {
            arrange.append(row("group", "Group", "rectangle.3.group", "⌘G") { $0.groupSelection() })
        }
        if EaselArrange.canUngroup(ids, in: document) {
            arrange.append(row("ungroup", "Ungroup", "rectangle.3.group.fill", "⇧⌘G") { $0.ungroupSelection() })
        }
        let locking = EaselArrange.shouldLock(ids, in: document)
        arrange.append(row("lock", locking ? "Lock" : "Unlock", locking ? "lock" : "lock.open", "⇧⌘L") { $0.toggleLock() })
        arrange += sectionMenuRows(context) + shapeMenuRows(context) + transformMenuRows(context) + pageMenuRows(context)
        var object: [EaselMenuRow] = []
        if context.target == .object, let item = context.items.first, let raw = item.url, !item.kind.holdsText {
            if pageObjects != nil, fixedCanvasSize == nil, EaselWebItemChrome.canMakeLive(item) {
                let live = item.liveCapture == true
                object.append(row("live", live ? "Back to Snapshot" : "Make Live", live ? "photo" : "bolt.horizontal") { canvas in
                    canvas.setLiveCapture(item.id, enabled: !live)
                })
            }
            if onOpenURL != nil, let url = URL(string: raw) {
                object.append(row("open-source", "Open Source", "arrow.up.right.square") { $0.onOpenURL?(url) })
            }
            object.append(row("copy-source", "Copy Source URL", "link") { canvas in
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                if !pasteboard.setString(raw, forType: .string) { canvas.onError?(CocoaError(.fileWriteUnknown)) }
            })
        }
        object += EaselMenuRow.bridging(styleMenuItems(), prefix: "style")
        if let connector = makeConnectorMenu() {
            object += EaselMenuRow.bridging(connector.submenu?.items ?? [], prefix: "connector", anchors: [connector])
        }
        object += mindMapMenuRows(context) + textMenuRows(context) + linkMenuRows(context) + mediaMenuRows(context) + tableMenuRows(context)
            + codeMenuRows(context) + equationMenuRows(context) + connectorMenuRows(context) + styleMenuRows(context) + drawingMenuRows(context)
            + stampMenuRows(context)
        let view = [row("copy-image", "Copy as Image", "photo.on.rectangle") { $0.copySelectionAsImage() }, exportSelectionMenuRow(), selectAll]
            + zoomMenuRows(context)
        return [edit, arrange, object, view, [guides]]
    }
}
