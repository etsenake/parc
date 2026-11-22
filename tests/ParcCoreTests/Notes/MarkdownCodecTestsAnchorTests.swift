import Foundation
import Testing
@testable import ParcCore

struct MarkdownCodecTestsAnchorTests {
    typealias SourceCase = MarkdownCodecTestsSupport.SourceCase

    @Test(arguments: [
        SourceCase("anchored paragraph", "Hello there <!-- parc id=\"k3x9qa\" -->\n"),
        SourceCase("anchored heading keeps its slug text", "## Plan <!-- parc id=\"p1an2x\" -->\n"),
        SourceCase("anchored setext heading", "Title <!-- parc id=\"t1tle2\" -->\n===============================\n"),
        SourceCase("anchor beside a colour", "- Milk <!-- parc color=\"red\" id=\"m1lk22\" -->\n"),
        SourceCase("anchored empty item", "- <!-- parc id=\"emp7y2\" -->\n"),
        SourceCase("anchored task", "- [x] Done <!-- parc id=\"d0ne22\" -->\n"),
        SourceCase("anchored empty paragraph", "<!-- parc paragraph id=\"blank2\" -->\n"),
        SourceCase("anchored code", "```swift\nlet x = 1\n```\n<!-- parc id=\"c0de42\" -->\n"),
        SourceCase("anchored divider", "---\n<!-- parc id=\"d4v4de\" -->\n"),
        SourceCase("anchored equation", "$$\nx^2\n$$\n<!-- parc id=\"eq2222\" -->\n"),
        SourceCase("anchored table", "| A   | B   |\n| --- | --- |\n| 1   | 2   |\n<!-- parc id=\"tab1e2\" -->\n"),
        SourceCase("anchored image", "![Cat](cat.png) <!-- parc id=\"cat234\" -->\n"),
        SourceCase("anchored page link", "[Other](Other.md) <!-- parc id=\"pag3li\" -->\n"),
        SourceCase("anchored quote", "> Wise words <!-- parc id=\"qu0te2\" -->\n"),
        SourceCase("anchored toggle", "<details open>\n<summary>More <!-- parc id=\"t0ggle\" --></summary>\n\nInside\n\n</details>\n"),
        SourceCase("anchored toc", "<!-- toc -->\n<!-- parc id=\"t0c222\" -->\n"),
    ])
    func anchoredBlocksSaveBackExactly(fixture: SourceCase) {
        NoteMarkdownCheck.checkExact(fixture.markdown, fixture.testDescription)
    }

    @Test
    func anAnchorStaysOutOfTheHeadingText() {
        let page = NoteMarkdown.parse("## Plan <!-- parc id=\"p1an2x\" -->\n\nBody <!-- parc id=\"bad value\" -->\n\nPlain\n")
        #expect(page.blocks[0].props.anchor == "p1an2x" && page.blocks[0].text.string == "Plan", "the anchor reads back and stays out of the heading text")
    }

    @Test
    func anchorsWithSpacesAreIgnored() {
        let page = NoteMarkdown.parse("## Plan <!-- parc id=\"p1an2x\" -->\n\nBody <!-- parc id=\"bad value\" -->\n\nPlain\n")
        #expect(page.blocks.count == 3 && page.blocks[1].props.anchor == nil, "an anchor with spaces is ignored")
    }

    @Test
    func unanchoredBlocksStayUnanchored() {
        let page = NoteMarkdown.parse("## Plan <!-- parc id=\"p1an2x\" -->\n\nBody <!-- parc id=\"bad value\" -->\n\nPlain\n")
        #expect(page.blocks[2].props.anchor == nil, "unanchored blocks stay unanchored")
    }

    @Test
    func anchorsOnContainerBlocksAndEmptyParagraphsRoundTrip() {
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
        var anchoredOnly = NoteBlock.paragraph()
        anchoredOnly.props.anchor = "trail2"
        let model = NotePage(blocks: [callout, item, columns, custom, toggleHeading, anchoredOnly])
        NoteMarkdownCheck.checkModelRoundTrip(model, "anchors on callouts, nested items, columns, custom callout bodies and toggle headings")
    }

    @Test
    func anchoredIndentedCodeUsesAFence() {
        var fenced = NoteBlock(.code, text: NoteText("indented"))
        fenced.props.fence = "    "
        fenced.props.anchor = "f3nce2"
        let indented = NoteMarkdown.parse(NoteMarkdown.serialize(NotePage(blocks: [fenced])))
        #expect(indented.blocks.first?.props.anchor == "f3nce2" && indented.blocks.first?.text.string == "indented", "anchored indented code switches to a fence so the anchor has somewhere to live")
    }

    @Test
    func anUnanchoredParagraphWritesNoComment() {
        #expect(NoteMarkdown.serialize(NotePage(blocks: [.paragraph("Hi")])) == "Hi\n", "no anchor, no comment")
    }
}
