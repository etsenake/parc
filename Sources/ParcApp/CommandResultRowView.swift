import AppKit

final class CommandResultRowView: NSTableRowView {
    var onPress: ((NSEvent) -> Bool)?
    private(set) var isHovered = false
    private var hover: NSTrackingArea?
    private var resignObserver: NSObjectProtocol?
    private var cells: [CommandResultCell] { subviews.compactMap { $0 as? CommandResultCell } }

    deinit { if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) } }
    override var isSelected: Bool {
        didSet { cells.forEach { $0.setSelected(isSelected) }; refreshHighlight() }
    }
    override func didAddSubview(_ subview: NSView) {
        super.didAddSubview(subview)
        if let cell = subview as? CommandResultCell {
            cell.setHovered(isHovered); cell.setSelected(isSelected)
        }
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hover { removeTrackingArea(hover) }
        setHovered(false)
        let area = NSTrackingArea(rect: .zero,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(area); hover = area
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        setHovered(false)
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        resignObserver = nil
        if let window {
            resignObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification,
                object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.setHovered(false) }
                }
        }
    }
    override func prepareForReuse() {
        setHovered(false); onPress = nil
        for cell in cells { cell.onPress = nil; cell.onDelete = nil }
        super.prepareForReuse()
    }
    private func containsPointer(_ event: NSEvent) -> Bool {
        guard let window, window.isKeyWindow, event.window === window,
              !isHiddenOrHasHiddenAncestor else { return false }
        return visibleRect.contains(convert(event.locationInWindow, from: nil))
    }
    private func setHovered(_ value: Bool) {
        guard isHovered != value else { return }
        isHovered = value; cells.forEach { $0.setHovered(value) }; refreshHighlight()
    }
    override func mouseEntered(with event: NSEvent) {
    }
    override func mouseMoved(with event: NSEvent) { setHovered(containsPointer(event)) }
    override func mouseExited(with event: NSEvent) {
        guard event.trackingArea === hover else { return }
        setHovered(false)
    }
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let hit = super.hitTest(point) else { return nil }
        var view: NSView? = hit
        while let current = view, current !== self {
            if current is NSControl && !(current is NSTextField) { return hit }
            view = current.superview
        }
        return self
    }
    override func mouseDown(with event: NSEvent) {
        guard event.type == .leftMouseDown, containsPointer(event) else { return }
        _ = onPress?(event)
    }
    var selectedColor: NSColor = CommandBarPalette.colourless.selected { didSet { refreshHighlight() } }
    let highlight = CALayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        highlight.cornerRadius = 6; highlight.cornerCurve = .continuous
        layer?.insertSublayer(highlight, at: 0)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var wantsUpdateLayer: Bool { true }
    override func layout() {
        super.layout()
        if let layer, highlight.superlayer !== layer { layer.insertSublayer(highlight, at: 0) }
        highlight.frame = bounds.insetBy(dx: 2, dy: 2)
    }
    override func updateLayer() { super.updateLayer(); refreshHighlight() }
    private func refreshHighlight() {
        let color: NSColor = isSelected ? selectedColor
            : isHovered ? CommandBarPalette.rowHover : .clear
        effectiveAppearance.performAsCurrentDrawingAppearance { highlight.backgroundColor = color.cgColor }
    }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance(); refreshHighlight()
    }
}
