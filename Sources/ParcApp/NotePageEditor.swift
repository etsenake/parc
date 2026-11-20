import AppKit
import Combine

enum NoteCaretDirection: Hashable { case up, down, left, right }

enum NoteSlashTrigger: Hashable {
    case slash(NotePosition)
    case plus(after: NoteBlockID)
    case turnInto([NoteBlockID])
}

@MainActor
final class NotePageEditor {
    let session: NotePageSession
    let environment: NoteEnvironment
    private(set) var canvas: NotePageCanvasView!
    private(set) var selection: NoteSelectionController!
    private(set) var formatBar: NoteFormatBarController!
    private(set) var slashMenu: NoteSlashMenuController!
    private(set) var handles: NoteBlockHandleController!
    private(set) var find: NoteFindController!
    var onOpenURL: ((URL) -> Void)?
    var onOpenNote: ((URL) -> Void)?
    var onError: ((Error) -> Void)?
    var onFocusTitle: (() -> Void)?
    var onPrint: (() -> Void)?
    var onChange: ((NotePageChange) -> Void)?
    var pasteboard: NSPasteboard = .general
    private var subscription: AnyCancellable?
    private var isApplying = false
    private var pasteMenu: NotePasteLinkMenu?
    private var lastReadOnly: Bool?

    init(session: NotePageSession, environment: NoteEnvironment) {
        self.session = session
        self.environment = environment
        canvas = NotePageCanvasView(editor: self)
        selection = NoteSelectionController(editor: self)
        formatBar = NoteFormatBarController(editor: self)
        slashMenu = NoteSlashMenuController(editor: self)
        handles = NoteBlockHandleController(editor: self)
        find = NoteFindController(editor: self)
        subscription = session.changes.sink { [weak self] change in self?.sessionDidChange(change) }
        canvas.reload()
        lastReadOnly = isReadOnly
    }

    var isReadOnly: Bool { session.isReadOnly || session.page.settings.locked }

    var isPlainText: Bool { environment.isPlainText }

    func makeBlockView(for block: NoteBlock) -> NoteBlockView {
        let view = NoteBlockViewFactory.make(block, editor: self)
        view.isReadOnly = isReadOnly
        return view
    }

    static var lastUsedColor: NoteColorStyle? {
        get { NoteColorRecents.load().first }
        set { if let newValue { NoteColorRecents.record(newValue) } }
    }

    var focusedTextHost: NoteTextHost? {
        guard let view = canvas.window?.firstResponder as? NoteTextView, view.isDescendant(of: canvas) else { return nil }
        return view.host
    }

    var ownsFocus: Bool {
        guard let responder = canvas.window?.firstResponder as? NSView else { return false }
        guard responder === canvas || responder.isDescendant(of: canvas) else { return false }
        if let header = canvas.headerView, responder.isDescendant(of: header) { return false }
        return !responder.isDescendant(of: canvas.overlayView)
    }

    var hasMarkedText: Bool { focusedTextHost?.textView.hasMarkedText() ?? false }

    func textDidChange(in host: NoteTextHost) {
        let view = host.textView
        guard !view.hasMarkedText(), !isApplying else { return }
        dismissPasteMenu()
        if isReadOnly {
            if let text = session.page.block(host.blockID)?.text(in: host.field) {
                isApplying = true
                view.apply(text, selection: view.selectedOffsets)
                isApplying = false
            }
            return
        }
        session.setText(view.noteText, of: (host.blockID, host.field), origin: view, selection: selection.sessionSelection(for: host))
        slashMenu.textDidChange(in: host)
    }

    func textSelectionDidChange(in host: NoteTextHost) {
        guard !host.textView.hasMarkedText(), !isApplying, !selection.isApplying, !selection.isTracking else { return }
        session.setSelection(selection.sessionSelection(for: host), origin: host.textView)
        formatBar.selectionDidChange()
    }

    func focus(_ position: NotePosition) {
        focus(position, range: nil)
    }

    func focus(_ position: NotePosition, range: Range<Int>?) {
        guard let view = materializedView(for: position.block) else { return }
        isApplying = true
        defer { isApplying = false }
        guard view.focus(at: range == nil ? position.offset : nil, field: position.field) else { return }
        if let range, let host = view.textHost(for: position.field) { host.textView.selectedOffsets = range }
    }

    func materializedView(for id: NoteBlockID) -> NoteBlockView? {
        canvas.layoutSubtreeIfNeeded()
        canvas.scrollBlockToVisible(id)
        canvas.layoutSubtreeIfNeeded()
        return canvas.blockView(for: id)
    }

    func open(_ url: URL) {
        if url.isFileURL, NoteFileKind(url: url) != nil { onOpenNote?(url) } else { onOpenURL?(url) }
    }

    func appearanceDidChange() {
        for view in canvas.materializedViews { view.themeDidChange() }
        canvas.needsDisplay = true
    }

    func dismissOverlays() {
        dismissPasteMenu()
        slashMenu.dismiss(animated: false)
        formatBar.dismiss(animated: false)
        hideDropIndicator()
    }

    private func sessionDidChange(_ change: NotePageChange) {
        let hadFocus = ownsFocus
        let focusedOrigin = focusedTextHost.map { ObjectIdentifier($0.textView) }
        isApplying = true
        if change.kind != .selection {
            canvas.apply(change)
            if lastReadOnly != isReadOnly { applyReadOnly() }
            canvas.layoutSubtreeIfNeeded()
        }
        if let menu = pasteMenu, session.selection != .caret(menu.link.end) { dismissPasteMenu() }
        selection.apply(session.selection)
        isApplying = false
        if change.kind != .selection, hadFocus, change.origin == nil || change.origin != focusedOrigin {
            restoreFocus()
        }
        formatBar.selectionDidChange()
        handles.layoutDidChange()
        onChange?(change)
    }

    private func applyReadOnly() {
        lastReadOnly = isReadOnly
        for view in canvas.materializedViews { view.isReadOnly = isReadOnly }
        if isReadOnly { dismissOverlays() }
    }

    func restoreFocus() {
        selection.focusSelection()
        guard case .text(let anchor, let head) = session.selection, anchor.block == head.block, anchor.field == head.field else { return }
        let range = min(anchor.offset, head.offset)..<max(anchor.offset, head.offset)
        if let host = focusedTextHost, host.blockID == head.block, host.field == head.field, host.textView.selectedOffsets == range { return }
        focus(head, range: range)
    }

    var targetBlocks: [NoteBlockID] {
        let page = session.page
        switch session.selection {
        case .blocks(let ids): return page.topLevelSelection(ids)
        case .cells(let table, _, _): return [table]
        case .text(let anchor, let head):
            if anchor.block == head.block { return [head.block] }
            let order = page.visibleTextOrder()
            guard let from = order.firstIndex(of: anchor.block), let to = order.firstIndex(of: head.block) else { return [head.block] }
            return page.topLevelSelection(order[min(from, to)...max(from, to)])
        case .none:
            return focusedTextHost.map { [$0.blockID] } ?? []
        }
    }

    var hasTextRange: Bool {
        switch session.selection {
        case .text(let anchor, let head): return anchor != head
        case .blocks(let ids): return ids.contains { session.page.block($0)?.kind.hasRichText == true }
        default: return false
        }
    }

    var isCrossBlockSelection: Bool {
        if case .text(let anchor, let head) = session.selection { return anchor.block != head.block || anchor.field != head.field }
        return false
    }

    var hasCopyableSelection: Bool {
        switch session.selection {
        case .none: return false
        case .text(let anchor, let head): return anchor != head
        case .blocks(let ids): return !ids.isEmpty
        case .cells: return true
        }
    }

    func handleTextCommand(_ selector: Selector, in host: NoteTextHost) -> Bool {
        let view = host.textView
        guard !view.hasMarkedText() else { return false }
        if selection.handleTextCommand(selector, in: host) { return true }
        if case .blocks = session.selection, let handled = handleBlockSelectionCommand(selector) { return handled }
        if isCrossBlockSelection, let handled = handleCrossBlockCommand(selector) { return handled }
        guard let block = session.page.block(host.blockID) else { return false }
        let range = view.selectedOffsets
        let length = (view.string as NSString).length
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            return insertNewline(block: block, host: host, range: range)
        case #selector(NSResponder.insertLineBreak(_:)), #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)):
            guard !isReadOnly else { return true }
            if host.field != .body && !(host.field.isCell) { return true }
            if host.field.isCell { return false }
            view.insertText("\n", replacementRange: view.selectedRange())
            return true
        case #selector(NSResponder.deleteBackward(_:)), #selector(NSResponder.deleteWordBackward(_:)),
             #selector(NSResponder.deleteToBeginningOfLine(_:)), #selector(NSResponder.deleteToBeginningOfParagraph(_:)),
             #selector(NSResponder.deleteBackwardByDecomposingPreviousCharacter(_:)):
            guard range == 0..<0 else { return false }
            guard !isReadOnly else { return true }
            guard host.field == .body else { return !host.field.isCell }
            dismissOverlaysForStructure()
            session.mergeBackward(host.blockID)
            return true
        case #selector(NSResponder.deleteForward(_:)), #selector(NSResponder.deleteWordForward(_:)),
             #selector(NSResponder.deleteToEndOfLine(_:)), #selector(NSResponder.deleteToEndOfParagraph(_:)):
            guard range.isEmpty, range.lowerBound == length else { return false }
            guard !isReadOnly else { return true }
            guard host.field == .body else { return !host.field.isCell }
            dismissOverlaysForStructure()
            session.mergeForward(host.blockID)
            return true
        case #selector(NSResponder.insertTab(_:)):
            guard host.field == .body, !block.kind.hasPlainText else { return false }
            guard !isReadOnly else { return true }
            session.indent([host.blockID])
            return true
        case #selector(NSResponder.insertBacktab(_:)):
            guard host.field == .body, !block.kind.hasPlainText else { return false }
            guard !isReadOnly else { return true }
            session.outdent([host.blockID])
            return true
        case #selector(NSResponder.moveUp(_:)):
            guard host.field == .body, range.isEmpty, view.isOnFirstLine(range.lowerBound),
                  session.page.visibleTextOrder().first == host.blockID, let onFocusTitle else { return false }
            onFocusTitle()
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            if dismissTopOverlay() { return true }
            guard host.field == .body || host.field == .caption else { return false }
            view.selectedOffsets = range.lowerBound..<range.lowerBound
            session.setSelection(.blocks([host.blockID]))
            restoreFocus()
            return true
        default:
            return false
        }
    }

    private func insertNewline(block: NoteBlock, host: NoteTextHost, range: Range<Int>) -> Bool {
        guard !isReadOnly else { return true }
        switch host.field {
        case .cell: return false
        case .caption:
            dismissOverlaysForStructure()
            let fresh = NoteBlock.paragraph()
            session.insertBlocks([fresh], .after(block.id), select: .caret(NotePosition(fresh.id, 0)))
            return true
        case .body:
            break
        }
        if block.kind.hasPlainText {
            guard block.kind == .code else { return false }
            let text = host.textView.string
            guard NoteCodeEditing.exitsOnReturn(text, selection: range) else { return false }
            dismissOverlaysForStructure()
            let fresh = NoteBlock.paragraph()
            let trimmed = NoteCodeEditing.trimmedForExit(text)
            session.edit("New Block", selection: .caret(NotePosition(fresh.id, 0))) { page in
                page.update(block.id) { $0.text = NoteText(trimmed) }
                page.insert([fresh], .after(block.id))
            }
            return true
        }
        guard block.kind.hasRichText else { return false }
        dismissOverlaysForStructure()
        var caret = NotePosition(block.id, range.lowerBound)
        if !range.isEmpty {
            guard let start = session.deleteSelection(.text(anchor: NotePosition(block.id, range.lowerBound),
                                                             head: NotePosition(block.id, range.upperBound))) else { return true }
            caret = start
        }
        session.splitBlock(at: caret)
        return true
    }

    private func handleCrossBlockCommand(_ selector: Selector) -> Bool? {
        switch selector {
        case #selector(NSResponder.deleteBackward(_:)), #selector(NSResponder.deleteForward(_:)),
             #selector(NSResponder.deleteWordBackward(_:)), #selector(NSResponder.deleteWordForward(_:)),
             #selector(NSResponder.deleteToBeginningOfLine(_:)), #selector(NSResponder.deleteToEndOfLine(_:)),
             #selector(NSResponder.deleteBackwardByDecomposingPreviousCharacter(_:)):
            guard !isReadOnly else { return true }
            dismissOverlaysForStructure()
            session.deleteSelection()
            return true
        case #selector(NSResponder.insertNewline(_:)):
            guard !isReadOnly else { return true }
            dismissOverlaysForStructure()
            if let caret = session.deleteSelection() { session.splitBlock(at: caret) }
            return true
        case #selector(NSResponder.insertLineBreak(_:)):
            guard !isReadOnly else { return true }
            session.insertText(NoteText("\n"))
            return true
        case #selector(NSResponder.insertTab(_:)):
            guard !isReadOnly else { return true }
            session.indent(targetBlocks)
            return true
        case #selector(NSResponder.insertBacktab(_:)):
            guard !isReadOnly else { return true }
            session.outdent(targetBlocks)
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            if dismissTopOverlay() { return true }
            session.setSelection(.blocks(targetBlocks))
            restoreFocus()
            return true
        default:
            return nil
        }
    }

    private func handleBlockSelectionCommand(_ selector: Selector) -> Bool? {
        switch selector {
        case #selector(NSResponder.deleteBackward(_:)), #selector(NSResponder.deleteForward(_:)):
            guard !isReadOnly else { return true }
            dismissOverlaysForStructure()
            session.deleteSelection()
            return true
        case #selector(NSResponder.insertNewline(_:)):
            return enterBlockSelection()
        case #selector(NSResponder.insertTab(_:)):
            guard !isReadOnly else { return true }
            session.indent(targetBlocks)
            return true
        case #selector(NSResponder.insertBacktab(_:)):
            guard !isReadOnly else { return true }
            session.outdent(targetBlocks)
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            if dismissTopOverlay() { return true }
            session.setSelection(.none)
            return true
        default:
            return nil
        }
    }

    private func enterBlockSelection() -> Bool {
        let ids = targetBlocks
        let page = session.page
        let toggles = ids.filter { page.block($0)?.isToggle == true }
        if !toggles.isEmpty, !isReadOnly, toggles.contains(where: { page.block($0)?.props.expanded == false }) {
            session.edit("Expand", affected: Set(toggles), selection: session.selection) { page in
                for id in toggles { page.update(id) { $0.props.expanded = true } }
            }
            return true
        }
        guard let first = ids.first, let block = page.block(first) else { return true }
        if block.kind == .pageLink, let target = block.props.target, let url = environment.resolveNoteLink(target) {
            open(url)
            return true
        }
        guard block.kind.hasRichText || block.kind.hasPlainText else { return true }
        let caret = NotePosition(first, block.text.length)
        session.setSelection(.caret(caret))
        focus(caret)
        return true
    }

    func handleKeyDown(_ event: NSEvent, in host: NoteTextHost?) -> Bool {
        if let pasteMenu, handlePasteMenuKey(event, menu: pasteMenu) { return true }
        if slashMenu.handleKey(event) { return true }
        if formatBar.handleKey(event) { return true }
        if handles.handleKey(event) { return true }
        if event.modifierFlags.intersection([.command, .control, .option]).isEmpty == false || host == nil,
           performKeyEquivalent(event) { return true }
        guard host == nil || session.selection.isBlockSelection else { return false }
        return handleSelectionKey(event)
    }

    private func handleSelectionKey(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .control, .option, .shift])
        let blocks = session.selection.isBlockSelection
        switch event.keyCode {
        case 36 where flags.isEmpty, 76 where flags.isEmpty:
            guard blocks else { return false }
            return enterBlockSelection()
        case 51 where flags.isEmpty, 117 where flags.isEmpty:
            guard blocks || isCrossBlockSelection else { return false }
            guard !isReadOnly else { NSSound.beep(); return true }
            dismissOverlaysForStructure()
            session.deleteSelection()
            return true
        case 2 where flags == .control:
            guard blocks else { return false }
            guard !isReadOnly else { NSSound.beep(); return true }
            session.deleteSelection()
            return true
        case 48 where flags.isEmpty || flags == .shift:
            guard blocks || isCrossBlockSelection else { return false }
            guard !isReadOnly else { NSSound.beep(); return true }
            if flags == .shift { session.outdent(targetBlocks) } else { session.indent(targetBlocks) }
            return true
        case 53 where flags.isEmpty:
            if dismissTopOverlay() { return true }
            guard blocks else { return false }
            session.setSelection(.none)
            return true
        default:
            return false
        }
    }

    @discardableResult
    private func dismissTopOverlay() -> Bool {
        if pasteMenu != nil { dismissPasteMenu(); return true }
        if slashMenu.isOpen { slashMenu.dismiss(animated: true); return true }
        return false
    }

    private func dismissOverlaysForStructure() {
        dismissPasteMenu()
        if slashMenu.isOpen { slashMenu.dismiss(animated: false) }
    }

    func performKeyEquivalent(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown, let command = NoteKeyCommands.command(for: event) else { return false }
        guard !hasMarkedText else { return false }
        if command.isEdit, isReadOnly, command != .undo, command != .redo {
            NSSound.beep()
            return true
        }
        guard validate(command) else { return false }
        return perform(command)
    }

    func validate(_ command: NoteKeyCommand) -> Bool {
        if command.isEdit && isReadOnly { return false }
        let page = session.page
        switch command {
        case .mark, .inlineEquation:
            return !isPlainText && hasTextRange
        case .lastColor:
            return !isPlainText && Self.lastUsedColor != nil && (hasTextRange || session.selection.isBlockSelection)
        case .link:
            return !isPlainText && hasTextRange && !isCrossBlockSelection
        case .turnInto(let target):
            guard !isPlainText else { return false }
            if target == .page { return environment.documentURL != nil && targetBlocks.contains { page.block($0)?.kind.hasRichText == true } }
            return targetBlocks.contains { id in page.block(id).map { $0.kind.hasRichText || $0.kind.hasPlainText } ?? false }
        case .duplicate, .moveBlocks, .indent, .outdent:
            return !targetBlocks.isEmpty
        case .modifyBlock:
            return targetBlocks.contains { id in
                guard let block = page.block(id) else { return false }
                return block.kind == .todo || block.isToggle || block.kind == .pageLink
            }
        case .toggleAllToggles:
            return !isReadOnly && page.allBlocks().contains(where: \.isToggle)
        case .blockActions:
            return !isReadOnly && !targetBlocks.isEmpty
        case .undo: return session.canUndo && !isReadOnly
        case .redo: return session.canRedo && !isReadOnly
        case .selectAll: return true
        case .copy: return hasCopyableSelection
        case .cut, .delete: return hasCopyableSelection
        case .paste, .pastePlainText: return canPaste
        case .find, .findAndReplace: return true
        case .findNext, .findPrevious: return true
        case .useSelectionForFind: return hasTextRange && !isCrossBlockSelection
        case .print: return onPrint != nil
        }
    }

    @discardableResult
    func perform(_ command: NoteKeyCommand) -> Bool {
        guard !hasMarkedText else { return false }
        if command.isEdit && isReadOnly { NSSound.beep(); return true }
        switch command {
        case .mark(let key):
            guard hasTextRange else { return false }
            session.toggleMark(key)
            return true
        case .inlineEquation:
            return convertToEquation()
        case .link:
            return false
        case .lastColor:
            guard let color = Self.lastUsedColor else { return false }
            session.setColor(color)
            Self.lastUsedColor = color
            return true
        case .turnInto(let target):
            return turnInto(target)
        case .duplicate:
            let ids = targetBlocks
            guard !ids.isEmpty else { return false }
            let previous = session.selection
            dismissOverlaysForStructure()
            session.duplicateBlocks(ids)
            if case .text = previous { session.setSelection(previous) }
            return true
        case .moveBlocks(let direction):
            let ids = targetBlocks
            guard !ids.isEmpty else { return false }
            dismissOverlaysForStructure()
            session.moveBlocks(ids, direction)
            if let first = ids.first { canvas.scrollBlockToVisible(first) }
            return true
        case .modifyBlock:
            return modifyBlocks()
        case .toggleAllToggles:
            return toggleAllToggles()
        case .blockActions:
            if handles.openBlockActions() { return true }
            let ids = targetBlocks
            guard !ids.isEmpty else { return false }
            slashMenu.open(.turnInto(ids))
            return true
        case .indent:
            return session.indent(targetBlocks)
        case .outdent:
            return session.outdent(targetBlocks)
        case .undo:
            dismissOverlays()
            session.undo()
            return true
        case .redo:
            dismissOverlays()
            session.redo()
            return true
        case .selectAll:
            selection.selectAll()
            return true
        case .copy:
            return copySelection()
        case .cut:
            return cutSelection()
        case .paste:
            return paste(plainText: false)
        case .pastePlainText:
            return paste(plainText: true)
        case .delete:
            guard hasCopyableSelection else { return false }
            dismissOverlaysForStructure()
            session.deleteSelection()
            return true
        case .find:
            find.show(replacing: false)
            return true
        case .findAndReplace:
            find.show(replacing: true)
            return true
        case .findNext:
            if find.isVisible { find.findNext() } else { find.show(replacing: false) }
            return true
        case .findPrevious:
            if find.isVisible { find.findPrevious() } else { find.show(replacing: false) }
            return true
        case .useSelectionForFind:
            find.useSelectionForFind()
            return true
        case .print:
            guard let onPrint else { return false }
            onPrint()
            return true
        }
    }

    func performMenuAction(_ action: Selector, sender: Any?) -> Bool {
        let tag = (sender as? NSMenuItem)?.tag ?? (sender as? NSValidatedUserInterfaceItem)?.tag ?? 0
        guard let command = NoteKeyCommands.command(forAction: action, tag: tag) else { return false }
        if command.isEdit && isReadOnly { NSSound.beep(); return true }
        guard validate(command) else { return false }
        return perform(command)
    }

    func validateMenuAction(_ item: NSValidatedUserInterfaceItem) -> Bool? {
        guard let action = item.action, let command = NoteKeyCommands.command(forAction: action, tag: item.tag) else { return nil }
        if let menuItem = item as? NSMenuItem {
            switch command {
            case .undo: menuItem.title = session.undoActionName.map { "Undo " + $0 } ?? "Undo"
            case .redo: menuItem.title = session.redoActionName.map { "Redo " + $0 } ?? "Redo"
            case .mark(let key): menuItem.state = hasTextRange && session.hasMark(key) ? .on : .off
            case .turnInto(let target): menuItem.state = isCurrentKind(target) ? .on : .off
            case .link: menuItem.title = currentLink != nil ? TextFormatCommand.editLinkTitle : TextFormatCommand.addLinkTitle
            default: break
            }
        }
        return validate(command)
    }

    private var currentLink: String? {
        guard case .text(let anchor, let head) = session.selection, anchor.block == head.block,
              let text = session.page.text(of: head) else { return nil }
        let offset = min(anchor.offset, head.offset)
        return text.length > offset ? text.marks(at: offset).link : nil
    }

    private func isCurrentKind(_ target: NoteTurnIntoTarget) -> Bool {
        let blocks = targetBlocks.compactMap { session.page.block($0) }
        guard !blocks.isEmpty else { return false }
        return blocks.allSatisfy { block in
            block.kind == target.kind && (target.headingLevel == nil || block.props.level == target.headingLevel)
        }
    }

    private func turnInto(_ target: NoteTurnIntoTarget) -> Bool {
        let page = session.page
        let ids = targetBlocks.filter { id in page.block(id).map { $0.kind.hasRichText || $0.kind.hasPlainText } ?? false }
        guard !ids.isEmpty else { return false }
        dismissOverlaysForStructure()
        if target == .page { return turnIntoPages(ids) }
        if let level = target.headingLevel {
            session.turnInto(ids, kind: .heading) { $0.level = level }
        } else {
            session.turnInto(ids, kind: target.kind)
        }
        return true
    }

    private func turnIntoPages(_ ids: [NoteBlockID]) -> Bool {
        guard let document = environment.documentURL, !isPlainText else { return false }
        let folder = document.deletingLastPathComponent()
        var replacements: [NoteBlockID: NoteBlock] = [:]
        for id in ids {
            guard let block = session.page.block(id), block.kind.hasRichText else { continue }
            let title = Self.fileTitle(block.text.plainText)
            let url = Self.uniqueNoteURL(in: folder, title: title)
            let body = NoteMarkdown.serialize(NotePage(blocks: block.children))
            do {
                try Data(body.utf8).write(to: url, options: .withoutOverwriting)
            } catch {
                onError?(error)
                continue
            }
            var props = NoteBlockProps()
            props.target = environment.linkTarget(for: url)
            replacements[id] = NoteBlock(.pageLink, text: NoteText(url.deletingPathExtension().lastPathComponent), props: props, id: id)
        }
        guard !replacements.isEmpty else { return true }
        session.edit("Turn Into Page", affected: Set(replacements.keys), selection: .blocks(Array(replacements.keys))) { page in
            for (id, block) in replacements { page.update(id) { $0 = block } }
        }
        return true
    }

    static func fileTitle(_ text: String) -> String {
        var title = text.components(separatedBy: .newlines).first ?? ""
        title = title.replacingOccurrences(of: NoteAtom.character, with: "")
        for character in ["/", ":", "\\"] { title = title.replacingOccurrences(of: character, with: "-") }
        title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        while title.hasPrefix(".") { title.removeFirst() }
        if title.count > 120 { title = String(title.prefix(120)).trimmingCharacters(in: .whitespaces) }
        return title.isEmpty ? "Untitled" : title
    }

    static func uniqueNoteURL(in folder: URL, title: String) -> URL {
        var candidate = folder.appendingPathComponent(title).appendingPathExtension("md")
        var number = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent("\(title) \(number)").appendingPathExtension("md")
            number += 1
        }
        return candidate
    }

    private func convertToEquation() -> Bool {
        guard case .text(let anchor, let head) = session.selection, anchor.block == head.block, anchor.field == head.field,
              anchor != head, let block = session.page.block(head.block), block.kind.hasRichText,
              let text = block.text(in: head.field) else { return false }
        let range = min(anchor.offset, head.offset)..<max(anchor.offset, head.offset)
        let source = text.slice(range).plainText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else { return false }
        let atom = NoteText.atom(.equation(source), marks: text.marks(at: range.lowerBound).withoutAtom)
        session.replaceText(at: NotePosition(head.block, range.lowerBound, field: head.field), length: range.count, with: atom)
        return true
    }

    private func modifyBlocks() -> Bool {
        let page = session.page
        let ids = targetBlocks
        let todos = ids.filter { page.block($0)?.kind == .todo }
        let toggles = ids.filter { page.block($0)?.isToggle == true }
        if todos.isEmpty, toggles.isEmpty, ids.count == 1, let block = page.block(ids[0]), block.kind == .pageLink,
           let target = block.props.target, let url = environment.resolveNoteLink(target) {
            open(url)
            return true
        }
        guard !todos.isEmpty || !toggles.isEmpty else { return false }
        guard !isReadOnly else { NSSound.beep(); return true }
        if !todos.isEmpty { session.toggleChecked(todos) }
        if !toggles.isEmpty {
            let expand = toggles.contains { page.block($0)?.props.expanded == false }
            session.edit(expand ? "Expand" : "Collapse", affected: Set(toggles), selection: session.selection) { page in
                for id in toggles { page.update(id) { $0.props.expanded = expand } }
            }
            if !expand { keepSelectionVisible() }
        }
        return true
    }

    private func toggleAllToggles() -> Bool {
        let toggles = session.page.allBlocks().filter(\.isToggle)
        guard !toggles.isEmpty else { return false }
        let expand = toggles.contains { !$0.props.expanded }
        session.setAllToggles(expanded: expand)
        if !expand { keepSelectionVisible() }
        return true
    }

    private func keepSelectionVisible() {
        let visible = Set(session.page.flattened().map(\.id))
        let page = session.page
        func nearestVisible(_ id: NoteBlockID) -> NoteBlockID? {
            var current: NoteBlockID? = id
            while let candidate = current, !visible.contains(candidate) { current = page.parent(of: candidate) }
            return current
        }
        switch session.selection {
        case .text(_, let head) where !visible.contains(head.block):
            guard let target = nearestVisible(head.block), let block = page.block(target) else { return }
            let caret = NotePosition(target, block.text.length)
            session.setSelection(.caret(caret))
            if ownsFocus || canvas.window?.firstResponder === canvas.window { focus(caret) }
        case .blocks(let ids) where ids.contains(where: { !visible.contains($0) }):
            let remaining = Array(Set(ids.compactMap(nearestVisible)))
            session.setSelection(remaining.isEmpty ? .none : .blocks(page.ordered(remaining)))
        default:
            break
        }
    }

    var canPaste: Bool {
        let readable: [NSPasteboard.PasteboardType] = [NoteClipboard.blocksType, .fileURL, .string, .html, .URL, .png, .tiff,
                                                       NoteClipboard.markdownType] + NoteClipboard.imageTypes.map(\.type)
        return pasteboard.availableType(from: readable) != nil
    }

    @discardableResult
    func copySelection() -> Bool {
        let target = session.selection
        guard hasCopyableSelection else { return false }
        let fragment = session.fragment(of: target)
        guard !fragment.isEmpty else { return false }
        var inline = false
        if case .text = target { inline = true }
        let payload = NoteClipboard.payload(for: fragment, inline: inline,
                                            base: environment.documentURL?.deletingLastPathComponent(),
                                            plainTextFile: isPlainText)
        return NoteClipboard.write(payload, to: pasteboard)
    }

    @discardableResult
    func cutSelection() -> Bool {
        guard !isReadOnly else { NSSound.beep(); return true }
        guard copySelection() else { return false }
        dismissOverlaysForStructure()
        session.deleteSelection()
        return true
    }

    @discardableResult
    func paste(plainText: Bool) -> Bool {
        guard !isReadOnly else { NSSound.beep(); return true }
        guard !hasMarkedText else { return false }
        dismissPasteMenu()
        let reading = NoteClipboard.read(pasteboard)
        let plainOnly = plainText || isPlainText || caretIsInPlainField
        switch NoteClipboard.choose(reading, plainOnly: plainOnly, canReadHTML: false) {
        case .nothing:
            return false
        case .plainText:
            guard let string = NoteClipboard.plainString(reading) else { return false }
            insertPlain(string)
        case .blocks:
            guard let archive = reading.archive else { return false }
            pasteBlocks(NoteClipboard.rebase(archive, into: environment), inline: archive.inline)
        case .files:
            let result = NoteClipboard.blocks(forFiles: reading.files, environment: environment)
            pasteBlocks(result.blocks, inline: false)
            if let failure = result.failures.first { onError?(failure) }
        case .image:
            guard let data = reading.image else { return false }
            do {
                let block = try NoteClipboard.imageBlock(data: data, fileExtension: reading.imageExtension ?? "png", environment: environment)
                pasteBlocks([block], inline: false)
            } catch {
                onError?(error)
            }
        case .html:
            guard let string = reading.string else { return false }
            insertPlain(string)
        case .url:
            let text = reading.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard let url = NoteClipboard.webURL(in: text) ?? reading.url else { return false }
            pasteURL(url, title: reading.urlTitle)
        case .markdown:
            guard let string = reading.string else { return false }
            pasteBlocks(NoteClipboard.markdownBlocks(string), inline: true)
        }
        return true
    }

    private var caretIsInPlainField: Bool {
        guard case .text(_, let head) = session.selection, !isCrossBlockSelection else { return false }
        if head.field != .body { return true }
        return session.page.block(head.block)?.kind.hasRichText != true
    }

    private func insertPlain(_ string: String) {
        let normalized = string.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        guard case .text = session.selection else {
            pasteBlocks(isPlainText ? NotePlainText.parse(normalized).blocks : NoteClipboard.plainBlocks(normalized), inline: false)
            return
        }
        if case .text(_, let head) = session.selection, !isCrossBlockSelection {
            if head.field.isCell || head.field == .caption {
                session.insertText(NoteText(normalized.replacingOccurrences(of: "\n", with: " ")))
                return
            }
            if session.page.block(head.block)?.kind.hasPlainText == true {
                session.insertText(NoteText(normalized))
                return
            }
        }
        guard normalized.contains("\n") else {
            session.insertText(NoteText(normalized))
            return
        }
        let blocks = isPlainText ? NotePlainText.parse(normalized).blocks : NoteClipboard.plainBlocks(normalized)
        pasteBlocks(blocks, inline: true)
    }

    private func pasteBlocks(_ blocks: [NoteBlock], inline: Bool) {
        guard !blocks.isEmpty else { return }
        dismissOverlaysForStructure()
        guard !inline, case .text(let anchor, let head) = session.selection, anchor == head, head.field == .body,
              let host = session.page.block(head.block), host.kind.hasRichText else {
            session.paste(blocks)
            return
        }
        let fresh = blocks.map { $0.withFreshIDs() }
        if host.text.isEmpty, host.kind == .paragraph, host.children.isEmpty {
            let landing = Self.landing(for: fresh)
            session.edit("Paste", selection: landing) { page in
                page.insert(fresh, .after(host.id))
                page.remove(host.id)
            }
        } else if head.offset == host.text.length {
            session.insertBlocks(fresh, .after(host.id), select: Self.landing(for: fresh))
        } else {
            session.paste(blocks)
        }
    }

    private static func landing(for blocks: [NoteBlock]) -> NotePageSelection {
        guard let last = blocks.last else { return .none }
        if last.kind.hasRichText || last.kind.hasPlainText { return .caret(NotePosition(last.id, last.text.length)) }
        return .blocks([last.id])
    }

    private func pasteURL(_ url: URL, title: String?) {
        let link = url.absoluteString
        if case .text(let anchor, let head) = session.selection, anchor != head, !isCrossBlockSelection,
           session.page.block(head.block)?.kind.hasRichText == true {
            session.setLink(link)
            return
        }
        guard case .text = session.selection else {
            var marks = NoteMarks.plain
            marks.link = link
            pasteBlocks([.paragraph(NoteText(title.flatMap { $0.isEmpty ? nil : $0 } ?? link, marks: marks))], inline: false)
            return
        }
        guard let caret = session.deleteSelection(), let text = session.page.text(of: caret) else { return }
        var marks = text.typingMarks(at: caret.offset)
        marks.link = link
        let label = NoteText(link, marks: marks)
        session.replaceText(at: caret, length: 0, with: label)
        guard caret.field == .body, session.page.block(caret.block)?.kind.hasRichText == true else { return }
        showPasteMenu(NotePastedLink(position: caret, length: label.length, url: url, title: title))
    }

    private func showPasteMenu(_ link: NotePastedLink) {
        dismissPasteMenu()
        guard let view = materializedView(for: link.position.block), let host = view.textHost(for: link.position.field) else { return }
        let caret = host.textView.caretRect(at: link.position.offset + link.length)
        let start = host.textView.caretRect(at: link.position.offset)
        let anchor = canvas.overlayView.convert(NSRect(x: start.minX, y: caret.minY, width: max(1, caret.maxX - start.minX), height: caret.height),
                                                from: host.textView)
        let menu = NotePasteLinkMenu(link: link, embeddable: NoteClipboard.isEmbeddable(link.url)) { [weak self] choice in
            self?.choosePasteOption(choice)
        }
        pasteMenu = menu
        menu.present(in: canvas.overlayView, anchor: anchor)
    }

    private func handlePasteMenuKey(_ event: NSEvent, menu: NotePasteLinkMenu) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .control, .option, .shift])
        if event.keyCode == 48, flags.isEmpty || flags == .shift {
            menu.list.moveHighlight(by: flags == .shift ? -1 : 1)
            return true
        }
        if flags.intersection([.command, .control, .option]).isEmpty, menu.list.handleKeyDown(event) { return true }
        dismissPasteMenu()
        return false
    }

    private func choosePasteOption(_ choice: NotePasteLinkMenu.Choice) {
        guard let link = pasteMenu?.link else { return }
        dismissPasteMenu()
        guard !isReadOnly, choice != .dismiss, let block = session.page.block(link.position.block),
              let text = block.text(in: link.position.field) else { return }
        let range = link.position.offset..<(link.position.offset + link.length)
        guard range.upperBound <= text.length, text.runs(in: range).allSatisfy({ $0.marks.link == link.url.absoluteString }) else { return }
        switch choice {
        case .dismiss:
            return
        case .mention:
            let atom = NoteText.atom(.link(url: link.url.absoluteString, title: link.title ?? ""), marks: text.marks(at: range.lowerBound).withoutAtom.unlinked)
            session.replaceText(at: link.position, length: link.length, with: atom)
        case .bookmark, .embed:
            var props = NoteBlockProps()
            props.source = link.url.absoluteString
            let fresh = NoteBlock(choice == .bookmark ? .bookmark : .embed, props: props)
            var remaining = text
            remaining.delete(range)
            let replacesBlock = remaining.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && block.kind == .paragraph && block.children.isEmpty
            session.edit(choice == .bookmark ? "Bookmark" : "Embed", selection: .blocks([fresh.id])) { page in
                if replacesBlock {
                    page.insert([fresh], .after(block.id))
                    page.remove(block.id)
                } else {
                    page.update(block.id) { $0.setText(remaining, in: link.position.field) }
                    page.insert([fresh], .after(block.id))
                }
            }
        }
    }

    func dismissPasteMenu() {
        guard let menu = pasteMenu else { return }
        pasteMenu = nil
        menu.dismiss()
    }

    static let externalDragTypes: [NSPasteboard.PasteboardType] = [.fileURL, .URL, .string, .png, .tiff, .html]
        + NoteClipboard.imageTypes.map(\.type)

    func dragOperation(for info: NSDraggingInfo, at point: NSPoint) -> NSDragOperation {
        guard !isReadOnly, info.draggingPasteboard.availableType(from: Self.externalDragTypes) != nil else {
            hideDropIndicator()
            return []
        }
        canvas.showDropIndicator(canvas.dropTarget(at: point, dragging: []))
        return info.draggingSourceOperationMask.contains(.copy) ? .copy : .generic
    }

    func dragExited() {
        hideDropIndicator()
    }

    func performDrop(_ info: NSDraggingInfo, at point: NSPoint) -> Bool {
        hideDropIndicator()
        guard !isReadOnly else { return false }
        let target = canvas.dropTarget(at: point, dragging: [])
        let reading = NoteClipboard.read(info.draggingPasteboard)
        var blocks: [NoteBlock] = []
        switch NoteClipboard.choose(reading, plainOnly: isPlainText, canReadHTML: false) {
        case .nothing:
            return false
        case .blocks:
            guard let archive = reading.archive else { return false }
            blocks = NoteClipboard.rebase(archive, into: environment).map { $0.withFreshIDs() }
        case .files:
            let result = NoteClipboard.blocks(forFiles: reading.files, environment: environment)
            blocks = result.blocks
            if let failure = result.failures.first { onError?(failure) }
        case .image:
            guard let data = reading.image else { return false }
            do { blocks = [try NoteClipboard.imageBlock(data: data, fileExtension: reading.imageExtension ?? "png", environment: environment)] }
            catch { onError?(error); return false }
        case .url:
            let text = reading.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard let url = NoteClipboard.webURL(in: text) ?? reading.url else { return false }
            var marks = NoteMarks.plain
            marks.link = url.absoluteString
            let label = reading.urlTitle.flatMap { $0.isEmpty ? nil : $0 } ?? url.absoluteString
            blocks = [.paragraph(NoteText(label, marks: marks))]
        case .markdown:
            blocks = NoteClipboard.markdownBlocks(reading.string ?? "")
        case .plainText, .html:
            guard let string = NoteClipboard.plainString(reading) else { return false }
            blocks = isPlainText ? NotePlainText.parse(string).blocks : NoteClipboard.plainBlocks(string)
        }
        guard !blocks.isEmpty else { return false }
        dismissOverlaysForStructure()
        let landing = Self.landing(for: blocks)
        switch target?.action {
        case .move(let insertion)?:
            session.insertBlocks(blocks, insertion, select: landing)
        case .placeBeside(let anchor, let side)?:
            session.insertBlocks(blocks, .after(anchor), select: landing)
            session.placeBeside(blocks.map(\.id), target: anchor, side: side)
        case nil:
            session.insertBlocks(blocks, .top(session.page.blocks.count), select: landing)
        }
        restoreFocus()
        return true
    }

    private func hideDropIndicator() {
        canvas.showDropIndicator(nil)
    }
}

extension NotePageSelection {
    var isBlockSelection: Bool {
        if case .blocks = self { return true }
        return false
    }
}

extension NoteTextField {
    var isCell: Bool {
        if case .cell = self { return true }
        return false
    }
}

private extension NoteMarks {
    var unlinked: NoteMarks {
        var value = self
        value.link = nil
        return value
    }
}

struct NotePastedLink: Hashable {
    var position: NotePosition
    var length: Int
    var url: URL
    var title: String?

    var end: NotePosition { NotePosition(position.block, position.offset + length, field: position.field) }
}

@MainActor
final class NotePasteLinkMenu {
    enum Choice: String { case dismiss, mention, bookmark, embed }

    let link: NotePastedLink
    let list: NoteMenuList
    private let panel: NoteFloatingPanel
    private let onChoose: (Choice) -> Void

    init(link: NotePastedLink, embeddable: Bool, onChoose: @escaping (Choice) -> Void) {
        self.link = link
        self.onChoose = onChoose
        let list = NoteMenuList()
        self.list = list
        var items: [NoteMenuList.Item] = [
            .init(id: Choice.dismiss.rawValue, title: "Dismiss", subtitle: "Keep it as a link", icon: .symbol("link"), section: "Paste as"),
            .init(id: Choice.mention.rawValue, title: "Mention", subtitle: "A tidy inline chip", icon: .symbol("at"), section: "Paste as"),
            .init(id: Choice.bookmark.rawValue, title: "Bookmark", subtitle: "A card with a preview", icon: .symbol("bookmark"), section: "Paste as"),
        ]
        if embeddable {
            items.append(.init(id: Choice.embed.rawValue, title: "Embed", subtitle: "Show it right in the page",
                               icon: .symbol("play.rectangle"), section: "Paste as"))
        }
        list.rowStyle = .detailed
        list.items = items
        list.prepare(origin: .keyboard)
        panel = NoteFloatingPanel(content: list)
        list.onActivate = { [weak self] item in
            guard let choice = Choice(rawValue: item.id) else { return }
            self?.onChoose(choice)
        }
        list.onCancel = { [weak self] in self?.onChoose(.dismiss) }
        list.setAccessibilityLabel("Paste link as")
    }

    func present(in host: NSView, anchor: NSRect) {
        panel.present(in: host, anchor: anchor, edge: .below, animated: true)
    }

    func dismiss() {
        panel.dismiss(animated: true)
    }
}
