import AppKit

extension NoteSelectionController {
    func handleTextCommand(_ selector: Selector, in host: NoteTextHost) -> Bool {
        guard !isTracking, !host.textView.hasMarkedText() else { return false }
        if case .cell = host.field { return false }
        if selector == #selector(NSResponder.cancelOperation(_:)), editor.slashMenu.isOpen { return false }
        return run(NSStringFromSelector(selector), on: sessionSelection(for: host), fromTextView: true)
    }

    func perform(_ selector: Selector) -> Bool {
        guard !isTracking else { return true }
        return run(NSStringFromSelector(selector), on: session.selection, fromTextView: false)
    }

    func selectAll() {
        if let view = canvas.window?.firstResponder as? NoteTextView, view.hasMarkedText() { return }
        selectAll(from: currentSelection())
    }

    private func selectAll(from selection: NotePageSelection) {
        let next = navigator().selectAllStep(selection, layout: layout)
        if let ids = next.selectedBlocks, let first = ids.first { blockRange = NoteBlockRange(anchor: first, head: ids.last ?? first) }
        goal.reset()
        select(next)
    }

    private func run(_ name: String, on selection: NotePageSelection, fromTextView: Bool) -> Bool {
        if name == "selectAll:" {
            selectAll(from: selection)
            return true
        }
        switch selection {
        case .text(let anchor, let head):
            return runText(name, anchor: anchor, head: head, fromTextView: fromTextView)
        case .blocks(let ids):
            return runBlocks(name, ids: ids)
        case .none, .cells:
            if fromTextView { return false }
            if Self.scrollCommands.contains(name) { scroll(name) }
            return true
        }
    }

    private func land(_ landing: NoteSelectionLanding) {
        switch landing {
        case .caret(let position):
            goal.moved(to: position)
            select(.caret(position))
        case .block(let id):
            transitBlock = id
            blockRange = NoteBlockRange(anchor: id, head: id)
            select(.blocks([id]))
        }
    }

    private func extendText(anchor: NotePosition, to head: NotePosition, keepGoal: Bool = false) {
        if keepGoal { goal.moved(to: head) } else { goal.reset() }
        select(.text(anchor: anchor, head: head))
    }

    private func goalX(for position: NotePosition) -> CGFloat {
        goal.value(for: position) { [layout] in layout.caretX(at: position) } ?? 0
    }

    private static let leftward: Set<String> = [
        "moveLeft:", "moveBackward:", "moveWordLeft:", "moveWordBackward:", "moveLeftAndModifySelection:", "moveBackwardAndModifySelection:",
        "moveWordLeftAndModifySelection:", "moveWordBackwardAndModifySelection:", "moveToBeginningOfLineAndModifySelection:",
        "moveToLeftEndOfLineAndModifySelection:", "moveToBeginningOfLine:", "moveToLeftEndOfLine:",
        "moveToBeginningOfParagraph:", "moveToBeginningOfParagraphAndModifySelection:", "moveParagraphBackwardAndModifySelection:",
    ]

    private static let deletions: Set<String> = [
        "deleteBackward:", "deleteForward:", "deleteWordBackward:", "deleteWordForward:", "deleteToBeginningOfLine:",
        "deleteToEndOfLine:", "deleteToBeginningOfParagraph:", "deleteToEndOfParagraph:",
        "deleteBackwardByDecomposingPreviousCharacter:", "delete:",
    ]

    private static let newlines: Set<String> = ["insertNewline:", "insertNewlineIgnoringFieldEditor:", "insertParagraphSeparator:"]

    static let scrollCommands: Set<String> = [
        "scrollPageUp:", "scrollPageDown:", "scrollToBeginningOfDocument:", "scrollToEndOfDocument:", "pageUp:", "pageDown:",
        "scrollLineUp:", "scrollLineDown:",
    ]

    private func runText(_ name: String, anchor: NotePosition, head: NotePosition, fromTextView: Bool) -> Bool {
        let nav = navigator()
        let single = anchor.block == head.block && anchor.field == head.field
        let (start, end) = nav.ordered(anchor, head)
        let collapsed = anchor == head
        let forward = !Self.leftward.contains(name)
        switch name {
        case "moveUp:", "moveDown:":
            let up = name == "moveUp:"
            let from = collapsed ? head : (up ? start : end)
            let x = goalX(for: from)
            if fromTextView, from.field == .body, layout.lineOffset(from: from, up: up, x: x) == nil,
               nav.caretNeighbour(of: from.block, forward: !up) == nil {
                return false
            }
            land(nav.verticalLanding(from: from, up: up, x: x, layout: layout))
            return true
        case "moveUpAndModifySelection:", "moveDownAndModifySelection:":
            let up = name == "moveUpAndModifySelection:"
            let next = nav.verticalHead(from: head, up: up, x: goalX(for: head), layout: layout)
            extendText(anchor: anchor, to: next, keepGoal: true)
            return true
        case "moveLeft:", "moveRight:", "moveBackward:", "moveForward:", "moveWordLeft:", "moveWordRight:", "moveWordBackward:", "moveWordForward:":
            let unit: NoteSelectionHorizontalUnit = name.hasPrefix("moveWord") ? .word : .character
            if !collapsed {
                if fromTextView && single { return false }
                goal.reset()
                select(.caret(forward ? end : start))
                return true
            }
            if name == "moveRight:" || name == "moveForward:", openEquation(at: head) { return true }
            guard let landing = nav.horizontalLanding(from: head, forward: forward, unit: unit, layout: layout) else { return !fromTextView }
            if fromTextView, case .caret(let position) = landing, position.block == head.block, position.field == head.field { return false }
            goal.reset()
            land(landing)
            return true
        case "moveLeftAndModifySelection:", "moveRightAndModifySelection:", "moveBackwardAndModifySelection:", "moveForwardAndModifySelection:":
            extendText(anchor: anchor, to: nav.horizontalHead(from: head, forward: forward, unit: .character, layout: layout))
            return true
        case "moveWordLeftAndModifySelection:", "moveWordRightAndModifySelection:", "moveWordBackwardAndModifySelection:", "moveWordForwardAndModifySelection:":
            extendText(anchor: anchor, to: nav.horizontalHead(from: head, forward: forward, unit: .word, layout: layout))
            return true
        case "moveToBeginningOfLineAndModifySelection:", "moveToLeftEndOfLineAndModifySelection:",
             "moveToEndOfLineAndModifySelection:", "moveToRightEndOfLineAndModifySelection:":
            extendText(anchor: anchor, to: NotePosition(head.block, layout.lineEdgeOffset(from: head, forward: forward), field: head.field))
            return true
        case "moveParagraphBackwardAndModifySelection:", "moveParagraphForwardAndModifySelection:":
            extendText(anchor: anchor, to: nav.paragraphHead(from: head, forward: forward, layout: layout))
            return true
        case "moveToBeginningOfParagraphAndModifySelection:", "moveToEndOfParagraphAndModifySelection:":
            extendText(anchor: anchor, to: NotePosition(head.block, paragraphEdge(of: head, forward: forward), field: head.field))
            return true
        case "moveToBeginningOfDocument:", "moveToEndOfDocument:":
            goal.reset()
            let beginning = name == "moveToBeginningOfDocument:"
            if let target = beginning ? nav.documentStart : nav.documentEnd(layout) {
                select(.caret(target))
            } else if let id = beginning ? nav.topLevel.first : nav.topLevel.last {
                select(.blocks([id]))
            }
            return true
        case "moveToBeginningOfDocumentAndModifySelection:", "moveToEndOfDocumentAndModifySelection:":
            let beginning = name == "moveToBeginningOfDocumentAndModifySelection:"
            guard head.field == .body, let target = beginning ? nav.documentStart : nav.documentEnd(layout) else { return true }
            extendText(anchor: anchor, to: target)
            return true
        case "cancelOperation:":
            let next = nav.escapeStep(.text(anchor: anchor, head: head))
            if let ids = next.selectedBlocks, let first = ids.first { blockRange = NoteBlockRange(anchor: first, head: ids.last ?? first) }
            goal.reset()
            select(next)
            return true
        default:
            guard !fromTextView else { return false }
            return runResponderText(name, anchor: anchor, head: head, forward: forward, nav: nav)
        }
    }

    private func openEquation(at position: NotePosition) -> Bool {
        guard !editor.isReadOnly, let text = session.page.text(of: position), position.offset >= 0, position.offset < text.length,
              case .equation = text.marks(at: position.offset).atom, let host = canvas.textHost(for: position) else { return false }
        let view = host.textView
        guard view.isEditable, !view.isEditingEquation else { return false }
        if view.window?.firstResponder !== view { editor.focus(position) }
        goal.reset()
        return view.editEquation(at: position.offset)
    }

    private func paragraphEdge(of position: NotePosition, forward: Bool) -> Int {
        let bounds = layout.paragraphBounds(at: position)
        return forward ? bounds.upperBound : bounds.lowerBound
    }

    private func runResponderText(_ name: String, anchor: NotePosition, head: NotePosition, forward: Bool, nav: NoteSelectionNavigator) -> Bool {
        if Self.deletions.contains(name) {
            guard !editor.isReadOnly else { return true }
            session.deleteSelection(.text(anchor: anchor, head: head))
            return true
        }
        if Self.newlines.contains(name) {
            guard !editor.isReadOnly else { return true }
            if let caret = session.deleteSelection(.text(anchor: anchor, head: head)) { session.splitBlock(at: caret) }
            return true
        }
        if Self.scrollCommands.contains(name) {
            scroll(name)
            return true
        }
        switch name {
        case "insertLineBreak:":
            typeText("\n")
        case "insertTab:", "insertBacktab:":
            guard !editor.isReadOnly else { return true }
            let ids = nav.covered(from: anchor, to: head)
            if name == "insertTab:" { session.indent(ids) } else { session.outdent(ids) }
        case "moveToBeginningOfLine:", "moveToLeftEndOfLine:", "moveToEndOfLine:", "moveToRightEndOfLine:":
            goal.reset()
            select(.caret(NotePosition(head.block, layout.lineEdgeOffset(from: head, forward: forward), field: head.field)))
        case "moveToBeginningOfParagraph:", "moveToEndOfParagraph:":
            goal.reset()
            select(.caret(NotePosition(head.block, paragraphEdge(of: head, forward: forward), field: head.field)))
        case "noop:", "complete:":
            break
        default:
            return false
        }
        return true
    }

    private func runBlocks(_ name: String, ids: [NoteBlockID]) -> Bool {
        let nav = navigator()
        if let transitBlock, ids == [transitBlock], let landing = transitLanding(name, from: transitBlock, nav: nav) {
            land(landing)
            return true
        }
        if Self.deletions.contains(name) {
            guard !editor.isReadOnly else { return true }
            session.deleteBlocks(ids)
            return true
        }
        if Self.newlines.contains(name) {
            enter(ids, nav: nav)
            return true
        }
        if Self.scrollCommands.contains(name) {
            scroll(name)
            return true
        }
        switch name {
        case "moveUp:", "moveDown:":
            guard let target = nav.step(from: ids, forward: name == "moveDown:") else { return true }
            blockRange = NoteBlockRange(anchor: target, head: target)
            select(.blocks([target]))
        case "moveUpAndModifySelection:", "moveDownAndModifySelection:":
            guard let first = ids.first else { return true }
            let range = nav.extend(blockRange ?? NoteBlockRange(anchor: first, head: ids.last ?? first), forward: name == "moveDownAndModifySelection:")
            blockRange = range
            select(.blocks(nav.blocks(from: range.anchor, to: range.head)))
        case "moveToBeginningOfDocument:", "moveToEndOfDocument:":
            guard let target = name == "moveToBeginningOfDocument:" ? nav.topLevel.first : nav.topLevel.last else { return true }
            blockRange = NoteBlockRange(anchor: target, head: target)
            select(.blocks([target]))
        case "moveToBeginningOfDocumentAndModifySelection:", "moveToEndOfDocumentAndModifySelection:":
            guard !editor.isReadOnly else { return true }
            session.moveBlocks(ids, name == "moveToBeginningOfDocumentAndModifySelection:" ? .up : .down)
        case "insertTab:":
            guard !editor.isReadOnly else { return true }
            session.indent(ids)
        case "insertBacktab:":
            guard !editor.isReadOnly else { return true }
            session.outdent(ids)
        case "cancelOperation:":
            blockRange = nil
            select(.none)
        case "insertLineBreak:":
            typeText("\n")
        case "moveLeft:", "moveRight:", "moveBackward:", "moveForward:", "noop:", "complete:":
            break
        default:
            return false
        }
        return true
    }

    private func transitLanding(_ name: String, from id: NoteBlockID, nav: NoteSelectionNavigator) -> NoteSelectionLanding? {
        let forward: Bool
        switch name {
        case "moveDown:", "moveRight:", "moveForward:": forward = true
        case "moveUp:", "moveLeft:", "moveBackward:": forward = false
        default: return nil
        }
        guard let next = nav.caretNeighbour(of: id, forward: forward) else { return nil }
        guard next.role == .text else { return .block(next.id) }
        if name == "moveUp:" || name == "moveDown:" {
            let x = goal.x ?? next.frame.minX
            let position = NotePosition(next.id, layout.entryOffset(in: next.id, x: x, fromAbove: forward))
            return .caret(position)
        }
        return .caret(NotePosition(next.id, forward ? 0 : layout.length(of: NotePosition(next.id, 0))))
    }

    private func enter(_ ids: [NoteBlockID], nav: NoteSelectionNavigator) {
        guard let id = blockRange?.head ?? ids.last, nav.role(of: id) == .text else { return }
        goal.reset()
        select(.caret(NotePosition(id, layout.length(of: NotePosition(id, 0)))))
    }

    private func scroll(_ name: String) {
        guard let scrollView = canvas.enclosingScrollView else { return }
        _ = scrollView.tryToPerform(NSSelectorFromString(name), with: nil)
    }

    func typeText(_ string: String) {
        guard !editor.isReadOnly, !string.isEmpty else { return }
        switch session.selection {
        case .blocks(let ids):
            replaceBlocks(ids, with: NoteText(string))
        case .text:
            session.insertText(NoteText(string))
        case .none, .cells:
            guard let target = compositionTarget(), let window = canvas.window else { return }
            goal.reset()
            editor.focus(target)
            guard let client = window.firstResponder as? NoteTextView, client !== responder else { return }
            client.insertText(string, replacementRange: NSRange(location: NSNotFound, length: 0))
        }
    }

    @discardableResult
    func replaceBlocks(_ ids: [NoteBlockID], with text: NoteText) -> NoteBlockID? {
        let targets = session.page.topLevelSelection(ids)
        guard let first = targets.first else { return nil }
        let paragraph = NoteBlock.paragraph(text)
        blockRange = nil
        session.edit("Typing", selection: .caret(NotePosition(paragraph.id, text.length))) { page in
            _ = page.insert([paragraph], .before(first))
            for id in targets { _ = page.remove(id) }
            page.collapseEmptyColumns()
        }
        return paragraph.id
    }

    func beginComposition(with event: NSEvent?, marked: Any, selectedRange: NSRange) {
        guard !editor.isReadOnly else { return }
        switch session.selection {
        case .blocks(let ids):
            replaceBlocks(ids, with: NoteText())
        case .text(let anchor, let head) where anchor != head:
            session.deleteSelection()
        default:
            break
        }
        guard let window = canvas.window else { return }
        if window.firstResponder === responder, let target = compositionTarget() {
            goal.reset()
            editor.focus(target)
            if window.firstResponder === responder { focusSelection() }
        }
        guard window.firstResponder !== responder else { return }
        if let event, event.type == .keyDown {
            window.postEvent(event, atStart: true)
        } else if let client = window.firstResponder as? NSTextInputClient {
            client.setMarkedText(marked, selectedRange: selectedRange, replacementRange: NSRange(location: NSNotFound, length: 0))
        }
    }

    private func compositionTarget() -> NotePosition? {
        let nav = navigator()
        switch session.selection {
        case .text(_, let head):
            if nav.role(of: head.block) == .text || head.field != .body { return head }
            return nearestText(to: head.block, nav: nav)
        case .blocks(let ids):
            guard let id = blockRange?.head ?? ids.last else { return documentFallback(nav) }
            return nearestText(to: id, nav: nav)
        case .cells(let table, _, let head):
            return NotePosition(table, 0, field: .cell(row: head.row, column: head.column))
        case .none:
            return documentFallback(nav)
        }
    }

    private func nearestText(to id: NoteBlockID, nav: NoteSelectionNavigator) -> NotePosition? {
        if nav.role(of: id) == .text { return NotePosition(id, layout.length(of: NotePosition(id, 0))) }
        if let previous = nav.textNeighbour(of: id, forward: false) {
            return NotePosition(previous.id, layout.length(of: NotePosition(previous.id, 0)))
        }
        if let next = nav.textNeighbour(of: id, forward: true) { return NotePosition(next.id, 0) }
        return documentFallback(nav)
    }

    private func documentFallback(_ nav: NoteSelectionNavigator) -> NotePosition? {
        if let end = nav.documentEnd(layout) { return end }
        let paragraph = NoteBlock.paragraph()
        let caret = NotePosition(paragraph.id, 0)
        session.insertBlocks([paragraph], .top(session.page.blocks.count), select: .caret(caret))
        return caret
    }
}
