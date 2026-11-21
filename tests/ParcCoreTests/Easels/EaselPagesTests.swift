import Foundation
import Testing
@testable import ParcCore

struct EaselPagesTests {
    func item(_ kind: EaselItemKind, x: Double, y: Double, width: Double = 100, height: Double = 80, z: Int = 0) -> EaselItem {
        EaselItem(kind: kind, frame: .init(x: x, y: y, width: width, height: height), zIndex: z)
    }

    func arrow(from start: UUID?, to end: UUID?, x: Double = 100, y: Double = 40) -> EaselItem {
        var value = EaselItem(kind: .arrow, frame: .init(x: x, y: y, width: 200, height: 1),
                              points: [EaselPoint(x: 0, y: 0), EaselPoint(x: 200, y: 0)])
        value.startConnection = start.map { EaselConnection(itemID: $0) }
        value.endConnection = end.map { EaselConnection(itemID: $0) }
        return value
    }

    func document(_ items: [EaselItem]) -> EaselDocument {
        EaselDocument(id: UUID(), title: "Board", createdAt: Date(timeIntervalSinceReferenceDate: 0),
                      modifiedAt: Date(timeIntervalSinceReferenceDate: 0), items: items)
    }

    func paged(_ items: [EaselItem]) -> (document: EaselDocument, first: UUID, second: UUID) {
        guard let change = EaselPages.adding(to: document(items)), let first = change.document.pages?.first?.id,
              let second = change.page else {
            Issue.record("adding a page failed")
            return (document(items), UUID(), UUID())
        }
        return (change.document, first, second)
    }

    @Test func aBoardWithoutPagesIsUnchanged() {
        let board = document([item(.sticky, x: 0, y: 0), item(.rectangle, x: 200, y: 0)])
        #expect(EaselPages.items(on: nil, in: board) == board.items, "a board without pages shows every object")
        #expect(EaselPages.view(board, page: UUID()) == board, "a board without pages has one view")
        #expect(EaselPages.resolvedPage(UUID(), in: board) == nil, "a board without pages has no page IDs")
        #expect(EaselPages.validationProblem(board) == nil, "a board without pages is valid")
        #expect(EaselPages.merging(board, page: nil, into: board) == board, "merging a single page is identity")
        #expect(EaselPages.collapsed(board) == board, "collapsing a board without pages changes nothing")
    }

    @Test func anUnpagedBoardOmitsUnusedFields() throws {
        let board = document([item(.sticky, x: 0, y: 0)])
        let plain = String(decoding: try JSONEncoder().encode(board), as: UTF8.self)
        #expect(!plain.contains("\"pages\"") && !plain.contains("\"page\""))
    }

    @Test func pagesRoundTripWithTheirObjects() throws {
        let (board, first, _) = paged([item(.sticky, x: 0, y: 0)])
        let decoded = try JSONDecoder().decode(EaselDocument.self, from: JSONEncoder().encode(board))
        #expect(decoded == board)
        #expect(decoded.items.first?.page == first)
    }

    @Test func aMissingObjectPageDefaultsToPageOne() {
        let (original, first, _) = paged([item(.sticky, x: 0, y: 0)])
        var board = original
        board.items[0].page = nil
        #expect(EaselPages.items(on: first, in: board) == board.items)
        #expect(EaselPages.validationProblem(board) == nil)
    }

    enum InvalidPages: CaseIterable {
        case duplicateID, missingPage, noPages, emptyPages, longName, blankName, multilineName, tooManyPages, onlyDividers
    }

    @Test(arguments: InvalidPages.allCases)
    func pageValidationRefusesInvalidRecords(_ invalid: InvalidPages) {
        let (original, first, _) = paged([item(.sticky, x: 0, y: 0)])
        var board = original
        let reason: String
        switch invalid {
        case .duplicateID:
            board.pages?.append(EaselPage(id: first, name: "Again"))
            reason = "duplicate page ID"
        case .missingPage:
            board.items[0].page = UUID()
            reason = "object on a missing page"
        case .noPages:
            board.pages = nil
            reason = "object on a missing page"
        case .emptyPages:
            board.pages = []
            reason = "page count"
        case .longName:
            board.pages?[0].name = String(repeating: "a", count: EaselPage.maximumNameLength + 1)
            reason = "page name"
        case .blankName:
            board.pages?[0].name = "   "
            reason = "page name"
        case .multilineName:
            board.pages?[0].name = "one\ntwo"
            reason = "page name"
        case .tooManyPages:
            board.items = []
            board.pages = (0...EaselPage.maximumCount).map { EaselPage(id: UUID(), name: "P\($0)") }
            reason = "page count"
        case .onlyDividers:
            board.items = []
            board.pages = [EaselPage(id: UUID(), name: "-"), EaselPage(id: UUID(), name: "-")]
            reason = "every page is a divider"
        }
        #expect(EaselPages.validationProblem(board) == reason)
    }

    @Test(arguments: [("  Ideas\nand plans  ", Optional("Ideas and plans")),
                      (" \n ", nil), ("👨‍👩‍👧 Team", "👨‍👩‍👧 Team")])
    func pageNamesTrimAndFlattenWithoutChangingEmoji(_ name: String, _ expected: String?) {
        #expect(EaselPages.cleanName(name) == expected)
    }

    @Test func pageNamesTrimToTheirLengthLimit() {
        #expect(EaselPages.cleanName(String(repeating: "b", count: 300))?.count == EaselPage.maximumNameLength)
    }

    @Test func addingAPagePinsExistingObjectsToPageOne() throws {
        let a = item(.sticky, x: 0, y: 0), b = item(.rectangle, x: 200, y: 0)
        guard let change = EaselPages.adding(to: document([a, b])), let pages = change.document.pages else {
            Issue.record("adding a page works"); return
        }
        #expect(pages.map(\.name) == ["Page 1", "Page 2"], "the second page gets the next name")
        #expect(change.page == pages[1].id, "adding a page switches to it")
        #expect(change.document.items.allSatisfy { $0.page == pages[0].id }, "existing objects pin to page one")
        #expect(EaselPages.items(on: change.page, in: change.document).isEmpty, "the new page starts empty")
        let third = try #require(EaselPages.adding(to: change.document, after: pages[0].id), "adding after a page works")
        #expect(third.document.pages?.map(\.name) == ["Page 1", "Page 3", "Page 2"], "pages insert after the chosen page")
        let named = try #require(EaselPages.adding(to: change.document, name: "  Ideas "), "named page")
        #expect(named.document.pages?.last?.name == "Ideas", "a typed name is cleaned")
        #expect(EaselPages.adding(to: change.document, name: "  ") == nil, "a blank name is refused")
        var full = document([])
        full.pages = (0..<EaselPage.maximumCount).map { EaselPage(id: UUID(), name: "P\($0)") }
        #expect(EaselPages.adding(to: full) == nil, "adding stops at the page limit")
        var taken = change.document
        taken.pages?[1].name = "Page 3"
        #expect(EaselPages.nextName(in: taken) == "Page 4", "new names skip names already in use")
    }

    @Test func renamingPagesAndMakingDividers() throws {
        let (board, first, second) = paged([item(.sticky, x: 0, y: 0)])
        let renamed = try #require(EaselPages.renaming(second, to: "Ideas", in: board), "rename works")
        #expect(renamed.pages?[1].name == "Ideas", "rename changes the name")
        #expect(EaselPages.renaming(second, to: "Ideas", in: renamed) == nil, "renaming to the same name is no change")
        #expect(EaselPages.renaming(second, to: "", in: renamed) == nil, "a blank rename is refused")
        #expect(EaselPages.renaming(first, to: "-", in: board) == nil, "a page with objects can't become a divider")
        let divider = try #require(EaselPages.renaming(second, to: "-", in: board), "an empty page becomes a divider")
        #expect(EaselPages.isDivider(divider.pages![1], in: divider), "a page named - is a divider")
        #expect(EaselPages.contentPages(divider).map(\.id) == [first], "dividers aren't pages you visit")
        #expect(EaselPages.resolvedPage(second, in: divider) == first, "a divider resolves to a real page")
        let added = try #require(EaselPages.addingDivider(to: board, after: first), "dividers can be added")
        #expect(added.document.pages?.map(\.name) == ["Page 1", "-", "Page 2"], "a divider lands after the page")
        #expect(added.page == first, "adding a divider keeps the current page")
        var lone = document([])
        lone.pages = [EaselPage(id: UUID(), name: "Solo"), EaselPage(id: UUID(), name: "-")]
        #expect(EaselPages.renaming(lone.pages![0].id, to: "-", in: lone) == nil, "the last real page can't become a divider")
    }

    @Test func reorderingPagesKeepsObjectsWithTheirPage() throws {
        let a = item(.sticky, x: 0, y: 0)
        var board = paged([a]).document
        board.items[0].page = nil
        let ids = board.pages!.map(\.id)
        let moved = try #require(EaselPages.moving(ids[0], to: 1, in: board), "reorder works")
        #expect(moved.pages?.map(\.id) == [ids[1], ids[0]], "the page moves")
        #expect(EaselPages.items(on: ids[0], in: moved).count == 1, "objects stay with their page when it moves")
        #expect(EaselPages.items(on: ids[1], in: moved).isEmpty, "the page that becomes first doesn't pick up objects")
        #expect(EaselPages.moving(ids[0], to: 0, in: board) == nil, "moving to the same place is no change")
        #expect(EaselPages.moving(UUID(), to: 0, in: board) == nil, "unknown pages don't move")
        let order = try #require(EaselPages.reordered(board, order: [ids[1], ids[0]]), "reorder by list")
        #expect(order.pages?.map(\.id) == [ids[1], ids[0]], "reordered applies the new order")
        #expect(EaselPages.reordered(board, order: [ids[1]]) == nil, "a partial order is refused")
        #expect(EaselPages.reordered(board, order: [ids[1], ids[1]]) == nil, "a repeated order is refused")
    }

    @Test func duplicatingAPageCopiesItsObjectsWithFreshIDs() throws {
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
        let again = try #require(EaselPages.duplicating(pages[0].id, in: change.document), "duplicate twice")
        #expect(again.document.pages?.map(\.name) == ["Page 1", "Page 1 copy 2", "Page 1 copy"], "repeat copies get a number")
    }

    @Test func deletingAPageRemovesItsObjects() throws {
        let keep = item(.sticky, x: 0, y: 0)
        let (board, first, second) = paged([keep])
        let add = try #require(EaselPages.adding(to: board, name: "Third"), "third page")
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
        let change = try #require(EaselPages.deleting(second, in: document), "delete works")
        #expect(change.document.pages?.map(\.id) == [first, third], "the page is gone")
        #expect(!change.document.items.contains { $0.id == doomed.id }, "its objects go with it")
        #expect(change.items == [doomed.id], "the change reports what was removed")
        #expect(change.page == third, "the next page is shown")
        let freed = change.document.items.first { $0.id == cross.id }
        #expect(freed?.endConnection == nil && freed?.startConnection != nil, "connectors elsewhere let go of removed objects")
        #expect(change.document.items.first { $0.id == stuck.id }?.attachedTo == nil, "attachments elsewhere let go too")
        #expect(EaselPages.validationProblem(change.document) == nil, "the result is valid")
        let last = try #require(EaselPages.deleting(third, in: change.document), "delete the last extra page")
        #expect(last.document.pages == nil && last.document.items.allSatisfy { $0.page == nil }, "a lone Page 1 folds back into a plain board")
        #expect(last.page == nil, "a plain board has no page to show")
        #expect(EaselPages.deleting(first, in: board.pages!.count == 2 ? EaselPages.deleting(second, in: board)!.document : board) == nil,
               "the only page can't be deleted")
        guard let renamed = EaselPages.renaming(first, to: "Ideas", in: board), let kept = EaselPages.deleting(second, in: renamed) else {
            Issue.record("renamed boards keep their page"); return
        }
        #expect(kept.document.pages?.map(\.name) == ["Ideas"], "a renamed last page stays")
        guard let withDivider = EaselPages.addingDivider(to: board, after: first),
              let dividerID = withDivider.document.pages?[1].id,
              let noDivider = EaselPages.deleting(dividerID, in: withDivider.document) else { Issue.record("delete a divider"); return }
        #expect(noDivider.document.pages?.count == 2, "dividers delete")
        var lone = document
        lone.pages = [EaselPage(id: first, name: "Page 1"), EaselPage(id: second, name: "-")]
        lone.items = [keep]
        #expect(EaselPages.deleting(first, in: lone) == nil, "the last real page stays when only dividers remain")
    }

    @Test func movingObjectsToAnotherPage() throws {
        let sticky = item(.sticky, x: 40, y: 60), other = item(.rectangle, x: 400, y: 0)
        var stamp = item(.stamp, x: 50, y: 70, width: 32, height: 32)
        stamp.stamp = "star"
        stamp.attachedTo = sticky.id
        var section = item(.section, x: 600, y: 0, width: 400, height: 400)
        section.text = "Box"
        let inside = item(.sticky, x: 650, y: 50)
        let (board, first, second) = paged([sticky, other, stamp, section, inside])
        let change = try #require(EaselPages.movingItems([sticky.id], to: second, in: board), "move works")
        #expect(change.items == [sticky.id, stamp.id], "attached objects follow")
        #expect(change.page == second, "the change names the destination")
        let moved = EaselPages.items(on: second, in: change.document)
        #expect(Set(moved.map(\.id)) == [sticky.id, stamp.id], "objects land on the destination page")
        #expect(moved.first { $0.id == sticky.id }?.frame == sticky.frame, "objects land in the same area")
        #expect(EaselPages.items(on: first, in: change.document).count == 3, "the rest stay")
        let boxed = try #require(EaselPages.movingItems([section.id], to: second, in: board), "move a section")
        #expect(boxed.items == [section.id, inside.id], "a section carries its contents")
        #expect(EaselPages.movingItems([sticky.id], to: first, in: board) == nil, "moving to the same page is no change")
        #expect(EaselPages.movingItems([sticky.id], to: UUID(), in: board) == nil, "moving to a missing page is refused")
        guard let divided = EaselPages.addingDivider(to: board, after: first), let divider = divided.document.pages?[1].id else {
            Issue.record("divider"); return
        }
        #expect(EaselPages.movingItems([sticky.id], to: divider, in: divided.document) == nil, "nothing moves onto a divider")
        #expect(EaselPages.validationProblem(change.document) == nil, "the move is valid")
    }

    @Test func connectorsFollowOrLetGoWhenObjectsMovePages() throws {
        let a = item(.rectangle, x: 0, y: 0), b = item(.rectangle, x: 300, y: 0), c = item(.rectangle, x: 600, y: 0)
        let ab = arrow(from: a.id, to: b.id), bc = arrow(from: b.id, to: c.id, x: 400)
        let free = arrow(from: nil, to: nil, x: 0, y: 300)
        let (board, first, second) = paged([a, b, c, ab, bc, free])
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
        var a = item(.sticky, x: 0, y: 0, z: 5), b = item(.sticky, x: 200, y: 0, z: 6), c = item(.sticky, x: 400, y: 0, z: 7)
        let group = UUID()
        a.groupID = group; b.groupID = group; c.groupID = group
        let (board, _, second) = paged([a, b, c])
        let withTarget = try #require(EaselPages.adding(to: board), "page")
        var document = withTarget.document
        var resident = item(.rectangle, x: 0, y: 0, z: 40)
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
        var root = item(.sticky, x: 0, y: 0), child = item(.sticky, x: 300, y: 0), grandchild = item(.sticky, x: 600, y: 0)
        root.mindMap = EaselMindMapLink()
        child.mindMap = EaselMindMapLink(parent: root.id, side: .right)
        grandchild.mindMap = EaselMindMapLink(parent: child.id, side: .right)
        var top = arrow(from: root.id, to: child.id), lower = arrow(from: child.id, to: grandchild.id, x: 400)
        top.mindMap = EaselMindMapLink(parent: root.id)
        lower.mindMap = EaselMindMapLink(parent: child.id)
        let (board, first, second) = paged([root, child, grandchild, top, lower])
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
        let a = item(.sticky, x: 0, y: 0), b = item(.sticky, x: 200, y: 0)
        var (board, first, second) = paged([a])
        var onSecond = b
        onSecond.page = second
        board.items.append(onSecond)
        let firstView = EaselPages.view(board, page: first)
        #expect(firstView.items.map(\.id) == [a.id], "the view shows only its page")
        #expect(EaselPages.merging(firstView, page: first, into: board) == board, "an unchanged view merges to the same board")
        var edited = firstView
        edited.items[0].frame.x = 50
        edited.items.append(item(.rectangle, x: 0, y: 300))
        let merged = EaselPages.merging(edited, page: first, into: board)
        #expect(merged.items.count == 3, "new objects join the board")
        #expect(merged.items.first { $0.id == a.id }?.frame.x == 50, "edits land")
        #expect(merged.items.last?.page == first, "new objects get the page's ID")
        #expect(merged.items.first { $0.id == b.id } == onSecond, "other pages are untouched")
        #expect(merged.items.map(\.id).prefix(2) == [a.id, b.id], "objects keep their places in the file")
        var removed = firstView
        removed.items.removeAll()
        #expect(EaselPages.merging(removed, page: first, into: board).items.map(\.id) == [b.id], "removals only touch the page")
        var pasted = document([item(.sticky, x: 0, y: 0)])
        pasted.items[0].page = UUID()
        #expect(EaselPages.merging(pasted, page: nil, into: document([])).items[0].page == nil, "a plain board drops page IDs")
        #expect(EaselPages.view(board, page: UUID()).items.map(\.id) == [a.id], "an unknown page shows page one")
    }

    @Test func undoShowsThePageTheChangeBelongedTo() throws {
        let a = item(.sticky, x: 0, y: 0)
        var (board, first, second) = paged([a])
        var b = item(.sticky, x: 0, y: 0)
        b.page = second
        board.items.append(b)
        var edited = board
        edited.items[0].frame.x = 90
        #expect(EaselPages.followedPage(from: edited, to: board, showing: second) == first, "undoing an edit on another page shows that page")
        #expect(EaselPages.followedPage(from: edited, to: board, showing: first) == first, "an edit on the shown page keeps the page")
        let deleted = try #require(EaselPages.deleting(second, in: board)?.document, "delete")
        #expect(EaselPages.followedPage(from: deleted, to: board, showing: first) == second, "undoing a delete shows the page again")
        #expect(EaselPages.followedPage(from: board, to: deleted, showing: second) == nil, "a board folded back to one page has no page ID")
        guard let named = EaselPages.renaming(first, to: "Ideas", in: board), let kept = EaselPages.deleting(second, in: named)?.document else {
            Issue.record("renamed delete"); return
        }
        #expect(EaselPages.followedPage(from: named, to: kept, showing: second) == first, "a removed page falls back to a real one")
        let renamed = try #require(EaselPages.renaming(second, to: "Ideas", in: board), "rename")
        #expect(EaselPages.followedPage(from: renamed, to: board, showing: first) == first, "a rename keeps the page")
    }

    @Test func findAndExportWalkEveryPage() throws {
        var section = item(.section, x: 0, y: 0, width: 500, height: 500)
        section.contentsHidden = true
        var note = item(.sticky, x: 50, y: 50)
        note.text = "needle"
        var (board, _, second) = paged([section])
        note.page = second
        board.items.append(note)
        #expect(EaselFinder.matches(of: "needle", in: board).map(\.itemID) == [note.id], "a closed section on one page hides nothing on another")
        var later = item(.sticky, x: 900, y: 900)
        later.text = "needle"
        board.items.insert(later, at: 0)
        #expect(EaselFinder.matches(of: "needle", in: board).map(\.itemID) == [later.id, note.id], "matches come page by page")
        let pages = EaselPages.exportedPages(board)
        #expect(pages.map(\.name) == ["Page 1", "Page 2"] && pages[1].items.map(\.id) == [note.id], "exports walk the filled pages")
        let html = EaselVectorExport.htmlDocument(board, art: EaselVectorArt())
        #expect(html.components(separatedBy: "<section class=\"easel-page\">").count == 3 && html.contains("<h2>Page 2</h2>"),
               "HTML gets a section per page")
        let plain = EaselVectorExport.htmlDocument(document([item(.sticky, x: 0, y: 0)]), art: EaselVectorArt())
        #expect(!plain.contains("easel-page"), "a board without pages exports as before")
        let divided = try #require(EaselPages.addingDivider(to: board, after: second), "divider")
        #expect(EaselPages.exportedPages(divided.document).count == 2, "dividers stay out of exports")
        let empty = paged([]).document
        #expect(EaselPages.exportedPages(empty).count == 1, "an empty board still exports one page")
    }
}
