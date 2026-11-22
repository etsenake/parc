import Foundation
import Testing
@testable import ParcCore

struct NoteMathParserTestsSizingAndBoxesTests {
    typealias NodeCase = NoteMathParserTestsSupport.NodeCase
    typealias ErrorCase = NoteMathParserTestsSupport.ErrorCase
    private typealias Parser = NoteMathParserTestsSupport

    struct DimensionCase: Sendable, CustomTestStringConvertible {
        let source: String
        let expected: Double
        let tolerance: Double

        init(_ source: String, _ expected: Double, _ tolerance: Double) {
            self.source = source
            self.expected = expected
            self.tolerance = tolerance
        }

        var testDescription: String { source }
    }

    @Test(arguments: [
        DimensionCase("1px", 0.100375, 1e-12),
        DimensionCase("1ex", 0.431, 1e-12),
        DimensionCase("10dd", 1.0700086430423511, 1e-9),
        DimensionCase("65536sp", 0.1, 1e-12),
    ])
    func eachDimensionConvertsToItsExpectedValue(fixture: DimensionCase) throws {
        let value = try #require(NoteMathParser.dimension(fixture.source))
        #expect(abs(value - fixture.expected) < fixture.tolerance)
    }

    @Test(arguments: ["1cc", "1nd", "1nc"])
    func additionalTeXDimensionsAreRecognized(source: String) {
        #expect(NoteMathParser.dimension(source) != nil)
    }

    struct SizeCase: Sendable, CustomTestStringConvertible {
        let name: String
        let factor: Double

        init(_ name: String, _ factor: Double) {
            self.name = name
            self.factor = factor
        }

        var testDescription: String { "\(name) scales by \(factor)" }
    }

    @Test(arguments: [
        SizeCase("tiny", 0.5), SizeCase("scriptsize", 0.7), SizeCase("footnotesize", 0.8),
        SizeCase("small", 0.9), SizeCase("normalsize", 1.0), SizeCase("large", 1.2),
        SizeCase("Large", 1.44), SizeCase("LARGE", 1.728), SizeCase("huge", 2.074), SizeCase("Huge", 2.488),
    ])
    func eachSizeCommandUsesItsExpectedScale(fixture: SizeCase) throws {
        #expect(try Parser.parse("\\\(fixture.name) x") == [.sized(fixture.factor, [.char("x", .ord)])])
    }

    @Test(arguments: [
        NodeCase("size switches cover the rest", "a \\Huge b c") { [.char("a", .ord), .sized(2.488, [.char("b", .ord), .char("c", .ord)])] },
        NodeCase("size switches stop at the brace", "{\\tiny x} y") { [.group([.sized(0.5, [.char("x", .ord)])]), .char("y", .ord)] },
        NodeCase("raisebox lifts text", "\\raisebox{0.25em}{hi}") { [.raised(0.25, [.text("hi", .roman)])] },
        NodeCase("raisebox takes math in dollars", "\\raisebox{-.1em}{$x$}") { [.raised(-0.1, [.mathStyle(.text, [.char("x", .ord)])])] },
        NodeCase("smash flattens both sides", "\\smash{y}") { [.smashed([.char("y", .ord)], top: true, bottom: true)] },
        NodeCase("smash t keeps depth", "\\smash[t]{y}") { [.smashed([.char("y", .ord)], top: true, bottom: false)] },
        NodeCase("smash b keeps height", "\\smash[b]{y}") { [.smashed([.char("y", .ord)], top: false, bottom: true)] },
        NodeCase("substack splits rows", "\\sum_{\\substack{i<n\\\\j}}") { [.scripts(base: .largeOperator("\u{2211}", .auto), superscript: nil,
            subscript: [.substack([[.char("i", .ord), .char("<", .rel), .char("n", .ord)], [.char("j", .ord)]])])] },
        NodeCase("colorbox", "\\colorbox{red}{hi}") { [.colorBox(NoteMathSymbols.color(named: "red")!, frame: nil, [.text("hi", .roman)])] },
        NodeCase("fcolorbox takes frame then background", "\\fcolorbox{blue}{red}{a $x$}") { [.colorBox(NoteMathSymbols.color(named: "red")!, frame: NoteMathSymbols.color(named: "blue")!, [.text("a ", .roman), .mathStyle(.text, [.char("x", .ord)])])] },
        NodeCase("rule with a lift", "\\rule[0.1em]{1em}{2pt}") { [.rule(width: 1, height: 0.2, raise: 0.1)] },
        NodeCase("explicit spaces", "\\hspace{2em}\\mkern18mu") { [.space(2), .space(1)] },
        NodeCase("boxed and phantom", "\\boxed{x}\\phantom{y}") { [.boxed([.char("x", .ord)]), .phantom([.char("y", .ord)], keepsWidth: true, keepsHeight: true)] },
        NodeCase("laps", "\\llap{a}\\mathrlap{b}\\clap{c}") { [.lap(.left, [.char("a", .ord)]), .lap(.right, [.char("b", .ord)]),
            .lap(.center, [.char("c", .ord)])] },
    ])
    func boxAndSizingCommandsProduceTheExpectedNodes(fixture: NodeCase) throws {
        #expect(try Parser.parse(fixture.source) == fixture.expected())
    }

    @Test(arguments: [
        ErrorCase("smash rejects other options", "\\smash[x]{y}",
                  .exact("\\smash takes [t] or [b], not [x]")),
        ErrorCase("unclosed substack", "\\substack{a",
                  .exact("Missing } to close this {")),
        ErrorCase("bad genfrac style", "\\genfrac(){}{7}{a}{b}",
                  .prefix("\\genfrac styles")),
    ])
    func invalidBoxArgumentsExplainTheError(fixture: ErrorCase) throws {
        try NoteMathParserTestsSupport.expectError(fixture)
    }

    @Test
    func generalizedFractionsReadDelimitersRuleAndStyle() throws {
        guard case .fraction(let general) = try Parser.parse("\\genfrac(]{0pt}{2}{a}{b}")[0] else { Issue.record("genfrac is a fraction"); return }
        #expect(general.left == "(" && general.right == "]" && !general.hasRule && general.level == .script, "genfrac reads delimiters, rule and style")
    }

    @Test
    func generalizedFractionsKeepACustomRule() throws {
        guard case .fraction(let thick) = try Parser.parse("\\genfrac{}{}{2pt}{}{a}{b}")[0] else { Issue.record("genfrac thickness"); return }
        #expect(thick.hasRule && thick.thickness == 0.2 && thick.left == nil && thick.level == nil, "genfrac keeps a custom rule")
    }

    @Test
    func generalizedFractionsAcceptBraceDelimiters() throws {
        guard case .fraction(let curly) = try Parser.parse("\\genfrac{\\{}{\\}}{}{0}{a}{b}")[0] else { Issue.record("genfrac curly"); return }
        #expect(curly.left == "{" && curly.right == "}" && curly.level == .display, "genfrac takes brace delimiters")
    }

    @Test(arguments: [
        NodeCase("href wraps math", "\\href{https://katex.org/}{x}") { [.link("https://katex.org/", [.char("x", .ord)])] },
        NodeCase("url unescapes", "\\url{https://a.b/c\\#d\\_e}") { [.link("https://a.b/c#d_e", [.text("https://a.b/c#d_e", .monospace)])] },
    ])
    func mathLinksKeepTheirTextAndUnescapeTheAddress(fixture: NodeCase) throws {
        #expect(try Parser.parse(fixture.source) == fixture.expected())
    }

    @Test(arguments: [
        ErrorCase("empty url", "\\url{}",
                  .prefix("\\url needs a link")),
    ])
    func anEmptyURLNeedsALink(fixture: ErrorCase) throws {
        try NoteMathParserTestsSupport.expectError(fixture)
    }

    @Test(arguments: ["tiny", "Huge", "raisebox", "smash", "substack", "genfrac", "colorbox", "fcolorbox",
                       "href", "url", "overgroup", "tripledash"])
    func sizeBoxAndLinkCommandsAreBuiltIn(name: String) {
        #expect(NoteMathParser.isBuiltIn(name), "\\\(name) is built in")
    }
}
