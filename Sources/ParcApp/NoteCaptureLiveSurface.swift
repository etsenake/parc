import AppKit

@MainActor
protocol NoteEmbeddedPageInputSurface: EmbeddedPageSurface {
    var scrollLatched: Bool { get set }
    var selected: Bool { get set }
    func takesPageInput(at windowPoint: NSPoint) -> Bool
}

extension NoteEmbedSurface: NoteEmbeddedPageInputSurface {}

@MainActor
final class NoteCaptureLiveSurface: NSView, NoteEmbeddedPageInputSurface {
    let browser: PCBrowserView
    let address: URL
    let captureLayout: EaselCaptureLayout
    var positioningAllowed = true {
        didSet {
            guard positioningAllowed != oldValue else { return }
            if !positioningAllowed, positioner.isPositioning { cancelPositioning() }
            if positioningAllowed { needsLayout = true }
        }
    }
    var onLayout: (() -> Void)?
    var onRetry: (() -> Void)?
    var onNavigate: ((URL) -> Bool)?
    var onDone: (() -> Void)?
    var onOpen: ((URL) -> Void)?
    var onSnapshot: (() -> Void)?
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
    private let positioner: EmbeddedLiveCapturePositioner
    private let content = NoteCaptureLiveClip()
    private let ring = CALayer()
    private let header = EmbeddedPageHeader()
    private let clip = NoteCaptureLiveClip()
    private let cover = NSView()
    private let fallback: NoteEmbedFallbackView
    private let reloadButton = NoteToolbarButton(icon: .symbol("arrow.clockwise"), label: "Reload")
    private let backButton = NoteToolbarButton(icon: .symbol("chevron.left"), label: "Back")
    private let openButton = NoteToolbarButton(icon: .symbol("arrow.up.right.square"), label: "Open in a tab")
    private let doneButton = NoteToolbarButton(icon: .symbol("checkmark"), label: "Back to the note")
    private let snapshotChip = NoteChip(EaselWebItemChrome.backToSnapshotTitle, icon: .symbol("photo"))
    private var status: String?
    private var retryTitle = "Retry"

    init(address: URL, layout: EaselCaptureLayout, title: String, profilePath: String) {
        self.address = address
        captureLayout = layout
        positioner = EmbeddedLiveCapturePositioner(layout: layout)
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
        cover.wantsLayer = true
        cover.isHidden = true
        content.addSubview(cover)
        fallback.onOpen = { [weak self] in self?.openInTab() }
        fallback.onRetry = { [weak self] in self?.onRetry?() }
        content.addSubview(fallback)
        content.addSubview(header)
        backButton.onPress = { [weak self] in self?.navigate(.back) }
        reloadButton.onPress = { [weak self] in self?.navigate(self?.browser.isLoading == true ? .stop : .reload) }
        openButton.onPress = { [weak self] in self?.openInTab() }
        doneButton.onPress = { [weak self] in self?.onDone?() }
        doneButton.isHidden = true
        snapshotChip.onPress = { [weak self] in self?.onSnapshot?() }
        snapshotChip.setToolTip(EaselWebItemChrome.backToSnapshotHelp)
        header.buttons = [backButton, reloadButton, openButton, doneButton]
        header.action = snapshotChip
        header.setBadge("Live", help: EaselWebItemChrome.liveHelp, live: true)
        header.setPage(title: title, host: NoteCaptureText.displayHost(address))
        header.showFavicon(for: address, source: NoteLinkMetadata.shared.cached(address)?.iconURL)
        layer?.addSublayer(ring)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Live capture: " + NoteCaptureText.displayHost(address))
        NoteAnimation.observeReduceMotion(self) { [weak self] in
            guard let self else { return }
            NoteAnimation.settle(self.ring)
        }
        setStatus("Loading webpage…", retry: false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    var inputAvailable: Bool {
        interactive && (browser.nativePage?.isClosed != false || browser.nativePage?.embeddedOwnerValid == true)
    }

    var showsRecovery: Bool { status != nil || browser.nativePage?.rendererCrash != nil }

    var pageArea: (page: NSRect, visible: NSRect) { (convert(browser.bounds, from: browser), convert(clip.bounds, from: clip)) }

    var pageRect: NSRect {
        NSRect(x: 1, y: EmbeddedPageHeader.height, width: max(1, bounds.width - 2), height: max(1, bounds.height - EmbeddedPageHeader.height - 1))
    }

    func setStatus(_ text: String?, retry: Bool) {
        status = text
        fallback.configure(status: text.map { EmbeddedPageStatusText.friendly($0, document: "note") }, retryTitle: retry ? retryTitle : nil)
        fallback.isHidden = text == nil
        cover.isHidden = text == nil
        refresh()
        needsLayout = true
    }

    func setRetryTitle(_ title: String) {
        retryTitle = title
        if let status { fallback.configure(status: EmbeddedPageStatusText.friendly(status, document: "note"), retryTitle: title) }
    }

    func refresh() {
        let page = browser.nativePage
        let live = page?.isClosed == false && page?.embeddedOwnerValid == true
        let pageTitle = browser.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if live, !pageTitle.isEmpty { header.setPage(title: pageTitle, host: NoteCaptureText.displayHost(page?.url ?? address)) }
        backButton.isEnabled = live && page?.canPerformNavigation(.back) == true
        let loading = browser.isLoading
        reloadButton.content = .icon(.symbol(loading ? "xmark" : "arrow.clockwise"))
        reloadButton.setAccessibilityLabel(loading ? "Stop" : "Reload")
        reloadButton.setToolTip(loading ? "Stop" : "Reload")
        reloadButton.isEnabled = live && page?.canPerformNavigation(loading ? .stop : .reload) == true
        doneButton.isHidden = !interactive
        setAccessibilityValue(page?.url?.absoluteString ?? address.absoluteString)
        header.needsLayout = true
    }

    func validateInput() {}

    func cancelPositioning() { positioner.cancel() }

    func positionCapture(force: Bool) {
        guard positioningAllowed else { return }
        positioner.position(browser: browser, clip: clip, force: force) { [weak self] text, retry in
            self?.setStatus(text, retry: retry)
        }
    }

    func focusRecovery() -> Bool {
        guard interactive, let window else { return false }
        let retryVisible = !fallback.isHidden && !fallback.retryChip.isHidden
        return window.makeFirstResponder(retryVisible ? fallback.retryChip : doneButton)
    }

    func focusRetry() {
        if interactive, !fallback.isHidden, !fallback.retryChip.isHidden { window?.makeFirstResponder(fallback.retryChip) }
    }

    override func cancelOperation(_ sender: Any?) { if interactive { onDone?() } }

    override func layout() {
        super.layout()
        content.frame = bounds
        NoteMediaMotion.instant { ring.frame = bounds.insetBy(dx: -3, dy: -3) }
        header.frame = NSRect(x: 0, y: 0, width: bounds.width, height: EmbeddedPageHeader.height)
        let zoom = browser.nativePage?.liveCaptureZoomFactor ?? 1
        clip.frame = positioner.clipFrame(in: pageRect, zoom: zoom)
        browser.frame = NSRect(origin: .zero, size: positioner.pageSize(zoom: zoom))
        cover.frame = pageRect
        fallback.frame = pageRect
        refreshColors()
        positionCapture(force: false)
        onLayout?()
    }

    private func refreshColors() {
        NoteMediaMotion.instant {
            content.layer?.backgroundColor = NoteMediaStyle.cg(NoteMediaStyle.cardFill, in: self)
            content.layer?.borderColor = NoteMediaStyle.cg(NoteMediaStyle.cardStroke, in: self)
            cover.layer?.backgroundColor = NoteMediaStyle.cg(NoteMediaStyle.cardFill, in: self)
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
        return convert(clip.bounds, from: clip).contains(convert(windowPoint, from: nil))
    }

    private func navigate(_ action: PCNativeNavigationAction) {
        guard let page = browser.nativePage, !page.isClosed, page.embeddedOwnerValid, page.canPerformNavigation(action) else { return }
        _ = page.performNavigation(action, inNewTab: false)
    }

    private func openInTab() {
        let page = browser.nativePage
        onOpen?(page?.isClosed == false ? (page?.url ?? address) : address)
    }
}

@MainActor
private final class NoteCaptureLiveClip: NSView {
    var exposesChildren: () -> Bool = { true }
    override var isFlipped: Bool { true }
    override func accessibilityChildren() -> [Any]? { exposesChildren() ? super.accessibilityChildren() : [] }
}
