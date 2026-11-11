import AppKit
import Combine

enum DocumentCardChrome {
    static let side: CGFloat = 140
    static let padding: CGFloat = 12
    static let artwork: CGFloat = 18
    static let radius: CGFloat = 12
    static let titleSize: CGFloat = 15
    static let gap: CGFloat = 8
    static func fill(dark: Bool) -> NSColor {
        dark ? NSColor(srgbRed: 0.20, green: 0.20, blue: 0.20, alpha: 1) : .white
    }
    static func title(dark: Bool) -> NSColor {
        dark ? NSColor(white: 1, alpha: 0.92) : NSColor(white: 0.07, alpha: 1)
    }
    static func hairline(dark: Bool, selected: Bool) -> NSColor {
        let alpha: CGFloat = selected ? (dark ? 0.28 : 0.16) : (dark ? 0.12 : 0.08)
        return NSColor(white: dark ? 1 : 0, alpha: alpha)
    }
}

@MainActor
final class DocumentsLibraryView: NSView, NSTextFieldDelegate, NSTableViewDataSource, NSTableViewDelegate {
    private struct Row: Equatable {
        let page: InternalPage
        let title: String
        let searchableText: String
        let modified: Date
    }
    private let store: BrowserStore
    private let profileID: UUID
    private let searchBackdrop = DownloadSearchBackdrop()
    private let search = DownloadSearchField(frame: .zero)
    private let createButton = ActionButton("", symbol: "square.and.pencil")
    private let grid = DocumentsGridTable()
    private var selectedPage: InternalPage?
    private let scroll = NSScrollView()
    private let empty = NSTextField(wrappingLabelWithString: "")
    private var rows: [Row] = []
    private var subscription: AnyCancellable?
    private var observedNotes: [NoteDocument] = []
    private var observedEasels: [EaselSummary] = []
    private var observedProfileRemovalPending = false
    var ownerValid: (() -> Bool)?
    var onOpen: ((InternalPage, String) -> Void)?
    var onCreate: (() -> Void)?
    var onRename: ((InternalPage, String) -> Void)?
    var onDelete: ((InternalPage, @escaping (Error?) -> Void) -> Void)?
    var onClose: (() -> Void)?
    var palette: ThemeChromePalette? {
        didSet {
            searchBackdrop.ink = .labelColor
            empty.textColor = .secondaryLabelColor
            createButton.contentTintColor = .labelColor
            rebuildCards()
        }
    }
    override var isFlipped: Bool { true }
    init(store: BrowserStore, profileID: UUID) {
        self.store = store; self.profileID = profileID
        super.init(frame: .zero)
        search.placeholderString = "Search Easels & Notes…"; search.delegate = self
        search.setAccessibilityLabel("Search Easels and Notes")
        searchBackdrop.wantsLayer = true; searchBackdrop.setAccessibilityElement(false)
        searchBackdrop.addSubview(search)
        searchBackdrop.onFocus = { [weak self] in
            guard let self, self.valid, let window = self.window, window.attachedSheet == nil else { return }
            if self.search.currentEditor() !== window.firstResponder { window.makeFirstResponder(self.search) }
        }
        createButton.actionBlock = { [weak self] in self?.createNote() }
        createButton.focusRingCornerRadius = 8
        createButton.setAccessibilityLabel("New Note")
        LiveShortcutToolTip.set(createButton, "New Note")
        grid.addTableColumn(NSTableColumn(identifier: .init("cards")))
        grid.style = .plain
        grid.headerView = nil; grid.rowHeight = DocumentCardChrome.side + 24; grid.intercellSpacing = .zero
        grid.backgroundColor = .clear; grid.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        grid.selectionHighlightStyle = .none; grid.delegate = self; grid.dataSource = self
        grid.setAccessibilityLabel("Easels and Notes")
        grid.onClose = { [weak self] in self?.onClose?() }
        grid.onSearch = { [weak self] in self?.focusSearch() }
        scroll.documentView = grid; scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = false
        scroll.scrollerStyle = .overlay; scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        empty.font = .systemFont(ofSize: 13)
        empty.textColor = .secondaryLabelColor
        empty.alignment = .center
        for view in [searchBackdrop, createButton, scroll, empty] { addSubview(view) }
        do { subscription = try NoteStore.sharedStore(directory: store.notesDirectory(for: profileID)).changes.sink { [weak self] in self?.reload() } }
        catch { empty.stringValue = error.localizedDescription }
        reload(force: true)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    private var chromeDark: Bool {
        palette?.isDark ?? (effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua)
    }
    func focusSearch() { window?.makeFirstResponder(search); search.selectText(nil) }
    func reload(force: Bool = false) {
        let selected = selectedPage
        do {
            let notes = try NoteStore.sharedStore(directory: store.notesDirectory(for: profileID)).list()
            let easels = try EaselEditorViewController.sharedStore(directory: store.easelsDirectory(for: profileID)).list()
            let pending = store.isProfileRemovalPending(profileID)
            if !force && shouldSkipCatalogReload(notes: notes, easels: easels, pending: pending) { return }
            rememberAppliedCatalog(notes: notes, easels: easels, pending: pending)
            let all = notes.map { Row(page: .note($0.id), title: $0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled Note" : $0.title,
                                      searchableText: $0.body.text.replacingOccurrences(of: "\n", with: " "), modified: $0.modifiedAt) }
                + easels.map { Row(page: .easel($0.id), title: $0.title, searchableText: "Easel · \($0.itemCount) objects", modified: $0.modifiedAt) }
            let next = all.filter { search.stringValue.isEmpty || $0.title.localizedCaseInsensitiveContains(search.stringValue)
                    || $0.searchableText.localizedCaseInsensitiveContains(search.stringValue) }
                .sorted { $0.modified == $1.modified ? $0.page.urlString < $1.page.urlString : $0.modified > $1.modified }
            empty.stringValue = next.isEmpty ? "Your local Easels and Notes will appear here." : ""
            empty.isHidden = !next.isEmpty
            selectedPage = next.contains(where: { $0.page == selected }) ? selected : nil
            let sameCards = zip(next, rows).allSatisfy { $0.page == $1.page && $0.title == $1.title } && next.count == rows.count
            rows = next
            if !sameCards { rebuildCards() }
            createButton.isEnabled = !pending
        } catch {
            observedNotes = []; observedEasels = []; observedProfileRemovalPending = false
            rows = []; selectedPage = nil; rebuildCards()
            empty.stringValue = error.localizedDescription; empty.isHidden = false
            createButton.isEnabled = !store.isProfileRemovalPending(profileID)
        }
    }

    private func shouldSkipCatalogReload(notes: [NoteDocument], easels: [EaselSummary], pending: Bool) -> Bool {
        notes == observedNotes
            && easels == observedEasels
            && pending == observedProfileRemovalPending
    }

    private func rememberAppliedCatalog(notes: [NoteDocument], easels: [EaselSummary], pending: Bool) {
        observedNotes = notes
        observedEasels = easels
        observedProfileRemovalPending = pending
    }
    private var current: Row? { rows.first { $0.page == selectedPage } }
    private var valid: Bool { window != nil && ownerValid?() == true }
    private func rebuildCards() {
        let focused = (window?.firstResponder as? NSView).flatMap { view in
            sequence(first: view, next: { $0.superview }).compactMap { $0 as? DocumentCard }.first
        }
        let restoreFocus = focused != nil
        grid.reloadData()
        if restoreFocus, let index = rows.firstIndex(where: { $0.page == selectedPage }) {
            revealCard(index); window?.makeFirstResponder(card(at: index))
        }
    }
    func numberOfRows(in tableView: NSTableView) -> Int { (rows.count + 1) / 2 }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let container = LayoutView()
        let dark = chromeDark
        for index in (row * 2)..<min(rows.count, row * 2 + 2) {
            let item = rows[index]
            let card = DocumentCard(title: item.title, isNote: item.page.noteID != nil, dark: dark)
            card.identifier = NSUserInterfaceItemIdentifier("document-\(index)")
            card.isSelected = item.page == selectedPage
            card.select = { [weak self] in self?.selectedPage = item.page; self?.updateSelection() }
            card.open = { [weak self] in
                guard let self else { return }; self.selectedPage = item.page; self.updateSelection(); self.open(item)
            }
            card.move = { [weak self] delta in self?.moveSelection(from: index, by: delta) ?? false }
            card.rename = { [weak self] in self?.rename(item) }
            card.delete = { [weak self] in self?.delete(item) }
            card.dismiss = { [weak self] in self?.onClose?() }
            container.addSubview(card)
        }
        container.onLayout = { [weak container] in
            guard let container else { return }
            let side = min(DocumentCardChrome.side, max(0, (container.bounds.width - 36) / 2))
            let x = max(12, (container.bounds.width - (2 * side + 12)) / 2)
            for (position, card) in container.subviews.enumerated() {
                card.frame = NSRect(x: x + CGFloat(position) * (side + 12), y: 12, width: side, height: side)
            }
        }
        return container
    }
    private func card(at index: Int) -> DocumentCard? {
        guard let row = grid.view(atColumn: 0, row: index / 2, makeIfNecessary: true) else { return nil }
        return row.subviews.first { $0.identifier?.rawValue == "document-\(index)" } as? DocumentCard
    }
    private func updateSelection() {
        let visible = grid.rows(in: grid.visibleRect)
        if visible.location != NSNotFound {
            for row in visible.location..<(visible.location + visible.length) {
                guard let view = grid.view(atColumn: 0, row: row, makeIfNecessary: false) else { continue }
                for (position, card) in view.subviews.compactMap({ $0 as? DocumentCard }).enumerated() {
                    let index = row * 2 + position
                    card.isSelected = rows.indices.contains(index) && rows[index].page == selectedPage
                }
            }
        }
    }
    private func revealCard(_ index: Int) { grid.scrollRowToVisible(index / 2) }
    private func moveSelection(from index: Int, by delta: Int) -> Bool {
        let next = index + delta
        guard rows.indices.contains(next) else { return false }
        selectedPage = rows[next].page; updateSelection(); revealCard(next)
        window?.makeFirstResponder(card(at: next)); return true
    }
    func controlTextDidChange(_ obj: Notification) { reload(force: true) }
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard !textView.hasMarkedText() else { return false }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            if !search.stringValue.isEmpty { search.stringValue = ""; reload(force: true) }
            else { onClose?() }
            return true
        }
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            if let row = current { open(row) } else if let first = rows.first { open(first) }
            return true
        }
        return false
    }
    override func cancelOperation(_ sender: Any?) {
        if !search.stringValue.isEmpty { search.stringValue = ""; reload(force: true); return }
        onClose?()
    }
    @objc private func createNote() { guard valid else { return }; onCreate?() }
    private func open(_ row: Row) { guard valid else { return }; onOpen?(row.page, row.title) }
    private func rename(_ row: Row) {
        guard valid, let window, window.attachedSheet == nil else { return }
        let dialog = PArcDialog(.init(title: [(row.page.noteID == nil ? "Rename Easel" : "Rename Note", false)],
            confirm: "Rename", cancel: "Cancel", field: .init(value: row.title, placeholder: "", required: false)))
        guard let field = dialog.textField else { return }
        _ = dialog.begin(for: window) { [weak self] result in
            guard let self, result == .confirm, self.valid else { return }
            do {
                if let id = row.page.noteID {
                    let session = try NoteStore.sharedStore(directory: self.store.notesDirectory(for: self.profileID)).load(id)
                    guard session.displayTitle == row.title else { throw NoteError.changed }
                    try session.updateTitle(field.stringValue, replacing: session.document.title)
                } else if let id = row.page.easelID {
                    let session = try EaselEditorViewController.sharedStore(directory: self.store.easelsDirectory(for: self.profileID)).load(id)
                    guard session.document.title == row.title else { throw NoteError.changed }
                    try session.perform("Rename Easel") { $0.title = field.stringValue.isEmpty ? "Untitled Easel" : field.stringValue }
                }
                self.onRename?(row.page, field.stringValue); self.reload()
            } catch { self.empty.stringValue = error.localizedDescription; self.empty.isHidden = self.rows.isEmpty == false }
        }
    }
    private func delete(_ row: Row) {
        guard valid, let window, window.attachedSheet == nil else { return }
        let note = row.page.noteID != nil
        PArcDialog.confirm(in: window, title: note ? "Are you sure you want to delete this note?" : "Are you sure you want to delete this Easel?",
                          message: note ? "Doing so will delete the note permanently." : "Doing so will delete the Easel permanently.",
                          confirm: "Delete", destructive: true) { [weak self] approved in
            guard let self, approved, self.valid else { return }
            self.onDelete?(row.page) { [weak self] error in
                guard let self else { return }
                self.reload()
                if let error {
                    self.empty.stringValue = error.localizedDescription
                    self.empty.isHidden = self.rows.isEmpty == false
                }
            }
        }
    }
    override func layout() {
        super.layout(); let w = bounds.width, h = bounds.height
        let create = LibraryPageHeader.height, inset = LibraryPageHeader.inset, top = LibraryPageHeader.top
        searchBackdrop.frame = NSRect(x: inset, y: top, width: max(0, w - 2 * inset - LibraryPageHeader.spacing - create), height: create)
        createButton.frame = NSRect(x: max(inset, w - inset - create), y: top, width: create, height: create)
        scroll.frame = NSRect(x: 0, y: LibraryPageHeader.contentTop, width: w, height: max(0, h - LibraryPageHeader.contentTop))
        let cardSide = min(DocumentCardChrome.side, max(0, (scroll.contentSize.width - 36) / 2))
        if grid.rowHeight != cardSide + 24 { grid.rowHeight = cardSide + 24 }
        empty.frame = NSRect(x: 24, y: 110, width: max(0, w - 48), height: 48)
    }
}

@MainActor
private final class DocumentCard: NSView {
    var open: (() -> Void)?
    var select: (() -> Void)?
    var rename: (() -> Void)?
    var delete: (() -> Void)?
    var dismiss: (() -> Void)?
    var move: ((Int) -> Bool)?
    var isSelected = false { didSet { needsDisplay = true } }
    private let titleLabel: NSTextField
    private let icon = NSImageView()
    private let isNote: Bool
    private let dark: Bool
    private let more = DocumentMoreButton()
    private var tracking: NSTrackingArea?
    private var trackingOpen = false
    private var hovered = false { didSet { more.alphaValue = hovered || isSelected ? 1 : 0; needsDisplay = true } }
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override var wantsUpdateLayer: Bool { true }
    init(title: String, isNote: Bool, dark: Bool) {
        self.isNote = isNote
        self.dark = dark
        titleLabel = NSTextField(wrappingLabelWithString: title)
        super.init(frame: .zero)
        setAccessibilityRole(.button)
        setAccessibilityLabel(title)
        setAccessibilityHelp(isNote ? "Note" : "Easel")
        wantsLayer = true; focusRingType = .exterior
        updateArtwork()
        icon.imageScaling = .scaleProportionallyUpOrDown
        titleLabel.font = .systemFont(ofSize: DocumentCardChrome.titleSize, weight: .semibold)
        titleLabel.textColor = DocumentCardChrome.title(dark: dark)
        titleLabel.lineBreakMode = .byWordWrapping
        titleLabel.maximumNumberOfLines = 5
        titleLabel.cell?.truncatesLastVisibleLine = true
        for view in [icon, titleLabel, more] { addSubview(view) }
        more.isBordered = false
        more.image = NSImage(systemSymbolName: "ellipsis", accessibilityDescription: "More")
        more.contentTintColor = DocumentCardChrome.title(dark: dark).withAlphaComponent(0.45)
        more.target = self; more.action = #selector(showMenu); more.setAccessibilityLabel("More actions for \(title)")
        more.alphaValue = 0
        more.tab = { [weak self] backwards in
            guard let self else { return false }
            if backwards { return self.window?.makeFirstResponder(self) ?? false }
            return self.move?(1) ?? false
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    private func updateArtwork() {
        let name = (isNote ? "note" : "easel") + (dark ? "-dark" : "")
        guard let directory = LibraryArtwork.directory,
              let base = NSImage(contentsOf: directory.appendingPathComponent(name + ".png")) else { return }
        if let data = try? Data(contentsOf: directory.appendingPathComponent(name + "@2x.png")),
           let rep = NSBitmapImageRep(data: data) {
            rep.size = NSSize(width: DocumentCardChrome.artwork, height: DocumentCardChrome.artwork)
            base.addRepresentation(rep)
        }
        icon.image = base
    }
    override func updateLayer() {
        let radius = DocumentCardChrome.radius
        layer?.cornerRadius = radius; layer?.cornerCurve = .continuous
        layer?.masksToBounds = false
        layer?.backgroundColor = DocumentCardChrome.fill(dark: dark).cgColor
        layer?.borderWidth = 1
        layer?.borderColor = DocumentCardChrome.hairline(dark: dark, selected: isSelected || hovered).cgColor
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = dark ? 0.18 : 0.10
        layer?.shadowRadius = dark ? 4 : 8
        layer?.shadowOffset = CGSize(width: 0, height: dark ? 1 : 2)
        layer?.shadowPath = CGPath(roundedRect: bounds, cornerWidth: radius, cornerHeight: radius, transform: nil)
        more.alphaValue = hovered || isSelected ? 1 : 0
    }
    override func layout() {
        super.layout()
        let pad = DocumentCardChrome.padding
        let art = DocumentCardChrome.artwork
        icon.frame = NSRect(x: pad, y: pad, width: art, height: art)
        more.frame = NSRect(x: max(0, bounds.width - 36), y: 4, width: 32, height: 32)
        let textWidth = max(0, bounds.width - pad * 2)
        let titleTop = pad + art + DocumentCardChrome.gap
        let titleHeight = titleLabel.sizeThatFits(NSSize(width: textWidth, height: bounds.height - titleTop - pad)).height
        titleLabel.frame = NSRect(x: pad, y: titleTop, width: textWidth,
                                  height: min(bounds.height - titleTop - pad, max(18, titleHeight)))
        needsDisplay = true
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let next = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .cursorUpdate, .activeInKeyWindow, .inVisibleRect], owner: self)
        tracking = next; addTrackingArea(next)
    }
    override func cursorUpdate(with event: NSEvent) { NSCursor.pointingHand.set() }
    override func mouseEntered(with event: NSEvent) { hovered = true }
    override func mouseExited(with event: NSEvent) { hovered = false }
    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) { trackingOpen = false; rightMouseDown(with: event); return }
        if more.hitTest(convert(event.locationInWindow, from: nil)) != nil { trackingOpen = false; more.mouseDown(with: event); return }
        trackingOpen = true
        window?.makeFirstResponder(self)
    }
    override func mouseUp(with event: NSEvent) {
        let shouldOpen = trackingOpen && bounds.contains(convert(event.locationInWindow, from: nil))
        trackingOpen = false
        if shouldOpen { open?() }
    }
    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { select?() }; return accepted
    }
    override func accessibilityPerformPress() -> Bool { open?(); return true }
    override func accessibilityPerformShowMenu() -> Bool { showMenu(); return true }
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let hit = super.hitTest(point) else { return nil }
        return hit === more || hit.isDescendant(of: more) ? hit : self
    }
    private func focusMore() { window?.makeFirstResponder(more) }
    @objc private func showMenu() {
        let menu = makeMenu(); menu.popUp(positioning: nil, at: NSPoint(x: more.frame.minX, y: more.frame.maxY), in: self)
    }
    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(DocumentActionItem(title: "Rename…", invoke: { [weak self] in self?.rename?() }))
        menu.addItem(DocumentActionItem(title: "Delete…", invoke: { [weak self] in self?.delete?() })); return menu
    }
    override func menu(for event: NSEvent) -> NSMenu? { makeMenu() }
    override func keyDown(with event: NSEvent) {
        guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { super.keyDown(with: event); return }
        switch event.keyCode {
        case 53: dismiss?()
        case 123: _ = move?(-1)
        case 124: _ = move?(1)
        case 125: _ = move?(2)
        case 126: _ = move?(-2)
        case 48:
            if event.modifierFlags.contains(.shift) {
                if move?(-1) == true { (window?.firstResponder as? DocumentCard)?.focusMore() }
                else { super.keyDown(with: event) }
            } else if window?.makeFirstResponder(more) != true { super.keyDown(with: event) }
        case 36, 49, 76: open?()
        case 51, 117: delete?()
        default: super.keyDown(with: event)
        }
    }
}

@MainActor
private final class DocumentsGridTable: NSTableView {
    var onClose: (() -> Void)?
    var onSearch: (() -> Void)?
    override var acceptsFirstResponder: Bool { false }
    override func validateProposedFirstResponder(_ responder: NSResponder, for event: NSEvent?) -> Bool {
        if responder is DocumentCard { return true }
        return super.validateProposedFirstResponder(responder, for: event)
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onClose?(); return }
        if event.charactersIgnoringModifiers == "f", event.modifierFlags.contains(.command) { onSearch?(); return }
        super.keyDown(with: event)
    }
}

@MainActor
private final class DocumentMoreButton: PointingHandButton {
    var tab: ((Bool) -> Bool)?
    override var acceptsFirstResponder: Bool { true }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 48, event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
           tab?(event.modifierFlags.contains(.shift)) == true { return }
        super.keyDown(with: event)
    }
}

@MainActor
private final class DocumentActionItem: NSMenuItem {
    private let invoke: () -> Void
    init(title: String, invoke: @escaping () -> Void) {
        self.invoke = invoke; super.init(title: title, action: #selector(run), keyEquivalent: ""); target = self
    }
    required init(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    @objc private func run() { invoke() }
}
