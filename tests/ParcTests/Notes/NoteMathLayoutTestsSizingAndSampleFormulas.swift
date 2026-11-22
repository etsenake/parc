import AppKit
import CoreText
import Testing
@testable import ParcCore
@testable import ParcNotes

@MainActor
struct NoteMathLayoutTestsSizingAndSampleFormulas {
    private let fixture: NoteMathLayoutTestsSupport.Fixture

    init() throws { fixture = try NoteMathLayoutTestsSupport.Fixture() }

    private struct SizeCase: Sendable, CustomTestStringConvertible {
        let command: String
        let factor: CGFloat
        var testDescription: String { command }
    }

    @Test(arguments: [SizeCase(command: "Huge", factor: 2.488), SizeCase(command: "tiny", factor: 0.5)])
    private func aSizeCommandScalesTheWidth(sample: SizeCase) throws {
        let scaled = try fixture.box("\\\(sample.command) x", display: false).width
        let normal = try fixture.box("x", display: false).width
        #expect(abs(scaled / normal - sample.factor) < 0.02)
    }

    @Test func sizesAreAbsoluteNotNested() throws {
        #expect(abs(try fixture.box("\\Huge{\\tiny x}", display: false).width - (try fixture.box("\\tiny x", display: false)).width) < 0.01)
    }

    @Test func normalsizeInAScriptKeepsTheScript() throws {
        #expect(abs(try fixture.box("x^{\\normalsize y}", display: false).width - (try fixture.box("x^{y}", display: false)).width) < 0.01)
    }

    @Test func raiseboxLiftsByItsLength() throws {
        #expect(abs(try fixture.box("\\raisebox{0.5em}{x}", display: false).ascent - (try fixture.box("\\text{x}", display: false)).ascent - 0.5 * fixture.size) < 0.01)
    }

    @Test func smashDropsTheHeight() throws {
        let smashed = try fixture.box("\\smash{\\frac{a}{b}}", display: false)
        #expect(smashed.ascent == 0)
        #expect(smashed.descent == 0)
    }

    @Test func smashKeepsTheInk() throws {
        let smashed = try fixture.box("\\smash{\\frac{a}{b}}", display: false)
        #expect(!smashed.inks.isEmpty)
    }

    @Test func smashBKeepsTheHeight() throws {
        let bottomless = try fixture.box("\\smash[b]{y}", display: false)
        #expect(bottomless.ascent > 0)
        #expect(bottomless.descent == 0)
    }

    @Test func substackStacksRows() throws {
        #expect(try fixture.box("\\substack{a\\\\b\\\\c}", display: false).height > (try fixture.box("\\substack{a}", display: false)).height * 2)
    }

    @Test func substackCellsUseScriptSize() throws {
        #expect(abs(try fixture.box("\\substack{a}", display: false).width - (try fixture.box("{\\scriptstyle a}", display: false)).width) < 0.01)
    }

    @Test func genfracDrawsItsOwnRuleThickness() throws {
        let thin = try fixture.box("\\genfrac{}{}{0.1em}{}{a}{b}", display: false)
        let found = thin.inks.compactMap { ink -> CGSize? in if case .rule(let ruleSize) = ink.content { return ruleSize }; return nil }
        #expect(found.count == 1)
        #expect(abs(found[0].height - 0.1 * fixture.size) < 0.01)
    }

    @Test func colorboxPadsByFboxsep() throws {
        #expect(abs(try fixture.box("\\colorbox{red}{hi}", display: false).width - (try fixture.box("\\text{hi}", display: false)).width - 0.6 * fixture.size) < 0.01)
    }

    @Test func theBackgroundDrawsFirst() throws {
        let colorBox = try fixture.box("\\colorbox{red}{hi}", display: false)
        #expect(colorBox.inks.first.map { if case .rule = $0.content, case .custom = $0.color { true } else { false } } == true)
    }

    @Test func fcolorboxAddsAFrame() throws {
        let framed = try fixture.box("\\fcolorbox{blue}{red}{hi}", display: false), text = try fixture.box("\\text{hi}", display: false)
        #expect(abs(framed.width - text.width - 0.68 * fixture.size) < 0.01)
        #expect(framed.inks.count == text.inks.count + 5)
    }

    @Test func hrefMakesAClickableLink() {
        let link = NoteMathRenderer.render("a + \\href{https://katex.org}{b}", fontSize: 40, color: .black, display: false)
        let marks = link.links(width: link.size.width)
        #expect(marks.count == 1)
        #expect(marks[0].url == "https://katex.org")
        #expect(marks[0].resolved)
        #expect(marks[0].rect.minX > link.size.width * 0.5)
    }

    @Test func urlUnderlines() throws {
        let url = try fixture.box("\\url{https://parc.is}", display: false)
        #expect(url.links.first?.url == "https://parc.is")
        #expect(url.inks.contains { if case .link = $0.color { true } else { false } })
    }

    @Test func overgroupArcsOverItsBase() throws {
        #expect(try fixture.box("\\overgroup{ABCD}", display: false).ascent > (try fixture.box("ABCD", display: false)).ascent + 0.1 * fixture.size)
    }

    @Test func undergroupHangsBelow() throws {
        #expect(try fixture.box("\\undergroup{ABCD}", display: false).descent > (try fixture.box("ABCD", display: false)).descent + 0.1 * fixture.size)
    }

    @Test func tripledashKeepsAMinusStrut() throws { #expect(try fixture.box("\\tripledash", display: false).ascent >= (try fixture.box("-", display: false)).ascent - 0.01) }

    @Test func aDashedBondAddsItsDashesAboveTheLine() throws {
        #expect(try fixture.box("\\ce{A\\bond{~-}B}", display: false).inks.count > (try fixture.box("\\ce{A\\bond{-}B}", display: false)).inks.count)
    }

    @Test(arguments: ["~", "~-", "~=", "~--", "-~-", "...", "...."]) func aBondDrawsBetweenTheAtoms(bond: String) {
        let rendering = NoteMathRenderer.render("\\ce{C\\bond{\(bond)}C}", fontSize: 30, color: .black, display: false)
        #expect(rendering.error == nil)
        #expect(fixture.bitmap(rendering).ink(x: 0.35...0.65, y: 0...1) > 4)
    }

    nonisolated private static let formulas = [
        "x = \\frac{-b \\pm \\sqrt{b^2 - 4ac}}{2a}", "e^{i\\pi} + 1 = 0", "\\nabla \\times \\vec{E} = -\\frac{\\partial \\vec{B}}{\\partial t}",
        "\\int_{-\\infty}^{\\infty} e^{-x^2}\\,dx = \\sqrt{\\pi}", "\\sum_{n=1}^{\\infty} \\frac{1}{n^2} = \\frac{\\pi^2}{6}",
        "\\lim_{h \\to 0} \\frac{f(x+h) - f(x)}{h}", "\\mathbb{R}^n \\subseteq \\mathcal{L}(\\mathfrak{g}) \\cup \\boldsymbol{\\mu}",
        "\\begin{vmatrix} a & b \\\\ c & d \\end{vmatrix} = ad - bc", "\\begin{Bmatrix} 1 \\end{Bmatrix}\\begin{Vmatrix} 2 \\end{Vmatrix}",
        "|x| = \\begin{cases} x & \\text{if } x \\geq 0 \\\\ -x & \\text{otherwise} \\end{cases}",
        "\\begin{align*} f(x) &= (x+1)^2 \\\\ &= x^2 + 2x + 1 \\end{align*}", "\\begin{gathered} a = b \\\\ c = d \\end{gathered}",
        "\\oint_C \\mathbf{F} \\cdot d\\mathbf{r} = \\iint_S (\\nabla \\times \\mathbf{F}) \\cdot d\\mathbf{S}",
        "\\left\\langle \\psi \\middle| \\hat{H} \\middle| \\psi \\right\\rangle", "\\left\\lfloor \\frac{n}{2} \\right\\rfloor + \\left\\lceil \\frac{n}{2} \\right\\rceil = n",
        "\\binom{n}{k} = \\frac{n!}{k!(n-k)!}", "\\overbrace{1 + 2 + \\cdots + n}^{n \\text{ terms}} = \\underbrace{\\frac{n(n+1)}{2}}_{\\text{Gauss}}",
        "\\color{#e03e3e}{a^2} + \\textcolor{blue}{b^2}", "\\operatorname*{arg\\,max}_{\\theta} \\log p(x \\mid \\theta)",
        "\\sqrt[3]{\\frac{\\alpha}{\\beta}} \\approx \\tilde{x} \\ne \\bar{y} \\equiv \\dot{z} \\sim \\ddot{w}",
        "\\widetilde{abc} \\widehat{xyz} \\overleftarrow{AB} \\underrightarrow{CD} \\overleftrightarrow{EF}", "A \\longleftarrow B \\Longrightarrow C",
        "\\Bigl( \\bigl[ x \\bigr] \\Bigr) \\quad \\biggl\\{ y \\biggr\\} \\Biggl| z \\Biggr|", "\\begin{array}{|l|c|r|} \\hline 1 & 2 & 3 \\\\ \\hline \\end{array}",
        "\\boxed{E = mc^2} \\phantom{x} \\hphantom{y} \\vphantom{\\frac{a}{b}}", "\\displaystyle\\sum_i x_i \\textstyle\\sum_i x_i \\scriptstyle x \\scriptscriptstyle y",
        "\\forall \\epsilon > 0\\ \\exists \\delta > 0 : |x - a| < \\delta \\implies |f(x) - f(a)| < \\epsilon", "f'(x) = f''(x) + f'''(x)",
        "\\text{Résumé: 😀 数学}", "\\begin{smallmatrix} a & b \\\\ c & d \\end{smallmatrix}", "\\stackrel{\\text{def}}{=} \\overset{?}{=} \\underset{n}{\\max}",
        "x \\in \\{1, 2, 3\\} \\setminus \\emptyset", "A \\xrightarrow[\\text{under}]{f \\circ g} B \\xLeftrightarrow{} C \\xmapsto{n} D \\xhookrightarrow{i} E",
        "\\cancel{a} \\bcancel{b} \\xcancel{c} \\sout{d} \\in \\R \\setminus \\Q",
        "\\newcommand{\\norm}[1]{\\left\\lVert #1 \\right\\rVert} \\norm{\\vec{v}} \\le \\norm{u}", "\\ce{2H2 + O2 -> 2H2O}",
        "\\ce{Fe2(SO4)3 + 3Ba^2+ -> 3BaSO4 v + 2Fe^3+}", "\\ce{CaCO3(s) ->[\\Delta] CaO(s) + CO2(g) ^}",
        "\\ce{CH3COOH <=> CH3COO- + H+} \\quad \\ce{A <=>> B} \\quad \\ce{C <<=> D} \\quad \\ce{E <--> F}",
        "\\ce{^{235}_{92}U + ^{1}_{0}n -> ^{141}_{56}Ba + ^{92}_{36}Kr + 3^{1}_{0}n}", "\\ce{CuSO4*5H2O} \\quad \\ce{H-C#C-H} \\quad \\ce{[Cu(NH3)4]^2+}",
        "\\Delta H = \\pu{-285.8 kJ/mol} \\quad \\pu{6.022e23 mol-1} \\quad \\pu{25 °C}", "\\begin{equation*} \\llap{a}b \\mathrlap{c}d \\clap{e} \\end{equation*}",
    ]

    @Test(arguments: NoteMathLayoutTestsSizingAndSampleFormulas.formulas)
    func aSampleFormulaRendersInDisplayStyle(formula: String) {
        let rendering = NoteMathRenderer.render(formula, fontSize: 18, color: .black, display: true)
        #expect(rendering.error == nil)
        #expect(rendering.size.width.isFinite && rendering.size.height.isFinite)
        #expect(fixture.bitmap(rendering, scale: 1).ink(x: 0...1, y: 0...1) > 0)
    }

    @Test(arguments: NoteMathLayoutTestsSizingAndSampleFormulas.formulas)
    func aSampleFormulaRendersInlineToo(formula: String) {
        let rendering = NoteMathRenderer.render(formula, fontSize: 18, color: .black, display: false)
        #expect(rendering.error == nil)
        #expect(rendering.size.width.isFinite && rendering.size.height.isFinite)
        #expect(fixture.bitmap(rendering, scale: 1).ink(x: 0...1, y: 0...1) > 0)
    }
}
