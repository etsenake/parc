import Foundation
import Testing
@testable import ParcCore

struct MarkdownCodecTestsEscapingTests {
    typealias SourceCase = MarkdownCodecTestsSupport.SourceCase

    private let hazards = [
        "# not a heading", "> not a quote", "- not a list", "+ nor this", "* nor this", "1. not ordered", "2) nor this",
        "--- not a rule", "***", "___", "===", "---", "```not code", "~~~ nor this", "    four spaces", "\tTab start",
        "trailing space ", "<div>not html</div>", "<!-- not a comment -->", "[link](like) text", "[label]: not a definition",
        "[^1] not a footnote", "![not](image.png)", "*stars* and _underscores_ and ~tildes~", "a * b * c and 2*3*4",
        "snake_case and __dunder__", "`ticks` and ``double``", "x == y and ==not highlight==", "&amp; and &#123; literally",
        "$x$ and $5 and $$ and $a $b$", "https://example.com and www.example.com and me@example.com", "back\\slash and \\* and end\\",
        "| a | b |", ":--|--:", ":::columns", "::: column", "[[not wiki]]", "[ ] not a task", "pipe | in text", "<span>raw?</span>",
        "a\u{2028}# second line", "a\n- second line", "a\u{2028}===", "a\n    indented", "a \nspace before break", "a\n", "\u{2028}lead",
        "ends\u{2028}", "emoji 🎉 and ümlauts", "<https://x.y>", "!", "[", "]", "\\", "*", "_", "#", "|", "$", "&", "<", ">", "`",
    ]

    @Test
    func listChildrenThatLookLikeTableDelimitersRoundTrip() {
        var paintedTask = NoteBlock(.todo, children: [NoteBlock(.bulletedItem, text: "|")])
        paintedTask.color = .text(.red)
        let piped = NoteBlock(.bulletedItem, text: "a | b", children: [NoteBlock(.bulletedItem, text: "|")])
        NoteMarkdownCheck.checkModelRoundTrip(NotePage(blocks: [paintedTask, .paragraph("gap"), piped]), "nested item that would read as a table delimiter row")
    }

    @Test
    func aPageLinkLabelStartingWithItalicsRoundTrips() {
        var italic = NoteMarks()
        italic.italic = true
        var leaning = NoteBlock(.pageLink, text: NoteText("_ @ #", marks: italic) + NoteText("*   "))
        leaning.props.target = "Other.md"
        NoteMarkdownCheck.checkModelRoundTrip(NotePage(blocks: [leaning]), "page link label opening with italics")
    }

    @Test(arguments: [
        SourceCase("inline display math whose second line looks like a list item", "a $$ b\n    + c $$ d\n"),
        SourceCase("inline comment whose second line looks like a heading", "x <!-- a\n    # b --> y\n"),
        SourceCase("empty span in front of block HTML", "<span data-color=\"red\"></span><div> after\n"),
        SourceCase("empty bold in front of display math", "<b></b>$$x$$ after\n"),
        SourceCase("empty wrappers opening a quote and an item", "> <i></i><details> quoted\n\n- <u></u><pre> item\n"),
        SourceCase("empty bold opening a setext heading", "<b></b><div>\n===\n"),
        SourceCase("tab before block HTML inside a quote inside a list", "1.  > \t <details>\n"),
    ])
    func ambiguousInlineMarkupSettlesAfterOneSave(fixture: SourceCase) {
        NoteMarkdownCheck.checkStable(fixture.markdown, fixture.testDescription)
    }

    @Test
    func aMultilineRawAtomCanContainAQuoteLikeLine() {
        NoteMarkdownCheck.checkModelRoundTrip(NotePage(blocks: [.paragraph(NoteText("a ") + .atom(.raw("$$ b\n> c $$")) + NoteText(" d"))]),
                                          "multi-line raw atom with a quote-like line")
    }

    @Test
    func textCanStartWithBlockHTMLWithoutChangingKind() {
        let exposed = [NoteBlock.paragraph(.atom(.raw("<div>")) + NoteText(" x")), NoteBlock(.bulletedItem, text: .atom(.raw("<details>")) + NoteText(" y")),
                       NoteBlock(.quote, text: .atom(.raw("<pre>")) + NoteText(" z"))]
        NoteMarkdownCheck.checkModelRoundTrip(NotePage(blocks: exposed), "text that opens with block HTML in a paragraph, an item and a quote")
    }

    @Test
    func paragraphsKeepLiteralMarkdown() {
        var page = NotePage()
        for hazard in hazards { page.blocks.append(.paragraph(NoteText(hazard))) }
        NoteMarkdownCheck.checkModelRoundTrip(page, "paragraph escaping")
    }

    @Test
    func listItemsKeepLiteralMarkdown() {
        var items = NotePage()
        for hazard in hazards { items.blocks.append(NoteBlock(.bulletedItem, text: NoteText(hazard))) }
        NoteMarkdownCheck.checkModelRoundTrip(items, "list item escaping")
    }

    @Test
    func headingsKeepLiteralMarkdown() {
        var headings = NotePage()
        for hazard in hazards + ["Title #", "C# and F#", "##"] { headings.blocks.append(.heading(2, NoteText(hazard))) }
        NoteMarkdownCheck.checkModelRoundTrip(headings, "heading escaping")
    }

    @Test
    func tableCellsKeepLiteralMarkdown() {
        let cells = hazards.map { NoteText($0) }
        var table = NoteBlock(.table)
        table.props.table = NoteTable(rows: stride(from: 0, to: cells.count, by: 3).map { Array(cells[$0..<min($0 + 3, cells.count)]) })
        NoteMarkdownCheck.checkModelRoundTrip(NotePage(blocks: [table]), "cell escaping")
    }

    @Test
    func toggleSummariesKeepLiteralMarkdown() {
        var toggles = NotePage()
        for hazard in hazards + ["</summary> sneaky", "<summary>"] { toggles.blocks.append(NoteBlock(.toggle, text: NoteText(hazard))) }
        NoteMarkdownCheck.checkModelRoundTrip(toggles, "summary escaping")
    }

    @Test
    func ordinaryProseSavesWithoutEscapes() {
        let clean = NoteMarkdown.serialize(NotePage(blocks: [.paragraph("Plain prose costs $5, uses snake_case, 2 * 3, a-b, (parens), \"quotes\" and C# — no escapes needed.")]))
        #expect(clean == "Plain prose costs $5, uses snake_case, 2 * 3, a-b, (parens), \"quotes\" and C# — no escapes needed.\n", "ordinary prose stays unescaped: \(clean)")
    }
}
