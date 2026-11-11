import AppKit

@MainActor
final class SidebarPreviewCard: SidebarPreviewSurface, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
    static let searchMiss = "No tabs matching that search\n🤔"
    var onAction: ((SidebarPreviewRow, SidebarPreviewAction) -> Void)?
    var onEscape: (() -> Void)?
    var onSettings: (() -> Void)?
    var onHeightChange: (() -> Void)?
    var requestFavicon: ((URL, @escaping (NSImage?) -> Void) -> Void)? { didSet { loadProviderIcon() } }
    var modifierFlags: () -> NSEvent.ModifierFlags = { NSEvent.modifierFlags }
    private let domain: SidebarRecentDomain?
    private let providerURL: URL?
    private let icon = NSImageView()
    private let heading = NSTextField(labelWithString: "Recents")
    private let create = ActionButton("New Page", symbol: "plus")
    private let settings = ActionButton("Previews Settings", symbol: "gearshape")
    private let split = ActionButton("Open in Split View", symbol: "rectangle.split.2x1")
    private let site = NSTextField(labelWithString: "")
    private let picture = SidebarPreviewPicture()
    private let showsPicture: Bool
    private let search = NSTextField()
    private let divider = SidebarPreviewDivider()
    private let message = NSTextField(wrappingLabelWithString: "")
    private let scroll = NSScrollView()
    private let table = SidebarPreviewTable()
    private var rows: [SidebarPreviewRow] = []
    private var filtered: [SidebarPreviewRow] = []
    private var icons: [URL: NSImage] = [:]
    private var requestedIcons: Set<URL> = []
    private var dataGeneration: UInt64 = 0
    private var providerIconRequested = false
    private var trackedMenu: NSMenu?

    init(title: String, domain: SidebarRecentDomain?, providerURL: URL?, picture image: NSImage? = nil, site: String = "") {
        self.domain = domain; self.providerURL = providerURL; showsPicture = image != nil
        super.init(frame: .zero)
        if domain != nil || image != nil { fill = SidebarPreviewColors.background }
        let primary = SidebarPreviewColors.primary(1), secondary = SidebarPreviewColors.primary(0.5)
        if domain != nil || image != nil {
            icon.image = NSImage(systemSymbolName: image != nil ? "globe" : "doc.text", accessibilityDescription: nil)
            icon.imageScaling = .scaleProportionallyUpOrDown; icon.contentTintColor = secondary
            heading.font = .systemFont(ofSize: 13, weight: .semibold); heading.textColor = primary
            heading.lineBreakMode = .byTruncatingTail
        }
        if let image {
            heading.stringValue = title
            self.site.stringValue = site
            self.site.font = .systemFont(ofSize: 11); self.site.textColor = secondary; self.site.lineBreakMode = .byTruncatingTail
            Self.styleHeaderButton(split, label: "Open in Split View", tint: secondary)
            split.actionBlock = { [weak self] in
                guard let self, let row = self.rows.first else { return }
                self.onAction?(row, .split)
            }
            picture.image = image
            for view in [icon, heading, self.site, split, picture] as [NSView] { content.addSubview(view) }
            setAccessibilityElement(false)
            return
        }
        if let domain {
            for (button, label) in [(create, domain.createTitle), (settings, "Previews Settings")] {
                Self.styleHeaderButton(button, label: label, tint: secondary)
            }
            create.actionBlock = { [weak self] in
                guard let self else { return }
                self.onAction?(SidebarPreviewRow(id: domain.createURL.absoluteString, tabID: nil, title: domain.createTitle,
                    url: domain.createURL, visitedAt: nil), .create(self.modifiers))
            }
            settings.actionBlock = { [weak self] in self?.onSettings?() }
            for view in [icon, heading, create, settings] as [NSView] { content.addSubview(view) }
        } else {
            icon.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 12, weight: .heavy))
            icon.contentTintColor = secondary
            let placeholder = "Search " + title
            search.isBordered = false; search.isBezeled = false; search.drawsBackground = false
            search.focusRingType = .none; search.usesSingleLineMode = true
            search.cell?.isScrollable = true; search.cell?.wraps = false
            search.font = .systemFont(ofSize: 13); search.textColor = primary
            search.placeholderAttributedString = NSAttributedString(string: placeholder,
                attributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.placeholderTextColor])
            search.setAccessibilityLabel(placeholder)
            search.delegate = self
            divider.wantsLayer = true
            for view in [icon, search, divider] as [NSView] { content.addSubview(view) }
        }
        message.font = .systemFont(ofSize: 13); message.textColor = .secondaryLabelColor; message.alignment = .center
        let column = NSTableColumn(identifier: .init("page")); column.resizingMask = .autoresizingMask
        table.addTableColumn(column); table.headerView = nil
        table.rowHeight = SidebarPreviewItemView.height; table.intercellSpacing = NSSize(width: 0, height: 1)
        table.backgroundColor = .clear; table.focusRingType = .none
        table.style = .plain; table.selectionHighlightStyle = .none
        table.allowsEmptySelection = true; table.allowsMultipleSelection = false
        table.delegate = self; table.dataSource = self
        table.setAccessibilityLabel(domain != nil ? "Recent pages" : "Folder pages")
        table.onActivate = { [weak self] row in self?.activate(row) }
        table.onEscape = { [weak self] in self?.onEscape?() }
        table.onHover = { [weak self] in self?.refreshHighlights() }
        table.makeMenu = { [weak self] row in self?.contextMenu(row: row) }
        scroll.documentView = table; scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        scroll.drawsBackground = false; scroll.horizontalScrollElasticity = .none
        scroll.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(listScrolled),
            name: NSView.boundsDidChangeNotification, object: scroll.contentView)
        for view in [scroll, message] as [NSView] { content.addSubview(view) }
        message.isHidden = true
        setAccessibilityElement(false)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    private static func styleHeaderButton(_ button: ActionButton, label: String, tint: NSColor) {
        button.title = ""; button.imagePosition = .imageOnly; button.toolTip = label
        button.image = button.image?.withSymbolConfiguration(.init(pointSize: 12, weight: .medium))
        button.setAccessibilityLabel(label); button.contentTintColor = tint
        button.focusRingCornerRadius = 5
    }

    override var preferredHeight: CGFloat {
        if showsPicture { return SidebarPreviewMetrics.header + pictureHeight + 8 }
        let body = filtered.isEmpty ? messageHeight + 24 : CGFloat(filtered.count) * (table.rowHeight + 1) + 4
        return SidebarPreviewMetrics.header + min(SidebarPreviewMetrics.maximumHeight - SidebarPreviewMetrics.header, body)
    }
    private var pictureHeight: CGFloat {
        let size = picture.image?.size ?? .zero
        guard size.width > 0 else { return 0 }
        let fitted = ((SidebarPreviewMetrics.width - 16) * size.height / size.width).rounded()
        return min(SidebarPreviewMetrics.maximumHeight - SidebarPreviewMetrics.header - 8, fitted)
    }
    private var messageHeight: CGFloat {
        let bounds = NSRect(x: 0, y: 0, width: SidebarPreviewMetrics.width - 32, height: 1000)
        return ceil(message.cell?.cellSize(forBounds: bounds).height ?? 16)
    }
    override func layout() {
        super.layout()
        let header = SidebarPreviewMetrics.header, width = bounds.width
        if showsPicture {
            icon.frame = NSRect(x: 13, y: (header - 16) / 2, width: 16, height: 16)
            split.frame = NSRect(x: width - 32, y: (header - 24) / 2, width: 24, height: 24)
            let textX = icon.frame.maxX + 8, textWidth = max(0, split.frame.minX - textX - 8)
            heading.frame = NSRect(x: textX, y: 8, width: textWidth, height: 17)
            site.frame = NSRect(x: textX, y: 25, width: textWidth, height: 14)
            picture.frame = NSRect(x: 8, y: header, width: max(0, width - 16), height: max(0, bounds.height - header - 8))
            return
        }
        if domain != nil {
            icon.frame = NSRect(x: 13, y: (header - 16) / 2, width: 16, height: 16)
            settings.frame = NSRect(x: width - 32, y: (header - 24) / 2, width: 24, height: 24)
            create.frame = settings.frame.offsetBy(dx: -26, dy: 0)
            heading.frame = NSRect(x: icon.frame.maxX + 8, y: (header - 18) / 2,
                                   width: max(0, create.frame.minX - icon.frame.maxX - 16), height: 18)
        } else {
            icon.frame = NSRect(x: 13, y: (header - 16) / 2, width: 14, height: 16)
            search.frame = NSRect(x: icon.frame.maxX + 9, y: (header - 20) / 2,
                                  width: max(0, width - icon.frame.maxX - 17), height: 20)
            divider.frame = NSRect(x: 1, y: header - 1, width: max(0, width - 2), height: 1)
        }
        scroll.frame = NSRect(x: 4, y: header, width: max(0, width - 8), height: max(0, bounds.height - header - 4))
        table.tableColumns.first?.width = scroll.contentSize.width
        let height = min(messageHeight, max(0, bounds.height - header - 24))
        message.frame = NSRect(x: 16, y: header + max(12, (bounds.height - header - height) / 2),
                               width: max(0, width - 32), height: height)
    }
    var ownsFirstResponder: Bool {
        guard let responder = window?.firstResponder as? NSView else { return false }
        if responder === self || responder.isDescendant(of: self) { return true }
        if let text = responder as? NSTextView, text.isFieldEditor, let field = text.delegate as? NSView {
            return field.isDescendant(of: self)
        }
        return false
    }
    func focusKeyboard() {
        guard !showsPicture else { return }
        if !filtered.indices.contains(table.selectedRow), !filtered.isEmpty { select(0) }
        window?.makeFirstResponder(domain == nil ? search : table)
    }
    func owns(_ menu: NSMenu) -> Bool { trackedMenu === menu }
    func setHeading(_ title: String, site: String) {
        guard showsPicture else { return }
        heading.stringValue = title; self.site.stringValue = site
    }
    func setPicture(_ image: NSImage) {
        guard showsPicture else { return }
        picture.image = image; needsLayout = true
        onHeightChange?()
    }
    func setRows(_ values: [SidebarPreviewRow]) {
        dataGeneration &+= 1; rows = values
        guard !showsPicture else { return }
        let urls = Set(values.map(\.url))
        icons = icons.filter { urls.contains($0.key) }; requestedIcons = Set(icons.keys)
        filterRows()
    }
    override func retire() {
        super.retire()
        onAction = nil; onEscape = nil; onSettings = nil; onHeightChange = nil; requestFavicon = nil
        trackedMenu?.cancelTracking(); trackedMenu = nil
        table.isRetired = true
    }
    private func loadProviderIcon() {
        guard domain != nil || showsPicture, !providerIconRequested, let providerURL, let requestFavicon else { return }
        providerIconRequested = true
        requestFavicon(providerURL) { [weak self] image in if let image { self?.icon.image = image } }
    }
    func controlTextDidChange(_ obj: Notification) { filterRows() }
    private func filterRows() {
        let selectedID = filtered.indices.contains(table.selectedRow) ? filtered[table.selectedRow].id : nil
        let query = search.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        filtered = rows.filter { $0.matches(query) }
        table.reloadData(); table.deselectAll(nil)
        if let selectedID, let index = filtered.firstIndex(where: { $0.id == selectedID }) { select(index) }
        else if !query.isEmpty, !filtered.isEmpty { select(0) }
        message.stringValue = query.isEmpty ? domain?.emptyMessage ?? Self.searchMiss : Self.searchMiss
        message.isHidden = !filtered.isEmpty
        scroll.isHidden = filtered.isEmpty
        needsLayout = true
        onHeightChange?()
    }
    private func select(_ index: Int) {
        table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        table.scrollRowToVisible(index)
    }
    private func refreshHighlights() {
        table.enumerateAvailableRowViews { view, row in
            guard let view = view as? SidebarPreviewRowView else { return }
            view.isHovered = row == table.hoveredRow; view.isFocused = row == table.selectedRow
        }
    }
    @objc private func listScrolled() { table.updateHover(atWindowPoint: window?.mouseLocationOutsideOfEventStream) }
    func numberOfRows(in tableView: NSTableView) -> Int { filtered.count }
    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let view = SidebarPreviewRowView()
        view.highlight = SidebarPreviewColors.primary(1)
        return view
    }
    func tableView(_ tableView: NSTableView, didAdd rowView: NSTableRowView, forRow row: Int) {
        guard let view = rowView as? SidebarPreviewRowView else { return }
        view.isHovered = row == table.hoveredRow; view.isFocused = row == table.selectedRow
    }
    func tableViewSelectionDidChange(_ notification: Notification) { refreshHighlights() }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard filtered.indices.contains(row) else { return nil }
        let value = filtered[row]
        let cell = SidebarPreviewItemView(row: value, title: SidebarPreviewColors.primary(1),
                                          secondary: SidebarPreviewColors.primary(0.5))
        cell.image = icons[value.url]
        if value.hasIcon, !requestedIcons.contains(value.url) {
            requestedIcons.insert(value.url)
            let token = dataGeneration
            requestFavicon?(value.url) { [weak self] image in
                guard let self, self.dataGeneration == token else { return }
                if let image { self.icons[value.url] = image }
                let indexes = IndexSet(self.filtered.indices.filter { self.filtered[$0].url == value.url })
                if !indexes.isEmpty { self.table.reloadData(forRowIndexes: indexes, columnIndexes: IndexSet(integer: 0)) }
            }
        }
        return cell
    }
    private var modifiers: SidebarPreviewModifiers { SidebarPreviewModifiers(eventFlags: modifierFlags().rawValue) }
    private func activateSelection() { activate(table.selectedRow) }
    private func activate(_ row: Int) {
        guard filtered.indices.contains(row) else { return }
        onAction?(filtered[row], .activate(modifiers))
    }
    private func contextMenu(row: Int) -> NSMenu? {
        guard filtered.indices.contains(row) else { return nil }
        let value = filtered[row]
        let menu = NSMenu()
        func add(_ title: String, _ action: SidebarPreviewAction) {
            menu.addItem(MenuAction.item(title) { [weak self] in self?.onAction?(value, action) })
        }
        if value.tabID != nil {
            add("Copy URL", .copyURL)
            add("Open in Split View", .split)
            add("Duplicate", .duplicate)
            menu.addItem(.separator()); add("Archive", .archive)
        } else {
            switch RecentPageText.rowMenu(value.url) {
            case .copyURL: add("Copy URL", .copyURL)
            case .linearIssue(let id): add("Copy Issue ID", .copyIssueID(id)); add("Copy Issue URL", .copyURL)
            case .none: return nil
            }
        }
        trackedMenu = menu
        return menu
    }
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.moveDown(_:)):
            if !filtered.isEmpty { select(min(filtered.count - 1, table.selectedRow + 1)) }
            return true
        case #selector(NSResponder.moveUp(_:)):
            if !filtered.isEmpty { select(max(0, table.selectedRow - 1)) }
            return true
        case #selector(NSResponder.insertNewline(_:)), #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)),
             #selector(NSResponder.insertLineBreak(_:)):
            activateSelection(); return true
        case #selector(NSResponder.cancelOperation(_:)): onEscape?(); return true
        default: return false
        }
    }
}

private final class SidebarPreviewTable: NSTableView {
    var onActivate: ((Int) -> Void)?
    var onEscape: (() -> Void)?
    var onHover: (() -> Void)?
    var makeMenu: ((Int) -> NSMenu?)?
    private(set) var hoveredRow = -1 { didSet { if hoveredRow != oldValue { onHover?() } } }
    var isRetired = false { didSet { if isRetired { hoveredRow = -1; updateTrackingAreas() } } }
    private var hoverArea: NSTrackingArea?
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        hoverArea = nil
        guard !isRetired else { return }
        let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(area); hoverArea = area
    }
    func updateHover(atWindowPoint point: NSPoint?) {
        guard !isRetired, let point else { hoveredRow = -1; return }
        let local = convert(point, from: nil)
        hoveredRow = visibleRect.contains(local) ? row(at: local) : -1
    }
    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        if event.trackingArea === hoverArea { updateHover(atWindowPoint: event.locationInWindow) }
    }
    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        updateHover(atWindowPoint: event.locationInWindow)
    }
    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        if event.trackingArea === hoverArea { hoveredRow = -1 }
    }
    override func mouseDown(with event: NSEvent) {
        let index = row(at: convert(event.locationInWindow, from: nil))
        super.mouseDown(with: event)
        guard index >= 0, !isRetired, let point = window?.mouseLocationOutsideOfEventStream,
              row(at: convert(point, from: nil)) == index else { return }
        onActivate?(index)
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 || event.keyCode == 76 { onActivate?(selectedRow) }
        else if event.keyCode == 53 { onEscape?() }
        else { super.keyDown(with: event) }
    }
    override func menu(for event: NSEvent) -> NSMenu? {
        let index = row(at: convert(event.locationInWindow, from: nil))
        guard index >= 0 else { return nil }
        selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        return makeMenu?(index)
    }
}

enum SidebarPreviewColors {
    static func primary(_ alpha: CGFloat) -> NSColor {
        NSColor(name: nil) { $0.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .white.withAlphaComponent(alpha) : .black.withAlphaComponent(alpha) }
    }
    static let background = NSColor(name: nil) {
        $0.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? NSColor(srgbRed: 0.129, green: 0.133, blue: 0.133, alpha: 1) : .white
    }
}

private final class SidebarPreviewPicture: NSView {
    var image: NSImage? { didSet { needsDisplay = true } }
    override var isFlipped: Bool { true }
    override var wantsUpdateLayer: Bool { true }
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 4; layer?.cornerCurve = .continuous; layer?.masksToBounds = true
        layer?.borderWidth = 0.5; layer?.contentsGravity = .resizeAspectFill
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func updateLayer() {
        guard let layer else { return }
        layer.contentsScale = window?.backingScaleFactor ?? 2
        layer.contents = image?.layerContents(forContentsScale: layer.contentsScale)
        effectiveAppearance.performAsCurrentDrawingAppearance { layer.borderColor = SidebarPreviewColors.primary(0.13).cgColor }
    }
}

final class SidebarPreviewDivider: NSView {
    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() {
        effectiveAppearance.performAsCurrentDrawingAppearance { layer?.backgroundColor = SidebarPreviewColors.primary(0.13).cgColor }
    }
}
