import Foundation

@main
struct EaselPagesTests {
    nonisolated(unsafe) static var assertions = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        assertions += 1
        if !condition() { fatalError(message) }
    }

    static func main() throws {
        singlePageIsUnchanged()
        try savedFormat()
        validation()
        addPins()
        renameAndDividers()
        reorder()
        duplicate()
        deleteWithContents()
        moveItems()
        moveConnectors()
        moveGroupsAndZOrder()
        mindMaps()
        viewAndMerge()
        print("EaselPagesTests: \(assertions) assertions passed")
    }

    static func item(_ kind: EaselItemKind, x: Double, y: Double, width: Double = 100, height: Double = 80, z: Int = 0) -> EaselItem {
        EaselItem(kind: kind, frame: .init(x: x, y: y, width: width, height: height), zIndex: z)
    }

    static func arrow(from start: UUID?, to end: UUID?, x: Double = 100, y: Double = 40) -> EaselItem {
        var value = EaselItem(kind: .arrow, frame: .init(x: x, y: y, width: 200, height: 1),
                              points: [EaselPoint(x: 0, y: 0), EaselPoint(x: 200, y: 0)])
        value.startConnection = start.map { EaselConnection(itemID: $0) }
        value.endConnection = end.map { EaselConnection(itemID: $0) }
        return value
    }

    static func document(_ items: [EaselItem]) -> EaselDocument {
        EaselDocument(id: UUID(), title: "Board", createdAt: Date(timeIntervalSinceReferenceDate: 0),
                      modifiedAt: Date(timeIntervalSinceReferenceDate: 0), items: items)
    }

    static func paged(_ items: [EaselItem]) -> (document: EaselDocument, first: UUID, second: UUID) {
        guard let change = EaselPages.adding(to: document(items)), let first = change.document.pages?.first?.id,
              let second = change.page else { fatalError("adding a page failed") }
        return (change.document, first, second)
    }

    static func singlePageIsUnchanged() {
        let board = document([item(.sticky, x: 0, y: 0), item(.rectangle, x: 200, y: 0)])
        expect(EaselPages.items(on: nil, in: board) == board.items, "a board without pages shows every object")
        expect(EaselPages.view(board, page: UUID()) == board, "a board without pages has one view")
        expect(EaselPages.resolvedPage(UUID(), in: board) == nil, "a board without pages has no page IDs")
        expect(EaselPages.validationProblem(board) == nil, "a board without pages is valid")
        expect(EaselPages.merging(board, page: nil, into: board) == board, "merging a single page is identity")
        expect(EaselPages.collapsed(board) == board, "collapsing a board without pages changes nothing")
    }

    static func savedFormat() throws {
        let board = document([item(.sticky, x: 0, y: 0)])
        let plain = String(decoding: try JSONEncoder().encode(board), as: UTF8.self)
        expect(!plain.contains("\"pages\"") && !plain.contains("\"page\""), "unused page fields stay out of the file")
        let (paged, first, _) = paged(board.items)
        let data = try JSONEncoder().encode(paged)
        let decoded = try JSONDecoder().decode(EaselDocument.self, from: data)
        expect(decoded == paged, "pages round-trip")
        expect(decoded.items.allSatisfy { $0.page == first }, "objects remember their page")
        var legacy = paged
        legacy.items[0].page = nil
        expect(EaselPages.items(on: first, in: legacy).count == 1, "a missing page means the first page")
        expect(EaselPages.validationProblem(legacy) == nil, "hand-edited files without page IDs stay valid")
    }

    static func validation() {
        let (board, first, _) = paged([item(.sticky, x: 0, y: 0)])
        var duplicate = board
        duplicate.pages?.append(EaselPage(id: first, name: "Again"))
        expect(EaselPages.validationProblem(duplicate) == "duplicate page ID", "page IDs are unique")
        var missing = board
        missing.items[0].page = UUID()
        expect(EaselPages.validationProblem(missing) == "object on a missing page", "objects need a real page")
        var orphan = document([item(.sticky, x: 0, y: 0)])
        orphan.items[0].page = UUID()
        expect(EaselPages.validationProblem(orphan) == "object on a missing page", "a board without pages refuses page IDs")
        var empty = board
        empty.pages = []
        expect(EaselPages.validationProblem(empty) == "page count", "an empty page list is refused")
        var long = board
        long.pages?[0].name = String(repeating: "a", count: EaselPage.maximumNameLength + 1)
        expect(EaselPages.validationProblem(long) == "page name", "page names have a length limit")
        var blank = board
        blank.pages?[0].name = "   "
        expect(EaselPages.validationProblem(blank) == "page name", "blank page names are refused")
        var lines = board
        lines.pages?[0].name = "one\ntwo"
        expect(EaselPages.validationProblem(lines) == "page name", "page names stay on one line")
        var many = document([])
        many.pages = (0...EaselPage.maximumCount).map { EaselPage(id: UUID(), name: "P\($0)") }
        expect(EaselPages.validationProblem(many) == "page count", "page count has a limit")
        var dividers = document([])
        dividers.pages = [EaselPage(id: UUID(), name: "-"), EaselPage(id: UUID(), name: "-")]
        expect(EaselPages.validationProblem(dividers) == "every page is a divider", "a board keeps one real page")
        expect(EaselPages.cleanName("  Ideas\nand plans  ") == "Ideas and plans", "names flatten to one line")
        expect(EaselPages.cleanName(" \n ") == nil, "blank names are refused")
        expect(EaselPages.cleanName(String(repeating: "b", count: 300))?.count == EaselPage.maximumNameLength, "long names are trimmed")
        expect(EaselPages.cleanName("👨‍👩‍👧 Team") == "👨‍👩‍👧 Team", "emoji sequences survive cleaning")
    }

    static func addPins() {
        let a = item(.sticky, x: 0, y: 0), b = item(.rectangle, x: 200, y: 0)
        guard let change = EaselPages.adding(to: document([a, b])), let pages = change.document.pages else {
            return expect(false, "adding a page works")
        }
        expect(pages.map(\.name) == ["Page 1", "Page 2"], "the second page gets the next name")
        expect(change.page == pages[1].id, "adding a page switches to it")
        expect(change.document.items.allSatisfy { $0.page == pages[0].id }, "existing objects pin to page one")
        expect(EaselPages.items(on: change.page, in: change.document).isEmpty, "the new page starts empty")
        guard let third = EaselPages.adding(to: change.document, after: pages[0].id) else { return expect(false, "adding after a page works") }
        expect(third.document.pages?.map(\.name) == ["Page 1", "Page 3", "Page 2"], "pages insert after the chosen page")
        guard let named = EaselPages.adding(to: change.document, name: "  Ideas ") else { return expect(false, "named page") }
        expect(named.document.pages?.last?.name == "Ideas", "a typed name is cleaned")
        expect(EaselPages.adding(to: change.document, name: "  ") == nil, "a blank name is refused")
        var full = document([])
        full.pages = (0..<EaselPage.maximumCount).map { EaselPage(id: UUID(), name: "P\($0)") }
        expect(EaselPages.adding(to: full) == nil, "adding stops at the page limit")
        var taken = change.document
        taken.pages?[1].name = "Page 3"
        expect(EaselPages.nextName(in: taken) == "Page 4", "new names skip names already in use")
    }

    static func renameAndDividers() {
        let (board, first, second) = paged([item(.sticky, x: 0, y: 0)])
        guard let renamed = EaselPages.renaming(second, to: "Ideas", in: board) else { return expect(false, "rename works") }
        expect(renamed.pages?[1].name == "Ideas", "rename changes the name")
        expect(EaselPages.renaming(second, to: "Ideas", in: renamed) == nil, "renaming to the same name is no change")
        expect(EaselPages.renaming(second, to: "", in: renamed) == nil, "a blank rename is refused")
        expect(EaselPages.renaming(first, to: "-", in: board) == nil, "a page with objects can't become a divider")
        guard let divider = EaselPages.renaming(second, to: "-", in: board) else { return expect(false, "an empty page becomes a divider") }
        expect(EaselPages.isDivider(divider.pages![1], in: divider), "a page named - is a divider")
        expect(EaselPages.contentPages(divider).map(\.id) == [first], "dividers aren't pages you visit")
        expect(EaselPages.resolvedPage(second, in: divider) == first, "a divider resolves to a real page")
        guard let added = EaselPages.addingDivider(to: board, after: first) else { return expect(false, "dividers can be added") }
        expect(added.document.pages?.map(\.name) == ["Page 1", "-", "Page 2"], "a divider lands after the page")
        expect(added.page == first, "adding a divider keeps the current page")
        var lone = document([])
        lone.pages = [EaselPage(id: UUID(), name: "Solo"), EaselPage(id: UUID(), name: "-")]
        expect(EaselPages.renaming(lone.pages![0].id, to: "-", in: lone) == nil, "the last real page can't become a divider")
    }

    static func reorder() {
        let a = item(.sticky, x: 0, y: 0)
        var board = paged([a]).document
        board.items[0].page = nil
        let ids = board.pages!.map(\.id)
        guard let moved = EaselPages.moving(ids[0], to: 1, in: board) else { return expect(false, "reorder works") }
        expect(moved.pages?.map(\.id) == [ids[1], ids[0]], "the page moves")
        expect(EaselPages.items(on: ids[0], in: moved).count == 1, "objects stay with their page when it moves")
        expect(EaselPages.items(on: ids[1], in: moved).isEmpty, "the page that becomes first doesn't pick up objects")
        expect(EaselPages.moving(ids[0], to: 0, in: board) == nil, "moving to the same place is no change")
        expect(EaselPages.moving(UUID(), to: 0, in: board) == nil, "unknown pages don't move")
        guard let order = EaselPages.reordered(board, order: [ids[1], ids[0]]) else { return expect(false, "reorder by list") }
        expect(order.pages?.map(\.id) == [ids[1], ids[0]], "reordered applies the new order")
        expect(EaselPages.reordered(board, order: [ids[1]]) == nil, "a partial order is refused")
        expect(EaselPages.reordered(board, order: [ids[1], ids[1]]) == nil, "a repeated order is refused")
    }

    static func duplicate() {
        let sticky = item(.sticky, x: 0, y: 0, z: 1), shape = item(.rectangle, x: 300, y: 0, z: 2)
        var stamp = item(.stamp, x: 10, y: 10, width: 32, height: 32, z: 3)
        stamp.stamp = "heart"
        stamp.attachedTo = sticky.id
        let link = arrow(from: sticky.id, to: shape.id)
        var section = item(.section, x: -50, y: -50, width: 600, height: 300, z: 0)
        section.text = "Plan"
        var grouped = [sticky, shape]
        let group = UUID()
        for index in grouped.indices { grouped[index].groupID = group }
        let board = document(grouped + [stamp, link, section])
        guard let change = EaselPages.duplicating(nil, in: board), let pages = change.document.pages,
              let copyPage = change.page else { return expect(false, "duplicate works") }
        expect(pages.map(\.name) == ["Page 1", "Page 1 copy"], "the copy is named after the original")
        expect(copyPage == pages[1].id, "duplicate switches to the copy")
        let originals = EaselPages.items(on: pages[0].id, in: change.document)
        let copies = EaselPages.items(on: copyPage, in: change.document)
        expect(originals.count == 5 && copies.count == 5, "every object is copied")
        expect(Set(copies.map(\.id)).isDisjoint(with: Set(originals.map(\.id))), "copies get fresh IDs")
        expect(change.items == Set(copies.map(\.id)), "the change reports the copies")
        let copyIDs = Set(copies.map(\.id))
        guard let copiedArrow = copies.first(where: { $0.kind == .arrow }),
              let copiedStamp = copies.first(where: { $0.kind == .stamp }) else { return expect(false, "copies keep kinds") }
        expect(copiedArrow.startConnection.map { copyIDs.contains($0.itemID) } == true
               && copiedArrow.endConnection.map { copyIDs.contains($0.itemID) } == true, "connectors point inside the copy")
        expect(copiedStamp.attachedTo.map(copyIDs.contains) == true, "attachments point inside the copy")
        let copiedGroups = Set(copies.compactMap(\.groupID))
        expect(copiedGroups.count == 1 && !copiedGroups.contains(group), "groups get a fresh ID in the copy")
        expect(copies.map(\.zIndex).sorted() == originals.map(\.zIndex).sorted(), "the copy keeps the layer order")
        let copiedSection = copies.first { $0.kind == .section }
        expect(copiedSection.map { EaselBoardObjects.contents(of: $0, in: copies).count } == 4, "the section still holds its contents")
        expect(EaselPages.validationProblem(change.document) == nil, "the duplicate is valid")
        guard let again = EaselPages.duplicating(pages[0].id, in: change.document) else { return expect(false, "duplicate twice") }
        expect(again.document.pages?.map(\.name) == ["Page 1", "Page 1 copy 2", "Page 1 copy"], "repeat copies get a number")
    }

    static func deleteWithContents() {
        let keep = item(.sticky, x: 0, y: 0)
        let (board, first, second) = paged([keep])
        guard let add = EaselPages.adding(to: board, name: "Third") else { return expect(false, "third page") }
        var document = add.document
        let third = add.page!
        var doomed = item(.rectangle, x: 0, y: 0)
        doomed.page = second
        var cross = arrow(from: keep.id, to: doomed.id)
        cross.page = first
        var stuck = item(.stamp, x: 0, y: 0, width: 32, height: 32)
        stuck.stamp = "dot"
        stuck.attachedTo = doomed.id
        stuck.page = first
        document.items += [doomed, cross, stuck]
        guard let change = EaselPages.deleting(second, in: document) else { return expect(false, "delete works") }
        expect(change.document.pages?.map(\.id) == [first, third], "the page is gone")
        expect(!change.document.items.contains { $0.id == doomed.id }, "its objects go with it")
        expect(change.items == [doomed.id], "the change reports what was removed")
        expect(change.page == third, "the next page is shown")
        let freed = change.document.items.first { $0.id == cross.id }
        expect(freed?.endConnection == nil && freed?.startConnection != nil, "connectors elsewhere let go of removed objects")
        expect(change.document.items.first { $0.id == stuck.id }?.attachedTo == nil, "attachments elsewhere let go too")
        expect(EaselPages.validationProblem(change.document) == nil, "the result is valid")
        guard let last = EaselPages.deleting(third, in: change.document) else { return expect(false, "delete the last extra page") }
        expect(last.document.pages == nil && last.document.items.allSatisfy { $0.page == nil }, "a lone Page 1 folds back into a plain board")
        expect(last.page == nil, "a plain board has no page to show")
        expect(EaselPages.deleting(first, in: board.pages!.count == 2 ? EaselPages.deleting(second, in: board)!.document : board) == nil,
               "the only page can't be deleted")
        guard let renamed = EaselPages.renaming(first, to: "Ideas", in: board), let kept = EaselPages.deleting(second, in: renamed) else {
            return expect(false, "renamed boards keep their page")
        }
        expect(kept.document.pages?.map(\.name) == ["Ideas"], "a renamed last page stays")
        guard let withDivider = EaselPages.addingDivider(to: board, after: first),
              let dividerID = withDivider.document.pages?[1].id,
              let noDivider = EaselPages.deleting(dividerID, in: withDivider.document) else { return expect(false, "delete a divider") }
        expect(noDivider.document.pages?.count == 2, "dividers delete")
        var lone = document
        lone.pages = [EaselPage(id: first, name: "Page 1"), EaselPage(id: second, name: "-")]
        lone.items = [keep]
        expect(EaselPages.deleting(first, in: lone) == nil, "the last real page stays when only dividers remain")
    }

    static func moveItems() {
        let sticky = item(.sticky, x: 40, y: 60), other = item(.rectangle, x: 400, y: 0)
        var stamp = item(.stamp, x: 50, y: 70, width: 32, height: 32)
        stamp.stamp = "star"
        stamp.attachedTo = sticky.id
        var section = item(.section, x: 600, y: 0, width: 400, height: 400)
        section.text = "Box"
        let inside = item(.sticky, x: 650, y: 50)
        let (board, first, second) = paged([sticky, other, stamp, section, inside])
        guard let change = EaselPages.movingItems([sticky.id], to: second, in: board) else { return expect(false, "move works") }
        expect(change.items == [sticky.id, stamp.id], "attached objects follow")
        expect(change.page == second, "the change names the destination")
        let moved = EaselPages.items(on: second, in: change.document)
        expect(Set(moved.map(\.id)) == [sticky.id, stamp.id], "objects land on the destination page")
        expect(moved.first { $0.id == sticky.id }?.frame == sticky.frame, "objects land in the same area")
        expect(EaselPages.items(on: first, in: change.document).count == 3, "the rest stay")
        guard let boxed = EaselPages.movingItems([section.id], to: second, in: board) else { return expect(false, "move a section") }
        expect(boxed.items == [section.id, inside.id], "a section carries its contents")
        expect(EaselPages.movingItems([sticky.id], to: first, in: board) == nil, "moving to the same page is no change")
        expect(EaselPages.movingItems([sticky.id], to: UUID(), in: board) == nil, "moving to a missing page is refused")
        guard let divided = EaselPages.addingDivider(to: board, after: first), let divider = divided.document.pages?[1].id else {
            return expect(false, "divider")
        }
        expect(EaselPages.movingItems([sticky.id], to: divider, in: divided.document) == nil, "nothing moves onto a divider")
        expect(EaselPages.validationProblem(change.document) == nil, "the move is valid")
    }

    static func moveConnectors() {
        let a = item(.rectangle, x: 0, y: 0), b = item(.rectangle, x: 300, y: 0), c = item(.rectangle, x: 600, y: 0)
        let ab = arrow(from: a.id, to: b.id), bc = arrow(from: b.id, to: c.id, x: 400)
        let free = arrow(from: nil, to: nil, x: 0, y: 300)
        let (board, first, second) = paged([a, b, c, ab, bc, free])
        guard let change = EaselPages.movingItems([a.id, b.id], to: second, in: board) else { return expect(false, "move connected") }
        expect(change.items == [a.id, b.id, ab.id], "a connector goes along when both ends move")
        let left = change.document.items.first { $0.id == bc.id }
        expect(left?.page == first, "a half-moved connector stays on its page")
        expect(left?.startConnection == nil && left?.endConnection?.itemID == c.id, "its moved end lets go")
        expect(left?.frame.x == bc.frame.x && left?.points == bc.points, "the freed end stays where it was")
        let carried = change.document.items.first { $0.id == ab.id }
        expect(carried?.startConnection?.itemID == a.id && carried?.endConnection?.itemID == b.id, "a carried connector stays connected")
        guard let lone = EaselPages.movingItems([bc.id], to: second, in: board) else { return expect(false, "move a connector alone") }
        let alone = lone.document.items.first { $0.id == bc.id }
        expect(alone?.page == second && alone?.startConnection == nil && alone?.endConnection == nil, "a selected connector moves free")
        guard let freeMove = EaselPages.movingItems([free.id], to: second, in: board) else { return expect(false, "free arrow") }
        expect(freeMove.items == [free.id], "free arrows move by themselves")
    }

    static func moveGroupsAndZOrder() {
        var a = item(.sticky, x: 0, y: 0, z: 5), b = item(.sticky, x: 200, y: 0, z: 6), c = item(.sticky, x: 400, y: 0, z: 7)
        let group = UUID()
        a.groupID = group; b.groupID = group; c.groupID = group
        let (board, _, second) = paged([a, b, c])
        guard let withTarget = EaselPages.adding(to: board) else { return expect(false, "page") }
        var document = withTarget.document
        var resident = item(.rectangle, x: 0, y: 0, z: 40)
        resident.page = second
        document.items.append(resident)
        guard let change = EaselPages.movingItems([a.id, b.id], to: second, in: document) else { return expect(false, "group move") }
        let moved = change.document.items.filter { [a.id, b.id].contains($0.id) }
        let left = change.document.items.first { $0.id == c.id }
        expect(Set(moved.compactMap(\.groupID)).count == 1 && moved.first?.groupID != group, "moved group members get their own group")
        expect(left?.groupID == nil, "a lone group member left behind is ungrouped")
        expect(moved.allSatisfy { $0.zIndex > 40 }, "moved objects land on top of the destination")
        expect(moved.first { $0.id == a.id }!.zIndex < moved.first { $0.id == b.id }!.zIndex, "moved objects keep their order")
    }

    static func mindMaps() {
        var root = item(.sticky, x: 0, y: 0), child = item(.sticky, x: 300, y: 0), grandchild = item(.sticky, x: 600, y: 0)
        root.mindMap = EaselMindMapLink()
        child.mindMap = EaselMindMapLink(parent: root.id, side: .right)
        grandchild.mindMap = EaselMindMapLink(parent: child.id, side: .right)
        var top = arrow(from: root.id, to: child.id), lower = arrow(from: child.id, to: grandchild.id, x: 400)
        top.mindMap = EaselMindMapLink(parent: root.id)
        lower.mindMap = EaselMindMapLink(parent: child.id)
        let (board, first, second) = paged([root, child, grandchild, top, lower])
        guard let change = EaselPages.movingItems([child.id], to: second, in: board) else { return expect(false, "move a branch") }
        expect(change.items == [child.id, grandchild.id, lower.id], "a mind map node takes its subtree along")
        expect(!change.document.items.contains { $0.id == top.id }, "the branch to the parent left behind is cut")
        let moved = change.document.items.first { $0.id == child.id }
        expect(moved?.mindMap == EaselMindMapLink(), "the moved node becomes its own map")
        expect(change.document.items.first { $0.id == root.id }?.page == first, "the old root stays")
        guard let copy = EaselPages.duplicating(first, in: board) else { return expect(false, "duplicate a map") }
        let copies = EaselPages.items(on: copy.page, in: copy.document)
        let copyIDs = Set(copies.map(\.id))
        expect(copies.filter { $0.mindMap?.parent != nil }.allSatisfy { copyIDs.contains($0.mindMap!.parent!) },
               "duplicated mind maps point at their own copies")
    }

    static func viewAndMerge() {
        let a = item(.sticky, x: 0, y: 0), b = item(.sticky, x: 200, y: 0)
        var (board, first, second) = paged([a])
        var onSecond = b
        onSecond.page = second
        board.items.append(onSecond)
        let firstView = EaselPages.view(board, page: first)
        expect(firstView.items.map(\.id) == [a.id], "the view shows only its page")
        expect(EaselPages.merging(firstView, page: first, into: board) == board, "an unchanged view merges to the same board")
        var edited = firstView
        edited.items[0].frame.x = 50
        edited.items.append(item(.rectangle, x: 0, y: 300))
        let merged = EaselPages.merging(edited, page: first, into: board)
        expect(merged.items.count == 3, "new objects join the board")
        expect(merged.items.first { $0.id == a.id }?.frame.x == 50, "edits land")
        expect(merged.items.last?.page == first, "new objects get the page's ID")
        expect(merged.items.first { $0.id == b.id } == onSecond, "other pages are untouched")
        expect(merged.items.map(\.id).prefix(2) == [a.id, b.id], "objects keep their places in the file")
        var removed = firstView
        removed.items.removeAll()
        expect(EaselPages.merging(removed, page: first, into: board).items.map(\.id) == [b.id], "removals only touch the page")
        var pasted = document([item(.sticky, x: 0, y: 0)])
        pasted.items[0].page = UUID()
        expect(EaselPages.merging(pasted, page: nil, into: document([])).items[0].page == nil, "a plain board drops page IDs")
        expect(EaselPages.view(board, page: UUID()).items.map(\.id) == [a.id], "an unknown page shows page one")
    }
}
