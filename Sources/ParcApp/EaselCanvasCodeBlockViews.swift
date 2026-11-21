import AppKit
import CoreText
import ParcCore

extension NSAttributedString.Key {
    static let easelSyntaxFamily = NSAttributedString.Key("ParcEaselSyntaxFamily")
}

@MainActor
enum EaselCodeBlockStyle {
    static let synchronousHighlightLimit = 6_000
    static let staticHighlightLimit = 60_000
    static let cardFill = NoteTheme.codeBackground
    static let cardStroke = NoteTheme.separator
    static let labelInk = NoteTheme.secondaryInk
    private static var literalFonts: [String: NSFont] = [:]

    static func literal(_ font: NSFont) -> NSFont {
        let key = font.fontName + "@" + String(describing: font.pointSize)
        if let cached = literalFonts[key] { return cached }
        let settings: [[NSFontDescriptor.FeatureKey: Int]] = [
            [.typeIdentifier: kLigaturesType, .selectorIdentifier: kCommonLigaturesOffSelector],
            [.typeIdentifier: kLigaturesType, .selectorIdentifier: kRareLigaturesOffSelector],
            [.typeIdentifier: kContextualAlternatesType, .selectorIdentifier: kContextualAlternatesOffSelector],
        ]
        let literal = NSFont(descriptor: font.fontDescriptor.addingAttributes([.featureSettings: settings]), size: font.pointSize) ?? font
        literalFonts[key] = literal
        return literal
    }

    static var textStyle: NoteTextStyle { NoteTheme.textStyle(.code) }
    static var font: NSFont { literal(textStyle.font) }
    static var labelFont: NSFont { NoteTheme.chromeFont(12.5) }
    private static var tokenStyles: [NoteSyntaxKind: [NSAttributedString.Key: Any]] = [:]

    static func indent(language: String?, text: String) -> NoteCodeIndent {
        NoteCodeEditing.indent(forLanguage: EaselCodeBlock.language(language).id, text: text)
    }

    static func attributes(language: String?) -> [NSAttributedString.Key: Any] {
        let style = textStyle
        let paragraph = style.paragraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.tabStops = []
        let space = NSAttributedString(string: " ", attributes: [.font: font]).size().width
        paragraph.defaultTabInterval = space * CGFloat(NoteCodeEditing.indentWidth(forLanguage: EaselCodeBlock.language(language).id))
        return [.font: font, .foregroundColor: style.ink, .paragraphStyle: paragraph, .baselineOffset: style.baselineOffset, .ligature: 0]
    }

    static func tokens(_ code: String, language: String?, limit: Int) -> [NoteSyntaxToken] {
        let resolved = EaselCodeBlock.language(language)
        guard resolved.id != NoteCodeLanguage.plainText.id, (code as NSString).length <= limit else { return [] }
        return EaselCodeTokenCache.tokens(code, language: resolved)
    }

    static func tokenAttributes(_ kind: NoteSyntaxKind) -> [NSAttributedString.Key: Any] {
        if let cached = tokenStyles[kind] { return cached }
        var attributes = NoteTheme.syntaxAttributes(kind, size: textStyle.font.pointSize)
        if let bold = attributes[.font] as? NSFont { attributes[.font] = literal(bold) }
        let family = NoteTheme.syntaxFamily(kind.rawValue)
        if family != "plain" { attributes[.easelSyntaxFamily] = family }
        tokenStyles[kind] = attributes
        return attributes
    }

    static func apply(_ tokens: [NoteSyntaxToken], to storage: NSTextStorage, base: [NSAttributedString.Key: Any]) {
        let length = storage.length
        guard length > 0 else { return }
        storage.beginEditing()
        storage.setAttributes(base, range: NSRange(location: 0, length: length))
        for token in tokens where token.range.lowerBound >= 0 && token.range.lowerBound < length {
            let range = NSRange(location: token.range.lowerBound, length: min(token.range.upperBound, length) - token.range.lowerBound)
            guard range.length > 0 else { continue }
            storage.addAttributes(tokenAttributes(token.kind), range: range)
        }
        storage.endEditing()
    }

    static func attributed(_ code: String, language: String?) -> NSTextStorage {
        let base = attributes(language: language)
        let storage = NSTextStorage(string: code, attributes: base)
        apply(tokens(code, language: language, limit: staticHighlightLimit), to: storage, base: base)
        return storage
    }

    static func lightHex(_ color: NSColor) -> String? {
        var value: String?
        (NSAppearance(named: .aqua) ?? NSAppearance.currentDrawing()).performAsCurrentDrawingAppearance {
            guard let rgb = color.usingColorSpace(.sRGB) else { return }
            value = String(format: "#%02X%02X%02X", Int((rgb.redComponent * 255).rounded()),
                           Int((rgb.greenComponent * 255).rounded()), Int((rgb.blueComponent * 255).rounded()))
        }
        return value
    }

    static func palette() -> EaselCodePalette {
        func swatch(_ name: NSAppearance.Name) -> EaselCodePalette.Swatch {
            let appearance = NSAppearance(named: name) ?? NSAppearance.currentDrawing()
            var syntax: [String: String] = [:]
            for family in EaselCodePalette.standard.light.syntax.keys { syntax[family] = css(NoteTheme.syntaxColor(family), in: appearance) }
            return .init(fill: css(cardFill, in: appearance), line: css(cardStroke, in: appearance),
                         ink: css(NoteTheme.codeInk, in: appearance), syntax: syntax)
        }
        return EaselCodePalette(light: swatch(.aqua), dark: swatch(.darkAqua))
    }

    static func css(_ color: NSColor, in appearance: NSAppearance) -> String {
        var value = "#000000"
        appearance.performAsCurrentDrawingAppearance {
            guard let rgb = color.usingColorSpace(.sRGB) else { return }
            let channels = [rgb.redComponent, rgb.greenComponent, rgb.blueComponent].map { Int(($0 * 255).rounded()) }
            value = rgb.alphaComponent >= 0.999 ? String(format: "#%02X%02X%02X", channels[0], channels[1], channels[2])
                : "rgba(" + channels.map(String.init).joined(separator: ",") + "," + EaselVectorExport.number(Double(rgb.alphaComponent)) + ")"
        }
        return value
    }
}

@MainActor
final class EaselCodeLayout {
    let storage: NSTextStorage
    let manager = NSLayoutManager()
    let container: NSTextContainer
    private(set) var lineCount = 1

    init(code: String, language: String?, width: Double) {
        storage = EaselCodeBlockStyle.attributed(code, language: language)
        container = NSTextContainer(size: NSSize(width: EaselCodeBlock.textWidth(forWidth: width), height: CGFloat.greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        manager.addTextContainer(container)
        storage.addLayoutManager(manager)
        manager.ensureLayout(for: container)
        lineCount = Self.lineCount(manager: manager, container: container)
    }

    static func lineCount(manager: NSLayoutManager, container: NSTextContainer) -> Int {
        manager.ensureLayout(for: container)
        var count = 0
        manager.enumerateLineFragments(forGlyphRange: manager.glyphRange(for: container)) { _, _, _, _, _ in count += 1 }
        if !manager.extraLineFragmentRect.isEmpty { count += 1 }
        return max(1, count)
    }

    func draw(in frame: NSRect) {
        let origin = NSPoint(x: frame.minX + EaselCodeBlock.sidePadding, y: frame.minY + EaselCodeBlock.headerHeight)
        let range = manager.glyphRange(for: container)
        manager.drawBackground(forGlyphRange: range, at: origin)
        manager.drawGlyphs(forGlyphRange: range, at: origin)
    }

    func vectorText() -> EaselVectorText {
        var result = EaselVectorText()
        let text = storage.string as NSString
        manager.enumerateLineFragments(forGlyphRange: manager.glyphRange(for: container)) { [manager, storage] rect, _, _, glyphs, _ in
            let characters = manager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
            storage.enumerateAttributes(in: characters) { attributes, range, _ in
                var start = range.location
                let end = range.location + range.length
                while start < end {
                    var stop = start
                    while stop < end, text.character(at: stop) != 9, text.character(at: stop) != 10, text.character(at: stop) != 13 { stop += 1 }
                    if stop > start {
                        let glyph = manager.glyphIndexForCharacter(at: start)
                        let location = manager.location(forGlyphAt: glyph)
                        let font = attributes[.font] as? NSFont ?? EaselCodeBlockStyle.font
                        let oblique = ((attributes[.obliqueness] as? NSNumber)?.doubleValue ?? 0) > 0
                        var run = EaselVectorTextRun(x: Double(EaselCodeBlock.sidePadding + rect.minX + location.x),
                                                     y: Double(EaselCodeBlock.headerHeight + rect.minY + location.y),
                                                     text: text.substring(with: NSRange(location: start, length: stop - start)),
                                                     fontFamily: EaselVectorExport.codeFontFamily, fontSize: Double(font.pointSize),
                                                     weight: font.fontDescriptor.symbolicTraits.contains(.bold) ? 700 : 400,
                                                     italic: oblique || font.fontDescriptor.symbolicTraits.contains(.italic))
                        run.color = (attributes[.foregroundColor] as? NSColor).flatMap(EaselCodeBlockStyle.lightHex)
                        run.underline = ((attributes[.underlineStyle] as? NSNumber)?.intValue ?? 0) != 0
                        run.syntax = attributes[.easelSyntaxFamily] as? String
                        result.runs.append(run)
                    }
                    start = stop + 1
                }
            }
        }
        return result
    }

    static func vectorText(_ item: EaselItem) -> EaselVectorText {
        EaselCodeLayout(code: item.text, language: item.language, width: item.frame.width).vectorText()
    }

    static func rects(for range: Range<Int>, in item: EaselItem) -> [NSRect]? {
        let layout = EaselCodeLayoutCache.layout(for: item)
        guard !range.isEmpty, range.lowerBound >= 0, range.upperBound <= layout.storage.length else { return nil }
        let glyphs = layout.manager.glyphRange(forCharacterRange: NSRange(location: range.lowerBound, length: range.count), actualCharacterRange: nil)
        var rects: [NSRect] = []
        layout.manager.enumerateEnclosingRects(forGlyphRange: glyphs, withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0),
                                               in: layout.container) { rect, _ in
            guard rect.width.isFinite, rect.height.isFinite, !rect.isEmpty else { return }
            rects.append(rect.offsetBy(dx: item.frame.x + EaselCodeBlock.sidePadding, dy: item.frame.y + EaselCodeBlock.headerHeight).insetBy(dx: -2, dy: -1))
        }
        return rects.isEmpty ? nil : rects
    }
}

@MainActor
enum EaselCodeTokenCache {
    private struct Key: Hashable {
        var text: String
        var language: String
    }
    static let debounceNanoseconds: UInt64 = 100_000_000
    private static let limit = 64
    private static var entries: [Key: [NoteSyntaxToken]] = [:]
    private(set) static var misses = 0

    static func cached(_ code: String, language: String) -> [NoteSyntaxToken]? {
        entries[Key(text: code, language: language)]
    }

    static func store(_ tokens: [NoteSyntaxToken], code: String, language: String) {
        guard (code as NSString).length <= EaselCodeBlockStyle.staticHighlightLimit else { return }
        if entries.count >= limit { entries.removeAll(keepingCapacity: true) }
        entries[Key(text: code, language: language)] = tokens
    }

    static func tokens(_ code: String, language: NoteCodeLanguage) -> [NoteSyntaxToken] {
        if let hit = cached(code, language: language.id) { return hit }
        misses += 1
        let tokens = NoteSyntaxHighlighter.tokens(in: code, language: language)
        store(tokens, code: code, language: language.id)
        return tokens
    }
}

@MainActor
enum EaselCodeLayoutCache {
    private struct Key: Equatable {
        var text: String
        var language: String?
        var width: Double
    }
    private static var entries: [UUID: (key: Key, layout: EaselCodeLayout)] = [:]
    private static let limit = 256

    static func layout(for item: EaselItem) -> EaselCodeLayout {
        let key = Key(text: item.text, language: item.language, width: item.frame.width)
        if let entry = entries[item.id], entry.key == key { return entry.layout }
        let layout = EaselCodeLayout(code: item.text, language: item.language, width: item.frame.width)
        if entries.count >= limit { entries.removeAll(keepingCapacity: true) }
        entries[item.id] = (key, layout)
        return layout
    }

    static func height(for item: EaselItem) -> Double { EaselCodeBlock.height(lines: layout(for: item).lineCount) }
}

@MainActor
final class EaselCodeTextView: NSTextView {
    var language: String?
    @discardableResult override func scrollToVisible(_ rect: NSRect) -> Bool {
        let scrolled = super.scrollToVisible(rect)
        return EaselCaretReveal.keepClear(rect, of: self) || scrolled
    }
    var onEdit: (() -> Void)?
    var onExit: (() -> Void)?
    var onCommandReturn: (() -> Void)?
    var onResign: (() -> Void)?
    var onUndoDocument: (() -> Void)?
    var onRedoDocument: (() -> Void)?
    var canUndoDocument: (() -> Bool)?
    var canRedoDocument: (() -> Bool)?
    let localUndo = UndoManager()
    private var highlightTask: Task<Void, Never>?
    private var paintedCode: String?
    private var paintedLanguage: String??

    var codeAttributes: [NSAttributedString.Key: Any] = [:] {
        didSet { if !codeAttributes.isEmpty { super.typingAttributes = codeAttributes } }
    }

    override var typingAttributes: [NSAttributedString.Key: Any] {
        get { codeAttributes.isEmpty ? super.typingAttributes : codeAttributes }
        set { super.typingAttributes = codeAttributes.isEmpty ? newValue : codeAttributes }
    }

    override var undoManager: UndoManager? { localUndo }

    private var indentation: NoteCodeIndent { EaselCodeBlockStyle.indent(language: language, text: string) }
    private var languageID: String { EaselCodeBlock.language(language).id }
    private var selectedOffsets: Range<Int> {
        let range = selectedRange()
        return range.location..<(range.location + range.length)
    }

    func configure() {
        drawsBackground = false
        isRichText = false
        importsGraphics = false
        allowsUndo = true
        usesFindBar = false
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isAutomaticSpellingCorrectionEnabled = false
        isAutomaticTextCompletionEnabled = false
        isAutomaticLinkDetectionEnabled = false
        isAutomaticDataDetectionEnabled = false
        isContinuousSpellCheckingEnabled = false
        isGrammarCheckingEnabled = false
        smartInsertDeleteEnabled = false
        isHorizontallyResizable = false
        isVerticallyResizable = false
        textContainerInset = .zero
        textContainer?.lineFragmentPadding = 0
        textContainer?.widthTracksTextView = true
        textContainer?.heightTracksTextView = false
        layoutManager?.allowsNonContiguousLayout = false
        insertionPointColor = NoteTheme.caret
        selectedTextAttributes = [.backgroundColor: NoteTheme.selection]
    }

    func load(_ code: String, language: String?) {
        self.language = language
        codeAttributes = EaselCodeBlockStyle.attributes(language: language)
        let selection = selectedRange()
        textStorage?.setAttributedString(NSAttributedString(string: code, attributes: codeAttributes))
        let length = (code as NSString).length
        let start = min(selection.location, length)
        setSelectedRange(NSRange(location: start, length: min(selection.length, length - start)))
        localUndo.removeAllActions()
        rehighlight(force: true)
    }

    func applyLanguage(_ language: String?) {
        guard language != self.language else { return }
        self.language = language
        codeAttributes = EaselCodeBlockStyle.attributes(language: language)
        if let storage = textStorage, storage.length > 0, !hasMarkedText() {
            storage.setAttributes(codeAttributes, range: NSRange(location: 0, length: storage.length))
        }
        rehighlight(force: true)
    }

    var lineCount: Int {
        guard let manager = layoutManager, let container = textContainer else { return 1 }
        return EaselCodeLayout.lineCount(manager: manager, container: container)
    }

    func rehighlight(force: Bool = false) {
        let code = string
        guard force || code != paintedCode || paintedLanguage != .some(language) else { return }
        paintedCode = code
        paintedLanguage = .some(language)
        highlightTask?.cancel()
        highlightTask = nil
        let resolved = EaselCodeBlock.language(language)
        guard resolved.id != NoteCodeLanguage.plainText.id else { paint([], for: code); return }
        if let cached = EaselCodeTokenCache.cached(code, language: resolved.id) { paint(cached, for: code); return }
        if (code as NSString).length <= EaselCodeBlockStyle.synchronousHighlightLimit {
            paint(EaselCodeTokenCache.tokens(code, language: resolved), for: code)
            return
        }
        highlightTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: EaselCodeTokenCache.debounceNanoseconds)
            guard !Task.isCancelled else { return }
            let tokens = await Task.detached(priority: .userInitiated) { NoteSyntaxHighlighter.tokens(in: code, language: resolved) }.value
            guard !Task.isCancelled, let self, self.string == code else { return }
            EaselCodeTokenCache.store(tokens, code: code, language: resolved.id)
            self.paint(tokens, for: code)
        }
    }

    func cancelHighlighting() {
        highlightTask?.cancel()
        highlightTask = nil
    }

    private func paint(_ tokens: [NoteSyntaxToken], for code: String) {
        guard let storage = textStorage, storage.string == code, !hasMarkedText() else { return }
        EaselCodeBlockStyle.apply(tokens, to: storage, base: codeAttributes)
    }

    private func isCommandReturn(_ event: NSEvent) -> Bool {
        event.type == .keyDown && (event.keyCode == 36 || event.keyCode == 76)
            && event.modifierFlags.intersection([.command, .shift, .option, .control]) == .command && !hasMarkedText()
    }

    override func keyDown(with event: NSEvent) {
        if isCommandReturn(event), let onCommandReturn { onCommandReturn(); return }
        super.keyDown(with: event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if window?.firstResponder === self, isCommandReturn(event), let onCommandReturn { onCommandReturn(); return true }
        return super.performKeyEquivalent(with: event)
    }

    override func cancelOperation(_ sender: Any?) {
        if hasMarkedText() { super.cancelOperation(sender); return }
        onExit?()
    }

    override func doCommand(by selector: Selector) {
        guard isEditable, !hasMarkedText() else { super.doCommand(by: selector); return }
        let text = string, range = selectedOffsets
        switch selector {
        case #selector(insertNewline(_:)), #selector(insertLineBreak(_:)), #selector(insertNewlineIgnoringFieldEditor(_:)):
            perform(NoteCodeEditing.newline(in: text, selection: range, indent: indentation, language: languageID))
        case #selector(insertTab(_:)), #selector(insertTabIgnoringFieldEditor(_:)):
            perform(NoteCodeEditing.tab(in: text, selection: range, indent: indentation))
        case #selector(insertBacktab(_:)):
            if let edit = NoteCodeEditing.dedentLines(in: text, selection: range, indent: indentation) { perform(edit) }
        case #selector(deleteBackward(_:)):
            if let edit = NoteCodeEditing.deleteBackward(in: text, selection: range, indent: indentation) { perform(edit) }
            else { super.doCommand(by: selector) }
        case #selector(cancelOperation(_:)):
            onExit?()
        default:
            super.doCommand(by: selector)
        }
    }

    override func insertText(_ string: Any, replacementRange: NSRange) {
        if isEditable, !hasMarkedText(), replacementRange.location == NSNotFound, let typed = string as? String,
           let edit = NoteCodeEditing.closingBracket(typed, in: self.string, selection: selectedOffsets, indent: indentation) {
            perform(edit)
            return
        }
        super.insertText(string, replacementRange: replacementRange)
    }

    override func didChangeText() {
        super.didChangeText()
        rehighlight()
        onEdit?()
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned, let onResign { DispatchQueue.main.async { onResign() } }
        return resigned
    }

    func perform(_ edit: NoteCodeEdit) {
        let range = NSRange(location: edit.range.lowerBound, length: edit.range.count)
        guard let storage = textStorage, shouldChangeText(in: range, replacementString: edit.replacement) else { return }
        storage.replaceCharacters(in: range, with: NSAttributedString(string: edit.replacement, attributes: codeAttributes))
        setSelectedRange(NSRange(location: edit.selection.lowerBound, length: edit.selection.count))
        didChangeText()
        scrollRangeToVisible(selectedRange())
    }

    @objc func undo(_ sender: Any?) {
        if localUndo.canUndo { localUndo.undo() } else { onUndoDocument?() }
    }

    @objc func redo(_ sender: Any?) {
        if localUndo.canRedo { localUndo.redo() } else { onRedoDocument?() }
    }

    override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        if item.action == #selector(undo(_:)) { return localUndo.canUndo || canUndoDocument?() == true }
        if item.action == #selector(redo(_:)) { return localUndo.canRedo || canRedoDocument?() == true }
        return super.validateUserInterfaceItem(item)
    }
}

@MainActor
final class EaselCodeChip: PointingHandButton {
    var chipTitle: String { didSet { if !isFlashing { shownTitle = chipTitle } } }
    var symbol: String { didSet { if !isFlashing { shownSymbol = symbol } } }
    var onPress: (() -> Void)?
    private var shownTitle: String { didSet { invalidateIntrinsicContentSize(); needsDisplay = true } }
    private var shownSymbol: String { didSet { needsDisplay = true } }
    private(set) var isFlashing = false
    private var flashGeneration = 0
    private var hovering = false {
        didSet {
            guard hovering != oldValue else { return }
            needsDisplay = true
            EaselControlSurface.crossfade(self, duration: NoteAnimation.hoverDuration, pops: nil)
        }
    }
    private var hoverArea: NSTrackingArea?
    private let flashTitle: String?

    init(title: String, symbol: String, flashTitle: String? = nil) {
        self.flashTitle = flashTitle
        chipTitle = title
        self.symbol = symbol
        shownTitle = title
        shownSymbol = symbol
        super.init(frame: NSRect(x: 0, y: 0, width: 80, height: NoteTheme.chipHeight))
        isBordered = false
        self.title = ""
        imagePosition = .noImage
        refusesFirstResponder = true
        wantsLayer = true
        NoteAnimation.observeReduceMotion(self) { [weak self] in
            guard let self else { return }
            NoteAnimation.settle(self)
            EaselControlSurface.apply(self, hovered: false, pressed: false, casts: false)
        }
        target = self
        action = #selector(pressed)
        setAccessibilityRole(.button)
        setFrameSize(intrinsicContentSize)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    private var chipFont: NSFont { NoteTheme.chromeFont(12.5) }

    private func titleWidth(_ title: String) -> CGFloat {
        ceil(NSAttributedString(string: title, attributes: [.font: chipFont]).size().width)
    }

    override var intrinsicContentSize: NSSize {
        let text = max(titleWidth(shownTitle), titleWidth(chipTitle), flashTitle.map(titleWidth) ?? 0)
        return NSSize(width: text + 38, height: NoteTheme.chipHeight)
    }

    @objc private func pressed() { onPress?() }

    override func highlight(_ flag: Bool) {
        let released = !flag && isHighlighted
        super.highlight(flag)
        needsDisplay = true
        EaselControlSurface.apply(self, hovered: false, pressed: flag, released: released, casts: false)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseEntered(with event: NSEvent) { hovering = isEnabled }
    override func mouseExited(with event: NSEvent) { hovering = false }

    override func draw(_ dirtyRect: NSRect) {
        let pressed = isHighlighted
        if isEnabled, pressed || hovering {
            (pressed ? NoteTheme.pressedFill : NoteTheme.hoverFill).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: NoteTheme.controlRadius, yRadius: NoteTheme.controlRadius).fill()
        }
        let ink = isEnabled ? (hovering || pressed ? NoteTheme.menuInk : NoteTheme.menuSecondaryInk) : NoteTheme.tertiaryInk
        let content = 19 + titleWidth(shownTitle)
        let start = bounds.minX + max(9, ((bounds.width - content) / 2).rounded())
        drawSymbol(shownSymbol, in: NSRect(x: start, y: bounds.midY - 8, width: 16, height: 16), ink: ink)
        let x = start + 19
        let height = ceil(chipFont.ascender - chipFont.descender)
        NSAttributedString(string: shownTitle, attributes: [.font: chipFont, .foregroundColor: ink])
            .draw(with: NSRect(x: x, y: (bounds.midY - height / 2).rounded(), width: max(0, bounds.maxX - x - 8), height: height),
                  options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
    }

    private func drawSymbol(_ name: String, in rect: NSRect, ink: NSColor) {
        let configuration = NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
            .applying(NSImage.SymbolConfiguration(paletteColors: [ink]))
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(configuration) else { return }
        let size = image.size
        image.draw(in: NSRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2, width: size.width, height: size.height),
                   from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }

    func flash(_ title: String, symbol: String, duration: TimeInterval = 1.4) {
        flashGeneration += 1
        let generation = flashGeneration
        isFlashing = true
        EaselControlSurface.morph(self, pops: 0.88) {
            shownTitle = title
            shownSymbol = symbol
        }
        NSAccessibility.post(element: self, notification: .announcementRequested,
                             userInfo: [.announcement: title, .priority: NSAccessibilityPriorityLevel.medium.rawValue])
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            guard let self, self.flashGeneration == generation else { return }
            self.isFlashing = false
            EaselControlSurface.morph(self, pops: 0.94) {
                self.shownTitle = self.chipTitle
                self.shownSymbol = self.symbol
            }
            self.onSizeChange?()
        }
    }

    func cancelFlash() {
        guard isFlashing else { return }
        flashGeneration += 1
        isFlashing = false
        shownTitle = chipTitle
        shownSymbol = symbol
    }

    var onSizeChange: (() -> Void)?
}

@MainActor
final class EaselCodeBlockBar: NSView {
    static let padding: CGFloat = 2
    static let radius: CGFloat = 9
    let copy = EaselCodeChip(title: "Copy", symbol: "doc.on.doc", flashTitle: "Copied!")
    var itemID: UUID?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = Self.radius
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 1
        layer?.shadowOpacity = 1
        layer?.shadowRadius = 6
        layer?.shadowOffset = CGSize(width: 0, height: -1)
        addSubview(copy)
        copy.setAccessibilityHelp("Copies the code")
        setAccessibilityElement(true)
        setAccessibilityRole(.toolbar)
        setAccessibilityLabel("Code block")
        isHidden = true
        alphaValue = 0
        refreshColors()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    var preferredSize: NSSize {
        NSSize(width: ceil(copy.intrinsicContentSize.width + Self.padding * 2), height: NoteTheme.chipHeight + Self.padding * 2)
    }

    override func layout() {
        super.layout()
        copy.frame = NSRect(x: Self.padding, y: Self.padding, width: copy.intrinsicContentSize.width, height: NoteTheme.chipHeight)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, let hit = super.hitTest(point), hit !== self else { return nil }
        return hit
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshColors()
    }

    private func refreshColors() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.backgroundColor = NoteTheme.resolved(NoteTheme.menuFill, in: self)
        layer?.borderColor = NoteTheme.resolved(NoteTheme.menuHairline, in: self)
        layer?.shadowColor = NoteTheme.resolved(NoteTheme.menuShadow, in: self)
        CATransaction.commit()
    }
}

@MainActor
final class EaselCodeLanguageMenuTarget: NSObject {
    let choose: (String?) -> Void
    init(choose: @escaping (String?) -> Void) { self.choose = choose }
    @objc func chooseLanguage(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        choose(EaselCodeBlock.stored(EaselCodeBlock.language(id)))
    }
}

@MainActor
final class EaselCodeBlockState {
    var editor: EaselCodeTextView?
    var editingID: UUID?
    var undoGroup: UUID?
    var committedText: String?
    var finishing = false
    var barShown = false
    let bar = EaselCodeBlockBar()
}
