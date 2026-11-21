import AppKit

@MainActor
final class NoteCanvasOverlayView: NSView {
    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        return hit === self ? nil : hit
    }
}

@MainActor
final class NoteCanvasPassiveView: NSView {
    override var isFlipped: Bool { true }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

@MainActor
final class NoteCanvasDecorationView: NSView {
    enum Look: Equatable {
        case decoration(NoteCanvasDecoration.Style)
        case wash
    }

    var look: Look { didSet { if look != oldValue { needsDisplay = true } } }
    var spaceFocus: NSColor? { didSet { if look == .wash { needsDisplay = true } } }

    init(look: Look) {
        self.look = look
        super.init(frame: .zero)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
    override var wantsUpdateLayer: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    struct Paint {
        var fill: NSColor
        var border: NSColor?
        var radius: CGFloat
    }

    static func paint(for look: Look, spaceFocus: NSColor? = nil) -> Paint {
        switch look {
        case .wash:
            return Paint(fill: NoteTheme.blockSelectionWash(spaceFocus: spaceFocus), border: nil, radius: NoteTheme.blockRadius)
        case .decoration(.callout(let style)):
            switch style {
            case .background(let color)?: return Paint(fill: NoteTheme.color(.background(color)), border: nil, radius: NoteTheme.blockRadius)
            case .text?: return Paint(fill: .clear, border: NoteTheme.separator, radius: NoteTheme.blockRadius)
            case nil: return Paint(fill: NoteTheme.calloutFill, border: nil, radius: NoteTheme.blockRadius)
            }
        case .decoration(.background(let color)):
            return Paint(fill: NoteTheme.color(.background(color)), border: nil, radius: NoteTheme.blockRadius - 2)
        case .decoration(.quoteBar(let color)):
            return Paint(fill: color.map { NoteTheme.color(.text($0)) } ?? NoteTheme.quoteBar, border: nil, radius: 0)
        }
    }

    static func draw(_ style: NoteCanvasDecoration.Style, in rect: NSRect) {
        let paint = paint(for: .decoration(style))
        let path = NSBezierPath(roundedRect: rect, xRadius: paint.radius, yRadius: paint.radius)
        paint.fill.setFill()
        path.fill()
        guard let border = paint.border else { return }
        let inset = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: max(0, paint.radius - 0.5), yRadius: max(0, paint.radius - 0.5))
        inset.lineWidth = 1
        border.setStroke()
        inset.stroke()
    }

    override func updateLayer() {
        guard let layer else { return }
        layer.cornerCurve = .continuous
        let paint = Self.paint(for: look, spaceFocus: spaceFocus)
        layer.cornerRadius = paint.radius
        layer.backgroundColor = paint.fill.cgColor
        layer.borderWidth = paint.border == nil ? 0 : 1
        layer.borderColor = paint.border?.cgColor
    }
}

@MainActor
final class NoteCanvasDropIndicatorView: NSView {
    var spaceFocus: NSColor? { didSet { needsDisplay = true } }
    private(set) var target: NoteCanvasDropTarget?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        isHidden = true
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
    override var wantsUpdateLayer: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func updateLayer() {
        guard let layer else { return }
        layer.cornerCurve = .continuous
        layer.cornerRadius = NoteTheme.dropIndicatorThickness / 2
        layer.backgroundColor = NoteTheme.dropIndicator(spaceFocus: spaceFocus).cgColor
    }

    func show(_ next: NoteCanvasDropTarget?) {
        guard let layer else { return }
        guard let next else {
            guard target != nil else { return }
            target = nil
            NoteAnimation.fade(layer, to: 0, duration: NoteAnimation.hoverDuration, key: NoteAnimation.fadeKey) { [weak self] in
                guard let self, self.target == nil else { return }
                self.isHidden = true
            }
            return
        }
        let rect = next.lineRect(thickness: NoteTheme.dropIndicatorThickness).integral
        let wasShown = target != nil && !isHidden
        let turned = target.map { $0.isVertical != next.isVertical } ?? true
        target = next
        if !wasShown || turned {
            NoteAnimation.withoutAnimation {
                layer.removeAnimation(forKey: NoteAnimation.positionKey)
                layer.removeAnimation(forKey: NoteAnimation.boundsKey)
                frame = rect
            }
            isHidden = false
            NoteAnimation.fade(layer, to: 1, duration: NoteAnimation.hoverDuration, key: NoteAnimation.fadeKey)
            return
        }
        isHidden = false
        NoteAnimation.fade(layer, to: 1, duration: NoteAnimation.hoverDuration, key: NoteAnimation.fadeKey)
        guard frame != rect else { return }
        NoteAnimation.slide(self, to: rect, spring: .highlight)
    }
}

@MainActor
final class NoteCanvasSnapshotView: NSView {
    private let image: NSBitmapImageRep

    init?(capturing view: NSView) {
        let bounds = view.bounds
        guard bounds.width >= 1, bounds.height >= 1, bounds.width * bounds.height < 6_000_000,
              let rep = view.bitmapImageRepForCachingDisplay(in: bounds) else { return nil }
        view.cacheDisplay(in: bounds, to: rep)
        image = rep
        super.init(frame: view.frame)
        wantsLayer = true
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        image.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }
}

@MainActor
final class NoteCanvasColumnHandle: NSView {
    struct Key: Hashable {
        var columns: NoteBlockID
        var divider: Int
    }

    static let hitWidth: CGFloat = 12
    let key: Key
    weak var canvas: NotePageCanvasView?
    private let line = NoteCanvasPassiveView()
    private var tracking: NSTrackingArea?
    private var isHovered = false
    private var isDragging = false
    private var dragStart: CGFloat = 0

    init(key: Key, canvas: NotePageCanvasView) {
        self.key = key
        self.canvas = canvas
        super.init(frame: .zero)
        wantsLayer = true
        addSubview(line)
        line.layer?.cornerCurve = .continuous
        line.layer?.cornerRadius = 1
        line.alphaValue = 0
        setAccessibilityElement(true)
        setAccessibilityRole(.splitter)
        setAccessibilityLabel("Column divider")
        setAccessibilityHelp("Drag to resize the columns")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        line.frame = NSRect(x: (bounds.width - 2) / 2, y: 2, width: 2, height: max(0, bounds.height - 4))
        refreshLine()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshLine()
    }

    override func updateTrackingAreas() {
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .cursorUpdate, .activeInKeyWindow, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
        super.updateTrackingAreas()
    }

    override func cursorUpdate(with event: NSEvent) {
        if isDragging { NSCursor.resizeLeftRight.set(); return }
        if !applyNoteCursor(.resizeLeftRight, for: event) { super.cursorUpdate(with: event) }
    }

    override func mouseEntered(with event: NSEvent) { setHovered(NoteFloatingPanel.allowsHover(for: self, at: event.locationInWindow)) }

    override func mouseMoved(with event: NSEvent) {
        let allowed = NoteFloatingPanel.allowsHover(for: self, at: event.locationInWindow)
        setHovered(allowed)
        if allowed { NSCursor.resizeLeftRight.set() }
    }

    override func mouseExited(with event: NSEvent) { setHovered(false) }

    private func setHovered(_ hovered: Bool) {
        guard hovered != isHovered else { return }
        isHovered = hovered
        if !isDragging { setLineVisible(hovered) }
    }

    override func mouseDown(with event: NSEvent) {
        guard let canvas, canvas.beginColumnResize(key) else { return }
        isDragging = true
        dragStart = canvas.convert(event.locationInWindow, from: nil).x
        refreshLine()
        setLineVisible(true)
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDragging, let canvas else { return }
        canvas.updateColumnResize(delta: canvas.convert(event.locationInWindow, from: nil).x - dragStart)
    }

    override func mouseUp(with event: NSEvent) {
        guard isDragging else { return }
        isDragging = false
        canvas?.endColumnResize(commit: true)
        refreshLine()
        if !isHovered { setLineVisible(false) }
    }

    func cancelDrag() {
        guard isDragging else { return }
        isDragging = false
        canvas?.endColumnResize(commit: false)
        refreshLine()
        setLineVisible(isHovered)
    }

    private func setLineVisible(_ visible: Bool) {
        NoteAnimation.fade(line, visible: visible, duration: NoteAnimation.hoverDuration)
    }

    private func refreshLine() {
        let color = isDragging ? NoteTheme.dropIndicator(spaceFocus: canvas?.spaceFocus) : NoteTheme.dividerLine
        NoteAnimation.withoutAnimation {
            effectiveAppearance.performAsCurrentDrawingAppearance { line.layer?.backgroundColor = color.cgColor }
        }
    }
}
