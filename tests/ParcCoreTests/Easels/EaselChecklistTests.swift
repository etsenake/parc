import Foundation
import Testing
@testable import ParcCore

struct EaselChecklistTests {
    @Test func theOpenMarkerIsAnUntickedItem() {
        #expect(EaselChecklist.marker(EaselChecklist.openMarker) == .open)
    }

    @Test func theDoneMarkerIsATickedItem() {
        #expect(EaselChecklist.marker(EaselChecklist.doneMarker) == .done)
    }

    @Test func theDividerMarkerIsARule() {
        #expect(EaselChecklist.marker(EaselChecklist.dividerMarker) == .divider)
    }

    @Test(arguments: ["\u{258E}", ""])
    func quoteAndEmptyMarkersAreNotChecklistMarkers(marker: String) {
        #expect(EaselChecklist.marker(marker) == nil)
    }

    @Test func onlyOpenAndDoneMarkersAreItems() {
        #expect(EaselChecklist.Marker.open.isItem)
        #expect(EaselChecklist.Marker.done.isItem)
        #expect(!EaselChecklist.Marker.divider.isItem)
    }

    @Test func aMarkerSitsBetweenTwoTabs() {
        #expect(EaselChecklist.prefix(.done) == "\t\u{2611}\t")
    }

    @Test(arguments: [(15.0, 16.0), (3, 10), (400, 18)])
    func theBoxFollowsTheFontSizeWithinLimits(fontSize: Double, side: Double) {
        #expect(EaselChecklist.boxSide(fontSize: fontSize) == side)
    }

    @Test(arguments: [EaselChecklist.openMarker, EaselChecklist.doneMarker, EaselChecklist.dividerMarker])
    func checklistMarkersSurviveASave(marker: String) throws {
        let paragraph = EaselRichText.Paragraph(alignment: 0, direction: -1, lineBreak: 0, firstIndent: 0, headIndent: 24, tailIndent: 0,
                                                lineSpacing: 0, before: 4, after: 8, minimumHeight: 0, maximumHeight: 0, heightMultiple: 1.25,
                                                hyphenation: 0, tightening: 0, allowsTightening: true, defaultHyphenation: true,
                                                defaultTab: 0, tabs: [], lists: [.init(marker: marker, options: 0, start: 1)])
        let attributes = EaselRichText.Attributes(font: .init(name: "Helvetica", size: 15), ink: "#252525FF", paragraph: paragraph)
        let text = "\t" + marker + "\tItem\n"
        let rich = EaselRichText(runs: [.init(location: 0, length: (text as NSString).length, attributes: attributes)])
        try rich.validate(text: text)
        let decoded = try JSONDecoder().decode(EaselRichText.self, from: JSONEncoder().encode(rich))
        #expect(decoded == rich)
    }

    private static let item: EaselItem = {
        var item = EaselItem(kind: .text, frame: .init(x: 10, y: 20, width: 300, height: 80))
        item.text = "Item"
        return item
    }()

    private static let rule = EaselVectorRule(x1: 5, x2: 295, y: 60)

    private static var markup: String {
        var layout = EaselVectorText()
        var run = EaselVectorTextRun(x: 24, y: 12, text: "Item", fontFamily: "Helvetica", fontSize: 15)
        run.dimmed = true
        layout.runs = [run]
        layout.checkboxes = [EaselVectorCheckbox(x: 2, y: 2, size: 16, checked: false), EaselVectorCheckbox(x: 2, y: 30, size: 16, checked: true)]
        layout.rules = [rule]
        return EaselVectorExport.text(item, layout)
    }

    @Test func doneItemsFadeTheirWordsInTheExport() {
        #expect(Self.markup.contains("fill-opacity:.45"))
    }

    @Test func openBoxesAreExportedAsRings() {
        #expect(Self.markup.contains("fill:none;stroke:var(--easel-muted)"))
    }

    @Test func doneBoxesAreExportedFilledWithATick() {
        let markup = Self.markup
        #expect(markup.contains("var(--easel-todo,#2702C2)"))
        #expect(markup.contains("stroke:#FFFFFF"))
    }

    @Test func dividersAreExportedAsLines() {
        #expect(Self.markup.contains("<line x1=\"5\" y1=\"60\" x2=\"295\" y2=\"60\""))
    }

    @Test func aDividerAloneStillDraws() {
        var alone = EaselVectorText()
        alone.rules = [Self.rule]
        #expect(!EaselVectorExport.text(Self.item, alone).isEmpty)
    }

    @Test func theStylesheetDefinesTheRuleAndTickColoursForBothAppearances() {
        let css = EaselVectorExport.css(.standard)
        #expect(css.contains("--easel-rule:"))
        #expect(css.contains("--easel-todo:#9380E0"))
    }
}
