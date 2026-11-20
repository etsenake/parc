import AppKit

@MainActor
final class NoteEquationTextView: NSTextView {
    var onCommit: (() -> Void)?
    var onCancel: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
        if (event.keyCode == 36 || event.keyCode == 76), modifiers == .command, !hasMarkedText() {
            onCommit?()
            return
        }
        super.keyDown(with: event)
    }

    override func doCommand(by selector: Selector) {
        if selector == #selector(cancelOperation(_:)), !hasMarkedText() {
            onCancel?()
            return
        }
        super.doCommand(by: selector)
    }
}

@MainActor
final class NoteEquationEditorView: NSView, NoteFloatingPanelContent, NSTextViewDelegate {
    static let width: CGFloat = 380
    static let inset: CGFloat = 8
    static let fieldPadding = NSEdgeInsets(top: 7, left: 10, bottom: 7, right: 10)
    static let maximumLines = 8
    static let rowHeight: CGFloat = 30
    static let doneTitle = "Done"

    let textView = NoteEquationTextView()
    var preferredSizeDidChange: (() -> Void)?
    var onChange: ((String) -> Void)?
    var onCommit: (() -> Void)?
    var onCancel: (() -> Void)?
    private let fieldBox = NSView()
    private let scrollView = NSScrollView()
    private let doneButton = NoteChip(doneTitle, style: .filled)
    private let keycap = NoteKeycapLabel("⌘↩")
    private let message = NSTextField(wrappingLabelWithString: "")
    private let warning = NoteIconView(icon: .symbol("exclamationmark.triangle.fill"), pointSize: 11)
    private let draftUndo = UndoManager()
    private var lastSize = NSSize.zero
    private(set) var errorText: String?

    init(source: String) {
        super.init(frame: NSRect(x: 0, y: 0, width: Self.width, height: 80))
        fieldBox.wantsLayer = true
        fieldBox.layer?.cornerRadius = 8
        fieldBox.layer?.cornerCurve = .continuous
        addSubview(fieldBox)
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.contentView.drawsBackground = false
        scrollView.automaticallyAdjustsContentInsets = false
        fieldBox.addSubview(scrollView)
        configureTextView(source)
        scrollView.documentView = textView
        doneButton.onPress = { [weak self] in self?.onCommit?() }
        doneButton.setAccessibilityLabel("Done editing equation")
        addSubview(doneButton)
        keycap.textInk = NoteTheme.menuTertiaryInk
        addSubview(keycap)
        message.font = NoteTheme.nunitoRegular(NoteTheme.menuSubtitleSize)
        message.textColor = NoteTheme.destructiveInk
        message.maximumNumberOfLines = 2
        message.lineBreakMode = .byTruncatingTail
        message.isSelectable = false
        message.isHidden = true
        addSubview(message)
        warning.tint = NoteTheme.destructiveInk
        warning.isHidden = true
        addSubview(warning)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Edit equation")
        refreshFill()
        lastSize = fittingSize
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    private func configureTextView(_ source: String) {
        let font = NoteCodeFont.code(size: 13)
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = Self.lineHeight
        paragraph.maximumLineHeight = Self.lineHeight
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font, .foregroundColor: NoteTheme.ink, .paragraphStyle: paragraph,
            .baselineOffset: max(0, (Self.lineHeight - (font.ascender - font.descender + font.leading)) / 2),
        ]
        textView.isRichText = false
        textView.importsGraphics = false
        textView.drawsBackground = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.typingAttributes = attributes
        textView.insertionPointColor = NoteTheme.caret
        textView.selectedTextAttributes = [.backgroundColor: NoteTheme.selection]
        textView.textStorage?.setAttributedString(NSAttributedString(string: source, attributes: attributes))
        textView.delegate = self
        textView.setAccessibilityLabel("TeX")
        textView.onCommit = { [weak self] in self?.onCommit?() }
        textView.onCancel = { [weak self] in self?.onCancel?() }
    }

    static let lineHeight: CGFloat = 20

    var source: String { textView.string }

    private var fieldHeight: CGFloat {
        guard let layoutManager = textView.layoutManager, let container = textView.textContainer else { return Self.lineHeight }
        container.size = NSSize(width: Self.width - Self.inset * 2 - Self.fieldPadding.left - Self.fieldPadding.right,
                                height: .greatestFiniteMagnitude)
        layoutManager.ensureLayout(for: container)
        let used = textView.string.isEmpty ? Self.lineHeight : ceil(layoutManager.usedRect(for: container).height)
        let lines = min(CGFloat(Self.maximumLines), max(1, (used / Self.lineHeight).rounded(.up)))
        return lines * Self.lineHeight + Self.fieldPadding.top + Self.fieldPadding.bottom
    }

    private var messageHeight: CGFloat {
        guard let errorText else { return 0 }
        let width = messageWidth
        let bounds = NSAttributedString(string: errorText, attributes: [.font: message.font ?? NoteTheme.nunitoRegular(12)])
            .boundingRect(with: NSSize(width: width, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading])
        return min(ceil(bounds.height), ceil((message.font?.boundingRectForFont.height ?? 16) * 2))
    }

    private var actionsWidth: CGFloat { doneButton.intrinsicContentSize.width + 6 + keycap.intrinsicContentSize.width }

    private var messageWidth: CGFloat { Self.width - Self.inset * 2 - actionsWidth - 12 - 16 }

    override var fittingSize: NSSize {
        NSSize(width: Self.width, height: Self.inset + fieldHeight + 6 + max(Self.rowHeight, messageHeight + 8) + Self.inset)
    }

    override var intrinsicContentSize: NSSize { fittingSize }

    override func layout() {
        super.layout()
        let field = fieldHeight
        fieldBox.frame = NSRect(x: Self.inset, y: Self.inset, width: bounds.width - Self.inset * 2, height: field)
        scrollView.frame = NSRect(x: Self.fieldPadding.left, y: Self.fieldPadding.top,
                                  width: fieldBox.bounds.width - Self.fieldPadding.left - Self.fieldPadding.right,
                                  height: field - Self.fieldPadding.top - Self.fieldPadding.bottom)
        textView.minSize = NSSize(width: scrollView.contentSize.width, height: scrollView.contentSize.height)
        textView.maxSize = NSSize(width: scrollView.contentSize.width, height: .greatestFiniteMagnitude)
        textView.frame.size.width = scrollView.contentSize.width
        textView.sizeToFit()
        let rowTop = fieldBox.frame.maxY + 6
        let rowHeight = max(Self.rowHeight, messageHeight + 8)
        let doneWidth = doneButton.intrinsicContentSize.width
        doneButton.frame = NSRect(x: bounds.width - Self.inset - doneWidth, y: (rowTop + (rowHeight - NoteTheme.chipHeight) / 2).rounded(),
                                  width: doneWidth, height: NoteTheme.chipHeight)
        let keySize = keycap.intrinsicContentSize
        keycap.frame = NSRect(x: doneButton.frame.minX - 6 - keySize.width, y: (rowTop + (rowHeight - keySize.height) / 2).rounded(),
                              width: keySize.width, height: keySize.height)
        warning.frame = NSRect(x: Self.inset + 2, y: rowTop + 6, width: 14, height: 14)
        message.frame = NSRect(x: Self.inset + 20, y: rowTop + 4, width: messageWidth, height: messageHeight)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshFill()
    }

    private func refreshFill() {
        NoteAnimation.withoutAnimation { fieldBox.layer?.backgroundColor = NoteTheme.resolved(NoteTheme.fieldFill, in: self) }
    }

    func setError(_ text: String?, range: NSRange?) {
        if let layoutManager = textView.layoutManager {
            let whole = NSRange(location: 0, length: (textView.string as NSString).length)
            layoutManager.removeTemporaryAttribute(.underlineStyle, forCharacterRange: whole)
            layoutManager.removeTemporaryAttribute(.underlineColor, forCharacterRange: whole)
            layoutManager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: whole)
            if text != nil, let range, whole.length > 0 {
                let clamped = NSIntersectionRange(range.length == 0 ? NSRange(location: max(0, min(range.location, whole.length - 1)), length: 1) : range, whole)
                if clamped.length > 0 {
                    layoutManager.addTemporaryAttributes([
                        .underlineStyle: NSUnderlineStyle.single.rawValue,
                        .underlineColor: NoteTheme.destructiveInk,
                        .backgroundColor: NoteTheme.destructiveHighlight,
                    ], forCharacterRange: clamped)
                }
            }
        }
        guard text != errorText else { return }
        errorText = text
        message.stringValue = text ?? ""
        message.isHidden = text == nil
        warning.isHidden = text == nil
        setAccessibilityValue(text)
        if let text { NSAccessibility.post(element: message, notification: .announcementRequested,
                                           userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.low.rawValue]) }
        sizeMayHaveChanged()
    }

    private func sizeMayHaveChanged() {
        needsLayout = true
        let size = fittingSize
        guard size != lastSize else { return }
        lastSize = size
        preferredSizeDidChange?()
    }

    func textDidChange(_ notification: Notification) {
        onChange?(textView.string)
        sizeMayHaveChanged()
    }

    func undoManager(for view: NSTextView) -> UndoManager? { draftUndo }
}

@MainActor
final class NoteEquationBlockView: NoteBlockView {
    static let verticalPadding: CGFloat = 10
    static let minimumHeight: CGFloat = 46
    static let placeholderHeight: CGFloat = 46
    static let horizontalInset: CGFloat = 12
    static let placeholderText = "Add a TeX equation"
    static let displayScale: CGFloat = 1.2

    private var rendering: NoteMathRendering?
    private var draft: String?
    private var panel: NoteFloatingPanel?
    private var editorView: NoteEquationEditorView?
    private var outsideMonitor: Any?
    private var isHovered = false { didSet { if oldValue != isHovered { needsDisplay = true } } }
    private var tracking: NSTrackingArea?
    private var scrollOffset: CGFloat = 0

    override init(block: NoteBlock, editor: NotePageEditor?) {
        super.init(block: block, editor: editor)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        rerender()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    var source: String { draft ?? block.text.string }
    var isEditing: Bool { panel != nil }

    private var pageSettings: NotePageSettings { editor?.session.page.settings ?? NotePageSettings() }

    private var mathSize: CGFloat {
        let body = NoteTheme.bodyFont(pageSettings.font, small: pageSettings.smallText)
        return (NoteMathRenderer.fontSize(matching: body) * Self.displayScale * 4).rounded() / 4
    }

    private var ink: NSColor {
        if let color = block.color, !color.isBackground { return NoteTheme.color(color) }
        return NoteTheme.ink
    }

    private var isBlank: Bool { source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    private var errorFont: NSFont { NoteCodeFont.code(size: 13) }

    private var numbering: NoteMathNumberingContext { editor?.math.context(for: blockID) ?? NoteMathNumberingContext() }
    private var numberingFingerprint = ""

    func mathNumberingDidChange() {
        guard numbering.fingerprint(for: source, display: true) != numberingFingerprint else { return }
        let height = measureHeight(width: bounds.width)
        rerender()
        if measureHeight(width: bounds.width) != height { invalidateHeight() }
    }

    private func linkFrames() -> [NoteMathLinkMark] {
        guard let rendering, rendering.error == nil else { return [] }
        let available = bounds.width - Self.horizontalInset * 2
        let fits = rendering.size.width <= available
        let x = fits ? Self.horizontalInset : Self.horizontalInset - scrollOffset
        let y = ((bounds.height - rendering.size.height) / 2).rounded()
        return rendering.links(width: fits ? available : rendering.size.width).map { link in
            var placed = link
            placed.rect = link.rect.offsetBy(dx: x, dy: y)
            return placed
        }
    }

    private func link(at event: NSEvent) -> NoteMathLinkMark? {
        let point = convert(event.locationInWindow, from: nil)
        return linkFrames().first { $0.rect.insetBy(dx: -2, dy: -2).contains(point) }
    }

    private func refreshLinkTooltip(_ event: NSEvent) {
        if let link = link(at: event), !link.resolved {
            parcTooltip = TooltipConfiguration(NotePageMath.missingReferenceTooltip(link.key), anchor: .bottom, anchorRect: link.rect)
        } else if parcTooltip != nil {
            parcTooltip = nil
        }
    }

    private func rerender() {
        let context = numbering
        numberingFingerprint = context.fingerprint(for: source, display: true)
        rendering = isBlank ? nil : NoteMathRenderer.render(source, fontSize: mathSize, color: ink, display: true, numbering: context)
        let label: String
        if isBlank { label = "Empty equation" } else if let error = rendering?.error { label = "Equation that won’t typeset: \(source). \(error)" }
        else { label = "Equation: \(source)" }
        setAccessibilityLabel(label)
        setAccessibilityHelp(isReadOnly ? nil : "Click to edit the TeX")
        editorView?.setError(rendering?.error, range: rendering?.errorRange)
        clampScroll()
        needsDisplay = true
    }

    override func update(_ block: NoteBlock) {
        super.update(block)
        rerender()
    }

    override func themeDidChange() {
        super.themeDidChange()
        rerender()
    }

    override func readOnlyDidChange() {
        if isReadOnly { closeEditor(commit: true, reselect: false) }
        window?.invalidateCursorRects(for: self)
        rerender()
    }

    override func measureHeight(width: CGFloat) -> CGFloat {
        guard !isBlank else { return Self.placeholderHeight }
        guard let rendering else { return Self.minimumHeight }
        if rendering.error != nil { return Self.minimumHeight }
        return max(Self.minimumHeight, ceil(rendering.size.height) + Self.verticalPadding * 2)
    }

    override var handleAnchorY: CGFloat {
        isBlank || rendering?.error != nil ? Self.minimumHeight / 2 : measureHeight(width: bounds.width) / 2
    }

    private func invalidateHeight() {
        needsLayout = true
        needsDisplay = true
        guard window != nil else { return }
        editor?.canvas.blockHeightDidChange(blockID)
    }

    override func layout() {
        super.layout()
        clampScroll()
        repositionPanel()
    }

    override func setFrameOrigin(_ newOrigin: NSPoint) {
        super.setFrameOrigin(newOrigin)
        repositionPanel()
    }

    override func draw(_ dirtyRect: NSRect) {
        let radius = NoteTheme.blockRadius
        if let color = block.color, color.isBackground {
            NoteTheme.color(color).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()
        }
        if isBlank {
            drawPlaceholder()
        } else if let rendering, rendering.error != nil {
            drawError(rendering)
        } else if let rendering, let context = NSGraphicsContext.current?.cgContext {
            if isHovered && !isEditing && !isReadOnly {
                NoteTheme.hoverFill.setFill()
                NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()
            }
            let available = bounds.width - Self.horizontalInset * 2
            let fits = rendering.size.width <= available
            let x = fits ? Self.horizontalInset : Self.horizontalInset - scrollOffset
            let y = ((bounds.height - rendering.size.height) / 2).rounded()
            context.saveGState()
            context.clip(to: bounds.insetBy(dx: fits ? 0 : Self.horizontalInset / 2, dy: 0))
            rendering.drawFlipped(in: context, at: CGPoint(x: x, y: y), width: fits ? available : rendering.size.width)
            context.restoreGState()
        }
        if isEditing {
            NoteTheme.blockSelection.setFill()
            NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()
        }
    }

    private func drawPlaceholder() {
        let radius = NoteTheme.blockRadius
        (isHovered && !isReadOnly ? NoteTheme.hoverFill : NoteTheme.mediaPlaceholderFill).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()
        let font = NoteTheme.bodyFont(pageSettings.font, small: true)
        let ink = NoteTheme.secondaryInk
        let iconSide: CGFloat = 18
        var x: CGFloat = 14
        if let image = NoteIconRenderer.symbol("x.squareroot", pointSize: 15, weight: .medium) {
            NoteIconRenderer.drawTemplate(image, centeredIn: NSRect(x: x, y: 0, width: iconSide, height: bounds.height), tint: ink)
        }
        x += iconSide + 10
        let text = NSAttributedString(string: Self.placeholderText, attributes: [.font: font, .foregroundColor: ink])
        let size = text.size()
        text.draw(at: NSPoint(x: x, y: ((bounds.height - size.height) / 2).rounded()))
    }

    private func drawError(_ rendering: NoteMathRendering) {
        let radius = NoteTheme.blockRadius
        if isHovered && !isEditing && !isReadOnly {
            NoteTheme.hoverFill.setFill()
            NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()
        }
        let flattened = source.split(whereSeparator: \.isNewline).joined(separator: " ")
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let text = NSAttributedString(string: flattened, attributes: [.font: errorFont, .foregroundColor: NoteTheme.tertiaryInk,
                                                                       .paragraphStyle: paragraph])
        let glyph: CGFloat = 13, gap: CGFloat = 8
        let available = bounds.width - Self.horizontalInset * 2 - glyph - gap
        let width = min(available, ceil(text.size().width))
        let total = glyph + gap + width
        var x = ((bounds.width - total) / 2).rounded()
        let height = ceil(errorFont.ascender - errorFont.descender + errorFont.leading)
        if let image = NoteIconRenderer.symbol("exclamationmark.triangle.fill", pointSize: 11, weight: .semibold) {
            NoteIconRenderer.drawTemplate(image, centeredIn: NSRect(x: x, y: 0, width: glyph, height: bounds.height),
                                          tint: NoteTheme.destructiveInk.withAlphaComponent(0.8))
        }
        x += glyph + gap
        text.draw(with: NSRect(x: x, y: ((bounds.height - height) / 2).rounded(), width: width, height: height),
                  options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = NoteFloatingPanel.allowsHover(for: self, at: event.locationInWindow)
        refreshLinkTooltip(event)
    }

    override func mouseMoved(with event: NSEvent) {
        isHovered = NoteFloatingPanel.allowsHover(for: self, at: event.locationInWindow)
        refreshLinkTooltip(event)
    }

    override func mouseExited(with event: NSEvent) { isHovered = false }

    override func resetCursorRects() {
        if !isReadOnly {
            addCursorRect(bounds, cursor: .pointingHand)
        } else {
            for link in linkFrames() where link.resolved { addCursorRect(link.rect, cursor: .pointingHand) }
        }
    }

    override func scrollWheel(with event: NSEvent) {
        guard let rendering, rendering.error == nil, abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) else {
            super.scrollWheel(with: event)
            return
        }
        let overflow = rendering.size.width - (bounds.width - Self.horizontalInset * 2)
        guard overflow > 0 else { super.scrollWheel(with: event); return }
        scrollOffset -= event.scrollingDeltaX * (event.hasPreciseScrollingDeltas ? 1 : 8)
        clampScroll()
        needsDisplay = true
    }

    private func clampScroll() {
        let overflow = (rendering?.size.width ?? 0) - (bounds.width - Self.horizontalInset * 2)
        scrollOffset = overflow > 0 ? min(max(0, scrollOffset), overflow) : 0
    }

    override func mouseDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection([.shift, .command])
        if modifiers.isEmpty, !isEditing, let link = link(at: event), link.resolved, let editor, editor.math.follow(link) {
            return
        }
        if isReadOnly || !modifiers.isEmpty {
            NoteBlockPointer.selectBlock(self, with: event)
            return
        }
        if isEditing {
            window?.makeFirstResponder(editorView?.textView)
            return
        }
        openEditor()
    }

    override func accessibilityPerformPress() -> Bool {
        guard !isReadOnly else { return false }
        openEditor()
        return true
    }

    override func focus(at offset: Int?, field: NoteTextField = .body) -> Bool {
        guard !isReadOnly else { return false }
        openEditor()
        return isEditing
    }

    func openEditor() {
        guard !isReadOnly, panel == nil, let editor, window != nil else { return }
        draft = block.text.string
        let content = NoteEquationEditorView(source: block.text.string)
        content.frame.size = content.fittingSize
        content.onChange = { [weak self] text in self?.draftDidChange(text) }
        content.onCommit = { [weak self] in self?.closeEditor(commit: true, reselect: true) }
        content.onCancel = { [weak self] in self?.closeEditor(commit: false, reselect: true) }
        let floating = NoteFloatingPanel(content: content)
        floating.alignment = .center
        floating.onDismiss = { [weak self, weak floating] in
            guard let self, let floating, self.panel === floating else { return }
            self.finishEditing()
        }
        panel = floating
        editorView = content
        content.setError(rendering?.error, range: rendering?.errorRange)
        floating.present(in: editor.canvas.overlayView, anchor: anchorRect(in: editor.canvas.overlayView), edge: .below)
        window?.makeFirstResponder(content.textView)
        let end = (content.textView.string as NSString).length
        content.textView.setSelectedRange(NSRange(location: end, length: 0))
        outsideMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, let floating = self.panel, event.window === floating.window else { return }
                let inPanel = floating.bounds.contains(floating.convert(event.locationInWindow, from: nil))
                let inBlock = self.bounds.contains(self.convert(event.locationInWindow, from: nil))
                if !inPanel && !inBlock { self.closeEditor(commit: true, reselect: false) }
            }
            return event
        }
        needsDisplay = true
    }

    private func anchorRect(in overlay: NSView) -> NSRect {
        overlay.convert(bounds, from: self)
    }

    private func repositionPanel() {
        guard let panel, let overlay = panel.superview else { return }
        panel.reposition(anchor: anchorRect(in: overlay), edge: .below, animated: false)
    }

    private func draftDidChange(_ text: String) {
        draft = text
        rerender()
        invalidateHeight()
        editor?.math.draftDidChange(text, for: blockID)
    }

    func closeEditor(commit: Bool, reselect: Bool) {
        guard let floating = panel else { return }
        if commit, let final = draft, final != block.text.string {
            editor?.session.updateBlock(blockID, name: "Edit Equation") { $0.text = NoteText(final) }
        }
        finishEditing()
        floating.dismiss(animated: true)
        guard let editor else { return }
        if reselect {
            window?.makeFirstResponder(editor.canvas)
            editor.session.setSelection(.blocks([blockID]))
        }
    }

    private func finishEditing(endingDraft: Bool = true) {
        if let outsideMonitor { NSEvent.removeMonitor(outsideMonitor) }
        outsideMonitor = nil
        panel = nil
        editorView = nil
        draft = nil
        if endingDraft { editor?.math.endDraft(for: blockID) }
        rerender()
        invalidateHeight()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        guard newWindow == nil, let floating = panel else { return }
        let final = draft
        let id = blockID
        finishEditing(endingDraft: false)
        floating.dismiss(animated: false)
        guard let editor else { return }
        DispatchQueue.main.async { [weak editor] in
            guard let editor else { return }
            if let final, let current = editor.session.page.block(id), current.text.string != final {
                editor.session.updateBlock(id, name: "Edit Equation") { $0.text = NoteText(final) }
            }
            editor.math.endDraft(for: id)
        }
    }
}
