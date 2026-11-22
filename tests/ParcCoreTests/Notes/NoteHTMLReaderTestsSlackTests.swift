import Foundation
import Testing
@testable import ParcCore

struct NoteHTMLReaderTestsSlackTests {
    private typealias Fixture = NoteHTMLReaderTestsSupport

    private func importedBlocks() -> [NoteBlock] {
        let html = """
        <meta charset='utf-8'><div class="p-rich_text_section">Here's the plan for <b data-stringify-type="bold">Friday</b>:</div><ul data-stringify-type="unordered-list" data-indent="0" class="p-rich_text_list p-rich_text_list__bullet" data-border="0"><li data-stringify-indent="0" data-stringify-border="0">Ship it</li></ul><ul data-stringify-type="unordered-list" data-indent="1" class="p-rich_text_list p-rich_text_list__bullet p-rich_text_list--nested" data-border="0"><li data-stringify-indent="1" data-stringify-border="0">Run tests</li><li data-stringify-indent="1" data-stringify-border="0">Tag it</li></ul><ul data-stringify-type="unordered-list" data-indent="0" class="p-rich_text_list p-rich_text_list__bullet" data-border="0"><li data-stringify-indent="0" data-stringify-border="0">Celebrate <img data-id=":tada:" data-stringify-type="emoji" data-stringify-emoji=":tada:" class="c-emoji c-emoji__medium c-emoji--inline" src="https://a.slack-edge.com/production-standard-emoji-assets/14.0/apple-medium/1f389.png" alt="tada" aria-label="tada emoji"></li></ul><div class="p-rich_text_section"><a target="_blank" class="c-link" data-stringify-link="https://example.com" delay="150" data-sk="tooltip_parent" href="https://example.com" rel="noopener noreferrer">example.com</a> then <code data-stringify-type="code" class="c-mrkdwn__code">npm test</code><span class="c-mrkdwn__br" data-stringify-type="paragraph-break"></span>New paragraph</div><pre class="c-mrkdwn__pre" data-stringify-type="pre"><div class="p-rich_text_block--no-overflow">let x = 1<br>let y = 2</div></pre><blockquote type="cite" class="c-mrkdwn__quote" data-stringify-type="quote">Quoted <i data-stringify-type="italic">text</i></blockquote><span style="color: rgb(29, 28, 29); font-family: Slack-Lato, Slack-Fractions, appleLogo, sans-serif; font-size: 15px; background-color: rgb(248, 248, 248);">Plain loose text</span>
        """
        return Fixture.read(html)
    }

    private func blocks() throws -> [NoteBlock] {
        let blocks = importedBlocks()
        try #require(blocks.count == 8)
        return blocks
    }

    @Test
    func theImportKeepsTheExpectedBlockOrder() {
        let blocks = importedBlocks()
        Fixture.shape(blocks, ["paragraph", "bulletedItem", "bulletedItem", "paragraph", "paragraph", "code", "quote", "paragraph"], "Slack")
    }

    @Test
    func slackBoldKeepsItsMark() throws {
        let blocks = try blocks()
        #expect(Fixture.marks("Friday", blocks[0].text)?.bold == true, "Slack bold")
    }

    @Test
    func slackListsNestByDataIndent() throws {
        let blocks = try blocks()
        #expect(blocks[1].text.string == "Ship it" && blocks[1].children.map(\.text.string) == ["Run tests", "Tag it"], "data-indent lists nest: \(NoteHTMLCheck.outline([blocks[1]]))")
    }

    @Test
    func slackEmojiImagesBecomeShortcodes() throws {
        let blocks = try blocks()
        #expect(blocks[2].text.string == "Celebrate :tada:", "Slack emoji images become their shortcode")
    }

    @Test
    func slackLinksAndInlineCodeKeepTheirMarks() throws {
        let blocks = try blocks()
        #expect(Fixture.marks("example.com", blocks[3].text)?.link == "https://example.com" && Fixture.marks("npm test", blocks[3].text)?.code == true, "Slack link and code")
    }

    @Test
    func slackParagraphBreakSpansSplitParagraphs() throws {
        let blocks = try blocks()
        #expect(blocks[4].text.string == "New paragraph", "paragraph-break spans split paragraphs")
    }

    @Test
    func slackPreformattedTextKeepsLineBreaks() throws {
        let blocks = try blocks()
        #expect(blocks[5].text.string == "let x = 1\nlet y = 2", "Slack pre")
    }

    @Test
    func slackQuotesKeepTextAndItalic() throws {
        let blocks = try blocks()
        #expect(blocks[6].text.string == "Quoted text" && Fixture.marks("text", blocks[6].text)?.italic == true, "Slack quote")
    }

    @Test
    func slackNeutralColorsStayOutOfMarks() throws {
        let blocks = try blocks()
        #expect(blocks[7].text.string == "Plain loose text" && Fixture.marks("Plain", blocks[7].text)?.isPlain == true, "near-black ink and near-white backgrounds are ignored")
    }
}
