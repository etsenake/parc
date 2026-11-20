import CoreGraphics
import Foundation

enum NoteSelectionRole: Hashable {
    case text
    case object
    case decoration
    case layout
    case column

    var isSteppable: Bool {
        switch self {
        case .text, .object, .decoration: return true
        case .layout, .column: return false
        }
    }
}

struct NoteSelectionItem: Hashable {
    var id: NoteBlockID
    var parent: NoteBlockID?
    var depth: Int
    var role: NoteSelectionRole
    var frame: CGRect
}

enum NoteSelectionMark: Hashable {
    case text(Range<Int>)
    case wash
}

enum NoteSelectionLanding: Hashable {
    case caret(NotePosition)
    case block(NoteBlockID)
}

enum NoteSelectionGranularity: Hashable {
    case character
    case word
    case paragraph
}

enum NoteSelectionHorizontalUnit: Hashable {
    case character
    case word
}

struct NoteBlockRange: Hashable {
    var anchor: NoteBlockID
    var head: NoteBlockID
}

enum NoteSelectionDragTarget: Hashable {
    case text(NoteBlockID)
    case position(NotePosition)
    case blocks([NoteBlockID])
}

@MainActor
protocol NoteSelectionLayout {
    var items: [NoteSelectionItem] { get }
    func length(of position: NotePosition) -> Int
    func caretX(at position: NotePosition) -> CGFloat?
    func lineOffset(from position: NotePosition, up: Bool, x: CGFloat) -> Int?
    func entryOffset(in block: NoteBlockID, x: CGFloat, fromAbove: Bool) -> Int
    func characterOffset(from position: NotePosition, forward: Bool) -> Int?
    func wordOffset(from position: NotePosition, forward: Bool) -> Int?
    func paragraphOffset(from position: NotePosition, forward: Bool) -> Int?
    func lineEdgeOffset(from position: NotePosition, forward: Bool) -> Int
    func wordRange(at position: NotePosition) -> Range<Int>
}

struct NoteGoalColumn: Hashable {
    private(set) var x: CGFloat?
    private(set) var head: NotePosition?

    mutating func value(for head: NotePosition, current: () -> CGFloat?) -> CGFloat? {
        if let x, self.head == head { return x }
        x = current()
        self.head = x == nil ? nil : head
        return x
    }

    mutating func moved(to head: NotePosition) {
        if x != nil { self.head = head }
    }

    mutating func reset() {
        x = nil
        head = nil
    }
}

enum NoteSelectionAnnouncement {
    static func blocks(_ count: Int) -> String {
        count == 1 ? "1 block selected" : "\(count) blocks selected"
    }

    static let cleared = "Selection cleared"
}

@MainActor
struct NoteSelectionNavigator {
    let items: [NoteSelectionItem]
    private let indexes: [NoteBlockID: Int]

    init(items: [NoteSelectionItem]) {
        self.items = items
        var indexes: [NoteBlockID: Int] = [:]
        for (index, item) in items.enumerated() { indexes[item.id] = index }
        self.indexes = indexes
    }

    func index(of id: NoteBlockID) -> Int? { indexes[id] }

    func item(_ id: NoteBlockID) -> NoteSelectionItem? { indexes[id].map { items[$0] } }

    func role(of id: NoteBlockID) -> NoteSelectionRole? { item(id)?.role }

    var topLevel: [NoteBlockID] { items.filter { $0.parent == nil }.map(\.id) }

    func precedes(_ a: NotePosition, _ b: NotePosition) -> Bool {
        if a.block == b.block { return a.offset < b.offset }
        return (index(of: a.block) ?? 0) < (index(of: b.block) ?? 0)
    }

    func ordered(_ a: NotePosition, _ b: NotePosition) -> (start: NotePosition, end: NotePosition) {
        precedes(b, a) ? (b, a) : (a, b)
    }

    func isAncestor(_ ancestor: NoteBlockID, of id: NoteBlockID) -> Bool {
        var current = item(id)?.parent
        while let parent = current {
            if parent == ancestor { return true }
            current = item(parent)?.parent
        }
        return false
    }

    func subtreeEnd(_ index: Int) -> Int {
        let depth = items[index].depth
        var end = index
        while end + 1 < items.count, items[end + 1].depth > depth { end += 1 }
        return end
    }

    func topLevel(_ ids: Set<NoteBlockID>) -> [NoteBlockID] {
        items.compactMap { item in
            guard ids.contains(item.id) else { return nil }
            var current = item.parent
            while let parent = current {
                if ids.contains(parent) { return nil }
                current = self.item(parent)?.parent
            }
            return item.id
        }
    }

    func normalized(_ ids: Set<NoteBlockID>) -> [NoteBlockID] {
        var chosen = ids.filter { role(of: $0).map { $0 != .column } ?? false }
        for (index, item) in items.enumerated() where item.role == .layout && !chosen.contains(item.id) {
            let end = subtreeEnd(index)
            guard end > index else { continue }
            let inner = items[(index + 1)...end].filter(\.role.isSteppable)
            if !inner.isEmpty && inner.allSatisfy({ chosen.contains($0.id) }) { chosen.insert(item.id) }
        }
        return topLevel(chosen)
    }

    func expanded(_ ids: [NoteBlockID]) -> [NoteBlockID] {
        var result: [NoteBlockID] = []
        var seen = Set<NoteBlockID>()
        for id in ids {
            guard let index = index(of: id) else { continue }
            for item in items[index...subtreeEnd(index)] where seen.insert(item.id).inserted { result.append(item.id) }
        }
        return result
    }

    func blocks(from anchor: NoteBlockID, to head: NoteBlockID) -> [NoteBlockID] {
        guard let a = index(of: anchor), let h = index(of: head) else { return normalized([anchor, head]) }
        let lower = min(a, h), upper = max(subtreeEnd(a), subtreeEnd(h))
        return normalized(Set(items[lower...upper].map(\.id)))
    }

    func covered(from anchor: NotePosition, to head: NotePosition) -> [NoteBlockID] {
        let (start, end) = ordered(anchor, head)
        guard let s = index(of: start.block), let e = index(of: end.block) else { return [] }
        return normalized(Set(items[s...e].map(\.id)))
    }

    func marks(from anchor: NotePosition, to head: NotePosition, length: (NoteBlockID) -> Int) -> [NoteBlockID: NoteSelectionMark] {
        let (start, end) = ordered(anchor, head)
        if start.block == end.block { return [start.block: .text(start.offset..<max(start.offset, end.offset))] }
        guard let s = index(of: start.block), let e = index(of: end.block) else { return [:] }
        var result: [NoteBlockID: NoteSelectionMark] = [:]
        for index in s...e {
            let item = items[index]
            switch item.role {
            case .text:
                let lower = index == s ? start.offset : 0
                let upper = index == e ? end.offset : length(item.id)
                result[item.id] = .text(lower..<max(lower, upper))
            case .object, .decoration:
                result[item.id] = .wash
            case .layout, .column:
                break
            }
        }
        return result
    }

    private func steppableIndex(after index: Int) -> Int? {
        var next = index + 1
        while next < items.count {
            if items[next].role.isSteppable { return next }
            next += 1
        }
        return nil
    }

    private func steppableIndex(before index: Int) -> Int? {
        var previous = index - 1
        while previous >= 0 {
            if items[previous].role.isSteppable { return previous }
            previous -= 1
        }
        return nil
    }

    func step(from selection: [NoteBlockID], forward: Bool) -> NoteBlockID? {
        let found = selection.compactMap { index(of: $0) }
        guard let first = found.min(), let last = found.max() else { return nil }
        if forward {
            let end = found.map(subtreeEnd).max() ?? last
            return steppableIndex(after: end).map { items[$0].id } ?? items[last].id
        }
        return steppableIndex(before: first).map { items[$0].id } ?? items[first].id
    }

    func extend(_ range: NoteBlockRange, forward: Bool) -> NoteBlockRange {
        guard let a = index(of: range.anchor), let h = index(of: range.head) else { return range }
        var next: Int?
        if forward {
            if h >= a {
                next = steppableIndex(after: subtreeEnd(h))
            } else {
                var candidate = h + 1
                while candidate < a, items[candidate].depth > items[h].depth || !items[candidate].role.isSteppable { candidate += 1 }
                next = candidate
            }
        } else {
            if h <= a {
                next = steppableIndex(before: h)
            } else {
                var candidate = h - 1
                while candidate > a, items[candidate].depth > items[h].depth || !items[candidate].role.isSteppable { candidate -= 1 }
                next = candidate
            }
        }
        guard let next else { return range }
        return NoteBlockRange(anchor: range.anchor, head: items[next].id)
    }

    func toggling(_ id: NoteBlockID, in selection: [NoteBlockID]) -> [NoteBlockID] {
        var chosen = Set(selection)
        if chosen.contains(id) {
            chosen.remove(id)
        } else if let ancestor = selection.first(where: { isAncestor($0, of: id) }), let start = index(of: ancestor) {
            var removed: Set<NoteBlockID> = [ancestor]
            var current = item(id)?.parent
            while let parent = current, parent != ancestor {
                removed.insert(parent)
                current = item(parent)?.parent
            }
            if let own = index(of: id) { for item in items[own...subtreeEnd(own)] { removed.insert(item.id) } }
            chosen.remove(ancestor)
            for item in items[start...subtreeEnd(start)] where !removed.contains(item.id) && item.role.isSteppable {
                chosen.insert(item.id)
            }
        } else {
            chosen.insert(id)
        }
        return normalized(chosen)
    }

    func ownFrame(at index: Int) -> CGRect {
        var frame = items[index].frame
        if index + 1 < items.count, items[index + 1].parent == items[index].id {
            let childTop = items[index + 1].frame.minY
            if childTop > frame.minY && childTop < frame.maxY { frame.size.height = childTop - frame.minY }
        }
        return frame
    }

    func marquee(_ rect: CGRect, column: ClosedRange<CGFloat>? = nil) -> [NoteBlockID] {
        var area = rect
        if let column, rect.maxX < column.lowerBound || rect.minX > column.upperBound {
            let minX = min(rect.minX, column.lowerBound), maxX = max(rect.maxX, column.upperBound)
            area = CGRect(x: minX, y: rect.minY, width: maxX - minX, height: max(rect.height, 1))
        }
        let hit = items.indices.filter { index in
            items[index].role.isSteppable && !items[index].frame.isEmpty && ownFrame(at: index).intersects(area)
        }
        return normalized(Set(hit.map { items[$0].id }))
    }

    func nearestItem(to point: CGPoint) -> NoteSelectionItem? {
        var best: (score: (CGFloat, CGFloat, Int), item: NoteSelectionItem)?
        for index in items.indices where items[index].role.isSteppable {
            let frame = ownFrame(at: index)
            guard !frame.isEmpty else { continue }
            let dy = point.y < frame.minY ? frame.minY - point.y : (point.y > frame.maxY ? point.y - frame.maxY : 0)
            let dx = point.x < frame.minX ? frame.minX - point.x : (point.x > frame.maxX ? point.x - frame.maxX : 0)
            let score = (dy, dx, -items[index].depth)
            if best.map({ score < $0.score }) ?? true { best = (score, items[index]) }
        }
        return best?.item
    }

    func caretNeighbour(of id: NoteBlockID, forward: Bool) -> NoteSelectionItem? {
        guard var index = index(of: id) else { return nil }
        while true {
            index += forward ? 1 : -1
            guard items.indices.contains(index) else { return nil }
            switch items[index].role {
            case .text, .object: return items[index]
            case .decoration, .layout, .column: continue
            }
        }
    }

    func textNeighbour(of id: NoteBlockID, forward: Bool) -> NoteSelectionItem? {
        guard var index = index(of: id) else { return nil }
        while true {
            index += forward ? 1 : -1
            guard items.indices.contains(index) else { return nil }
            if items[index].role == .text { return items[index] }
        }
    }

    var documentStart: NotePosition? {
        items.first { $0.role == .text }.map { NotePosition($0.id, 0) }
    }

    func documentEnd(_ layout: NoteSelectionLayout) -> NotePosition? {
        items.last { $0.role == .text }.map { NotePosition($0.id, layout.length(of: NotePosition($0.id, 0))) }
    }

    func verticalLanding(from position: NotePosition, up: Bool, x: CGFloat, layout: NoteSelectionLayout) -> NoteSelectionLanding {
        if let offset = layout.lineOffset(from: position, up: up, x: x) {
            return .caret(NotePosition(position.block, offset, field: position.field))
        }
        if position.field != .body && up { return .block(position.block) }
        guard let next = caretNeighbour(of: position.block, forward: !up) else {
            return .caret(NotePosition(position.block, up ? 0 : layout.length(of: position), field: position.field))
        }
        if next.role == .text { return .caret(NotePosition(next.id, layout.entryOffset(in: next.id, x: x, fromAbove: !up))) }
        return .block(next.id)
    }

    func verticalHead(from head: NotePosition, up: Bool, x: CGFloat, layout: NoteSelectionLayout) -> NotePosition {
        if let offset = layout.lineOffset(from: head, up: up, x: x) {
            return NotePosition(head.block, offset, field: head.field)
        }
        guard head.field == .body, let next = textNeighbour(of: head.block, forward: !up) else {
            return NotePosition(head.block, up ? 0 : layout.length(of: head), field: head.field)
        }
        return NotePosition(next.id, layout.entryOffset(in: next.id, x: x, fromAbove: !up))
    }

    private func step(_ position: NotePosition, forward: Bool, unit: NoteSelectionHorizontalUnit, layout: NoteSelectionLayout) -> Int? {
        switch unit {
        case .character: return layout.characterOffset(from: position, forward: forward)
        case .word: return layout.wordOffset(from: position, forward: forward)
        }
    }

    private func entry(_ next: NoteBlockID, forward: Bool, unit: NoteSelectionHorizontalUnit, layout: NoteSelectionLayout) -> NotePosition {
        let edge = NotePosition(next, forward ? 0 : layout.length(of: NotePosition(next, 0)))
        guard unit == .word, let moved = layout.wordOffset(from: edge, forward: forward) else { return edge }
        return NotePosition(next, moved)
    }

    func horizontalLanding(from position: NotePosition, forward: Bool, unit: NoteSelectionHorizontalUnit,
                           layout: NoteSelectionLayout) -> NoteSelectionLanding? {
        if let offset = step(position, forward: forward, unit: unit, layout: layout) {
            return .caret(NotePosition(position.block, offset, field: position.field))
        }
        guard position.field == .body, let next = caretNeighbour(of: position.block, forward: forward) else { return nil }
        if next.role == .text { return .caret(entry(next.id, forward: forward, unit: unit, layout: layout)) }
        return .block(next.id)
    }

    func horizontalHead(from head: NotePosition, forward: Bool, unit: NoteSelectionHorizontalUnit, layout: NoteSelectionLayout) -> NotePosition {
        if let offset = step(head, forward: forward, unit: unit, layout: layout) {
            return NotePosition(head.block, offset, field: head.field)
        }
        guard head.field == .body, let next = textNeighbour(of: head.block, forward: forward) else { return head }
        return entry(next.id, forward: forward, unit: unit, layout: layout)
    }

    func paragraphHead(from head: NotePosition, forward: Bool, layout: NoteSelectionLayout) -> NotePosition {
        if let offset = layout.paragraphOffset(from: head, forward: forward) {
            return NotePosition(head.block, offset, field: head.field)
        }
        guard head.field == .body, let next = textNeighbour(of: head.block, forward: forward) else { return head }
        let edge = NotePosition(next.id, forward ? 0 : layout.length(of: NotePosition(next.id, 0)))
        return layout.paragraphOffset(from: edge, forward: forward).map { NotePosition(next.id, $0) } ?? edge
    }

    func span(anchor: NoteBlockID, anchorRange: Range<Int>, head: NoteBlockID, headRange: Range<Int>) -> (anchor: NotePosition, head: NotePosition) {
        let forward = anchor == head
            ? headRange.lowerBound >= anchorRange.lowerBound
            : (index(of: head) ?? 0) > (index(of: anchor) ?? 0)
        if forward {
            let end = anchor == head ? max(headRange.upperBound, anchorRange.upperBound) : headRange.upperBound
            return (NotePosition(anchor, anchorRange.lowerBound), NotePosition(head, end))
        }
        return (NotePosition(anchor, anchorRange.upperBound), NotePosition(head, headRange.lowerBound))
    }

    func granularRange(at position: NotePosition, granularity: NoteSelectionGranularity, layout: NoteSelectionLayout) -> Range<Int> {
        switch granularity {
        case .character: return position.offset..<position.offset
        case .word: return layout.wordRange(at: position)
        case .paragraph: return 0..<layout.length(of: position)
        }
    }

    func dragTarget(anchor: NoteBlockID, pointer: NoteSelectionItem?, outsideColumn: Bool, layout: NoteSelectionLayout) -> NoteSelectionDragTarget {
        guard let pointer else { return .text(anchor) }
        if outsideColumn { return .blocks(blocks(from: anchor, to: pointer.id)) }
        switch pointer.role {
        case .text:
            return .text(pointer.id)
        case .object, .layout, .column:
            return .blocks(blocks(from: anchor, to: pointer.id))
        case .decoration:
            let forward = (index(of: pointer.id) ?? 0) > (index(of: anchor) ?? 0)
            guard let next = textNeighbour(of: pointer.id, forward: forward) else { return .blocks(blocks(from: anchor, to: pointer.id)) }
            return .position(NotePosition(next.id, forward ? 0 : layout.length(of: NotePosition(next.id, 0))))
        }
    }

    func selectAllStep(_ selection: NotePageSelection, layout: NoteSelectionLayout) -> NotePageSelection {
        let all = topLevel
        switch selection {
        case .text(let anchor, let head):
            guard anchor.block == head.block && anchor.field == head.field else { return .blocks(all) }
            let length = layout.length(of: head)
            let range = min(anchor.offset, head.offset)..<max(anchor.offset, head.offset)
            if length > 0 && range != 0..<length {
                return .text(anchor: NotePosition(head.block, 0, field: head.field), head: NotePosition(head.block, length, field: head.field))
            }
            return .blocks([head.block])
        case .cells(let table, _, _):
            return .blocks([table])
        case .blocks, .none:
            return .blocks(all)
        }
    }

    func escapeStep(_ selection: NotePageSelection) -> NotePageSelection {
        switch selection {
        case .text(let anchor, let head):
            if anchor.block == head.block { return .blocks([head.block]) }
            let covered = covered(from: anchor, to: head)
            return covered.isEmpty ? .none : .blocks(covered)
        case .cells(let table, _, _):
            return .blocks([table])
        case .blocks, .none:
            return .none
        }
    }
}
