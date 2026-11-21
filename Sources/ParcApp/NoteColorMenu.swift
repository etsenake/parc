import AppKit

@MainActor
final class NoteColorMenuView: NSView, NoteFloatingPanelContent {
    typealias Slot = (section: Int, index: Int)

    static let swatchSide: CGFloat = 28
    static let swatchGap: CGFloat = 5
    static let columns = 10
    static let padding: CGFloat = 10
    static let headerHeight: CGFloat = 22
    static let sectionGap: CGFloat = 8
    static let footerHeight: CGFloat = 34

    var preferredSizeDidChange: (() -> Void)?
    var onPick: ((NoteColorChoice) -> Void)?
    var onCancel: (() -> Void)?
    var model: NoteColorMenuModel { didSet { if model != oldValue { rebuild() } } }

    private var swatches: [[NoteColorSwatchView]] = []
    private var headerFrames: [NSRect] = []
    private let plate = CALayer()
    private let keycap = NoteKeycapLabel(NoteFormatShortcut.lastColor.display)
    private var footerRect = NSRect.zero
    private(set) var highlighted: Slot?
    private var highlightFromPointer = false

    init(model: NoteColorMenuModel) {
        self.model = model
        super.init(frame: .zero)
        wantsLayer = true
        plate.cornerRadius = NoteTheme.menuHighlightRadius + 2
        plate.cornerCurve = .continuous
        plate.opacity = 0
        layer?.addSublayer(plate)
        keycap.isHidden = true
        addSubview(keycap)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Color")
        rebuild()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    static var gridWidth: CGFloat { CGFloat(columns) * swatchSide + CGFloat(columns - 1) * swatchGap }

    override var intrinsicContentSize: NSSize {
        let rows = CGFloat(model.sections.count)
        let height = Self.padding + rows * (Self.headerHeight + Self.swatchSide) + max(0, rows - 1) * Self.sectionGap + 6 + Self.footerHeight
        return NSSize(width: Self.gridWidth + Self.padding * 2, height: ceil(height))
    }

    override var fittingSize: NSSize { intrinsicContentSize }

    var lastUsed: NoteColorChoice? { model.sections.first { $0.id == "recent" }?.choices.first }

    func choice(at slot: Slot) -> NoteColorChoice? {
        guard model.sections.indices.contains(slot.section), model.sections[slot.section].choices.indices.contains(slot.index) else { return nil }
        return model.sections[slot.section].choices[slot.index]
    }

    private func rebuild() {
        let keep = highlighted.flatMap(choice(at:))
        swatches.flatMap { $0 }.forEach { $0.removeFromSuperview() }
        swatches = model.sections.enumerated().map { section, value in
            value.choices.enumerated().map { index, choice in
                let swatch = NoteColorSwatchView(choice: choice)
                swatch.onPress = { [weak self] in self?.pick((section, index)) }
                swatch.onHover = { [weak self] inside in self?.pointerHover((section, index), inside: inside) }
                addSubview(swatch)
                return swatch
            }
        }
        var y = Self.padding
        headerFrames = []
        for (section, row) in swatches.enumerated() {
            headerFrames.append(NSRect(x: Self.padding + 1, y: y, width: Self.gridWidth, height: Self.headerHeight))
            y += Self.headerHeight
            for (index, swatch) in row.enumerated() {
                swatch.frame = NSRect(x: Self.padding + CGFloat(index) * (Self.swatchSide + Self.swatchGap), y: y,
                                      width: Self.swatchSide, height: Self.swatchSide)
                swatch.isChecked = model.isChecked(swatch.choice) && model.sections[section].id != "recent"
                swatch.setAccessibilityLabel(swatch.choice.title)
                swatch.setAccessibilityHelp(model.sections[section].id == "recent" ? "Last Used" : nil)
            }
            y += Self.swatchSide + Self.sectionGap
        }
        footerRect = NSRect(x: 0, y: y - Self.sectionGap + 6, width: Self.gridWidth + Self.padding * 2, height: Self.footerHeight)
        setFrameSize(intrinsicContentSize)
        if let keep, let slot = slot(of: keep) { setHighlight(slot, animated: false) } else { setHighlight(nil, animated: false) }
        layoutFooter()
        needsDisplay = true
        preferredSizeDidChange?()
    }

    private func slot(of choice: NoteColorChoice) -> Slot? {
        for (section, value) in model.sections.enumerated() {
            if let index = value.choices.firstIndex(of: choice) { return (section, index) }
        }
        return nil
    }

    private func layoutFooter() {
        let size = keycap.intrinsicContentSize
        keycap.frame = NSRect(x: footerRect.maxX - Self.padding - size.width, y: (footerRect.midY - size.height / 2).rounded(),
                              width: size.width, height: size.height)
        keycap.isHidden = footerText.showsKeycap == false
    }

    private var footerText: (text: String, showsKeycap: Bool) {
        if let slot = highlighted, let choice = choice(at: slot) {
            return (choice.title, choice == lastUsed && slot.section == 0)
        }
        if let lastUsed { return (lastUsed.title + " again", true) }
        return ("Pick a color, any color", false)
    }

    override func draw(_ dirtyRect: NSRect) {
        let header: [NSAttributedString.Key: Any] = [.font: NoteTheme.menuHeaderFont(), .foregroundColor: NoteTheme.menuSecondaryInk,
                                                     .kern: 0.2]
        for (index, frame) in headerFrames.enumerated() where model.sections.indices.contains(index) {
            let text = NSAttributedString(string: model.sections[index].title, attributes: header)
            text.draw(at: NSPoint(x: frame.minX, y: frame.minY + 2))
        }
        NoteTheme.menuSeparator.setFill()
        NSRect(x: 0, y: footerRect.minY, width: bounds.width, height: 1 / (window?.backingScaleFactor ?? 2)).fill()
        let footer = footerText
        let label = NSAttributedString(string: footer.text, attributes: [.font: NoteTheme.nunitoBold(12.5),
                                                                          .foregroundColor: NoteTheme.menuSecondaryInk])
        let size = label.size()
        label.draw(at: NSPoint(x: Self.padding + 1, y: (footerRect.midY - size.height / 2).rounded()))
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshPlateColor()
        needsDisplay = true
    }

    private func refreshPlateColor() {
        NoteAnimation.withoutAnimation { plate.backgroundColor = NoteTheme.resolved(NoteTheme.menuHighlight, in: self) }
    }

    func setHighlight(_ slot: Slot?, animated: Bool) {
        let previous = highlighted
        highlighted = slot
        for (section, row) in swatches.enumerated() {
            for (index, swatch) in row.enumerated() { swatch.isHighlighted = slot.map { $0.section == section && $0.index == index } ?? false }
        }
        refreshPlateColor()
        if let slot, swatches.indices.contains(slot.section), swatches[slot.section].indices.contains(slot.index) {
            let target = swatches[slot.section][slot.index].frame.insetBy(dx: -3, dy: -3)
            if previous != nil, animated, plate.opacity > 0 {
                NoteAnimation.slideLayer(plate, to: target, spring: .glide)
            } else {
                NoteAnimation.withoutAnimation { plate.frame = target }
                NoteAnimation.fade(plate, to: 1, duration: animated ? NoteAnimation.hoverDuration : 0)
            }
            NSAccessibility.post(element: swatches[slot.section][slot.index], notification: .focusedUIElementChanged)
        } else {
            NoteAnimation.fade(plate, to: 0, duration: animated ? NoteAnimation.hoverDuration : 0)
        }
        layoutFooter()
        setNeedsDisplay(footerRect)
    }

    func prepare(origin: NoteMenuList.Origin) {
        highlightFromPointer = false
        guard origin == .keyboard else { setHighlight(nil, animated: false); return }
        let checked = model.choices.first { model.isChecked($0.choice) && model.sections[$0.section].id != "recent" }
        setHighlight(checked.map { ($0.section, $0.index) } ?? (0, 0), animated: false)
    }

    private func pointerHover(_ slot: Slot, inside: Bool) {
        if inside {
            highlightFromPointer = true
            setHighlight(slot, animated: true)
        } else if highlightFromPointer, let current = highlighted, current == slot {
            setHighlight(nil, animated: true)
        }
    }

    private func pick(_ slot: Slot) {
        guard let choice = choice(at: slot) else { return }
        onPick?(choice)
    }

    func handleKeyDown(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .control, .option])
        guard modifiers.isEmpty else { return false }
        func move(_ dx: Int, _ dy: Int) -> Bool {
            highlightFromPointer = false
            setHighlight(model.move(from: highlighted, dx: dx, dy: dy), animated: true)
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

    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {}
}

@MainActor
private final class NoteColorSwatchView: NSView {
    let choice: NoteColorChoice
    var isChecked = false { didSet { if oldValue != isChecked { needsDisplay = true; setAccessibilitySelected(isChecked) } } }
    var isHighlighted = false
    var onPress: (() -> Void)?
    var onHover: ((Bool) -> Void)?
    private var isPressed = false
    private var isHovered = false

    init(choice: NoteColorChoice) {
        self.choice = choice
        super.init(frame: NSRect(x: 0, y: 0, width: NoteColorMenuView.swatchSide, height: NoteColorMenuView.swatchSide))
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        setAccessibilityElement(true)
        setAccessibilityRole(.radioButton)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let tile = bounds.insetBy(dx: 2, dy: 2)
        let radius: CGFloat = 6
        let path = NSBezierPath(roundedRect: tile, xRadius: radius, yRadius: radius)
        let font = NoteTheme.nunitoExtraBold(15)
        switch choice {
        case .background(let color?):
            NoteTheme.color(.background(color)).setFill()
            path.fill()
            NoteTheme.swatch(color).withAlphaComponent(0.28).setStroke()
            path.lineWidth = 1
            path.stroke()
            NoteIconRenderer.drawText("A", font: font, in: tile, color: NoteTheme.menuInk, decoration: [])
        case .background(nil):
            NoteTheme.menuFill.setFill()
            path.fill()
            NoteTheme.menuHairline.setStroke()
            path.lineWidth = 1
            path.stroke()
            NSGraphicsContext.saveGraphicsState()
            path.addClip()
            let slash = NSBezierPath()
            slash.move(to: NSPoint(x: tile.minX, y: tile.maxY))
            slash.line(to: NSPoint(x: tile.maxX, y: tile.minY))
            slash.lineWidth = 1
            slash.stroke()
            NSGraphicsContext.restoreGraphicsState()
            NoteIconRenderer.drawText("A", font: font, in: tile, color: NoteTheme.menuInk, decoration: [])
        case .text(let color):
            NoteTheme.menuHairline.setStroke()
            path.lineWidth = 1
            path.stroke()
            NoteIconRenderer.drawText("A", font: font, in: tile, color: color.map { NoteTheme.color(.text($0)) } ?? NoteTheme.menuInk,
                                      decoration: [])
        }
        if isChecked {
            let ring = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.75, dy: 0.75), xRadius: radius + 2, yRadius: radius + 2)
            ring.lineWidth = 1.5
            NoteTheme.checkedInk.setStroke()
            ring.stroke()
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas where area.owner === self { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .cursorUpdate, .activeInKeyWindow, .inVisibleRect],
                                       owner: self))
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = NoteFloatingPanel.allowsHover(for: self, at: event.locationInWindow)
        onHover?(isHovered)
        applyNoteCursor(.pointingHand, for: event)
    }

    override func mouseMoved(with event: NSEvent) {
        let hovered = NoteFloatingPanel.allowsHover(for: self, at: event.locationInWindow)
        if hovered != isHovered {
            isHovered = hovered
            onHover?(hovered)
        }
        applyNoteCursor(.pointingHand, for: event)
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        onHover?(false)
    }

    override func cursorUpdate(with event: NSEvent) {
        if !applyNoteCursor(.pointingHand, for: event) { super.cursorUpdate(with: event) }
    }

    private func setPressed(_ pressed: Bool) {
        guard pressed != isPressed, let layer else { return }
        isPressed = pressed
        let centre = NoteAnimation.layerPoint(NSPoint(x: bounds.midX, y: bounds.midY), in: self)
        let transform = pressed ? NoteAnimation.scaleTransform(NoteAnimation.pressedScale, about: centre) : CATransform3DIdentity
        NoteAnimation.spring(layer, "transform", to: NSValue(caTransform3D: transform), spring: .press,
                             key: NoteAnimation.keyPrefix + "swatch.press")
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
