import CoreGraphics
import Foundation
import ParcCore

struct NoteCanvasInsets: Equatable {
    var top: CGFloat
    var left: CGFloat
    var bottom: CGFloat
    var right: CGFloat

    func scaled(_ factor: CGFloat) -> NoteCanvasInsets {
        NoteCanvasInsets(top: top * factor, left: left * factor, bottom: bottom * factor, right: right * factor)
    }
}

struct NoteCanvasSpacing: Equatable {
    var before: CGFloat
    var after: CGFloat
}

struct NoteCanvasMetrics: Equatable {
    var columnWidth: CGFloat = 720
    var pageSideMargin: CGFloat = 96
    var minimumSideMargin: CGFloat = 28
    var fullWidth = false
    var indentWidth: CGFloat = 26
    var columnGap: CGFloat = 46
    var gutterWidth: CGFloat = 46
    var minimumColumnWidth: CGFloat = 64
    var maximumColumns = 5
    var topInset: CGFloat = 64
    var headerGap: CGFloat = 4
    var bottomInset: CGFloat = 160
    var bottomViewportFraction: CGFloat = 0.3
    var calloutInsets = NoteCanvasInsets(top: 14, left: 14, bottom: 14, right: 18)
    var calloutChildIndent: CGFloat = 46
    var quoteChildIndent: CGFloat = 17
    var quoteBarWidth: CGFloat = 3
    var quoteBarInset: CGFloat = 1
    var toggleHintHeight: CGFloat = 28
    var syncedHeaderHeight: CGFloat = 8
    var syncedFooterHeight: CGFloat = 8
    var washOutsetX: CGFloat = 4
    var washOutsetY: CGFloat = 1
    var scale: CGFloat = 1
    var bodyLineHeight: CGFloat = 26
    var headingLineHeights: [CGFloat] = [40, 33, 28, 25, 24, 23]
    var codeLineHeight: CGFloat = 21
    var averageCharacterWidth: CGFloat = 8.4
    var dragLeadOffset: CGFloat = 26

    var blockSpacing: CGFloat = 2

    var textSpacing: NoteCanvasSpacing { NoteCanvasSpacing(before: blockSpacing, after: blockSpacing) }

    var slotGap: CGFloat { max(8 * scale, blockSpacing * 2) }

    func spacing(for block: NoteBlock) -> NoteCanvasSpacing {
        let value: (before: CGFloat, after: CGFloat)
        switch block.kind {
        case .paragraph, .bulletedItem, .numberedItem, .todo, .toggle, .quote, .divider, .pageLink, .tableOfContents, .breadcrumb, .html, .raw:
            return textSpacing
        case .heading:
            switch block.props.level {
            case 1: value = (12, 4)
            case 2: value = (8, 3)
            case 3: value = (6, 2)
            default: value = (4, 2)
            }
        case .callout, .code, .table, .image, .video, .audio, .file, .pdf, .embed, .easel, .bookmark, .equation: value = (6, 6)
        case .button: value = (4, 4)
        case .columns: value = (4, 4)
        case .synced: value = (4, 4)
        case .column: value = (0, 0)
        }
        return NoteCanvasSpacing(before: max(blockSpacing, (value.before * scale).rounded()),
                                 after: max(blockSpacing, (value.after * scale).rounded()))
    }

    func childIndent(of block: NoteBlock) -> CGFloat {
        switch block.kind {
        case .callout: return block.calloutDisplayIcon == nil ? calloutInsets.left : calloutChildIndent
        case .quote: return quoteChildIndent
        case .synced: return 0
        default: return indentWidth
        }
    }

    func headingLineHeight(_ level: Int) -> CGFloat {
        guard !headingLineHeights.isEmpty else { return bodyLineHeight }
        return headingLineHeights[min(max(level, 1), headingLineHeights.count) - 1]
    }

    func pageColumn(width: CGFloat) -> (x: CGFloat, width: CGFloat) {
        let normal = min(columnWidth, max(0, width - minimumSideMargin * 2))
        let used = fullWidth ? max(normal, width - pageSideMargin * 2) : normal
        return (((width - used) / 2).rounded(.down), used)
    }
}

struct NoteCanvasMeasure {
    var height: (NoteBlock, CGFloat) -> CGFloat
    var childIndent: (NoteBlock) -> CGFloat
}

struct NoteCanvasEntry: Equatable {
    var id: NoteBlockID
    var kind: NoteBlockKind
    var parent: Int?
    var previousSibling: Int?
    var nextSibling: Int?
    var depth: Int
    var flow: Int
    var flowPosition: Int
    var frame: CGRect = .zero
    var outerFrame: CGRect = .zero
    var childX: CGFloat = 0
    var subtreeEnd: Int
    var acceptsChildren: Bool
    var isToggle: Bool
    var isCollapsed: Bool
    var hasVisibleChildren = false
    var listOrdinal: Int?

    var isRow: Bool { flowPosition >= 0 }
}

struct NoteCanvasWash: Equatable {
    var key: NoteBlockID
    var rect: CGRect
}

struct NoteCanvasDecoration: Equatable {
    enum Style: Hashable {
        case callout(NoteColorStyle?)
        case background(NoteColor)
        case quoteBar(NoteColor?)
    }

    struct Key: Hashable {
        var owner: NoteBlockID
        var slot: Int
    }

    var key: Key
    var style: Style
    var rect: CGRect
    var depth: Int
}

enum NoteCanvasDropAction: Equatable {
    case move(NoteInsertion)
    case placeBeside(NoteBlockID, NoteDropSide)
}

struct NoteCanvasDropTarget: Equatable {
    enum Indicator: Equatable {
        case horizontal(x: CGFloat, y: CGFloat, width: CGFloat)
        case vertical(x: CGFloat, y: CGFloat, height: CGFloat)
    }

    var action: NoteCanvasDropAction
    var indicator: Indicator
    var depth: Int

    var isVertical: Bool {
        if case .vertical = indicator { return true }
        return false
    }

    func lineRect(thickness: CGFloat) -> CGRect {
        switch indicator {
        case .horizontal(let x, let y, let width):
            return CGRect(x: x, y: y - thickness / 2, width: max(thickness, width), height: thickness)
        case .vertical(let x, let y, let height):
            return CGRect(x: x - thickness / 2, y: y, width: thickness, height: max(thickness, height))
        }
    }

    @MainActor
    func perform(moving ids: [NoteBlockID], in session: NotePageSession) {
        switch action {
        case .move(let insertion): session.moveBlocks(ids, to: insertion)
        case .placeBeside(let target, let side): session.placeBeside(ids, target: target, side: side)
        }
    }
}

struct NoteCanvasTransition: Equatable {
    struct Group: Equatable {
        var owner: NoteBlockID
        var ids: [NoteBlockID]
        var top: CGFloat
        var height: CGFloat
    }

    var isStructural = false
    var inserted: [NoteBlockID] = []
    var removed: [NoteBlockID] = []
    var merged: Set<NoteBlockID> = []
    var moved: [NoteBlockID: CGVector] = [:]
    var revealed: [Group] = []
    var concealed: [Group] = []

    init() {}

    init(from old: NoteCanvasLayout, to new: NoteCanvasLayout) {
        isStructural = !old.hasSameStructure(as: new)
        guard isStructural else { return }
        var revealedIDs = Set<NoteBlockID>()
        var concealedIDs = Set<NoteBlockID>()
        for (index, entry) in new.entries.enumerated() where entry.isToggle {
            guard let previous = old.entry(entry.id), previous.isCollapsed != entry.isCollapsed,
                  let oldIndex = old.index(of: entry.id) else { continue }
            if entry.isCollapsed {
                let ids = old.entries[(oldIndex + 1)..<previous.subtreeEnd].map(\.id)
                concealedIDs.formUnion(ids)
                concealed.append(Group(owner: entry.id, ids: ids, top: previous.frame.maxY,
                                       height: max(0, previous.outerFrame.maxY - previous.frame.maxY)))
            } else {
                let ids = new.entries[(index + 1)..<entry.subtreeEnd].map(\.id)
                revealedIDs.formUnion(ids)
                revealed.append(Group(owner: entry.id, ids: ids, top: entry.frame.maxY,
                                      height: max(0, entry.outerFrame.maxY - entry.frame.maxY)))
            }
        }
        for entry in new.entries where old.index(of: entry.id) == nil && !revealedIDs.contains(entry.id) {
            inserted.append(entry.id)
        }
        for (index, entry) in old.entries.enumerated() where new.index(of: entry.id) == nil && !concealedIDs.contains(entry.id) {
            removed.append(entry.id)
            if Self.wasMerged(index, old: old, new: new) { merged.insert(entry.id) }
        }
        for entry in new.entries {
            guard let previous = old.entry(entry.id) else { continue }
            let delta = CGVector(dx: previous.frame.minX - entry.frame.minX, dy: previous.frame.minY - entry.frame.minY)
            if abs(delta.dx) > 0.5 || abs(delta.dy) > 0.5 { moved[entry.id] = delta }
        }
    }

    private static func wasMerged(_ index: Int, old: NoteCanvasLayout, new: NoteCanvasLayout) -> Bool {
        guard index > 0, let removed = old.blocks[old.entries[index].id],
              removed.kind.hasRichText || removed.kind.hasPlainText, !removed.text.isEmpty else { return false }
        let previousID = old.entries[index - 1].id
        guard let before = old.blocks[previousID], let after = new.blocks[previousID] else { return false }
        return before.text.string != after.text.string && after.text.string.hasSuffix(removed.text.string)
    }
}

struct NoteCanvasLayout {
    struct ColumnsRow: Equatable {
        var id: NoteBlockID
        var frame: CGRect
        var columns: [NoteBlockID]
        var columnFrames: [CGRect]
        var flows: [Int]
        var fractions: [CGFloat]
        var available: CGFloat
        var gap: CGFloat

        func gapRect(after index: Int) -> CGRect {
            guard index >= 0, index + 1 < columnFrames.count else { return .zero }
            let left = columnFrames[index], right = columnFrames[index + 1]
            return CGRect(x: left.maxX, y: frame.minY, width: max(0, right.minX - left.maxX), height: frame.height)
        }

        func columnIndex(atX x: CGFloat) -> Int {
            for (index, column) in columnFrames.enumerated() where x < column.maxX + gap / 2 { return index }
            return max(0, columnFrames.count - 1)
        }
    }

    private struct Context {
        var measure: NoteCanvasMeasure
        var overrides: [NoteBlockID: [CGFloat]]
    }

    private(set) var metrics: NoteCanvasMetrics
    private(set) var width: CGFloat
    private(set) var columnX: CGFloat
    private(set) var columnWidth: CGFloat
    private(set) var contentTop: CGFloat
    private(set) var contentBottom: CGFloat
    private(set) var entries: [NoteCanvasEntry] = []
    private(set) var blocks: [NoteBlockID: NoteBlock] = [:]
    private(set) var columnsRows: [NoteBlockID: ColumnsRow] = [:]
    private(set) var flows: [[Int]] = [[]]
    private(set) var isFlat = false
    private var flowBottoms: [CGFloat] = [0]
    private var indexByID: [NoteBlockID: Int] = [:]

    static let empty = NoteCanvasLayout(page: NotePage(), width: 0, headerHeight: 0, metrics: NoteCanvasMetrics(),
                                        measure: NoteCanvasMeasure(height: { _, _ in 0 }, childIndent: { _ in 0 }))

    init(page: NotePage, width: CGFloat, headerHeight: CGFloat, metrics: NoteCanvasMetrics,
         columnFractions overrides: [NoteBlockID: [CGFloat]] = [:], flat: Bool = false, measure: NoteCanvasMeasure) {
        self.metrics = metrics
        isFlat = flat
        self.width = width
        let column = metrics.pageColumn(width: width)
        columnX = column.x
        columnWidth = column.width
        contentTop = headerHeight > 0 ? headerHeight + metrics.headerGap : metrics.topInset
        contentBottom = contentTop
        let context = Context(measure: measure, overrides: overrides)
        let result = layoutList(page.blocks, parent: nil, x: column.x, width: column.width, top: contentTop,
                                leadingAfter: nil, depth: 0, flow: 0, context: context)
        contentBottom = result.bottom
        flowBottoms[0] = result.bottom
    }

    var isEmpty: Bool { entries.isEmpty }

    var columnRect: CGRect { CGRect(x: columnX, y: 0, width: columnWidth, height: contentBottom) }

    func index(of id: NoteBlockID) -> Int? { indexByID[id] }

    mutating func refresh(_ block: NoteBlock) {
        guard indexByID[block.id] != nil else { return }
        blocks[block.id] = block
    }

    func entry(_ id: NoteBlockID) -> NoteCanvasEntry? { indexByID[id].map { entries[$0] } }

    func frame(of id: NoteBlockID) -> CGRect? { entry(id)?.frame }

    func outerFrame(of id: NoteBlockID) -> CGRect? { entry(id)?.outerFrame }

    func listOrdinal(of id: NoteBlockID) -> Int? { entry(id)?.listOrdinal }

    func documentHeight(viewportHeight: CGFloat) -> CGFloat {
        max(viewportHeight, contentBottom + max(metrics.bottomInset, viewportHeight * metrics.bottomViewportFraction))
    }

    func hasSameStructure(as other: NoteCanvasLayout) -> Bool {
        guard entries.count == other.entries.count else { return false }
        for index in entries.indices {
            let mine = entries[index], theirs = other.entries[index]
            if mine.id != theirs.id || mine.isCollapsed != theirs.isCollapsed { return false }
            if mine.parent.map({ entries[$0].id }) != theirs.parent.map({ other.entries[$0].id }) { return false }
        }
        return true
    }

    func ancestors(of id: NoteBlockID) -> [NoteBlockID] {
        var result: [NoteBlockID] = []
        var parent = entry(id)?.parent
        while let index = parent {
            result.append(entries[index].id)
            parent = entries[index].parent
        }
        return result
    }

    func gutterRect(for id: NoteBlockID) -> CGRect? {
        guard let entry = entry(id), entry.isRow, entry.kind != .columns else { return nil }
        let leading = entry.kind == .callout ? entry.outerFrame.minX : entry.frame.minX
        return CGRect(x: leading - metrics.gutterWidth, y: entry.frame.minY, width: metrics.gutterWidth, height: entry.frame.height)
    }

    func blockID(at point: CGPoint) -> NoteBlockID? {
        locateRow(point, flow: 0, clamp: false).map { entries[$0].id }
    }

    func blockIDs(in rect: CGRect) -> [NoteBlockID] {
        entries.filter { $0.isRow && $0.kind != .columns && $0.frame.intersects(rect) }.map(\.id)
    }

    func entries(intersecting rect: CGRect) -> [NoteCanvasEntry] {
        entries.filter { $0.outerFrame.intersects(rect) || $0.frame.intersects(rect) }
    }

    func washRects(for ids: some Sequence<NoteBlockID>) -> [NoteCanvasWash] {
        let indices = Set(ids.compactMap { indexByID[$0] })
        guard !indices.isEmpty else { return [] }
        let roots = indices.filter { index in
            var parent = entries[index].parent
            while let ancestor = parent {
                if indices.contains(ancestor) { return false }
                parent = entries[ancestor].parent
            }
            return true
        }.sorted()
        var result: [NoteCanvasWash] = []
        var run: (key: NoteBlockID, rect: CGRect, last: Int)?
        for index in roots {
            let rect = washFrame(entries[index])
            if let current = run, entries[current.last].nextSibling == index {
                run = (current.key, current.rect.union(rect), index)
            } else {
                if let current = run { result.append(NoteCanvasWash(key: current.key, rect: current.rect)) }
                run = (entries[index].id, rect, index)
            }
        }
        if let current = run { result.append(NoteCanvasWash(key: current.key, rect: current.rect)) }
        return result
    }

    func decorations(in region: CGRect) -> [NoteCanvasDecoration] {
        let result = entries.filter { $0.isRow && $0.outerFrame.insetBy(dx: -8, dy: -8).intersects(region) }.flatMap(decorations(for:))
        return Self.paintingOrder(result)
    }

    func decorations(of ids: some Sequence<NoteBlockID>) -> [NoteCanvasDecoration] {
        Self.paintingOrder(ids.compactMap { entry($0) }.filter(\.isRow).flatMap(decorations(for:)))
    }

    private static func paintingOrder(_ decorations: [NoteCanvasDecoration]) -> [NoteCanvasDecoration] {
        decorations.sorted { lhs, rhs in
            let left = lhs.key.slot == 1 ? 1 : 0, right = rhs.key.slot == 1 ? 1 : 0
            return left != right ? left < right : lhs.depth < rhs.depth
        }
    }

    private func decorations(for entry: NoteCanvasEntry) -> [NoteCanvasDecoration] {
        guard let block = blocks[entry.id] else { return [] }
        var result: [NoteCanvasDecoration] = []
        let outset = metrics.washOutsetY * metrics.scale
        if entry.kind == .callout {
            result.append(NoteCanvasDecoration(key: .init(owner: entry.id, slot: 0), style: .callout(block.calloutDisplayColor),
                                               rect: entry.outerFrame, depth: entry.depth))
        } else if case .background(let color) = block.color, entry.kind != .columns {
            result.append(NoteCanvasDecoration(key: .init(owner: entry.id, slot: 0), style: .background(color),
                                               rect: entry.outerFrame.insetBy(dx: -metrics.washOutsetX, dy: -outset),
                                               depth: entry.depth))
        }
        if entry.kind == .quote, entry.hasVisibleChildren, entry.outerFrame.maxY > entry.frame.maxY {
            var ink: NoteColor?
            if case .text(let color) = block.color { ink = color }
            let bar = CGRect(x: entry.frame.minX + metrics.quoteBarInset, y: entry.frame.maxY, width: metrics.quoteBarWidth,
                             height: entry.outerFrame.maxY - entry.frame.maxY)
            result.append(NoteCanvasDecoration(key: .init(owner: entry.id, slot: 1), style: .quoteBar(ink), rect: bar,
                                               depth: entry.depth))
        }
        return result
    }

    func dropTarget(at point: CGPoint, dragging ids: [NoteBlockID], leadingX: CGFloat? = nil) -> NoteCanvasDropTarget? {
        guard let index = locateRow(point, flow: 0, clamp: true) else { return nil }
        let excluded = excludedIndices(ids)
        guard !excluded.contains(index) else { return nil }
        let target = entries[index]
        if !isFlat, let side = columnSide(for: index, point: point, dragging: ids) { return besideTarget(index, side: side) }
        if !isFlat, target.isToggle, !target.isCollapsed, !target.hasVisibleChildren,
           point.y > target.frame.maxY - metrics.toggleHintHeight, target.frame.height > metrics.toggleHintHeight {
            let y = target.frame.maxY - metrics.toggleHintHeight / 2
            return NoteCanvasDropTarget(action: .move(.firstChild(of: target.id)),
                                        indicator: .horizontal(x: target.childX, y: y, width: max(0, target.frame.maxX - target.childX)),
                                        depth: target.depth + 1)
        }
        if point.y < target.frame.midY {
            return NoteCanvasDropTarget(action: .move(.before(target.id)),
                                        indicator: .horizontal(x: target.outerFrame.minX, y: slotAbove(index),
                                                               width: target.outerFrame.width),
                                        depth: target.depth)
        }
        let lead = leadingX ?? point.x + metrics.dragLeadOffset
        var candidates: [(insertion: NoteInsertion, x: CGFloat, y: CGFloat, maxX: CGFloat, depth: Int)] = []
        if target.kind == .columns {
            candidates.append((.after(target.id), target.outerFrame.minX, slotBelow(index), target.outerFrame.maxX, target.depth))
        } else if !isFlat, target.hasVisibleChildren, index + 1 < entries.count {
            let y = (target.frame.maxY + entries[index + 1].outerFrame.minY) / 2
            candidates.append((.firstChild(of: target.id), target.childX, y, target.frame.maxX, target.depth + 1))
        } else {
            if target.acceptsChildren && target.kind != .column && !isFlat {
                let room = target.outerFrame.maxY - target.frame.maxY
                let y = room > 0.5 ? target.frame.maxY + min(room / 2, metrics.slotGap / 2) : slotBelow(index)
                candidates.append((target.isCollapsed ? .lastChild(of: target.id) : .firstChild(of: target.id),
                                   target.childX, y, target.frame.maxX, target.depth + 1))
            }
            candidates.append((.after(target.id), target.outerFrame.minX, slotBelow(index), target.outerFrame.maxX, target.depth))
            var current = index
            while entries[current].nextSibling == nil, let parent = entries[current].parent,
                  entries[parent].kind != .column, entries[parent].kind != .columns {
                let ancestor = entries[parent]
                candidates.append((.after(ancestor.id), ancestor.outerFrame.minX, slotBelow(parent), ancestor.outerFrame.maxX,
                                   ancestor.depth))
                current = parent
            }
        }
        guard var best = candidates.first else { return nil }
        for candidate in candidates.dropFirst() where abs(candidate.x - lead) < abs(best.x - lead) { best = candidate }
        return NoteCanvasDropTarget(action: .move(best.insertion),
                                    indicator: .horizontal(x: best.x, y: best.y, width: max(0, best.maxX - best.x)),
                                    depth: best.depth)
    }

    static func normalizedFractions(_ raw: [CGFloat?], count: Int) -> [CGFloat] {
        guard count > 0 else { return [] }
        let values: [CGFloat?] = (0..<count).map { index in
            guard index < raw.count, let value = raw[index], value.isFinite, value > 0 else { return nil }
            return value
        }
        let known = values.compactMap { $0 }
        let fallback = known.isEmpty ? 1 / CGFloat(count) : known.reduce(0, +) / CGFloat(known.count)
        let filled = values.map { $0 ?? fallback }
        let total = filled.reduce(0, +)
        return filled.map { $0 / total }
    }

    static func resizedFractions(_ fractions: [CGFloat], divider: Int, delta: CGFloat, available: CGFloat,
                                 minimumWidth: CGFloat) -> [CGFloat] {
        guard divider >= 0, divider + 1 < fractions.count, available > 0 else { return fractions }
        var result = fractions
        let pair = fractions[divider] + fractions[divider + 1]
        let floor = min(pair / 2, minimumWidth / available)
        let left = min(max(fractions[divider] + delta / available, floor), pair - floor)
        result[divider] = left
        result[divider + 1] = pair - left
        return result
    }

    private func washFrame(_ entry: NoteCanvasEntry) -> CGRect {
        let base = entry.kind == .column ? entry.frame : entry.outerFrame
        return base.insetBy(dx: -metrics.washOutsetX, dy: -metrics.washOutsetY * metrics.scale)
    }

    private func excludedIndices(_ ids: [NoteBlockID]) -> Set<Int> {
        var result = Set<Int>()
        for id in ids {
            guard let index = indexByID[id] else { continue }
            result.formUnion(index..<max(index + 1, entries[index].subtreeEnd))
        }
        return result
    }

    private func locateRow(_ point: CGPoint, flow: Int, clamp: Bool) -> Int? {
        guard flows.indices.contains(flow) else { return nil }
        let rows = flows[flow]
        guard !rows.isEmpty else { return nil }
        var low = 0, high = rows.count - 1
        while low < high {
            let middle = (low + high + 1) / 2
            let boundary = (entries[rows[middle - 1]].frame.maxY + entries[rows[middle]].frame.minY) / 2
            if boundary <= point.y { low = middle } else { high = middle - 1 }
        }
        let index = rows[low]
        if !clamp {
            let slack = metrics.slotGap
            if low == 0 && point.y < entries[index].outerFrame.minY - slack { return nil }
            if low == rows.count - 1 && point.y > flowBottoms[flow] + slack { return nil }
        }
        if entries[index].kind == .columns, let row = columnsRows[entries[index].id], !row.flows.isEmpty {
            let column = row.columnIndex(atX: point.x)
            if let inner = locateRow(point, flow: row.flows[column], clamp: clamp) { return inner }
            return clamp ? index : nil
        }
        return index
    }

    private func slotAbove(_ index: Int) -> CGFloat {
        let entry = entries[index]
        let top = entry.outerFrame.minY
        var previousBottom = top - metrics.slotGap
        if let previous = entry.previousSibling, entries[previous].kind != .column {
            previousBottom = entries[previous].outerFrame.maxY
        } else if let parent = entry.parent, entries[parent].kind != .column, entries[parent].kind != .columns {
            previousBottom = entries[parent].frame.maxY
        } else if entry.flowPosition > 0 {
            previousBottom = entries[flows[entry.flow][entry.flowPosition - 1]].outerFrame.maxY
        }
        return (previousBottom + top) / 2
    }

    private func slotBelow(_ index: Int) -> CGFloat {
        let entry = entries[index]
        let bottom = entry.outerFrame.maxY
        if let next = entry.nextSibling, entries[next].kind != .column {
            return (bottom + entries[next].outerFrame.minY) / 2
        }
        guard let parent = entry.parent else { return bottom + metrics.slotGap / 2 }
        let room = entries[parent].outerFrame.maxY - bottom
        if room > 0.5 { return bottom + min(room / 2, metrics.slotGap / 2) }
        return slotBelow(parent)
    }

    private func containsColumns(_ block: NoteBlock) -> Bool {
        block.kind == .columns || block.kind == .column || block.children.contains { containsColumns($0) }
    }

    private func columnSide(for index: Int, point: CGPoint, dragging ids: [NoteBlockID]) -> NoteDropSide? {
        let entry = entries[index]
        guard entry.isRow, entry.kind != .columns else { return nil }
        if ids.contains(where: { id in blocks[id].map(containsColumns) ?? false }) { return nil }
        var leading = entry.kind == .callout ? entry.outerFrame.minX : entry.frame.minX
        var trailing = entry.outerFrame.maxX
        if let parent = entry.parent {
            let column = entries[parent]
            guard column.kind == .column, let rowIndex = column.parent, let row = columnsRows[entries[rowIndex].id],
                  row.columns.count < metrics.maximumColumns else { return nil }
            leading = column.frame.minX
            trailing = column.frame.maxX
        }
        let span = max(0, trailing - leading)
        if point.x < leading - metrics.gutterWidth { return .left }
        if point.x > trailing - min(span * 0.2, 140) { return .right }
        return nil
    }

    private func besideTarget(_ index: Int, side: NoteDropSide) -> NoteCanvasDropTarget {
        let entry = entries[index]
        let edge: CGFloat = 6
        if let parent = entry.parent, entries[parent].kind == .column, let rowIndex = entries[parent].parent,
           let row = columnsRows[entries[rowIndex].id], let position = row.columns.firstIndex(of: entries[parent].id) {
            let column = row.columnFrames[position]
            let x: CGFloat
            if side == .left { x = position == 0 ? column.minX - edge : column.minX - row.gap / 2 }
            else { x = position == row.columns.count - 1 ? column.maxX + edge : column.maxX + row.gap / 2 }
            return NoteCanvasDropTarget(action: .placeBeside(entry.id, side),
                                        indicator: .vertical(x: x, y: row.frame.minY, height: row.frame.height),
                                        depth: entry.depth)
        }
        let box = entry.outerFrame
        return NoteCanvasDropTarget(action: .placeBeside(entry.id, side),
                                    indicator: .vertical(x: side == .left ? box.minX - edge : box.maxX + edge, y: box.minY,
                                                         height: box.height),
                                    depth: entry.depth)
    }

    private mutating func append(_ block: NoteBlock, parent: Int?, previous: Int?, depth: Int, flow: Int, isRow: Bool,
                                 ordinal: Int?) -> Int {
        let index = entries.count
        var position = -1
        if isRow {
            position = flows[flow].count
            flows[flow].append(index)
        }
        entries.append(NoteCanvasEntry(id: block.id, kind: block.kind, parent: parent, previousSibling: previous, nextSibling: nil,
                                       depth: depth, flow: flow, flowPosition: position, subtreeEnd: index + 1,
                                       acceptsChildren: block.acceptsChildren, isToggle: block.isToggle,
                                       isCollapsed: block.isToggle && !block.props.expanded, listOrdinal: ordinal))
        indexByID[block.id] = index
        blocks[block.id] = block
        if let previous { entries[previous].nextSibling = index }
        return index
    }

    private mutating func makeFlow() -> Int {
        flows.append([])
        flowBottoms.append(0)
        return flows.count - 1
    }

    private mutating func layoutList(_ list: [NoteBlock], parent: Int?, x: CGFloat, width: CGFloat, top: CGFloat,
                                     leadingAfter: CGFloat?, depth: Int, flow: Int, context: Context) -> (bottom: CGFloat, after: CGFloat?) {
        var cursor = top
        var pending = leadingAfter
        var ordinal = 0
        var previousWasNumbered = false
        var previous: Int?
        for block in list {
            let spacing = metrics.spacing(for: block)
            let y = (pending.map { cursor + max($0, spacing.before) } ?? cursor).rounded()
            var listOrdinal: Int?
            if block.kind == .numberedItem {
                ordinal = previousWasNumbered ? ordinal + 1 : (block.props.listStart ?? 1)
                listOrdinal = ordinal
                previousWasNumbered = true
            } else {
                previousWasNumbered = false
            }
            let placed = layoutBlock(block, parent: parent, previous: previous, x: x, width: width, y: y, depth: depth,
                                     flow: flow, ordinal: listOrdinal, context: context)
            previous = placed.index
            cursor = placed.bottom
            pending = placed.after
        }
        return (cursor, pending)
    }

    private mutating func layoutBlock(_ block: NoteBlock, parent: Int?, previous: Int?, x: CGFloat, width: CGFloat, y: CGFloat,
                                      depth: Int, flow: Int, ordinal: Int?, context: Context) -> (index: Int, bottom: CGFloat, after: CGFloat) {
        let spacing = metrics.spacing(for: block)
        let index = append(block, parent: parent, previous: previous, depth: depth, flow: flow, isRow: true, ordinal: ordinal)
        switch block.kind {
        case .columns:
            let bottom = layoutColumns(block, index: index, x: x, width: width, y: y, depth: depth, context: context)
            return (index, bottom, spacing.after)
        case .synced:
            let row = CGRect(x: x, y: y, width: width, height: max(0, context.measure.height(block, width)).rounded(.up))
            entries[index].frame = row
            let inner = layoutChildren(block, index: index, row: row, rowAfter: 0, trailing: 0, depth: depth, flow: flow, context: context)
            let bottom = (inner.bottom + metrics.syncedFooterHeight * metrics.scale).rounded()
            entries[index].outerFrame = CGRect(x: x, y: y, width: width, height: bottom - y)
            entries[index].subtreeEnd = entries.count
            return (index, bottom, spacing.after)
        case .callout:
            let row = CGRect(x: x, y: y, width: width, height: max(0, context.measure.height(block, width)).rounded(.up))
            entries[index].frame = row
            let trailing = metrics.calloutInsets.right
            let inner = layoutChildren(block, index: index, row: row, rowAfter: metrics.textSpacing.after, trailing: trailing,
                                       depth: depth, flow: flow, context: context)
            let bottom = entries[index].hasVisibleChildren ? (inner.bottom + metrics.calloutInsets.bottom * metrics.scale).rounded() : inner.bottom
            entries[index].outerFrame = CGRect(x: x, y: y, width: width, height: bottom - y)
            entries[index].subtreeEnd = entries.count
            return (index, bottom, spacing.after)
        default:
            let row = CGRect(x: x, y: y, width: width, height: max(0, context.measure.height(block, width)).rounded(.up))
            entries[index].frame = row
            let inner = layoutChildren(block, index: index, row: row, rowAfter: spacing.after, trailing: 0, depth: depth, flow: flow,
                                       context: context)
            entries[index].outerFrame = CGRect(x: x, y: y, width: width, height: inner.bottom - y)
            entries[index].subtreeEnd = entries.count
            return (index, inner.bottom, inner.after)
        }
    }

    private mutating func layoutChildren(_ block: NoteBlock, index: Int, row: CGRect, rowAfter: CGFloat, trailing: CGFloat,
                                         depth: Int, flow: Int, context: Context) -> (bottom: CGFloat, after: CGFloat) {
        let indent = min(max(0, context.measure.childIndent(block)), row.width)
        let childX = (row.minX + indent).rounded()
        let childWidth = max(0, row.maxX - trailing - childX)
        entries[index].childX = childX
        guard block.showsChildren, !block.children.isEmpty else { return (row.maxY, rowAfter) }
        entries[index].hasVisibleChildren = true
        let result = layoutList(block.children, parent: index, x: childX, width: childWidth, top: row.maxY,
                                leadingAfter: rowAfter, depth: depth + 1, flow: flow, context: context)
        return (result.bottom, result.after ?? rowAfter)
    }

    private mutating func layoutColumns(_ block: NoteBlock, index: Int, x: CGFloat, width: CGFloat, y: CGFloat, depth: Int,
                                        context: Context) -> CGFloat {
        let columns = block.children
        let gap = metrics.columnGap
        let fractions = Self.normalizedFractions(context.overrides[block.id] ?? columns.map { $0.props.width.map { CGFloat($0) } },
                                                 count: columns.count)
        let available = max(0, width - gap * CGFloat(max(0, columns.count - 1)))
        var cursor = x
        var bottom = y
        var frames: [CGRect] = []
        var columnIndices: [Int?] = []
        var columnFlows: [Int] = []
        var previous: Int?
        for (position, column) in columns.enumerated() {
            let columnWidth = position == columns.count - 1 ? max(0, x + width - cursor) : (available * fractions[position]).rounded()
            let flow = makeFlow()
            columnFlows.append(flow)
            if column.kind == .column {
                let columnIndex = append(column, parent: index, previous: previous, depth: depth, flow: flow, isRow: false,
                                         ordinal: nil)
                previous = columnIndex
                entries[columnIndex].childX = cursor
                entries[columnIndex].hasVisibleChildren = !column.children.isEmpty
                let result = layoutList(column.children, parent: columnIndex, x: cursor, width: columnWidth, top: y,
                                        leadingAfter: nil, depth: depth, flow: flow, context: context)
                entries[columnIndex].subtreeEnd = entries.count
                flowBottoms[flow] = result.bottom
                bottom = max(bottom, result.bottom)
                columnIndices.append(columnIndex)
            } else {
                let result = layoutList([column], parent: index, x: cursor, width: columnWidth, top: y, leadingAfter: nil,
                                        depth: depth, flow: flow, context: context)
                flowBottoms[flow] = result.bottom
                bottom = max(bottom, result.bottom)
                columnIndices.append(nil)
            }
            frames.append(CGRect(x: cursor, y: y, width: columnWidth, height: 0))
            cursor += columnWidth + gap
        }
        if columns.isEmpty { bottom = y } else { bottom = max(bottom, y + metrics.bodyLineHeight) }
        for position in frames.indices {
            frames[position].size.height = bottom - y
            if let columnIndex = columnIndices[position] {
                entries[columnIndex].frame = frames[position]
                entries[columnIndex].outerFrame = frames[position]
            }
        }
        let rowFrame = CGRect(x: x, y: y, width: width, height: bottom - y)
        entries[index].frame = rowFrame
        entries[index].outerFrame = rowFrame
        entries[index].childX = x
        entries[index].hasVisibleChildren = !columns.isEmpty
        entries[index].subtreeEnd = entries.count
        columnsRows[block.id] = ColumnsRow(id: block.id, frame: rowFrame, columns: columns.map(\.id), columnFrames: frames,
                                           flows: columnFlows, fractions: fractions, available: available, gap: gap)
        return bottom
    }
}

enum NoteCanvasEstimate {
    static func height(of block: NoteBlock, width: CGFloat, metrics: NoteCanvasMetrics) -> CGFloat {
        let scale = metrics.scale
        let caption: CGFloat = block.kind.hasCaption && !block.props.caption.isEmpty ? 26 * scale : 0
        switch block.kind {
        case .paragraph, .bulletedItem, .numberedItem, .todo, .toggle, .quote, .callout:
            let inset: CGFloat
            let padding: CGFloat
            switch block.kind {
            case .paragraph: inset = 0; padding = 6
            case .quote: inset = metrics.quoteChildIndent; padding = 6
            case .callout: inset = metrics.childIndent(of: block) + metrics.calloutInsets.right; padding = metrics.calloutInsets.top * 2
            default: inset = metrics.indentWidth; padding = 6
            }
            let hint = block.isToggle && block.props.expanded && block.children.isEmpty ? metrics.toggleHintHeight : 0
            return lines(block.text.string, width: width - inset, characterWidth: metrics.averageCharacterWidth) * metrics.bodyLineHeight
                + padding + hint
        case .heading:
            let lineHeight = metrics.headingLineHeight(block.props.level)
            let ratio = lineHeight / max(1, metrics.bodyLineHeight)
            let inset = block.props.toggleable ? metrics.indentWidth : 0
            let padding: CGFloat = [24, 18, 14, 10, 8, 8][min(max(block.props.level, 1), 6) - 1]
            let hint = block.isToggle && block.props.expanded && block.children.isEmpty ? metrics.toggleHintHeight : 0
            return lines(block.text.string, width: width - inset, characterWidth: metrics.averageCharacterWidth * ratio) * lineHeight
                + padding + hint
        case .code:
            let count = CGFloat(max(1, block.text.string.split(separator: "\n", omittingEmptySubsequences: false).count))
            return count * metrics.codeLineHeight + 36 * scale + caption
        case .html, .raw:
            let count = CGFloat(max(1, block.text.string.split(separator: "\n", omittingEmptySubsequences: false).count))
            return count * metrics.codeLineHeight + 16 * scale
        case .equation: return 56 * scale
        case .divider: return 13 * scale
        case .embed:
            guard block.props.source?.isEmpty == false else { return 60 + caption }
            return CGFloat(NoteEmbedSizing.height(of: block.props)) + 38 + caption
        case .easel:
            guard block.props.source?.isEmpty == false else { return 60 }
            return CGFloat(NoteEmbedSizing.height(of: block.props)) + 38 + 16
        case .image, .video:
            let used = block.props.width.map { CGFloat($0) <= 1 ? width * CGFloat($0) : min(width, CGFloat($0)) } ?? width
            return min(used * 0.5625, 480) + caption
        case .audio: return 54 * scale + caption
        case .file: return 40 * scale + caption
        case .pdf:
            guard block.props.source?.isEmpty == false else { return 64 + caption }
            return NotePDFLayout.viewerHeight(width: NotePDFLayout.displayWidth(fraction: block.props.width, columnWidth: width), aspect: nil)
                + 12 + caption
        case .bookmark: return 104 * scale + caption
        case .pageLink: return metrics.bodyLineHeight + 4 * scale
        case .button: return NoteButtonMetrics.height(scale: scale)
        case .tableOfContents: return 3 * metrics.bodyLineHeight
        case .breadcrumb: return metrics.bodyLineHeight + 8 * scale
        case .table:
            let rows = CGFloat(max(1, block.props.table?.rowCount ?? 3))
            return rows * (metrics.bodyLineHeight + 10 * scale) + 2
        case .columns, .column: return 0
        case .synced: return metrics.syncedHeaderHeight * scale
        }
    }

    private static func lines(_ text: String, width: CGFloat, characterWidth: CGFloat) -> CGFloat {
        let perLine = max(8, Int(max(1, width) / max(1, characterWidth)))
        var total = 0
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            total += max(1, (line.utf16.count + perLine - 1) / perLine)
        }
        return CGFloat(max(1, total))
    }
}
