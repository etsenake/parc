import Foundation
import Testing
@testable import ParcCore

struct EaselPagesModelTests {
    @Test func aBoardWithoutPagesIsUnchanged() {
        let board = EaselPagesTestsSupport.document([EaselPagesTestsSupport.item(.sticky, x: 0, y: 0), EaselPagesTestsSupport.item(.rectangle, x: 200, y: 0)])
        #expect(EaselPages.items(on: nil, in: board) == board.items, "a board without pages shows every object")
        #expect(EaselPages.view(board, page: UUID()) == board, "a board without pages has one view")
        #expect(EaselPages.resolvedPage(UUID(), in: board) == nil, "a board without pages has no page IDs")
        #expect(EaselPages.validationProblem(board) == nil, "a board without pages is valid")
        #expect(EaselPages.merging(board, page: nil, into: board) == board, "merging a single page is identity")
        #expect(EaselPages.collapsed(board) == board, "collapsing a board without pages changes nothing")
    }

    @Test func anUnpagedBoardOmitsUnusedFields() throws {
        let board = EaselPagesTestsSupport.document([EaselPagesTestsSupport.item(.sticky, x: 0, y: 0)])
        let plain = String(decoding: try JSONEncoder().encode(board), as: UTF8.self)
        #expect(!plain.contains("\"pages\"") && !plain.contains("\"page\""))
    }

    @Test func pagesRoundTripWithTheirObjects() throws {
        let (board, first, _) = EaselPagesTestsSupport.paged([EaselPagesTestsSupport.item(.sticky, x: 0, y: 0)])
        let decoded = try JSONDecoder().decode(EaselDocument.self, from: JSONEncoder().encode(board))
        #expect(decoded == board)
        #expect(decoded.items.first?.page == first)
    }

    @Test func aMissingObjectPageDefaultsToPageOne() {
        let (original, first, _) = EaselPagesTestsSupport.paged([EaselPagesTestsSupport.item(.sticky, x: 0, y: 0)])
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
        let (original, first, _) = EaselPagesTestsSupport.paged([EaselPagesTestsSupport.item(.sticky, x: 0, y: 0)])
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
        let a = EaselPagesTestsSupport.item(.sticky, x: 0, y: 0), b = EaselPagesTestsSupport.item(.rectangle, x: 200, y: 0)
        guard let change = EaselPages.adding(to: EaselPagesTestsSupport.document([a, b])), let pages = change.document.pages else {
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
        var full = EaselPagesTestsSupport.document([])
        full.pages = (0..<EaselPage.maximumCount).map { EaselPage(id: UUID(), name: "P\($0)") }
        #expect(EaselPages.adding(to: full) == nil, "adding stops at the page limit")
        var taken = change.document
        taken.pages?[1].name = "Page 3"
        #expect(EaselPages.nextName(in: taken) == "Page 4", "new names skip names already in use")
    }

    @Test
    func renamingChangesTheNameOnlyWhenItIsDifferentAndNonblank() throws {
        let (board, _, second) = EaselPagesTestsSupport.paged([EaselPagesTestsSupport.item(.sticky, x: 0, y: 0)])
        let renamed = try #require(EaselPages.renaming(second, to: "Ideas", in: board), "rename works")
        #expect(renamed.pages?[1].name == "Ideas", "rename changes the name")
        #expect(EaselPages.renaming(second, to: "Ideas", in: renamed) == nil, "renaming to the same name is no change")
        #expect(EaselPages.renaming(second, to: "", in: renamed) == nil, "a blank rename is refused")
    }

    @Test
    func aPageWithObjectsCannotBecomeADivider() {
        let (board, first, _) = EaselPagesTestsSupport.paged([EaselPagesTestsSupport.item(.sticky, x: 0, y: 0)])
        #expect(EaselPages.renaming(first, to: "-", in: board) == nil, "a page with objects can't become a divider")
    }

    @Test
    func anEmptyPageCanBecomeANonNavigableDivider() throws {
        let (board, first, second) = EaselPagesTestsSupport.paged([EaselPagesTestsSupport.item(.sticky, x: 0, y: 0)])
        let divider = try #require(EaselPages.renaming(second, to: "-", in: board), "an empty page becomes a divider")
        #expect(EaselPages.isDivider(divider.pages![1], in: divider), "a page named - is a divider")
        #expect(EaselPages.contentPages(divider).map(\.id) == [first], "dividers aren't pages you visit")
        #expect(EaselPages.resolvedPage(second, in: divider) == first, "a divider resolves to a real page")
    }

    @Test
    func anAddedDividerLandsAfterTheCurrentPage() throws {
        let (board, first, _) = EaselPagesTestsSupport.paged([EaselPagesTestsSupport.item(.sticky, x: 0, y: 0)])
        let added = try #require(EaselPages.addingDivider(to: board, after: first), "dividers can be added")
        #expect(added.document.pages?.map(\.name) == ["Page 1", "-", "Page 2"], "a divider lands after the page")
        #expect(added.page == first, "adding a divider keeps the current page")
    }

    @Test
    func theLastRealPageCannotBecomeADivider() {
        var lone = EaselPagesTestsSupport.document([])
        lone.pages = [EaselPage(id: UUID(), name: "Solo"), EaselPage(id: UUID(), name: "-")]
        #expect(EaselPages.renaming(lone.pages![0].id, to: "-", in: lone) == nil, "the last real page can't become a divider")
    }

    @Test func reorderingPagesKeepsObjectsWithTheirPage() throws {
        let a = EaselPagesTestsSupport.item(.sticky, x: 0, y: 0)
        var board = EaselPagesTestsSupport.paged([a]).document
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
}
