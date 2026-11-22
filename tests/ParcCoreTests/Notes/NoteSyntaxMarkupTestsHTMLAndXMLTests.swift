import Foundation
import Testing
@testable import ParcCore

struct NoteSyntaxMarkupTestsHTMLAndXMLTests {
    typealias TokenCase = NoteSyntaxMarkupTestsSupport.TokenCase
    private typealias SyntaxProbe = NoteSyntaxMarkupTestsSupport.SyntaxProbe

    private static let htmlSource = """
        <!DOCTYPE html>
        <!-- a <b>comment</b> -->
        <html lang="en">
          <head>
            <style>
              body > .card:hover { color: #ff0066; margin: 0 auto; }
            </style>
            <script>
              const tag = "</div>"; if (a < b && c > d) { console.log(`x ${a}`); } // </p>
            </script>
            <script type="application/ld+json">{"name": "Parc"}</script>
          </head>
          <body class='main' hidden data-x=1>Fish &amp; chips &#x1F600;<br/><input disabled></body>
        </html>
        """

    private static let htmlTokens = [
        TokenCase("<!DOCTYPE html>", .meta),
        TokenCase("<!-- a <b>comment</b> -->", .comment),
        TokenCase("html", .tag, 2),
        TokenCase("lang", .attribute),
        TokenCase("\"en\"", .string),
        TokenCase("style", .tag),
        TokenCase("body", .tag),
        TokenCase(".card", .attribute),
        TokenCase(":hover", .keyword),
        TokenCase("color", .property),
        TokenCase("#ff0066", .constant),
        TokenCase("auto", .constant),
        TokenCase("const", .keyword),
        TokenCase("\"</div>\"", .string),
        TokenCase("<", .operatorSymbol, 11),
        TokenCase("console", .builtin),
        TokenCase("log", .function),
        TokenCase("`x ", .string),
        TokenCase("// </p>", .comment),
        TokenCase("script", .tag, 2),
        TokenCase("\"name\"", .property),
        TokenCase("\"Parc\"", .string),
        TokenCase("'main'", .string),
        TokenCase("hidden", .attribute),
        TokenCase("1", .string),
        TokenCase("Fish", nil),
        TokenCase("&amp;", .escape),
        TokenCase("&#x1F600;", .escape),
        TokenCase("br", .tag),
        TokenCase("/>", .punctuation),
        TokenCase("disabled", .attribute),
    ]

    @Test(arguments: htmlTokens)
    func htmlFragmentsHaveTheExpectedHighlight(token: TokenCase) {
        SyntaxProbe("html", Self.htmlSource).expect(token)
    }

    @Test
    func htmlTokenRangesAreWellFormed() {
        SyntaxProbe("html", Self.htmlSource).expectWellFormed()
    }

    private static let xmlSource = """
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0"><dict><key>Name</key><string>Parc &lt;3</string>
        <![CDATA[ <raw> & stuff ]]><x:item xmlns:x="urn:x"/></dict></plist>
        <!-- done -->
        """

    private static let xmlTokens = [
        TokenCase("<?xml version=\"1.0\" encoding=\"UTF-8\"?>", .meta),
        TokenCase("plist", .tag),
        TokenCase("version", .attribute, 2),
        TokenCase("key", .tag),
        TokenCase("Name", nil),
        TokenCase("&lt;", .escape),
        TokenCase("<![CDATA[", .meta),
        TokenCase(" <raw> & stuff ", .string),
        TokenCase("x:item", .tag),
        TokenCase("xmlns:x", .attribute),
        TokenCase("<!-- done -->", .comment),
    ]

    @Test(arguments: xmlTokens)
    func xmlFragmentsHaveTheExpectedHighlight(token: TokenCase) {
        SyntaxProbe("xml", Self.xmlSource).expect(token)
    }

    @Test
    func xmlTokenRangesAreWellFormed() {
        SyntaxProbe("xml", Self.xmlSource).expectWellFormed()
    }
}
