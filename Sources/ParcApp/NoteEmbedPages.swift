import AppKit
import Combine

extension NotePageEditor: EmbeddedPageOwner {
    var embeddedPagesOpen: Bool { true }

    func embeddedPage(_ id: UUID, wants url: String, variant: EmbeddedPageFingerprint?) -> Bool {
        guard variant == nil, let block = session.page.block(NoteBlockID(id)) else { return false }
        return NoteEmbeddedPages.address(of: block)?.absoluteString == url
    }

    func embeddedPageFingerprint(for ids: Set<UUID>) -> EmbeddedPageFingerprint {
        EmbeddedPageFingerprint(Dictionary(uniqueKeysWithValues: ids.compactMap { id in
            session.page.block(NoteBlockID(id)).flatMap(NoteEmbeddedPages.address(of:)).map { (id, $0.absoluteString) }
        }))
    }

    func recordEmbeddedPageNavigation(_ url: URL, for id: UUID, expectedURL: String) throws {}
}

@MainActor
final class NoteEmbeddedPages: EmbeddedPagePool {
    private static var pools: [ObjectIdentifier: NoteEmbeddedPages] = [:]
    private let editor: NotePageEditor
    private var changes: AnyCancellable?
    private var scrolls: AnyCancellable?
    private var pointerMonitor: Any?
    private var scrollMonitor: Any?
    private var scrollLatch = NoteEmbedScrollLatch()
    private var latchedSource: ObjectIdentifier?
    private var escapeConfirmation = NoteEmbedEscapeConfirmation()
    private var retiring = Set<UUID>()
    var onOpen: ((URL) -> Void)?

    static func address(of block: NoteBlock) -> URL? {
        guard block.kind == .embed, let source = block.props.source else { return nil }
        return NoteMediaSource.webURL(from: source)
    }

    static func pool(for editor: NotePageEditor) -> NoteEmbeddedPages? { pools[ObjectIdentifier(editor)] }

    static func pool(for controller: NotePageViewController) -> NoteEmbeddedPages? {
        guard controller.isViewLoaded, let editor = controller.editor else { return nil }
        return pool(for: editor)
    }

    @discardableResult
    static func configure(_ controller: NotePageViewController, binding: PCNativeBrowserWindow, profilePath: String,
                          validOwner: @escaping () -> Bool, activeOwner: @escaping () -> Bool,
                          selectionChanged: @escaping () -> Void, metadataChanged: @escaping () -> Void,
                          contextImage: @escaping (PCBrowserView, PCNativeContextImage) -> Void,
                          open: @escaping (URL) -> Void, windowTransfer: WindowTransfer? = nil) -> Bool {
        guard controller.isViewLoaded, let editor = controller.editor else { return windowTransfer == nil }
        let key = ObjectIdentifier(editor)
        if let windowTransfer {
            guard let pool = pools[key], pool.rebindWindowTransfer(windowTransfer, binding: binding, profilePath: profilePath,
                validOwner: validOwner, activeOwner: activeOwner, selectionChanged: selectionChanged,
                metadataChanged: metadataChanged) else { return false }
            pool.onContextImage = contextImage
            pool.onOpen = open
            return true
        }
        if let pool = pools[key] {
            pool.onContextImage = contextImage
            pool.onOpen = open
            return true
        }
        let pool = NoteEmbeddedPages(editor: editor, binding: binding, profilePath: profilePath, validOwner: validOwner,
                                     activeOwner: activeOwner, selectionChanged: selectionChanged, metadataChanged: metadataChanged)
        pools[key] = pool
        pool.onContextImage = contextImage
        pool.onOpen = open
        pool.onError = { [weak editor] in editor?.onError?($0) }
        notifyBlocks(of: editor)
        return true
    }

    static func retire(_ controller: NotePageViewController) {
        guard controller.isViewLoaded, let editor = controller.editor else { return }
        retire(editor)
    }

    static func retire(_ editor: NotePageEditor) {
        guard let pool = pools.removeValue(forKey: ObjectIdentifier(editor)) else { return }
        pool.deactivate()
        pool.removeMonitors()
        pool.disposeAfterClosure()
        notifyBlocks(of: editor)
    }

    static func escapeOwner(for page: PCNativePage) -> NoteEmbeddedPages? {
        pools.values.first { $0.selectedPage === page }
    }

    static func lingering(containing page: PCNativePage) -> NoteEmbeddedPages? {
        liveOwners.lazy.compactMap { $0 as? NoteEmbeddedPages }.first { $0.contains(page) }
    }

    private static func notifyBlocks(of editor: NotePageEditor) {
        for view in editor.canvas.materializedViews { (view as? NoteEmbedBlockView)?.pageHostDidChange() }
    }

    private init(editor: NotePageEditor, binding: PCNativeBrowserWindow, profilePath: String,
                 validOwner: @escaping () -> Bool, activeOwner: @escaping () -> Bool,
                 selectionChanged: @escaping () -> Void, metadataChanged: @escaping () -> Void) {
        self.editor = editor
        super.init(owner: editor, hostView: editor.canvas, binding: binding, profilePath: profilePath, validOwner: validOwner,
                   activeOwner: activeOwner, selectionChanged: selectionChanged, metadataChanged: metadataChanged)
        changes = editor.session.changes.sink { [weak self] change in
            guard change.kind != .selection else { return }
            self?.reconcile()
        }
        if let clip = editor.canvas.enclosingScrollView?.contentView {
            scrolls = NotificationCenter.default.publisher(for: NSView.boundsDidChangeNotification, object: clip).sink { [weak self] _ in
                MainActor.assumeIsolated { self?.startVisiblePages() }
            }
        }
        installMonitors()
    }

    override func refreshVisibility() {
        super.refreshVisibility()
        startVisiblePages()
    }

    private func startVisiblePages() {
        guard gate.admitsCreation else { return }
        for (id, entry) in entries where !entry.started { start(id, entry: entry) }
    }

    var activeBlock: NoteBlockID? { interacting ? selectedID.map(NoteBlockID.init) : nil }

    func surface(for block: NoteBlockID, address: URL) -> NoteEmbedSurface? {
        if let existing = entries[block.raw], existing.originalURL != address.absoluteString { return nil }
        let profilePath = self.profilePath
        guard let entry = surface(id: block.raw, url: address.absoluteString, variant: nil, make: {
            NoteEmbedSurface(address: address, profilePath: profilePath)
        }), let surface = entry.surface as? NoteEmbedSurface else { return nil }
        if surface.onDone == nil {
            surface.onDone = { [weak self] in self?.finishInteraction(block) }
            surface.onOpen = { [weak self] url in self?.onOpen?(url) }
        }
        surface.selected = editor.session.selection == .blocks([block])
        return surface
    }

    override func loadURL(for url: URL, entry: EmbeddedPageEntry) -> URL {
        (entry.surface as? NoteEmbedSurface)?.liveAddress ?? url
    }

    func activate(_ block: NoteBlockID) {
        guard let entry = entries[block.raw], wants(block.raw, entry) else { return }
        synchronize(wanted: { [unowned self] in self.wants($0, $1) }, selection: block.raw, interacting: true)
        guard let page = selectedPage, entry.page === page, let window = hostView?.window, window.attachedSheet == nil else { return }
        window.makeFirstResponder(page.nativeView)
    }

    func deactivate() {
        escapeConfirmation = NoteEmbedEscapeConfirmation()
        guard interacting || selectedID != nil else { return }
        synchronize(wanted: { [unowned self] in self.wants($0, $1) }, selection: nil, interacting: false)
    }

    private func finishInteraction(_ block: NoteBlockID) {
        guard activeBlock == block else { return }
        deactivate()
        guard let window = editor.canvas.window, window.attachedSheet == nil else { return }
        window.makeFirstResponder(editor.canvas)
        editor.session.setSelection(.blocks([block]))
    }

    override func revealEntry(_ id: UUID) {
        let block = NoteBlockID(id)
        editor.canvas.revealBlock(block)
        if let entry = entries[id], wants(id, entry) {
            synchronize(wanted: { [unowned self] in self.wants($0, $1) }, selection: id, interacting: true)
        }
    }

    private func reconcile() {
        guard !gate.isDisposed else { return }
        let keepSelection = selectedID.flatMap { id in entries[id].map { wants(id, $0) } } == true
        synchronize(wanted: { [unowned self] in self.wants($0, $1) },
                    selection: keepSelection ? selectedID : nil, interacting: keepSelection && interacting)
        retiring = retiring.filter { id in entries[id].map { !wants(id, $0) } ?? false }
        let orphans = entries.filter { id, entry in !wants(id, entry) && entry.page?.isClosed == false && !retiring.contains(id) }
        guard !orphans.isEmpty, !gate.isTransferring, !gate.isRetiring else { return }
        retiring.formUnion(orphans.keys)
        let targets = orphans.map { (self as EmbeddedPagePool, $0.value) }
        EmbeddedPagePool.requestRetirement(of: targets, owners: [self], valid: { [weak self] in
            guard let self else { return false }
            return orphans.allSatisfy { id, entry in self.entries[id] === entry && !self.wants(id, entry) }
        }, completion: { [weak self] allowed in
            guard let self else { return }
            if allowed { self.retiring.subtract(orphans.keys) }
            self.reconcile()
            Self.notifyBlocks(of: self.editor)
        })
    }

    func canLeave(from page: PCNativePage) -> Bool { selectedPage === page && activeBlock != nil }

    func pageEscape(_ page: PCNativePage, prefersConfirmation: Bool) {
        guard canLeave(from: page), let block = activeBlock else { return }
        if escapeConfirmation.receive(prefersConfirmation: prefersConfirmation, now: ProcessInfo.processInfo.systemUptime) {
            finishInteraction(block)
        } else {
            editor.handles.presentToast?(.pressAgain(shortcut: "⎋", title: "head back to the note"))
        }
    }

    private func installMonitors() {
        if pointerMonitor == nil {
            pointerMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
                MainActor.assumeIsolated { self?.pointerDown(event) }
                return event
            }
        }
        if scrollMonitor == nil {
            scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                MainActor.assumeIsolated { self?.chainsToNote(event) == true } ? nil : event
            }
        }
    }

    private func removeMonitors() {
        if let pointerMonitor { NSEvent.removeMonitor(pointerMonitor) }
        if let scrollMonitor { NSEvent.removeMonitor(scrollMonitor) }
        pointerMonitor = nil
        scrollMonitor = nil
    }

    private func pageUnderPointer(_ event: NSEvent) -> UUID? {
        guard !gate.isDisposed, gate.admitsInput, validOwner(), let window = hostView?.window, event.window === window,
              window.attachedSheet == nil, let root = window.contentView else { return nil }
        let point = root.superview.map { $0.convert(event.locationInWindow, from: nil) } ?? event.locationInWindow
        let hit = root.hitTest(point)
        for (id, entry) in entries {
            guard let surface = entry.surface as? NoteEmbedSurface, surface.window === window,
                  let block = surface.superview, surface.takesPageInput(at: event.locationInWindow),
                  hit === block || hit?.isDescendant(of: surface.browser) == true, wants(id, entry) else { continue }
            return id
        }
        return nil
    }

    private func pointerDown(_ event: NSEvent) {
        guard let window = hostView?.window, event.window === window else { return }
        let inside = selectedID.flatMap { entries[$0] }.map { entry in
            entry.surface.window === window && entry.surface.bounds.contains(entry.surface.convert(event.locationInWindow, from: nil))
        } ?? false
        switch NoteEmbedPointerDecision.decide(pageUnderPointer: pageUnderPointer(event), active: selectedID, insideActive: inside) {
        case .activate(let id): activate(NoteBlockID(id))
        case .finish: deactivate()
        case .none: break
        }
    }

    private static func scrollPhase(of event: NSEvent) -> NoteEmbedScrollLatch.Phase {
        if event.momentumPhase == .ended || event.momentumPhase == .cancelled { return .momentumEnded }
        if !event.momentumPhase.isEmpty { return .momentum }
        if event.phase.contains(.began) { return .began }
        if event.phase.contains(.ended) || event.phase.contains(.cancelled) { return .ended }
        if event.phase.isEmpty { return .discrete }
        return .changed
    }

    private func chainsToNote(_ event: NSEvent) -> Bool {
        guard let window = hostView?.window, event.window === window else { return false }
        let phase = Self.scrollPhase(of: event)
        let starts = scrollLatch.startsGesture(phase, time: event.timestamp)
        let page = starts ? pageUnderPointer(event) : nil
        let previous = scrollLatch.latchedPage
        let route = scrollLatch.receive(phase, deltaX: Double(event.scrollingDeltaX), deltaY: Double(event.scrollingDeltaY),
                                        time: event.timestamp, pageUnderPointer: page)
        if starts || previous != scrollLatch.latchedPage { latchedSource = nil }
        for (id, entry) in entries { (entry.surface as? NoteEmbedSurface)?.scrollLatched = scrollLatch.latchedPage == id }
        guard route == .note else { return false }
        scrollNote(with: event, phase: phase)
        return true
    }

    private func scrollNote(with event: NSEvent, phase: NoteEmbedScrollLatch.Phase) {
        guard let scrollView = editor.canvas.enclosingScrollView else { return }
        if phase == .discrete {
            scrollView.scrollWheel(with: event)
            return
        }
        let clip = scrollView.contentView
        let delta = Double(event.scrollingDeltaY) * (event.hasPreciseScrollingDeltas ? 1 : Double(scrollView.verticalLineScroll))
        var bounds = clip.bounds
        bounds.origin.y = CGFloat(NoteEmbedScrollLatch.noteOffset(Double(bounds.origin.y), delta: delta, flipped: clip.isFlipped))
        clip.scroll(to: clip.constrainBoundsRect(bounds).origin)
        scrollView.reflectScrolledClipView(clip)
    }

    private func ownsLatchedPage(_ source: PCNativeHistorySwipeSource) -> Bool {
        if latchedSource == ObjectIdentifier(source) { return true }
        guard let id = scrollLatch.latchedPage, let entry = entries[id], let view = source.overlayContainer,
              view.isDescendant(of: entry.surface.browser) else { return false }
        latchedSource = ObjectIdentifier(source)
        return true
    }

    override func pageScrollBegan(momentum: Bool, from source: PCNativeHistorySwipeSource) {
        guard scrollLatch.awaitsPageAcknowledgement, ownsLatchedPage(source) else { return }
        scrollLatch.pageScrollBegan(momentum: momentum)
    }

    override func pageScrollUpdated(consumed: Bool, from source: PCNativeHistorySwipeSource) {
        guard scrollLatch.awaitsPageAcknowledgement, !consumed, ownsLatchedPage(source) else { return }
        scrollLatch.pageScrollUpdated(consumed: consumed)
    }

    override func didDispose() {
        removeMonitors()
        changes = nil
        scrolls = nil
    }
}
