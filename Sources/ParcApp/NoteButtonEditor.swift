import AppKit
import Combine

@MainActor
final class NoteButtonTemplateView: NSView, NSMenuItemValidation {
    static let sideMargin: CGFloat = 34
    static let minimumHeight: CGFloat = 44

    let session: NotePageSession
    let templateEditor: NotePageEditor
    var onChange: (([NoteBlock]) -> Void)?
    var onHeightChange: (() -> Void)?
    var onEscape: (() -> Void)?
    private(set) var contentHeight: CGFloat = NoteButtonTemplateView.minimumHeight
    private var subscription: AnyCancellable?

    init(blocks: [NoteBlock], settings: NotePageSettings, host: NotePageEditor, width: CGFloat) {
        var inner = NotePageSettings()
        inner.font = settings.font
        inner.smallText = settings.smallText
        session = NotePageSession(page: NotePage(settings: inner, blocks: blocks))
        templateEditor = NotePageEditor(session: session, environment: host.environment)
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: Self.minimumHeight))
        templateEditor.isTemplateEditor = true
        templateEditor.onOpenURL = { [weak host] url in host?.open(url) }
        templateEditor.onOpenNote = { [weak host] url in host?.open(url) }
        templateEditor.onError = { [weak host] error in host?.onError?(error) }
        templateEditor.handles.presentToast = { [weak host] content in host?.formatBar.showToast(content) }
        templateEditor.formatBar.onToast = { [weak host] content in host?.formatBar.showToast(content) }
        templateEditor.onUnhandledEscape = { [weak self] in
            guard let self, let onEscape = self.onEscape else { return false }
            onEscape()
            return true
        }
        templateEditor.onCanvasLayout = { [weak self] in self?.measure() }
        let canvas = templateEditor.canvas!
        canvas.metricsAdjustment = { metrics in
            metrics.fullWidth = true
            metrics.pageSideMargin = Self.sideMargin
            metrics.minimumSideMargin = Self.sideMargin
            metrics.topInset = 6
            metrics.bottomInset = 8
            metrics.bottomViewportFraction = 0
        }
        canvas.frame = bounds
        addSubview(canvas)
        subscription = session.changes.sink { [weak self] change in
            guard let self, change.kind != .selection else { return }
            self.onChange?(self.blocks)
        }
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Blocks this button adds")
        canvas.layoutSubtreeIfNeeded()
        measure()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    var canvas: NotePageCanvasView { templateEditor.canvas }

    var blocks: [NoteBlock] {
        let current = session.page.blocks
        if current.count == 1, NoteMDWriter.isBareEmptyParagraph(current[0]) { return [] }
        return current
    }

    override func layout() {
        super.layout()
        if canvas.frame != bounds { NoteAnimation.withoutAnimation { canvas.frame = bounds } }
        canvas.syncOverlayPlacement()
    }

    private func measure() {
        let height = max(Self.minimumHeight, ceil(canvas.contentHeight))
        guard abs(height - contentHeight) > 0.5 else { return }
        contentHeight = height
        onHeightChange?()
    }

    func attach(to host: NSView) {
        canvas.overlayHost = host
        canvas.syncOverlayPlacement()
    }

    func detach() {
        templateEditor.dismissOverlays()
        canvas.overlayHost = nil
    }

    func focus() {
        guard let window else { return }
        let page = session.page
        let target = page.visibleTextOrder().last.map { id in NotePosition(id, page.block(id)?.text.length ?? 0) }
        window.makeFirstResponder(canvas)
        if let target {
            session.setSelection(.caret(target))
            templateEditor.focus(target)
        }
    }

    var ownsFocus: Bool { templateEditor.ownsFocus }

    @objc func undo(_ sender: Any?) { _ = templateEditor.performMenuAction(#selector(undo(_:)), sender: sender) }
    @objc func redo(_ sender: Any?) { _ = templateEditor.performMenuAction(#selector(redo(_:)), sender: sender) }
    @objc func copy(_ sender: Any?) { _ = templateEditor.performMenuAction(#selector(copy(_:)), sender: sender) }
    @objc func cut(_ sender: Any?) { _ = templateEditor.performMenuAction(#selector(cut(_:)), sender: sender) }
    @objc func paste(_ sender: Any?) { _ = templateEditor.performMenuAction(#selector(paste(_:)), sender: sender) }
    @objc func pasteAsPlainText(_ sender: Any?) { _ = templateEditor.performMenuAction(#selector(pasteAsPlainText(_:)), sender: sender) }
    @objc func delete(_ sender: Any?) { _ = templateEditor.performMenuAction(#selector(delete(_:)), sender: sender) }
    override func selectAll(_ sender: Any?) { _ = templateEditor.performMenuAction(#selector(selectAll(_:)), sender: sender) }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        templateEditor.validateMenuAction(menuItem) ?? false
    }
}

@MainActor
final class NoteButtonActionCard: NSView {
    static let padding: CGFloat = 10
    static let headerHeight: CGFloat = 28
    static let bodyGap: CGFloat = 6

    private(set) var action: NoteButtonAction
    var onChange: ((NoteButtonActionCard) -> Void)?
    var onHeightChange: (() -> Void)?
    var onMore: ((NoteButtonActionCard, NSView) -> Void)?
    var onPlacement: ((NoteButtonActionCard, NSView) -> Void)?
    var onTarget: ((NoteButtonActionCard, NSView) -> Void)?
    var onClose: (() -> Void)?

    private let icon = NoteIconView(pointSize: 13)
    private let title = NSTextField(labelWithString: "")
    private let more = NoteToolbarButton(icon: .symbol("ellipsis"), label: "More actions")
    private let placementButton = NoteToolbarButton(.text(""), label: "Where the blocks go")
    private(set) var template: NoteButtonTemplateView?
    private let messageField = NoteSearchField(placeholder: "Are you sure?")
    private let targetButton = NoteToolbarButton(.iconAndText(.symbol("link"), ""), label: "Choose what to open")

    init(action: NoteButtonAction, host: NotePageEditor, width: CGFloat) {
        self.action = action
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 80))
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.cornerCurve = .continuous
        title.font = NoteTheme.chromeFont(13)
        title.textColor = NoteTheme.menuInk
        title.lineBreakMode = .byTruncatingTail
        icon.tint = NoteTheme.menuSecondaryInk
        more.iconPointSize = 13
        more.onPress = { [weak self] in
            guard let self else { return }
            self.onMore?(self, self.more)
        }
        addSubview(icon)
        addSubview(title)
        addSubview(more)
        switch action {
        case .insert(let placement, let blocks):
            icon.icon = .symbol("square.stack.3d.down.right")
            title.stringValue = "Insert blocks"
            placementButton.showsDisclosure = true
            placementButton.content = .text(placement.title)
            placementButton.onPress = { [weak self] in
                guard let self else { return }
                self.onPlacement?(self, self.placementButton)
            }
            addSubview(placementButton)
            let editor = NoteButtonTemplateView(blocks: blocks, settings: host.session.page.settings, host: host,
                                                width: width - Self.padding * 2)
            editor.onChange = { [weak self] blocks in
                guard let self, case .insert(let placement, _) = self.action else { return }
                self.action = .insert(placement: placement, blocks: blocks)
                self.onChange?(self)
            }
            editor.onHeightChange = { [weak self] in
                self?.needsLayout = true
                self?.onHeightChange?()
            }
            editor.onEscape = { [weak self] in self?.onClose?() }
            editor.wantsLayer = true
            editor.layer?.cornerRadius = 8
            editor.layer?.cornerCurve = .continuous
            addSubview(editor)
            template = editor
        case .confirm(let message):
            icon.icon = .symbol("questionmark.bubble")
            title.stringValue = "Show confirmation"
            messageField.showsIcon = false
            messageField.text = message
            messageField.textField.setAccessibilityLabel("Confirmation message")
            messageField.onChange = { [weak self] text in
                guard let self else { return }
                self.action = .confirm(message: text)
                self.onChange?(self)
            }
            messageField.onCommand = { [weak self] selector in
                switch selector {
                case #selector(NSResponder.insertNewline(_:)), #selector(NSResponder.cancelOperation(_:)):
                    self?.onClose?()
                    return true
                default:
                    return false
                }
            }
            addSubview(messageField)
        case .open(let target):
            icon.icon = .symbol("arrow.up.right.square")
            title.stringValue = "Open a note or link"
            targetButton.onPress = { [weak self] in
                guard let self else { return }
                self.onTarget?(self, self.targetButton)
            }
            addSubview(targetButton)
            refreshTarget(target)
        }
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(title.stringValue)
        refreshFill()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    var bodyHeight: CGFloat {
        switch action {
        case .insert: return template?.contentHeight ?? NoteButtonTemplateView.minimumHeight
        case .confirm, .open: return NoteTheme.fieldHeight
        }
    }

    var preferredHeight: CGFloat { Self.padding + Self.headerHeight + Self.bodyGap + bodyHeight + Self.padding }

    func setPlacement(_ placement: NoteButtonPlacement) {
        guard case .insert(let current, let blocks) = action, current != placement else { return }
        action = .insert(placement: placement, blocks: blocks)
        placementButton.content = .text(placement.title)
        needsLayout = true
        onChange?(self)
    }

    func setTarget(_ target: String) {
        guard case .open(let current) = action, current != target else { return }
        action = .open(target: target)
        refreshTarget(target)
        onChange?(self)
    }

    private func refreshTarget(_ target: String) {
        if target.isEmpty {
            targetButton.content = .iconAndText(.symbol("link"), "Choose a note or paste a link")
            targetButton.iconTint = NoteTheme.menuTertiaryInk
        } else if NoteLinkInput.isRelative(target) {
            targetButton.content = .iconAndText(.symbol("doc.text"), NoteButton.targetLabel(target))
            targetButton.iconTint = nil
        } else {
            targetButton.content = .iconAndText(.symbol("globe"), NoteLinkInput.displayText(target))
            targetButton.iconTint = nil
        }
        targetButton.setAccessibilityLabel(target.isEmpty ? "Choose what to open" : "Opens " + NoteButton.targetLabel(target))
        needsLayout = true
    }

    func focusBody() {
        switch action {
        case .insert: template?.focus()
        case .confirm: messageField.focus()
        case .open: onTarget?(self, targetButton)
        }
    }

    override func layout() {
        super.layout()
        let inset = Self.padding
        let header = Self.headerHeight
        NoteAnimation.withoutAnimation {
            icon.frame = NSRect(x: inset - 2, y: inset + (header - 20) / 2, width: 20, height: 20)
            more.frame = NSRect(x: bounds.width - inset - 26, y: inset + 1, width: 26, height: 26)
            var titleRight = more.frame.minX - 6
            if placementButton.superview != nil {
                let width = min(placementButton.intrinsicContentSize.width, bounds.width * 0.55)
                placementButton.frame = NSRect(x: more.frame.minX - 4 - width, y: inset, width: width, height: NoteTheme.toolbarButtonSize.height)
                titleRight = placementButton.frame.minX - 6
            }
            let titleHeight = ceil((title.font ?? NoteTheme.chromeFont(13)).boundingRectForFont.height)
            title.frame = NSRect(x: icon.frame.maxX + 6, y: inset + (header - titleHeight) / 2, width: max(0, titleRight - icon.frame.maxX - 6),
                                 height: titleHeight)
            let body = NSRect(x: inset, y: inset + header + Self.bodyGap, width: bounds.width - inset * 2, height: bodyHeight)
            template?.frame = body
            messageField.frame = body
            targetButton.frame = body
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshFill()
    }

    private func refreshFill() {
        NoteAnimation.withoutAnimation {
            layer?.backgroundColor = NoteTheme.resolved(NoteTheme.fieldFill, in: self)
            template?.layer?.backgroundColor = NoteTheme.resolved(NoteTheme.menuFill, in: self)
        }
    }
}

@MainActor
private final class NoteButtonCardStack: NSView {
    override var isFlipped: Bool { true }
}

@MainActor
final class NoteButtonEditorView: NSView, NoteFloatingPanelContent {
    static let width: CGFloat = 460
    static let inset: CGFloat = 12
    static let cardGap: CGFloat = 8
    static let maximumCardsHeight: CGFloat = 440

    var preferredSizeDidChange: (() -> Void)?
    var onClose: (() -> Void)?
    private weak var editor: NotePageEditor?
    private let blockID: NoteBlockID
    private let token = UUID()
    private var icon: String?
    private let iconButton = NoteToolbarButton(icon: .symbol("face.smiling"), label: "Choose an icon")
    private let nameField = NoteSearchField(placeholder: "Button name")
    private let header = NSTextField(labelWithString: "When pressed")
    private let emptyLabel = NSTextField(labelWithString: "Nothing happens yet. Add an action and give it a job.")
    private let scroll = NSScrollView()
    private let stack = NoteButtonCardStack()
    private var cards: [NoteButtonActionCard] = []
    private let addButton = NoteChip("New action", icon: .symbol("plus"))
    private let doneButton = NoteChip("Done", style: .filled)
    private var auxiliary: NoteFloatingPanel?
    private var clipObserver: NSObjectProtocol?
    private var lastSize = NSSize.zero
    private var isTornDown = false

    init(block: NoteBlock, editor: NotePageEditor) {
        self.editor = editor
        blockID = block.id
        icon = block.props.icon.flatMap { $0.isEmpty ? nil : $0 }
        super.init(frame: NSRect(x: 0, y: 0, width: Self.width, height: 200))
        let button = block.buttonValue
        iconButton.iconPointSize = 18
        iconButton.onPress = { [weak self] in self?.chooseIcon() }
        addSubview(iconButton)
        nameField.showsIcon = false
        nameField.text = button.name
        nameField.textField.font = NoteTheme.nunitoBold(14)
        nameField.textField.setAccessibilityLabel("Button name")
        nameField.onChange = { [weak self] _ in self?.commit() }
        nameField.onCommand = { [weak self] selector in
            switch selector {
            case #selector(NSResponder.insertNewline(_:)), #selector(NSResponder.cancelOperation(_:)):
                self?.onClose?()
                return true
            default:
                return false
            }
        }
        addSubview(nameField)
        header.font = NoteTheme.menuHeaderFont()
        header.textColor = NoteTheme.menuTertiaryInk
        addSubview(header)
        emptyLabel.font = NoteTheme.nunitoRegular(13)
        emptyLabel.textColor = NoteTheme.menuSecondaryInk
        addSubview(emptyLabel)
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.automaticallyAdjustsContentInsets = false
        scroll.contentView.drawsBackground = false
        scroll.documentView = stack
        addSubview(scroll)
        scroll.contentView.postsBoundsChangedNotifications = true
        clipObserver = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: scroll.contentView,
                                                              queue: nil) { [weak self] _ in
            MainActor.assumeIsolated { self?.syncOverlays() }
        }
        addButton.onPress = { [weak self] in self?.chooseNewAction() }
        addButton.setAccessibilityLabel("Add an action")
        addSubview(addButton)
        doneButton.onPress = { [weak self] in self?.onClose?() }
        doneButton.setAccessibilityLabel("Done editing button")
        addSubview(doneButton)
        for action in button.actions { cards.append(makeCard(action)) }
        for card in cards { stack.addSubview(card) }
        refreshIcon()
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Edit button")
        layoutCards(animated: false)
        lastSize = fittingSize
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    private var contentWidth: CGFloat { Self.width - Self.inset * 2 }

    private var cardsHeight: CGFloat {
        guard !cards.isEmpty else { return 0 }
        return cards.map(\.preferredHeight).reduce(0, +) + Self.cardGap * CGFloat(cards.count - 1)
    }

    private var scrollHeight: CGFloat { cards.isEmpty ? 22 : min(cardsHeight, Self.maximumCardsHeight) }

    override var fittingSize: NSSize {
        NSSize(width: Self.width, height: Self.inset + NoteTheme.fieldHeight + 14 + 16 + 6 + scrollHeight + 12 + NoteTheme.chipHeight + Self.inset)
    }

    override var intrinsicContentSize: NSSize { fittingSize }

    override func layout() {
        super.layout()
        let inset = Self.inset
        NoteAnimation.withoutAnimation {
            iconButton.frame = NSRect(x: inset, y: inset, width: NoteTheme.fieldHeight, height: NoteTheme.fieldHeight)
            nameField.frame = NSRect(x: iconButton.frame.maxX + 8, y: inset, width: bounds.width - iconButton.frame.maxX - 8 - inset,
                                     height: NoteTheme.fieldHeight)
            header.frame = NSRect(x: inset + 2, y: nameField.frame.maxY + 14, width: contentWidth, height: 16)
            scroll.frame = NSRect(x: inset, y: header.frame.maxY + 6, width: contentWidth, height: scrollHeight)
            emptyLabel.frame = NSRect(x: inset + 2, y: scroll.frame.minY + 2, width: contentWidth, height: 18)
            emptyLabel.isHidden = !cards.isEmpty
            let rowY = scroll.frame.maxY + 12
            let addWidth = addButton.intrinsicContentSize.width
            addButton.frame = NSRect(x: inset - 4, y: rowY, width: addWidth, height: NoteTheme.chipHeight)
            let doneWidth = doneButton.intrinsicContentSize.width
            doneButton.frame = NSRect(x: bounds.width - inset - doneWidth, y: rowY, width: doneWidth, height: NoteTheme.chipHeight)
        }
        layoutCards(animated: false)
        syncOverlays()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        syncOverlays()
    }

    private func layoutCards(animated: Bool) {
        var y: CGFloat = 0
        let width = contentWidth
        for card in cards {
            let frame = NSRect(x: 0, y: y, width: width, height: card.preferredHeight)
            if animated, card.frame.width > 0, card.frame != frame, !NoteAnimation.reduceMotion {
                NoteAnimation.slide(card, to: frame, spring: .reorder)
            } else if card.frame != frame {
                NoteAnimation.withoutAnimation { card.frame = frame }
            }
            y = frame.maxY + Self.cardGap
        }
        let height = max(cardsHeight, 1)
        if stack.frame.size != NSSize(width: width, height: height) {
            NoteAnimation.withoutAnimation { stack.frame = NSRect(x: 0, y: 0, width: width, height: height) }
        }
    }

    private func sizeMayHaveChanged() {
        needsLayout = true
        let size = fittingSize
        guard size != lastSize else { return }
        lastSize = size
        preferredSizeDidChange?()
    }

    func syncOverlays() {
        for card in cards { card.template?.canvas.syncOverlayPlacement() }
    }

    private var templates: [NoteButtonTemplateView] { cards.compactMap(\.template) }

    func didPresent() {
        guard let host = editor?.canvas.overlayView else { return }
        for template in templates { template.attach(to: host) }
        nameField.focus()
        nameField.textField.currentEditor()?.selectAll(nil)
    }

    func tearDown() {
        guard !isTornDown else { return }
        isTornDown = true
        auxiliary?.dismiss(animated: false)
        auxiliary = nil
        for template in templates { template.detach() }
        if let clipObserver { NotificationCenter.default.removeObserver(clipObserver) }
        clipObserver = nil
    }

    func contains(_ view: NSView) -> Bool {
        if view.isDescendant(of: self) { return true }
        if let auxiliary, view.isDescendant(of: auxiliary) { return true }
        return templates.contains { view.isDescendant(of: $0.canvas.overlayView) }
    }

    var hasFocus: Bool {
        guard let responder = window?.firstResponder as? NSView else { return false }
        return contains(responder)
    }

    private func makeCard(_ action: NoteButtonAction) -> NoteButtonActionCard {
        let card = NoteButtonActionCard(action: action, host: editor!, width: contentWidth)
        card.onChange = { [weak self] _ in self?.commit() }
        card.onHeightChange = { [weak self] in
            self?.layoutCards(animated: false)
            self?.sizeMayHaveChanged()
        }
        card.onClose = { [weak self] in self?.onClose?() }
        card.onMore = { [weak self] card, anchor in self?.showMore(for: card, from: anchor) }
        card.onPlacement = { [weak self] card, anchor in self?.choosePlacement(for: card, from: anchor) }
        card.onTarget = { [weak self] card, anchor in self?.chooseTarget(for: card, from: anchor) }
        return card
    }

    private func commit() {
        guard !isTornDown, let editor else { return }
        editor.session.setButton(blockID, name: NoteButton.normalizedName(nameField.text), icon: .some(icon), actions: cards.map(\.action),
                                 coalescing: .lasting(blockID, token))
    }

    private func refreshIcon() {
        if let icon {
            iconButton.content = .icon(.emoji(icon))
            iconButton.iconTint = nil
            iconButton.setAccessibilityLabel("Icon: \(icon). Choose another")
        } else {
            iconButton.content = .icon(.symbol("face.smiling"))
            iconButton.iconTint = NoteTheme.menuTertiaryInk
            iconButton.setAccessibilityLabel("Choose an icon")
        }
    }

    @discardableResult
    private func presentAuxiliary(_ content: NSView, from anchor: NSView, edge: NoteFloatingPanel.Edge = .below,
                                  alignment: NoteFloatingPanel.Alignment = .leading) -> NoteFloatingPanel? {
        guard let host = editor?.canvas.overlayView else { return nil }
        auxiliary?.dismiss(animated: false)
        let panel = NoteFloatingPanel(content: content)
        panel.alignment = alignment
        panel.onDismiss = { [weak self, weak panel] in
            guard let self, let panel, self.auxiliary === panel else { return }
            self.auxiliary = nil
        }
        panel.present(in: host, anchor: host.convert(anchor.bounds, from: anchor), edge: edge, animated: true)
        auxiliary = panel
        return panel
    }

    private func dismissAuxiliary() {
        auxiliary?.dismiss(animated: true)
        auxiliary = nil
    }

    private func menu(_ items: [NoteMenuList.Item], from anchor: NSView, alignment: NoteFloatingPanel.Alignment = .leading,
                      onPick: @escaping (String) -> Void) {
        let list = NoteMenuList(items: items)
        list.rowStyle = items.contains { $0.subtitle != nil } ? .detailed : .compact
        list.minimumWidth = 220
        list.takesKeyboardFocus = true
        list.onActivate = { [weak self] item in
            self?.dismissAuxiliary()
            onPick(item.id)
        }
        list.onCancel = { [weak self] in self?.dismissAuxiliary() }
        list.prepare(origin: .pointer)
        presentAuxiliary(list, from: anchor, alignment: alignment)
        window?.makeFirstResponder(list)
    }

    private func chooseIcon() {
        let picker = NoteEmojiPicker(showsRemove: icon != nil, showsRandom: true)
        picker.currentEmoji = icon
        picker.onPick = { [weak self] emoji in
            guard let self else { return }
            self.icon = emoji
            self.refreshIcon()
            self.commit()
            self.dismissAuxiliary()
            NoteAnimation.pop(self.iconButton, from: 0.85, spring: .check)
        }
        picker.onRemove = { [weak self] in
            guard let self else { return }
            self.icon = nil
            self.refreshIcon()
            self.commit()
            self.dismissAuxiliary()
        }
        picker.onCancel = { [weak self] in self?.dismissAuxiliary() }
        presentAuxiliary(picker, from: iconButton)
        picker.focusSearch()
    }

    private func chooseNewAction() {
        var insert = NoteMenuList.Item(id: NoteButtonAction.Kind.insert.rawValue, title: "Insert blocks")
        insert.subtitle = "Add blocks to this note"
        insert.icon = .symbol("square.stack.3d.down.right")
        var confirm = NoteMenuList.Item(id: NoteButtonAction.Kind.confirm.rawValue, title: "Show confirmation")
        confirm.subtitle = "Ask before carrying on"
        confirm.icon = .symbol("questionmark.bubble")
        var open = NoteMenuList.Item(id: NoteButtonAction.Kind.open.rawValue, title: "Open a note or link")
        open.subtitle = "Jump to a note or a web page"
        open.icon = .symbol("arrow.up.right.square")
        menu([insert, confirm, open], from: addButton) { [weak self] id in
            guard let kind = NoteButtonAction.Kind(rawValue: id) else { return }
            self?.append(.blank(kind))
        }
    }

    private func append(_ action: NoteButtonAction) {
        guard editor != nil else { return }
        let card = makeCard(action)
        cards.append(card)
        stack.addSubview(card)
        layoutCards(animated: false)
        if let host = editor?.canvas.overlayView { card.template?.attach(to: host) }
        commit()
        sizeMayHaveChanged()
        layoutSubtreeIfNeeded()
        NoteAnimation.insert(card)
        stack.scrollToVisible(card.frame)
        card.focusBody()
    }

    private func showMore(for card: NoteButtonActionCard, from anchor: NSView) {
        guard let index = cards.firstIndex(where: { $0 === card }) else { return }
        var up = NoteMenuList.Item(id: "up", title: "Move Up")
        up.icon = .symbol("arrow.up")
        up.isEnabled = index > 0
        var down = NoteMenuList.Item(id: "down", title: "Move Down")
        down.icon = .symbol("arrow.down")
        down.isEnabled = index + 1 < cards.count
        var duplicate = NoteMenuList.Item(id: "duplicate", title: "Duplicate")
        duplicate.icon = .symbol("plus.square.on.square")
        var delete = NoteMenuList.Item(id: "delete", title: "Delete")
        delete.icon = .symbol("trash")
        delete.isDestructive = true
        delete.separatorBefore = true
        menu([up, down, duplicate, delete], from: anchor, alignment: .trailing) { [weak self] id in
            switch id {
            case "up": self?.move(card, by: -1)
            case "down": self?.move(card, by: 1)
            case "duplicate": self?.duplicate(card)
            case "delete": self?.remove(card)
            default: break
            }
        }
    }

    private func move(_ card: NoteButtonActionCard, by delta: Int) {
        guard let index = cards.firstIndex(where: { $0 === card }), cards.indices.contains(index + delta) else { return }
        cards.swapAt(index, index + delta)
        layoutCards(animated: true)
        commit()
        syncOverlays()
    }

    private func duplicate(_ card: NoteButtonActionCard) {
        guard let index = cards.firstIndex(where: { $0 === card }) else { return }
        var action = card.action
        if case .insert(let placement, let blocks) = action { action = .insert(placement: placement, blocks: blocks.map { $0.withFreshIDs() }) }
        let copy = makeCard(action)
        cards.insert(copy, at: index + 1)
        stack.addSubview(copy)
        layoutCards(animated: true)
        if let host = editor?.canvas.overlayView { copy.template?.attach(to: host) }
        commit()
        sizeMayHaveChanged()
        NoteAnimation.insert(copy)
    }

    private func remove(_ card: NoteButtonActionCard) {
        guard let index = cards.firstIndex(where: { $0 === card }) else { return }
        cards.remove(at: index)
        card.template?.detach()
        commit()
        NoteAnimation.remove(card) { card.removeFromSuperview() }
        layoutCards(animated: true)
        sizeMayHaveChanged()
    }

    private func choosePlacement(for card: NoteButtonActionCard, from anchor: NSView) {
        guard case .insert(let current, _) = card.action else { return }
        let symbols: [NoteButtonPlacement: String] = [.below: "arrow.down.to.line", .above: "arrow.up.to.line",
                                                      .top: "arrow.up.to.line.compact", .bottom: "arrow.down.to.line.compact"]
        let items = NoteButtonPlacement.allCases.map { placement -> NoteMenuList.Item in
            var item = NoteMenuList.Item(id: placement.rawValue, title: placement.title)
            item.icon = .symbol(symbols[placement] ?? "arrow.down")
            item.isChecked = placement == current
            return item
        }
        menu(items, from: anchor, alignment: .trailing) { [weak card] id in
            guard let placement = NoteButtonPlacement(rawValue: id) else { return }
            card?.setPlacement(placement)
        }
    }

    private func chooseTarget(for card: NoteButtonActionCard, from anchor: NSView) {
        guard case .open(let current) = card.action, let editor else { return }
        let environment = editor.environment
        let view = NoteLinkEditorView(existingLink: current.isEmpty ? nil : current,
                                      search: { environment.searchNotes($0, limit: NoteLinkEditorView.resultLimit) },
                                      linkTarget: { environment.linkTarget(for: $0) })
        view.onAction = { [weak self, weak card, weak editor] action in
            switch action {
            case .apply(let link): card?.setTarget(link)
            case .remove: card?.setTarget("")
            case .open(let link): editor?.formatBar.open(link)
            case .cancel: break
            }
            self?.dismissAuxiliary()
        }
        presentAuxiliary(view, from: anchor)
        view.focusField()
    }
}
