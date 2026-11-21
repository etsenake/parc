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
