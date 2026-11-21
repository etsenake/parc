import AppKit

@MainActor
final class NoteEmbedFallbackView: NSView {
    var onOpen: (() -> Void)?
    var onRetry: (() -> Void)?
    private let address: URL
    private let card = NoteLinkCardView(style: .bookmark)
    private let statusLabel: NSTextField
    let retryChip = NoteChip("Retry", icon: .symbol("arrow.clockwise"))
    private var tracking: NSTrackingArea?

    init(address: URL) {
        self.address = address
        statusLabel = NoteMediaStyle.label("", font: NoteMediaStyle.smallFont, color: NoteTheme.secondaryInk, lines: 2)
        super.init(frame: .zero)
        wantsLayer = true
        statusLabel.alignment = .center
        card.onOpen = { [weak self] in self?.onOpen?() }
        retryChip.onPress = { [weak self] in self?.onRetry?() }
        retryChip.isHidden = true
        for view in [card, statusLabel, retryChip] as [NSView] { addSubview(view) }
        configure(preview: NoteLinkMetadata.shared.cached(address))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    func configure(preview: NoteLinkPreview?) {
        let failed = preview == nil && NoteLinkMetadata.shared.failure(for: address) != nil
        card.configure(url: address, preview: preview, loading: preview == nil && !failed)
        needsLayout = true
    }

    func configure(status: String?, retryTitle: String?) {
        statusLabel.stringValue = status ?? ""
        retryChip.chipTitle = retryTitle ?? "Retry"
        retryChip.isHidden = retryTitle == nil
        setAccessibilityLabel(status)
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let width = min(560, max(0, bounds.width - 32))
        let cardHeight = card.height(for: width)
        let chipSize = retryChip.isHidden ? .zero : retryChip.intrinsicContentSize
        let statusHeight: CGFloat = statusLabel.stringValue.isEmpty ? 0 : 34
        let total = cardHeight + (statusHeight > 0 ? 10 + statusHeight : 0) + (chipSize.height > 0 ? 8 + chipSize.height : 0)
        var y = max(12, ((bounds.height - total) / 2).rounded())
        card.frame = NSRect(x: ((bounds.width - width) / 2).rounded(), y: y, width: width, height: cardHeight)
        y = card.frame.maxY + 10
        statusLabel.frame = NSRect(x: card.frame.minX, y: y, width: width, height: statusHeight)
        y += statusHeight + 8
        retryChip.frame = NSRect(x: ((bounds.width - chipSize.width) / 2).rounded(), y: y, width: chipSize.width, height: chipSize.height)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseMoved(with event: NSEvent) { card.setHovered(card.frame.contains(convert(event.locationInWindow, from: nil))) }
    override func mouseExited(with event: NSEvent) { card.setHovered(false) }
}
