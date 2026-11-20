import Foundation

@main @MainActor
struct NoteMathNumberingTests {
    static func expect(_ value: Bool, _ message: String, line: UInt = #line) {
        if !value { failTest(message, line: line) }
    }

    static func equation(_ source: String) -> NoteBlock { NoteBlock(.equation, text: NoteText(source)) }

    static func main() {
        let first = equation("\\begin{align} a \\label{one} \\\\ b \\end{align}")
        let plain = equation("x^2")
        let second = equation("\\begin{equation} c \\label{three} \\end{equation}")
        let tagged = equation("d \\tag{T} \\label{tee}")
        let toggle = NoteBlock(.toggle, text: NoteText("More"))
        var nested = toggle
        nested.children = [equation("\\begin{gather} e \\label{four} \\end{gather}")]
        var page = NotePage()
        page.blocks = [first, .paragraph(NoteText("between")), plain, second, tagged, nested]
        let numberer = NotePageMathNumberer()
        let numbering = numberer.numbering(for: page)
        expect(numbering.context(for: first.id).firstNumber == 0 && numbering.context(for: second.id).firstNumber == 2,
               "numbers run through the note in order")
        expect(numbering.references["one"] == [.text("1", .roman)] && numbering.references["three"] == [.text("3", .roman)],
               "labels resolve to page numbers: \(numbering.references)")
        expect(numbering.references["tee"] == [.text("T", .roman)], "tags override the number")
        expect(numbering.references["four"] == [.text("4", .roman)], "equations inside collapsed blocks still count")
        expect(numbering.targets["three"] == second.id, "labels know their block")
        expect(numbering.total == 4, "four numbered rows")
        var reordered = page
        reordered.blocks = [second, first, .paragraph(NoteText("between")), plain, tagged, nested]
        let moved = numberer.numbering(for: reordered)
        expect(moved.references["three"] == [.text("1", .roman)] && moved.references["one"] == [.text("2", .roman)], "reordering renumbers")
        var duplicated = page
        let copy = equation("\\begin{equation} z \\label{one} \\end{equation}")
        duplicated.blocks.append(copy)
        let clashing = numberer.numbering(for: duplicated)
        expect(clashing.targets["one"] == first.id && clashing.context(for: copy.id).takenLabels == ["one"], "a repeated label stays with the first")
        do {
            _ = try NoteMathParser.parseEquation(copy.text.string, display: true, numbering: clashing.context(for: copy.id))
            failTest("the repeated label fails to typeset")
        } catch {
            expect(error.message.contains("already labels an earlier equation"), "the repeat explains itself")
        }
        let context = numbering.context(for: second.id)
        expect(context.fingerprint(for: "\\eqref{one}", display: false) != NoteMathNumberingContext().fingerprint(for: "\\eqref{one}", display: false),
               "reference fingerprints change with the labels")
        expect(context.fingerprint(for: "x^2", display: true).isEmpty, "plain equations don't care about numbering")
        var removed = page
        removed.blocks.removeFirst()
        expect(numberer.numbering(for: removed).references["three"] == [.text("1", .roman)], "removing an equation renumbers the rest")
        let drafted = numberer.numbering(for: page, drafts: [plain.id: "\\begin{equation} y \\label{draft} \\end{equation}"])
        expect(drafted.references["draft"] == [.text("3", .roman)] && drafted.references["three"] == [.text("4", .roman)],
               "an open draft numbers itself and shifts the rest: \(drafted.references)")
        expect(drafted.entries[plain.id]?.labels == ["draft"], "a draft's labels belong to its block")
        expect(numberer.numbering(for: page) == numbering, "dropping the draft brings back the committed numbering")
        exportsNumbersAndLinks()
        print("NoteMathNumberingTests passed")
    }

    static func exportsNumbersAndLinks() {
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
        expect(context(first.text.string)?.firstNumber == 0 && context(second.text.string)?.firstNumber == 2,
               "every exported equation continues the note's numbering")
        expect(context(reference.text.string)?.references["three"] == [.text("3", .roman)], "exported references resolve across equations")
        expect(context("\\eqref{eq:one}")?.references["eq:one"] == [.text("1", .roman)], "inline references resolve too")
        expect(html.contains("<div data-block=\"equation\" id=\"eq-eq-one\"") && html.contains("<span id=\"eq-two\"></span>"),
               "labelled equations carry an anchor per label")
        expect(html.contains("id=\"eq-three-2\""), "equation anchors never collide with heading anchors")
        expect(html.contains("<area shape=\"rect\" coords=\"1,2,12,15\" href=\"#eq-three-2\" alt=\"Equation 3\">"),
               "display references link to their equation")
        expect(html.contains("href=\"#eq-eq-one\" alt=\"Equation 1\""), "inline references link to their equation")
        expect(!html.contains("#missing") && html.contains("usemap=\"#equation-links-"), "only labels that exist become links")
        let fragment = NotePageHTML.fragment(page.blocks)
        expect(fragment.contains("$$" + NotePageHTMLWriter.escape(second.text.string) + "$$") && !fragment.contains("<area"),
               "copied HTML keeps the TeX source")
    }
}
