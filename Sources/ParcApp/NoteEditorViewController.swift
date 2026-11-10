import AppKit
import Combine

@MainActor
final class NoteEditorViewController: NSViewController, NSTextViewDelegate {
    let session: NoteSession
    let text = EaselStyledTextView(frame: .zero)
    let titleText = NoteTitleTextView(frame: .zero)
    private let scroll = NSScrollView()
    private lazy var documentView = NoteDocumentLayout(title: titleText, body: text)
    private let status = NSTextField(labelWithString: "Saved on this Mac")
    private let retry = PointingHandButton(title: "Retry", target: nil, action: nil)
    private let discard = PointingHandButton(title: "Discard Draft", target: nil, action: nil)
    private let formatButton = PointingHandButton(title: "Format Paragraph", target: nil, action: nil)
    private(set) var formatting: NoteFormattingView!
    private var subscription: AnyCancellable?
    private var diskSaveSubscription: AnyCancellable?
    private let bodyPublications = PassthroughSubject<UUID, Never>()
    private var bodyPublicationSubscription: AnyCancellable?
    private var pendingBodyPublication: UUID?
    var hasPendingBodyPublication: Bool { pendingBodyPublication != nil }
    private(set) var chromeLayoutCount = 0
    private var laidOutErrorChrome = false
    /// Last chrome geometry `layoutDocument` applied. Identical inputs skip
    /// footer/scroll/format/key-loop work; document height reflow still runs.
    private var lastAppliedChromeFingerprint: NoteEditorChromeFingerprint?
    private var base: NoteDocument
    private var publishing = false
    private var error: Error?
    private var bodyDirty = false
    private var titleDirty = false
    private var pairedDraft = false
    var canAcceptExternalSplitDrop: Bool {
        !session.document.deleted && !text.hasMarkedText() && !titleText.hasMarkedText()
    }
    var onTitleChange: ((String) -> Void)?
    var onOpenURL: ((URL) -> Void)?
    init(directory: URL, documentID: UUID) throws {
        session = try NoteStore.sharedStore(directory: directory).load(documentID)
        base = session.document
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func loadView() {
        let root = NoteLayoutView(); view = root
        scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true; scroll.drawsBackground = false
        scroll.automaticallyAdjustsContentInsets = false; scroll.contentInsets = NSEdgeInsets()
        scroll.contentView.drawsBackground = false
        scroll.documentView = documentView; root.addSubview(scroll)
        titleText.font = NoteDocumentAppearance.titleFont
        titleText.textColor = NoteDocumentAppearance.titleColor
        titleText.typingAttributes = NoteDocumentAppearance.titleAttributes
        titleText.defaultParagraphStyle = NoteDocumentAppearance.titleAttributes[.paragraphStyle] as? NSParagraphStyle
        titleText.placeholderAttributedString = NoteDocumentAppearance.titlePlaceholder
        titleText.insertionPointColor = NoteDocumentAppearance.cursorColor
        var titleSelectionAttributes = titleText.selectedTextAttributes
        titleSelectionAttributes[.backgroundColor] = NoteDocumentAppearance.selectionColor
        titleText.selectedTextAttributes = titleSelectionAttributes
        titleText.isRichText = false; titleText.usesFontPanel = false; titleText.usesFindBar = false
        titleText.isEditable = true; titleText.isSelectable = true; titleText.allowsUndo = true
        titleText.isContinuousSpellCheckingEnabled = true; titleText.drawsBackground = false
        titleText.isVerticallyResizable = true; titleText.isHorizontallyResizable = false
        titleText.textContainer?.widthTracksTextView = true; titleText.textContainerInset = .zero
        titleText.delegate = self; NoteAccessibility.configureTitle(titleText)
        text.isRichText = true; text.isEditable = true; text.isSelectable = true; text.allowsUndo = true
        text.isVerticallyResizable = true; text.isHorizontallyResizable = false
        text.textContainer?.widthTracksTextView = true; text.textContainerInset = NSSize(width: 0, height: 6)
        text.backgroundColor = .clear; text.drawsBackground = false; text.delegate = self
        text.font = NoteDocumentAppearance.bodyFont
        text.typingAttributes = NoteDocumentAppearance.bodyAttributes
        text.defaultParagraphStyle = NoteDocumentAppearance.bodyAttributes[.paragraphStyle] as? NSParagraphStyle
        text.paragraphBodyPointSize = NoteDocumentAppearance.bodyFont.pointSize
        text.insertionPointColor = NoteDocumentAppearance.cursorColor
        var selectionAttributes = text.selectedTextAttributes
        selectionAttributes[.backgroundColor] = NoteDocumentAppearance.selectionColor
        text.selectedTextAttributes = selectionAttributes
        var linkAttributes = text.linkTextAttributes ?? [:]
        linkAttributes[.foregroundColor] = NoteDocumentAppearance.linkColor
        text.linkTextAttributes = linkAttributes
        text.usesFontPanel = true; text.isContinuousSpellCheckingEnabled = true
        NoteAccessibility.configureBody(text); text.hasLoadedDocument = true
        text.onClipboardError = { [weak self] in self?.showError($0) }
        formatting = NoteFormattingView(text: text, session: session)
        formatting.onError = { [weak self] in self?.showError($0) }
        formatting.bindMotion()
        documentView.addSubview(formatting)
        // Native keyboard/AX access complements the recovered hover gutter.
        formatButton.target = formatting; formatButton.action = #selector(NoteFormattingView.formatSelection(_:))
        formatButton.bezelStyle = .inline; formatButton.font = .systemFont(ofSize: 11)
        NoteAccessibility.configureFormatFallback(formatButton, selection: false); root.addSubview(formatButton)
        text.usesFindBar = true; text.isIncrementalSearchingEnabled = true
        status.font = .systemFont(ofSize: 11); status.textColor = .secondaryLabelColor
        status.lineBreakMode = .byTruncatingTail; root.addSubview(status)
        retry.target = self; retry.action = #selector(retrySave); root.addSubview(retry)
        discard.target = self; discard.action = #selector(discardDraft); root.addSubview(discard)
        NoteAccessibility.configureFooter(retry: retry, discard: discard, status: status)
        root.onLayout = { [weak self] in self?.layoutDocument() }
        apply(base)
        //
        // true). Title updates remain immediate. Disk save is a separate
        // 3-second delayed DocumentsClient.save effect.
        bodyPublicationSubscription = bodyPublications
            .throttle(for: .milliseconds(500), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] token in
                MainActor.assumeIsolated {
                    guard let self, self.pendingBodyPublication == token else { return }
                    self.pendingBodyPublication = nil
                    guard !self.session.document.deleted, self.bodyDirty,
                          !self.text.hasMarkedText() else { return }
                    _ = self.saveBody()
                }
            }
        diskSaveSubscription = session.$diskSaveGeneration.sink { [weak self] _ in
            guard let self, !self.publishing else { return }
            if let diskError = self.session.diskSaveError { self.showError(diskError) }
            else { self.updateStatus() }
        }
        subscription = session.$document.sink { [weak self] document in
            guard let self, !self.publishing else { return }
            if document.revision != self.base.revision { self.formatting.contentsChanged() }
            if document.deleted {
                // The durable tombstone intentionally clears its stored fields.
                // Retain this view's original text/selection for read-only Copy;
                // never apply the tombstone as a replacement empty document.
                self.base.revision = document.revision; self.base.deleted = true
                self.text.isEditable = false; self.titleText.isEditable = false
                self.formatting.retire(); self.formatButton.isEnabled = false
                self.pendingBodyPublication = nil
                self.bodyDirty = false; self.titleDirty = false; self.pairedDraft = false
                self.showError(NoteError.deleted); return
            }
            let renamed = document.title != self.base.title
            if document.body != self.base.body && !self.bodyDirty && !self.text.hasMarkedText() { self.applyBody(document.body); self.base.body = document.body }
            if !self.titleDirty && !self.titleText.hasMarkedText() && self.view.window?.firstResponder !== self.titleText { self.applyTitle(document.title); self.base.title = document.title }
            self.base.revision = document.revision; self.base.deleted = document.deleted
            if let diskError = self.session.diskSaveError { self.showError(diskError) }
            if renamed { self.onTitleChange?(document.title.isEmpty ? "Untitled Note" : document.title) }
            else { self.updateStatus() }
        }
    }
    private func apply(_ value: NoteDocument) {
        pendingBodyPublication = nil
        base = value; applyTitle(value.title); applyBody(value.body)
        bodyDirty = false; titleDirty = false; pairedDraft = false; error = nil; updateStatus()
    }
    private func applyTitle(_ value: String) {
        let selection = titleText.selectedRange()
        titleText.textStorage?.setAttributedString(NSAttributedString(string: value, attributes: NoteDocumentAppearance.titleAttributes))
        titleText.typingAttributes = NoteDocumentAppearance.titleAttributes
        titleText.setSelectedRange(NSRange(location: min(selection.location, value.utf16.count), length: 0))
        titleText.resetEditingHistory(); titleText.needsDisplay = true; view.needsLayout = true
    }
    private func applyBody(_ body: NoteBody) {
        publishing = true; defer { publishing = false }
        formatting?.contentsChanged()
        let selection = text.selectedRange()
        text.textStorage?.setAttributedString(NoteDocumentAppearance.attributedBody(body))
        text.setSelectedRange(NSRange(location: min(selection.location, text.string.utf16.count), length: 0))
        if body.text.isEmpty { text.typingAttributes = NoteDocumentAppearance.bodyAttributes }
        text.resetEditingHistory(); view.needsLayout = true
    }
    private func layoutDocument() {
        guard isViewLoaded else { return }
        let size = view.bounds.size
        let stackedError = error != nil && size.width < 225
        let footerHeight: CGFloat = error == nil ? 30 : (stackedError ? 90 : 54)
        let expectedScroll = NSRect(x: 0, y: 0, width: size.width, height: max(0, size.height - footerHeight))
        let fingerprint = NoteEditorChromeFingerprint(
            width: size.width,
            height: size.height,
            hasError: error != nil,
            stackedError: stackedError
        )
        let formatEnabled = text.isEditable && !text.hasMarkedText()
        // Same spirit as Easel document chrome (`lastChromeSize`): when the
        // note chrome geometry fingerprint already matches, skip footer /
        // scroll / format / key-loop writes. Typing may still change document
        // height — reflow that without marking the whole chrome dirty.
        if NoteEditorChromeLayoutSkip.shouldSkip(
            previous: lastAppliedChromeFingerprint,
            next: fingerprint
        ), scroll.frame == expectedScroll, documentView.bounds.width >= 1 {
            formatButton.isEnabled = formatEnabled
            if documentView.reflowIfHeightChanged(viewport: scroll.contentSize, title: titleText, body: text) {
                formatting.frame = documentView.bounds
                formatting.reconcileGeometry()
            }
            return
        }
        chromeLayoutCount += 1
        scroll.frame = expectedScroll
        documentView.arrange(viewport: scroll.contentSize, title: titleText, body: text)
        formatting.frame = documentView.bounds; formatting.reconcileGeometry()
        formatButton.frame = NSRect(x: 12, y: size.height - 27, width: min(130, max(0, size.width - (error == nil ? 24 : 225))), height: 23)
        formatButton.isHidden = stackedError || formatButton.frame.width < 80
        formatButton.isEnabled = formatEnabled
        status.frame = error == nil
            ? NSRect(x: 148, y: size.height - 24, width: max(0, size.width - 166), height: 18)
            : NSRect(x: 18, y: size.height - 49, width: max(0, size.width - 36), height: 18)
        retry.frame = NSRect(x: size.width - 195, y: size.height - 29, width: 62, height: 26)
        discard.frame = NSRect(x: size.width - 130, y: size.height - 29, width: 116, height: 26)
        if stackedError {
            // Local durability controls remain usable in a narrow split pane.
            // This footer is an explicit adaptation, separate from load errors.
            status.frame = NSRect(x: 18, y: size.height - 86, width: max(0, size.width - 36), height: 18)
            retry.frame = NSRect(x: 18, y: size.height - 62, width: min(62, max(0, size.width - 36)), height: 26)
            discard.frame = NSRect(x: 18, y: size.height - 32, width: min(116, max(0, size.width - 36)), height: 26)
        }
        NoteAccessibility.wireKeyLoop(title: titleText, body: text, format: formatButton, retry: retry, discard: discard)
        laidOutErrorChrome = error != nil
        lastAppliedChromeFingerprint = fingerprint
    }
    func textDidBeginEditing(_ notification: Notification) {
        if notification.object as? NSTextView === titleText { formatting.retire() }
    }
    func textDidChange(_ notification: Notification) {
        guard !publishing, let source = notification.object as? NSTextView else { return }
        // Do not set needsLayout on every keystroke. layoutDocument skips
        // chrome when the geometry fingerprint matches and still reflows
        // document height when typing changes it.
        if source === titleText {
            titleDirty = true; titleText.needsDisplay = true
            layoutDocument()
            if !titleText.hasMarkedText() { _ = saveTitle() } else { updateStatus() }
        } else if source === text {
            formatting.contentsChanged(); bodyDirty = true
            // A composing draft cannot be published by an older queued edit.
            pendingBodyPublication = nil
            layoutDocument()
            if !text.hasMarkedText() {
                let token = UUID(); pendingBodyPublication = token
                bodyPublications.send(token)
            }
            updateStatus()
        }
    }
    func textViewDidChangeSelection(_ notification: Notification) {
        guard notification.object as? NSTextView === text else { return }
        formatting?.selectionChanged()
        NoteAccessibility.configureFormatFallback(formatButton, selection: text.selectedRange().length > 0)
    }
    func textDidEndEditing(_ notification: Notification) {
        if notification.object as? NSTextView === titleText {
            if !titleText.hasMarkedText() { _ = saveTitle() }
        } else if notification.object as? NSTextView === text { formatting?.selection.editingEnded() }
    }
    private func saveTitle() -> Bool {
        if pairedDraft { return savePairedDraft() }
        guard titleDirty else { return true }
        publishing = true; defer { publishing = false }
        do {
            try session.updateTitle(titleText.string, replacing: base.title)
            base.title = session.document.title; base.revision = session.document.revision
            titleDirty = false; if !bodyDirty { error = nil }; updateStatus()
            onTitleChange?(session.displayTitle); return true
        } catch { showError(error); return false }
    }
    private func saveBody() -> Bool {
        pendingBodyPublication = nil
        if pairedDraft { return savePairedDraft() }
        guard !text.hasMarkedText() else { return false }
        guard bodyDirty else { return true }
        publishing = true; defer { publishing = false }
        do {
            var body = base.body; body.text = text.string; body.richText = try EaselRichTextCodec.snapshot(text.attributedString())
            let previous = base
            try session.updateBody(body, replacing: base.body)
            formatting.localBodyPublished(previous: previous)
            base.body = session.document.body; base.revision = session.document.revision
            bodyDirty = false; if !titleDirty { error = nil }; updateStatus(); return true
        } catch { showError(error); return false }
    }
    // Called before original tab/window/profile retirement and app shutdown.
    // A failed disk write keeps the real draft and refuses that close.
    func prepareToClose() -> Bool {
        guard isViewLoaded, !session.document.deleted else { return true }
        formatting.retire(); pendingBodyPublication = nil
        if titleText.hasMarkedText() { titleText.unmarkText(); titleDirty = titleText.string != base.title }
        text.finishComposition()
        let titleSaved = saveTitle(), bodySaved = saveBody()
        guard titleSaved && bodySaved else { return false }
        do { try session.flushDelayedDiskSave(); error = nil; updateStatus(); return true }
        catch { showError(error); return false }
    }
    func findInDocument() {
        guard isViewLoaded, !session.document.deleted, let window = view.window,
              window.isKeyWindow, window.attachedSheet == nil else { return }
        formatting.retire(); NoteAccessibility.returnFocus(to: text, in: window)
        let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        item.tag = NSTextFinder.Action.showFindInterface.rawValue
        text.performTextFinderAction(item)
    }
    func focusContent() {
        guard isViewLoaded, let window = view.window, window.isKeyWindow, window.attachedSheet == nil else { return }
        if window.firstResponder === titleText { return }
        if let current = window.firstResponder as? NSView, current.isDescendant(of: view) { return }
        let target = titleText.string.isEmpty ? titleText : text
        NoteAccessibility.returnFocus(to: target, in: window)
    }
    private func showError(_ error: Error) { self.error = error; updateStatus() }
    private func updateStatus() {
        let retryWasHidden = retry.isHidden
        status.stringValue = error?.localizedDescription
            ?? (bodyDirty || titleDirty || session.hasDelayedDiskSave || session.diskSaveError != nil
                ? "Saving on this Mac…" : "Saved on this Mac")
        status.toolTip = error?.localizedDescription; retry.isHidden = error == nil || session.document.deleted
        discard.isHidden = retry.isHidden
        NoteAccessibility.configureFooter(retry: retry, discard: discard, status: status)
        // Footer height follows error presence, including a deleted document
        // whose Retry/Discard controls stay hidden.
        if retry.isHidden != retryWasHidden || (error != nil) != laidOutErrorChrome {
            view.needsLayout = true
        }
    }
    @objc private func retrySave() { _ = prepareToClose() }
    @objc private func discardDraft() { apply(session.document) }
    override func viewWillDisappear() { formatting?.retire(); super.viewWillDisappear() }
    func textView(_ textView: NSTextView, doCommandBy command: Selector) -> Bool {
        guard textView === titleText || textView === text,
              !textView.hasMarkedText(), !titleText.hasMarkedText(), !text.hasMarkedText(),
              !session.document.deleted, textView.isEditable, textView.selectedRanges.count == 1,
              let window = view.window, window.isKeyWindow, window.attachedSheet == nil,
              window.firstResponder === textView else { return false }
        if command == #selector(NSResponder.cancelOperation(_:)) {
            if formatting.isPresentingMenu { formatting.dismiss() }
            else { textView.setSelectedRange(NSRange(location: textView.selectedRange().location, length: 0)) }
            return true
        }
        if textView === titleText {
            if command == #selector(NSResponder.insertNewline(_:)) || command == #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)) {
                transferTitleSuffix(); return true
            }
            if command == #selector(NSResponder.insertTabIgnoringFieldEditor(_:)) { return true }
            if command == #selector(NSResponder.moveDown(_:)) || command == #selector(NSResponder.insertTab(_:)) ||
                (command == #selector(NSResponder.moveRight(_:)) && titleText.selectedRange() == NSRange(location: titleText.string.utf16.count, length: 0)) {
                _ = saveTitle(); focus(text, at: 0); return true
            }
        } else {
            if NoteKeyboardEditing.isBeginningOfLine(command),
               let caret = NoteKeyboardEditing.beginningOfLineCaret(in: text.string, selection: text.selectedRange()) {
                text.setSelectedRange(caret); return true
            }
            // Body `insertNewline:` is witness slot 10 / FormatMenu.didPressEnter.
            // Absent a menu the selector stays native. Alternate-Return is not mapped.
            if command == #selector(NSResponder.insertNewline(_:)), formatting.isPresentingMenu {
                formatting.pressEnter(); return true
            }
            if command == #selector(NSResponder.moveUp(_:)), NoteKeyboardEditing.isFirstVisualLine(text) {
                focus(titleText, at: titleText.string.utf16.count); return true
            }
            if command == #selector(NSResponder.moveLeft(_:)), text.selectedRange() == NSRange(location: 0, length: 0) {
                focus(titleText, at: titleText.string.utf16.count); return true
            }
            if command == #selector(NSResponder.deleteBackward(_:)), text.selectedRange() == NSRange(location: 0, length: 0), NoteKeyboardEditing.hasDefaultTyping(text) {
                transferBodyLine(); return true
            }
            if command == #selector(NSResponder.moveDown(_:)) || command == #selector(NSResponder.moveRight(_:)) {
                formatting.dismiss()
            }
        }
        return false
    }
    private func focus(_ target: NSTextView, at offset: Int) {
        formatting.retire()
        let original = target.string
        guard let window = view.window, window.makeFirstResponder(target),
              window.firstResponder === target, !session.document.deleted,
              target.string == original, NoteKeyboardEditing.valid(NSRange(location: offset, length: 0), in: original) else { return }
        target.setSelectedRange(NSRange(location: offset, length: 0)); NoteAccessibility.reveal(target.selectedRange(), in: target)
    }
    private func transferTitleSuffix() {
        guard let range = NoteKeyboardEditing.titleSuffix(titleText.string, selection: titleText.selectedRange()) else { return }
        let suffix = (titleText.string as NSString).substring(with: range)
        let insertion = suffix + (text.string.isEmpty ? "" : "\n")
        let next = NSMutableAttributedString(attributedString: text.attributedString())
        next.insert(NSAttributedString(string: insertion, attributes: text.typingAttributes), at: 0)
        transfer(titleRange: range, titleReplacement: "", body: next, destination: text, caret: 0)
    }
    private func transferBodyLine() {
        let line = NoteKeyboardEditing.firstLine(text.string), offset = titleText.string.utf16.count
        // The plain title cannot carry embedded images. Keep the original body
        // intact rather than silently erase an attachment's only local bytes.
        let first = text.attributedString().attributedSubstring(from: line.removal)
        guard !EaselTextAttachments.hasImages(first) else { showError(EaselTextClipboardError.unsupportedFormatting); return }
        let next = NSMutableAttributedString(attributedString: text.attributedString()); next.deleteCharacters(in: line.removal)
        transfer(titleRange: NSRange(location: offset, length: 0), titleReplacement: line.text, body: next, destination: titleText, caret: offset)
    }
    private func transfer(titleRange: NSRange, titleReplacement: String, body: NSAttributedString, destination: NSTextView, caret: Int) {
        do { _ = try EaselRichTextCodec.snapshot(body) } catch { showError(error); return }
        formatting.retire(); pendingBodyPublication = nil; publishing = true
        titleText.breakUndoCoalescing(); text.breakUndoCoalescing()
        titleText.insertText(titleReplacement, replacementRange: titleRange)
        replaceBodyForTransfer(body, selection: NSRange(location: 0, length: 0))
        publishing = false; titleDirty = true; bodyDirty = true; pairedDraft = true
        _ = savePairedDraft(); focus(destination, at: caret); view.needsLayout = true
    }
    private func replaceBodyForTransfer(_ value: NSAttributedString, selection: NSRange) {
        let original = NSAttributedString(attributedString: text.attributedString()), selected = text.selectedRange()
        guard !original.isEqual(to: value) else { text.setSelectedRange(selection); return }
        text.localUndo.registerUndo(withTarget: self) { editor in editor.replaceBodyForTransfer(original, selection: selected) }
        text.localUndo.setActionName("Move text between title and body")
        text.localUndo.disableUndoRegistration()
        text.textStorage?.setAttributedString(value); text.setSelectedRange(selection)
        text.localUndo.enableUndoRegistration(); text.didChangeText()
    }
    private func savePairedDraft() -> Bool {
        pendingBodyPublication = nil
        guard !titleText.hasMarkedText(), !text.hasMarkedText() else { return false }
        publishing = true; defer { publishing = false }
        do {
            var body = base.body; body.text = text.string; body.richText = try EaselRichTextCodec.snapshot(text.attributedString())
            try session.updateTitleAndBody(title: titleText.string, body: body, replacingTitle: base.title, body: base.body)
            base = session.document; titleDirty = false; bodyDirty = false; pairedDraft = false; error = nil
            onTitleChange?(session.displayTitle); updateStatus(); return true
        } catch { showError(error); return false }
    }
    func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
        guard let url = (link as? URL) ?? (link as? String).flatMap(URL.init(string:)),
              ["http", "https", "mailto"].contains(url.scheme?.lowercased() ?? "") else { return true }
        onOpenURL?(url); return true
    }
}

@MainActor
private final class NoteLayoutView: NoteCanvasView {
    var onLayout: (() -> Void)?
    override var isFlipped: Bool { true }
    override func layout() { super.layout(); onLayout?() }
}

/// Inputs `NoteEditorViewController.layoutDocument` uses to place scroll,
/// footer, format control and the key loop. Identical values mean those chrome
/// frames would only be rewritten; document height reflow is separate.
struct NoteEditorChromeFingerprint: Equatable {
    var width: CGFloat
    var height: CGFloat
    var hasError: Bool
    var stackedError: Bool
}

/// True no-op gate for note editor chrome layout. A first apply
/// (`previous == nil`) or any bounds/error-footer input change still runs the
/// full chrome pass. Matching fingerprints skip footer/scroll/format/key-loop
/// work while typing may still reflow document height.
enum NoteEditorChromeLayoutSkip {
    static func shouldSkip(
        previous: NoteEditorChromeFingerprint?,
        next: NoteEditorChromeFingerprint
    ) -> Bool {
        previous == next
    }
}
