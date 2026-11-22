import Foundation
import Testing
@testable import ParcCore

struct NoteHTMLRoundTripTestsFragmentTests {
    private typealias Fixture = NoteHTMLRoundTripTestsSupport

    @Test
    func blocksSurviveAnHTMLFragmentRoundTrip() {
        let original = Fixture.page
        let html = NotePageHTML.fragment(original)
        let back = NoteHTMLReader.blocks(from: html, baseURL: nil)
        let problems = NoteHTMLCheck.same(original, back)
        #expect(problems.isEmpty, Comment(rawValue: "round trip differs:\n" + problems.prefix(12).joined(separator: "\n") + "\n" + NoteHTMLCheck.outline(back)))
    }

    @Test
    func aSecondRoundTripWritesTheSameHTML() {
        let original = Fixture.page
        let html = NotePageHTML.fragment(original)
        let back = NoteHTMLReader.blocks(from: html, baseURL: nil)
        let again = NotePageHTML.fragment(back)
        #expect(again == html, "a second trip writes the same HTML")
    }

    @Test
    func aFragmentNeedsNoDocumentOrStylesheet() {
        let html = NotePageHTML.fragment(Fixture.page)
        #expect(!html.contains("<html") && !html.contains("<style"), "fragments are bare HTML")
    }

    @Test
    func headingsExportWithTheirOutlineAnchors() {
        let html = NotePageHTML.fragment(Fixture.page)
        #expect(html.contains("<h1 id=\"big-title\">Big title</h1>"), "semantic headings with anchors for the outline")
    }

    @Test
    func inlineMarksExportAsSemanticHTML() {
        let html = NotePageHTML.fragment(Fixture.page)
        #expect(html.contains("<strong>bold</strong>") && html.contains("<em>italic</em>") && html.contains("<u>under</u>")
               && html.contains("<s>struck</s>") && html.contains("<code>code &lt;&amp;&gt;</code>"), "semantic inline marks")
    }

    @Test
    func aSingleAnchorSpansStyledAndPlainLinkText() {
        let html = NotePageHTML.fragment(Fixture.page)
        #expect(html.contains("<a href=\"https://parc.example/a?b=1&amp;c=2\"><strong>bold link</strong> plain link</a>"), "one anchor spans a link's runs")
    }

    @Test
    func fragmentColorsUseInlineStyles() {
        let html = NotePageHTML.fragment(Fixture.page)
        #expect(html.contains("style=\"color:#D44C47\""), "colours carry inline styles for Mail and Docs")
    }

    @Test
    func anOrderedListKeepsItsStartNumber() {
        let html = NotePageHTML.fragment(Fixture.page)
        #expect(html.contains("<ol start=\"4\">"), "list start")
    }

    @Test
    func todosExportAsDisabledCheckboxes() {
        let html = NotePageHTML.fragment(Fixture.page)
        #expect(html.contains("<input type=\"checkbox\" disabled checked>"), "task list checkboxes")
    }

    @Test
    func codeBlocksExportTheirLanguageClass() {
        let html = NotePageHTML.fragment(Fixture.page)
        #expect(html.contains("<pre><code class=\"language-swift\">"), "code language class")
    }

    @Test
    func aTableExportsItsHeaderRow() {
        let html = NotePageHTML.fragment(Fixture.page)
        #expect(html.contains("<thead><tr><th scope=\"col\""), "table header row")
    }

    @Test
    func repeatedSpacesSurviveExport() {
        let html = NotePageHTML.fragment(Fixture.page)
        #expect(html.contains("two &nbsp;spaces"), "runs of spaces survive")
    }

    @Test
    func indentedChildrenFollowTheirParent() {
        let html = NotePageHTML.fragment(Fixture.page)
        #expect(html.contains("<p>Text with kids</p><div class=\"indented\" style=\"padding-left:1.5em\"><p>Nested text</p>"), "text children sit in an indented div right after their parent")
    }

    @Test
    func importedIndentedDivsNestUnderThePreviousBlock() {
        let notion = NoteHTMLReader.blocks(from: "<p>Parent</p><div class=\"indented\"><p>Child</p></div><h2>Head</h2><div class=\"indented\"><p>Kid</p></div>", baseURL: nil)
        #expect(notion.count == 2 && notion[0].children.map(\.text.string) == ["Child"] && notion[1].children.map(\.text.string) == ["Kid"], "Notion's exported indented divs nest under the block before them")
    }

    @Test
    func anEmptyPageProducesAnEmptyFragment() {
        let blank = NotePageHTML.fragment([])
        #expect(blank.isEmpty, "nothing in, nothing out")
    }

    @Test
    func clipboardImagesUseResolvedFileURLs() {
        let resolved = NotePageHTML.fragment([Fixture.block(.image) { $0.source = "Attachments/a.png" }]) { source in
            URL(fileURLWithPath: "/Users/me/Notes").appendingPathComponent(source)
        }
        #expect(resolved.contains("src=\"file:///Users/me/Notes/Attachments/a.png\""), "assets resolve for the clipboard: \(resolved)")
    }
}
