import Foundation

@main
struct EaselMindMapTests {
    @MainActor static var assertions = 0

    @MainActor static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        assertions += 1
        if !condition() { fatalError(message) }
    }

    @MainActor static func main() {
        model()
        starterMap()
        children()
        twoSided()
        spacing()
        movingAndSnapping()
        removal()
        reparenting()
        collapsing()
        dropping()
        copying()
        export()
        print("EaselMindMapTests: \(assertions) assertions passed")
    }

    static func document(_ items: [EaselItem]) -> EaselDocument {
        EaselDocument(id: UUID(), title: "Map", createdAt: Date(timeIntervalSinceReferenceDate: 0),
                      modifiedAt: Date(timeIntervalSinceReferenceDate: 0), items: items)
    }

    @MainActor static func accepts(_ items: [EaselItem]) -> Bool {
        (try? EaselSession(inMemory: document(items), assets: [:])) != nil
    }

    static func node(_ text: String, width: Double = 120, height: Double = 30, kind: EaselItemKind = .text) -> EaselItem {
        EaselItem(kind: kind, frame: EaselRect(x: 400, y: 300, width: width, height: height), text: text)
    }

    static func item(_ id: UUID, in document: EaselDocument) -> EaselItem? { document.items.first { $0.id == id } }

    static func nodes(_ document: EaselDocument) -> [EaselItem] { document.items.filter(EaselMindMap.isNode) }
    static func branches(_ document: EaselDocument) -> [EaselItem] { document.items.filter(EaselMindMap.isBranch) }

    static func overlaps(_ document: EaselDocument) -> Bool {
        let hidden = EaselMindMap.hiddenIDs(in: document.items)
        let frames = nodes(document).filter { !hidden.contains($0.id) }.map(\.frame)
        for (index, a) in frames.enumerated() {
            for b in frames[(index + 1)...] where a.x < b.x + b.width && b.x < a.x + a.width && a.y < b.y + b.height && b.y < a.y + a.height {
                return true
            }
        }
        return false
    }

    static func starter() -> (document: EaselDocument, root: UUID, kids: [UUID]) {
        let root = node("Big idea", width: 160, height: 40)
        let kids = [node("One"), node("Two")]
        let made = EaselMindMap.creatingMap(root: root, children: kids, in: document([])) ?? document([])
        return (made, root.id, kids.map(\.id))
    }

    @MainActor static func model() {
        let plain = node("Plain")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let bare = String(decoding: (try? encoder.encode(plain)) ?? Data(), as: UTF8.self)
        expect(!bare.contains("mindMap"), "objects outside a mind map save no mind map field")
        var child = node("Child")
        child.mindMap = EaselMindMapLink(parent: plain.id, side: .left)
        let data = (try? encoder.encode(child)) ?? Data()
        expect(String(decoding: data, as: UTF8.self).contains("\"mindMap\":{\"parent\""), "a node saves its parent")
        expect((try? JSONDecoder().decode(EaselItem.self, from: data)) == child, "a node round-trips")
        var root = plain
        root.mindMap = EaselMindMapLink()
        expect(accepts([root, child]), "a root and its child are valid")
        var sided = plain
        sided.mindMap = EaselMindMapLink(side: .left)
        expect(!accepts([sided]), "a root can't pick a side")
        var looped = plain
        looped.mindMap = EaselMindMapLink(parent: plain.id)
        expect(accepts([looped]), "a node that is its own parent still opens")
        let repaired = EaselMindMap.tidied(document([looped]))
        expect(repaired.items[0].mindMap?.parent == nil, "a self-parented node is repaired")
        expect(EaselMindMap.tree(of: [looped]).roots == [plain.id], "a self-parented node becomes a root")
        var picture = EaselItem(kind: .freehand, frame: EaselRect(x: 0, y: 0, width: 10, height: 10))
        picture.points = [EaselPoint(x: 0, y: 0), EaselPoint(x: 10, y: 10)]
        picture.mindMap = EaselMindMapLink()
        expect(!accepts([picture]), "drawings can't be nodes")
        var arrow = EaselItem(kind: .arrow, frame: EaselRect(x: 0, y: 0, width: 10, height: 10))
        arrow.points = [EaselPoint(x: 0, y: 0), EaselPoint(x: 10, y: 10)]
        arrow.mindMap = EaselMindMapLink()
        expect(!accepts([arrow]), "a branch needs a parent")
        arrow.mindMap = EaselMindMapLink(parent: plain.id, collapsed: true)
        expect(!accepts([arrow]), "a branch can't collapse")
        expect(EaselMindMap.canStart(from: plain) && !EaselMindMap.canStart(from: root), "plain text can become a root, a node can't")
        var shape = plain
        shape.kind = .rectangle
        expect(!EaselMindMap.canStart(from: shape), "only text becomes a root")
    }

    @MainActor static func starterMap() {
        let (map, root, kids) = starter()
        expect(nodes(map).count == 3 && branches(map).count == 2, "a new map is a root with two children joined by branches")
        expect(accepts(map.items), "a new map is a valid Easel")
        guard let top = item(root, in: map), let one = item(kids[0], in: map), let two = item(kids[1], in: map) else {
            return expect(false, "every node is placed")
        }
        expect(top.frame.x == 400 && top.frame.y == 300, "the root stays put")
        expect(one.frame.x == top.frame.x + top.frame.width + EaselMindMap.rootGap, "children sit one gap to the right of the root")
        expect(one.frame.x == two.frame.x && one.frame.y < two.frame.y, "children stack in order")
        expect(two.frame.y - (one.frame.y + one.frame.height) == EaselMindMap.siblingGap, "siblings keep the sibling gap")
        let middle = (one.frame.y + two.frame.y + two.frame.height) / 2
        expect(abs(middle - (top.frame.y + top.frame.height / 2)) < 1, "children centre on their parent")
        let lines = branches(map)
        expect(lines.allSatisfy { $0.resolvedRouting == .curved && $0.resolvedEndHead == .none }, "branches are curved lines without heads")
        expect(lines.allSatisfy { $0.startConnection?.itemID == root && $0.startConnection?.side == .right }, "branches leave the root's right side")
        expect(Set(lines.compactMap { $0.endConnection?.itemID }) == Set(kids), "each child gets its own branch")
        expect(Set(lines.map(\.color)).count == 2, "first-level branches get different colours")
        let palette = Set(NoteColor.allCases.compactMap { EaselPalette.hex(.note($0), role: .ink) })
        expect(lines.allSatisfy { palette.contains($0.color) }, "branch colours come from the Notes palette")
        expect(EaselMindMap.tidied(map) == map, "laying out a tidy map changes nothing")
        var plain = node("Lonely")
        plain.mindMap = EaselMindMapLink()
        expect(EaselMindMap.creatingMap(root: plain, children: [], in: document([plain])) == nil, "a node can't start a second map")
    }

    @MainActor static func children() {
        let (map, root, kids) = starter()
        guard let template = EaselMindMap.template(forChildOf: kids[0], in: map),
              let grown = EaselMindMap.adding(template, to: kids[0], in: map),
              let child = item(template.id, in: grown), let parent = item(kids[0], in: grown) else {
            return expect(false, "a child can be added")
        }
        expect(template.text.isEmpty && template.kind == .text && template.textStyle?.autoWidth == true, "a new child starts empty and hugs its text")
        expect(child.mindMap?.parent == kids[0], "the child links to its parent")
        expect(child.frame.x == parent.frame.x + parent.frame.width + EaselMindMap.levelGap, "deeper levels use the level gap")
        let parentBranch = branches(grown).first { $0.endConnection?.itemID == kids[0] }
        let childBranch = branches(grown).first { $0.endConnection?.itemID == template.id }
        expect(parentBranch != nil && childBranch?.color == parentBranch?.color, "children inherit their branch colour")
        expect(childBranch?.strokeWidth == EaselMindMap.deepBranchWidth, "deeper branches are thinner")
        expect(!overlaps(grown), "adding a child keeps nodes apart")
        guard let sibling = EaselMindMap.template(forChildOf: root, in: grown),
              let wider = EaselMindMap.addingSibling(sibling, after: kids[0], in: grown) else {
            return expect(false, "a sibling can be added")
        }
        let order = EaselMindMap.tree(of: wider.items).nodes[root]?.children ?? []
        expect(order == [kids[0], sibling.id, kids[1]], "a sibling lands right after its node")
        expect(Set(branches(wider).filter { $0.startConnection?.itemID == root }.map(\.color)).count == 3, "each first-level branch steps to a new colour")
        expect(!overlaps(wider), "adding a sibling keeps nodes apart")
        var locked = map
        if let index = locked.items.firstIndex(where: { $0.id == kids[0] }) { locked.items[index].locked = true }
        expect(EaselMindMap.adding(template, to: kids[0], in: locked) == nil, "a locked node takes no children")
    }

    @MainActor static func twoSided() {
        let (map, root, _) = starter()
        guard let template = EaselMindMap.template(forChildOf: root, side: .left, in: map),
              let both = EaselMindMap.adding(template, to: root, side: .left, in: map),
              let left = item(template.id, in: both), let top = item(root, in: both) else {
            return expect(false, "a child can go on the left")
        }
        expect(left.mindMap?.side == .left, "a left child remembers its side")
        expect(left.frame.x + left.frame.width + EaselMindMap.rootGap == top.frame.x, "left children sit one gap to the left of the root")
        expect(abs(left.frame.y + left.frame.height / 2 - (top.frame.y + top.frame.height / 2)) < 1, "a lone left child centres on the root")
        let branch = branches(both).first { $0.endConnection?.itemID == template.id }
        expect(branch?.startConnection?.side == .left && branch?.endConnection?.side == .right, "left branches leave the root's left side")
        guard let grand = EaselMindMap.template(forChildOf: template.id, in: both),
              let deeper = EaselMindMap.adding(grand, to: template.id, in: both), let leaf = item(grand.id, in: deeper),
              let parent = item(template.id, in: deeper) else { return expect(false, "left nodes take children") }
        expect(leaf.frame.x + leaf.frame.width + EaselMindMap.levelGap == parent.frame.x, "left subtrees keep growing left")
        expect(leaf.mindMap?.side == nil, "only first-level nodes save a side")
        expect(EaselMindMap.balancedSide(of: root, in: EaselMindMap.tree(of: deeper.items)) == .left, "new root children balance the sides")
        expect(!overlaps(deeper), "two-sided maps keep nodes apart")
    }

    @MainActor static func spacing() {
        var (map, root, kids) = starter()
        var parents = kids
        for round in 0..<3 {
            var next: [UUID] = []
            for parent in parents {
                for index in 0..<2 {
                    let child = node("Node \(round)-\(index)", width: Double(60 + 20 * index), height: Double(24 + 18 * round))
                    if let grown = EaselMindMap.adding(child, to: parent, in: map) { map = grown; next.append(child.id) }
                }
            }
            parents = next
        }
        expect(nodes(map).count == 3 + 4 + 8 + 16, "a deep map keeps every node")
        expect(!overlaps(map), "a deep map lays out without overlaps")
        let tree = EaselMindMap.tree(of: map.items)
        for (id, entry) in tree.nodes {
            guard let parentID = entry.parent, let child = item(id, in: map), let parent = item(parentID, in: map) else { continue }
            let gap = child.frame.x - (parent.frame.x + parent.frame.width)
            expect(gap == EaselMindMap.gap(depth: entry.depth), "every child keeps the gap for its depth")
        }
        if let index = map.items.firstIndex(where: { $0.id == kids[0] }) { map.items[index].frame.height = 220 }
        let grown = EaselMindMap.tidied(map)
        expect(!overlaps(grown), "a node that grows pushes its neighbours apart")
        expect(item(root, in: grown)?.frame == item(root, in: map)?.frame, "re-laying out keeps the root still")
    }

    @MainActor static func movingAndSnapping() {
        let (map, root, kids) = starter()
        var moved = map
        if let index = moved.items.firstIndex(where: { $0.id == root }) { moved.items[index].frame.x += 100; moved.items[index].frame.y += 50 }
        let carried = EaselDependents.settle(moved, previous: map, moved: [root])
        for id in kids {
            guard let before = item(id, in: map)?.frame, let after = item(id, in: carried)?.frame else { return expect(false, "children survive") }
            expect(after.x == before.x + 100 && after.y == before.y + 50, "moving the root moves the whole map")
        }
        let lines = branches(carried)
        expect(lines.count == 2 && lines.allSatisfy { line in
            branches(map).contains { $0.id == line.id && $0.frame.x + 100 == line.frame.x }
        }, "branches follow their nodes")
        var stray = map
        if let index = stray.items.firstIndex(where: { $0.id == kids[1] }) { stray.items[index].frame.x += 300 }
        let preview = EaselDependents.settle(stray, context: EaselSettleContext(previous: map), moved: [kids[1]], tidy: false)
        expect(item(kids[1], in: preview)?.frame.x == (item(kids[1], in: map)?.frame.x ?? 0) + 300, "a drag preview lets a node wander")
        let snapped = EaselDependents.settle(stray, previous: map, moved: [kids[1]])
        expect(item(kids[1], in: snapped)?.frame == item(kids[1], in: map)?.frame, "a node let go away from any slot snaps back into place")
    }

    @MainActor static func removal() {
        let (start, root, kids) = starter()
        guard let leaf = EaselMindMap.template(forChildOf: kids[0], in: start),
              let map = EaselMindMap.adding(leaf, to: kids[0], in: start) else { return expect(false, "a leaf can be added") }
        let removed = EaselDependents.removing([kids[0]], from: map)
        expect(item(kids[0], in: removed) == nil && item(leaf.id, in: removed) == nil, "deleting a node deletes its subtree")
        expect(branches(removed).count == 1, "deleting a node deletes its branches")
        expect(EaselDependents.removalClosure([kids[0]], in: map).count == 4, "the subtree and both branches go in one step")
        guard let branch = branches(map).first(where: { $0.endConnection?.itemID == kids[0] }) else { return expect(false, "the branch exists") }
        let cut = EaselMindMap.tidied(EaselDependents.removing([branch.id], from: map))
        expect(item(kids[0], in: cut)?.mindMap == EaselMindMapLink(), "deleting a branch turns its node into a new root")
        expect(item(leaf.id, in: cut)?.mindMap?.parent == kids[0], "the detached node keeps its own children")
        expect(EaselMindMap.tree(of: cut.items).roots.count == 2, "the map splits in two")
        let gone = EaselMindMap.tidied(EaselDependents.removing([root], from: map))
        expect(nodes(gone).isEmpty && branches(gone).isEmpty, "deleting the root deletes the whole map")
    }

    @MainActor static func reparenting() {
        let (map, root, kids) = starter()
        guard let indented = EaselMindMap.indenting(kids[1], in: map) else { return expect(false, "the second child can indent") }
        expect(item(kids[1], in: indented)?.mindMap?.parent == kids[0], "Tab makes a node the child of the sibling above")
        expect(EaselMindMap.indenting(kids[0], in: map) == nil, "the first child has no sibling above to join")
        expect(!overlaps(indented), "indenting keeps nodes apart")
        guard let outdented = EaselMindMap.outdenting(kids[1], in: indented) else { return expect(false, "an indented node can come back") }
        expect(item(kids[1], in: outdented)?.mindMap?.parent == root, "Shift-Tab moves a node up a level")
        expect(EaselMindMap.tree(of: outdented.items).nodes[root]?.children == kids, "it lands right after its old parent")
        expect(EaselMindMap.outdenting(kids[0], in: map) == nil, "first-level nodes can't outdent past the root")
    }

    @MainActor static func collapsing() {
        let (start, _, kids) = starter()
        guard let leaf = EaselMindMap.template(forChildOf: kids[0], in: start),
              let map = EaselMindMap.adding(leaf, to: kids[0], in: start) else { return expect(false, "a leaf can be added") }
        expect(EaselMindMap.settingCollapsed(true, [kids[1]], in: map) == nil, "a leaf has nothing to collapse")
        guard let folded = EaselMindMap.settingCollapsed(true, [kids[0]], in: map) else { return expect(false, "a branch collapses") }
        expect(item(kids[0], in: folded)?.mindMap?.collapsed == true, "collapsing saves on the node")
        let hidden = EaselMindMap.hiddenIDs(in: folded.items)
        let leafBranch = branches(folded).first { $0.endConnection?.itemID == leaf.id }?.id
        expect(hidden.contains(leaf.id) && leafBranch.map(hidden.contains) == true && hidden.count == 2, "collapsing hides the subtree and its branches")
        expect(EaselBoardObjects.hiddenIDs(in: folded.items) == hidden, "the board hides collapsed nodes everywhere")
        expect(EaselMindMap.hiddenCount(of: kids[0], in: EaselMindMap.tree(of: folded.items)) == 1, "the chip counts hidden nodes")
        guard let template = EaselMindMap.template(forChildOf: kids[0], in: folded),
              let opened = EaselMindMap.adding(template, to: kids[0], in: folded) else { return expect(false, "a collapsed node takes children") }
        expect(item(kids[0], in: opened)?.mindMap?.collapsed == nil, "adding a child expands its parent")
        let expanded = EaselMindMap.settingCollapsed(false, [kids[0]], in: folded)
        expect(expanded.map { EaselMindMap.hiddenIDs(in: $0.items).isEmpty } == true, "expanding shows the subtree again")
    }

    @MainActor static func dropping() {
        let (map, root, kids) = starter()
        guard let target = item(kids[0], in: map), let dragged = item(kids[1], in: map) else { return expect(false, "nodes exist") }
        let pointer = EaselPoint(x: target.frame.x + 10, y: target.frame.y + 10)
        guard let drop = EaselMindMap.drop(for: kids[1], frame: dragged.frame, pointer: pointer, in: map) else {
            return expect(false, "dropping onto a node finds it")
        }
        expect(drop.parent == kids[0] && drop.onto, "dropping onto a node makes it the parent")
        guard let moved = EaselMindMap.moving(kids[1], to: drop, in: map) else { return expect(false, "the drop applies") }
        expect(item(kids[1], in: moved)?.mindMap?.parent == kids[0], "the dropped node joins its new parent")
        expect(EaselMindMap.moving(root, to: EaselMindMapDrop(parent: kids[0], side: .right, index: 0, onto: true, slot: pointer), in: map) == nil,
               "a node can't move under its own subtree")
        let loose = node("Loose", kind: .sticky)
        let board = EaselDocument(id: map.id, title: map.title, createdAt: map.createdAt, modifiedAt: map.modifiedAt, items: map.items + [loose])
        guard let attach = EaselMindMap.drop(for: loose.id, frame: loose.frame, pointer: pointer, in: board),
              let attached = EaselMindMap.moving(loose.id, to: attach, in: board) else { return expect(false, "an object can be dropped on a node") }
        expect(item(loose.id, in: attached)?.mindMap?.parent == kids[0], "dropping an object on a node attaches it")
        expect(branches(attached).count == 3, "the attached object gets a branch")
        let far = EaselPoint(x: 5_000, y: 5_000)
        expect(EaselMindMap.drop(for: loose.id, frame: loose.frame, pointer: far, in: board) == nil, "far from the map nothing attaches")
        guard let reorder = EaselMindMap.drop(for: kids[1], frame: EaselRect(x: dragged.frame.x, y: target.frame.y - 30,
                                                                                width: dragged.frame.width, height: dragged.frame.height),
                                              pointer: EaselPoint(x: -100, y: -100), in: map) else { return expect(false, "a slot is found") }
        expect(reorder.parent == root && reorder.index == 0 && !reorder.onto, "dragging above a sibling offers the slot before it")
        let swapped = EaselMindMap.moving(kids[1], to: reorder, in: map)
        expect(swapped.map { EaselMindMap.tree(of: $0.items).nodes[root]?.children } == [kids[1], kids[0]], "reordering swaps siblings")
    }

    @MainActor static func copying() {
        let (map, _, kids) = starter()
        let whole = Set(map.items.map(\.id))
        guard let copy = EaselArrange.duplicating(whole, in: map) else { return expect(false, "a map duplicates") }
        let settled = EaselMindMap.tidied(copy.document)
        expect(EaselMindMap.tree(of: settled.items).roots.count == 2, "a duplicated map is its own map")
        expect(nodes(settled).count == 6 && branches(settled).count == 4, "the copy keeps every node and branch")
        expect(accepts(settled.items), "a duplicated map is valid")
        expect(EaselMindMap.tree(of: settled.items).hidden.isEmpty, "nothing is hidden in an open map")
        guard let single = EaselArrange.duplicating([kids[0]], in: map) else { return expect(false, "a node duplicates") }
        let lone = single.copies.compactMap { item($0, in: single.document) }
        expect(lone.count == 1 && lone[0].mindMap == nil, "a lone copied leaf becomes a plain object")
        guard let leaf = EaselMindMap.template(forChildOf: kids[0], in: map),
              let deep = EaselMindMap.adding(leaf, to: kids[0], in: map) else { return expect(false, "a grandchild is added") }
        let below = EaselMindMap.tree(of: deep.items).nodes[kids[0]]?.children ?? []
        guard let grand = below.first else { return expect(false, "the grandchild exists") }
        let part = Set([kids[0], grand] + deep.items.filter { EaselMindMap.isBranch($0) && $0.endConnection?.itemID == grand }.map(\.id))
        guard let partial = EaselArrange.duplicating(part, in: deep) else { return expect(false, "part of a map duplicates") }
        let pasted = partial.copies.compactMap { item($0, in: partial.document) }
        expect(pasted.filter { $0.kind == .arrow }.allSatisfy { $0.startConnection != nil && $0.endConnection != nil },
               "pasting part of a map leaves no loose branch")
        let top = pasted.first { $0.kind != .arrow && $0.text == item(kids[0], in: map)?.text }
        let settledPart = EaselMindMap.tidied(partial.document)
        expect(top.flatMap { item($0.id, in: settledPart) }?.mindMap?.parent == nil, "the pasted top node becomes a root")
        expect(EaselMindMap.tree(of: settledPart.items).roots.count == 2, "the pasted piece is its own map")
    }

    @MainActor static func export() {
        let (start, _, kids) = starter()
        guard let leaf = EaselMindMap.template(forChildOf: kids[0], in: start),
              let map = EaselMindMap.adding(leaf, to: kids[0], in: start),
              let folded = EaselMindMap.settingCollapsed(true, [kids[0]], in: map) else { return expect(false, "a map can fold") }
        let open = EaselVectorExport.svg(map.items, art: EaselVectorArt(), title: "Map")
        let closed = EaselVectorExport.svg(folded.items, art: EaselVectorArt(), title: "Map")
        expect(open.components(separatedBy: "<path").count > closed.components(separatedBy: "<path").count, "exports leave out collapsed branches")
        expect(branches(map).allSatisfy { !EaselVectorExport.element($0, art: EaselVectorArt()).isEmpty }, "branches export as connectors")
    }
}
