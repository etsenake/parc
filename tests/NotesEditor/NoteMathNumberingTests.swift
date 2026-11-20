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
        print("NoteMathNumberingTests passed")
    }
}
