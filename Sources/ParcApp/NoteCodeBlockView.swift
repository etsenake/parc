import AppKit
import Combine
import CoreText

@MainActor
final class NoteCodeTextView: NoteTextView {
    var indentation: () -> NoteCodeIndent = { .spaces(2) }
    var languageID: () -> String = { "" }
    var onExit: ((_ trimsBlankLine: Bool) -> Void)?
    var onEdit: (() -> Void)?
    var codeAttributes: [NSAttributedString.Key: Any] = [:] {
        didSet { if !codeAttributes.isEmpty { super.typingAttributes = codeAttributes } }
    }

    override var typingAttributes: [NSAttributedString.Key: Any] {
        get { codeAttributes.isEmpty ? super.typingAttributes : codeAttributes }
        set { super.typingAttributes = codeAttributes.isEmpty ? newValue : codeAttributes }
    }

    private func exitsOnCommandReturn(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
        guard event.type == .keyDown, event.keyCode == 36 || event.keyCode == 76, modifiers == .command,
              !hasMarkedText(), isEditable, let onExit else { return false }
        onExit(false)
        return true
    }

    override func keyDown(with event: NSEvent) {
        if exitsOnCommandReturn(event) { return }
        super.keyDown(with: event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if window?.firstResponder === self, exitsOnCommandReturn(event) { return true }
        return super.performKeyEquivalent(with: event)
    }

    override func doCommand(by selector: Selector) {
        guard isEditable, !hasMarkedText() else { super.doCommand(by: selector); return }
        let text = string, range = selectedOffsets
        switch selector {
        case #selector(insertNewline(_:)), #selector(insertLineBreak(_:)), #selector(insertNewlineIgnoringFieldEditor(_:)):
            if NoteCodeEditing.exitsOnReturn(text, selection: range), let onExit {
                onExit(true)
                return
            }
            perform(NoteCodeEditing.newline(in: text, selection: range, indent: indentation(), language: languageID()))
        case #selector(insertTab(_:)), #selector(insertTabIgnoringFieldEditor(_:)):
            perform(NoteCodeEditing.tab(in: text, selection: range, indent: indentation()))
        case #selector(insertBacktab(_:)):
            if let edit = NoteCodeEditing.dedentLines(in: text, selection: range, indent: indentation()) { perform(edit) }
        case #selector(deleteBackward(_:)):
            if let edit = NoteCodeEditing.deleteBackward(in: text, selection: range, indent: indentation()) {
                perform(edit)
            } else {
                super.doCommand(by: selector)
            }
        default:
            super.doCommand(by: selector)
        }
    }

    override func insertText(_ string: Any, replacementRange: NSRange) {
        if isEditable, !hasMarkedText(), replacementRange.location == NSNotFound, let typed = string as? String,
           let edit = NoteCodeEditing.closingBracket(typed, in: self.string, selection: selectedOffsets, indent: indentation()) {
            perform(edit)
            return
        }
        super.insertText(string, replacementRange: replacementRange)
    }

    override func didChangeText() {
        super.didChangeText()
        onEdit?()
    }

    func perform(_ edit: NoteCodeEdit) {
        let range = NSRange(location: edit.range.lowerBound, length: edit.range.count)
        guard let storage = textStorage, shouldChangeText(in: range, replacementString: edit.replacement) else { return }
        storage.replaceCharacters(in: range, with: NSAttributedString(string: edit.replacement, attributes: codeAttributes))
        setSelectedRange(NSRange(location: edit.selection.lowerBound, length: edit.selection.count))
        didChangeText()
        scrollRangeToVisible(selectedRange())
    }
}

@MainActor
final class NoteCodeScrollView: NSScrollView {
    private var routesVertically: Bool?

    override func scrollWheel(with event: NSEvent) {
        if event.phase == .began || (event.phase == [] && event.momentumPhase == []) {
            routesVertically = abs(event.scrollingDeltaY) >= abs(event.scrollingDeltaX)
        }
        let vertical = routesVertically ?? (abs(event.scrollingDeltaY) >= abs(event.scrollingDeltaX))
        if event.phase == .ended || event.phase == .cancelled || event.momentumPhase == .ended { routesVertically = nil }
        if vertical || !hasHorizontalScroller { nextResponder?.scrollWheel(with: event) } else { super.scrollWheel(with: event) }
    }
}

@MainActor
final class NoteCodeLanguagePicker: NSView, NoteFloatingPanelContent {
    let search = NoteSearchField(placeholder: "Search languages")
    let list = NoteMenuList()
    var preferredSizeDidChange: (() -> Void)?
    var onChoose: ((NoteCodeLanguage) -> Void)?
    var onCancel: (() -> Void)?

    static let width: CGFloat = 240
    static let inset: CGFloat = NoteTheme.menuInset

    init(current: String) {
        super.init(frame: .zero)
        let selected = NoteCodeLanguage.named(current)?.id ?? NoteCodeLanguage.plainText.id
        list.fixedWidth = Self.width
        list.maximumHeight = 300
        list.noResultsTitle = "No language by that name."
        list.items = NoteCodeLanguage.all.map {
            NoteMenuList.Item(id: $0.id, title: $0.name, isChecked: $0.id == selected, keywords: $0.aliases)
        }
        list.prepare(origin: .keyboard)
        list.highlight(id: selected, animated: false)
        list.onActivate = { [weak self] item in
            guard let language = NoteCodeLanguage.all.first(where: { $0.id == item.id }) else { return }
            self?.onChoose?(language)
        }
        list.onCancel = { [weak self] in self?.onCancel?() }
        list.preferredSizeDidChange = { [weak self] in
            self?.needsLayout = true
            self?.preferredSizeDidChange?()
        }
        search.bind(to: list)
        addSubview(search)
        addSubview(list)
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    override var fittingSize: NSSize {
        NSSize(width: Self.width, height: Self.inset + NoteTheme.fieldHeight + Self.inset / 2 + list.intrinsicContentSize.height)
    }

    override var intrinsicContentSize: NSSize { fittingSize }

    override func layout() {
        super.layout()
        search.frame = NSRect(x: Self.inset, y: Self.inset, width: bounds.width - Self.inset * 2, height: NoteTheme.fieldHeight)
        let top = Self.inset + NoteTheme.fieldHeight + Self.inset / 2
        list.frame = NSRect(x: 0, y: top, width: bounds.width, height: max(0, bounds.height - top))
    }
}

@MainActor
final class NoteCodeCard: NSView {
    override var isFlipped: Bool { true }
}

@MainActor
final class NoteCodeBar: NSView {
    static let platePadding: CGFloat = 2
    static let plateRadius: CGFloat = 9

    let plate = NSView()
    var isShown = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        plate.wantsLayer = true
        plate.layer?.cornerRadius = Self.plateRadius
        plate.layer?.cornerCurve = .continuous
        plate.layer?.borderWidth = 1
        plate.layer?.shadowOpacity = 1
        plate.layer?.shadowRadius = 6
        plate.layer?.shadowOffset = CGSize(width: 0, height: -1)
        plate.setAccessibilityElement(false)
        addSubview(plate)
        setAccessibilityElement(false)
        refreshPlate()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard isShown, let hit = super.hitTest(point), hit !== self, hit !== plate else { return nil }
        return hit
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshPlate()
    }

    private func refreshPlate() {
        NoteAnimation.withoutAnimation {
            plate.layer?.backgroundColor = NoteTheme.resolved(NoteTheme.menuFill, in: self)
            plate.layer?.borderColor = NoteTheme.resolved(NoteTheme.menuHairline, in: self)
            plate.layer?.shadowColor = NoteTheme.resolved(NoteTheme.menuShadow, in: self)
        }
    }
}

@MainActor
final class NoteCodeCaptionHost: NoteTextHost {
    let blockID: NoteBlockID
    let field: NoteTextField = .caption
    let textView: NoteTextView

    init(blockID: NoteBlockID, textView: NoteTextView) {
        self.blockID = blockID
        self.textView = textView
    }
}

@MainActor
final class NoteCodeBlockView: NoteBlockView, NoteTextHost {
    static let cornerRadius: CGFloat = 8
    static let barInset: CGFloat = 6
    static let barSpacing: CGFloat = 2
    static let captionGap: CGFloat = 6
    static let copiedDuration: TimeInterval = 1.5
    static let synchronousHighlightLimit = 6_000

    let field: NoteTextField = .body
    var textView: NoteTextView { codeView }
    let codeView = NoteCodeTextView()
    let captionView = NoteTextView()
    private lazy var captionHost = NoteCodeCaptionHost(blockID: blockID, textView: captionView)
    private let card = NoteCodeCard()
    private let scrollView = NoteCodeScrollView()
    private let bar = NoteCodeBar()
    private let languageButton = NoteToolbarButton(.text(NoteCodeLanguage.plainText.name), label: "Change language")
    private let captionButton = NoteChip("Caption", icon: .symbol("captions.bubble"))
    private let wrapButton = NoteChip("Wrap", icon: .symbol("arrow.turn.down.left"))
    private let copyButton = NoteChip("Copy", icon: .symbol("doc.on.doc"))
    private var tracking: NSTrackingArea?
    private var isHovering = false
    private var barVisible = false
    private var picker: NoteFloatingPanel?
    private var pickerMonitor: Any?
    private var copiedWork: DispatchWorkItem?
    private var highlightGeneration = 0
    private var paintedCode: String?
    private var paintedLanguage: String?
    private var wantsCaption = false
    private var measuredWidth: CGFloat = -1
    private var measuredText = ""
    private var measuredWrap = false
    private var measuredTextHeight: CGFloat = 0
    private var appliedStyle: StyleKey?
    private let modeControl = NoteDiagramModeControl()
    private let previewDivider = NSView()
    private var preview: NoteMermaidPreviewView?
    private var shownMode: NoteDiagramMode = .code
    private var isEditingCode = false
    private var slidesCardOnce = false
    private lazy var diagramClient = NoteMermaidRenderer.shared.makeClient()
    private var diagramRequest: NoteMermaidRequest?
    private var diagramWork: DispatchWorkItem?
    private var diagramProblemRange: Range<Int>?

    static let modeFadeIn: CFTimeInterval = 0.18
    static let modeFadeOut: CFTimeInterval = 0.12

    private struct StyleKey: Equatable {
        var size: CGFloat
        var lineHeight: CGFloat
        var wrap: Bool
        var tabWidth: Int
    }

    override init(block: NoteBlock, editor: NotePageEditor?) {
        super.init(block: block, editor: editor)
        card.wantsLayer = true
        card.layer?.cornerRadius = Self.cornerRadius
        card.layer?.cornerCurve = .continuous
        card.layer?.masksToBounds = true
        addSubview(card)
        configureScrollView()
        configureCodeView()
        configureCaption()
        configureBar()
        configureDiagram()
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        applyBlock(block, force: true)
        NoteAnimation.observeReduceMotion(self) { [weak self] in
            guard let self else { return }
            NoteAnimation.settle(self.bar)
            NoteAnimation.settle(self.copyButton)
            NoteAnimation.settle(self.card)
            self.settleDiagramViews()
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    var language: NoteCodeLanguage? { NoteCodeLanguage.named(block.props.language) }
    var languageName: String {
        language?.name ?? (block.props.language.isEmpty ? NoteCodeLanguage.plainText.name : block.props.language)
    }
    var languageID: String { language?.id ?? NoteCodeEditing.normalizedLanguage(block.props.language) }
    var isDiagram: Bool { NoteMermaid.isDiagram(block) }

    private var presentedMode: NoteDiagramMode {
        isDiagram ? NoteMermaid.presentedMode(stored: NoteMermaid.storedMode(of: block), editing: isEditingCode) : .code
    }

    private var pageSettings: NotePageSettings { editor?.session.page.settings ?? NotePageSettings() }
    private var codeStyle: NoteTextStyle { NoteTheme.textStyle(.code, small: pageSettings.smallText) }
    private var captionStyle: NoteTextStyle { NoteTheme.textStyle(.caption, font: pageSettings.font, small: pageSettings.smallText) }
    private var codePresentation: NoteTextPresentation { NoteTextPresentation(role: .code, small: pageSettings.smallText) }
    private var captionPresentation: NoteTextPresentation {
        NoteTextPresentation(role: .caption, pageFont: pageSettings.font, small: pageSettings.smallText)
    }
    private var padding: NSEdgeInsets {
        var insets = NoteTheme.codePadding
        insets.top = insets.bottom
        return insets
    }

    override var textHosts: [NoteTextHost] { showsCaption ? [self, captionHost] : [self] }

    private var showsCaption: Bool { !block.props.caption.isEmpty || wantsCaption }

    private func configureScrollView() {
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.verticalScrollElasticity = .none
        scrollView.horizontalScrollElasticity = .automatic
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentView.drawsBackground = false
        scrollView.documentView = codeView
        card.addSubview(scrollView)
    }

    private func configureCodeView() {
        codeView.host = self
        codeView.editor = editor
        codeView.isRichText = false
        codeView.importsGraphics = false
        codeView.allowsImageEditing = false
        codeView.isAutomaticQuoteSubstitutionEnabled = false
        codeView.isAutomaticDashSubstitutionEnabled = false
        codeView.isAutomaticTextReplacementEnabled = false
        codeView.isAutomaticSpellingCorrectionEnabled = false
        codeView.isAutomaticTextCompletionEnabled = false
        codeView.isAutomaticLinkDetectionEnabled = false
        codeView.isAutomaticDataDetectionEnabled = false
        codeView.isContinuousSpellCheckingEnabled = false
        codeView.isGrammarCheckingEnabled = false
        codeView.smartInsertDeleteEnabled = false
        codeView.usesFindBar = false
        codeView.layoutManager?.allowsNonContiguousLayout = false
        codeView.inputRulesEnabled = false
        codeView.presentation = codePresentation
        codeView.placeholder = NoteTheme.placeholder(for: .code)
        codeView.setAccessibilityLabel("Code")
        codeView.indentation = { [weak self] in
            guard let self else { return .spaces(2) }
            return NoteCodeEditing.indent(forLanguage: self.languageID, text: self.codeView.string)
        }
        codeView.languageID = { [weak self] in self?.languageID ?? "" }
        codeView.onExit = { [weak self] trims in self?.exitBelow(trimmingBlankLine: trims) }
        codeView.onEdit = { [weak self] in self?.codeDidChange() }
    }

    private func configureCaption() {
        captionView.host = captionHost
        captionView.editor = editor
        captionView.presentation = captionPresentation
        captionView.placeholder = NoteTheme.captionPlaceholder
        captionView.placeholderShowsWhenUnfocused = true
        captionView.onFocusChange = { [weak self] focused in
            if !focused { self?.captionDidEndEditing() }
        }
        captionView.setAccessibilityLabel("Caption")
        addSubview(captionView)
    }

    private func configureBar() {
        bar.alphaValue = 0
        bar.layer?.opacity = 0
        bar.isHidden = true
        card.addSubview(bar)
        languageButton.showsDisclosure = true
        languageButton.onPress = { [weak self] in self?.toggleLanguagePicker() }
        captionButton.onPress = { [weak self] in self?.addCaption() }
        wrapButton.onPress = { [weak self] in self?.toggleWrap() }
        copyButton.onPress = { [weak self] in self?.copyCode() }
        for button in [languageButton, captionButton, wrapButton, copyButton] { bar.addSubview(button) }
        captionButton.setAccessibilityHelp("Adds a caption under the code")
        wrapButton.setAccessibilityHelp("Wraps long lines instead of scrolling sideways")
        copyButton.setAccessibilityLabel("Copy code")
    }

    private func refreshAccessibilityActions() {
        var actions = [NSAccessibilityCustomAction(name: "Copy code") { [weak self] in self?.copyCode(); return true }]
        if !isReadOnly {
            actions.append(NSAccessibilityCustomAction(name: "Change language") { [weak self] in
                self?.toggleLanguagePicker()
                return true
            })
            actions.append(NSAccessibilityCustomAction(name: block.props.wrap ? "Stop wrapping lines" : "Wrap long lines") { [weak self] in
                self?.toggleWrap()
                return true
            })
            if !showsCaption {
                actions.append(NSAccessibilityCustomAction(name: "Add caption") { [weak self] in self?.addCaption(); return true })
            }
            if isDiagram {
                for mode in NoteDiagramMode.allCases where mode != NoteMermaid.storedMode(of: block) {
                    actions.append(NSAccessibilityCustomAction(name: "Show " + mode.title.lowercased()) { [weak self] in
                        self?.chooseDiagramMode(mode)
                        return true
                    })
                }
            }
        }
        setAccessibilityCustomActions(actions)
    }

    override func update(_ block: NoteBlock) {
        super.update(block)
        applyBlock(block, force: false)
    }

    private func applyBlock(_ block: NoteBlock, force: Bool) {
        let style = codeStyle
        let key = StyleKey(size: style.font.pointSize, lineHeight: style.lineHeight, wrap: block.props.wrap,
                           tabWidth: NoteCodeEditing.indent(forLanguage: languageID).width)
        let restyle = force || key != appliedStyle
        if restyle {
            codeView.codeAttributes = codeAttributes(style)
            if codeView.presentation != codePresentation { codeView.presentation = codePresentation }
            appliedStyle = key
        }
        let attributes = codeView.codeAttributes
        codeView.insertionPointColor = NoteTheme.caret
        codeView.selectedTextAttributes = [.backgroundColor: NoteTheme.selection]
        if force || (codeView.string != block.text.string && !codeView.hasMarkedText()) {
            let selection = codeView.selectedOffsets
            codeView.apply(NoteText(block.text.string), selection: nil)
            codeView.textStorage?.setAttributes(attributes, range: NSRange(location: 0, length: (codeView.string as NSString).length))
            codeView.selectedOffsets = selection
            measuredWidth = -1
        } else if restyle, let storage = codeView.textStorage, storage.length > 0 {
            storage.setAttributes(attributes, range: NSRange(location: 0, length: storage.length))
            measuredWidth = -1
        }
        if captionView.presentation != captionPresentation { captionView.presentation = captionPresentation }
        if force || (captionView.noteText != block.props.caption && !captionView.hasMarkedText()) {
            captionView.apply(block.props.caption, selection: nil)
        }
        languageButton.content = .text(languageName)
        languageButton.setAccessibilityLabel("Language: \(languageName)")
        wrapButton.isChecked = block.props.wrap
        modeControl.select(NoteMermaid.storedMode(of: block), animated: !force && window != nil)
        refreshDiagramMode(animated: !force)
        refreshEditable()
        configureWrapping()
        rehighlight(force: force)
        refreshCard()
        refreshDiagram(immediately: force || !isEditingCode)
        setAccessibilityLabel(isDiagram ? "Mermaid diagram" : "Code block, \(languageName)")
        needsLayout = true
    }

    private func codeAttributes(_ style: NoteTextStyle) -> [NSAttributedString.Key: Any] {
        let paragraph = style.paragraphStyle()
        paragraph.lineBreakMode = block.props.wrap ? .byWordWrapping : .byClipping
        let space = NSAttributedString(string: " ", attributes: [.font: style.font]).size().width
        paragraph.tabStops = []
        paragraph.defaultTabInterval = space * CGFloat(NoteCodeEditing.indent(forLanguage: languageID).width)
        return [.font: NoteCodeFont.literal(style.font), .foregroundColor: style.ink, .paragraphStyle: paragraph,
                .baselineOffset: style.baselineOffset, .ligature: 0]
    }

    private func refreshEditable() {
        let editable = !isReadOnly
        codeView.isEditable = editable
        captionView.isEditable = editable
        languageButton.isEnabled = editable
        wrapButton.isEnabled = editable
        modeControl.isEnabled = editable
        captionButton.isHidden = !editable || showsCaption
        layoutBar()
        refreshAccessibilityActions()
    }

    override func readOnlyDidChange() {
        refreshEditable()
        if isReadOnly { closeLanguagePicker() }
    }

    override func themeDidChange() {
        super.themeDidChange()
        measuredWidth = -1
        appliedStyle = nil
        applyBlock(block, force: false)
        rehighlight(force: true)
    }

    private func configureWrapping() {
        guard let container = codeView.textContainer else { return }
        let wrap = block.props.wrap
        scrollView.hasHorizontalScroller = !wrap
        codeView.isHorizontallyResizable = !wrap
        codeView.isVerticallyResizable = false
        container.widthTracksTextView = wrap
        container.heightTracksTextView = false
        codeView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        if !wrap {
            container.size = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        }
    }

    private func textWidth(for width: CGFloat) -> CGFloat {
        max(40, width - padding.left - padding.right)
    }

    private func codeHeight(width: CGFloat) -> CGFloat {
        let available = textWidth(for: width)
        let text = codeView.string
        if measuredWidth == available, measuredText == text, measuredWrap == block.props.wrap { return measuredTextHeight }
        guard let layoutManager = codeView.layoutManager, let container = codeView.textContainer else { return codeStyle.lineHeight }
        if block.props.wrap {
            container.size = NSSize(width: available, height: CGFloat.greatestFiniteMagnitude)
        }
        layoutManager.ensureLayout(for: container)
        var used = layoutManager.usedRect(for: container).height
        let lineHeight = codeStyle.lineHeight
        if (text as NSString).length == 0 { used = lineHeight }
        let height = max(lineHeight, ceil(used))
        measuredWidth = available
        measuredText = text
        measuredWrap = block.props.wrap
        measuredTextHeight = height
        return height
    }

    private func captionHeight(width: CGFloat) -> CGFloat {
        guard showsCaption, let layoutManager = captionView.layoutManager, let container = captionView.textContainer else { return 0 }
        container.size = NSSize(width: max(1, width), height: CGFloat.greatestFiniteMagnitude)
        layoutManager.ensureLayout(for: container)
        let line = captionStyle.lineHeight
        let used = captionView.string.isEmpty ? line : ceil(layoutManager.usedRect(for: container).height)
        return max(line, used)
    }

    private var dividerHeight: CGFloat { shownMode == .split ? 1 : 0 }

    private func codeSectionHeight(width: CGFloat) -> CGFloat {
        shownMode.showsCode ? padding.top + codeHeight(width: width) + padding.bottom : 0
    }

    private func previewHeight(width: CGFloat) -> CGFloat {
        guard shownMode.showsDiagram, let preview else { return 0 }
        return preview.height(for: width)
    }

    private func cardHeight(width: CGFloat) -> CGFloat {
        codeSectionHeight(width: width) + dividerHeight + previewHeight(width: width)
    }

    override func measureHeight(width: CGFloat) -> CGFloat {
        let caption = captionHeight(width: width)
        return cardHeight(width: width) + (caption > 0 ? Self.captionGap + caption : 0)
    }

    override var handleAnchorY: CGFloat { padding.top + codeStyle.lineHeight / 2 }

    override func layout() {
        super.layout()
        NoteAnimation.withoutAnimation {
            let width = bounds.width
            let cardHeight = self.cardHeight(width: width)
            let cardFrame = NSRect(x: 0, y: 0, width: width, height: cardHeight)
            if slidesCardOnce, abs(card.frame.width - width) < 0.5, card.frame != cardFrame {
                NoteAnimation.slide(card, to: cardFrame, spring: .reorder)
            } else {
                card.frame = cardFrame
            }
            slidesCardOnce = false
            let textHeight = codeHeight(width: width)
            let available = textWidth(for: width)
            scrollView.frame = NSRect(x: padding.left, y: padding.top, width: available, height: textHeight)
            if block.props.wrap {
                codeView.frame = NSRect(x: 0, y: 0, width: available, height: textHeight)
            } else {
                let used = codeView.layoutManager.flatMap { manager in codeView.textContainer.map { manager.usedRect(for: $0).width } } ?? 0
                codeView.frame = NSRect(x: 0, y: 0, width: max(available, ceil(used) + 2), height: textHeight)
            }
            let codeSection = codeSectionHeight(width: width)
            previewDivider.frame = NSRect(x: 0, y: codeSection, width: width, height: 1)
            if let preview {
                preview.frame = NSRect(x: 0, y: codeSection + dividerHeight, width: width, height: preview.height(for: width))
            }
            layoutBar()
            let caption = captionHeight(width: width)
            captionView.isHidden = caption == 0
            captionView.frame = NSRect(x: 0, y: cardHeight + Self.captionGap, width: width, height: caption)
        }
    }

    private var barButtons: [NSView] { [copyButton, wrapButton, captionButton, languageButton, modeControl].filter { !$0.isHidden } }

    private func layoutBar() {
        let width = card.bounds.width
        let height = NoteTheme.chipHeight
        let pad = NoteCodeBar.platePadding
        bar.frame = NSRect(x: 0, y: 0, width: width, height: Self.barInset * 2 + height + pad * 2)
        let y = Self.barInset + pad
        var x = width - Self.barInset - pad
        for button in barButtons {
            let buttonWidth = button.intrinsicContentSize.width
            x -= buttonWidth
            button.frame = NSRect(x: x, y: y, width: buttonWidth, height: height)
            x -= Self.barSpacing
        }
        let left = x + Self.barSpacing - pad
        bar.plate.frame = NSRect(x: left, y: Self.barInset, width: max(0, width - Self.barInset - left), height: height + pad * 2)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshCard()
        refreshDiagram(immediately: true)
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        if superview != nil { refreshDiagram(immediately: true) } else { cancelDiagram() }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { refreshDiagram(immediately: true) }
    }

    private func refreshCard() {
        let fill: NSColor
        if let color = block.color, color.isBackground { fill = NoteTheme.color(color) } else { fill = NoteTheme.codeBackground }
        NoteAnimation.withoutAnimation {
            card.layer?.backgroundColor = NoteTheme.resolved(fill, in: self)
            previewDivider.layer?.backgroundColor = NoteTheme.resolved(NoteTheme.separator, in: self)
        }
    }

    private func codeDidChange() {
        measuredWidth = -1
        clearProblemMarks()
        refreshDiagram(immediately: false)
        rehighlight()
        needsLayout = true
        reportHeightChange()
    }

    private func reportHeightChange() {
        guard window != nil else { return }
        editor?.canvas.blockHeightDidChange(blockID)
    }

    func rehighlight(force: Bool = false) {
        let code = codeView.string
        let language = languageID
        guard force || code != paintedCode || language != paintedLanguage else { return }
        paintedCode = code
        paintedLanguage = language
        highlightGeneration &+= 1
        let generation = highlightGeneration
        guard let layoutManager = codeView.layoutManager else { return }
        guard NoteCodeLanguage.named(language) != nil, language != NoteCodeLanguage.plainText.id else {
            layoutManager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: NSRange(location: 0, length: (code as NSString).length))
            layoutManager.removeTemporaryAttribute(.font, forCharacterRange: NSRange(location: 0, length: (code as NSString).length))
            return
        }
        if (code as NSString).length <= Self.synchronousHighlightLimit {
            paint(NoteSyntaxHighlighter.tokens(in: code, language: language), for: code)
            return
        }
        Task.detached(priority: .userInitiated) { [weak self] in
            let tokens = NoteSyntaxHighlighter.tokens(in: code, language: language)
            await MainActor.run { [weak self] in
                guard let self, self.highlightGeneration == generation, self.codeView.string == code else { return }
                self.paint(tokens, for: code)
            }
        }
    }

    private func paint(_ tokens: [NoteSyntaxToken], for code: String) {
        guard let layoutManager = codeView.layoutManager else { return }
        let length = (code as NSString).length
        let whole = NSRange(location: 0, length: length)
        layoutManager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: whole)
        layoutManager.removeTemporaryAttribute(.font, forCharacterRange: whole)
        let style = codeStyle
        let bold = NoteCodeFont.literal(NoteTheme.boldCodeFont(size: style.font.pointSize))
        let italic = NoteCodeFont.literal(NSFontManager.shared.convert(style.font, toHaveTrait: .italicFontMask))
        for token in tokens where token.range.lowerBound < length {
            let range = NSRange(location: token.range.lowerBound, length: min(token.range.upperBound, length) - token.range.lowerBound)
            guard range.length > 0 else { continue }
            let name = token.kind.rawValue
            var attributes: [NSAttributedString.Key: Any] = [.foregroundColor: NoteTheme.syntaxColor(name)]
            if NoteTheme.syntaxIsBold(name) || token.kind == .strong { attributes[.font] = bold }
            if NoteTheme.syntaxIsItalic(name) || token.kind == .emphasis { attributes[.font] = italic }
            layoutManager.addTemporaryAttributes(attributes, forCharacterRange: range)
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .cursorUpdate, .activeInKeyWindow, .inVisibleRect],
                                  owner: self)
        addTrackingArea(area)
        tracking = area
    }

    private func applyPointerCursor(for event: NSEvent) -> Bool {
        guard let content = window?.contentView,
              let hit = content.hitTest(content.superview?.convert(event.locationInWindow, from: nil) ?? event.locationInWindow)
        else { return false }
        if hit === self {
            NSCursor.arrow.set()
            return true
        }
        guard hit === card || hit === scrollView || hit === scrollView.contentView else { return false }
        (shownMode.showsCode ? NSCursor.iBeam : NSCursor.arrow).set()
        return true
    }

    override func cursorUpdate(with event: NSEvent) {
        if !applyPointerCursor(for: event) { super.cursorUpdate(with: event) }
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = NoteFloatingPanel.allowsHover(for: self, at: event.locationInWindow)
        refreshBar()
    }

    override func mouseMoved(with event: NSEvent) {
        _ = applyPointerCursor(for: event)
        let allowed = NoteFloatingPanel.allowsHover(for: self, at: event.locationInWindow)
        if allowed != isHovering {
            isHovering = allowed
            refreshBar()
        }
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        refreshBar()
    }

    private func refreshBar() {
        let visible = isHovering || picker != nil || copiedWork != nil
        guard visible != barVisible else { return }
        barVisible = visible
        bar.isShown = visible
        if visible { bar.isHidden = false }
        NoteAnimation.fade(bar, visible: visible, duration: NoteAnimation.hoverDuration) { [weak self] in
            guard let self, !self.barVisible else { return }
            self.bar.isHidden = true
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if card.frame.contains(point) {
            if let preview, !preview.isHidden, shownMode.showsDiagram,
               preview.frame.contains(card.convert(event.locationInWindow, from: nil)) {
                if isReadOnly { super.mouseDown(with: event) } else { beginEditing(at: (codeView.string as NSString).length) }
                return
            }
            guard shownMode.showsCode else { super.mouseDown(with: event); return }
            let local = codeView.convert(event.locationInWindow, from: nil)
            let clamped = NSPoint(x: max(0, local.x), y: min(max(0, local.y), codeView.bounds.height - 1))
            window?.makeFirstResponder(codeView)
            let offset = codeView.offset(at: clamped)
            codeView.selectedOffsets = offset..<offset
            return
        }
        super.mouseDown(with: event)
    }

    override func focus(at offset: Int?, field: NoteTextField = .body) -> Bool {
        if field == .caption, !showsCaption {
            wantsCaption = true
            invalidateHeight()
        }
        let revealsCode = field == .body && isDiagram && !shownMode.showsCode
        if revealsCode {
            isEditingCode = true
            refreshDiagramMode(animated: true)
            layoutSubtreeIfNeeded()
        }
        let focused = super.focus(at: offset, field: field)
        if revealsCode, !focused {
            isEditingCode = false
            refreshDiagramMode(animated: false)
        }
        return focused
    }

    private func invalidateHeight() {
        refreshEditable()
        needsLayout = true
        reportHeightChange()
    }

    private func exitBelow(trimmingBlankLine: Bool) {
        guard let editor else { return }
        let current = codeView.string
        let trimmed = trimmingBlankLine ? NoteCodeEditing.trimmedForExit(current) : current
        let fresh = NoteBlock.paragraph()
        editor.session.edit("New Block", selection: .caret(NotePosition(fresh.id, 0))) { page in
            if trimmed != current { page.update(blockID) { $0.text = NoteText(trimmed) } }
            page.insert([fresh], .after(blockID))
        }
        editor.canvas.layoutSubtreeIfNeeded()
        editor.focus(NotePosition(fresh.id, 0))
    }

    private func addCaption() {
        guard !isReadOnly else { return }
        wantsCaption = true
        invalidateHeight()
        layoutSubtreeIfNeeded()
        window?.makeFirstResponder(captionView)
        captionView.selectedOffsets = captionView.noteText.length..<captionView.noteText.length
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if newWindow == nil {
            closeLanguagePicker()
            cancelDiagram()
        }
    }

    private func captionDidEndEditing() {
        guard wantsCaption, block.props.caption.isEmpty, captionView.string.isEmpty else { return }
        wantsCaption = false
        invalidateHeight()
    }

    private func toggleWrap() {
        guard let editor, !isReadOnly else { return }
        let wrap = !block.props.wrap
        editor.session.updateBlock(blockID, name: wrap ? "Wrap Code" : "Unwrap Code") { $0.props.wrap = wrap }
    }

    private func copyCode() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(codeView.string, forType: .string)
        copiedWork?.cancel()
        copyButton.flash("Copied!", icon: .symbol("checkmark"), duration: Self.copiedDuration)
        glideBar()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.copiedWork = nil
                self.glideBar()
                self.refreshBar()
            }
        }
        copiedWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.copiedDuration + 0.02, execute: work)
    }

    private func glideBar() {
        let views = barButtons + [bar.plate]
        let before = views.map(\.frame)
        layoutBar()
        guard window != nil, !NoteAnimation.reduceMotion else { return }
        for (view, previous) in zip(views, before) where previous != view.frame && !previous.isEmpty {
            let goal = view.frame
            NoteAnimation.withoutAnimation { view.frame = previous }
            _ = NoteAnimation.slide(view, to: goal, spring: .highlight)
        }
    }

    private func toggleLanguagePicker() {
        if picker != nil { closeLanguagePicker(); return }
        guard let editor, !isReadOnly else { return }
        let content = NoteCodeLanguagePicker(current: block.props.language)
        content.frame.size = content.fittingSize
        let panel = NoteFloatingPanel(content: content)
        content.onChoose = { [weak self] language in self?.choose(language) }
        content.onCancel = { [weak self] in
            self?.closeLanguagePicker()
            self?.restoreCodeFocus()
        }
        panel.onDismiss = { [weak self, weak panel] in
            guard let self, self.picker === panel else { return }
            self.picker = nil
            self.removePickerMonitor()
            self.refreshBar()
            self.syncEditingSoon()
        }
        let overlay = editor.canvas.overlayView
        let anchor = overlay.convert(languageButton.bounds, from: languageButton)
        picker = panel
        panel.present(in: overlay, anchor: anchor, edge: .below)
        content.search.focus()
        refreshBar()
        pickerMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, let panel = self.picker, event.window === panel.window else { return }
                let inPanel = panel.bounds.contains(panel.convert(event.locationInWindow, from: nil))
                let onButton = self.languageButton.bounds.contains(self.languageButton.convert(event.locationInWindow, from: nil))
                if !inPanel && !onButton { self.closeLanguagePicker() }
            }
            return event
        }
    }

    private func removePickerMonitor() {
        if let pickerMonitor { NSEvent.removeMonitor(pickerMonitor) }
        pickerMonitor = nil
    }

    private func closeLanguagePicker() {
        guard let panel = picker else { return }
        picker = nil
        removePickerMonitor()
        panel.dismiss(animated: true)
        refreshBar()
        syncEditingSoon()
    }

    private func choose(_ language: NoteCodeLanguage) {
        closeLanguagePicker()
        guard let editor else { return }
        let value = language.id == NoteCodeLanguage.plainText.id ? "" : language.id
        if NoteCodeLanguage.named(block.props.language)?.id != NoteCodeLanguage.named(value)?.id || block.props.language != value {
            editor.session.updateBlock(blockID, name: "Code Language") { $0.props.language = value }
        }
        restoreCodeFocus()
    }

    private func restoreCodeFocus() {
        let selection = codeView.selectedOffsets
        window?.makeFirstResponder(codeView)
        codeView.selectedOffsets = selection
    }

    private func configureDiagram() {
        previewDivider.wantsLayer = true
        previewDivider.isHidden = true
        previewDivider.setAccessibilityElement(false)
        card.addSubview(previewDivider, positioned: .below, relativeTo: bar)
        modeControl.isHidden = true
        modeControl.onChoose = { [weak self] mode in self?.chooseDiagramMode(mode) }
        bar.addSubview(modeControl)
        codeView.onFocusChange = { [weak self] focused in self?.codeFocusDidChange(focused) }
    }

    private func ensurePreview() {
        guard preview == nil else { return }
        let view = NoteMermaidPreviewView()
        view.isHidden = true
        card.addSubview(view, positioned: .below, relativeTo: bar)
        preview = view
    }

    private func refreshDiagramMode(animated: Bool) {
        let mode = presentedMode
        modeControl.isHidden = !isDiagram
        wrapButton.isHidden = !mode.showsCode
        defer { layoutBar() }
        guard mode != shownMode else { return }
        let animate = animated && window != nil && !NoteAnimation.reduceMotion
        shownMode = mode
        if mode.showsDiagram { ensurePreview() }
        setShown(scrollView, mode.showsCode, animate: animate)
        setShown(previewDivider, mode == .split, animate: animate)
        if let preview { setShown(preview, mode.showsDiagram, animate: animate) }
        if mode.showsDiagram { refreshDiagram(immediately: true) } else { cancelDiagram() }
        slidesCardOnce = animate
        needsLayout = true
        reportHeightChange()
    }

    private func isShownInCurrentMode(_ view: NSView) -> Bool {
        if view === scrollView { return shownMode.showsCode }
        if view === previewDivider { return shownMode == .split }
        return shownMode.showsDiagram
    }

    private func setShown(_ view: NSView, _ shown: Bool, animate: Bool) {
        if shown {
            let wasHidden = view.isHidden
            view.isHidden = false
            if animate, wasHidden {
                NoteAnimation.withoutAnimation { view.alphaValue = 0; view.layer?.opacity = 0 }
                NoteAnimation.fade(view, visible: true, duration: Self.modeFadeIn)
            } else if !animate {
                if let layer = view.layer { NoteAnimation.settle(layer) }
                NoteAnimation.withoutAnimation { view.alphaValue = 1; view.layer?.opacity = 1 }
            }
        } else if !view.isHidden {
            guard animate else {
                view.isHidden = true
                NoteAnimation.withoutAnimation { view.alphaValue = 1; view.layer?.opacity = 1 }
                return
            }
            NoteAnimation.fade(view, visible: false, duration: Self.modeFadeOut) { [weak self, weak view] in
                guard let self, let view, !self.isShownInCurrentMode(view) else { return }
                view.isHidden = true
            }
        }
    }

    private func settleDiagramViews() {
        var views: [(NSView, Bool)] = [(scrollView, shownMode.showsCode), (previewDivider, shownMode == .split)]
        if let preview { views.append((preview, shownMode.showsDiagram)) }
        for (view, shown) in views {
            view.isHidden = !shown
            NoteAnimation.withoutAnimation { view.alphaValue = 1; view.layer?.opacity = 1 }
        }
        needsLayout = true
    }

    private func codeFocusDidChange(_ focused: Bool) {
        if !focused, picker != nil { return }
        guard focused != isEditingCode else { return }
        isEditingCode = focused
        refreshDiagramMode(animated: true)
    }

    private func syncEditingSoon() {
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.codeFocusDidChange(self.window?.firstResponder === self.codeView)
            }
        }
    }

    private func beginEditing(at offset: Int) {
        guard !isReadOnly else { return }
        isEditingCode = true
        refreshDiagramMode(animated: true)
        layoutSubtreeIfNeeded()
        window?.makeFirstResponder(codeView)
        codeView.selectedOffsets = offset..<offset
    }

    private func chooseDiagramMode(_ mode: NoteDiagramMode) {
        guard let editor, !isReadOnly, isDiagram else { return }
        let stored: NoteDiagramMode? = mode == .preview ? nil : mode
        modeControl.select(mode, animated: true)
        if block.props.diagramMode != stored {
            editor.session.updateBlock(blockID, name: "Diagram View") { $0.props.diagramMode = stored }
        }
        guard mode == .preview, window?.firstResponder === codeView else { return }
        editor.selection.select(.blocks([blockID]))
        isEditingCode = window?.firstResponder === codeView
        refreshDiagramMode(animated: true)
    }

    private func refreshDiagram(immediately: Bool) {
        guard isDiagram, shownMode.showsDiagram, let preview else { cancelDiagram(); return }
        let renderer = NoteMermaidRenderer.shared
        let request = NoteMermaidRequest(source: codeView.string, theme: .note(appearance: effectiveAppearance, settings: pageSettings))
        guard request != diagramRequest else { return }
        guard NoteMermaid.hasContent(request.source) else {
            cancelDiagram()
            diagramRequest = request
            markProblem(nil, source: request.source)
            present(art: nil, problem: nil, message: NoteMermaidPreviewView.emptyTitle, animated: false)
            return
        }
        diagramRequest = request
        diagramWork?.cancel()
        diagramWork = nil
        if let hit = renderer.cached(request) {
            renderer.cancel(diagramClient)
            show(hit, for: request, animated: preview.hasDrawing)
            return
        }
        if !preview.hasDrawing, preview.problem == nil {
            if let known = renderer.lastKnown(request) {
                show(known, for: request, animated: false)
            } else {
                present(art: nil, problem: nil, message: NoteMermaidPreviewView.drawingTitle, animated: false)
            }
        }
        guard superview != nil else { return }
        if immediately || !preview.hasDrawing {
            startDiagram(request)
            return
        }
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.startDiagram(request) }
        }
        diagramWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + NoteMermaid.typingDelay, execute: work)
    }

    private func startDiagram(_ request: NoteMermaidRequest) {
        diagramWork = nil
        guard request == diagramRequest else { return }
        NoteMermaidRenderer.shared.render(request, client: diagramClient) { [weak self] result in
            guard let self, request == self.diagramRequest else { return }
            self.show(result, for: request, animated: true)
        }
    }

    private func cancelDiagram() {
        diagramWork?.cancel()
        diagramWork = nil
        guard diagramRequest != nil else { return }
        diagramRequest = nil
        NoteMermaidRenderer.shared.cancel(diagramClient)
    }

    private func show(_ result: NoteMermaidResult, for request: NoteMermaidRequest, animated: Bool) {
        switch result {
        case .art(let art):
            markProblem(nil, source: request.source)
            present(art: art, problem: nil, message: nil, animated: animated)
        case .failure(let message), .unavailable(let message):
            let problem = NoteMermaidProblem(message: message)
            markProblem(problem, source: request.source)
            present(art: preview?.art, problem: problem, message: nil, animated: animated)
        }
    }

    private func present(art: NoteMermaidArt?, problem: NoteMermaidProblem?, message: String?, animated: Bool) {
        guard let preview else { return }
        let width = bounds.width
        let before = preview.height(for: width)
        preview.show(art: art, problem: problem, message: message, animated: animated)
        needsLayout = true
        if preview.height(for: width) != before { reportHeightChange() }
    }

    private func markProblem(_ problem: NoteMermaidProblem?, source: String) {
        clearProblemMarks()
        guard let problem, let range = problem.range(in: source), NoteMermaid.normalizedSource(codeView.string) == source,
              let layoutManager = codeView.layoutManager, range.upperBound <= (codeView.string as NSString).length else { return }
        layoutManager.addTemporaryAttributes([.underlineStyle: NSUnderlineStyle([.single, .patternDot]).rawValue,
                                              .underlineColor: NoteTheme.destructiveInk],
                                             forCharacterRange: NSRange(location: range.lowerBound, length: range.count))
        diagramProblemRange = range
    }

    private func clearProblemMarks() {
        guard diagramProblemRange != nil, let layoutManager = codeView.layoutManager else { return }
        diagramProblemRange = nil
        let whole = NSRange(location: 0, length: (codeView.string as NSString).length)
        layoutManager.removeTemporaryAttribute(.underlineStyle, forCharacterRange: whole)
        layoutManager.removeTemporaryAttribute(.underlineColor, forCharacterRange: whole)
    }
}
