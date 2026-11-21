import AppKit
import Combine
import ParcCore
import ParcEngine

@MainActor
final class EaselBrowserObjects: EmbeddedPagePool, EaselBrowserObjectHosting {
    let session: EaselSession
    private var canvas: EaselCanvasView? { hostView as? EaselCanvasView }
    private var replacementObserver: UUID?
    private var documentObserver: AnyCancellable?
    var loadsLinkPreviews = true
    var scheduleSnapshotDeadline: (TimeInterval, @escaping () -> Void) -> Void = { delay, work in
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { work() }
    }

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
        scheduleSnapshotDeadline(deadline) { MainActor.assumeIsolated { collection.expire() } }
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
            NoteEmbedSurface(address: address, profilePath: profilePath, host: .easel, captureLayout: layout,
                             loadsLinkPreview: loadsLinkPreviews)
        }) else { return nil }
        guard entry.surface.onDone == nil, let view = entry.surface as? NoteEmbedSurface else { return entry.surface }
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
        let current = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
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
        EmbeddedPageFingerprint(Dictionary(document.items.filter { ids.contains($0.id) }.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last }))
    }
    func recordEmbeddedPageNavigation(_ url: URL, for id: UUID, expectedURL: String) throws {
        do { _ = try recordBrowserNavigation(url, itemID: id, expectedURL: expectedURL) }
        catch EaselStoreError.browserInUse { }
    }
}

@MainActor
final class EaselSnapshotHeader: NSView {
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

extension EaselScrollContainer {
    init(_ native: PCNativeCaptureScrollContainer) {
        self.init(anchorID: native.anchorID, path: native.path, scroll: EaselPoint(x: native.scrollOffset.x, y: native.scrollOffset.y),
                  frame: EaselRect(x: native.frame.minX, y: native.frame.minY, width: native.frame.width, height: native.frame.height))
    }
}

extension EaselCaptureLayout {
    @MainActor var nativeScrollContainers: [PCNativeCaptureScrollContainer] {
        (scrollContainers ?? []).compactMap {
            PCNativeCaptureScrollContainer(anchorID: $0.anchorID, path: $0.path, scrollOffset: NSPoint(x: $0.scroll.x, y: $0.scroll.y),
                                           frame: NSRect(x: $0.frame.x, y: $0.frame.y, width: $0.frame.width, height: $0.frame.height))
        }
    }
}
