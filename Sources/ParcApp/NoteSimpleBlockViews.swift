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
enum NoteBlockPointer {
    static func selectBlock(_ view: NoteBlockView, with event: NSEvent) {
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
        NoteBlockPointer.selectBlock(self, with: event)
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
        guard window != nil else { return }
        editor?.canvas.blockHeightDidChange(blockID)
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
        NoteBlockPointer.selectBlock(self, with: event)
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
final class NoteRawBlockView: NoteBlockView, NoteTextHost {
    static let padding = NSEdgeInsets(top: 28, left: 14, bottom: 12, right: 14)
    static let cornerRadius: CGFloat = 8
    static let lineHeight: CGFloat = 20

    let field: NoteTextField = .body
    var textView: NoteTextView { rawView }
    let rawView = NoteCodeTextView()
    private let card = NoteCodeCard()
    private let label = NSTextField(labelWithString: "")
    private let icon = NoteIconView(icon: .symbol("chevron.left.forwardslash.chevron.right"), pointSize: 10)
    private var measured: (width: CGFloat, text: String, height: CGFloat)?

    override init(block: NoteBlock, editor: NotePageEditor?) {
        super.init(block: block, editor: editor)
        card.wantsLayer = true
        card.layer?.cornerRadius = Self.cornerRadius
        card.layer?.cornerCurve = .continuous
        addSubview(card)
        label.font = NoteTheme.menuHeaderFont()
        label.textColor = NoteTheme.tertiaryInk
        label.setAccessibilityElement(false)
        card.addSubview(label)
        icon.tint = NoteTheme.tertiaryInk
        icon.setAccessibilityElement(false)
        card.addSubview(icon)
        rawView.host = self
        rawView.editor = editor
        rawView.isRichText = false
        rawView.importsGraphics = false
        rawView.isAutomaticQuoteSubstitutionEnabled = false
        rawView.isAutomaticDashSubstitutionEnabled = false
        rawView.isAutomaticTextReplacementEnabled = false
        rawView.isAutomaticSpellingCorrectionEnabled = false
        rawView.isAutomaticLinkDetectionEnabled = false
        rawView.isAutomaticDataDetectionEnabled = false
        rawView.isContinuousSpellCheckingEnabled = false
        rawView.isGrammarCheckingEnabled = false
        rawView.smartInsertDeleteEnabled = false
        rawView.inputRulesEnabled = false
        rawView.presentation = NoteTextPresentation(role: .code)
        rawView.textContainer?.widthTracksTextView = true
        rawView.languageID = { [weak self] in self?.block.kind == .html ? "html" : "markdown" }
        rawView.indentation = { [weak self] in
            NoteCodeEditing.indent(forLanguage: self?.block.kind == .html ? "html" : "markdown", text: self?.rawView.string ?? "")
        }
        rawView.onExit = { [weak self] trims in self?.exitBelow(trimmingBlankLine: trims) }
        rawView.onEdit = { [weak self] in self?.rawDidChange() }
        card.addSubview(rawView)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        apply(block, force: true)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var textHosts: [NoteTextHost] { [self] }

    var kindLabel: String { block.kind == .html ? "HTML" : "Markdown" }

    private var attributes: [NSAttributedString.Key: Any] {
        let font = NoteCodeFont.code(size: 13)
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = Self.lineHeight
        paragraph.maximumLineHeight = Self.lineHeight
        paragraph.lineBreakMode = .byCharWrapping
        let space = NSAttributedString(string: " ", attributes: [.font: font]).size().width
        paragraph.tabStops = []
        paragraph.defaultTabInterval = space * 4
        return [.font: font, .foregroundColor: NoteTheme.secondaryInk, .paragraphStyle: paragraph, .ligature: 0,
                .baselineOffset: max(0, (Self.lineHeight - (font.ascender - font.descender + font.leading)) / 2)]
    }

    override func update(_ block: NoteBlock) {
        super.update(block)
        apply(block, force: false)
    }

    private func apply(_ block: NoteBlock, force: Bool) {
        let attributes = self.attributes
        rawView.codeAttributes = attributes
        rawView.typingAttributes = attributes
        rawView.insertionPointColor = NoteTheme.caret
        rawView.selectedTextAttributes = [.backgroundColor: NoteTheme.selection]
        rawView.isEditable = !isReadOnly
        if force || (rawView.string != block.text.string && !rawView.hasMarkedText()) {
            let selection = rawView.selectedOffsets
            rawView.apply(NoteText(block.text.string), selection: nil)
            if let storage = rawView.textStorage, storage.length > 0 {
                storage.setAttributes(attributes, range: NSRange(location: 0, length: storage.length))
            }
            rawView.selectedOffsets = selection
            measured = nil
        }
        label.stringValue = kindLabel
        setAccessibilityLabel("\(kindLabel) kept as written")
        rawView.setAccessibilityLabel("\(kindLabel) source")
        refreshCard()
        needsLayout = true
    }

    override func readOnlyDidChange() {
        rawView.isEditable = !isReadOnly
    }

    override func themeDidChange() {
        super.themeDidChange()
        apply(block, force: false)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshCard()
    }

    private func refreshCard() {
        NoteAnimation.withoutAnimation { card.layer?.backgroundColor = NoteTheme.resolved(NoteTheme.codeBackground, in: self) }
    }

    private func textHeight(width: CGFloat) -> CGFloat {
        let available = max(40, width - Self.padding.left - Self.padding.right)
        let text = rawView.string
        if let measured, measured.width == available, measured.text == text { return measured.height }
        guard let layoutManager = rawView.layoutManager, let container = rawView.textContainer else { return Self.lineHeight }
        container.size = NSSize(width: available, height: .greatestFiniteMagnitude)
        layoutManager.ensureLayout(for: container)
        let height = text.isEmpty ? Self.lineHeight : max(Self.lineHeight, ceil(layoutManager.usedRect(for: container).height))
        measured = (available, text, height)
        return height
    }

    override func measureHeight(width: CGFloat) -> CGFloat {
        Self.padding.top + textHeight(width: width) + Self.padding.bottom
    }

    override var handleAnchorY: CGFloat { Self.padding.top + Self.lineHeight / 2 }

    override func layout() {
        super.layout()
        NoteAnimation.withoutAnimation {
            card.frame = bounds
            let labelSize = label.intrinsicContentSize
            let labelWidth = ceil(label.attributedStringValue.size().width) + 6
            icon.frame = NSRect(x: Self.padding.left, y: 9, width: 12, height: 12)
            label.frame = NSRect(x: icon.frame.maxX + 5, y: (15 - labelSize.height / 2).rounded(), width: max(labelSize.width, labelWidth),
                                 height: labelSize.height)
            let available = max(40, bounds.width - Self.padding.left - Self.padding.right)
            rawView.frame = NSRect(x: Self.padding.left, y: Self.padding.top, width: available, height: textHeight(width: bounds.width))
        }
    }

    override func mouseDown(with event: NSEvent) {
        let local = rawView.convert(event.locationInWindow, from: nil)
        let clamped = NSPoint(x: max(0, local.x), y: min(max(0, local.y), max(0, rawView.bounds.height - 1)))
        window?.makeFirstResponder(rawView)
        let offset = rawView.offset(at: clamped)
        rawView.selectedOffsets = offset..<offset
    }

    private func rawDidChange() {
        measured = nil
        needsLayout = true
        guard window != nil else { return }
        editor?.canvas.blockHeightDidChange(blockID)
    }

    private func exitBelow(trimmingBlankLine: Bool) {
        guard let editor else { return }
        let current = rawView.string
        let trimmed = trimmingBlankLine ? NoteCodeEditing.trimmedForExit(current) : current
        let fresh = NoteBlock.paragraph()
        let id = blockID
        editor.session.edit("New Block", selection: .caret(NotePosition(fresh.id, 0))) { page in
            if trimmed != current { page.update(id) { $0.text = NoteText(trimmed) } }
            page.insert([fresh], .after(id))
        }
        editor.canvas.layoutSubtreeIfNeeded()
        editor.focus(NotePosition(fresh.id, 0))
    }
}
