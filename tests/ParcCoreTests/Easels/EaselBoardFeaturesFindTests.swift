import Foundation
import Testing
@testable import ParcCore

struct EaselBoardFeaturesFindTests {
    @Test
    func readingOrderGoesLeftToRightBeforeTheNextRow() {
        let right = EaselBoardFeaturesTestsSupport.item(.sticky, "b", x: 300, y: 104)
        let left = EaselBoardFeaturesTestsSupport.item(.sticky, "a", x: 20, y: 100)
        let below = EaselBoardFeaturesTestsSupport.item(.sticky, "c", x: 0, y: 400)
        let order = EaselFinder.readingOrder([below, right, left]).map(\.text)
        #expect(order == ["a", "b", "c"], "objects on roughly the same row read left to right before the next row")
    }

    @Test
    func anObjectBelowTheRowAnchorStartsItsOwnRow() {
        let tall = EaselBoardFeaturesTestsSupport.item(.section, "t", x: 0, y: 0, width: 100, height: 1000)
        let beside = EaselBoardFeaturesTestsSupport.item(.text, "s", x: 400, y: 450)
        #expect(EaselFinder.readingOrder([beside, tall]).map(\.text) == ["t", "s"], "an object starting below half the row's anchor starts a new row")
    }

    @Test
    func findReturnsSearchableTextInReadingOrderWithUTF16Ranges() {
        let sticky = EaselBoardFeaturesTestsSupport.item(.sticky, "Plan the launch, then plan the party", x: 0, y: 0)
        let arrow = EaselBoardFeaturesTestsSupport.item(.arrow, "plan B", x: 0, y: 300)
        let image = EaselItem(kind: .image, frame: .init(x: 0, y: 500, width: 10, height: 10), text: "plan", assetID: "x")
        let link = EaselBoardFeaturesTestsSupport.item(.link, "Planning guide", x: 300, y: 0)
        let board = EaselBoardFeaturesTestsSupport.document([link, arrow, sticky, image])
        let matches = EaselFinder.matches(of: "plan", in: board)
        #expect(matches.count == 4, "stickies, connector labels and link cards match but images never do")
        #expect(matches.map(\.itemID) == [sticky.id, sticky.id, link.id, arrow.id], "matches follow reading order")
        #expect(matches[0].range == 0..<4 && matches[1].range == 22..<26, "ranges are UTF-16 offsets in order")
    }

    @Test
    func matchCaseRestrictsTheResults() {
        let sticky = EaselBoardFeaturesTestsSupport.item(.sticky, "Plan the launch, then plan the party", x: 0, y: 0)
        let arrow = EaselBoardFeaturesTestsSupport.item(.arrow, "plan B", x: 0, y: 300)
        let image = EaselItem(kind: .image, frame: .init(x: 0, y: 500, width: 10, height: 10), text: "plan", assetID: "x")
        let link = EaselBoardFeaturesTestsSupport.item(.link, "Planning guide", x: 300, y: 0)
        let board = EaselBoardFeaturesTestsSupport.document([link, arrow, sticky, image])
        #expect(EaselFinder.matches(of: "plan", in: board, options: NoteFindOptions(matchCase: true)).count == 2, "Match Case is honoured")
    }

    @Test
    func anEmptySearchFindsNothing() {
        let sticky = EaselBoardFeaturesTestsSupport.item(.sticky, "Plan the launch, then plan the party", x: 0, y: 0)
        let arrow = EaselBoardFeaturesTestsSupport.item(.arrow, "plan B", x: 0, y: 300)
        let image = EaselItem(kind: .image, frame: .init(x: 0, y: 500, width: 10, height: 10), text: "plan", assetID: "x")
        let link = EaselBoardFeaturesTestsSupport.item(.link, "Planning guide", x: 300, y: 0)
        let board = EaselBoardFeaturesTestsSupport.document([link, arrow, sticky, image])
        #expect(EaselFinder.matches(of: "", in: board).isEmpty, "an empty query finds nothing")
    }

    @Test
    func searchIgnoresAccentsByDefault() {
        let accented = EaselBoardFeaturesTestsSupport.document([EaselBoardFeaturesTestsSupport.item(.text, "Café crème", x: 0, y: 0)])
        #expect(EaselFinder.matches(of: "creme", in: accented).count == 1, "finding ignores accents unless Match Case is on")
    }

    @Test
    func theCurrentMatchSurvivesRefresh() {
        let sticky = EaselBoardFeaturesTestsSupport.item(.sticky, "Plan the launch, then plan the party", x: 0, y: 0)
        let arrow = EaselBoardFeaturesTestsSupport.item(.arrow, "plan B", x: 0, y: 300)
        let image = EaselItem(kind: .image, frame: .init(x: 0, y: 500, width: 10, height: 10), text: "plan", assetID: "x")
        let link = EaselBoardFeaturesTestsSupport.item(.link, "Planning guide", x: 300, y: 0)
        let board = EaselBoardFeaturesTestsSupport.document([link, arrow, sticky, image])
        let matches = EaselFinder.matches(of: "plan", in: board)
        #expect(EaselFinder.index(of: matches[2], in: matches, document: board) == 2, "the current match survives a refresh")
    }

    @Test
    func aVanishedMatchFallsBackToTheFirst() {
        let sticky = EaselBoardFeaturesTestsSupport.item(.sticky, "Plan the launch, then plan the party", x: 0, y: 0)
        let arrow = EaselBoardFeaturesTestsSupport.item(.arrow, "plan B", x: 0, y: 300)
        let image = EaselItem(kind: .image, frame: .init(x: 0, y: 500, width: 10, height: 10), text: "plan", assetID: "x")
        let link = EaselBoardFeaturesTestsSupport.item(.link, "Planning guide", x: 300, y: 0)
        let board = EaselBoardFeaturesTestsSupport.document([link, arrow, sticky, image])
        let matches = EaselFinder.matches(of: "plan", in: board)
        let gone = EaselFindMatch(itemID: UUID(), part: .text, range: 0..<1)
        #expect(EaselFinder.index(of: gone, in: matches, document: board) == 0, "a vanished match falls back to the first")
    }

    @Test
    func withoutMatchesThereIsNoCurrentMatch() {
        let sticky = EaselBoardFeaturesTestsSupport.item(.sticky, "Plan the launch, then plan the party", x: 0, y: 0)
        let arrow = EaselBoardFeaturesTestsSupport.item(.arrow, "plan B", x: 0, y: 300)
        let image = EaselItem(kind: .image, frame: .init(x: 0, y: 500, width: 10, height: 10), text: "plan", assetID: "x")
        let link = EaselBoardFeaturesTestsSupport.item(.link, "Planning guide", x: 300, y: 0)
        let board = EaselBoardFeaturesTestsSupport.document([link, arrow, sticky, image])
        #expect(EaselFinder.index(of: nil, in: [], document: board) == nil, "no matches means no current match")
    }

    @Test func findSkipsTitlesThatAreNotDrawn() {
        var section = EaselBoardFeaturesTestsSupport.item(.section, "Hidden plans", x: 0, y: 0, width: 600, height: 400)
        section.contentsHidden = true
        let inside = EaselBoardFeaturesTestsSupport.item(.sticky, "plans inside", x: 40, y: 60)
        var captured = EaselBoardFeaturesTestsSupport.item(.webCard, "plans captured", x: 900, y: 0)
        captured.url = "https://example.com/plans"
        captured.assetID = "a"
        var card = EaselBoardFeaturesTestsSupport.item(.webCard, "plans card", x: 900, y: 300)
        card.url = "https://example.com/plans"
        var live = EaselBoardFeaturesTestsSupport.item(.browser, "plans live", x: 900, y: 600)
        live.url = "https://example.com/plans"
        let board = EaselBoardFeaturesTestsSupport.document([section, inside, captured, card, live])
        let found = EaselFinder.matches(of: "plans", in: board).map(\.itemID)
        #expect(found.contains(section.id), "a section hiding its contents still shows its own title")
        #expect(!found.contains(inside.id), "objects tucked inside a hidden section are left out")
        #expect(!found.contains(captured.id) && !found.contains(live.id), "captured and live webpages show no title on the canvas, so they aren't searched")
        #expect(found.contains(card.id), "a webpage card that draws its title is searched")
        #expect(EaselFinder.matches(of: "example", in: board).isEmpty, "hidden URLs are never searched")
    }

    @Test
    func tableSearchFindsMatchesInCellOrder() {
        var grid = EaselBoardFeaturesTestsSupport.item(.table, "", x: 0, y: 0, width: 280, height: 72)
        grid.table = EaselTable(columnWidths: [140, 140], rowHeights: [36, 36],
                                cells: [[EaselTableCell(text: "cat"), EaselTableCell(text: "dog")],
                                        [EaselTableCell(text: "cat food"), EaselTableCell(text: "")]])
        let board = EaselBoardFeaturesTestsSupport.document([grid])
        let matches = EaselFinder.matches(of: "cat", in: board)
        #expect(matches.map(\.part) == [.cell(row: 0, column: 0), .cell(row: 1, column: 0)], "table cells are searched row by row")
    }

    @Test
    func findStartsAtTheFirstMatch() {
        let first = EaselBoardFeaturesTestsSupport.item(.sticky, "cat cat", x: 0, y: 0)
        let second = EaselBoardFeaturesTestsSupport.item(.sticky, "cat", x: 0, y: 400)
        let board = EaselBoardFeaturesTestsSupport.document([first, second])
        let state = EaselBoardFeaturesTestsSupport.session("cat", in: board)
        #expect(state.matches.count == 3 && state.currentIndex == 0, "a fresh search starts at the first match")
    }

    @Test(arguments: [(3, 0), (-1, 2)])
    func findWrapsInEitherDirection(_ step: Int, _ expected: Int) {
        let first = EaselBoardFeaturesTestsSupport.item(.sticky, "cat cat", x: 0, y: 0)
        let second = EaselBoardFeaturesTestsSupport.item(.sticky, "cat", x: 0, y: 400)
        let board = EaselBoardFeaturesTestsSupport.document([first, second])
        var state = EaselBoardFeaturesTestsSupport.session("cat", in: board)
        state.step(step)
        #expect(state.currentIndex == expected)
    }

    @Test
    func findRefreshKeepsTheMatchAfterEditing() {
        let first = EaselBoardFeaturesTestsSupport.item(.sticky, "cat cat", x: 0, y: 0)
        let second = EaselBoardFeaturesTestsSupport.item(.sticky, "cat", x: 0, y: 400)
        let board = EaselBoardFeaturesTestsSupport.document([first, second])
        var state = EaselBoardFeaturesTestsSupport.session("cat", in: board)
        state.step(-1)
        var edited = board
        edited.items[0].text = "cat dog"
        state.refresh(in: edited, keeping: state.currentMatch)
        #expect(state.currentMatch?.itemID == second.id && state.matches.count == 2, "a refresh after an edit keeps the current match")
        #expect(state.countLabel(replacing: false, in: edited) == "2 of 2", "the count says where you are")
    }

    @Test
    func findCanStartAtAMatchAlreadyInView() {
        let first = EaselBoardFeaturesTestsSupport.item(.sticky, "cat cat", x: 0, y: 0)
        let second = EaselBoardFeaturesTestsSupport.item(.sticky, "cat", x: 0, y: 400)
        let board = EaselBoardFeaturesTestsSupport.document([first, second])
        var preferred = EaselFindSession()
        preferred.query = "cat"
        preferred.refresh(in: board, keeping: nil) { matches in matches.firstIndex { $0.itemID == second.id } }
        #expect(preferred.currentMatch?.itemID == second.id, "a new search can start at the first match already in view")
    }

    @Test
    func theFindCountExplainsAMissingQueryOrMatch() {
        let first = EaselBoardFeaturesTestsSupport.item(.sticky, "cat cat", x: 0, y: 0)
        let second = EaselBoardFeaturesTestsSupport.item(.sticky, "cat", x: 0, y: 400)
        let board = EaselBoardFeaturesTestsSupport.document([first, second])
        var none = EaselBoardFeaturesTestsSupport.session("zebra", in: board)
        #expect(none.countLabel(replacing: true, in: board) == "No matches", "no matches says so")
        none.query = ""
        #expect(none.countLabel(replacing: true, in: board).isEmpty, "an empty query shows no count")
    }

    @Test
    func aVisibleMatchDoesNotMoveTheCanvas() {
        let visible = EaselRect(x: 0, y: 0, width: 1000, height: 800)
        let inside = EaselRect(x: 400, y: 300, width: 200, height: 100)
        #expect(EaselViewportFocus.plan(target: inside, visible: visible, magnification: 1, minimum: 0.33, maximum: 4) == nil,
               "a match already in view doesn't move the canvas")
    }

    @Test
    func anOffscreenMatchPansToItsCentre() {
        let visible = EaselRect(x: 0, y: 0, width: 1000, height: 800)
        let offscreen = EaselRect(x: 3000, y: 2000, width: 200, height: 100)
        let pan = EaselViewportFocus.plan(target: offscreen, visible: visible, magnification: 1, minimum: 0.33, maximum: 4)
        #expect(pan?.magnification == 1 && pan?.center == EaselPoint(x: 3100, y: 2050), "an off-screen match pans to its centre")
    }

    @Test
    func aMatchLargerThanTheViewportZoomsOut() {
        let visible = EaselRect(x: 0, y: 0, width: 1000, height: 800)
        let huge = EaselRect(x: 0, y: 0, width: 4000, height: 3000)
        let out = EaselViewportFocus.plan(target: huge, visible: visible, magnification: 1, minimum: 0.33, maximum: 4)
        #expect((out?.magnification ?? 1) < 1, "a match bigger than the view zooms out to fit")
    }

    @Test
    func aMatchTooSmallToReadZoomsToActualSize() {
        let inside = EaselRect(x: 400, y: 300, width: 200, height: 100)
        let tiny = EaselViewportFocus.plan(target: inside, visible: EaselRect(x: 0, y: 0, width: 4000, height: 3200), magnification: 0.25,
                                           minimum: 0.25, maximum: 4)
        #expect(tiny?.magnification == 1, "a match too small to read zooms in to 100%")
    }

    @Test
    func followingAnObjectLinkFocusesAtActualSize() {
        let visible = EaselRect(x: 0, y: 0, width: 1000, height: 800)
        let inside = EaselRect(x: 400, y: 300, width: 200, height: 100)
        let focused = EaselViewportFocus.plan(target: inside, visible: visible, magnification: 2.5, minimum: 0.33, maximum: 4, mode: .focus)
        #expect(focused?.magnification == 1 && focused?.center == EaselPoint(x: 500, y: 350), "focusing a link shows its object at 100%")
    }

    @Test
    func invalidMatchGeometryDoesNotMoveTheCanvas() {
        let visible = EaselRect(x: 0, y: 0, width: 1000, height: 800)
        let bad = EaselRect(x: .nan, y: 0, width: 1, height: 1)
        #expect(EaselViewportFocus.plan(target: bad, visible: visible, magnification: 1, minimum: 0.33, maximum: 4) == nil, "bad geometry is ignored")
    }
}
