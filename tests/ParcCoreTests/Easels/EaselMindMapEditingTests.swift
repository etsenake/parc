import Foundation
import Testing
@testable import ParcCore

struct EaselMindMapEditingTests {
    @Test
    func movingTheRootCarriesItsNodesAndBranches() throws {
        let (map, root, kids) = EaselMindMapTestsSupport.starter()
        var moved = map
        if let index = moved.items.firstIndex(where: { $0.id == root }) { moved.items[index].frame.x += 100; moved.items[index].frame.y += 50 }
        let carried = EaselDependents.settle(moved, previous: map, moved: [root])
        for id in kids {
            let before = try #require(EaselMindMapTestsSupport.item(id, in: map)?.frame, "children survive")
            let after = try #require(EaselMindMapTestsSupport.item(id, in: carried)?.frame, "children survive")
            #expect(after.x == before.x + 100 && after.y == before.y + 50, "moving the root moves the whole map")
        }
        let lines = EaselMindMapTestsSupport.branches(carried)
        #expect(lines.count == 2 && lines.allSatisfy { line in
            EaselMindMapTestsSupport.branches(map).contains { $0.id == line.id && $0.frame.x + 100 == line.frame.x }
        }, "branches follow their nodes")
    }

    @Test
    func aDragPreviewCanMoveANodeOutsideItsSlot() {
        let (map, _, kids) = EaselMindMapTestsSupport.starter()
        var stray = map
        if let index = stray.items.firstIndex(where: { $0.id == kids[1] }) { stray.items[index].frame.x += 300 }
        let preview = EaselDependents.settle(stray, context: EaselSettleContext(previous: map), moved: [kids[1]], tidy: false)
        #expect(EaselMindMapTestsSupport.item(kids[1], in: preview)?.frame.x == (EaselMindMapTestsSupport.item(kids[1], in: map)?.frame.x ?? 0) + 300, "a drag preview lets a node wander")
    }

    @Test
    func releasingANodeOutsideASlotSnapsItBack() {
        let (map, _, kids) = EaselMindMapTestsSupport.starter()
        var stray = map
        if let index = stray.items.firstIndex(where: { $0.id == kids[1] }) { stray.items[index].frame.x += 300 }
        let snapped = EaselDependents.settle(stray, previous: map, moved: [kids[1]])
        #expect(EaselMindMapTestsSupport.item(kids[1], in: snapped)?.frame == EaselMindMapTestsSupport.item(kids[1], in: map)?.frame, "a node let go away from any slot snaps back into place")
    }

    @Test
    func deletingANodeTakesItsSubtreeAndBranches() {
        let (start, _, kids) = EaselMindMapTestsSupport.starter()
        guard let leaf = EaselMindMap.template(forChildOf: kids[0], in: start),
              let map = EaselMindMap.adding(leaf, to: kids[0], in: start) else { Issue.record("a leaf can be added"); return }
        let removed = EaselDependents.removing([kids[0]], from: map)
        #expect(EaselMindMapTestsSupport.item(kids[0], in: removed) == nil && EaselMindMapTestsSupport.item(leaf.id, in: removed) == nil, "deleting a node deletes its subtree")
        #expect(EaselMindMapTestsSupport.branches(removed).count == 1, "deleting a node deletes its branches")
        #expect(EaselDependents.removalClosure([kids[0]], in: map).count == 4, "the subtree and both branches go in one step")
    }

    @Test
    func deletingABranchCreatesANewRootForTheDetachedSubtree() throws {
        let (start, _, kids) = EaselMindMapTestsSupport.starter()
        guard let leaf = EaselMindMap.template(forChildOf: kids[0], in: start),
              let map = EaselMindMap.adding(leaf, to: kids[0], in: start) else { Issue.record("a leaf can be added"); return }
        let branch = try #require(EaselMindMapTestsSupport.branches(map).first(where: { $0.endConnection?.itemID == kids[0] }), "the branch exists")
        let cut = EaselMindMap.tidied(EaselDependents.removing([branch.id], from: map))
        #expect(EaselMindMapTestsSupport.item(kids[0], in: cut)?.mindMap == EaselMindMapLink(), "deleting a branch turns its node into a new root")
        #expect(EaselMindMapTestsSupport.item(leaf.id, in: cut)?.mindMap?.parent == kids[0], "the detached node keeps its own children")
        #expect(EaselMindMap.tree(of: cut.items).roots.count == 2, "the map splits in two")
    }

    @Test
    func deletingTheRootRemovesTheWholeMap() {
        let (start, root, kids) = EaselMindMapTestsSupport.starter()
        guard let leaf = EaselMindMap.template(forChildOf: kids[0], in: start),
              let map = EaselMindMap.adding(leaf, to: kids[0], in: start) else { Issue.record("a leaf can be added"); return }
        let gone = EaselMindMap.tidied(EaselDependents.removing([root], from: map))
        #expect(EaselMindMapTestsSupport.nodes(gone).isEmpty && EaselMindMapTestsSupport.branches(gone).isEmpty, "deleting the root deletes the whole map")
    }

    @Test
    func indentingMakesANodeTheChildOfItsPreviousSibling() throws {
        let (map, _, kids) = EaselMindMapTestsSupport.starter()
        let indented = try #require(EaselMindMap.indenting(kids[1], in: map), "the second child can indent")
        #expect(EaselMindMapTestsSupport.item(kids[1], in: indented)?.mindMap?.parent == kids[0], "Tab makes a node the child of the sibling above")
        #expect(!EaselMindMapTestsSupport.overlaps(indented), "indenting keeps nodes apart")
    }

    @Test
    func indentRequiresAPreviousSibling() {
        let (map, _, kids) = EaselMindMapTestsSupport.starter()
        #expect(EaselMindMap.indenting(kids[0], in: map) == nil, "the first child has no sibling above to join")
    }

    @Test
    func outdentingMovesAfterItsFormerParent() throws {
        let (map, root, kids) = EaselMindMapTestsSupport.starter()
        let indented = try #require(EaselMindMap.indenting(kids[1], in: map), "the second child can indent")
        let outdented = try #require(EaselMindMap.outdenting(kids[1], in: indented), "an indented node can come back")
        #expect(EaselMindMapTestsSupport.item(kids[1], in: outdented)?.mindMap?.parent == root, "Shift-Tab moves a node up a level")
        #expect(EaselMindMap.tree(of: outdented.items).nodes[root]?.children == kids, "it lands right after its old parent")
    }

    @Test
    func firstLevelNodesCannotOutdent() {
        let (map, _, kids) = EaselMindMapTestsSupport.starter()
        #expect(EaselMindMap.outdenting(kids[0], in: map) == nil, "first-level nodes can't outdent past the root")
    }

    @Test func collapsingHidesASubtreeAndItsBranches() throws {
        let (start, _, kids) = EaselMindMapTestsSupport.starter()
        guard let leaf = EaselMindMap.template(forChildOf: kids[0], in: start),
              let map = EaselMindMap.adding(leaf, to: kids[0], in: start) else { Issue.record("a leaf can be added"); return }
        #expect(EaselMindMap.settingCollapsed(true, [kids[1]], in: map) == nil, "a leaf has nothing to collapse")
        let folded = try #require(EaselMindMap.settingCollapsed(true, [kids[0]], in: map), "a branch collapses")
        #expect(EaselMindMapTestsSupport.item(kids[0], in: folded)?.mindMap?.collapsed == true, "collapsing saves on the node")
        let hidden = EaselMindMap.hiddenIDs(in: folded.items)
        let leafBranch = EaselMindMapTestsSupport.branches(folded).first { $0.endConnection?.itemID == leaf.id }?.id
        #expect(hidden.contains(leaf.id) && leafBranch.map(hidden.contains) == true && hidden.count == 2, "collapsing hides the subtree and its branches")
        #expect(EaselBoardObjects.hiddenIDs(in: folded.items) == hidden, "the board hides collapsed nodes everywhere")
        #expect(EaselMindMap.hiddenCount(of: kids[0], in: EaselMindMap.tree(of: folded.items)) == 1, "the chip counts hidden nodes")
        guard let template = EaselMindMap.template(forChildOf: kids[0], in: folded),
              let opened = EaselMindMap.adding(template, to: kids[0], in: folded) else { Issue.record("a collapsed node takes children"); return }
        #expect(EaselMindMapTestsSupport.item(kids[0], in: opened)?.mindMap?.collapsed == nil, "adding a child expands its parent")
        let expanded = EaselMindMap.settingCollapsed(false, [kids[0]], in: folded)
        #expect(expanded.map { EaselMindMap.hiddenIDs(in: $0.items).isEmpty } == true, "expanding shows the subtree again")
    }

    @Test
    func droppingANodeOntoAnotherMakesItTheParent() throws {
        let (map, _, kids) = EaselMindMapTestsSupport.starter()
        let target = try #require(EaselMindMapTestsSupport.item(kids[0], in: map), "nodes exist")
        let dragged = try #require(EaselMindMapTestsSupport.item(kids[1], in: map), "nodes exist")
        let pointer = EaselPoint(x: target.frame.x + 10, y: target.frame.y + 10)
        guard let drop = EaselMindMap.drop(for: kids[1], frame: dragged.frame, pointer: pointer, in: map) else {
            Issue.record("dropping onto a node finds it"); return
        }
        #expect(drop.parent == kids[0] && drop.onto, "dropping onto a node makes it the parent")
        let moved = try #require(EaselMindMap.moving(kids[1], to: drop, in: map), "the drop applies")
        #expect(EaselMindMapTestsSupport.item(kids[1], in: moved)?.mindMap?.parent == kids[0], "the dropped node joins its new parent")
    }

    @Test
    func aNodeCannotMoveUnderItsOwnSubtree() throws {
        let (map, root, kids) = EaselMindMapTestsSupport.starter()
        let target = try #require(EaselMindMapTestsSupport.item(kids[0], in: map), "nodes exist")
        let pointer = EaselPoint(x: target.frame.x + 10, y: target.frame.y + 10)
        #expect(EaselMindMap.moving(root, to: EaselMindMapDrop(parent: kids[0], side: .right, index: 0, onto: true, slot: pointer), in: map) == nil,
               "a node can't move under its own subtree")
    }

    @Test
    func anObjectDroppedOnANodeGetsAParentAndBranch() throws {
        let (map, _, kids) = EaselMindMapTestsSupport.starter()
        let target = try #require(EaselMindMapTestsSupport.item(kids[0], in: map), "nodes exist")
        let pointer = EaselPoint(x: target.frame.x + 10, y: target.frame.y + 10)
        let loose = EaselMindMapTestsSupport.node("Loose", kind: .sticky)
        let board = EaselDocument(id: map.id, title: map.title, createdAt: map.createdAt, modifiedAt: map.modifiedAt, items: map.items + [loose])
        guard let attach = EaselMindMap.drop(for: loose.id, frame: loose.frame, pointer: pointer, in: board),
              let attached = EaselMindMap.moving(loose.id, to: attach, in: board) else { Issue.record("an object can be dropped on a node"); return }
        #expect(EaselMindMapTestsSupport.item(loose.id, in: attached)?.mindMap?.parent == kids[0], "dropping an object on a node attaches it")
        #expect(EaselMindMapTestsSupport.branches(attached).count == 3, "the attached object gets a branch")
    }

    @Test
    func anObjectFarFromTheMapDoesNotAttach() {
        let (map, _, _) = EaselMindMapTestsSupport.starter()
        let loose = EaselMindMapTestsSupport.node("Loose", kind: .sticky)
        let board = EaselDocument(id: map.id, title: map.title, createdAt: map.createdAt, modifiedAt: map.modifiedAt, items: map.items + [loose])
        let far = EaselPoint(x: 5_000, y: 5_000)
        #expect(EaselMindMap.drop(for: loose.id, frame: loose.frame, pointer: far, in: board) == nil, "far from the map nothing attaches")
    }

    @Test
    func draggingAboveASiblingMovesToTheSlotBeforeIt() throws {
        let (map, root, kids) = EaselMindMapTestsSupport.starter()
        let target = try #require(EaselMindMapTestsSupport.item(kids[0], in: map), "nodes exist")
        let dragged = try #require(EaselMindMapTestsSupport.item(kids[1], in: map), "nodes exist")
        guard let reorder = EaselMindMap.drop(for: kids[1], frame: EaselRect(x: dragged.frame.x, y: target.frame.y - 30,
                                                                                width: dragged.frame.width, height: dragged.frame.height),
                                              pointer: EaselPoint(x: -100, y: -100), in: map) else { Issue.record("a slot is found"); return }
        #expect(reorder.parent == root && reorder.index == 0 && !reorder.onto, "dragging above a sibling offers the slot before it")
        let swapped = EaselMindMap.moving(kids[1], to: reorder, in: map)
        #expect(swapped.map { EaselMindMap.tree(of: $0.items).nodes[root]?.children } == [kids[1], kids[0]], "reordering swaps siblings")
    }
}
