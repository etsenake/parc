import Foundation
import Testing
@testable import ParcCore

struct EaselMindMapModelTests {
    @MainActor @Test func mindMapNodesSaveTheirParent() throws {
        let plain = EaselMindMapTestsSupport.node("Plain")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let bare = String(decoding: (try? encoder.encode(plain)) ?? Data(), as: UTF8.self)
        #expect(!bare.contains("mindMap"), "objects outside a mind map save no mind map field")
        var child = EaselMindMapTestsSupport.node("Child")
        child.mindMap = EaselMindMapLink(parent: plain.id, side: .left)
        let data = (try? encoder.encode(child)) ?? Data()
        #expect(String(decoding: data, as: UTF8.self).contains("\"mindMap\":{\"parent\""), "a node saves its parent")
        #expect((try? JSONDecoder().decode(EaselItem.self, from: data)) == child, "a node round-trips")
        var root = plain
        root.mindMap = EaselMindMapLink()
        #expect(EaselMindMapTestsSupport.accepts([root, child]), "a root and its child are valid")
        var sided = plain
        sided.mindMap = EaselMindMapLink(side: .left)
        #expect(!EaselMindMapTestsSupport.accepts([sided]), "a root can't pick a side")
        var looped = plain
        looped.mindMap = EaselMindMapLink(parent: plain.id)
        #expect(EaselMindMapTestsSupport.accepts([looped]), "a node that is its own parent still opens")
        let repaired = EaselMindMap.tidied(EaselMindMapTestsSupport.document([looped]))
        #expect(repaired.items[0].mindMap?.parent == nil, "a self-parented node is repaired")
        #expect(EaselMindMap.tree(of: [looped]).roots == [plain.id], "a self-parented node becomes a root")
        var picture = EaselItem(kind: .freehand, frame: EaselRect(x: 0, y: 0, width: 10, height: 10))
        picture.points = [EaselPoint(x: 0, y: 0), EaselPoint(x: 10, y: 10)]
        picture.mindMap = EaselMindMapLink()
        #expect(!EaselMindMapTestsSupport.accepts([picture]), "drawings can't be nodes")
        var arrow = EaselItem(kind: .arrow, frame: EaselRect(x: 0, y: 0, width: 10, height: 10))
        arrow.points = [EaselPoint(x: 0, y: 0), EaselPoint(x: 10, y: 10)]
        arrow.mindMap = EaselMindMapLink()
        #expect(!EaselMindMapTestsSupport.accepts([arrow]), "a branch needs a parent")
        arrow.mindMap = EaselMindMapLink(parent: plain.id, collapsed: true)
        #expect(!EaselMindMapTestsSupport.accepts([arrow]), "a branch can't collapse")
        #expect(EaselMindMap.canStart(from: plain) && !EaselMindMap.canStart(from: root), "plain text can become a root, a node can't")
        var shape = plain
        shape.kind = .rectangle
        #expect(!EaselMindMap.canStart(from: shape), "only text becomes a root")
    }

    @MainActor @Test func aNewMapIsARootWithTwoChildrenJoinedByBranches() {
        let (map, root, kids) = EaselMindMapTestsSupport.starter()
        #expect(EaselMindMapTestsSupport.nodes(map).count == 3 && EaselMindMapTestsSupport.branches(map).count == 2, "a new map is a root with two children joined by branches")
        #expect(EaselMindMapTestsSupport.accepts(map.items), "a new map is a valid Easel")
        guard let top = EaselMindMapTestsSupport.item(root, in: map), let one = EaselMindMapTestsSupport.item(kids[0], in: map), let two = EaselMindMapTestsSupport.item(kids[1], in: map) else {
            Issue.record("every node is placed"); return
        }
        #expect(top.frame.x == 400 && top.frame.y == 300, "the root stays put")
        #expect(one.frame.x == top.frame.x + top.frame.width + EaselMindMap.rootGap, "children sit one gap to the right of the root")
        #expect(one.frame.x == two.frame.x && one.frame.y < two.frame.y, "children stack in order")
        #expect(two.frame.y - (one.frame.y + one.frame.height) == EaselMindMap.siblingGap, "siblings keep the sibling gap")
        let middle = (one.frame.y + two.frame.y + two.frame.height) / 2
        #expect(abs(middle - (top.frame.y + top.frame.height / 2)) < 1, "children centre on their parent")
        let lines = EaselMindMapTestsSupport.branches(map)
        #expect(lines.allSatisfy { $0.resolvedRouting == .curved && $0.resolvedEndHead == .none }, "branches are curved lines without heads")
        #expect(lines.allSatisfy { $0.startConnection?.itemID == root && $0.startConnection?.side == .right }, "branches leave the root's right side")
        #expect(Set(lines.compactMap { $0.endConnection?.itemID }) == Set(kids), "each child gets its own branch")
        #expect(Set(lines.map(\.color)).count == 2, "first-level branches get different colours")
        let palette = Set(NoteColor.allCases.compactMap { EaselPalette.hex(.note($0), role: .ink) })
        #expect(lines.allSatisfy { palette.contains($0.color) }, "branch colours come from the Notes palette")
        #expect(EaselMindMap.tidied(map) == map, "laying out a tidy map changes nothing")
        var plain = EaselMindMapTestsSupport.node("Lonely")
        plain.mindMap = EaselMindMapLink()
        #expect(EaselMindMap.creatingMap(root: plain, children: [], in: EaselMindMapTestsSupport.document([plain])) == nil, "a node can't start a second map")
    }

    @Test func childrenCanBeAddedAndLinkToTheirParent() {
        let (map, root, kids) = EaselMindMapTestsSupport.starter()
        guard let template = EaselMindMap.template(forChildOf: kids[0], in: map),
              let grown = EaselMindMap.adding(template, to: kids[0], in: map),
              let child = EaselMindMapTestsSupport.item(template.id, in: grown), let parent = EaselMindMapTestsSupport.item(kids[0], in: grown) else {
            Issue.record("a child can be added"); return
        }
        #expect(template.text.isEmpty && template.kind == .text && template.textStyle?.autoWidth == true, "a new child starts empty and hugs its text")
        #expect(child.mindMap?.parent == kids[0], "the child links to its parent")
        #expect(child.frame.x == parent.frame.x + parent.frame.width + EaselMindMap.levelGap, "deeper levels use the level gap")
        let parentBranch = EaselMindMapTestsSupport.branches(grown).first { $0.endConnection?.itemID == kids[0] }
        let childBranch = EaselMindMapTestsSupport.branches(grown).first { $0.endConnection?.itemID == template.id }
        #expect(parentBranch != nil && childBranch?.color == parentBranch?.color, "children inherit their branch colour")
        #expect(childBranch?.strokeWidth == EaselMindMap.deepBranchWidth, "deeper branches are thinner")
        #expect(!EaselMindMapTestsSupport.overlaps(grown), "adding a child keeps nodes apart")
        guard let sibling = EaselMindMap.template(forChildOf: root, in: grown),
              let wider = EaselMindMap.addingSibling(sibling, after: kids[0], in: grown) else {
            Issue.record("a sibling can be added"); return
        }
        let order = EaselMindMap.tree(of: wider.items).nodes[root]?.children ?? []
        #expect(order == [kids[0], sibling.id, kids[1]], "a sibling lands right after its node")
        #expect(Set(EaselMindMapTestsSupport.branches(wider).filter { $0.startConnection?.itemID == root }.map(\.color)).count == 3, "each first-level branch steps to a new colour")
        #expect(!EaselMindMapTestsSupport.overlaps(wider), "adding a sibling keeps nodes apart")
        var locked = map
        if let index = locked.items.firstIndex(where: { $0.id == kids[0] }) { locked.items[index].locked = true }
        #expect(EaselMindMap.adding(template, to: kids[0], in: locked) == nil, "a locked node takes no children")
    }

    @Test func childrenCanGoOnEitherSideOfTheRoot() {
        let (map, root, _) = EaselMindMapTestsSupport.starter()
        guard let template = EaselMindMap.template(forChildOf: root, side: .left, in: map),
              let both = EaselMindMap.adding(template, to: root, side: .left, in: map),
              let left = EaselMindMapTestsSupport.item(template.id, in: both), let top = EaselMindMapTestsSupport.item(root, in: both) else {
            Issue.record("a child can go on the left"); return
        }
        #expect(left.mindMap?.side == .left, "a left child remembers its side")
        #expect(left.frame.x + left.frame.width + EaselMindMap.rootGap == top.frame.x, "left children sit one gap to the left of the root")
        #expect(abs(left.frame.y + left.frame.height / 2 - (top.frame.y + top.frame.height / 2)) < 1, "a lone left child centres on the root")
        let branch = EaselMindMapTestsSupport.branches(both).first { $0.endConnection?.itemID == template.id }
        #expect(branch?.startConnection?.side == .left && branch?.endConnection?.side == .right, "left branches leave the root's left side")
        guard let grand = EaselMindMap.template(forChildOf: template.id, in: both),
              let deeper = EaselMindMap.adding(grand, to: template.id, in: both), let leaf = EaselMindMapTestsSupport.item(grand.id, in: deeper),
              let parent = EaselMindMapTestsSupport.item(template.id, in: deeper) else { Issue.record("left nodes take children"); return }
        #expect(leaf.frame.x + leaf.frame.width + EaselMindMap.levelGap == parent.frame.x, "left subtrees keep growing left")
        #expect(leaf.mindMap?.side == nil, "only first-level nodes save a side")
        #expect(EaselMindMap.balancedSide(of: root, in: EaselMindMap.tree(of: deeper.items)) == .left, "new root children balance the sides")
        #expect(!EaselMindMapTestsSupport.overlaps(deeper), "two-sided maps keep nodes apart")
    }

    @Test func deepMapsLayOutWithoutOverlapsAndGrowingNodesPushNeighboursApart() {
        var (map, root, kids) = EaselMindMapTestsSupport.starter()
        var parents = kids
        for round in 0..<3 {
            var next: [UUID] = []
            for parent in parents {
                for index in 0..<2 {
                    let child = EaselMindMapTestsSupport.node("Node \(round)-\(index)", width: Double(60 + 20 * index), height: Double(24 + 18 * round))
                    if let grown = EaselMindMap.adding(child, to: parent, in: map) { map = grown; next.append(child.id) }
                }
            }
            parents = next
        }
        #expect(EaselMindMapTestsSupport.nodes(map).count == 3 + 4 + 8 + 16, "a deep map keeps every node")
        #expect(!EaselMindMapTestsSupport.overlaps(map), "a deep map lays out without overlaps")
        let tree = EaselMindMap.tree(of: map.items)
        for (id, entry) in tree.nodes {
            guard let parentID = entry.parent, let child = EaselMindMapTestsSupport.item(id, in: map), let parent = EaselMindMapTestsSupport.item(parentID, in: map) else { continue }
            let gap = child.frame.x - (parent.frame.x + parent.frame.width)
            #expect(gap == EaselMindMap.gap(depth: entry.depth), "every child keeps the gap for its depth")
        }
        if let index = map.items.firstIndex(where: { $0.id == kids[0] }) { map.items[index].frame.height = 220 }
        let grown = EaselMindMap.tidied(map)
        #expect(!EaselMindMapTestsSupport.overlaps(grown), "a node that grows pushes its neighbours apart")
        #expect(EaselMindMapTestsSupport.item(root, in: grown)?.frame == EaselMindMapTestsSupport.item(root, in: map)?.frame, "re-laying out keeps the root still")
    }
}
