import Foundation
import Testing
@testable import ParcCore

struct MarkdownCodecTests: NoteFixtures {
    func blocks(_ source: String) -> [NoteBlock] { NoteMarkdown.parse(source).blocks }

    func noteCallouts() {
        let plain = NoteBlock(.callout, text: "No icon, no colour")
        let plainText = NoteMarkdown.serialize(NotePage(blocks: [plain]))
        #expect(plainText == "> [!NOTE]\n> No icon, no colour <!-- parc -->\n", "a bare plain callout still carries Parc's comment")
        NoteMarkdownCheck.checkModelRoundTrip(NotePage(blocks: [plain]), "plain callout without icon or colour")
        var plainUnderlined = NoteBlock(.callout, text: NoteText("under", marks: NoteMarks(underline: true)) + NoteText(" lined"))
        plainUnderlined.children = [NoteBlock(.bulletedItem, text: "item")]
        NoteMarkdownCheck.checkModelRoundTrip(NotePage(blocks: [plainUnderlined]), "plain callout opening with inline HTML")
        let plainEmpty = NoteBlock(.callout, children: [NoteBlock(.bulletedItem, text: "item")])
        NoteMarkdownCheck.checkModelRoundTrip(NotePage(blocks: [plainEmpty]), "empty plain callout with a list")
        var plainIcon = NoteBlock(.callout, text: "Lit")
        plainIcon.props.icon = "🔥"
        NoteMarkdownCheck.checkModelRoundTrip(NotePage(blocks: [plainIcon]), "plain callout with an icon")
        var plainFolded = NoteBlock(.callout, text: "Folded", children: [.paragraph("inside")])
        plainFolded.props.toggleable = true
        NoteMarkdownCheck.checkModelRoundTrip(NotePage(blocks: [plainFolded]), "folding plain callout")

        NoteMarkdownCheck.checkExact("> [!NOTE]\n> Useful information.\n", "GitHub NOTE")
        NoteMarkdownCheck.checkExact("> [!NOTE]\n>\n> - only a list\n", "GitHub NOTE without text")
        NoteMarkdownCheck.checkExact("> [!NOTE]\n> Two\\\n> lines\n>\n> Second paragraph.\n", "GitHub NOTE with a body")
        var note = NoteMarkdown.parse("> [!NOTE]\n> Useful information.\n")
        #expect(note.blocks[0].props.alert == "NOTE", "a GitHub NOTE loads as a note alert")
        note.blocks[0].text = NoteText("Edited information.")
        #expect(NoteMarkdown.serialize(note) == "> [!NOTE]\n> Edited information.\n", "editing a GitHub NOTE's text adds no comment")
        note.blocks[0].props.icon = "🌳"
        let restyled = NoteMarkdown.serialize(note)
        #expect(restyled == "> [!NOTE]\n> Edited information. <!-- parc alert icon=\"🌳\" -->\n", "a picked icon is saved with the alert flag")
        NoteMarkdownCheck.checkModelRoundTrip(note, "GitHub NOTE with a picked icon")
        note.blocks[0].props.icon = ""
        note.blocks[0].color = .background(.pink)
        NoteMarkdownCheck.checkModelRoundTrip(note, "GitHub NOTE with its icon removed and a picked colour")
        var anchored = NoteBlock(.callout, text: "Linked")
        anchored.props.alert = "NOTE"
        anchored.props.anchor = "n0te22"
        NoteMarkdownCheck.checkModelRoundTrip(NotePage(blocks: [anchored]), "GitHub NOTE with a block anchor")
        var empty = NoteBlock(.callout)
        empty.props.alert = "NOTE"
        NoteMarkdownCheck.checkModelRoundTrip(NotePage(blocks: [empty, NoteBlock(.callout)]), "empty GitHub NOTE beside an empty plain callout")
    }

    @Test func aLeadingDividerThatCouldOpenFrontMatterIs() {
        var paintedRule = NoteBlock(.divider)
        paintedRule.color = .background(.orange)
        for (label, model) in [("divider pair", [NoteBlock(.divider), .paragraph("between"), NoteBlock(.divider)]),
                               ("divider before dots", [NoteBlock(.divider), .paragraph("...")]),
                               ("painted divider pair", [paintedRule, NoteBlock(.divider)])] {
            let page = NotePage(blocks: model)
            #expect(NoteMarkdown.serialize(page).hasPrefix(" ---\n"), "\(label): a leading divider that could open front matter is indented")
            NoteMarkdownCheck.checkModelRoundTrip(page, label)
        }
    }

    @Test func codeTheWriterMustFenceAfterAListLoads() {
        for (label, text) in [("ticked", "[x]\u{2028}after"), ("open", "[ ]\u{2028}after"), ("vertical tab", "[x]\u{0B}after")] {
            let numbered = NoteBlock(.numberedItem, text: NoteText(text))
            let bulleted = NoteBlock(.bulletedItem, text: NoteText(text))
            NoteMarkdownCheck.checkModelRoundTrip(NotePage(blocks: [numbered, .paragraph("gap"), bulleted]), "task-like text before a break, \(label)")
        }

        NoteMarkdownCheck.checkStable("-\n\n\n    code\n", "indented code after a list and a blank paragraph")
        #expect(blocks("-\n\n\n    code\n").last?.props.fence == nil, "code the writer must fence after a list loads without the indented style")
        NoteMarkdownCheck.checkStable("    code\n<!-- parc color=\"red\" -->\n", "indented code with a Parc comment")
        #expect(blocks("    code\n<!-- parc color=\"red\" -->\n").first?.props.fence == nil, "indented code with settings loads as fenced")
        var unicodeBlank = NoteBlock(.code, text: NoteText("\u{00A0}"))
        unicodeBlank.props.fence = "    "
        NoteMarkdownCheck.checkModelRoundTrip(NotePage(blocks: [unicodeBlank]), "indented code whose only line is a no-break space")
    }

    @Test func definitionsWithAnHTMLBlockContinuationStayOneRaw() {
        NoteMarkdownCheck.checkExact("[r]: /url\n    <details>x\n", "definition continued by a block HTML line")
        #expect(blocks("[r]: /url\n     <details>x\n").map(\.kind) == [.raw], "definitions with an HTML-block continuation stay one raw block")
        NoteMarkdownCheck.checkExact("[r]: /url\n    <div>\n===\n", "definition continued by a setext heading that opens with HTML")
        NoteMarkdownCheck.checkStable("[r]: /url\n$$x$$ y\n", "definition continued by inline display math")
        NoteMarkdownCheck.checkStable("> - [r]: /url\n>       <!-- c --> tail\n", "nested definition continued by a comment")
        NoteMarkdownCheck.checkStable("[r]: /url\ntext\n", "definition followed by an ordinary line")
        #expect(blocks("[r]: /url\ntext\n").map(\.kind) == [.raw, .paragraph], "an ordinary continuation still becomes a paragraph")

        NoteMarkdownCheck.checkStable("> [!tip]- T\n>     <summary>S</summary> x\n", "titled callout continued by block HTML")
        NoteMarkdownCheck.checkStable("> [!TIP] T\n>     <div>x\n", "GitHub alert title continued by block HTML")
        NoteMarkdownCheck.checkStable("> [!TIP] <!-- parc -->\n>     <div>x\n", "empty GitHub alert title continued by block HTML")
        NoteMarkdownCheck.checkStable("> [!NOTE] Hi <!-- parc alert -->\n>     <pre>x\n", "kept GitHub note continued by a pre tag")
        var tipped = NoteBlock(.callout, text: "Title", children: [.paragraph(.atom(.raw("<div>")) + NoteText(" body"))])
        tipped.props.alert = "TIP"
        var plain = NoteBlock(.callout, children: [.paragraph(.atom(.raw("<details>")) + NoteText(" body"))])
        plain.props.icon = "💡"
        var titled = NoteBlock(.callout, text: "Why", children: [.paragraph(.atom(.raw("<summary>")) + NoteText(" body"))])
        titled.props.alert = "faq"
        NoteMarkdownCheck.checkModelRoundTrip(NotePage(blocks: [tipped, plain, titled]), "callouts whose first child opens with block HTML")

        var paintedTask = NoteBlock(.todo, children: [NoteBlock(.bulletedItem, text: "|")])
        paintedTask.color = .text(.red)
        let piped = NoteBlock(.bulletedItem, text: "a | b", children: [NoteBlock(.bulletedItem, text: "|")])
        NoteMarkdownCheck.checkModelRoundTrip(NotePage(blocks: [paintedTask, .paragraph("gap"), piped]), "nested item that would read as a table delimiter row")

        var italic = NoteMarks()
        italic.italic = true
        var leaning = NoteBlock(.pageLink, text: NoteText("_ @ #", marks: italic) + NoteText("*   "))
        leaning.props.target = "Other.md"
        NoteMarkdownCheck.checkModelRoundTrip(NotePage(blocks: [leaning]), "page link label opening with italics")

        NoteMarkdownCheck.checkStable("a $$ b\n    + c $$ d\n", "inline display math whose second line looks like a list item")
        NoteMarkdownCheck.checkStable("x <!-- a\n    # b --> y\n", "inline comment whose second line looks like a heading")
        NoteMarkdownCheck.checkModelRoundTrip(NotePage(blocks: [.paragraph(NoteText("a ") + .atom(.raw("$$ b\n> c $$")) + NoteText(" d"))]),
                                          "multi-line raw atom with a quote-like line")

        NoteMarkdownCheck.checkStable("<span data-color=\"red\"></span><div> after\n", "empty span in front of block HTML")
        NoteMarkdownCheck.checkStable("<b></b>$$x$$ after\n", "empty bold in front of display math")
        NoteMarkdownCheck.checkStable("> <i></i><details> quoted\n\n- <u></u><pre> item\n", "empty wrappers opening a quote and an item")
        NoteMarkdownCheck.checkStable("<b></b><div>\n===\n", "empty bold opening a setext heading")
        let exposed = [NoteBlock.paragraph(.atom(.raw("<div>")) + NoteText(" x")), NoteBlock(.bulletedItem, text: .atom(.raw("<details>")) + NoteText(" y")),
                       NoteBlock(.quote, text: .atom(.raw("<pre>")) + NoteText(" z"))]
        NoteMarkdownCheck.checkModelRoundTrip(NotePage(blocks: exposed), "text that opens with block HTML in a paragraph, an item and a quote")

        NoteMarkdownCheck.checkStable("1.  > \t <details>\n", "tab before block HTML inside a quote inside a list")
    }

    @Test func exactFixtures() {
        let fixtures: [(String, String)] = [
            ("heading levels", "# One\n\n## Two\n\n### Three\n\n#### Four\n\n##### Five\n\n###### Six\n"),
            ("setext headings", "Title\n=====\n\nSubtitle\n--------\n"),
            ("paragraph breaks", "Soft wrapped\nparagraph line\nand a hard break\\\nnext line.\n"),
            ("emphasis", "Some *italic*, **bold**, ***both***, ~~struck~~ and `code` text.\n"),
            ("links", "A [link](https://example.com/a?b=c) and https://example.com, <ftp://files.example.com> and https://bare.example.com/x.\n"),
            ("bullets", "- one\n- two\n  - nested\n  - nested two\n- three\n"),
            ("bullet markers", "* star\n* star two\n\n+ plus\n"),
            ("ordered", "1. first\n2. second\n3. third\n"),
            ("ordered paren start", "3) three\n4) four\n"),
            ("loose list", "- one\n\n- two\n\n- three\n"),
            ("loose list with child", "1. First\n\n   More about first.\n\n2. Second\n"),
            ("tasks", "- [ ] open\n- [x] done\n  - [ ] nested\n"),
            ("quote", "> Quoted text\n> continues\n>\n> Second paragraph\n"),
            ("nested quote", "> Outer\n>\n> > Inner\n"),
            ("fenced code", "```swift\nlet value = 1\nprint(value)\n```\n"),
            ("tilde fence", "~~~python title=\"run.py\"\nprint(\"hi\")\n~~~\n"),
            ("long fence", "````\n```\nnested fence\n```\n````\n"),
            ("indented code", "    let indented = true\n    return indented\n"),
            ("empty code", "```\n```\n"),
            ("thematic breaks", "---\n\n***\n\n___\n\n* * *\n"),
            ("table", "| Name | Count | Note |\n| :--- | :---: | ---: |\n| a    | 1     | x    |\n| b    | 2     |      |\n"),
            ("html block", "<div align=\"center\">\n  <img src=\"logo.png\" width=\"80\">\n</div>\n"),
            ("html comment", "<!-- just a comment -->\n"),
            ("definitions", "Read [the docs][docs] and [faq].\n\n[docs]: https://example.com/docs\n[faq]: https://example.com/faq \"FAQ\"\n"),
            ("footnotes", "A claim.[^1]\n\n[^1]: The source.\n    More detail.\n"),
            ("empty paragraphs", "\nFirst\n\n\nSecond\n\n"),
            ("math block", "$$\n\\int_0^1 x\\,dx\n$$\n"),
            ("math fence", "```math\na^2 + b^2 = c^2\n```\n"),
            ("inline math", "Euler: $e^{i\\pi} + 1 = 0$, costs $5 and $10.\n"),
            ("inline extras", "<u>under</u>, <span data-color=\"red\">red</span>, <mark data-color=\"blue_background\">blue</mark> and ==marked==.\n"),
            ("block color", "Painted paragraph <!-- parc color=\"purple_background\" -->\n\n## Heading <!-- parc color=\"red\" -->\n\n- item <!-- parc color=\"green\" -->\n"),
            ("divider color", "---\n<!-- parc color=\"gray\" -->\n"),
            ("toc", "<!-- toc -->\n\n# Intro\n"),
            ("callout github", "> [!TIP]\n> Try the shortcut. <!-- parc icon=\"💡\" color=\"yellow_background\" -->\n"),
            ("callout obsidian", "> [!faq]- Why markdown?\n> Because files outlive apps.\n"),
            ("callout github note", "> [!NOTE]\n> Useful note.\n>\n> - with a list\n"),
            ("callout plain", "> [!NOTE]\n> Plain callout. <!-- parc -->\n>\n> - with a list\n"),
            ("toggle", "<details open>\n<summary>Open toggle</summary>\n\nInside.\n\n</details>\n"),
            ("toggle closed empty", "<details>\n<summary>Nothing here</summary>\n</details>\n"),
            ("toggle heading", "<details>\n<summary><h2>Section</h2></summary>\n\n- child\n\n</details>\n"),
            ("nested toggles", "<details open>\n<summary>Outer</summary>\n\n<details>\n<summary>Inner</summary>\n\nDeep.\n\n</details>\n\n</details>\n"),
            ("columns", ":::: columns\n::: column\nLeft side\n:::\n::: {.column width=\"40%\"}\nRight side\n\n- with a list\n:::\n::::\n"),
            ("indented text", "Parent paragraph\n\n::: indent\nA child\n\n- and a list\n:::\n\n## Heading <!-- parc color=\"red\" -->\n\n:::: indent\nUnder the heading\n\n::: indent\nDeeper\n:::\n::::\n\nAfter\n"),
            ("indented empty parent", "<!-- parc paragraph -->\n\n::: indent\nOnly the child\n:::\n"),
            ("indent in a list", "- item\n\n  Text\n\n  ::: indent\n  nested\n  :::\n- next\n"),
            ("indent around columns", "Lead\n\n:::::: indent\n::::: columns\n:::: column\nLeft\n\n::: indent\nkid\n:::\n::::\n:::: column\nRight\n::::\n:::::\n::::::\n"),
            ("image", "![A cat](Attachments/cat.png \"A *cute* cat\") <!-- parc width=\"320\" align=\"left\" -->\n"),
            ("video audio file", "![](Attachments/clip.mp4)\n\n![](Attachments/song.mp3)\n\n![report.pdf](Attachments/report.pdf)\n"),
            ("embed", "![](https://www.youtube.com/watch?v=dQw4w9WgXcQ)\n\n![](https://example.com/widget) <!-- parc embed -->\n"),
            ("bookmark", "[The Verge](https://www.theverge.com) <!-- parc bookmark summary=\"Tech news\" site=\"The Verge\" thumbnail=\"https://example.com/t.png\" -->\n"),
            ("bare bookmark", "<https://example.com> <!-- parc bookmark -->\n"),
            ("page link", "[Project plan](Project%20plan.md)\n\n[Elsewhere](../Other/Notes.md) <!-- parc color=\"blue\" -->\n"),
            ("mentions", "Ask [[Ada Lovelace]] or [[People/Grace|Grace]] about [Roadmap](Roadmap.md) by <time datetime=\"2026-11-20T09:30\" data-remind>2026-11-20 09:30</time>.\n"),
            ("link mention", "Saw <a href=\"https://example.com\" data-mention>Example Domain</a> today.\n"),
            ("raw inline", "Press <kbd>⌘</kbd> + <kbd>K</kbd>, see ![icon](icon.png) and H<sub>2</sub>O.\n"),
            ("escapes", "Literal \\*stars*, \\_under_, # hash, 1. not a list, \\[not a link](x), a \\`tick\\` and a \\ backslash, \\\\* too.\n"),
            ("entities", "Fish &amp; chips &copy; 2026 &#x1F600; &nbsp;space.\n"),
            ("empty items", "-\n- [ ]\n-\n"),
            ("ordered restart", "1. one\n2. two\n\n<!-- -->\n\n1. again\n"),
        ]
        for (label, source) in fixtures where label != "entities" && label != "escapes" {
            NoteMarkdownCheck.checkExact(source, label)
        }
        NoteMarkdownCheck.checkStable(fixtures.first { $0.0 == "entities" }!.1, "entities")
        NoteMarkdownCheck.checkExact(fixtures.first { $0.0 == "escapes" }!.1, "escapes")
        NoteMarkdownCheck.checkStable("Angle <https://example.com> and <me@example.com> links.\n", "angle autolinks")
    }

    @Test func atxHeadingsNeedASpaceAndAtMostSix() {
        let headings = blocks("# A #\n\n## B ##\n\n####### not\n\n#5 not\n")
        #expect(headings.map(\.kind) == [.heading, .heading, .paragraph, .paragraph], "ATX headings need a space and at most six marks")
        #expect(headings[0].text.string == "A" && headings[1].props.level == 2, "closing hashes are dropped")

        let setext = blocks("Multi\nline title\n---\n")
        #expect(setext.count == 1 && setext[0].kind == .heading && setext[0].props.level == 2 && setext[0].text.string == "Multi\u{2028}line title", "setext headings take every paragraph line")
    }

    @Test func twoSpacesAndBackslashAreHardBreaksANewline() {
        let breaks = blocks("a  \nb\\\nc\nd\n")
        #expect(breaks[0].text.string == "a\nb\nc\u{2028}d", "two spaces and backslash are hard breaks, a newline is soft")
    }

    @Test func onlyBlankLinesBetweenItemsMarkAListLoose() {
        let lists = blocks("- a\n- b\n\n  c\n- d\n")
        #expect(lists.count == 3 && !lists.contains { $0.props.looseList }, "only blank lines between items mark a list loose")
        #expect(blocks("- a\n\n- b\n").allSatisfy { $0.props.looseList }, "a gap between items marks the list loose")
        #expect(lists[1].children.first?.text.string == "c", "a continuation paragraph becomes a child")
    }

    @Test func lazyContinuationLinesJoinTheParagraph() {
        let lazy = blocks("> lazy\ncontinuation\n\n- item\nlazy line\n")
        #expect(lazy[0].text.string == "lazy\u{2028}continuation" && lazy[1].text.string == "item\u{2028}lazy line", "lazy continuation lines join the paragraph")
    }

    @Test func startNumbersStayOnTheFirstItem() {
        let numbered = blocks("7. seven\n8. eight\n")
        #expect(numbered[0].props.listStart == 7 && numbered[1].props.listStart == nil, "start numbers stay on the first item")
    }

    @Test func onlyAListStartingAt1CanInterruptA() {
        let interrupt = blocks("text\n2. not a list\n")
        #expect(interrupt.count == 1 && interrupt[0].kind == .paragraph, "only a list starting at 1 can interrupt a paragraph")
    }

    @Test func changingTheMarkerStartsANewListAndKeeps() {
        let markers = blocks("- a\n+ b\n* c\n")
        #expect(markers.map(\.props.bulletMarker) == [nil, "+", "*"], "changing the marker starts a new list and keeps the marker")
    }

    @Test func orderedItemsAfterTheFirstFollowOn() {
        let ordered = blocks("1. a\n1. b\n1. c\n")
        #expect(ordered.map(\.props.listStart) == [nil, nil, nil], "ordered items after the first follow on")

        let task = blocks("1. [x] ordered task\n")
        #expect(task[0].kind == .todo && task[0].props.checked && task[0].props.orderedDelimiter == ".", "ordered task items stay ordered")
    }

    @Test func infoStringsKeepTheLanguageAndTheRest() {
        let code = blocks("```js title=\"app.js\"\nx\n```\n")
        #expect(code[0].props.language == "js" && code[0].props.info == "title=\"app.js\"", "info strings keep the language and the rest")

        let unclosed = blocks("```\nnever closed\n\nstill code\n")
        #expect(unclosed.count == 1 && unclosed[0].text.string == "never closed\n\nstill code", "an unclosed fence runs to the end")

        let indented = blocks("    a\n\n    b\n\n\nafter\n")
        #expect(indented[0].kind == .code && indented[0].text.string == "a\n\nb", "indented code keeps inner blank lines and drops trailing ones")

        let tabs = blocks("-\tone\n\n>\tquoted\n")
        #expect(tabs[0].text.string == "one" && tabs[1].text.string == "quoted", "tabs count as indentation")

        let table = blocks("| a | b |\n|---|:-:|\n| 1 | 2 | 3 |\n| only |\n")
        let model = table[0].props.table!
        #expect(model.rows == [["a", "b"], ["1", "2"], ["only", ""]], "extra cells are dropped and short rows padded")
        #expect(model.alignments == [nil, .center], "alignment comes from the delimiter row")

        let pipes = blocks("| `a\\|b` | c \\| d |\n| --- | --- |\n")
        #expect(pipes[0].props.table!.rows[0].map(\.string) == ["a|b", "c | d"], "escaped pipes stay inside cells, even in code")

        let notTable = blocks("a | b\n-- | -- | --\n")
        #expect(notTable[0].kind == .paragraph, "the delimiter row must match the header")

        let html = blocks("<div>\n*not emphasis*\n</div>\n\n*emphasis*\n")
        #expect(html[0].kind == .html && html[0].text.string == "<div>\n*not emphasis*\n</div>" && html[1].kind == .paragraph, "HTML blocks end at a blank line")

        let script = blocks("<script>\nlet a = 1\n\nlet b = 2\n</script>\nafter\n")
        #expect(script[0].kind == .html && script[0].text.string.hasSuffix("</script>") && script[1].text.string == "after", "script blocks run to their closing tag")

        let references = blocks("[Ref]: /url\n\n[ref]\n")
        #expect(references[0].kind == .raw && references[1].text.marks(at: 0).link == "/url", "references resolve case-insensitively")

        let entityInCode = blocks("`&amp;` and \\`x\\`\n")
        #expect(entityInCode[0].text.string == "&amp; and `x`", "code spans keep entities literally")
    }

    @Test func aBackslashAtTheEndOfABlockStays() {
        let problems = onLargeStack {
            let deep = NoteMarkdown.parse(String(repeating: "> ", count: 5000) + "deep\n" + String(repeating: "*a ", count: 3000) + String(repeating: "b* ", count: 3000) + "\n")
            return NoteMarkdownCheck.stableProblems(NoteMarkdown.serialize(deep), "deep nesting")
        }
        for problem in problems { Issue.record(Comment(rawValue: problem)) }
        let breakAtEnd = blocks("ends with backslash\\\n")
        #expect(breakAtEnd[0].text.string == "ends with backslash\\", "a backslash at the end of a block stays literal")
    }

    @Test func emphasisNests() {
        func text(_ source: String) -> NoteText { blocks(source)[0].text }
        let nested = text("**bold *both* bold**")
        #expect(nested.string == "bold both bold" && nested.marks(at: 0).bold && nested.marks(at: 5).italic && nested.marks(at: 5).bold, "emphasis nests")
        let intraword = text("snake_case_name and a*b*c")
        #expect(intraword.string == "snake_case_name and abc" && intraword.marks(at: 21).italic, "underscores stay literal inside words, stars do not")
        let ruleOfThree = text("*foo**bar**baz*")
        #expect(ruleOfThree.string == "foobarbaz" && ruleOfThree.marks(at: 4).bold && ruleOfThree.marks(at: 4).italic, "the rule of three keeps nesting right")
        let unmatched = text("**open and *close")
        #expect(unmatched.string == "**open and *close", "unmatched delimiters stay text")
        let strike = text("~one~ ~~two~~ ~~~three~~~")
        #expect(strike.marks(at: 0).strikethrough && strike.marks(at: 4).strikethrough && !strike.marks(at: 12).strikethrough, "one or two tildes strike, three do not")
        let codeSpan = text("`` a ` b `` and ` x `")
        #expect(codeSpan.string == "a ` b and x", "code spans strip one padding space")
        let link = text("[a *b*](</my url> 'title') [c](d)")
        #expect(link.marks(at: 0).atom != nil, "titled links stay raw so the title survives")
        #expect(link.marks(at: link.length - 1).link == "d", "plain links become link marks")
        let angle = text("[x](<a b>)")
        #expect(angle.marks(at: 0).link == "a b", "angle destinations keep spaces")
        let autolinks = text("<mailto:a@b.c> <a@b.co> www.example.com/path. https://x.org/a_(b) and foo@bar.baz.")
        let marks = (0..<autolinks.length).compactMap { autolinks.marks(at: $0).link }
        #expect(marks.contains("mailto:a@b.co") && marks.contains("http://www.example.com/path") && marks.contains("https://x.org/a_(b)") && marks.contains("mailto:foo@bar.baz"), "angle autolinks, www, URLs and emails all link: \(Set(marks))")
        let trailing = text("Visit https://example.com/page).")
        #expect((0..<trailing.length).compactMap { trailing.marks(at: $0).link }.allSatisfy { $0 == "https://example.com/page" }, "trailing punctuation is left out")
        let html = text("a <span data-color=\"red\">red <b>bold</b></span> <mark>hi</mark> <ins>in</ins> <a href=\"https://x.y\">x</a>")
        let redIndex = (html.string as NSString).range(of: "red").location
        let boldIndex = (html.string as NSString).range(of: "bold").location
        #expect(html.marks(at: redIndex).color == .text(.red) && html.marks(at: boldIndex).bold && html.marks(at: boldIndex).color == .text(.red), "paired inline HTML becomes marks")
        #expect(html.marks(at: (html.string as NSString).range(of: "hi").location).color == .background(.yellow), "a bare mark is a yellow highlight")
        #expect(html.marks(at: (html.string as NSString).range(of: "in").location).underline, "ins underlines")
        #expect(html.marks(at: html.length - 1).link == "https://x.y", "anchor tags with only href are links")
        let unpaired = text("x <b>never closed and <span class=\"k\">kept</span>")
        #expect(unpaired.marks(at: 2).atom == .raw("<b>") && !unpaired.marks(at: 5).bold, "unpaired tags stay raw")
        let spanAtoms = (0..<unpaired.length).compactMap { unpaired.marks(at: $0).atom }
        #expect(spanAtoms.contains(.raw("<span class=\"k\">")) && spanAtoms.contains(.raw("</span>")), "unknown spans stay raw on both ends")
        let math = text("$a$ $ b$ $c $ costs $5 and $6 today. \\$e and $y$")
        #expect(!(0..<text("$x$5").length).contains { text("$x$5").marks(at: $0).atom != nil }, "a digit after the closing dollar cancels math")
        let atoms = (0..<math.length).compactMap { math.marks(at: $0).atom }
        #expect(atoms == [.equation("a"), .equation("y")], "inline math needs tight dollars and no digit after: \(atoms)")
        let display = text("Area: $$\\pi r^2$$ done")
        #expect(display.marks(at: 6).atom == .raw("$$\\pi r^2$$"), "inline display math is kept verbatim")
        let wiki = text("[[Note]] [[Folder/Note#Part|Alias]] [[ ]]")
        #expect(wiki.marks(at: 0).atom == .page(target: "Note", title: "Note")
               && wiki.marks(at: 2).atom == .page(target: "Folder/Note#Part", title: "Alias"), "wiki links become page mentions")
        let relative = text("[Plan](Plan.md) and [the plan](Plan.md)")
        #expect(relative.marks(at: 0).atom == .page(target: "Plan.md", title: "Plan") && relative.marks(at: relative.length - 1).link == "Plan.md", "a relative link named after its note is a mention, other text stays a link")
        let date = text("<time datetime=\"2026-01-02\">soon</time> <time datetime=\"bad\">x</time>")
        #expect(date.marks(at: 0).atom == .date(NoteDateMention(year: 2026, month: 1, day: 2)), "time tags become date mentions")
        #expect(date.marks(at: 2).atom == .raw("<time datetime=\"bad\">"), "invalid dates stay raw")
    }

    @Test func iconAndCoverLoad() {
        let source = """
        ---
        icon: 🍎
        cover: "https://example.com/cover.jpg"
        cover-position: 0.25
        font: mono
        small-text: true
        full-width: true
        locked: false
        title: Weekly review
        tags: [work, "deep focus"]
        aliases:
          - Review
          - "2026: week 47"
        rating: 4.5
        due: 2026-11-27
        done: true
        version: "1.0"
        empty:
        meta:
          owner: ada
        # a comment
        script: |
          multi
          line
        ---
        Body text.

        """
        let page = NoteMarkdown.parse(source)
        let settings = page.settings
        #expect(settings.icon == "🍎" && settings.cover == NoteCover(source: "https://example.com/cover.jpg", position: 0.25), "icon and cover load")
        #expect(settings.font == .mono && settings.smallText && settings.fullWidth && !settings.locked, "page switches load")
        let properties = Dictionary(uniqueKeysWithValues: settings.properties.map { ($0.key, $0.value) })
        #expect(properties["title"] == .text("Weekly review") && properties["tags"] == .list(["work", "deep focus"])
               && properties["aliases"] == .list(["Review", "2026: week 47"]) && properties["rating"] == .number(4.5)
               && properties["due"] == .date("2026-11-27") && properties["done"] == .checkbox(true) && properties["version"] == .text("1.0")
               && properties["empty"] == .text("") && properties["locked"] == .checkbox(false), "simple keys become properties: \(settings.properties)")
        #expect(settings.preservedFrontMatter == ["meta:\n  owner: ada", "# a comment", "script: |\n  multi\n  line"], "complex YAML is kept verbatim: \(settings.preservedFrontMatter)")
        #expect(page.blocks.count == 1 && page.blocks[0].text.string == "Body text.", "the body follows the front matter")
        NoteMarkdownCheck.checkModelRoundTrip(page, "front matter")
        NoteMarkdownCheck.checkStable(source, "front matter")
    }

    @Test func unclosedFrontMatterIsAThematicBreak() {
        var custom = NotePage(blocks: [.paragraph("x")])
        custom.settings.icon = "-"
        custom.settings.properties = [
            NotePageProperty(key: "quoted", value: .text("true")), NotePageProperty(key: "number text", value: .text("42")),
            NotePageProperty(key: "colon", value: .text("a: b")), NotePageProperty(key: "hash", value: .text("a #b")),
            NotePageProperty(key: "list", value: .list(["1", "null", "", "- x", "[y]"])), NotePageProperty(key: "weird key: yes", value: .number(-3)),
            NotePageProperty(key: "multi", value: .text("line\nbreak")), NotePageProperty(key: "blank list", value: .list([])),
            NotePageProperty(key: "when", value: .date("2026-11-20T10:00")),
        ]
        NoteMarkdownCheck.checkModelRoundTrip(custom, "YAML quoting")

        let notFrontMatter = NoteMarkdown.parse("---\nnot closed\n")
        #expect(notFrontMatter.settings.isDefault && notFrontMatter.blocks.first?.kind == .divider, "unclosed front matter is a thematic break")
        NoteMarkdownCheck.checkExact("---\nicon: 📓\n---\n\n# Journal\n", "icon only")
        #expect(NoteMarkdown.parse("\u{FEFF}---\nicon: 📓\n---\nHi\n").settings.icon == "📓", "a byte-order mark doesn't hide front matter")
    }

    @Test func gitHubAlertsBecomeCallouts() {
        let alert = blocks("> [!WARNING]\n> Watch out.\n>\n> Second.\n")[0]
        #expect(alert.kind == .callout && alert.props.alert == "WARNING" && alert.text.string == "Watch out." && alert.children.count == 1, "GitHub alerts become callouts")
        let note = blocks("> [!NOTE]\n> Hi\n")[0]
        #expect(note.props.alert == "NOTE" && note.props.icon == nil && note.color == nil, "a hand-written GitHub NOTE is a note alert")
        let plain = blocks("> [!NOTE]\n> Hi <!-- parc -->\n")[0]
        #expect(plain.props.alert == nil && plain.text.string == "Hi" && plain.props.icon == nil, "Parc's comment marks a plain callout")
        let iconic = blocks("> [!NOTE]\n> Hi <!-- parc icon=\"🔥\" -->\n")[0]
        #expect(iconic.props.alert == nil && iconic.props.icon == "🔥", "a plain callout's icon comment keeps it plain")
        let kept = blocks("> [!NOTE]\n> Hi <!-- parc alert icon=\"🌳\" -->\n")[0]
        #expect(kept.props.alert == "NOTE" && kept.props.icon == "🌳", "the alert flag keeps a restyled GitHub NOTE a note")
        let obsidian = blocks("> [!tip]+ Title here\n> Body line\n")[0]
        #expect(obsidian.props.alert == "tip" && obsidian.props.toggleable && obsidian.props.expanded && obsidian.text.string == "Title here"
               && obsidian.children.first?.text.string == "Body line", "Obsidian titles and folds load")
        let empty = blocks("> [!NOTE]\n> <!-- parc icon=\"🔥\" -->\n>\n> Child paragraph.\n")[0]
        #expect(empty.text.isEmpty && empty.props.icon == "🔥" && empty.children.count == 1, "an attribute line marks empty callout text")
        let quote = blocks("> Not [!NOTE] a callout\n")[0]
        #expect(quote.kind == .quote, "the marker must open the quote")

        var callout = NoteBlock(.callout, text: "Body *text*", children: [.paragraph("child"), NoteBlock(.bulletedItem, text: "item")])
        callout.props.icon = "💡"
        callout.color = .background(.gray)
        NoteMarkdownCheck.checkModelRoundTrip(NotePage(blocks: [callout]), "default callout")
        callout.props.alert = "abstract"
        callout.props.toggleable = true
        callout.props.expanded = false
        NoteMarkdownCheck.checkModelRoundTrip(NotePage(blocks: [callout]), "titled callout")
        callout.text = NoteText()
        NoteMarkdownCheck.checkModelRoundTrip(NotePage(blocks: [callout]), "titled callout without title")
        callout.props.alert = "IMPORTANT"
        NoteMarkdownCheck.checkModelRoundTrip(NotePage(blocks: [callout]), "empty alert text")
        let bare = NoteBlock(.quote, children: [.paragraph("first child")])
        NoteMarkdownCheck.checkModelRoundTrip(NotePage(blocks: [bare, NoteBlock(.quote), NoteBlock(.callout)]), "empty quotes")
        noteCallouts()
    }

    @Test func detailsBecomeToggles() {
        let toggles = blocks("<details>\n<summary>Closed **bold**</summary>\n\n\nAfter a blank.\n\n</details>\n")
        #expect(toggles.count == 1 && toggles[0].kind == .toggle && !toggles[0].props.expanded && toggles[0].text.marks(at: 8).bold, "details become toggles")
        #expect(toggles[0].children.map(\.kind) == [.paragraph, .paragraph] && toggles[0].children[0].text.isEmpty, "extra blank lines are empty blocks")
        let unmatched = blocks("<details>\n<summary>x</summary>\n\nno close\n")
        #expect(unmatched[0].kind == .html && unmatched[1].kind == .paragraph, "an unclosed details stays HTML")
        let rawDetails = blocks("<details>\n<summary>x</summary>\nraw body\n</details>\n")
        #expect(rawDetails.count == 1 && rawDetails[0].kind == .html, "details with raw HTML inside stay verbatim")

        var heading = NoteBlock.heading(3, "Toggle heading")
        heading.props.toggleable = true
        heading.props.expanded = false
        heading.children = [.paragraph("hidden"), .paragraph()]
        var toggle = NoteBlock(.toggle, text: "Empty child", children: [.paragraph()])
        toggle.color = .text(.orange)
        NoteMarkdownCheck.checkModelRoundTrip(NotePage(blocks: [heading, toggle, NoteBlock(.toggle)]), "toggles")
    }

    @Test func looseBlocksGetTheirOwnColumn() {
        let columns = blocks("::: {.columns}\nloose\n\n::: column\ninside\n:::\n:::\n")[0]
        #expect(columns.kind == .columns && columns.children.count == 2 && columns.children.allSatisfy { $0.kind == .column }, "loose blocks get their own column")
        let indented = blocks("Para\n\n::: indent\nkid\n:::\n\n# Head\n::: {.indent}\nunder\n:::\n")
        #expect(indented.count == 2 && indented[0].children.map(\.text.string) == ["kid"] && indented[1].children.map(\.text.string) == ["under"], "an indent fence nests under the block before it")
        let orphan = blocks("::: indent\nalone\n:::\n\n---\n\n::: indent\nafter rule\n:::\n")
        #expect(orphan.map(\.kind) == [.paragraph, .divider, .paragraph] && orphan[0].text.isEmpty && orphan[2].children.first?.text.string == "after rule", "an indent with nothing to hold it gets an empty line as its parent")
        let listed = blocks("- item\n\n::: indent\nkid\n:::\n")
        #expect(listed.count == 1 && listed[0].children.first?.text.string == "kid", "an indent after a list item nests in the item")
        NoteMarkdownCheck.checkModelRoundTrip(NotePage(blocks: [NoteBlock(.paragraph, text: ":::", children: [.paragraph(":::"), .paragraph("::: indent")]),
                                                            .paragraph("::: indent")]), "colons inside indents")
        let unknown = blocks(":::tip\nDocusaurus\n:::\n")
        #expect(unknown.count == 1 && unknown[0].kind == .paragraph, "unknown directives stay text")
        let fenced = blocks("::: column\n```\n:::\n```\n:::\n")[0]
        #expect(fenced.children.first?.children.first?.text.string == ":::", "a fence inside a column keeps its colons")

        var left = NoteBlock(.column, children: [.paragraph("left"), NoteBlock(.columns, children: [NoteBlock(.column, children: [.paragraph("deep")])])])
        left.props.width = 1.0 / 3.0
        let right = NoteBlock(.column, children: [.paragraph(), .paragraph("after empty")])
        var grid = NoteBlock(.columns, children: [left, right])
        grid.color = .background(.blue)
        NoteMarkdownCheck.checkModelRoundTrip(NotePage(blocks: [grid]), "columns")
    }

    @Test func mediaAndLinks() {
        let media = blocks("![](a.png)\n\n![](b.MOV)\n\n![](c.flac)\n\n![](d.zip)\n\n![](https://youtu.be/x)\n\n![](https://cdn.example.com/photo?id=1)\n\n![x](a.png) <!-- parc paragraph -->\n")
        #expect(media.map(\.kind) == [.image, .video, .audio, .file, .embed, .image, .paragraph], "media kind follows the extension: \(media.map(\.kind))")

        var image = NoteBlock(.image)
        image.props.source = "Attachments/My Photo (1).png"
        image.props.alt = "A [bracketed] *alt*"
        image.props.caption = NoteText(pieces: [("Caption with ", .plain), ("bold", { var m = NoteMarks(); m.bold = true; return m }()), (" and \"quotes\" & \\ slashes", .plain)])
        image.props.width = 412.5
        image.props.alignment = .right
        var video = NoteBlock(.video)
        video.props.source = "https://example.com/stream"
        var file = NoteBlock(.file)
        file.props.source = "Attachments/archive.tar.gz"
        file.props.alt = "archive.tar.gz"
        var embed = NoteBlock(.embed)
        embed.props.source = "https://www.figma.com/file/abc"
        var bookmark = NoteBlock(.bookmark)
        bookmark.props.source = "https://example.com/article"
        bookmark.props.bookmark = NoteBookmark(title: "An *article* [title]", summary: "Summary with \"quotes\" and --> arrows", siteName: "Example",
                                               iconURL: "https://example.com/favicon.ico", imageURL: "https://example.com/og.png")
        bookmark.props.caption = "My caption"
        var untitled = NoteBlock(.bookmark)
        untitled.props.source = "https://example.com/plain"
        untitled.props.bookmark = NoteBookmark()
        untitled.props.caption = "caption without title"
        var pageLink = NoteBlock(.pageLink, text: "Meeting *notes*")
        pageLink.props.target = "Meetings/2026-11-20%20Standup.md"
        let linkParagraph = NoteBlock.paragraph(NoteText("Just a link", marks: { var m = NoteMarks(); m.link = "Other.md"; return m }()))
        let mentionParagraph = NoteBlock.paragraph(.atom(.page(target: "Other.md", title: "Other")))
        let imageParagraph = NoteBlock.paragraph(.atom(.raw("![x](y.png)")))
        NoteMarkdownCheck.checkModelRoundTrip(NotePage(blocks: [image, video, file, embed, bookmark, untitled, pageLink, linkParagraph, mentionParagraph, imageParagraph]), "media and links")
    }

    @Test func mentionsAndRaw() {
        var mentions = NoteText("Talk to ")
        mentions.append(.atom(.page(target: "People/Ada Lovelace.md", title: "Ada Lovelace")))
        mentions.append(NoteText(" and "))
        mentions.append(.atom(.page(target: "Grace", title: "Admiral Hopper")))
        mentions.append(NoteText(" on "))
        mentions.append(.atom(.date(NoteDateMention(year: 2026, month: 12, day: 1, hour: 14, minute: 5, remind: true))))
        mentions.append(NoteText(", read "))
        mentions.append(.atom(.link(url: "https://example.com/a?b=1&c=2", title: "Example *site* [1]")))
        mentions.append(NoteText(", solve "))
        mentions.append(.atom(.equation("x_1 + y^2")))
        mentions.append(NoteText(" and "))
        mentions.append(.atom(.equation("$ odd \\")))
        mentions.append(NoteText("5 then "))
        mentions.append(.atom(.raw("<kbd>")))
        mentions.append(NoteText("K"))
        mentions.append(.atom(.raw("</kbd>")))
        NoteMarkdownCheck.checkModelRoundTrip(NotePage(blocks: [.paragraph(mentions)]), "mentions")
    }

    @Test func ordinaryProseStaysUnescaped() {
        let hazards = [
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
        var page = NotePage()
        for hazard in hazards { page.blocks.append(.paragraph(NoteText(hazard))) }
        NoteMarkdownCheck.checkModelRoundTrip(page, "paragraph escaping")
        var items = NotePage()
        for hazard in hazards { items.blocks.append(NoteBlock(.bulletedItem, text: NoteText(hazard))) }
        NoteMarkdownCheck.checkModelRoundTrip(items, "list item escaping")
        var headings = NotePage()
        for hazard in hazards + ["Title #", "C# and F#", "##"] { headings.blocks.append(.heading(2, NoteText(hazard))) }
        NoteMarkdownCheck.checkModelRoundTrip(headings, "heading escaping")
        let cells = hazards.map { NoteText($0) }
        var table = NoteBlock(.table)
        table.props.table = NoteTable(rows: stride(from: 0, to: cells.count, by: 3).map { Array(cells[$0..<min($0 + 3, cells.count)]) })
        NoteMarkdownCheck.checkModelRoundTrip(NotePage(blocks: [table]), "cell escaping")
        var toggles = NotePage()
        for hazard in hazards + ["</summary> sneaky", "<summary>"] { toggles.blocks.append(NoteBlock(.toggle, text: NoteText(hazard))) }
        NoteMarkdownCheck.checkModelRoundTrip(toggles, "summary escaping")
        let clean = NoteMarkdown.serialize(NotePage(blocks: [.paragraph("Plain prose costs $5, uses snake_case, 2 * 3, a-b, (parens), \"quotes\" and C# — no escapes needed.")]))
        #expect(clean == "Plain prose costs $5, uses snake_case, 2 * 3, a-b, (parens), \"quotes\" and C# — no escapes needed.\n", "ordinary prose stays unescaped: \(clean)")
    }

    @Test func oneParagraphPerLine() {
        let source = "first line\n\n  indented # not markdown *at all*\nlast"
        let page = NotePlainText.parse(source)
        #expect(page.blocks.count == 4 && page.blocks.allSatisfy { $0.kind == .paragraph }, "one paragraph per line")
        #expect(NotePlainText.serialize(page) == source, "plain text saves verbatim")
        #expect(NotePlainText.serialize(NotePlainText.parse("trailing\n")) == "trailing\n", "a trailing newline survives")
        #expect(NotePlainText.serialize(NotePlainText.parse("")) == "", "an empty file stays empty")
    }

    @Test func theAnchorReadsBackAndStaysOutOfThe() {
        let fixtures: [(String, String)] = [
            ("anchored paragraph", "Hello there <!-- parc id=\"k3x9qa\" -->\n"),
            ("anchored heading keeps its slug text", "## Plan <!-- parc id=\"p1an2x\" -->\n"),
            ("anchored setext heading", "Title <!-- parc id=\"t1tle2\" -->\n===============================\n"),
            ("anchor beside a colour", "- Milk <!-- parc color=\"red\" id=\"m1lk22\" -->\n"),
            ("anchored empty item", "- <!-- parc id=\"emp7y2\" -->\n"),
            ("anchored task", "- [x] Done <!-- parc id=\"d0ne22\" -->\n"),
            ("anchored empty paragraph", "<!-- parc paragraph id=\"blank2\" -->\n"),
            ("anchored code", "```swift\nlet x = 1\n```\n<!-- parc id=\"c0de42\" -->\n"),
            ("anchored divider", "---\n<!-- parc id=\"d4v4de\" -->\n"),
            ("anchored equation", "$$\nx^2\n$$\n<!-- parc id=\"eq2222\" -->\n"),
            ("anchored table", "| A   | B   |\n| --- | --- |\n| 1   | 2   |\n<!-- parc id=\"tab1e2\" -->\n"),
            ("anchored image", "![Cat](cat.png) <!-- parc id=\"cat234\" -->\n"),
            ("anchored page link", "[Other](Other.md) <!-- parc id=\"pag3li\" -->\n"),
            ("anchored quote", "> Wise words <!-- parc id=\"qu0te2\" -->\n"),
            ("anchored toggle", "<details open>\n<summary>More <!-- parc id=\"t0ggle\" --></summary>\n\nInside\n\n</details>\n"),
            ("anchored toc", "<!-- toc -->\n<!-- parc id=\"t0c222\" -->\n"),
        ]
        for (label, source) in fixtures { NoteMarkdownCheck.checkExact(source, label) }

        let page = NoteMarkdown.parse("## Plan <!-- parc id=\"p1an2x\" -->\n\nBody <!-- parc id=\"bad value\" -->\n\nPlain\n")
        #expect(page.blocks[0].props.anchor == "p1an2x" && page.blocks[0].text.string == "Plan", "the anchor reads back and stays out of the heading text")
        #expect(page.blocks.count == 3 && page.blocks[1].props.anchor == nil, "an anchor with spaces is ignored")
        #expect(page.blocks[2].props.anchor == nil, "unanchored blocks stay unanchored")
    }

    @Test func anchoredIndentedCodeSwitchesToAFenceSoThe() {
        var callout = NoteBlock(.callout, text: NoteText("Careful"))
        callout.props.icon = "⚠️"
        callout.props.anchor = "ca11ou"
        var item = NoteBlock(.bulletedItem, text: NoteText(""))
        item.props.anchor = "it3m22"
        var child = NoteBlock(.bulletedItem, text: NoteText(""))
        child.props.anchor = "ch1ld2"
        item.children = [child]
        var columns = NoteBlock(.columns, children: [NoteBlock(.column, children: [.paragraph("Left")]), NoteBlock(.column, children: [.paragraph("Right")])])
        columns.props.anchor = "c0lumn"
        var lead = NoteBlock.paragraph("Lead")
        lead.props.anchor = "lead22"
        var custom = NoteBlock(.callout, text: NoteText("Title"), children: [lead])
        custom.props.alert = "faq"
        var toggleHeading = NoteBlock.heading(3, "Fold")
        toggleHeading.props.toggleable = true
        toggleHeading.props.anchor = "f0ld22"
        var fenced = NoteBlock(.code, text: NoteText("indented"))
        fenced.props.fence = "    "
        fenced.props.anchor = "f3nce2"
        var anchoredOnly = NoteBlock.paragraph()
        anchoredOnly.props.anchor = "trail2"
        let model = NotePage(blocks: [callout, item, columns, custom, toggleHeading, anchoredOnly])
        NoteMarkdownCheck.checkModelRoundTrip(model, "anchors on callouts, nested items, columns, custom callout bodies and toggle headings")
        let indented = NoteMarkdown.parse(NoteMarkdown.serialize(NotePage(blocks: [fenced])))
        #expect(indented.blocks.first?.props.anchor == "f3nce2" && indented.blocks.first?.text.string == "indented", "anchored indented code switches to a fence so the anchor has somewhere to live")
        #expect(NoteMarkdown.serialize(NotePage(blocks: [.paragraph("Hi")])) == "Hi\n", "no anchor, no comment")
    }
}
