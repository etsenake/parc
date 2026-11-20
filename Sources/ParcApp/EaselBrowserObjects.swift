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
        guard let entry = surface(id: item.id, url: url, variant: Self.variant(item), make: {
            EaselBrowserSurface(profilePath: profilePath, captureLayout: layout)
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
        return view
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
    private let clip = EaselLiveCaptureClip()
    private var positioning: PCNativeLiveCapturePosition?
    private var positionGeneration: UInt64 = 0
    private var positionedWidth: CGFloat = 0
    private var positionedZoom: Double = 0
    var positioningAllowed = true {
        didSet {
            guard positioningAllowed != oldValue else { return }
            if !positioningAllowed, positioning != nil { cancelPositioning() }
            if positioningAllowed { needsLayout = true }
        }
    }
    var onSnapshot: (() -> Void)?
    private let snapshot = PointingHandButton(title: "Snapshot", target: nil, action: nil)
    var interactive = false { didSet { if oldValue != interactive { if !interactive { input?.cancel(restoreFocus: false) }; needsLayout = true } } }
    var onLayout: (() -> Void)?
    var onRetry: (() -> Void)?
    var onDone: (() -> Void)?
    var onNavigate: ((URL) -> Bool)?
    private var input: EaselWebInput?
    private var lastDraft = EaselWebNavigation.Draft()
    private let label = PointingHandButton(title: "Webpage", target: nil, action: nil)
    private let status = NSTextField(wrappingLabelWithString: "")
    private let cover = NSView()
    private let retry = PointingHandButton(title: "Retry", target: nil, action: nil)
    private let back = PointingHandButton(), forward = PointingHandButton(), reload = PointingHandButton(), done = PointingHandButton()
    private let security = PointingHandButton()
    var inputAvailable: Bool {
        interactive && (browser.nativePage?.isClosed != false || browser.nativePage?.embeddedOwnerValid == true)
    }
    override var isFlipped: Bool { true }
    init(profilePath: String, captureLayout: EaselCaptureLayout?) {
        self.captureLayout = captureLayout
        browser = PCBrowserView(frame: .zero, profilePath: profilePath)
        super.init(frame: .zero)
        wantsLayer = true; layer?.cornerRadius = 8; layer?.masksToBounds = true
        clip.wantsLayer = true; clip.layer?.masksToBounds = true
        addSubview(clip); clip.addSubview(browser)
        cover.wantsLayer = true; cover.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor; cover.isHidden = true
        addSubview(cover); addSubview(label); addSubview(status); addSubview(retry)
        snapshot.target = self; snapshot.action = #selector(showSnapshot); snapshot.isHidden = captureLayout == nil
        snapshot.toolTip = "Return to the original captured image"; addSubview(snapshot)
        label.font = .systemFont(ofSize: 11); label.lineBreakMode = .byTruncatingMiddle
        label.isBordered = false; label.alignment = .left; label.target = self; label.action = #selector(editAddress)
        label.setAccessibilityLabel("Edit webpage address or search")
        status.font = .systemFont(ofSize: 12); status.alignment = .center; status.textColor = .secondaryLabelColor
        for (button, title, symbol, selector) in [(back,"Back","chevron.left",#selector(goBack)),(forward,"Forward","chevron.right",#selector(goForward)),(reload,"Reload","arrow.clockwise",#selector(reloadOrStop)),(done,"Return to Easel","checkmark",#selector(finish)),(security,"Site information","lock",#selector(siteInfo))] {
            button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
            button.bezelStyle = .texturedRounded; button.toolTip = title; button.setAccessibilityLabel(title)
            button.target = self; button.action = selector; addSubview(button)
        }
        retry.target = self; retry.action = #selector(retryPage)
        setAccessibilityElement(false)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() {
        effectiveAppearance.performAsCurrentDrawingAppearance { layer?.backgroundColor = EaselAppearance.surface.cgColor }
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
    override func layout() {
        super.layout()
        clip.frame = NSRect(x: 0, y: 32, width: bounds.width, height: max(1, bounds.height - 32))
        if let captureLayout {
            let zoom = browser.nativePage?.liveCaptureZoomFactor ?? 1
            let width = min(bounds.width, max(1, bounds.height - 32) * captureLayout.region.width / captureLayout.region.height,
                            captureLayout.viewport.x * zoom, captureLayout.viewport.y * zoom * captureLayout.region.width / captureLayout.region.height)
            let height = width * captureLayout.region.height / captureLayout.region.width
            clip.frame = NSRect(x: (bounds.width - width) / 2, y: 32 + (max(1, bounds.height - 32) - height) / 2, width: width, height: height)
            browser.frame = NSRect(x: 0, y: 0, width: captureLayout.viewport.x * zoom, height: captureLayout.viewport.y * zoom)
            clip.isHidden = false
            positionCapture()
        } else { browser.frame = clip.bounds }
        back.frame = NSRect(x: 4, y: 3, width: 25, height: 25)
        forward.frame = NSRect(x: 30, y: 3, width: 25, height: 25)
        reload.frame = NSRect(x: 56, y: 3, width: 25, height: 25)
        done.frame = NSRect(x: max(82, bounds.width - 30), y: 3, width: 25, height: 25)
        security.frame = NSRect(x: 82, y: 3, width: 25, height: 25)
        label.frame = NSRect(x: 140, y: 9, width: max(0, bounds.width - 178), height: 17)
        status.frame = NSRect(x: 14, y: max(38, bounds.midY - 25), width: max(0, bounds.width - 28), height: 48)
        retry.frame = NSRect(x: max(0, bounds.midX - 40), y: min(bounds.maxY - 32, status.frame.maxY), width: 80, height: 26)
        cover.frame = clip.frame
        snapshot.frame = NSRect(x: 110, y: 3, width: 80, height: 25)
        if captureLayout != nil { label.isHidden = true; back.isHidden = true; forward.isHidden = true }
        onLayout?()
    }
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard interactive else { return nil }
        return super.hitTest(point)
    }
    var pageArea: (page: NSRect, visible: NSRect) { (convert(browser.bounds, from: browser), clip.frame) }
    func setRetryTitle(_ title: String) { retry.title = title }
    func focusRetry() { if interactive && !retry.isHidden { window?.makeFirstResponder(retry) } }
    var showsRecovery: Bool { !status.isHidden || browser.nativePage?.rendererCrash != nil }
    func focusRecovery() -> Bool {
        guard interactive, let window else { return false }
        return window.makeFirstResponder(retry.isHidden ? done : retry)
    }
    override func cancelOperation(_ sender: Any?) {
        if input != nil { input?.cancel(); return }
        if interactive { onDone?() }
    }
    override func accessibilityChildren() -> [Any]? { inputAvailable ? super.accessibilityChildren() : [] }
    func setStatus(_ text: String?, retry retryVisible: Bool = false) {
        status.stringValue = text ?? ""; status.isHidden = text == nil; retry.isHidden = !retryVisible
        cover.isHidden = captureLayout == nil || text == nil; needsLayout = true
    }
    func refresh() {
        input?.validate()
        let page = browser.nativePage
        let interactive = inputAvailable
        label.title = page?.url?.host ?? "Webpage"
        label.isEnabled = interactive && page?.canPerformNavigation(.reload) == true
        label.toolTip = page?.url?.absoluteString
        back.isEnabled = interactive && page?.canPerformNavigation(.back) == true
        forward.isEnabled = interactive && page?.canPerformNavigation(.forward) == true
        let action: PCNativeNavigationAction = browser.isLoading ? .stop : .reload
        reload.isEnabled = interactive && page?.canPerformNavigation(action) == true
        reload.image = NSImage(systemSymbolName: browser.isLoading ? "xmark" : "arrow.clockwise", accessibilityDescription: browser.isLoading ? "Stop" : "Reload")
        done.isEnabled = interactive; retry.isEnabled = interactive; snapshot.isEnabled = interactive
        setAccessibilityHidden(!interactive)
        security.isEnabled = interactive && browser.canShowSiteInfo
    }
    func validateInput() { input?.validate() }
    @objc private func editAddress() {
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
        if !editor.show(from: label) { editor.cancel(restoreFocus: false) }
    }
    func cancelPositioning() {
        positionGeneration &+= 1; positioning?.cancel(); positioning = nil
        positionedWidth = 0; positionedZoom = 0
    }
    func positionCapture(force: Bool = false) {
        guard positioningAllowed, let layout = captureLayout, let page = browser.nativePage, !page.isClosed,
              page.embeddedOwnerValid, !browser.isLoading, window != nil else { return }
        let zoom = page.liveCaptureZoomFactor
        let width = min(clip.bounds.width, clip.bounds.height * layout.region.width / layout.region.height)
        guard width > 0, zoom.isFinite, zoom > 0,
              force || positionedWidth != width || positionedZoom != zoom else { return }
        cancelPositioning(); positionedWidth = width; positionedZoom = zoom
        let generation = positionGeneration
        browser.frame = NSRect(x: 0, y: 0, width: layout.viewport.x * zoom, height: layout.viewport.y * zoom)
        setStatus("Positioning live capture…")
        positioning = page.positionLiveCapture(NSRect(x: layout.region.x, y: layout.region.y,
            width: layout.region.width, height: layout.region.height),
            scrollOffset: NSPoint(x: layout.scroll.x, y: layout.scroll.y), displayWidth: width) { [weak self, weak page] success in
                MainActor.assumeIsolated {
                    guard let self, let page, self.positionGeneration == generation,
                          self.browser.nativePage === page, page.embeddedOwnerValid else { return }
                    self.positioning = nil
                    self.setStatus(success ? nil : "This page could not align with the captured region.", retry: !success)
                }
            }
        if positioning == nil { setStatus("Live capture is unavailable for this page.", retry: true) }
    }
    @objc private func showSnapshot() { onSnapshot?() }
    @objc private func goBack() { _ = browser.nativePage?.performNavigation(.back, inNewTab: false) }
    @objc private func goForward() { _ = browser.nativePage?.performNavigation(.forward, inNewTab: false) }
    @objc private func reloadOrStop() { _ = browser.nativePage?.performNavigation(browser.isLoading ? .stop : .reload, inNewTab: false) }
    @objc private func siteInfo() { _ = browser.showSiteInfo(from: security) }
    @objc private func finish() { onDone?() }
    @objc private func retryPage() { onRetry?() }
}

@MainActor
private final class EaselLiveCaptureClip: NSView {
    override var isFlipped: Bool { true }
}
