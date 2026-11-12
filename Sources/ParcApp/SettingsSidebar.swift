import AppKit

@MainActor
final class SettingsSidebarController: NSViewController, NSOutlineViewDataSource, NSOutlineViewDelegate {
    let table = NSOutlineView()
    private let panes: [SettingsWindow.Pane]
    private var syncing = false
    private var memberName = "Your Card"
    private var memberColors: [NSColor] = []
    var onSelect: ((SettingsWindow.Pane) -> Void)?

    init(panes: [SettingsWindow.Pane]) {
        self.panes = panes
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func loadView() {
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: SettingsLayout.sidebarWidth, height: SettingsLayout.contentHeight))
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        let column = NSTableColumn(identifier: .init("pane"))
        table.addTableColumn(column)
        table.outlineTableColumn = column
        table.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        table.headerView = nil
        table.style = .sourceList
        table.backgroundColor = .clear
        table.rowSizeStyle = .custom
        table.indentationPerLevel = 0
        table.allowsEmptySelection = false
        table.allowsMultipleSelection = false
        table.dataSource = self; table.delegate = self
        table.setAccessibilityLabel("Settings sections")
        scroll.documentView = table
        view = scroll
        table.reloadData()
        table.sizeLastColumnToFit()
    }

    func select(_ pane: SettingsWindow.Pane) {
        guard let row = panes.firstIndex(of: pane) else { return }
        _ = view
        syncing = true
        if table.selectedRow != row { table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false) }
        table.scrollRowToVisible(row)
        syncing = false
    }

    func updateMembership(name: String, colors: [NSColor]) {
        guard name != memberName || colors != memberColors else { return }
        memberName = name; memberColors = colors
        guard isViewLoaded, let row = panes.firstIndex(of: .membership) else { return }
        table.reloadData(forRowIndexes: IndexSet(integer: row), columnIndexes: IndexSet(integer: 0))
    }

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int { item == nil ? panes.count : 0 }
    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any { panes[index].rawValue }
    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool { false }

    func outlineView(_ outlineView: NSOutlineView, tintConfigurationForItem item: Any) -> NSTintConfiguration? { .monochrome }

    func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat {
        pane(item) == .membership ? SettingsLayout.sidebarMemberRowHeight : SettingsLayout.sidebarRowHeight
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let pane = pane(item) else { return nil }
        if pane == .membership {
            let cell = SettingsSidebarMemberCell()
            cell.update(name: memberName, colors: memberColors)
            return cell
        }
        let cell = SettingsSidebarCell()
        cell.update(title: pane.rawValue, symbol: pane.symbol)
        return cell
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        guard !syncing, panes.indices.contains(table.selectedRow) else { return }
        onSelect?(panes[table.selectedRow])
    }

    private func pane(_ item: Any) -> SettingsWindow.Pane? { (item as? String).flatMap(SettingsWindow.Pane.init(rawValue:)) }
}

@MainActor
final class SettingsSidebarCell: NSTableCellView {
    private let icon = NSImageView()
    private let title = NSTextField(labelWithString: "")

    override init(frame: NSRect) {
        super.init(frame: frame)
        title.font = .systemFont(ofSize: SettingsLayout.sidebarFontSize)
        title.lineBreakMode = .byTruncatingTail
        icon.symbolConfiguration = .init(pointSize: SettingsLayout.sidebarFontSize, weight: .regular)
        icon.imageScaling = .scaleProportionallyDown
        icon.setAccessibilityElement(false)
        addSubview(icon); addSubview(title)
        imageView = icon
        updateColors()
    }
    convenience init() { self.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var backgroundStyle: NSView.BackgroundStyle { didSet { updateColors() } }

    private func updateColors() {
        title.textColor = backgroundStyle == .emphasized ? .alternateSelectedControlTextColor : .textColor
    }

    func update(title value: String, symbol: String) {
        title.stringValue = value
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        setAccessibilityLabel(value)
    }

    override func layout() {
        super.layout()
        icon.frame = NSRect(x: 2, y: ((bounds.height - 20) / 2).rounded(), width: 22, height: 20)
        title.frame = NSRect(x: 32, y: ((bounds.height - 18) / 2).rounded(), width: max(0, bounds.width - 34), height: 18)
    }
}

@MainActor
final class SettingsSidebarMemberCell: NSTableCellView {
    private let avatar = SettingsMemberAvatar()
    private let name = NSTextField(labelWithString: "")

    override init(frame: NSRect) {
        super.init(frame: frame)
        name.font = .systemFont(ofSize: SettingsLayout.sidebarFontSize, weight: .semibold)
        name.lineBreakMode = .byTruncatingTail
        [avatar, name].forEach(addSubview)
        updateColors()
    }
    convenience init() { self.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var backgroundStyle: NSView.BackgroundStyle { didSet { updateColors() } }

    private func updateColors() {
        name.textColor = backgroundStyle == .emphasized ? .alternateSelectedControlTextColor : .textColor
    }

    func update(name value: String, colors: [NSColor]) {
        name.stringValue = value
        avatar.update(name: value, colors: colors)
        setAccessibilityLabel(value)
    }

    override func layout() {
        super.layout()
        let size: CGFloat = 28
        avatar.frame = NSRect(x: 0, y: ((bounds.height - size) / 2).rounded(), width: size, height: size)
        name.frame = NSRect(x: size + 8, y: ((bounds.height - 18) / 2).rounded(), width: max(0, bounds.width - size - 10), height: 18)
    }
}

@MainActor
final class SettingsMemberAvatar: NSView {
    private var initials = ""
    private var colors: [NSColor] = []

    override init(frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityElement(false)
    }
    convenience init() { self.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func update(name: String, colors: [NSColor]) {
        let words = name.split(whereSeparator: { $0.isWhitespace })
        initials = String(words.prefix(2).compactMap(\.first)).uppercased()
        self.colors = colors
        needsDisplay = true
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        let circle = NSBezierPath(ovalIn: bounds.insetBy(dx: 0.5, dy: 0.5))
        let accent = NSColor.controlAccentColor
        let fills = colors.count >= 2 ? [colors[0], colors[1]] : [accent, accent.blended(withFraction: 0.4, of: .white) ?? accent]
        NSGradient(colors: fills)?.draw(in: circle, angle: -45)
        guard !initials.isEmpty else { return }
        let text = NSAttributedString(string: initials, attributes: [
            .font: NSFont.systemFont(ofSize: (bounds.height * 0.4).rounded(), weight: .semibold),
            .foregroundColor: NSColor.white])
        let size = text.size()
        text.draw(at: NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2))
    }
}
