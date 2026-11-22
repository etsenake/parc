import AppKit
import ParcCore

@MainActor
class NoteLinkBlockView: NoteCaptionedBlockView {
    typealias Style = NoteLinkEntryView.Style

    private var entry: NoteLinkEntryView?
    private var card: NoteLinkCardView?
    private var tracking: NSTrackingArea?
    private var hovering = false
    private var fetching: URL?
    private var attempted: URL?
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
        guard fetching != url, attempted != url else { return }
        fetching = url
        attempted = url
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
        editor?.follow(url, event: NSApp.currentEvent)
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
    private var linkZone = NoteZoneCursor(includesDescendants: true)
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
                iconView.icon = .noteMark
            }
            setAccessibilityRole(.link)
            setAccessibilityLabel("Link to note: " + title.stringValue)
        }
        removeChip.isHidden = !(broken && canEdit)
        badge.isHidden = broken
        refreshCursorIfPointerOwned()
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
        let area = NSTrackingArea(rect: .zero, options: [.cursorUpdate, .mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) { setHovered(!broken && isTopmost(atWindowPoint: event.locationInWindow)) }

    override func mouseMoved(with event: NSEvent) {
        setHovered(!broken && isTopmost(atWindowPoint: event.locationInWindow))
        linkZone.moved(linkCursor(for: event), in: self, event: event)
    }

    override func mouseExited(with event: NSEvent) {
        setHovered(false)
        linkZone.exited()
    }

    private func linkCursor(for event: NSEvent) -> NSCursor? {
        !broken && fill.frame.contains(convert(event.locationInWindow, from: nil)) ? .pointingHand : nil
    }

    override func cursorUpdate(with event: NSEvent) {
        if !linkZone.cursorUpdate(linkCursor(for: event), in: self, event: event) { super.cursorUpdate(with: event) }
    }

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
