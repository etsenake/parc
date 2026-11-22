import Foundation
import Testing
@testable import ParcCore

struct NoteSyntaxMarkupTestsMarkdownAndDiffTests {
    typealias TokenCase = NoteSyntaxMarkupTestsSupport.TokenCase
    private typealias SyntaxProbe = NoteSyntaxMarkupTestsSupport.SyntaxProbe

    private static let markdownSource = """
        ---
        title: Hello
        tags: [a, b]
        ---
        # Big *title*
        Setext heading
        ==============
        Some **bold**, _soft_, ~~gone~~ and `code *not em*` with a [link](https://parc.dev "t") and ![img](a.png).
        snake_case_word stays plain, and so does 2 * 3 * 4.
        > quoted [ref][1] <span data-color="red">red</span>
        - [x] done item
        12. ordered \\*escaped\\*
        ```swift
        let x = "fenced" // comment
        ```
        ~~~
        plain fence
        ~~~
        [1]: https://example.com
        ***
        Visit https://parc.dev/notes, or <mailto:hi@parc.dev>.
        """

    private static let markdownTokens = [
        TokenCase("---", .meta),
        TokenCase("title", .property),
        TokenCase("Hello", .string),
        TokenCase("# Big *title*", .heading),
        TokenCase("Setext heading", .heading),
        TokenCase("==============", .punctuation),
        TokenCase("**bold**", .strong),
        TokenCase("_soft_", .emphasis),
        TokenCase("~~gone~~", .deleted),
        TokenCase("`code *not em*`", .string),
        TokenCase("[link]", .link),
        TokenCase("https://parc.dev", .string),
        TokenCase("[img]", .link),
        TokenCase("snake_case_word", nil),
        TokenCase("* 3 *", nil),
        TokenCase(">", .punctuation, 1),
        TokenCase("[ref]", .link),
        TokenCase("span", .tag),
        TokenCase("data-color", .attribute),
        TokenCase("\"red\"", .string),
        TokenCase("[x]", .keyword),
        TokenCase("12.", .punctuation),
        TokenCase("\\*", .escape),
        TokenCase("```", .punctuation),
        TokenCase("swift", .attribute),
        TokenCase("let", .keyword),
        TokenCase("\"fenced\"", .string),
        TokenCase("// comment", .comment),
        TokenCase("plain fence", .string),
        TokenCase("[1]", .link, 2),
        TokenCase("https://example.com", .string),
        TokenCase("***", .punctuation),
        TokenCase("https://parc.dev/notes", .link),
        TokenCase("<mailto:hi@parc.dev>", .link),
    ]

    @Test(arguments: markdownTokens)
    func markdownFragmentsHaveTheExpectedHighlight(token: TokenCase) {
        SyntaxProbe("markdown", Self.markdownSource).expect(token)
    }

    @Test
    func markdownTokenRangesAreWellFormed() {
        SyntaxProbe("markdown", Self.markdownSource).expectWellFormed()
    }

    private static let markdownListSource = "- item\n* other\n+ third"

    private static let markdownListTokens = [
        TokenCase("-", .punctuation),
        TokenCase("*", .punctuation),
        TokenCase("+", .punctuation),
    ]

    @Test(arguments: markdownListTokens)
    func markdownListFragmentsHaveTheExpectedHighlight(token: TokenCase) {
        SyntaxProbe("md", Self.markdownListSource).expect(token)
    }

    private static let diffSource = """
        diff --git a/notes.md b/notes.md
        index 83db48f..bf269f4 100644
        --- a/notes.md
        +++ b/notes.md
        @@ -1,4 +1,4 @@ func header()
         context line
        --- removed line that looks like a header
        +++ added line that looks like a header
        -old
        +new
        \\ No newline at end of file
        """

    private static let diffTokens = [
        TokenCase("diff --git a/notes.md b/notes.md", .meta),
        TokenCase("index 83db48f..bf269f4 100644", .meta),
        TokenCase("--- a/notes.md", .heading),
        TokenCase("+++ b/notes.md", .heading),
        TokenCase("@@ -1,4 +1,4 @@", .meta),
        TokenCase("context line", nil),
        TokenCase("--- removed line that looks like a header", .deleted),
        TokenCase("+++ added line that looks like a header", .inserted),
        TokenCase("-old", .deleted),
        TokenCase("+new", .inserted),
        TokenCase("\\ No newline at end of file", .comment),
    ]

    @Test(arguments: diffTokens)
    func diffFragmentsHaveTheExpectedHighlight(token: TokenCase) {
        SyntaxProbe("diff", Self.diffSource).expect(token)
    }

    @Test
    func diffTokenRangesAreWellFormed() {
        SyntaxProbe("diff", Self.diffSource).expectWellFormed()
    }

    private static let patchSource = "+added\n-removed\n same"

    private static let patchTokens = [
        TokenCase("+added", .inserted),
        TokenCase("-removed", .deleted),
    ]

    @Test(arguments: patchTokens)
    func patchFragmentsHaveTheExpectedHighlight(token: TokenCase) {
        SyntaxProbe("patch", Self.patchSource).expect(token)
    }
}
