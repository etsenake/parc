import AppKit
import Combine

@MainActor
enum NoteBlockWash {
    static let flashColor = NoteTheme.adaptive("OutlineFlash", light: NoteTheme.rgb(0x2702C2, 0.16), dark: NoteTheme.rgb(0x9380E0, 0.3))
    static let flashDuration: CFTimeInterval = 0.6

    static func flash(_ view: NSView) {
        guard let host = view.layer else { return }
        let wash = CALayer()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        wash.frame = view.bounds.insetBy(dx: -6, dy: 0)
        wash.cornerRadius = NoteTheme.blockRadius
        wash.cornerCurve = .continuous
        var color = flashColor.cgColor
        view.effectiveAppearance.performAsCurrentDrawingAppearance { color = flashColor.cgColor }
        wash.backgroundColor = color
        wash.opacity = 0
        host.insertSublayer(wash, at: 0)
        CATransaction.commit()
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1
        fade.toValue = 0
        fade.duration = flashDuration
        fade.timingFunction = CAMediaTimingFunction(controlPoints: 0.215, 0.61, 0.355, 1)
        CATransaction.begin()
        CATransaction.setCompletionBlock { wash.removeFromSuperlayer() }
        wash.add(fade, forKey: "parc.note.flash")
        CATransaction.commit()
    }
}

@MainActor
private func selectWholeBlock(_ view: NoteBlockView, with event: NSEvent) {
    guard let editor = view.editor else { return }
    if editor.selection.canvasMouseDown(event) { return }
    let id = view.blockID
    var ids = [id]
    if event.modifierFlags.contains(.command) || event.modifierFlags.contains(.shift),
       case .blocks(let current) = editor.session.selection {
        ids = current.contains(id) && event.modifierFlags.contains(.command) ? current.filter { $0 != id } : current + [id]
        ids = editor.session.page.ordered(ids)
    }
    view.window?.makeFirstResponder(editor.canvas)
    editor.session.setSelection(ids.isEmpty ? .none : .blocks(ids))
}

@MainActor
final class NoteDividerBlockView: NoteBlockView {
    static let height: CGFloat = 13
    static let thickness: CGFloat = 1

    override init(block: NoteBlock, editor: NotePageEditor?) {
        super.init(block: block, editor: editor)
        setAccessibilityElement(true)
        setAccessibilityRole(.splitter)
        setAccessibilityLabel("Divider")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func measureHeight(width: CGFloat) -> CGFloat { Self.height }

    override var handleAnchorY: CGFloat { Self.height / 2 }

    override func draw(_ dirtyRect: NSRect) {
        let ink = block.color.map { $0.isBackground ? NoteTheme.separator : NoteTheme.color($0) } ?? NoteTheme.separator
        let scale = window?.backingScaleFactor ?? 2
        let y = ((bounds.height - Self.thickness) / 2 * scale).rounded() / scale
        ink.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: y, width: bounds.width, height: Self.thickness)).fill()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        selectWholeBlock(self, with: event)
    }
}

@MainActor
final class NoteTOCBlockView: NoteBlockView {
    static let verticalPadding: CGFloat = 4
    static let rowPadding: CGFloat = 4
    static let indentStep: CGFloat = 22
    static let emptyText = "Add headings to fill this in"

    private(set) var entries: [NoteOutlineEntry] = []
    private var rows: [NoteTOCRowView] = []
    private let emptyRow = NoteTOCRowView(entry: nil)
    private var subscription: AnyCancellable?

    override init(block: NoteBlock, editor: NotePageEditor?) {
        super.init(block: block, editor: editor)
        emptyRow.title = Self.emptyText
        addSubview(emptyRow)
        setAccessibilityElement(true)
        setAccessibilityRole(.list)
        setAccessibilityLabel("Table of contents")
        subscription = editor?.session.changes.sink { [weak self] change in
            guard change.kind != .selection else { return }
            self?.reloadEntries()
        }
        reloadEntries(force: true)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private var pageSettings: NotePageSettings { editor?.session.page.settings ?? NotePageSettings() }

    private var rowFont: NSFont {
        let settings = pageSettings
        let base = NoteTheme.bodyFont(settings.font, small: true)
        return settings.smallText ? (NSFont(descriptor: base.fontDescriptor, size: base.pointSize - 1.5) ?? base) : base
    }

    private var lineHeight: CGFloat { (rowFont.pointSize * 1.45).rounded() }

    private var ink: NSColor {
        if let color = block.color, !color.isBackground { return NoteTheme.color(color) }
        return NoteTheme.secondaryInk
    }

    func reloadEntries(force: Bool = false) {
        let next = editor.map { NoteOutline.entries(in: $0.session.page) } ?? []
        guard force || next != entries else { return }
        entries = next
        while rows.count > entries.count { rows.removeLast().removeFromSuperview() }
        while rows.count < entries.count {
            let row = NoteTOCRowView(entry: nil)
            row.onActivate = { [weak self, weak row] in
                guard let self, let id = row?.entry?.id else { return }
                self.jump(to: id)
            }
            rows.append(row)
            addSubview(row)
        }
        for (row, entry) in zip(rows, entries) {
            row.entry = entry
            row.title = entry.title
        }
        emptyRow.isHidden = !entries.isEmpty
        restyleRows()
        setAccessibilityChildren(entries.isEmpty ? [emptyRow] : rows)
        needsLayout = true
        invalidateCanvasLayout()
    }

    private func restyleRows() {
        let font = rowFont, line = lineHeight
        for row in rows { row.style(font: font, lineHeight: line, ink: ink, interactive: true) }
        emptyRow.style(font: font, lineHeight: line, ink: NoteTheme.placeholderInk, interactive: false)
    }

    private func invalidateCanvasLayout() {
        superview?.needsLayout = true
        editor?.canvas.needsLayout = true
    }

    func rowHeights(width: CGFloat) -> [CGFloat] {
        let font = rowFont, line = lineHeight
        if entries.isEmpty { return [NoteTOCRowView.height(of: Self.emptyText, font: font, lineHeight: line, width: width)] }
        return entries.map { entry in
            let available = max(40, width - CGFloat(entry.depth) * Self.indentStep)
            return NoteTOCRowView.height(of: entry.title, font: font, lineHeight: line, width: available)
        }
    }

    override func measureHeight(width: CGFloat) -> CGFloat {
        Self.verticalPadding * 2 + rowHeights(width: width - Self.horizontalInset * 2).reduce(0, +)
    }

    static let horizontalInset: CGFloat = 2

    override var handleAnchorY: CGFloat { Self.verticalPadding + Self.rowPadding + lineHeight / 2 }

    override func layout() {
        super.layout()
        let width = bounds.width - Self.horizontalInset * 2
        let heights = rowHeights(width: width)
        var y = Self.verticalPadding
        if entries.isEmpty {
            emptyRow.frame = NSRect(x: Self.horizontalInset, y: y, width: width, height: heights.first ?? 0)
            return
        }
        for (index, row) in rows.enumerated() {
            let indent = CGFloat(entries[index].depth) * Self.indentStep
            row.frame = NSRect(x: Self.horizontalInset + indent, y: y, width: max(40, width - indent), height: heights[index])
            y += heights[index]
        }
    }

    override func update(_ block: NoteBlock) {
        super.update(block)
        restyleRows()
    }

    override func themeDidChange() {
        super.themeDidChange()
        restyleRows()
        needsLayout = true
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let color = block.color, color.isBackground else { return }
        NoteTheme.color(color).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: NoteTheme.blockRadius, yRadius: NoteTheme.blockRadius).fill()
    }

    override func mouseDown(with event: NSEvent) {
        selectWholeBlock(self, with: event)
    }

    func jump(to id: NoteBlockID) {
        guard let editor else { return }
        editor.canvas.scrollBlockToVisible(id)
        editor.canvas.layoutSubtreeIfNeeded()
        guard let target = editor.canvas.blockView(for: id) else { return }
        NoteBlockWash.flash(target)
    }
}

@MainActor
final class NoteTOCRowView: NSView {
    var entry: NoteOutlineEntry?
    var title = "" { didSet { if oldValue != title { setAccessibilityLabel(title); needsDisplay = true } } }
    var onActivate: (() -> Void)?
    private var font = NSFont.systemFont(ofSize: 15)
    private var lineHeight: CGFloat = 22
    private var ink = NSColor.secondaryLabelColor
    private var isInteractive = true
    private var isHovered = false { didSet { if oldValue != isHovered { needsDisplay = true } } }
    private var isPressed = false { didSet { if oldValue != isPressed { needsDisplay = true } } }
    private var tracking: NSTrackingArea?

    init(entry: NoteOutlineEntry?) {
        self.entry = entry
        super.init(frame: .zero)
        setAccessibilityElement(true)
        setAccessibilityRole(.link)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    func style(font: NSFont, lineHeight: CGFloat, ink: NSColor, interactive: Bool) {
        self.font = font
        self.lineHeight = lineHeight
        self.ink = ink
        isInteractive = interactive
        setAccessibilityRole(interactive ? .link : .staticText)
        window?.invalidateCursorRects(for: self)
        needsDisplay = true
    }

    static func attributes(font: NSFont, lineHeight: CGFloat, ink: NSColor, underline: Bool) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = lineHeight
        paragraph.maximumLineHeight = lineHeight
        paragraph.lineBreakMode = .byWordWrapping
        var attributes: [NSAttributedString.Key: Any] = [
            .font: font, .foregroundColor: ink, .paragraphStyle: paragraph,
            .baselineOffset: max(0, (lineHeight - (font.ascender - font.descender + font.leading)) / 2),
        ]
        if underline {
            attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
            attributes[.underlineColor] = ink.withAlphaComponent(0.55)
        }
        return attributes
    }

    static func height(of title: String, font: NSFont, lineHeight: CGFloat, width: CGFloat) -> CGFloat {
        let text = NSAttributedString(string: title, attributes: attributes(font: font, lineHeight: lineHeight, ink: .labelColor, underline: false))
        let bounds = text.boundingRect(with: NSSize(width: max(1, width), height: .greatestFiniteMagnitude),
                                       options: [.usesLineFragmentOrigin, .usesFontLeading])
        let lines = max(1, (bounds.height / lineHeight).rounded())
        return lines * lineHeight + NoteTOCBlockView.rowPadding * 2
    }

    override func draw(_ dirtyRect: NSRect) {
        let color = isPressed ? NoteTheme.ink : ink
        let text = NSAttributedString(string: title, attributes: Self.attributes(font: font, lineHeight: lineHeight, ink: color,
                                                                                  underline: isInteractive && isHovered))
        let rect = bounds.insetBy(dx: 0, dy: NoteTOCBlockView.rowPadding)
        let used = text.boundingRect(with: rect.size, options: [.usesLineFragmentOrigin, .usesFontLeading])
        text.draw(with: NSRect(x: rect.minX, y: rect.minY, width: min(rect.width, ceil(used.width) + 1), height: rect.height),
                  options: [.usesLineFragmentOrigin, .usesFontLeading])
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(area)
        tracking = area
    }

    override func resetCursorRects() {
        if isInteractive { addCursorRect(textRect, cursor: .pointingHand) }
    }

    private var textRect: NSRect {
        let text = NSAttributedString(string: title, attributes: Self.attributes(font: font, lineHeight: lineHeight, ink: ink, underline: false))
        let used = text.boundingRect(with: NSSize(width: bounds.width, height: .greatestFiniteMagnitude),
                                     options: [.usesLineFragmentOrigin, .usesFontLeading])
        return NSRect(x: 0, y: 0, width: min(bounds.width, ceil(used.width) + 4), height: bounds.height)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let hit = super.hitTest(point) else { return nil }
        guard isInteractive else { return nil }
        return textRect.contains(convert(point, from: superview)) ? hit : nil
    }

    override func mouseEntered(with event: NSEvent) { isHovered = isInteractive }

    override func mouseExited(with event: NSEvent) { isHovered = false; isPressed = false }

    override func mouseDown(with event: NSEvent) {
        guard isInteractive else { return super.mouseDown(with: event) }
        isPressed = true
        while let next = window?.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            let inside = textRect.contains(convert(next.locationInWindow, from: nil))
            isPressed = inside
            if next.type == .leftMouseUp {
                isPressed = false
                if inside { onActivate?() }
                return
            }
        }
        isPressed = false
    }

    override func accessibilityPerformPress() -> Bool {
        guard isInteractive else { return false }
        onActivate?()
        return true
    }
}

@MainActor
final class NoteRawBlockView: NoteBlockView {}
