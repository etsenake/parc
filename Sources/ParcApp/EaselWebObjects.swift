import AppKit

@MainActor
final class EaselWebObjects: EaselHostedObjects {
    private weak var canvas: EaselCanvasView?
    private var cards: [UUID: EaselBookmarkView] = [:]

    private init(canvas: EaselCanvasView) { self.canvas = canvas }

    @discardableResult
    static func install(on canvas: EaselCanvasView) -> EaselWebObjects {
        if let existing = canvas.hostedObjects.lazy.compactMap({ $0 as? EaselWebObjects }).first { return existing }
        let objects = EaselWebObjects(canvas: canvas)
        canvas.hostedObjects.append(objects)
        return objects
    }

    func hosts(_ item: EaselItem) -> Bool { item.kind == .link && item.url != nil }

    func hostedView(for item: EaselItem) -> NSView? {
        guard hosts(item), let raw = item.url, let url = URL(string: raw) else { return nil }
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
        let linked = Set(items.filter(hosts).map(\.id))
        for id in Array(cards.keys) where !linked.contains(id) {
            cards.removeValue(forKey: id)?.removeFromSuperview()
        }
    }
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
