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
        pool.disposeAfterClosure()
        notifyBlocks(of: editor)
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
        installPointerMonitor()
        guard let page = selectedPage, entry.page === page, let window = hostView?.window, window.attachedSheet == nil else { return }
        window.makeFirstResponder(page.nativeView)
    }

    func deactivate() {
        removePointerMonitor()
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
            installPointerMonitor()
        }
    }

    private func reconcile() {
        guard !gate.isDisposed else { return }
        if let id = selectedID, entries[id].map({ wants(id, $0) }) != true { removePointerMonitor() }
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

    private func installPointerMonitor() {
        guard pointerMonitor == nil else { return }
        pointerMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            MainActor.assumeIsolated { self?.pointerDown(event) }
            return event
        }
    }

    private func removePointerMonitor() {
        if let pointerMonitor { NSEvent.removeMonitor(pointerMonitor) }
        pointerMonitor = nil
    }

    private func pointerDown(_ event: NSEvent) {
        guard let id = selectedID, let entry = entries[id], let window = hostView?.window, event.window === window else { return }
        let surface = entry.surface
        if surface.window === window, surface.bounds.contains(surface.convert(event.locationInWindow, from: nil)) { return }
        deactivate()
    }

    override func didDispose() {
        removePointerMonitor()
        changes = nil
        scrolls = nil
    }
}
