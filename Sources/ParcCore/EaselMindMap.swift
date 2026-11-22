import Foundation

package struct EaselMindMapTree {
    package struct Node: Equatable {
        package let id: UUID
        package var parent: UUID?
        package var depth = 0
        package var side = EaselMindMapLink.Side.right
        package var children: [UUID] = []
        package var collapsed = false
    }

    package var nodes: [UUID: Node] = [:]
    package var roots: [UUID] = []
    package var branches: [UUID: UUID] = [:]

    package func root(of id: UUID) -> UUID? {
        guard nodes[id] != nil else { return nil }
        var current = id, steps = 0
        while let parent = nodes[current]?.parent, steps <= nodes.count { current = parent; steps += 1 }
        return current
    }

    package func children(of id: UUID, side: EaselMindMapLink.Side) -> [UUID] {
        (nodes[id]?.children ?? []).filter { nodes[$0]?.side == side }
    }

    package func descendants(of id: UUID) -> [UUID] {
        var result: [UUID] = []
        var seen: Set<UUID> = [id]
        var stack = Array((nodes[id]?.children ?? []).reversed())
        while let next = stack.popLast() {
            guard seen.insert(next).inserted else { continue }
            result.append(next)
            stack.append(contentsOf: (nodes[next]?.children ?? []).reversed())
        }
        return result
    }

    package func contains(_ id: UUID, inSubtreeOf ancestor: UUID) -> Bool {
        var current: UUID? = id, steps = 0
        while let value = current, steps <= nodes.count {
            if value == ancestor { return true }
            current = nodes[value]?.parent
            steps += 1
        }
        return false
    }

    package var hidden: Set<UUID> {
        var result = Set<UUID>()
        var visited = Set<UUID>()
        var stack = roots
        while let id = stack.popLast() {
            guard visited.insert(id).inserted, let node = nodes[id] else { continue }
            guard node.collapsed else {
                stack.append(contentsOf: node.children)
                continue
            }
            var inner = node.children
            while let next = inner.popLast() {
                guard next != id, result.insert(next).inserted else { continue }
                inner.append(contentsOf: nodes[next]?.children ?? [])
            }
        }
        return result
    }
}

package struct EaselMindMapDrop: Equatable {
    package var parent: UUID
    package var side: EaselMindMapLink.Side
    package var index: Int
    package var onto: Bool
    package var slot: EaselPoint

    package init(parent: UUID, side: EaselMindMapLink.Side, index: Int, onto: Bool, slot: EaselPoint) {
        self.parent = parent
        self.side = side
        self.index = index
        self.onto = onto
        self.slot = slot
    }
}

package enum EaselMindMap {
    package static let rootGap = 72.0
    static let levelGap = 48.0
    static let siblingGap = 16.0
    static let deepBranchWidth = 2.0
    static let dropReach = 72.0
    package static let rootText = "Big idea"
    package static let starterTexts = ["A thought", "Another thought"]
    static let branchColors: [NoteColor] = [.orange, .yellow, .green, .blue, .purple, .pink, .red, .brown, .gray]

    package static func isNodeKind(_ kind: EaselItemKind) -> Bool { EaselMindMapLink.holdsNode(kind) }

    package static func isNode(_ item: EaselItem) -> Bool { item.mindMap != nil && isNodeKind(item.kind) }
    static func isBranch(_ item: EaselItem) -> Bool { item.mindMap != nil && item.kind == .arrow }
    package static func gap(depth: Int) -> Double { depth <= 1 ? rootGap : levelGap }

    static func branchColor(_ index: Int) -> String {
        let count = branchColors.count
        let color = branchColors[((index % count) + count) % count]
        return EaselPalette.hex(.note(color), role: .ink) ?? EaselPalette.automaticInk
    }

    static func connectionSides(_ side: EaselMindMapLink.Side) -> (start: EaselConnection.Side, end: EaselConnection.Side) {
        side == .right ? (.right, .left) : (.left, .right)
    }

    package static func tree(of items: [EaselItem], previous: [EaselItem]? = nil) -> EaselMindMapTree {
        var tree = EaselMindMapTree()
        var order: [UUID] = [], links: [UUID: EaselMindMapLink] = [:], frames: [UUID: EaselRect] = [:]
        for item in items where isNode(item) && links[item.id] == nil {
            links[item.id] = item.mindMap
            frames[item.id] = item.frame
            order.append(item.id)
        }
        guard !order.isEmpty else { return tree }
        var earlier: [UUID: EaselMindMapLink] = [:]
        for item in previous ?? [] where isNode(item) && earlier[item.id] == nil { earlier[item.id] = item.mindMap }
        var inherited: [UUID: EaselMindMapLink.Side] = [:]
        func resolve(_ id: UUID) -> UUID? {
            guard var candidate = links[id]?.parent, candidate != id else { return nil }
            var hops = 0
            while links[candidate] == nil {
                guard hops < 256, let link = earlier[candidate], let up = link.parent else { return nil }
                inherited[id] = link.side ?? .right
                candidate = up
                hops += 1
            }
            return candidate == id ? nil : candidate
        }
        var parents: [UUID: UUID] = [:]
        for id in order { if let parent = resolve(id) { parents[id] = parent } }
        var acyclic = Set<UUID>()
        for id in order where !acyclic.contains(id) {
            var path: [UUID] = [], onPath = Set<UUID>(), current = id
            while !acyclic.contains(current) {
                guard onPath.insert(current).inserted else {
                    if let last = path.last { parents[last] = nil }
                    break
                }
                path.append(current)
                guard let parent = parents[current] else { break }
                current = parent
            }
            acyclic.formUnion(path)
        }
        var children: [UUID: [UUID]] = [:]
        for id in order { if let parent = parents[id] { children[parent, default: []].append(id) } }
        func key(_ id: UUID) -> (Double, Double, String) {
            let frame = frames[id] ?? EaselRect(x: 0, y: 0, width: 0, height: 0)
            return (frame.y + frame.height / 2, frame.x, id.uuidString)
        }
        for (parent, list) in children { children[parent] = list.sorted { key($0) < key($1) } }
        for id in order where parents[id] == nil {
            tree.roots.append(id)
            tree.nodes[id] = EaselMindMapTree.Node(id: id, parent: nil, depth: 0, side: .right, children: children[id] ?? [])
            var queue = [id], cursor = 0
            while cursor < queue.count {
                let current = queue[cursor]
                cursor += 1
                guard let node = tree.nodes[current] else { continue }
                for child in node.children where tree.nodes[child] == nil {
                    let side = node.depth == 0 ? (inherited[child] ?? links[child]?.side ?? .right) : node.side
                    let kids = children[child] ?? []
                    tree.nodes[child] = EaselMindMapTree.Node(id: child, parent: current, depth: node.depth + 1, side: side,
                                                              children: kids, collapsed: links[child]?.collapsed == true && !kids.isEmpty)
                    queue.append(child)
                }
            }
        }
        for item in items where isBranch(item) {
            guard let child = item.endConnection?.itemID, tree.nodes[child]?.parent != nil, tree.branches[child] == nil else { continue }
            tree.branches[child] = item.id
        }
        return tree
    }

    package static func hiddenIDs(in items: [EaselItem]) -> Set<UUID> {
        guard items.contains(where: { $0.mindMap?.collapsed == true }) else { return [] }
        let hidden = tree(of: items).hidden
        guard !hidden.isEmpty else { return [] }
        var result = hidden
        for item in items where isBranch(item) {
            if let child = item.endConnection?.itemID, hidden.contains(child) { result.insert(item.id) }
        }
        return result
    }

    package static func settling(_ next: EaselDocument, previous: EaselDocument, moved: Set<UUID>,
                         tidy: Bool) -> (document: EaselDocument, moved: Set<UUID>) {
        guard next.items.contains(where: { $0.mindMap != nil }) else { return (next, moved) }
        let carried = carrying(next, previous: previous, moved: moved)
        guard tidy else { return carried }
        let settled = tidied(carried.document, previous: previous)
        guard settled != carried.document else { return carried }
        var before: [UUID: EaselRect] = [:]
        for item in carried.document.items where before[item.id] == nil { before[item.id] = item.frame }
        var shifted = carried.moved
        for item in settled.items where item.kind != .arrow && before[item.id] != item.frame { shifted.insert(item.id) }
        return (settled, shifted)
    }

    package static func tidied(_ document: EaselDocument, previous: EaselDocument? = nil) -> EaselDocument {
        guard document.items.contains(where: { $0.mindMap != nil }) else { return document }
        var next = document
        for index in next.items.indices where next.items[index].mindMap != nil
            && !isNodeKind(next.items[index].kind) && next.items[index].kind != .arrow {
            next.items[index].mindMap = nil
        }
        let tree = tree(of: next.items, previous: previous?.items)
        for index in next.items.indices where isNode(next.items[index]) {
            guard let node = tree.nodes[next.items[index].id] else { continue }
            let link = EaselMindMapLink(parent: node.parent, side: node.depth == 1 && node.side == .left ? .left : nil,
                                        collapsed: node.collapsed ? true : nil)
            if next.items[index].mindMap != link { next.items[index].mindMap = link }
        }
        next = syncingBranches(next, tree: tree)
        return routingBranches(laidOut(next, tree: tree))
    }

    static func syncingBranches(_ document: EaselDocument, tree: EaselMindMapTree) -> EaselDocument {
        var next = document
        var branchOf: [UUID: EaselItem] = [:], doomed = Set<UUID>(), updates: [UUID: EaselItem] = [:]
        for arrow in next.items where isBranch(arrow) {
            guard let child = arrow.endConnection?.itemID, let node = tree.nodes[child], let parent = node.parent,
                  branchOf[child] == nil else {
                doomed.insert(arrow.id)
                continue
            }
            let shaped = shapedBranch(arrow, parent: parent, child: child, side: node.side)
            branchOf[child] = shaped
            if shaped != arrow { updates[arrow.id] = shaped }
        }
        if !doomed.isEmpty || !updates.isEmpty {
            next.items = next.items.compactMap { doomed.contains($0.id) ? nil : (updates[$0.id] ?? $0) }
        }
        var lookup: [UUID: EaselItem] = [:]
        for item in next.items where lookup[item.id] == nil { lookup[item.id] = item }
        var created: [EaselItem] = []
        for root in tree.roots {
            for id in tree.descendants(of: root) {
                guard let node = tree.nodes[id], let parentID = node.parent, branchOf[id] == nil,
                      let parent = lookup[parentID], let child = lookup[id] else { continue }
                let style = branchStyle(for: node, tree: tree, branches: branchOf)
                let zIndex = max(Int.min + 1, min(parent.zIndex, child.zIndex)) - 1
                let branch = makeBranch(parent: parent, child: child, side: node.side, style: style, zIndex: zIndex)
                branchOf[id] = branch
                created.append(branch)
            }
        }
        next.items.append(contentsOf: created)
        return next
    }

    private static func shapedBranch(_ arrow: EaselItem, parent: UUID, child: UUID, side: EaselMindMapLink.Side) -> EaselItem {
        var next = arrow
        let sides = connectionSides(side)
        next.mindMap = EaselMindMapLink(parent: parent)
        next.startConnection = EaselConnection(itemID: parent, side: sides.start)
        next.endConnection = EaselConnection(itemID: child, side: sides.end)
        next.waypoints = nil
        return next
    }

    private static func branchStyle(for node: EaselMindMapTree.Node, tree: EaselMindMapTree,
                                    branches: [UUID: EaselItem]) -> EaselConnectorStyle {
        if let parentID = node.parent, let parentBranch = branches[parentID] {
            var style = EaselConnectorStyle(parentBranch)
            style.labelBackground = nil
            if node.depth == 2, parentBranch.strokeWidth == nil { style.strokeWidth = deepBranchWidth }
            return style
        }
        var used = Set<String>(), count = 0
        if let rootID = node.parent {
            for sibling in tree.nodes[rootID]?.children ?? [] {
                guard let branch = branches[sibling] else { continue }
                count += 1
                if let color = EaselPalette.normalized(branch.color) { used.insert(color) }
            }
        }
        let index = (0..<branchColors.count).first { !used.contains(EaselPalette.normalized(branchColor($0)) ?? "") } ?? count
        return EaselConnectorStyle(startHead: nil, endHead: EaselArrowHead.none, routing: .curved, color: branchColor(index))
    }

    private static func makeBranch(parent: EaselItem, child: EaselItem, side: EaselMindMapLink.Side,
                                   style: EaselConnectorStyle, zIndex: Int) -> EaselItem {
        let sides = connectionSides(side)
        var branch = EaselConnectorRouter.make(from: EaselConnectorAttachment.magnet(sides.start, on: parent),
                                               to: EaselConnectorAttachment.magnet(sides.end, on: child), style: style,
                                               routing: style.routing, startConnection: EaselConnection(itemID: parent.id, side: sides.start),
                                               endConnection: EaselConnection(itemID: child.id, side: sides.end), zIndex: zIndex) { id in
            id == parent.id ? parent : id == child.id ? child : nil
        }
        branch.color = style.color
        branch.strokeWidth = style.strokeWidth
        branch.strokeDash = style.strokeDash
        branch.mindMap = EaselMindMapLink(parent: parent.id)
        return branch
    }

    package static func laidOut(_ document: EaselDocument, tree: EaselMindMapTree) -> EaselDocument {
        guard !tree.roots.isEmpty else { return document }
        var frames: [UUID: EaselRect] = [:]
        for item in document.items where tree.nodes[item.id] != nil && frames[item.id] == nil { frames[item.id] = item.frame }
        func visibleChildren(_ id: UUID) -> [UUID] {
            guard let node = tree.nodes[id], !node.collapsed else { return [] }
            return node.children.filter { frames[$0] != nil }
        }
        var extents: [UUID: Double] = [:]
        var stack: [(id: UUID, done: Bool)] = tree.roots.map { ($0, false) }
        while let entry = stack.popLast() {
            let kids = visibleChildren(entry.id)
            if entry.done {
                let total = kids.reduce(0) { $0 + (extents[$1] ?? 0) } + siblingGap * Double(max(0, kids.count - 1))
                extents[entry.id] = max(frames[entry.id]?.height ?? 0, total)
            } else {
                stack.append((entry.id, true))
                for kid in kids { stack.append((kid, false)) }
            }
        }
        var placed: [UUID: EaselRect] = [:], owner: [UUID: UUID] = [:]
        var queue: [(id: UUID, frame: EaselRect, depth: Int, root: UUID)] = []
        for root in tree.roots {
            guard let frame = frames[root] else { continue }
            placed[root] = frame
            owner[root] = root
            queue.append((root, frame, 0, root))
        }
        var cursor = 0
        while cursor < queue.count {
            let entry = queue[cursor]
            cursor += 1
            let kids = visibleChildren(entry.id)
            guard !kids.isEmpty else { continue }
            for side in EaselMindMapLink.Side.allCases {
                let group = kids.filter { tree.nodes[$0]?.side == side }
                guard !group.isEmpty else { continue }
                let total = group.reduce(0) { $0 + (extents[$1] ?? 0) } + siblingGap * Double(group.count - 1)
                var top = entry.frame.y + entry.frame.height / 2 - total / 2
                let spacing = gap(depth: entry.depth + 1)
                for kid in group {
                    guard let own = frames[kid] else { continue }
                    let band = extents[kid] ?? own.height
                    let x = side == .right ? entry.frame.x + entry.frame.width + spacing : entry.frame.x - spacing - own.width
                    let rect = EaselRect(x: x.rounded(), y: (top + band / 2 - own.height / 2).rounded(), width: own.width, height: own.height)
                    placed[kid] = rect
                    owner[kid] = entry.root
                    queue.append((kid, rect, entry.depth + 1, entry.root))
                    top += band + siblingGap
                }
            }
        }
        for (id, node) in tree.nodes where node.collapsed {
            guard let new = placed[id], let old = frames[id] else { continue }
            let dx = new.x - old.x, dy = new.y - old.y
            for hidden in tree.descendants(of: id) where placed[hidden] == nil {
                guard let frame = frames[hidden] else { continue }
                placed[hidden] = EaselRect(x: frame.x + dx, y: frame.y + dy, width: frame.width, height: frame.height)
                owner[hidden] = owner[id]
            }
        }
        let hidden = tree.hidden
        var shifts: [UUID: (dx: Double, dy: Double)] = [:]
        for (id, rect) in placed where !hidden.contains(id) {
            guard let root = owner[id] else { continue }
            let current = shifts[root] ?? (0, 0)
            shifts[root] = (max(current.dx, -rect.x), max(current.dy, -rect.y))
        }
        var next = document
        for index in next.items.indices {
            let id = next.items[index].id
            guard var rect = placed[id], let root = owner[id] else { continue }
            if let shift = shifts[root] { rect.x += shift.dx; rect.y += shift.dy }
            if hidden.contains(id) { rect.x = max(0, rect.x); rect.y = max(0, rect.y) }
            if next.items[index].frame != rect { next.items[index].frame = rect }
        }
        return next
    }

    static func routingBranches(_ document: EaselDocument) -> EaselDocument {
        guard document.items.contains(where: isBranch) else { return document }
        var lookup: [UUID: EaselItem] = [:]
        for item in document.items where lookup[item.id] == nil { lookup[item.id] = item }
        var next = document
        for index in next.items.indices where isBranch(next.items[index]) {
            let settled = EaselConnectorRouter.settled(next.items[index]) { lookup[$0] }
            if settled != next.items[index] { next.items[index] = settled }
        }
        return next
    }

    static func carrying(_ next: EaselDocument, previous: EaselDocument,
                         moved: Set<UUID>) -> (document: EaselDocument, moved: Set<UUID>) {
        guard !moved.isEmpty, previous.items.contains(where: { $0.mindMap != nil }) else { return (next, moved) }
        let tree = tree(of: previous.items)
        var before: [UUID: EaselRect] = [:]
        for item in previous.items where before[item.id] == nil { before[item.id] = item.frame }
        var after: [UUID: EaselRect] = [:]
        for item in next.items where after[item.id] == nil { after[item.id] = item.frame }
        var shifts: [UUID: (dx: Double, dy: Double)] = [:]
        for id in moved where tree.nodes[id] != nil {
            guard let old = before[id], let new = after[id], old.width == new.width, old.height == new.height else { continue }
            let dx = new.x - old.x, dy = new.y - old.y
            guard dx != 0 || dy != 0, dx.isFinite, dy.isFinite else { continue }
            for descendant in tree.descendants(of: id) where !moved.contains(descendant) && shifts[descendant] == nil {
                guard before[descendant] == after[descendant] else { continue }
                shifts[descendant] = (dx, dy)
            }
        }
        guard !shifts.isEmpty else { return (next, moved) }
        var result = next, carried = moved
        for index in result.items.indices {
            let id = result.items[index].id
            guard let shift = shifts[id], let old = before[id] else { continue }
            result.items[index].frame.x = old.x + shift.dx
            result.items[index].frame.y = old.y + shift.dy
            carried.insert(id)
        }
        return (result, carried)
    }

    static func removalDependents(of ids: Set<UUID>, in document: EaselDocument) -> Set<UUID> {
        guard !ids.isEmpty, document.items.contains(where: { $0.mindMap != nil }) else { return [] }
        let tree = tree(of: document.items)
        var nodes = Set<UUID>()
        for id in ids where tree.nodes[id] != nil {
            nodes.insert(id)
            nodes.formUnion(tree.descendants(of: id))
        }
        guard !nodes.isEmpty else { return [] }
        var result = nodes
        for item in document.items where isBranch(item) {
            if let child = item.endConnection?.itemID, nodes.contains(child) { result.insert(item.id) }
        }
        return result.subtracting(ids)
    }

    static func detaching(_ removed: Set<UUID>, from original: EaselDocument, in next: EaselDocument) -> EaselDocument {
        let cut = Set(original.items.filter { isBranch($0) && removed.contains($0.id) }
            .compactMap { $0.endConnection?.itemID }.filter { !removed.contains($0) })
        guard !cut.isEmpty else { return next }
        var result = next
        for index in result.items.indices where cut.contains(result.items[index].id) && isNode(result.items[index]) {
            result.items[index].mindMap = EaselMindMapLink()
        }
        return result
    }

    static func relinked(_ copies: [EaselItem], ids: [UUID: UUID]) -> [EaselItem] {
        guard copies.contains(where: { $0.mindMap != nil }) else { return copies }
        let copied = Set(ids.values)
        var parents = Set<UUID>()
        for copy in copies where isNode(copy) {
            if let parent = copy.mindMap?.parent, let mapped = ids[parent] { parents.insert(mapped) }
        }
        let kept = copies.compactMap { item -> EaselItem? in
            guard item.kind == .arrow, let link = item.mindMap else { return item }
            guard let parent = link.parent, let mapped = ids[parent], copied.contains(mapped),
                  let child = item.endConnection?.itemID, copied.contains(child) else { return nil }
            return item
        }
        return kept.map { item in
            guard let link = item.mindMap else { return item }
            var copy = item
            if item.kind == .arrow {
                if let parent = link.parent, let mapped = ids[parent], let child = item.endConnection?.itemID, copied.contains(child) {
                    copy.mindMap = EaselMindMapLink(parent: mapped)
                } else {
                    copy.mindMap = nil
                }
            } else if !isNodeKind(item.kind) {
                copy.mindMap = nil
            } else if let parent = link.parent {
                if let mapped = ids[parent] {
                    copy.mindMap = EaselMindMapLink(parent: mapped, side: link.side, collapsed: link.collapsed)
                } else {
                    copy.mindMap = parents.contains(item.id) ? EaselMindMapLink() : nil
                }
            }
            return copy
        }
    }

    static func balancedSide(of root: UUID, in tree: EaselMindMapTree) -> EaselMindMapLink.Side {
        let left = tree.children(of: root, side: .left).count, right = tree.children(of: root, side: .right).count
        return left > 0 && left < right ? .left : .right
    }

    package static func template(forChildOf parentID: UUID, side requested: EaselMindMapLink.Side? = nil,
                         in document: EaselDocument) -> EaselItem? {
        let tree = tree(of: document.items)
        guard let parentNode = tree.nodes[parentID], let parent = document.items.first(where: { $0.id == parentID }) else { return nil }
        let side = parentNode.parent == nil ? (requested ?? balancedSide(of: parentID, in: tree)) : parentNode.side
        let siblings = tree.children(of: parentID, side: side)
        let sibling = siblings.last.flatMap { last in document.items.first { $0.id == last } }
        let reference = sibling ?? parent
        var node = EaselItem(kind: reference.kind, frame: EaselRect(x: parent.frame.x, y: parent.frame.y,
                                                                    width: reference.frame.width, height: reference.frame.height),
                             text: "", color: reference.color)
        node.textStyle = reference.textStyle
        node.shape = reference.shape
        node.fill = reference.fill
        node.fillOpacity = reference.fillOpacity
        node.strokeWidth = reference.strokeWidth
        node.strokeDash = reference.strokeDash
        if reference.kind == .text {
            var style = reference.textStyle ?? EaselTextStyle()
            if sibling == nil, parentNode.parent == nil {
                style.size = .body
                style.customSize = nil
            }
            style.autoWidth = true
            node.textStyle = style
        }
        return node
    }

    static func orderedFrame(_ frame: EaselRect, parent: EaselRect, side: EaselMindMapLink.Side, depth: Int,
                             siblings: [EaselRect], at index: Int) -> EaselRect {
        let mid: Double
        if siblings.isEmpty {
            mid = parent.y + parent.height / 2
        } else if index <= 0 {
            mid = siblings[0].y - 1
        } else if index >= siblings.count {
            mid = siblings[siblings.count - 1].y + siblings[siblings.count - 1].height + 1
        } else {
            mid = (siblings[index - 1].y + siblings[index - 1].height / 2 + siblings[index].y + siblings[index].height / 2) / 2
        }
        let x = side == .right ? parent.x + parent.width + gap(depth: depth) : parent.x - gap(depth: depth) - frame.width
        return EaselRect(x: x, y: mid - frame.height / 2, width: frame.width, height: frame.height)
    }

    private static func frames(_ ids: [UUID], in document: EaselDocument) -> [EaselRect] {
        var lookup: [UUID: EaselRect] = [:]
        for item in document.items where lookup[item.id] == nil { lookup[item.id] = item.frame }
        return ids.compactMap { lookup[$0] }
    }

    package static func creatingMap(root: EaselItem, children: [EaselItem], in document: EaselDocument) -> EaselDocument? {
        guard isNodeKind(root.kind), !root.isLocked, children.allSatisfy({ isNodeKind($0.kind) }) else { return nil }
        var next = document
        var top = root
        top.mindMap = EaselMindMapLink()
        if let index = next.items.firstIndex(where: { $0.id == root.id }) {
            guard next.items[index].mindMap == nil else { return nil }
            next.items[index] = top
        } else {
            next.items.append(top)
        }
        for (offset, child) in children.enumerated() {
            var node = child
            node.mindMap = EaselMindMapLink(parent: top.id)
            node.frame = EaselRect(x: top.frame.x + top.frame.width + rootGap, y: top.frame.y + Double(offset) * 10,
                                   width: child.frame.width, height: child.frame.height)
            next.items.append(node)
        }
        return tidied(next, previous: document)
    }

    package static func adding(_ node: EaselItem, to parentID: UUID, side requested: EaselMindMapLink.Side? = nil, at index: Int? = nil,
                       in document: EaselDocument) -> EaselDocument? {
        guard isNodeKind(node.kind), !document.items.contains(where: { $0.id == node.id }) else { return nil }
        let tree = tree(of: document.items)
        guard let parentNode = tree.nodes[parentID], let parent = document.items.first(where: { $0.id == parentID }),
              !parent.isLocked else { return nil }
        let root = parentNode.parent == nil
        let side = root ? (requested ?? balancedSide(of: parentID, in: tree)) : parentNode.side
        let siblings = frames(tree.children(of: parentID, side: side), in: document)
        var placed = node
        placed.frame = orderedFrame(node.frame, parent: parent.frame, side: side, depth: parentNode.depth + 1,
                                    siblings: siblings, at: index ?? siblings.count)
        placed.mindMap = EaselMindMapLink(parent: parentID, side: root && side == .left ? .left : nil)
        var next = document
        if parentNode.collapsed, let position = next.items.firstIndex(where: { $0.id == parentID }) {
            next.items[position].mindMap?.collapsed = nil
        }
        next.items.append(placed)
        return tidied(next, previous: document)
    }

    static func addingSibling(_ node: EaselItem, after id: UUID, in document: EaselDocument) -> EaselDocument? {
        let tree = tree(of: document.items)
        guard let current = tree.nodes[id], let parent = current.parent,
              let position = tree.children(of: parent, side: current.side).firstIndex(of: id) else { return nil }
        return adding(node, to: parent, side: current.side, at: position + 1, in: document)
    }

    package static func indenting(_ id: UUID, in document: EaselDocument) -> EaselDocument? {
        let tree = tree(of: document.items)
        guard let current = tree.nodes[id], let parent = current.parent,
              let me = document.items.firstIndex(where: { $0.id == id }), !document.items[me].isLocked else { return nil }
        let group = tree.children(of: parent, side: current.side)
        guard let position = group.firstIndex(of: id), position > 0 else { return nil }
        let target = group[position - 1]
        guard let targetNode = tree.nodes[target], let targetIndex = document.items.firstIndex(where: { $0.id == target }) else { return nil }
        let siblings = frames(tree.children(of: target, side: current.side), in: document)
        var next = document
        next.items[me].mindMap = EaselMindMapLink(parent: target, collapsed: next.items[me].mindMap?.collapsed)
        next.items[me].frame = orderedFrame(next.items[me].frame, parent: next.items[targetIndex].frame, side: current.side,
                                            depth: targetNode.depth + 1, siblings: siblings, at: siblings.count)
        next.items[targetIndex].mindMap?.collapsed = nil
        return tidied(next, previous: document)
    }

    package static func outdenting(_ id: UUID, in document: EaselDocument) -> EaselDocument? {
        let tree = tree(of: document.items)
        guard let current = tree.nodes[id], let parentID = current.parent, let parentNode = tree.nodes[parentID],
              let grandID = parentNode.parent, let grandNode = tree.nodes[grandID],
              let me = document.items.firstIndex(where: { $0.id == id }), !document.items[me].isLocked,
              let grand = document.items.first(where: { $0.id == grandID }) else { return nil }
        let side = parentNode.side
        let group = tree.children(of: grandID, side: side)
        guard let position = group.firstIndex(of: parentID) else { return nil }
        var next = document
        next.items[me].mindMap = EaselMindMapLink(parent: grandID, side: grandNode.parent == nil && side == .left ? .left : nil,
                                                  collapsed: next.items[me].mindMap?.collapsed)
        next.items[me].frame = orderedFrame(next.items[me].frame, parent: grand.frame, side: side, depth: grandNode.depth + 1,
                                            siblings: frames(group, in: document), at: position + 1)
        return tidied(next, previous: document)
    }

    package static func settingCollapsed(_ collapsed: Bool, _ ids: Set<UUID>, in document: EaselDocument) -> EaselDocument? {
        let tree = tree(of: document.items)
        var next = document, changed = false
        let value: Bool? = collapsed ? true : nil
        for index in next.items.indices where ids.contains(next.items[index].id) {
            guard let node = tree.nodes[next.items[index].id], node.parent != nil, !node.children.isEmpty,
                  next.items[index].mindMap?.collapsed != value else { continue }
            next.items[index].mindMap?.collapsed = value
            changed = true
        }
        return changed ? tidied(next, previous: document) : nil
    }

    package static func canCollapse(_ id: UUID, in tree: EaselMindMapTree) -> Bool {
        guard let node = tree.nodes[id] else { return false }
        return node.parent != nil && !node.children.isEmpty
    }

    package static func moving(_ id: UUID, to drop: EaselMindMapDrop, in document: EaselDocument) -> EaselDocument? {
        let tree = tree(of: document.items)
        guard let me = document.items.firstIndex(where: { $0.id == id }), isNodeKind(document.items[me].kind),
              !document.items[me].isLocked, let parentNode = tree.nodes[drop.parent],
              let parent = document.items.first(where: { $0.id == drop.parent }), !parent.isLocked,
              !tree.contains(drop.parent, inSubtreeOf: id) else { return nil }
        let root = parentNode.parent == nil
        let side = root ? drop.side : parentNode.side
        let siblings = frames(tree.children(of: drop.parent, side: side).filter { $0 != id }, in: document)
        var next = document
        next.items[me].mindMap = EaselMindMapLink(parent: drop.parent, side: root && side == .left ? .left : nil,
                                                  collapsed: next.items[me].mindMap?.collapsed)
        next.items[me].frame = orderedFrame(next.items[me].frame, parent: parent.frame, side: side, depth: parentNode.depth + 1,
                                            siblings: siblings, at: max(0, min(drop.index, siblings.count)))
        if let position = next.items.firstIndex(where: { $0.id == drop.parent }) { next.items[position].mindMap?.collapsed = nil }
        return tidied(next, previous: document)
    }

    package static func drop(for id: UUID, frame: EaselRect, pointer: EaselPoint, in document: EaselDocument) -> EaselMindMapDrop? {
        let tree = tree(of: document.items)
        guard !tree.nodes.isEmpty else { return nil }
        var frames: [UUID: EaselRect] = [:], order: [UUID: Int] = [:]
        for item in EaselArrange.paintOrder(document) where tree.nodes[item.id] != nil && frames[item.id] == nil {
            frames[item.id] = item.frame
            order[item.id] = order.count
        }
        let dragged = tree.nodes[id]
        let excluded = Set([id] + (dragged == nil ? [] : tree.descendants(of: id)))
        let hidden = tree.hidden
        let candidates = tree.nodes.keys.filter { !excluded.contains($0) && !hidden.contains($0) && frames[$0] != nil }
        let over = candidates.filter { candidate in
            guard let rect = frames[candidate] else { return false }
            return pointer.x >= rect.x - 6 && pointer.x <= rect.x + rect.width + 6 && pointer.y >= rect.y - 6 && pointer.y <= rect.y + rect.height + 6
        }.max { (order[$0] ?? 0) < (order[$1] ?? 0) }
        if let target = over, let node = tree.nodes[target], let rect = frames[target] {
            let side = node.parent == nil ? (pointer.x < rect.x + rect.width / 2 ? EaselMindMapLink.Side.left : .right) : node.side
            let group = node.collapsed ? [] : tree.children(of: target, side: side).filter { !excluded.contains($0) }
            let siblings = group.compactMap { frames[$0] }
            return EaselMindMapDrop(parent: target, side: side, index: siblings.count, onto: true,
                                    slot: slot(parent: rect, depth: node.depth + 1, side: side, siblings: siblings, at: siblings.count))
        }
        guard let dragged, dragged.parent != nil else { return nil }
        var best: (score: Double, drop: EaselMindMapDrop)?
        for candidate in candidates {
            guard let node = tree.nodes[candidate], !node.collapsed, let rect = frames[candidate] else { continue }
            let sides: [EaselMindMapLink.Side] = node.parent == nil ? [.right, .left] : [node.side]
            for side in sides {
                let siblings = tree.children(of: candidate, side: side).filter { !excluded.contains($0) }.compactMap { frames[$0] }
                let column = side == .right ? rect.x + rect.width + gap(depth: node.depth + 1) : rect.x - gap(depth: node.depth + 1)
                let attach = side == .right ? frame.x : frame.x + frame.width
                let dx = abs(attach - column)
                guard dx <= dropReach else { continue }
                let middle = frame.y + frame.height / 2
                for index in 0...siblings.count {
                    let point = slot(parent: rect, depth: node.depth + 1, side: side, siblings: siblings, at: index)
                    let dy = abs(middle - point.y)
                    guard dy <= dropReach / 2 + (siblings.isEmpty ? rect.height / 2 : 0) else { continue }
                    let score = dy + dx / 2
                    if score < (best?.score ?? .infinity) {
                        best = (score, EaselMindMapDrop(parent: candidate, side: side, index: index, onto: false, slot: point))
                    }
                }
            }
        }
        return best?.drop
    }

    package static func slot(parent: EaselRect, depth: Int, side: EaselMindMapLink.Side, siblings: [EaselRect], at index: Int) -> EaselPoint {
        let x = side == .right ? parent.x + parent.width + gap(depth: depth) : parent.x - gap(depth: depth)
        let y: Double
        if siblings.isEmpty {
            y = parent.y + parent.height / 2
        } else if index <= 0 {
            y = siblings[0].y - siblingGap / 2
        } else if index >= siblings.count {
            y = siblings[siblings.count - 1].y + siblings[siblings.count - 1].height + siblingGap / 2
        } else {
            y = (siblings[index - 1].y + siblings[index - 1].height + siblings[index].y) / 2
        }
        return EaselPoint(x: x, y: y)
    }

    package static func childSides(of id: UUID, in tree: EaselMindMapTree) -> [EaselMindMapLink.Side] {
        guard let node = tree.nodes[id] else { return [] }
        return node.parent == nil ? [.right, .left] : [node.side]
    }

    package static func canStart(from item: EaselItem) -> Bool {
        item.kind == .text && item.mindMap == nil && !item.isLocked
    }

    package static func hiddenCount(of id: UUID, in tree: EaselMindMapTree) -> Int {
        guard tree.nodes[id]?.collapsed == true else { return 0 }
        return tree.descendants(of: id).count
    }
}
