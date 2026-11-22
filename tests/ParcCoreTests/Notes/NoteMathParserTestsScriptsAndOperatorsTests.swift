import Foundation
import Testing
@testable import ParcCore

struct NoteMathParserTestsScriptsAndOperatorsTests {
    typealias NodeCase = NoteMathParserTestsSupport.NodeCase
    typealias ExpansionCase = NoteMathParserTestsSupport.ExpansionCase
    private typealias Parser = NoteMathParserTestsSupport

    @Test(arguments: [
        NodeCase("superscript", "x^2") { [.scripts(base: .char("x", .ord), superscript: [.char("2", .ord)], subscript: nil)] },
        NodeCase("grouped subscript", "x_{ij}") { [.scripts(base: .char("x", .ord), superscript: nil, subscript: [.char("i", .ord), .char("j", .ord)])] },
        NodeCase("prime", "f'") { [.scripts(base: .char("f", .ord), superscript: [.char("′", .ord)], subscript: nil)] },
        NodeCase("double prime", "f''") { [.scripts(base: .char("f", .ord), superscript: [.char("″", .ord)], subscript: nil)] },
        NodeCase("prime then superscript merge", "f'^2") { [.scripts(base: .char("f", .ord), superscript: [.char("′", .ord), .char("2", .ord)], subscript: nil)] },
        NodeCase("prime then subscript", "f'_1") { [.scripts(base: .char("f", .ord), superscript: [.char("′", .ord)], subscript: [.char("1", .ord)])] },
        NodeCase("script with no base", "^2") { [.scripts(base: nil, superscript: [.char("2", .ord)], subscript: nil)] },
        NodeCase("command as a script", "x^\\alpha") { [.scripts(base: .char("x", .ord), superscript: [.char("α", .ord)], subscript: nil)] },
    ])
    func scriptsAndPrimesAttachToTheirBase(fixture: NodeCase) throws {
        #expect(try Parser.parse(fixture.source) == fixture.expected())
    }

    @Test(arguments: [
        ExpansionCase("script order doesn't matter", "x_i^2",
                      "x^2_i"),
    ])
    func subscriptAndSuperscriptCanAppearInEitherOrder(fixture: ExpansionCase) throws {
        #expect(try Parser.parse(fixture.source) == Parser.parse(fixture.expanded))
    }

    @Test
    func aScriptTakesAnUnbracedFraction() throws {
        #expect(try Parser.parse("e^\\frac12").count == 1, "TeX-style unbraced fraction in a script")
    }

    @Test
    func aBracedBaseTakesAnotherSuperscript() throws {
        #expect(try Parser.parse("{x^2}^3").count == 1, "braced base takes another superscript")
    }

    @Test(arguments: [
        NodeCase("fraction", "\\frac{a}{b}") { [.fraction(NoteMathFraction(numerator: [.char("a", .ord)], denominator: [.char("b", .ord)]))] },
        NodeCase("unbraced fraction", "\\frac12") { [.fraction(NoteMathFraction(numerator: [.char("1", .ord)], denominator: [.char("2", .ord)]))] },
        NodeCase("infix over", "{a \\over b}") { [.group([.fraction(NoteMathFraction(numerator: [.char("a", .ord)], denominator: [.char("b", .ord)]))])] },
        NodeCase("square root", "\\sqrt{x}") { [.radical([.char("x", .ord)], degree: nil)] },
        NodeCase("cube root", "\\sqrt[3]{x}") { [.radical([.char("x", .ord)], degree: [.char("3", .ord)])] },
        NodeCase("unbraced radicand", "\\sqrt[n]2") { [.radical([.char("2", .ord)], degree: [.char("n", .ord)])] },
    ])
    func fractionsAndRadicalsKeepTheirArguments(fixture: NodeCase) throws {
        #expect(try Parser.parse(fixture.source) == fixture.expected())
    }

    @Test
    func dfracForcesDisplayStyle() throws {
        guard case .fraction(let display)? = try Parser.parse("\\dfrac ab").first else {
            Issue.record("dfrac parses as a fraction")
            return
        }
        #expect(display.level == .display, "dfrac forces display")
    }

    @Test
    func tfracForcesTextStyle() throws {
        guard case .fraction(let text)? = try Parser.parse("\\tfrac ab").first else {
            Issue.record("tfrac parses as a fraction")
            return
        }
        #expect(text.level == .text, "tfrac forces text")
    }

    @Test
    func binomHasParenthesesAndNoRule() throws {
        if case .fraction(let binom)? = try Parser.parse("\\binom{n}{k}").first {
            #expect(!binom.hasRule && binom.left == "(" && binom.right == ")", "binom has parens and no rule")
        } else {
            Issue.record("binom parses as a fraction")
            return
        }
    }

    @Test(arguments: [
        NodeCase("sum with limits", "\\sum_{i=1}^n") { [.scripts(base: .largeOperator("∑", .auto), superscript: [.char("n", .ord)],
            subscript: [.char("i", .ord), .char("=", .rel), .char("1", .ord)])] },
        NodeCase("integrals keep limits beside", "\\int_0^1") { [.scripts(base: .largeOperator("∫", .beside), superscript: [.char("1", .ord)],
            subscript: [.char("0", .ord)])] },
        NodeCase("\\nolimits", "\\sum\\nolimits_i") { [.scripts(base: .largeOperator("∑", .beside), superscript: nil, subscript: [.char("i", .ord)])] },
        NodeCase("more big operators", "\\iint\\oint\\bigcup\\prod") { [.largeOperator("∬", .beside), .largeOperator("∮", .beside),
            .largeOperator("⋃", .auto), .largeOperator("∏", .auto)] },
        NodeCase("sin", "\\sin x") { [.function("sin", .beside), .char("x", .ord)] },
        NodeCase("function names", "\\max\\log\\ln\\exp") { [.function("max", .auto), .function("log", .beside), .function("ln", .beside),
            .function("exp", .beside)] },
        NodeCase("operatorname", "\\operatorname{Tr} A") { [.operatorName([.char("T", .ord), .char("r", .ord)], .beside), .char("A", .ord)] },
    ])
    func operatorsAndFunctionsKeepTheirLimitPlacement(fixture: NodeCase) throws {
        #expect(try Parser.parse(fixture.source) == fixture.expected())
    }

    @Test
    func limitsStacksIntegralLimits() throws {
        #expect(try Parser.parse("\\int\\limits_0^1").first.map { node in
            if case .scripts(.largeOperator("∫", .above)?, _, _) = node { return true }
            return false
        } == true, "\\limits stacks integral limits")
    }

    @Test
    func limTakesALowerLimit() throws {
        #expect(try Parser.parse("\\lim_{x\\to0}").first == .scripts(base: .function("lim", .auto), superscript: nil,
                                                          subscript: [.char("x", .ord), .char("→", .rel), .char("0", .ord)]), "lim")
    }

    @Test
    func aStarredOperatorNameTakesLimits() throws {
        #expect(try Parser.parse("\\operatorname*{argmax}_x").first.map { node in
            if case .scripts(.operatorName(_, .auto)?, nil, _) = node { return true }
            return false
        } == true, "operatorname star takes limits")
    }

    @Test
    func bmodSitsBetweenItsOperands() throws {
        #expect(try Parser.parse("a \\bmod b").count == 3, "bmod")
    }

    @Test
    func repeatedLimitsCommandsStillProduceOneOperator() throws {
        #expect(try Parser.parse("\\sum\\limits\\limits").count == 1, "limits twice is fine")
    }
}
