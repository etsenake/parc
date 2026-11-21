import AppKit

@MainActor
final class EaselTextCompletions: EaselTextCompletion {
    private let parts: [EaselTextCompletion]

    init(_ parts: [EaselTextCompletion]) { self.parts = parts }

    func attach(_ view: EaselStyledTextView) { parts.forEach { $0.attach(view) } }
    func textDidChange(in view: EaselStyledTextView) { parts.forEach { $0.textDidChange(in: view) } }
    func handle(_ selector: Selector, in view: EaselStyledTextView) -> Bool { parts.contains { $0.handle(selector, in: view) } }
    func perform(_ request: EaselTextRequest, in view: EaselStyledTextView) -> Bool { parts.contains { $0.perform(request, in: view) } }
    func dismiss() { parts.forEach { $0.dismiss() } }
    func detach() { parts.forEach { $0.detach() } }
}

@MainActor
final class EaselSlashCompletion: EaselTextCompletion {
    private weak var view: EaselStyledTextView?
    private var presenter: NoteSlashListPresenter!
    private var token: NoteQueryToken?
    private var tracker = NoteQueryTracker.slash
    private var results: [EaselSlashRow] = []
    private var currentQuery: String?
    private var cancelledStart: Int?
    private var previous = ""
    private var observer: NSObjectProtocol?
    private var pointerMonitor: Any?
    private var pickerPanel: NoteFloatingPanel?

    init() {
        presenter = NoteSlashListPresenter(overlay: { [weak self] in self?.host })
        let list = presenter.list
        list.maximumHeight = 372
        list.filtersOnTyping = false
        list.fixedWidth = NoteSlashMenuController.blockMenuWidth
        list.noResultsTitle = "Nothing by that name. Keep typing?"
        list.setAccessibilityLabel("Insert")
        list.onActivate = { [weak self] item in self?.choose(item.id) }
        list.onCancel = { [weak self] in self?.cancel() }
        list.onHighlight = { [weak self] item in
            guard let self else { return }
            self.presenter.highlightDidChange(item, block: item.flatMap { found in self.results.first { $0.id == found.id }?.item.block })
        }
    }

    func attach(_ view: EaselStyledTextView) {
        detach()
        self.view = view
        previous = view.string
        observer = NotificationCenter.default.addObserver(forName: NSTextView.didChangeSelectionNotification, object: view,
                                                          queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.selectionDidChange() }
        }
    }

    func detach() {
        dismiss()
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        view = nil
    }

    private var canvas: EaselCanvasView? {
        var ancestor = view?.superview
        while let current = ancestor {
            if let canvas = current as? EaselCanvasView { return canvas }
            ancestor = current.superview
        }
        return nil
    }

    private var host: NSView? { canvas?.menuHost }

    private var isOpen: Bool { token != nil }

    func textDidChange(in view: EaselStyledTextView) {
        guard view === self.view else { return }
        let old = previous
        previous = view.string
        guard !view.hasMarkedText(), view.selectedRanges.count == 1, view.selectedRange().length == 0 else { dismiss(); return }
        if isOpen { refresh(); return }
        guard canvas?.slashMenuAvailable == true else { return }
        let caret = view.selectedRange().location
        if let found = NoteTriggerRule.trigger(from: old, to: view.string, caret: caret), found.trigger == .slash, !isCode(at: found.start, in: view) {
            cancelledStart = nil
            open(start: found.start, resuming: false)
            return
        }
        guard case .inline(.slash, let start)? = NoteTriggerRule.resumedTrigger(from: old, to: view.string, caret: caret),
              !isCode(at: start, in: view), cancelledStart != start else { return }
        open(start: start, resuming: true)
    }

    func handle(_ selector: Selector, in view: EaselStyledTextView) -> Bool {
        guard view === self.view, isOpen else { return false }
        let list = presenter.list
        switch selector {
        case #selector(NSResponder.moveUp(_:)), #selector(NSResponder.insertBacktab(_:)): return list.moveHighlight(by: -1)
        case #selector(NSResponder.moveDown(_:)): return list.moveHighlight(by: 1)
        case #selector(NSResponder.insertTab(_:)): return list.activateHighlighted() || list.moveHighlight(by: 1)
        case #selector(NSResponder.insertNewline(_:)), #selector(NSResponder.insertLineBreak(_:)):
            if list.activateHighlighted() { return true }
            dismiss()
            return false
        case #selector(NSResponder.cancelOperation(_:)):
            cancel()
            return true
        default:
            return false
        }
    }

    func dismiss() {
        token = nil
        results = []
        currentQuery = nil
        stopWatchingPointer()
        presenter.list.filterText = ""
        presenter.clearVisuals(animated: true)
        for panel in [presenter.presentedPanel, pickerPanel] {
            guard let panel, panel.isPresented else { continue }
            panel.dismiss(animated: true)
        }
        pickerPanel = nil
    }

    private func cancel() {
        cancelledStart = token?.start
        dismiss()
    }

    private func open(start: Int, resuming: Bool) {
        guard let view, let canvas else { return }
        let text = view.string, caret = view.selectedRange().location
        token = NoteQueryToken(start: start, trigger: "/", text: text, caret: caret)
        tracker = .slash
        let context = canvas.slashContext
        if resuming, let query = resolvedQuery()?.query {
            tracker.resume(query: query) { !EaselSlashCatalog.results(for: $0, in: context).isEmpty }
        }
        currentQuery = nil
        results = []
        presenter.list.filterText = ""
        presenter.list.prepare(origin: .keyboard)
        watchPointer()
        refresh()
    }

    private func resolvedQuery() -> NoteQueryMatch? {
        guard let view, var token, view.selectedRanges.count == 1, view.selectedRange().length == 0 else { return nil }
        let match = token.resolve(in: view.string, caret: view.selectedRange().location)
        self.token = token
        return match
    }

    private func selectionDidChange() {
        guard let view else { return }
        if view.string != previous, !view.hasMarkedText() { previous = view.string }
        guard isOpen, !view.hasMarkedText() else { return }
        refresh()
    }

    private func refresh() {
        guard let canvas, let match = resolvedQuery() else { dismiss(); return }
        let found = EaselSlashCatalog.results(for: match.query, in: canvas.slashContext)
        guard tracker.update(query: match.query, hasResults: !found.isEmpty) == .open else { dismiss(); return }
        guard match.query != currentQuery || presenter.presentedPanel == nil else { return }
        currentQuery = match.query
        results = found
        let filtering = !match.query.isEmpty
        presenter.show(found.map { NoteSlashMenuRows.item(for: $0.item, filtering: filtering) }, detailed: !filtering, highlightFirst: filtering,
                       anchor: { [weak self] in self?.menuAnchor() })
    }

    private func menuAnchor() -> NSRect? {
        guard let token, let rect = caretRect(at: token.start) else { return nil }
        return rect.offsetBy(dx: -NoteTheme.menuInset - 4, dy: 0)
    }

    private func caretRect(at location: Int) -> NSRect? {
        guard let view, let host, let window = view.window, location <= (view.string as NSString).length else { return nil }
        let screen = view.firstRect(forCharacterRange: NSRange(location: location, length: 0), actualRange: nil)
        guard screen.origin.x.isFinite, screen.origin.y.isFinite, screen.height > 0 else { return nil }
        return host.convert(window.convertFromScreen(screen), from: nil)
    }

    private func isCode(at location: Int, in view: EaselStyledTextView) -> Bool {
        guard let storage = view.textStorage, location >= 0, location < storage.length else { return false }
        return EaselTextAppearance.isInlineCode(storage.attributes(at: location, effectiveRange: nil))
    }

    private func choose(_ id: String) {
        guard let row = results.first(where: { $0.id == id }), let view, let match = resolvedQuery() else { dismiss(); return }
        let range = NSRange(location: match.range.lowerBound, length: match.range.count)
        let canvas = self.canvas
        dismiss()
        switch row.action {
        case .text(let id):
            guard let kind = Self.paragraph(id) else { NSSound.beep(); return }
            view.applySlashParagraph(kind, removing: range)
        case .emoji:
            view.insertCompletion("", replacing: range, name: "Slash")
            openEmojiPicker(at: range.location)
        case .object(let object):
            view.insertCompletion("", replacing: range, name: "Slash")
            if canvas?.placeSlashObject(object) != true { NSSound.beep() }
        case .divider, .mention, .date, .inlineEquation:
            NSSound.beep()
        }
    }

    private static func paragraph(_ id: String) -> EaselParagraphEditing.Kind? {
        switch id {
        case "text": return .text
        case "heading1": return .heading1
        case "heading2": return .heading2
        case "heading3": return .heading3
        case "bulleted": return .bullets
        case "numbered": return .numbers
        case "quote": return .quote
        default: return nil
        }
    }

    private func openEmojiPicker(at location: Int) {
        guard let view, let host, let rect = caretRect(at: location) else { return }
        let picker = NoteEmojiPicker(showsRandom: true, library: EaselNoteEnvironment(folder: canvas?.notesFolder?()).emojiLibrary)
        let panel = NoteFloatingPanel(content: picker)
        panel.maximumHeight = 400
        pickerPanel = panel
        picker.onPick = { [weak self, weak view] character in
            self?.dismiss()
            guard let view else { return }
            view.window?.makeFirstResponder(view)
            let caret = min(location, (view.string as NSString).length)
            if NoteCustomEmojiName.name(inReference: character) != nil, view.insertCustomEmoji(character, replacing: NSRange(location: caret, length: 0)) { return }
            view.insertCompletion(character, replacing: NSRange(location: caret, length: 0), name: "Emoji")
        }
        picker.onCancel = { [weak self, weak view] in
            self?.dismiss()
            if let view { view.window?.makeFirstResponder(view) }
        }
        watchPointer()
        panel.present(in: host, anchor: rect, edge: .below, animated: true)
        picker.focusSearch()
    }

    private func watchPointer() {
        guard pointerMonitor == nil else { return }
        pointerMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            MainActor.assumeIsolated { self?.pointerWentDown(event) }
            return event
        }
    }

    private func stopWatchingPointer() {
        if let pointerMonitor { NSEvent.removeMonitor(pointerMonitor) }
        pointerMonitor = nil
    }

    private func pointerWentDown(_ event: NSEvent) {
        let panels = [presenter.presentedPanel, pickerPanel].compactMap { $0 }.filter(\.isPresented)
        if panels.contains(where: { $0.window === event.window && $0.bounds.contains($0.convert(event.locationInWindow, from: nil)) }) { return }
        if pickerPanel == nil, let view, view.window === event.window, let content = event.window?.contentView,
           let hit = content.hitTest(content.superview?.convert(event.locationInWindow, from: nil) ?? event.locationInWindow),
           hit === view || hit.isDescendant(of: view) { return }
        dismiss()
    }
}
