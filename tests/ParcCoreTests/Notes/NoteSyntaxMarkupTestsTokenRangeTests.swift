import Foundation
import Testing
@testable import ParcCore

struct NoteSyntaxMarkupTestsTokenRangeTests {
    private typealias SyntaxProbe = NoteSyntaxMarkupTestsSupport.SyntaxProbe
    typealias TokenCase = NoteSyntaxMarkupTestsSupport.TokenCase

    private static let emojiCode = "let 🌳 = \"🌳\" // 🌳"
    private static let languageIDs = NoteCodeLanguage.all.map(\.id)

    @Test(arguments: [TokenCase("\"🌳\"", .string), TokenCase("// 🌳", .comment)])
    func emojiDoNotShiftTheHighlightedFragments(token: TokenCase) {
        SyntaxProbe("swift", Self.emojiCode).expect(token)
    }

    @Test
    func theLastEmojiTokenEndsAtTheUTF16Length() {
        let code = Self.emojiCode
        let emoji = SyntaxProbe("swift", code)
        #expect(emoji.tokens.last?.range.upperBound == (code as NSString).length)
    }

    private static let trickySnippets = [
        "\"unterminated", "/* open", "`${`${`${", "<div <span", "'''", "#{", "${", "$(", "<<EOF", "@\"", "r#\"",
        "[[", "--[[", "{-", "```", "<!--", "\\", "\u{1F600}\"\u{1F600}", "a /b/ c", "\n\n\t ", "%w(", "~r/", "<?php",
        "<a type=\"", "<a type='", "<script type=\"", "<script type=\"text/x", "<a type=",
    ]

    @Test(arguments: languageIDs, trickySnippets)
    func trickySnippetsHaveWellFormedTokenRanges(language: String, snippet: String) {
        SyntaxProbe(language, snippet).expectWellFormed()
    }

    @Test(arguments: languageIDs, trickySnippets)
    func repeatingTrickySnippetsKeepsTokenRangesWellFormed(language: String, snippet: String) {
        SyntaxProbe(language, String(repeating: snippet, count: 50)).expectWellFormed()
    }

    @Test(arguments: languageIDs)
    func aLongBlockOfCodeStaysWellFormed(language: String) {
        let line = "let value = compute(\"text\", 0x2A) /* note */ + `tpl ${a / b}` // tail <b>x</b> $var #{x}\n"
        SyntaxProbe(language, String(repeating: line, count: 2_000)).expectWellFormed()
    }

    @Test(arguments: languageIDs)
    func anAdversarialBlockOfCodeStaysWellFormed(language: String) {
        SyntaxProbe(language, String(repeating: "( / [ * _ ` < ${ #{ \" ' ", count: 4_000)).expectWellFormed()
    }

    @Test
    func anUnclosedTypeAttributeAtTheEndOfAnHTMLBlockDoesNotCrash() {
        let probe = SyntaxProbe("html", "<script type=\"")
        probe.expectWellFormed()
        #expect(probe.kind("script") == .tag)
    }

    @Test
    func deeplyNestedStyleInterpolationStaysWellFormed() {
        SyntaxProbe("scss", String(repeating: "#{", count: 200_000)).expectWellFormed()
    }
}
