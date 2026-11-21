import AppKit

@MainActor
final class EaselNoteEnvironment: NoteEnvironment {
    let folder: URL?
    init(folder: URL?) { self.folder = folder }

    var documentURL: URL? { folder?.appendingPathComponent("Easel", isDirectory: false) }
    var isPlainText: Bool { false }
    var emojiLibrary: NoteEmojiLibrary? { documentURL.map(NoteEmojiLibrary.library(for:)) }

    func resolve(_ source: String) -> URL? { URL(string: source) }
    func importAsset(from url: URL) throws -> String { throw CocoaError(.fileWriteNoPermission) }
    func importAsset(data: Data, fileExtension: String, suggestedName: String?) throws -> String { throw CocoaError(.fileWriteNoPermission) }

    func searchNotes(_ query: String, limit: Int) -> [NoteReference] {
        guard let folder, limit > 0 else { return [] }
        return NoteLibrary.shared(folder: folder).search(query, limit: limit)
    }

    func linkTarget(for note: URL) -> String { URL(fileURLWithPath: note.path).absoluteString }

    func resolveNoteLink(_ target: String) -> URL? {
        guard let url = URL(string: target), url.isFileURL else { return nil }
        return NoteFilePaths.canonical(url)
    }

    func createNote(titled title: String) throws -> URL {
        guard let folder else { throw NoteFileError.missing }
        return try NoteLibrary.createNote(in: folder, title: title)
    }

    static func customEmoji(_ name: String, in library: NoteEmojiLibrary?) -> EaselRichText.Inline? {
        guard let library, let entry = library.emoji(named: name) else { return nil }
        let data = try? Data(contentsOf: library.imageURL(for: entry), options: .mappedIfSafe)
        let inline = EaselRichText.Inline.emoji(entry.name, image: data)
        if (try? inline.validate()) != nil { return inline }
        let bare = EaselRichText.Inline.emoji(entry.name, image: nil)
        return (try? bare.validate()) != nil ? bare : nil
    }
}

@MainActor
final class EaselMentionCompletion: EaselTextCompletion {
    private enum Mode { case mention(NoteMentionMenu.Scope), date(Int), equation(Int) }

    private weak var view: EaselStyledTextView?
    private var presenter: NoteSlashListPresenter!
    private var mode: Mode?
    private var token: NoteQueryToken?
    private var tracker = NoteQueryTracker.mention
    private var currentQuery: String?
    private var cancelledStart: Int?
    private var choices: [String: NoteMentionMenu.Choice] = [:]
    private var previous = ""
    private var observer: NSObjectProtocol?
    private var datePicker: NoteDatePickerView?
    private var floating: NoteFloatingPanel?
    private var equation: (editor: NoteEquationEditorView, original: String)?
    private var pointerMonitor: Any?

    init() {
        presenter = NoteSlashListPresenter(overlay: { [weak self] in self?.host })
        let list = presenter.list
        list.maximumHeight = 372
        list.filtersOnTyping = false
        list.fixedWidth = NoteSlashMenuController.mentionMenuWidth
        list.onActivate = { [weak self] item in self?.choose(item.id) }
        list.onCancel = { [weak self] in self?.cancel() }
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

    private var host: NSView? { canvas?.menuHost ?? view?.superview }

    private var environment: EaselNoteEnvironment { EaselNoteEnvironment(folder: canvas?.notesFolder?()) }

    func textDidChange(in view: EaselStyledTextView) {
        guard view === self.view else { return }
        let old = previous
        previous = view.string
        guard !view.hasMarkedText(), view.selectedRanges.count == 1, view.selectedRange().length == 0 else { dismiss(); return }
        switch mode {
        case .mention?: refresh(); return
        case .date?, .equation?: dismiss(); return
        case nil: break
        }
        let caret = view.selectedRange().location
        if let found = NoteTriggerRule.trigger(from: old, to: view.string, caret: caret), found.trigger != .slash, !isCode(at: found.start) {
            cancelledStart = nil
            open(start: found.start, trigger: found.trigger, resuming: false)
            return
        }
        guard case .inline(let trigger, let start)? = NoteTriggerRule.resumedTrigger(from: old, to: view.string, caret: caret),
              trigger != .slash, !isCode(at: start), cancelledStart != start else { return }
        open(start: start, trigger: trigger, resuming: true)
    }

    func handle(_ selector: Selector, in view: EaselStyledTextView) -> Bool {
        guard view === self.view, let mode else { return false }
        switch mode {
        case .equation:
            return false
        case .date:
            if datePicker?.handleCommand(selector) == true { return true }
            switch selector {
            case #selector(NSResponder.cancelOperation(_:)), #selector(NSResponder.insertNewline(_:)): dismiss(); return true
            case #selector(NSResponder.moveLeft(_:)): return datePicker?.move(byDays: -1) ?? false
            case #selector(NSResponder.moveRight(_:)): return datePicker?.move(byDays: 1) ?? false
            case #selector(NSResponder.moveUp(_:)): return datePicker?.move(byDays: -7) ?? false
            case #selector(NSResponder.moveDown(_:)): return datePicker?.move(byDays: 7) ?? false
            default: return false
            }
        case .mention:
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
    }

    func perform(_ request: EaselTextRequest, in view: EaselStyledTextView) -> Bool {
        guard view === self.view, view.isEditable, !view.hasMarkedText(), view.selectedRanges.count == 1 else { return false }
        switch request {
        case .mention(let dates):
            let range = view.selectedRange()
            view.insertCompletion("@", replacing: range, name: dates ? "Date" : "Mention")
            previous = view.string
            cancelledStart = nil
            open(start: range.location, trigger: .mention, resuming: false, scope: dates ? .dates : .everything)
            return true
        case .inlineEquation:
            let range = view.selectedRange()
            let selected = (view.string as NSString).substring(with: range)
            let tex = selected.contains(where: \.isNewline) || selected.contains("\u{FFFC}") ? "" : selected
            guard view.replace(range, with: .equation(tex), name: "Inline Equation") else { return false }
            previous = view.string
            return openEquation(at: range.location)
        case .activate(let index):
            guard let inline = EaselInlineText.inline(at: index, in: view.attributedString()) else { return false }
            switch inline.kind {
            case .note:
                guard let url = inline.noteURL, let canvas else { return false }
                if url.scheme == "parc" { canvas.onOpenURL?(url) } else { canvas.onOpenNote?(url) }
                return true
            case .date: return openDate(at: index)
            case .equation: return openEquation(at: index)
            case .emoji: return false
            }
        case .customEmoji(let reference, let range):
            guard let name = NoteCustomEmojiName.name(inReference: reference),
                  let inline = EaselNoteEnvironment.customEmoji(name, in: environment.emojiLibrary) else { return false }
            NoteEmojiCatalog.shared.recordUse(reference)
            let result = view.replace(range, with: inline, name: "Emoji")
            previous = view.string
            return result
        }
    }

    func dismiss() {
        let wasEquation: Bool
        if case .equation? = mode { wasEquation = true } else { wasEquation = false }
        if wasEquation { finishEquation(commit: true) }
        mode = nil
        token = nil
        choices = [:]
        currentQuery = nil
        datePicker = nil
        equation = nil
        stopWatchingPointer()
        presenter.list.filterText = ""
        presenter.clearVisuals(animated: true)
        for panel in [presenter.presentedPanel, floating] {
            guard let panel, panel.isPresented else { continue }
            panel.dismiss(animated: true)
        }
        floating = nil
    }

    private func cancel() {
        cancelledStart = token?.start
        dismiss()
    }

    private func open(start: Int, trigger: NoteInlineTrigger, resuming: Bool, scope requested: NoteMentionMenu.Scope? = nil) {
        guard let view else { return }
        dismiss()
        let scope = requested ?? (trigger == .noteLink ? .notes : .everything)
        token = NoteQueryToken(start: start, trigger: trigger.symbol, text: view.string, caret: view.selectedRange().location)
        mode = .mention(scope)
        tracker = .mention
        if resuming, let query = resolvedQuery()?.query {
            let parser = NoteDateParser(), environment = self.environment
            tracker.resume(query: query) { prefix in
                NoteMentionMenu.contents(for: prefix, scope: scope, environment: environment, parser: parser).hasResults
                    || NoteMentionMenu.isStillTyping(prefix, scope: scope, parser: parser)
            }
        }
        currentQuery = nil
        presenter.list.filterText = ""
        presenter.list.setAccessibilityLabel(scope == .dates ? "Insert a date" : "Mention a note or date")
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
        guard case .mention? = mode, !view.hasMarkedText() else { return }
        refresh()
    }

    private func refresh() {
        guard case .mention(let scope)? = mode, let match = resolvedQuery() else { dismiss(); return }
        let parser = NoteDateParser()
        let contents = NoteMentionMenu.contents(for: match.query, scope: scope, environment: environment, parser: parser)
        let alive = contents.hasResults || NoteMentionMenu.isStillTyping(match.query, scope: scope, parser: parser)
        guard tracker.update(query: match.query, hasResults: alive) == .open else { dismiss(); return }
        guard match.query != currentQuery || presenter.presentedPanel == nil else { return }
        currentQuery = match.query
        choices = contents.choices
        presenter.list.noResultsTitle = NoteMentionMenu.noResultsTitle(for: scope)
        presenter.show(contents.items, detailed: false, highlightFirst: true, anchor: { [weak self] in self?.menuAnchor() })
    }

    private func choose(_ id: String) {
        guard let choice = choices[id], let view, let match = resolvedQuery() else { dismiss(); return }
        let range = NSRange(location: match.range.lowerBound, length: match.range.count)
        let environment = self.environment
        dismiss()
        switch choice {
        case .date(let mention):
            _ = view.replace(range, with: .date(mention), name: mention.remind ? "Reminder" : "Date")
            if mention.remind { NoteReminderCenter.shared.requestAuthorizationIfNeeded() }
        case .note(let reference):
            _ = view.replace(range, with: .note(reference.url, title: reference.title), name: "Mention")
        case .createNote(let name):
            do {
                let url = try environment.createNote(titled: name)
                _ = view.replace(range, with: .note(url, title: url.deletingPathExtension().lastPathComponent), name: "Mention")
            } catch { canvas?.onError?(error) }
        }
        previous = view.string
    }

    private func openDate(at index: Int) -> Bool {
        guard let view, let mention = EaselInlineText.inline(at: index, in: view.attributedString())?.dateMention,
              let host, let anchor = rect(of: index) else { return false }
        dismiss()
        let picker = NoteDatePickerView(mention: mention)
        picker.onChange = { [weak self] value in self?.updateDate(value, at: index) }
        picker.onRemove = { [weak self] in self?.removeInline(at: index, name: "Remove Date") }
        picker.onNeedsTextFocus = { [weak self] in self?.focusText(after: index) }
        let panel = NoteFloatingPanel(content: picker)
        panel.onDismiss = { [weak self, weak panel] in
            guard let self, self.floating === panel else { return }
            self.mode = nil; self.datePicker = nil; self.floating = nil
        }
        datePicker = picker
        floating = panel
        mode = .date(index)
        watchPointer()
        panel.present(in: host, anchor: anchor, edge: .below, animated: true)
        return true
    }

    private func updateDate(_ value: NoteDateMention, at index: Int) {
        guard let view, EaselInlineText.inline(at: index, in: view.attributedString())?.kind == .date else { dismiss(); return }
        let selection = view.selectedRanges
        _ = view.replace(NSRange(location: index, length: 1), with: .date(value), name: value.remind ? "Reminder" : "Change Date")
        view.selectedRanges = selection
        previous = view.string
        if value.remind { NoteReminderCenter.shared.requestAuthorizationIfNeeded() }
        if let panel = floating, panel.isPresented, let anchor = rect(of: index) {
            panel.reposition(anchor: anchor, edge: panel.resolvedEdge, animated: true)
        }
    }

    private func removeInline(at index: Int, name: String) {
        guard let view, EaselInlineText.inline(at: index, in: view.attributedString()) != nil else { dismiss(); return }
        dismiss()
        _ = view.replace(NSRange(location: index, length: 1), with: nil, name: name)
        previous = view.string
        view.window?.makeFirstResponder(view)
    }

    private func focusText(after index: Int) {
        guard let view else { return }
        view.window?.makeFirstResponder(view)
        view.setSelectedRange(NSRange(location: min(index + 1, (view.string as NSString).length), length: 0))
    }

    private func openEquation(at index: Int) -> Bool {
        guard let view, let inline = EaselInlineText.inline(at: index, in: view.attributedString()), inline.kind == .equation,
              let host, let anchor = rect(of: index) else { return false }
        dismiss()
        let source = inline.tex ?? ""
        let editor = NoteEquationEditorView(source: source)
        editor.frame.size = editor.fittingSize
        editor.onChange = { [weak self] text in self?.previewEquation(text, at: index) }
        editor.onCommit = { [weak self] in self?.finishEquation(commit: true); self?.dismiss(); self?.focusText(after: index) }
        editor.onCancel = { [weak self] in self?.finishEquation(commit: false); self?.dismiss(); self?.focusText(after: index) }
        let panel = NoteFloatingPanel(content: editor)
        panel.onDismiss = { [weak self, weak panel] in
            guard let self, self.floating === panel else { return }
            self.finishEquation(commit: true)
            self.mode = nil; self.floating = nil
        }
        equation = (editor, source)
        floating = panel
        mode = .equation(index)
        watchPointer()
        panel.present(in: host, anchor: anchor, edge: .below, animated: true)
        view.window?.makeFirstResponder(editor.textView)
        editor.textView.setSelectedRange(NSRange(location: (editor.textView.string as NSString).length, length: 0))
        return true
    }

    private func previewEquation(_ text: String, at index: Int) {
        guard let view, EaselInlineText.inline(at: index, in: view.attributedString())?.kind == .equation else { return }
        view.previewInline(.equation(String(text.prefix(4_000))), at: index)
    }

    private func finishEquation(commit: Bool) {
        guard case .equation(let index)? = mode, let view, let equation else { return }
        self.equation = nil
        let text = String(equation.editor.textView.string.prefix(4_000))
        view.previewInline(.equation(equation.original), at: index)
        guard commit, text != equation.original else { return }
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, equation.original.isEmpty {
            _ = view.replace(NSRange(location: index, length: 1), with: nil, name: "Inline Equation")
        } else {
            _ = view.replace(NSRange(location: index, length: 1), with: .equation(text), name: "Edit Equation")
        }
        previous = view.string
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

    private func rect(of index: Int) -> NSRect? {
        guard let view, let host, let window = view.window, index < (view.string as NSString).length else { return nil }
        let screen = view.firstRect(forCharacterRange: NSRange(location: index, length: 1), actualRange: nil)
        guard screen.origin.x.isFinite, screen.origin.y.isFinite, screen.height > 0 else { return nil }
        return host.convert(window.convertFromScreen(screen), from: nil)
    }

    private func isCode(at location: Int) -> Bool {
        guard let storage = view?.textStorage, location >= 0, location < storage.length else { return false }
        return EaselTextAppearance.isInlineCode(storage.attributes(at: location, effectiveRange: nil))
    }

    private func watchPointer() {
        guard pointerMonitor == nil else { return }
        pointerMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            MainActor.assumeIsolated { self?.pointerWentDown(event) }
            return event
        }
    }

    private func stopWatchingPointer() {
        if let pointerMonitor { NSEvent.removeMonitor(pointerMonitor) }
        pointerMonitor = nil
    }

    private func pointerWentDown(_ event: NSEvent) {
        let panels = [presenter.presentedPanel, floating].compactMap { $0 }
        guard !panels.contains(where: { $0.window === event.window && $0.bounds.contains($0.convert(event.locationInWindow, from: nil)) }) else { return }
        if case .mention? = mode, let view, event.window === view.window, view.bounds.contains(view.convert(event.locationInWindow, from: nil)) {
            dismiss()
            return
        }
        dismiss()
    }
}
