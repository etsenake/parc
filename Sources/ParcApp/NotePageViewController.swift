import AppKit
import Combine

@MainActor
final class NotePageViewController: NSViewController, NSMenuItemValidation, NSUserInterfaceValidations {
    let file: NoteFileSession
    private(set) var editor: NotePageEditor!
    var onTitleChange: ((String) -> Void)?
    var onURLChange: ((URL) -> Void)?
    var onOpenURL: ((URL) -> Void)?
    var onOpenNote: ((URL) -> Void)?
    var onToast: ((ParcToastContent) -> Void)?
    private let root = NotePageRootView()
    private let scroll = NSScrollView()
    private let status = NotePageStatusView()
    private var header: NotePageTitleHeader?
    private var lease: NoteFileLease?
    private var subscriptions = Set<AnyCancellable>()
    private var unsavedSince: Date?
    private var slowSaveToken = 0
    private var transientError: String?
    private var renameWork: DispatchWorkItem?
    private var spaceAppearance: NSAppearance?
    private var reportedTitle: String?

    static let slowSaveDelay: TimeInterval = 8
    static let renamePause: TimeInterval = 1.2

    private static let editorActions: Set<String> = [
        "undo:", "redo:", "copy:", "cut:", "paste:", "pasteAsPlainText:", "pasteAsRichText:", "pasteAndMatchStyle:",
        "delete:", "selectAll:", "formatText:",
    ]

    init(file: NoteFileSession) {
        self.file = file
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func loadView() {
        let editor = NotePageEditor(session: file.page, environment: file.environment)
        self.editor = editor
        editor.onOpenURL = { [weak self] url in self?.onOpenURL?(url) }
        editor.onOpenNote = { [weak self] url in self?.onOpenNote?(url) }
        editor.onError = { [weak self] error in self?.showTransientError(error) }
        editor.onFocusTitle = { [weak self] in self?.focusTitle(atEnd: true) }
        editor.onPrint = { [weak self] in self?.printPage() }
        editor.onChange = { [weak self] change in self?.pageDidChange(change) }
        editor.handles.presentToast = { [weak self] content in self?.onToast?(content) }

        root.controller = self
        root.registerForDraggedTypes(NotePageEditor.externalDragTypes)
        root.setAccessibilityElement(true)
        root.setAccessibilityRole(.group)
        root.setAccessibilityLabel("Note")

        scroll.drawsBackground = false
        scroll.contentView.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.verticalScrollElasticity = .allowed
        scroll.horizontalScrollElasticity = .none
        scroll.automaticallyAdjustsContentInsets = false
        scroll.contentInsets = NSEdgeInsets()
        scroll.documentView = editor.canvas
        root.addSubview(scroll)

        let header = NotePageTitleHeader()
        header.onCommit = { [weak self] title in self?.commitTitle(title) }
        header.onEdit = { [weak self] in self?.titleDidEdit() }
        header.onExit = { [weak self] in self?.focusFirstBlock() }
        self.header = header
        editor.canvas.headerView = header

        status.onAction = { [weak self] action in self?.performStatusAction(action) }
        root.addSubview(status)
        root.onLayout = { [weak self] in self?.layoutRoot() }
        view = root

        editor.canvas.spaceFocus = spaceFocus
        lease = NoteFileLease(file)
        reportedTitle = file.title
        refreshTitle()
        file.$state
            .sink { [weak self] state in self?.saveStateDidChange(state) }
            .store(in: &subscriptions)
        file.urlChanges
            .sink { [weak self] url in self?.fileDidMove(to: url) }
            .store(in: &subscriptions)
        refreshStatus()
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        editor?.dismissOverlays()
        if header?.isEditing == true { commitPendingTitle() }
    }

    var canAcceptExternalDrop: Bool { isViewLoaded && !(editor?.hasMarkedText ?? false) && !(header?.hasMarkedText ?? false) }

    var isReadOnly: Bool { editor?.isReadOnly ?? (file.page.isReadOnly || file.page.page.settings.locked) }

    func inheritSpaceContentAppearance(_ appearance: NSAppearance?) {
        spaceAppearance = appearance
        guard isViewLoaded else { return }
        view.appearance = appearance
        root.needsDisplay = true
        editor.appearanceDidChange()
        status.needsDisplay = true
        header?.themeDidChange()
    }

    var spaceFocus: NSColor? {
        didSet {
            guard isViewLoaded else { return }
            editor.canvas.spaceFocus = spaceFocus
        }
    }

    func focusContent() {
        guard isViewLoaded, let window = view.window else { return }
        if header?.isPlaceholderTitle == true, !isReadOnly {
            focusTitle(atEnd: true)
            return
        }
        switch editor.session.selection {
        case .text, .blocks, .cells:
            if !editor.ownsFocus { window.makeFirstResponder(editor.canvas) }
            editor.restoreFocus()
            if editor.ownsFocus { return }
        case .none:
            break
        }
        focusFirstBlock()
    }

    func prepareToClose() -> Bool {
        guard isViewLoaded else {
            do { try file.flush(); return true } catch { return false }
        }
        editor.dismissOverlays()
        commitPendingTitle()
        do {
            try file.flush()
            return true
        } catch {
            showTransientError(error)
            return false
        }
    }

    func teardown() {
        editor?.dismissOverlays()
        lease?.end()
        lease = nil
    }

    func perform(_ action: BrowserFindAction) -> Bool {
        guard isViewLoaded else { return false }
        switch action {
        case .show: return editor.perform(.find)
        case .replace: return editor.perform(.findAndReplace)
        case .next: return editor.perform(.findNext)
        case .previous: return editor.perform(.findPrevious)
        case .useSelection: return editor.perform(.useSelectionForFind)
        case .jumpToSelection:
            editor.restoreFocus()
            return true
        }
    }

    fileprivate func routeKeyEquivalent(_ event: NSEvent) -> Bool {
        guard let window = view.window, window.isKeyWindow, let responder = window.firstResponder as? NSView,
              responder === view || responder.isDescendant(of: view) else { return false }
        if editor.ownsFocus { return editor.performKeyEquivalent(event) }
        guard let command = NoteKeyCommands.command(for: event) else { return false }
        switch command {
        case .find, .findAndReplace, .findNext, .findPrevious, .print:
            return editor.validate(command) && editor.perform(command)
        default:
            return false
        }
    }

    override func responds(to selector: Selector!) -> Bool {
        if let selector, Self.editorActions.contains(NSStringFromSelector(selector)) {
            guard isViewLoaded, editor.ownsFocus else { return false }
        }
        return super.responds(to: selector)
    }

    @objc func undo(_ sender: Any?) { _ = editor.performMenuAction(#selector(undo(_:)), sender: sender) }
    @objc func redo(_ sender: Any?) { _ = editor.performMenuAction(#selector(redo(_:)), sender: sender) }
    @objc func copy(_ sender: Any?) { _ = editor.performMenuAction(#selector(copy(_:)), sender: sender) }
    @objc func cut(_ sender: Any?) { _ = editor.performMenuAction(#selector(cut(_:)), sender: sender) }
    @objc func paste(_ sender: Any?) { _ = editor.performMenuAction(#selector(paste(_:)), sender: sender) }
    @objc func pasteAsPlainText(_ sender: Any?) { _ = editor.performMenuAction(#selector(pasteAsPlainText(_:)), sender: sender) }
    @objc func pasteAsRichText(_ sender: Any?) { _ = editor.performMenuAction(#selector(pasteAsRichText(_:)), sender: sender) }
    @objc func delete(_ sender: Any?) { _ = editor.performMenuAction(#selector(delete(_:)), sender: sender) }
    @objc override func selectAll(_ sender: Any?) { _ = editor.performMenuAction(#selector(selectAll(_:)), sender: sender) }
    @objc func formatText(_ sender: Any?) { _ = editor.performMenuAction(NoteKeyCommands.formatTextAction, sender: sender) }

    func validateMenuItem(_ item: NSMenuItem) -> Bool { validateUserInterfaceItem(item) }

    func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        guard isViewLoaded else { return false }
        return editor.validateMenuAction(item) ?? false
    }

    fileprivate func dragOperation(_ info: NSDraggingInfo) -> NSDragOperation {
        editor.dragOperation(for: info, at: editor.canvas.convert(info.draggingLocation, from: nil))
    }

    fileprivate func performDrop(_ info: NSDraggingInfo) -> Bool {
        editor.performDrop(info, at: editor.canvas.convert(info.draggingLocation, from: nil))
    }

    fileprivate func dragExited() { editor.dragExited() }

    private func layoutRoot() {
        scroll.frame = root.bounds
        let size = status.fittingSize
        let width = min(size.width, max(0, root.bounds.width - 32))
        status.frame = NSRect(x: (root.bounds.width - width) / 2, y: root.bounds.height - size.height - 14, width: width, height: size.height)
    }

    private func focusFirstBlock() {
        guard let window = view.window else { return }
        let page = editor.session.page
        if let first = page.visibleTextOrder().first {
            let caret = NotePosition(first, 0)
            window.makeFirstResponder(editor.canvas)
            editor.session.setSelection(.caret(caret))
            editor.focus(caret)
        } else if !isReadOnly {
            let fresh = NoteBlock.paragraph()
            window.makeFirstResponder(editor.canvas)
            editor.session.insertBlocks([fresh], .top(0), select: .caret(NotePosition(fresh.id, 0)))
            editor.focus(NotePosition(fresh.id, 0))
        }
    }

    private func focusTitle(atEnd: Bool) {
        guard let header, let window = view.window, !isReadOnly else { return }
        editor.canvas.scrollToVisible(header.frame)
        header.focus(in: window, atEnd: atEnd)
    }

    private func refreshTitle() {
        let placeholder = Self.isPlaceholderTitle(file.title)
        header?.setTitle(placeholder ? "" : file.title, placeholderTitle: placeholder)
        header?.isReadOnly = isReadOnly
        header?.font = NoteTheme.titleFont(editor.session.page.settings.font)
    }

    static func isPlaceholderTitle(_ title: String) -> Bool {
        title.range(of: "^Untitled( [0-9]+)?$", options: .regularExpression) != nil
    }

    private func titleDidEdit() {
        header?.errorMessage = nil
        renameWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.commitPendingTitle() }
        }
        renameWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.renamePause, execute: work)
    }

    private func commitPendingTitle() {
        renameWork?.cancel()
        renameWork = nil
        guard let header, header.isDirty, !header.hasMarkedText else { return }
        commitTitle(header.title)
    }

    private func commitTitle(_ typed: String) {
        renameWork?.cancel()
        renameWork = nil
        guard !isReadOnly else { refreshTitle(); return }
        let trimmed = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        let wantsPlaceholder = trimmed.isEmpty
        if wantsPlaceholder, Self.isPlaceholderTitle(file.title) {
            header?.markClean()
            return
        }
        let before = file.title
        do {
            if wantsPlaceholder {
                try renameToUntitled()
            } else if trimmed != before {
                _ = try file.rename(to: trimmed)
            }
            header?.markClean()
            header?.errorMessage = nil
            if file.title != before { reportTitle() }
            if file.title != trimmed, !wantsPlaceholder, header?.isEditing == false { refreshTitle() }
        } catch {
            header?.errorMessage = error.localizedDescription
            if let header {
                NSAccessibility.post(element: header, notification: .announcementRequested,
                                     userInfo: [.announcement: error.localizedDescription, .priority: NSAccessibilityPriorityLevel.high.rawValue])
            }
        }
    }

    private func renameToUntitled() throws {
        var lastError: Error?
        for number in 1...50 {
            do {
                _ = try file.rename(to: number == 1 ? "Untitled" : "Untitled \(number)")
                return
            } catch let error as NoteFileError {
                if case .nameTaken = error { lastError = error; continue }
                throw error
            }
        }
        if let lastError { throw lastError }
    }

    private func fileDidMove(to url: URL) {
        onURLChange?(url)
        if header?.isEditing != true { refreshTitle() }
        reportTitle()
    }

    private func reportTitle() {
        guard file.title != reportedTitle else { return }
        reportedTitle = file.title
        onTitleChange?(file.title)
    }

    private func pageDidChange(_ change: NotePageChange) {
        if change.kind == .settings || change.kind == .replaced {
            refreshTitle()
            refreshStatus()
        }
        if change.kind != .selection, transientError != nil {
            transientError = nil
            refreshStatus()
        }
    }

    private func saveStateDidChange(_ state: NoteFileSaveState) {
        switch state {
        case .unsaved, .saving:
            if unsavedSince == nil {
                unsavedSince = Date()
                slowSaveToken += 1
                let token = slowSaveToken
                DispatchQueue.main.asyncAfter(deadline: .now() + Self.slowSaveDelay) { [weak self] in
                    MainActor.assumeIsolated {
                        guard let self, self.slowSaveToken == token else { return }
                        self.refreshStatus()
                    }
                }
            }
        default:
            unsavedSince = nil
            slowSaveToken += 1
        }
        if case .saved = state { transientError = nil }
        refreshStatus()
    }

    private func showTransientError(_ error: Error) {
        transientError = error.localizedDescription
        refreshStatus()
    }

    private var currentStatus: NotePageStatus {
        switch file.state {
        case .conflict: return .conflict
        case .failed(let message): return .failed(message)
        case .missing: return .missing
        case .unsaved, .saving:
            if let since = unsavedSince, Date().timeIntervalSince(since) >= Self.slowSaveDelay - 0.05 { return .slowSave }
        case .saved:
            break
        }
        if let transientError { return .notice(transientError) }
        if file.page.page.settings.locked { return .locked }
        if file.page.isReadOnly { return .readOnly }
        if file.kind == .plainText { return .plainText }
        return .none
    }

    private func refreshStatus() {
        guard isViewLoaded else { return }
        let next = currentStatus
        guard next != status.status else { return }
        status.show(next)
        root.needsLayout = true
    }

    private func performStatusAction(_ action: NotePageStatus.Action) {
        switch action {
        case .retry, .restore:
            do { try file.flush() } catch { showTransientError(error) }
        case .keepMine:
            file.resolveConflict(keepMine: true)
        case .useFile:
            file.resolveConflict(keepMine: false)
        case .unlock:
            editor.session.updateSettings(name: "Unlock Page") { $0.locked = false }
        case .dismiss:
            transientError = nil
        }
        refreshStatus()
    }

    func printPage() {
        guard isViewLoaded, let window = view.window else { return }
        let info = NSPrintInfo.shared.copy() as? NSPrintInfo ?? NSPrintInfo()
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        info.isVerticallyCentered = false
        let width = info.paperSize.width - info.leftMargin - info.rightMargin
        let text = NSTextView(frame: NSRect(x: 0, y: 0, width: width, height: 100))
        text.textContainerInset = .zero
        text.textContainer?.lineFragmentPadding = 0
        text.isEditable = false
        text.drawsBackground = false
        text.appearance = NSAppearance(named: .aqua)
        var document = NSAttributedString()
        (NSAppearance(named: .aqua) ?? text.effectiveAppearance).performAsCurrentDrawingAppearance {
            document = NotePagePrintDocument.render(title: file.title, page: editor.session.page, plainText: file.kind == .plainText)
        }
        text.textStorage?.setAttributedString(document)
        text.sizeToFit()
        let operation = NSPrintOperation(view: text, printInfo: info)
        operation.jobTitle = file.title
        operation.showsPrintPanel = true
        operation.showsProgressPanel = true
        operation.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
    }
}

@MainActor
final class NoteFileLease {
    nonisolated(unsafe) private var file: NoteFileSession?

    init(_ file: NoteFileSession) {
        self.file = file
        file.retain()
    }

    func end() {
        file?.release()
        file = nil
    }

    deinit {
        guard let file else { return }
        DispatchQueue.main.async { MainActor.assumeIsolated { file.release() } }
    }
}

@MainActor
final class NotePageRootView: NSView {
    weak var controller: NotePageViewController?
    var onLayout: (() -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NoteTheme.paper.cgColor
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        onLayout?()
        CATransaction.commit()
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if controller?.routeKeyEquivalent(event) == true { return true }
        return super.performKeyEquivalent(with: event)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { controller?.dragOperation(sender) ?? [] }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { controller?.dragOperation(sender) ?? [] }
    override func draggingExited(_ sender: NSDraggingInfo?) { controller?.dragExited() }
    override func draggingEnded(_ sender: NSDraggingInfo) { controller?.dragExited() }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { controller?.dragOperation(sender).isEmpty == false }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool { controller?.performDrop(sender) ?? false }
}

enum NotePageStatus: Equatable {
    enum Action: Equatable { case retry, keepMine, useFile, restore, unlock, dismiss }

    case none
    case slowSave
    case failed(String)
    case conflict
    case missing
    case locked
    case readOnly
    case plainText
    case notice(String)

    var message: String {
        switch self {
        case .none: return ""
        case .slowSave: return "Saving is taking its sweet time…"
        case .failed(let detail): return detail.isEmpty ? "Couldn’t save this note." : "Couldn’t save this note. \(detail)"
        case .conflict: return "This file changed somewhere else too."
        case .missing: return "This note’s file has wandered off."
        case .locked: return "Locked, so no edits for now."
        case .readOnly: return "Read-only. Parc can look but not touch."
        case .plainText: return "Plain text file, so formatting’s off."
        case .notice(let detail): return detail
        }
    }

    var actions: [(Action, String)] {
        switch self {
        case .failed: return [(.retry, "Retry")]
        case .conflict: return [(.keepMine, "Keep mine"), (.useFile, "Use the file’s version")]
        case .missing: return [(.restore, "Put it back")]
        case .locked: return [(.unlock, "Unlock")]
        case .notice: return [(.dismiss, "OK")]
        case .none, .slowSave, .readOnly, .plainText: return []
        }
    }

    var isAlert: Bool {
        switch self {
        case .failed, .conflict, .missing, .notice: return true
        default: return false
        }
    }
}

@MainActor
final class NotePageStatusView: NSView {
    private(set) var status: NotePageStatus = .none
    var onAction: ((NotePageStatus.Action) -> Void)?
    private let label = NSTextField(labelWithString: "")
    private var buttons: [NotePageStatusButton] = []
    private var generation = 0

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 0.5
        layer?.shadowOpacity = 0.12
        layer?.shadowRadius = 7
        layer?.shadowOffset = CGSize(width: 0, height: -1)
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        addSubview(label)
        isHidden = true
        alphaValue = 0
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Note status")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NoteTheme.panelFill.cgColor
            layer?.borderColor = NoteTheme.panelStroke.cgColor
            layer?.shadowColor = NSColor.black.cgColor
        }
        label.textColor = status.isAlert ? NoteTheme.ink : NoteTheme.secondaryInk
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override var fittingSize: NSSize {
        let labelSize = label.fittingSize
        let buttonWidth = buttons.reduce(CGFloat(0)) { $0 + $1.fittingSize.width + 6 }
        return NSSize(width: ceil(labelSize.width + buttonWidth + 24), height: 30)
    }

    override func layout() {
        super.layout()
        var x: CGFloat = 12
        let labelWidth = max(0, bounds.width - 24 - buttons.reduce(CGFloat(0)) { $0 + $1.fittingSize.width + 6 })
        let labelHeight = label.fittingSize.height
        label.frame = NSRect(x: x, y: (bounds.height - labelHeight) / 2, width: labelWidth, height: labelHeight)
        x = label.frame.maxX + 6
        for button in buttons {
            let size = button.fittingSize
            button.frame = NSRect(x: x, y: (bounds.height - size.height) / 2, width: size.width, height: size.height)
            x += size.width + 6
        }
    }

    func show(_ next: NotePageStatus) {
        let wasShowing = status != .none
        status = next
        generation += 1
        let token = generation
        guard next != .none else {
            NoteAnimation.fade(self, visible: false, duration: 0.15) { [weak self] in
                guard let self, self.generation == token else { return }
                self.isHidden = true
            }
            return
        }
        label.stringValue = next.message
        label.toolTip = next.message
        for button in buttons { button.removeFromSuperview() }
        buttons = next.actions.map { action, title in
            let button = NotePageStatusButton(title: title, action: action)
            button.target = self
            button.action = #selector(buttonPressed(_:))
            addSubview(button)
            return button
        }
        setAccessibilityValue(next.message)
        needsDisplay = true
        needsLayout = true
        superview?.needsLayout = true
        isHidden = false
        if !wasShowing { NoteAnimation.fade(self, visible: true, duration: 0.15) } else { alphaValue = 1 }
        if next.isAlert {
            NSAccessibility.post(element: self, notification: .announcementRequested,
                                 userInfo: [.announcement: next.message, .priority: NSAccessibilityPriorityLevel.high.rawValue])
        }
    }

    @objc private func buttonPressed(_ sender: NotePageStatusButton) {
        onAction?(sender.statusAction)
    }
}

@MainActor
final class NotePageStatusButton: PointingHandButton {
    let statusAction: NotePageStatus.Action
    private var hovering = false

    init(title: String, action: NotePageStatus.Action) {
        statusAction = action
        super.init(frame: .zero)
        self.title = title
        isBordered = false
        bezelStyle = .inline
        wantsLayer = true
        layer?.cornerRadius = NoteTheme.controlRadius
        layer?.cornerCurve = .continuous
        refreshTitle()
        setAccessibilityLabel(title)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var wantsUpdateLayer: Bool { true }

    override var fittingSize: NSSize {
        let size = attributedTitle.size()
        return NSSize(width: ceil(size.width) + 14, height: 22)
    }

    override func updateLayer() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = (isHighlighted ? NoteTheme.pressedFill : hovering ? NoteTheme.hoverFill : NSColor.clear).cgColor
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshTitle()
        needsDisplay = true
    }

    override func mouseEntered(with event: NSEvent) {
        hovering = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        hovering = false
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        pressScale(0.95)
        super.mouseDown(with: event)
        pressScale(1)
        needsDisplay = true
    }

    private func pressScale(_ scale: CGFloat) {
        guard let layer else { return }
        let center = CATransform3DMakeTranslation(layer.bounds.midX, layer.bounds.midY, 0)
        let back = CATransform3DMakeTranslation(-layer.bounds.midX, -layer.bounds.midY, 0)
        let transform = CATransform3DConcat(CATransform3DConcat(back, CATransform3DMakeScale(scale, scale, 1)), center)
        NoteAnimation.animate(layer, "transform", to: NSValue(caTransform3D: transform), spring: .press, key: "note.press")
    }

    private func refreshTitle() {
        attributedTitle = NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NoteTheme.accent,
        ])
    }
}

@MainActor
final class NotePageTitleHeader: NSView, NSTextViewDelegate, NoteCanvasHeader {
    var onCommit: ((String) -> Void)?
    var onEdit: (() -> Void)?
    var onExit: (() -> Void)?
    private let field = NotePageTitleTextView()
    private let error = NSTextField(wrappingLabelWithString: "")
    private(set) var isDirty = false
    private(set) var isPlaceholderTitle = false
    private var applying = false

    static let topInset: CGFloat = 72
    static let bottomInset: CGFloat = 14

    override init(frame: NSRect) {
        super.init(frame: frame)
        field.delegate = self
        field.placeholder = "Untitled"
        addSubview(field)
        error.font = .systemFont(ofSize: 12, weight: .medium)
        error.isHidden = true
        addSubview(error)
        themeDidChange()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    var font: NSFont = NoteTheme.titleFont(.standard) {
        didSet {
            guard font != oldValue else { return }
            field.font = font
            field.typingAttributes[.font] = font
            invalidateHeight()
        }
    }

    var title: String { field.string.replacingOccurrences(of: "\n", with: " ") }

    var isEditing: Bool { window?.firstResponder === field }

    var hasMarkedText: Bool { field.hasMarkedText() }

    var isReadOnly = false { didSet { field.isEditable = !isReadOnly } }

    var errorMessage: String? {
        didSet {
            guard errorMessage != oldValue else { return }
            error.stringValue = errorMessage ?? ""
            error.isHidden = errorMessage == nil
            invalidateHeight()
        }
    }

    func setTitle(_ value: String, placeholderTitle: Bool) {
        isPlaceholderTitle = placeholderTitle
        guard !isEditing || !isDirty else { return }
        guard field.string != value else { return }
        applying = true
        field.string = value
        applying = false
        isDirty = false
        invalidateHeight()
    }

    func markClean() { isDirty = false }

    func themeDidChange() {
        field.textColor = NoteTheme.titleInk
        field.insertionPointColor = NoteTheme.caret
        field.selectedTextAttributes = [.backgroundColor: NoteTheme.selection]
        field.placeholderColor = NoteTheme.placeholderInk
        error.textColor = NoteTheme.color(.text(.red))
        field.needsDisplay = true
    }

    func focus(in window: NSWindow, atEnd: Bool) {
        window.makeFirstResponder(field)
        let length = (field.string as NSString).length
        field.setSelectedRange(NSRange(location: atEnd ? length : 0, length: 0))
    }

    private var column: NSRect {
        if let canvas = superview as? NotePageCanvasView {
            let rect = canvas.contentRect
            return NSRect(x: rect.minX - frame.minX, y: 0, width: rect.width, height: bounds.height)
        }
        return bounds
    }

    func canvasHeaderHeight(width: CGFloat, column: NSRect) -> CGFloat {
        height(for: max(1, column.width))
    }

    override var fittingSize: NSSize {
        let width = max(1, column.width)
        return NSSize(width: bounds.width, height: height(for: width))
    }

    private func height(for width: CGFloat) -> CGFloat {
        let titleHeight = field.height(for: width)
        let errorHeight = errorMessage == nil ? 0 : error.sizeThatFits(NSSize(width: width, height: .greatestFiniteMagnitude)).height + 6
        return Self.topInset + titleHeight + errorHeight + Self.bottomInset
    }

    override func layout() {
        super.layout()
        let column = self.column
        let width = column.width
        let titleHeight = field.height(for: width)
        field.frame = NSRect(x: column.minX, y: Self.topInset, width: width, height: titleHeight)
        if errorMessage != nil {
            let size = error.sizeThatFits(NSSize(width: width, height: .greatestFiniteMagnitude))
            error.frame = NSRect(x: column.minX, y: field.frame.maxY + 6, width: width, height: size.height)
        }
    }

    private func invalidateHeight() {
        needsLayout = true
        superview?.needsLayout = true
    }

    func textDidChange(_ notification: Notification) {
        guard !applying, !field.hasMarkedText() else { return }
        isDirty = true
        invalidateHeight()
        onEdit?()
    }

    func textDidEndEditing(_ notification: Notification) {
        guard isDirty else { return }
        onCommit?(title)
    }

    func textView(_ textView: NSTextView, shouldChangeTextIn range: NSRange, replacementString: String?) -> Bool {
        guard let replacementString, replacementString.rangeOfCharacter(from: .newlines) != nil else { return true }
        let flattened = replacementString.components(separatedBy: .newlines).joined(separator: " ")
        textView.insertText(flattened, replacementRange: range)
        return false
    }

    func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard !textView.hasMarkedText() else { return false }
        switch selector {
        case #selector(NSResponder.insertNewline(_:)), #selector(NSResponder.insertTab(_:)):
            if isDirty { onCommit?(title) }
            onExit?()
            return true
        case #selector(NSResponder.moveDown(_:)):
            let length = (textView.string as NSString).length
            guard textView.selectedRange().location >= length || field.isOnLastLine else { return false }
            if isDirty { onCommit?(title) }
            onExit?()
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            if isDirty { onCommit?(title) }
            onExit?()
            return true
        default:
            return false
        }
    }
}

@MainActor
final class NotePageTitleTextView: NSTextView {
    var placeholder: String? { didSet { needsDisplay = true } }
    var placeholderColor: NSColor = NoteTheme.placeholderInk { didSet { needsDisplay = true } }

    convenience init() {
        self.init(usingTextLayoutManager: false)
        isRichText = false
        importsGraphics = false
        allowsUndo = true
        drawsBackground = false
        textContainerInset = .zero
        textContainer?.lineFragmentPadding = 0
        textContainer?.widthTracksTextView = true
        isVerticallyResizable = false
        isHorizontallyResizable = false
        usesFindBar = false
        isAutomaticQuoteSubstitutionEnabled = true
        isAutomaticDashSubstitutionEnabled = true
        font = NoteTheme.titleFont(.standard)
        setAccessibilityLabel("Title")
        setAccessibilityRole(.textField)
    }

    override var acceptsFirstResponder: Bool { isEditable }

    override var readablePasteboardTypes: [NSPasteboard.PasteboardType] { [.string] }

    func height(for width: CGFloat) -> CGFloat {
        guard let layoutManager, let textContainer else { return 48 }
        textContainer.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
        layoutManager.ensureLayout(for: textContainer)
        let used = layoutManager.usedRect(for: textContainer).height
        let line = font.map { layoutManager.defaultLineHeight(for: $0) } ?? 48
        return ceil(max(used, line))
    }

    var isOnLastLine: Bool {
        guard let layoutManager else { return true }
        let length = (string as NSString).length
        guard length > 0 else { return true }
        let caret = min(selectedRange().location, length - 1)
        let glyph = layoutManager.glyphIndexForCharacter(at: caret)
        let line = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        let last = layoutManager.lineFragmentRect(forGlyphAt: layoutManager.glyphIndexForCharacter(at: length - 1), effectiveRange: nil)
        return abs(line.minY - last.minY) < 1
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, let placeholder, let font else { return }
        NSAttributedString(string: placeholder, attributes: [.font: font, .foregroundColor: placeholderColor])
            .draw(at: NSPoint(x: textContainerOrigin.x, y: textContainerOrigin.y))
    }

    override func didChangeText() {
        super.didChangeText()
        needsDisplay = true
    }
}

enum NotePagePrintDocument {
    @MainActor
    static func render(title: String, page: NotePage, plainText: Bool) -> NSAttributedString {
        let output = NSMutableAttributedString()
        let ink = NSColor.black
        let secondary = NSColor(white: 0.4, alpha: 1)
        func paragraph(spacingBefore: CGFloat = 2, after: CGFloat = 6, indent: CGFloat = 0) -> NSParagraphStyle {
            let style = NSMutableParagraphStyle()
            style.paragraphSpacingBefore = spacingBefore
            style.paragraphSpacing = after
            style.lineHeightMultiple = 1.2
            style.firstLineHeadIndent = indent
            style.headIndent = indent
            return style
        }
        output.append(NSAttributedString(string: title + "\n", attributes: [
            .font: NoteTheme.titleFont(page.settings.font), .foregroundColor: ink, .paragraphStyle: paragraph(after: 14),
        ]))
        let body = NoteTheme.bodyFont(plainText ? .mono : page.settings.font, small: page.settings.smallText)
        func styled(_ text: NoteText, font: NSFont, color: NSColor) -> NSAttributedString {
            let result = NSMutableAttributedString()
            for run in text.runs() {
                var value = run.marks.atom?.fallbackText ?? (text.string as NSString).substring(with: NSRange(location: run.range.lowerBound, length: run.range.count))
                if case .equation? = run.marks.atom { value = "$" + value + "$" }
                var runFont = font
                if run.marks.code { runFont = NoteTheme.codeFont(size: font.pointSize * 0.88) }
                else if run.marks.bold || run.marks.italic {
                    runFont = NoteTheme.bodyFont(page.settings.font, small: page.settings.smallText, bold: run.marks.bold, italic: run.marks.italic)
                    if font.pointSize != runFont.pointSize { runFont = NSFontManager.shared.convert(runFont, toSize: font.pointSize) }
                }
                var attributes: [NSAttributedString.Key: Any] = [.font: runFont, .foregroundColor: color]
                if run.marks.underline || run.marks.link != nil { attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue }
                if run.marks.strikethrough { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
                if let style = run.marks.color {
                    if style.isBackground { attributes[.backgroundColor] = NoteTheme.color(style).usingColorSpace(.sRGB) }
                    else { attributes[.foregroundColor] = NoteTheme.color(style).usingColorSpace(.sRGB) ?? color }
                }
                result.append(NSAttributedString(string: value, attributes: attributes))
            }
            return result
        }
        var numbers: [Int: Int] = [:]
        func walk(_ blocks: [NoteBlock], depth: Int) {
            for block in blocks {
                let indent = CGFloat(depth) * 22
                if block.kind != .numberedItem { numbers[depth] = nil }
                var prefix = ""
                var font = body
                var color = ink
                var style = paragraph(indent: indent)
                switch block.kind {
                case .heading:
                    font = NoteTheme.headingFont(block.props.level, font: page.settings.font, small: page.settings.smallText)
                    style = paragraph(spacingBefore: 12, after: 4, indent: indent)
                case .bulletedItem: prefix = "•  "
                case .numberedItem:
                    let number = (numbers[depth] ?? (block.props.listStart ?? 1) - 1) + 1
                    numbers[depth] = number
                    prefix = "\(number).  "
                case .todo:
                    prefix = block.props.checked ? "☑  " : "☐  "
                    if block.props.checked { color = secondary }
                case .toggle: prefix = block.props.expanded ? "▾  " : "▸  "
                case .quote: prefix = "┃  "
                case .callout: prefix = (block.props.icon ?? "💡") + "  "
                case .code, .equation, .html, .raw:
                    font = NoteTheme.codeFont(size: max(10, body.pointSize - 3))
                case .divider:
                    output.append(NSAttributedString(string: "———\n", attributes: [.font: body, .foregroundColor: secondary, .paragraphStyle: style]))
                    continue
                case .image, .video, .audio, .file, .bookmark, .embed, .pageLink:
                    let label = block.kind == .pageLink ? block.text.plainText : (block.props.caption.isEmpty ? (block.props.source ?? "") : block.props.caption.plainText)
                    output.append(NSAttributedString(string: "↗ " + label + "\n", attributes: [.font: body, .foregroundColor: secondary, .paragraphStyle: style]))
                    continue
                case .table:
                    let rows = block.props.table?.rows ?? []
                    for row in rows {
                        output.append(NSAttributedString(string: row.map(\.plainText).joined(separator: "  │  ") + "\n",
                                                         attributes: [.font: body, .foregroundColor: ink, .paragraphStyle: style]))
                    }
                    continue
                case .tableOfContents, .columns, .column, .paragraph:
                    break
                }
                if block.kind.hasRichText || block.kind.hasPlainText {
                    let line = NSMutableAttributedString(string: prefix, attributes: [.font: body, .foregroundColor: secondary])
                    line.append(block.kind.hasPlainText ? NSAttributedString(string: block.text.string, attributes: [.font: font, .foregroundColor: color])
                                                        : styled(block.text, font: font, color: color))
                    line.append(NSAttributedString(string: "\n"))
                    line.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: line.length))
                    if block.kind == .todo && block.props.checked {
                        line.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue,
                                          range: NSRange(location: prefix.utf16.count, length: max(0, line.length - prefix.utf16.count - 1)))
                    }
                    output.append(line)
                }
                if block.showsChildren { walk(block.children, depth: block.kind == .columns || block.kind == .column ? depth : depth + 1) }
            }
        }
        walk(page.blocks, depth: 0)
        return output
    }
}
