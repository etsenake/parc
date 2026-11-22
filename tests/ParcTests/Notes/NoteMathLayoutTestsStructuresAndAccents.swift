import AppKit
import CoreText
import Testing
@testable import Parc
@testable import ParcCore

@MainActor
struct NoteMathLayoutTestsStructuresAndAccents {
    private let fixture: NoteMathLayoutTestsSupport.Fixture

    init() throws { fixture = try NoteMathLayoutTestsSupport.Fixture() }

    @Test func aFractionIsTallerThanItsNumerator() throws { #expect(try fixture.box("\\frac{a}{b}").height > (try fixture.box("a")).height * 2) }

    @Test func theFractionStacksTheNumeratorOverTheDenominator() throws {
        let fraction = try fixture.box("\\frac{a}{b}")
        let a = fixture.inks(fraction, glyph: fixture.glyph("𝑎")), b = fixture.inks(fraction, glyph: fixture.glyph("𝑏"))
        #expect(a.count == 1)
        #expect(b.count == 1)
        #expect(a[0].origin.y > 0)
        #expect(b[0].origin.y < 0)
    }

    @Test func aFractionHasOneRuleOnTheMathAxisCoveringTheNumerator() throws {
        let fraction = try fixture.box("\\frac{a}{b}")
        let found = fixture.rules(fraction)
        #expect(found.count == 1)
        guard let rule = found.first, case .rule(let ruleSize) = rule.content else { return }
        #expect(abs(rule.origin.y + ruleSize.height / 2 - fixture.axis) < 0.01)
        #expect(ruleSize.width >= (try fixture.box("a")).width)
    }

    @Test func displayFractionsAreBigger() throws {
        #expect(try fixture.box("\\frac{a}{b}", display: true).height > (try fixture.box("\\frac{a}{b}", display: false)).height)
    }

    @Test func tfracIsSmallerThanDfrac() throws { #expect(try fixture.box("\\tfrac{a}{b}").height < (try fixture.box("\\dfrac{a}{b}")).height) }

    @Test func binomialsHaveNoRule() throws { #expect(fixture.rules(try fixture.box("\\binom{n}{k}")).isEmpty) }

    @Test func binomialsHaveParentheses() throws { #expect(try fixture.box("\\binom{n}{k}").width > (try fixture.box("\\frac{n}{k}")).width) }

    @Test func nestedFractionsStack() throws { #expect(try fixture.box("\\frac{\\frac{1}{2}}{3}").height > (try fixture.box("\\frac{a}{b}")).height) }

    @Test func aRadicalWrapsItsRadicand() throws {
        let root = try fixture.box("\\sqrt{x}"), x = try fixture.box("x")
        #expect(root.width > x.width)
        #expect(root.ascent > x.ascent)
    }

    @Test func aRadicalHasAnOverbar() throws { #expect(!fixture.rules(try fixture.box("\\sqrt{x}")).isEmpty) }

    @Test func aTallRadicandPicksABiggerRadical() throws {
        let tall = try fixture.box("\\sqrt{\\frac{a}{b}}")
        let surdGlyphs = tall.inks.compactMap { ink -> CGGlyph? in
            if case .glyph(let glyph, _) = ink.content, ink.origin.x < 1 { return glyph }
            return nil
        }
        #expect(!surdGlyphs.contains(fixture.glyph("√")))
    }

    @Test func theDegreeTakesRoom() throws { #expect(try fixture.box("\\sqrt[3]{x}").width > (try fixture.box("\\sqrt{x}")).width) }

    @Test func radicalsStretchToTallContent() throws {
        #expect(try fixture.box("\\sqrt{\\begin{matrix}1\\\\2\\\\3\\\\4\\\\5\\\\6\\end{matrix}}").height > fixture.size * 6)
    }

    private func sumExtents() throws -> (display: CGRect, text: CGRect, displayBox: NoteMathBox, textBox: NoteMathBox) {
        let display = try fixture.box("\\sum_{i=1}^{n} i")
        let text = try fixture.box("\\sum_{i=1}^{n} i", display: false)
        let variants = fixture.font.verticalConstruction(fixture.glyph("∑"))?.variants ?? []
        let shown = display.inks.filter { if case .glyph(let g, _) = $0.content { return variants.contains { $0.glyph == g } } else { return false } }
        return (fixture.extent(shown), fixture.extent(fixture.inks(text, glyph: fixture.glyph("∑"))), display, text)
    }

    @Test func displaySumsAreBigger() throws {
        let sums = try sumExtents()
        #expect(sums.display.height > sums.text.height)
    }

    @Test func displayLimitsSitAbove() throws {
        let sums = try sumExtents()
        let n = fixture.inks(sums.displayBox, glyph: fixture.scriptGlyph("𝑛", 1))
        #expect(n.count == 1)
        #expect(fixture.extent(n).minY > sums.display.maxY)
    }

    @Test func theLowerLimitSitsBelow() throws {
        let sums = try sumExtents()
        let i = fixture.inks(sums.displayBox, glyph: fixture.scriptGlyph("𝑖", 1)).sorted { $0.origin.y < $1.origin.y }
        #expect(fixture.extent([i[0]]).maxY < sums.display.minY)
    }

    @Test func textStyleLimitsGoBeside() throws {
        let sums = try sumExtents()
        let textN = fixture.inks(sums.textBox, glyph: fixture.scriptGlyph("𝑛", 1))
        #expect(textN.count == 1)
        #expect(textN[0].origin.x > sums.text.maxX - 1)
    }

    @Test func integralLimitsGoBesideNudgedByItsSlant() throws {
        let integral = try fixture.box("\\int_0^1 f")
        let one = fixture.inks(integral, glyph: fixture.scriptGlyph("1", 1)), zero = fixture.inks(integral, glyph: fixture.scriptGlyph("0", 1))
        #expect(one.count == 1)
        #expect(zero.count == 1)
        #expect(one[0].origin.x > zero[0].origin.x)
    }

    @Test func limitsStackIntegralLimits() throws {
        let beside = fixture.inks(try fixture.box("\\int_0^1 f"), glyph: fixture.scriptGlyph("1", 1))
        let stacked = fixture.inks(try fixture.box("\\int\\limits_0^1 f"), glyph: fixture.scriptGlyph("1", 1))
        #expect(stacked.count == 1)
        #expect(stacked[0].origin.y > beside[0].origin.y)
    }

    @Test func limPutsItsLimitUnderneathInDisplay() throws {
        #expect(try fixture.box("\\lim_{x\\to 0} f").descent > (try fixture.box("\\lim f")).descent + fixture.size * 0.3)
    }

    @Test func bigOperatorsCentreOnTheAxis() throws {
        let sums = try sumExtents()
        #expect(abs((sums.text.minY + sums.text.maxY) / 2 - fixture.axis) < 0.5)
    }

    private func delimiterExtent(_ latex: String) throws -> CGRect { fixture.extent(try fixture.box(latex).inks.filter { $0.origin.x < 0.5 }) }

    @Test func bigDelimitersGrow() throws {
        let small = try delimiterExtent("\\left( x \\right)")
        let medium = try delimiterExtent("\\left( \\frac{a}{b} \\right)")
        let large = try delimiterExtent("\\left( \\frac{\\frac{a}{b}}{\\frac{c}{d}} \\right)")
        #expect(small.height < medium.height)
        #expect(medium.height < large.height)
    }

    private let tallColumn = "\\begin{matrix}1\\\\2\\\\3\\\\4\\\\5\\\\6\\\\7\\\\8\\end{matrix}"

    @Test func veryTallDelimitersAreAssembledFromParts() throws {
        #expect(try fixture.box("\\left( \(tallColumn) \\right)").inks.filter { $0.origin.x < 0.5 }.count > 2)
    }

    @Test func theAssemblyCoversTheContent() throws {
        let content = try fixture.box(tallColumn)
        let leftInks = try fixture.box("\\left( \(tallColumn) \\right)").inks.filter { $0.origin.x < 0.5 }
        #expect(fixture.extent(leftInks).height >= content.height * 0.9)
    }

    @Test func aMiddleDelimiterIsDrawn() throws { #expect(fixture.inks(try fixture.box("\\left\\{ x \\middle| x > 0 \\right\\}"), glyph: fixture.glyph("|")).count == 1) }

    @Test func aNullDelimiterKeepsASliverOfSpace() throws { #expect(try fixture.box("\\left. x \\right|").width > (try fixture.box("x")).width) }

    @Test func bigBiggAndBiggestGrow() throws {
        let sizes = try ["\\big(", "\\Big(", "\\bigg(", "\\Bigg("].map { fixture.extent(try fixture.box($0).inks).height }
        #expect(sizes == sizes.sorted())
        #expect(Set(sizes).count == 4)
    }

    @Test func delimitersWithoutAssembliesUseTheirLargestVariant() throws {
        let angle = try delimiterExtent("\\left\\langle \\begin{matrix}1\\\\2\\\\3\\\\4\\\\5\\\\6\\\\7\\\\8\\\\9\\\\10\\end{matrix} \\right\\rangle")
        #expect(angle.height > fixture.size * 3)
    }

    @Test func aHatSitsAboveItsBase() throws {
        let x = try fixture.box("x"), hat = try fixture.box("\\hat{x}")
        #expect(hat.ascent > x.ascent)
    }

    @Test func aHatKeepsTheWidthOfItsBase() throws {
        let x = try fixture.box("x"), hat = try fixture.box("\\hat{x}")
        #expect(abs(hat.width - x.width + fixture.font.italicCorrection(fixture.glyph("𝑥")) * fixture.size / 1000) < 0.5)
    }

    @Test func hatUsesTheCombiningCircumflex() throws { #expect(fixture.inks(try fixture.box("\\hat{x}"), glyph: fixture.glyph("\u{0302}")).count == 1) }

    @Test func accentsRiseOverTallBases() throws {
        let tallAccent = fixture.inks(try fixture.box("\\hat{A}"), glyph: fixture.font.flattenedAccent(fixture.glyph("\u{0302}")) ?? fixture.glyph("\u{0302}"))
        #expect(tallAccent.first.map { $0.origin.y > 0 } == true)
    }

    @Test func widehatPicksAWiderVariant() throws { #expect(fixture.inks(try fixture.box("\\widehat{xyz}"), glyph: fixture.glyph("\u{0302}")).isEmpty) }

    @Test func overArrowsStretchAcrossTheirBase() throws {
        let letters = Set(["𝐴", "𝐵", "𝐶", "𝐷"].map(fixture.glyph))
        let arrowInks = try fixture.box("\\overrightarrow{ABCD}").inks.filter { ink in
            if case .glyph(let value, _) = ink.content { return !letters.contains(value) }
            return false
        }
        #expect(fixture.extent(arrowInks).width >= (try fixture.box("ABCD")).width * 0.95)
    }

    @Test func overbraceAndItsLabelStackUp() throws {
        #expect(try fixture.box("\\overbrace{a+b+c}^{n}").ascent > (try fixture.box("a+b+c")).ascent + fixture.size * 0.4)
    }

    @Test func underbraceAndItsLabelHangDown() throws {
        #expect(try fixture.box("\\underbrace{a+b+c}_{n}").descent > (try fixture.box("a+b+c")).descent + fixture.size * 0.4)
    }

    @Test func labelledArrowsStretchPastTheirLabel() throws {
        let label = try fixture.box("\\xrightarrow{\\text{long label}}")
        let labelWidth = try fixture.box("\\scriptstyle\\text{long label}").width
        let arrow = fixture.extent(label.inks.filter { if case .glyph = $0.content { return true } else { return false } })
        #expect(arrow.width > labelWidth)
        #expect(label.width > labelWidth)
    }

    @Test func theLabelSitsAboveTheArrow() throws { #expect(try fixture.box("\\xrightarrow{\\text{long label}}").ascent > fixture.size * 0.6) }

    @Test func anArrowMakesRoomForLabelsAboveAndBelow() throws {
        let both = try fixture.box("\\xleftarrow[below]{above}")
        #expect(both.descent > fixture.size * 0.3)
        #expect(both.ascent > fixture.size * 0.6)
    }

    @Test func emptyLabelledArrowsStillReadAsLongArrows() throws { #expect(try fixture.box("\\xLeftrightarrow{}").width >= fixture.size * 1.4 - 0.01) }

    @Test func cancelDrawsOneStroke() throws {
        let cancel = try fixture.box("\\cancel{x+y}")
        #expect(fixture.segments(cancel) == 1)
    }

    @Test func cancelKeepsTheWidthOfItsBase() throws {
        let cancel = try fixture.box("\\cancel{x+y}")
        #expect(abs(cancel.width - (try fixture.box("x+y")).width) < 0.01)
    }

    @Test func xcancelCrosses() throws { #expect(fixture.segments(try fixture.box("\\xcancel{x}")) == 2) }

    @Test func overlineAddsABarAbove() throws {
        let overline = try fixture.box("\\overline{xy}")
        #expect(overline.ascent > (try fixture.box("xy")).ascent)
        #expect(!fixture.rules(overline).isEmpty)
    }

    @Test func underlineHangsBelow() throws { #expect(try fixture.box("\\underline{xy}").descent > (try fixture.box("xy")).descent) }
}
