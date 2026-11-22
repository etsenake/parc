import Foundation
import Testing
@testable import ParcCore

struct NoteMathParserTestsDecorationsAndStylesTests {
    typealias NodeCase = NoteMathParserTestsSupport.NodeCase
    private typealias Parser = NoteMathParserTestsSupport

    @Test(arguments: [
        NodeCase("utilde", "\\utilde{AB}") { [.decorated(.underArrow("\u{0330}"), [.char("A", .ord), .char("B", .ord)])] },
        NodeCase("Overrightarrow", "\\Overrightarrow{AB}") { [.decorated(.overArrow("\u{21D2}"), [.char("A", .ord), .char("B", .ord)])] },
        NodeCase("overleftharpoon", "\\overleftharpoon{AB}") { [.decorated(.overArrow("\u{21BC}"), [.char("A", .ord), .char("B", .ord)])] },
        NodeCase("overrightharpoon", "\\overrightharpoon{AB}") { [.decorated(.overArrow("\u{21C0}"), [.char("A", .ord), .char("B", .ord)])] },
        NodeCase("overlinesegment", "\\overlinesegment{AB}") { [.decorated(.lineSegment(true), [.char("A", .ord), .char("B", .ord)])] },
        NodeCase("underlinesegment", "\\underlinesegment{AB}") { [.decorated(.lineSegment(false), [.char("A", .ord), .char("B", .ord)])] },
        NodeCase("phase", "\\phase{AB}") { [.decorated(.phase, [.char("A", .ord), .char("B", .ord)])] },
        NodeCase("underbar underlines text", "\\underbar{ab}") { [.decorated(.underline, [.text("ab", .roman)])] },
        NodeCase("xlongequal", "\\xlongequal{a}") { [.extensibleArrow("=", over: [.char("a", .ord)], under: nil)] },
        NodeCase("xtwoheadrightarrow", "\\xtwoheadrightarrow{a}") { [.extensibleArrow("↠", over: [.char("a", .ord)], under: nil)] },
        NodeCase("xtwoheadleftarrow", "\\xtwoheadleftarrow[b]{a}") { [.extensibleArrow("↞", over: [.char("a", .ord)], under: [.char("b", .ord)])] },
        NodeCase("overgroup", "\\overgroup{AB}") { [.decorated(.overArrow("\u{23E0}"), [.char("A", .ord), .char("B", .ord)])] },
        NodeCase("undergroup", "\\undergroup{AB}") { [.decorated(.underArrow("\u{23E1}"), [.char("A", .ord), .char("B", .ord)])] },
        NodeCase("hat", "\\hat{x}") { [.decorated(.accent("\u{0302}"), [.char("x", .ord)])] },
        NodeCase("unbraced vec", "\\vec v") { [.decorated(.accent("\u{20D7}"), [.char("v", .ord)])] },
        NodeCase("widehat", "\\widehat{AB}") { [.decorated(.wideAccent("\u{0302}"), [.char("A", .ord), .char("B", .ord)])] },
        NodeCase("overline and underline", "\\overline{z}\\underline{w}") { [.decorated(.overline, [.char("z", .ord)]), .decorated(.underline, [.char("w", .ord)])] },
        NodeCase("over arrow", "\\overrightarrow{AB}") { [.decorated(.overArrow("→"), [.char("A", .ord), .char("B", .ord)])] },
        NodeCase("labelled arrow with both labels", "\\xrightarrow[a]{b}") { [.extensibleArrow("→", over: [.char("b", .ord)], under: [.char("a", .ord)])] },
        NodeCase("empty labelled arrow", "\\xLeftarrow{}") { [.extensibleArrow("⇐", over: [], under: nil)] },
        NodeCase("cancel family", "\\cancel{x}\\bcancel{y}\\xcancel{z}\\sout{w}") { [
            .decorated(.cancel, [.char("x", .ord)]), .decorated(.backCancel, [.char("y", .ord)]),
            .decorated(.crossCancel, [.char("z", .ord)]), .decorated(.strike, [.char("w", .ord)]),
            ] },
    ])
    func decorationsKeepTheirExpectedShapeAndContent(fixture: NodeCase) throws {
        #expect(try Parser.parse(fixture.source) == fixture.expected())
    }

    @Test
    func anActuarialAngleTakesBracedOrBareContents() throws {
        #expect(try Parser.parse("\\angl{n}") == [.decorated(.actuarialAngle, [.char("n", .ord)])] && Parser.parse("\\angln") == Parser.parse("\\angl{n}"), "angl")
    }

    @Test
    func anOverbraceTakesASuperscriptLabel() throws {
        #expect(try Parser.parse("\\overbrace{a+b}^{n}").first.map { node in
            if case .scripts(.decorated(.overbrace, _)?, [.char("n", .ord)]?, nil) = node { return true }
            return false
        } == true, "overbrace label")
    }

    @Test
    func anUnderbraceTakesASubscriptLabel() throws {
        #expect(try Parser.parse("\\underbrace{x}_{k}").count == 1, "underbrace label")
    }

    @Test(arguments: [
        NodeCase("blackboard bold", "\\mathbb{R}") { [.styled(.doubleStruck, [.char("R", .ord)])] },
        NodeCase("font commands", "\\mathcal{L}\\mathfrak{g}\\mathsf{x}\\mathtt{y}\\mathrm{d}\\mathbf{v}\\mathit{w}\\boldsymbol{\\mu}") { [
            .styled(.script, [.char("L", .ord)]), .styled(.fraktur, [.char("g", .ord)]), .styled(.sansSerif, [.char("x", .ord)]),
            .styled(.monospace, [.char("y", .ord)]), .styled(.roman, [.char("d", .ord)]), .styled(.bold, [.char("v", .ord)]),
            .styled(.italic, [.char("w", .ord)]), .styled(.boldItalic, [.char("μ", .ord)]),
            ] },
        NodeCase("colour switch covers the rest of the group", "a \\color{red} b + c") { [.char("a", .ord), .colored(NoteMathColor(red: 1, green: 0, blue: 0), [.char("b", .ord), .char("+", .bin), .char("c", .ord)])] },
        NodeCase("textcolor with short hex", "\\textcolor{#00f}{y} z") { [.colored(NoteMathColor(red: 0, green: 0, blue: 1), [.char("y", .ord)]), .char("z", .ord)] },
        NodeCase("bare hex colour", "\\color{FF8000}x") { [.colored(NoteMathColor(red: 1, green: 128.0 / 255, blue: 0), [.char("x", .ord)])] },
        NodeCase("style switch", "{\\displaystyle x}") { [.group([.mathStyle(.display, [.char("x", .ord)])])] },
    ])
    func fontAndColorCommandsKeepTheirStyle(fixture: NodeCase) throws {
        #expect(try Parser.parse(fixture.source) == fixture.expected())
    }

    @Test
    func spacingCommandsUseTeXWidths() throws {
        let spaces: [Double] = try Parser.parse("a\\,b\\:c\\;d\\!e\\quad f\\qquad g~h").compactMap { node in
            if case .space(let amount) = node { return amount }
            return nil
        }
        let expectedSpaces: [Double] = [3.0 / 18, 4.0 / 18, 5.0 / 18, -3.0 / 18, 1, 2, 1.0 / 3]
        #expect(spaces == expectedSpaces, "spacing commands")
    }

    @Test(arguments: [
        NodeCase("negations", "\\not= \\not\\in \\not<") { [.char("≠", .rel), .char("∉", .rel), .char("≮", .rel)] },
        NodeCase("overset", "\\overset{!}{=}") { [.stacked(base: [.char("=", .rel)], over: [.char("!", .close)], under: nil)] },
        NodeCase("top-level line breaks", "a \\\\ b") { [.lines([[.char("a", .ord)], [.char("b", .ord)]])] },
        NodeCase("number set shorthands", "\\R\\N\\Z\\Q\\C") { ["ℝ", "ℕ", "ℤ", "ℚ", "ℂ"].map { .char($0, .ord) } },
        NodeCase("colon spaces like amsmath and ltimes is binary", "f\\colon A \\ltimes B") { [.char("f", .ord), .group([.space(2.0 / 18), .char(":", .punct), .space(6.0 / 18)]),
            .char("A", .ord), .char("⋉", .bin), .char("B", .ord)] },
        NodeCase("math classes", "\\mathrel{x}\\mathbin{y}") { [.classed(.rel, [.char("x", .ord)]), .classed(.bin, [.char("y", .ord)])] },
    ])
    func spacingAndClassificationCommandsKeepTheirNodeTypes(fixture: NodeCase) throws {
        #expect(try Parser.parse(fixture.source) == fixture.expected())
    }

    @Test
    func stackrelKeepsTheRelationClass() throws {
        #expect(try Parser.parse("\\stackrel{def}{=}").first.map { node in
            if case .classed(.rel, _) = node { return true }
            return false
        } == true, "stackrel is a relation")
    }
}
