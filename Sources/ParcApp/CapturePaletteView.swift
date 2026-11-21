import AppKit

@MainActor
final class CapturePaletteView: NSView {
    nonisolated static let placeholder = "Send to or search…"

    let search = NoteSearchField(placeholder: CapturePaletteView.placeholder)
    let list = NoteMenuList()
    var onSizeChange: (() -> Void)?
    private let mainPage = CapturePalettePage()
    private let framePage = CapturePalettePage()
    private let statusRule = CapturePaletteRule()
    private let status = NSTextField(wrappingLabelWithString: "")
    private(set) var frameContent: NSView?

    init(placeholder: String = CapturePaletteView.placeholder) {
        super.init(frame: NSRect(x: 0, y: 0, width: CapturePresentation.paletteWidth, height: 200))
        search.placeholder = placeholder
        wantsLayer = true
        list.fixedWidth = CapturePresentation.paletteWidth
        list.maximumHeight = 10_000
        list.noResultsTitle = "Nothing by that name. Try another word?"
        list.setAccessibilityLabel("Capture actions")
        list.preferredSizeDidChange = { [weak self] in self?.sizeChanged() }
        status.font = NoteTheme.menuSubtitleFont()
        status.textColor = NoteTheme.menuSecondaryInk
        status.maximumNumberOfLines = 5
        status.isHidden = true
        statusRule.isHidden = true
        status.setAccessibilityLabel("Capture status")
        for view in [search, list, statusRule, status] as [NSView] { mainPage.addSubview(view) }
        framePage.isHidden = true
        addSubview(mainPage)
        addSubview(framePage)
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
    override var fittingSize: NSSize { NSSize(width: CapturePresentation.paletteWidth, height: naturalHeight) }
    override var intrinsicContentSize: NSSize { fittingSize }

    var showsFramePage: Bool { frameContent != nil }
    var statusText: String { status.stringValue }

    var naturalHeight: CGFloat {
        if let frameContent { return ceil(frameContent.fittingSize.height) }
        return searchSlot + list.intrinsicContentSize.height + statusHeight
    }

    private var searchSlot: CGFloat { NoteTheme.fieldHeight + NoteTheme.menuInset * 2 }
    private var statusInset: CGFloat { NoteTheme.menuInset + 10 }

    private var statusHeight: CGFloat {
        guard !status.isHidden else { return 0 }
        let width = CapturePresentation.paletteWidth - statusInset * 2
        return ceil(status.sizeThatFits(NSSize(width: width, height: .greatestFiniteMagnitude)).height) + 18
    }

    override func layout() {
        super.layout()
        NoteAnimation.withoutAnimation {
            mainPage.frame = bounds
            framePage.frame = bounds
            let inset = NoteTheme.menuInset
            search.frame = NSRect(x: inset, y: inset, width: bounds.width - inset * 2, height: NoteTheme.fieldHeight)
            let statusHeight = statusHeight
            list.frame = NSRect(x: 0, y: searchSlot - inset, width: bounds.width,
                                height: max(0, bounds.height - searchSlot - statusHeight + inset))
            statusRule.frame = NSRect(x: 0, y: bounds.height - statusHeight, width: bounds.width, height: 1)
            status.frame = NSRect(x: statusInset, y: bounds.height - statusHeight + 9,
                                  width: bounds.width - statusInset * 2, height: max(0, statusHeight - 18))
            frameContent?.frame = framePage.bounds
        }
    }

    func setStatus(_ text: String?) {
        let value = text ?? ""
        guard value != status.stringValue else { return }
        status.stringValue = value
        status.isHidden = value.isEmpty
        statusRule.isHidden = value.isEmpty
        needsLayout = true
        sizeChanged()
    }

    func showFramePage(_ content: NSView) {
        frameContent?.removeFromSuperview()
        frameContent = content
        framePage.addSubview(content)
        content.frame = NSRect(origin: .zero, size: NSSize(width: CapturePresentation.paletteWidth, height: content.fittingSize.height))
        slide(forward: true)
        mainPage.isHidden = true
        framePage.isHidden = false
        needsLayout = true
        sizeChanged()
    }

    func showMainPage(animated: Bool = true) {
        guard let frameContent else { return }
        if animated { slide(forward: false) }
        framePage.isHidden = true
        mainPage.isHidden = false
        frameContent.removeFromSuperview()
        self.frameContent = nil
        needsLayout = true
        sizeChanged()
    }

    func frameContentSizeChanged() {
        needsLayout = true
        sizeChanged()
    }

    private func sizeChanged() {
        invalidateIntrinsicContentSize()
        onSizeChange?()
    }

    private func slide(forward: Bool) {
        guard let layer, window != nil else { return }
        let transition = CATransition()
        if NoteAnimation.reduceMotion {
            transition.type = .fade
            transition.duration = NoteAnimation.reducedFadeDuration
        } else {
            transition.type = .push
            transition.subtype = forward ? .fromRight : .fromLeft
            transition.duration = 0.22
            transition.timingFunction = NoteCurve.hud
        }
        layer.add(transition, forKey: NoteAnimation.keyPrefix + "capture.page")
    }
}

@MainActor
private final class CapturePalettePage: NSView {
    override var isFlipped: Bool { true }
}

@MainActor
private final class CapturePaletteRule: NSView {
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        NoteTheme.menuSeparator.setFill()
        NSRect(x: 0, y: 0, width: bounds.width, height: 1 / (window?.backingScaleFactor ?? 2)).fill()
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
}

@MainActor
final class CapturePalette: NSObject {
    static let flyoutCloseDelay = 0.15
    static let flyoutMaximumHeight: CGFloat = 420

    var onAction: ((CapturePaletteAction) -> Void)?
    var onCancel: (() -> Void)?
    var onSizeChange: (() -> Void)?
    let view = CapturePaletteView()
    let card: NoteFloatingPanel
    private(set) var context = CapturePaletteContext()
    private(set) var rows: [CapturePaletteRow] = []
    private var flyout: Flyout?
    private var pendingFlyoutClose: DispatchWorkItem?
    private var placedSize = NSSize.zero

    private struct Flyout {
        let panel: NoteFloatingPanel
        let menu: CapturePaletteView
        let submenu: CapturePaletteSubmenu
        var rows: [CapturePaletteRow]
    }

    override init() {
        card = NoteFloatingPanel(content: view)
        super.init()
        card.gap = 0
        card.margin = 0
        card.sideAlignmentOffset = 0
        view.onSizeChange = { [weak self] in self?.onSizeChange?() }
        view.search.onChange = { [weak self] _ in self?.reload(resetHighlight: true) }
        view.search.onCommand = { [weak self] selector in
            guard let self else { return false }
            return self.perform(selector, in: .main, editor: self.view.search.textField.currentEditor() as? NSTextView)
        }
        view.list.onActivate = { [weak self] item in self?.activate(id: item.id, inFlyout: false) }
        view.list.onHighlight = { [weak self] item in self?.mainHighlightChanged(item) }
        view.list.onCancel = { [weak self] in self?.onCancel?() }
        reload(resetHighlight: true)
    }

    var isPresented: Bool { card.isPresented }
    var hasSubmenu: Bool { flyout != nil }
    var highlightedRow: CapturePaletteRow? {
        view.list.highlightedItem.flatMap { item in rows.first { $0.id == item.id } }
    }

    func update(_ change: (inout CapturePaletteContext) -> Void) {
        var next = context
        change(&next)
        guard next != context else { return }
        context = next
        reload(resetHighlight: false)
    }

    func reset() {
        closeFlyout(animated: false)
        view.search.text = ""
        view.setStatus(nil)
        view.showMainPage()
        view.list.prepare(origin: .pointer)
        reload(resetHighlight: true)
    }

    func setStatus(_ text: String?) { view.setStatus(text) }

    func focusSearch() { view.search.focus() }

    func place(_ frame: NSRect, image: NSRect, in host: NSView) {
        let placement = Self.anchor(for: frame, image: image)
        let presented = card.isPresented && card.superview === host
        let size = card.preferredSize
        guard !presented || placement.anchor != card.anchor || placement.edge != card.preferredEdge
                || card.maximumHeight != frame.height || size != placedSize else { return }
        placedSize = size
        card.maximumHeight = frame.height
        if presented {
            card.reposition(anchor: placement.anchor, edge: placement.edge, animated: true)
        } else {
            card.present(in: host, anchor: placement.anchor, edge: placement.edge, animated: true)
        }
        view.layoutSubtreeIfNeeded()
        if let flyout, let anchor = rowAnchor(for: flyout.submenu, in: host) {
            flyout.panel.reposition(anchor: anchor, edge: .trailing, animated: true)
        }
    }

    func hide(animated: Bool) {
        closeFlyout(animated: false)
        pendingFlyoutClose?.cancel()
        card.dismiss(animated: animated)
    }

    func closeSubmenu() { closeFlyout(animated: true) }

    func showFramePage(_ page: NSView) {
        closeFlyout(animated: false)
        view.showFramePage(page)
    }

    static func anchor(for frame: NSRect, image: NSRect) -> (anchor: NSRect, edge: NoteFloatingPanel.Edge) {
        if frame.minX >= image.maxX { return (NSRect(x: frame.minX, y: frame.minY, width: 0, height: 0), .trailing) }
        if frame.maxX <= image.minX { return (NSRect(x: frame.maxX, y: frame.minY, width: 0, height: 0), .leading) }
        return (NSRect(x: frame.minX, y: frame.minY, width: frame.width, height: 0), .below)
    }

    func perform(_ selector: Selector, in focus: CapturePaletteFocus, editor: NSTextView?) -> Bool {
        let field: NoteSearchField?
        let list: NoteMenuList?
        let shown: [CapturePaletteRow]
        switch focus {
        case .main: field = view.search; list = view.list; shown = rows
        case .submenu: field = flyout?.menu.search; list = flyout?.menu.list; shown = flyout?.rows ?? []
        case .frame: return false
        }
        guard let field, let list else { return false }
        let composing = editor?.hasMarkedText() == true
        guard let key = Self.key(for: selector) else { return composing ? false : list.handle(command: selector) }
        let range = editor?.selectedRange() ?? NSRange(location: 0, length: 0)
        let length = ((editor?.string ?? field.text) as NSString).length
        let highlighted = list.highlightedItem.flatMap { item in shown.first { $0.id == item.id }?.action }
        switch CapturePaletteKeys.command(key, focus: focus, highlighted: highlighted,
                                          caretAtStart: range.location == 0 && range.length == 0,
                                          caretAtEnd: range.location == length && range.length == 0, composing: composing) {
        case .move(let delta):
            list.origin = .keyboard
            list.moveHighlight(by: delta)
            return true
        case .activate:
            list.activateHighlighted()
            return true
        case .open(let submenu):
            openFlyout(submenu, keyboard: true)
            return true
        case .closeSubmenu:
            closeFlyout(animated: true, refocus: true)
            return true
        case .cancel:
            onCancel?()
            return true
        case .consume:
            return true
        case .back, .pass:
            return false
        }
    }

    private static func key(for selector: Selector) -> CapturePaletteKey? {
        switch selector {
        case #selector(NSResponder.moveUp(_:)): return .up
        case #selector(NSResponder.moveDown(_:)): return .down
        case #selector(NSResponder.moveLeft(_:)): return .left
        case #selector(NSResponder.moveRight(_:)): return .right
        case #selector(NSResponder.insertNewline(_:)), #selector(NSResponder.insertLineBreak(_:)),
             #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)): return .enter
        case #selector(NSResponder.cancelOperation(_:)): return .escape
        case #selector(NSResponder.insertTab(_:)), #selector(NSResponder.insertBacktab(_:)): return .tab
        default: return nil
        }
    }

    private func reload(resetHighlight: Bool) {
        let query = view.search.text
        rows = CapturePaletteMenu.rows(context, query: query)
        let keep = !resetHighlight && (view.list.hasKeyboardHighlight || flyout != nil)
        view.list.setItems(rows.map { item(for: $0, detailed: false) }, keepingHighlight: keep)
        if resetHighlight && !query.isEmpty { view.list.prepare(origin: .keyboard) }
        if resetHighlight { closeFlyout(animated: true) } else { refreshFlyout() }
        updateHelp()
    }

    private func item(for row: CapturePaletteRow, detailed: Bool) -> NoteMenuList.Item {
        var item = NoteMenuList.Item(id: row.id, title: row.title)
        item.subtitle = row.subtitle
        item.section = row.section
        item.separatorBefore = row.separatorBefore
        item.isEnabled = row.isEnabled
        item.isChecked = row.isChecked
        item.hasSubmenu = row.hasSubmenu
        item.icon = Self.icon(for: row.action)
        item.accessibilityLabel = Self.accessibilityLabel(for: row)
        if detailed, case .document(let document) = row.action { item.subtitle = NoteRelativeTime.edited(document.modifiedAt) }
        return item
    }

    private static func icon(for action: CapturePaletteAction) -> NoteIcon {
        switch action {
        case .easels: return .easelMark
        case .notes: return .noteMark
        case .document(let document):
            switch document.target {
            case .easel: return .easelMark
            case .note(let url): return NoteIcon.note(document.icon, at: url)
            }
        default: return .symbol(action.symbol)
        }
    }

    private static func accessibilityLabel(for row: CapturePaletteRow) -> String? {
        switch row.action {
        case .easels: return "Send to an Easel"
        case .notes: return "Send to a note"
        case .document(let document):
            return (document.kind == .easel ? "Send to Easel: " : "Send to note: ") + document.title
        default: return nil
        }
    }

    private func updateHelp() {
        let help = view.list.highlightedItem.map { "\($0.title) is highlighted. Use Up and Down, then Return." }
            ?? (rows.isEmpty ? "No matches" : "Use Up and Down to choose an action, then Return.")
        view.search.textField.setAccessibilityHelp(help)
    }

    private func activate(id: String, inFlyout: Bool) {
        let shown = inFlyout ? flyout?.rows ?? [] : rows
        guard let row = shown.first(where: { $0.id == id }), row.isEnabled else { return }
        if let submenu = row.action.submenu {
            openFlyout(submenu, keyboard: NSApp.currentEvent?.type == .keyDown || view.list.hasKeyboardHighlight)
            return
        }
        onAction?(row.action)
    }

    private func mainHighlightChanged(_ item: NoteMenuList.Item?) {
        updateHelp()
        guard let item, let row = rows.first(where: { $0.id == item.id }) else { return }
        if let flyout, flyout.submenu == row.action.submenu { pendingFlyoutClose?.cancel(); return }
        if NSApp.currentEvent?.type == .keyDown {
            pendingFlyoutClose?.cancel()
            closeFlyout(animated: true)
            return
        }
        if let submenu = row.action.submenu {
            pendingFlyoutClose?.cancel()
            openFlyout(submenu, keyboard: false)
            return
        }
        guard flyout != nil else { return }
        pendingFlyoutClose?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.closeFlyout(animated: true) }
        pendingFlyoutClose = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.flyoutCloseDelay, execute: work)
    }

    private func openFlyout(_ submenu: CapturePaletteSubmenu, keyboard: Bool) {
        if let flyout, flyout.submenu == submenu {
            if keyboard { focusFlyout() }
            return
        }
        closeFlyout(animated: false)
        guard let host = card.superview, let anchor = rowAnchor(for: submenu, in: host) else { return }
        let menu = CapturePaletteView(placeholder: submenu == .easels ? "Search Easels…" : "Search notes…")
        menu.list.rowStyle = .detailed
        menu.list.noResultsTitle = view.list.noResultsTitle
        menu.list.setAccessibilityLabel(submenu == .easels ? "Easels" : "Notes")
        menu.list.onActivate = { [weak self] item in self?.activate(id: item.id, inFlyout: true) }
        menu.list.onCancel = { [weak self] in self?.closeFlyout(animated: true, refocus: true) }
        menu.list.onCollapse = { [weak self] in self?.closeFlyout(animated: true, refocus: true) }
        menu.list.onHighlight = { [weak self] item in if item != nil { self?.pendingFlyoutClose?.cancel() } }
        menu.search.onChange = { [weak self] _ in self?.reloadFlyout(resetHighlight: true) }
        menu.search.onCommand = { [weak self, weak menu] selector in
            guard let self, let menu else { return false }
            return self.perform(selector, in: .submenu(submenu), editor: menu.search.textField.currentEditor() as? NSTextView)
        }
        let panel = NoteFloatingPanel(content: menu)
        panel.maximumHeight = Self.flyoutMaximumHeight
        menu.onSizeChange = { [weak panel] in panel?.contentSizeDidChange(animated: true) }
        panel.onDismiss = { [weak self, weak panel] in
            guard let self, let panel, self.flyout?.panel === panel else { return }
            self.flyout = nil
        }
        flyout = Flyout(panel: panel, menu: menu, submenu: submenu, rows: [])
        reloadFlyout(resetHighlight: true)
        menu.list.prepare(origin: keyboard ? .keyboard : .pointer)
        panel.present(in: host, anchor: anchor, edge: .trailing)
        if keyboard { focusFlyout() }
    }

    private func focusFlyout() {
        guard let flyout else { return }
        if flyout.menu.list.highlightedItem == nil { flyout.menu.list.prepare(origin: .keyboard) }
        flyout.menu.search.focus()
    }

    private func closeFlyout(animated: Bool, refocus: Bool = false) {
        pendingFlyoutClose?.cancel()
        guard let flyout else { return }
        self.flyout = nil
        let window = flyout.menu.window
        let wasEditing = window != nil && window?.firstResponder === flyout.menu.search.textField.currentEditor()
        flyout.panel.dismiss(animated: animated)
        if wasEditing || refocus { view.search.focus() }
    }

    private func reloadFlyout(resetHighlight: Bool) {
        guard var current = flyout else { return }
        current.rows = CapturePaletteMenu.submenu(current.submenu, context: context, query: current.menu.search.text)
        flyout = current
        current.menu.list.setItems(current.rows.map { item(for: $0, detailed: true) }, keepingHighlight: !resetHighlight)
        if resetHighlight && !current.menu.search.text.isEmpty { current.menu.list.prepare(origin: .keyboard) }
    }

    private func refreshFlyout() {
        guard let flyout else { return }
        guard rows.contains(where: { $0.action.submenu == flyout.submenu && $0.isEnabled }) else {
            closeFlyout(animated: true)
            return
        }
        reloadFlyout(resetHighlight: false)
        view.layoutSubtreeIfNeeded()
        if let host = card.superview, let anchor = rowAnchor(for: flyout.submenu, in: host) {
            flyout.panel.reposition(anchor: anchor, edge: .trailing, animated: true)
        }
    }

    private func rowAnchor(for submenu: CapturePaletteSubmenu, in host: NSView) -> NSRect? {
        let id = submenu == .easels ? CapturePaletteAction.easels.id : CapturePaletteAction.notes.id
        guard let row = view.list.rowFrame(forItemID: id) else { return nil }
        return host.convert(row, from: view.list)
    }
}
