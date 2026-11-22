import Foundation
import Testing
@testable import ParcCore

struct NoteHTMLReaderTestsGitHubTests {
    private typealias Fixture = NoteHTMLReaderTestsSupport

    private func importedBlocks() -> [NoteBlock] {
        let html = """
        <article class="markdown-body entry-content container-lg" itemprop="text"><div class="markdown-heading" dir="auto"><h1 tabindex="-1" class="heading-element" dir="auto">Parc</h1><a id="user-content-parc" class="anchor" aria-label="Permalink: Parc" href="#parc"><svg class="octicon octicon-link" viewBox="0 0 16 16" version="1.1" width="16" height="16" aria-hidden="true"><path d="m7.775 3.275"></path></svg></a></div>
        <p dir="auto">A browser that <strong>feels</strong> like home. See <a href="/etsenake/parc/blob/main/docs/product.md">the guide</a> and <code>make test</code>.</p>
        <div class="markdown-alert markdown-alert-warning" dir="auto"><p class="markdown-alert-title" dir="auto"><svg class="octicon octicon-alert mr-2" viewBox="0 0 16 16" version="1.1" width="16" height="16" aria-hidden="true"><path d="M6.457 1.047"></path></svg>Warning</p><p dir="auto">Builds take a while.</p>
        </div>
        <div class="highlight highlight-source-shell notranslate position-relative overflow-auto" dir="auto"><pre>git clone https://github.com/etsenake/parc
        <span class="pl-c1">cd</span> parc &amp;&amp; make</pre><div class="zeroclipboard-container"><clipboard-copy aria-label="Copy" class="ClipboardButton btn" data-copy-feedback="Copied!" value="git clone" tabindex="0" role="button"><svg aria-hidden="true" height="16" viewBox="0 0 16 16" version="1.1" width="16" class="octicon octicon-copy"><path d="M0 6.75C0"></path></svg></clipboard-copy></div></div>
        <ul class="contains-task-list">
        <li class="task-list-item"><input type="checkbox" id="" disabled="" class="task-list-item-checkbox" checked=""> Tabs</li>
        <li class="task-list-item"><input type="checkbox" id="" disabled="" class="task-list-item-checkbox"> Notes
        <ul>
        <li>Markdown files</li>
        </ul>
        </li>
        </ul>
        <markdown-accessiblity-table><table>
        <thead>
        <tr>
        <th align="left">Key</th>
        <th align="center">Action</th>
        </tr>
        </thead>
        <tbody>
        <tr>
        <td align="left"><kbd>⌘T</kbd></td>
        <td align="center">New tab</td>
        </tr>
        </tbody>
        </table></markdown-accessiblity-table>
        <p dir="auto"><a target="_blank" rel="noopener noreferrer" href="/etsenake/parc/raw/main/docs/screenshot.png"><img src="/etsenake/parc/raw/main/docs/screenshot.png" alt="Screenshot" style="max-width: 100%;"></a></p>
        <p dir="auto">Math: <math-renderer class="js-inline-math" style="display: inline" data-static-url="https://github.githubassets.com/static" data-run-id="abc">$E = mc^2$</math-renderer> <g-emoji class="g-emoji" alias="tada">🎉</g-emoji></p>
        <math-renderer class="js-display-math" style="display: block" data-static-url="https://github.githubassets.com/static">$$\\sum_{i=1}^n i$$</math-renderer>
        <details><summary>More</summary><p dir="auto">Hidden <em>bits</em>.</p></details>
        <blockquote><p dir="auto">Quote line one<br>line two</p></blockquote>
        </article>
        """
        return Fixture.read(html, base: "https://github.com/etsenake/parc")
    }

    private func blocks() throws -> [NoteBlock] {
        let blocks = importedBlocks()
        try #require(blocks.count == 12)
        return blocks
    }

    @Test
    func theImportKeepsTheExpectedBlockOrder() {
        let blocks = importedBlocks()
        Fixture.shape(blocks, ["heading", "paragraph", "callout", "code", "todo", "todo", "table", "image", "paragraph", "equation", "toggle", "quote"], "GitHub")
    }

    @Test
    func gitHubPermalinkAnchorsStayOutOfTheHeading() throws {
        let blocks = try blocks()
        #expect(blocks[0].text.string == "Parc", "permalink anchors vanish")
    }

    @Test
    func gitHubInlineMarksKeepBoldAndCode() throws {
        let blocks = try blocks()
        let body = blocks[1].text
        #expect(Fixture.marks("feels", body)?.bold == true && Fixture.marks("make test", body)?.code == true, "GitHub inline marks")
    }

    @Test
    func gitHubRelativeLinksResolveAgainstTheRepo() throws {
        let blocks = try blocks()
        let body = blocks[1].text
        #expect(Fixture.marks("the guide", body)?.link == "https://github.com/etsenake/parc/blob/main/docs/product.md", "relative links resolve")
    }

    @Test
    func gitHubAlertsBecomeCallouts() throws {
        let blocks = try blocks()
        #expect(blocks[2].props.alert == "WARNING" && blocks[2].text.string == "Builds take a while.", "GitHub alert becomes a callout")
    }

    @Test
    func gitHubCodeKeepsItsLinesAndLanguage() throws {
        let blocks = try blocks()
        #expect(blocks[3].props.language == "shell" && blocks[3].text.string == "git clone https://github.com/etsenake/parc\ncd parc && make", "code block keeps lines and language: \(blocks[3].text.string.debugDescription)")
    }

    @Test
    func gitHubCheckedTasksStayChecked() throws {
        let blocks = try blocks()
        #expect(blocks[4].props.checked && blocks[4].text.string == "Tabs", "checked task")
    }

    @Test
    func gitHubTasksCanHaveNestedLists() throws {
        let blocks = try blocks()
        #expect(!blocks[5].props.checked && blocks[5].text.string == "Notes" && blocks[5].children.map(\.text.string) == ["Markdown files"], "task with nested list")
    }

    @Test
    func gitHubTablesKeepHeadersAndAlignment() throws {
        let blocks = try blocks()
        let table = try #require(blocks[6].props.table)
        #expect(table.headerRow && table.alignments == [.left, .center], "GitHub table header and alignment")
    }

    @Test
    func gitHubKeyboardMarkupBecomesCodeInTableCells() throws {
        let blocks = try blocks()
        let table = try #require(blocks[6].props.table)
        #expect(table.rows[1].map(\.string) == ["⌘T", "New tab"] && table.rows[1][0].runs().first?.marks.code == true, "kbd is code")
    }

    @Test
    func gitHubImageSourcesResolveAgainstTheRepo() throws {
        let blocks = try blocks()
        #expect(blocks[7].props.source == "https://github.com/etsenake/parc/raw/main/docs/screenshot.png" && blocks[7].props.alt == "Screenshot", "image src resolves against the base URL")
    }

    @Test
    func gitHubInlineMathBecomesAnEquation() throws {
        let blocks = try blocks()
        let math = blocks[8].text
        #expect(math.runs().contains { $0.marks.atom == .equation("E = mc^2") }, "inline math becomes an equation")
    }

    @Test
    func aGitHubEmojiKeepsItsCharacter() throws {
        let blocks = try blocks()
        let math = blocks[8].text
        #expect(math.plainText.hasSuffix("🎉"), "g-emoji keeps its emoji")
    }

    @Test
    func gitHubDisplayMathBecomesAnEquationBlock() throws {
        let blocks = try blocks()
        #expect(blocks[9].text.string == "\\sum_{i=1}^n i", "display math becomes an equation block")
    }

    @Test
    func gitHubDetailsBecomeClosedToggles() throws {
        let blocks = try blocks()
        #expect(blocks[10].text.string == "More" && !blocks[10].props.expanded && blocks[10].children.first?.text.string == "Hidden bits.", "details becomes a toggle")
    }

    @Test
    func aBreakInsideAGitHubQuoteBecomesASoftBreak() throws {
        let blocks = try blocks()
        #expect(blocks[11].text.string == "Quote line one\nline two", "br inside a quote is a soft break")
    }
}
