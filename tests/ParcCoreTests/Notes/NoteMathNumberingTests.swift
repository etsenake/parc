import Foundation
import Testing
@testable import ParcCore

@MainActor struct NoteMathNumberingTests {
    func equation(_ source: String) -> NoteBlock { NoteBlock(.equation, text: NoteText(source)) }

    @Test func exportedEquationsKeepTheirNumbersAndLinks() {
        let first = equation("\\begin{align} a \\label{eq:one} \\\\ b \\label{two} \\end{align}")
        let second = equation("\\begin{equation} c \\label{three} \\end{equation}")
        let reference = equation("x = \\eqref{three}")
        let page = NotePage(blocks: [first, .heading(1, NoteText("eq-three")),
                                     .paragraph(NoteText("See ") + NoteText.atom(.equation("\\eqref{eq:one}"))), second, reference])
        var seen: [(String, Bool, NoteMathNumberingContext)] = []
        let html = NotePageHTML.document(page, title: "Maths", assets: { _ in nil }, embedImages: true, equationArt: { tex, display, context in
            seen.append((tex, display, context))
            let links = ["eq:one", "three", "missing"].filter { tex.contains("{" + $0 + "}") && tex.contains("ref") }
                .map { NoteEquationArt.Link(key: $0, rect: CGRect(x: 1.4, y: 2.6, width: 10, height: 12)) }
            return NoteEquationArt(url: URL(string: "data:image/svg+xml,x")!, links: links)
        })
        func context(_ tex: String) -> NoteMathNumberingContext? { seen.first { $0.0 == tex }?.2 }
        #expect(context(first.text.string)?.firstNumber == 0 && context(second.text.string)?.firstNumber == 2, "every exported equation continues the note's numbering")
        #expect(context(reference.text.string)?.references["three"] == [.text("3", .roman)], "exported references resolve across equations")
        #expect(context("\\eqref{eq:one}")?.references["eq:one"] == [.text("1", .roman)], "inline references resolve too")
        #expect(html.contains("<div data-block=\"equation\" id=\"eq-eq-one\"") && html.contains("<span id=\"eq-two\"></span>"), "labelled equations carry an anchor per label")
        #expect(html.contains("id=\"eq-three-2\""), "equation anchors never collide with heading anchors")
        #expect(html.contains("<area shape=\"rect\" coords=\"1,2,12,15\" href=\"#eq-three-2\" alt=\"Equation 3\">"), "display references link to their equation")
        #expect(html.contains("href=\"#eq-eq-one\" alt=\"Equation 1\""), "inline references link to their equation")
        #expect(!html.contains("#missing") && html.contains("usemap=\"#equation-links-"), "only labels that exist become links")
        let fragment = NotePageHTML.fragment(page.blocks)
        #expect(fragment.contains("$$" + NotePageHTMLWriter.escape(second.text.string) + "$$") && !fragment.contains("<area"), "copied HTML keeps the TeX source")
    }
}
