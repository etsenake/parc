import AppKit

@MainActor
final class SplitDropPlaceholderCard: NSView {
    static let longestSide: CGFloat = 250
    static let cornerRadius: CGFloat = 20
    static let inset: CGFloat = 8
    static let spacing: CGFloat = 24
    static let iconSide: CGFloat = 16
    static var titleFont: NSFont { NSFontManager.shared.convert(.systemFont(ofSize: 13), toHaveTrait: .boldFontMask) }

    let iconView: NSImageView
    let titleView: NSTextField
    private let stack: NSStackView

    init(icon: NSImage, title: String) {
        iconView = NSImageView(image: icon)
        titleView = NSTextField(labelWithString: title)
        titleView.font = Self.titleFont
        titleView.alignment = .center
        titleView.maximumNumberOfLines = 3
        titleView.lineBreakMode = .byWordWrapping
        titleView.cell?.truncatesLastVisibleLine = true
        stack = NSStackView(views: [iconView, titleView])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = Self.spacing
        super.init(frame: .zero)
        wantsLayer = true
        stack.translatesAutoresizingMaskIntoConstraints = false
        iconView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: Self.iconSide),
            iconView.heightAnchor.constraint(equalToConstant: Self.iconSide),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: Self.inset),
            stack.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: Self.inset),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -Self.inset),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -Self.inset),
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() {
        layer?.backgroundColor = SadTabContent.backing.cgColor
        layer?.cornerRadius = Self.cornerRadius
        layer?.cornerCurve = .continuous
    }
    override func layout() {
        super.layout()
        titleView.preferredMaxLayoutWidth = bounds.width - 2 * Self.inset
    }

    static func size(forIncomingPane pane: NSSize) -> NSSize? {
        guard pane.width > 0, pane.height > 0, pane.width.isFinite, pane.height.isFinite else { return nil }
        return pane.height >= pane.width
            ? NSSize(width: longestSide * pane.width / pane.height, height: longestSide)
            : NSSize(width: longestSide, height: longestSide * pane.height / pane.width)
    }

    static func image(icon: NSImage?, title: String, incomingPane: NSSize) -> NSImage? {
        guard let size = size(forIncomingPane: incomingPane) else { return nil }
        let card = SplitDropPlaceholderCard(icon: icon ?? NSImage(size: NSSize(width: iconSide, height: iconSide)), title: title)
        card.frame = NSRect(origin: .zero, size: size)
        card.layoutSubtreeIfNeeded()
        guard let bitmap = card.bitmapImageRepForCachingDisplay(in: card.bounds) else { return nil }
        card.cacheDisplay(in: card.bounds, to: bitmap)
        let image = NSImage(size: card.bounds.size)
        image.addRepresentation(bitmap)
        return image
    }

    struct ItemImage {
        let size: NSSize
        let contents: Any?
    }

    @discardableResult
    static func present(_ image: NSImage, on sender: NSDraggingInfo, admits: @escaping (NSPasteboardItem) -> Bool) -> [Int: ItemImage] {
        var replaced: [Int: ItemImage] = [:]
        sender.enumerateDraggingItems(options: [], for: nil, classes: [NSPasteboardItem.self], searchOptions: [:]) { item, index, _ in
            guard let pasteboardItem = item.item as? NSPasteboardItem, admits(pasteboardItem) else { return }
            replaced[index] = ItemImage(size: item.draggingFrame.size, contents: item.imageComponentsProvider?().first?.contents)
            item.setDraggingFrame(NSRect(origin: item.draggingFrame.origin, size: image.size), contents: image)
        }
        return replaced
    }

    static func restore(_ images: [Int: ItemImage], on sender: NSDraggingInfo) {
        guard !images.isEmpty else { return }
        sender.enumerateDraggingItems(options: [], for: nil, classes: [NSPasteboardItem.self], searchOptions: [:]) { item, index, _ in
            guard let own = images[index], let contents = own.contents else { return }
            item.setDraggingFrame(NSRect(origin: item.draggingFrame.origin, size: own.size), contents: contents)
        }
    }
}
