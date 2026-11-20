import Foundation

enum NoteDropSide: Hashable { case left, right }

enum NoteMoveDirection: Hashable { case up, down }

enum NoteBlockConversion: Hashable {
    case text
    case heading(Int)
    case toggleHeading(Int)
    case bulletedList
    case numberedList
    case todo
    case toggle
    case quote
    case callout
    case code
    case equation
    case divider

    static let turnIntoChoices: [NoteBlockConversion] = [
        .text, .heading(1), .heading(2), .heading(3), .heading(4), .bulletedList, .numberedList, .todo, .toggle,
        .code, .quote, .callout, .equation, .toggleHeading(1), .toggleHeading(2), .toggleHeading(3), .toggleHeading(4),
    ]

    var kind: NoteBlockKind {
        switch self {
        case .text: return .paragraph
        case .heading, .toggleHeading: return .heading
        case .bulletedList: return .bulletedItem
        case .numberedList: return .numberedItem
        case .todo: return .todo
        case .toggle: return .toggle
        case .quote: return .quote
        case .callout: return .callout
        case .code: return .code
        case .equation: return .equation
        case .divider: return .divider
        }
    }

    func configure(_ props: inout NoteBlockProps, from source: NoteBlock) {
        switch self {
        case .heading(let level):
            props.level = min(max(level, 1), 6)
            props.toggleable = source.kind == .toggle
        case .toggleHeading(let level):
            props.level = min(max(level, 1), 6)
            if !props.toggleable { props.expanded = source.isToggle ? source.props.expanded : true }
            props.toggleable = true
        default:
            break
        }
    }
}

extension NotePage {
    func text(of position: NotePosition) -> NoteText? {
        guard let block = block(position.block) else { return nil }
        return block.text(in: position.field)
    }

    func visibleTextOrder() -> [NoteBlockID] {
        index.visibleIDs.filter { block($0)?.kind.hasText == true }
    }

    func previousVisible(_ id: NoteBlockID) -> NoteBlockID? {
        guard let position = visiblePosition(of: id), position > 0 else { return nil }
        return index.visibleIDs[position - 1]
    }

    func nextVisible(_ id: NoteBlockID) -> NoteBlockID? {
        guard let position = visiblePosition(of: id), position + 1 < index.visibleIDs.count else { return nil }
        return index.visibleIDs[position + 1]
    }

    func previousContent(before id: NoteBlockID) -> NoteBlockID? {
        guard var position = visiblePosition(of: id) else { return nil }
        let boundary = containingColumn(of: id)
        let order = index.visibleIDs
        while position > 0 {
            position -= 1
            guard let candidate = block(order[position]) else { continue }
            if candidate.kind.isColumnStructure { continue }
            return containingColumn(of: candidate.id) == boundary ? candidate.id : nil
        }
        return nil
    }

    func nextContent(after id: NoteBlockID) -> NoteBlockID? {
        guard var position = visiblePosition(of: id) else { return nil }
        let boundary = containingColumn(of: id)
        let order = index.visibleIDs
        while position + 1 < order.count {
            position += 1
            guard let candidate = block(order[position]) else { continue }
            if candidate.kind.isColumnStructure { continue }
            return containingColumn(of: candidate.id) == boundary ? candidate.id : nil
        }
        return nil
    }

    func ordered(_ ids: some Sequence<NoteBlockID>) -> [NoteBlockID] {
        var seen = Set<NoteBlockID>()
        let unique = ids.filter { contains($0) && seen.insert($0).inserted }
        return unique.sorted { (documentPosition(of: $0) ?? 0) < (documentPosition(of: $1) ?? 0) }
    }

    func topLevelSelection(_ ids: some Sequence<NoteBlockID>) -> [NoteBlockID] {
        let all = ordered(ids)
        let wanted = Set(all)
        return all.filter { id in !ancestors(of: id).contains(where: wanted.contains) }
    }

    func caretSelection(atEndOf id: NoteBlockID) -> NotePageSelection {
        guard let block = block(id) else { return .none }
        return block.kind.hasText ? .caret(NotePosition(id, block.text.length)) : .blocks([id])
    }

    func caretSelection(atStartOf id: NoteBlockID) -> NotePageSelection {
        guard let block = block(id) else { return .none }
        return block.kind.hasText ? .caret(NotePosition(id, 0)) : .blocks([id])
    }

    func clamped(_ selection: NotePageSelection) -> NotePageSelection {
        func clamp(_ position: NotePosition) -> NotePosition? {
            guard let text = text(of: position) else { return nil }
            return NotePosition(position.block, min(max(0, position.offset), text.length), field: position.field)
        }
        switch selection {
        case .none: return .none
        case .text(let anchor, let head):
            guard let anchor = clamp(anchor), let head = clamp(head) else {
                return [anchor.block, head.block].first(where: contains).map { .blocks([$0]) } ?? .none
            }
            return .text(anchor: anchor, head: head)
        case .blocks(let ids):
            let kept = ids.filter(contains)
            return kept.isEmpty ? .none : .blocks(kept)
        case .cells(let table, let anchor, let head):
            guard let grid = block(table)?.props.table else { return .none }
            func fit(_ cell: NoteTableCell) -> NoteTableCell {
                NoteTableCell(row: min(max(0, cell.row), grid.rowCount - 1), column: min(max(0, cell.column), grid.columnCount - 1))
            }
            return .cells(table: table, anchor: fit(anchor), head: fit(head))
        }
    }

    func fieldOrder(_ field: NoteTextField) -> (Int, Int, Int) {
        switch field {
        case .body: return (0, 0, 0)
        case .cell(let row, let column): return (1, row, column)
        case .caption: return (2, 0, 0)
        }
    }

    func precedes(_ lhs: NotePosition, _ rhs: NotePosition) -> Bool {
        if lhs.block != rhs.block {
            return (documentPosition(of: lhs.block) ?? 0) < (documentPosition(of: rhs.block) ?? 0)
        }
        if lhs.field != rhs.field {
            let left = fieldOrder(lhs.field), right = fieldOrder(rhs.field)
            return (left.0, left.1, left.2) < (right.0, right.1, right.2)
        }
        return lhs.offset < rhs.offset
    }

    @discardableResult
    mutating func merge(_ id: NoteBlockID, into targetID: NoteBlockID) -> Bool {
        guard id != targetID, let merged = block(id), let target = block(targetID), target.kind.hasText,
              !isAncestor(id, of: targetID) else { return false }
        let appended: NoteText
        if target.kind.hasPlainText { appended = NoteText(merged.text.plainText) }
        else if merged.kind.hasPlainText { appended = NoteText(merged.text.string) }
        else { appended = merged.text }
        let parentID = parent(of: id)
        let siblings = siblings(of: id)
        guard let position = siblings.firstIndex(where: { $0.id == id }) else { return false }
        let previousSibling = position > 0 ? siblings[position - 1] : nil
        let nextSibling = position + 1 < siblings.count ? siblings[position + 1] : nil
        remove(id)
        if !merged.children.isEmpty {
            if let previousSibling, previousSibling.acceptsChildren, previousSibling.showsChildren, !previousSibling.kind.isColumnStructure {
                insert(merged.children, .lastChild(of: previousSibling.id))
            } else if let nextSibling {
                insert(merged.children, .before(nextSibling.id))
            } else if let parentID {
                insert(merged.children, .lastChild(of: parentID))
            } else {
                insert(merged.children, .top(blocks.count))
            }
        }
        update(targetID) { $0.text.append(appended) }
        return true
    }

    @discardableResult
    mutating func convertBlock(_ id: NoteBlockID, to kind: NoteBlockKind, configure: (inout NoteBlockProps) -> Void = { _ in }) -> Bool {
        guard let block = block(id), !block.kind.isColumnStructure, !kind.isColumnStructure else { return false }
        var converted = block.converted(to: kind, configure: configure)
        let lifted = converted.acceptsChildren ? [] : converted.children
        if !lifted.isEmpty { converted.children = [] }
        update(id) { $0 = converted }
        if !lifted.isEmpty { insert(lifted, .after(id)) }
        return true
    }

    @discardableResult
    mutating func convertBlock(_ id: NoteBlockID, to conversion: NoteBlockConversion) -> Bool {
        guard let source = block(id) else { return false }
        return convertBlock(id, to: conversion.kind) { conversion.configure(&$0, from: source) }
    }

    @discardableResult
    mutating func deleteRange(from start: NotePosition, to end: NotePosition) -> Bool {
        guard start.block != end.block, let startBlock = block(start.block), let endBlock = block(end.block),
              let startOrder = visiblePosition(of: start.block), let endOrder = visiblePosition(of: end.block),
              startOrder < endOrder else { return false }
        let order = index.visibleIDs
        let between = order[(startOrder + 1)..<endOrder].filter { id in
            guard let block = block(id) else { return false }
            return !block.kind.isColumnStructure && !isAncestor(id, of: start.block)
        }
        let mergesText = start.field == .body && end.field == .body && startBlock.kind.hasText && endBlock.kind.hasText
        var removed = Set(between)
        if mergesText { removed.insert(end.block) }
        var touched = removed
        for id in removed { touched.formUnion(ancestors(of: id)) }
        let adoptsChildren = mergesText && startBlock.acceptsChildren && startBlock.showsChildren && !isAncestor(start.block, of: end.block)
        let adopted = adoptsChildren ? endBlock.children : []
        func prune(_ list: [NoteBlock]) -> [NoteBlock] {
            var result: [NoteBlock] = []
            result.reserveCapacity(list.count)
            for var block in list {
                guard touched.contains(block.id) else { result.append(block); continue }
                if removed.contains(block.id) {
                    if block.id == end.block {
                        if !adoptsChildren { result.append(contentsOf: prune(block.children)) }
                    } else if !block.isCollapsed {
                        result.append(contentsOf: prune(block.children))
                    }
                } else {
                    block.children = prune(block.children)
                    result.append(block)
                }
            }
            return result
        }
        if mergesText {
            let startText = startBlock.text
            let tail = endBlock.text.slice(end.offset..<endBlock.text.length)
            let joined: NoteText
            if startBlock.kind.hasPlainText { joined = NoteText(tail.plainText) }
            else if endBlock.kind.hasPlainText { joined = NoteText(tail.string) }
            else { joined = tail }
            blocks = prune(blocks)
            update(start.block) { block in
                block.text = startText.slice(0..<start.offset) + joined
                if block.isCollapsed { block.children = [] }
                if adoptsChildren { block.children = adopted + block.children }
            }
        } else {
            blocks = prune(blocks)
            update(start.block) { block in
                if block.isCollapsed { block.children = [] }
                guard var text = block.text(in: start.field) else { return }
                text.delete(start.offset..<text.length)
                block.setText(text, in: start.field)
            }
            update(end.block) { block in
                guard var text = block.text(in: end.field) else { return }
                text.delete(0..<end.offset)
                block.setText(text, in: end.field)
            }
        }
        collapseEmptyColumns()
        return true
    }

    func textFragment(from start: NotePosition, to end: NotePosition) -> [NoteBlock] {
        guard let first = visiblePosition(of: start.block), let last = visiblePosition(of: end.block), first <= last else { return [] }
        let range = index.visibleIDs[first...last].filter { block($0).map { !$0.kind.isColumnStructure } ?? false }
        let inRange = Set(range)
        var nodes: [NoteBlockID: NoteBlock] = [:]
        var roots: [NoteBlockID] = []
        var childrenOf: [NoteBlockID: [NoteBlockID]] = [:]
        for id in range {
            guard var copy = block(id) else { continue }
            if copy.kind.hasText {
                let length = copy.text.length
                let lower = id == start.block && start.field == .body ? min(start.offset, length) : 0
                let upper = id == end.block && end.field == .body ? min(end.offset, length) : length
                copy.text = copy.text.slice(lower..<max(lower, upper))
            }
            if id == end.block || !copy.isCollapsed { copy.children = [] }
            nodes[id] = copy
            if let parent = ancestors(of: id).first(where: inRange.contains) { childrenOf[parent, default: []].append(id) }
            else { roots.append(id) }
        }
        func build(_ id: NoteBlockID) -> NoteBlock {
            var node = nodes[id]!
            node.children += (childrenOf[id] ?? []).map(build)
            return node
        }
        return roots.map { build($0).withFreshIDs() }
    }

    mutating func collapseEmptyColumns() {
        var fixes: [[Int]] = []
        func scan(_ list: [NoteBlock], path: [Int], parentIsColumns: Bool) {
            for (index, block) in list.enumerated() {
                let location = path + [index]
                if block.kind == .column && !parentIsColumns { fixes.append(location) }
                if block.kind == .columns,
                   block.children.count < 2 || block.children.contains(where: { $0.kind != .column || $0.children.isEmpty }) {
                    fixes.append(location)
                }
                if !block.children.isEmpty { scan(block.children, path: location, parentIsColumns: block.kind == .columns) }
            }
        }
        scan(blocks, path: [], parentIsColumns: false)
        for location in fixes.sorted(by: { $0.lexicographicallyPrecedes($1) }).reversed() {
            replaceBlock(at: location) { block in
                if block.kind == .column { return block.children }
                var cleaned = block
                cleaned.children = block.children.compactMap { child -> NoteBlock? in
                    if child.kind == .column { return child.children.isEmpty ? nil : child }
                    return NoteBlock(.column, children: [child])
                }
                if cleaned.children.isEmpty { return [] }
                if cleaned.children.count == 1 { return cleaned.children[0].children }
                return [cleaned]
            }
        }
        if blocks.isEmpty { blocks = [.paragraph()] }
    }

    private mutating func replaceBlock(at location: [Int], _ transform: (NoteBlock) -> [NoteBlock]) {
        guard let index = location.last else { return }
        let parentPath = Array(location.dropLast())
        func apply(_ list: inout [NoteBlock]) {
            guard list.indices.contains(index) else { return }
            list.replaceSubrange(index...index, with: transform(list[index]))
        }
        if parentPath.isEmpty { apply(&blocks); return }
        guard let parent = blockID(at: parentPath) else { return }
        update(parent) { apply(&$0.children) }
    }

    private func blockID(at location: [Int]) -> NoteBlockID? {
        var list = blocks
        var found: NoteBlockID?
        for index in location {
            guard list.indices.contains(index) else { return nil }
            found = list[index].id
            list = list[index].children
        }
        return found
    }
}

extension NoteBlock {
    func text(in field: NoteTextField) -> NoteText? {
        switch field {
        case .body: return text
        case .caption: return props.caption
        case .cell(let row, let column): return props.table?.cell(row, column)
        }
    }

    mutating func setText(_ value: NoteText, in field: NoteTextField) {
        switch field {
        case .body: text = kind.hasPlainText ? NoteText(value.string) : value
        case .caption: props.caption = value
        case .cell(let row, let column):
            guard var table = props.table, table.rows.indices.contains(row), table.rows[row].indices.contains(column) else { return }
            table.rows[row][column] = value
            props.table = table
        }
    }

    var conversion: NoteBlockConversion? {
        switch kind {
        case .paragraph: return .text
        case .heading: return props.toggleable ? .toggleHeading(props.level) : .heading(props.level)
        case .bulletedItem: return .bulletedList
        case .numberedItem: return .numberedList
        case .todo: return .todo
        case .toggle: return .toggle
        case .quote: return .quote
        case .callout: return .callout
        case .code: return .code
        case .equation: return .equation
        case .divider: return .divider
        default: return nil
        }
    }

    var continuationKind: NoteBlockKind {
        switch kind {
        case .bulletedItem, .numberedItem, .todo, .toggle: return kind
        default: return .paragraph
        }
    }

    func continuation() -> NoteBlock {
        var fresh = NoteBlock(continuationKind)
        switch kind {
        case .bulletedItem, .numberedItem, .todo:
            fresh.props.bulletMarker = props.bulletMarker
            fresh.props.orderedDelimiter = props.orderedDelimiter
        case .toggle:
            fresh.props.expanded = props.expanded
        default:
            break
        }
        return fresh
    }

    func converted(to kind: NoteBlockKind, configure: (inout NoteBlockProps) -> Void = { _ in }) -> NoteBlock {
        var copy = self
        let wasToggle = isToggle
        if kind.hasPlainText && !self.kind.hasPlainText { copy.text = NoteText(text.plainText) }
        else if kind.hasRichText && self.kind.hasPlainText { copy.text = NoteText(text.string) }
        else if !kind.hasText { copy.text = NoteText() }
        copy.kind = kind
        var props = copy.props
        if kind != .todo { props.checked = false }
        if kind != .numberedItem { props.listStart = nil }
        if kind == .heading {
            if self.kind == .toggle { props.toggleable = true }
            else if self.kind != .heading { props.toggleable = false }
        } else {
            props.toggleable = false
        }
        if kind == .toggle || (kind == .heading && props.toggleable) { props.expanded = wasToggle ? self.props.expanded : true }
        if kind == .callout && props.icon == nil { props.icon = "💡" }
        if kind == .table && props.table == nil {
            var table = NoteTable.empty()
            if self.kind.hasText && !text.isEmpty { table.rows[0][0] = self.kind.hasRichText ? text : NoteText(text.string) }
            props.table = table
        }
        configure(&props)
        copy.props = props
        return copy
    }
}

extension NotePageSession {
    nonisolated static let maximumColumns = 5
    nonisolated static let minimumColumnFraction = 0.08

    func setText(_ value: NoteText, of position: (block: NoteBlockID, field: NoteTextField), origin: AnyObject? = nil,
                 selection after: NotePageSelection? = nil) {
        guard let current = page.block(position.block)?.text(in: position.field), current != value else {
            if let after { setSelection(after, origin: origin) }
            return
        }
        let coalescing: NoteEditCoalescing = value.length < current.length
            ? .deleting(position.block, position.field) : .typing(position.block, position.field)
        edit("Typing", kind: .text, coalescing: coalescing, affected: [position.block], origin: origin, selection: after) { page in
            page.update(position.block) { $0.setText(value, in: position.field) }
        }
    }

    func replaceText(at position: NotePosition, length: Int, with value: NoteText, origin: AnyObject? = nil) {
        guard var text = page.text(of: position) else { return }
        let lower = min(max(0, position.offset), text.length)
        text.replace(lower..<(lower + max(0, length)), with: value)
        let caret = NotePosition(position.block, lower + value.length, field: position.field)
        setText(text, of: (position.block, position.field), origin: origin, selection: .caret(caret))
    }

    @discardableResult
    func splitBlock(at position: NotePosition) -> NoteBlockID? {
        guard let block = page.block(position.block) else { return nil }
        if position.field == .caption {
            let fresh = NoteBlock.paragraph()
            edit("New Block", selection: .caret(NotePosition(fresh.id, 0))) { $0.insert([fresh], .after(block.id)) }
            return fresh.id
        }
        guard position.field == .body, block.kind.hasRichText else { return nil }
        let text = block.text
        let offset = min(max(0, position.offset), text.length)
        if text.isEmpty, block.children.isEmpty, let handled = splitEmpty(block) { return handled }
        if offset == 0 && !text.isEmpty { return insertAbove(block) }
        let intoChildren = block.kind == .callout || (block.isToggle && block.props.expanded)
            || (!block.children.isEmpty && block.showsChildren && block.acceptsChildren)
        var fresh = block.continuation()
        if intoChildren && (block.isToggle || block.kind == .callout || block.kind == .quote) { fresh = NoteBlock(.paragraph) }
        fresh.text = text.slice(offset..<text.length)
        if !fresh.text.isEmpty { fresh.color = block.color }
        let created = fresh
        edit("New Block", selection: .caret(NotePosition(created.id, 0))) { page in
            page.update(block.id) { $0.text = text.slice(0..<offset) }
            page.insert([created], intoChildren ? .firstChild(of: block.id) : .after(block.id))
        }
        return created.id
    }

    private func splitEmpty(_ block: NoteBlock) -> NoteBlockID? {
        let caret = NotePageSelection.caret(NotePosition(block.id, 0))
        switch block.kind {
        case .bulletedItem, .numberedItem, .todo, .toggle:
            if let parentID = page.parent(of: block.id), let parent = page.block(parentID), parent.kind.isListItem || parent.isToggle,
               outdent([block.id], selection: caret) {
                return block.id
            }
            convert([block.id], name: "Turn Into", selection: caret) { $0.convertBlock(block.id, to: .paragraph) }
            return block.id
        case .quote:
            convert([block.id], name: "Turn Into", selection: caret) { $0.convertBlock(block.id, to: .paragraph) }
            return block.id
        default:
            return nil
        }
    }

    private func insertAbove(_ block: NoteBlock) -> NoteBlockID {
        var above = block.kind.isListItem || block.kind == .toggle ? block.continuation() : NoteBlock(.paragraph)
        if block.kind == .toggle { above.props.expanded = true }
        var movesStart = false
        if block.kind == .numberedItem, let start = block.props.listStart {
            let siblings = page.siblings(of: block.id)
            if let index = siblings.firstIndex(where: { $0.id == block.id }), index == 0 || siblings[index - 1].kind != .numberedItem {
                above.props.listStart = start
                movesStart = true
            }
        }
        let created = above
        edit("New Block", selection: .caret(NotePosition(block.id, 0))) { page in
            page.insert([created], .before(block.id))
            if movesStart { page.update(block.id) { $0.props.listStart = nil } }
        }
        return created.id
    }

    @discardableResult
    func insertBlockBreak() -> NoteBlockID? {
        switch selection {
        case .none, .cells:
            return nil
        case .blocks(let ids):
            let targets = page.ordered(ids)
            let toggles = targets.filter { page.block($0)?.isCollapsed == true }
            if !toggles.isEmpty, toggles.count == targets.count {
                edit("Expand", selection: selection) { page in page.updateBlocks(toggles) { $0.props.expanded = true } }
            } else if let first = targets.first(where: { page.block($0)?.kind.hasText == true }) {
                setSelection(page.caretSelection(atEndOf: first))
            }
            return nil
        case .text(let anchor, let head):
            if anchor == head { return splitBlock(at: anchor) }
            return group("New Block") { () -> NoteBlockID? in
                guard let caret = deleteSelection() else { return nil }
                return splitBlock(at: caret)
            }
        }
    }

    @discardableResult
    func mergeBackward(_ id: NoteBlockID) -> Bool {
        guard let block = page.block(id), block.kind.hasText else { return false }
        let caret = NotePageSelection.caret(NotePosition(id, 0))
        if block.kind.hasRichText && block.kind != .paragraph {
            convert([id], name: "Turn Into", selection: caret) { $0.convertBlock(id, to: .paragraph) }
            return true
        }
        if block.kind.hasPlainText {
            guard block.text.isEmpty else { return false }
            convert([id], name: "Turn Into", selection: caret) { $0.convertBlock(id, to: .paragraph) }
            return true
        }
        if let parentID = page.parent(of: id), let parent = page.block(parentID), !parent.kind.isColumnStructure,
           parent.children.last?.id == id, outdent([id], selection: caret) {
            return true
        }
        guard let previousID = page.previousContent(before: id), let previous = page.block(previousID) else { return false }
        if previous.kind.hasText {
            let join = previous.text.length
            edit("Delete", selection: .caret(NotePosition(previousID, join))) { page in page.merge(id, into: previousID) }
            return true
        }
        if block.text.isEmpty && block.children.isEmpty {
            edit("Delete", selection: .blocks([previousID])) { page in
                page.remove(id)
                page.collapseEmptyColumns()
            }
        } else {
            setSelection(.blocks([previousID]))
        }
        return true
    }

    func mergeForward(_ id: NoteBlockID) {
        guard let block = page.block(id), block.kind.hasText, let nextID = page.nextContent(after: id),
              let next = page.block(nextID) else { return }
        if next.kind.hasText {
            if block.text.isEmpty && block.children.isEmpty && !page.isAncestor(id, of: nextID) {
                edit("Delete", selection: .caret(NotePosition(nextID, 0))) { page in
                    page.remove(id)
                    page.collapseEmptyColumns()
                }
                return
            }
            let join = block.text.length
            edit("Delete", selection: .caret(NotePosition(id, join))) { page in page.merge(nextID, into: id) }
        } else if block.text.isEmpty && block.children.isEmpty {
            edit("Delete", selection: .blocks([nextID])) { page in
                page.remove(id)
                page.collapseEmptyColumns()
            }
        } else {
            setSelection(.blocks([nextID]))
        }
    }

    @discardableResult
    func deleteBackward() -> Bool {
        switch selection {
        case .none:
            return false
        case .blocks, .cells:
            deleteSelection()
            return true
        case .text(let anchor, let head):
            guard anchor == head else { deleteSelection(); return true }
            guard let text = page.text(of: anchor) else { return false }
            if let range = text.composedRange(before: anchor.offset) {
                replaceText(at: NotePosition(anchor.block, range.lowerBound, field: anchor.field), length: range.count, with: NoteText())
                return true
            }
            switch anchor.field {
            case .body: return mergeBackward(anchor.block)
            case .caption:
                setSelection(.blocks([anchor.block]))
                return true
            case .cell: return false
            }
        }
    }

    @discardableResult
    func deleteForward() -> Bool {
        switch selection {
        case .none:
            return false
        case .blocks, .cells:
            deleteSelection()
            return true
        case .text(let anchor, let head):
            guard anchor == head else { deleteSelection(); return true }
            guard let text = page.text(of: anchor) else { return false }
            if let range = text.composedRange(after: anchor.offset) {
                replaceText(at: NotePosition(anchor.block, range.lowerBound, field: anchor.field), length: range.count, with: NoteText())
                return true
            }
            guard anchor.field == .body else { return false }
            let before = page
            mergeForward(anchor.block)
            return page != before || selection != .caret(anchor)
        }
    }

    @discardableResult
    func indent(_ ids: [NoteBlockID]) -> Bool {
        indent(ids, selection: selection)
    }

    @discardableResult
    func outdent(_ ids: [NoteBlockID]) -> Bool {
        outdent(ids, selection: selection)
    }

    private func siblingRuns(_ targets: [NoteBlockID]) -> [[NoteBlockID]] {
        var runs: [[NoteBlockID]] = []
        var lastParent: NoteBlockID?? = .none
        var lastIndex = -2
        for id in targets {
            guard let path = page.path(of: id) else { continue }
            let parent = page.parent(of: id)
            if case .some(let previous) = lastParent, previous == parent, path.last! == lastIndex + 1 {
                runs[runs.count - 1].append(id)
            } else {
                runs.append([id])
            }
            lastParent = .some(parent)
            lastIndex = path.last!
        }
        return runs
    }

    private func indent(_ ids: [NoteBlockID], selection after: NotePageSelection) -> Bool {
        let targets = page.topLevelSelection(ids).filter { page.block($0)?.kind.isColumnStructure == false }
        var moves: [(run: [NoteBlockID], parent: NoteBlockID)] = []
        for run in siblingRuns(targets) {
            let siblings = page.siblings(of: run[0])
            guard let index = siblings.firstIndex(where: { $0.id == run[0] }), index > 0 else { continue }
            let previous = siblings[index - 1]
            guard previous.acceptsChildren, !previous.kind.isColumnStructure else { continue }
            moves.append((run, previous.id))
        }
        guard !moves.isEmpty else { return false }
        edit("Indent", selecting: { $0.clamped(after) }) { page in
            for move in moves {
                let moved = page.removeBlocks(move.run)
                page.update(move.parent) { parent in
                    parent.children.append(contentsOf: moved)
                    if parent.isToggle { parent.props.expanded = true }
                }
            }
        }
        return true
    }

    private func outdent(_ ids: [NoteBlockID], selection after: NotePageSelection) -> Bool {
        let targets = page.topLevelSelection(ids).filter { page.block($0)?.kind.isColumnStructure == false }
        var moves: [(run: [NoteBlockID], parent: NoteBlockID)] = []
        for run in siblingRuns(targets) {
            guard let parentID = page.parent(of: run[0]), let parent = page.block(parentID), !parent.kind.isColumnStructure,
                  let lastIndex = parent.children.firstIndex(where: { $0.id == run.last! }) else { continue }
            let trailing = parent.children[(lastIndex + 1)...]
            if !trailing.isEmpty && page.block(run.last!)?.acceptsChildren != true { continue }
            moves.append((run, parentID))
        }
        guard !moves.isEmpty else { return false }
        edit("Outdent", selecting: { $0.clamped(after) }) { page in
            for move in moves.reversed() {
                guard let parent = page.block(move.parent), let lastIndex = parent.children.firstIndex(where: { $0.id == move.run.last! })
                else { continue }
                let trailing = Array(parent.children[(lastIndex + 1)...])
                var moved = page.removeBlocks(move.run + trailing.map(\.id)).filter { block in move.run.contains(block.id) }
                if !trailing.isEmpty, !moved.isEmpty {
                    moved[moved.count - 1].children.append(contentsOf: trailing)
                    if moved[moved.count - 1].isToggle { moved[moved.count - 1].props.expanded = true }
                }
                page.insert(moved, .after(move.parent))
            }
        }
        return true
    }

    private func convert(_ ids: [NoteBlockID], name: String, selection after: NotePageSelection, _ body: (inout NotePage) -> Void) {
        edit(name, selecting: { $0.clamped(after) }, body)
    }

    func turnInto(_ ids: [NoteBlockID], kind: NoteBlockKind, configure: @escaping (inout NoteBlockProps) -> Void = { _ in }) {
        let targets = page.ordered(ids)
        guard !targets.isEmpty else { return }
        convert(targets, name: "Turn Into", selection: selection) { page in
            page.convertBlocks(targets) { block in
                block.kind.isColumnStructure ? nil : block.converted(to: kind, configure: configure)
            }
        }
    }

    func turnInto(_ ids: [NoteBlockID], conversion: NoteBlockConversion) {
        let targets = page.ordered(ids)
        guard !targets.isEmpty else { return }
        convert(targets, name: "Turn Into", selection: selection) { page in
            page.convertBlocks(targets) { block in
                block.kind.isColumnStructure ? nil : block.converted(to: conversion.kind) { conversion.configure(&$0, from: block) }
            }
        }
    }

    @discardableResult
    func applyBlockShortcut(_ id: NoteBlockID, prefixLength: Int, conversion: NoteBlockConversion) -> Bool {
        guard let block = page.block(id), block.kind.hasRichText, prefixLength >= 0, prefixLength <= block.text.length else { return false }
        let remaining = block.text.slice(prefixLength..<block.text.length)
        let caretOffset: Int
        if let caret = selection.caret, caret.block == id, caret.field == .body { caretOffset = max(0, caret.offset - prefixLength) }
        else { caretOffset = 0 }
        if conversion == .divider {
            if remaining.isEmpty {
                let fresh = NoteBlock.paragraph()
                edit("Turn Into", selection: .caret(NotePosition(fresh.id, 0))) { page in
                    page.convertBlock(id, to: .divider)
                    page.insert([fresh], .after(id))
                }
            } else {
                let divider = NoteBlock(.divider)
                edit("Turn Into", selection: .caret(NotePosition(id, caretOffset))) { page in
                    page.update(id) { $0.text = remaining }
                    page.insert([divider], .before(id))
                }
            }
            return true
        }
        edit("Turn Into", selecting: { $0.clamped(.caret(NotePosition(id, caretOffset))) }) { page in
            page.update(id) { $0.text = remaining }
            page.convertBlock(id, to: conversion)
        }
        return true
    }

    func updateBlock(_ id: NoteBlockID, name: String = "Change", _ transform: @escaping (inout NoteBlock) -> Void) {
        edit(name, selecting: { $0.clamped(self.selection) }) { page in page.update(id, transform) }
    }

    func updateSettings(name: String = "Page Settings", _ transform: (inout NotePageSettings) -> Void) {
        edit(name, kind: .settings, affected: [], selection: selection) { page in transform(&page.settings) }
    }

    @discardableResult
    func insertBlocks(_ blocks: [NoteBlock], _ position: NoteInsertion, select: NotePageSelection? = nil) -> [NoteBlockID] {
        guard !blocks.isEmpty else { return [] }
        let after = select ?? Self.landing(after: blocks)
        edit("Insert", selection: after) { page in page.insert(blocks, position) }
        return blocks.map(\.id)
    }

    static func landing(after blocks: [NoteBlock]) -> NotePageSelection {
        guard var current = blocks.last else { return .none }
        while current.showsChildren, let last = current.children.last { current = last }
        return current.kind.hasText ? .caret(NotePosition(current.id, current.text.length)) : .blocks([current.id])
    }

    func deleteBlocks(_ ids: [NoteBlockID]) {
        let targets = page.topLevelSelection(ids)
        guard let first = targets.first, let firstPosition = page.visiblePosition(of: first) ?? page.documentPosition(of: first) else { return }
        let removed = Set(targets)
        let order = page.index.visibleIDs
        func isRemoved(_ id: NoteBlockID) -> Bool { removed.contains(id) || page.ancestors(of: id).contains(where: removed.contains) }
        var before: NoteBlockID?
        var position = min(firstPosition, order.count)
        while position > 0 {
            position -= 1
            let id = order[position]
            if page.block(id)?.kind.isColumnStructure == false && !isRemoved(id) { before = id; break }
        }
        var after: NoteBlockID?
        position = firstPosition
        while position + 1 < order.count {
            position += 1
            let id = order[position]
            if page.block(id)?.kind.isColumnStructure == false && !isRemoved(id) { after = id; break }
        }
        edit("Delete", selecting: { page in
            if let before, page.contains(before) { return page.caretSelection(atEndOf: before) }
            if let after, page.contains(after) { return page.caretSelection(atStartOf: after) }
            return page.blocks.first.map { page.caretSelection(atStartOf: $0.id) } ?? NotePageSelection.none
        }) { page in
            page.removeBlocks(targets)
            page.collapseEmptyColumns()
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

    private func canPlace(_ moving: [NoteBlockID], at position: NoteInsertion) -> Bool {
        let blocks = moving.compactMap { page.block($0) }
        let carriesColumns = blocks.contains { block in
            block.kind == .columns || block.children.contains { $0.kind == .columns }
        }
        let movesColumn = blocks.contains { $0.kind == .column }
        let parent: NoteBlockID?
        switch position {
        case .top: parent = nil
        case .before(let anchor), .after(let anchor): parent = page.parent(of: anchor)
        case .firstChild(let anchor), .lastChild(let anchor): parent = anchor
        }
        guard let parent else { return !movesColumn }
        guard let parentBlock = page.block(parent) else { return false }
        if parentBlock.kind == .columns { return blocks.allSatisfy { $0.kind == .column } }
        if movesColumn { return false }
        if carriesColumns && (parentBlock.kind == .column || page.containingColumn(of: parent) != nil) { return false }
        return parentBlock.acceptsChildren
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
        guard canPlace(targets, at: position) else { return }
        edit("Move", selecting: { $0.clamped(self.selection) }) { page in
            let moved = page.removeBlocks(targets)
            page.insert(moved, position)
            if case .firstChild(let parent) = position { page.update(parent) { if $0.isToggle { $0.props.expanded = true } } }
            if case .lastChild(let parent) = position { page.update(parent) { if $0.isToggle { $0.props.expanded = true } } }
            page.collapseEmptyColumns()
        }
    }

    func moveBlocks(_ ids: [NoteBlockID], toColumn column: NoteBlockID, at index: Int) {
        guard let target = page.block(column), target.kind == .column else { return }
        let moving = Set(page.topLevelSelection(ids))
        let remaining = target.children.filter { !moving.contains($0.id) }
        if index <= 0 || remaining.isEmpty { moveBlocks(ids, to: .firstChild(of: column)) }
        else if index >= remaining.count { moveBlocks(ids, to: .lastChild(of: column)) }
        else { moveBlocks(ids, to: .before(remaining[index].id)) }
    }

    func moveBlocks(_ ids: [NoteBlockID], _ direction: NoteMoveDirection) {
        let targets = page.topLevelSelection(ids)
        guard let first = targets.first, let last = targets.last else { return }
        let siblings = page.siblings(of: first)
        guard let firstIndex = siblings.firstIndex(where: { $0.id == first }),
              let lastIndex = page.siblings(of: last).firstIndex(where: { $0.id == last }) else { return }
        switch direction {
        case .up:
            if firstIndex > 0 { moveBlocks(targets, to: .before(siblings[firstIndex - 1].id)) }
            else if let parent = page.parent(of: first), page.block(parent)?.kind.isColumnStructure == false {
                moveBlocks(targets, to: .before(parent))
            }
        case .down:
            let trailing = page.siblings(of: last)
            if lastIndex + 1 < trailing.count { moveBlocks(targets, to: .after(trailing[lastIndex + 1].id)) }
            else if let parent = page.parent(of: last), page.block(parent)?.kind.isColumnStructure == false {
                moveBlocks(targets, to: .after(parent))
            }
        }
    }

    func placeBeside(_ ids: [NoteBlockID], target: NoteBlockID, side: NoteDropSide) {
        let moving = page.topLevelSelection(ids)
        guard !moving.isEmpty, !moving.contains(target), !moving.contains(where: { page.isAncestor($0, of: target) }) else { return }
        let carriesColumns = moving.contains { id in
            guard let block = page.block(id) else { return true }
            return block.kind.isColumnStructure || block.children.contains { $0.kind.isColumnStructure }
        }
        guard !carriesColumns else { return }
        edit("Move", selecting: { $0.clamped(self.selection) }) { page in
            let original = page
            let moved = page.removeBlocks(moving)
            page.collapseEmptyColumns()
            guard let targetBlock = page.block(target) else { page = original; return }
            let column = targetBlock.kind == .column ? target : page.containingColumn(of: target)
            if let column {
                guard let columnsID = page.parent(of: column), let columns = page.block(columnsID),
                      columns.children.count < Self.maximumColumns else { page = original; return }
                page.insert([NoteBlock(.column, children: moved)], side == .left ? .before(column) : .after(column))
                page.update(columnsID) { block in for index in block.children.indices { block.children[index].props.width = nil } }
            } else {
                let targetColumn = NoteBlock(.column, children: [targetBlock])
                let movedColumn = NoteBlock(.column, children: moved)
                let columns = NoteBlock(.columns, children: side == .left ? [movedColumn, targetColumn] : [targetColumn, movedColumn])
                page.update(target) { $0 = columns }
            }
            page.collapseEmptyColumns()
        }
    }

    func setColumnWidths(_ columnsID: NoteBlockID, _ fractions: [Double]) {
        guard let columns = page.block(columnsID), columns.kind == .columns, fractions.count == columns.children.count,
              fractions.allSatisfy({ $0.isFinite && $0 > 0 }) else { return }
        let normalized = Self.distribute(fractions, minimum: Self.minimumColumnFraction)
        edit("Resize Columns", coalescing: .adjusting(columnsID), selection: selection) { page in
            page.update(columnsID) { block in
                for index in block.children.indices { block.children[index].props.width = normalized[index] }
            }
        }
    }

    nonisolated static func distribute(_ weights: [Double], minimum: Double) -> [Double] {
        guard !weights.isEmpty else { return [] }
        guard minimum * Double(weights.count) < 1 else { return Array(repeating: 1 / Double(weights.count), count: weights.count) }
        var pinned = Set<Int>()
        var result = weights
        while true {
            let free = 1 - minimum * Double(pinned.count)
            let freeWeight = weights.indices.filter { !pinned.contains($0) }.map { weights[$0] }.reduce(0, +)
            var changed = false
            for index in weights.indices {
                if pinned.contains(index) { result[index] = minimum; continue }
                result[index] = freeWeight > 0 ? weights[index] / freeWeight * free : free / Double(weights.count - pinned.count)
                if result[index] < minimum { pinned.insert(index); changed = true }
            }
            if !changed { return result }
        }
    }

    func resetColumnWidths(_ columnsID: NoteBlockID) {
        guard let columns = page.block(columnsID), columns.kind == .columns else { return }
        edit("Resize Columns", selection: selection) { page in
            page.update(columnsID) { block in for index in block.children.indices { block.children[index].props.width = nil } }
        }
    }

    func toggleExpanded(_ id: NoteBlockID) {
        guard let block = page.block(id), block.isToggle else { return }
        setExpanded([id], !block.props.expanded, name: block.props.expanded ? "Collapse" : "Expand")
    }

    func setAllToggles(expanded: Bool) {
        let ids = page.allBlocks().filter(\.isToggle).map(\.id)
        guard !ids.isEmpty else { return }
        setExpanded(ids, expanded, name: expanded ? "Expand All" : "Collapse All")
    }

    private func setExpanded(_ ids: [NoteBlockID], _ expanded: Bool, name: String) {
        let current = selection
        edit(name, affected: Set(ids), selecting: { page in
            guard !expanded else { return current }
            func reveal(_ id: NoteBlockID) -> NoteBlockID {
                var visible = id
                for ancestor in page.ancestors(of: id) where page.block(ancestor)?.isCollapsed == true { visible = ancestor }
                return visible
            }
            switch current {
            case .text(let anchor, let head):
                let anchorHost = reveal(anchor.block), headHost = reveal(head.block)
                if anchorHost == anchor.block && headHost == head.block { return current }
                return page.caretSelection(atEndOf: headHost)
            case .blocks(let blockIDs):
                let revealed = page.ordered(blockIDs.map(reveal))
                return .blocks(revealed)
            case .cells(let table, _, _):
                let host = reveal(table)
                return host == table ? current : .blocks([host])
            case .none:
                return current
            }
        }) { page in
            page.updateBlocks(ids) { $0.props.expanded = expanded }
        }
    }

    func toggleChecked(_ ids: [NoteBlockID]) {
        let todos = page.ordered(ids).filter { page.block($0)?.kind == .todo }
        guard !todos.isEmpty else { return }
        let value = !todos.allSatisfy { page.block($0)?.props.checked == true }
        edit(value ? "Check" : "Uncheck", affected: Set(todos), selection: selection) { page in
            page.updateBlocks(todos) { $0.props.checked = value }
        }
    }

    func textSegments(of value: NotePageSelection) -> [(position: NotePosition, range: Range<Int>)] {
        switch value {
        case .none:
            return []
        case .cells(let table, let anchor, let head):
            guard let grid = page.block(table)?.props.table else { return [] }
            var result: [(position: NotePosition, range: Range<Int>)] = []
            for row in min(anchor.row, head.row)...max(anchor.row, head.row) {
                for column in min(anchor.column, head.column)...max(anchor.column, head.column) {
                    guard let cell = grid.cell(row, column) else { continue }
                    result.append((NotePosition(table, 0, field: .cell(row: row, column: column)), 0..<cell.length))
                }
            }
            return result
        case .blocks(let ids):
            var result: [(position: NotePosition, range: Range<Int>)] = []
            func collect(_ block: NoteBlock) {
                if block.kind.hasRichText { result.append((NotePosition(block.id, 0), 0..<block.text.length)) }
                result.append(contentsOf: cellSegments(of: block))
                for child in block.children { collect(child) }
            }
            for id in page.topLevelSelection(ids) { if let block = page.block(id) { collect(block) } }
            return result
        case .text(let anchor, let head):
            let (start, end) = orderedEnds(anchor, head)
            if start.block == end.block && start.field == end.field {
                return [(start, start.offset..<max(start.offset, end.offset))]
            }
            if start.block == end.block {
                guard let block = page.block(start.block) else { return [] }
                return fieldSegments(of: block, from: start, to: end)
            }
            guard let from = page.visiblePosition(of: start.block), let to = page.visiblePosition(of: end.block), from <= to else { return [] }
            var result: [(position: NotePosition, range: Range<Int>)] = []
            for id in page.index.visibleIDs[from...to] {
                guard let block = page.block(id) else { continue }
                if id == start.block {
                    let length = block.text(in: start.field)?.length ?? 0
                    result.append((start, min(start.offset, length)..<length))
                    if start.field != .body { result.append(contentsOf: cellSegments(of: block, after: start.field)) }
                } else if id == end.block {
                    if end.field != .body {
                        if block.kind.hasText { result.append((NotePosition(id, 0), 0..<block.text.length)) }
                        result.append(contentsOf: cellSegments(of: block, before: end.field))
                    }
                    result.append((NotePosition(id, 0, field: end.field), 0..<end.offset))
                } else if block.kind.hasText {
                    result.append((NotePosition(id, 0), 0..<block.text.length))
                } else {
                    result.append(contentsOf: cellSegments(of: block))
                }
            }
            return result
        }
    }

    private func cellSegments(of block: NoteBlock, after lower: NoteTextField? = nil, before limit: NoteTextField? = nil)
        -> [(position: NotePosition, range: Range<Int>)] {
        guard let grid = block.props.table else { return [] }
        var result: [(position: NotePosition, range: Range<Int>)] = []
        for row in grid.rows.indices {
            for column in grid.rows[row].indices {
                let field = NoteTextField.cell(row: row, column: column)
                if let lower, page.fieldOrder(field) <= page.fieldOrder(lower) { continue }
                if let limit, page.fieldOrder(field) >= page.fieldOrder(limit) { continue }
                result.append((NotePosition(block.id, 0, field: field), 0..<grid.rows[row][column].length))
            }
        }
        return result
    }

    private func fieldSegments(of block: NoteBlock, from start: NotePosition, to end: NotePosition)
        -> [(position: NotePosition, range: Range<Int>)] {
        var result: [(position: NotePosition, range: Range<Int>)] = []
        let startLength = block.text(in: start.field)?.length ?? 0
        result.append((start, min(start.offset, startLength)..<startLength))
        if case .cell = start.field, case .cell = end.field {
            result.append(contentsOf: cellSegments(of: block, after: start.field, before: end.field))
        }
        result.append((NotePosition(block.id, 0, field: end.field), 0..<end.offset))
        return result
    }

    func orderedEnds(_ anchor: NotePosition, _ head: NotePosition) -> (NotePosition, NotePosition) {
        page.precedes(head, anchor) ? (head, anchor) : (anchor, head)
    }

    func hasMark(_ key: NoteMarkKey, in value: NotePageSelection? = nil) -> Bool {
        let segments = textSegments(of: value ?? selection).filter { segment in
            !segment.range.isEmpty && (segment.position.field != .body || page.block(segment.position.block)?.kind.hasRichText == true)
        }
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
        var target = value ?? selection
        if let caret = target.caret, let text = page.text(of: caret), let range = text.linkRange(at: caret.offset) {
            target = .text(anchor: NotePosition(caret.block, range.lowerBound, field: caret.field),
                           head: NotePosition(caret.block, range.upperBound, field: caret.field))
        }
        updateMarks(in: target, name: url == nil ? "Remove Link" : "Link") { $0.link = url }
    }

    func setColor(_ style: NoteColorStyle?, in value: NotePageSelection? = nil) {
        let target = value ?? selection
        switch target {
        case .blocks(let ids):
            setBlockColor(ids, style)
        case .text(let anchor, let head) where anchor == head && anchor.field == .body:
            setBlockColor([anchor.block], style)
        default:
            updateMarks(in: target, name: "Color") { $0.color = style }
        }
    }

    func setBlockColor(_ ids: [NoteBlockID], _ style: NoteColorStyle?) {
        let targets = page.ordered(ids).filter { page.block($0)?.kind.supportsColor == true }
        guard !targets.isEmpty else { return }
        edit("Color", affected: Set(targets), selection: selection) { page in
            page.updateBlocks(targets) { $0.color = style }
        }
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
        case .none:
            return nil
        case .cells(let table, let anchor, let head):
            let rows = min(anchor.row, head.row)...max(anchor.row, head.row)
            let columns = min(anchor.column, head.column)...max(anchor.column, head.column)
            edit("Clear Cells", selection: target) { page in
                page.update(table) { block in
                    guard var grid = block.props.table else { return }
                    for row in rows where grid.rows.indices.contains(row) {
                        for column in columns where grid.rows[row].indices.contains(column) { grid.rows[row][column] = NoteText() }
                    }
                    block.props.table = grid
                }
            }
            return nil
        case .blocks(let ids):
            deleteBlocks(ids)
            return selection.caret
        case .text(let anchor, let head):
            let (start, end) = orderedEnds(anchor, head)
            if start == end { return start }
            if start.block == end.block && start.field == end.field {
                guard page.text(of: start) != nil else { return nil }
                edit("Delete", kind: .text, affected: [start.block], selection: .caret(start)) { page in
                    page.update(start.block) { block in
                        guard var text = block.text(in: start.field) else { return }
                        text.delete(start.offset..<end.offset)
                        block.setText(text, in: start.field)
                    }
                }
                return start
            }
            if start.block == end.block {
                edit("Delete", kind: .text, affected: [start.block], selection: .caret(start)) { page in
                    page.update(start.block) { block in
                        for segment in self.fieldSegments(of: block, from: start, to: end) {
                            guard var text = block.text(in: segment.position.field) else { continue }
                            text.delete(segment.range)
                            block.setText(text, in: segment.position.field)
                        }
                    }
                }
                return start
            }
            edit("Delete", selecting: { $0.clamped(.caret(start)) }) { page in page.deleteRange(from: start, to: end) }
            return page.contains(start.block) ? start : selection.caret
        }
    }

    func insertText(_ value: NoteText, replacing target: NotePageSelection? = nil) {
        let target = target ?? selection
        switch target {
        case .none:
            return
        case .text(let anchor, let head):
            if anchor == head { insertInline(value, at: anchor); return }
            let start = orderedEnds(anchor, head).0
            group("Typing", continuing: .typing(start.block, start.field)) {
                if let caret = deleteSelection(target) { insertInline(value, at: caret) }
            }
        case .blocks(let ids):
            let targets = page.topLevelSelection(ids)
            guard let first = targets.first else { return }
            let fresh = NoteBlock.paragraph(value)
            edit("Typing", coalescing: .typing(fresh.id, .body), selection: .caret(NotePosition(fresh.id, value.length))) { page in
                page.insert([fresh], .before(first))
                page.removeBlocks(targets)
                page.collapseEmptyColumns()
            }
        case .cells(let table, let anchor, let head):
            let row = min(anchor.row, head.row), column = min(anchor.column, head.column)
            let field = NoteTextField.cell(row: row, column: column)
            group("Typing", continuing: .typing(table, field)) {
                deleteSelection(target)
                replaceText(at: NotePosition(table, 0, field: field), length: page.block(table)?.text(in: field)?.length ?? 0, with: value)
            }
        }
    }

    private func insertInline(_ value: NoteText, at caret: NotePosition) {
        guard let current = page.text(of: caret) else { return }
        var inserted = value
        if inserted.isPlain { inserted = NoteText(value.string, marks: current.typingMarks(at: caret.offset)) }
        replaceText(at: caret, length: 0, with: inserted)
    }

    @discardableResult
    func selectAllStep() -> NotePageSelection {
        let everything = NotePageSelection.blocks(page.blocks.map(\.id))
        let next: NotePageSelection
        switch selection {
        case .none:
            next = everything
        case .text(let anchor, let head):
            if anchor.block == head.block && anchor.field == head.field, let text = page.text(of: anchor) {
                let lower = min(anchor.offset, head.offset), upper = max(anchor.offset, head.offset)
                if text.length > 0 && !(lower == 0 && upper == text.length) {
                    next = .text(anchor: NotePosition(anchor.block, 0, field: anchor.field),
                                 head: NotePosition(anchor.block, text.length, field: anchor.field))
                } else if case .cell = anchor.field, let grid = page.block(anchor.block)?.props.table, grid.rowCount * grid.columnCount > 1 {
                    next = .cells(table: anchor.block, anchor: NoteTableCell(row: 0, column: 0),
                                  head: NoteTableCell(row: grid.rowCount - 1, column: grid.columnCount - 1))
                } else {
                    next = .blocks([anchor.block])
                }
            } else {
                let (start, end) = orderedEnds(anchor, head)
                guard let from = page.visiblePosition(of: start.block), let to = page.visiblePosition(of: end.block), from <= to else {
                    next = everything
                    break
                }
                let touched = page.index.visibleIDs[from...to].filter { page.block($0)?.kind.isColumnStructure == false }
                next = .blocks(page.topLevelSelection(touched))
            }
        case .cells(let table, let anchor, let head):
            if let grid = page.block(table)?.props.table,
               min(anchor.row, head.row) == 0, min(anchor.column, head.column) == 0,
               max(anchor.row, head.row) == grid.rowCount - 1, max(anchor.column, head.column) == grid.columnCount - 1 {
                next = .blocks([table])
            } else if let grid = page.block(table)?.props.table {
                next = .cells(table: table, anchor: NoteTableCell(row: 0, column: 0),
                              head: NoteTableCell(row: grid.rowCount - 1, column: grid.columnCount - 1))
            } else {
                next = everything
            }
        case .blocks(let ids):
            next = Set(page.topLevelSelection(ids)) == Set(page.blocks.map(\.id)) ? selection : everything
        }
        setSelection(next)
        return selection
    }

    func setCaption(_ text: NoteText, of id: NoteBlockID, origin: AnyObject? = nil) {
        guard page.block(id)?.kind.hasCaption == true else { return }
        let caret = NotePosition(id, text.length, field: .caption)
        setText(text, of: (id, .caption), origin: origin, selection: .caret(caret))
    }

    func addCaption(to id: NoteBlockID) {
        guard let block = page.block(id), block.kind.hasCaption else { return }
        setSelection(.caret(NotePosition(id, block.props.caption.length, field: .caption)))
    }

    func removeCaption(from id: NoteBlockID) {
        guard let block = page.block(id), block.kind.hasCaption else { return }
        let current = selection
        let inCaption: Bool
        switch current {
        case .text(let anchor, let head): inCaption = (anchor.block == id && anchor.field == .caption) || (head.block == id && head.field == .caption)
        default: inCaption = false
        }
        let after: NotePageSelection = inCaption ? .blocks([id]) : current
        if block.props.caption.isEmpty { setSelection(after); return }
        edit("Remove Caption", selection: after) { page in page.update(id) { $0.props.caption = NoteText() } }
    }

    func fragment(of value: NotePageSelection? = nil) -> [NoteBlock] {
        let target = value ?? selection
        switch target {
        case .none:
            return []
        case .blocks(let ids):
            return page.topLevelSelection(ids).compactMap { page.block($0)?.withFreshIDs() }
        case .cells(let table, let anchor, let head):
            guard let grid = page.block(table)?.props.table else { return [] }
            let rows = min(anchor.row, head.row)...max(anchor.row, head.row)
            let columns = min(anchor.column, head.column)...max(anchor.column, head.column)
            let picked = rows.compactMap { row in grid.rows.indices.contains(row)
                ? columns.compactMap { grid.cell(row, $0) } : nil }
            var props = NoteBlockProps()
            props.table = NoteTable(rows: picked, headerRow: false)
            return [NoteBlock(.table, props: props)]
        case .text(let anchor, let head):
            let (start, end) = orderedEnds(anchor, head)
            if start == end { return [] }
            if start.block == end.block {
                guard let block = page.block(start.block) else { return [] }
                let pieces = start.field == end.field
                    ? [(start, start.offset..<end.offset)]
                    : fieldSegments(of: block, from: start, to: end).map { ($0.position, $0.range) }
                var joined = NoteText()
                for (index, piece) in pieces.enumerated() {
                    guard let text = block.text(in: piece.0.field) else { continue }
                    if index > 0 { joined.append(NoteText(" ")) }
                    joined.append(block.kind.hasPlainText && piece.0.field == .body ? NoteText(text.slice(piece.1).string) : text.slice(piece.1))
                }
                return [NoteBlock.paragraph(joined)]
            }
            return page.textFragment(from: start, to: end)
        }
    }

    func paste(_ blocks: [NoteBlock], replacing target: NotePageSelection? = nil) {
        let target = target ?? selection
        guard !blocks.isEmpty, !isReadOnly else { return }
        group("Paste") {
            switch target {
            case .none:
                let units = Self.clipboardForest(blocks, insideColumn: false)
                insertBlocks(units, .top(page.blocks.count))
            case .blocks(let ids):
                guard let last = page.topLevelSelection(ids).last, let anchor = page.block(last) else { return }
                let insideColumn = anchor.kind == .column || page.containingColumn(of: last) != nil
                let units = Self.clipboardForest(blocks, insideColumn: insideColumn)
                guard !units.isEmpty else { return }
                insertBlocks(units, anchor.kind == .column ? .lastChild(of: last) : .after(last))
            case .cells(let table, let anchor, let head):
                pasteIntoCells(blocks, table: table, origin: NoteTableCell(row: min(anchor.row, head.row), column: min(anchor.column, head.column)),
                               clearing: target)
            case .text(let anchor, let head):
                guard let caret = deleteSelection(target) else { return }
                pasteAtCaret(blocks, caret: caret, replacedSelection: anchor != head)
            }
        }
    }

    func pasteText(_ string: String, replacing target: NotePageSelection? = nil) {
        let normalized = string.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        guard !normalized.isEmpty else { return }
        let lines = normalized.components(separatedBy: "\n")
        if lines.count == 1 {
            group("Paste") { insertText(NoteText(normalized), replacing: target) }
        } else {
            paste(lines.map { NoteBlock.paragraph(NoteText($0)) }, replacing: target)
        }
    }

    private func pasteAtCaret(_ blocks: [NoteBlock], caret: NotePosition, replacedSelection: Bool) {
        guard let host = page.block(caret.block) else { return }
        let insideColumn = page.containingColumn(of: host.id) != nil
        let units = Self.clipboardForest(blocks, insideColumn: insideColumn)
        guard !units.isEmpty else { return }
        if caret.field != .body || !host.kind.hasRichText {
            let inline: NoteText
            if caret.field == .body {
                inline = NoteText(Self.plainLines(of: units).joined(separator: "\n"))
            } else if units.count == 1, units[0].kind.hasRichText, units[0].children.isEmpty {
                inline = units[0].text
            } else {
                inline = NoteText(Self.plainLines(of: units).joined(separator: " "))
            }
            insertInline(inline, at: caret)
            return
        }
        let replacesHost = host.text.isEmpty && host.kind == .paragraph && host.children.isEmpty
        if units.count == 1, units[0].kind.hasRichText, units[0].children.isEmpty {
            let unit = units[0]
            if replacesHost && unit.kind != .paragraph {
                edit("Paste", selection: .caret(NotePosition(host.id, unit.text.length))) { page in
                    page.update(host.id) { block in
                        block.kind = unit.kind
                        block.props = unit.props
                        block.color = unit.color
                        block.text = unit.text
                    }
                }
            } else {
                insertInline(unit.text, at: caret)
            }
            return
        }
        if replacesHost {
            edit("Paste", selection: Self.landing(after: units)) { page in
                page.insert(units, .before(host.id))
                page.remove(host.id)
            }
            return
        }
        let offset = min(caret.offset, host.text.length)
        if offset == 0 && !replacedSelection {
            edit("Paste", selection: Self.landing(after: units)) { page in page.insert(units, .before(host.id)) }
            return
        }
        let head = host.text.slice(0..<offset), tail = host.text.slice(offset..<host.text.length)
        var rest = units
        var merged = head
        if let first = rest.first, first.kind.hasRichText {
            merged.append(first.text)
            rest.removeFirst()
            rest = first.children + rest
        }
        var landing: NotePageSelection = .caret(NotePosition(host.id, merged.length))
        if !tail.isEmpty {
            if let lastRoot = rest.last, case let last = lastRoot.lastVisibleDescendant(), last.kind.hasRichText {
                landing = .caret(NotePosition(last.id, last.text.length))
                rest[rest.count - 1] = Self.appendingText(tail, toLastDescendantOf: lastRoot)
            } else {
                if !rest.isEmpty { landing = Self.landing(after: rest) }
                var tailBlock = host.continuation()
                tailBlock.text = tail
                rest.append(tailBlock)
            }
        } else if !rest.isEmpty {
            landing = Self.landing(after: rest)
        }
        let intoChildren = !host.children.isEmpty && host.showsChildren
        let inserted = rest
        edit("Paste", selection: landing) { page in
            page.update(host.id) { $0.text = merged }
            page.insert(inserted, intoChildren ? .firstChild(of: host.id) : .after(host.id))
        }
    }

    private func pasteIntoCells(_ blocks: [NoteBlock], table: NoteBlockID, origin: NoteTableCell, clearing target: NotePageSelection) {
        guard page.block(table)?.props.table != nil else { return }
        if blocks.count == 1, blocks[0].kind == .table, let source = blocks[0].props.table {
            edit("Paste", selection: .cells(table: table, anchor: origin,
                                            head: NoteTableCell(row: origin.row + source.rowCount - 1, column: origin.column + source.columnCount - 1))) { page in
                page.update(table) { block in
                    guard var grid = block.props.table else { return }
                    while grid.rowCount < origin.row + source.rowCount { grid.insertRow(at: grid.rowCount) }
                    while grid.columnCount < origin.column + source.columnCount { grid.insertColumn(at: grid.columnCount) }
                    for (rowOffset, row) in source.rows.enumerated() {
                        for (columnOffset, cell) in row.enumerated() { grid.rows[origin.row + rowOffset][origin.column + columnOffset] = cell }
                    }
                    block.props.table = grid
                }
            }
            return
        }
        let units = Self.clipboardForest(blocks, insideColumn: true)
        let text = units.count == 1 && units[0].kind.hasRichText && units[0].children.isEmpty
            ? units[0].text : NoteText(Self.plainLines(of: units).joined(separator: " "))
        let field = NoteTextField.cell(row: origin.row, column: origin.column)
        deleteSelection(target)
        edit("Paste", selection: .caret(NotePosition(table, text.length, field: field))) { page in
            page.update(table) { $0.setText(text, in: field) }
        }
    }

    private static func appendingText(_ text: NoteText, toLastDescendantOf block: NoteBlock) -> NoteBlock {
        var copy = block
        if copy.children.isEmpty || !copy.showsChildren {
            copy.text.append(copy.kind.hasPlainText ? NoteText(text.string) : text)
        } else {
            copy.children[copy.children.count - 1] = appendingText(text, toLastDescendantOf: copy.children[copy.children.count - 1])
        }
        return copy
    }

    static func plainLines(of blocks: [NoteBlock]) -> [String] {
        var lines: [String] = []
        func walk(_ block: NoteBlock) {
            if block.kind.hasText { lines.append(block.text.plainText) }
            else if let table = block.props.table { lines.append(contentsOf: table.rows.map { $0.map(\.plainText).joined(separator: "\t") }) }
            else if let source = block.props.source { lines.append(source) }
            block.children.forEach(walk)
        }
        blocks.forEach(walk)
        return lines
    }

    static func clipboardForest(_ blocks: [NoteBlock], insideColumn: Bool) -> [NoteBlock] {
        func sanitize(_ list: [NoteBlock], insideColumn: Bool) -> [NoteBlock] {
            var result: [NoteBlock] = []
            for block in list {
                switch block.kind {
                case .column:
                    result.append(contentsOf: sanitize(block.children, insideColumn: insideColumn))
                case .columns:
                    let columns = block.children.map { child -> NoteBlock in
                        var column = child.kind == .column ? child : NoteBlock(.column, children: [child])
                        column.children = sanitize(column.children, insideColumn: true)
                        return column
                    }.filter { !$0.children.isEmpty }
                    if insideColumn || columns.count < 2 {
                        result.append(contentsOf: columns.flatMap(\.children))
                    } else {
                        var copy = block
                        copy.children = columns
                        result.append(copy)
                    }
                default:
                    var copy = block
                    copy.children = sanitize(block.children, insideColumn: insideColumn)
                    result.append(copy)
                }
            }
            return result
        }
        return sanitize(blocks, insideColumn: insideColumn).map { $0.withFreshIDs() }
    }

    func updateTable(_ id: NoteBlockID, name: String = "Edit Table", _ transform: @escaping (inout NoteTable) -> Void) {
        updateBlock(id, name: name) { block in
            guard var table = block.props.table else { return }
            transform(&table)
            table.normalize()
            block.props.table = table
        }
    }

    @discardableResult
    private func editTable(_ id: NoteBlockID, name: String, coalescing: NoteEditCoalescing = .none,
                           _ transform: (inout NoteTable) -> Bool, remap: (NoteTableCell) -> NoteTableCell?) -> Bool {
        guard var table = page.block(id)?.props.table, transform(&table) else { return false }
        table.normalize()
        let updated = table
        let current = selection
        func movedCell(_ cell: NoteTableCell) -> NoteTableCell {
            let target = remap(cell) ?? cell
            return NoteTableCell(row: min(max(0, target.row), updated.rowCount - 1), column: min(max(0, target.column), updated.columnCount - 1))
        }
        func movedPosition(_ position: NotePosition) -> NotePosition {
            guard position.block == id, case .cell(let row, let column) = position.field else { return position }
            let original = NoteTableCell(row: row, column: column)
            let mapped = remap(original)
            let cell = movedCell(original)
            let length = updated.cell(cell.row, cell.column)?.length ?? 0
            return NotePosition(id, mapped == nil ? 0 : min(position.offset, length), field: .cell(row: cell.row, column: cell.column))
        }
        let after: NotePageSelection
        switch current {
        case .text(let anchor, let head): after = .text(anchor: movedPosition(anchor), head: movedPosition(head))
        case .cells(let table, let anchor, let head) where table == id: after = .cells(table: id, anchor: movedCell(anchor), head: movedCell(head))
        default: after = current
        }
        edit(name, coalescing: coalescing, affected: [id], selection: after) { page in
            page.update(id) { $0.props.table = updated }
        }
        return true
    }

    @discardableResult
    func insertTableRow(_ id: NoteBlockID, at index: Int) -> Bool {
        editTable(id, name: "Insert Row", { table in table.insertRow(at: index); return true }) { cell in
            NoteTableCell(row: cell.row >= index ? cell.row + 1 : cell.row, column: cell.column)
        }
    }

    @discardableResult
    func deleteTableRow(_ id: NoteBlockID, at index: Int) -> Bool {
        editTable(id, name: "Delete Row", { $0.deleteRow(at: index) }) { cell in
            if cell.row == index { return nil }
            return NoteTableCell(row: cell.row > index ? cell.row - 1 : cell.row, column: cell.column)
        }
    }

    @discardableResult
    func duplicateTableRow(_ id: NoteBlockID, at index: Int) -> Bool {
        editTable(id, name: "Duplicate Row", { $0.duplicateRow(at: index) }) { cell in
            NoteTableCell(row: cell.row > index ? cell.row + 1 : cell.row, column: cell.column)
        }
    }

    @discardableResult
    func moveTableRow(_ id: NoteBlockID, from source: Int, to destination: Int) -> Bool {
        editTable(id, name: "Move Row", { $0.moveRow(from: source, to: destination) }) { cell in
            NoteTableCell(row: NoteTable.movedIndex(cell.row, from: source, to: destination), column: cell.column)
        }
    }

    @discardableResult
    func insertTableColumn(_ id: NoteBlockID, at index: Int) -> Bool {
        editTable(id, name: "Insert Column", { table in table.insertColumn(at: index); return true }) { cell in
            NoteTableCell(row: cell.row, column: cell.column >= index ? cell.column + 1 : cell.column)
        }
    }

    @discardableResult
    func deleteTableColumn(_ id: NoteBlockID, at index: Int) -> Bool {
        editTable(id, name: "Delete Column", { $0.deleteColumn(at: index) }) { cell in
            if cell.column == index { return nil }
            return NoteTableCell(row: cell.row, column: cell.column > index ? cell.column - 1 : cell.column)
        }
    }

    @discardableResult
    func duplicateTableColumn(_ id: NoteBlockID, at index: Int) -> Bool {
        editTable(id, name: "Duplicate Column", { $0.duplicateColumn(at: index) }) { cell in
            NoteTableCell(row: cell.row, column: cell.column > index ? cell.column + 1 : cell.column)
        }
    }

    @discardableResult
    func moveTableColumn(_ id: NoteBlockID, from source: Int, to destination: Int) -> Bool {
        editTable(id, name: "Move Column", { $0.moveColumn(from: source, to: destination) }) { cell in
            NoteTableCell(row: cell.row, column: NoteTable.movedIndex(cell.column, from: source, to: destination))
        }
    }

    @discardableResult
    func setTableHeaderRow(_ id: NoteBlockID, _ enabled: Bool) -> Bool {
        editTable(id, name: "Header Row", { table in
            guard table.headerRow != enabled else { return false }
            table.headerRow = enabled
            return true
        }) { $0 }
    }

    @discardableResult
    func setTableHeaderColumn(_ id: NoteBlockID, _ enabled: Bool) -> Bool {
        editTable(id, name: "Header Column", { table in
            guard table.headerColumn != enabled else { return false }
            table.headerColumn = enabled
            return true
        }) { $0 }
    }

    @discardableResult
    func setTableColumnWidth(_ id: NoteBlockID, column: Int, width: Double?) -> Bool {
        editTable(id, name: "Resize Column", coalescing: .adjusting(id), { table in
            guard column >= 0, column < table.columnCount else { return false }
            table.setColumnWidth(width, at: column)
            return true
        }) { $0 }
    }

    @discardableResult
    func setTableColumnAlignment(_ id: NoteBlockID, column: Int, _ alignment: NoteAlignment?) -> Bool {
        editTable(id, name: "Align Column", { table in
            guard column >= 0, column < table.columnCount else { return false }
            table.setAlignment(alignment, at: column)
            return true
        }) { $0 }
    }
}
