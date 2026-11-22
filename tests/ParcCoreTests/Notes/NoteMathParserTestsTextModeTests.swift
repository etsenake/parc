import Foundation
import Testing
@testable import ParcCore

struct NoteMathParserTestsTextModeTests {
    typealias NodeCase = NoteMathParserTestsSupport.NodeCase
    typealias ErrorCase = NoteMathParserTestsSupport.ErrorCase
    private typealias Parser = NoteMathParserTestsSupport

    @Test(arguments: [
        NodeCase("text accents compose", "\\text{\\'e\\`a\\^o\\~n\\=u\\u{a}\\.z\\\"o\\r a\\H o\\v c}") { [.text("éàôñūăżöåőč", .roman)] },
        NodeCase("accents sit on dotless i", "\\text{\\'{\\i}}") { [.text("ı\u{0301}", .roman)] },
        NodeCase("nested text styles", "\\text{a \\textbf{b} c}") { [.group([.text("a ", .roman), .text("b", .bold), .text(" c", .roman)])] },
        NodeCase("text switches stop at the brace", "\\text{a {\\bf b} c}") { [.group([.text("a ", .roman), .text("b", .bold), .text(" c", .roman)])] },
        NodeCase("color in text", "\\text{a {\\color{red} b}}") { [.group([.text("a ", .roman), .colored(NoteMathSymbols.color(named: "red")!, [.text(" b", .roman)])])] },
        NodeCase("textcolor in text", "\\text{\\textcolor{red}{b}}") { [.group([.colored(NoteMathSymbols.color(named: "red")!, [.text("b", .roman)])])] },
        NodeCase("sizes in text", "\\text{\\tiny a}") { [.group([.sized(0.5, [.text("a", .roman)])])] },
        NodeCase("text symbols", "\\text{\\textdollar\\textless\\textunderscore\\textquotedblleft\\pounds\\aa\\ss\\o}") { [.text("$<_“£åßø", .roman)] },
        NodeCase("text ligatures", "\\text{a---b--c ``q'' it's}") { [.text("a—b–c “q” it’s", .roman)] },
        NodeCase("typewriter text keeps its dashes", "\\texttt{a--b}") { [.text("a--b", .monospace)] },
        NodeCase("tie is a no-break space", "\\text{a~b}") { [.text("a\u{00A0}b", .roman)] },
        NodeCase("spacing in text", "\\text{a\\hspace{1em}b}") { [.group([.text("a", .roman), .space(1), .text("b", .roman)])] },
        NodeCase("href in text", "\\text{\\href{https://a.b}{go}}") { [.group([.link("https://a.b", [.text("go", .roman)])])] },
        NodeCase("textcircled", "\\text{\\textcircled{a}}") { [.text("ⓐ", .roman)] },
        NodeCase("underline in text", "\\text{\\underline{a}}") { [.group([.decorated(.underline, [.text("a", .roman)])])] },
        NodeCase("paren math in text", "\\text{\\(x\\)}") { [.group([.mathStyle(.text, [.char("x", .ord)])])] },
        NodeCase("text keeps its spaces", "\\text{if } x") { [.text("if ", .roman), .char("x", .ord)] },
        NodeCase("text collapses spaces and unescapes", "\\text{a  {b}\\%}") { [.text("a b%", .roman)] },
        NodeCase("bold text", "\\textbf{Hi}") { [.text("Hi", .bold)] },
    ])
    func textCommandsProduceTheExpectedTextNodes(fixture: NodeCase) throws {
        #expect(try Parser.parse(fixture.source) == fixture.expected())
    }

    @Test(arguments: ["KaTeX", "verb|a|"])
    func aLogoOrVerbatimCommandProducesOneTextNode(command: String) throws {
        #expect(try Parser.parse("\\text{\\\(command)}").count == 1)
    }

    @Test
    func dollarDelimitedMathWorksInsideText() throws {
        #expect(try Parser.parse("\\text{for $x>0$}").first.map { node in
            if case .group(let parts) = node, parts.count == 2, case .mathStyle(.text, let math) = parts[1] { return math.count == 3 }
            return false
        } == true, "inline math inside text")
    }

    @Test(arguments: [
        ErrorCase("unclosed paren math", "\\text{\\(x}",
                  .prefix("Missing \\) to close")),
        ErrorCase("stray close paren math", "x \\)",
                  .exact("\\) without a matching \\(")),
    ])
    func unmatchedMathParenthesesExplainTheError(fixture: ErrorCase) throws {
        try NoteMathParserTestsSupport.expectError(fixture)
    }
}
