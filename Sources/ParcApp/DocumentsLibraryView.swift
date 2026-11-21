import AppKit
import Combine

enum DocumentCardChrome {
    static let side: CGFloat = 140
    static let padding: CGFloat = 12
    static let artwork: CGFloat = 18
    static let radius: CGFloat = 12
    static let titleSize: CGFloat = 15
    static let previewSize: CGFloat = 12
    static let dateSize: CGFloat = 11
    static let emojiSize: CGFloat = 16
    static let gap: CGFloat = 8
    static let lineGap: CGFloat = 4
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
        let item: DocumentsLibraryItem
        let page: InternalPage
        var title: String { item.title }
    }
    private static let searchLimit = 10_000
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
    private var library: NoteLibrary?
    private var subscription: AnyCancellable?
    private var folderSubscription: AnyCancellable?
    private var observedInputs: DocumentsLibraryInputs?
    private let scopeBar = DocumentsFolderScopeBar()
    private(set) var folderScope: URL?
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
            scopeBar.restyle()
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
        scopeBar.isHidden = true
        scopeBar.onClear = { [weak self] in self?.scope(to: nil) }
        for view in [searchBackdrop, createButton, scopeBar, scroll, empty] { addSubview(view) }
        if !store.isEphemeral {
            folderSubscription = NoteFolderPreferences.changes.filter { $0 == profileID }.sink { [weak self] _ in
                self?.bindLibrary(); self?.reload(force: true)
            }
            bindLibrary()
        }
        reload(force: true)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    private var chromeDark: Bool {
        palette?.isDark ?? (effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua)
    }
    func scope(to folder: URL?) {
        var next = folder.map { URL(fileURLWithPath: NoteFilePaths.canonical($0).path, isDirectory: true) }
        if let chosen = next, !store.isEphemeral, chosen.path == NoteFolderPreferences.library(for: profileID).folder.path { next = nil }
        guard next?.path != folderScope?.path else { return }
        folderScope = next
        scopeBar.isHidden = next == nil
        if let next { scopeBar.show(next) }
        let title = next.map { "New Note in " + DocumentsFolderScopeBar.name(of: $0) } ?? "New Note"
        createButton.setAccessibilityLabel(title)
        LiveShortcutToolTip.set(createButton, title)
        selectedPage = nil
        guard !store.isEphemeral else { return }
        bindLibrary()
        reload(force: true)
        needsLayout = true
    }
    private func bindLibrary() {
        let space = NoteFolderPreferences.library(for: profileID)
        let next: NoteLibrary
        if let folderScope, folderScope.path != space.folder.path, !space.contains(folderScope) {
            next = NoteLibrary.browsing(folderScope)
        } else {
            next = space
        }
        guard next !== library else { return }
        library = next
        subscription = next.changes.sink { [weak self] in self?.reload() }
    }
    func focusSearch() { window?.makeFirstResponder(search); search.selectText(nil) }
    func reload(force: Bool = false) {
        let selected = selectedPage
        guard !store.isEphemeral, let library else {
            observedInputs = nil
            rows = []; selectedPage = nil; rebuildCards()
            empty.isHidden = true
            createButton.isEnabled = false
            return
        }
        do {
            let directory = store.easelsDirectory(for: profileID)
            let inputs = try DocumentsLibraryCatalog.inputs(
                library: library, easels: { try EaselEditorViewController.sharedStore(directory: directory).list() },
                pending: store.isProfileRemovalPending(profileID), query: search.stringValue, searchLimit: Self.searchLimit,
                folder: folderScope)
            if !force && inputs == observedInputs { return }
            observedInputs = inputs
            let next = DocumentsLibraryCatalog.visible(inputs).compactMap(Self.row)
            empty.stringValue = next.isEmpty ? DocumentsLibraryCatalog.emptyMessage(query: inputs.query, scoped: folderScope != nil) : ""
            empty.isHidden = !next.isEmpty
            selectedPage = next.contains(where: { $0.page == selected }) ? selected : nil
            let sameCards = next == rows
            rows = next
            if !sameCards { rebuildCards() }
            createButton.isEnabled = !inputs.pending
        } catch {
            observedInputs = nil
            rows = []; selectedPage = nil; rebuildCards()
            empty.stringValue = error.localizedDescription; empty.isHidden = false
            createButton.isEnabled = !store.isProfileRemovalPending(profileID)
        }
    }

    private static func row(_ item: DocumentsLibraryItem) -> Row? {
        if let url = item.noteURL { return Row(item: item, page: .note(url)) }
        return item.easelID.map { Row(item: item, page: .easel($0)) }
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
        let dark = chromeDark, now = Date()
        for index in (row * 2)..<min(rows.count, row * 2 + 2) {
            let item = rows[index]
            let card = DocumentCard(item: item.item, dark: dark, now: now)
            card.identifier = NSUserInterfaceItemIdentifier("document-\(index)")
            card.isSelected = item.page == selectedPage
            card.select = { [weak self] in self?.selectedPage = item.page; self?.updateSelection() }
            card.open = { [weak self] in
                guard let self else { return }; self.selectedPage = item.page; self.updateSelection(); self.open(item)
            }
            card.move = { [weak self] delta in self?.moveSelection(from: index, by: delta) ?? false }
            card.rename = { [weak self] in self?.rename(item) }
            card.reveal = { [weak self] in self?.reveal(item) }
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
    @objc private func createNote() {
        guard valid else { return }
        guard let folderScope else { onCreate?(); return }
        do {
            let url = try NoteLibrary.createNote(in: folderScope, title: nil)
            onOpen?(.note(url), url.deletingPathExtension().lastPathComponent)
        } catch { report(error) }
    }
    private func open(_ row: Row) { guard valid else { return }; onOpen?(row.page, row.title) }
    private func report(_ error: Error) {
        guard let window else { return }
        ParcDialog.inform(in: window, .init(error: error), queued: true)
    }
    private func rename(_ row: Row) {
        guard valid, let window, window.attachedSheet == nil else { return }
        let dialog = ParcDialog(.init(title: [(row.item.isNote ? "Rename Note" : "Rename Easel", false)],
            confirm: "Rename", cancel: "Cancel", field: .init(value: row.title, placeholder: "", required: false)))
        guard let field = dialog.textField else { return }
        _ = dialog.begin(for: window) { [weak self] result in
            guard let self, result == .confirm, self.valid else { return }
            do {
                if let url = row.item.noteURL {
                    let renamed = try NoteLibrary.rename(url, to: field.stringValue)
                    let title = renamed.deletingPathExtension().lastPathComponent
                    self.store.updateNoteFile(from: url, to: renamed, title: title)
                    if self.selectedPage == row.page { self.selectedPage = .note(renamed) }
                    self.onRename?(.note(renamed), title)
                } else if let id = row.item.easelID {
                    let session = try EaselEditorViewController.sharedStore(directory: self.store.easelsDirectory(for: self.profileID)).load(id)
                    guard session.document.title == row.title else { throw DocumentsLibraryRenameError.changed }
                    try session.perform("Rename Easel") { $0.title = field.stringValue.isEmpty ? DocumentsLibraryCatalog.untitledEasel : field.stringValue }
                    self.onRename?(row.page, field.stringValue)
                }
                self.reload()
            } catch { self.reload(); self.report(error) }
        }
    }
    private func reveal(_ row: Row) {
        guard valid, let url = row.item.noteURL else { return }
        guard FileManager.default.fileExists(atPath: url.path) else { reload(force: true); report(NoteFileError.missing); return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
    private func delete(_ row: Row) {
        guard valid, let window, window.attachedSheet == nil else { return }
        let note = row.item.isNote
        ParcDialog.confirm(in: window, title: note ? "Move “\(row.title)” to the Trash?" : "Are you sure you want to delete this Easel?",
                          message: note ? "Any tabs showing it close too. You can fish it out of the Trash later." : "Doing so will delete the Easel permanently.",
                          confirm: note ? "Move to Trash" : "Delete", destructive: true) { [weak self] approved in
            guard let self, approved, self.valid else { return }
            self.onDelete?(row.page) { [weak self] error in
                guard let self else { return }
                self.reload()
                if let error, (error as? CocoaError)?.code != .userCancelled { self.report(error) }
            }
        }
    }
    override func layout() {
        super.layout(); let w = bounds.width, h = bounds.height
        let create = LibraryPageHeader.height, inset = LibraryPageHeader.inset, top = LibraryPageHeader.top
        searchBackdrop.frame = NSRect(x: inset, y: top, width: max(0, w - 2 * inset - LibraryPageHeader.spacing - create), height: create)
        createButton.frame = NSRect(x: max(inset, w - inset - create), y: top, width: create, height: create)
        let scopeHeight: CGFloat = scopeBar.isHidden ? 0 : DocumentsFolderScopeBar.height + 4
        scopeBar.frame = NSRect(x: inset, y: LibraryPageHeader.contentTop, width: max(0, w - 2 * inset), height: DocumentsFolderScopeBar.height)
        let contentTop = LibraryPageHeader.contentTop + scopeHeight
        scroll.frame = NSRect(x: 0, y: contentTop, width: w, height: max(0, h - contentTop))
        let cardSide = min(DocumentCardChrome.side, max(0, (scroll.contentSize.width - 36) / 2))
        if grid.rowHeight != cardSide + 24 { grid.rowHeight = cardSide + 24 }
        empty.frame = NSRect(x: 24, y: 110 + scopeHeight, width: max(0, w - 48), height: 48)
    }
}

@MainActor
private final class DocumentsFolderScopeBar: NSView {
    static let height: CGFloat = 30
    private let icon = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private let clear = ActionButton("", symbol: "xmark")
    var onClear: (() -> Void)?
    override var isFlipped: Bool { true }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.cornerCurve = .continuous
        icon.imageScaling = .scaleProportionallyDown
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        icon.setAccessibilityElement(false)
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.lineBreakMode = .byTruncatingMiddle
        label.setAccessibilityElement(false)
        clear.actionBlock = { [weak self] in self?.onClear?() }
        clear.focusRingCornerRadius = 6
        clear.setAccessibilityLabel("Show All Notes")
        LiveShortcutToolTip.set(clear, "Show All Notes")
        for view in [icon, label, clear] as [NSView] { addSubview(view) }
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        restyle()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    static func name(of folder: URL) -> String {
        let name = FileManager.default.displayName(atPath: folder.path)
        return name.isEmpty ? folder.lastPathComponent : name
    }

    static func symbol(for folder: URL) -> String {
        if folder.path == "/" || folder.deletingLastPathComponent().path == "/Volumes" { return "internaldrive" }
        if folder.path == FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path { return "house" }
        return "folder"
    }

    func show(_ folder: URL) {
        let name = Self.name(of: folder)
        icon.image = NSImage(systemSymbolName: Self.symbol(for: folder), accessibilityDescription: nil)
        label.stringValue = name
        LiveShortcutToolTip.set(self, (folder.path as NSString).abbreviatingWithTildeInPath)
        setAccessibilityLabel("Showing notes in " + name)
        needsLayout = true
    }

    func restyle() {
        icon.contentTintColor = .secondaryLabelColor
        label.textColor = .labelColor
        clear.contentTintColor = .secondaryLabelColor
        needsDisplay = true
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        layer?.backgroundColor = NSColor(white: dark ? 1 : 0, alpha: dark ? 0.08 : 0.05).cgColor
    }

    override func layout() {
        super.layout()
        let h = bounds.height
        icon.frame = NSRect(x: 9, y: (h - 18) / 2, width: 18, height: 18)
        clear.frame = NSRect(x: bounds.width - 4 - 24, y: (h - 24) / 2, width: 24, height: 24)
        let labelHeight = ceil(label.intrinsicContentSize.height)
        label.frame = NSRect(x: icon.frame.maxX + 6, y: (h - labelHeight) / 2, width: max(0, clear.frame.minX - icon.frame.maxX - 12),
                             height: labelHeight)
    }
}

@MainActor
private final class DocumentCard: NSView {
    var open: (() -> Void)?
    var select: (() -> Void)?
    var rename: (() -> Void)?
    var reveal: (() -> Void)?
    var delete: (() -> Void)?
    var dismiss: (() -> Void)?
    var move: ((Int) -> Bool)?
    var isSelected = false { didSet { needsDisplay = true } }
    private let titleLabel: NSTextField
    private let previewLabel: NSTextField
    private let dateLabel: NSTextField
    private let emojiLabel: NSTextField
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
    init(item: DocumentsLibraryItem, dark: Bool, now: Date) {
        isNote = item.isNote
        self.dark = dark
        titleLabel = NSTextField(wrappingLabelWithString: item.title)
        previewLabel = NSTextField(wrappingLabelWithString: item.preview)
        let age = DocumentsLibraryCatalog.edited(item.modified, now: now)
        dateLabel = NSTextField(labelWithString: age)
        emojiLabel = NSTextField(labelWithString: item.emoji ?? "")
        super.init(frame: .zero)
        setAccessibilityRole(.button)
        setAccessibilityLabel(item.title)
        setAccessibilityHelp((isNote ? "Note" : "Easel") + ", edited " + age.lowercased())
        if !item.preview.isEmpty { setAccessibilityValue(item.preview) }
        wantsLayer = true; focusRingType = .exterior
        updateArtwork()
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.isHidden = item.emoji != nil
        emojiLabel.isHidden = item.emoji == nil
        emojiLabel.font = .systemFont(ofSize: DocumentCardChrome.emojiSize)
        emojiLabel.alignment = .center
        titleLabel.font = .systemFont(ofSize: DocumentCardChrome.titleSize, weight: .semibold)
        titleLabel.textColor = DocumentCardChrome.title(dark: dark)
        titleLabel.lineBreakMode = .byWordWrapping
        titleLabel.cell?.truncatesLastVisibleLine = true
        previewLabel.font = .systemFont(ofSize: DocumentCardChrome.previewSize)
        previewLabel.textColor = DocumentCardChrome.title(dark: dark).withAlphaComponent(0.55)
        previewLabel.lineBreakMode = .byWordWrapping
        previewLabel.cell?.truncatesLastVisibleLine = true
        previewLabel.isHidden = item.preview.isEmpty
        dateLabel.font = .systemFont(ofSize: DocumentCardChrome.dateSize)
        dateLabel.textColor = DocumentCardChrome.title(dark: dark).withAlphaComponent(0.4)
        dateLabel.lineBreakMode = .byTruncatingTail
        for label in [titleLabel, previewLabel, dateLabel, emojiLabel] { label.setAccessibilityElement(false) }
        for view in [icon, titleLabel, emojiLabel, previewLabel, dateLabel, more] { addSubview(view) }
        more.isBordered = false
        more.image = NSImage(systemSymbolName: "ellipsis", accessibilityDescription: "More")
        more.contentTintColor = DocumentCardChrome.title(dark: dark).withAlphaComponent(0.45)
        more.target = self; more.action = #selector(showMenu); more.setAccessibilityLabel("More actions for \(item.title)")
        more.alphaValue = 0
        more.tab = { [weak self] backwards in
            guard let self else { return false }
            if backwards { return self.window?.makeFirstResponder(self) ?? false }
            return self.move?(1) ?? false
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    private func updateArtwork() {
        icon.image = (isNote ? DocumentDefaultIcon.note : .easel).card(dark: dark)
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
        emojiLabel.frame = NSRect(x: pad - 3, y: pad - 2, width: art + 6, height: art + 4)
        more.frame = NSRect(x: max(0, bounds.width - 36), y: 4, width: 32, height: 32)
        let textWidth = max(0, bounds.width - pad * 2)
        let dateHeight = ceil(dateLabel.intrinsicContentSize.height)
        dateLabel.frame = NSRect(x: pad, y: max(0, bounds.height - pad - dateHeight), width: textWidth, height: dateHeight)
        let titleTop = pad + art + DocumentCardChrome.gap
        let bottom = dateLabel.frame.minY - DocumentCardChrome.lineGap
        let titleLine = ceil(titleLabel.font.map { $0.ascender - $0.descender + $0.leading } ?? 18)
        let titleRoom = max(titleLine, floor(max(0, bottom - titleTop) / titleLine) * titleLine)
        titleLabel.maximumNumberOfLines = 0
        let titleFit = ceil(titleLabel.sizeThatFits(NSSize(width: textWidth, height: .greatestFiniteMagnitude)).height)
        let titleHeight = min(titleRoom, max(titleLine, titleFit))
        titleLabel.maximumNumberOfLines = max(1, Int((titleRoom / titleLine).rounded()))
        titleLabel.frame = NSRect(x: pad, y: titleTop, width: textWidth, height: titleHeight)
        let previewTop = titleLabel.frame.maxY + DocumentCardChrome.lineGap
        let previewLine = ceil(previewLabel.font.map { $0.ascender - $0.descender + $0.leading } ?? 15)
        let previewLines = previewLabel.stringValue.isEmpty ? 0 : Int(max(0, bottom - previewTop) / previewLine)
        previewLabel.isHidden = previewLines == 0
        previewLabel.maximumNumberOfLines = previewLines
        previewLabel.frame = NSRect(x: pad, y: previewTop, width: textWidth, height: CGFloat(previewLines) * previewLine)
        needsDisplay = true
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let next = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .cursorUpdate, .activeInKeyWindow, .inVisibleRect], owner: self)
        tracking = next; addTrackingArea(next)
    }
    override func cursorUpdate(with event: NSEvent) { NSCursor.pointingHand.set() }
    override func mouseEntered(with event: NSEvent) { hovered = isTopmost(atWindowPoint: event.locationInWindow) }
    override func mouseMoved(with event: NSEvent) {
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { super.mouseMoved(with: event); return }
        let value = isTopmost(atWindowPoint: event.locationInWindow)
        if value != hovered { hovered = value }
    }
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
        if isNote {
            menu.addItem(DocumentActionItem(title: "Show in Finder", invoke: { [weak self] in self?.reveal?() }))
            menu.addItem(.separator())
            menu.addItem(DocumentActionItem(title: "Move to Trash…", invoke: { [weak self] in self?.delete?() }))
        } else {
            menu.addItem(DocumentActionItem(title: "Delete…", invoke: { [weak self] in self?.delete?() }))
        }
        return menu
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
