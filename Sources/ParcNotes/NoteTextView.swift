import AppKit
import ParcCore
import ParcKit

@MainActor
public class NoteTextView: NoteCursorTextView {
    enum ClickTarget: Equatable {
        case link(String)
        case atom(NoteAtom)
    }

    weak var host: NoteTextHost?
    weak var editor: NotePageEditor?
    var placeholder: String? { didSet { if oldValue != placeholder { needsDisplay = true } } }
    var placeholderShowsWhenUnfocused = false { didSet { if oldValue != placeholderShowsWhenUnfocused { needsDisplay = true } } }
    var crossBlockHighlight: Range<Int>? {
        didSet {
            guard oldValue != crossBlockHighlight else { return }
            noteLayoutManager?.crossBlockHighlight = crossBlockHighlight
            needsDisplay = true
        }
    }
    var findHighlights: [NoteFindHighlight] = [] {
        didSet {
            guard oldValue != findHighlights else { return }
            noteLayoutManager?.findHighlights = findHighlights
            needsDisplay = true
        }
    }
    var presentation = NoteTextPresentation() { didSet { if oldValue != presentation { refreshRendering() } } }
    var inputRulesEnabled = true
    var onContentHeightChange: (() -> Void)?
    var onFocusChange: ((Bool) -> Void)?
    private(set) var noteText = NoteText()
    private(set) var textRevision = 0
    private(set) var isFocused = false
    private var isApplying = false
    private var isEditingText = false
    private var pendingInsertion: String?
    private var codeTypingCaret: Int?
    private var isInsertingText = false
    private var compositionBase: NoteText?
    private var deferredText: (text: NoteText, selection: Range<Int>?)?
    private var renderingDeferred = false
    private var lastContentHeight: CGFloat = 0
    private var hoveredRange: NSRange?
    private var equationPanel: NoteFloatingPanel?
    private var equationEdit: (offset: Int, original: NoteText)?
    private var equationMonitor: Any?
    private var keyObservers: [NSObjectProtocol] = []

    convenience init() {
        self.init(usingTextLayoutManager: false)
        textContainer?.replaceLayoutManager(NoteLayoutManager())
        isRichText = true
        importsGraphics = false
        allowsImageEditing = false
        usesFontPanel = false
        usesRuler = false
        usesFindBar = false
        isIncrementalSearchingEnabled = false
        drawsBackground = false
        textContainerInset = .zero
        textContainer?.lineFragmentPadding = 0
        textContainer?.widthTracksTextView = true
        textContainer?.heightTracksTextView = false
        textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        isVerticallyResizable = false
        isHorizontallyResizable = false
        allowsUndo = false
        smartInsertDeleteEnabled = false
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticLinkDetectionEnabled = false
        isAutomaticDataDetectionEnabled = false
        isAutomaticTextCompletionEnabled = false
        isAutomaticTextReplacementEnabled = NSSpellChecker.isAutomaticTextReplacementEnabled
        isAutomaticSpellingCorrectionEnabled = NSSpellChecker.isAutomaticSpellingCorrectionEnabled
        isContinuousSpellCheckingEnabled = true
        isGrammarCheckingEnabled = false
        displaysLinkToolTips = false
        linkTextAttributes = [:]
        markedTextAttributes = [.underlineStyle: NSUnderlineStyle.single.rawValue]
        insertionPointColor = NoteTheme.caret
        selectedTextAttributes = [.backgroundColor: NoteTheme.selection]
        noteLayoutManager?.crossBlockColor = NoteTheme.selection
        noteLayoutManager?.inactiveSelectionColor = NoteTheme.inactiveSelection
        noteLayoutManager?.findColor = NoteTheme.findMatch
        noteLayoutManager?.findCurrentColor = NoteTheme.findCurrentMatch
        noteLayoutManager?.inlineCodeFill = NoteTheme.inlineCodeBackground
        unregisterDraggedTypes()
        setAccessibilityRole(.textArea)
        refreshTypingAttributes()
    }

    var noteLayoutManager: NoteLayoutManager? { layoutManager as? NoteLayoutManager }

    var field: NoteTextField { host?.field ?? .body }

    var lineHeight: CGFloat { NoteTextRendering.lineHeight(presentation) }

    var typingMarks: NoteMarks {
        get { (typingAttributes[.noteMarks] as? NoteMarksValue)?.marks ?? .plain }
        set {
            if !newValue.code { codeTypingCaret = nil }
            typingAttributes = NoteTextRendering.typingAttributes(newValue, presentation, flexible: NoteTextRendering.needsFlexibleLines(noteText))
        }
    }

    func apply(_ text: NoteText, selection: Range<Int>?) {
        if hasMarkedText() {
            deferredText = text == noteText ? nil : (text, selection)
            return
        }
        renderingDeferred = false
        let previous = selectedOffsets
        if !findHighlights.isEmpty, text.string != noteText.string { findHighlights = [] }
        isApplying = true
        noteText = text
        textRevision &+= 1
        let numbering = NoteTextRendering.needsFlexibleLines(text) ? editor?.math.inlineContext : nil
        textStorage?.setAttributedString(NoteTextRendering.attributedString(text, presentation,
                                                                            numbering: numbering ?? NoteMathNumberingContext(),
                                                                            emoji: editor?.environment.emojiLibrary))
        selectedOffsets = selection ?? previous
        isApplying = false
        refreshTypingAttributes()
        resetHover()
        needsDisplay = true
        reportContentHeight()
    }

    func refreshRendering() {
        guard !hasMarkedText() else {
            renderingDeferred = true
            return
        }
        apply(noteText, selection: nil)
    }

    func customEmojiDidChange() {
        let uses = noteText.spans.contains { span in
            if case .customEmoji = span.marks.atom { return true }
            return false
        }
        if uses { refreshRendering() }
    }

    func mathNumberingDidChange() {
        let references = noteText.spans.contains { span in
            if case .equation(let source) = span.marks.atom { return source.contains("ref") }
            return false
        }
        if references { refreshRendering() }
    }

    private func equationLink(at point: NSPoint) -> NoteMathLinkMark? {
        guard let layoutManager, let textContainer, let index = characterIndex(at: point),
              case .equation = noteText.marks(at: index).atom,
              let attachment = textStorage?.attribute(.attachment, at: index, effectiveRange: nil) as? NoteAtomAttachment,
              let cell = attachment.atomCell else { return nil }
        let glyph = layoutManager.glyphIndexForCharacter(at: index)
        let line = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        let location = layoutManager.location(forGlyphAt: glyph)
        let size = layoutManager.attachmentSize(forGlyphAt: glyph)
        let baseline = line.minY + location.y
        let bottom = baseline - cell.cellBaselineOffset().y
        let frame = NSRect(x: line.minX + location.x + textContainerOrigin.x, y: bottom - size.height + textContainerOrigin.y,
                           width: size.width, height: size.height)
        _ = textContainer
        return cell.mathLink(at: point, cellFrame: frame)
    }

    var selectedOffsets: Range<Int> {
        get {
            let range = selectedRange()
            return range.location..<(range.location + range.length)
        }
        set {
            let length = (string as NSString).length
            let lower = min(max(0, newValue.lowerBound), length), upper = min(max(lower, newValue.upperBound), length)
            setSelectedRange(NSRange(location: lower, length: upper - lower))
        }
    }

    func caretRect(at offset: Int) -> NSRect {
        guard let layoutManager, let textContainer else { return .zero }
        layoutManager.ensureLayout(for: textContainer)
        let length = (string as NSString).length
        let clamped = min(max(0, offset), length)
        let extra = layoutManager.extraLineFragmentRect
        if length == 0 || (clamped == length && extra.height > 0) {
            let height = extra.height > 0 ? extra.height : lineHeight
            let x = length == 0 ? 0 : extra.minX
            return NSRect(x: textContainerOrigin.x + x, y: textContainerOrigin.y + extra.minY, width: 1, height: height)
        }
        let glyph = layoutManager.glyphIndexForCharacter(at: min(clamped, length - 1))
        var rect = layoutManager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: textContainer)
        let line = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        rect.origin.y = line.minY
        rect.size.height = line.height
        if clamped == length { rect.origin.x = rect.maxX }
        rect.size.width = 1
        return rect.offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
    }

    func offset(at point: NSPoint) -> Int {
        guard let layoutManager, let textContainer else { return 0 }
        let local = NSPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)
        var fraction: CGFloat = 0
        let index = layoutManager.characterIndex(for: local, in: textContainer, fractionOfDistanceBetweenInsertionPoints: &fraction)
        return min((string as NSString).length, index + (fraction > 0.5 ? 1 : 0))
    }

    func selectionRects(for range: Range<Int>) -> [NSRect] {
        guard let layoutManager, let textContainer, !range.isEmpty else { return [] }
        var rects: [NSRect] = []
        let glyphs = layoutManager.glyphRange(forCharacterRange: NSRange(location: range.lowerBound, length: range.count), actualCharacterRange: nil)
        layoutManager.enumerateEnclosingRects(forGlyphRange: glyphs, withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0), in: textContainer) { rect, _ in
            rects.append(rect.offsetBy(dx: self.textContainerOrigin.x, dy: self.textContainerOrigin.y))
        }
        return rects
    }

    func isOnFirstLine(_ offset: Int) -> Bool {
        abs(caretRect(at: offset).minY - caretRect(at: 0).minY) < 1
    }

    func isOnLastLine(_ offset: Int) -> Bool {
        abs(caretRect(at: offset).minY - caretRect(at: (string as NSString).length).minY) < 1
    }

    func offset(nearestX x: CGFloat, onFirstLine: Bool) -> Int {
        let line = caretRect(at: onFirstLine ? 0 : (string as NSString).length)
        return offset(at: NSPoint(x: x, y: line.midY))
    }

    var firstLineRect: NSRect { caretRect(at: 0) }

    func contentHeight() -> CGFloat {
        guard let layoutManager, let textContainer, (string as NSString).length > 0 else { return lineHeight }
        layoutManager.ensureLayout(for: textContainer)
        return max(lineHeight, ceil(layoutManager.usedRect(for: textContainer).height))
    }

    private func reportContentHeight() {
        guard bounds.width > 0 else { return }
        let height = contentHeight()
        guard abs(height - lastContentHeight) > 0.25 else { return }
        lastContentHeight = height
        onContentHeightChange?()
    }

    private var inputRulesActive: Bool {
        inputRulesEnabled && isEditable && field == .body && !(editor?.environment.isPlainText ?? false)
    }

    private func currentTypingMarks() -> NoteMarks {
        let caret = selectedRange().location
        var marks = noteText.typingMarks(at: caret)
        if let codeCaret = codeTypingCaret, codeCaret != caret || selectedRange().length > 0 { codeTypingCaret = nil }
        if codeTypingCaret != nil {
            marks.code = true
        } else if marks.code, caret >= noteText.length || !noteText.marks(at: caret).code {
            marks.code = false
        }
        return marks
    }

    private func refreshTypingAttributes() {
        typingAttributes = NoteTextRendering.typingAttributes(currentTypingMarks(), presentation,
                                                              flexible: NoteTextRendering.needsFlexibleLines(noteText))
    }

    public override func shouldChangeText(in affectedCharRange: NSRange, replacementString: String?) -> Bool {
        let allowed = super.shouldChangeText(in: affectedCharRange, replacementString: replacementString)
        if allowed && !isApplying { isEditingText = true }
        return allowed
    }

    public override func insertText(_ string: Any, replacementRange: NSRange) {
        let wasComposing = hasMarkedText()
        pendingInsertion = (string as? NSAttributedString)?.string ?? (string as? String)
        if wasComposing { pendingInsertion = nil }
        isInsertingText = true
        super.insertText(string, replacementRange: replacementRange)
        isInsertingText = false
        pendingInsertion = nil
    }

    public override func didChangeText() {
        super.didChangeText()
        isEditingText = false
        guard !isApplying, let storage = textStorage else { return }
        noteText = NoteTextRendering.noteText(from: storage)
        textRevision &+= 1
        let inserted = pendingInsertion
        pendingInsertion = nil
        reportContentHeight()
        needsDisplay = true
        guard !hasMarkedText() else { return }
        let reconciled = reconcileComposition()
        if codeTypingCaret != nil { codeTypingCaret = selectedRange().location }
        refreshTypingAttributes()
        guard let host, let editor else { return }
        editor.textDidChange(in: host)
        if let inserted, inputRulesActive, !reconciled { runInputRules(after: inserted) }
    }

    public override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        if !hasMarkedText() {
            compositionBase = noteText
            deferredText = nil
        }
        super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
    }

    public override func unmarkText() {
        let wasComposing = hasMarkedText()
        let revision = textRevision
        super.unmarkText()
        guard wasComposing, revision == textRevision, !isApplying, !isEditingText, !isInsertingText, let host, let editor else { return }
        reconcileComposition()
        refreshTypingAttributes()
        editor.textDidChange(in: host)
    }

    @discardableResult
    private func reconcileComposition() -> Bool {
        let base = compositionBase
        let deferred = deferredText
        compositionBase = nil
        deferredText = nil
        if let deferred, deferred.text != base {
            if let base {
                let merged = NoteTextRendering.mergeComposition(committed: noteText, base: base, external: deferred.text,
                                                                 caret: selectedRange().location)
                apply(merged.text, selection: merged.caret..<merged.caret)
            } else {
                apply(deferred.text, selection: deferred.selection)
            }
            return true
        }
        if renderingDeferred { apply(noteText, selection: nil) }
        return false
    }

    public override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting: Bool) {
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)
        guard !isApplying, !isEditingText, !hasMarkedText() else { return }
        refreshTypingAttributes()
        guard !stillSelecting, window?.firstResponder === self, let host, let editor else { return }
        editor.textSelectionDidChange(in: host)
    }

    public override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { setFocused(true) }
        return accepted
    }

    public override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned { setFocused(false) }
        return resigned
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { finishEquationEditorAfterRemoval() }
        if window?.firstResponder !== self { setFocused(false) }
        observeKeyState()
    }

    private func observeKeyState() {
        for observer in keyObservers { NotificationCenter.default.removeObserver(observer) }
        keyObservers = []
        guard let window else { return }
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification] {
            keyObservers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.keyStateDidChange() }
            })
        }
    }

    private func keyStateDidChange() {
        guard crossBlockHighlight != nil || !selectedOffsets.isEmpty else { return }
        needsDisplay = true
    }

    private func setFocused(_ focused: Bool) {
        guard focused != isFocused else { return }
        isFocused = focused
        needsDisplay = true
        refreshPointerCursor()
        onFocusChange?(focused)
    }

    var showsPlaceholder: Bool {
        guard let placeholder, !placeholder.isEmpty, noteText.isEmpty, !hasMarkedText(), isEditable else { return false }
        return isFocused || placeholderShowsWhenUnfocused
    }

    public override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard showsPlaceholder, let placeholder else { return }
        let origin = textContainerOrigin
        NoteTextRendering.placeholder(placeholder, presentation)
            .draw(with: NSRect(x: origin.x, y: origin.y, width: max(0, bounds.width - origin.x), height: lineHeight),
                  options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
    }

    public override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    public override func keyDown(with event: NSEvent) {
        if !hasMarkedText(), let editor {
            if editor.handleKeyDown(event, in: host) { return }
            if editor.selection.handleBlockEdgeKey(event) { return }
        }
        if handleTypingMarkChord(event) { return }
        super.keyDown(with: event)
    }

    public override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.firstResponder === self, !hasMarkedText() else { return super.performKeyEquivalent(with: event) }
        if let editor, editor.handleKeyDown(event, in: host) { return true }
        if handleTypingMarkChord(event) { return true }
        return super.performKeyEquivalent(with: event)
    }

    static func typingMarkKey(for event: NSEvent) -> NoteMarkKey? {
        guard event.type == .keyDown, let key = event.charactersIgnoringModifiers?.lowercased() else { return nil }
        let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
        switch (key, modifiers) {
        case ("b", [.command]): return .bold
        case ("i", [.command]): return .italic
        case ("u", [.command]): return .underline
        case ("s", [.command, .shift]): return .strikethrough
        case ("e", [.command]): return .code
        default: return nil
        }
    }

    private func handleTypingMarkChord(_ event: NSEvent) -> Bool {
        guard let key = Self.typingMarkKey(for: event), selectedOffsets.isEmpty, isEditable,
              !(editor?.environment.isPlainText ?? false) else { return false }
        toggleTypingMark(key)
        return true
    }

    func toggleTypingMark(_ key: NoteMarkKey) {
        var marks = typingMarks
        marks[key].toggle()
        typingMarks = marks
        if key == .code { codeTypingCaret = marks.code ? selectedRange().location : nil }
    }

    public override func doCommand(by selector: Selector) {
        guard !hasMarkedText() else { super.doCommand(by: selector); return }
        if selector == #selector(insertNewline(_:)), inputRulesActive, applyNewlineRule() { return }
        if let host, let editor, editor.handleTextCommand(selector, in: host) { return }
        super.doCommand(by: selector)
    }

    public override func selectAll(_ sender: Any?) {
        if let editor {
            editor.selection.selectAll()
        } else {
            super.selectAll(sender)
        }
    }

    public override func flagsChanged(with event: NSEvent) {
        super.flagsChanged(with: event)
        refreshPointerCursor(modifiers: event.modifierFlags)
    }

    public override func updateDragTypeRegistration() {}

    public override var acceptableDragTypes: [NSPasteboard.PasteboardType] { [] }

    public override var writablePasteboardTypes: [NSPasteboard.PasteboardType] { [.string] }

    public override var readablePasteboardTypes: [NSPasteboard.PasteboardType] { [.string] }

    public override func copy(_ sender: Any?) {
        guard let editor else { copyPlain(); return }
        editor.copySelection()
    }

    public override func cut(_ sender: Any?) {
        guard let editor else { return }
        editor.cutSelection()
    }

    public override func paste(_ sender: Any?) {
        editor?.paste(plainText: false)
    }

    public override func pasteAsPlainText(_ sender: Any?) {
        editor?.paste(plainText: true)
    }

    public override func pasteAsRichText(_ sender: Any?) {
        editor?.paste(plainText: false)
    }

    private func copyPlain() {
        let range = selectedOffsets
        guard !range.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(noteText.slice(range).plainText, forType: .string)
    }

    public override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        if let editor, let result = editor.validateMenuAction(item) { return result }
        return super.validateUserInterfaceItem(item)
    }

    public override func mouseDown(with event: NSEvent) {
        if let editor, editor.selection.textViewMouseDown(self, with: event) { return }
        let point = convert(event.locationInWindow, from: nil)
        if event.clickCount == 1, event.modifierFlags.intersection([.command, .shift, .option, .control]).isEmpty,
           let link = equationLink(at: point), link.resolved, let editor, editor.math.follow(link) {
            return
        }
        if event.clickCount == 1, isEditable, event.modifierFlags.intersection([.command, .shift, .option, .control]).isEmpty,
           let index = characterIndex(at: point), let atom = noteText.marks(at: index).atom {
            switch atom {
            case .equation:
                if editEquation(at: index) { return }
            case .date:
                if let editor, let host {
                    selectedOffsets = index..<(index + 1)
                    editor.slashMenu.openDatePicker(at: NotePosition(host.blockID, index, field: host.field))
                    return
                }
            case .page, .link, .raw, .customEmoji:
                break
            }
        }
        if event.clickCount == 1, let hit = clickTarget(at: point), opensOnClick(event.modifierFlags, target: hit.target) {
            trackClick(on: hit.target, from: event)
            return
        }
        super.mouseDown(with: event)
    }

    private func trackClick(on target: ClickTarget, from event: NSEvent) {
        guard let window else { return }
        let start = event.locationInWindow
        while true {
            guard let next = window.nextEvent(matching: [.leftMouseUp, .leftMouseDragged], until: .distantFuture,
                                              inMode: .eventTracking, dequeue: true) else { return }
            if next.type == .leftMouseUp {
                open(target, event: event)
                return
            }
            if hypot(next.locationInWindow.x - start.x, next.locationInWindow.y - start.y) > 3 {
                window.postEvent(next, atStart: true)
                super.mouseDown(with: event)
                return
            }
        }
    }

    func opensOnClick(_ modifiers: NSEvent.ModifierFlags, target: ClickTarget?) -> Bool {
        let relevant = modifiers.intersection([.command, .shift, .option, .control])
        if relevant == .command { return true }
        if relevant == .shift { return (!isEditable || !isFocused) && target.map(peeksOnShiftClick) == true }
        guard relevant.isEmpty else { return false }
        return !isEditable || !isFocused
    }

    private func peeksOnShiftClick(_ target: ClickTarget) -> Bool {
        guard let editor, editor.allowsShiftClickPeek(), let url = webURL(target) else { return false }
        return NoteLinkClick.shift.route(for: url, automaticPeek: false, shiftPeek: true) == .peek
    }

    private func webURL(_ target: ClickTarget) -> URL? {
        switch target {
        case .link(let value), .atom(.link(let value, _)): return URL(string: value).flatMap { $0.scheme == nil ? nil : $0 }
        case .atom: return nil
        }
    }

    func clickTarget(at point: NSPoint) -> (target: ClickTarget, range: Range<Int>)? {
        guard let index = characterIndex(at: point) else { return nil }
        let marks = noteText.marks(at: index)
        if let atom = marks.atom {
            switch atom {
            case .page, .link: return (.atom(atom), index..<(index + 1))
            case .equation, .date, .raw, .customEmoji: return nil
            }
        }
        guard let link = marks.link else { return nil }
        return (.link(link), linkRange(around: index, link: link))
    }

    private func linkRange(around index: Int, link: String) -> Range<Int> {
        let runs = noteText.runs()
        guard let hit = runs.firstIndex(where: { $0.range.contains(index) }) else { return index..<(index + 1) }
        var lower = hit, upper = hit
        while lower > 0, runs[lower - 1].marks.link == link { lower -= 1 }
        while upper + 1 < runs.count, runs[upper + 1].marks.link == link { upper += 1 }
        return runs[lower].range.lowerBound..<runs[upper].range.upperBound
    }

    private func characterIndex(at point: NSPoint) -> Int? {
        guard let layoutManager, let textContainer, (string as NSString).length > 0 else { return nil }
        let local = NSPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)
        var fraction: CGFloat = 0
        let glyph = layoutManager.glyphIndex(for: local, in: textContainer, fractionOfDistanceThroughGlyph: &fraction)
        let rect = layoutManager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: textContainer)
        guard rect.contains(local) else { return nil }
        let index = layoutManager.characterIndexForGlyph(at: glyph)
        return index < (string as NSString).length ? index : nil
    }

    func open(_ target: ClickTarget, event: NSEvent?) {
        guard let editor else { return }
        switch target {
        case .link(let value):
            if let url = URL(string: value), url.scheme != nil { editor.follow(url, event: event) }
            else if let url = editor.environment.resolveNoteLink(value) { editor.open(url) }
        case .atom(.page(let target, _)):
            if let url = editor.environment.resolveNoteLink(target) { editor.open(url) }
        case .atom(.link(let value, _)):
            if let url = URL(string: value) { editor.follow(url, event: event) }
        case .atom:
            break
        }
    }

    public override func pointerCursor(at point: NSPoint, modifiers: NSEvent.ModifierFlags) -> NSCursor {
        if let link = equationLink(at: point), link.resolved { return .pointingHand }
        if let hit = clickTarget(at: point), opensOnClick(modifiers, target: hit.target) { return .pointingHand }
        return super.pointerCursor(at: point, modifiers: modifiers)
    }

    public override func pointerMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        updateHover(at: point)
        if let link = equationLink(at: point), !link.resolved {
            parcTooltip = TooltipConfiguration(NotePageMath.missingReferenceTooltip(link.key), anchor: .bottom, anchorRect: link.rect)
        } else if parcTooltip != nil {
            parcTooltip = nil
        }
    }

    public override func pointerExited(with event: NSEvent) {
        resetHover()
        if parcTooltip != nil { parcTooltip = nil }
    }

    private func updateHover(at point: NSPoint) {
        let hit = clickTarget(at: point)
        let range = hit.map { NSRange(location: $0.range.lowerBound, length: $0.range.count) }
        guard range != hoveredRange else { return }
        resetHover()
        if let range, case .link = hit?.target {
            layoutManager?.addTemporaryAttribute(.underlineColor, value: NoteTheme.link, forCharacterRange: range)
        }
        hoveredRange = range
    }

    private func resetHover() {
        guard let range = hoveredRange else { return }
        hoveredRange = nil
        let length = (string as NSString).length
        let clamped = NSIntersectionRange(range, NSRange(location: 0, length: length))
        if clamped.length > 0 { layoutManager?.removeTemporaryAttribute(.underlineColor, forCharacterRange: clamped) }
    }

    @discardableResult
    func editEquation(at offset: Int) -> Bool {
        guard isEditable, let editor, offset >= 0, offset < noteText.length,
              case .equation(let source) = noteText.marks(at: offset).atom else { return false }
        closeEquationEditor(commit: true)
        let content = NoteEquationEditorView(source: source)
        content.frame.size = content.fittingSize
        content.onChange = { [weak self] text in self?.previewEquation(text) }
        content.onCommit = { [weak self] in self?.closeEquationEditor(commit: true) }
        content.onCancel = { [weak self] in self?.closeEquationEditor(commit: false) }
        let panel = NoteFloatingPanel(content: content)
        panel.onDismiss = { [weak self, weak panel] in
            guard let self, let panel, self.equationPanel === panel else { return }
            self.closeEquationEditor(commit: true)
        }
        equationEdit = (offset, noteText)
        equationPanel = panel
        selectedOffsets = offset..<(offset + 1)
        let overlay = editor.canvas.overlayView
        panel.present(in: overlay, anchor: overlay.convert(atomRect(at: offset), from: self), edge: .below)
        window?.makeFirstResponder(content.textView)
        let end = (content.textView.string as NSString).length
        content.textView.setSelectedRange(NSRange(location: end, length: 0))
        equationMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, let panel = self.equationPanel, event.window === panel.window else { return }
                if !panel.bounds.contains(panel.convert(event.locationInWindow, from: nil)) { self.closeEquationEditor(commit: true) }
            }
            return event
        }
        return true
    }

    var isEditingEquation: Bool { equationEdit != nil }

    private func atomRect(at offset: Int) -> NSRect {
        let rects = selectionRects(for: offset..<(offset + 1))
        return rects.first ?? caretRect(at: offset)
    }

    private func previewEquation(_ source: String) {
        guard let edit = equationEdit, edit.offset < noteText.length else { return }
        var preview = noteText
        let marks = noteText.marks(at: edit.offset).withoutAtom
        preview.replace(edit.offset..<(edit.offset + 1), with: NoteText.atom(.equation(source), marks: marks))
        apply(preview, selection: edit.offset..<(edit.offset + 1))
        if let panel = equationPanel, let overlay = panel.superview {
            panel.reposition(anchor: overlay.convert(atomRect(at: edit.offset), from: self), edge: .below, animated: false)
        }
    }

    private func equationResult(_ edit: (offset: Int, original: NoteText), commit: Bool) -> (text: NoteText, caret: Int) {
        guard commit else { return (edit.original, edit.offset + 1) }
        var final = noteText
        if edit.offset < final.length, case .equation(let source) = final.marks(at: edit.offset).atom,
           source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            final.delete(edit.offset..<(edit.offset + 1))
            return (final, edit.offset)
        }
        return (final, edit.offset + 1)
    }

    private func dismissEquationPanel() {
        equationEdit = nil
        if let equationMonitor { NSEvent.removeMonitor(equationMonitor) }
        equationMonitor = nil
        let panel = equationPanel
        equationPanel = nil
        panel?.dismiss(animated: true)
    }

    func closeEquationEditor(commit: Bool) {
        guard let edit = equationEdit else { return }
        let result = equationResult(edit, commit: commit)
        dismissEquationPanel()
        apply(result.text, selection: result.caret..<result.caret)
        if result.text != edit.original, let editor, let host {
            let id = host.blockID, field = host.field
            editor.session.edit("Equation", kind: .text, affected: [id], origin: self,
                                selection: .caret(NotePosition(id, result.caret, field: field))) { page in
                page.update(id) { $0.setText(result.text, in: field) }
            }
        }
        window?.makeFirstResponder(self)
        selectedOffsets = result.caret..<result.caret
    }

    private func finishEquationEditorAfterRemoval() {
        guard let edit = equationEdit else { return }
        let result = equationResult(edit, commit: true)
        dismissEquationPanel()
        apply(edit.original, selection: nil)
        guard result.text != edit.original, let editor, let host else { return }
        let id = host.blockID, field = host.field, original = edit.original
        DispatchQueue.main.async { [weak editor] in
            guard let session = editor?.session, session.page.block(id)?.text(in: field) == original else { return }
            session.edit("Equation", kind: .text, affected: [id]) { page in page.update(id) { $0.setText(result.text, in: field) } }
        }
    }

    private func applyNewlineRule() -> Bool {
        guard let editor, let host, selectedOffsets.isEmpty, let block = editor.session.page.block(host.blockID),
              let rule = NoteInputRules.onNewline(text: noteText, caret: selectedOffsets.lowerBound, block: block) else { return false }
        perform(rule, in: block, editor: editor)
        return true
    }

    private func runInputRules(after inserted: String) {
        guard let editor, let host, selectedOffsets.isEmpty, let block = editor.session.page.block(host.blockID),
              block.text == noteText,
              let rule = NoteInputRules.afterTyping(inserted, text: noteText, caret: selectedOffsets.lowerBound, block: block) else { return }
        perform(rule, in: block, editor: editor)
    }

    private func perform(_ rule: NoteInputRule, in block: NoteBlock, editor: NotePageEditor) {
        switch rule {
        case .inline(let conversion):
            if let literal = conversion.literal {
                editor.session.setText(literal, of: (block.id, field), origin: self,
                                       selection: .caret(NotePosition(block.id, conversion.literalCaret, field: field)))
            }
            editor.session.breakCoalescing()
            apply(conversion.text, selection: conversion.caret..<conversion.caret)
            typingMarks = conversion.typingMarks
            editor.session.applyInlineConversion(conversion, to: block.id, field: field, origin: self)
        case .block(let conversion):
            if let literal = conversion.literal {
                editor.session.setText(literal, of: (block.id, field), origin: self,
                                       selection: .caret(NotePosition(block.id, literal.length, field: field)))
            }
            editor.session.breakCoalescing()
            guard let position = editor.session.applyBlockShortcut(conversion, to: block.id) else { return }
            editor.focus(position)
        }
    }
}
