import AppKit

@MainActor
class NoteLinkBlockView: NoteCaptionedBlockView {
    enum Style { case bookmark, embed }

    private var entry: NoteLinkEntryView?
    private var card: NoteLinkCardView?
    private var tracking: NSTrackingArea?
    private var hovering = false
    private var fetching: URL?
    private let toolbar = NoteMediaToolbar()
    private let copyButton = NoteToolbarButton(icon: .symbol("link"), label: "Copy link")
    private let captionButton = NoteToolbarButton(icon: .symbol("text.below.photo"), label: "Caption")
    private let deleteButton = NoteToolbarButton(icon: .symbol("trash"), label: "Delete")

    override init(block: NoteBlock, editor: NotePageEditor?) {
        super.init(block: block, editor: editor)
        copyButton.onPress = { [weak self] in self?.copyLink() }
        captionButton.onPress = { [weak self] in self?.revealCaption() }
        deleteButton.onPress = { [weak self] in self?.deleteBlock() }
        addSubview(toolbar)
        setAccessibilityElement(false)
        rebuild(notify: false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    var url: URL? {
        guard let source = block.props.source?.trimmingCharacters(in: .whitespacesAndNewlines), !source.isEmpty else { return nil }
        if let web = NoteMediaSource.webURL(from: source) { return web }
        return editor?.environment.resolve(source) ?? URL(string: source)
    }

    override var allowsCaption: Bool { url != nil }

    override func update(_ block: NoteBlock) {
        super.update(block)
        rebuild(notify: false)
    }

    override func readOnlyDidChange() { rebuild() }

    private func rebuild(notify: Bool = true) {
        if let url {
            entry?.removeFromSuperview()
            entry = nil
            let view = card ?? NoteLinkCardView(style: .bookmark)
            if card == nil {
                view.onOpen = { [weak self] in self?.openLink() }
                view.onHeightChange = { [weak self] in self?.invalidateMeasuredHeight() }
                addSubview(view, positioned: .below, relativeTo: toolbar)
                card = view
            }
            let preview = storedPreview ?? NoteLinkMetadata.shared.cached(url)
            let failed = preview == nil && NoteLinkMetadata.shared.failure(for: url) != nil
            view.configure(url: url, preview: preview, loading: preview == nil && !failed)
            view.setSelected(isBlockSelected)
            if storedPreview == nil { fetchMetadata(for: url) }
        } else {
            card?.removeFromSuperview()
            card = nil
            let view = entry ?? NoteLinkEntryView(style: .bookmark)
            if entry == nil {
                view.onSubmit = { [weak self] url in self?.create(url) }
                addSubview(view, positioned: .below, relativeTo: toolbar)
                entry = view
            }
            view.editable = canEdit
        }
        refreshCaption()
        configureToolbar()
        refreshAccessibility()
        if notify { invalidateMeasuredHeight() } else { needsLayout = true }
    }

    override func focus(at offset: Int?, field: NoteTextField = .body) -> Bool {
        if field == .caption { return super.focus(at: offset, field: field) }
        guard url == nil, canEdit, let entry else { return false }
        return entry.beginEditing()
    }

    private var storedPreview: NoteLinkPreview? {
        guard let stored = block.props.bookmark else { return nil }
        let preview = NoteLinkPreview(title: stored.title, summary: stored.summary, siteName: stored.siteName,
                                      iconURL: stored.iconURL, imageURL: stored.imageURL)
        return preview.isEmpty ? nil : preview
    }

    private func fetchMetadata(for url: URL) {
        guard fetching != url else { return }
        fetching = url
        NoteLinkMetadata.shared.fetch(url) { [weak self] result in
            guard let self, self.url == url else { return }
            self.fetching = nil
            if case .success(let preview) = result { self.storeIfNeeded(preview, for: url) }
            self.rebuild()
        }
    }

    private func storeIfNeeded(_ preview: NoteLinkPreview, for url: URL) {
        guard canEdit, block.props.bookmark == nil, !preview.isEmpty, let session = editor?.session,
              let source = block.props.source else { return }
        let stored = preview.bookmark
        session.updateBlockMetadata(blockID, kind: .structure) { block in
            guard block.props.source == source, block.props.bookmark == nil else { return }
            block.props.bookmark = stored
        }
    }

    private func create(_ url: URL) {
        guard canEdit, let session = editor?.session else { return }
        let id = blockID
        session.edit("Add Bookmark", coalescing: .typing(id, .body), affected: [id]) { page in
            page.update(id) {
                $0.props.source = url.absoluteString
                $0.props.bookmark = nil
            }
        }
        if let cached = NoteLinkMetadata.shared.cached(url) { storeIfNeeded(cached, for: url) }
    }

    func openLink() {
        guard let url else { return }
        editor?.open(url)
    }

    private func copyLink() {
        guard let url else { return }
        let board = NSPasteboard.general
        board.clearContents()
        board.writeObjects([url as NSURL])
        board.setString(url.absoluteString, forType: .string)
    }

    private func deleteBlock() {
        guard canEdit else { return }
        editor?.session.deleteBlocks([blockID])
    }

    private func configureToolbar() {
        var buttons: [NoteControlButton] = [copyButton]
        if canEdit {
            if !captionVisible { buttons.append(captionButton) }
            buttons.append(deleteButton)
        }
        toolbar.setButtons(url == nil ? [] : buttons)
        needsLayout = true
    }

    override func captionRevealDidChange() { configureToolbar() }

    private func refreshAccessibility() {
        guard let url else { return }
        let title = (storedPreview ?? NoteLinkMetadata.shared.cached(url))?.title ?? NoteMediaFormat.displayHost(url)
        card?.setAccessibilityLabel("Bookmark: " + title)
    }

    private static let inset: CGFloat = 4

    override func measureHeight(width: CGFloat) -> CGFloat {
        let body = card?.height(for: width) ?? entry?.height ?? NoteLinkEntryView.defaultHeight
        return ceil(Self.inset * 2 + body + captionHeight(width: width))
    }

    override var handleAnchorY: CGFloat { Self.inset + (card == nil ? NoteLinkEntryView.defaultHeight / 2 : 18) }

    override func layout() {
        super.layout()
        let width = bounds.width
        var bottom = Self.inset
        if let card {
            card.frame = NSRect(x: 0, y: Self.inset, width: width, height: card.height(for: width))
            bottom = card.frame.maxY
        } else if let entry {
            entry.frame = NSRect(x: 0, y: Self.inset, width: width, height: entry.height)
            bottom = entry.frame.maxY
        }
        layoutCaption(top: bottom, x: 0, width: width)
        let toolbarWidth = toolbar.fittingWidth
        toolbar.frame = NSRect(x: max(0, width - 8 - toolbarWidth), y: Self.inset + 8, width: toolbarWidth, height: NoteMediaToolbar.height)
    }

    override func setBlockSelected(_ selected: Bool, animated: Bool) {
        super.setBlockSelected(selected, animated: animated)
        card?.setSelected(selected)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) { setHovering(isTopmost(atWindowPoint: event.locationInWindow)) }
    override func mouseMoved(with event: NSEvent) { setHovering(isTopmost(atWindowPoint: event.locationInWindow)) }
    override func mouseExited(with event: NSEvent) { setHovering(false) }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { setHovering(false) }
    }

    private func setHovering(_ value: Bool) {
        guard value != hovering else { return }
        hovering = value
        card?.setHovered(value)
        if value && card != nil && !toolbar.buttons.isEmpty {
            configureToolbar()
            layoutSubtreeIfNeeded()
            toolbar.show()
        } else {
            toolbar.hide()
        }
    }
}

@MainActor
final class NoteBookmarkBlockView: NoteLinkBlockView {}

@MainActor
final class NoteLinkCardView: NSView {
    enum Layout { case bookmark }

    var onOpen: (() -> Void)?
    var onHeightChange: (() -> Void)?
    private let card = CALayer()
    private let preview = CALayer()
    private let favicon = CALayer()
    private let ring = CALayer()
    private let title: NSTextField
    private let summary: NSTextField
    private let site: NSTextField
    private let shimmerLines = [NoteMediaShimmer(), NoteMediaShimmer()]
    private let previewShimmer = NoteMediaShimmer()
    private var url: URL?
    private var info: NoteLinkPreview?
    private var loading = false
    private var hovered = false
    private var pressed = false
    private var hasPreviewImage = false

    init(style: Layout) {
        title = NoteMediaStyle.label("", font: NoteTheme.nunitoBold(14.5), color: NoteTheme.ink)
        summary = NoteMediaStyle.label("", font: NoteTheme.nunitoRegular(13), color: NoteTheme.secondaryInk, lines: 2)
        summary.lineBreakMode = .byWordWrapping
        summary.cell?.truncatesLastVisibleLine = true
        site = NoteMediaStyle.label("", font: NoteTheme.nunitoRegular(12.5), color: NoteTheme.tertiaryInk)
        super.init(frame: .zero)
        wantsLayer = true
        card.cornerRadius = NoteMediaStyle.cardRadius
        card.cornerCurve = .continuous
        card.borderWidth = 1
        card.masksToBounds = true
        preview.contentsGravity = .resizeAspectFill
        preview.masksToBounds = true
        preview.opacity = 0
        favicon.contentsGravity = .resizeAspect
        favicon.cornerRadius = 3
        favicon.cornerCurve = .continuous
        favicon.masksToBounds = true
        ring.cornerRadius = NoteMediaStyle.cardRadius + 2
        ring.cornerCurve = .continuous
        ring.borderWidth = 2
        ring.isHidden = true
        layer?.addSublayer(card)
        card.addSublayer(preview)
        layer?.addSublayer(favicon)
        layer?.addSublayer(ring)
        previewShimmer.cornerRadius = 0
        addSubview(previewShimmer)
        for line in shimmerLines {
            line.cornerRadius = 3
            addSubview(line)
        }
        for view in [title, summary, site] { addSubview(view) }
        setAccessibilityElement(true)
        setAccessibilityRole(.link)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    func configure(url: URL, preview info: NoteLinkPreview?, loading: Bool) {
        let changedImage = info?.imageURL != self.info?.imageURL || url != self.url
        let changedIcon = info?.iconURL != self.info?.iconURL || url != self.url
        self.url = url
        self.info = info
        self.loading = loading
        let host = NoteMediaFormat.displayHost(url)
        title.stringValue = info?.title ?? host
        summary.stringValue = info?.summary ?? ""
        site.stringValue = siteLine(url: url)
        setAccessibilityValue(url.absoluteString)
        setAccessibilityHelp(loading ? "Fetching a preview." : "Opens the link.")
        if changedImage { loadPreview() }
        if changedIcon { loadFavicon() }
        refreshShimmer()
        needsLayout = true
    }

    private func siteLine(url: URL) -> String {
        var text = url.absoluteString
        if text.hasPrefix("https://") { text.removeFirst(8) } else if text.hasPrefix("http://") { text.removeFirst(7) }
        if text.hasSuffix("/") { text.removeLast() }
        return text
    }

    private func refreshShimmer() {
        let showLines = loading && summary.stringValue.isEmpty
        for line in shimmerLines { line.isHidden = !showLines }
        previewShimmer.isHidden = !(loading || (info?.imageURL != nil && !hasPreviewImage))
    }

    private func loadPreview() {
        hasPreviewImage = false
        NoteMediaMotion.instant { preview.contents = nil; preview.opacity = 0 }
        guard let link = info?.imageURL, let imageURL = URL(string: link) else { refreshShimmer(); return }
        let expected = url
        NoteMediaImageLoader.shared.load(imageURL, pixels: 1024) { [weak self] result in
            guard let self, self.url == expected, self.info?.imageURL == link else { return }
            if case .success(let image) = result {
                self.hasPreviewImage = true
                NoteMediaMotion.instant { self.preview.contents = image.first }
                NoteMediaMotion.fadeIn(self.preview)
            }
            self.refreshShimmer()
            self.needsLayout = true
        }
    }

    private func loadFavicon() {
        NoteMediaMotion.instant { favicon.contents = NoteMediaStyle.symbol("globe", size: 12, weight: .medium).map { NoteMediaStyle.tinted($0, NoteTheme.tertiaryInk, in: self) } }
        guard let link = info?.iconURL ?? url.flatMap(NoteLinkMetadataParser.defaultIcon), let iconURL = URL(string: link) else { return }
        let expected = url
        NoteMediaImageLoader.shared.load(iconURL, pixels: 64) { [weak self] result in
            guard let self, self.url == expected, case .success(let image) = result else { return }
            NoteMediaMotion.instant { self.favicon.contents = image.first }
        }
    }

    var showsPreview: Bool { info?.imageURL != nil }

    func height(for width: CGFloat) -> CGFloat {
        let hasSummary = !(info?.summary ?? "").isEmpty || loading
        return hasSummary || (showsPreview && width >= 360) ? 106 : 72
    }

    override func layout() {
        super.layout()
        let bounds = self.bounds
        let showsImage = showsPreview && bounds.width >= 360
        let previewWidth = showsImage ? min(250, (bounds.width * 0.33).rounded()) : 0
        let previewRect = NSRect(x: bounds.width - previewWidth, y: 0, width: previewWidth, height: bounds.height)
        let textRect = NSRect(x: 16, y: 14, width: max(0, bounds.width - previewWidth - 32), height: bounds.height - 28)
        NoteMediaMotion.instant {
            card.frame = bounds
            preview.frame = previewRect
            ring.frame = bounds.insetBy(dx: -3, dy: -3)
            let scale = window?.backingScaleFactor ?? 2
            preview.contentsScale = scale
            favicon.contentsScale = scale
        }
        previewShimmer.frame = previewRect
        let summaryText = summary.stringValue
        let hasSummary = !summaryText.isEmpty || loading
        title.frame = NSRect(x: textRect.minX, y: textRect.minY, width: textRect.width, height: 21)
        var y = title.frame.maxY + 3
        if hasSummary {
            summary.frame = NSRect(x: textRect.minX, y: y, width: textRect.width, height: 36)
            shimmerLines[0].frame = NSRect(x: textRect.minX, y: y + 4, width: textRect.width * 0.92, height: 10)
            shimmerLines[1].frame = NSRect(x: textRect.minX, y: y + 22, width: textRect.width * 0.6, height: 10)
            y += 40
        } else {
            summary.frame = .zero
        }
        let siteY = max(y, textRect.maxY - 18)
        NoteMediaMotion.instant { favicon.frame = NSRect(x: textRect.minX, y: siteY + 1, width: 16, height: 16) }
        site.frame = NSRect(x: textRect.minX + 22, y: siteY, width: max(0, textRect.width - 22), height: 18)
        refreshColors()
    }

    private func refreshColors() {
        let fill = pressed ? NoteTheme.pressedFill : hovered ? NoteTheme.hoverFill : NSColor.clear
        NoteMediaMotion.instant {
            card.backgroundColor = NoteMediaStyle.cg(fill, in: self)
            card.borderColor = NoteMediaStyle.cg(NoteMediaStyle.cardStroke, in: self)
            ring.borderColor = NoteMediaStyle.cg(NoteTheme.accent, in: self)
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsLayout = true
        if !hasPreviewImage { loadFavicon() }
    }

    func setHovered(_ value: Bool) {
        hovered = value
        let from = card.presentation()?.backgroundColor
        refreshColors()
        guard !NoteAnimation.reduceMotion, let from else { return }
        let fade = CABasicAnimation(keyPath: "backgroundColor")
        fade.fromValue = from
        fade.toValue = card.backgroundColor
        fade.duration = 0.1
        fade.timingFunction = CAMediaTimingFunction(controlPoints: 0.42, 0, 1, 1)
        card.add(fade, forKey: "link.hover")
    }

    func setSelected(_ selected: Bool) {
        NoteMediaMotion.instant { ring.isHidden = !selected }
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        pressed = true
        refreshColors()
        if let layer { NoteMediaMotion.press(layer, pressed: true, in: self, scale: 0.992) }
    }

    override func mouseDragged(with event: NSEvent) {
        let inside = bounds.contains(convert(event.locationInWindow, from: nil))
        guard inside != pressed else { return }
        pressed = inside
        refreshColors()
        if let layer { NoteMediaMotion.press(layer, pressed: inside, in: self, scale: 0.992) }
    }

    override func mouseUp(with event: NSEvent) {
        let inside = bounds.contains(convert(event.locationInWindow, from: nil))
        pressed = false
        refreshColors()
        if let layer { NoteMediaMotion.press(layer, pressed: false, in: self, scale: 0.992) }
        if inside { onOpen?() }
    }

    override func accessibilityPerformPress() -> Bool {
        onOpen?()
        return true
    }
}

@MainActor
final class NoteLinkEntryView: NoteMediaContentHostlessCard, NSTextFieldDelegate {
    static let defaultHeight: CGFloat = 52
    var onSubmit: ((URL) -> Void)?
    var editable = true { didSet { applyMode() } }
    private let icon = NSImageView()
    private let field = NSTextField()
    private let submit: NoteChip
    private let readOnlyLabel: NSTextField
    private let hint: NSTextField
    private let style: NoteLinkBlockView.Style

    init(style: NoteLinkBlockView.Style) {
        self.style = style
        submit = NoteChip(style == .embed ? "Embed link" : "Create bookmark", icon: .symbol(style == .embed ? "rectangle.on.rectangle" : "bookmark"))
        readOnlyLabel = NoteMediaStyle.label(style == .embed ? "No embed here yet" : "No bookmark here yet",
                                             font: NoteMediaStyle.titleFont, color: NoteTheme.secondaryInk)
        hint = NoteMediaStyle.label("That doesn’t look like a link.", font: NoteMediaStyle.smallFont, color: NoteMediaStyle.warningInk)
        super.init(frame: .zero)
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.contentTintColor = NoteTheme.tertiaryInk
        icon.image = NoteMediaStyle.symbol(style == .embed ? "rectangle.on.rectangle" : "bookmark", size: 16, weight: .medium)
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = NoteTheme.nunitoRegular(14)
        field.textColor = NoteTheme.ink
        field.placeholderAttributedString = NSAttributedString(
            string: style == .embed ? "Paste a link to embed…" : "Paste a link to bookmark…",
            attributes: [.font: NoteTheme.nunitoRegular(14), .foregroundColor: NoteTheme.placeholderInk])
        field.delegate = self
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        field.setAccessibilityLabel(style == .embed ? "Link to embed" : "Link to bookmark")
        submit.onPress = { [weak self] in self?.submitLink() }
        hint.isHidden = true
        for view in [icon, field, submit, readOnlyLabel, hint] as [NSView] { addSubview(view) }
        applyMode()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    var height: CGFloat { Self.defaultHeight }

    private func applyMode() {
        field.isHidden = !editable
        submit.isHidden = !editable
        readOnlyLabel.isHidden = editable
        needsLayout = true
    }

    func beginEditing() -> Bool {
        guard editable, let window else { return false }
        return window.makeFirstResponder(field)
    }

    private func submitLink() {
        guard let url = NoteMediaSource.webURL(from: field.stringValue) else {
            hint.isHidden = false
            needsLayout = true
            if let layer = field.layer ?? { field.wantsLayer = true; return field.layer }(), !NoteAnimation.reduceMotion {
                let shake = CAKeyframeAnimation(keyPath: "transform.translation.x")
                shake.values = [0, -6, 5, -3, 2, 0]
                shake.duration = 0.32
                layer.add(shake, forKey: "link.shake")
            }
            return
        }
        onSubmit?(url)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.insertNewline(_:)): submitLink(); return true
        case #selector(NSResponder.cancelOperation(_:)):
            field.stringValue = ""
            hint.isHidden = true
            window?.makeFirstResponder(nil)
            return true
        default: return false
        }
    }

    func controlTextDidChange(_ obj: Notification) {
        if !hint.isHidden { hint.isHidden = true; needsLayout = true }
    }

    override func layout() {
        super.layout()
        let height = bounds.height
        icon.frame = NSRect(x: 16, y: (height - 18) / 2, width: 18, height: 18)
        let size = submit.intrinsicContentSize
        submit.frame = NSRect(x: bounds.width - 12 - size.width, y: (height - size.height) / 2, width: size.width, height: size.height)
        let hintWidth = hint.isHidden ? 0 : min(190, ceil(hint.intrinsicContentSize.width))
        let fieldWidth = max(40, submit.frame.minX - 8 - 44 - (hintWidth > 0 ? hintWidth + 8 : 0))
        field.frame = NSRect(x: 44, y: (height - 20) / 2, width: fieldWidth, height: 20)
        hint.frame = NSRect(x: field.frame.maxX + 8, y: (height - 16) / 2, width: hintWidth, height: 16)
        readOnlyLabel.frame = NSRect(x: 44, y: (height - 20) / 2, width: max(0, bounds.width - 56), height: 20)
    }

    override func mouseDown(with event: NSEvent) {
        guard editable else { return }
        window?.makeFirstResponder(field)
    }
}

@MainActor
class NoteMediaContentHostlessCard: NSView {
    private let card = CALayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        card.cornerRadius = NoteMediaStyle.cardRadius
        card.cornerCurve = .continuous
        card.borderWidth = 1
        layer?.addSublayer(card)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        NoteMediaMotion.instant {
            card.frame = bounds
            card.backgroundColor = NoteMediaStyle.cg(NoteMediaStyle.cardFill, in: self)
            card.borderColor = NoteMediaStyle.cg(NoteMediaStyle.cardStroke, in: self)
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsLayout = true
    }
}

@MainActor
final class NotePageLinkBlockView: NoteBlockView {
    private let fill = CALayer()
    private let ring = CALayer()
    private let iconView = NoteIconView(pointSize: 17)
    private let badge = NSImageView()
    private let title: NSTextField
    private let underline = CALayer()
    private let note: NSTextField
    private let removeChip = NoteChip("Remove", icon: .symbol("trash"))
    private var target: URL?
    private var broken = false
    private var tracking: NSTrackingArea?
    private var hovered = false
    private var pressed = false
    private static let height: CGFloat = 34

    override init(block: NoteBlock, editor: NotePageEditor?) {
        title = NoteMediaStyle.label("", font: NoteTheme.nunitoBold(16), color: NoteTheme.mentionInk)
        note = NoteMediaStyle.label("", font: NoteTheme.nunitoRegular(13), color: NoteTheme.tertiaryInk)
        super.init(block: block, editor: editor)
        fill.cornerRadius = NoteTheme.controlRadius
        fill.cornerCurve = .continuous
        fill.opacity = 0
        ring.cornerRadius = NoteTheme.controlRadius
        ring.cornerCurve = .continuous
        ring.borderWidth = 1.5
        ring.isHidden = true
        layer?.addSublayer(fill)
        layer?.addSublayer(ring)
        layer?.addSublayer(underline)
        badge.image = NoteMediaStyle.symbol("arrow.up.right", size: 7, weight: .black)
        badge.imageScaling = .scaleNone
        badge.wantsLayer = true
        badge.layer?.cornerRadius = 5
        removeChip.onPress = { [weak self] in self?.remove() }
        for view in [iconView, badge, title, note, removeChip] as [NSView] { addSubview(view) }
        setAccessibilityElement(true)
        refresh()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func update(_ block: NoteBlock) {
        super.update(block)
        refresh()
    }

    override func readOnlyDidChange() { refresh() }

    private var canEdit: Bool { !isReadOnly && editor?.isReadOnly != true }

    private func refresh() {
        let raw = block.props.target ?? ""
        let resolved = raw.isEmpty ? nil : (editor?.environment.resolveNoteLink(raw) ?? URL(string: raw))
        target = resolved
        broken = resolved.map { !$0.isFileURL || !FileManager.default.fileExists(atPath: $0.path) } ?? true
        if broken {
            let remembered = block.text.plainText.trimmingCharacters(in: .whitespacesAndNewlines)
            let name = remembered.isEmpty ? NoteLinkedNote.title(fromTarget: raw) : remembered
            iconView.icon = .symbol("questionmark.square.dashed")
            iconView.tint = NoteTheme.tertiaryInk
            title.stringValue = "This note moved or was deleted"
            title.textColor = NoteTheme.secondaryInk
            note.stringValue = name
            setAccessibilityRole(.group)
            setAccessibilityLabel("Broken note link" + (name.isEmpty ? "" : ": " + name))
        } else if let target {
            let name = target.deletingPathExtension().lastPathComponent
            title.stringValue = name.isEmpty ? NoteTheme.titlePlaceholder : name
            title.textColor = NoteTheme.mentionInk
            note.stringValue = ""
            if let emoji = NoteLinkedNote.icon(for: target), !emoji.isEmpty, emoji.count <= 2 {
                iconView.icon = .emoji(emoji)
            } else {
                iconView.icon = .symbol("doc.text")
                iconView.tint = NoteTheme.secondaryInk
            }
            setAccessibilityRole(.link)
            setAccessibilityLabel("Link to note: " + title.stringValue)
        }
        removeChip.isHidden = !(broken && canEdit)
        badge.isHidden = broken
        window?.invalidateCursorRects(for: self)
        needsLayout = true
    }

    override func measureHeight(width: CGFloat) -> CGFloat { Self.height }
    override var handleAnchorY: CGFloat { Self.height / 2 }

    override func layout() {
        super.layout()
        let height = bounds.height
        iconView.frame = NSRect(x: 4, y: (height - 24) / 2, width: 24, height: 24)
        badge.frame = NSRect(x: iconView.frame.maxX - 9, y: iconView.frame.maxY - 9, width: 10, height: 10)
        var trailing = bounds.width - 6
        if !removeChip.isHidden {
            let size = removeChip.intrinsicContentSize
            removeChip.frame = NSRect(x: trailing - size.width, y: (height - size.height) / 2, width: size.width, height: size.height)
            trailing = removeChip.frame.minX - 8
        }
        let available = max(0, trailing - 34)
        let titleWidth = min(available, NoteMediaStyle.textWidth(title))
        title.frame = NSRect(x: 34, y: (height - 22) / 2, width: titleWidth, height: 22)
        let noteWidth = max(0, min(available - titleWidth - 8, NoteMediaStyle.textWidth(note)))
        note.frame = NSRect(x: title.frame.maxX + 8, y: (height - 18) / 2 + 1, width: noteWidth, height: 18)
        NoteMediaMotion.instant {
            fill.frame = NSRect(x: 0, y: 1, width: min(bounds.width, (broken ? note.frame.maxX : title.frame.maxX) + 8), height: height - 2)
            ring.frame = fill.frame
            underline.frame = NSRect(x: title.frame.minX + 2, y: title.frame.maxY - 2, width: broken ? 0 : max(0, titleWidth - 6), height: 1)
            fill.backgroundColor = NoteMediaStyle.cg(pressed ? NoteTheme.pressedFill : NoteTheme.hoverFill, in: self)
            ring.borderColor = NoteMediaStyle.cg(NoteTheme.accent, in: self)
            underline.backgroundColor = NoteMediaStyle.cg(NoteTheme.mentionUnderline, in: self)
            badge.layer?.backgroundColor = NoteMediaStyle.cg(NoteTheme.menuFill, in: self)
        }
        badge.contentTintColor = NoteTheme.secondaryInk
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsLayout = true
    }

    override func themeDidChange() {
        super.themeDidChange()
        needsLayout = true
    }

    override func setBlockSelected(_ selected: Bool, animated: Bool) {
        super.setBlockSelected(selected, animated: animated)
        NoteMediaMotion.instant { ring.isHidden = !selected }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) { setHovered(!broken && isTopmost(atWindowPoint: event.locationInWindow)) }
    override func mouseExited(with event: NSEvent) { setHovered(false) }

    private func setHovered(_ value: Bool) {
        guard value != hovered else { return }
        hovered = value
        let target: Float = value ? 1 : 0
        let from = fill.presentation()?.opacity ?? fill.opacity
        NoteMediaMotion.instant { fill.opacity = target }
        guard !NoteAnimation.reduceMotion else { return }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = from
        fade.toValue = target
        fade.duration = 0.1
        fill.add(fade, forKey: "pagelink.hover")
    }

    override func resetCursorRects() {
        guard !broken else { return }
        addCursorRect(fill.frame, cursor: .pointingHand)
    }

    override func mouseDown(with event: NSEvent) {
        guard !broken, fill.frame.contains(convert(event.locationInWindow, from: nil)) else { super.mouseDown(with: event); return }
        pressed = true
        needsLayout = true
    }

    override func mouseUp(with event: NSEvent) {
        guard pressed else { super.mouseUp(with: event); return }
        pressed = false
        needsLayout = true
        if fill.frame.contains(convert(event.locationInWindow, from: nil)) { openNote() }
    }

    override func accessibilityPerformPress() -> Bool {
        guard !broken else { return false }
        openNote()
        return true
    }

    private func openNote() {
        guard let target, !broken else { return }
        editor?.open(target)
    }

    private func remove() {
        guard canEdit else { return }
        editor?.session.deleteBlocks([blockID])
    }
}
