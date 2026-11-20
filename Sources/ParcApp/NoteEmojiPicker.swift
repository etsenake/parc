import AppKit

@MainActor
enum NoteEmojiDrawing {
    static let gridPointSize: CGFloat = 22
    static let toneSample = "\u{270B}"
    private static var drawable: [String: Bool] = [:]
    private static var texts: [String: NSAttributedString] = [:]
    private static let fontName = "AppleColorEmoji"

    static func font(size: CGFloat) -> NSFont {
        NSFont(name: fontName, size: size) ?? .systemFont(ofSize: size)
    }

    static func prepare(_ catalog: NoteEmojiCatalog) {
        guard catalog.availability == nil else { return }
        catalog.availability = { canDraw($0) }
    }

    static func canDraw(_ emoji: NoteEmoji) -> Bool {
        emoji.version < 15 || canDraw(emoji.character)
    }

    static func canDraw(_ character: String) -> Bool {
        if let known = drawable[character] { return known }
        let font = font(size: 20)
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: character, attributes: [.font: font]))
        let runs = CTLineGetGlyphRuns(line) as! [CTRun]
        var glyphCount = 0
        var native = !runs.isEmpty
        for run in runs {
            let count = CTRunGetGlyphCount(run)
            glyphCount += count
            var glyphs = [CGGlyph](repeating: 0, count: count)
            CTRunGetGlyphs(run, CFRange(location: 0, length: count), &glyphs)
            if glyphs.contains(0) { native = false }
            let attributes = CTRunGetAttributes(run) as NSDictionary
            if let runFont = attributes[NSAttributedString.Key.font] as? NSFont, runFont.fontName != font.fontName { native = false }
        }
        let result = native && glyphCount == 1
        drawable[character] = result
        return result
    }

    static func text(_ character: String, size: CGFloat) -> NSAttributedString {
        let key = "\(size)|\(character)"
        if let cached = texts[key] { return cached }
        let text = NSAttributedString(string: character, attributes: [.font: font(size: size)])
        texts[key] = text
        return text
    }

    static func draw(_ character: String, size: CGFloat, centeredIn rect: NSRect) {
        let text = text(character, size: size)
        let measured = text.size()
        text.draw(at: NSPoint(x: rect.midX - measured.width / 2, y: rect.midY - measured.height / 2))
    }

    static func image(_ character: String, size: CGFloat, side: CGFloat) -> NSImage {
        let text = text(character, size: size)
        return NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            let measured = text.size()
            text.draw(at: NSPoint(x: rect.midX - measured.width / 2, y: rect.midY - measured.height / 2))
            return true
        }
    }

    static func toneHand(_ tone: NoteEmojiSkinTone) -> String {
        tone.modifier.map { toneSample + String(Character($0)) } ?? toneSample
    }

    static func categoryGlyph(_ category: NoteEmojiCategory) -> NSImage {
        let codes: [NoteEmojiCategory: UInt32] = [.people: 0xE9DE, .nature: 0xE9E3, .food: 0xE943, .activities: 0xE919,
                                                  .travel: 0xE9F6, .objects: 0xE971, .symbols: 0xE97D, .flags: 0xE96B]
        if let code = codes[category] { return SidebarIconCatalog.featherImage(code, size: 16) }
        let image = NSImage(size: NSSize(width: 16, height: 16), flipped: true) { rect in
            let unit = rect.width / 24
            let path = NSBezierPath(ovalIn: NSRect(x: 2 * unit, y: 2 * unit, width: 20 * unit, height: 20 * unit))
            path.move(to: NSPoint(x: 12 * unit, y: 6 * unit))
            path.line(to: NSPoint(x: 12 * unit, y: 12 * unit))
            path.line(to: NSPoint(x: 16 * unit, y: 14 * unit))
            path.lineWidth = 2 * unit
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            NSColor.black.setStroke()
            path.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }

    static func symbol(_ name: String, pointSize: CGFloat) -> NSImage {
        let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(configuration)
        return image ?? NSImage(size: NSSize(width: pointSize, height: pointSize))
    }
}

@MainActor
final class NoteEmojiButton: PointingHandButton {
    enum Face: Equatable {
        case glyph(NSImage)
        case emoji(String)
        case title(String)
    }

    var face: Face { didSet { if face != oldValue { invalidateIntrinsicContentSize(); needsDisplay = true } } }
    var isSelected = false { didSet { if isSelected != oldValue { needsDisplay = true } } }
    var showsSelectedPlate = true
    var isKeyFocused = false { didSet { if isKeyFocused != oldValue { refreshHover() } } }
    var onPress: (() -> Void)?
    private lazy var plate = TranslucentButtonFace(view: self)
    private var tracking: NSTrackingArea?
    private var hovering = false { didSet { if hovering != oldValue { refreshHover() } } }

    init(_ face: Face, label: String, tooltip: String? = nil) {
        self.face = face
        super.init(frame: .zero)
        title = ""
        isBordered = false
        bezelStyle = .regularSquare
        imagePosition = .noImage
        refusesFirstResponder = true
        focusRingType = .none
        target = self
        action = #selector(press)
        setAccessibilityLabel(label)
        if let tooltip { parcTooltip = TooltipConfiguration(tooltip) }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    static let titleFont = NSFont.systemFont(ofSize: 13, weight: .medium)

    override var intrinsicContentSize: NSSize {
        if case .title(let text) = face {
            let width = (text as NSString).size(withAttributes: [.font: Self.titleFont]).width
            return NSSize(width: ceil(width) + 18, height: 30)
        }
        return NSSize(width: 30, height: 30)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeInActiveApp, .inVisibleRect], owner: self)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) { hovering = isTopmost(atWindowPoint: event.locationInWindow) }
    override func mouseMoved(with event: NSEvent) { hovering = isTopmost(atWindowPoint: event.locationInWindow) }
    override func mouseExited(with event: NSEvent) { hovering = false }

    override var isEnabled: Bool { didSet { if isEnabled != oldValue { needsDisplay = true } } }

    private func refreshHover() {
        plate.setHovered((hovering || isKeyFocused) && !(isSelected && showsSelectedPlate))
        needsDisplay = true
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func viewDidHide() {
        super.viewDidHide()
        hovering = false
        plate.stop()
    }

    override func draw(_ dirtyRect: NSRect) {
        plate.setPressed(isHighlighted && isEnabled)
        if isSelected && showsSelectedPlate {
            NoteTheme.blockSelection.setFill()
            NSBezierPath(roundedRect: bounds, xRadius: NoteTheme.controlRadius, yRadius: NoteTheme.controlRadius).fill()
        }
        let enabled = isEnabled
        let selected = isSelected
        let face = face
        plate.draw(in: bounds, enabled: enabled, view: self) { tint in
            switch face {
            case .glyph(let image):
                drawGlyph(image, tint: selected && enabled ? NoteTheme.ink : tint)
            case .emoji(let character):
                NoteEmojiDrawing.draw(character, size: 18, centeredIn: bounds)
            case .title(let text):
                let color = enabled ? NoteTheme.secondaryInk : tint
                let string = NSAttributedString(string: text, attributes: [.font: Self.titleFont, .foregroundColor: color])
                let size = string.size()
                string.draw(at: NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2))
            }
        }
    }

    private func drawGlyph(_ image: NSImage, tint: NSColor) {
        plate.drawGlyph(image, tint: tint.usingColorSpace(.sRGB) ?? tint, in: bounds, view: self)
    }

    @objc private func press() { onPress?() }
}

@MainActor
final class NoteEmojiSearchBox: NSView {
    let field = NSTextField()
    private let glyph = NSImageView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 13)
        field.textColor = NoteTheme.ink
        field.lineBreakMode = .byTruncatingTail
        field.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        field.placeholderAttributedString = NSAttributedString(string: "Search emoji", attributes: [
            .font: NSFont.systemFont(ofSize: 13), .foregroundColor: NoteTheme.placeholderInk])
        field.setAccessibilityLabel("Search emoji")
        glyph.image = NoteEmojiDrawing.symbol("magnifyingglass", pointSize: 11)
        glyph.contentTintColor = NoteTheme.tertiaryInk
        glyph.setAccessibilityElement(false)
        addSubview(glyph)
        addSubview(field)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        glyph.frame = NSRect(x: 8, y: (bounds.height - 16) / 2, width: 16, height: 16)
        let height = ceil(field.intrinsicContentSize.height)
        field.frame = NSRect(x: 28, y: floor((bounds.height - height) / 2), width: max(0, bounds.width - 36), height: height)
    }

    override func draw(_ dirtyRect: NSRect) {
        NoteTheme.hoverFill.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8).fill()
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(field)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

@MainActor
final class NoteEmojiToneStrip: NSView {
    var onChoose: ((NoteEmojiSkinTone) -> Void)?
    private(set) var buttons: [NoteEmojiButton] = []
    var selected: NoteEmojiSkinTone = .none { didSet { refresh() } }
    private(set) var focused: NoteEmojiSkinTone?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        for tone in NoteEmojiSkinTone.allCases {
            let button = NoteEmojiButton(.emoji(NoteEmojiDrawing.toneHand(tone)), label: tone.displayName + " skin tone")
            button.onPress = { [weak self] in self?.onChoose?(tone) }
            buttons.append(button)
            addSubview(button)
        }
        setAccessibilityRole(.group)
        setAccessibilityLabel("Skin tone")
        refresh()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        let side: CGFloat = 30
        let gap: CGFloat = 4
        let total = CGFloat(buttons.count) * side + CGFloat(buttons.count - 1) * gap
        var x = bounds.width - total
        for button in buttons {
            button.frame = NSRect(x: x, y: (bounds.height - side) / 2, width: side, height: side)
            x += side + gap
        }
    }

    func beginFocus() { focused = selected; refresh() }

    func endFocus() { focused = nil; refresh() }

    func moveFocus(by delta: Int) {
        let count = NoteEmojiSkinTone.allCases.count
        let start = (focused ?? selected).rawValue
        focused = NoteEmojiSkinTone(rawValue: (start + delta + count) % count)
        refresh()
    }

    func chooseFocused() { onChoose?(focused ?? selected) }

    private func refresh() {
        for (index, button) in buttons.enumerated() {
            button.isSelected = index == selected.rawValue
            button.isKeyFocused = index == focused?.rawValue
            button.setAccessibilityValue(index == selected.rawValue ? "Selected" : nil)
        }
    }
}

@MainActor
final class NoteEmojiCategoryBar: NSView {
    var onSelect: ((NoteEmojiCategory) -> Void)?
    private(set) var selected: NoteEmojiCategory?
    private var buttons: [(category: NoteEmojiCategory, button: NoteEmojiButton)] = []
    private let plate = NSView()
    private let line = NSView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        plate.wantsLayer = true
        plate.layer?.cornerRadius = NoteTheme.controlRadius
        plate.layer?.cornerCurve = .continuous
        plate.isHidden = true
        line.wantsLayer = true
        addSubview(line)
        addSubview(plate)
        for category in NoteEmojiCategory.allCases {
            let button = NoteEmojiButton(.glyph(NoteEmojiDrawing.categoryGlyph(category)), label: category.displayName,
                                         tooltip: category.displayName)
            button.showsSelectedPlate = false
            button.onPress = { [weak self] in self?.onSelect?(category) }
            buttons.append((category, button))
            addSubview(button)
        }
        setAccessibilityRole(.toolbar)
        setAccessibilityLabel("Emoji categories")
        refreshColors()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        line.frame = NSRect(x: 0, y: 0, width: bounds.width, height: 1 / (window?.backingScaleFactor ?? 2))
        let side: CGFloat = 30
        let inset: CGFloat = 8
        let step = buttons.count > 1 ? (bounds.width - 2 * inset - side) / CGFloat(buttons.count - 1) : 0
        for (index, entry) in buttons.enumerated() {
            entry.button.frame = NSRect(x: round(inset + CGFloat(index) * step), y: round((bounds.height - side) / 2 + 0.5),
                                        width: side, height: side)
        }
        placePlate(animated: false)
    }

    func setEnabled(_ enabled: Bool, for category: NoteEmojiCategory) {
        buttons.first { $0.category == category }?.button.isEnabled = enabled
    }

    func select(_ category: NoteEmojiCategory?, animated: Bool) {
        guard category != selected else { return }
        selected = category
        for entry in buttons {
            entry.button.isSelected = entry.category == category
            entry.button.setAccessibilityValue(entry.category == category ? "Selected" : nil)
        }
        placePlate(animated: animated)
    }

    private func placePlate(animated: Bool) {
        guard let selected, let button = buttons.first(where: { $0.category == selected })?.button else {
            plate.isHidden = true
            return
        }
        let wasHidden = plate.isHidden
        let from = plate.layer?.presentation()?.position ?? plate.layer?.position
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        plate.frame = button.frame
        plate.isHidden = false
        CATransaction.commit()
        guard animated, !wasHidden, !NoteAnimation.reduceMotion, let layer = plate.layer, let from else { return }
        let to = layer.position
        guard from != to else { return }
        layer.add(NoteAnimation.spring("position", .highlight, from: NSValue(point: from), to: NSValue(point: to)), forKey: "note.emoji.category")
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshColors()
    }

    private func refreshColors() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        effectiveAppearance.performAsCurrentDrawingAppearance {
            plate.layer?.backgroundColor = NoteTheme.hoverFill.cgColor
            line.layer?.backgroundColor = NoteTheme.separator.cgColor
        }
        CATransaction.commit()
    }
}

@MainActor
final class NoteEmojiAccessibilityElement: NSAccessibilityElement {
    weak var grid: NoteEmojiGridView?
    let index: Int

    init(grid: NoteEmojiGridView, index: Int, label: String) {
        self.grid = grid
        self.index = index
        super.init()
        setAccessibilityRole(.button)
        setAccessibilityLabel(label)
    }

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityParent() -> Any? { grid }

    override func accessibilityFrame() -> NSRect {
        guard let grid, let window = grid.window, grid.contains(index) else { return .zero }
        return window.convertToScreen(grid.convert(grid.cellFrame(of: index), to: nil))
    }

    override func isAccessibilitySelected() -> Bool { grid?.highlighted == index }
    override func accessibilityPerformPress() -> Bool { grid?.pick(at: index) ?? false }
}

@MainActor
final class NoteEmojiGridView: NSView {
    struct Item: Equatable {
        let emoji: NoteEmoji
        let character: String
    }

    struct Section {
        let category: NoteEmojiCategory?
        let title: String?
        let items: [Item]
    }

    enum Move { case left, right, up, down, pageUp, pageDown, first, last }

    private struct Row {
        let start: Int
        let count: Int
        let y: CGFloat
    }

    static let cell: CGFloat = 32
    static let inset: CGFloat = 8
    static let headerHeight: CGFloat = 28
    static let sectionGap: CGFloat = 6
    static let hoverScale: CGFloat = 1.18
    static let pressScale: CGFloat = 0.9
    static let headerFont = NSFont.systemFont(ofSize: 12, weight: .semibold)

    var onPick: ((Item) -> Void)?
    var onHighlight: ((Item?) -> Void)?
    var currentCharacter: String? { didSet { resolveCurrent(); needsDisplay = true } }

    private(set) var items: [Item] = []
    private(set) var highlighted: Int?
    private(set) var highlightFromKeyboard = false
    private var sections: [Section] = []
    private var pressed: Int?
    private var current: Int?
    private var rows: [Row] = []
    private var rowOfItem: [Int] = []
    private var headers: [(title: String, y: CGFloat)] = []
    private var sectionStarts: [(category: NoteEmojiCategory?, y: CGFloat)] = []
    private var columns = 1
    private var originX: CGFloat = 0
    private let overlay = CALayer()
    private let plate = CALayer()
    private let glyph = CALayer()
    private var overlayIndex: Int?
    private var tracking: NSTrackingArea?
    private var elements: [Int: NoteEmojiAccessibilityElement] = [:]

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        plate.cornerRadius = NoteTheme.controlRadius
        plate.cornerCurve = .continuous
        glyph.contentsGravity = .center
        overlay.addSublayer(plate)
        overlay.addSublayer(glyph)
        overlay.isHidden = true
        overlay.zPosition = 1
        layer?.addSublayer(overlay)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }
    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    var isEmpty: Bool { items.isEmpty }
    var firstCategory: NoteEmojiCategory? { sectionStarts.first?.category }
    var lastCategory: NoteEmojiCategory? { sectionStarts.last?.category }

    func contains(_ index: Int) -> Bool { items.indices.contains(index) }

    func setSections(_ sections: [Section], width: CGFloat, minimumHeight: CGFloat) {
        self.sections = sections
        highlighted = nil
        highlightFromKeyboard = false
        pressed = nil
        layoutGrid(width: width, minimumHeight: minimumHeight)
    }

    func layoutGrid(width: CGFloat, minimumHeight: CGFloat) {
        columns = max(1, Int((width - 2 * Self.inset) / Self.cell))
        originX = floor((width - CGFloat(columns) * Self.cell) / 2)
        rows = []
        rowOfItem = []
        headers = []
        sectionStarts = []
        items = []
        var y: CGFloat = 4
        for section in sections where !section.items.isEmpty {
            sectionStarts.append((section.category, y))
            if let title = section.title {
                headers.append((title, y))
                y += Self.headerHeight
            }
            let first = items.count
            items.append(contentsOf: section.items)
            var offset = 0
            while offset < section.items.count {
                let count = min(columns, section.items.count - offset)
                rows.append(Row(start: first + offset, count: count, y: y))
                rowOfItem.append(contentsOf: repeatElement(rows.count - 1, count: count))
                offset += count
                y += Self.cell
            }
            y += Self.sectionGap
        }
        setFrameSize(NSSize(width: width, height: max(ceil(y + 4), minimumHeight)))
        if let highlighted, !items.indices.contains(highlighted) { self.highlighted = nil }
        resolveCurrent()
        elements = [:]
        overlayIndex = nil
        updateOverlay(animated: false)
        needsDisplay = true
        window?.invalidateCursorRects(for: self)
    }

    func cellFrame(of index: Int) -> NSRect {
        let row = rows[rowOfItem[index]]
        return NSRect(x: originX + CGFloat(index - row.start) * Self.cell, y: row.y, width: Self.cell, height: Self.cell)
    }

    func index(at point: NSPoint) -> Int? {
        let candidate = firstRow(endingBelow: point.y)
        guard candidate < rows.count, rows[candidate].y <= point.y else { return nil }
        let row = rows[candidate]
        let column = Int(floor((point.x - originX) / Self.cell))
        guard column >= 0, column < row.count else { return nil }
        return row.start + column
    }

    private func firstRow(endingBelow y: CGFloat) -> Int {
        var low = 0
        var high = rows.count
        while low < high {
            let middle = (low + high) / 2
            if rows[middle].y + Self.cell <= y { low = middle + 1 } else { high = middle }
        }
        return low
    }

    func origin(of category: NoteEmojiCategory) -> CGFloat? {
        sectionStarts.first { $0.category == category }.map { max(0, $0.y - 4) }
    }

    func category(at y: CGFloat) -> NoteEmojiCategory? {
        (sectionStarts.last { $0.y <= y } ?? sectionStarts.first)?.category
    }

    private func resolveCurrent() {
        guard let currentCharacter else { current = nil; return }
        let bare = NoteEmojiCatalog.unqualified(currentCharacter)
        current = items.firstIndex { $0.character == currentCharacter }
            ?? items.firstIndex { $0.emoji.tone(of: currentCharacter) != nil || NoteEmojiCatalog.unqualified($0.emoji.character) == bare }
    }

    override func draw(_ dirtyRect: NSRect) {
        let headerAttributes: [NSAttributedString.Key: Any] = [.font: Self.headerFont, .foregroundColor: NoteTheme.secondaryInk]
        for header in headers where header.y < dirtyRect.maxY && header.y + Self.headerHeight > dirtyRect.minY {
            let text = NSAttributedString(string: header.title, attributes: headerAttributes)
            let size = text.size()
            text.draw(at: NSPoint(x: originX + 6, y: header.y + (Self.headerHeight - size.height) / 2 + 3))
        }
        var rowIndex = firstRow(endingBelow: dirtyRect.minY)
        while rowIndex < rows.count, rows[rowIndex].y < dirtyRect.maxY {
            let row = rows[rowIndex]
            for index in row.start..<(row.start + row.count) {
                let rect = cellFrame(of: index)
                if index == current {
                    NoteTheme.blockSelection.setFill()
                    NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1), xRadius: NoteTheme.controlRadius, yRadius: NoteTheme.controlRadius).fill()
                }
                if index == overlayIndex { continue }
                NoteEmojiDrawing.draw(items[index].character, size: NoteEmojiDrawing.gridPointSize, centeredIn: rect)
            }
            rowIndex += 1
        }
    }

    func setHighlight(_ index: Int?, fromKeyboard: Bool, animated: Bool = true) {
        let target = index.flatMap { items.indices.contains($0) ? $0 : nil }
        guard target != highlighted || fromKeyboard != highlightFromKeyboard else { return }
        highlighted = target
        highlightFromKeyboard = fromKeyboard && target != nil
        updateOverlay(animated: animated)
        onHighlight?(target.map { items[$0] })
        guard let target else { return }
        if fromKeyboard {
            let rowTop = rows[rowOfItem[target]].y
            var visible = cellFrame(of: target).insetBy(dx: 0, dy: -Self.sectionGap)
            if let header = headers.first(where: { abs($0.y + Self.headerHeight - rowTop) < 0.5 }) {
                visible = visible.union(NSRect(x: visible.minX, y: header.y, width: 1, height: 1))
            }
            scrollToVisible(visible)
            NSAccessibility.post(element: element(for: target), notification: .focusedUIElementChanged)
        }
    }

    @discardableResult
    func move(_ move: Move) -> Bool {
        guard !items.isEmpty else { return false }
        guard let origin = highlighted else {
            setHighlight(move == .last || move == .up ? items.count - 1 : 0, fromKeyboard: true)
            return true
        }
        let rowIndex = rowOfItem[origin]
        let column = origin - rows[rowIndex].start
        let pageRows = max(1, Int(visibleRect.height / Self.cell) - 1)
        func item(inRow index: Int) -> Int {
            let row = rows[min(max(index, 0), rows.count - 1)]
            return row.start + min(column, row.count - 1)
        }
        let target: Int
        switch move {
        case .left: target = max(0, origin - 1)
        case .right: target = min(items.count - 1, origin + 1)
        case .up: target = item(inRow: rowIndex - 1)
        case .down: target = item(inRow: rowIndex + 1)
        case .pageUp: target = item(inRow: rowIndex - pageRows)
        case .pageDown: target = item(inRow: rowIndex + pageRows)
        case .first: target = 0
        case .last: target = items.count - 1
        }
        setHighlight(target, fromKeyboard: true)
        return true
    }

    @discardableResult
    func pickHighlighted() -> Bool {
        guard let highlighted else { return false }
        return pick(at: highlighted)
    }

    @discardableResult
    func pick(at index: Int) -> Bool {
        guard items.indices.contains(index) else { return false }
        onPick?(items[index])
        return true
    }

    private func updateOverlay(animated: Bool) {
        let previous = overlayIndex
        guard let target = highlighted, items.indices.contains(target) else {
            overlayIndex = nil
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            overlay.isHidden = true
            glyph.removeAllAnimations()
            CATransaction.commit()
            if let previous, items.indices.contains(previous) { setNeedsDisplay(cellFrame(of: previous)) }
            return
        }
        let rect = cellFrame(of: target)
        let isPressed = pressed == target
        let changed = target != previous
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        overlay.frame = rect
        plate.frame = overlay.bounds.insetBy(dx: 1, dy: 1)
        glyph.frame = overlay.bounds
        effectiveAppearance.performAsCurrentDrawingAppearance {
            plate.backgroundColor = (isPressed ? NoteTheme.pressedFill : NoteTheme.hoverFill).cgColor
        }
        if changed {
            let scale = (window?.backingScaleFactor ?? 2) * Self.hoverScale
            glyph.contentsScale = scale
            glyph.contents = NoteEmojiDrawing.image(items[target].character, size: NoteEmojiDrawing.gridPointSize, side: Self.cell)
                .layerContents(forContentsScale: scale)
            glyph.removeAllAnimations()
            glyph.transform = CATransform3DIdentity
        }
        overlay.isHidden = false
        CATransaction.commit()
        overlayIndex = target
        if changed {
            if let previous, items.indices.contains(previous) { setNeedsDisplay(cellFrame(of: previous)) }
            setNeedsDisplay(rect)
        }
        let scale: CGFloat = NoteAnimation.reduceMotion ? 1 : (isPressed ? Self.pressScale : Self.hoverScale)
        animateGlyph(to: scale, from: changed ? 1 : nil, animated: animated)
    }

    private func animateGlyph(to scale: CGFloat, from start: CGFloat?, animated: Bool) {
        let presented = glyph.presentation()?.value(forKeyPath: "transform.scale") as? CGFloat
        let from = start ?? presented ?? (glyph.value(forKeyPath: "transform.scale") as? CGFloat) ?? 1
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        glyph.setValue(scale, forKeyPath: "transform.scale")
        CATransaction.commit()
        glyph.removeAnimation(forKey: "note.emoji.scale")
        guard animated, !NoteAnimation.reduceMotion, abs(from - scale) > 0.001 else { return }
        glyph.add(NoteAnimation.spring("transform.scale", .press, from: from, to: scale), forKey: "note.emoji.scale")
    }

    func settleMotion() {
        glyph.removeAllAnimations()
        updateOverlay(animated: false)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) { hover(at: event.locationInWindow) }
    override func mouseMoved(with event: NSEvent) { hover(at: event.locationInWindow) }

    override func mouseExited(with event: NSEvent) {
        if !highlightFromKeyboard, pressed == nil { setHighlight(nil, fromKeyboard: false) }
    }

    private func hover(at windowPoint: NSPoint) {
        guard pressed == nil else { return }
        guard isTopmost(atWindowPoint: windowPoint) else {
            if !highlightFromKeyboard { setHighlight(nil, fromKeyboard: false) }
            return
        }
        let index = index(at: convert(windowPoint, from: nil))
        if index == nil && highlightFromKeyboard { return }
        setHighlight(index, fromKeyboard: false)
    }

    func refreshHover() {
        guard !highlightFromKeyboard, pressed == nil, let window else { return }
        let point = window.mouseLocationOutsideOfEventStream
        if visibleRect.contains(convert(point, from: nil)) {
            hover(at: point)
        } else if highlighted != nil {
            setHighlight(nil, fromKeyboard: false)
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard let index = index(at: convert(event.locationInWindow, from: nil)) else { return }
        pressed = index
        if highlighted == index && !highlightFromKeyboard {
            updateOverlay(animated: true)
        } else {
            setHighlight(index, fromKeyboard: false)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard pressed != nil else { return }
        let over = index(at: convert(event.locationInWindow, from: nil))
        if over != highlighted {
            setHighlight(over, fromKeyboard: false)
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard let target = pressed else { return }
        let over = index(at: convert(event.locationInWindow, from: nil))
        pressed = nil
        updateOverlay(animated: true)
        if over == target { pick(at: target) }
    }

    override func resetCursorRects() {
        let visible = visibleRect
        var rowIndex = firstRow(endingBelow: visible.minY)
        while rowIndex < rows.count, rows[rowIndex].y < visible.maxY {
            let row = rows[rowIndex]
            let rect = NSRect(x: originX, y: row.y, width: CGFloat(row.count) * Self.cell, height: Self.cell).intersection(visible)
            if !rect.isEmpty { addCursorRect(rect, cursor: .pointingHand) }
            rowIndex += 1
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateOverlay(animated: false)
        needsDisplay = true
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        overlayIndex = nil
        updateOverlay(animated: false)
    }

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .group }
    override func accessibilityLabel() -> String? { "Emoji" }

    override func accessibilityChildren() -> [Any]? {
        let visible = visibleRect
        var children: [Any] = []
        var rowIndex = firstRow(endingBelow: visible.minY)
        while rowIndex < rows.count, rows[rowIndex].y < visible.maxY {
            let row = rows[rowIndex]
            for index in row.start..<(row.start + row.count) { children.append(element(for: index)) }
            rowIndex += 1
        }
        return children
    }

    private func element(for index: Int) -> NoteEmojiAccessibilityElement {
        if let cached = elements[index] { return cached }
        let element = NoteEmojiAccessibilityElement(grid: self, index: index, label: items[index].emoji.displayName)
        elements[index] = element
        return element
    }
}

@MainActor
final class NoteEmojiPicker: NSView, NSTextFieldDelegate {
    static let preferredSize = NSSize(width: 408, height: 388)
    private static let padding: CGFloat = 10
    private static let rowHeight: CGFloat = 30
    private static let barHeight: CGFloat = 40

    var onPick: ((String) -> Void)?
    var onRemove: (() -> Void)?
    var onCancel: (() -> Void)?
    var currentEmoji: String? { didSet { grid.currentCharacter = currentEmoji } }

    let catalog: NoteEmojiCatalog
    let showsRemove: Bool
    let showsRandom: Bool
    private let searchBox = NoteEmojiSearchBox()
    private let toneButton: NoteEmojiButton
    private let randomButton = NoteEmojiButton(.glyph(NoteEmojiDrawing.symbol("shuffle", pointSize: 12)), label: "Random", tooltip: "Random")
    private let removeButton = NoteEmojiButton(.title("Remove"), label: "Remove icon")
    private let toneStrip = NoteEmojiToneStrip()
    private let scrollView = NSScrollView()
    private let grid = NoteEmojiGridView()
    private let categoryBar = NoteEmojiCategoryBar()
    private let emptyLabel = NSTextField(labelWithString: "No emoji match that. Try another word?")
    private var query = ""
    private var keyboardNavigating = false
    private var programmaticScroll = false
    private var observers: [NSObjectProtocol] = []
    private var motionObserver: NSObjectProtocol?

    init(catalog: NoteEmojiCatalog? = nil, showsRemove: Bool = false, showsRandom: Bool = false) {
        let catalog = catalog ?? .shared
        self.catalog = catalog
        self.showsRemove = showsRemove
        self.showsRandom = showsRandom
        toneButton = NoteEmojiButton(.emoji(NoteEmojiDrawing.toneHand(catalog.skinTone)), label: "Skin tone", tooltip: "Skin tone")
        super.init(frame: NSRect(origin: .zero, size: Self.preferredSize))
        NoteEmojiDrawing.prepare(catalog)
        searchBox.field.delegate = self
        toneButton.showsSelectedPlate = false
        toneButton.onPress = { [weak self] in self?.setToneStripOpen(true) }
        randomButton.onPress = { [weak self] in self?.pickRandom() }
        removeButton.onPress = { [weak self] in self?.onRemove?() }
        toneStrip.onChoose = { [weak self] tone in self?.chooseTone(tone) }
        toneStrip.selected = catalog.skinTone
        toneStrip.isHidden = true
        categoryBar.onSelect = { [weak self] category in self?.jump(to: category) }
        grid.onPick = { [weak self] item in self?.pick(item.character) }
        scrollView.documentView = grid
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.horizontalScrollElasticity = .none
        scrollView.contentView.postsBoundsChangedNotifications = true
        emptyLabel.font = .systemFont(ofSize: 13)
        emptyLabel.textColor = NoteTheme.secondaryInk
        emptyLabel.alignment = .center
        emptyLabel.isHidden = true
        randomButton.isHidden = !showsRandom
        removeButton.isHidden = !showsRemove
        for view in [scrollView, emptyLabel, categoryBar, searchBox, toneButton, randomButton, removeButton, toneStrip] as [NSView] {
            addSubview(view)
        }
        setAccessibilityRole(.group)
        setAccessibilityLabel("Emoji picker")
        observers.append(NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: scrollView.contentView,
                                                                queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.scrolled() }
        })
        motionObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { if NoteAnimation.reduceMotion { self?.grid.settleMotion() } }
        }
        arrange()
        reload()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    deinit {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        if let motionObserver { NSWorkspace.shared.notificationCenter.removeObserver(motionObserver) }
    }

    override var isFlipped: Bool { true }
    override var intrinsicContentSize: NSSize { Self.preferredSize }
    override var fittingSize: NSSize { Self.preferredSize }
    override var acceptsFirstResponder: Bool { true }

    var searchField: NSTextField { searchBox.field }
    var searchQuery: String { query }

    func focusSearch() {
        window?.makeFirstResponder(searchBox.field)
    }

    func reload() {
        let tone = catalog.skinTone
        var sections: [NoteEmojiGridView.Section] = []
        if query.isEmpty {
            let recents = catalog.recents.compactMap { character in
                catalog.entry(for: character).map { NoteEmojiGridView.Item(emoji: $0, character: character) }
            }
            if !recents.isEmpty {
                sections.append(NoteEmojiGridView.Section(category: .recents, title: NoteEmojiCategory.recents.displayName, items: recents))
            }
            for section in catalog.sections() {
                let items = section.emoji.map { NoteEmojiGridView.Item(emoji: $0, character: $0.character(with: tone)) }
                sections.append(NoteEmojiGridView.Section(category: section.category, title: section.category.displayName, items: items))
            }
            categoryBar.setEnabled(!recents.isEmpty, for: .recents)
        } else {
            let results = catalog.search(query)
            let items = results.map { NoteEmojiGridView.Item(emoji: $0, character: $0.character(with: tone)) }
            sections.append(NoteEmojiGridView.Section(category: nil, title: nil, items: items))
        }
        grid.setSections(sections, width: scrollView.contentSize.width, minimumHeight: scrollView.contentSize.height)
        grid.currentCharacter = currentEmoji
        emptyLabel.isHidden = !(grid.isEmpty && !query.isEmpty)
        if !query.isEmpty, !grid.isEmpty { grid.setHighlight(0, fromKeyboard: true, animated: false) }
        scrollTo(y: 0)
        categoryBar.select(query.isEmpty ? grid.firstCategory : nil, animated: false)
    }

    override func layout() {
        super.layout()
        arrange()
    }

    private func arrange() {
        let padding = Self.padding
        let rowHeight = Self.rowHeight
        var trailing = bounds.width - padding
        if showsRemove {
            let width = removeButton.intrinsicContentSize.width
            removeButton.frame = NSRect(x: trailing - width, y: padding, width: width, height: rowHeight)
            trailing -= width + 4
        }
        if showsRandom {
            randomButton.frame = NSRect(x: trailing - rowHeight, y: padding, width: rowHeight, height: rowHeight)
            trailing -= rowHeight + 4
        }
        toneButton.frame = NSRect(x: trailing - rowHeight, y: padding, width: rowHeight, height: rowHeight)
        trailing -= rowHeight + 6
        searchBox.frame = NSRect(x: padding, y: padding, width: max(0, trailing - padding), height: rowHeight)
        toneStrip.frame = NSRect(x: padding, y: padding, width: bounds.width - 2 * padding, height: rowHeight)
        let gridTop = padding + rowHeight + 6
        categoryBar.frame = NSRect(x: 0, y: bounds.height - Self.barHeight, width: bounds.width, height: Self.barHeight)
        let previousWidth = scrollView.frame.width
        scrollView.frame = NSRect(x: 0, y: gridTop, width: bounds.width, height: max(0, categoryBar.frame.minY - gridTop))
        emptyLabel.frame = NSRect(x: padding, y: scrollView.frame.minY + 40, width: bounds.width - 2 * padding, height: 20)
        if scrollView.frame.width != previousWidth || grid.frame.width != scrollView.contentSize.width
            || grid.frame.height < scrollView.contentSize.height {
            let anchor = scrollView.contentView.bounds.minY
            grid.layoutGrid(width: scrollView.contentSize.width, minimumHeight: scrollView.contentSize.height)
            scrollTo(y: anchor)
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        toneStrip.selected = catalog.skinTone
        toneButton.face = .emoji(NoteEmojiDrawing.toneHand(catalog.skinTone))
        reload()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    private func scrollTo(y: CGFloat) {
        let clip = scrollView.contentView
        let maximum = max(0, grid.frame.height - clip.bounds.height)
        programmaticScroll = true
        clip.scroll(to: NSPoint(x: 0, y: min(max(0, y), maximum)))
        scrollView.reflectScrolledClipView(clip)
        programmaticScroll = false
    }

    private func scrolled() {
        grid.refreshHover()
        window?.invalidateCursorRects(for: grid)
        guard !programmaticScroll, query.isEmpty else { return }
        let clip = scrollView.contentView.bounds
        let atBottom = clip.maxY >= grid.frame.height - 1 && clip.minY > 0
        categoryBar.select(atBottom ? grid.lastCategory : grid.category(at: clip.minY + Self.rowHeight), animated: true)
    }

    private func jump(to category: NoteEmojiCategory) {
        setToneStripOpen(false)
        if !query.isEmpty {
            searchBox.field.stringValue = ""
            query = ""
            keyboardNavigating = false
            reload()
        }
        guard let y = grid.origin(of: category) else { return }
        scrollTo(y: y)
        categoryBar.select(category, animated: true)
        grid.refreshHover()
    }

    private func pick(_ character: String) {
        catalog.recordUse(character)
        onPick?(character)
    }

    private func pickRandom() {
        guard let emoji = catalog.random() else { return }
        onPick?(catalog.character(for: emoji))
    }

    private var isToneStripOpen: Bool { !toneStrip.isHidden }

    private func setToneStripOpen(_ open: Bool) {
        guard open != isToneStripOpen else { return }
        let row: [NSView] = [searchBox, toneButton, randomButton, removeButton].filter { $0 !== randomButton || showsRandom }
            .filter { $0 !== removeButton || showsRemove }
        if open {
            toneStrip.selected = catalog.skinTone
            toneStrip.beginFocus()
            toneStrip.isHidden = false
            toneStrip.wantsLayer = true
            toneStrip.layer?.opacity = 0
            NoteAnimation.fade(toneStrip, visible: true)
            for view in row {
                view.wantsLayer = true
                NoteAnimation.fade(view, visible: false) { [weak view] in
                    MainActor.assumeIsolated {
                        guard let view, view.layer?.opacity == 0 else { return }
                        view.isHidden = true
                    }
                }
            }
        } else {
            toneStrip.endFocus()
            for view in row {
                view.isHidden = false
                NoteAnimation.fade(view, visible: true)
            }
            NoteAnimation.fade(toneStrip, visible: false) { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, self.toneStrip.layer?.opacity == 0 else { return }
                    self.toneStrip.isHidden = true
                }
            }
        }
    }

    private func chooseTone(_ tone: NoteEmojiSkinTone) {
        catalog.skinTone = tone
        toneStrip.selected = tone
        toneButton.face = .emoji(NoteEmojiDrawing.toneHand(tone))
        let anchor = scrollView.contentView.bounds.minY
        let selected = categoryBar.selected
        reload()
        scrollTo(y: anchor)
        categoryBar.select(query.isEmpty ? selected : nil, animated: false)
        setToneStripOpen(false)
        focusSearch()
    }

    func controlTextDidBeginEditing(_ notification: Notification) {
        (notification.userInfo?["NSFieldEditor"] as? NSTextView)?.insertionPointColor = NoteTheme.caret
    }

    func controlTextDidChange(_ notification: Notification) {
        let value = searchBox.field.stringValue
        guard value != query else { return }
        query = value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : value
        keyboardNavigating = false
        setToneStripOpen(false)
        reload()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        handle(commandSelector, fromSearch: true)
    }

    override func keyDown(with event: NSEvent) {
        interpretKeyEvents([event])
    }

    override func insertText(_ insertString: Any) {
        let text = (insertString as? String) ?? (insertString as? NSAttributedString)?.string ?? ""
        guard !text.isEmpty else { return }
        setToneStripOpen(false)
        focusSearch()
        searchBox.field.currentEditor()?.insertText(text)
    }

    override func doCommand(by selector: Selector) {
        if !handle(selector, fromSearch: false) { super.doCommand(by: selector) }
    }

    private func handle(_ selector: Selector, fromSearch: Bool) -> Bool {
        if isToneStripOpen {
            switch selector {
            case #selector(moveLeft(_:)), #selector(moveUp(_:)): toneStrip.moveFocus(by: -1)
            case #selector(moveRight(_:)), #selector(moveDown(_:)): toneStrip.moveFocus(by: 1)
            case #selector(insertNewline(_:)): toneStrip.chooseFocused()
            case #selector(cancelOperation(_:)): setToneStripOpen(false)
            default: return false
            }
            return true
        }
        let horizontal = keyboardNavigating || query.isEmpty || !fromSearch
        switch selector {
        case #selector(moveDown(_:)): navigate(.down)
        case #selector(moveUp(_:)): navigate(.up)
        case #selector(moveLeft(_:)):
            guard horizontal else { return false }
            navigate(.left)
        case #selector(moveRight(_:)):
            guard horizontal else { return false }
            navigate(.right)
        case #selector(pageDown(_:)), #selector(scrollPageDown(_:)): navigate(.pageDown)
        case #selector(pageUp(_:)), #selector(scrollPageUp(_:)): navigate(.pageUp)
        case #selector(insertNewline(_:)):
            if !grid.pickHighlighted() { NSSound.beep() }
        case #selector(cancelOperation(_:)):
            if !query.isEmpty {
                searchBox.field.stringValue = ""
                query = ""
                keyboardNavigating = false
                reload()
            } else {
                onCancel?()
            }
        default:
            return false
        }
        return true
    }

    private func navigate(_ move: NoteEmojiGridView.Move) {
        keyboardNavigating = true
        grid.move(move)
    }
}

@MainActor
final class NoteEmojiSuggestionRow: NSView {
    let index: Int
    weak var list: NoteEmojiSuggestionList?
    private let glyph = NSTextField(labelWithString: "")
    private let name = NSTextField(labelWithString: "")
    private let code = NSTextField(labelWithString: "")

    init(index: Int, list: NoteEmojiSuggestionList) {
        self.index = index
        self.list = list
        super.init(frame: .zero)
        glyph.font = NoteEmojiDrawing.font(size: 18)
        glyph.alignment = .center
        name.font = .systemFont(ofSize: 13)
        name.textColor = NoteTheme.ink
        name.lineBreakMode = .byTruncatingTail
        code.font = .systemFont(ofSize: 12)
        code.textColor = NoteTheme.tertiaryInk
        code.alignment = .right
        code.lineBreakMode = .byTruncatingHead
        for label in [glyph, name, code] {
            label.setAccessibilityElement(false)
            addSubview(label)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    func show(character: String, emoji: NoteEmoji) {
        glyph.stringValue = character
        name.stringValue = emoji.displayName
        code.stringValue = ":" + emoji.shortcode + ":"
        setAccessibilityLabel(emoji.displayName)
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let height = bounds.height
        glyph.frame = NSRect(x: 8, y: (height - 24) / 2, width: 26, height: 24)
        let codeWidth = min(ceil(code.intrinsicContentSize.width), bounds.width * 0.42)
        code.frame = NSRect(x: bounds.width - 10 - codeWidth, y: (height - 16) / 2, width: codeWidth, height: 16)
        name.frame = NSRect(x: 40, y: (height - 17) / 2, width: max(0, code.frame.minX - 48), height: 17)
    }

    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .button }
    override func isAccessibilitySelected() -> Bool { list?.selectedIndex == index }
    override func accessibilityPerformPress() -> Bool { list?.pick(at: index) ?? false }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        name.needsDisplay = true
        code.needsDisplay = true
    }
}

@MainActor
final class NoteEmojiSuggestionList: NSView {
    struct Suggestion: Equatable {
        let emoji: NoteEmoji
        let character: String
    }

    static let rowHeight: CGFloat = 32
    static let width: CGFloat = 300
    static let padding: CGFloat = 4

    let catalog: NoteEmojiCatalog
    var limit: Int { didSet { if limit != oldValue { reload() } } }
    var query = "" { didSet { if query != oldValue { reload() } } }
    var onPick: ((String) -> Void)?
    var onCancel: (() -> Void)?
    var onResultsChange: ((Int) -> Void)?
    private(set) var suggestions: [Suggestion] = []
    private(set) var selectedIndex: Int?
    private var rows: [NoteEmojiSuggestionRow] = []
    private let highlight = NSView()
    private var tracking: NSTrackingArea?

    init(catalog: NoteEmojiCatalog? = nil, limit: Int = 8) {
        let catalog = catalog ?? .shared
        self.catalog = catalog
        self.limit = limit
        super.init(frame: NSRect(x: 0, y: 0, width: Self.width, height: Self.padding * 2))
        NoteEmojiDrawing.prepare(catalog)
        wantsLayer = true
        highlight.wantsLayer = true
        highlight.layer?.cornerRadius = NoteTheme.controlRadius
        highlight.layer?.cornerCurve = .continuous
        highlight.isHidden = true
        highlight.setAccessibilityElement(false)
        addSubview(highlight)
        setAccessibilityRole(.list)
        setAccessibilityLabel("Emoji suggestions")
        refreshColors()
        reload()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    var hasResults: Bool { !suggestions.isEmpty }

    var preferredSize: NSSize {
        NSSize(width: Self.width, height: CGFloat(suggestions.count) * Self.rowHeight + Self.padding * 2)
    }

    override var intrinsicContentSize: NSSize { preferredSize }
    override var fittingSize: NSSize { preferredSize }

    func reload() {
        let previous = selectedIndex.map { suggestions[$0].emoji }
        let tone = catalog.skinTone
        if query.trimmingCharacters(in: .whitespaces).isEmpty {
            suggestions = catalog.recents.prefix(limit).compactMap { character in
                catalog.entry(for: character).map { Suggestion(emoji: $0, character: character) }
            }
        } else {
            suggestions = catalog.search(query, limit: limit).map { Suggestion(emoji: $0, character: $0.character(with: tone)) }
        }
        while rows.count < suggestions.count {
            let row = NoteEmojiSuggestionRow(index: rows.count, list: self)
            rows.append(row)
            addSubview(row)
        }
        for (index, row) in rows.enumerated() {
            row.isHidden = index >= suggestions.count
            if index < suggestions.count { row.show(character: suggestions[index].character, emoji: suggestions[index].emoji) }
        }
        let kept = previous.flatMap { emoji in suggestions.firstIndex { $0.emoji == emoji } }
        selectedIndex = suggestions.isEmpty ? nil : (kept ?? 0)
        invalidateIntrinsicContentSize()
        setFrameSize(preferredSize)
        needsLayout = true
        placeHighlight(animated: false)
        window?.invalidateCursorRects(for: self)
        onResultsChange?(suggestions.count)
    }

    override func layout() {
        super.layout()
        for (index, row) in rows.enumerated() {
            row.frame = rowFrame(index)
        }
        placeHighlight(animated: false)
    }

    private func rowFrame(_ index: Int) -> NSRect {
        NSRect(x: Self.padding, y: Self.padding + CGFloat(index) * Self.rowHeight, width: bounds.width - Self.padding * 2, height: Self.rowHeight)
    }

    @discardableResult
    func moveSelection(by delta: Int) -> Bool {
        guard !suggestions.isEmpty else { return false }
        let start = selectedIndex ?? (delta > 0 ? -1 : suggestions.count)
        select((start + delta + suggestions.count) % suggestions.count, animated: true)
        return true
    }

    func select(_ index: Int?, animated: Bool) {
        let target = index.flatMap { suggestions.indices.contains($0) ? $0 : nil }
        guard target != selectedIndex else { return }
        selectedIndex = target
        placeHighlight(animated: animated)
        if let target { NSAccessibility.post(element: rows[target], notification: .focusedUIElementChanged) }
    }

    @discardableResult
    func pickSelected() -> Bool {
        guard let selectedIndex else { return false }
        return pick(at: selectedIndex)
    }

    @discardableResult
    func pick(at index: Int) -> Bool {
        guard suggestions.indices.contains(index) else { return false }
        let character = suggestions[index].character
        catalog.recordUse(character)
        onPick?(character)
        return true
    }

    func handle(_ selector: Selector) -> Bool {
        switch selector {
        case #selector(moveUp(_:)): return moveSelection(by: -1)
        case #selector(moveDown(_:)): return moveSelection(by: 1)
        case #selector(insertNewline(_:)), #selector(insertTab(_:)): return pickSelected()
        case #selector(cancelOperation(_:)):
            guard let onCancel else { return false }
            onCancel()
            return true
        default: return false
        }
    }

    private func placeHighlight(animated: Bool) {
        guard let selectedIndex, suggestions.indices.contains(selectedIndex) else {
            highlight.isHidden = true
            return
        }
        let wasHidden = highlight.isHidden
        let from = highlight.layer?.presentation()?.position ?? highlight.layer?.position
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        highlight.frame = rowFrame(selectedIndex).insetBy(dx: 0, dy: 1)
        highlight.isHidden = false
        CATransaction.commit()
        guard animated, !wasHidden, !NoteAnimation.reduceMotion, let layer = highlight.layer, let from, from != layer.position else { return }
        layer.add(NoteAnimation.spring("position", .highlight, from: NSValue(point: from), to: NSValue(point: layer.position)),
                  forKey: "note.emoji.suggestion")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeInActiveApp, .inVisibleRect], owner: self)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseMoved(with event: NSEvent) {
        guard isTopmost(atWindowPoint: event.locationInWindow), let index = row(at: event) else { return }
        select(index, animated: true)
    }

    override func mouseDown(with event: NSEvent) {
        guard let index = row(at: event) else { return }
        select(index, animated: false)
    }

    override func mouseUp(with event: NSEvent) {
        guard let index = row(at: event), index == selectedIndex else { return }
        pick(at: index)
    }

    private func row(at event: NSEvent) -> Int? {
        let point = convert(event.locationInWindow, from: nil)
        let index = Int(floor((point.y - Self.padding) / Self.rowHeight))
        guard point.y >= Self.padding, suggestions.indices.contains(index) else { return nil }
        return index
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshColors()
    }

    private func refreshColors() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        effectiveAppearance.performAsCurrentDrawingAppearance {
            highlight.layer?.backgroundColor = NoteTheme.hoverFill.cgColor
        }
        CATransaction.commit()
    }
}
