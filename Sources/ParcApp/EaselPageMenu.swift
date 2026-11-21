import AppKit
import UniformTypeIdentifiers

@MainActor
final class EaselPageMenu {
    enum ExportFormat: String, CaseIterable {
        case image, html, pdf

        var title: String {
            switch self {
            case .image: return "Image…"
            case .html: return "HTML File…"
            case .pdf: return "PDF…"
            }
        }

        var symbol: String {
            switch self {
            case .image: return "photo"
            case .html: return "doc.text"
            case .pdf: return "doc.richtext"
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

    func items() -> [NoteMenuList.Item] {
        let canAct = editor.canExportImage
        var result: [NoteMenuList.Item] = []
        result.append(.init(id: "copy-link", title: "Copy Link", icon: .symbol("link"), isEnabled: canAct))
        result.append(.init(id: "copy-image", title: "Copy as Image", icon: .symbol("doc.on.doc"), isEnabled: canAct))
        result.append(.init(id: "export", title: "Export", icon: .symbol("square.and.arrow.up"), isEnabled: canAct, hasSubmenu: true))
        var library = NoteMenuList.Item(id: "library", title: "Show in Library", icon: .symbol("books.vertical"),
                                        isEnabled: actions.showInLibrary != nil)
        library.separatorBefore = true
        result.append(library)
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
        case "copy-link": close(); editor.copyLink()
        case "copy-image": close(); editor.copyImage()
        case "export": presentExport(from: row)
        case "library": close(); actions.showInLibrary?()
        case "duplicate": close(); actions.duplicate?()
        case "delete": close(); actions.delete?()
        default: break
        }
    }

    private func presentExport(from row: NSRect?) {
        guard let popover, popover.isOpen else { return }
        exportPopover?.close(animated: false)
        let list = NoteMenuList(items: ExportFormat.allCases.map { format in
            NoteMenuList.Item(id: format.rawValue, title: format.title, icon: .symbol(format.symbol), shortcut: format.shortcut)
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
        return ("\(count) object\(count == 1 ? "" : "s")", NoteRelativeTime.edited(document.modifiedAt))
    }
}

@MainActor
final class EaselPageMenuView: NSView, NoteFloatingPanelContent {
    static let width: CGFloat = 260
    unowned let pageMenu: EaselPageMenu
    let list: NoteMenuList
    var preferredSizeDidChange: (() -> Void)?
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
        list.onActivate = { [weak self] item in
            guard let self else { return }
            self.pageMenu.activate(item, from: self.rowRect(for: item.id))
        }
        list.onCancel = { [weak menu] in menu?.close() }
        list.preferredSizeDidChange = { [weak self] in self?.preferredSizeDidChange?() }
        separator.wantsLayer = true
        statsLabel.font = NoteTheme.nunitoBold(12)
        statsLabel.textColor = NoteTheme.menuSecondaryInk
        editedLabel.font = NoteTheme.nunitoRegular(12)
        editedLabel.textColor = NoteTheme.menuTertiaryInk
        for view in [list, separator, statsLabel, editedLabel] { addSubview(view) }
        let lines = menu.footerLines()
        statsLabel.stringValue = lines.stats
        editedLabel.stringValue = lines.edited
        refreshAppearance()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
    override var fittingSize: NSSize { NSSize(width: Self.width, height: list.fittingSize.height + 1 + 50) }
    override var intrinsicContentSize: NSSize { fittingSize }

    func rowRect(for id: String) -> NSRect? {
        let visible = list.visibleItems
        guard let index = visible.firstIndex(where: { $0.id == id }) else { return nil }
        let separators = visible.prefix(index + 1).enumerated().filter { $0.offset > 0 && $0.element.separatorBefore }.count
        let y = NoteTheme.menuInset + CGFloat(index) * list.rowHeight + CGFloat(separators) * NoteTheme.menuSeparatorSlot
        return convert(NSRect(x: NoteTheme.menuInset, y: y, width: list.frame.width - NoteTheme.menuInset * 2, height: list.rowHeight), from: list)
    }

    override func layout() {
        super.layout()
        let listHeight = list.fittingSize.height
        list.frame = NSRect(x: 0, y: 0, width: bounds.width, height: listHeight)
        separator.frame = NSRect(x: 0, y: listHeight, width: bounds.width, height: 1)
        let y = listHeight + 9
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
            separator.layer?.backgroundColor = NoteTheme.resolved(NoteTheme.menuSeparator, in: self)
        }
    }
}
