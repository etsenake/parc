import Foundation
import Testing
@testable import ParcCore

struct EaselPagesNavigationTests {
    @Test
    func undoShowsThePageWhereAnObjectChanged() {
        let a = EaselPagesTestsSupport.item(.sticky, x: 0, y: 0)
        var (board, first, second) = EaselPagesTestsSupport.paged([a])
        var b = EaselPagesTestsSupport.item(.sticky, x: 0, y: 0)
        b.page = second
        board.items.append(b)
        var edited = board
        edited.items[0].frame.x = 90
        #expect(EaselPages.followedPage(from: edited, to: board, showing: second) == first, "undoing an edit on another page shows that page")
        #expect(EaselPages.followedPage(from: edited, to: board, showing: first) == first, "an edit on the shown page keeps the page")
    }

    @Test
    func undoAndRedoADeletionFollowTheRestoredOrFlattenedPage() throws {
        let a = EaselPagesTestsSupport.item(.sticky, x: 0, y: 0)
        var (board, first, second) = EaselPagesTestsSupport.paged([a])
        var b = EaselPagesTestsSupport.item(.sticky, x: 0, y: 0)
        b.page = second
        board.items.append(b)
        let deleted = try #require(EaselPages.deleting(second, in: board)?.document, "delete")
        #expect(EaselPages.followedPage(from: deleted, to: board, showing: first) == second, "undoing a delete shows the page again")
        #expect(EaselPages.followedPage(from: board, to: deleted, showing: second) == nil, "a board folded back to one page has no page ID")
    }

    @Test
    func deletingAnActivePageFallsBackToARemainingPage() {
        let a = EaselPagesTestsSupport.item(.sticky, x: 0, y: 0)
        var (board, first, second) = EaselPagesTestsSupport.paged([a])
        var b = EaselPagesTestsSupport.item(.sticky, x: 0, y: 0)
        b.page = second
        board.items.append(b)
        guard let named = EaselPages.renaming(first, to: "Ideas", in: board), let kept = EaselPages.deleting(second, in: named)?.document else {
            Issue.record("renamed delete"); return
        }
        #expect(EaselPages.followedPage(from: named, to: kept, showing: second) == first, "a removed page falls back to a real one")
    }

    @Test
    func undoingARenameKeepsTheDisplayedPage() throws {
        let a = EaselPagesTestsSupport.item(.sticky, x: 0, y: 0)
        var (board, first, second) = EaselPagesTestsSupport.paged([a])
        var b = EaselPagesTestsSupport.item(.sticky, x: 0, y: 0)
        b.page = second
        board.items.append(b)
        let renamed = try #require(EaselPages.renaming(second, to: "Ideas", in: board), "rename")
        #expect(EaselPages.followedPage(from: renamed, to: board, showing: first) == first, "a rename keeps the page")
    }

    @Test
    func aHiddenSectionCannotHideMatchesOnAnotherPage() {
        var section = EaselPagesTestsSupport.item(.section, x: 0, y: 0, width: 500, height: 500)
        section.contentsHidden = true
        var note = EaselPagesTestsSupport.item(.sticky, x: 50, y: 50)
        note.text = "needle"
        var (board, _, second) = EaselPagesTestsSupport.paged([section])
        note.page = second
        board.items.append(note)
        #expect(EaselFinder.matches(of: "needle", in: board).map(\.itemID) == [note.id], "a closed section on one page hides nothing on another")
    }

    @Test
    func findingReturnsMatchesInPageOrder() {
        var section = EaselPagesTestsSupport.item(.section, x: 0, y: 0, width: 500, height: 500)
        section.contentsHidden = true
        var note = EaselPagesTestsSupport.item(.sticky, x: 50, y: 50)
        note.text = "needle"
        var (board, _, second) = EaselPagesTestsSupport.paged([section])
        note.page = second
        board.items.append(note)
        var later = EaselPagesTestsSupport.item(.sticky, x: 900, y: 900)
        later.text = "needle"
        board.items.insert(later, at: 0)
        #expect(EaselFinder.matches(of: "needle", in: board).map(\.itemID) == [later.id, note.id], "matches come page by page")
    }

    @Test
    func exportingListsFilledPagesInOrder() {
        var section = EaselPagesTestsSupport.item(.section, x: 0, y: 0, width: 500, height: 500)
        section.contentsHidden = true
        var note = EaselPagesTestsSupport.item(.sticky, x: 50, y: 50)
        note.text = "needle"
        var (board, _, second) = EaselPagesTestsSupport.paged([section])
        note.page = second
        board.items.append(note)
        var later = EaselPagesTestsSupport.item(.sticky, x: 900, y: 900)
        later.text = "needle"
        board.items.insert(later, at: 0)
        let pages = EaselPages.exportedPages(board)
        #expect(pages.map(\.name) == ["Page 1", "Page 2"] && pages[1].items.map(\.id) == [note.id], "exports walk the filled pages")
    }

    @Test
    func htmlExportsOneSectionPerPage() {
        var section = EaselPagesTestsSupport.item(.section, x: 0, y: 0, width: 500, height: 500)
        section.contentsHidden = true
        var note = EaselPagesTestsSupport.item(.sticky, x: 50, y: 50)
        note.text = "needle"
        var (board, _, second) = EaselPagesTestsSupport.paged([section])
        note.page = second
        board.items.append(note)
        var later = EaselPagesTestsSupport.item(.sticky, x: 900, y: 900)
        later.text = "needle"
        board.items.insert(later, at: 0)
        let html = EaselVectorExport.htmlDocument(board, art: EaselVectorArt())
        #expect(html.components(separatedBy: "<section class=\"easel-page\">").count == 3 && html.contains("<h2>Page 2</h2>"),
               "HTML gets a section per page")
    }

    @Test
    func anUnpagedBoardExportsWithoutPageSections() {
        let plain = EaselVectorExport.htmlDocument(EaselPagesTestsSupport.document([EaselPagesTestsSupport.item(.sticky, x: 0, y: 0)]), art: EaselVectorArt())
        #expect(!plain.contains("easel-page"), "a board without pages exports as before")
    }

    @Test
    func dividersAreOmittedFromPageExports() throws {
        var section = EaselPagesTestsSupport.item(.section, x: 0, y: 0, width: 500, height: 500)
        section.contentsHidden = true
        var note = EaselPagesTestsSupport.item(.sticky, x: 50, y: 50)
        note.text = "needle"
        var (board, _, second) = EaselPagesTestsSupport.paged([section])
        note.page = second
        board.items.append(note)
        var later = EaselPagesTestsSupport.item(.sticky, x: 900, y: 900)
        later.text = "needle"
        board.items.insert(later, at: 0)
        let divided = try #require(EaselPages.addingDivider(to: board, after: second), "divider")
        #expect(EaselPages.exportedPages(divided.document).count == 2, "dividers stay out of exports")
    }

    @Test
    func anEmptyBoardStillExportsOnePage() {
        let empty = EaselPagesTestsSupport.paged([]).document
        #expect(EaselPages.exportedPages(empty).count == 1, "an empty board still exports one page")
    }
}
