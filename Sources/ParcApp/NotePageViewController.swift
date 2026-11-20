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
    var onTrashed: ((URL) -> Void)?
    var downloadFolder: (@MainActor () async -> URL?)?
    private let root = NotePageRootView()
    private let scroll = NSScrollView()
    private let status = NotePageStatusView()
    private var header: NotePageHeaderView?
    private var pageMenu: NotePageMenu?
    private var pageMenuButton: NotePageMenuButton?
    private var lease: NoteFileLease?
    private var isTornDown = false
    private var isPreparingPrint = false
    private static var openEditors: [ObjectIdentifier: Int] = [:]
    static let pageMenuInset = NSPoint(x: 14, y: 12)
    private var subscriptions = Set<AnyCancellable>()
    private var unsavedSince: Date?
    private var slowSaveToken = 0
    private var transientError: String?
    private var spaceAppearance: NSAppearance?
    private var reportedTitle: String?

    static let slowSaveDelay: TimeInterval = 8

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
        editor.onFocusTitle = { [weak self] in self?.focusTitle(selectAll: false) }
        editor.onPrint = { [weak self] in self?.printPage() }
        editor.onChange = { [weak self] change in self?.pageDidChange(change) }
        editor.handles.presentToast = { [weak self] content in self?.onToast?(content) }
        editor.handles.downloadFolder = { [weak self] in await self?.downloadFolder?() }
        editor.formatBar.onToast = { [weak self] content in self?.onToast?(content) }

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

        let header = NotePageHeaderView(editor: editor, file: file)
        header.onTitleCommit = { [weak self] title in try self?.commitTitle(title) }
        self.header = header
        editor.canvas.headerView = header

        let pageMenu = NotePageMenu(editor: editor, file: file)
        pageMenu.onToast = { [weak self] content in self?.onToast?(content) }
        pageMenu.onTrashed = { [weak self] url in self?.onTrashed?(url) }
        self.pageMenu = pageMenu
        let pageMenuButton = pageMenu.makeButton()
        root.addSubview(pageMenuButton)
        self.pageMenuButton = pageMenuButton
        editor.find.topInset = Self.pageMenuInset.y + NotePageMenuButton.size.height + 6

        status.onAction = { [weak self] action in self?.performStatusAction(action) }
        root.addSubview(status)
        root.onLayout = { [weak self] in self?.layoutRoot() }
        view = root

        editor.canvas.spaceFocus = spaceFocus
        Self.openEditors[ObjectIdentifier(file), default: 0] += 1
        lease = NoteFileLease(file)
        reportedTitle = file.title
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
        pageMenu?.close(animated: false)
        editor?.dismissOverlays()
        header?.commitTitle()
    }

    var canAcceptExternalDrop: Bool { isViewLoaded && !(editor?.hasMarkedText ?? false) && !(header?.titleView.hasMarkedText() ?? false) }

    var isReadOnly: Bool { editor?.isReadOnly ?? (file.page.isReadOnly || file.page.page.settings.locked) }

    func inheritSpaceContentAppearance(_ appearance: NSAppearance?) {
        spaceAppearance = appearance
        guard isViewLoaded else { return }
        view.appearance = appearance
        root.needsDisplay = true
        editor.appearanceDidChange()
        status.needsDisplay = true
        header?.needsDisplay = true
    }

    var spaceFocus: NSColor? {
        didSet {
            guard isViewLoaded, spaceFocus != oldValue else { return }
            editor.canvas.spaceFocus = spaceFocus
        }
    }

    func focusContent() {
        guard isViewLoaded, let window = view.window else { return }
        if !isReadOnly, let header {
            let title = header.title.trimmingCharacters(in: .whitespacesAndNewlines)
            if title.isEmpty {
                focusTitle(selectAll: false)
                return
            }
            if Self.isPlaceholderTitle(title), editor.session.page.plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                focusTitle(selectAll: true)
                return
            }
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
        pageMenu?.close(animated: false)
        editor.dismissOverlays()
        header?.commitTitle()
        do {
            try file.flush()
            return true
        } catch {
            showTransientError(error)
            return false
        }
    }

    func teardown() {
        guard !isTornDown else { return }
        isTornDown = true
        pageMenu?.close(animated: false)
        editor?.dismissOverlays()
        editor?.slashMenu.tearDown()
        if isViewLoaded, Self.closeEditor(of: file) {
            try? file.flush()
            NotePageHistory.fileWillClose(file)
        }
        lease?.end()
        lease = nil
    }

    private static func closeEditor(of file: NoteFileSession) -> Bool {
        let key = ObjectIdentifier(file)
        guard let count = openEditors[key] else { return false }
        if count > 1 {
            openEditors[key] = count - 1
            return false
        }
        openEditors.removeValue(forKey: key)
        return true
    }

    static func findCommand(for action: BrowserFindAction) -> NoteKeyCommand? {
        switch action {
        case .show: return .find
        case .replace: return .findAndReplace
        case .next: return .findNext
        case .previous: return .findPrevious
        case .useSelection: return .useSelectionForFind
        case .jumpToSelection: return nil
        }
    }

    @discardableResult
    func reveal(anchor: String) -> Bool {
        guard isViewLoaded, !isTornDown else { return false }
        return editor.reveal(anchor: anchor)
    }

    func canPerform(_ action: BrowserFindAction) -> Bool {
        guard isViewLoaded, !isTornDown, !editor.hasMarkedText else { return false }
        if let command = Self.findCommand(for: action) { return editor.validate(command) }
        if case .none = editor.session.selection { return false }
        return true
    }

    func perform(_ action: BrowserFindAction) -> Bool {
        guard canPerform(action) else { return false }
        if let command = Self.findCommand(for: action) { return editor.perform(command) }
        editor.restoreFocus()
        return true
    }

    fileprivate func routeKeyEquivalent(_ event: NSEvent) -> Bool {
        guard let window = view.window, window.isKeyWindow, let responder = window.firstResponder as? NSView,
              responder === view || responder.isDescendant(of: view) else { return false }
        if editor.ownsFocus {
            if editor.performKeyEquivalent(event) { return true }
            guard !editor.hasMarkedText, let chord = NoteKeyChord(event: event) else { return false }
            return NoteFormatShortcuts.displacedFormat(for: chord) { format in
                KeyboardShortcuts.shared.activeShortcut(for: format.bindingID).map { TextFormatKeyEquivalent(key: $0.key, modifiers: $0.flags) }
            } != nil
        }
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
        if let pageMenuButton {
            let size = NotePageMenuButton.size
            pageMenuButton.frame = NSRect(x: max(0, root.bounds.width - size.width - Self.pageMenuInset.x), y: Self.pageMenuInset.y,
                                          width: size.width, height: size.height)
        }
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

    private func focusTitle(selectAll: Bool) {
        guard let header, view.window != nil, !isReadOnly else { return }
        editor.canvas.scrollToVisible(header.titleView.frame.offsetBy(dx: header.frame.minX, dy: header.frame.minY))
        header.focusTitle(selectAll: selectAll)
    }

    static func isPlaceholderTitle(_ title: String) -> Bool {
        title.range(of: "^Untitled( [0-9]+)?$", options: .regularExpression) != nil
    }

    private func commitTitle(_ title: String) throws {
        guard !isReadOnly else { return }
        let before = file.title
        _ = try file.rename(to: title)
        if file.title != before { reportTitle() }
    }

    private func fileDidMove(to url: URL) {
        onURLChange?(url)
        reportTitle()
    }

    private func reportTitle() {
        guard file.title != reportedTitle else { return }
        reportedTitle = file.title
        onTitleChange?(file.title)
    }

    private func pageDidChange(_ change: NotePageChange) {
        if change.kind == .settings || change.kind == .replaced { refreshStatus() }
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
        case .retry:
            do { try file.flush() } catch { showTransientError(error) }
        case .restore:
            do { try file.restore() } catch { showTransientError(error) }
        case .keepMine:
            file.resolveConflict(keepMine: true)
        case .useFile:
            file.resolveConflict(keepMine: false)
        case .unlock:
            editor.session.updateSettings(name: "Unlock Note") { $0.locked = false }
        case .dismiss:
            transientError = nil
        }
        refreshStatus()
    }

    func printPage() {
        guard isViewLoaded, view.window?.attachedSheet == nil, !isPreparingPrint else { return }
        isPreparingPrint = true
        NotePagePrintView.prepare(page: editor.session.page, title: file.title, environment: editor.environment) { [weak self] printView in
            guard let self else { return }
            self.isPreparingPrint = false
            guard !self.isTornDown, let window = self.view.window, window.attachedSheet == nil else { return }
            let operation = printView.printOperation(info: printView.printInfo())
            operation.showsPrintPanel = true
            operation.showsProgressPanel = true
            operation.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
        }
    }
}

extension NotePageViewController: TextFormatShortcutOwner {
    func formatKeyEquivalent(for command: TextFormatCommand) -> TextFormatKeyEquivalent? {
        NoteFormatShortcuts.keyEquivalent(for: command)
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
        case .conflict: return [(.keepMine, "Keep Mine"), (.useFile, "Use the File’s Version")]
        case .missing: return [(.restore, "Put It Back")]
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
