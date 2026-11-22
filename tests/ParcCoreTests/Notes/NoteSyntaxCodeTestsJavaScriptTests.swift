import Foundation
import Testing
@testable import ParcCore

struct NoteSyntaxCodeTestsJavaScriptTests {
    typealias TokenCase = NoteSyntaxCodeTestsSupport.TokenCase
    private typealias SyntaxProbe = NoteSyntaxCodeTestsSupport.SyntaxProbe

    private static let javascriptSource = """
        import { a } from "./mod.js" // "quote in comment
        const re = /[/]+\\d{2}/gi, half = total / 2 / count;
        const tpl = `sum ${ { a: 1 }.a + `inner ${deep}` } done`;
        let big = 12_345n, hex = 0xFFn; class Foo extends Bar { #secret = 1; get x() { return this.#secret } }
        const s = 'it\\'s /* not */ a comment';
        html`<b>${name}</b>`;
        function ok(y) { return /foo/.test(y) }
        """

    private static let javascriptTokens = [
        TokenCase("import", .keyword),
        TokenCase("\"./mod.js\"", .string),
        TokenCase("// \"quote in comment", .comment),
        TokenCase("/[/]+\\d{2}/gi", .regex),
        TokenCase("/", .operatorSymbol, 7),
        TokenCase("/", .operatorSymbol, 8),
        TokenCase("total", nil),
        TokenCase("`sum ", .string),
        TokenCase("${", .punctuation),
        TokenCase("1", .number),
        TokenCase("`inner ", .string),
        TokenCase(" done`", .string),
        TokenCase("12_345n", .number),
        TokenCase("0xFFn", .number),
        TokenCase("Foo", .type),
        TokenCase("Bar", .type),
        TokenCase("#secret", .property),
        TokenCase("this", .keyword),
        TokenCase("'it\\'s /* not */ a comment'", nil),
        TokenCase("/* not */", .string),
        TokenCase("\\'", .escape),
        TokenCase("html", .function),
        TokenCase("/foo/", .regex),
        TokenCase("test", .function),
    ]

    @Test(arguments: javascriptTokens)
    func javascriptFragmentsHaveTheExpectedHighlight(token: TokenCase) {
        SyntaxProbe("js", Self.javascriptSource).expect(token)
    }

    @Test
    func javascriptTokenRangesAreWellFormed() {
        SyntaxProbe("js", Self.javascriptSource).expectWellFormed()
    }

    private static let typescriptSource = "interface User { name: string; age?: number }\ntype Id = string | number;\nenum Color { Red }\n@Component({}) class A implements B {}"

    private static let typescriptTokens = [
        TokenCase("interface", .keyword),
        TokenCase("User", .type),
        TokenCase("string", .type),
        TokenCase("number", .type),
        TokenCase("type", .keyword),
        TokenCase("Id", .type),
        TokenCase("enum", .keyword),
        TokenCase("@Component", .attribute),
        TokenCase("implements", .keyword),
    ]

    @Test(arguments: typescriptTokens)
    func typescriptFragmentsHaveTheExpectedHighlight(token: TokenCase) {
        SyntaxProbe("ts", Self.typescriptSource).expect(token)
    }

    private static let jsxSource = """
        const App = () => (
          <div className="app" onClick={() => go(1)}>
            Hello {user.name}, it's <b>bold</b> &amp; <Card {...props} title='x' />
          </div>
        );
        const less = a < b;
        """

    private static let jsxTokens = [
        TokenCase("div", .tag),
        TokenCase("className", .attribute),
        TokenCase("\"app\"", .string),
        TokenCase("onClick", .attribute),
        TokenCase("go", .function),
        TokenCase("Hello", nil),
        TokenCase("it's", nil),
        TokenCase("name", .property),
        TokenCase("b", .tag),
        TokenCase("&amp;", .escape),
        TokenCase("Card", .tag),
        TokenCase("'x'", .string),
        TokenCase("</", .punctuation),
        TokenCase("<", .operatorSymbol, 6),
    ]

    @Test(arguments: jsxTokens)
    func jsxFragmentsHaveTheExpectedHighlight(token: TokenCase) {
        SyntaxProbe("jsx", Self.jsxSource).expect(token)
    }

    @Test
    func jsxTokenRangesAreWellFormed() {
        SyntaxProbe("jsx", Self.jsxSource).expectWellFormed()
    }

    private static let tsxSource = "const el: JSX.Element = <Button kind=\"primary\">{label as string}</Button>;"

    private static let tsxTokens = [
        TokenCase("Button", .tag),
        TokenCase("kind", .attribute),
        TokenCase("as", .keyword),
        TokenCase("string", .type),
    ]

    @Test(arguments: tsxTokens)
    func tsxFragmentsHaveTheExpectedHighlight(token: TokenCase) {
        SyntaxProbe("tsx", Self.tsxSource).expect(token)
    }
}
