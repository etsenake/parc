import AppKit
import ParcCore
import ParcKit

@MainActor
final class NoteMenuFooter: NSView {
    var text = "" { didSet { needsDisplay = true; setAccessibilityLabel(text) } }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let scale = window?.backingScaleFactor ?? 2
        NoteTheme.menuSeparator.setFill()
        NSRect(x: 0, y: 0, width: bounds.width, height: 1 / scale).fill()
        let attributes: [NSAttributedString.Key: Any] = [.font: NoteTheme.menuSubtitleFont(), .foregroundColor: NoteTheme.menuTertiaryInk]
        let string = NSAttributedString(string: text, attributes: attributes)
        let size = string.size()
        string.draw(in: NSRect(x: NoteTheme.menuInset + 10, y: (bounds.height - size.height) / 2 + 1,
                               width: bounds.width - (NoteTheme.menuInset + 10) * 2, height: ceil(size.height)))
    }
}

@MainActor
final class NoteSearchableMenuView: NSView, NoteFloatingPanelContent {
    static let width: CGFloat = 264
    static let footerHeight: CGFloat = 30

    let search: NoteSearchField
    let list = NoteMenuList()
    let footer = NoteMenuFooter()
    var preferredSizeDidChange: (() -> Void)?
    var footerText: String? {
        didSet {
            footer.text = footerText ?? ""
            footer.isHidden = footerText == nil
            needsLayout = true
            preferredSizeDidChange?()
        }
    }

    init(placeholder: String) {
        search = NoteSearchField(placeholder: placeholder)
        super.init(frame: NSRect(x: 0, y: 0, width: Self.width, height: 200))
        search.bind(to: list)
        list.fixedWidth = Self.width
        list.maximumHeight = 360
        list.preferredSizeDidChange = { [weak self] in
            self?.needsLayout = true
            self?.preferredSizeDidChange?()
        }
        footer.isHidden = true
        addSubview(search)
        addSubview(list)
        addSubview(footer)
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    private var searchSlot: CGFloat { NoteTheme.fieldHeight + NoteTheme.menuInset * 2 }

    override var fittingSize: NSSize {
        NSSize(width: Self.width, height: searchSlot + list.intrinsicContentSize.height + (footer.isHidden ? 0 : Self.footerHeight))
    }

    override var intrinsicContentSize: NSSize { fittingSize }

    override func layout() {
        super.layout()
        let inset = NoteTheme.menuInset
        search.frame = NSRect(x: inset, y: inset, width: bounds.width - inset * 2, height: NoteTheme.fieldHeight)
        let footerHeight = footer.isHidden ? 0 : Self.footerHeight
        let listHeight = max(0, bounds.height - searchSlot - footerHeight)
        list.frame = NSRect(x: 0, y: searchSlot - inset, width: bounds.width, height: listHeight + inset)
        footer.frame = NSRect(x: 0, y: bounds.height - footerHeight, width: bounds.width, height: footerHeight)
    }
}

@MainActor
extension NoteMenuList.Item {
    init(_ entry: NoteBlockMenuEntry) {
        self.init(id: entry.id, title: entry.title)
        subtitle = entry.subtitle
        shortcut = entry.shortcut
        section = entry.section
        isChecked = entry.isChecked
        isDestructive = entry.isDestructive
        isEnabled = entry.isEnabled
        hasSubmenu = entry.hasSubmenu
        keywords = entry.keywords
        switch entry.icon {
        case .symbol(let name): icon = .symbol(name)
        case .glyph(let text): icon = .glyph(text)
        case .textColor(let color):
            icon = .glyph("A")
            iconTint = color.map { NoteTheme.color(.text($0)) } ?? NoteTheme.ink
            iconFill = NoteTheme.menuFill
        case .backgroundColor(let color):
            icon = .glyph("A")
            iconTint = NoteTheme.ink
            iconFill = color.map { NoteTheme.color(.background($0)) } ?? NoteTheme.menuFill
        case nil: break
        }
    }
}

@MainActor
final class NoteBlockMenuController: NSObject {
    unowned let editor: NotePageEditor
    private(set) var targets: [NoteBlockID] = []
    private var entries: [NoteBlockMenuEntry] = []
    private var shown: [NoteBlockMenuEntry] = []
    private var panel: NoteFloatingPanel?
    private var menu: NoteSearchableMenuView?
    private var flyout: (panel: NoteFloatingPanel, list: NoteMenuList, parentID: String, entries: [NoteBlockMenuEntry])?
    private var mover: (panel: NoteFloatingPanel, view: NoteSearchableMenuView, notes: [NoteReference])?
    private var keyboardInFlyout = false
    private var restoreSelection: NotePageSelection?
    private var restoreResponder: NSResponder?
    private var monitor: Any?
    private var pendingFlyoutClose: DispatchWorkItem?
    var onClose: (() -> Void)?

    init(editor: NotePageEditor) {
        self.editor = editor
    }

    var isOpen: Bool { panel?.isPresented == true }

    func open(for ids: [NoteBlockID], anchor: NSRect, keyboard: Bool, previousSelection: NotePageSelection, startInMoveTo: Bool = false) {
        dismiss(animated: false, restore: false)
        let page = editor.session.page
        let top = page.topLevelSelection(ids)
        let blocks = top.compactMap { page.block($0) }
        var context = NoteBlockMenuContext(blocks: blocks, isReadOnly: editor.isReadOnly, canMoveToNotes: canMoveToNotes,
                                           supportsBlockLinks: editor.canLinkBlocks, tableEntries: Self.tableEntries(for: blocks),
                                           columnLimit: editor.session.columnSplitLimit(top))
        context.canTurnIntoSynced = !editor.isPlainText && page.canTurnIntoSynced(top)
        if blocks.count == 1, blocks[0].kind == .synced {
            context.syncedOriginalFound = editor.synced.info(for: blocks[0].id).map { !$0.isMissing } ?? false
        }
        let available = NoteBlockMenuModel.entries(for: context)
        guard !blocks.isEmpty, !available.isEmpty else { return }
        targets = top
        entries = available
        restoreSelection = previousSelection
        restoreResponder = editor.canvas.window?.firstResponder
        let view = NoteSearchableMenuView(placeholder: NoteBlockMenuModel.searchPlaceholder)
        wire(view.search)
        view.list.origin = keyboard ? .keyboard : .pointer
        view.list.onActivate = { [weak self] item in self?.activate(item, inFlyout: false) }
        view.list.onHighlight = { [weak self] item in self?.mainHighlightChanged(item) }
        view.list.onCancel = { [weak self] in self?.dismiss(animated: true, restore: true) }
        view.footerText = NoteBlockMenuModel.footer(for: blocks)
        menu = view
        applyFilter("")
        view.list.prepare(origin: keyboard ? .keyboard : .pointer)
        let card = NoteFloatingPanel(content: view)
        card.onDismiss = { [weak self, weak card] in self?.panelDidDismiss(card) }
        panel = card
        card.present(in: editor.canvas.overlayView, anchor: anchor, edge: .below)
        view.search.focus()
        installMonitor()
        if startInMoveTo, let move = shown.first(where: { $0.action == .moveTo }) {
            view.list.highlight(id: move.id, animated: false)
            openMover(keyboard: true)
        }
    }

    func dismiss(animated: Bool = true, restore: Bool = true) {
        guard let panel else { return }
        closeFlyout(animated: false)
        closeMover(animated: false)
        removeMonitor()
        pendingFlyoutClose?.cancel()
        self.panel = nil
        let view = menu
        menu = nil
        panel.dismiss(animated: animated)
        if let field = view?.search.textField, editor.canvas.window?.firstResponder === field.currentEditor() {
            editor.canvas.window?.makeFirstResponder(nil)
        }
        if restore { restoreFocus() }
        restoreSelection = nil
        restoreResponder = nil
        onClose?()
    }

    func handleKey(_ event: NSEvent) -> Bool {
        guard isOpen else { return false }
        if event.keyCode == 53 {
            if flyout != nil || mover != nil { closeFlyout(animated: true); closeMover(animated: true); return true }
            dismiss(animated: true, restore: true)
            return true
        }
        return activeList?.handleKeyDown(event) ?? false
    }

    private var canMoveToNotes: Bool {
        guard !editor.isTemplateEditor, let url = editor.environment.documentURL, NoteFileKind(url: url) == .markdown else { return false }
        return !editor.environment.isPlainText
    }

    private var activeList: NoteMenuList? {
        if let mover { return mover.view.list }
        if keyboardInFlyout, let flyout { return flyout.list }
        return menu?.list
    }

    private func panelDidDismiss(_ card: NoteFloatingPanel?) {
        guard let card, card === panel else { return }
        dismiss(animated: false, restore: false)
    }

    private func applyFilter(_ query: String) {
        guard let menu else { return }
        shown = NoteBlockMenuModel.filter(entries, query: query)
        let filtering = !NoteBlockMenuModel.normalized(query).isEmpty
        var items: [NoteMenuList.Item] = []
        var lastGroup: Int?
        for entry in shown {
            var item = NoteMenuList.Item(entry)
            if !filtering {
                item.separatorBefore = lastGroup != nil && lastGroup != entry.group
                item.section = nil
            }
            lastGroup = entry.group
            items.append(item)
        }
        menu.list.noResultsTitle = "Nothing by that name. Try another word?"
        menu.list.setItems(items, keepingHighlight: false)
        if filtering { menu.list.prepare(origin: .keyboard) }
    }

    private func entry(for item: NoteMenuList.Item, inFlyout: Bool) -> NoteBlockMenuEntry? {
        if inFlyout, let flyout { return flyout.entries.first { $0.id == item.id } }
        return shown.first { $0.id == item.id }
    }

    private func mainHighlightChanged(_ item: NoteMenuList.Item?) {
        guard let item else { return }
        if let flyout, flyout.parentID == item.id { pendingFlyoutClose?.cancel(); return }
        if NSApp.currentEvent?.type == .keyDown {
            pendingFlyoutClose?.cancel()
            closeFlyout(animated: true)
            closeMover(animated: true)
            return
        }
        if item.hasSubmenu {
            pendingFlyoutClose?.cancel()
            openSubmenu(for: item, keyboard: false)
            return
        }
        guard flyout != nil || mover != nil else { return }
        pendingFlyoutClose?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.closeFlyout(animated: true)
            self?.closeMover(animated: true)
        }
        pendingFlyoutClose = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    private func activate(_ item: NoteMenuList.Item, inFlyout: Bool) {
        guard let entry = entry(for: item, inFlyout: inFlyout) else { return }
        if !inFlyout, entry.hasSubmenu {
            openSubmenu(for: item, keyboard: menu?.list.origin == .keyboard || NSApp.currentEvent?.type == .keyDown)
            return
        }
        guard let action = entry.action else { return }
        perform(action)
    }

    private func openSubmenu(for item: NoteMenuList.Item, keyboard: Bool) {
        guard let entry = shown.first(where: { $0.id == item.id }) else { return }
        if entry.action == .moveTo {
            closeFlyout(animated: false)
            openMover(keyboard: keyboard)
            return
        }
        closeMover(animated: false)
        if let flyout, flyout.parentID == entry.id {
            if keyboard { focusFlyout() }
            return
        }
        closeFlyout(animated: false)
        guard let menu, let anchor = highlightedRowFrame(of: menu.list) else { return }
        let list = NoteMenuList()
        list.minimumWidth = 200
        list.maximumHeight = 360
        list.items = entry.children.map { child in
            var item = NoteMenuList.Item(child)
            item.section = child.section == entry.title ? nil : child.section
            return item
        }
        list.onActivate = { [weak self] item in self?.activate(item, inFlyout: true) }
        list.onCancel = { [weak self] in self?.closeFlyout(animated: true) }
        list.onCollapse = { [weak self] in self?.closeFlyout(animated: true) }
        list.onHighlight = { [weak self] item in if item != nil { self?.pendingFlyoutClose?.cancel() } }
        let card = NoteFloatingPanel(content: list)
        card.onDismiss = { [weak self, weak card] in
            guard let self, let card, self.flyout?.panel === card else { return }
            self.flyout = nil
            self.keyboardInFlyout = false
        }
        flyout = (card, list, entry.id, entry.children)
        card.present(in: editor.canvas.overlayView, anchor: anchor, edge: .trailing)
        if keyboard { focusFlyout() } else { list.prepare(origin: .pointer) }
    }

    private func focusFlyout() {
        guard let flyout else { return }
        keyboardInFlyout = true
        flyout.list.prepare(origin: .keyboard)
        if let checked = flyout.list.items.first(where: \.isChecked) { flyout.list.highlight(id: checked.id, animated: false) }
    }

    private func closeFlyout(animated: Bool) {
        guard let flyout else { return }
        self.flyout = nil
        keyboardInFlyout = false
        flyout.panel.dismiss(animated: animated)
    }

    private func openMover(keyboard: Bool) {
        if mover != nil {
            if keyboard { mover?.view.search.focus() }
            return
        }
        guard let menu, let anchor = highlightedRowFrame(of: menu.list) else { return }
        let view = NoteSearchableMenuView(placeholder: NoteBlockMenuModel.moveSearchPlaceholder)
        view.list.rowStyle = .detailed
        view.list.noResultsTitle = "No other notes to move to yet."
        view.list.onActivate = { [weak self] item in self?.chooseNote(item) }
        view.list.onCancel = { [weak self] in self?.closeMover(animated: true) }
        view.list.onCollapse = { [weak self] in self?.closeMover(animated: true) }
        view.list.onHighlight = { [weak self] item in if item != nil { self?.pendingFlyoutClose?.cancel() } }
        wire(view.search)
        let card = NoteFloatingPanel(content: view)
        card.onDismiss = { [weak self, weak card] in
            guard let self, let card, self.mover?.panel === card else { return }
            self.mover = nil
        }
        mover = (card, view, [])
        refreshNotes("")
        view.list.prepare(origin: keyboard ? .keyboard : .pointer)
        card.present(in: editor.canvas.overlayView, anchor: anchor, edge: .trailing)
        if keyboard { view.search.focus() }
    }

    private func closeMover(animated: Bool) {
        guard let mover else { return }
        self.mover = nil
        let wasEditing = editor.canvas.window?.firstResponder === mover.view.search.textField.currentEditor()
        mover.panel.dismiss(animated: animated)
        if wasEditing { menu?.search.focus() }
    }

    private func refreshNotes(_ query: String) {
        guard var current = mover else { return }
        let notes = editor.environment.searchNotes(query, limit: 30).filter { NoteFileKind(url: $0.url) == .markdown }
        current.notes = notes
        mover = current
        current.view.list.setItems(notes.map { note in
            var item = NoteMenuList.Item(id: note.url.absoluteString, title: note.title)
            item.subtitle = NoteRelativeTime.edited(note.modifiedAt)
            item.icon = NoteIcon.note(note.icon, at: note.url)
            return item
        }, keepingHighlight: false)
        if !NoteBlockMenuModel.normalized(query).isEmpty { current.view.list.prepare(origin: .keyboard) }
    }

    private func chooseNote(_ item: NoteMenuList.Item) {
        guard let note = mover?.notes.first(where: { $0.url.absoluteString == item.id }) else { return }
        perform(.moveToNote(note.url), title: note.title)
    }

    private func highlightedRowFrame(of list: NoteMenuList) -> NSRect? {
        let overlay = editor.canvas.overlayView
        if let row = list.highlightedRowFrame { return overlay.convert(row, from: list) }
        if let pointer = list.window?.mouseLocationOutsideOfEventStream {
            let local = overlay.convert(pointer, from: nil)
            let listFrame = overlay.convert(list.bounds, from: list)
            return NSRect(x: listFrame.minX, y: local.y - list.rowHeight / 2, width: listFrame.width, height: list.rowHeight)
        }
        return panel?.frame
    }

    private func wire(_ search: NoteSearchField) {
        search.onChange = { [weak self, weak search] text in
            guard let self, let search else { return }
            self.searchChanged(text, in: search)
        }
        search.onCommand = { [weak self, weak search] selector in
            guard let self, let search else { return false }
            return self.searchCommand(selector, in: search)
        }
    }

    private func searchChanged(_ text: String, in search: NoteSearchField) {
        if let mover, search === mover.view.search {
            refreshNotes(text)
            return
        }
        closeFlyout(animated: true)
        closeMover(animated: true)
        applyFilter(text)
    }

    private func searchCommand(_ selector: Selector, in search: NoteSearchField) -> Bool {
        let inMover = mover.map { search === $0.view.search } ?? false
        let editor = search.textField.currentEditor() as? NSTextView
        let range = editor?.selectedRange() ?? NSRange(location: 0, length: 0)
        let atStart = range.location == 0 && range.length == 0
        let atEnd = range.location == ((editor?.string ?? search.text) as NSString).length
        switch selector {
        case #selector(NSResponder.cancelOperation(_:)):
            if inMover { closeMover(animated: true); return true }
            if flyout != nil, keyboardInFlyout { closeFlyout(animated: true); return true }
            dismiss(animated: true, restore: true)
            return true
        case #selector(NSResponder.moveLeft(_:)):
            if inMover && atStart { closeMover(animated: true); return true }
            if !inMover, keyboardInFlyout, atStart { closeFlyout(animated: true); return true }
            return false
        case #selector(NSResponder.moveRight(_:)):
            guard !inMover, atEnd else { return false }
            if keyboardInFlyout { return true }
            guard let item = menu?.list.highlightedItem, item.hasSubmenu else { return false }
            openSubmenu(for: item, keyboard: true)
            return true
        case #selector(NSResponder.insertTab(_:)):
            return true
        default:
            let list = inMover ? mover?.view.list : (keyboardInFlyout ? flyout?.list : menu?.list)
            if list?.origin != .keyboard, selector == #selector(NSResponder.moveDown(_:)) || selector == #selector(NSResponder.moveUp(_:)) {
                list?.prepare(origin: .keyboard)
                return true
            }
            return list?.handle(command: selector) ?? false
        }
    }

    private static let tableKeywords: [String: [String]] = [
        "table.headerRow": ["header", "first row"],
        "table.headerColumn": ["header", "first column"],
        "table.fitWidth": ["width", "fit", "reset", "columns"],
    ]

    static func tableEntries(for blocks: [NoteBlock]) -> [NoteBlockMenuEntry] {
        guard let first = blocks.first, blocks.allSatisfy({ $0.kind == .table }) else { return [] }
        let perTable = blocks.map { NoteTableBlockView.tableMenuItems(for: $0) }
        return NoteTableBlockView.tableMenuItems(for: first).map { item in
            let states = perTable.compactMap { items in items.first { $0.id == item.id } }
            var entry = NoteBlockMenuEntry(id: item.id, title: item.title, keywords: tableKeywords[item.id] ?? [], group: 1,
                                           isChecked: states.allSatisfy(\.isChecked), isEnabled: states.contains(where: \.isEnabled),
                                           action: .tableItem(item.id))
            switch item.icon {
            case .symbol(let name)?: entry.icon = .symbol(name)
            case .glyph(let text)?: entry.icon = .glyph(text)
            default: break
            }
            return entry
        }
    }

    private func installMonitor() {
        removeMonitor()
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel]) { [weak self] event in
            guard let self, self.isOpen else { return event }
            let cards = [self.panel, self.flyout?.panel, self.mover?.panel].compactMap { $0 }
            let inside = cards.contains { card in
                guard card.window === event.window else { return false }
                return card.bounds.contains(card.convert(event.locationInWindow, from: nil))
            }
            if !inside {
                let restore = event.type != .leftMouseDown
                self.dismiss(animated: true, restore: restore)
            }
            return event
        }
    }

    private func removeMonitor() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private func restoreFocus() {
        let session = editor.session
        if let previous = restoreSelection, case .text(let anchor, let head) = previous,
           session.page.block(anchor.block) != nil, session.page.block(head.block) != nil,
           case .blocks = session.selection {
            session.setSelection(previous)
            editor.focus(head)
            return
        }
        if let caret = session.selection.caret, session.page.block(caret.block) != nil {
            editor.focus(caret)
            return
        }
        if let responder = restoreResponder, let window = editor.canvas.window,
           (responder as? NSView)?.window === window {
            window.makeFirstResponder(responder)
        }
    }

    private func perform(_ action: NoteBlockAction, title: String? = nil) {
        let ids = targets
        let session = editor.session
        let page = session.page
        let live = ids.filter { page.block($0) != nil }
        guard !live.isEmpty else { dismiss(animated: true, restore: true); return }
        switch action {
        case .delete:
            dismiss(animated: true, restore: false)
            session.deleteBlocks(live)
            if let caret = session.selection.caret { editor.focus(caret) }
            return
        case .duplicate:
            dismiss(animated: true, restore: false)
            session.duplicateBlocks(live)
            return
        case .turnInto(let style):
            session.turnInto(live, kind: style.kind) { style.configure(&$0) }
        case .turnIntoColumns(let count):
            session.turnIntoColumns(live, count: count)
        case .color(let style):
            session.setColor(style, in: .blocks(live))
            if let style { NoteColorRecents.record(style) }
        case .language(let language):
            update(live, name: "Code Language") { $0.props.language = language }
        case .wrapCode:
            let wrap = !live.allSatisfy { page.block($0)?.props.wrap == true }
            update(live, name: wrap ? "Wrap Code" : "Unwrap Code") { $0.props.wrap = wrap }
        case .diagramMode(let mode):
            update(live, name: "Diagram View") { $0.props.diagramMode = mode == .preview ? nil : mode }
        case .align(let alignment):
            update(live, name: "Align") { $0.props.alignment = alignment }
        case .tableItem(let id):
            let tables = live.compactMap { page.block($0) }.filter { $0.kind == .table }
            let states = tables.map { table in NoteTableBlockView.tableMenuItems(for: table).first { $0.id == id } }
            let turnOn = !states.allSatisfy { $0?.isChecked == true }
            let name = states.compactMap { $0?.title }.first ?? "Table"
            session.group(name) {
                for (table, state) in zip(tables, states) {
                    guard let state, state.isEnabled, state.isChecked != turnOn else { continue }
                    NoteTableBlockView.performTableMenuItem(id, on: table.id, session: session)
                }
            }
        case .download:
            if let source = page.block(live[0])?.props.source { editor.handles.download(source) }
        case .fullScreen:
            dismiss(animated: true, restore: false)
            (editor.canvas.blockView(for: live[0]) as? NoteMediaBlockView)?.presentPreview()
            return
        case .viewOriginal:
            if let source = page.block(live[0])?.props.source, let url = editor.environment.resolve(source) {
                dismiss(animated: true, restore: true)
                editor.open(url)
                return
            }
        case .cropImage:
            dismiss(animated: true, restore: false)
            (editor.canvas.blockView(for: live[0]) as? NoteMediaBlockView)?.beginCrop()
            return
        case .altText:
            dismiss(animated: true, restore: false)
            (editor.canvas.blockView(for: live[0]) as? NoteMediaBlockView)?.editAltText()
            return
        case .mask(let mask):
            (editor.canvas.blockView(for: live[0]) as? NoteMediaBlockView)?.applyMask(mask)
        case .copyOriginalLink:
            if let source = page.block(live[0])?.props.source {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(source, forType: .string)
                if let url = URL(string: source) { pasteboard.setString(url.absoluteString, forType: .URL) }
                editor.handles.presentToast?(.copiedLinks(URL(string: source).map { [$0] } ?? []))
            }
        case .moveToNote(let url):
            dismiss(animated: true, restore: false)
            editor.handles.move(live, to: url, title: title)
            return
        case .moveTo:
            openMover(keyboard: true)
            return
        case .copyLink:
            dismiss(animated: true, restore: true)
            editor.copyLink(toBlock: live[0])
            return
        case .editButton:
            dismiss(animated: true, restore: false)
            (editor.materializedView(for: live[0]) as? NoteButtonBlockView)?.openEditor()
            return
        case .unwrapButton:
            dismiss(animated: true, restore: false)
            session.unwrapButton(live[0])
            if let caret = session.selection.caret { editor.focus(caret) } else { editor.restoreFocus() }
            return
        case .turnIntoSynced:
            dismiss(animated: true, restore: false)
            editor.synced.turnIntoSynced(live)
            return
        case .copySynced:
            dismiss(animated: true, restore: true)
            editor.synced.copyAndSync(live[0])
            return
        case .goToOriginal:
            dismiss(animated: true, restore: true)
            editor.synced.goToOriginal(live[0])
            return
        case .unsync:
            dismiss(animated: true, restore: false)
            editor.synced.unsync(live[0])
            return
        case .unsyncAll:
            dismiss(animated: true, restore: false)
            editor.synced.unsyncAll(live[0])
            return
        }
        dismiss(animated: true, restore: true)
    }

    private func update(_ ids: [NoteBlockID], name: String, _ transform: @escaping (inout NoteBlock) -> Void) {
        let session = editor.session
        session.edit(name, affected: Set(ids), selection: session.selection) { page in
            for id in ids { page.update(id, transform) }
        }
    }
}
