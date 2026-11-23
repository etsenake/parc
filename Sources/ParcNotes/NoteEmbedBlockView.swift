import AppKit
import ParcCore

@MainActor
final class NoteEmbedBlockView: NoteCaptionedBlockView, NotePageHostObserving {
    private static let inset: CGFloat = 4
    private static let handleRoom: CGFloat = 8
    private var entry: NoteLinkEntryView?
    private var surface: NoteEmbedSurface?
    private var standby: NoteEmbedStandbyView?
    private let handle = NoteEmbedResizeHandle(frame: NSRect(origin: .zero, size: NoteEmbedResizeHandle.size))
    private var dragStart: Double?
    private var liveHeight: Double?
    private var tracking: NSTrackingArea?
    private let pageZone = NoteZoneCursor()

    override init(block: NoteBlock, editor: NotePageEditor?) {
        super.init(block: block, editor: editor)
        handle.onDrag = { [weak self] delta in self?.resize(by: delta, commit: false) }
        handle.onEnd = { [weak self] delta in self?.resize(by: delta, commit: true) }
        handle.onStep = { [weak self] delta in
            self?.dragStart = nil
            self?.resize(by: delta, commit: true)
        }
        addSubview(handle)
        setAccessibilityElement(false)
        rebuild(notify: false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    var address: URL? { NoteEmbeddedPages.address(of: block) }

    override var allowsCaption: Bool { address != nil }

    private var pages: NoteEmbeddedPages? { editor.flatMap { NoteEmbeddedPages.pool(for: $0) } }

    private var pageHeight: Double { liveHeight ?? NoteEmbedSizing.height(of: block.props) }

    private var frameHeight: CGFloat { NoteEmbedSurface.headerHeight + CGFloat(pageHeight) + 1 }

    func pageHostDidChange() { rebuild() }

    override func update(_ block: NoteBlock) {
        let previous = self.block
        super.update(block)
        if previous.props.height != block.props.height { liveHeight = nil }
        rebuild(notify: false)
    }

    override func readOnlyDidChange() { rebuild() }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { attachSurface() }
    }

    private func rebuild(notify: Bool = true) {
        if address != nil {
            entry?.removeFromSuperview()
            entry = nil
            attachSurface()
        } else {
            detachSurface()
            standby?.removeFromSuperview()
            standby = nil
            let view = entry ?? NoteLinkEntryView(style: .embed)
            if entry == nil {
                view.onSubmit = { [weak self] url in self?.create(url) }
                addSubview(view, positioned: .below, relativeTo: handle)
                entry = view
            }
            view.editable = canEdit
        }
        handle.isHidden = address == nil || !canEdit
        refreshCaption()
        refreshCursorIfPointerOwned()
        if notify { invalidateMeasuredHeight() } else { needsLayout = true }
    }

    private func attachSurface() {
        guard let address else { return }
        if let next = window == nil ? nil : pages?.surface(for: blockID, address: address) {
            if next.superview !== self { addSubview(next, positioned: .below, relativeTo: handle) }
            if surface !== next { detachSurface() }
            surface = next
            next.selected = isBlockSelected
            refreshCaptionButton()
            standby?.removeFromSuperview()
            standby = nil
        } else {
            detachSurface()
            if standby?.address != address {
                standby?.removeFromSuperview()
                let view = NoteEmbedStandbyView(address: address)
                view.onOpen = { [weak self] in self?.editor?.open(address) }
                view.selected = isBlockSelected
                addSubview(view, positioned: .below, relativeTo: handle)
                standby = view
            }
        }
        needsLayout = true
    }

    private func refreshCaptionButton() {
        guard let surface, surface.superview === self else { return }
        surface.onCaption = canEdit && !captionVisible ? { [weak self] in self?.revealCaption() } : nil
    }

    override func captionRevealDidChange() { refreshCaptionButton() }

    private func detachSurface() {
        if let surface, surface.superview === self { surface.removeFromSuperview() }
        surface = nil
    }

    override func focus(at offset: Int?, field: NoteTextField = .body) -> Bool {
        if field == .caption { return super.focus(at: offset, field: field) }
        guard address == nil, canEdit, let entry else { return false }
        return entry.beginEditing()
    }

    private func create(_ url: URL) {
        guard canEdit, let session = editor?.session else { return }
        let id = blockID
        session.edit("Embed Link", coalescing: .typing(id, .body), affected: [id]) { page in
            page.update(id) {
                $0.props.source = url.absoluteString
                $0.props.bookmark = nil
            }
        }
    }

    private func resize(by delta: CGFloat, commit: Bool) {
        guard canEdit, address != nil else { return }
        let start = dragStart ?? NoteEmbedSizing.height(of: block.props)
        dragStart = commit ? nil : start
        let height = NoteEmbedSizing.resized(from: start, by: Double(delta))
        guard commit else {
            if liveHeight != height {
                liveHeight = height
                invalidateMeasuredHeight()
            }
            return
        }
        let stored = NoteEmbedSizing.stored(height)
        guard stored != block.props.height, let session = editor?.session else {
            liveHeight = nil
            invalidateMeasuredHeight()
            return
        }
        let id = blockID
        session.edit("Resize Embed", affected: [id]) { page in
            page.update(id) { $0.props.height = stored }
        }
        liveHeight = nil
        invalidateMeasuredHeight()
    }

    override func measureHeight(width: CGFloat) -> CGFloat {
        guard address != nil else {
            return ceil(Self.inset * 2 + (entry?.height ?? NoteLinkEntryView.defaultHeight) + captionHeight(width: width))
        }
        return ceil(Self.inset + frameHeight + Self.handleRoom + captionHeight(width: width) + Self.inset)
    }

    override var handleAnchorY: CGFloat {
        address == nil ? Self.inset + NoteLinkEntryView.defaultHeight / 2 : Self.inset + NoteEmbedSurface.headerHeight / 2
    }

    override func layout() {
        super.layout()
        let width = bounds.width
        guard address != nil else {
            entry?.frame = NSRect(x: 0, y: Self.inset, width: width, height: entry?.height ?? NoteLinkEntryView.defaultHeight)
            layoutCaption(top: (entry?.frame.maxY ?? Self.inset), x: 0, width: width)
            return
        }
        let box = NSRect(x: 0, y: Self.inset, width: width, height: frameHeight)
        NoteAnimation.withoutAnimation {
            if let surface, surface.superview === self { surface.frame = box }
            standby?.frame = box
        }
        let size = NoteEmbedResizeHandle.size
        handle.frame = NSRect(x: ((width - size.width) / 2).rounded(), y: box.maxY - size.height / 2 + 1, width: size.width, height: size.height)
        layoutCaption(top: box.maxY + Self.handleRoom - NoteMediaStyle.captionGap, x: 0, width: width)
    }

    override func setBlockSelected(_ selected: Bool, animated: Bool) {
        super.setBlockSelected(selected, animated: animated)
        if let surface, surface.superview === self { surface.selected = selected }
        standby?.selected = selected
    }

    private func pageCursor(for event: NSEvent) -> NSCursor? {
        guard let surface, surface.superview === self, !surface.interactive,
              convert(surface.pageRect, from: surface).contains(convert(event.locationInWindow, from: nil)) else { return nil }
        return .pointingHand
    }

    override func cursorUpdate(with event: NSEvent) {
        if !pageZone.cursorUpdate(pageCursor(for: event), in: self, event: event) { super.cursorUpdate(with: event) }
    }

    override func mouseDown(with event: NSEvent) {
        guard let surface, surface.superview === self, !surface.interactive, let pages,
              surface.pageRect.contains(surface.convert(event.locationInWindow, from: nil)) else {
            super.mouseDown(with: event)
            return
        }
        pages.activate(blockID)
        refreshCursorIfPointerOwned()
        if surface.interactive { window?.postEvent(event, atStart: true) }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.cursorUpdate, .mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) {
        handle.setVisible(!handle.isHidden && NoteFloatingPanel.allowsHover(for: self, at: event.locationInWindow))
    }

    override func mouseMoved(with event: NSEvent) {
        handle.setVisible(!handle.isHidden && NoteFloatingPanel.allowsHover(for: self, at: event.locationInWindow))
        pageZone.moved(pageCursor(for: event), in: self, event: event)
    }

    override func mouseExited(with event: NSEvent) {
        handle.setVisible(false)
        pageZone.exited()
    }
}

@MainActor
private final class NoteEmbedStandbyView: NSView {
    let address: URL
    var onOpen: (() -> Void)?
    var selected = false {
        didSet {
            guard selected != oldValue else { return }
            NoteAnimation.fade(ring, to: selected ? 1 : 0, duration: 0.12)
        }
    }
    private let ring = CALayer()
    private let fallback: NoteEmbedFallbackView

    init(address: URL) {
        self.address = address
        fallback = NoteEmbedFallbackView(address: address)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = NoteMediaStyle.cardRadius
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 1
        ring.cornerRadius = NoteMediaStyle.cardRadius + 3
        ring.cornerCurve = .continuous
        ring.borderWidth = 2
        ring.opacity = 0
        layer?.addSublayer(ring)
        fallback.onOpen = { [weak self] in self?.onOpen?() }
        fallback.configure(status: "Waking the page up…", retryTitle: nil)
        addSubview(fallback)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Live page: " + NoteMediaFormat.displayHost(address))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        fallback.frame = bounds.insetBy(dx: 1, dy: 1)
        NoteMediaMotion.instant {
            ring.frame = bounds.insetBy(dx: -3, dy: -3)
            layer?.backgroundColor = NoteMediaStyle.cg(NoteMediaStyle.cardFill, in: self)
            layer?.borderColor = NoteMediaStyle.cg(NoteMediaStyle.cardStroke, in: self)
            ring.borderColor = NoteMediaStyle.cg(NoteTheme.accent, in: self)
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsLayout = true
    }
}
