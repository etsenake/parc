import AppKit

@MainActor
final class NoteLinkCardView: NSView {
    enum Layout { case bookmark }

    var onOpen: (() -> Void)?
    var onHeightChange: (() -> Void)?
    private let card = CALayer()
    private let preview = CALayer()
    private let favicon = CALayer()
    private let ring = CALayer()
    private let title: NSTextField
    private let summary: NSTextField
    private let site: NSTextField
    private let shimmerLines = [NoteMediaShimmer(), NoteMediaShimmer()]
    private let previewShimmer = NoteMediaShimmer()
    private var url: URL?
    private var info: NoteLinkPreview?
    private var loading = false
    private var hovered = false
    private var pressed = false
    private var hasPreviewImage = false
    private var previewFailed = false

    init(style: Layout) {
        title = NoteMediaStyle.label("", font: NoteTheme.nunitoBold(14.5), color: NoteTheme.ink)
        summary = NoteMediaStyle.label("", font: NoteTheme.nunitoRegular(13), color: NoteTheme.secondaryInk, lines: 2)
        summary.lineBreakMode = .byWordWrapping
        summary.cell?.truncatesLastVisibleLine = true
        site = NoteMediaStyle.label("", font: NoteTheme.nunitoRegular(12.5), color: NoteTheme.tertiaryInk)
        super.init(frame: .zero)
        wantsLayer = true
        card.cornerRadius = NoteMediaStyle.cardRadius
        card.cornerCurve = .continuous
        card.borderWidth = 1
        card.masksToBounds = true
        preview.contentsGravity = .resizeAspectFill
        preview.masksToBounds = true
        preview.opacity = 0
        favicon.contentsGravity = .resizeAspect
        favicon.cornerRadius = 3
        favicon.cornerCurve = .continuous
        favicon.masksToBounds = true
        ring.cornerRadius = NoteMediaStyle.cardRadius + 2
        ring.cornerCurve = .continuous
        ring.borderWidth = 2
        ring.isHidden = true
        layer?.addSublayer(card)
        card.addSublayer(preview)
        layer?.addSublayer(favicon)
        layer?.addSublayer(ring)
        previewShimmer.cornerRadius = 0
        addSubview(previewShimmer)
        for line in shimmerLines {
            line.cornerRadius = 3
            addSubview(line)
        }
        for view in [title, summary, site] { addSubview(view) }
        setAccessibilityElement(true)
        setAccessibilityRole(.link)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    func configure(url: URL, preview info: NoteLinkPreview?, loading: Bool) {
        let changedImage = info?.imageURL != self.info?.imageURL || url != self.url
        let changedIcon = info?.iconURL != self.info?.iconURL || url != self.url
        self.url = url
        self.info = info
        self.loading = loading
        let host = NoteMediaFormat.displayHost(url)
        title.stringValue = info?.title ?? host
        summary.stringValue = info?.summary ?? ""
        site.stringValue = siteLine(url: url)
        setAccessibilityValue(url.absoluteString)
        setAccessibilityHelp(loading ? "Fetching a preview." : "Opens the link.")
        if changedImage { loadPreview() }
        if changedIcon { loadFavicon() }
        refreshShimmer()
        needsLayout = true
    }

    private func siteLine(url: URL) -> String {
        var text = url.absoluteString
        if text.hasPrefix("https://") { text.removeFirst(8) } else if text.hasPrefix("http://") { text.removeFirst(7) }
        if text.hasSuffix("/") { text.removeLast() }
        return text
    }

    private func refreshShimmer() {
        let showLines = loading && summary.stringValue.isEmpty
        for line in shimmerLines { line.isHidden = !showLines }
        previewShimmer.isHidden = !showsPreview || (hasPreviewImage && !loading)
    }

    private func loadPreview() {
        hasPreviewImage = false
        previewFailed = false
        NoteMediaMotion.instant { preview.contents = nil; preview.opacity = 0 }
        guard let link = info?.imageURL, let imageURL = URL(string: link) else { refreshShimmer(); return }
        let expected = url
        NoteMediaImageLoader.shared.load(imageURL, pixels: 1024) { [weak self] result in
            guard let self, self.url == expected, self.info?.imageURL == link else { return }
            switch result {
            case .success(let image):
                self.hasPreviewImage = true
                NoteMediaMotion.instant { self.preview.contents = image.first }
                NoteMediaMotion.fadeIn(self.preview)
            case .failure:
                self.previewFailed = true
                self.onHeightChange?()
            }
            self.refreshShimmer()
            self.needsLayout = true
        }
    }

    private func loadFavicon() {
        NoteMediaMotion.instant { favicon.contents = NoteMediaStyle.symbol("globe", size: 12, weight: .medium).map { NoteMediaStyle.tinted($0, NoteTheme.tertiaryInk, in: self) } }
        guard let link = info?.iconURL ?? url.flatMap(NoteLinkMetadataParser.defaultIcon), let iconURL = URL(string: link) else { return }
        let expected = url
        NoteMediaImageLoader.shared.load(iconURL, pixels: 64) { [weak self] result in
            guard let self, self.url == expected, case .success(let image) = result else { return }
            NoteMediaMotion.instant { self.favicon.contents = image.first }
        }
    }

    var showsPreview: Bool { info?.imageURL != nil && !previewFailed }

    func height(for width: CGFloat) -> CGFloat {
        let hasSummary = !(info?.summary ?? "").isEmpty || loading
        return hasSummary || (showsPreview && width >= 360) ? 106 : 72
    }

    override func layout() {
        super.layout()
        let bounds = self.bounds
        let showsImage = showsPreview && bounds.width >= 360
        let previewWidth = showsImage ? min(250, (bounds.width * 0.33).rounded()) : 0
        let previewRect = NSRect(x: bounds.width - previewWidth, y: 0, width: previewWidth, height: bounds.height)
        let textRect = NSRect(x: 16, y: 14, width: max(0, bounds.width - previewWidth - 32), height: bounds.height - 28)
        NoteMediaMotion.instant {
            card.frame = bounds
            preview.frame = previewRect
            ring.frame = bounds.insetBy(dx: -3, dy: -3)
            let scale = window?.backingScaleFactor ?? 2
            preview.contentsScale = scale
            favicon.contentsScale = scale
        }
        previewShimmer.frame = previewRect
        let summaryText = summary.stringValue
        let hasSummary = !summaryText.isEmpty || loading
        title.frame = NSRect(x: textRect.minX, y: textRect.minY, width: textRect.width, height: 21)
        var y = title.frame.maxY + 3
        if hasSummary {
            summary.frame = NSRect(x: textRect.minX, y: y, width: textRect.width, height: 36)
            shimmerLines[0].frame = NSRect(x: textRect.minX, y: y + 4, width: textRect.width * 0.92, height: 10)
            shimmerLines[1].frame = NSRect(x: textRect.minX, y: y + 22, width: textRect.width * 0.6, height: 10)
            y += 40
        } else {
            summary.frame = .zero
        }
        let siteY = max(y, textRect.maxY - 18)
        NoteMediaMotion.instant { favicon.frame = NSRect(x: textRect.minX, y: siteY + 1, width: 16, height: 16) }
        site.frame = NSRect(x: textRect.minX + 22, y: siteY, width: max(0, textRect.width - 22), height: 18)
        refreshColors()
    }

    private func refreshColors() {
        let fill = pressed ? NoteTheme.pressedFill : hovered ? NoteTheme.hoverFill : NSColor.clear
        NoteMediaMotion.instant {
            card.backgroundColor = NoteMediaStyle.cg(fill, in: self)
            card.borderColor = NoteMediaStyle.cg(NoteMediaStyle.cardStroke, in: self)
            ring.borderColor = NoteMediaStyle.cg(NoteTheme.accent, in: self)
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsLayout = true
        if !hasPreviewImage { loadFavicon() }
    }

    func setHovered(_ value: Bool) {
        hovered = value
        let from = card.presentation()?.backgroundColor
        refreshColors()
        guard !NoteAnimation.reduceMotion, let from else { return }
        let fade = CABasicAnimation(keyPath: "backgroundColor")
        fade.fromValue = from
        fade.toValue = card.backgroundColor
        fade.duration = 0.1
        fade.timingFunction = CAMediaTimingFunction(controlPoints: 0.42, 0, 1, 1)
        card.add(fade, forKey: "link.hover")
    }

    func setSelected(_ selected: Bool) {
        NoteMediaMotion.instant { ring.isHidden = !selected }
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        pressed = true
        refreshColors()
        if let layer { NoteMediaMotion.press(layer, pressed: true, in: self, scale: 0.992) }
    }

    override func mouseDragged(with event: NSEvent) {
        let inside = bounds.contains(convert(event.locationInWindow, from: nil))
        guard inside != pressed else { return }
        pressed = inside
        refreshColors()
        if let layer { NoteMediaMotion.press(layer, pressed: inside, in: self, scale: 0.992) }
    }

    override func mouseUp(with event: NSEvent) {
        let inside = bounds.contains(convert(event.locationInWindow, from: nil))
        pressed = false
        refreshColors()
        if let layer { NoteMediaMotion.press(layer, pressed: false, in: self, scale: 0.992) }
        if inside { onOpen?() }
    }

    override func accessibilityPerformPress() -> Bool {
        onOpen?()
        return true
    }
}
