import Foundation
import Testing
@testable import ParcCore

struct NoteSyntaxMarkupTestsStylesheetTests {
    typealias TokenCase = NoteSyntaxMarkupTestsSupport.TokenCase
    private typealias SyntaxProbe = NoteSyntaxMarkupTestsSupport.SyntaxProbe

    private static let cssSource = """
        @import url(https://fonts.googleapis.com/css);
        :root { --accent: #6c5ce7; }
        @media (max-width: 600px) and screen {
          nav a[href^="http"]::after, #main > li + li { content: "→ { not a block"; width: calc(100% - 2rem) !important; }
        }
        /* comment with a "quote */
        .btn{background:rgba(0,0,0,.5);transition:all .2s ease-in-out}
        """

    private static let cssTokens = [
        TokenCase("@import", .keyword),
        TokenCase("url", .function),
        TokenCase("https://fonts.googleapis.com/css", .string),
        TokenCase(":root", .keyword),
        TokenCase("--accent", .variable),
        TokenCase("#6c5ce7", .constant),
        TokenCase("@media", .keyword),
        TokenCase("max-width", .property),
        TokenCase("600px", .number),
        TokenCase("and", .keyword),
        TokenCase("nav", .tag),
        TokenCase("href", .attribute),
        TokenCase("^", .operatorSymbol),
        TokenCase("\"http\"", .string),
        TokenCase("::after", .keyword),
        TokenCase("#main", .attribute),
        TokenCase(">", .operatorSymbol, 1),
        TokenCase("content", .property),
        TokenCase("\"→ { not a block\"", .string),
        TokenCase("calc", .function),
        TokenCase("100%", .number),
        TokenCase("2rem", .number),
        TokenCase("!important", .keyword),
        TokenCase("/* comment with a \"quote */", .comment),
        TokenCase(".btn", .attribute),
        TokenCase("background", .property),
        TokenCase("rgba", .function),
        TokenCase(".5", .number),
        TokenCase(".2s", .number),
        TokenCase("ease-in-out", .constant),
    ]

    @Test(arguments: cssTokens)
    func cssFragmentsHaveTheExpectedHighlight(token: TokenCase) {
        SyntaxProbe("css", Self.cssSource).expect(token)
    }

    @Test
    func cssTokenRangesAreWellFormed() {
        SyntaxProbe("css", Self.cssSource).expectWellFormed()
    }

    private static let scssSource = """
        @use "sass:math";
        $base: 16px !default; // line comment
        @mixin pad($size) { padding: math.div($size, 2); }
        .card {
          &:hover { color: darken($brand, 10%); }
          .title-#{$name} { @include pad(4px); }
          %placeholder { margin: 0; }
          @extend %placeholder;
        }
        """

    private static let scssTokens = [
        TokenCase("@use", .keyword),
        TokenCase("\"sass:math\"", .string),
        TokenCase("$base", .variable),
        TokenCase("16px", .number),
        TokenCase("!default", .keyword),
        TokenCase("// line comment", .comment),
        TokenCase("@mixin", .keyword),
        TokenCase("pad", .function),
        TokenCase("padding", .property),
        TokenCase("div", .function),
        TokenCase("&", .keyword),
        TokenCase(":hover", .keyword),
        TokenCase("darken", .function),
        TokenCase("10%", .number),
        TokenCase(".title-", .attribute),
        TokenCase("#{", .punctuation),
        TokenCase("$name", .variable),
        TokenCase("@include", .keyword),
        TokenCase("%placeholder", .attribute),
        TokenCase("@extend", .keyword),
    ]

    @Test(arguments: scssTokens)
    func scssFragmentsHaveTheExpectedHighlight(token: TokenCase) {
        SyntaxProbe("scss", Self.scssSource).expect(token)
    }

    @Test
    func scssTokenRangesAreWellFormed() {
        SyntaxProbe("scss", Self.scssSource).expectWellFormed()
    }
}
