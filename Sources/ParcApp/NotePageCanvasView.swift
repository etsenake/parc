import AppKit

@MainActor
final class NotePageCanvasView: NSView {
    weak var editor: NotePageEditor?
    let overlayView = NSView()
    var headerView: NSView? {
        didSet {
            oldValue?.removeFromSuperview()
            if let headerView { addSubview(headerView, positioned: .below, relativeTo: overlayView) }
            needsLayout = true
        }
    }
    private var views: [NoteBlockID: NoteBlockView] = [:]
    private var frames: [NoteBlockID: NSRect] = [:]

    init(editor: NotePageEditor) {
        self.editor = editor
        super.init(frame: .zero)
        wantsLayer = true
        addSubview(overlayView)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    var contentRect: NSRect {
        let width = min(NoteTheme.pageColumnWidth, max(0, bounds.width - NoteTheme.minimumSideMargin * 2))
        return NSRect(x: (bounds.width - width) / 2, y: 0, width: width, height: bounds.height)
    }

    func reload() {
        guard let editor else { return }
        for view in views.values { view.removeFromSuperview() }
        views.removeAll()
        for block in editor.session.page.allBlocks() {
            let view = editor.makeBlockView(for: block)
            views[block.id] = view
            addSubview(view, positioned: .below, relativeTo: overlayView)
        }
        needsLayout = true
    }

    func apply(_ change: NotePageChange) {
        guard let editor else { return }
        if change.kind == .replaced || change.kind == .structure || change.kind == .settings { reload(); return }
        for id in change.blocks {
            guard let block = editor.session.page.block(id) else { continue }
            views[id]?.update(block)
        }
        needsLayout = true
    }

    override func layout() {
        super.layout()
        guard let editor else { return }
        let column = contentRect
        var y: CGFloat = headerView.map { $0.frame = NSRect(x: column.minX, y: 0, width: column.width, height: $0.fittingSize.height); return $0.frame.maxY } ?? 64
        frames.removeAll()
        for flat in editor.session.page.flattened() {
            guard let view = views[flat.id] else { continue }
            let x = column.minX + CGFloat(flat.depth) * NoteTheme.indentWidth
            let width = max(0, column.maxX - x)
            let height = view.measureHeight(width: width)
            let frame = NSRect(x: x, y: y, width: width, height: height)
            view.frame = frame
            view.isHidden = false
            frames[flat.id] = frame
            y = frame.maxY + NoteTheme.blockSpacing
        }
        overlayView.frame = bounds
    }

    func blockView(for id: NoteBlockID) -> NoteBlockView? { views[id] }

    func frame(of id: NoteBlockID) -> NSRect? { frames[id] }

    func blockID(at point: NSPoint) -> NoteBlockID? {
        frames.first { $0.value.insetBy(dx: -NoteTheme.gutterWidth, dy: -NoteTheme.blockSpacing).contains(point) }?.key
    }

    func textHost(for position: NotePosition) -> NoteTextHost? {
        views[position.block]?.textHost(for: position.field)
    }

    func scrollBlockToVisible(_ id: NoteBlockID) {
        guard let frame = frames[id] else { return }
        scrollToVisible(frame.insetBy(dx: 0, dy: -40))
    }

    var documentHeight: CGFloat { (frames.values.map(\.maxY).max() ?? 0) + 160 }
}
