import Foundation
import Testing
@testable import ParcCore

struct MarkdownCodecTestsExactRoundTripTests {
    typealias SourceCase = MarkdownCodecTestsSupport.SourceCase

    @Test(arguments: [
        SourceCase("heading levels", "# One\n\n## Two\n\n### Three\n\n#### Four\n\n##### Five\n\n###### Six\n"),
        SourceCase("setext headings", "Title\n=====\n\nSubtitle\n--------\n"),
        SourceCase("paragraph breaks", "Soft wrapped\nparagraph line\nand a hard break\\\nnext line.\n"),
        SourceCase("emphasis", "Some *italic*, **bold**, ***both***, ~~struck~~ and `code` text.\n"),
        SourceCase("links", "A [link](https://example.com/a?b=c) and https://example.com, <ftp://files.example.com> and https://bare.example.com/x.\n"),
        SourceCase("bullets", "- one\n- two\n  - nested\n  - nested two\n- three\n"),
        SourceCase("bullet markers", "* star\n* star two\n\n+ plus\n"),
        SourceCase("ordered", "1. first\n2. second\n3. third\n"),
        SourceCase("ordered paren start", "3) three\n4) four\n"),
        SourceCase("loose list", "- one\n\n- two\n\n- three\n"),
        SourceCase("loose list with child", "1. First\n\n   More about first.\n\n2. Second\n"),
        SourceCase("tasks", "- [ ] open\n- [x] done\n  - [ ] nested\n"),
        SourceCase("quote", "> Quoted text\n> continues\n>\n> Second paragraph\n"),
        SourceCase("nested quote", "> Outer\n>\n> > Inner\n"),
        SourceCase("fenced code", "```swift\nlet value = 1\nprint(value)\n```\n"),
        SourceCase("tilde fence", "~~~python title=\"run.py\"\nprint(\"hi\")\n~~~\n"),
        SourceCase("long fence", "````\n```\nnested fence\n```\n````\n"),
        SourceCase("indented code", "    let indented = true\n    return indented\n"),
        SourceCase("empty code", "```\n```\n"),
        SourceCase("thematic breaks", "---\n\n***\n\n___\n\n* * *\n"),
        SourceCase("table", "| Name | Count | Note |\n| :--- | :---: | ---: |\n| a    | 1     | x    |\n| b    | 2     |      |\n"),
        SourceCase("html block", "<div align=\"center\">\n  <img src=\"logo.png\" width=\"80\">\n</div>\n"),
        SourceCase("html comment", "<!-- just a comment -->\n"),
        SourceCase("definitions", "Read [the docs][docs] and [faq].\n\n[docs]: https://example.com/docs\n[faq]: https://example.com/faq \"FAQ\"\n"),
        SourceCase("footnotes", "A claim.[^1]\n\n[^1]: The source.\n    More detail.\n"),
        SourceCase("empty paragraphs", "\nFirst\n\n\nSecond\n\n"),
        SourceCase("math block", "$$\n\\int_0^1 x\\,dx\n$$\n"),
        SourceCase("math fence", "```math\na^2 + b^2 = c^2\n```\n"),
        SourceCase("inline math", "Euler: $e^{i\\pi} + 1 = 0$, costs $5 and $10.\n"),
        SourceCase("inline extras", "<u>under</u>, <span data-color=\"red\">red</span>, <mark data-color=\"blue_background\">blue</mark> and ==marked==.\n"),
        SourceCase("block color", "Painted paragraph <!-- parc color=\"purple_background\" -->\n\n## Heading <!-- parc color=\"red\" -->\n\n- item <!-- parc color=\"green\" -->\n"),
        SourceCase("divider color", "---\n<!-- parc color=\"gray\" -->\n"),
        SourceCase("toc", "<!-- toc -->\n\n# Intro\n"),
        SourceCase("callout github", "> [!TIP]\n> Try the shortcut. <!-- parc icon=\"💡\" color=\"yellow_background\" -->\n"),
        SourceCase("callout obsidian", "> [!faq]- Why markdown?\n> Because files outlive apps.\n"),
        SourceCase("callout github note", "> [!NOTE]\n> Useful note.\n>\n> - with a list\n"),
        SourceCase("callout plain", "> [!NOTE]\n> Plain callout. <!-- parc -->\n>\n> - with a list\n"),
        SourceCase("toggle", "<details open>\n<summary>Open toggle</summary>\n\nInside.\n\n</details>\n"),
        SourceCase("toggle closed empty", "<details>\n<summary>Nothing here</summary>\n</details>\n"),
        SourceCase("toggle heading", "<details>\n<summary><h2>Section</h2></summary>\n\n- child\n\n</details>\n"),
        SourceCase("nested toggles", "<details open>\n<summary>Outer</summary>\n\n<details>\n<summary>Inner</summary>\n\nDeep.\n\n</details>\n\n</details>\n"),
        SourceCase("columns", ":::: columns\n::: column\nLeft side\n:::\n::: {.column width=\"40%\"}\nRight side\n\n- with a list\n:::\n::::\n"),
        SourceCase("indented text", "Parent paragraph\n\n::: indent\nA child\n\n- and a list\n:::\n\n## Heading <!-- parc color=\"red\" -->\n\n:::: indent\nUnder the heading\n\n::: indent\nDeeper\n:::\n::::\n\nAfter\n"),
        SourceCase("indented empty parent", "<!-- parc paragraph -->\n\n::: indent\nOnly the child\n:::\n"),
        SourceCase("indent in a list", "- item\n\n  Text\n\n  ::: indent\n  nested\n  :::\n- next\n"),
        SourceCase("indent around columns", "Lead\n\n:::::: indent\n::::: columns\n:::: column\nLeft\n\n::: indent\nkid\n:::\n::::\n:::: column\nRight\n::::\n:::::\n::::::\n"),
        SourceCase("image", "![A cat](Attachments/cat.png \"A *cute* cat\") <!-- parc width=\"320\" align=\"left\" -->\n"),
        SourceCase("video audio file", "![](Attachments/clip.mp4)\n\n![](Attachments/song.mp3)\n\n![report.pdf](Attachments/report.pdf)\n"),
        SourceCase("embed", "![](https://www.youtube.com/watch?v=dQw4w9WgXcQ)\n\n![](https://example.com/widget) <!-- parc embed -->\n"),
        SourceCase("bookmark", "[The Verge](https://www.theverge.com) <!-- parc bookmark summary=\"Tech news\" site=\"The Verge\" thumbnail=\"https://example.com/t.png\" -->\n"),
        SourceCase("bare bookmark", "<https://example.com> <!-- parc bookmark -->\n"),
        SourceCase("page link", "[Project plan](Project%20plan.md)\n\n[Elsewhere](../Other/Notes.md) <!-- parc color=\"blue\" -->\n"),
        SourceCase("mentions", "Ask [[Ada Lovelace]] or [[People/Grace|Grace]] about [Roadmap](Roadmap.md) by <time datetime=\"2026-11-20T09:30\" data-remind>2026-11-20 09:30</time>.\n"),
        SourceCase("link mention", "Saw <a href=\"https://example.com\" data-mention>Example Domain</a> today.\n"),
        SourceCase("raw inline", "Press <kbd>⌘</kbd> + <kbd>K</kbd>, see ![icon](icon.png) and H<sub>2</sub>O.\n"),
        SourceCase("escapes", "Literal \\*stars*, \\_under_, # hash, 1. not a list, \\[not a link](x), a \\`tick\\` and a \\ backslash, \\\\* too.\n"),
        SourceCase("empty items", "-\n- [ ]\n-\n"),
        SourceCase("ordered restart", "1. one\n2. two\n\n<!-- -->\n\n1. again\n"),
    ])
    func commonMarkdownFixturesSaveBackExactly(fixture: SourceCase) {
        NoteMarkdownCheck.checkExact(fixture.markdown, fixture.testDescription)
    }

    @Test(arguments: [
        SourceCase("entities", "Fish &amp; chips &copy; 2026 &#x1F600; &nbsp;space.\n"),
        SourceCase("angle autolinks", "Angle <https://example.com> and <me@example.com> links.\n"),
    ])
    func entitiesAndAngleAutolinksSettleAfterOneSave(fixture: SourceCase) {
        NoteMarkdownCheck.checkStable(fixture.markdown, fixture.testDescription)
    }
}
