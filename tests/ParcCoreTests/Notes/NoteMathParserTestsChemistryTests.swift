import Foundation
import Testing
@testable import ParcCore

struct NoteMathParserTestsChemistryTests {
    typealias ExpansionCase = NoteMathParserTestsSupport.ExpansionCase
    typealias ErrorCase = NoteMathParserTestsSupport.ErrorCase
    private typealias Parser = NoteMathParserTestsSupport

    @Test(arguments: [
        ExpansionCase("subscripted formula", "\\ce{H2O}",
                      "{\\mathrm{H}_{2}\\mathrm{O}}"),
        ExpansionCase("parentheses take subscripts", "\\ce{Fe2(SO4)3}",
                      "{\\mathrm{Fe}_{2}(\\mathrm{S}\\mathrm{O}_{4})_{3}}"),
        ExpansionCase("charge over a subscript", "\\ce{SO4^2-}",
                      "{\\mathrm{S}\\mathrm{O}_{4}^{2-}}"),
        ExpansionCase("positive trailing charge", "\\ce{Na+}",
                      "{\\mathrm{Na}^{+}}"),
        ExpansionCase("negative trailing charge", "\\ce{NO3-}",
                      "{\\mathrm{N}\\mathrm{O}_{3}^{-}}"),
        ExpansionCase("braced and bare charges", "\\ce{Fe^{3+}}",
                      "\\ce{Fe^3+}"),
        ExpansionCase("isotope prescripts line up on the right", "\\ce{^{14}_{6}C}",
                      "{{}^{\\hphantom{14}}_{\\hphantom{6}}{}^{\\mathllap{14}}_{\\mathllap{6}}\\mathrm{C}}"),
        ExpansionCase("braced isotope form", "\\ce{{}^{14}_{6}C}",
                      "\\ce{^{14}_{6}C}"),
        ExpansionCase("stoichiometric number", "\\ce{2H2O}",
                      "{2\\mathrm{H}_{2}\\mathrm{O}}"),
        ExpansionCase("fractional stoichiometric number", "\\ce{1/2O2}",
                      "{\\tfrac{1}{2}\\mathrm{O}_{2}}"),
        ExpansionCase("aqueous state", "\\ce{NaCl(aq)}",
                      "{\\mathrm{Na}\\mathrm{Cl}\\mathrm{(}\\mathrm{aq}\\mathrm{)}}"),
        ExpansionCase("liquid state", "\\ce{H2O(l)}",
                      "{\\mathrm{H}_{2}\\mathrm{O}\\mathrm{(}\\mathrm{l}\\mathrm{)}}"),
        ExpansionCase("solid state", "\\ce{Fe(s)}",
                      "{\\mathrm{Fe}\\mathrm{(}\\mathrm{s}\\mathrm{)}}"),
        ExpansionCase("capital parentheses are groups, not states", "\\ce{Fe(CN)6^3-}",
                      "{\\mathrm{Fe}(\\mathrm{C}\\mathrm{N})_{6}^{3-}}"),
        ExpansionCase("single bond", "\\ce{C6H5-CHO}",
                      "{\\mathrm{C}_{6}\\mathrm{H}_{5}{-}\\mathrm{C}\\mathrm{H}\\mathrm{O}}"),
        ExpansionCase("double and triple bonds", "\\ce{X=Y#Z}",
                      "{\\mathrm{X}{=}\\mathrm{Y}{\\equiv}\\mathrm{Z}}"),
        ExpansionCase("star and dot both make addition compounds", "\\ce{CuSO4*5H2O}",
                      "\\ce{CuSO4.5H2O}"),
        ExpansionCase("bracketed complex ion", "\\ce{[AgCl2]-}",
                      "{\\lbrack\\mathrm{Ag}\\mathrm{Cl}_{2}\\rbrack^{-}}"),
        ExpansionCase("electron", "\\ce{e-}",
                      "{\\mathrm{e}^{-}}"),
        ExpansionCase("oxidation state", "\\ce{Fe^{II}}",
                      "{\\mathrm{Fe}^{\\mathrm{II}}}"),
        ExpansionCase("math escapes", "\\ce{$x$ H2O}",
                      "{{x} \\mathrm{H}_{2}\\mathrm{O}}"),
        ExpansionCase("variable stoichiometry stays italic", "\\ce{n H2O}",
                      "{n\\, \\mathrm{H}_{2}\\mathrm{O}}"),
    ])
    func chemicalFormulasProduceTheExpectedNotation(fixture: ExpansionCase) throws {
        #expect(try Parser.parse(fixture.source) == Parser.parse(fixture.expanded))
    }

    @Test
    func additionCompoundsUseABinaryDot() throws {
        #expect(try Parser.contains(Parser.parse("\\ce{CuSO4*5H2O}")) { $0 == .char("⋅", .bin) }, "addition dot")
    }

    @Test
    func aPlusBetweenSpeciesIsABinaryOperator() throws {
        let reaction = try Parser.parse("\\ce{2H2 + O2 -> 2H2O}")
        #expect(Parser.contains(reaction) { $0 == .char("+", .bin) }, "plus between species")
    }

    struct ArrowCase: Sendable, CustomTestStringConvertible {
        let source: String
        let symbol: String

        init(_ source: String, _ symbol: String) {
            self.source = source
            self.symbol = symbol
        }

        var testDescription: String { "\(source) becomes \(symbol)" }
    }

    @Test(arguments: [
        ArrowCase("->", "→"), ArrowCase("<-", "←"), ArrowCase("<->", "↔"), ArrowCase("<-->", "⇄"),
        ArrowCase("<=>", "⇌"), ArrowCase("<=>>", "⥂"), ArrowCase("<<=>", "⥄"),
    ])
    func reactionArrowsUseTheirExpectedSymbols(fixture: ArrowCase) throws {
        #expect(try Parser.arrow(Parser.parse("\\ce{A \(fixture.source) B}"))?.0 == fixture.symbol)
    }

    @Test
    func reactionArrowsNeedNoSpaces() throws {
        #expect(try Parser.arrow(Parser.parse("\\ce{A->B}"))?.0 == "→", "arrows need no spaces")
    }

    @Test
    func aReactionArrowKeepsItsLabelsAboveAndBelow() throws {
        let labelled = try #require(Parser.arrow(Parser.parse("\\ce{A ->[H2O][\\Delta] B}")), "labelled arrow parses")
        #expect(try labelled.1 == Parser.parse("\\mathrm{H}_{2}\\mathrm{O}") && labelled.2 == [.group([.char("Δ", .ord)])], "arrow labels above and below, with chemistry in the label")
    }

    @Test
    func aSingleArrowLabelGoesAbove() throws {
        #expect(try Parser.arrow(Parser.parse("\\ce{A ->[heat] B}"))?.2 == nil, "a single label goes above")
    }

    @Test
    func precipitateUsesADownArrow() throws {
        #expect(try Parser.contains(Parser.parse("\\ce{BaSO4 v}")) { $0 == .classed(.rel, [.char("↓", .rel)]) }, "precipitate")
    }

    @Test
    func gasUsesAnUpArrow() throws {
        #expect(try Parser.contains(Parser.parse("\\ce{H2 ^}")) { $0 == .classed(.rel, [.char("↑", .rel)]) }, "gas")
    }

    @Test
    func aCapitalVStaysVanadium() throws {
        #expect(try !Parser.contains(Parser.parse("\\ce{V2O5}")) { $0 == .char("↓", .rel) }, "a capital V is vanadium")
    }

    @Test
    func aMacroCanContainAChemicalFormula() throws {
        let nested = try Parser.parse("\\newcommand{\\water}{\\ce{H2O}}\\water")
        #expect(try nested == Parser.parse("\\ce{H2O}"), "chemistry inside a macro")
    }

    @Test
    func anUnclosedChemistryLabelPointsToTheCommand() throws {
        let unclosed = try Parser.failure("x + \\ce{A ->[heat B}")
        #expect(unclosed.message == "Missing ] in this formula" && unclosed.offset == 4, "chemistry errors point at \\ce")
    }

    @Test(arguments: [
        ErrorCase("ce needs an argument", "\\ce",
                  .exact("\\ce needs {…} after it")),
        ErrorCase("unknown bonds explain themselves", "\\ce{A\\bond{?}B}",
                  .exact("\\bond doesn't know \u{201C}?\u{201D}")),
    ])
    func chemistryCommandsExplainBadArguments(fixture: ErrorCase) throws {
        try NoteMathParserTestsSupport.expectError(fixture)
    }

    @Test(arguments: [
        ExpansionCase("bond commands match bond characters", "\\ce{A\\bond{-}B\\bond{=}C\\bond{#}D}",
                      "\\ce{A-B=C#D}"),
        ExpansionCase("numbered bonds", "\\ce{A\\bond{1}B\\bond{2}C\\bond{3}D}",
                      "\\ce{A-B=C#D}"),
    ])
    func bondNotationProducesTheExpectedFormula(fixture: ExpansionCase) throws {
        #expect(try Parser.parse(fixture.source) == Parser.parse(fixture.expanded))
    }

    @Test(arguments: ["~", "~-", "~=", "~--", "-~-", "...", "....", "->", "<-"])
    func eachNamedBondChangesTheFormula(bond: String) throws {
        let nodes = try Parser.parse("\\ce{A\\bond{\(bond)}B}")
        #expect(try nodes.count == 1 && !Parser.parse("\\ce{AB}").isEmpty && nodes != Parser.parse("\\ce{AB}"), "bond \(bond) draws something")
    }

    @Test(arguments: ["~", "~-", "~=", "~--", "-~-", "...", "...."])
    func eachDashedBondParses(bond: String) throws {
        _ = try Parser.parse("\\ce{C\\bond{\(bond)}C}")
    }

    @Test
    func aDashedBondStacksARaisedLineOnATinyTripleDash() throws {
        let wavy = String(describing: try Parser.parse("\\ce{A\\bond{~-}B}"))
        #expect(wavy.contains("raised(-0.1") && wavy.contains("sized(0.5"), "a dashed bond stacks a raised line over a tiny triple dash")
    }

    @Test
    func aRightArrowBondUsesARelationArrow() throws {
        #expect(try Parser.contains(Parser.parse("\\ce{A\\bond{->}B}")) { $0 == .char("→", .rel) }, "arrow bond")
    }

    @Test(arguments: [
        ExpansionCase("radical anion", "\\ce{OCO^{.-}}",
                      "{\\mathrm{O}\\mathrm{C}\\mathrm{O}^{\\cdot -}}"),
        ExpansionCase("radical with a count", "\\ce{NO^{(2.)-}}",
                      "{\\mathrm{N}\\mathrm{O}^{(2\\cdot )-}}"),
        ExpansionCase("one electron dot", "\\ce{Mg^.}",
                      "{\\mathrm{Mg}^{\\cdot}}"),
        ExpansionCase("two electron dots", "\\ce{M^{..}_i}",
                      "{\\mathrm{M}^{\\cdot \\cdot }_{i}}"),
        ExpansionCase("excited state keeps its asterisk", "\\ce{NO^*}",
                      "{\\mathrm{N}\\mathrm{O}^{*}}"),
        ExpansionCase("an italic variable subscript", "\\ce{NO_x}",
                      "{\\mathrm{N}\\mathrm{O}_{x}}"),
        ExpansionCase("an italic variable charge", "\\ce{Fe^n+}",
                      "{\\mathrm{Fe}^{n+}}"),
        ExpansionCase("hapticity then a bond", "\\ce{[Pt(\\eta^2-C2H4)Cl3]-}",
                      "{\\lbrack\\mathrm{Pt}(\\eta ^{2}{-}\\mathrm{C}_{2}\\mathrm{H}_{4})\\mathrm{Cl}_{3}\\rbrack^{-}}"),
        ExpansionCase("a space after a Greek letter is ignored", "\\ce{\\beta +}",
                      "{\\beta ^{+}}"),
        ExpansionCase("a second subscript gets its own base", "\\ce{CO3^2-_{(aq)}}",
                      "{\\mathrm{C}\\mathrm{O}_{3}^{2-}{}_{(\\mathrm{aq})}}"),
        ExpansionCase("math inside a state", "\\ce{NaOH(aq,$\\infty$)}",
                      "{\\mathrm{Na}\\mathrm{O}\\mathrm{H}\\mathrm{(}\\mathrm{aq}{,}{\\infty}\\mathrm{)}}"),
        ExpansionCase("circa", "\\ce{ZnS(\\ca$c$)}",
                      "{\\mathrm{Zn}\\mathrm{S}({\\sim}{c})}"),
        ExpansionCase("braces make upright text", "\\ce{{Gluconic Acid} + H2O2}",
                      "{\\text{Gluconic Acid} + \\mathrm{H}_{2}\\mathrm{O}_{2}}"),
        ExpansionCase("a braced hyphen isn't a bond", "\\ce{$cis${-}[PtCl2(NH3)2]}",
                      "{{cis}\\text{-}\\lbrack\\mathrm{Pt}\\mathrm{Cl}_{2}(\\mathrm{N}\\mathrm{H}_{3})_{2}\\rbrack}"),
        ExpansionCase("a spaced minus is an operator", "\\ce{A - B}",
                      "{\\mathrm{A} - \\mathrm{B}}"),
        ExpansionCase("a bare mass number belongs to the next element", "\\ce{H^3HO}",
                      "{\\mathrm{H}{}^{\\hphantom{3}}{}^{\\mathllap{3}}\\mathrm{H}\\mathrm{O}}"),
        ExpansionCase("orbitals", "\\ce{1s^2-N}",
                      "{1\\mathrm{s}^{2}{-}\\mathrm{N}}"),
        ExpansionCase("an italic n prefix", "\\ce{n-Pr}",
                      "{n{-}\\mathrm{Pr}}"),
        ExpansionCase("an italic i prefix", "\\ce{iPr}",
                      "{i\\mathrm{Pr}}"),
        ExpansionCase("chemistry inside \\frac", "\\ce{\\frac{[Hg^2+][Hg]}{[Hg2^2+]}}",
                      "{\\frac{\\lbrack\\mathrm{Hg}^{2+}\\rbrack\\lbrack\\mathrm{Hg}\\rbrack}{\\lbrack\\mathrm{Hg}_{2}^{2+}\\rbrack}}"),
        ExpansionCase("a tilde is a space", "\\ce{A~B}",
                      "{\\mathrm{A}\\ \\mathrm{B}}"),
    ])
    func chemicalScriptsAndSpecialFormsKeepTheirNotation(fixture: ExpansionCase) throws {
        #expect(try Parser.parse(fixture.source) == Parser.parse(fixture.expanded))
    }

    @Test
    func aParenthesizedPrecipitateKeepsItsBrackets() throws {
        #expect(try Parser.contains(Parser.parse("\\ce{A v B (v) -> B ^ B (^)}")) { $0 == .classed(.rel, [.char("(", .open), .char("↓", .rel), .char(")", .close)]) }, "precipitate in parentheses")
    }
}
