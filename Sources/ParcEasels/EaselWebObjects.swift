import AppKit
import ParcCore
import ParcNotes

@MainActor
final class EaselWebObjects: EaselHostedObjects, EaselCanvasPasteChoices {
    private weak var canvas: EaselCanvasView?
    private var cards: [UUID: EaselBookmarkView] = [:]
    private var entries: [UUID: EaselLinkEntryHost] = [:]
    private var known: Set<UUID>?
    private var searchPopover: NotePagePopover?
    private var searchList: NoteMenuList?
    private var searchTarget: UUID?
    private var searchCategory = EaselWebNavigation.Category.images
    private var pasteMenu: NotePasteLinkMenu?
    private var pasteTarget: UUID?
    private var pasteMonitor: Any?
    private var downloads: [UUID: Task<Void, Never>] = [:]

    private init(canvas: EaselCanvasView) { self.canvas = canvas }

    @discardableResult
    static func install(on canvas: EaselCanvasView) -> EaselWebObjects {
        if let existing = canvas.hostedObjects.lazy.compactMap({ $0 as? EaselWebObjects }).first { return existing }
        let objects = EaselWebObjects(canvas: canvas)
        canvas.hostedObjects.append(objects)
        return objects
    }

    func hosts(_ item: EaselItem) -> Bool {
        item.kind == .link || (item.kind == .browser && item.url == nil)
    }

    func hostedView(for item: EaselItem) -> NSView? {
        guard hosts(item) else { return nil }
        if item.isEmptyPlaceholder { return entryView(for: item) }
        guard let raw = item.url, let url = URL(string: raw) else { return nil }
        let view = cards[item.id] ?? EaselBookmarkView()
        if cards[item.id] == nil {
            let id = item.id
            view.onOpen = { [weak self] in
                guard let self, let canvas = self.canvas,
                      let current = canvas.session.document.items.first(where: { $0.id == id }),
                      let raw = current.url, let url = URL(string: raw) else { return }
                canvas.onOpenURL?(url)
            }
            view.onPreview = { [weak self] preview, address in self?.canvas?.recordLinkPreview(preview, for: id, url: address) }
            cards[item.id] = view
        }
        view.configure(item, url: url, savesPreview: canvas?.viewOnly == false)
        return view
    }

    func synchronizeHosted(items: [EaselItem], selection: Set<UUID>, interacting: Bool) {
        let linked = Set(items.filter { $0.kind == .link && $0.url != nil }.map(\.id))
        for id in Array(cards.keys) where !linked.contains(id) { cards.removeValue(forKey: id)?.removeFromSuperview() }
        let empty = items.filter { hosts($0) && $0.isEmptyPlaceholder }
        let emptyIDs = Set(empty.map(\.id))
        for id in Array(entries.keys) where !emptyIDs.contains(id) {
            if searchTarget == id { closeSearch() }
            entries.removeValue(forKey: id)?.removeFromSuperview()
        }
        let editable = canvas?.viewOnly == false
        for item in empty {
            guard let host = entries[item.id] else { continue }
            host.accepting = interacting && editable && selection == [item.id]
            host.entry.editable = editable
            if !host.accepting, searchTarget == item.id { closeSearch() }
        }
        if let pasteTarget, selection != [pasteTarget] || !linked.contains(pasteTarget) { dismissPasteMenu() }
        let fresh = known.map { emptyIDs.subtracting($0) } ?? []
        known = Set(items.map(\.id))
        if editable, interacting, selection.count == 1, let id = selection.first, fresh.contains(id) {
            DispatchQueue.main.async { [weak self] in self?.focusEntry(id) }
        }
    }

    private func entryView(for item: EaselItem) -> NSView {
        if let existing = entries[item.id], existing.kind == item.kind { return existing }
        let host = EaselLinkEntryHost(kind: item.kind)
        let id = item.id
        let entry = host.entry
        if item.kind == .browser {
            EmbeddedPageSearchRows.configure(entry)
            entry.onTextChange = { [weak self] text in self?.refreshSearch(for: id, text: text) }
            entry.onCommand = { [weak self] selector in self?.searchCommand(selector, for: id) ?? false }
            entry.onUnrecognized = { [weak self] _ in self?.searchTarget == id && self?.searchList?.activateHighlighted() == true }
        } else {
            entry.parseLink = { text in NoteMediaSource.webURL(from: text).flatMap { $0.user == nil && $0.password == nil ? $0 : nil } }
        }
        entry.onSubmit = { [weak self] url in self?.fill(id, with: url) }
        entry.onCancel = { [weak self] in
            self?.closeSearch()
            guard let canvas = self?.canvas, let window = canvas.window else { return }
            window.makeFirstResponder(canvas)
        }
        entries[item.id] = host
        return host
    }

    private func focusEntry(_ id: UUID) {
        guard let host = entries[id], host.accepting, host.window != nil else { return }
        _ = host.entry.beginEditing()
    }

    private func fill(_ id: UUID, with url: URL) {
        closeSearch()
        guard let canvas, canvas.fillWebObject(id, url: url) else { entries[id]?.entry.refuse(); return }
        if let window = canvas.window, window.firstResponder is NSText { window.makeFirstResponder(canvas) }
    }

    private func popoverHost() -> NSView? { canvas?.enclosingScrollView?.superview ?? canvas }

    private func refreshSearch(for id: UUID, text: String) {
        let items = EmbeddedPageSearchRows.items(for: text)
        guard !items.isEmpty, let host = entries[id], let container = popoverHost() else { closeSearch(); return }
        if searchTarget != id || searchPopover?.isOpen != true {
            closeSearch()
            let list = NoteMenuList()
            list.minimumWidth = 260
            list.setAccessibilityLabel("Search results")
            list.onActivate = { [weak self] item in self?.activateSearch(item, for: id) }
            list.onCancel = { [weak self] in self?.closeSearch() }
            let popover = NotePagePopover(content: list)
            popover.exempt(host)
            popover.onClose = { [weak self, weak popover] in
                guard let self, self.searchPopover === popover else { return }
                self.searchPopover = nil
                self.searchList = nil
                self.searchTarget = nil
            }
            list.items = items
            list.prepare(origin: .keyboard)
            list.highlight(id: searchCategory.rawValue, animated: false)
            searchList = list
            searchPopover = popover
            searchTarget = id
            popover.present(in: container, anchor: container.convert(host.bounds, from: host), edge: .below, alignment: .leading)
            return
        }
        searchList?.setItems(items, keepingHighlight: true)
        if searchList?.highlightedItem == nil { searchList?.highlight(id: searchCategory.rawValue, animated: false) }
    }

    private func searchCommand(_ selector: Selector, for id: UUID) -> Bool {
        guard searchTarget == id, let list = searchList, searchPopover?.isOpen == true else { return false }
        switch selector {
        case #selector(NSResponder.moveUp(_:)), #selector(NSResponder.moveDown(_:)): return list.handle(command: selector)
        case #selector(NSResponder.insertNewline(_:)): return list.activateHighlighted()
        case #selector(NSResponder.cancelOperation(_:)): closeSearch(); return true
        default: return false
        }
    }

    private func activateSearch(_ item: NoteMenuList.Item, for id: UUID) {
        guard let entry = entries[id]?.entry, let found = EmbeddedPageSearchRows.search(for: item, text: entry.text) else { return }
        searchCategory = found.search.category
        fill(id, with: found.url)
    }

    private func closeSearch() {
        let popover = searchPopover
        searchPopover = nil
        searchList = nil
        searchTarget = nil
        popover?.close()
    }

    func offerPasteChoices(for id: UUID, url: URL) {
        dismissPasteMenu()
        guard let canvas, let container = popoverHost(), let card = cards[id], card.window != nil else { return }
        let media = NoteClipboard.linkedMediaKind(url)
        let menu = NotePasteLinkMenu(url: url, leading: [.link, .bookmark], embeddable: true, media: media, place: .easel) { [weak self] choice in
            self?.choosePaste(choice, for: id, url: url)
        }
        menu.list.highlight(id: NotePasteLinkMenu.Choice.bookmark.rawValue, animated: false)
        pasteMenu = menu
        pasteTarget = id
        menu.present(in: container, anchor: container.convert(card.bounds, from: card))
        installPasteMonitor(canvas: canvas)
        guard media == nil else { return }
        NoteLinkKindProbe.kind(of: url) { [weak self, weak menu] kind in
            guard let self, let menu, self.pasteMenu === menu, let kind else { return }
            menu.offer(kind)
        }
    }

    private func installPasteMonitor(canvas: EaselCanvasView) {
        guard pasteMonitor == nil else { return }
        pasteMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel]) { [weak self] event in
            MainActor.assumeIsolated { self?.handlePasteEvent(event) == true } ? nil : event
        }
    }

    private func handlePasteEvent(_ event: NSEvent) -> Bool {
        guard let menu = pasteMenu, menu.isPresented, let window = canvas?.window else { dismissPasteMenu(); return false }
        guard event.window === window else { return false }
        switch event.type {
        case .keyDown:
            let flags = event.modifierFlags.intersection([.command, .control, .option, .shift])
            if event.keyCode == 48, flags.isEmpty || flags == .shift {
                menu.list.moveHighlight(by: flags == .shift ? -1 : 1)
                return true
            }
            if flags.intersection([.command, .control, .option]).isEmpty, menu.list.handleKeyDown(event) { return true }
            dismissPasteMenu()
            return false
        case .scrollWheel:
            dismissPasteMenu()
            return false
        default:
            if !menu.contains(windowPoint: event.locationInWindow) { dismissPasteMenu() }
            return false
        }
    }

    private func dismissPasteMenu() {
        if let pasteMonitor { NSEvent.removeMonitor(pasteMonitor) }
        pasteMonitor = nil
        let menu = pasteMenu
        pasteMenu = nil
        pasteTarget = nil
        menu?.dismiss()
    }

    private func choosePaste(_ choice: NotePasteLinkMenu.Choice, for id: UUID, url: URL) {
        dismissPasteMenu()
        guard let canvas else { return }
        switch choice {
        case .dismiss, .bookmark, .mention, .easel: return
        case .link: canvas.turnBookmark(id, into: .text)
        case .embed: canvas.turnBookmark(id, into: .browser)
        case .video: canvas.replaceBookmark(id, withMedia: .video, url: url, data: nil)
        case .audio: canvas.replaceBookmark(id, withMedia: .audio, url: url, data: nil)
        case .image: download(url, for: id, kind: .image)
        case .pdf: download(url, for: id, kind: .pdf)
        }
    }

    private func download(_ url: URL, for id: UUID, kind: EaselItemKind) {
        downloads[id]?.cancel()
        downloads[id] = Task { [weak self] in
            do {
                let body = try await EaselCanvasView.download(url, kind: kind)
                guard let self, !Task.isCancelled else { return }
                self.downloads.removeValue(forKey: id)
                self.canvas?.replaceBookmark(id, withMedia: kind, url: url, data: body)
            } catch {
                guard let self, !Task.isCancelled else { return }
                self.downloads.removeValue(forKey: id)
                self.canvas?.onError?(error)
            }
        }
    }
}

@MainActor
final class EaselLinkEntryHost: NSView {
    let kind: EaselItemKind
    let entry: NoteLinkEntryView
    var accepting = false

    init(kind: EaselItemKind) {
        self.kind = kind
        entry = NoteLinkEntryView(style: kind == .browser ? .embed : .bookmark)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = NoteMediaStyle.cardRadius
        layer?.cornerCurve = .continuous
        addSubview(entry)
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() { layer?.backgroundColor = NoteMediaStyle.cg(EaselAppearance.cardFill, in: self) }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }

    override func layout() {
        super.layout()
        let height = min(bounds.height, NoteLinkEntryView.defaultHeight)
        entry.frame = NSRect(x: 0, y: ((bounds.height - height) / 2).rounded(), width: bounds.width, height: height)
    }

    override func hitTest(_ point: NSPoint) -> NSView? { accepting ? super.hitTest(point) : nil }
    override func accessibilityChildren() -> [Any]? { accepting ? super.accessibilityChildren() : [] }
}

@MainActor
final class EaselBookmarkView: NSView {
    var onOpen: (() -> Void)?
    var onPreview: ((EaselLinkPreviewData, String) -> Void)?
    private let card = NoteLinkCardView(style: .bookmark)
    private var url: URL?
    private var fetched: URL?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = NoteMediaStyle.cardRadius
        layer?.cornerCurve = .continuous
        card.showsPointer = false
        card.onOpen = { [weak self] in self?.onOpen?() }
        addSubview(card)
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    func configure(_ item: EaselItem, url: URL, savesPreview: Bool) {
        self.url = url
        let stored = item.preview.map(Self.noteLinkPreview)
        let preview = stored ?? NoteLinkMetadata.shared.cached(url)
        let failed = preview == nil && NoteLinkMetadata.shared.failure(for: url) != nil
        card.configure(url: url, preview: preview, loading: preview == nil && !failed)
        card.setAccessibilityLabel("Bookmark: " + (preview?.title ?? EaselBookmarkCard.host(url)))
        if stored == nil, savesPreview { fetch(url) }
    }

    private func fetch(_ url: URL) {
        if let cached = NoteLinkMetadata.shared.cached(url) { save(cached, for: url); return }
        guard fetched != url else { return }
        fetched = url
        NoteLinkMetadata.shared.fetch(url) { [weak self] result in
            guard let self, self.url == url else { return }
            if case .success(let preview) = result { self.save(preview, for: url) }
            else if let url = self.url { self.card.configure(url: url, preview: nil, loading: false) }
        }
    }

    private func save(_ preview: NoteLinkPreview, for url: URL) {
        card.configure(url: url, preview: preview, loading: false)
        guard let data = EaselBookmarkCard.preview(title: preview.title, summary: preview.summary, siteName: preview.siteName,
                                                   imageURL: preview.imageURL, iconURL: preview.iconURL) else { return }
        onPreview?(data, url.absoluteString)
    }

    static func noteLinkPreview(_ data: EaselLinkPreviewData) -> NoteLinkPreview {
        NoteLinkPreview(title: data.title, summary: data.summary, siteName: data.siteName,
                        iconURL: data.icon.flatMap { EaselLinkPreviewData.isAddress($0) ? $0 : nil },
                        imageURL: data.image.flatMap { EaselLinkPreviewData.isAddress($0) ? $0 : nil })
    }

    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() { layer?.backgroundColor = NoteMediaStyle.cg(EaselAppearance.cardFill, in: self) }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }

    override func layout() {
        super.layout()
        card.frame = bounds
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
