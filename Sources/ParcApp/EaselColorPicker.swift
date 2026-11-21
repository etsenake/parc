import AppKit

@MainActor
final class EaselColorPicker: NSView, NoteFloatingPanelContent {
    enum Tile: Equatable {
        case color(EaselPaletteColor)
        case custom
        case sampler
        case fill(EaselFillMode)
        case opacity
        case weight(EaselStrokeWeight)
        case dash(EaselStrokeDash)
        case labelBackground
    }
    typealias Slot = (row: Int, index: Int)

    static let tileSide: CGFloat = 28
    static let gap: CGFloat = 5
    static let columns = 10
    static let padding: CGFloat = 10
    static let headerHeight: CGFloat = 22
    static let rowGap: CGFloat = 6
    static let sectionGap: CGFloat = 8
    static let footerHeight: CGFloat = 34
    static let lineTileWidth: CGFloat = 40
    static let customColorKey = "Parc.Easel.Style.CustomColor"
    static var gridWidth: CGFloat { CGFloat(columns) * tileSide + CGFloat(columns - 1) * gap }

    var preferredSizeDidChange: (() -> Void)?
    var onChange: ((EaselStyleChange) -> Void)?
    var onScrubChange: ((EaselStyleChange, UUID) -> Void)?
    var onCancel: (() -> Void)?
    var controls: EaselStyleControls { didSet { if controls != oldValue { rebuild() } } }
    var summary: EaselStyleSummary { didSet { if summary != oldValue { refreshState(popping: true) } } }

    private var rows: [[EaselColorPickerTile]] = []
    private var headers: [(title: String, frame: NSRect)] = []
    private let plate = CALayer()
    private let hexField = NoteSearchField(placeholder: "Hex code")
    private var footerRect = NSRect.zero
    private var contentHeight: CGFloat = 0
    private var customHex: String?
    private var shownCustom: String?
    private var notice: String?
    private(set) var highlighted: Slot?
    private var highlightFromPointer = false
    private var scrubGroup: UUID?
    private var scrubPreview: Double?

    init(controls: EaselStyleControls, summary: EaselStyleSummary = EaselStyleSummary()) {
        self.controls = controls
        self.summary = summary
        super.init(frame: .zero)
        wantsLayer = true
        plate.cornerRadius = NoteTheme.menuHighlightRadius + 2
        plate.cornerCurve = .continuous
        plate.opacity = 0
        layer?.addSublayer(plate)
        hexField.showsIcon = false
        hexField.textField.font = NoteTheme.nunitoBold(12.5)
        hexField.onSubmit = { [weak self] text in self?.submitHex(text) }
        hexField.onChange = { [weak self] _ in self?.showNotice(nil) }
        hexField.onCommand = { [weak self] selector in
            guard selector == #selector(NSResponder.cancelOperation(_:)) else { return false }
            self?.onCancel?()
            return true
        }
        addSubview(hexField)
        hexField.textField.setAccessibilityLabel("Custom color hex code")
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Style")
        rebuild()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: Self.gridWidth + Self.padding * 2, height: ceil(contentHeight)) }
    override var fittingSize: NSSize { intrinsicContentSize }

    private var textOnly: Bool { controls.colorRole == .ink && !controls.fill && controls.weights.isEmpty && !controls.dash }
    private var isDark: Bool { NoteTheme.isDark(effectiveAppearance) }

    func tile(at slot: Slot) -> Tile? { view(at: slot)?.tile }

    private func view(at slot: Slot) -> EaselColorPickerTile? {
        guard rows.indices.contains(slot.row), rows[slot.row].indices.contains(slot.index) else { return nil }
        return rows[slot.row][slot.index]
    }

    private func slot(of tile: Tile) -> Slot? {
        for (row, views) in rows.enumerated() {
            if let index = views.firstIndex(where: { $0.tile == tile }) { return (row, index) }
        }
        return nil
    }

    private func slot(of view: EaselColorPickerTile) -> Slot? {
        for (row, views) in rows.enumerated() {
            if let index = views.firstIndex(where: { $0 === view }) { return (row, index) }
        }
        return nil
    }

    private func rebuild() {
        let keep = highlighted.flatMap(tile(at:))
        rows.flatMap { $0 }.forEach { $0.removeFromSuperview() }
        rows = []
        headers = []
        var y = Self.padding
        func header(_ title: String) {
            headers.append((title, NSRect(x: Self.padding + 1, y: y, width: Self.gridWidth, height: Self.headerHeight)))
            y += Self.headerHeight
        }
        func frame(_ x: CGFloat, _ width: CGFloat) -> NSRect { NSRect(x: x, y: y, width: width, height: Self.tileSide) }
        header("Color")
        rows.append(controls.colors.enumerated().map { index, color in
            make(.color(color), frame: frame(Self.padding + CGFloat(index) * (Self.tileSide + Self.gap), Self.tileSide))
        })
        y += Self.tileSide + Self.rowGap
        rows.append([make(.custom, frame: frame(Self.padding, Self.tileSide)),
                     make(.sampler, frame: frame(Self.padding + Self.tileSide + Self.gap, Self.tileSide))])
        let fieldX = Self.padding + 2 * (Self.tileSide + Self.gap)
        hexField.frame = frame(fieldX, min(150, Self.padding + Self.gridWidth - fieldX))
        y += Self.tileSide
        if controls.labelBackground {
            y += Self.rowGap
            rows.append([make(.labelBackground, frame: frame(Self.padding, 160))])
            y += Self.tileSide
        }
        if controls.fill {
            y += Self.sectionGap
            header("Fill")
            let width = (Self.gridWidth - 2 * Self.gap) / 3
            rows.append(EaselFillMode.allCases.enumerated().map { index, mode in
                make(.fill(mode), frame: frame(Self.padding + CGFloat(index) * (width + Self.gap), width))
            })
            y += Self.tileSide + Self.rowGap
            rows.append([make(.opacity, frame: frame(Self.padding, Self.gridWidth))])
            y += Self.tileSide
        }
        if !controls.weights.isEmpty || controls.dash {
            y += Self.sectionGap
            header(controls.lineTitle)
            var x = Self.padding
            var line: [EaselColorPickerTile] = []
            for weight in controls.weights {
                line.append(make(.weight(weight), frame: frame(x, Self.lineTileWidth)))
                x += Self.lineTileWidth + Self.gap
            }
            if controls.dash {
                if !controls.weights.isEmpty { x += 12 }
                for dash in EaselStrokeDash.allCases {
                    line.append(make(.dash(dash), frame: frame(x, Self.lineTileWidth)))
                    x += Self.lineTileWidth + Self.gap
                }
            }
            rows.append(line)
            y += Self.tileSide
        }
        footerRect = NSRect(x: 0, y: y + 6, width: Self.gridWidth + Self.padding * 2, height: Self.footerHeight)
        contentHeight = footerRect.maxY
        setFrameSize(intrinsicContentSize)
        refreshState(popping: false)
        setHighlight(keep.flatMap { slot(of: $0) }, animated: false)
        needsDisplay = true
        preferredSizeDidChange?()
    }

    private func make(_ tile: Tile, frame: NSRect) -> EaselColorPickerTile {
        let view = EaselColorPickerTile(tile: tile, role: controls.colorRole, glyph: textOnly)
        view.frame = frame
        view.onPress = { [weak self, weak view] in
            guard let self, let view else { return }
            self.activate(view)
        }
        view.onHover = { [weak self, weak view] inside in
            guard let self, let view else { return }
            self.pointerHover(view, inside: inside)
        }
        view.onScrub = { [weak self] value, finished in self?.scrub(value, finished: finished) }
        addSubview(view)
        return view
    }

    private func refreshState(popping: Bool) {
        if case .custom(let hex)? = summary.color { shownCustom = hex }
        customHex = shownCustom ?? UserDefaults.standard.string(forKey: Self.customColorKey).flatMap(EaselPalette.normalized)
        for view in rows.flatMap({ $0 }) {
            let checked: Bool
            switch view.tile {
            case .color(let color): checked = summary.color == .palette(color)
            case .custom:
                view.customHex = customHex
                if case .custom? = summary.color { checked = true } else { checked = false }
            case .sampler: checked = false
            case .fill(let mode): checked = summary.fill == mode
            case .opacity:
                view.opacity = summary.fillOpacity
                checked = false
            case .weight(let weight): checked = summary.weight == weight
            case .dash(let dash): checked = summary.dash == dash
            case .labelBackground: checked = summary.labelBackground == true
            }
            if popping, checked, !view.isChecked { _ = NoteAnimation.pop(view) }
            view.isChecked = checked
            view.setAccessibilityLabel(title(for: view))
        }
        setNeedsDisplay(footerRect)
    }

    private func title(for view: EaselColorPickerTile) -> String {
        switch view.tile {
        case .color(let color): return color.title(dark: isDark)
        case .custom: return view.customHex.map { "Custom " + $0 } ?? "Custom Color"
        case .sampler: return "Pick from Screen"
        case .fill(let mode): return mode.title
        case .opacity: return "Opacity"
        case .weight(let weight):
            if weight == .none { return "No Outline" }
            return weight.title + (controls.lineTitle == "Outline" ? " Outline" : " Line")
        case .dash(let dash): return dash.rawValue.capitalized + (controls.lineTitle == "Outline" ? " Outline" : " Line")
        case .labelBackground: return "Label Background"
        }
    }

    private var footerText: String {
        if let notice { return notice }
        if let slot = highlighted, let view = view(at: slot) {
            switch view.tile {
            case .opacity: return view.valueText == "Mixed" ? "Mixed Opacity" : "Opacity " + view.valueText
            case .custom: return title(for: view) + " · type # for another"
            default: return title(for: view)
            }
        }
        return "Pick a color, any color"
    }

    private func showNotice(_ text: String?) {
        guard notice != text else { return }
        notice = text
        setNeedsDisplay(footerRect)
    }

    override func draw(_ dirtyRect: NSRect) {
        let header: [NSAttributedString.Key: Any] = [.font: NoteTheme.menuHeaderFont(), .foregroundColor: NoteTheme.menuSecondaryInk, .kern: 0.2]
        for item in headers {
            NSAttributedString(string: item.title, attributes: header).draw(at: NSPoint(x: item.frame.minX, y: item.frame.minY + 2))
        }
        NoteTheme.menuSeparator.setFill()
        NSRect(x: 0, y: footerRect.minY, width: bounds.width, height: 1 / (window?.backingScaleFactor ?? 2)).fill()
        let ink = notice == nil ? NoteTheme.menuSecondaryInk : NoteTheme.destructiveInk
        let label = NSAttributedString(string: footerText, attributes: [.font: NoteTheme.nunitoBold(12.5), .foregroundColor: ink])
        let size = label.size()
        label.draw(at: NSPoint(x: Self.padding + 1, y: (footerRect.midY - size.height / 2).rounded()))
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshPlateColor()
        refreshState(popping: false)
        needsDisplay = true
    }

    private func refreshPlateColor() {
        NoteAnimation.withoutAnimation { plate.backgroundColor = NoteTheme.resolved(NoteTheme.menuHighlight, in: self) }
    }

    func setHighlight(_ slot: Slot?, animated: Bool) {
        let previous = highlighted
        highlighted = slot
        for (row, views) in rows.enumerated() {
            for (index, view) in views.enumerated() { view.isHighlighted = slot.map { $0.row == row && $0.index == index } ?? false }
        }
        refreshPlateColor()
        if let slot, let view = view(at: slot) {
            let target = view.frame.insetBy(dx: -3, dy: -3)
            if previous != nil, animated, plate.opacity > 0 {
                NoteAnimation.slideLayer(plate, to: target, spring: .glide)
            } else {
                NoteAnimation.withoutAnimation { plate.frame = target }
                NoteAnimation.fade(plate, to: 1, duration: animated ? NoteAnimation.hoverDuration : 0)
            }
            NSAccessibility.post(element: view, notification: .focusedUIElementChanged)
        } else {
            NoteAnimation.fade(plate, to: 0, duration: animated ? NoteAnimation.hoverDuration : 0)
        }
        setNeedsDisplay(footerRect)
    }

    func prepare(origin: NoteMenuList.Origin) {
        highlightFromPointer = false
        guard origin == .keyboard else { setHighlight(nil, animated: false); return }
        let checked = rows.enumerated().lazy.compactMap { row, views in
            views.firstIndex { $0.isChecked }.map { (row, $0) }
        }.first
        setHighlight(checked ?? (0, 0), animated: false)
    }

    func focusHexField() { hexField.focus() }

    private func pointerHover(_ view: EaselColorPickerTile, inside: Bool) {
        guard let slot = slot(of: view) else { return }
        if inside {
            highlightFromPointer = true
            setHighlight(slot, animated: true)
        } else if highlightFromPointer, let current = highlighted, current == slot {
            setHighlight(nil, animated: true)
        }
    }

    private func activate(_ view: EaselColorPickerTile) {
        showNotice(nil)
        switch view.tile {
        case .color(let color): onChange?(.color(.palette(color)))
        case .custom:
            if let hex = view.customHex { onChange?(.color(.custom(hex))) }
            editHex(seed: nil)
        case .sampler: sample()
        case .fill(let mode): onChange?(.fill(mode))
        case .opacity: break
        case .weight(let weight): onChange?(.weight(weight))
        case .dash(let dash): onChange?(.dash(dash))
        case .labelBackground: onChange?(.labelBackground(summary.labelBackground != true))
        }
    }

    private func scrub(_ value: Double, finished: Bool) {
        setNeedsDisplay(footerRect)
        guard let onScrubChange else {
            if finished { onChange?(.fillOpacity(value)) }
            return
        }
        let group = scrubGroup ?? UUID()
        if finished {
            scrubGroup = nil; scrubPreview = nil
            onScrubChange(.fillOpacity(value), group)
            return
        }
        let shown = (value * 100).rounded() / 100
        guard shown != scrubPreview else { return }
        scrubGroup = group; scrubPreview = shown
        onScrubChange(.fillOpacity(shown), group)
    }

    private func editHex(seed: String?) {
        hexField.focus()
        if let seed {
            hexField.text = seed
            hexField.textField.currentEditor()?.selectedRange = NSRange(location: (seed as NSString).length, length: 0)
        } else {
            if hexField.text.isEmpty, let customHex { hexField.text = customHex }
            hexField.textField.currentEditor()?.selectAll(nil)
        }
    }

    private func submitHex(_ text: String) {
        guard let hex = EaselPalette.parseHex(text) else {
            showNotice("That’s not a hex color. Try #2C6C91.")
            return
        }
        hexField.text = hex
        choose(custom: hex)
    }

    private func choose(custom hex: String) {
        UserDefaults.standard.set(hex, forKey: Self.customColorKey)
        customHex = hex
        shownCustom = hex
        onChange?(.color(.custom(hex)))
        refreshState(popping: true)
    }

    private func sample() {
        NSColorSampler().show { [weak self] color in
            DispatchQueue.main.async {
                guard let self, let color, let hex = (try? EaselRichTextCodec.hex(color)).flatMap({ EaselPalette.normalized(String($0.prefix(7))) })
                else { return }
                self.hexField.text = hex
                self.choose(custom: hex)
            }
        }
    }

    func handleKeyDown(_ event: NSEvent) -> Bool {
        guard hexField.textField.currentEditor() == nil else { return false }
        let modifiers = event.modifierFlags.intersection([.command, .control, .option])
        guard modifiers.isEmpty else { return false }
        if let slot = highlighted, tile(at: slot) == .opacity, event.keyCode == 123 || event.keyCode == 124 {
            onChange?(.fillOpacity(EaselColorPickerTile.stepped(summary.fillOpacity ?? 1, up: event.keyCode == 124)))
            return true
        }
        if let typed = event.charactersIgnoringModifiers, typed.count == 1, typed == "#" {
            editHex(seed: "#")
            return true
        }
        switch event.keyCode {
        case 123: return move(by: -1)
        case 124: return move(by: 1)
        case 126: return moveRow(by: -1)
        case 125: return moveRow(by: 1)
        case 48: return move(by: event.modifierFlags.contains(.shift) ? -1 : 1)
        case 36, 76, 49:
            guard let slot = highlighted, let view = view(at: slot) else { return false }
            activate(view)
            return true
        case 53:
            onCancel?()
            return true
        default:
            return false
        }
    }

    private func move(by step: Int) -> Bool {
        let flat = rows.enumerated().flatMap { row, views in views.indices.map { (row, $0) } }
        guard !flat.isEmpty else { return false }
        highlightFromPointer = false
        guard let current = highlighted, let position = flat.firstIndex(where: { $0.0 == current.row && $0.1 == current.index }) else {
            let first = step < 0 ? flat[flat.count - 1] : flat[0]
            setHighlight((first.0, first.1), animated: true)
            return true
        }
        let next = flat[(position + step + flat.count * 2) % flat.count]
        setHighlight((next.0, next.1), animated: true)
        return true
    }

    private func moveRow(by step: Int) -> Bool {
        guard !rows.isEmpty else { return false }
        highlightFromPointer = false
        guard let current = highlighted, let origin = view(at: current) else {
            setHighlight((step < 0 ? rows.count - 1 : 0, 0), animated: true)
            return true
        }
        let row = (current.row + step + rows.count) % rows.count
        let targets = rows[row]
        guard let index = targets.indices.min(by: { abs(targets[$0].frame.midX - origin.frame.midX) < abs(targets[$1].frame.midX - origin.frame.midX) })
        else { return false }
        setHighlight((row, index), animated: true)
        return true
    }

    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {}
}

@MainActor
private final class EaselColorPickerTile: NSView {
    let tile: EaselColorPicker.Tile
    let role: EaselColorRole
    let glyph: Bool
    var customHex: String? { didSet { if oldValue != customHex { needsDisplay = true } } }
    var opacity: Double? { didSet { if oldValue != opacity { needsDisplay = true; refreshValue() } } }
    var isChecked = false { didSet { if oldValue != isChecked { needsDisplay = true; setAccessibilitySelected(isChecked) } } }
    var isHighlighted = false { didSet { if oldValue != isHighlighted { needsDisplay = true } } }
    var onPress: (() -> Void)?
    var onHover: ((Bool) -> Void)?
    var onScrub: ((Double, Bool) -> Void)?
    private var isPressed = false
    private var scrubbing: Double?

    init(tile: EaselColorPicker.Tile, role: EaselColorRole, glyph: Bool) {
        self.tile = tile
        self.role = role
        self.glyph = glyph
        super.init(frame: .zero)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        setAccessibilityElement(true)
        switch tile {
        case .sampler: setAccessibilityRole(.button)
        case .opacity: setAccessibilityRole(.slider); refreshValue()
        case .labelBackground: setAccessibilityRole(.checkBox)
        default: setAccessibilityRole(.radioButton)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    var displayedOpacity: Double { scrubbing ?? opacity ?? 1 }
    var valueText: String { opacity == nil && scrubbing == nil ? "Mixed" : Self.percent(displayedOpacity) }

    static func percent(_ value: Double) -> String { String(Int((value * 100).rounded())) + "%" }

    static func stepped(_ value: Double, up: Bool) -> Double {
        let tenths = value * 10
        let next = up ? (tenths + 0.0001).rounded(.down) + 1 : (tenths - 0.0001).rounded(.up) - 1
        return min(1, max(0, next / 10))
    }

    private var trackRect: NSRect { NSRect(x: 78, y: bounds.midY - 2, width: max(40, bounds.width - 78 - 56), height: 4) }

    private var ink: NSColor {
        isChecked ? NoteTheme.checkedInk : isHighlighted || isPressed ? NoteTheme.menuInk : NoteTheme.menuSecondaryInk
    }

    override func draw(_ dirtyRect: NSRect) {
        switch tile {
        case .color(let color):
            drawSwatch(EaselInk.color(EaselPalette.stored(color, role: role), adaptive: true, role: role))
        case .custom:
            if let customHex { drawSwatch(EaselInk.fixed(customHex)) } else { drawEmptyCustom() }
        case .sampler:
            NoteIconRenderer.draw(.symbol("eyedropper"), in: bounds, tint: ink, pointSize: 14)
        case .fill(let mode):
            drawCheckedPlate()
            drawFillIcon(mode, in: NSRect(x: 10, y: bounds.midY - 7, width: 14, height: 14))
            drawLabel(mode.title, x: 32)
        case .opacity:
            drawOpacity()
        case .weight(let weight):
            drawCheckedPlate()
            drawWeight(weight)
        case .dash(let dash):
            drawCheckedPlate()
            drawDash(dash)
        case .labelBackground:
            drawLabelBackground()
        }
    }

    private func drawLabelBackground() {
        let box = NSRect(x: 8, y: bounds.midY - 7, width: 14, height: 14)
        let path = NSBezierPath(roundedRect: box.insetBy(dx: 0.75, dy: 0.75), xRadius: 4, yRadius: 4)
        if isChecked {
            NoteTheme.todoCheckFill.setFill(); path.fill()
            let tick = NSBezierPath()
            tick.move(to: NSPoint(x: box.minX + 3.5, y: box.midY))
            tick.line(to: NSPoint(x: box.minX + 6, y: box.maxY - 3.5))
            tick.line(to: NSPoint(x: box.maxX - 3, y: box.minY + 3.5))
            tick.lineWidth = 1.75; tick.lineCapStyle = .round; tick.lineJoinStyle = .round
            NoteTheme.menuFill.setStroke(); tick.stroke()
        } else {
            path.lineWidth = 1.5; NoteTheme.todoBox.setStroke(); path.stroke()
        }
        drawLabel("Label Background", x: 30)
    }

    private func drawSwatch(_ color: NSColor) {
        let tileRect = bounds.insetBy(dx: 2, dy: 2)
        switch role {
        case .ink:
            if glyph {
                let path = NSBezierPath(roundedRect: tileRect, xRadius: 6, yRadius: 6)
                NoteTheme.menuHairline.setStroke(); path.lineWidth = 1; path.stroke()
                NoteIconRenderer.drawText("A", font: NoteTheme.nunitoExtraBold(15), in: tileRect, color: color, decoration: [])
            } else {
                let dot = NSRect(x: bounds.midX - 8, y: bounds.midY - 8, width: 16, height: 16)
                color.setFill(); NSBezierPath(ovalIn: dot).fill()
                let ring = NSBezierPath(ovalIn: dot.insetBy(dx: 0.5, dy: 0.5))
                NoteTheme.menuHairline.setStroke(); ring.lineWidth = 1; ring.stroke()
            }
        case .fill, .sticky:
            let paper = tileRect.insetBy(dx: 1, dy: 1)
            let path = NSBezierPath(roundedRect: paper, xRadius: role == .sticky ? 3 : 5, yRadius: role == .sticky ? 3 : 5)
            color.setFill(); path.fill()
            if role == .sticky {
                let fold = NSBezierPath()
                fold.move(to: NSPoint(x: paper.maxX - 7, y: paper.maxY))
                fold.line(to: NSPoint(x: paper.maxX, y: paper.maxY - 7))
                fold.line(to: NSPoint(x: paper.maxX - 7, y: paper.maxY - 7))
                fold.close()
                NoteTheme.pressedFill.setFill(); fold.fill()
            }
            NoteTheme.menuHairline.setStroke(); path.lineWidth = 1; path.stroke()
        case .highlight:
            let bar = NSRect(x: bounds.midX - 10, y: bounds.midY - 5, width: 20, height: 10)
            color.withAlphaComponent(0.75).setFill()
            NSBezierPath(roundedRect: bar, xRadius: 5, yRadius: 5).fill()
        }
        if isChecked {
            let ring = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.75, dy: 0.75), xRadius: 8, yRadius: 8)
            ring.lineWidth = 1.5
            NoteTheme.checkedInk.setStroke(); ring.stroke()
        }
    }

    private func drawEmptyCustom() {
        let tileRect = bounds.insetBy(dx: 3, dy: 3)
        let path = NSBezierPath(roundedRect: tileRect, xRadius: 6, yRadius: 6)
        path.lineWidth = 1
        path.setLineDash([2.5, 2.5], count: 2, phase: 0)
        NoteTheme.menuHairline.setStroke(); path.stroke()
        NoteIconRenderer.draw(.symbol("plus"), in: bounds, tint: ink, pointSize: 11)
    }

    private func drawCheckedPlate() {
        guard isChecked else { return }
        NoteTheme.checkedFill.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: NoteTheme.controlRadius, yRadius: NoteTheme.controlRadius).fill()
    }

    private func drawLabel(_ text: String, x: CGFloat) {
        let label = NSAttributedString(string: text, attributes: [.font: NoteTheme.nunitoBold(12.5), .foregroundColor: ink])
        let size = label.size()
        label.draw(at: NSPoint(x: x, y: (bounds.midY - size.height / 2).rounded()))
    }

    private func drawFillIcon(_ mode: EaselFillMode, in rect: NSRect) {
        let path = NSBezierPath(roundedRect: rect.insetBy(dx: 0.75, dy: 0.75), xRadius: 3.5, yRadius: 3.5)
        switch mode {
        case .none:
            NSGraphicsContext.saveGraphicsState()
            path.addClip()
            let slash = NSBezierPath()
            slash.move(to: NSPoint(x: rect.minX, y: rect.maxY)); slash.line(to: NSPoint(x: rect.maxX, y: rect.minY))
            slash.lineWidth = 1.25; ink.setStroke(); slash.stroke()
            NSGraphicsContext.restoreGraphicsState()
        case .transparent:
            ink.withAlphaComponent(0.3).setFill(); path.fill()
        case .solid:
            ink.setFill(); path.fill()
        }
        path.lineWidth = 1.5; ink.setStroke(); path.stroke()
    }

    private func drawWeight(_ weight: EaselStrokeWeight) {
        let line = NSBezierPath()
        line.move(to: NSPoint(x: bounds.midX - 11, y: bounds.midY)); line.line(to: NSPoint(x: bounds.midX + 11, y: bounds.midY))
        line.lineCapStyle = .round
        switch weight {
        case .none:
            line.lineWidth = 1.5
            line.setLineDash([1.5, 3], count: 2, phase: 0)
            ink.withAlphaComponent(0.6).setStroke(); line.stroke()
            let slash = NSBezierPath()
            slash.move(to: NSPoint(x: bounds.midX - 6, y: bounds.midY + 6)); slash.line(to: NSPoint(x: bounds.midX + 6, y: bounds.midY - 6))
            slash.lineWidth = 1.5; slash.lineCapStyle = .round; ink.setStroke(); slash.stroke()
        case .thin: line.lineWidth = 1.5; ink.setStroke(); line.stroke()
        case .medium: line.lineWidth = 3; ink.setStroke(); line.stroke()
        case .thick: line.lineWidth = 5.5; ink.setStroke(); line.stroke()
        }
    }

    private func drawDash(_ dash: EaselStrokeDash) {
        let line = NSBezierPath()
        line.move(to: NSPoint(x: bounds.midX - 12, y: bounds.midY)); line.line(to: NSPoint(x: bounds.midX + 12, y: bounds.midY))
        line.lineWidth = 2.5; line.lineCapStyle = .round
        switch dash {
        case .solid: break
        case .dashed: line.setLineDash([3.5, 5.5], count: 2, phase: 0)
        case .dotted: line.setLineDash([0, 5], count: 2, phase: 0)
        }
        ink.setStroke(); line.stroke()
    }

    private func drawOpacity() {
        let title = NSAttributedString(string: "Opacity", attributes: [.font: NoteTheme.nunitoBold(12.5), .foregroundColor: ink])
        title.draw(at: NSPoint(x: 8, y: (bounds.midY - title.size().height / 2).rounded()))
        let track = trackRect, value = displayedOpacity
        NoteTheme.fieldFill.setFill()
        NSBezierPath(roundedRect: track, xRadius: 2, yRadius: 2).fill()
        var filled = track
        filled.size.width = track.width * CGFloat(value)
        NoteTheme.accent.setFill()
        NSBezierPath(roundedRect: filled, xRadius: 2, yRadius: 2).fill()
        let knob = NSRect(x: track.minX + track.width * CGFloat(value) - 7, y: bounds.midY - 7, width: 14, height: 14)
        NoteTheme.menuFill.setFill(); NSBezierPath(ovalIn: knob).fill()
        let ring = NSBezierPath(ovalIn: knob.insetBy(dx: 0.5, dy: 0.5))
        NoteTheme.menuHairline.setStroke(); ring.lineWidth = 1; ring.stroke()
        let label = NSAttributedString(string: valueText, attributes: [.font: NoteTheme.nunitoBold(12.5), .foregroundColor: NoteTheme.menuSecondaryInk])
        let size = label.size()
        label.draw(at: NSPoint(x: bounds.maxX - 8 - size.width, y: (bounds.midY - size.height / 2).rounded()))
    }

    private func refreshValue() {
        guard tile == .opacity else { return }
        let previous = accessibilityValue() as? String
        setAccessibilityLabel("Opacity")
        setAccessibilityValue(valueText)
        if let previous, previous != valueText { NSAccessibility.post(element: self, notification: .valueChanged) }
    }

    private func grabsTrack(_ event: NSEvent) -> Bool {
        let point = convert(event.locationInWindow, from: nil)
        return trackRect.insetBy(dx: -10, dy: -10).contains(point)
    }

    private func scrubValue(_ event: NSEvent) -> Double {
        let x = convert(event.locationInWindow, from: nil).x
        let track = trackRect
        return Double(min(1, max(0, (x - track.minX) / max(1, track.width))) * 20).rounded() / 20
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas where area.owner === self { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .cursorUpdate, .activeInKeyWindow, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { onHover?(NoteFloatingPanel.allowsHover(for: self, at: event.locationInWindow)) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }
    override func cursorUpdate(with event: NSEvent) { NSCursor.pointingHand.set() }

    private func setPressed(_ pressed: Bool) {
        guard pressed != isPressed, let layer else { return }
        isPressed = pressed
        needsDisplay = true
        guard tile != .opacity else { return }
        let centre = NoteAnimation.layerPoint(NSPoint(x: bounds.midX, y: bounds.midY), in: self)
        let transform = pressed ? NoteAnimation.scaleTransform(NoteAnimation.pressedScale, about: centre) : CATransform3DIdentity
        NoteAnimation.spring(layer, "transform", to: NSValue(caTransform3D: transform), spring: .press, key: NoteAnimation.keyPrefix + "easel.style.press")
    }

    override func mouseDown(with event: NSEvent) {
        if tile == .opacity {
            guard grabsTrack(event) else { return }
            scrubbing = scrubValue(event); needsDisplay = true; refreshValue()
            onScrub?(displayedOpacity, false)
            return
        }
        setPressed(true)
    }

    override func mouseDragged(with event: NSEvent) {
        if tile == .opacity {
            guard scrubbing != nil else { return }
            scrubbing = scrubValue(event); needsDisplay = true; refreshValue()
            onScrub?(displayedOpacity, false)
            return
        }
        setPressed(bounds.contains(convert(event.locationInWindow, from: nil)))
    }

    override func mouseUp(with event: NSEvent) {
        if tile == .opacity {
            guard scrubbing != nil else { return }
            let value = scrubValue(event)
            scrubbing = nil
            needsDisplay = true; refreshValue()
            onScrub?(value, true)
            return
        }
        let inside = bounds.contains(convert(event.locationInWindow, from: nil))
        setPressed(false)
        if inside { onPress?() }
    }

    override func accessibilityPerformPress() -> Bool {
        guard tile != .opacity else { return false }
        onPress?()
        return true
    }

    override func accessibilityPerformIncrement() -> Bool { step(by: 0.1) }
    override func accessibilityPerformDecrement() -> Bool { step(by: -0.1) }

    private func step(by amount: Double) -> Bool {
        guard tile == .opacity else { return false }
        onScrub?(Self.stepped(displayedOpacity, up: amount > 0), true)
        return true
    }
}

extension EaselCanvasView {
    func makeStylePicker() -> EaselColorPicker? {
        guard let controls = styleControls else { return nil }
        let picker = EaselColorPicker(controls: controls, summary: styleSummary)
        picker.onChange = { [weak self, weak picker] change in
            guard let self, let picker else { return }
            self.applyStyle(change)
            if let controls = self.styleControls { picker.controls = controls }
            picker.summary = self.styleSummary
        }
        picker.onScrubChange = { [weak self, weak picker] change, group in
            guard let self, let picker else { return }
            self.applyStyle(change, coalescing: group)
            picker.summary = self.styleSummary
        }
        return picker
    }
}
