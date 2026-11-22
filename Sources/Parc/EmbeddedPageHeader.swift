import AppKit

@MainActor
final class EmbeddedPageHeader: NSView {
    static let height: CGFloat = 38
    var buttons: [NoteToolbarButton] = [] {
        didSet {
            oldValue.forEach { $0.removeFromSuperview() }
            buttons.forEach { addSubview($0) }
            needsLayout = true
        }
    }
    var action: NoteChip? {
        didSet {
            oldValue?.removeFromSuperview()
            if let action { addSubview(action) }
            needsLayout = true
        }
    }
    var onTitle: (() -> Void)?
    var showsRule = true { didSet { rule.isHidden = !showsRule } }
    private let rule = CALayer()
    private let favicon = CALayer()
    private let titleLabel = NoteMediaStyle.label("", font: NoteTheme.nunitoBold(13), color: NoteTheme.ink)
    private let hostLabel = NoteMediaStyle.label("", font: NoteTheme.nunitoRegular(12), color: NoteTheme.tertiaryInk)
    private let badge = EmbeddedPageBadge()
    private var faviconSource: String?
    private var faviconAddress: URL?
    private var titleArea = NSRect.zero

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.addSublayer(rule)
        layer?.addSublayer(favicon)
        favicon.contentsGravity = .resizeAspect
        favicon.cornerRadius = 3
        favicon.cornerCurve = .continuous
        favicon.masksToBounds = true
        for label in [titleLabel, hostLabel] {
            label.setAccessibilityElement(false)
            addSubview(label)
        }
        badge.isHidden = true
        addSubview(badge)
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    var titleText: String { titleLabel.stringValue }

    func setPage(title: String, host: String) {
        guard titleLabel.stringValue != title || hostLabel.stringValue != host else { return }
        titleLabel.stringValue = title
        hostLabel.stringValue = host
        needsLayout = true
    }

    func setBadge(_ text: String?, help: String?, live: Bool) {
        badge.configure(text: text, help: help, live: live)
        badge.isHidden = text == nil
        needsLayout = true
    }

    func showFavicon(for address: URL, source: String?) {
        guard faviconAddress != address || faviconSource != source || favicon.contents == nil else { return }
        faviconAddress = address
        faviconSource = source
        let link = source ?? NoteLinkMetadataParser.defaultIcon(for: address)
        NoteMediaMotion.instant {
            favicon.contents = NoteMediaStyle.symbol("globe", size: 12, weight: .medium).map { NoteMediaStyle.tinted($0, NoteTheme.tertiaryInk, in: self) }
        }
        guard let link, let iconURL = URL(string: link) else { return }
        NoteMediaImageLoader.shared.load(iconURL, pixels: 64) { [weak self] result in
            guard let self, self.faviconAddress == address, self.faviconSource == source,
                  case .success(let image) = result else { return }
            NoteMediaMotion.instant { self.favicon.contents = image.first }
        }
    }

    func loadPreview(for address: URL, _ completion: @escaping (NoteLinkPreview?) -> Void) {
        showFavicon(for: address, source: NoteLinkMetadata.shared.cached(address)?.iconURL)
        guard NoteLinkMetadata.shared.cached(address) == nil, NoteLinkMetadata.shared.failure(for: address) == nil else { return }
        NoteLinkMetadata.shared.fetch(address) { [weak self] result in
            guard let self, self.faviconAddress == address else { return }
            if case .success(let preview) = result {
                self.showFavicon(for: address, source: preview.iconURL)
                completion(preview)
            } else { completion(nil) }
        }
    }

    override func layout() {
        super.layout()
        let width = bounds.width, height = bounds.height
        NoteMediaMotion.instant {
            rule.frame = NSRect(x: 1, y: height - 1, width: max(0, width - 2), height: 1)
            rule.backgroundColor = NoteMediaStyle.cg(NoteMediaStyle.cardStroke, in: self)
            favicon.frame = NSRect(x: 12, y: (height - 16) / 2, width: 16, height: 16)
            favicon.contentsScale = window?.backingScaleFactor ?? 2
        }
        let size = NoteTheme.toolbarButtonSize
        var trailing = width - 6
        for button in buttons.reversed() where !button.isHidden {
            button.frame = NSRect(x: trailing - size.width, y: (height - size.height) / 2, width: size.width, height: size.height)
            trailing = button.frame.minX - 2
        }
        if let action, !action.isHidden {
            let chip = action.intrinsicContentSize
            action.frame = NSRect(x: trailing - 4 - chip.width, y: ((height - chip.height) / 2).rounded(), width: chip.width, height: chip.height)
            trailing = action.frame.minX - 4
        }
        let textLeading: CGFloat = 36
        if !badge.isHidden {
            let fitted = min(badge.intrinsicContentSize.width, max(0, trailing - 6 - textLeading - 60))
            badge.frame = NSRect(x: trailing - 6 - fitted, y: ((height - EmbeddedPageBadge.height) / 2).rounded(),
                                 width: fitted, height: EmbeddedPageBadge.height)
            trailing = badge.frame.minX - 2
        }
        let available = max(0, trailing - 8 - textLeading)
        let titleWidth = min(available, NoteMediaStyle.textWidth(titleLabel))
        titleLabel.frame = NSRect(x: textLeading, y: (height - 18) / 2, width: titleWidth, height: 18)
        let hostWidth = max(0, min(available - titleWidth - 6, NoteMediaStyle.textWidth(hostLabel)))
        hostLabel.frame = NSRect(x: titleLabel.frame.maxX + 6, y: (height - 16) / 2 + 1, width: hostWidth, height: 16)
        titleArea = NSRect(x: 8, y: 0, width: max(0, max(titleLabel.frame.maxX, hostLabel.frame.maxX) - 8), height: height)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsLayout = true
        if faviconSource == nil, let faviconAddress {
            favicon.contents = nil
            showFavicon(for: faviconAddress, source: nil)
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        if hit === titleLabel || hit === hostLabel { return self }
        return hit
    }

    override func resetCursorRects() {
        if onTitle != nil { addCursorRect(titleArea, cursor: .pointingHand) }
    }

    override func mouseDown(with event: NSEvent) {
        guard let onTitle, titleArea.contains(convert(event.locationInWindow, from: nil)) else { return }
        onTitle()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
final class EmbeddedPageBadge: NSView {
    static let height: CGFloat = 20
    private let label = NoteMediaStyle.label("", font: NoteTheme.nunitoBold(11), color: NoteTheme.secondaryInk)
    private let dot = CALayer()
    private var live = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = Self.height / 2
        layer?.cornerCurve = .continuous
        dot.cornerRadius = 3
        layer?.addSublayer(dot)
        label.lineBreakMode = .byTruncatingTail
        label.setAccessibilityElement(false)
        addSubview(label)
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    func configure(text: String?, help: String?, live: Bool) {
        label.stringValue = text ?? ""
        self.live = live
        toolTip = help
        setAccessibilityValue(text)
        setAccessibilityLabel(text)
        setAccessibilityHelp(help)
        invalidateIntrinsicContentSize()
        needsLayout = true
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: ceil(NoteMediaStyle.textWidth(label)) + (live ? 30 : 18), height: Self.height)
    }

    override func layout() {
        super.layout()
        let leading: CGFloat = live ? 20 : 9
        NoteMediaMotion.instant {
            dot.isHidden = !live
            dot.frame = NSRect(x: 9, y: (bounds.height - 6) / 2, width: 6, height: 6)
            dot.backgroundColor = NoteMediaStyle.cg(NoteTheme.accent, in: self)
            layer?.backgroundColor = NoteMediaStyle.cg(NoteTheme.chipFill, in: self)
        }
        label.textColor = live ? NoteTheme.ink : NoteTheme.secondaryInk
        label.frame = NSRect(x: leading, y: (bounds.height - 15) / 2, width: max(0, bounds.width - leading - 9), height: 15)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsLayout = true
    }
}
