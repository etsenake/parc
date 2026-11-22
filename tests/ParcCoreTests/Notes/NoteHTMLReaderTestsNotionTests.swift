import Foundation
import Testing
@testable import ParcCore

struct NoteHTMLReaderTestsNotionTests {
    private typealias Fixture = NoteHTMLReaderTestsSupport

    private func importedBlocks() -> [NoteBlock] {
        let html = """
        <meta charset="utf-8"><h2 id="1a2b" class="">Trip ideas</h2><p id="2b3c" class="">A <mark class="highlight-red">red</mark> word, a <span class="highlight-yellow_background">sunny</span> one and <code>inline code</code>.</p><ul id="3c4d" class="bulleted-list"><li style="list-style-type:disc">Lisbon<ul id="3c4e" class="bulleted-list"><li style="list-style-type:circle">Trams</li></ul></li></ul><ol type="1" id="4d5e" class="numbered-list" start="3"><li>Book flights</li></ol><ul id="5e6f" class="to-do-list"><li><div class="checkbox checkbox-on"></div> <span class="to-do-children-checked">Passport</span></li></ul><ul id="6f7a" class="to-do-list"><li><div class="checkbox checkbox-off"></div> <span class="to-do-children-unchecked">Adapters</span></li></ul><ul id="7a8b" class="toggle"><li><details open=""><summary>Packing</summary><p id="8b9c" class="">Socks</p></details></li></ul><figure class="block-color-gray_background callout" style="white-space:pre-wrap;display:flex" id="9c0d"><div style="font-size:1.5em"><span class="icon">✈️</span></div><div style="width:100%">Window seat, always.</div></figure><blockquote id="0d1e" class="block-color-purple">Travel light.</blockquote><pre id="1e2f" class="code"><code class="language-JavaScript">const trip = plan("Lisbon")</code></pre><figure id="2f3a" class="equation"><style>@import url('https://cdnjs.cloudflare.com/ajax/libs/KaTeX/0.16.9/katex.min.css')</style><div class="equation-container"><span class="katex-display"><span class="katex"><span class="katex-mathml"><math xmlns="http://www.w3.org/1998/Math/MathML" display="block"><semantics><mrow><mi>a</mi></mrow><annotation encoding="application/x-tex">a^2 + b^2 = c^2</annotation></semantics></math></span><span class="katex-html" aria-hidden="true"><span class="base">a2+b2=c2</span></span></span></span></div></figure><table id="3a4b" class="simple-table"><thead class="simple-table-header"><tr id="r1"><th id="c1" class="simple-table-header-color simple-table-header">City</th><th id="c2" class="simple-table-header-color simple-table-header">Days</th></tr></thead><tbody><tr id="r2"><th id="c3" class="simple-table-header-color simple-table-header">Porto</th><td id="c4">2</td></tr></tbody></table><div id="4b5c" class="column-list"><div id="a1" style="width:50%" class="column"><p>Left side</p></div><div id="b1" style="width:50%" class="column"><p>Right side</p></div></div><figure id="5c6d"><a href="https://www.visitportugal.com/" class="bookmark source"><div class="bookmark-info"><div class="bookmark-text"><div class="bookmark-title">Visit Portugal</div><div class="bookmark-description">Official tourism site</div></div><div class="bookmark-href">https://www.visitportugal.com/</div></div></a></figure><hr id="6d7e"/><figure id="7e8f" class="image"><a href="Trip/tram.jpg"><img style="width:640px" src="Trip/tram.jpg"/></a><figcaption>Tram 28</figcaption></figure><p>Equation <span class="notion-text-equation-token" contenteditable="false"><span class="katex"><span class="katex-mathml"><math><semantics><annotation encoding="application/x-tex">\\pi r^2</annotation></semantics></math></span><span class="katex-html" aria-hidden="true">πr2</span></span></span> inline.</p>
        """
        return Fixture.read(html)
    }

    private func blocks() throws -> [NoteBlock] {
        let blocks = importedBlocks()
        try #require(blocks.count == 17)
        return blocks
    }

    @Test
    func theImportKeepsTheExpectedBlockOrder() {
        let blocks = importedBlocks()
        Fixture.shape(blocks, ["heading", "paragraph", "bulletedItem", "numberedItem", "todo", "todo", "toggle", "callout", "quote", "code",
                       "equation", "table", "columns", "bookmark", "divider", "image", "paragraph"], "Notion")
    }

    @Test
    func notionHeadingsKeepTheirLevel() throws {
        let blocks = try blocks()
        #expect(blocks[0].props.level == 2 && blocks[0].text.string == "Trip ideas", "Notion heading")
    }

    @Test
    func notionRedHighlightBecomesRedInk() throws {
        let blocks = try blocks()
        #expect(Fixture.marks("red", blocks[1].text)?.color == .text(.red), "highlight-red is red ink")
    }

    @Test
    func notionYellowBackgroundStaysYellow() throws {
        let blocks = try blocks()
        #expect(Fixture.marks("sunny", blocks[1].text)?.color == .background(.yellow), "highlight-yellow_background")
    }

    @Test
    func notionInlineCodeKeepsItsMark() throws {
        let blocks = try blocks()
        #expect(Fixture.marks("inline code", blocks[1].text)?.code == true, "inline code")
    }

    @Test
    func notionNestedBulletsStayUnderTheirParent() throws {
        let blocks = try blocks()
        #expect(blocks[2].children.map(\.text.string) == ["Trams"], "nested bullets")
    }

    @Test
    func notionOrderedListsKeepTheirStartNumber() throws {
        let blocks = try blocks()
        #expect(blocks[3].props.listStart == 3, "ol start carries over")
    }

    @Test
    func notionCheckedTodosStayChecked() throws {
        let blocks = try blocks()
        #expect(blocks[4].props.checked && blocks[4].text.string == "Passport", "Notion checked to-do")
    }

    @Test
    func notionOpenTodosStayOpen() throws {
        let blocks = try blocks()
        #expect(!blocks[5].props.checked && blocks[5].text.string == "Adapters", "Notion open to-do")
    }

    @Test
    func notionToggleItemsLiftIntoAToggle() throws {
        let blocks = try blocks()
        #expect(blocks[6].text.string == "Packing" && blocks[6].props.expanded && blocks[6].children.first?.text.string == "Socks", "toggle list item lifts to a toggle")
    }

    @Test
    func notionCalloutsKeepTheirIconAndBackground() throws {
        let blocks = try blocks()
        #expect(blocks[7].props.icon == "✈️" && blocks[7].text.string == "Window seat, always." && blocks[7].color == .background(.gray), "Notion callout: \(NoteHTMLCheck.outline([blocks[7]])) icon \(String(describing: blocks[7].props.icon))")
    }

    @Test
    func notionQuotesKeepTheirColor() throws {
        let blocks = try blocks()
        #expect(blocks[8].text.string == "Travel light." && blocks[8].color == .text(.purple), "quote colour")
    }

    @Test
    func notionCodeKeepsItsLanguage() throws {
        let blocks = try blocks()
        #expect(blocks[9].props.language == "javascript" && blocks[9].text.string == "const trip = plan(\"Lisbon\")", "Notion code")
    }

    @Test
    func notionDisplayEquationsReadTheTeXAnnotation() throws {
        let blocks = try blocks()
        #expect(blocks[10].text.string == "a^2 + b^2 = c^2", "Notion equation reads the TeX annotation")
    }

    @Test
    func notionSimpleTablesKeepRowAndColumnHeaders() throws {
        let blocks = try blocks()
        #expect(blocks[11].props.table?.headerRow == true && blocks[11].props.table?.headerColumn == true, "Notion simple table headers")
    }

    @Test
    func notionColumnsKeepTheirChildren() throws {
        let blocks = try blocks()
        #expect(blocks[12].children.count == 2 && blocks[12].children.allSatisfy { $0.kind == .column }
               && blocks[12].children[1].children.first?.text.string == "Right side", "Notion columns")
    }

    @Test
    func notionBookmarksKeepTheirSourceTitleAndSummary() throws {
        let blocks = try blocks()
        #expect(blocks[13].props.source == "https://www.visitportugal.com/" && blocks[13].props.bookmark?.title == "Visit Portugal"
               && blocks[13].props.bookmark?.summary == "Official tourism site", "Notion bookmark")
    }

    @Test
    func notionImagesKeepTheirCaption() throws {
        let blocks = try blocks()
        #expect(blocks[15].props.source == "Trip/tram.jpg" && blocks[15].props.caption.string == "Tram 28", "Notion image with caption")
    }

    @Test
    func notionInlineEquationsReadTheTeXAnnotation() throws {
        let blocks = try blocks()
        #expect(blocks[16].text.runs().contains { $0.marks.atom == .equation("\\pi r^2") } && blocks[16].text.plainText == "Equation \\pi r^2 inline.", "Notion inline equation: \(blocks[16].text.plainText.debugDescription)")
    }
}
