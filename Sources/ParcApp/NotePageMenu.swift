import AppKit
import Combine
import UniformTypeIdentifiers

@MainActor
final class NotePageMenu {
    enum ExportFormat: String, CaseIterable {
        case markdown, html, pdf

        var title: String {
            switch self {
            case .markdown: return "Markdown File…"
            case .html: return "HTML File…"
            case .pdf: return "PDF…"
            }
        }

        var contentType: UTType {
            switch self {
            case .markdown: return UTType(filenameExtension: "md") ?? .plainText
            case .html: return .html
            case .pdf: return .pdf
            }
        }

        var fileExtension: String {
            switch self {
            case .markdown: return "md"
            case .html: return "html"
            case .pdf: return "pdf"
            }
        }
    }

    unowned let editor: NotePageEditor
    let file: NoteFileSession?
    var onToast: ((ParcToastContent) -> Void)?
    var onTrashed: ((URL) -> Void)?
    var onOpenHistory: (() -> Void)?
    private var popover: NotePagePopover?
    private var exportPopover: NotePagePopover?
    private weak var content: NotePageMenuView?
    private var subscription: AnyCancellable?

    init(editor: NotePageEditor, file: NoteFileSession?) {
        self.editor = editor
        self.file = file
    }

    var isOpen: Bool { popover?.isOpen == true }

    var url: URL? { file?.url ?? editor.environment.documentURL }

    var title: String {
        if let file { return file.title }
        return url?.deletingPathExtension().lastPathComponent ?? "Untitled"
    }

    var isPlainText: Bool { editor.environment.isPlainText }

    func showToast(_ content: ParcToastContent) {
        if let onToast { onToast(content); return }
        (editor.canvas.window?.windowController as? BrowserWindowController)?.showToast(content)
    }

    func makeButton() -> NotePageMenuButton {
        NotePageMenuButton(menu: self)
    }

    func toggle(from view: NSView, anchor: NSRect? = nil, origin: NoteMenuList.Origin = .pointer) {
        if isOpen { close() } else { present(from: view, anchor: anchor, origin: origin) }
    }

    func present(from view: NSView, anchor: NSRect? = nil, origin: NoteMenuList.Origin = .pointer) {
        close(animated: false)
        let overlay = editor.canvas.overlayView
        let menu = NotePageMenuView(menu: self)
        menu.list.prepare(origin: origin)
        let popover = NotePagePopover(content: menu)
        popover.exempt(view)
        popover.onKeyDown = { [weak menu] event in menu?.list.handleKeyDown(event) ?? false }
        popover.onClose = { [weak self] in
            self?.popover = nil
            self?.subscription = nil
            self?.content = nil
            (view as? NotePageMenuButton)?.menuDidClose()
        }
        self.popover = popover
        content = menu
        subscription = editor.session.changes.sink { [weak self] change in
            guard change.kind != .selection else { return }
            self?.content?.refresh()
        }
        let rect = overlay.convert(anchor ?? view.bounds, from: view)
        popover.present(in: overlay, anchor: rect, edge: .below, alignment: .trailing)
        (view as? NotePageMenuButton)?.menuDidOpen()
    }

    func close(animated: Bool = true) {
        exportPopover?.close(animated: animated)
        popover?.close(animated: animated)
    }

    func items() -> [NoteMenuList.Item] {
        let settings = editor.session.page.settings
        let hasFile = url != nil
        var result: [NoteMenuList.Item] = []
        if !isPlainText {
            result.append(.init(id: "small-text", title: "Small Text", icon: .symbol("textformat.size.smaller"), isChecked: settings.smallText,
                                isEnabled: !editor.session.isReadOnly))
            result.append(.init(id: "full-width", title: "Full Width", icon: .symbol("arrow.left.and.right"), isChecked: settings.fullWidth,
                                isEnabled: !editor.session.isReadOnly))
        }
        result.append(.init(id: "lock", title: settings.locked ? "Unlock Page" : "Lock Page",
                            icon: .symbol(settings.locked ? "lock.open" : "lock"), isChecked: settings.locked,
                            isEnabled: !editor.session.isReadOnly))
        var copy = NoteMenuList.Item(id: "copy-markdown", title: isPlainText ? "Copy Text" : "Copy as Markdown", icon: .symbol("doc.on.doc"))
        copy.separatorBefore = true
        result.append(copy)
        result.append(.init(id: "copy-link", title: "Copy Link", icon: .symbol("link"), isEnabled: hasFile))
        result.append(.init(id: "export", title: "Export", icon: .symbol("square.and.arrow.up"), hasSubmenu: true))
        result.append(.init(id: "reveal", title: "Show in Finder", icon: .symbol("folder"), isEnabled: hasFile))
        result.append(.init(id: "history", title: "Page History", icon: .symbol("clock.arrow.circlepath"), isEnabled: hasFile))
        if isPlainText {
            result.append(.init(id: "turn-markdown", title: "Turn into a Markdown Note", icon: .symbol("doc.richtext"), isEnabled: hasFile))
        }
        var trash = NoteMenuList.Item(id: "trash", title: "Move to Trash", icon: .symbol("trash"), isEnabled: hasFile, isDestructive: true)
        trash.separatorBefore = true
        result.append(trash)
        return result
    }

    func activate(_ item: NoteMenuList.Item, from row: NSRect?) {
        switch item.id {
        case "small-text": toggleSetting("Small Text") { $0.smallText.toggle() }
        case "full-width": toggleSetting("Full Width") { $0.fullWidth.toggle() }
        case "lock":
            let locked = editor.session.page.settings.locked
            editor.session.updateSettings(name: locked ? "Unlock Page" : "Lock Page") { $0.locked.toggle() }
            content?.refresh()
        case "copy-markdown": close(); copyMarkdown()
        case "copy-link": close(); copyLink()
        case "export": presentExport(from: row)
        case "reveal": close(); revealInFinder()
        case "history": close(); showHistory()
        case "turn-markdown": close(); turnIntoMarkdown()
        case "trash": close(); moveToTrash()
        default: break
        }
    }

    func setFont(_ font: NotePageFont) {
        guard editor.session.page.settings.font != font else { return }
        crossfade { self.editor.session.updateSettings(name: "Page Font") { $0.font = font } }
        content?.refresh()
    }

    private func toggleSetting(_ name: String, _ change: (inout NotePageSettings) -> Void) {
        var next = editor.session.page.settings
        change(&next)
        crossfade { self.editor.session.updateSettings(name: name) { $0 = next } }
        content?.refresh()
    }

    func crossfade(_ change: () -> Void) {
        let canvas = editor.canvas!
        let visible = canvas.visibleRect.intersection(canvas.bounds)
        guard !visible.isEmpty, canvas.window != nil, let rep = canvas.bitmapImageRepForCachingDisplay(in: visible) else {
            change()
            return
        }
        canvas.cacheDisplay(in: visible, to: rep)
        let image = NSImage(size: visible.size)
        image.addRepresentation(rep)
        let snapshot = NotePagePassiveImageView(frame: canvas.overlayView.convert(visible, from: canvas))
        snapshot.image = image
        snapshot.imageScaling = .scaleAxesIndependently
        snapshot.wantsLayer = true
        canvas.overlayView.addSubview(snapshot, positioned: .below, relativeTo: canvas.overlayView.subviews.first)
        change()
        canvas.layoutSubtreeIfNeeded()
        guard let layer = snapshot.layer else { snapshot.removeFromSuperview(); return }
        NoteAnimation.fade(layer, to: 0, duration: NoteAnimation.reducedFadeDuration) { [weak snapshot] in
            snapshot?.removeFromSuperview()
        }
    }

    static func markdownForCopy(_ page: NotePage, title: String, plainText: Bool) -> String {
        if plainText { return NotePlainText.serialize(page) }
        return NotePageExport.markdownForCopy(body: NoteMarkdown.serialize(NotePage(blocks: page.blocks)), title: title)
    }

    func copyMarkdown() {
        let text = Self.markdownForCopy(editor.session.page, title: title, plainText: isPlainText)
        let board = NSPasteboard.general
        board.clearContents()
        board.setString(text, forType: .string)
        showToast(.standard(isPlainText ? "Copied Text" : "Copied Markdown"))
    }

    func copyLink() {
        guard let url else { return }
        let board = NSPasteboard.general
        board.clearContents()
        board.writeObjects([url as NSURL])
        board.setString(url.absoluteString, forType: .string)
        showToast(.copiedLinks([url]))
    }

    func revealInFinder() {
        guard let url else { return }
        try? file?.flush()
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func showHistory() {
        if let onOpenHistory { onOpenHistory(); return }
        guard let file else { return }
        NotePageHistory.present(editor: editor, file: file)
    }

    private func presentExport(from row: NSRect?) {
        guard let popover, popover.isOpen else { return }
        exportPopover?.close(animated: false)
        let list = NoteMenuList(items: ExportFormat.allCases.map { format in
            NoteMenuList.Item(id: format.rawValue, title: format.title, icon: .symbol(format == .pdf ? "doc.richtext" : "doc.text"))
        })
        list.minimumWidth = 180
        let child = NotePagePopover(content: list, parent: popover)
        list.onActivate = { [weak self] item in
            guard let self, let format = ExportFormat(rawValue: item.id) else { return }
            self.close()
            self.export(format)
        }
        list.onCancel = { [weak child] in child?.close() }
        list.onCollapse = { [weak child] in child?.close() }
        child.onKeyDown = { [weak list] event in list?.handleKeyDown(event) ?? false }
        child.onClose = { [weak self] in self?.exportPopover = nil }
        exportPopover = child
        let overlay = editor.canvas.overlayView
        let panelFrame = popover.panel.frame
        let anchor = row.map { overlay.convert($0, from: content) } ?? NSRect(x: panelFrame.minX, y: panelFrame.midY, width: panelFrame.width, height: 30)
        let side = NSRect(x: panelFrame.minX, y: anchor.minY, width: panelFrame.width, height: anchor.height)
        child.present(in: overlay, anchor: side, edge: .leading)
        if NSApp.currentEvent?.type == .keyDown { list.prepare(origin: .keyboard); list.moveHighlight(by: 1) }
    }

    func export(_ format: ExportFormat) {
        guard let window = editor.canvas.window else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [format.contentType]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = title + "." + format.fileExtension
        if let folder = url?.deletingLastPathComponent() { panel.directoryURL = folder }
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let destination = panel.url else { return }
            MainActor.assumeIsolated { self?.write(format, to: destination) }
        }
    }

    func write(_ format: ExportFormat, to destination: URL) {
        do {
            switch format {
            case .markdown:
                let text = isPlainText ? NotePlainText.serialize(editor.session.page) : NoteMarkdown.serialize(editor.session.page)
                try Data(text.utf8).write(to: destination, options: .atomic)
                try copyAssets(to: destination.deletingLastPathComponent())
            case .html:
                try Data(htmlDocument().utf8).write(to: destination, options: .atomic)
            case .pdf:
                try writePDF(to: destination)
            }
            showToast(.standard("Exported \(destination.lastPathComponent)"))
        } catch {
            editor.onError?(error)
        }
    }

    func htmlDocument() -> String {
        let environment = editor.environment
        return NotePageHTML.document(editor.session.page, title: title, assets: { environment.resolve($0) }, embedImages: true)
    }

    private func copyAssets(to folder: URL) throws {
        guard let base = url?.deletingLastPathComponent(), base.standardizedFileURL != folder.standardizedFileURL else { return }
        let manager = FileManager.default
        for source in NotePageExport.relativeAssetSources(in: editor.session.page) {
            let decoded = source.removingPercentEncoding ?? source
            let from = URL(fileURLWithPath: decoded, relativeTo: base).standardizedFileURL
            let to = URL(fileURLWithPath: decoded, relativeTo: folder).standardizedFileURL
            guard from.path.hasPrefix(base.standardizedFileURL.path), to.path.hasPrefix(folder.standardizedFileURL.path),
                  manager.fileExists(atPath: from.path), !manager.fileExists(atPath: to.path) else { continue }
            try manager.createDirectory(at: to.deletingLastPathComponent(), withIntermediateDirectories: true)
            try manager.copyItem(at: from, to: to)
        }
    }

    private func writePDF(to destination: URL) throws {
        let html = htmlDocument()
        guard let data = html.data(using: .utf8),
              let text = NSAttributedString(html: data, baseURL: url?.deletingLastPathComponent() ?? FileManager.default.temporaryDirectory,
                                            documentAttributes: nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let info = NSPrintInfo.shared.copy() as? NSPrintInfo ?? NSPrintInfo()
        info.jobDisposition = .save
        info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = destination
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        info.topMargin = 54
        info.bottomMargin = 54
        info.leftMargin = 54
        info.rightMargin = 54
        let width = info.paperSize.width - info.leftMargin - info.rightMargin
        let view = NSTextView(frame: NSRect(x: 0, y: 0, width: width, height: 100))
        view.appearance = NSAppearance(named: .aqua)
        view.drawsBackground = false
        view.textContainerInset = .zero
        view.textStorage?.setAttributedString(text)
        view.isVerticallyResizable = true
        view.sizeToFit()
        let operation = NSPrintOperation(view: view, printInfo: info)
        operation.showsPrintPanel = false
        operation.showsProgressPanel = false
        operation.jobTitle = title
        guard operation.run() else { throw CocoaError(.fileWriteUnknown) }
    }

    func turnIntoMarkdown() {
        guard isPlainText, let url else { return }
        let target = NotePageExport.markdownCopyURL(for: url) { FileManager.default.fileExists(atPath: $0.path) }
        do {
            try file?.flush()
            let text = NoteMarkdown.serialize(NotePage(blocks: editor.session.page.blocks))
            try Data(text.utf8).write(to: target, options: .withoutOverwriting)
            showToast(.standard("Saved a Markdown copy", subLabel: target.lastPathComponent))
            editor.onOpenNote?(target)
        } catch {
            editor.onError?(error)
        }
    }

    func moveToTrash() {
        guard let url, let window = editor.canvas.window else { return }
        let name = title
        ParcDialog.confirm(in: window, title: "Move “\(name)” to the Trash?",
                           message: "You can fish it back out of the Trash in Finder.",
                           confirm: "Move to Trash", destructive: true) { [weak self] (confirmed: Bool) in
            guard confirmed, let self else { return }
            do {
                try? self.file?.flush()
                try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                self.onTrashed?(url)
            } catch {
                self.editor.onError?(error)
            }
        }
    }

    func footerLines() -> (stats: String, edited: String) {
        let stats = NotePageStats(page: editor.session.page)
        let edited: String
        switch file?.state {
        case .unsaved?, .saving?:
            edited = NoteRelativeTime.edited(Date())
        default:
            let date = url.flatMap { try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate }
            edited = NoteRelativeTime.edited(date)
        }
        return (stats.summary, edited)
    }
}

@MainActor
final class NotePagePassiveImageView: NSImageView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

@MainActor
final class NotePageMenuView: NSView, NoteFloatingPanelContent {
    static let width: CGFloat = 284
    unowned let pageMenu: NotePageMenu
    let list: NoteMenuList
    var preferredSizeDidChange: (() -> Void)?
    private var cards: [NotePageFontCard] = []
    private let topSeparator = NSView()
    private let bottomSeparator = NSView()
    private let statsLabel = NSTextField(labelWithString: "")
    private let editedLabel = NSTextField(labelWithString: "")
    private let showsFonts: Bool

    init(menu: NotePageMenu) {
        self.pageMenu = menu
        showsFonts = !menu.isPlainText
        list = NoteMenuList(items: menu.items())
        list.fixedWidth = Self.width
        list.maximumHeight = 600
        super.init(frame: NSRect(x: 0, y: 0, width: Self.width, height: 400))
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Page Options")
        if showsFonts {
            for font in NotePageFont.allCases {
                let card = NotePageFontCard(font: font)
                card.onPress = { [weak menu] in menu?.setFont(font) }
                cards.append(card)
                addSubview(card)
            }
        }
        list.onActivate = { [weak self] item in
            guard let self else { return }
            self.pageMenu.activate(item, from: self.rowRect(for: item.id))
        }
        list.onCancel = { [weak menu] in menu?.close() }
        list.preferredSizeDidChange = { [weak self] in self?.preferredSizeDidChange?() }
        for separator in [topSeparator, bottomSeparator] {
            separator.wantsLayer = true
            addSubview(separator)
        }
        topSeparator.isHidden = !showsFonts
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

    private var cardsHeight: CGFloat { showsFonts ? NotePageFontCard.size.height + 20 : 0 }
    private var footerHeight: CGFloat { 50 }

    override var fittingSize: NSSize {
        NSSize(width: Self.width, height: cardsHeight + list.fittingSize.height + 1 + footerHeight)
    }

    override var intrinsicContentSize: NSSize { fittingSize }

    func refresh() {
        let current = pageMenu.editor.session.page.settings.font
        for card in cards {
            card.isCurrent = card.pageFont == current
            card.isEnabled = !pageMenu.editor.session.isReadOnly
        }
        list.setItems(pageMenu.items(), keepingHighlight: true)
        let lines = pageMenu.footerLines()
        statsLabel.stringValue = lines.stats
        editedLabel.stringValue = lines.edited
        needsLayout = true
        preferredSizeDidChange?()
    }

    func rowRect(for id: String) -> NSRect? {
        guard let index = list.visibleItems.firstIndex(where: { $0.id == id }) else { return nil }
        let separators = list.visibleItems.prefix(index + 1).filter(\.separatorBefore).count
        let headerOffset: CGFloat = 4
        let y = headerOffset + CGFloat(index) * list.rowHeight + CGFloat(separators) * 9
        return convert(NSRect(x: 0, y: y, width: list.frame.width, height: list.rowHeight), from: list)
    }

    override func layout() {
        super.layout()
        var y: CGFloat = 0
        if showsFonts {
            let size = NotePageFontCard.size
            let gap = (bounds.width - 16 - size.width * CGFloat(cards.count)) / CGFloat(max(1, cards.count - 1))
            for (index, card) in cards.enumerated() {
                card.frame = NSRect(x: 8 + CGFloat(index) * (size.width + gap), y: 10, width: size.width, height: size.height)
            }
            y = cardsHeight
            topSeparator.frame = NSRect(x: 0, y: y - 1, width: bounds.width, height: 1)
        }
        let listHeight = list.fittingSize.height
        list.frame = NSRect(x: 0, y: y, width: bounds.width, height: listHeight)
        y += listHeight
        bottomSeparator.frame = NSRect(x: 0, y: y, width: bounds.width, height: 1)
        y += 9
        let statsHeight = ceil(statsLabel.intrinsicContentSize.height)
        statsLabel.frame = NSRect(x: 14, y: y, width: bounds.width - 28, height: statsHeight)
        editedLabel.frame = NSRect(x: 14, y: y + statsHeight + 1, width: bounds.width - 28, height: ceil(editedLabel.intrinsicContentSize.height))
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshAppearance()
    }

    private func refreshAppearance() {
        NoteAnimation.withoutAnimation {
            for separator in [topSeparator, bottomSeparator] {
                separator.layer?.backgroundColor = NoteTheme.resolved(NoteTheme.menuSeparator, in: self)
            }
        }
    }
}

@MainActor
final class NotePageFontCard: NoteControlButton {
    static let size = NSSize(width: 62, height: 66)
    let pageFont: NotePageFont
    var isCurrent = false { didSet { if isCurrent != oldValue { needsDisplay = true; setAccessibilityValue(isCurrent ? "Selected" : nil) } } }

    init(font: NotePageFont) {
        self.pageFont = font
        super.init(frame: NSRect(origin: .zero, size: Self.size))
        cornerRadius = 8
        setAccessibilityLabel("\(Self.name(font)) font")
        setToolTip(Self.name(font) + " font")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    static func name(_ font: NotePageFont) -> String {
        switch font {
        case .standard: return "Default"
        case .serif: return "Serif"
        case .mono: return "Mono"
        case .wide: return "Wide"
        }
    }

    static func sampleFont(_ font: NotePageFont) -> NSFont {
        let base = NoteTheme.titleFont(font)
        return NSFont(descriptor: base.fontDescriptor, size: font == .serif ? 27 : font == .standard ? 25 : 21) ?? base
    }

    override var intrinsicContentSize: NSSize { Self.size }

    override func fill(hovered: Bool, pressed: Bool, checked: Bool) -> NSColor? {
        if isCurrent { return NoteTheme.checkedFill }
        return super.fill(hovered: hovered, pressed: pressed, checked: checked)
    }

    override func drawContent(in bounds: NSRect, ink: NSColor) {
        if let fill = fill(hovered: isHovered, pressed: isPressed, checked: false) {
            fill.setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8).fill()
        }
        if isCurrent {
            NoteTheme.accent.setStroke()
            let ring = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 7, yRadius: 7)
            ring.lineWidth = 2
            ring.stroke()
        }
        let sampleInk = isCurrent ? NoteTheme.checkedInk : NoteTheme.menuInk
        let sample = NSAttributedString(string: "Ag", attributes: [.font: Self.sampleFont(pageFont), .foregroundColor: sampleInk])
        let size = sample.size()
        sample.draw(at: NSPoint(x: bounds.midX - size.width / 2, y: 30 - size.height / 2 + 2))
        let label = NSAttributedString(string: Self.name(pageFont), attributes: [
            .font: NoteTheme.nunitoBold(11.5), .foregroundColor: isCurrent ? NoteTheme.checkedInk : NoteTheme.menuSecondaryInk])
        let labelSize = label.size()
        label.draw(at: NSPoint(x: bounds.midX - labelSize.width / 2, y: bounds.maxY - labelSize.height - 7))
    }
}

@MainActor
final class NotePageMenuButton: NSView {
    static let size = NSSize(width: 30, height: 30)
    unowned let pageMenu: NotePageMenu
    let button = NoteToolbarButton(icon: .symbol("ellipsis"), label: "Page Options")
    private weak var trackedView: NSView?
    private var paneArea: NSTrackingArea?
    private var isPaneHovered = false
    private var isMenuOpen = false
    private var hasKeyboardFocus = false

    init(menu: NotePageMenu) {
        self.pageMenu = menu
        super.init(frame: NSRect(origin: .zero, size: Self.size))
        wantsLayer = true
        button.iconPointSize = 15
        button.onPress = { [weak self] in
            guard let self else { return }
            self.pageMenu.toggle(from: self)
        }
        addSubview(button)
        setAccessibilityElement(false)
        layer?.opacity = 0
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
    override var intrinsicContentSize: NSSize { Self.size }
    override var acceptsFirstResponder: Bool { true }
    override var canBecomeKeyView: Bool { NSApp.isFullKeyboardAccessEnabled }

    override func layout() {
        super.layout()
        button.frame = bounds.insetBy(dx: 1, dy: 1)
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        if let paneArea, let trackedView { trackedView.removeTrackingArea(paneArea) }
        paneArea = nil
        trackedView = superview
        guard let superview else { return }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        superview.addTrackingArea(area)
        paneArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        isPaneHovered = true
        refreshVisibility()
    }

    override func mouseExited(with event: NSEvent) {
        isPaneHovered = false
        refreshVisibility()
    }

    func menuDidOpen() {
        isMenuOpen = true
        button.isChecked = true
        refreshVisibility()
    }

    func menuDidClose() {
        isMenuOpen = false
        button.isChecked = false
        refreshVisibility()
    }

    private func refreshVisibility() {
        guard let layer else { return }
        let visible = isPaneHovered || isMenuOpen || hasKeyboardFocus
        NoteAnimation.fade(layer, to: visible ? 1 : 0, duration: NoteAnimation.hoverDuration)
    }

    override func becomeFirstResponder() -> Bool {
        hasKeyboardFocus = true
        refreshVisibility()
        needsDisplay = true
        return true
    }

    override func resignFirstResponder() -> Bool {
        hasKeyboardFocus = false
        refreshVisibility()
        needsDisplay = true
        return true
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 76, 49, 125: pageMenu.present(from: self, origin: .keyboard)
        default: super.keyDown(with: event)
        }
    }

    override var focusRingMaskBounds: NSRect { bounds }

    override func drawFocusRingMask() {
        NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: NoteTheme.controlRadius, yRadius: NoteTheme.controlRadius).fill()
    }

    override func accessibilityChildren() -> [Any]? { [button] }
}
