import AppKit
import Combine

@MainActor
final class NoteSlashMenuController {
    unowned let editor: NotePageEditor

    private enum Mode: Equatable {
        case blocks(NoteCatalogContext)
        case turnInto([NoteBlockID])
        case mention(NoteMentionMenu.Scope)
        case emoji
        case emojiPicker
        case date
    }

    private struct TextKey: Equatable {
        var block: NoteBlockID
        var field: NoteTextField
    }

    private struct Anchor: Equatable {
        var block: NoteBlockID
        var field: NoteTextField
        var token: NoteQueryToken
        var start: Int { token.start }
        var key: TextKey { TextKey(block: block, field: field) }
        var position: NotePosition { NotePosition(block, start, field: field) }
    }

    static let blockMenuWidth: CGFloat = 324
    static let mentionMenuWidth: CGFloat = 300
    static let turnIntoMenuWidth: CGFloat = 248

    private var mode: Mode? {
        didSet { if mode == nil { stopWatchingPointer() } else { watchPointer() } }
    }
    private var anchor: Anchor?
    private var tracker = NoteQueryTracker.slash
    private var currentQuery: String?
    private var results: [NoteCatalogItem] = []
    private var mentionChoices: [String: NoteMentionMenu.Choice] = [:]
    private let list = NoteMenuList()
    private lazy var listPanel = makePanel(list)
    private var emojiList: NoteEmojiSuggestionList?
    private var emojiPanel: NoteFloatingPanel?
    private var pickerPanel: NoteFloatingPanel?
    private var datePicker: NoteDatePickerView?
    private var datePanel: NoteFloatingPanel?
    private var datePosition: NotePosition?
    private var preview: NoteBlockPreviewCard?
    private var ghost: NoteMenuGhostView?
    private var previousText: (key: TextKey, text: String)?
    private var latestText: (key: TextKey, text: String)?
    private var subscription: AnyCancellable?
    private var fileSubscription: AnyCancellable?
    private var pointerMonitor: Any?
    private var reminderTask: Task<Void, Never>?
    private var reminderDocument: URL?
    private let openedAt = Date()
    private var isTornDown = false

    init(editor: NotePageEditor) {
        self.editor = editor
        list.maximumHeight = 372
        list.onActivate = { [weak self] item in self?.activate(item) }
        list.onCancel = { [weak self] in self?.dismiss() }
        list.onHighlight = { [weak self] item in self?.highlightDidChange(item) }
        subscription = editor.session.changes.sink { [weak self] change in self?.sessionDidChange(change) }
        reminderDocument = editor.environment.documentURL
        fileSubscription = NoteFileSession.openSessions.first { $0.page === editor.session }?.urlChanges
            .sink { [weak self] url in self?.documentDidMove(to: url) }
        scheduleReminderSync(after: 1)
    }

    var isOpen: Bool { mode != nil }

    private var page: NotePage { editor.session.page }

    private var isEnabled: Bool { !editor.environment.isPlainText && !editor.isReadOnly }

    func open(_ trigger: NoteSlashTrigger) {
        guard isEnabled else { return }
        switch trigger {
        case .slash(let position):
            let key = TextKey(block: position.block, field: position.field)
            guard allowsBlocks(key) else { return }
            openBlocks(makeAnchor(key, start: position.offset, trigger: "/"), context: context(for: position.block, plus: false), origin: .keyboard)
        case .plus(let id):
            openPlus(id)
        case .turnInto(let ids):
            openTurnInto(ids)
        }
    }

    func openDatePicker(at position: NotePosition) {
        guard isEnabled, let mention = dateMention(at: position) else { return }
        dismiss(animated: false)
        let picker = NoteDatePickerView(mention: mention)
        picker.onChange = { [weak self] value in self?.updateDate(value) }
        picker.onRemove = { [weak self] in self?.removeDate() }
        let panel = makePanel(picker)
        datePicker = picker
        datePanel = panel
        datePosition = position
        mode = .date
        guard let rect = overlayRect(TextKey(block: position.block, field: position.field), from: position.offset, to: position.offset + 1) else {
            dismiss(animated: false)
            return
        }
        panel.present(in: editor.canvas.overlayView, anchor: rect, edge: .below, animated: true)
    }

    func textDidChange(in host: NoteTextHost) {
        guard isEnabled, !host.textView.hasMarkedText() else { return }
        let key = TextKey(block: host.blockID, field: host.field)
        if let mode {
            switch mode {
            case .blocks, .mention:
                if anchor?.key == key { refresh() } else { dismiss() }
            case .emoji:
                if anchor?.key == key { refreshEmoji() } else { dismiss() }
            case .date, .turnInto:
                dismiss()
            case .emojiPicker:
                break
            }
            return
        }
        guard let text = page.block(key.block)?.text(in: key.field), let caret = caret(in: key),
              let old = previousText?.key == key ? previousText?.text : nil else { return }
        let new = text.string
        guard let typed = NoteTriggerRule.insertion(from: old, to: new, caret: caret) else { return }
        if typed.text == ":", let done = NoteTriggerRule.completedShortcode(in: new, caret: caret), completeShortcode(done, in: key) { return }
        guard allowsInline(key) else { return }
        if let found = NoteTriggerRule.trigger(from: old, to: new, caret: caret), !text.marks(at: found.start).code {
            switch found.trigger {
            case .slash:
                guard allowsBlocks(key) else { return }
                openBlocks(makeAnchor(key, start: found.start, trigger: "/"), context: context(for: key.block, plus: false), origin: .keyboard)
            case .mention:
                openMention(makeAnchor(key, start: found.start, trigger: "@"), scope: .everything)
            case .noteLink:
                openMention(makeAnchor(key, start: found.start, trigger: "[["), scope: .notes)
            }
            return
        }
        if typed.text.count == 1, let emoji = NoteTriggerRule.emojiQuery(in: new, caret: caret), !text.marks(at: emoji.start).code {
            openEmoji(makeAnchor(key, start: emoji.start, trigger: ":"), query: emoji.query)
        }
    }

    func handleKey(_ event: NSEvent) -> Bool {
        guard let mode, event.type == .keyDown else { return false }
        if let view = editor.canvas.window?.firstResponder as? NSTextView, view.hasMarkedText() { return false }
        let flags = event.modifierFlags.intersection([.command, .control, .option, .shift])
        switch mode {
        case .emoji:
            return handleEmojiKey(event, flags: flags)
        case .date:
            return handleDateKey(event, flags: flags)
        case .emojiPicker:
            guard event.keyCode == 53 else { return false }
            closeEmojiPicker()
            return true
        case .blocks, .mention, .turnInto:
            return handleListKey(event, flags: flags, mode: mode)
        }
    }

    func handleTextCommand(_ selector: Selector) -> Bool {
        guard let mode else { return false }
        switch mode {
        case .emoji:
            if selector == #selector(NSResponder.cancelOperation(_:)) { dismiss(); return true }
            return emojiList?.handle(selector) ?? false
        case .date:
            switch selector {
            case #selector(NSResponder.cancelOperation(_:)), #selector(NSResponder.insertNewline(_:)): dismiss(); return true
            case #selector(NSResponder.moveLeft(_:)): return datePicker?.move(byDays: -1) ?? false
            case #selector(NSResponder.moveRight(_:)): return datePicker?.move(byDays: 1) ?? false
            case #selector(NSResponder.moveUp(_:)): return datePicker?.move(byDays: -7) ?? false
            case #selector(NSResponder.moveDown(_:)): return datePicker?.move(byDays: 7) ?? false
            default: return false
            }
        case .emojiPicker:
            return false
        case .blocks, .mention, .turnInto:
            switch selector {
            case #selector(NSResponder.moveUp(_:)), #selector(NSResponder.insertBacktab(_:)): return list.moveHighlight(by: -1)
            case #selector(NSResponder.moveDown(_:)): return list.moveHighlight(by: 1)
            case #selector(NSResponder.insertTab(_:)): return list.activateHighlighted() || list.moveHighlight(by: 1)
            case #selector(NSResponder.insertNewline(_:)), #selector(NSResponder.insertLineBreak(_:)):
                if list.activateHighlighted() { return true }
                dismiss()
                return false
            case #selector(NSResponder.cancelOperation(_:)):
                dismiss()
                return true
            default:
                return false
            }
        }
    }

    func dismiss(animated: Bool = true) {
        mode = nil
        anchor = nil
        results = []
        mentionChoices = [:]
        currentQuery = nil
        datePosition = nil
        list.filterText = ""
        ghost?.removeFromSuperview()
        ghost = nil
        hidePreview(animated: animated)
        for panel in [listPanel, emojiPanel, pickerPanel, datePanel] {
            guard let panel, panel.isPresented else { continue }
            panel.dismiss(animated: animated)
        }
        datePicker = nil
    }

    private func openBlocks(_ anchor: Anchor, context: NoteCatalogContext, origin: NoteMenuList.Origin) {
        closePanels(except: listPanel)
        self.anchor = anchor
        mode = .blocks(context)
        tracker = .slash
        currentQuery = nil
        results = []
        list.filtersOnTyping = false
        list.filterText = ""
        list.fixedWidth = Self.blockMenuWidth
        list.noResultsTitle = "No blocks by that name. Keep typing?"
        list.setAccessibilityLabel("Insert a block")
        list.prepare(origin: origin)
        refresh()
    }

    private func openPlus(_ id: NoteBlockID) {
        guard let block = page.block(id) else { return }
        var target = id
        if block.kind == .paragraph && block.text.isEmpty && block.children.isEmpty {
            if editor.session.selection.caret != NotePosition(id, 0) {
                editor.session.setSelection(.caret(NotePosition(id, 0)))
                editor.focus(NotePosition(id, 0))
            }
        } else {
            let fresh = NoteBlock.paragraph()
            let above = NSEvent.modifierFlags.contains(.option)
            let position: NoteInsertion = above ? .before(id) : (block.acceptsChildren && block.showsChildren && !block.children.isEmpty ? .firstChild(of: id) : .after(id))
            editor.session.insertBlocks([fresh], position, select: .caret(NotePosition(fresh.id, 0)))
            target = fresh.id
            editor.canvas.layoutSubtreeIfNeeded()
            editor.focus(NotePosition(target, 0))
        }
        openBlocks(makeAnchor(TextKey(block: target, field: .body), start: 0, trigger: ""), context: context(for: target, plus: true), origin: .pointer)
    }

    private func openTurnInto(_ ids: [NoteBlockID]) {
        let targets = page.ordered(ids).filter { page.block($0) != nil }
        guard let first = targets.first, let frame = editor.canvas.frame(of: first) else { return }
        closePanels(except: listPanel)
        anchor = nil
        mode = .turnInto(targets)
        let blocks = targets.compactMap { page.block($0) }
        let current = NoteCatalogBlock.turnIntoTargets.first { template in blocks.allSatisfy(template.describes) }
        let keyboard = NSApp.currentEvent?.type == .keyDown
        list.filtersOnTyping = true
        list.filterText = ""
        list.fixedWidth = Self.turnIntoMenuWidth
        list.rowStyle = .compact
        list.noResultsTitle = "No block by that name."
        list.setAccessibilityLabel("Turn into")
        list.prepare(origin: keyboard ? .keyboard : .pointer)
        list.items = NoteBlockCatalog.turnIntoMenuItems.map { item in
            var entry = self.row(for: item, filtering: true)
            entry.section = "Turn into"
            entry.isChecked = item.block == current
            return entry
        }
        if keyboard, let current, let checked = NoteBlockCatalog.turnIntoMenuItems.first(where: { $0.block == current }) {
            list.highlight(id: checked.id, animated: false)
        }
        let rect = editor.canvas.overlayView.convert(NSRect(x: frame.minX, y: frame.minY, width: min(frame.width, 240), height: min(frame.height, 30)),
                                                     from: editor.canvas)
        listPanel.present(in: editor.canvas.overlayView, anchor: rect, edge: .below, animated: true)
    }

    private func openMention(_ anchor: Anchor, scope: NoteMentionMenu.Scope) {
        closePanels(except: listPanel)
        self.anchor = anchor
        mode = .mention(scope)
        tracker = .mention
        currentQuery = nil
        list.filtersOnTyping = false
        list.filterText = ""
        list.fixedWidth = Self.mentionMenuWidth
        list.setAccessibilityLabel(scope == .dates ? "Insert a date" : "Mention a note or date")
        list.prepare(origin: .keyboard)
        refresh()
    }

    private func openEmoji(_ anchor: Anchor, query: String) {
        let suggestions = emojiList ?? makeEmojiList()
        suggestions.query = query
        guard suggestions.hasResults else { return }
        closePanels(except: emojiPanel)
        self.anchor = anchor
        mode = .emoji
        currentQuery = query
        guard let panel = emojiPanel, let rect = overlayRect(anchor.key, from: anchor.start) else { dismiss(animated: false); return }
        panel.contentSizeDidChange(animated: false)
        panel.present(in: editor.canvas.overlayView, anchor: rect.offsetBy(dx: -NoteTheme.menuInset, dy: 0), edge: .below, animated: true)
    }

    private func openEmojiPicker(at position: NotePosition) {
        let key = TextKey(block: position.block, field: position.field)
        guard let rect = overlayRect(key, from: position.offset) else { return }
        closePanels(except: nil)
        let picker = NoteEmojiPicker(showsRandom: true)
        picker.onPick = { [weak self] character in self?.insertPickedEmoji(character) }
        picker.onCancel = { [weak self] in self?.closeEmojiPicker() }
        let panel = makePanel(picker)
        pickerPanel = panel
        anchor = makeAnchor(key, start: position.offset, trigger: "")
        mode = .emojiPicker
        panel.present(in: editor.canvas.overlayView, anchor: rect, edge: .below, animated: true)
        picker.focusSearch()
    }

    @discardableResult
    private func refresh() -> Bool {
        guard let mode else { return false }
        guard let query = liveMatch()?.query else { dismiss(); return false }
        switch mode {
        case .blocks(let context):
            let match = context.mode == .plus && query.hasPrefix("/") ? String(query.dropFirst()) : query
            let found = NoteBlockCatalog.results(for: match, in: context)
            guard tracker.update(query: match, hasResults: !found.isEmpty) == .open else { dismiss(); return false }
            guard query != currentQuery || !listPanel.isPresented else { return true }
            currentQuery = query
            results = found
            show(found.map { row(for: $0, filtering: !match.isEmpty) }, detailed: match.isEmpty, highlightFirst: !match.isEmpty)
        case .mention(let scope):
            let parser = NoteDateParser()
            let contents = NoteMentionMenu.contents(for: query, scope: scope, environment: editor.environment, parser: parser)
            let alive = contents.hasResults || NoteMentionMenu.isStillTyping(query, scope: scope, parser: parser)
            guard tracker.update(query: query, hasResults: alive) == .open else { dismiss(); return false }
            guard query != currentQuery || !listPanel.isPresented else { return true }
            currentQuery = query
            mentionChoices = contents.choices
            list.noResultsTitle = NoteMentionMenu.noResultsTitle(for: scope)
            show(contents.items, detailed: false, highlightFirst: true)
        default:
            return false
        }
        return true
    }

    private func show(_ items: [NoteMenuList.Item], detailed: Bool, highlightFirst: Bool) {
        crossfade {
            list.rowStyle = detailed ? .detailed : .compact
            list.items = items
            if highlightFirst, list.highlightedIndex == nil, let first = items.firstIndex(where: \.isEnabled) {
                list.highlightedIndex = first
            }
        }
        if !detailed { hidePreview(animated: true) }
        guard !listPanel.isPresented, let rect = menuAnchor() else { return }
        listPanel.present(in: editor.canvas.overlayView, anchor: rect, edge: .below, animated: true)
    }

    private func crossfade(_ update: () -> Void) {
        guard listPanel.isPresented, !NoteAnimation.reduceMotion, let clip = list.superview, let listLayer = list.layer,
              list.bounds.width > 1, list.bounds.height > 1, let rep = list.bitmapImageRepForCachingDisplay(in: list.bounds) else {
            update()
            return
        }
        list.cacheDisplay(in: list.bounds, to: rep)
        let image = NSImage(size: list.bounds.size)
        image.addRepresentation(rep)
        ghost?.removeFromSuperview()
        let fading = NoteMenuGhostView(frame: list.frame)
        fading.image = image
        clip.addSubview(fading, positioned: .above, relativeTo: list)
        ghost = fading
        update()
        NoteAnimation.withoutAnimation { listLayer.opacity = 0 }
        NoteAnimation.spring(listLayer, "opacity", to: Float(1), spring: .highlight, key: NoteAnimation.keyPrefix + "slash.in")
        guard let ghostLayer = fading.layer else { fading.removeFromSuperview(); return }
        NoteAnimation.spring(ghostLayer, "opacity", to: Float(0), spring: .highlight, key: NoteAnimation.keyPrefix + "slash.out") { [weak self, weak fading] in
            fading?.removeFromSuperview()
            if self?.ghost === fading { self?.ghost = nil }
        }
    }

    private func refreshEmoji() {
        guard let anchor, let text = page.block(anchor.block)?.text(in: anchor.field), let caret = caret(in: anchor.key) else { dismiss(); return }
        if let done = NoteTriggerRule.completedShortcode(in: text.string, caret: caret), done.range.lowerBound == anchor.start {
            dismiss()
            _ = completeShortcode(done, in: anchor.key)
            return
        }
        guard let match = liveMatch(), NoteTriggerRule.isEmojiQuery(match.query) else { dismiss(); return }
        currentQuery = match.query
        emojiList?.query = match.query
        if emojiList?.hasResults != true { dismiss() }
    }

    private func liveMatch() -> NoteQueryMatch? {
        guard var anchor, let text = page.block(anchor.block)?.text(in: anchor.field), let caret = caret(in: anchor.key) else { return nil }
        let match = anchor.token.resolve(in: text.string, caret: caret)
        self.anchor = anchor
        return match
    }

    private func makeAnchor(_ key: TextKey, start: Int, trigger: String) -> Anchor {
        let text = page.block(key.block)?.text(in: key.field)?.string ?? ""
        let caret = caret(in: key) ?? start + (trigger as NSString).length
        return Anchor(block: key.block, field: key.field, token: NoteQueryToken(start: start, trigger: trigger, text: text, caret: caret))
    }

    private func activate(_ item: NoteMenuList.Item) {
        guard let mode else { return }
        switch mode {
        case .blocks:
            if let chosen = results.first(where: { $0.id == item.id }) { choose(chosen) }
        case .turnInto(let ids):
            guard let block = NoteBlockCatalog.turnIntoMenuItems.first(where: { $0.id == item.id })?.block else { return }
            dismiss()
            guard !editor.isReadOnly else { return }
            editor.session.turnInto(ids, kind: block.kind, configure: block.configure)
        case .mention(let scope):
            if let choice = mentionChoices[item.id] { chooseMention(choice, scope: scope) }
        default:
            break
        }
    }

    private func choose(_ item: NoteCatalogItem) {
        guard let anchor, let range = liveMatch()?.range else { dismiss(); return }
        let position = NotePosition(anchor.block, range.lowerBound, field: anchor.field)
        dismiss()
        if item.effect == .block(.newNote) {
            createNoteBlock(at: position, removing: range)
            return
        }
        guard let outcome = NoteCatalogApplier.apply(item.effect, to: page, at: position, removing: range) else {
            NSSound.beep()
            return
        }
        commit(outcome)
    }

    private func commit(_ outcome: NoteCatalogOutcome) {
        editor.session.edit(outcome.name, selection: outcome.selection) { page in page = outcome.page }
        editor.canvas.layoutSubtreeIfNeeded()
        if let id = outcome.activate {
            editor.canvas.scrollBlockToVisible(id)
            editor.canvas.layoutSubtreeIfNeeded()
            _ = editor.canvas.blockView(for: id)?.focus(at: outcome.selection.caret?.offset, field: .body)
        } else if let caret = outcome.selection.caret {
            editor.focus(caret)
        }
        guard let followUp = outcome.followUp else { return }
        Task { @MainActor [weak self] in self?.perform(followUp) }
    }

    private func perform(_ followUp: NoteCatalogOutcome.FollowUp) {
        guard isEnabled else { return }
        switch followUp {
        case .mention(let position, let datesOnly):
            openMention(makeAnchor(TextKey(block: position.block, field: position.field), start: position.offset, trigger: "@"),
                        scope: datesOnly ? .dates : .everything)
        case .emoji(let position):
            openEmojiPicker(at: position)
        case .pickNote(let position):
            openMention(makeAnchor(TextKey(block: position.block, field: position.field), start: position.offset, trigger: ""), scope: .noteBlock)
        case .editEquation(let position):
            editor.canvas.layoutSubtreeIfNeeded()
            if editor.canvas.textHost(for: position)?.textView.editEquation(at: position.offset) == true { return }
            let range = position.offset..<(position.offset + 1)
            editor.session.setSelection(.text(anchor: position, head: NotePosition(position.block, range.upperBound, field: position.field)))
            editor.canvas.textHost(for: position)?.textView.selectedOffsets = range
        }
    }

    private func createNoteBlock(at position: NotePosition, removing range: Range<Int>) {
        do {
            let url = try editor.environment.createNote(titled: "Untitled")
            guard let outcome = NoteCatalogApplier.place(pageLink(to: url), template: nil, into: page, at: position, removing: range, name: "New Note") else { return }
            commit(outcome)
            editor.open(url)
        } catch {
            editor.onError?(error)
        }
    }

    private func pageLink(to url: URL) -> NoteBlock {
        var props = NoteBlockProps()
        props.target = editor.environment.linkTarget(for: url)
        return NoteBlock(.pageLink, text: NoteText(url.deletingPathExtension().lastPathComponent), props: props)
    }

    private func chooseMention(_ choice: NoteMentionMenu.Choice, scope: NoteMentionMenu.Scope) {
        guard let anchor, let range = liveMatch()?.range else { dismiss(); return }
        dismiss()
        let note: URL
        let title: String
        switch choice {
        case .date(let mention):
            replace(range, in: anchor.key, with: .atom(.date(mention)), name: mention.remind ? "Reminder" : "Date")
            if mention.remind {
                NoteReminderCenter.shared.requestAuthorizationIfNeeded()
                scheduleReminderSync(after: 0.2)
            }
            return
        case .note(let reference):
            note = reference.url
            title = reference.title
        case .createNote(let name):
            do { note = try editor.environment.createNote(titled: name) } catch { editor.onError?(error); return }
            title = note.deletingPathExtension().lastPathComponent
        }
        if scope == .noteBlock {
            var link = pageLink(to: note)
            link.text = NoteText(title)
            let position = NotePosition(anchor.block, range.lowerBound, field: anchor.field)
            guard let outcome = NoteCatalogApplier.place(link, template: nil, into: page, at: position, removing: range, name: "Link to Note") else { return }
            commit(outcome)
            return
        }
        replace(range, in: anchor.key, with: .atom(.page(target: editor.environment.linkTarget(for: note), title: title)), name: "Mention")
    }

    private func replace(_ range: Range<Int>, in key: TextKey, with inserted: NoteText, name: String) {
        guard let text = page.block(key.block)?.text(in: key.field) else { return }
        var marks = text.typingMarks(at: range.lowerBound)
        marks.link = nil
        var value = NoteText()
        for run in inserted.runs() {
            var runMarks = marks
            runMarks.atom = run.marks.atom
            value.append(NoteText((inserted.string as NSString).substring(with: NSRange(location: run.range.lowerBound, length: run.range.count)), marks: runMarks))
        }
        let caret = NotePosition(key.block, range.lowerBound + value.length, field: key.field)
        editor.session.edit(name, kind: .text, affected: [key.block], selection: .caret(caret)) { page in
            page.update(key.block) { block in
                guard var current = block.text(in: key.field) else { return }
                current.replace(range, with: value)
                block.setText(current, in: key.field)
            }
        }
        editor.focus(caret)
    }

    private func completeShortcode(_ done: (range: Range<Int>, shortcode: String), in key: TextKey) -> Bool {
        guard allowsInline(key) else { return false }
        let catalog = NoteEmojiCatalog.shared
        guard let emoji = catalog.emoji(forShortcode: done.shortcode) else { return false }
        let character = catalog.character(for: emoji)
        catalog.recordUse(character)
        replace(done.range, in: key, with: NoteText(character), name: "Emoji")
        return true
    }

    private func insertEmoji(_ character: String) {
        guard let anchor, let range = liveMatch()?.range else { dismiss(); return }
        dismiss()
        replace(range, in: anchor.key, with: NoteText(character), name: "Emoji")
    }

    private func insertPickedEmoji(_ character: String) {
        guard let anchor else { dismiss(); return }
        let key = anchor.key
        let offset = min(anchor.start, page.block(key.block)?.text(in: key.field)?.length ?? 0)
        dismiss()
        replace(offset..<offset, in: key, with: NoteText(character), name: "Emoji")
    }

    private func closeEmojiPicker() {
        let position = anchor?.position
        dismiss()
        if let position { editor.focus(position) }
    }

    private func makeEmojiList() -> NoteEmojiSuggestionList {
        let suggestions = NoteEmojiSuggestionList(limit: 8)
        suggestions.onPick = { [weak self] character in self?.insertEmoji(character) }
        suggestions.onCancel = { [weak self] in self?.dismiss() }
        let panel = makePanel(suggestions)
        suggestions.onResultsChange = { [weak panel] _ in panel?.contentSizeDidChange(animated: true) }
        emojiList = suggestions
        emojiPanel = panel
        return suggestions
    }

    private func dateMention(at position: NotePosition) -> NoteDateMention? {
        guard let text = page.text(of: position), position.offset >= 0, position.offset < text.length,
              case .date(let mention)? = text.marks(at: position.offset).atom else { return nil }
        return mention
    }

    private func updateDate(_ value: NoteDateMention) {
        guard !editor.isReadOnly, let position = datePosition, dateMention(at: position) != nil, let text = page.text(of: position) else {
            dismiss()
            return
        }
        var replaced = text
        replaced.replace(position.offset..<(position.offset + 1), with: .atom(.date(value), marks: text.marks(at: position.offset).withoutAtom))
        editor.session.edit(value.remind ? "Reminder" : "Change Date", kind: .text, affected: [position.block], selection: editor.session.selection) { page in
            page.update(position.block) { $0.setText(replaced, in: position.field) }
        }
        if value.remind { NoteReminderCenter.shared.requestAuthorizationIfNeeded() }
        scheduleReminderSync(after: 0.3)
        editor.canvas.layoutSubtreeIfNeeded()
        if let panel = datePanel, panel.isPresented,
           let rect = overlayRect(TextKey(block: position.block, field: position.field), from: position.offset, to: position.offset + 1) {
            panel.reposition(anchor: rect, edge: panel.resolvedEdge, animated: true)
        }
    }

    private func removeDate() {
        guard let position = datePosition, dateMention(at: position) != nil, let text = page.text(of: position) else { dismiss(); return }
        dismiss()
        var replaced = text
        replaced.delete(position.offset..<(position.offset + 1))
        editor.session.edit("Remove Date", kind: .text, affected: [position.block], selection: .caret(position)) { page in
            page.update(position.block) { $0.setText(replaced, in: position.field) }
        }
        editor.focus(position)
        scheduleReminderSync(after: 0.3)
    }

    private func handleListKey(_ event: NSEvent, flags: NSEvent.ModifierFlags, mode: Mode) -> Bool {
        switch event.keyCode {
        case 125 where flags.isEmpty, 45 where flags == .control:
            list.moveHighlight(by: 1)
            return true
        case 126 where flags.isEmpty, 35 where flags == .control, 48 where flags == .shift:
            list.moveHighlight(by: -1)
            return true
        case 36 where flags.isEmpty, 76 where flags.isEmpty:
            if list.activateHighlighted() { return true }
            if case .turnInto = mode { return true }
            dismiss()
            return false
        case 48 where flags.isEmpty:
            if list.activateHighlighted() { return true }
            list.moveHighlight(by: 1)
            return true
        case 53:
            dismiss()
            return true
        case 115 where flags.isEmpty, 119 where flags.isEmpty, 116 where flags.isEmpty, 121 where flags.isEmpty:
            return list.handleKeyDown(event)
        default:
            guard case .turnInto = mode else { return false }
            if flags.contains(.command) {
                dismiss(animated: false)
                return false
            }
            _ = list.handleKeyDown(event)
            return true
        }
    }

    private func handleEmojiKey(_ event: NSEvent, flags: NSEvent.ModifierFlags) -> Bool {
        guard let emojiList else { return false }
        switch event.keyCode {
        case 125 where flags.isEmpty, 45 where flags == .control: return emojiList.moveSelection(by: 1)
        case 126 where flags.isEmpty, 35 where flags == .control: return emojiList.moveSelection(by: -1)
        case 36 where flags.isEmpty, 76 where flags.isEmpty, 48 where flags.isEmpty: return emojiList.pickSelected()
        case 53: dismiss(); return true
        default: return false
        }
    }

    private func handleDateKey(_ event: NSEvent, flags: NSEvent.ModifierFlags) -> Bool {
        switch event.keyCode {
        case 53, 36, 76:
            let position = datePosition
            dismiss()
            if let position { editor.focus(NotePosition(position.block, position.offset + 1, field: position.field)) }
            return true
        default:
            return datePicker?.handleKeyDown(event) ?? false
        }
    }

    private func highlightDidChange(_ item: NoteMenuList.Item?) {
        guard case .blocks = mode, list.rowStyle == .detailed, let item,
              let block = results.first(where: { $0.id == item.id })?.block else {
            hidePreview(animated: true)
            return
        }
        showPreview(for: block, item: item)
    }

    private func showPreview(for block: NoteCatalogBlock, item: NoteMenuList.Item) {
        guard listPanel.isPresented, let overlay = listPanel.superview else { return }
        let card = preview ?? NoteBlockPreviewCard()
        preview = card
        card.show(block, title: item.title, summary: item.subtitle ?? "")
        let size = card.fittingSize
        let gap = NoteTheme.menuGap
        let panelFrame = NoteFloatingPanel.topDown(listPanel.frame, in: overlay)
        let visible = NoteFloatingPanel.topDown(overlay.visibleRect, in: overlay)
        var x = panelFrame.maxX + gap
        if x + size.width > visible.maxX - NoteTheme.menuScreenMargin { x = panelFrame.minX - gap - size.width }
        guard x >= visible.minX + NoteTheme.menuScreenMargin else { hidePreview(animated: false); return }
        let rowY = list.highlightedIndex.flatMap { _ in highlightedRowTop() } ?? 0
        var y = panelFrame.minY + rowY - 8
        y = min(max(y, visible.minY + NoteTheme.menuScreenMargin), visible.maxY - NoteTheme.menuScreenMargin - size.height)
        let target = NoteFloatingPanel.topDown(NSRect(x: x, y: y, width: size.width, height: size.height), in: overlay).integral
        if card.superview !== overlay {
            card.frame = target
            overlay.addSubview(card)
            NoteAnimation.presentHUD(card, about: NSPoint(x: x > panelFrame.maxX ? 0 : size.width, y: size.height / 2))
        } else if card.frame != target {
            NoteAnimation.slide(card, to: target, spring: .glide)
        }
    }

    private func highlightedRowTop() -> CGFloat? {
        guard let index = list.highlightedIndex, list.items.indices.contains(index) else { return nil }
        let header = NoteTheme.menuHeaderHeight, separator = NoteTheme.menuSeparatorSlot
        var y = NoteTheme.menuInset
        var section: String?
        for position in 0...index {
            let item = list.items[position]
            if let next = item.section, next != section {
                if position > 0 { y += separator }
                y += header
                section = next
            }
            if position < index { y += list.rowHeight }
        }
        let scroll = list.enclosingScrollViewOffset
        return max(0, y - scroll)
    }

    private func hidePreview(animated: Bool) {
        guard let card = preview, card.superview != nil else { return }
        guard animated, !NoteAnimation.reduceMotion else { card.removeFromSuperview(); return }
        NoteAnimation.dismissHUD(card, about: NSPoint(x: 0, y: card.bounds.midY)) { [weak card] in
            card?.removeFromSuperview()
            card?.layer?.opacity = 1
        }
    }

    private func sessionDidChange(_ change: NotePageChange) {
        recordText()
        if change.kind != .selection { scheduleReminderSync(after: 0.8) }
        guard let mode else { return }
        switch mode {
        case .turnInto(let ids):
            if change.kind != .selection, ids.contains(where: { page.block($0) == nil }) { dismiss(animated: false) }
        case .date:
            guard let position = datePosition, dateMention(at: position) != nil else { dismiss(animated: false); return }
            switch editor.session.selection {
            case .text(_, let head) where head.block != position.block || head.field != position.field: dismiss()
            case .blocks, .cells: dismiss()
            default: break
            }
        case .emojiPicker:
            if let anchor, page.block(anchor.block) == nil { dismiss(animated: false) }
            else if change.kind == .selection { dismiss() }
        case .blocks, .mention, .emoji:
            guard let query = liveMatch()?.query else {
                dismiss(animated: change.kind == .selection)
                return
            }
            if change.kind == .selection, query != currentQuery {
                if mode == .emoji { refreshEmoji() } else { refresh() }
            }
        }
    }

    private func recordText() {
        guard case .text(_, let head) = editor.session.selection, let text = page.text(of: head) else {
            previousText = latestText
            latestText = nil
            return
        }
        let key = TextKey(block: head.block, field: head.field)
        if let latestText, latestText.key == key, latestText.text == text.string { return }
        previousText = latestText
        latestText = (key, text.string)
    }

    func tearDown() {
        guard !isTornDown else { return }
        dismiss(animated: false)
        isTornDown = true
        subscription = nil
        fileSubscription = nil
        guard reminderTask != nil else { return }
        reminderTask?.cancel()
        reminderTask = nil
        syncReminders()
    }

    private func scheduleReminderSync(after delay: TimeInterval) {
        guard !isTornDown, !editor.environment.isPlainText else { return }
        reminderTask?.cancel()
        reminderTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled, let self, !self.isTornDown else { return }
            self.reminderTask = nil
            self.syncReminders()
        }
    }

    private func documentDidMove(to url: URL) {
        if let previous = reminderDocument, previous != url { NoteReminderCenter.shared.noteMoved(from: previous, to: url) }
        reminderDocument = url
        scheduleReminderSync(after: 0)
    }

    private func syncReminders() {
        guard !editor.environment.isPlainText else { return }
        let document = editor.environment.documentURL
        if let previous = reminderDocument, let document, previous != document { NoteReminderCenter.shared.noteMoved(from: previous, to: document) }
        reminderDocument = document ?? reminderDocument
        NoteReminderCenter.shared.reconcile(page: page, document: document, title: document?.deletingPathExtension().lastPathComponent ?? "",
                                            openedAt: openedAt)
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
        guard let mode else { return }
        let panels = [listPanel, emojiPanel, pickerPanel, datePanel].compactMap { $0 }.filter(\.isPresented)
        if panels.contains(where: { $0.window === event.window && $0.bounds.contains($0.convert(event.locationInWindow, from: nil)) }) { return }
        switch mode {
        case .blocks, .mention, .emoji:
            if let anchor, let view = editor.canvas.blockView(for: anchor.block)?.textHost(for: anchor.field)?.textView,
               view.window === event.window, let hit = hitView(for: event), hit === view || hit.isDescendant(of: view) { return }
        case .turnInto, .emojiPicker, .date:
            break
        }
        dismiss()
    }

    private func hitView(for event: NSEvent) -> NSView? {
        guard let content = event.window?.contentView else { return nil }
        return content.hitTest(content.superview?.convert(event.locationInWindow, from: nil) ?? event.locationInWindow)
    }

    private func caret(in key: TextKey) -> Int? {
        guard case .text(let anchor, let head) = editor.session.selection, anchor == head,
              head.block == key.block, head.field == key.field else { return nil }
        return head.offset
    }

    private func allowsInline(_ key: TextKey) -> Bool {
        guard let block = page.block(key.block), block.text(in: key.field) != nil else { return false }
        return key.field != .body || block.kind.hasRichText
    }

    private func allowsBlocks(_ key: TextKey) -> Bool {
        key.field == .body && page.block(key.block)?.kind.hasRichText == true
    }

    private func context(for block: NoteBlockID, plus: Bool) -> NoteCatalogContext {
        var context = plus ? NoteCatalogContext.plus : .slash
        context.allowsColumns = page.parent(of: block) == nil
        context.allowsNewNote = editor.environment.documentURL != nil
        return context
    }

    private func menuAnchor() -> NSRect? {
        guard let anchor, let rect = overlayRect(anchor.key, from: anchor.start) else { return nil }
        return rect.offsetBy(dx: -NoteTheme.menuInset - 4, dy: 0)
    }

    private func overlayRect(_ key: TextKey, from start: Int, to end: Int? = nil) -> NSRect? {
        guard let view = editor.canvas.blockView(for: key.block)?.textHost(for: key.field)?.textView else { return nil }
        var rect = view.caretRect(at: start)
        if let end {
            let last = view.caretRect(at: end)
            if abs(last.minY - rect.minY) < 1 { rect = rect.union(last) }
        }
        return editor.canvas.overlayView.convert(rect, from: view)
    }

    private func makePanel(_ content: NSView) -> NoteFloatingPanel {
        let panel = NoteFloatingPanel(content: content)
        panel.maximumHeight = 400
        return panel
    }

    private func closePanels(except keep: NoteFloatingPanel?) {
        ghost?.removeFromSuperview()
        ghost = nil
        hidePreview(animated: false)
        for panel in [listPanel, emojiPanel, pickerPanel, datePanel] {
            guard let panel, panel !== keep, panel.isPresented else { continue }
            panel.dismiss(animated: false)
        }
        if keep !== datePanel { datePicker = nil; datePosition = nil }
    }

    private func row(for item: NoteCatalogItem, filtering: Bool) -> NoteMenuList.Item {
        NoteSlashMenuRows.item(for: item, filtering: filtering)
    }
}

@MainActor
private final class NoteMenuGhostView: NSImageView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        imageScaling = .scaleNone
        imageAlignment = .alignTopLeft
        wantsLayer = true
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

private extension NoteMenuList {
    var enclosingScrollViewOffset: CGFloat {
        subviews.compactMap { $0 as? NSScrollView }.first?.contentView.bounds.origin.y ?? 0
    }
}

@MainActor
final class NoteBlockPreviewCard: NSView {
    static let width: CGFloat = 220
    private static let stageHeight: CGFloat = 116
    private var block: NoteCatalogBlock = .text
    private var title = ""
    private var summary = ""

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: Self.width, height: 180))
        wantsLayer = true
        layer?.cornerRadius = NoteTheme.menuRadius
        layer?.cornerCurve = .continuous
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowRadius = 7
        layer?.shadowOffset = CGSize(width: 0, height: -2)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        refreshChrome()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override var fittingSize: NSSize { NSSize(width: Self.width, height: ceil(Self.stageHeight + 16 + 10 + titleHeight + 2 + summaryHeight + 12)) }

    private var titleFont: NSFont { NoteTheme.nunitoExtraBold(13.5) }
    private var summaryFont: NSFont { NoteTheme.nunitoRegular(12) }
    private var titleHeight: CGFloat { ceil(titleFont.ascender - titleFont.descender) }
    private var summaryHeight: CGFloat {
        let text = NSAttributedString(string: summary, attributes: [.font: summaryFont])
        return ceil(text.boundingRect(with: NSSize(width: Self.width - 28, height: 60), options: [.usesLineFragmentOrigin]).height)
    }

    func show(_ block: NoteCatalogBlock, title: String, summary: String) {
        guard block != self.block || title != self.title || summary != self.summary else { return }
        self.block = block
        self.title = title
        self.summary = summary
        setAccessibilityLabel("Preview: \(title). \(summary)")
        setFrameSize(fittingSize)
        refreshChrome()
        needsDisplay = true
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshChrome()
        needsDisplay = true
    }

    private func refreshChrome() {
        guard let layer else { return }
        NoteAnimation.withoutAnimation {
            layer.backgroundColor = NoteTheme.resolved(NoteTheme.menuFill, in: self)
            layer.borderColor = NoteTheme.resolved(NoteTheme.menuHairline, in: self)
            layer.borderWidth = 1 / (window?.backingScaleFactor ?? 2)
            layer.shadowOpacity = NoteTheme.isDark(effectiveAppearance) ? 0.32 : 0.12
            layer.shadowPath = CGPath(roundedRect: bounds, cornerWidth: NoteTheme.menuRadius, cornerHeight: NoteTheme.menuRadius, transform: nil)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let stage = NSRect(x: 8, y: 8, width: bounds.width - 16, height: Self.stageHeight)
        NoteTheme.paper.setFill()
        NSBezierPath(roundedRect: stage, xRadius: 8, yRadius: 8).fill()
        NoteTheme.menuHairline.setStroke()
        let outline = NSBezierPath(roundedRect: stage.insetBy(dx: 0.25, dy: 0.25), xRadius: 8, yRadius: 8)
        outline.lineWidth = 0.5
        outline.stroke()
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: stage, xRadius: 8, yRadius: 8).addClip()
        drawSample(in: stage.insetBy(dx: 16, dy: 14))
        NSGraphicsContext.restoreGraphicsState()
        let titleTop = stage.maxY + 10
        NSAttributedString(string: title, attributes: [.font: titleFont, .foregroundColor: NoteTheme.menuInk])
            .draw(with: NSRect(x: 14, y: titleTop, width: bounds.width - 28, height: titleHeight), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
        NSAttributedString(string: summary, attributes: [.font: summaryFont, .foregroundColor: NoteTheme.menuSecondaryInk])
            .draw(with: NSRect(x: 14, y: titleTop + titleHeight + 2, width: bounds.width - 28, height: summaryHeight), options: [.usesLineFragmentOrigin])
    }

    private func bar(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, alpha: CGFloat = 1) {
        NoteTheme.tertiaryInk.withAlphaComponent(0.55 * alpha).setFill()
        NSBezierPath(roundedRect: NSRect(x: x, y: y, width: max(6, width), height: 6), xRadius: 3, yRadius: 3).fill()
    }

    private func text(_ string: String, _ font: NSFont, at point: NSPoint, color: NSColor? = nil) {
        NSAttributedString(string: string, attributes: [.font: font, .foregroundColor: color ?? NoteTheme.ink]).draw(at: point)
    }

    private func icon(_ name: String, in rect: NSRect, size: CGFloat, tint: NSColor? = nil) {
        NoteIconRenderer.draw(.symbol(name), in: rect, tint: tint ?? NoteTheme.secondaryInk, pointSize: size, weight: .semibold)
    }

    private func drawSample(in rect: NSRect) {
        let x = rect.minX, width = rect.width
        var y = rect.minY
        switch block {
        case .text:
            for fraction in [1, 0.94, 0.88, 0.55] as [CGFloat] { bar(x, y + 6, width * fraction); y += 18 }
        case .heading(let level), .toggleHeading(let level):
            let toggles: Bool
            if case .toggleHeading = block { toggles = true } else { toggles = false }
            let font = NoteTheme.nunitoExtraBold([20, 17, 15][min(max(level, 1), 3) - 1])
            let indent: CGFloat = toggles ? 18 : 0
            if toggles { triangle(at: NSPoint(x: x + 2, y: y + font.ascender * 0.55), open: true) }
            text("Heading \(level)", font, at: NSPoint(x: x + indent, y: y))
            y += ceil(font.ascender - font.descender) + 10
            for fraction in [0.9, 0.7] as [CGFloat] { bar(x + indent, y, (width - indent) * fraction); y += 16 }
        case .bulleted, .numbered, .todo:
            for row in 0..<3 {
                let mid = y + 9
                switch block {
                case .bulleted:
                    NoteTheme.ink.setFill()
                    NSBezierPath(ovalIn: NSRect(x: x + 3, y: mid - 2.5, width: 5, height: 5)).fill()
                case .numbered:
                    text("\(row + 1).", NoteTheme.nunitoBold(12.5), at: NSPoint(x: x, y: mid - 9))
                default:
                    let box = NSRect(x: x, y: mid - 7, width: 14, height: 14)
                    let path = NSBezierPath(roundedRect: box, xRadius: 4, yRadius: 4)
                    if row == 0 {
                        NoteTheme.todoCheckFill.setFill()
                        path.fill()
                        icon("checkmark", in: box, size: 9, tint: .white)
                    } else {
                        NoteTheme.secondaryInk.setStroke()
                        path.lineWidth = 1.3
                        path.stroke()
                    }
                }
                bar(x + 22, mid - 3, (width - 22) * [0.8, 0.62, 0.72][row], alpha: block == .todo && row == 0 ? 0.5 : 1)
                y += 26
            }
        case .toggle:
            triangle(at: NSPoint(x: x + 2, y: y + 9), open: true)
            bar(x + 18, y + 6, width * 0.6)
            bar(x + 18, y + 26, width * 0.7, alpha: 0.7)
            bar(x + 18, y + 44, width * 0.5, alpha: 0.7)
            triangle(at: NSPoint(x: x + 2, y: y + 71), open: false)
            bar(x + 18, y + 68, width * 0.55)
        case .quote:
            NoteTheme.quoteBar.setFill()
            NSBezierPath(roundedRect: NSRect(x: x, y: y, width: 3, height: 64), xRadius: 1.5, yRadius: 1.5).fill()
            text("Notes are letters", NoteTheme.nunitoItalic(15), at: NSPoint(x: x + 14, y: y + 4))
            text("to future you.", NoteTheme.nunitoItalic(15), at: NSPoint(x: x + 14, y: y + 26))
            bar(x + 14, y + 52, width * 0.4, alpha: 0.7)
        case .callout:
            let box = NSRect(x: x - 4, y: y, width: width + 8, height: 70)
            NoteTheme.calloutFill.setFill()
            NSBezierPath(roundedRect: box, xRadius: 6, yRadius: 6).fill()
            NoteIconRenderer.draw(.emoji("💡"), in: NSRect(x: box.minX + 8, y: box.minY + 8, width: 20, height: 20), tint: NoteTheme.ink, pointSize: 14)
            bar(box.minX + 36, box.minY + 15, box.width * 0.6)
            bar(box.minX + 36, box.minY + 33, box.width * 0.5)
            bar(box.minX + 36, box.minY + 51, box.width * 0.35)
        case .divider:
            bar(x, y + 10, width * 0.8)
            NoteTheme.separator.setFill()
            NSRect(x: x, y: y + 40, width: width, height: 1).fill()
            bar(x, y + 64, width * 0.65)
        case .newNote, .linkToNote:
            let row = NSRect(x: x, y: y + 22, width: width, height: 28)
            icon(block == .newNote ? "doc.badge.plus" : "doc.text", in: NSRect(x: row.minX, y: row.minY, width: 22, height: 28), size: 15)
            let label = block == .newNote ? "Untitled" : "Trip ideas"
            text(label, NoteTheme.nunitoBold(15), at: NSPoint(x: row.minX + 28, y: row.minY + 4))
            NoteTheme.linkUnderline.setFill()
            let labelWidth = NSAttributedString(string: label, attributes: [.font: NoteTheme.nunitoBold(15)]).size().width
            NSRect(x: row.minX + 28, y: row.maxY - 3, width: labelWidth, height: 1).fill()
            if block == .linkToNote { icon("arrow.up.right", in: NSRect(x: row.minX + 32 + labelWidth, y: row.minY, width: 14, height: 28), size: 10) }
        case .table:
            let grid = NSRect(x: x, y: y + 4, width: width, height: 78)
            NoteTheme.tableHeaderFill.setFill()
            NSRect(x: grid.minX, y: grid.minY, width: grid.width, height: grid.height / 3).fill()
            NoteTheme.separator.setStroke()
            let path = NSBezierPath(rect: grid)
            for index in 1..<3 {
                path.move(to: NSPoint(x: grid.minX + grid.width * CGFloat(index) / 3, y: grid.minY))
                path.line(to: NSPoint(x: grid.minX + grid.width * CGFloat(index) / 3, y: grid.maxY))
                path.move(to: NSPoint(x: grid.minX, y: grid.minY + grid.height * CGFloat(index) / 3))
                path.line(to: NSPoint(x: grid.maxX, y: grid.minY + grid.height * CGFloat(index) / 3))
            }
            path.lineWidth = 1
            path.stroke()
        case .image, .video, .audio, .file, .embed, .bookmark:
            mediaSample(in: NSRect(x: x, y: y, width: width, height: rect.height))
        case .tableOfContents:
            for (index, indent) in ([0, 14, 14, 0, 14] as [CGFloat]).enumerated() {
                bar(x + indent, y + 4, (width - indent) * (index % 2 == 0 ? 0.55 : 0.45), alpha: 0.8)
                y += 17
            }
        case .equation:
            let base = NoteTheme.nunitoItalic(26)
            let small = NoteTheme.nunitoItalic(15)
            let formula = NSMutableAttributedString(string: "e", attributes: [.font: base, .foregroundColor: NoteTheme.ink])
            formula.append(NSAttributedString(string: "iπ", attributes: [.font: small, .foregroundColor: NoteTheme.ink, .baselineOffset: 12]))
            formula.append(NSAttributedString(string: " + 1 = 0", attributes: [.font: NoteTheme.nunitoRegular(26), .foregroundColor: NoteTheme.ink]))
            let size = formula.size()
            formula.draw(at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2))
        case .code:
            let box = NSRect(x: x - 4, y: y, width: width + 8, height: rect.height)
            NoteTheme.codeBackground.setFill()
            NSBezierPath(roundedRect: box, xRadius: 6, yRadius: 6).fill()
            let mono = NoteTheme.codeFont(size: 11.5)
            let lines: [[(String, NSColor)]] = [
                [("let ", NoteTheme.syntaxColor("keyword")), ("mood", NoteTheme.codeInk), (" = ", NoteTheme.codeInk), ("\"cosy\"", NoteTheme.syntaxColor("string"))],
                [("if ", NoteTheme.syntaxColor("keyword")), ("mood", NoteTheme.codeInk), (".isEmpty {", NoteTheme.codeInk)],
                [("  print", NoteTheme.syntaxColor("function")), ("(", NoteTheme.codeInk), ("42", NoteTheme.syntaxColor("number")), (")", NoteTheme.codeInk)],
                [("}", NoteTheme.codeInk)],
            ]
            var lineY = box.minY + 10
            for line in lines {
                let string = NSMutableAttributedString()
                for (piece, color) in line { string.append(NSAttributedString(string: piece, attributes: [.font: mono, .foregroundColor: color])) }
                string.draw(at: NSPoint(x: box.minX + 10, y: lineY))
                lineY += 19
            }
        case .columns(let count):
            let gap: CGFloat = 8
            let column = (width - gap * CGFloat(count - 1)) / CGFloat(count)
            for index in 0..<count {
                let left = x + CGFloat(index) * (column + gap)
                NoteTheme.mediaPlaceholderFill.setFill()
                NSBezierPath(roundedRect: NSRect(x: left, y: y, width: column, height: rect.height), xRadius: 5, yRadius: 5).fill()
                for (row, fraction) in ([0.8, 0.6, 0.7] as [CGFloat]).enumerated() { bar(left + 6, y + 10 + CGFloat(row) * 16, (column - 12) * fraction) }
            }
        }
    }

    private func triangle(at point: NSPoint, open: Bool) {
        let path = NSBezierPath()
        if open {
            path.move(to: NSPoint(x: point.x, y: point.y - 3))
            path.line(to: NSPoint(x: point.x + 9, y: point.y - 3))
            path.line(to: NSPoint(x: point.x + 4.5, y: point.y + 4))
        } else {
            path.move(to: NSPoint(x: point.x + 1, y: point.y - 5))
            path.line(to: NSPoint(x: point.x + 8, y: point.y))
            path.line(to: NSPoint(x: point.x + 1, y: point.y + 5))
        }
        path.close()
        NoteTheme.ink.setFill()
        path.fill()
    }

    private func mediaSample(in rect: NSRect) {
        switch block {
        case .audio:
            let row = NSRect(x: rect.minX - 4, y: rect.midY - 22, width: rect.width + 8, height: 44)
            NoteTheme.mediaPlaceholderFill.setFill()
            NSBezierPath(roundedRect: row, xRadius: 22, yRadius: 22).fill()
            icon("play.fill", in: NSRect(x: row.minX + 10, y: row.minY, width: 24, height: row.height), size: 13, tint: NoteTheme.accent)
            var left = row.minX + 42
            for (index, height) in ([8, 16, 22, 12, 18, 26, 14, 20, 10, 16, 24, 12, 8, 18, 14] as [CGFloat]).enumerated() where left < row.maxX - 14 {
                NoteTheme.tertiaryInk.withAlphaComponent(index < 6 ? 0.9 : 0.45).setFill()
                NSBezierPath(roundedRect: NSRect(x: left, y: row.midY - height / 2, width: 3, height: height), xRadius: 1.5, yRadius: 1.5).fill()
                left += 7
            }
        case .file:
            let row = NSRect(x: rect.minX, y: rect.midY - 20, width: rect.width, height: 40)
            icon("paperclip", in: NSRect(x: row.minX, y: row.minY, width: 22, height: row.height), size: 15)
            text("Itinerary.pdf", NoteTheme.nunitoBold(14), at: NSPoint(x: row.minX + 28, y: row.minY + 3))
            text("1.2 MB", NoteTheme.nunitoRegular(11.5), at: NSPoint(x: row.minX + 28, y: row.minY + 21), color: NoteTheme.tertiaryInk)
        case .bookmark:
            let card = NSRect(x: rect.minX - 4, y: rect.minY + 8, width: rect.width + 8, height: rect.height - 16)
            NoteTheme.menuHairline.setStroke()
            let path = NSBezierPath(roundedRect: card, xRadius: 6, yRadius: 6)
            path.lineWidth = 1
            path.stroke()
            let thumb = NSRect(x: card.maxX - 56, y: card.minY, width: 56, height: card.height)
            NoteTheme.mediaPlaceholderFill.setFill()
            NSBezierPath(roundedRect: thumb.insetBy(dx: 1, dy: 1), xRadius: 5, yRadius: 5).fill()
            text("A tidy little card", NoteTheme.nunitoBold(12.5), at: NSPoint(x: card.minX + 10, y: card.minY + 10))
            bar(card.minX + 10, card.minY + 32, card.width - 82, alpha: 0.7)
            NoteTheme.accent.withAlphaComponent(0.7).setFill()
            NSBezierPath(roundedRect: NSRect(x: card.minX + 10, y: card.maxY - 18, width: 9, height: 9), xRadius: 2, yRadius: 2).fill()
            bar(card.minX + 24, card.maxY - 17, 70, alpha: 0.6)
        default:
            let box = NSRect(x: rect.minX - 4, y: rect.minY, width: rect.width + 8, height: rect.height)
            NoteTheme.mediaPlaceholderFill.setFill()
            NSBezierPath(roundedRect: box, xRadius: 6, yRadius: 6).fill()
            if block == .embed {
                for index in 0..<3 {
                    NoteTheme.tertiaryInk.withAlphaComponent(0.6).setFill()
                    NSBezierPath(ovalIn: NSRect(x: box.minX + 9 + CGFloat(index) * 9, y: box.minY + 8, width: 5, height: 5)).fill()
                }
                NoteTheme.separator.setFill()
                NSRect(x: box.minX, y: box.minY + 20, width: box.width, height: 1).fill()
            }
            let name = block == .image ? "photo" : block == .video ? "play.circle.fill" : "globe"
            icon(name, in: box.offsetBy(dx: 0, dy: block == .embed ? 10 : 0), size: 26, tint: NoteTheme.tertiaryInk)
        }
    }
}

@MainActor
enum NoteSlashMenuRows {
    static func item(for item: NoteCatalogItem, filtering: Bool) -> NoteMenuList.Item {
        var row = NoteMenuList.Item(id: item.id, title: item.title, subtitle: filtering ? nil : item.summary, icon: nil,
                                    shortcut: item.hint, section: filtering ? nil : item.section.title)
        switch item.icon {
        case .symbol(let name):
            row.icon = .symbol(name)
        case .text(let text):
            row.icon = .glyph(text)
        case .swatch(let style):
            row.icon = .glyph("A")
            switch style {
            case .text(let color)?:
                row.iconTint = NoteTheme.color(.text(color))
            case .background(let color)?:
                row.iconTint = NoteTheme.menuInk
                row.iconFill = NoteTheme.color(.background(color))
            case nil:
                row.iconTint = NoteTheme.menuInk
            }
        }
        row.isDestructive = item.effect == .action(.delete)
        row.keywords = item.aliases + item.keywords
        row.accessibilityLabel = item.title + ". " + item.summary
        return row
    }
}
