import AppKit
import UniformTypeIdentifiers

@MainActor
final class EaselPageMenu {
    enum ExportFormat: String, CaseIterable {
        case image, html, pdf, stickies

        var title: String {
            switch self {
            case .image: return "Image…"
            case .html: return "HTML File…"
            case .pdf: return "PDF…"
            case .stickies: return "Stickies as CSV…"
            }
        }

        var symbol: String {
            switch self {
            case .image: return "photo"
            case .html: return "doc.text"
            case .pdf: return "doc.richtext"
            case .stickies: return "list.bullet.rectangle"
            }
        }

        var shortcut: String? { self == .image ? "⇧⌘S" : nil }
    }

    struct Actions {
        var showInLibrary: (() -> Void)?
        var duplicate: (() -> Void)?
        var delete: (() -> Void)?
    }

    unowned let editor: EaselEditorViewController
    var actions = Actions()
    private var popover: NotePagePopover?
    private var exportPopover: NotePagePopover?
    private weak var content: EaselPageMenuView?
    private weak var anchorButton: NSButton?

    init(editor: EaselEditorViewController) {
        self.editor = editor
    }

    var isOpen: Bool { popover?.isOpen == true }

    func toggle(from button: NSButton) {
        if isOpen { close(); return }
        present(from: button, origin: NSApp.currentEvent?.type == .keyDown ? .keyboard : .pointer)
    }

    func present(from button: NSButton, origin: NoteMenuList.Origin) {
        close(animated: false)
        guard editor.canExportImage else { return }
        let host = editor.view
        let menu = EaselPageMenuView(menu: self)
        menu.list.prepare(origin: origin)
        let popover = NotePagePopover(content: menu)
        popover.exempt(button)
        popover.onKeyDown = { [weak menu] event in menu?.list.handleKeyDown(event) ?? false }
        popover.onClose = { [weak self, weak button] in
            self?.popover = nil
            self?.content = nil
            (button as? EaselPaletteButton)?.state = .off
        }
        self.popover = popover
        content = menu
        anchorButton = button
        popover.present(in: host, anchor: host.convert(button.bounds, from: button), edge: .below, alignment: .trailing)
        if origin == .keyboard { menu.list.moveHighlight(by: 1) }
    }

    func close(animated: Bool = true) {
        exportPopover?.close(animated: animated)
        popover?.close(animated: animated)
    }

    static let toggleIDs: Set<String> = ["lock"]

    func isOn(_ id: String) -> Bool? {
        id == "lock" ? editor.session.document.isLocked : nil
    }

    static func page(font family: EaselTextStyle.Family) -> NotePageFont {
        switch family {
        case .clean: return .standard
        case .fancy: return .serif
        case .mono: return .mono
        case .hip: return .wide
        }
    }

    static func family(font: NotePageFont) -> EaselTextStyle.Family {
        switch font {
        case .standard: return .clean
        case .serif: return .fancy
        case .mono: return .mono
        case .wide: return .hip
        }
    }

    func setDefaultFamily(_ font: NotePageFont) {
        editor.setDefaultFamily(Self.family(font: font))
        content?.refresh()
    }

    func items() -> [NoteMenuList.Item] {
        let canAct = editor.canExportImage
        var result: [NoteMenuList.Item] = []
        let locked = editor.session.document.isLocked
        var lock = NoteMenuList.Item(id: "lock", title: "Lock Easel", icon: .symbol(locked ? "lock.fill" : "lock"), isEnabled: canAct)
        lock.accessibilityLabel = "Lock Easel" + (locked ? ", on" : ", off")
        result.append(lock)
        var copy = NoteMenuList.Item(id: "copy-markdown", title: "Copy as Markdown", icon: .symbol("doc.on.doc"), isEnabled: canAct)
        copy.separatorBefore = true
        result.append(copy)
        result.append(.init(id: "copy-link", title: "Copy Link", icon: .symbol("link"), isEnabled: canAct))
        result.append(.init(id: "copy-image", title: "Copy as Image", icon: .symbol("photo.on.rectangle"), isEnabled: canAct))
        result.append(.init(id: "export", title: "Export", icon: .symbol("square.and.arrow.up"), isEnabled: canAct, hasSubmenu: true))
        var library = NoteMenuList.Item(id: "library", title: "Show in Library", icon: .symbol("books.vertical"),
                                        isEnabled: actions.showInLibrary != nil)
        library.separatorBefore = true
        result.append(library)
        result.append(.init(id: "templates", title: "Templates…", icon: .symbol("square.grid.2x2"),
                            isEnabled: canAct && editor.canvas.acceptsTemplates))
        result.append(.init(id: "history", title: "Easel History", icon: .symbol("clock.arrow.circlepath"), isEnabled: canAct))
        result.append(.init(id: "duplicate", title: "Duplicate", icon: .symbol("plus.square.on.square"),
                            isEnabled: canAct && actions.duplicate != nil))
        var delete = NoteMenuList.Item(id: "delete", title: "Delete Easel…", icon: .symbol("trash"),
                                       isEnabled: canAct && actions.delete != nil, isDestructive: true)
        delete.separatorBefore = true
        result.append(delete)
        return result
    }

    func activate(_ item: NoteMenuList.Item, from row: NSRect?) {
        switch item.id {
        case "lock":
            editor.toggleLock()
            content?.refresh()
        case "copy-markdown": close(); editor.copyMarkdown()
        case "copy-link": close(); editor.copyLink()
        case "copy-image": close(); editor.copyImage()
        case "export": presentExport(from: row)
        case "library": close(); actions.showInLibrary?()
        case "history": close(); EaselHistoryPanel.present(editor: editor)
        case "templates": close(); EaselTemplatePanel.present(editor: editor)
        case "duplicate": close(); actions.duplicate?()
        case "delete": close(); actions.delete?()
        default: break
        }
    }

    private func presentExport(from row: NSRect?) {
        guard let popover, popover.isOpen else { return }
        exportPopover?.close(animated: false)
        let hasStickies = !EaselSelectionExport.stickies(in: editor.session.document).isEmpty
        let list = NoteMenuList(items: ExportFormat.allCases.map { format in
            var item = NoteMenuList.Item(id: format.rawValue, title: format.title, icon: .symbol(format.symbol), shortcut: format.shortcut,
                                         isEnabled: format != .stickies || hasStickies)
            item.separatorBefore = format == .stickies
            return item
        })
        list.minimumWidth = 180
        let child = NotePagePopover(content: list, parent: popover)
        list.onActivate = { [weak self] item in
            guard let self, let format = ExportFormat(rawValue: item.id) else { return }
            self.close()
            self.editor.export(format)
        }
        list.onCancel = { [weak child] in child?.close() }
        list.onCollapse = { [weak child] in child?.close() }
        child.onKeyDown = { [weak list] event in list?.handleKeyDown(event) ?? false }
        child.onClose = { [weak self] in self?.exportPopover = nil }
        exportPopover = child
        let host = editor.view
        let panelFrame = popover.panel.frame
        let anchor = row.flatMap { rect in content.map { host.convert(rect, from: $0) } }
            ?? NSRect(x: panelFrame.minX, y: panelFrame.midY, width: panelFrame.width, height: 30)
        child.present(in: host, anchor: NSRect(x: panelFrame.minX, y: anchor.minY, width: panelFrame.width, height: anchor.height), edge: .leading)
        if NSApp.currentEvent?.type == .keyDown { list.prepare(origin: .keyboard); list.moveHighlight(by: 1) }
    }

    func footerLines() -> (stats: String, edited: String) {
        let document = editor.session.document
        let count = document.items.count
        let objects = "\(count) object\(count == 1 ? "" : "s")"
        let words = EaselBoardText.stats(of: document)
        let summary = words.words == 0 ? objects : objects + " · " + words.wordLabel + " · " + words.readingLabel
        return (summary, NoteRelativeTime.edited(document.modifiedAt))
    }
}

@MainActor
final class EaselPageMenuView: NSView, NoteFloatingPanelContent {
    static let width: CGFloat = 284
    private weak var pageMenu: EaselPageMenu?
    let list: NoteMenuList
    var preferredSizeDidChange: (() -> Void)?
    private var cards: [NotePageFontCard] = []
    private var switches: [String: NotePageMenuSwitch] = [:]
    private let topSeparator = NSView()
    private let separator = NSView()
    private let statsLabel = NSTextField(labelWithString: "")
    private let editedLabel = NSTextField(labelWithString: "")

    init(menu: EaselPageMenu) {
        pageMenu = menu
        list = NoteMenuList(items: menu.items())
        list.fixedWidth = Self.width
        list.maximumHeight = 600
        super.init(frame: NSRect(x: 0, y: 0, width: Self.width, height: 300))
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Easel Options")
        for font in NotePageFont.allCases {
            let card = NotePageFontCard(font: font)
            card.setToolTip(NotePageFontCard.name(font) + " text for new objects")
            card.setAccessibilityLabel("\(NotePageFontCard.name(font)) text for new objects")
            card.onPress = { [weak menu] in menu?.setDefaultFamily(font) }
            cards.append(card)
            addSubview(card)
        }
        list.onActivate = { [weak self] item in
            guard let self else { return }
            self.pageMenu?.activate(item, from: self.rowRect(for: item.id))
        }
        list.onCancel = { [weak menu] in menu?.close() }
        list.preferredSizeDidChange = { [weak self] in self?.preferredSizeDidChange?() }
        for view in [topSeparator, separator] {
            view.wantsLayer = true
            addSubview(view)
        }
        statsLabel.font = NoteTheme.nunitoBold(12)
        statsLabel.textColor = NoteTheme.menuSecondaryInk
        editedLabel.font = NoteTheme.nunitoRegular(12)
        editedLabel.textColor = NoteTheme.menuTertiaryInk
        addSubview(list)
        addSubview(statsLabel)
        addSubview(editedLabel)
        refresh()
        refreshAppearance()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    private var cardsHeight: CGFloat { NotePageFontCard.size.height + 20 }
    private var footerHeight: CGFloat { 50 }

    override var fittingSize: NSSize {
        NSSize(width: Self.width, height: cardsHeight + list.fittingSize.height + 1 + footerHeight)
    }

    override var intrinsicContentSize: NSSize { fittingSize }

    func refresh() {
        guard let pageMenu else { return }
        let current = EaselPageMenu.page(font: pageMenu.editor.session.document.resolvedDefaultFamily)
        let editable = !pageMenu.editor.session.document.isLocked
        for card in cards {
            card.isCurrent = card.pageFont == current
            card.isEnabled = editable
        }
        let items = pageMenu.items()
        list.setItems(items, keepingHighlight: true)
        refreshSwitches(items)
        let lines = pageMenu.footerLines()
        statsLabel.stringValue = lines.stats
        editedLabel.stringValue = lines.edited
        needsLayout = true
        preferredSizeDidChange?()
    }

    private func refreshSwitches(_ items: [NoteMenuList.Item]) {
        guard let pageMenu else { return }
        for item in items where EaselPageMenu.toggleIDs.contains(item.id) {
            let on = pageMenu.isOn(item.id) ?? false
            let view = switches[item.id] ?? {
                let created = NotePageMenuSwitch(isOn: on)
                addSubview(created, positioned: .above, relativeTo: list)
                switches[item.id] = created
                return created
            }()
            view.isOn = on
            view.isEnabled = item.isEnabled
        }
    }

    func rowRect(for id: String) -> NSRect? {
        let visible = list.visibleItems
        guard let index = visible.firstIndex(where: { $0.id == id }) else { return nil }
        let separators = visible.prefix(index + 1).enumerated().filter { $0.offset > 0 && $0.element.separatorBefore }.count
        let y = NoteTheme.menuInset + CGFloat(index) * list.rowHeight + CGFloat(separators) * NoteTheme.menuSeparatorSlot
        return convert(NSRect(x: NoteTheme.menuInset, y: y, width: list.frame.width - NoteTheme.menuInset * 2, height: list.rowHeight), from: list)
    }

    override func layout() {
        super.layout()
        let size = NotePageFontCard.size
        let gap = (bounds.width - 16 - size.width * CGFloat(cards.count)) / CGFloat(max(1, cards.count - 1))
        for (index, card) in cards.enumerated() {
            card.frame = NSRect(x: 8 + CGFloat(index) * (size.width + gap), y: 10, width: size.width, height: size.height)
        }
        topSeparator.frame = NSRect(x: 0, y: cardsHeight - 1, width: bounds.width, height: 1)
        let listHeight = list.fittingSize.height
        list.frame = NSRect(x: 0, y: cardsHeight, width: bounds.width, height: listHeight)
        let switchSize = NotePageMenuSwitch.size
        for (id, view) in switches {
            guard let row = rowRect(for: id) else { view.isHidden = true; continue }
            view.isHidden = false
            view.frame = NSRect(x: row.maxX - 10 - switchSize.width, y: (row.midY - switchSize.height / 2).rounded(),
                                width: switchSize.width, height: switchSize.height)
        }
        let top = cardsHeight + listHeight
        separator.frame = NSRect(x: 0, y: top, width: bounds.width, height: 1)
        let y = top + 9
        let statsHeight = ceil(statsLabel.intrinsicContentSize.height)
        statsLabel.frame = NSRect(x: 14, y: y, width: bounds.width - 28, height: statsHeight)
        editedLabel.frame = NSRect(x: 14, y: y + statsHeight + 1, width: bounds.width - 28, height: ceil(editedLabel.intrinsicContentSize.height))
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshAppearance()
        redisplayChromeSubtree()
    }

    private func refreshAppearance() {
        NoteAnimation.withoutAnimation {
            for view in [topSeparator, separator] {
                view.layer?.backgroundColor = NoteTheme.resolved(NoteTheme.menuSeparator, in: self)
            }
        }
    }
}
