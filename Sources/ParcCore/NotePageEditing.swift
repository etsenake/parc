import Foundation

enum NoteDropSide: Hashable { case left, right }

enum NoteMoveDirection: Hashable { case up, down }

extension NotePage {
    func text(of position: NotePosition) -> NoteText? {
        guard let block = block(position.block) else { return nil }
        return block.text(in: position.field)
    }

    func visibleTextOrder() -> [NoteBlockID] {
        flattened().map(\.id).filter { id in
            guard let block = block(id) else { return false }
            return block.kind.hasRichText || block.kind.hasPlainText
        }
    }

    func previousVisible(_ id: NoteBlockID) -> NoteBlockID? {
        let order = flattened().map(\.id)
        guard let index = order.firstIndex(of: id), index > 0 else { return nil }
        return order[index - 1]
    }

    func nextVisible(_ id: NoteBlockID) -> NoteBlockID? {
        let order = flattened().map(\.id)
        guard let index = order.firstIndex(of: id), index + 1 < order.count else { return nil }
        return order[index + 1]
    }

    func ordered(_ ids: some Sequence<NoteBlockID>) -> [NoteBlockID] {
        let wanted = Set(ids)
        return documentOrder().filter { wanted.contains($0) }
    }

    func topLevelSelection(_ ids: some Sequence<NoteBlockID>) -> [NoteBlockID] {
        let all = ordered(ids)
        return all.filter { id in !all.contains { $0 != id && isAncestor($0, of: id) } }
    }
}

extension NoteBlock {
    func text(in field: NoteTextField) -> NoteText? {
        switch field {
        case .body: return text
        case .caption: return props.caption
        case .cell(let row, let column):
            guard let table = props.table, table.rows.indices.contains(row), table.rows[row].indices.contains(column) else { return nil }
            return table.rows[row][column]
        }
    }

    mutating func setText(_ value: NoteText, in field: NoteTextField) {
        switch field {
        case .body: text = value
        case .caption: props.caption = value
        case .cell(let row, let column):
            guard var table = props.table, table.rows.indices.contains(row), table.rows[row].indices.contains(column) else { return }
            table.rows[row][column] = value
            props.table = table
        }
    }

    func converted(to kind: NoteBlockKind, configure: (inout NoteBlockProps) -> Void = { _ in }) -> NoteBlock {
        var copy = self
        if kind.hasPlainText && !self.kind.hasPlainText { copy.text = NoteText(text.plainText) }
        if !kind.hasRichText && !kind.hasPlainText && kind != .table { copy.text = NoteText() }
        copy.kind = kind
        if kind != .todo { copy.props.checked = false }
        if kind != .heading { copy.props.toggleable = false }
        if kind == .toggle || (kind == .heading && copy.props.toggleable) { copy.props.expanded = true }
        if kind == .callout && copy.props.icon == nil { copy.props.icon = "💡" }
        if kind == .table && copy.props.table == nil { copy.props.table = .empty() }
        configure(&copy.props)
        return copy
    }
}

extension NotePageSession {
    func setText(_ value: NoteText, of position: (block: NoteBlockID, field: NoteTextField), origin: AnyObject? = nil,
                 selection after: NotePageSelection? = nil) {
        guard page.block(position.block)?.text(in: position.field) != value else {
            if let after { setSelection(after, origin: origin) }
            return
        }
        edit("Typing", kind: .text, coalescing: .typing(position.block, position.field), affected: [position.block],
             origin: origin, selection: after) { page in
            page.update(position.block) { $0.setText(value, in: position.field) }
        }
    }

    func replaceText(at position: NotePosition, length: Int, with value: NoteText, origin: AnyObject? = nil) {
        guard var text = page.text(of: position) else { return }
        text.replace(position.offset..<(position.offset + length), with: value)
        let caret = NotePosition(position.block, position.offset + value.length, field: position.field)
        setText(text, of: (position.block, position.field), origin: origin, selection: .caret(caret))
    }

    @discardableResult
    func splitBlock(at position: NotePosition) -> NoteBlockID? {
        guard position.field == .body, let block = page.block(position.block), block.kind.hasRichText else { return nil }
        let text = block.text
        let offset = min(max(0, position.offset), text.length)
        if block.kind.isListItem || block.kind == .toggle || block.kind == .quote || block.kind == .callout,
           text.isEmpty, block.children.isEmpty {
            if page.parent(of: block.id) != nil, block.kind.isListItem { return outdent([block.id]) ? block.id : nil }
            turnInto([block.id], kind: .paragraph)
            return block.id
        }
        var fresh = NoteBlock(.paragraph)
        switch block.kind {
        case .bulletedItem, .numberedItem, .todo:
            fresh.kind = block.kind
            fresh.props.bulletMarker = block.props.bulletMarker
            fresh.props.orderedDelimiter = block.props.orderedDelimiter
        case .toggle:
            fresh.kind = block.props.expanded ? .paragraph : .toggle
        default:
            break
        }
        if offset == 0 && !text.isEmpty {
            var above = fresh
            above.kind = block.kind == .heading ? .paragraph : fresh.kind
            if block.kind == .heading { above = NoteBlock(.paragraph) }
            edit("New Block", selection: .caret(NotePosition(block.id, 0))) { page in
                page.insert([above], .before(block.id))
            }
            return above.id
        }
        fresh.text = text.slice(offset..<text.length)
        let head = text.slice(0..<offset)
        let intoChildren = block.isToggle ? block.props.expanded : (!block.children.isEmpty && block.acceptsChildren)
        edit("New Block", selection: .caret(NotePosition(fresh.id, 0))) { page in
            page.update(block.id) { $0.text = head }
            if intoChildren {
                if block.kind.isListItem && block.children.first.map({ !$0.kind.isListItem }) == true { fresh.kind = .paragraph }
                page.insert([fresh], .firstChild(of: block.id))
            } else {
                page.insert([fresh], .after(block.id))
            }
        }
        return fresh.id
    }

    @discardableResult
    func mergeBackward(_ id: NoteBlockID) -> Bool {
        guard let block = page.block(id) else { return false }
        if block.kind != .paragraph && block.kind.hasRichText {
            turnInto([id], kind: .paragraph)
            return true
        }
        if let parent = page.parent(of: id), page.block(parent)?.kind != .column {
            if page.siblings(of: id).last?.id == id || !(page.block(id)?.acceptsChildren ?? false) {
                if outdent([id]) { return true }
            }
        }
        guard let previousID = page.previousVisible(id), let previous = page.block(previousID) else { return false }
        if !(previous.kind.hasRichText || previous.kind.hasPlainText) {
            if block.text.isEmpty && block.children.isEmpty {
                edit("Delete", selection: .blocks([previousID])) { page in page.remove(id) }
            } else {
                setSelection(.blocks([previousID]))
            }
            return true
        }
        let joinOffset = previous.text.length
        let appended = previous.kind.hasPlainText ? NoteText(block.text.plainText) : block.text
        edit("Delete", selection: .caret(NotePosition(previousID, joinOffset))) { page in
            guard let removed = page.remove(id) else { return }
            page.update(previousID) { $0.text.append(appended) }
            guard !removed.children.isEmpty else { return }
            if page.block(previousID)?.acceptsChildren == true { page.insert(removed.children, .lastChild(of: previousID)) }
            else { page.insert(removed.children, .after(previousID)) }
        }
        return true
    }

    func mergeForward(_ id: NoteBlockID) {
        guard let next = page.nextVisible(id), let nextBlock = page.block(next) else { return }
        if nextBlock.kind.hasRichText || nextBlock.kind.hasPlainText { mergeBackward(next) }
        else { setSelection(.blocks([next])) }
    }

    @discardableResult
    func indent(_ ids: [NoteBlockID]) -> Bool {
        let targets = page.topLevelSelection(ids)
        guard let first = targets.first else { return false }
        let siblings = page.siblings(of: first)
        guard let index = siblings.firstIndex(where: { $0.id == first }), index > 0 else { return false }
        let parentID = siblings[index - 1].id
        guard page.block(parentID)?.acceptsChildren == true,
              targets.allSatisfy({ id in page.siblings(of: id).contains { $0.id == parentID } }) else { return false }
        let caret = selection
        edit("Indent", selection: caret) { page in
            var moved: [NoteBlock] = []
            for id in targets { if let block = page.remove(id) { moved.append(block) } }
            page.update(parentID) { parent in
                parent.children.append(contentsOf: moved)
                if parent.isToggle { parent.props.expanded = true }
            }
        }
        return true
    }

    @discardableResult
    func outdent(_ ids: [NoteBlockID]) -> Bool {
        let targets = page.topLevelSelection(ids)
        guard let first = targets.first, let parentID = page.parent(of: first),
              targets.allSatisfy({ page.parent(of: $0) == parentID }),
              let parent = page.block(parentID), parent.kind != .column else { return false }
        guard let last = targets.last, let lastIndex = parent.children.firstIndex(where: { $0.id == last }) else { return false }
        let trailing = Array(parent.children[(lastIndex + 1)...])
        let lastBlock = page.block(last)
        if !trailing.isEmpty && lastBlock?.acceptsChildren != true { return false }
        let caret = selection
        edit("Outdent", selection: caret) { page in
            var moved: [NoteBlock] = []
            for id in targets { if let block = page.remove(id) { moved.append(block) } }
            for block in trailing { page.remove(block.id) }
            if !trailing.isEmpty, !moved.isEmpty { moved[moved.count - 1].children.append(contentsOf: trailing) }
            page.insert(moved, .after(parentID))
        }
        return true
    }

    func turnInto(_ ids: [NoteBlockID], kind: NoteBlockKind, configure: @escaping (inout NoteBlockProps) -> Void = { _ in }) {
        let targets = page.ordered(ids)
        guard !targets.isEmpty else { return }
        let caret = selection
        edit("Turn Into", selection: caret) { page in
            for id in targets {
                guard let block = page.block(id) else { continue }
                var converted = block.converted(to: kind, configure: configure)
                let lifted = converted.acceptsChildren ? [] : converted.children
                if !lifted.isEmpty { converted.children = [] }
                page.update(id) { $0 = converted }
                if !lifted.isEmpty { page.insert(lifted, .after(id)) }
            }
        }
    }

    func updateBlock(_ id: NoteBlockID, name: String = "Change", _ transform: @escaping (inout NoteBlock) -> Void) {
        edit(name, affected: [id], selection: selection) { page in page.update(id, transform) }
    }

    func updateSettings(name: String = "Page Settings", _ transform: (inout NotePageSettings) -> Void) {
        edit(name, kind: .settings, affected: [], selection: selection) { page in transform(&page.settings) }
    }

    @discardableResult
    func insertBlocks(_ blocks: [NoteBlock], _ position: NoteInsertion, select: NotePageSelection? = nil) -> [NoteBlockID] {
        guard !blocks.isEmpty else { return [] }
        let after = select ?? (blocks.last.map { block -> NotePageSelection in
            block.kind.hasRichText || block.kind.hasPlainText ? .caret(NotePosition(block.id, block.text.length)) : .blocks([block.id])
        } ?? selection)
        edit("Insert", selection: after) { page in page.insert(blocks, position) }
        return blocks.map(\.id)
    }

    func deleteBlocks(_ ids: [NoteBlockID]) {
        let targets = page.topLevelSelection(ids)
        guard let first = targets.first else { return }
        let order = page.flattened().map(\.id)
        let removed = Set(targets)
        let landing = order[..<(order.firstIndex(of: first) ?? 0)].last { id in
            !removed.contains(id) && !targets.contains { page.isAncestor($0, of: id) }
        }
        var next: NotePageSelection = .none
        if let landing, let block = page.block(landing) {
            next = block.kind.hasRichText || block.kind.hasPlainText ? .caret(NotePosition(landing, block.text.length)) : .blocks([landing])
        }
        edit("Delete", selection: next) { page in
            for id in targets { page.remove(id) }
            page.collapseEmptyColumns()
        }
        if page.blocks.count == 1, page.blocks[0].kind == .paragraph, page.blocks[0].text.isEmpty, next == .none {
            setSelection(.caret(NotePosition(page.blocks[0].id, 0)))
        }
    }

    @discardableResult
    func duplicateBlocks(_ ids: [NoteBlockID]) -> [NoteBlockID] {
        let targets = page.topLevelSelection(ids)
        guard let last = targets.last else { return [] }
        let copies = targets.compactMap { page.block($0)?.withFreshIDs() }
        edit("Duplicate", selection: .blocks(copies.map(\.id))) { page in page.insert(copies, .after(last)) }
        return copies.map(\.id)
    }

    func moveBlocks(_ ids: [NoteBlockID], to position: NoteInsertion) {
        let targets = page.topLevelSelection(ids)
        guard !targets.isEmpty else { return }
        switch position {
        case .before(let anchor), .after(let anchor), .firstChild(let anchor), .lastChild(let anchor):
            if targets.contains(anchor) || targets.contains(where: { page.isAncestor($0, of: anchor) }) { return }
        case .top:
            break
        }
        let caret = selection
        edit("Move", selection: caret) { page in
            var moved: [NoteBlock] = []
            for id in targets { if let block = page.remove(id) { moved.append(block) } }
            page.insert(moved, position)
            page.collapseEmptyColumns()
        }
    }

    func moveBlocks(_ ids: [NoteBlockID], _ direction: NoteMoveDirection) {
        let targets = page.topLevelSelection(ids)
        guard let first = targets.first, let last = targets.last else { return }
        let siblings = page.siblings(of: first)
        guard let firstIndex = siblings.firstIndex(where: { $0.id == first }),
              let lastIndex = siblings.firstIndex(where: { $0.id == last }) else { return }
        switch direction {
        case .up:
            if firstIndex > 0 { moveBlocks(targets, to: .before(siblings[firstIndex - 1].id)) }
            else if let parent = page.parent(of: first), page.block(parent)?.kind != .column { moveBlocks(targets, to: .before(parent)) }
        case .down:
            if lastIndex + 1 < siblings.count { moveBlocks(targets, to: .after(siblings[lastIndex + 1].id)) }
            else if let parent = page.parent(of: last), page.block(parent)?.kind != .column { moveBlocks(targets, to: .after(parent)) }
        }
    }

    func placeBeside(_ ids: [NoteBlockID], target: NoteBlockID, side: NoteDropSide) {
        let moving = page.topLevelSelection(ids)
        guard !moving.isEmpty, !moving.contains(target), !moving.contains(where: { page.isAncestor($0, of: target) }) else { return }
        let caret = selection
        edit("Move", selection: caret) { page in
            var moved: [NoteBlock] = []
            for id in moving { if let block = page.remove(id) { moved.append(block) } }
            if let parentID = page.parent(of: target), page.block(parentID)?.kind == .column,
               let columnsID = page.parent(of: parentID), let columns = page.block(columnsID), columns.children.count < 5 {
                let column = NoteBlock(.column, children: moved)
                page.insert([column], side == .left ? .before(parentID) : .after(parentID))
                page.update(columnsID) { block in for index in block.children.indices { block.children[index].props.width = nil } }
            } else {
                guard let original = page.block(target) else { return }
                let targetColumn = NoteBlock(.column, children: [original])
                let movedColumn = NoteBlock(.column, children: moved)
                let columns = NoteBlock(.columns, children: side == .left ? [movedColumn, targetColumn] : [targetColumn, movedColumn])
                page.update(target) { $0 = columns }
            }
            page.collapseEmptyColumns()
        }
    }

    func toggleExpanded(_ id: NoteBlockID) {
        guard let block = page.block(id), block.isToggle else { return }
        updateBlock(id, name: block.props.expanded ? "Collapse" : "Expand") { $0.props.expanded.toggle() }
    }

    func setAllToggles(expanded: Bool) {
        let ids = page.allBlocks().filter(\.isToggle).map(\.id)
        guard !ids.isEmpty else { return }
        edit(expanded ? "Expand All" : "Collapse All", affected: Set(ids), selection: selection) { page in
            for id in ids { page.update(id) { $0.props.expanded = expanded } }
        }
    }

    func toggleChecked(_ ids: [NoteBlockID]) {
        let todos = page.ordered(ids).filter { page.block($0)?.kind == .todo }
        guard !todos.isEmpty else { return }
        let value = !todos.allSatisfy { page.block($0)?.props.checked == true }
        edit(value ? "Check" : "Uncheck", affected: Set(todos), selection: selection) { page in
            for id in todos { page.update(id) { $0.props.checked = value } }
        }
    }

    func textSegments(of value: NotePageSelection) -> [(position: NotePosition, range: Range<Int>)] {
        switch value {
        case .none, .cells: return []
        case .blocks(let ids):
            return page.ordered(ids).compactMap { id in
                guard let block = page.block(id), block.kind.hasRichText else { return nil }
                return (NotePosition(id, 0), 0..<block.text.length)
            }
        case .text(let anchor, let head):
            let (start, end) = orderedEnds(anchor, head)
            if start.block == end.block && start.field == end.field {
                return [(start, start.offset..<end.offset)]
            }
            let order = page.visibleTextOrder()
            guard let from = order.firstIndex(of: start.block), let to = order.firstIndex(of: end.block), from <= to else { return [] }
            return order[from...to].compactMap { id in
                guard let block = page.block(id) else { return nil }
                let length = block.text.length
                let lower = id == start.block ? start.offset : 0
                let upper = id == end.block ? end.offset : length
                return (NotePosition(id, lower), lower..<max(lower, upper))
            }
        }
    }

    func orderedEnds(_ anchor: NotePosition, _ head: NotePosition) -> (NotePosition, NotePosition) {
        if anchor.block == head.block && anchor.field == head.field {
            return anchor.offset <= head.offset ? (anchor, head) : (head, anchor)
        }
        let order = page.visibleTextOrder()
        let a = order.firstIndex(of: anchor.block) ?? 0, h = order.firstIndex(of: head.block) ?? 0
        return a <= h ? (anchor, head) : (head, anchor)
    }

    func hasMark(_ key: NoteMarkKey, in value: NotePageSelection? = nil) -> Bool {
        let segments = textSegments(of: value ?? selection).filter { !$0.range.isEmpty }
        guard !segments.isEmpty else { return false }
        return segments.allSatisfy { segment in
            page.block(segment.position.block)?.text(in: segment.position.field)?.allHave(key, in: segment.range) ?? false
        }
    }

    func toggleMark(_ key: NoteMarkKey, in value: NotePageSelection? = nil) {
        let target = value ?? selection
        let enable = !hasMark(key, in: target)
        updateMarks(in: target, name: key.rawValue.capitalized) { $0[key] = enable }
    }

    func setLink(_ url: String?, in value: NotePageSelection? = nil) {
        updateMarks(in: value ?? selection, name: url == nil ? "Remove Link" : "Link") { $0.link = url }
    }

    func setColor(_ style: NoteColorStyle?, in value: NotePageSelection? = nil) {
        let target = value ?? selection
        if case .blocks(let ids) = target {
            edit("Color", affected: Set(ids), selection: target) { page in
                for id in ids { page.update(id) { $0.color = style } }
            }
            return
        }
        updateMarks(in: target, name: "Color") { $0.color = style }
    }

    func updateMarks(in value: NotePageSelection, name: String, _ transform: @escaping (inout NoteMarks) -> Void) {
        let segments = textSegments(of: value).filter { !$0.range.isEmpty }
        guard !segments.isEmpty else { return }
        edit(name, kind: .text, affected: Set(segments.map(\.position.block)), selection: value) { page in
            for segment in segments {
                page.update(segment.position.block) { block in
                    guard var text = block.text(in: segment.position.field), block.kind.hasRichText || segment.position.field != .body else { return }
                    text.updateMarks(in: segment.range, transform)
                    block.setText(text, in: segment.position.field)
                }
            }
        }
    }

    @discardableResult
    func deleteSelection(_ value: NotePageSelection? = nil) -> NotePosition? {
        let target = value ?? selection
        switch target {
        case .none: return nil
        case .cells(let table, let anchor, let head):
            let rows = min(anchor.row, head.row)...max(anchor.row, head.row)
            let columns = min(anchor.column, head.column)...max(anchor.column, head.column)
            updateBlock(table, name: "Clear Cells") { block in
                guard var grid = block.props.table else { return }
                for row in rows where grid.rows.indices.contains(row) {
                    for column in columns where grid.rows[row].indices.contains(column) { grid.rows[row][column] = NoteText() }
                }
                block.props.table = grid
            }
            return nil
        case .blocks(let ids):
            deleteBlocks(ids)
            return selection.caret
        case .text(let anchor, let head):
            let (start, end) = orderedEnds(anchor, head)
            if start == end { return start }
            if start.block == end.block && start.field == end.field {
                replaceText(at: start, length: end.offset - start.offset, with: NoteText())
                return start
            }
            let order = page.visibleTextOrder()
            guard let from = order.firstIndex(of: start.block), let to = order.firstIndex(of: end.block) else { return nil }
            let middle = Array(order[(from + 1)..<to])
            guard let endBlock = page.block(end.block) else { return nil }
            let tail = endBlock.text.slice(end.offset..<endBlock.text.length)
            edit("Delete", selection: .caret(start)) { page in
                page.update(start.block) { block in
                    var text = block.text
                    text.replace(start.offset..<text.length, with: block.kind.hasPlainText ? NoteText(tail.plainText) : tail)
                    block.text = text
                }
                for id in middle where !page.isAncestor(id, of: start.block) { page.remove(id) }
                if let removed = page.remove(end.block), !removed.children.isEmpty {
                    if page.block(start.block)?.acceptsChildren == true { page.insert(removed.children, .lastChild(of: start.block)) }
                    else { page.insert(removed.children, .after(start.block)) }
                }
                page.collapseEmptyColumns()
            }
            return start
        }
    }

    func insertText(_ value: NoteText, replacing target: NotePageSelection? = nil) {
        guard let caret = deleteSelection(target ?? selection) else { return }
        guard let text = page.text(of: caret) else { return }
        var inserted = value
        if inserted.spans.allSatisfy({ $0.marks.isPlain }) { inserted = NoteText(value.string, marks: text.typingMarks(at: caret.offset)) }
        replaceText(at: caret, length: 0, with: inserted)
    }

    func fragment(of value: NotePageSelection? = nil) -> [NoteBlock] {
        let target = value ?? selection
        switch target {
        case .none: return []
        case .blocks(let ids):
            return page.topLevelSelection(ids).compactMap { page.block($0)?.withFreshIDs() }
        case .cells(let table, let anchor, let head):
            guard let grid = page.block(table)?.props.table else { return [] }
            let rows = min(anchor.row, head.row)...max(anchor.row, head.row)
            let columns = min(anchor.column, head.column)...max(anchor.column, head.column)
            let picked = rows.compactMap { row in grid.rows.indices.contains(row)
                ? columns.compactMap { grid.rows[row].indices.contains($0) ? grid.rows[row][$0] : nil } : nil }
            var props = NoteBlockProps()
            props.table = NoteTable(rows: picked, headerRow: false)
            return [NoteBlock(.table, props: props)]
        case .text:
            return textSegments(of: target).compactMap { segment -> NoteBlock? in
                guard let block = page.block(segment.position.block), let text = block.text(in: segment.position.field) else { return nil }
                var copy = NoteBlock(segment.position.field == .body ? block.kind : .paragraph, text: text.slice(segment.range),
                                     props: segment.position.field == .body ? block.props : NoteBlockProps(), color: block.color)
                copy.props.caption = NoteText()
                return copy
            }
        }
    }

    func paste(_ blocks: [NoteBlock], replacing target: NotePageSelection? = nil) {
        guard !blocks.isEmpty else { return }
        let fresh = blocks.map { $0.withFreshIDs() }
        if case .blocks(let ids) = target ?? selection, let last = page.ordered(ids).last {
            insertBlocks(fresh, .after(last))
            return
        }
        guard let caret = deleteSelection(target ?? selection), let host = page.block(caret.block) else {
            insertBlocks(fresh, .top(page.blocks.count))
            return
        }
        if caret.field != .body || host.kind.hasPlainText {
            let joined = fresh.map { $0.text.plainText }.joined(separator: "\n")
            replaceText(at: caret, length: 0, with: caret.field == .body && host.kind.hasPlainText ? NoteText(joined) : NoteText(joined.replacingOccurrences(of: "\n", with: " ")))
            return
        }
        if fresh.count == 1, fresh[0].kind.hasRichText, fresh[0].children.isEmpty {
            replaceText(at: caret, length: 0, with: fresh[0].text)
            return
        }
        let head = host.text.slice(0..<caret.offset), tail = host.text.slice(caret.offset..<host.text.length)
        var inserted = fresh
        var mergedFirst = false
        if let first = inserted.first, first.kind.hasRichText, first.children.isEmpty {
            mergedFirst = true
            inserted.removeFirst()
        }
        var landing = NotePosition(host.id, head.length + (mergedFirst ? fresh[0].text.length : 0))
        var tailBlock: NoteBlock?
        if !tail.isEmpty {
            if let last = inserted.last, last.kind.hasRichText, last.children.isEmpty {
                inserted[inserted.count - 1].text.append(tail)
                landing = NotePosition(last.id, last.text.length)
            } else {
                tailBlock = NoteBlock(host.kind == .heading ? .paragraph : host.kind, text: tail)
            }
        } else if let last = inserted.last {
            landing = last.kind.hasRichText || last.kind.hasPlainText ? NotePosition(last.id, last.text.length) : landing
        }
        let caretSelection = NotePageSelection.caret(landing)
        edit("Paste", selection: caretSelection) { page in
            page.update(host.id) { block in
                block.text = mergedFirst ? head + fresh[0].text : head
            }
            var extras = inserted
            if let tailBlock { extras.append(tailBlock) }
            page.insert(extras, .after(host.id))
            if host.text.isEmpty, !mergedFirst, extras.count > 0, host.children.isEmpty, host.kind == .paragraph {
                page.remove(host.id)
            }
        }
        if page.block(landing.block) == nil, let last = inserted.last { setSelection(.blocks([last.id])) }
    }

    func updateTable(_ id: NoteBlockID, name: String = "Edit Table", _ transform: @escaping (inout NoteTable) -> Void) {
        updateBlock(id, name: name) { block in
            guard var table = block.props.table else { return }
            transform(&table)
            table.normalize()
            block.props.table = table
        }
    }
}

extension NotePage {
    mutating func collapseEmptyColumns() {
        func clean(_ list: [NoteBlock]) -> [NoteBlock] {
            var result: [NoteBlock] = []
            for var block in list {
                block.children = clean(block.children)
                if block.kind == .column && block.children.isEmpty { continue }
                if block.kind == .columns {
                    block.children = block.children.filter { $0.kind == .column && !$0.children.isEmpty }
                    if block.children.isEmpty { continue }
                    if block.children.count == 1 { result.append(contentsOf: block.children[0].children); continue }
                }
                result.append(block)
            }
            return result
        }
        blocks = clean(blocks)
        if blocks.isEmpty { blocks = [.paragraph()] }
    }
}
