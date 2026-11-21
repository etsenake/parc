import Foundation

package enum NoteFileReconciler {
    private struct Signature: Hashable {
        var kind: NoteBlockKind
        var text: NoteText
        var props: NoteBlockProps
        var color: NoteColorStyle?

        package init(kind: NoteBlockKind, text: NoteText, props: NoteBlockProps, color: NoteColorStyle? = nil) {
            self.kind = kind
            self.text = text
            self.props = props
            self.color = color
        }
    }

    package static let identityLimit = 20_000

    package static func preservingIdentity(of old: NotePage, in new: NotePage) -> NotePage {
        let before = old.allBlocks(), after = new.allBlocks()
        guard !before.isEmpty, !after.isEmpty, before.count <= identityLimit, after.count <= identityLimit else { return new }
        let oldSignatures = before.map(signature), newSignatures = after.map(signature)
        var removed = Set<Int>(), inserted = Set<Int>()
        for change in newSignatures.difference(from: oldSignatures) {
            switch change {
            case .remove(let offset, _, _): removed.insert(offset)
            case .insert(let offset, _, _): inserted.insert(offset)
            }
        }
        var mapping: [NoteBlockID: NoteBlockID] = [:]
        var oldIndex = 0, newIndex = 0
        var oldGap: [Int] = [], newGap: [Int] = []
        func pairGap() {
            for (o, n) in zip(oldGap, newGap) where before[o].kind == after[n].kind { mapping[after[n].id] = before[o].id }
            oldGap.removeAll()
            newGap.removeAll()
        }
        while oldIndex < before.count || newIndex < after.count {
            if oldIndex < before.count, removed.contains(oldIndex) { oldGap.append(oldIndex); oldIndex += 1; continue }
            if newIndex < after.count, inserted.contains(newIndex) { newGap.append(newIndex); newIndex += 1; continue }
            pairGap()
            guard oldIndex < before.count, newIndex < after.count else { break }
            mapping[after[newIndex].id] = before[oldIndex].id
            oldIndex += 1
            newIndex += 1
        }
        pairGap()
        var page = new
        page.blocks = remap(new.blocks, mapping)
        return page
    }

    package static func mapSelection(_ selection: NotePageSelection, from old: NotePage, to new: NotePage) -> NotePageSelection {
        switch selection {
        case .none:
            return .none
        case .text(let anchor, let head):
            guard let mappedHead = mapPosition(head, from: old, to: new) else { return .none }
            if anchor == head { return .caret(mappedHead) }
            guard let mappedAnchor = mapPosition(anchor, from: old, to: new) else { return .caret(mappedHead) }
            return .text(anchor: mappedAnchor, head: mappedHead)
        case .blocks(let ids):
            let surviving = ids.filter { new.block($0) != nil }
            return surviving.isEmpty ? .none : .blocks(surviving)
        case .cells(let table, let anchor, let head):
            guard let rows = new.block(table)?.props.table?.rows,
                  [anchor, head].allSatisfy({ rows.indices.contains($0.row) && rows[$0.row].indices.contains($0.column) })
            else { return .none }
            return selection
        }
    }

    package static func mapPosition(_ position: NotePosition, from old: NotePage, to new: NotePage) -> NotePosition? {
        if let block = new.block(position.block), let length = length(of: position.field, in: block) {
            var mapped = position
            mapped.offset = min(max(0, position.offset), length)
            return mapped
        }
        let newOrder = new.documentOrder()
        guard !newOrder.isEmpty else { return nil }
        let oldOrder = old.documentOrder()
        let index = oldOrder.firstIndex(of: position.block) ?? 0
        let target = newOrder[min(index, newOrder.count - 1)]
        let length = new.block(target).map(\.text.length) ?? 0
        return NotePosition(target, min(max(0, position.offset), length))
    }

    private static func length(of field: NoteTextField, in block: NoteBlock) -> Int? {
        switch field {
        case .body:
            return block.text.length
        case .caption:
            return block.props.caption.length
        case .cell(let row, let column):
            guard let rows = block.props.table?.rows, rows.indices.contains(row), rows[row].indices.contains(column) else { return nil }
            return rows[row][column].length
        }
    }

    private static func signature(_ block: NoteBlock) -> Signature {
        Signature(kind: block.kind, text: block.text, props: block.props, color: block.color)
    }

    private static func remap(_ blocks: [NoteBlock], _ mapping: [NoteBlockID: NoteBlockID]) -> [NoteBlock] {
        blocks.map { block in
            var copy = block
            if let preserved = mapping[block.id] { copy.id = preserved }
            copy.children = remap(block.children, mapping)
            return copy
        }
    }
}
