import Foundation
import Testing
@testable import ParcCore

struct EaselPagesOrganizationTests {
    @Test
    func duplicatingAPageCopiesItsObjectsWithFreshIDs() {
        let sticky = EaselPagesTestsSupport.item(.sticky, x: 0, y: 0, z: 1), shape = EaselPagesTestsSupport.item(.rectangle, x: 300, y: 0, z: 2)
        var stamp = EaselPagesTestsSupport.item(.stamp, x: 10, y: 10, width: 32, height: 32, z: 3)
        stamp.stamp = "heart"
        stamp.attachedTo = sticky.id
        let link = EaselPagesTestsSupport.arrow(from: sticky.id, to: shape.id)
        var section = EaselPagesTestsSupport.item(.section, x: -50, y: -50, width: 600, height: 300, z: 0)
        section.text = "Plan"
        var grouped = [sticky, shape]
        let group = UUID()
        for index in grouped.indices { grouped[index].groupID = group }
        let board = EaselPagesTestsSupport.document(grouped + [stamp, link, section])
        guard let change = EaselPages.duplicating(nil, in: board), let pages = change.document.pages,
              let copyPage = change.page else { Issue.record("duplicate works"); return }
        #expect(pages.map(\.name) == ["Page 1", "Page 1 copy"], "the copy is named after the original")
        #expect(copyPage == pages[1].id, "duplicate switches to the copy")
        let originals = EaselPages.items(on: pages[0].id, in: change.document)
        let copies = EaselPages.items(on: copyPage, in: change.document)
        #expect(originals.count == 5 && copies.count == 5, "every object is copied")
        #expect(Set(copies.map(\.id)).isDisjoint(with: Set(originals.map(\.id))), "copies get fresh IDs")
        #expect(change.items == Set(copies.map(\.id)), "the change reports the copies")
        let copyIDs = Set(copies.map(\.id))
        guard let copiedArrow = copies.first(where: { $0.kind == .arrow }),
              let copiedStamp = copies.first(where: { $0.kind == .stamp }) else { Issue.record("copies keep kinds"); return }
        #expect(copiedArrow.startConnection.map { copyIDs.contains($0.itemID) } == true
               && copiedArrow.endConnection.map { copyIDs.contains($0.itemID) } == true, "connectors point inside the copy")
        #expect(copiedStamp.attachedTo.map(copyIDs.contains) == true, "attachments point inside the copy")
        let copiedGroups = Set(copies.compactMap(\.groupID))
        #expect(copiedGroups.count == 1 && !copiedGroups.contains(group), "groups get a fresh ID in the copy")
        #expect(copies.map(\.zIndex).sorted() == originals.map(\.zIndex).sorted(), "the copy keeps the layer order")
        let copiedSection = copies.first { $0.kind == .section }
        #expect(copiedSection.map { EaselBoardObjects.contents(of: $0, in: copies).count } == 4, "the section still holds its contents")
        #expect(EaselPages.validationProblem(change.document) == nil, "the duplicate is valid")
    }

    @Test
    func repeatCopiesGetANumber() throws {
        let sticky = EaselPagesTestsSupport.item(.sticky, x: 0, y: 0, z: 1), shape = EaselPagesTestsSupport.item(.rectangle, x: 300, y: 0, z: 2)
        var stamp = EaselPagesTestsSupport.item(.stamp, x: 10, y: 10, width: 32, height: 32, z: 3)
        stamp.stamp = "heart"
        stamp.attachedTo = sticky.id
        let link = EaselPagesTestsSupport.arrow(from: sticky.id, to: shape.id)
        var section = EaselPagesTestsSupport.item(.section, x: -50, y: -50, width: 600, height: 300, z: 0)
        section.text = "Plan"
        var grouped = [sticky, shape]
        let group = UUID()
        for index in grouped.indices { grouped[index].groupID = group }
        let board = EaselPagesTestsSupport.document(grouped + [stamp, link, section])
        guard let change = EaselPages.duplicating(nil, in: board), let pages = change.document.pages,
              change.page != nil else { Issue.record("duplicate works"); return }
        let again = try #require(EaselPages.duplicating(pages[0].id, in: change.document), "duplicate twice")
        #expect(again.document.pages?.map(\.name) == ["Page 1", "Page 1 copy 2", "Page 1 copy"], "repeat copies get a number")
    }

    @Test
    func deletingAPageRemovesItsObjectsAndFreesTheirDependents() throws {
        let keep = EaselPagesTestsSupport.item(.sticky, x: 0, y: 0)
        let (board, first, second) = EaselPagesTestsSupport.paged([keep])
        let add = try #require(EaselPages.adding(to: board, name: "Third"), "third page")
        var document = add.document
        let third = add.page!
        var doomed = EaselPagesTestsSupport.item(.rectangle, x: 0, y: 0)
        doomed.page = second
        var cross = EaselPagesTestsSupport.arrow(from: keep.id, to: doomed.id)
        cross.page = first
        var stuck = EaselPagesTestsSupport.item(.stamp, x: 0, y: 0, width: 32, height: 32)
        stuck.stamp = "dot"
        stuck.attachedTo = doomed.id
        stuck.page = first
        document.items += [doomed, cross, stuck]
        let change = try #require(EaselPages.deleting(second, in: document), "delete works")
        #expect(change.document.pages?.map(\.id) == [first, third], "the page is gone")
        #expect(!change.document.items.contains { $0.id == doomed.id }, "its objects go with it")
        #expect(change.items == [doomed.id], "the change reports what was removed")
        #expect(change.page == third, "the next page is shown")
        let freed = change.document.items.first { $0.id == cross.id }
        #expect(freed?.endConnection == nil && freed?.startConnection != nil, "connectors elsewhere let go of removed objects")
        #expect(change.document.items.first { $0.id == stuck.id }?.attachedTo == nil, "attachments elsewhere let go too")
        #expect(EaselPages.validationProblem(change.document) == nil, "the result is valid")
    }

    @Test
    func deletingTheLastDefaultPageFoldsBackIntoAPlainBoard() throws {
        let keep = EaselPagesTestsSupport.item(.sticky, x: 0, y: 0)
        let (board, first, second) = EaselPagesTestsSupport.paged([keep])
        let add = try #require(EaselPages.adding(to: board, name: "Third"), "third page")
        var document = add.document
        let third = add.page!
        var doomed = EaselPagesTestsSupport.item(.rectangle, x: 0, y: 0)
        doomed.page = second
        var cross = EaselPagesTestsSupport.arrow(from: keep.id, to: doomed.id)
        cross.page = first
        var stuck = EaselPagesTestsSupport.item(.stamp, x: 0, y: 0, width: 32, height: 32)
        stuck.stamp = "dot"
        stuck.attachedTo = doomed.id
        stuck.page = first
        document.items += [doomed, cross, stuck]
        let change = try #require(EaselPages.deleting(second, in: document), "delete works")
        let last = try #require(EaselPages.deleting(third, in: change.document), "delete the last extra page")
        #expect(last.document.pages == nil && last.document.items.allSatisfy { $0.page == nil }, "a lone Page 1 folds back into a plain board")
        #expect(last.page == nil, "a plain board has no page to show")
    }

    @Test
    func theOnlyPageCannotBeDeleted() {
        let keep = EaselPagesTestsSupport.item(.sticky, x: 0, y: 0)
        let (board, first, second) = EaselPagesTestsSupport.paged([keep])
        #expect(EaselPages.deleting(first, in: board.pages!.count == 2 ? EaselPages.deleting(second, in: board)!.document : board) == nil,
               "the only page can't be deleted")
    }

    @Test
    func aRenamedLastPageStays() {
        let keep = EaselPagesTestsSupport.item(.sticky, x: 0, y: 0)
        let (board, first, second) = EaselPagesTestsSupport.paged([keep])
        guard let renamed = EaselPages.renaming(first, to: "Ideas", in: board), let kept = EaselPages.deleting(second, in: renamed) else {
            Issue.record("renamed boards keep their page"); return
        }
        #expect(kept.document.pages?.map(\.name) == ["Ideas"], "a renamed last page stays")
    }

    @Test
    func dividersCanBeDeleted() {
        let keep = EaselPagesTestsSupport.item(.sticky, x: 0, y: 0)
        let (board, first, _) = EaselPagesTestsSupport.paged([keep])
        guard let withDivider = EaselPages.addingDivider(to: board, after: first),
              let dividerID = withDivider.document.pages?[1].id,
              let noDivider = EaselPages.deleting(dividerID, in: withDivider.document) else { Issue.record("delete a divider"); return }
        #expect(noDivider.document.pages?.count == 2, "dividers delete")
    }

    @Test
    func theLastRealPageStaysWhenOnlyDividersRemain() throws {
        let keep = EaselPagesTestsSupport.item(.sticky, x: 0, y: 0)
        let (board, first, second) = EaselPagesTestsSupport.paged([keep])
        let add = try #require(EaselPages.adding(to: board, name: "Third"), "third page")
        var document = add.document
        var doomed = EaselPagesTestsSupport.item(.rectangle, x: 0, y: 0)
        doomed.page = second
        var cross = EaselPagesTestsSupport.arrow(from: keep.id, to: doomed.id)
        cross.page = first
        var stuck = EaselPagesTestsSupport.item(.stamp, x: 0, y: 0, width: 32, height: 32)
        stuck.stamp = "dot"
        stuck.attachedTo = doomed.id
        stuck.page = first
        document.items += [doomed, cross, stuck]
        var lone = document
        lone.pages = [EaselPage(id: first, name: "Page 1"), EaselPage(id: second, name: "-")]
        lone.items = [keep]
        #expect(EaselPages.deleting(first, in: lone) == nil, "the last real page stays when only dividers remain")
    }

    @Test
    func movedObjectsKeepTheirLocationAndTakeTheirAttachments() throws {
        let sticky = EaselPagesTestsSupport.item(.sticky, x: 40, y: 60), other = EaselPagesTestsSupport.item(.rectangle, x: 400, y: 0)
        var stamp = EaselPagesTestsSupport.item(.stamp, x: 50, y: 70, width: 32, height: 32)
        stamp.stamp = "star"
        stamp.attachedTo = sticky.id
        var section = EaselPagesTestsSupport.item(.section, x: 600, y: 0, width: 400, height: 400)
        section.text = "Box"
        let inside = EaselPagesTestsSupport.item(.sticky, x: 650, y: 50)
        let (board, first, second) = EaselPagesTestsSupport.paged([sticky, other, stamp, section, inside])
        let change = try #require(EaselPages.movingItems([sticky.id], to: second, in: board), "move works")
        #expect(change.items == [sticky.id, stamp.id], "attached objects follow")
        #expect(change.page == second, "the change names the destination")
        let moved = EaselPages.items(on: second, in: change.document)
        #expect(Set(moved.map(\.id)) == [sticky.id, stamp.id], "objects land on the destination page")
        #expect(moved.first { $0.id == sticky.id }?.frame == sticky.frame, "objects land in the same area")
        #expect(EaselPages.items(on: first, in: change.document).count == 3, "the rest stay")
        #expect(EaselPages.validationProblem(change.document) == nil, "the move is valid")
    }

    @Test
    func movingASectionTakesItsContents() throws {
        let sticky = EaselPagesTestsSupport.item(.sticky, x: 40, y: 60), other = EaselPagesTestsSupport.item(.rectangle, x: 400, y: 0)
        var stamp = EaselPagesTestsSupport.item(.stamp, x: 50, y: 70, width: 32, height: 32)
        stamp.stamp = "star"
        stamp.attachedTo = sticky.id
        var section = EaselPagesTestsSupport.item(.section, x: 600, y: 0, width: 400, height: 400)
        section.text = "Box"
        let inside = EaselPagesTestsSupport.item(.sticky, x: 650, y: 50)
        let (board, _, second) = EaselPagesTestsSupport.paged([sticky, other, stamp, section, inside])
        let boxed = try #require(EaselPages.movingItems([section.id], to: second, in: board), "move a section")
        #expect(boxed.items == [section.id, inside.id], "a section carries its contents")
    }

    @Test
    func movingToTheSameOrMissingPageDoesNothing() {
        let sticky = EaselPagesTestsSupport.item(.sticky, x: 40, y: 60), other = EaselPagesTestsSupport.item(.rectangle, x: 400, y: 0)
        var stamp = EaselPagesTestsSupport.item(.stamp, x: 50, y: 70, width: 32, height: 32)
        stamp.stamp = "star"
        stamp.attachedTo = sticky.id
        var section = EaselPagesTestsSupport.item(.section, x: 600, y: 0, width: 400, height: 400)
        section.text = "Box"
        let inside = EaselPagesTestsSupport.item(.sticky, x: 650, y: 50)
        let (board, first, _) = EaselPagesTestsSupport.paged([sticky, other, stamp, section, inside])
        #expect(EaselPages.movingItems([sticky.id], to: first, in: board) == nil, "moving to the same page is no change")
        #expect(EaselPages.movingItems([sticky.id], to: UUID(), in: board) == nil, "moving to a missing page is refused")
    }

    @Test
    func objectsCannotMoveOntoADivider() {
        let sticky = EaselPagesTestsSupport.item(.sticky, x: 40, y: 60), other = EaselPagesTestsSupport.item(.rectangle, x: 400, y: 0)
        var stamp = EaselPagesTestsSupport.item(.stamp, x: 50, y: 70, width: 32, height: 32)
        stamp.stamp = "star"
        stamp.attachedTo = sticky.id
        var section = EaselPagesTestsSupport.item(.section, x: 600, y: 0, width: 400, height: 400)
        section.text = "Box"
        let inside = EaselPagesTestsSupport.item(.sticky, x: 650, y: 50)
        let (board, first, _) = EaselPagesTestsSupport.paged([sticky, other, stamp, section, inside])
        guard let divided = EaselPages.addingDivider(to: board, after: first), let divider = divided.document.pages?[1].id else {
            Issue.record("divider"); return
        }
        #expect(EaselPages.movingItems([sticky.id], to: divider, in: divided.document) == nil, "nothing moves onto a divider")
    }

    @Test func connectorsFollowOrLetGoWhenObjectsMovePages() throws {
        let a = EaselPagesTestsSupport.item(.rectangle, x: 0, y: 0), b = EaselPagesTestsSupport.item(.rectangle, x: 300, y: 0), c = EaselPagesTestsSupport.item(.rectangle, x: 600, y: 0)
        let ab = EaselPagesTestsSupport.arrow(from: a.id, to: b.id), bc = EaselPagesTestsSupport.arrow(from: b.id, to: c.id, x: 400)
        let free = EaselPagesTestsSupport.arrow(from: nil, to: nil, x: 0, y: 300)
        let (board, first, second) = EaselPagesTestsSupport.paged([a, b, c, ab, bc, free])
        let change = try #require(EaselPages.movingItems([a.id, b.id], to: second, in: board), "move connected")
        #expect(change.items == [a.id, b.id, ab.id], "a connector goes along when both ends move")
        let left = change.document.items.first { $0.id == bc.id }
        #expect(left?.page == first, "a half-moved connector stays on its page")
        #expect(left?.startConnection == nil && left?.endConnection?.itemID == c.id, "its moved end lets go")
        #expect(left?.frame.x == bc.frame.x && left?.points == bc.points, "the freed end stays where it was")
        let carried = change.document.items.first { $0.id == ab.id }
        #expect(carried?.startConnection?.itemID == a.id && carried?.endConnection?.itemID == b.id, "a carried connector stays connected")
        let lone = try #require(EaselPages.movingItems([bc.id], to: second, in: board), "move a connector alone")
        let alone = lone.document.items.first { $0.id == bc.id }
        #expect(alone?.page == second && alone?.startConnection == nil && alone?.endConnection == nil, "a selected connector moves free")
        let freeMove = try #require(EaselPages.movingItems([free.id], to: second, in: board), "free arrow")
        #expect(freeMove.items == [free.id], "free arrows move by themselves")
    }

    @Test func movedGroupsKeepTheirOrderOnTopOfTheDestination() throws {
        var a = EaselPagesTestsSupport.item(.sticky, x: 0, y: 0, z: 5), b = EaselPagesTestsSupport.item(.sticky, x: 200, y: 0, z: 6), c = EaselPagesTestsSupport.item(.sticky, x: 400, y: 0, z: 7)
        let group = UUID()
        a.groupID = group; b.groupID = group; c.groupID = group
        let (board, _, second) = EaselPagesTestsSupport.paged([a, b, c])
        let withTarget = try #require(EaselPages.adding(to: board), "page")
        var document = withTarget.document
        var resident = EaselPagesTestsSupport.item(.rectangle, x: 0, y: 0, z: 40)
        resident.page = second
        document.items.append(resident)
        let change = try #require(EaselPages.movingItems([a.id, b.id], to: second, in: document), "group move")
        let moved = change.document.items.filter { [a.id, b.id].contains($0.id) }
        let left = change.document.items.first { $0.id == c.id }
        #expect(Set(moved.compactMap(\.groupID)).count == 1 && moved.first?.groupID != group, "moved group members get their own group")
        #expect(left?.groupID == nil, "a lone group member left behind is ungrouped")
        #expect(moved.allSatisfy { $0.zIndex > 40 }, "moved objects land on top of the destination")
        #expect(moved.first { $0.id == a.id }!.zIndex < moved.first { $0.id == b.id }!.zIndex, "moved objects keep their order")
    }

    @Test func movingAMindMapNodeTakesItsSubtreeAlong() throws {
        var root = EaselPagesTestsSupport.item(.sticky, x: 0, y: 0), child = EaselPagesTestsSupport.item(.sticky, x: 300, y: 0), grandchild = EaselPagesTestsSupport.item(.sticky, x: 600, y: 0)
        root.mindMap = EaselMindMapLink()
        child.mindMap = EaselMindMapLink(parent: root.id, side: .right)
        grandchild.mindMap = EaselMindMapLink(parent: child.id, side: .right)
        var top = EaselPagesTestsSupport.arrow(from: root.id, to: child.id), lower = EaselPagesTestsSupport.arrow(from: child.id, to: grandchild.id, x: 400)
        top.mindMap = EaselMindMapLink(parent: root.id)
        lower.mindMap = EaselMindMapLink(parent: child.id)
        let (board, first, second) = EaselPagesTestsSupport.paged([root, child, grandchild, top, lower])
        let change = try #require(EaselPages.movingItems([child.id], to: second, in: board), "move a branch")
        #expect(change.items == [child.id, grandchild.id, lower.id], "a mind map node takes its subtree along")
        #expect(!change.document.items.contains { $0.id == top.id }, "the branch to the parent left behind is cut")
        let moved = change.document.items.first { $0.id == child.id }
        #expect(moved?.mindMap == EaselMindMapLink(), "the moved node becomes its own map")
        #expect(change.document.items.first { $0.id == root.id }?.page == first, "the old root stays")
        let copy = try #require(EaselPages.duplicating(first, in: board), "duplicate a map")
        let copies = EaselPages.items(on: copy.page, in: copy.document)
        let copyIDs = Set(copies.map(\.id))
        #expect(copies.filter { $0.mindMap?.parent != nil }.allSatisfy { copyIDs.contains($0.mindMap!.parent!) },
               "duplicated mind maps point at their own copies")
    }

    @Test func aPageViewMergesBackIntoTheBoard() {
        let a = EaselPagesTestsSupport.item(.sticky, x: 0, y: 0), b = EaselPagesTestsSupport.item(.sticky, x: 200, y: 0)
        var (board, first, second) = EaselPagesTestsSupport.paged([a])
        var onSecond = b
        onSecond.page = second
        board.items.append(onSecond)
        let firstView = EaselPages.view(board, page: first)
        #expect(firstView.items.map(\.id) == [a.id], "the view shows only its page")
        #expect(EaselPages.merging(firstView, page: first, into: board) == board, "an unchanged view merges to the same board")
        var edited = firstView
        edited.items[0].frame.x = 50
        edited.items.append(EaselPagesTestsSupport.item(.rectangle, x: 0, y: 300))
        let merged = EaselPages.merging(edited, page: first, into: board)
        #expect(merged.items.count == 3, "new objects join the board")
        #expect(merged.items.first { $0.id == a.id }?.frame.x == 50, "edits land")
        #expect(merged.items.last?.page == first, "new objects get the page's ID")
        #expect(merged.items.first { $0.id == b.id } == onSecond, "other pages are untouched")
        #expect(merged.items.map(\.id).prefix(2) == [a.id, b.id], "objects keep their places in the file")
        var removed = firstView
        removed.items.removeAll()
        #expect(EaselPages.merging(removed, page: first, into: board).items.map(\.id) == [b.id], "removals only touch the page")
        var pasted = EaselPagesTestsSupport.document([EaselPagesTestsSupport.item(.sticky, x: 0, y: 0)])
        pasted.items[0].page = UUID()
        #expect(EaselPages.merging(pasted, page: nil, into: EaselPagesTestsSupport.document([])).items[0].page == nil, "a plain board drops page IDs")
        #expect(EaselPages.view(board, page: UUID()).items.map(\.id) == [a.id], "an unknown page shows page one")
    }
}
