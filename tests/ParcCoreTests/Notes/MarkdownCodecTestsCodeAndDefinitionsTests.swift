import Foundation
import Testing
@testable import ParcCore

struct MarkdownCodecTestsCodeAndDefinitionsTests: NoteFixtures {
    typealias SourceCase = MarkdownCodecTestsSupport.SourceCase

    private func blocks(_ source: String) -> [NoteBlock] { NoteMarkdown.parse(source).blocks }

    struct TaskText: Sendable, CustomTestStringConvertible {
        let testDescription: String
        let text: String

        init(_ label: String, _ text: String) {
            testDescription = label
            self.text = text
        }
    }

    @Test(arguments: [
        TaskText("ticked", "[x]\u{2028}after"),
        TaskText("open", "[ ]\u{2028}after"),
        TaskText("vertical tab", "[x]\u{0B}after"),
    ])
    func taskLikeTextBeforeABreakSurvivesInListItems(fixture: TaskText) {
        let (label, text) = (fixture.testDescription, fixture.text)
        let numbered = NoteBlock(.numberedItem, text: NoteText(text))
        let bulleted = NoteBlock(.bulletedItem, text: NoteText(text))
        NoteMarkdownCheck.checkModelRoundTrip(NotePage(blocks: [numbered, .paragraph("gap"), bulleted]), "task-like text before a break, \(label)")
    }

    @Test(arguments: [
        SourceCase("indented code after a list and a blank paragraph", "-\n\n\n    code\n"),
        SourceCase("indented code with a Parc comment", "    code\n<!-- parc color=\"red\" -->\n"),
    ])
    func indentedCodeThatNeedsAFenceSettlesAfterOneSave(fixture: SourceCase) {
        NoteMarkdownCheck.checkStable(fixture.markdown, fixture.testDescription)
    }

    @Test
    func indentedCodeAfterAListLoadsWithoutTheIndentedStyle() {
        #expect(blocks("-\n\n\n    code\n").last?.props.fence == nil, "code the writer must fence after a list loads without the indented style")
    }

    @Test
    func indentedCodeWithSettingsLoadsWithoutTheIndentedStyle() {
        #expect(blocks("    code\n<!-- parc color=\"red\" -->\n").first?.props.fence == nil, "indented code with settings loads as fenced")
    }

    @Test
    func indentedCodeCanContainOnlyANoBreakSpace() {
        var unicodeBlank = NoteBlock(.code, text: NoteText("\u{00A0}"))
        unicodeBlank.props.fence = "    "
        NoteMarkdownCheck.checkModelRoundTrip(NotePage(blocks: [unicodeBlank]), "indented code whose only line is a no-break space")
    }

    @Test(arguments: [
        SourceCase("definition continued by a block HTML line", "[r]: /url\n    <details>x\n"),
        SourceCase("definition continued by a setext heading that opens with HTML", "[r]: /url\n    <div>\n===\n"),
    ])
    func definitionsWithBlockHTMLSaveBackExactly(fixture: SourceCase) {
        NoteMarkdownCheck.checkExact(fixture.markdown, fixture.testDescription)
    }

    @Test(arguments: [
        SourceCase("definition continued by inline display math", "[r]: /url\n$$x$$ y\n"),
        SourceCase("nested definition continued by a comment", "> - [r]: /url\n>       <!-- c --> tail\n"),
        SourceCase("definition followed by an ordinary line", "[r]: /url\ntext\n"),
    ])
    func definitionsWithUnusualContinuationsSettleAfterOneSave(fixture: SourceCase) {
        NoteMarkdownCheck.checkStable(fixture.markdown, fixture.testDescription)
    }

    @Test
    func aDefinitionWithBlockHTMLLoadsAsOneRawBlock() {
        #expect(blocks("[r]: /url\n     <details>x\n").map(\.kind) == [.raw], "definitions with an HTML-block continuation stay one raw block")
    }

    @Test
    func anOrdinaryLineAfterADefinitionLoadsAsAParagraph() {
        #expect(blocks("[r]: /url\ntext\n").map(\.kind) == [.raw, .paragraph], "an ordinary continuation still becomes a paragraph")
    }

    @Test
    func aCodeFenceKeepsTheLanguageAndRemainingInfo() {
        let code = blocks("```js title=\"app.js\"\nx\n```\n")
        #expect(code[0].props.language == "js" && code[0].props.info == "title=\"app.js\"", "info strings keep the language and the rest")
    }

    @Test
    func anUnclosedCodeFenceRunsToTheEnd() {
        let unclosed = blocks("```\nnever closed\n\nstill code\n")
        #expect(unclosed.count == 1 && unclosed[0].text.string == "never closed\n\nstill code", "an unclosed fence runs to the end")
    }

    @Test
    func indentedCodeKeepsOnlyItsInnerBlankLines() {
        let indented = blocks("    a\n\n    b\n\n\nafter\n")
        #expect(indented[0].kind == .code && indented[0].text.string == "a\n\nb", "indented code keeps inner blank lines and drops trailing ones")
    }

    @Test
    func deepNestingSettlesAfterOneSave() async {
        let problems = await onLargeStack {
            let deep = NoteMarkdown.parse(String(repeating: "> ", count: 5000) + "deep\n" + String(repeating: "*a ", count: 3000) + String(repeating: "b* ", count: 3000) + "\n")
            return NoteMarkdownCheck.stableProblems(NoteMarkdown.serialize(deep), "deep nesting")
        }
        for problem in problems { Issue.record(Comment(rawValue: problem)) }
    }

    @Test
    func aBackslashAtTheEndOfABlockStaysLiteral() {
        let breakAtEnd = blocks("ends with backslash\\\n")
        #expect(breakAtEnd[0].text.string == "ends with backslash\\", "a backslash at the end of a block stays literal")
    }
}
