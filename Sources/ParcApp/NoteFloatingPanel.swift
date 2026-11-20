import AppKit

enum NoteIcon: Hashable {
    case symbol(String)
    case glyph(String)
    case emoji(String)
}

@MainActor
class NoteFloatingPanel: NSView {
    enum Edge { case below, above }
    let contentView: NSView
    var onDismiss: (() -> Void)?
    private(set) var isPresented = false

    init(content: NSView) {
        contentView = content
        super.init(frame: NSRect(origin: .zero, size: content.fittingSize))
        wantsLayer = true
        layer?.cornerRadius = NoteTheme.menuRadius
        layer?.cornerCurve = .continuous
        addSubview(content)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    var preferredSize: NSSize { contentView.fittingSize }

    func present(in host: NSView, anchor: NSRect, edge: Edge = .below, animated: Bool = true) {
        if superview !== host { host.addSubview(self) }
        isPresented = true
        reposition(anchor: anchor, edge: edge, animated: false)
    }

    func reposition(anchor: NSRect, edge: Edge = .below, animated: Bool = true) {
        let size = preferredSize
        let y = edge == .below ? anchor.maxY + 6 : anchor.minY - 6 - size.height
        frame = NSRect(x: anchor.minX, y: y, width: size.width, height: size.height)
        contentView.frame = bounds
    }

    func dismiss(animated: Bool = true, completion: (() -> Void)? = nil) {
        isPresented = false
        removeFromSuperview()
        onDismiss?()
        completion?()
    }
}

@MainActor
final class NoteMenuList: NSView {
    struct Item: Hashable {
        var id: String
        var title: String
        var subtitle: String?
        var icon: NoteIcon?
        var shortcut: String?
        var section: String?
        var isChecked = false
        var isEnabled = true
        var isDestructive = false
        var hasSubmenu = false
    }

    var items: [Item] = [] { didSet { highlightedIndex = nil; needsLayout = true; invalidateIntrinsicContentSize() } }
    var highlightedIndex: Int?
    var onActivate: ((Item) -> Void)?
    var onHighlight: ((Item?) -> Void)?

    override var isFlipped: Bool { true }

    override var intrinsicContentSize: NSSize { NSSize(width: 260, height: CGFloat(items.count) * 34 + 8) }

    override var fittingSize: NSSize { intrinsicContentSize }

    @discardableResult
    func moveHighlight(by delta: Int) -> Bool {
        let enabled = items.indices.filter { items[$0].isEnabled }
        guard !enabled.isEmpty else { return false }
        let position = highlightedIndex.flatMap { enabled.firstIndex(of: $0) } ?? (delta > 0 ? -1 : enabled.count)
        highlightedIndex = enabled[(position + delta + enabled.count) % enabled.count]
        onHighlight?(highlightedIndex.map { items[$0] })
        needsDisplay = true
        return true
    }

    @discardableResult
    func activateHighlighted() -> Bool {
        guard let index = highlightedIndex, items.indices.contains(index), items[index].isEnabled else { return false }
        onActivate?(items[index])
        return true
    }
}
