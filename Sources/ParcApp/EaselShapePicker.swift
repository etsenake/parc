import AppKit

@MainActor
final class EaselShapePickerView: NSView, NoteFloatingPanelContent {
    static let cellSide: CGFloat = 34
    static let cellGap: CGFloat = 4
    static let padding: CGFloat = 10
    static let headerHeight: CGFloat = 22
    static let sectionGap: CGFloat = 8
    static let footerHeight: CGFloat = 34

    var preferredSizeDidChange: (() -> Void)?
    var onPick: ((EaselShape) -> Void)?
    var onCancel: (() -> Void)?
    var onPinChange: ((Bool) -> Void)?
    var checked: Set<EaselShape> = [] { didSet { if checked != oldValue { refreshChecks() } } }
    var isPinned = false { didSet { if isPinned != oldValue { refreshPin() } } }

    private var cells: [[EaselShapeCell]] = []
    private var headerFrames: [NSRect] = []
    private let plate = CALayer()
    private let pin = EaselPaletteButton(title: "", target: nil, action: nil)
    private var footerRect = NSRect.zero
    private(set) var highlighted: EaselShapeCatalog.Slot?
    private var highlightFromPointer = false
    private let showsPin: Bool

    init(checked: Set<EaselShape> = [], pinned: Bool = false, showsPin: Bool = true) {
        self.checked = checked
        isPinned = pinned
        self.showsPin = showsPin
        super.init(frame: .zero)
        wantsLayer = true
        plate.cornerRadius = NoteTheme.menuHighlightRadius + 2
        plate.cornerCurve = .continuous
        plate.opacity = 0
        layer?.addSublayer(plate)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Shapes")
        NoteAnimation.observeReduceMotion(self) { [weak self] in
            guard let self else { return }
            NoteAnimation.settle(self)
            self.cells.joined().forEach { $0.refreshSurface() }
        }
        pin.target = self; pin.action = #selector(togglePin)
        pin.setButtonType(.pushOnPushOff); pin.imagePosition = .imageOnly
        if showsPin { addSubview(pin) }
        build()
        refreshPin()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    static var gridWidth: CGFloat { CGFloat(EaselShapeCatalog.columns) * cellSide + CGFloat(EaselShapeCatalog.columns - 1) * cellGap }

    override var intrinsicContentSize: NSSize {
        let rows = EaselShapeCatalog.families.map { CGFloat(($0.shapes.count + EaselShapeCatalog.columns - 1) / EaselShapeCatalog.columns) }
        let grid = rows.reduce(0) { $0 + $1 * cellSideWithGap - Self.cellGap }
        let families = CGFloat(EaselShapeCatalog.families.count)
        let height = Self.padding + families * Self.headerHeight + grid + max(0, families - 1) * Self.sectionGap + 6 + Self.footerHeight
        return NSSize(width: Self.gridWidth + Self.padding * 2, height: ceil(height))
    }

    override var fittingSize: NSSize { intrinsicContentSize }

    private var cellSideWithGap: CGFloat { Self.cellSide + Self.cellGap }

    private func build() {
        var y = Self.padding
        for (family, value) in EaselShapeCatalog.families.enumerated() {
            headerFrames.append(NSRect(x: Self.padding + 1, y: y, width: Self.gridWidth, height: Self.headerHeight))
            y += Self.headerHeight
            var row: [EaselShapeCell] = []
            for (index, shape) in value.shapes.enumerated() {
                let cell = EaselShapeCell(shape: shape)
                let slot = EaselShapeCatalog.Slot(family: family, index: index)
                cell.onPress = { [weak self] in self?.pick(slot) }
                cell.onHover = { [weak self] inside in self?.pointerHover(slot, inside: inside) }
                cell.frame = NSRect(x: Self.padding + CGFloat(index % EaselShapeCatalog.columns) * cellSideWithGap,
                                    y: y + CGFloat(index / EaselShapeCatalog.columns) * cellSideWithGap,
                                    width: Self.cellSide, height: Self.cellSide)
                addSubview(cell)
                row.append(cell)
            }
            cells.append(row)
            let rows = CGFloat((value.shapes.count + EaselShapeCatalog.columns - 1) / EaselShapeCatalog.columns)
            y += rows * cellSideWithGap - Self.cellGap + Self.sectionGap
        }
        footerRect = NSRect(x: 0, y: y - Self.sectionGap + 6, width: Self.gridWidth + Self.padding * 2, height: Self.footerHeight)
        pin.frame = NSRect(x: footerRect.maxX - Self.padding - 26, y: (footerRect.midY - 13).rounded(), width: 26, height: 26)
        setFrameSize(intrinsicContentSize)
        refreshChecks()
    }

    private func refreshChecks() {
        for row in cells { for cell in row { cell.setChecked(checked == [cell.shape], animated: window != nil) } }
    }

    private func refreshPin() {
        pin.state = isPinned ? .on : .off
        pin.image = NSImage(systemSymbolName: isPinned ? "pin.fill" : "pin", accessibilityDescription: nil)
        pin.setEaselTooltip(isPinned ? "Stays open while you place shapes" : "Keep open to place several shapes")
        pin.setAccessibilityLabel("Keep open")
        pin.setAccessibilityValue(isPinned ? "On" : "Off")
    }

    @objc private func togglePin() {
        isPinned.toggle()
        onPinChange?(isPinned)
    }

    override func draw(_ dirtyRect: NSRect) {
        let header: [NSAttributedString.Key: Any] = [.font: NoteTheme.menuHeaderFont(), .foregroundColor: NoteTheme.menuSecondaryInk, .kern: 0.2]
        for (index, frame) in headerFrames.enumerated() where EaselShapeCatalog.families.indices.contains(index) {
            NSAttributedString(string: EaselShapeCatalog.families[index].title, attributes: header).draw(at: NSPoint(x: frame.minX, y: frame.minY + 2))
        }
        NoteTheme.menuSeparator.setFill()
        NSRect(x: 0, y: footerRect.minY, width: bounds.width, height: 1 / (window?.backingScaleFactor ?? 2)).fill()
        let title = highlighted.flatMap(EaselShapeCatalog.shape(at:)).map(EaselShapeGeometry.displayName) ?? "Pick a shape, any shape"
        let label = NSAttributedString(string: title, attributes: [.font: NoteTheme.nunitoBold(12.5), .foregroundColor: NoteTheme.menuSecondaryInk])
        label.draw(at: NSPoint(x: Self.padding + 1, y: (footerRect.midY - label.size().height / 2).rounded()))
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshPlateColor()
        needsDisplay = true
    }

    private func refreshPlateColor() {
        NoteAnimation.withoutAnimation { plate.backgroundColor = NoteTheme.resolved(NoteTheme.menuHighlight, in: self) }
    }

    private func cell(at slot: EaselShapeCatalog.Slot) -> EaselShapeCell? {
        guard cells.indices.contains(slot.family), cells[slot.family].indices.contains(slot.index) else { return nil }
        return cells[slot.family][slot.index]
    }

    func setHighlight(_ slot: EaselShapeCatalog.Slot?, animated: Bool) {
        let previous = highlighted
        highlighted = slot
        let chosen = slot.flatMap { cell(at: $0) }
        for row in cells { for cell in row { cell.isHighlighted = cell === chosen } }
        refreshPlateColor()
        if let target = chosen {
            let frame = target.frame.insetBy(dx: -2, dy: -2)
            if previous != nil, animated, plate.opacity > 0, !NoteAnimation.reduceMotion {
                NoteAnimation.slideLayer(plate, to: frame, spring: .glide)
            } else {
                NoteAnimation.withoutAnimation { plate.frame = frame }
                NoteAnimation.fade(plate, to: 1, duration: animated ? NoteAnimation.hoverDuration : 0)
            }
            NSAccessibility.post(element: target, notification: .focusedUIElementChanged)
        } else {
            NoteAnimation.fade(plate, to: 0, duration: animated ? NoteAnimation.hoverDuration : 0)
        }
        setNeedsDisplay(footerRect)
    }

    func prepare(origin: NoteMenuList.Origin) {
        highlightFromPointer = false
        guard origin == .keyboard else { setHighlight(nil, animated: false); return }
        let start = checked.count == 1 ? checked.first.flatMap(EaselShapeCatalog.slot(of:)) : nil
        setHighlight(start ?? EaselShapeCatalog.Slot(family: 0, index: 0), animated: false)
    }

    private func pointerHover(_ slot: EaselShapeCatalog.Slot, inside: Bool) {
        if inside {
            highlightFromPointer = true
            setHighlight(slot, animated: true)
        } else if highlightFromPointer, highlighted == slot {
            setHighlight(nil, animated: true)
        }
    }

    private func pick(_ slot: EaselShapeCatalog.Slot) {
        guard let shape = EaselShapeCatalog.shape(at: slot) else { return }
        onPick?(shape)
    }

    func handleKeyDown(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return false }
        func move(_ dx: Int, _ dy: Int) -> Bool {
            highlightFromPointer = false
            setHighlight(EaselShapeCatalog.move(from: highlighted, dx: dx, dy: dy), animated: true)
            return true
        }
        switch event.keyCode {
        case 123: return move(-1, 0)
        case 124: return move(1, 0)
        case 126: return move(0, -1)
        case 125: return move(0, 1)
        case 48: return move(event.modifierFlags.contains(.shift) ? -1 : 1, 0)
        case 36, 76, 49:
            guard let highlighted else { return false }
            pick(highlighted)
            return true
        case 53:
            onCancel?()
            return true
        default:
            return false
        }
    }

    override func accessibilityChildren() -> [Any]? {
        var children: [Any] = cells.joined().map { $0 }
        if showsPin { children.append(pin) }
        return children
    }

    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {}
}

@MainActor
private final class EaselShapeCell: NSView {
    let shape: EaselShape
    private(set) var isChecked = false
    var isHighlighted = false { didSet { if oldValue != isHighlighted { refreshSurface() } } }
    var onPress: (() -> Void)?
    var onHover: ((Bool) -> Void)?
    private var isPressed = false
    private let ring = EaselControlSurface.makeRing()

    init(shape: EaselShape) {
        self.shape = shape
        super.init(frame: NSRect(x: 0, y: 0, width: EaselShapePickerView.cellSide, height: EaselShapePickerView.cellSide))
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        layer?.addSublayer(ring)
        setEaselTooltip(EaselShapeGeometry.displayName(shape))
        setAccessibilityElement(true)
        setAccessibilityRole(.radioButton)
        setAccessibilityLabel(EaselShapeGeometry.displayName(shape))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func setChecked(_ checked: Bool, animated: Bool) {
        guard checked != isChecked else { return }
        isChecked = checked
        needsDisplay = true
        setAccessibilitySelected(checked)
        EaselControlSurface.setRing(ring, in: self, shown: checked, animated: animated)
    }

    func refreshSurface(released: Bool = false) {
        EaselControlSurface.apply(self, hovered: isHighlighted, pressed: isPressed, released: released)
    }

    override func layout() {
        super.layout()
        NoteAnimation.withoutAnimation { ring.frame = bounds.insetBy(dx: 0.75, dy: 0.75) }
    }

    override func draw(_ dirtyRect: NSRect) {
        let natural = EaselShapeGeometry.defaultSize(shape)
        let side = Double(bounds.width) - 12
        let scale = side / max(natural.width, natural.height)
        let width = natural.width * scale, height = natural.height * scale
        let frame = EaselRect(x: (Double(bounds.width) - width) / 2, y: (Double(bounds.height) - height) / 2, width: width, height: height)
        let ink = isChecked ? NoteTheme.checkedInk : NoteTheme.menuInk
        let outline = EaselShapeRendering.bezierPath(EaselShapeGeometry.outline(shape, in: frame))
        ink.withAlphaComponent(0.1).setFill(); outline.fill()
        outline.lineWidth = 1.5; outline.lineJoinStyle = .round
        ink.setStroke(); outline.stroke()
        let details = EaselShapeGeometry.details(shape, in: frame)
        if !details.isEmpty {
            let lines = EaselShapeRendering.bezierPath(details)
            lines.lineWidth = 1.5; lines.lineCapStyle = .round
            lines.stroke()
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
        NoteAnimation.withoutAnimation { ring.borderColor = NoteTheme.resolved(NoteTheme.checkedInk, in: self) }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas where area.owner === self { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .cursorUpdate, .activeInKeyWindow, .inVisibleRect],
                                       owner: self))
    }

    override func mouseEntered(with event: NSEvent) {
        onHover?(NoteFloatingPanel.allowsHover(for: self, at: event.locationInWindow))
    }

    override func mouseExited(with event: NSEvent) { onHover?(false) }

    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }
    override func cursorUpdate(with event: NSEvent) { NSCursor.pointingHand.set() }

    private func setPressed(_ pressed: Bool) {
        guard pressed != isPressed else { return }
        isPressed = pressed
        refreshSurface(released: !pressed)
    }

    override func mouseDown(with event: NSEvent) { setPressed(true) }

    override func mouseDragged(with event: NSEvent) {
        setPressed(bounds.contains(convert(event.locationInWindow, from: nil)))
    }

    override func mouseUp(with event: NSEvent) {
        let inside = bounds.contains(convert(event.locationInWindow, from: nil))
        setPressed(false)
        if inside { onPress?() }
    }

    override func accessibilityPerformPress() -> Bool {
        onPress?()
        return true
    }
}
