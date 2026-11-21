import Foundation

@main
struct EaselChecklistTests {
    @MainActor static var assertions = 0

    @MainActor static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        assertions += 1
        if !condition() { fatalError(message) }
    }

    @MainActor static func main() throws {
        markers()
        try savedLists()
        exports()
        print("EaselChecklistTests: \(assertions) assertions passed")
    }

    @MainActor static func markers() {
        expect(EaselChecklist.marker(EaselChecklist.openMarker) == .open, "the open marker is an unticked item")
        expect(EaselChecklist.marker(EaselChecklist.doneMarker) == .done, "the done marker is a ticked item")
        expect(EaselChecklist.marker(EaselChecklist.dividerMarker) == .divider, "the divider marker is a rule")
        expect(EaselChecklist.marker("\u{258E}") == nil && EaselChecklist.marker("") == nil, "quote and empty markers are not checklist markers")
        expect(EaselChecklist.Marker.open.isItem && !EaselChecklist.Marker.divider.isItem, "only open and done markers are items")
        expect(EaselChecklist.prefix(.done) == "\t\u{2611}\t", "a marker sits between two tabs")
        expect(EaselChecklist.boxSide(fontSize: 15) == 16 && EaselChecklist.boxSide(fontSize: 3) == 10 && EaselChecklist.boxSide(fontSize: 400) == 18,
               "the box follows the font size within limits")
    }

    @MainActor static func savedLists() throws {
        for marker in [EaselChecklist.openMarker, EaselChecklist.doneMarker, EaselChecklist.dividerMarker] {
            let paragraph = EaselRichText.Paragraph(alignment: 0, direction: -1, lineBreak: 0, firstIndent: 0, headIndent: 24, tailIndent: 0,
                                                    lineSpacing: 0, before: 4, after: 8, minimumHeight: 0, maximumHeight: 0, heightMultiple: 1.25,
                                                    hyphenation: 0, tightening: 0, allowsTightening: true, defaultHyphenation: true,
                                                    defaultTab: 0, tabs: [], lists: [.init(marker: marker, options: 0, start: 1)])
            let attributes = EaselRichText.Attributes(font: .init(name: "Helvetica", size: 15), ink: "#252525FF", paragraph: paragraph)
            let text = "\t" + marker + "\tItem\n"
            let rich = EaselRichText(runs: [.init(location: 0, length: (text as NSString).length, attributes: attributes)])
            try rich.validate(text: text)
            let data = try JSONEncoder().encode(rich)
            let decoded = try JSONDecoder().decode(EaselRichText.self, from: data)
            expect(decoded == rich, "checklist markers survive a save")
        }
    }

    @MainActor static func exports() {
        var item = EaselItem(kind: .text, frame: .init(x: 10, y: 20, width: 300, height: 80))
        item.text = "Item"
        var layout = EaselVectorText()
        var run = EaselVectorTextRun(x: 24, y: 12, text: "Item", fontFamily: "Helvetica", fontSize: 15)
        run.dimmed = true
        layout.runs = [run]
        layout.checkboxes = [EaselVectorCheckbox(x: 2, y: 2, size: 16, checked: false), EaselVectorCheckbox(x: 2, y: 30, size: 16, checked: true)]
        layout.rules = [EaselVectorRule(x1: 5, x2: 295, y: 60)]
        let markup = EaselVectorExport.text(item, layout)
        expect(markup.contains("fill-opacity:.45"), "done items fade their words")
        expect(markup.contains("fill:none;stroke:var(--easel-muted)"), "open boxes are drawn as rings")
        expect(markup.contains("var(--easel-todo,#2702C2)") && markup.contains("stroke:#FFFFFF"), "done boxes are filled with a tick")
        expect(markup.contains("<line x1=\"5\" y1=\"60\" x2=\"295\" y2=\"60\""), "dividers are drawn as lines")
        var alone = EaselVectorText()
        alone.rules = layout.rules
        expect(!EaselVectorExport.text(item, alone).isEmpty, "a divider alone still draws")
        let css = EaselVectorExport.css(.standard)
        expect(css.contains("--easel-rule:") && css.contains("--easel-todo:#9380E0"), "the stylesheet defines the rule and tick colours for both appearances")
    }
}
