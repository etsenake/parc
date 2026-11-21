import AppKit
import Combine
import ParcCore

@MainActor
final class NoteEaselPageRegistry {
    struct Page {
        let block: NoteBlockID
        let session: EaselSession
        let directory: URL
        let item: UUID
    }

    private static var registries: [ObjectIdentifier: NoteEaselPageRegistry] = [:]
    private weak var editor: NotePageEditor?
    private var pages: [UUID: Page] = [:]
    private var watches: [ObjectIdentifier: AnyCancellable] = [:]

    private init(editor: NotePageEditor) { self.editor = editor }

    static func existing(for editor: NotePageEditor) -> NoteEaselPageRegistry? {
        guard let registry = registries[ObjectIdentifier(editor)], registry.editor === editor else { return nil }
        return registry
    }

    static func registry(for editor: NotePageEditor) -> NoteEaselPageRegistry {
        if let registry = existing(for: editor) { return registry }
        registries = registries.filter { $0.value.editor != nil }
        let registry = NoteEaselPageRegistry(editor: editor)
        registries[ObjectIdentifier(editor)] = registry
        return registry
    }

    func page(_ key: UUID) -> Page? { pages[key] }

    func keys(of block: NoteBlockID) -> [UUID: UUID] {
        pages.filter { $0.value.block == block }.mapValues(\.item)
    }

    func register(_ key: UUID, block: NoteBlockID, session: EaselSession, directory: URL, item: UUID) {
        pages[key] = Page(block: block, session: session, directory: directory.standardizedFileURL, item: item)
        let id = ObjectIdentifier(session)
        guard watches[id] == nil else { return }
        watches[id] = session.$document.sink { [weak self, weak session] next in
            guard let self, let session else { return }
            self.documentWillChange(next, in: session)
        }
    }

    func wants(_ key: UUID, url: String, variant: EmbeddedPageFingerprint?) -> Bool? {
        guard let page = pages[key], let editor else { return nil }
        guard let block = editor.session.page.block(page.block), NoteEaselAddress.id(of: block) == page.session.document.id,
              NoteEaselHost.host(for: editor)?.directory == page.directory else { return false }
        return page.session.embeddedPagesOpen && page.session.embeddedPage(page.item, wants: url, variant: variant)
    }

    func fingerprint(_ key: UUID) -> String? {
        guard let page = pages[key], let item = page.session.document.items.first(where: { $0.id == page.item }) else { return nil }
        return "easel " + page.block.raw.uuidString + " " + item.id.uuidString + " " + (item.url ?? "") + (item.captureLayout == nil ? "" : " live")
    }

    private func documentWillChange(_ next: EaselDocument, in session: EaselSession) {
        guard let editor, let pool = NoteEmbeddedPages.pool(for: editor) else { return }
        for (key, page) in pages where page.session === session {
            guard let entry = pool.entries[key], entry.variant == nil,
                  let item = next.items.first(where: { $0.id == page.item && $0.kind == .browser }), let url = item.url,
                  session.isRecordingBrowserNavigation(page.item, from: entry.originalURL, to: url) else { continue }
            entry.originalURL = url
        }
        DispatchQueue.main.async { [weak pool] in pool?.reconcile() }
    }
}

@MainActor
final class NoteEaselPages: EaselBrowserObjectHosting {
    let block: NoteBlockID
    let session: EaselSession
    private weak var pool: NoteEmbeddedPages?
    private weak var canvas: EaselCanvasView?
    private let registry: NoteEaselPageRegistry
    private let directory: URL
    private let isActive: () -> Bool
    private var snapshotChrome: EaselSnapshotHeader?
    private var framingFailures: Set<UUID> = []

    init(block: NoteBlockID, session: EaselSession, directory: URL, editor: NotePageEditor, pool: NoteEmbeddedPages,
         canvas: EaselCanvasView, isActive: @escaping () -> Bool) {
        self.block = block
        self.session = session
        self.directory = directory
        self.pool = pool
        self.canvas = canvas
        self.isActive = isActive
        registry = NoteEaselPageRegistry.registry(for: editor)
    }

    func hosts(_ pool: NoteEmbeddedPages, _ session: EaselSession, _ canvas: EaselCanvasView) -> Bool {
        self.pool === pool && self.session === session && self.canvas === canvas
    }

    private func key(_ item: UUID) -> UUID { NoteEaselPageKey.key(block: block.raw, item: item) }

    private static func variant(_ item: EaselItem) -> EmbeddedPageFingerprint? { item.captureLayout.map(EmbeddedPageFingerprint.init) }

    private static func matches(_ item: EaselItem, _ entry: EmbeddedPageEntry) -> Bool {
        item.ownsEmbeddedPage && item.url == entry.originalURL && variant(item) == entry.variant
    }

    func surface(for item: EaselItem) -> NSView? {
        guard let pool, item.ownsEmbeddedPage, let url = item.url else { return nil }
        let key = key(item.id), variant = Self.variant(item)
        if let existing = pool.entries[key], existing.originalURL != url || existing.variant != variant { return nil }
        registry.register(key, block: block, session: session, directory: directory, item: item.id)
        let profilePath = pool.profilePath, layout = item.captureLayout
        let address = URL(string: url) ?? URL(string: "about:blank")!
        guard let entry = pool.surface(id: key, url: url, variant: variant, make: {
            EaselBrowserSurface(profilePath: profilePath, address: address, captureLayout: layout)
        }), let view = entry.surface as? EaselBrowserSurface else { return nil }
        guard view.onDone == nil else { return view }
        let id = item.id
        view.onDone = { [weak self, weak entry] in
            guard let self, let entry, let pool = self.pool, pool.entries[key] === entry,
                  pool.accessibilitySurface(for: key) === entry.surface, let canvas = self.canvas,
                  let window = canvas.window, window.attachedSheet == nil else { return }
            canvas.cancelOperation(nil); window.makeFirstResponder(canvas)
            canvas.layoutSubtreeIfNeeded()
        }
        view.onSnapshot = { [weak self] in self?.canvas?.setLiveCapture(id, enabled: false) }
        view.onOpen = { [weak self] url in self?.pool?.onOpen?(url) }
        view.onFramingFailed = { [weak self] in
            self?.framingFailures.insert(id)
            DispatchQueue.main.async { [weak self] in self?.canvas?.setLiveCapture(id, enabled: false) }
        }
        return view
    }

    func snapshotHeader(for item: EaselItem) -> NSView? {
        guard pool != nil, EaselWebItemChrome.isSnapshot(item), let raw = item.url, let address = URL(string: raw) else { return nil }
        let header = snapshotChrome ?? EaselSnapshotHeader()
        snapshotChrome = header
        let id = item.id
        header.onMakeLive = { [weak self] in
            self?.framingFailures.remove(id)
            self?.canvas?.setLiveCapture(id, enabled: true)
        }
        header.onOpen = { [weak self] in self?.pool?.onOpen?(address) }
        header.configure(item, address: address, framingFailed: framingFailures.contains(id))
        return header
    }

    func synchronize(items: [EaselItem], selection: Set<UUID>, interacting: Bool) {
        guard let pool, !pool.disposed else { return }
        let chosen = isActive() && interacting && selection.count == 1
            ? selection.first.flatMap { id in items.contains { $0.id == id && $0.ownsEmbeddedPage } ? key(id) : nil } : nil
        if let chosen {
            pool.synchronize(wanted: { [unowned pool] in pool.wants($0, $1) }, selection: chosen, interacting: true)
        } else if let current = pool.selectedID, registry.page(current)?.block == block {
            pool.synchronize(wanted: { [unowned pool] in pool.wants($0, $1) }, selection: nil, interacting: false)
        }
    }

    func release() { synchronize(items: [], selection: [], interacting: false) }

    func focusPage(for id: UUID) -> Bool { pool?.focusPage(for: key(id)) ?? false }

    func accessibilitySurface(for id: UUID) -> NSView? { pool?.accessibilitySurface(for: key(id)) }

    func prepareReplacement(_ next: EaselDocument, valid: @escaping () -> Bool, completion: @escaping (Bool) -> Void) {
        guard let pool else { completion(valid()); return }
        let original = session.document
        guard valid(), !pool.gate.isTransferring, !pool.gate.isRetiring else { completion(false); return }
        let mine = registry.keys(of: block).compactMap { key, item -> (EmbeddedPagePool, EmbeddedPageEntry)? in
            guard let entry = pool.entries[key] else { return nil }
            return next.items.contains { $0.id == item && Self.matches($0, entry) } ? nil : (pool, entry)
        }
        let tabs = EmbeddedPagePool.liveOwners.compactMap { $0 as? EaselBrowserObjects }.filter { $0.session === session }
        let theirs = tabs.flatMap { owner in owner.entries.compactMap { id, entry -> (EmbeddedPagePool, EmbeddedPageEntry)? in
            next.items.contains { $0.id == id && Self.matches($0, entry) } ? nil : (owner, entry)
        } }
        guard tabs.allSatisfy({ !$0.gate.isTransferring && !$0.gate.isRetiring }) else { completion(false); return }
        EmbeddedPagePool.requestRetirement(of: mine + theirs, owners: [pool] + tabs, valid: { [weak self] in
            guard let self else { return false }
            return valid() && self.session.document == original
        }, completion: completion)
    }
}
