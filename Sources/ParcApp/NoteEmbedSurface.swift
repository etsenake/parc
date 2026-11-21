import AppKit

@MainActor
final class NoteEmbedSurface: NSView, EmbeddedPageSurface {
    static let headerHeight: CGFloat = 38
    let browser: PCBrowserView
    let address: URL
    let liveAddress: URL
    var positioningAllowed = true
    var onLayout: (() -> Void)?
    var onRetry: (() -> Void)?
    var onNavigate: ((URL) -> Bool)?
    var onDone: (() -> Void)?
    var onOpen: ((URL) -> Void)?
    var onCaption: (() -> Void)? {
        didSet {
            guard captionButton.isHidden != (onCaption == nil) else { return }
            captionButton.isHidden = onCaption == nil
            header.needsLayout = true
        }
    }
    var interactive = false {
        didSet {
            guard interactive != oldValue else { return }
            refresh()
            refreshRing(animated: true)
            superview?.refreshCursorIfPointerOwned()
        }
    }
    var selected = false { didSet { if selected != oldValue { refreshRing(animated: true) } } }
    var scrollLatched = false
    private let content = NoteEmbedPageClip()
    private let ring = CALayer()
    private let header = EmbeddedPageHeader()
    private let clip = NoteEmbedPageClip()
    private let backButton = NoteToolbarButton(icon: .symbol("chevron.left"), label: "Back")
    private let reloadButton = NoteToolbarButton(icon: .symbol("arrow.clockwise"), label: "Reload")
    private let openButton = NoteToolbarButton(icon: .symbol("arrow.up.right.square"), label: "Open in a tab")
    private let doneButton = NoteToolbarButton(icon: .symbol("checkmark"), label: "Back to the note")
    private let captionButton = NoteToolbarButton(icon: .symbol("text.below.photo"), label: "Caption")
    private let fallback: NoteEmbedFallbackView
    private var status: String?
    private var retryTitle = "Retry"

    init(address: URL, profilePath: String) {
        self.address = address
        liveAddress = NoteEmbedAddress.liveURL(for: address)
        browser = PCBrowserView(frame: .zero, profilePath: profilePath)
        fallback = NoteEmbedFallbackView(address: address)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = false
        content.wantsLayer = true
        content.layer?.cornerRadius = NoteMediaStyle.cardRadius
        content.layer?.cornerCurve = .continuous
        content.layer?.borderWidth = 1
        content.layer?.masksToBounds = true
        addSubview(content)
        ring.cornerRadius = NoteMediaStyle.cardRadius + 3
        ring.cornerCurve = .continuous
        ring.borderWidth = 2
        ring.opacity = 0
        clip.wantsLayer = true
        clip.layer?.masksToBounds = true
        clip.exposesChildren = { [weak self] in self?.inputAvailable == true }
        content.addSubview(clip)
        clip.addSubview(browser)
        fallback.onOpen = { [weak self] in
            guard let self else { return }
            self.onOpen?(self.address)
        }
        fallback.onRetry = { [weak self] in self?.onRetry?() }
        content.addSubview(fallback)
        content.addSubview(header)
        backButton.onPress = { [weak self] in self?.navigate(.back) }
        reloadButton.onPress = { [weak self] in self?.reloadOrStop() }
        openButton.onPress = { [weak self] in self?.openInTab() }
        doneButton.onPress = { [weak self] in self?.onDone?() }
        doneButton.isHidden = true
        captionButton.onPress = { [weak self] in self?.onCaption?() }
        captionButton.isHidden = true
        header.buttons = [captionButton, backButton, reloadButton, openButton, doneButton]
        layer?.addSublayer(ring)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Live page: " + NoteMediaFormat.displayHost(address))
        NoteAnimation.observeReduceMotion(self) { [weak self] in
            guard let self else { return }
            NoteAnimation.settle(self.ring)
            if let layer = self.fallback.layer { NoteAnimation.settle(layer) }
        }
        header.loadPreview(for: address) { [weak self] preview in
            if let preview { self?.fallback.configure(preview: preview) }
            self?.refresh()
        }
        setStatus("Loading webpage…", retry: false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    var inputAvailable: Bool {
        interactive && (browser.nativePage?.isClosed != false || browser.nativePage?.embeddedOwnerValid == true)
    }

    var showsRecovery: Bool { status != nil || browser.nativePage?.rendererCrash != nil }

    var pageArea: (page: NSRect, visible: NSRect) { (convert(browser.bounds, from: browser), clip.frame) }

    var pageRect: NSRect {
        NSRect(x: 1, y: Self.headerHeight, width: max(1, bounds.width - 2), height: max(1, bounds.height - Self.headerHeight - 1))
    }

    func setStatus(_ text: String?, retry: Bool) {
        let wasLive = status == nil
        status = text
        fallback.configure(status: text.map(Self.friendly), retryTitle: retry ? retryTitle : nil)
        if text == nil {
            if !wasLive || !fallback.isHidden { hideFallback() }
        } else {
            fallback.layer?.removeAllAnimations()
            fallback.isHidden = false
            fallback.alphaValue = 1
            fallback.layer?.opacity = 1
        }
        refresh()
        needsLayout = true
    }

    private static func friendly(_ text: String) -> String { EmbeddedPageStatusText.friendly(text, document: "note") }

    func setRetryTitle(_ title: String) {
        retryTitle = title
        if let status { fallback.configure(status: Self.friendly(status), retryTitle: title) }
    }

    private func hideFallback() {
        guard !fallback.isHidden else { return }
        NoteAnimation.fade(fallback, visible: false, duration: 0.18) { [weak self] in
            guard let self, self.status == nil else { return }
            self.fallback.isHidden = true
        }
    }

    func refresh() {
        let page = browser.nativePage
        let live = page?.isClosed == false && page?.embeddedOwnerValid == true
        let title = browser.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let preview = NoteLinkMetadata.shared.cached(address)
        header.setPage(title: live && !title.isEmpty ? title : (preview?.title ?? NoteMediaFormat.displayHost(address)),
                       host: NoteMediaFormat.displayHost(live ? (page?.url ?? address) : address))
        backButton.isEnabled = live && page?.canPerformNavigation(.back) == true
        let loading = browser.isLoading
        reloadButton.content = .icon(.symbol(loading ? "xmark" : "arrow.clockwise"))
        reloadButton.setAccessibilityLabel(loading ? "Stop" : "Reload")
        reloadButton.setToolTip(loading ? "Stop" : "Reload")
        reloadButton.isEnabled = live && page?.canPerformNavigation(loading ? .stop : .reload) == true
        doneButton.isHidden = !interactive
        setAccessibilityValue(page?.url?.absoluteString ?? address.absoluteString)
        header.needsLayout = true
        needsLayout = true
    }

    func validateInput() {}

    func cancelPositioning() {}

    func positionCapture(force: Bool) {}

    func focusRecovery() -> Bool { false }

    func focusRetry() {}

    override func layout() {
        super.layout()
        let width = bounds.width
        content.frame = bounds
        NoteMediaMotion.instant {
            ring.frame = bounds.insetBy(dx: -3, dy: -3)
        }
        header.frame = NSRect(x: 0, y: 0, width: width, height: Self.headerHeight)
        clip.frame = pageRect
        browser.frame = clip.bounds
        fallback.frame = pageRect
        refreshColors()
        onLayout?()
    }

    private func refreshColors() {
        NoteMediaMotion.instant {
            content.layer?.backgroundColor = NoteMediaStyle.cg(NoteMediaStyle.cardFill, in: self)
            content.layer?.borderColor = NoteMediaStyle.cg(NoteMediaStyle.cardStroke, in: self)
            ring.borderColor = NoteMediaStyle.cg(NoteTheme.accent, in: self)
        }
    }

    private func refreshRing(animated: Bool) {
        let target: Float = interactive || selected ? 1 : 0
        if animated { NoteAnimation.fade(ring, to: target, duration: 0.12) }
        else { NoteMediaMotion.instant { ring.opacity = target } }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsLayout = true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        if status == nil, pageRect.contains(local) {
            let admits = NSApp.currentEvent?.type == .scrollWheel ? scrollLatched : interactive
            if !admits { return nil }
        }
        return super.hitTest(point)
    }

    func takesPageInput(at windowPoint: NSPoint) -> Bool {
        guard !showsRecovery, !isHiddenOrHasHiddenAncestor, let page = browser.nativePage,
              !page.isClosed, page.embeddedOwnerValid else { return false }
        return pageRect.contains(convert(windowPoint, from: nil))
    }

    private func navigate(_ action: PCNativeNavigationAction) {
        guard let page = browser.nativePage, !page.isClosed, page.embeddedOwnerValid, page.canPerformNavigation(action) else { return }
        _ = page.performNavigation(action, inNewTab: false)
    }

    private func reloadOrStop() { navigate(browser.isLoading ? .stop : .reload) }

    private func openInTab() {
        guard let current = browser.nativePage?.url, browser.nativePage?.isClosed == false else { onOpen?(address); return }
        let unchanged = current.absoluteString == liveAddress.absoluteString || current.absoluteString == address.absoluteString
        onOpen?(unchanged ? address : current)
    }
}

@MainActor
private final class NoteEmbedPageClip: NSView {
    var exposesChildren: () -> Bool = { true }
    override var isFlipped: Bool { true }
    override func accessibilityChildren() -> [Any]? { exposesChildren() ? super.accessibilityChildren() : [] }
}

@MainActor
final class NoteEmbedFallbackView: NSView {
    var onOpen: (() -> Void)?
    var onRetry: (() -> Void)?
    private let address: URL
    private let card = NoteLinkCardView(style: .bookmark)
    private let statusLabel: NSTextField
    let retryChip = NoteChip("Retry", icon: .symbol("arrow.clockwise"))
    private var tracking: NSTrackingArea?

    init(address: URL) {
        self.address = address
        statusLabel = NoteMediaStyle.label("", font: NoteMediaStyle.smallFont, color: NoteTheme.secondaryInk, lines: 2)
        super.init(frame: .zero)
        wantsLayer = true
        statusLabel.alignment = .center
        card.onOpen = { [weak self] in self?.onOpen?() }
        retryChip.onPress = { [weak self] in self?.onRetry?() }
        retryChip.isHidden = true
        for view in [card, statusLabel, retryChip] as [NSView] { addSubview(view) }
        configure(preview: NoteLinkMetadata.shared.cached(address))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    func configure(preview: NoteLinkPreview?) {
        let failed = preview == nil && NoteLinkMetadata.shared.failure(for: address) != nil
        card.configure(url: address, preview: preview, loading: preview == nil && !failed)
        needsLayout = true
    }

    func configure(status: String?, retryTitle: String?) {
        statusLabel.stringValue = status ?? ""
        retryChip.chipTitle = retryTitle ?? "Retry"
        retryChip.isHidden = retryTitle == nil
        setAccessibilityLabel(status)
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let width = min(560, max(0, bounds.width - 32))
        let cardHeight = card.height(for: width)
        let chipSize = retryChip.isHidden ? .zero : retryChip.intrinsicContentSize
        let statusHeight: CGFloat = statusLabel.stringValue.isEmpty ? 0 : 34
        let total = cardHeight + (statusHeight > 0 ? 10 + statusHeight : 0) + (chipSize.height > 0 ? 8 + chipSize.height : 0)
        var y = max(12, ((bounds.height - total) / 2).rounded())
        card.frame = NSRect(x: ((bounds.width - width) / 2).rounded(), y: y, width: width, height: cardHeight)
        y = card.frame.maxY + 10
        statusLabel.frame = NSRect(x: card.frame.minX, y: y, width: width, height: statusHeight)
        y += statusHeight + 8
        retryChip.frame = NSRect(x: ((bounds.width - chipSize.width) / 2).rounded(), y: y, width: chipSize.width, height: chipSize.height)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseMoved(with event: NSEvent) {
        card.setHovered(card.frame.contains(convert(event.locationInWindow, from: nil))
                        && NoteFloatingPanel.allowsHover(for: self, at: event.locationInWindow))
    }

    override func mouseExited(with event: NSEvent) { card.setHovered(false) }
}

@MainActor
final class NoteEmbedResizeHandle: NSView {
    static let size = NSSize(width: 72, height: 14)
    var onDrag: ((CGFloat) -> Void)?
    var onEnd: ((CGFloat) -> Void)?
    var onStep: ((CGFloat) -> Void)?
    private let pill = CALayer()
    private var tracking: NSTrackingArea?
    private var start: NSPoint?
    private var hovered = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        pill.cornerRadius = 2.5
        pill.cornerCurve = .continuous
        pill.borderWidth = 1
        pill.opacity = 0
        layer?.addSublayer(pill)
        setAccessibilityElement(true)
        setAccessibilityRole(.splitter)
        setAccessibilityLabel("Resize live page")
        setAccessibilityHelp("Drag up or down to change the height.")
        addCursorUpdateArea()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    func setVisible(_ visible: Bool) {
        let target: Float = visible || hovered || start != nil ? 1 : 0
        guard pill.opacity != target else { return }
        NoteAnimation.fade(pill, to: target, duration: NoteAnimation.hoverDuration)
    }

    override func layout() {
        super.layout()
        NoteMediaMotion.instant {
            pill.frame = NSRect(x: (bounds.width - 36) / 2, y: (bounds.height - 5) / 2, width: 36, height: 5)
            pill.backgroundColor = NoteMediaStyle.cg(NoteMediaStyle.handleFill, in: self)
            pill.borderColor = NoteMediaStyle.cg(NoteMediaStyle.handleStroke, in: self)
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsLayout = true
    }

    override func cursorUpdate(with event: NSEvent) {
        if applyNoteCursor(.resizeUpDown, for: event) { return }
        super.cursorUpdate(with: event)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) {
        hovered = NoteFloatingPanel.allowsHover(for: self, at: event.locationInWindow)
        setVisible(hovered)
    }

    override func mouseExited(with event: NSEvent) { hovered = false; setVisible(false) }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        start = event.locationInWindow
        setVisible(true)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start else { return }
        onDrag?(start.y - event.locationInWindow.y)
    }

    override func mouseUp(with event: NSEvent) {
        guard let start else { return }
        self.start = nil
        onEnd?(start.y - event.locationInWindow.y)
        setVisible(false)
    }

    override func accessibilityPerformIncrement() -> Bool { onStep?(40); return true }
    override func accessibilityPerformDecrement() -> Bool { onStep?(-40); return true }
}
