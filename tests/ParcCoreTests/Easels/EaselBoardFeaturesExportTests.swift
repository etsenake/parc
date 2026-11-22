import Foundation
import Testing
@testable import ParcCore

struct EaselBoardFeaturesExportTests {
    @Test
    func objectLinksRoundTripTheEaselAndObjectIDs() {
        let easel = UUID(), object = UUID()
        let link = EaselObjectAddress.urlString(easel: easel, object: object)
        #expect(link == "parc://easel/" + easel.uuidString.lowercased() + "#" + object.uuidString.lowercased(), "object links are the Easel link plus the object id")
        #expect(EaselObjectAddress.target(of: link)?.easel == easel && EaselObjectAddress.target(of: link)?.object == object, "object links round trip")
    }

    @Test
    func anObjectLinkOpensThePlainEaselAddress() {
        let easel = UUID(), object = UUID()
        let link = EaselObjectAddress.urlString(easel: easel, object: object)
        #expect(InternalPage(urlString: link) == .easel(easel), "an object link still opens its Easel")
        #expect(InternalPage(urlString: link)?.urlString == InternalPage.easel(easel).urlString, "tabs keep the plain Easel address")
    }

    @Test
    func easelObjectLinksRejectInvalidFragmentsAndQueries() {
        let easel = UUID(), object = UUID()
        #expect(InternalPage(urlString: "parc://easel/" + easel.uuidString + "#heading") == nil, "other fragments aren't Easel links")
        #expect(InternalPage(urlString: "parc://easel/" + easel.uuidString + "?x=1#" + object.uuidString) == nil, "queries still aren't Easel links")
    }

    @Test
    func aPlainEaselLinkDoesNotIdentifyAnObject() {
        let easel = UUID()
        #expect(EaselObjectAddress.target(of: InternalPage.easel(easel).urlString) == nil, "a plain Easel link names no object")
    }

    @Test
    func exportingASectionIncludesItsVisibleContents() {
        let section = EaselBoardFeaturesTestsSupport.item(.section, "Ideas", x: 0, y: 0, width: 600, height: 400)
        let inside = EaselBoardFeaturesTestsSupport.item(.sticky, "inside", x: 40, y: 40)
        let outside = EaselBoardFeaturesTestsSupport.item(.sticky, "outside", x: 900, y: 40)
        var arrow = EaselBoardFeaturesTestsSupport.item(.arrow, "", x: 240, y: 90, width: 660, height: 1)
        arrow.points = [EaselPoint(x: 0, y: 0), EaselPoint(x: 660, y: 0)]
        arrow.startConnection = EaselConnection(itemID: inside.id)
        arrow.endConnection = EaselConnection(itemID: outside.id)
        let board = EaselDocument(id: UUID(), title: "Board", createdAt: Date(), modifiedAt: Date(), items: [section, inside, outside, arrow])
        let scope = EaselSelectionExport.scope([section.id], in: board)
        #expect(scope == [section.id, inside.id], "exporting a section brings its contents along")
    }

    @Test
    func exportingAVanishedSelectionIncludesNothing() {
        let section = EaselBoardFeaturesTestsSupport.item(.section, "Ideas", x: 0, y: 0, width: 600, height: 400)
        let inside = EaselBoardFeaturesTestsSupport.item(.sticky, "inside", x: 40, y: 40)
        let outside = EaselBoardFeaturesTestsSupport.item(.sticky, "outside", x: 900, y: 40)
        var arrow = EaselBoardFeaturesTestsSupport.item(.arrow, "", x: 240, y: 90, width: 660, height: 1)
        arrow.points = [EaselPoint(x: 0, y: 0), EaselPoint(x: 660, y: 0)]
        arrow.startConnection = EaselConnection(itemID: inside.id)
        arrow.endConnection = EaselConnection(itemID: outside.id)
        let board = EaselDocument(id: UUID(), title: "Board", createdAt: Date(), modifiedAt: Date(), items: [section, inside, outside, arrow])
        #expect(EaselSelectionExport.scope([UUID()], in: board).isEmpty, "a vanished selection exports nothing")
    }

    @Test
    func aSelectionExportKeepsOnlySelectedObjectsAndConnections() {
        let section = EaselBoardFeaturesTestsSupport.item(.section, "Ideas", x: 0, y: 0, width: 600, height: 400)
        let inside = EaselBoardFeaturesTestsSupport.item(.sticky, "inside", x: 40, y: 40)
        let outside = EaselBoardFeaturesTestsSupport.item(.sticky, "outside", x: 900, y: 40)
        var arrow = EaselBoardFeaturesTestsSupport.item(.arrow, "", x: 240, y: 90, width: 660, height: 1)
        arrow.points = [EaselPoint(x: 0, y: 0), EaselPoint(x: 660, y: 0)]
        arrow.startConnection = EaselConnection(itemID: inside.id)
        arrow.endConnection = EaselConnection(itemID: outside.id)
        let board = EaselDocument(id: UUID(), title: "Board", createdAt: Date(), modifiedAt: Date(), items: [section, inside, outside, arrow])
        let subset = EaselSelectionExport.document(board, keeping: [inside.id, arrow.id])
        #expect(subset.items.map(\.id) == [inside.id, arrow.id], "the export keeps only the chosen objects")
        #expect(subset.items.last?.endConnection == nil && subset.items.last?.startConnection?.itemID == inside.id,
               "connectors let go of objects left out of the export")
    }

    @Test
    func hiddenSectionContentsAreOmittedFromExport() {
        let section = EaselBoardFeaturesTestsSupport.item(.section, "Ideas", x: 0, y: 0, width: 600, height: 400)
        let inside = EaselBoardFeaturesTestsSupport.item(.sticky, "inside", x: 40, y: 40)
        let outside = EaselBoardFeaturesTestsSupport.item(.sticky, "outside", x: 900, y: 40)
        var hidden = section
        hidden.contentsHidden = true
        let tucked = EaselDocument(id: UUID(), title: "Board", createdAt: Date(), modifiedAt: Date(), items: [hidden, inside, outside])
        #expect(EaselSelectionExport.scope([hidden.id], in: tucked) == [hidden.id], "hidden section contents stay out, as on the canvas")
        #expect(EaselSelectionExport.stickies(in: tucked).map(\.id) == [outside.id], "hidden stickies stay out of the CSV")
    }

    @Test
    func stickyExportReadsInOrderAndHonoursSelection() {
        let first = EaselBoardFeaturesTestsSupport.item(.sticky, "Plain", x: 300, y: 0)
        let second = EaselBoardFeaturesTestsSupport.item(.sticky, "Says \"hi\", twice\nand more", x: 0, y: 0)
        let third = EaselBoardFeaturesTestsSupport.item(.sticky, "Below", x: 0, y: 400)
        let board = EaselDocument(id: UUID(), title: "Board", createdAt: Date(), modifiedAt: Date(),
                                  items: [third, first, EaselBoardFeaturesTestsSupport.item(.text, "not a sticky", x: 0, y: 200), second])
        let stickies = EaselSelectionExport.stickies(in: board)
        #expect(stickies.map(\.id) == [second.id, first.id, third.id], "stickies export in reading order")
        #expect(EaselSelectionExport.stickies(in: board, within: [first.id]).map(\.id) == [first.id], "a selection exports only its stickies")
    }

    @Test
    func stickyCSVQuotesContentFields() {
        let first = EaselBoardFeaturesTestsSupport.item(.sticky, "Plain", x: 300, y: 0)
        let second = EaselBoardFeaturesTestsSupport.item(.sticky, "Says \"hi\", twice\nand more", x: 0, y: 0)
        let third = EaselBoardFeaturesTestsSupport.item(.sticky, "Below", x: 0, y: 400)
        let board = EaselDocument(id: UUID(), title: "Board", createdAt: Date(), modifiedAt: Date(),
                                  items: [third, first, EaselBoardFeaturesTestsSupport.item(.text, "not a sticky", x: 0, y: 200), second])
        let stickies = EaselSelectionExport.stickies(in: board)
        let csv = EaselSelectionExport.stickyCSV(stickies)
        #expect(csv == "Content\r\n\"Says \"\"hi\"\", twice\nand more\"\r\nPlain\r\nBelow\r\n", "the CSV has a Content column with quoted fields")
    }

    @Test
    func anEmptyStickyCSVStillHasAHeader() {
        #expect(EaselSelectionExport.stickyCSV([]) == "Content\r\n", "no stickies still makes a valid CSV")
    }

    @Test
    func stickyCSVProtectsFormulaStarters() {
        let risky = ["=1+1", "+5", "-2", "@SUM(A1)", "\tgo", "\rgo"].map { EaselBoardFeaturesTestsSupport.item(.sticky, $0, x: 0, y: 0) }
        let safe = EaselSelectionExport.stickyCSV(risky)
        #expect(safe == "Content\r\n\"'=1+1\"\r\n\"'+5\"\r\n\"'-2\"\r\n\"'@SUM(A1)\"\r\n\"'\tgo\"\r\n\"'\rgo\"\r\n", "formula starters are defused with a quoted apostrophe")
    }

    @Test
    func anEmptyStickyStillExportsARow() {
        #expect(EaselSelectionExport.stickyCSV([EaselBoardFeaturesTestsSupport.item(.sticky, "", x: 0, y: 0)]) == "Content\r\n\"\"\r\n", "an empty sticky stays a row")
    }

    @Test
    func anEqualsSignInsideTextIsLeftAlone() {
        #expect(EaselSelectionExport.stickyCSV([EaselBoardFeaturesTestsSupport.item(.sticky, "a=b", x: 0, y: 0)]) == "Content\r\na=b\r\n", "an equals sign inside text is left alone")
    }

    @Test
    func tableCopyKeepsItsOwnFieldRules() {
        #expect(EaselTableData.field("=1", separator: ",") == "=1", "table copy keeps its own field rules")
    }
}
