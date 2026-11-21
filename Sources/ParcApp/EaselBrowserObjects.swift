import AppKit
import Combine

@MainActor
final class EaselBrowserObjects: EmbeddedPagePool, EaselBrowserObjectHosting {
    private let session: EaselSession
    private var canvas: EaselCanvasView? { hostView as? EaselCanvasView }
    private var replacementObserver: UUID?
    private var documentObserver: AnyCancellable?

    init(session: EaselSession, canvas: EaselCanvasView, binding: PCNativeBrowserWindow,
         profilePath: String, validOwner: @escaping () -> Bool,
         activeOwner: @escaping () -> Bool, selectionChanged: @escaping () -> Void,
         metadataChanged: @escaping () -> Void) {
        self.session = session
        super.init(owner: session, hostView: canvas, binding: binding, profilePath: profilePath, validOwner: validOwner,
                   activeOwner: activeOwner, selectionChanged: selectionChanged, metadataChanged: metadataChanged)
        replacementObserver = session.observeReplacement { [weak self] next in
            guard let self else { return true }
            return self.entries.allSatisfy { id, entry in
                guard entry.page?.isClosed == false || entry.request?.isPending == true else { return true }
                return next?.items.contains { item in
                    guard item.id == id, item.ownsEmbeddedPage, Self.variant(item) == entry.variant, let url = item.url else { return false }
                    return url == entry.originalURL || (entry.page?.isClosed == false && entry.request == nil
                        && self.session.isRecordingBrowserNavigation(id, from: entry.originalURL, to: url))
                } == true
            }
        }
        documentObserver = session.$document.sink { [weak self] next in
            guard let self else { return }
            for (id, entry) in self.entries {
                if let item = next.items.first(where: { $0.id == id && $0.kind == .browser }), let url = item.url,
                   self.session.isRecordingBrowserNavigation(id, from: entry.originalURL, to: url) {
                    entry.originalURL = url
                }
            }
            for (id, entry) in Array(self.entries) where
                !next.items.contains(where: { $0.id == id && Self.matches($0, entry) })
                && entry.page?.isClosed != false {
                entry.cancelRequest()
                if entry.request == nil { entry.surface.removeFromSuperview(); self.entries.removeValue(forKey: id) }
            }
            self.releaseIfIdle()
        }
        canvas.pageObjects = self
    }

    fileprivate static func variant(_ item: EaselItem) -> EmbeddedPageFingerprint? { item.captureLayout.map(EmbeddedPageFingerprint.init) }
    fileprivate static func matches(_ item: EaselItem, _ entry: EmbeddedPageEntry) -> Bool {
        item.ownsEmbeddedPage && item.url == entry.originalURL && variant(item) == entry.variant
    }

    override func revealEntry(_ id: UUID) { canvas?.selectBrowserObject(id) }

    func exportSnapshots(within deadline: TimeInterval, _ completion: @escaping ([UUID: EaselPageSnapshot]) -> Void) {
        let collection = SnapshotCollection(completion)
        for (id, entry) in entries where !disposed && session.document.items.contains(where: { $0.id == id && Self.matches($0, entry) }) {
            let area = entry.surface.pageArea
            guard let page = entry.page, !page.isClosed, page.embeddedOwnerValid, !area.page.isEmpty, !area.visible.isEmpty,
                  page.responds(to: #selector(PCNativePage.snapshotEmbeddedPage(completion:))) else { continue }
            collection.request()
            let started = page.snapshotEmbeddedPage { result in
                MainActor.assumeIsolated {
                    collection.receive(id, result.image.map { EaselPageSnapshot(image: $0, pageFrame: area.page, visibleFrame: area.visible) })
                }
            }
            if !started { collection.receive(id, nil) }
        }
        collection.requested()
        DispatchQueue.main.asyncAfter(deadline: .now() + deadline) { MainActor.assumeIsolated { collection.expire() } }
    }
    @MainActor private final class SnapshotCollection {
        private var snapshots: [UUID: EaselPageSnapshot] = [:]
        private var pending = 0, requesting = true, delivered = false
        private let completion: ([UUID: EaselPageSnapshot]) -> Void
        init(_ completion: @escaping ([UUID: EaselPageSnapshot]) -> Void) { self.completion = completion }
        func request() { pending += 1 }
        func receive(_ id: UUID, _ snapshot: EaselPageSnapshot?) {
            guard !delivered else { return }
            if let snapshot { snapshots[id] = snapshot }
            pending -= 1; finish()
        }
        func requested() { requesting = false; finish() }
        func expire() { requesting = false; pending = 0; finish() }
        private func finish() {
            guard !delivered, !requesting, pending == 0 else { return }
            delivered = true; completion(snapshots)
        }
    }

    func surface(for item: EaselItem) -> NSView? {
        guard item.ownsEmbeddedPage, let url = item.url else { return nil }
        let profilePath = self.profilePath, layout = item.captureLayout
        let address = URL(string: url) ?? URL(string: "about:blank")!
        guard let entry = surface(id: item.id, url: url, variant: Self.variant(item), make: {
            EaselBrowserSurface(profilePath: profilePath, address: address, captureLayout: layout)
        }) else { return nil }
        guard entry.surface.onDone == nil, let view = entry.surface as? EaselBrowserSurface else { return entry.surface }
        view.onDone = { [weak self, weak entry] in
            guard let self, let entry, self.entries[item.id] === entry,
                  self.accessibilitySurface(for: item.id) === entry.surface, let canvas = self.canvas,
                  let window = canvas.window, window.attachedSheet == nil else { return }
            canvas.cancelOperation(nil); window.makeFirstResponder(canvas)
            canvas.layoutSubtreeIfNeeded()
        }
        view.onSnapshot = { [weak self] in self?.canvas?.setLiveCapture(item.id, enabled: false) }
        view.onOpen = { [weak self] url in self?.canvas?.onOpenURL?(url) }
        view.onFramingFailed = { [weak self] in
            self?.framingFailures.insert(item.id)
            DispatchQueue.main.async { [weak self] in self?.canvas?.setLiveCapture(item.id, enabled: false) }
        }
        return view
    }

    private var snapshotChrome: EaselSnapshotHeader?
    private var framingFailures: Set<UUID> = []
    func snapshotHeader(for item: EaselItem) -> NSView? {
        guard EaselWebItemChrome.isSnapshot(item), let raw = item.url, let address = URL(string: raw) else { return nil }
        let header = snapshotChrome ?? EaselSnapshotHeader()
        snapshotChrome = header
        let id = item.id
        header.onMakeLive = { [weak self] in
            self?.framingFailures.remove(id)
            self?.canvas?.setLiveCapture(id, enabled: true)
        }
        header.onOpen = { [weak self] in self?.canvas?.onOpenURL?(address) }
        header.configure(item, address: address, framingFailed: framingFailures.contains(id))
        return header
    }

    func synchronize(items: [EaselItem], selection: Set<UUID>, interacting: Bool) {
        let current = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        synchronize(wanted: { id, entry in current[id].map { Self.matches($0, entry) } == true },
                    selection: selection.count == 1 ? selection.first : nil, interacting: interacting)
    }

    func prepareReplacement(_ next: EaselDocument, valid: @escaping () -> Bool, completion: @escaping (Bool) -> Void) {
        let original = session.document
        guard valid(), !gate.isTransferring, !gate.isRetiring else { completion(false); return }
        let owners = Self.liveOwners.compactMap { $0 as? EaselBrowserObjects }.filter { $0.session === session }
        let targets = owners.flatMap { owner in owner.entries.compactMap { id, entry -> (EmbeddedPagePool, EmbeddedPageEntry)? in
            next.items.contains { $0.id == id && Self.matches($0, entry) } ? nil : (owner, entry)
        } }
        EmbeddedPagePool.requestRetirement(of: targets, owners: owners, valid: { [weak self] in
            guard let self else { return false }
            return valid() && self.session.document == original
        }, completion: completion)
    }

    override func didDispose() {
        if let replacementObserver { session.removeReplacementObserver(replacementObserver); self.replacementObserver = nil }
        documentObserver = nil
    }
}

extension EaselSession: EmbeddedPageOwner {
    var embeddedPagesOpen: Bool { !isClosed && !isDeleted }
    func embeddedPage(_ id: UUID, wants url: String, variant: EmbeddedPageFingerprint?) -> Bool {
        document.items.contains { $0.id == id && $0.ownsEmbeddedPage && $0.url == url && $0.captureLayout.map(EmbeddedPageFingerprint.init) == variant }
    }
    func embeddedPageFingerprint(for ids: Set<UUID>) -> EmbeddedPageFingerprint {
        EmbeddedPageFingerprint(Dictionary(uniqueKeysWithValues: document.items.filter { ids.contains($0.id) }.map { ($0.id, $0) }))
    }
    func recordEmbeddedPageNavigation(_ url: URL, for id: UUID, expectedURL: String) throws {
        do { _ = try recordBrowserNavigation(url, itemID: id, expectedURL: expectedURL) }
        catch EaselStoreError.browserInUse { }
    }
}

@MainActor
private final class EaselBrowserSurface: NSView, EmbeddedPageSurface {
    let browser: PCBrowserView
    private let captureLayout: EaselCaptureLayout?
    private let address: URL
    private let clip = EaselLiveCaptureClip()
    private var positioning: PCNativeLiveCapturePosition?
    private var positionGeneration: UInt64 = 0
    private var positionedWidth: CGFloat = 0
    private var positionedZoom: Double = 0
    var positioningAllowed = true {
        didSet {
            guard positioningAllowed != oldValue else { return }
            if !positioningAllowed, positioning != nil { stopPositioning() }
            if positioningAllowed { needsLayout = true }
        }
    }
    var onSnapshot: (() -> Void)?
    var onOpen: ((URL) -> Void)?
    var onFramingFailed: (() -> Void)?
    private var framing = EaselLiveFraming()
    var interactive = false {
        didSet {
            guard oldValue != interactive else { return }
            if !interactive { input?.cancel(restoreFocus: false) }
            if !interactive && framing.revealsPage { positionCapture(force: true) }
            refresh(); needsLayout = true
        }
    }
    var onLayout: (() -> Void)?
    var onRetry: (() -> Void)?
    var onDone: (() -> Void)?
    var onNavigate: ((URL) -> Bool)?
    private var input: EaselWebInput?
    private var lastDraft = EaselWebNavigation.Draft()
    private let header = EmbeddedPageHeader()
    private let cover = NSView()
    private let fallback: NoteEmbedFallbackView
    private var status: String?
    private var retryTitle = "Retry"
    private let backButton = NoteToolbarButton(icon: .symbol("chevron.left"), label: "Back")
    private let reloadButton = NoteToolbarButton(icon: .symbol("arrow.clockwise"), label: "Reload")
    private let openButton = NoteToolbarButton(icon: .symbol("arrow.up.right.square"), label: "Open in a tab")
    private let moreButton = NoteToolbarButton(icon: .symbol("ellipsis"), label: "More")
    private let doneButton = NoteToolbarButton(icon: .symbol("checkmark"), label: "Back to the Easel")
    private let snapshotChip = NoteChip(EaselWebItemChrome.backToSnapshotTitle, icon: .symbol("photo"))
    var inputAvailable: Bool {
        interactive && (browser.nativePage?.isClosed != false || browser.nativePage?.embeddedOwnerValid == true)
    }
    override var isFlipped: Bool { true }
    init(profilePath: String, address: URL, captureLayout: EaselCaptureLayout?) {
        self.captureLayout = captureLayout
        self.address = address
        browser = PCBrowserView(frame: .zero, profilePath: profilePath)
        fallback = NoteEmbedFallbackView(address: address)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = NoteMediaStyle.cardRadius; layer?.cornerCurve = .continuous
        layer?.borderWidth = 1; layer?.masksToBounds = true
        clip.wantsLayer = true; clip.layer?.masksToBounds = true
        addSubview(clip); clip.addSubview(browser)
        cover.wantsLayer = true; cover.isHidden = true
        fallback.isHidden = true
        fallback.onOpen = { [weak self] in self?.openInTab() }
        fallback.onRetry = { [weak self] in self?.onRetry?() }
        fallback.retryChip.acceptsKeyboardFocus = true
        addSubview(cover); addSubview(fallback); addSubview(header)
        backButton.onPress = { [weak self] in self?.navigate(.back) }
        reloadButton.onPress = { [weak self] in self?.reloadOrStop() }
        openButton.onPress = { [weak self] in self?.openInTab() }
        moreButton.onPress = { [weak self] in self?.showMore() }
        doneButton.onPress = { [weak self] in self?.onDone?() }
        doneButton.acceptsKeyboardFocus = true
        snapshotChip.onPress = { [weak self] in self?.onSnapshot?() }
        snapshotChip.setToolTip(EaselWebItemChrome.backToSnapshotHelp)
        if captureLayout != nil {
            header.buttons = [reloadButton, openButton, moreButton, doneButton]
            header.action = snapshotChip
            header.setBadge("Live", help: EaselWebItemChrome.liveHelp, live: true)
        } else {
            header.buttons = [backButton, reloadButton, openButton, moreButton, doneButton]
            header.onTitle = { [weak self] in self?.editAddress() }
        }
        header.loadPreview(for: address) { [weak self] preview in
            if let preview { self?.fallback.configure(preview: preview) }
            self?.refresh()
        }
        setAccessibilityElement(false)
        refresh()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() {
        layer?.backgroundColor = NoteMediaStyle.cg(NoteTheme.panelFill, in: self)
        layer?.borderColor = NoteMediaStyle.cg(NoteTheme.panelStroke, in: self)
        cover.layer?.backgroundColor = NoteMediaStyle.cg(NoteTheme.menuFill, in: self)
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
    private var headerHeight: CGFloat { EmbeddedPageHeader.height }
    private var pageRect: NSRect { NSRect(x: 0, y: headerHeight, width: bounds.width, height: max(1, bounds.height - headerHeight)) }
    override func layout() {
        super.layout()
        header.frame = NSRect(x: 0, y: 0, width: bounds.width, height: headerHeight)
        clip.frame = pageRect
        if let captureLayout {
            let zoom = browser.nativePage?.liveCaptureZoomFactor ?? 1
            let size = EaselCaptureGeometry.displaySize(captureLayout, availableWidth: bounds.width,
                                                        availableHeight: pageRect.height, pageZoom: zoom)
            let width = size.width, height = size.height
            clip.frame = NSRect(x: (bounds.width - width) / 2, y: headerHeight + (pageRect.height - height) / 2, width: width, height: height)
            browser.frame = NSRect(x: 0, y: 0, width: captureLayout.viewport.x * zoom, height: captureLayout.viewport.y * zoom)
            clip.isHidden = false
            positionCapture()
        } else { browser.frame = clip.bounds }
        cover.frame = pageRect
        fallback.frame = pageRect
        onLayout?()
    }
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard interactive else { return nil }
        if NSApp.currentEvent?.type == .scrollWheel,
           !EaselLiveFraming.admitsPageScrolling(framesCapture: captureLayout != nil),
           pageRect.contains(convert(point, from: superview)) { return nil }
        return super.hitTest(point)
    }
    var pageArea: (page: NSRect, visible: NSRect) { (convert(browser.bounds, from: browser), clip.frame) }
    func setRetryTitle(_ title: String) {
        retryTitle = title
        if let status { fallback.configure(status: Self.friendly(status), retryTitle: fallback.retryChip.isHidden ? nil : title) }
    }
    func focusRetry() { if interactive && !fallback.isHidden && !fallback.retryChip.isHidden { window?.makeFirstResponder(fallback.retryChip) } }
    var showsRecovery: Bool { status != nil || browser.nativePage?.rendererCrash != nil }
    func focusRecovery() -> Bool {
        guard interactive, let window else { return false }
        let retryVisible = !fallback.isHidden && !fallback.retryChip.isHidden
        return window.makeFirstResponder(retryVisible ? fallback.retryChip : doneButton)
    }
    override func cancelOperation(_ sender: Any?) {
        if input != nil { input?.cancel(); return }
        if interactive { onDone?() }
    }
    override func accessibilityChildren() -> [Any]? { inputAvailable ? super.accessibilityChildren() : [] }
    private static func friendly(_ text: String) -> String { EmbeddedPageStatusText.friendly(text, document: "Easel") }
    func setStatus(_ text: String?, retry retryVisible: Bool = false) {
        if text == nil, captureLayout != nil, !framing.revealsPage { showLiningUp(); return }
        status = text
        fallback.configure(status: text.map(Self.friendly), retryTitle: retryVisible ? retryTitle : nil)
        fallback.isHidden = text == nil; cover.isHidden = text == nil
        needsLayout = true
    }
    func refresh() {
        input?.validate()
        let page = browser.nativePage
        let interactive = inputAvailable
        let live = page?.isClosed == false && page?.embeddedOwnerValid == true
        let preview = NoteLinkMetadata.shared.cached(address)
        let current = live ? (page?.url ?? address) : address
        let pageTitle = browser.title.trimmingCharacters(in: .whitespacesAndNewlines)
        header.setPage(title: live && !pageTitle.isEmpty ? pageTitle : (preview?.title ?? EaselWebItemChrome.displayHost(address)),
                       host: EaselWebItemChrome.displayHost(current))
        header.toolTip = captureLayout == nil ? "Edit webpage address or search" : nil
        header.onTitle = captureLayout == nil && interactive ? { [weak self] in self?.editAddress() } : nil
        backButton.isEnabled = interactive && page?.canPerformNavigation(.back) == true
        let loading = browser.isLoading
        reloadButton.content = .icon(.symbol(loading ? "xmark" : "arrow.clockwise"))
        reloadButton.setAccessibilityLabel(loading ? "Stop" : "Reload")
        reloadButton.setToolTip(loading ? "Stop" : "Reload")
        reloadButton.isEnabled = interactive && page?.canPerformNavigation(loading ? .stop : .reload) == true
        openButton.isEnabled = true
        moreButton.isEnabled = interactive
        snapshotChip.isEnabled = interactive
        doneButton.isHidden = !interactive
        fallback.retryChip.isEnabled = interactive
        setAccessibilityHidden(!interactive)
        header.needsLayout = true
        window?.invalidateCursorRects(for: header)
    }
    func validateInput() { input?.validate() }
    private func editAddress() {
        guard interactive, let page = browser.nativePage, page.embeddedOwnerValid else { return }
        input?.cancel()
        var draft = lastDraft
        if draft.mode == .address { draft.text = page.url?.absoluteString ?? "" }
        let editor = EaselWebInput(draft: draft, validOwner: { [weak self, weak page] in
            guard let self, let page else { return false }
            return self.interactive && self.browser.nativePage === page && !page.isClosed && page.embeddedOwnerValid
        }, submit: { [weak self] url, draft in
            guard let self, self.onNavigate?(url) == true else { return false }
            self.lastDraft = draft; return true
        })
        input = editor
        editor.onClose = { [weak self, weak editor] in if self?.input === editor { self?.input = nil } }
        if !editor.show(from: header) { editor.cancel(restoreFocus: false) }
    }
    private func showMore() {
        guard interactive else { return }
        let menu = NSMenu()
        menu.autoenablesItems = false
        func add(_ title: String, enabled: Bool, _ action: Selector) {
            let row = NSMenuItem(title: title, action: action, keyEquivalent: "")
            row.target = self; row.isEnabled = enabled; menu.addItem(row)
        }
        let page = browser.nativePage
        if captureLayout == nil {
            add("Forward", enabled: page?.canPerformNavigation(.forward) == true, #selector(goForward))
            add("Edit Address or Search…", enabled: page?.canPerformNavigation(.reload) == true, #selector(editAddressFromMenu))
        } else {
            add("Back to Snapshot", enabled: true, #selector(showSnapshot))
        }
        add("Open in a Tab", enabled: true, #selector(openFromMenu))
        menu.addItem(.separator())
        add("Site Information", enabled: browser.canShowSiteInfo, #selector(siteInfo))
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: moreButton.bounds.maxY + 4), in: moreButton)
    }
    private func navigate(_ action: PCNativeNavigationAction) {
        guard let page = browser.nativePage, !page.isClosed, page.embeddedOwnerValid, page.canPerformNavigation(action) else { return }
        _ = page.performNavigation(action, inNewTab: false)
    }
    private func reloadOrStop() { navigate(browser.isLoading ? .stop : .reload) }
    private func openInTab() {
        let page = browser.nativePage
        onOpen?(page?.isClosed == false ? (page?.url ?? address) : address)
    }
    func cancelPositioning() {
        stopPositioning()
        guard captureLayout != nil else { return }
        framing.pageChanged()
        if status == nil || status == "Positioning live capture…" { showLiningUp() }
    }
    private func stopPositioning() {
        positionGeneration &+= 1; positioning?.cancel(); positioning = nil
        positionedWidth = 0; positionedZoom = 0
    }
    private func showLiningUp() {
        status = "Positioning live capture…"
        fallback.configure(status: Self.friendly("Positioning live capture…"), retryTitle: nil)
        fallback.isHidden = false; cover.isHidden = false
        needsLayout = true
    }
    private func framed(_ success: Bool) {
        switch framing.positioned(success: success, pageStillLoading: browser.isLoading) {
        case .reveal: setStatus(nil, retry: false)
        case .keepWaiting: showLiningUp()
        case .backToSnapshot:
            setStatus("This page could not align with the captured region.", retry: false)
            onFramingFailed?()
        }
    }
    func positionCapture(force: Bool = false) {
        guard positioningAllowed, let layout = captureLayout, let page = browser.nativePage, !page.isClosed,
              page.embeddedOwnerValid, window != nil else { return }
        let zoom = page.liveCaptureZoomFactor
        let width = min(clip.bounds.width, clip.bounds.height * layout.region.width / layout.region.height)
        guard width > 0, zoom.isFinite, zoom > 0,
              force || positionedWidth != width || positionedZoom != zoom else { return }
        stopPositioning(); positionedWidth = width; positionedZoom = zoom
        let generation = positionGeneration
        browser.frame = NSRect(x: 0, y: 0, width: layout.viewport.x * zoom, height: layout.viewport.y * zoom)
        if !framing.revealsPage { showLiningUp() }
        positioning = page.positionLiveCapture(NSRect(x: layout.region.x, y: layout.region.y,
            width: layout.region.width, height: layout.region.height),
            scrollOffset: NSPoint(x: layout.scroll.x, y: layout.scroll.y), displayWidth: width) { [weak self, weak page] success in
                MainActor.assumeIsolated {
                    guard let self, let page, self.positionGeneration == generation,
                          self.browser.nativePage === page, page.embeddedOwnerValid else { return }
                    self.positioning = nil
                    self.framed(success)
                }
            }
        if positioning == nil { framed(false) }
    }
    @objc private func showSnapshot() { onSnapshot?() }
    @objc private func goForward() { navigate(.forward) }
    @objc private func editAddressFromMenu() { editAddress() }
    @objc private func openFromMenu() { openInTab() }
    @objc private func siteInfo() { _ = browser.showSiteInfo(from: moreButton) }
}

@MainActor
private final class EaselSnapshotHeader: NSView {
    var onMakeLive: (() -> Void)?
    var onOpen: (() -> Void)?
    private let header = EmbeddedPageHeader()
    private let makeLive = NoteChip(EaselWebItemChrome.makeLiveTitle, icon: .symbol("dot.radiowaves.left.and.right"), style: .filled)
    private let openButton = NoteToolbarButton(icon: .symbol("arrow.up.right.square"), label: "Open in a tab")
    private var address: URL?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = NoteMediaStyle.cardRadius
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 1
        layer?.shadowOpacity = 0.12
        layer?.shadowRadius = 6
        layer?.shadowOffset = CGSize(width: 0, height: -2)
        header.showsRule = false
        makeLive.onPress = { [weak self] in self?.onMakeLive?() }
        makeLive.setToolTip(EaselWebItemChrome.makeLiveHelp)
        openButton.onPress = { [weak self] in self?.onOpen?() }
        header.buttons = [openButton]
        addSubview(header)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    func configure(_ item: EaselItem, address: URL, framingFailed: Bool) {
        let canGoLive = EaselWebItemChrome.canMakeLive(item)
        header.setPage(title: EaselWebItemChrome.title(for: item), host: EaselWebItemChrome.displayHost(address))
        if framingFailed && canGoLive {
            header.setBadge(EaselLiveFraming.failureBadge, help: EaselLiveFraming.failureHelp, live: false)
        } else {
            header.setBadge(EaselWebItemChrome.badge(for: item), help: EaselWebItemChrome.badgeHelp(for: item), live: false)
        }
        header.action = canGoLive ? makeLive : nil
        setAccessibilityLabel("Captured page: " + EaselWebItemChrome.title(for: item))
        if self.address != address {
            self.address = address
            header.showFavicon(for: address, source: NoteLinkMetadata.shared.cached(address)?.iconURL)
        }
        needsLayout = true
    }

    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() {
        layer?.backgroundColor = NoteMediaStyle.cg(NoteTheme.menuFill, in: self)
        layer?.borderColor = NoteMediaStyle.cg(NoteTheme.panelStroke, in: self)
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
    override func layout() {
        super.layout()
        header.frame = bounds
        header.needsLayout = true
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {}
}

@MainActor
private final class EaselLiveCaptureClip: NSView {
    override var isFlipped: Bool { true }
}
