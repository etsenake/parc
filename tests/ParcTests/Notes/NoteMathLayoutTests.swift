import AppKit
import CoreText
import Testing
@testable import Parc
@testable import ParcCore

@MainActor
struct NoteMathLayoutTests {
    let font: NoteMathFont
    let size: CGFloat = 20

    init() throws {
        NoteEditorFixtures.useMathFont()
        font = try #require(NoteMathRenderer.font)
    }

    func box(_ latex: String, display: Bool = true) throws -> NoteMathBox {
        NoteMathTypesetter(font: font, baseSize: size).typeset(try NoteMathParser.parse(latex), display: display)
    }

    func tagged(_ latex: String) throws -> NoteMathBox {
        NoteMathTypesetter(font: font, baseSize: size).typeset(try NoteMathParser.parseEquation(latex, display: true), display: true)
    }

    func glyph(_ symbol: String) -> CGGlyph { font.glyph(for: symbol.unicodeScalars.first!) }

    func scriptGlyph(_ symbol: String, _ level: Int) -> CGGlyph { font.scriptGlyph(glyph(symbol), level: level) }

    func inks(_ box: NoteMathBox, glyph target: CGGlyph) -> [NoteMathInk] {
        box.inks.filter { ink in
            if case .glyph(let glyph, _) = ink.content { return glyph == target }
            return false
        }
    }

    func extent(_ inks: [NoteMathInk]) -> CGRect {
        inks.reduce(CGRect.null) { result, ink in
            guard case .glyph(let glyph, let ctFont) = ink.content else { return result }
            let scale = CTFontGetSize(ctFont) / font.unitsPerEm
            let bounds = font.metrics(glyph).bounds
            return result.union(CGRect(x: ink.origin.x + bounds.minX * scale, y: ink.origin.y + bounds.minY * scale,
                                       width: bounds.width * scale, height: bounds.height * scale))
        }
    }

    func rules(_ box: NoteMathBox) -> [NoteMathInk] {
        box.inks.filter { if case .rule = $0.content { return true } else { return false } }
    }

    func ruleCount(_ box: NoteMathBox) -> Int { rules(box).count }

    func segments(_ box: NoteMathBox) -> Int {
        box.inks.filter { if case .segment = $0.content { return true } else { return false } }.count
    }

    var axis: CGFloat { font.constants[.axisHeight] * size / 1000 }

    @Test func theFontHasAMathTable() { #expect(font.hasMathTable) }

    @Test func unitsPerEm() { #expect(font.unitsPerEm == 1000) }

    @Test func axisHeightIsAboutAQuarterEm() {
        #expect(font.constants[.axisHeight] > 200)
        #expect(font.constants[.axisHeight] < 300)
    }

    @Test func scriptScales() {
        #expect(font.constants.scriptPercentScaleDown == 70)
        #expect(font.constants.scriptScriptPercentScaleDown == 55)
    }

    @Test func constantsDecodeWithSigns() {
        #expect(font.constants[.fractionRuleThickness] > 0)
        #expect(font.constants[.radicalKernAfterDegree] < 0)
    }

    @Test func connectorOverlap() { #expect(font.minConnectorOverlap > 0) }

    @Test func parenthesesHaveVariantsAndAnAssembly() {
        let paren = font.verticalConstruction(glyph("("))
        #expect((paren?.variants.count ?? 0) > 5)
        #expect(paren?.parts.contains(where: { $0.isExtender }) == true)
    }

    @Test func overbraceAssemblesHorizontally() { #expect(font.horizontalConstruction(glyph("\u{23DE}"))?.parts.isEmpty == false) }

    @Test func italicFHasAnItalicCorrection() { #expect(font.italicCorrection(glyph("𝑓")) > 0) }

    @Test func italicXHasAnAccentAttachment() { #expect(font.topAccentAttachment(glyph("𝑥")) != nil) }

    @Test func italicVHasMathKerning() { #expect(font.kernSet(glyph("𝑉")) != nil) }

    @Test(arguments: [
        ("x", NoteMathVariant.normal, 0x1D465 as UInt32), ("h", .normal, 0x210E), ("α", .normal, 0x1D6FC), ("Γ", .normal, 0x393), ("2", .normal, 0x32),
        ("R", .doubleStruck, 0x211D), ("Z", .doubleStruck, 0x2124), ("L", .script, 0x2112), ("g", .fraktur, 0x1D524), ("v", .bold, 0x1D42F),
        ("Γ", .italic, 0x1D6E4), ("μ", .boldItalic, 0x1D741), ("x", .roman, 0x78), ("1", .monospace, 0x1D7F7), ("a", .sansSerif, 0x1D5BA),
        ("ϕ", .normal, 0x1D719), ("∂", .normal, 0x1D715),
    ] as [(String, NoteMathVariant, UInt32)])
    func aLetterMapsIntoItsAlphabetAndTheFontCoversIt(symbol: String, variant: NoteMathVariant, expected: UInt32) {
        let mapped = NoteMathAlphabet.map(symbol, variant: variant)
        #expect(mapped.unicodeScalars.first?.value == expected)
        #expect(font.glyph(for: mapped.unicodeScalars.first!) != 0)
    }

    @Test func boldTextMapsAsciiAndKeepsAccents() { #expect(NoteMathAlphabet.mapText("ab1é", style: .bold) == "𝐚𝐛𝟏é") }

    func advance(_ symbol: String) -> CGFloat { font.metrics(glyph(symbol)).advance * size / 1000 }

    @Test func binaryOperatorsGetMediumSpaces() throws {
        let gap = try box("a+b").width - (try box("a").width + (try box("b").width) + advance("+"))
        #expect(abs(gap - 2 * 4 * size / 18) < 0.01)
    }

    @Test func relationsGetThickSpaces() throws {
        let gap = try box("a=b").width - (try box("a").width + (try box("b").width) + advance("="))
        #expect(abs(gap - 2 * 5 * size / 18) < 0.01)
    }

    @Test func aLeadingMinusIsUnary() throws {
        #expect(abs(try box("-b").width - (advance("\u{2212}") + (try box("b").width))) < 0.01)
    }

    @Test func punctuationGetsAThinSpace() throws {
        #expect(try box("a,b").width > (try box("a").width) + (try box("b").width) + advance(",") + 0.1)
    }

    @Test func noMediumSpaceInsideScripts() throws {
        let sum = try box("x^{a+b}").width - (try box("x^{ab}").width)
        #expect(abs(sum - font.metrics(scriptGlyph("+", 1)).advance * size * 0.7 / 1000) < 0.01)
    }

    @Test func quadIsOneEm() throws {
        #expect(abs(try box("a\\quad b").width - (try box("a").width + (try box("b").width) + size)) < 0.01)
    }

    @Test func functionNamesAreUprightAndSpaced() throws { #expect(try box("\\sin x").width > (try box("sinx").width) - 3) }

    @Test func superscriptsAreRaised() throws {
        let two = inks(try box("x^2"), glyph: scriptGlyph("2", 1))
        #expect(two.count == 1)
        #expect(two[0].origin.y > size * 0.25)
    }

    @Test func aSuperscriptGrowsTheBox() throws {
        let raised = try box("x^2"), base = try box("x")
        #expect(raised.ascent > base.ascent)
        #expect(raised.width > base.width)
    }

    @Test func scriptSizeIsSeventyPercent() throws {
        let two = inks(try box("x^2"), glyph: scriptGlyph("2", 1))
        guard case .glyph(_, let scriptFont)? = two.first?.content else {
            Issue.record("the superscript is a glyph")
            return
        }
        #expect(abs(CTFontGetSize(scriptFont) - size * 0.7) < 0.01)
    }

    @Test func subscriptsAreLowered() throws {
        let lowered = try box("x_2")
        let sub = inks(lowered, glyph: scriptGlyph("2", 1))
        #expect(sub.count == 1)
        #expect(sub[0].origin.y < 0)
        #expect(lowered.descent > (try box("x")).descent)
    }

    func scriptPair() throws -> [NoteMathInk] { inks(try box("x_2^2"), glyph: scriptGlyph("2", 1)).sorted { $0.origin.y > $1.origin.y } }

    @Test func superscriptSitsAboveSubscript() throws {
        let pair = try scriptPair()
        #expect(pair.count == 2)
        #expect(pair[0].origin.y > 0)
        #expect(pair[1].origin.y < 0)
    }

    @Test func subAndSuperscriptKeepTheirGap() throws {
        let pair = try scriptPair()
        #expect(extent([pair[0]]).minY - extent([pair[1]]).maxY >= font.constants[.subSuperscriptGapMin] * size / 1000 - 0.01)
    }

    @Test func theSuperscriptIsNudgedByTheItalicCorrection() throws {
        let pair = try scriptPair()
        #expect(pair[0].origin.x > pair[1].origin.x)
    }

    @Test func primesRideHigh() throws {
        #expect(inks(try box("f'"), glyph: scriptGlyph("′", 1)).first.map { $0.origin.y > 0 } == true)
    }

    @Test func secondLevelScriptsAreFiftyFivePercent() throws {
        let nestedTwo = inks(try box("e^{x^2}"), glyph: scriptGlyph("2", 2))
        guard case .glyph(_, let tiny)? = nestedTwo.first?.content else {
            Issue.record("nested script exists")
            return
        }
        #expect(abs(CTFontGetSize(tiny) - size * 0.55) < 0.01)
    }

    @Test func aSuperscriptOnAClosingParen() throws { #expect(try box("(x+y)^2").ascent > (try box("(x+y)")).ascent) }

    @Test func aFractionIsTallerThanItsNumerator() throws { #expect(try box("\\frac{a}{b}").height > (try box("a")).height * 2) }

    @Test func numeratorAboveDenominatorBelow() throws {
        let fraction = try box("\\frac{a}{b}")
        let a = inks(fraction, glyph: glyph("𝑎")), b = inks(fraction, glyph: glyph("𝑏"))
        #expect(a.count == 1)
        #expect(b.count == 1)
        #expect(a[0].origin.y > 0)
        #expect(b[0].origin.y < 0)
    }

    @Test func aFractionHasOneRuleOnTheMathAxisCoveringTheNumerator() throws {
        let fraction = try box("\\frac{a}{b}")
        let found = rules(fraction)
        #expect(found.count == 1)
        guard let rule = found.first, case .rule(let ruleSize) = rule.content else { return }
        #expect(abs(rule.origin.y + ruleSize.height / 2 - axis) < 0.01)
        #expect(ruleSize.width >= (try box("a")).width)
    }

    @Test func displayFractionsAreBigger() throws {
        #expect(try box("\\frac{a}{b}", display: true).height > (try box("\\frac{a}{b}", display: false)).height)
    }

    @Test func tfracIsSmallerThanDfrac() throws { #expect(try box("\\tfrac{a}{b}").height < (try box("\\dfrac{a}{b}")).height) }

    @Test func binomialsHaveNoRule() throws { #expect(rules(try box("\\binom{n}{k}")).isEmpty) }

    @Test func binomialsHaveParentheses() throws { #expect(try box("\\binom{n}{k}").width > (try box("\\frac{n}{k}")).width) }

    @Test func nestedFractionsStack() throws { #expect(try box("\\frac{\\frac{1}{2}}{3}").height > (try box("\\frac{a}{b}")).height) }

    @Test func aRadicalWrapsItsRadicand() throws {
        let root = try box("\\sqrt{x}"), x = try box("x")
        #expect(root.width > x.width)
        #expect(root.ascent > x.ascent)
    }

    @Test func aRadicalHasAnOverbar() throws { #expect(!rules(try box("\\sqrt{x}")).isEmpty) }

    @Test func aTallRadicandPicksABiggerRadical() throws {
        let tall = try box("\\sqrt{\\frac{a}{b}}")
        let surdGlyphs = tall.inks.compactMap { ink -> CGGlyph? in
            if case .glyph(let glyph, _) = ink.content, ink.origin.x < 1 { return glyph }
            return nil
        }
        #expect(!surdGlyphs.contains(glyph("√")))
    }

    @Test func theDegreeTakesRoom() throws { #expect(try box("\\sqrt[3]{x}").width > (try box("\\sqrt{x}")).width) }

    @Test func radicalsStretchToTallContent() throws {
        #expect(try box("\\sqrt{\\begin{matrix}1\\\\2\\\\3\\\\4\\\\5\\\\6\\end{matrix}}").height > size * 6)
    }

    func sumExtents() throws -> (display: CGRect, text: CGRect, displayBox: NoteMathBox, textBox: NoteMathBox) {
        let display = try box("\\sum_{i=1}^{n} i")
        let text = try box("\\sum_{i=1}^{n} i", display: false)
        let variants = font.verticalConstruction(glyph("∑"))?.variants ?? []
        let shown = display.inks.filter { if case .glyph(let g, _) = $0.content { return variants.contains { $0.glyph == g } } else { return false } }
        return (extent(shown), extent(inks(text, glyph: glyph("∑"))), display, text)
    }

    @Test func displaySumsAreBigger() throws {
        let sums = try sumExtents()
        #expect(sums.display.height > sums.text.height)
    }

    @Test func displayLimitsSitAbove() throws {
        let sums = try sumExtents()
        let n = inks(sums.displayBox, glyph: scriptGlyph("𝑛", 1))
        #expect(n.count == 1)
        #expect(extent(n).minY > sums.display.maxY)
    }

    @Test func theLowerLimitSitsBelow() throws {
        let sums = try sumExtents()
        let i = inks(sums.displayBox, glyph: scriptGlyph("𝑖", 1)).sorted { $0.origin.y < $1.origin.y }
        #expect(extent([i[0]]).maxY < sums.display.minY)
    }

    @Test func textStyleLimitsGoBeside() throws {
        let sums = try sumExtents()
        let textN = inks(sums.textBox, glyph: scriptGlyph("𝑛", 1))
        #expect(textN.count == 1)
        #expect(textN[0].origin.x > sums.text.maxX - 1)
    }

    @Test func integralLimitsGoBesideNudgedByItsSlant() throws {
        let integral = try box("\\int_0^1 f")
        let one = inks(integral, glyph: scriptGlyph("1", 1)), zero = inks(integral, glyph: scriptGlyph("0", 1))
        #expect(one.count == 1)
        #expect(zero.count == 1)
        #expect(one[0].origin.x > zero[0].origin.x)
    }

    @Test func limitsStackIntegralLimits() throws {
        let beside = inks(try box("\\int_0^1 f"), glyph: scriptGlyph("1", 1))
        let stacked = inks(try box("\\int\\limits_0^1 f"), glyph: scriptGlyph("1", 1))
        #expect(stacked.count == 1)
        #expect(stacked[0].origin.y > beside[0].origin.y)
    }

    @Test func limPutsItsLimitUnderneathInDisplay() throws {
        #expect(try box("\\lim_{x\\to 0} f").descent > (try box("\\lim f")).descent + size * 0.3)
    }

    @Test func bigOperatorsCentreOnTheAxis() throws {
        let sums = try sumExtents()
        #expect(abs((sums.text.minY + sums.text.maxY) / 2 - axis) < 0.5)
    }

    func delimiterExtent(_ latex: String) throws -> CGRect { extent(try box(latex).inks.filter { $0.origin.x < 0.5 }) }

    @Test func bigDelimitersGrow() throws {
        let small = try delimiterExtent("\\left( x \\right)")
        let medium = try delimiterExtent("\\left( \\frac{a}{b} \\right)")
        let large = try delimiterExtent("\\left( \\frac{\\frac{a}{b}}{\\frac{c}{d}} \\right)")
        #expect(small.height < medium.height)
        #expect(medium.height < large.height)
    }

    let tallColumn = "\\begin{matrix}1\\\\2\\\\3\\\\4\\\\5\\\\6\\\\7\\\\8\\end{matrix}"

    @Test func veryTallDelimitersAreAssembledFromParts() throws {
        #expect(try box("\\left( \(tallColumn) \\right)").inks.filter { $0.origin.x < 0.5 }.count > 2)
    }

    @Test func theAssemblyCoversTheContent() throws {
        let content = try box(tallColumn)
        let leftInks = try box("\\left( \(tallColumn) \\right)").inks.filter { $0.origin.x < 0.5 }
        #expect(extent(leftInks).height >= content.height * 0.9)
    }

    @Test func aMiddleDelimiterIsDrawn() throws { #expect(inks(try box("\\left\\{ x \\middle| x > 0 \\right\\}"), glyph: glyph("|")).count == 1) }

    @Test func aNullDelimiterKeepsASliverOfSpace() throws { #expect(try box("\\left. x \\right|").width > (try box("x")).width) }

    @Test func bigBiggAndBiggestGrow() throws {
        let sizes = try ["\\big(", "\\Big(", "\\bigg(", "\\Bigg("].map { extent(try box($0).inks).height }
        #expect(sizes == sizes.sorted())
        #expect(Set(sizes).count == 4)
    }

    @Test func delimitersWithoutAssembliesUseTheirLargestVariant() throws {
        let angle = try delimiterExtent("\\left\\langle \\begin{matrix}1\\\\2\\\\3\\\\4\\\\5\\\\6\\\\7\\\\8\\\\9\\\\10\\end{matrix} \\right\\rangle")
        #expect(angle.height > size * 3)
    }

    @Test func aHatSitsAboveWithoutWidening() throws {
        let x = try box("x"), hat = try box("\\hat{x}")
        #expect(hat.ascent > x.ascent)
        #expect(abs(hat.width - x.width + font.italicCorrection(glyph("𝑥")) * size / 1000) < 0.5)
    }

    @Test func hatUsesTheCombiningCircumflex() throws { #expect(inks(try box("\\hat{x}"), glyph: glyph("\u{0302}")).count == 1) }

    @Test func accentsRiseOverTallBases() throws {
        let tallAccent = inks(try box("\\hat{A}"), glyph: font.flattenedAccent(glyph("\u{0302}")) ?? glyph("\u{0302}"))
        #expect(tallAccent.first.map { $0.origin.y > 0 } == true)
    }

    @Test func widehatPicksAWiderVariant() throws { #expect(inks(try box("\\widehat{xyz}"), glyph: glyph("\u{0302}")).isEmpty) }

    @Test func overArrowsStretchAcrossTheirBase() throws {
        let letters = Set(["𝐴", "𝐵", "𝐶", "𝐷"].map(glyph))
        let arrowInks = try box("\\overrightarrow{ABCD}").inks.filter { ink in
            if case .glyph(let value, _) = ink.content { return !letters.contains(value) }
            return false
        }
        #expect(extent(arrowInks).width >= (try box("ABCD")).width * 0.95)
    }

    @Test func overbraceAndItsLabelStackUp() throws {
        #expect(try box("\\overbrace{a+b+c}^{n}").ascent > (try box("a+b+c")).ascent + size * 0.4)
    }

    @Test func underbraceAndItsLabelHangDown() throws {
        #expect(try box("\\underbrace{a+b+c}_{n}").descent > (try box("a+b+c")).descent + size * 0.4)
    }

    @Test func labelledArrowsStretchPastTheirLabel() throws {
        let label = try box("\\xrightarrow{\\text{long label}}")
        let labelWidth = try box("\\scriptstyle\\text{long label}").width
        let arrow = extent(label.inks.filter { if case .glyph = $0.content { return true } else { return false } })
        #expect(arrow.width > labelWidth)
        #expect(label.width > labelWidth)
    }

    @Test func theLabelSitsAboveTheArrow() throws { #expect(try box("\\xrightarrow{\\text{long label}}").ascent > size * 0.6) }

    @Test func labelsAboveAndBelow() throws {
        let both = try box("\\xleftarrow[below]{above}")
        #expect(both.descent > size * 0.3)
        #expect(both.ascent > size * 0.6)
    }

    @Test func emptyLabelledArrowsStillReadAsLongArrows() throws { #expect(try box("\\xLeftrightarrow{}").width >= size * 1.4 - 0.01) }

    @Test func cancelStrikesWithoutChangingWidth() throws {
        let cancel = try box("\\cancel{x+y}")
        #expect(segments(cancel) == 1)
        #expect(abs(cancel.width - (try box("x+y")).width) < 0.01)
    }

    @Test func xcancelCrosses() throws { #expect(segments(try box("\\xcancel{x}")) == 2) }

    @Test func overlineAddsABarAbove() throws {
        let overline = try box("\\overline{xy}")
        #expect(overline.ascent > (try box("xy")).ascent)
        #expect(!rules(overline).isEmpty)
    }

    @Test func underlineHangsBelow() throws { #expect(try box("\\underline{xy}").descent > (try box("xy")).descent) }

    @Test func alignedLinesUpTheEqualsSigns() throws {
        let aligned = try box("\\begin{aligned} a &= b + c \\\\ x + y + z &= d \\end{aligned}")
        let equals = inks(aligned, glyph: glyph("="))
        #expect(equals.count == 2)
        #expect(abs(equals[0].origin.x - equals[1].origin.x) < 0.01)
        #expect(equals[0].origin.y > equals[1].origin.y)
    }

    @Test func matrixColumnsCentreTheirCells() throws {
        let matrix = try box("\\begin{matrix} 1 \\\\ 333 \\end{matrix}")
        #expect(abs(extent(inks(matrix, glyph: glyph("1"))).midX - extent(inks(matrix, glyph: glyph("3"))).midX) < 0.6)
    }

    @Test func matrixColumnsAlignWithAGap() throws {
        let columns = try box("\\begin{pmatrix} 1 & 2 \\\\ 3 & 4 \\end{pmatrix}")
        let x1 = inks(columns, glyph: glyph("1"))[0].origin.x, x3 = inks(columns, glyph: glyph("3"))[0].origin.x
        let x2 = inks(columns, glyph: glyph("2"))[0].origin.x, x4 = inks(columns, glyph: glyph("4"))[0].origin.x
        #expect(abs(x1 - x3) < 0.01)
        #expect(abs(x2 - x4) < 0.01)
        #expect(x2 > x1 + size * 0.9)
    }

    @Test func matricesCentreOnTheAxis() throws {
        let columns = try box("\\begin{pmatrix} 1 & 2 \\\\ 3 & 4 \\end{pmatrix}")
        #expect(abs((columns.ascent - columns.descent) / 2 - axis) < 0.5)
    }

    @Test func casesStackTheirRows() throws {
        #expect(try box("f = \\begin{cases} 1 & x > 0 \\\\ 0 & \\text{else} \\end{cases}").height > size * 1.8)
    }

    @Test func anArrayDrawsItsVerticalAndHorizontalRules() throws {
        #expect(ruleCount(try box("\\begin{array}{c|c} a & b \\\\ \\hline c & d \\end{array}")) == 2)
    }

    @Test func topLevelLineBreaksStackLines() throws { #expect(try box("a = b \\\\ c = d").height > size * 1.5) }

    @Test func linesAreCentred() throws {
        let centred = inks(try box("x \\\\ xxx"), glyph: glyph("𝑥"))
        let top = extent(centred.filter { $0.origin.y > 0 }), bottom = extent(centred.filter { $0.origin.y < 0 })
        #expect(abs(top.midX - bottom.midX) < 0.6)
        #expect(top.width < bottom.width)
    }

    @Test func alignatDropsAlignedsQuadBetweenPairs() throws {
        let alignat = try box("\\begin{alignat*}{2} a &= b & c &= d \\end{alignat*}")
        let aligned = try box("\\begin{aligned} a &= b & c &= d \\end{aligned}")
        #expect(abs(aligned.width - alignat.width - size) < 0.5)
    }

    func multlineRows() throws -> (NoteMathBox, [NoteMathInk]) {
        let multline = try box("\\begin{multline*} a+b+c+d+e \\\\ x \\\\ y \\end{multline*}")
        return (multline, multline.inks.sorted { $0.origin.y > $1.origin.y })
    }

    @Test func multlinesFirstLineHugsTheLeft() throws {
        let (_, rows) = try multlineRows()
        #expect(try #require(rows.first).origin.x < 0.2 * size)
    }

    @Test func multlinesLastLineHugsTheRight() throws {
        let (multline, rows) = try multlineRows()
        #expect(try #require(rows.last).origin.x > multline.width - size)
    }

    @Test func multlineCentresTheMiddleLine() throws {
        let (multline, rows) = try multlineRows()
        let first = try #require(rows.first), last = try #require(rows.last)
        let middle = rows.filter { abs($0.origin.y - (first.origin.y + last.origin.y) / 2) < 0.3 * size }
        #expect(middle.count == 1)
        #expect(abs(middle[0].origin.x - multline.width / 2) < 0.6 * size)
    }

    @Test func subarrayIsScriptSizedAndTight() throws {
        let subarray = try box("\\begin{subarray}{c} a \\\\ b \\end{subarray}"), matrix = try box("\\begin{matrix} a \\\\ b \\end{matrix}")
        #expect(subarray.height < matrix.height * 0.75)
        #expect(subarray.width < matrix.width)
    }

    @Test func subarrayLeftAlignsLeft() throws {
        let rows = try box("\\begin{subarray}{l} abc \\\\ d \\end{subarray}").inks.sorted { $0.origin.y > $1.origin.y }
        #expect(abs((rows.first?.origin.x ?? 1) - (rows.last?.origin.x ?? 0)) < 0.1 * size)
    }

    @Test func dcasesSetsItsCellsInDisplayStyle() throws {
        #expect(try box("\\begin{dcases} \\frac{1}{2} & x \\end{dcases}").height > (try box("\\begin{cases} \\frac{1}{2} & x \\end{cases}")).height)
    }

    @Test func darraySetsItsCellsInDisplayStyle() throws {
        #expect(try box("\\begin{darray}{c} \\sum_{i=1}^n i \\end{darray}").height > (try box("\\begin{array}{c} \\sum_{i=1}^n i \\end{array}")).height)
    }

    @Test func matrixStarRightPushesShortEntriesRight() throws {
        let right = try box("\\begin{matrix*}[r] 1 \\\\ -10 \\end{matrix*}").inks.max { $0.origin.y < $1.origin.y }
        let left = try box("\\begin{matrix*}[l] 1 \\\\ -10 \\end{matrix*}").inks.max { $0.origin.y < $1.origin.y }
        #expect((right?.origin.x ?? 0) > (left?.origin.x ?? 0) + 0.5 * size)
    }

    @Test func aDashedColumnDrawsAsDashes() throws { #expect(ruleCount(try box("\\begin{array}{c:c} a & b \\\\ c & d \\end{array}")) > 2) }

    @Test func aSolidColumnIsOneRule() throws { #expect(ruleCount(try box("\\begin{array}{c|c} a & b \\\\ c & d \\end{array}")) == 1) }

    @Test func hdashlineDrawsAsDashes() throws { #expect(ruleCount(try box("\\begin{array}{cc} a & b \\\\ \\hdashline c & d \\end{array}")) > 2) }

    @Test func cdArrowsReachAtLeastThreeEmsWithHalfEmGaps() throws {
        let plain = try box("\\begin{CD} A @>>> B \\end{CD}")
        let objects = try box("A").width + (try box("B").width)
        #expect(plain.width >= objects + 3 * size + size - 0.5)
    }

    @Test func labelsAboveStretchTheCDArrow() throws {
        let plain = try box("\\begin{CD} A @>>> B \\end{CD}")
        let labelled = try box("\\begin{CD} A @>{\\text{a long label}}>> B \\end{CD}")
        #expect(labelled.width > plain.width + size)
        #expect(labelled.ascent > plain.ascent)
    }

    @Test func labelsBelowHangUnderTheCDArrow() throws {
        #expect(try box("\\begin{CD} A @>>{g}> B \\end{CD}").descent > (try box("\\begin{CD} A @>>> B \\end{CD}")).descent)
    }

    @Test func atEqualsDrawsALongEquals() throws { #expect(ruleCount(try box("\\begin{CD} A @= B \\end{CD}")) == 2) }

    @Test func aVerticalArrowRowSitsBetweenObjects() throws {
        let column = try box("\\begin{CD} A \\\\ @VVV \\\\ B \\end{CD}")
        #expect(column.height > (try box("\\begin{matrix} A \\\\ B \\end{matrix}")).height + 0.8 * size)
    }

    @Test func sideLabelsWidenTheDiagramInsteadOfSpillingOut() throws {
        let column = try box("\\begin{CD} A \\\\ @VVV \\\\ B \\end{CD}")
        let sides = try box("\\begin{CD} A \\\\ @VfVgV \\\\ B \\end{CD}")
        #expect(sides.width > column.width + 0.3 * size)
        let ink = extent(sides.inks)
        #expect(ink.minX >= -0.01)
        #expect(ink.maxX <= sides.width + 0.01)
    }

    @Test func aSquareDiagramLaysOut() throws {
        let grid = try box("\\begin{CD} A @>>> B \\\\ @VVV @AAA \\\\ C @<<< D \\end{CD}")
        #expect(grid.width >= 2 * (try box("A")).width + 3 * size)
        #expect(grid.height > 2.5 * size)
    }

    @Test func scriptAlternatesExist() { #expect(font.hasScriptAlternates) }

    @Test(arguments: ["𝑥", "2", "+", "(", "∑", "′"])
    func aSymbolHasDistinctScriptLevels(symbol: String) {
        let one = scriptGlyph(symbol, 1), two = scriptGlyph(symbol, 2)
        #expect(one != glyph(symbol))
        #expect(two != one)
        #expect(two != glyph(symbol))
    }

    @Test func superscriptsUseLevelOneAlternates() throws {
        let level1 = try box("x^{y}")
        #expect(inks(level1, glyph: scriptGlyph("𝑦", 1)).count == 1)
        #expect(inks(level1, glyph: glyph("𝑦")).isEmpty)
    }

    @Test func secondLevelScriptsUseLevelTwoAlternates() throws { #expect(inks(try box("x^{y^{z}}"), glyph: scriptGlyph("𝑧", 2)).count == 1) }

    @Test func alternateGlyphsStillUseTheMathScriptScale() throws {
        let found = inks(try box("x^{y^{z}}"), glyph: scriptGlyph("𝑧", 2)).first
        guard case .glyph(_, let tiny)? = found?.content else {
            Issue.record("the level two glyph exists")
            return
        }
        #expect(abs(CTFontGetSize(tiny) - size * 0.55) < 0.01)
    }

    @Test func styleSwitchesPickTheMatchingLevel() throws {
        let styled = try box("\\scriptstyle a \\scriptscriptstyle b")
        #expect(inks(styled, glyph: scriptGlyph("𝑎", 1)).count == 1)
        #expect(inks(styled, glyph: scriptGlyph("𝑏", 2)).count == 1)
    }

    @Test func functionNamesInScriptsUseAlternates() throws { #expect(inks(try box("e^{\\sin x}"), glyph: scriptGlyph("s", 1)).count == 1) }

    @Test func textStyleFractionsUseScriptGlyphs() throws {
        #expect(inks(try box("\\frac{a}{b}", display: false), glyph: scriptGlyph("𝑎", 1)).count == 1)
    }

    @Test func smallDelimitersInScriptsUseAlternates() throws {
        #expect(inks(try box("x_{\\left( a \\right)}"), glyph: scriptGlyph("(", 1)).count == 1)
    }

    @Test func scriptSizeTwoIsWiderThanTheTextTwo() { #expect(font.metrics(scriptGlyph("2", 1)).advance > font.metrics(glyph("2")).advance) }

    @Test func tallBasesGetTheFlattenedAccent() throws {
        let flat = try #require(font.flattenedAccent(glyph("\u{0302}")))
        #expect(inks(try box("\\hat{A}"), glyph: flat).count == 1)
    }

    @Test func shortBasesKeepTheFullAccent() throws {
        let flat = try #require(font.flattenedAccent(glyph("\u{0302}")))
        #expect(inks(try box("\\hat{x}"), glyph: flat).isEmpty)
        #expect(inks(try box("\\hat{x}"), glyph: glyph("\u{0302}")).count == 1)
    }

    @Test func macrosLayOutLikeTheirExpansion() throws {
        #expect(abs(try box("\\newcommand{\\sq}[1]{#1^2}\\sq{x}").width - (try box("x^2")).width) < 0.001)
    }

    @Test func formulaNumbersAreSubscripts() throws {
        let two = inks(try box("\\ce{H2O}"), glyph: scriptGlyph("2", 1))
        #expect(two.count == 1)
        #expect(two[0].origin.y < 0)
    }

    @Test func elementsAreUpright() throws {
        let water = try box("\\ce{H2O}")
        #expect(inks(water, glyph: glyph("H")).count == 1)
        #expect(inks(water, glyph: glyph("𝐻")).isEmpty)
    }

    @Test func chargeAboveAndCountBelowShareAColumn() throws {
        let sulfate = try box("\\ce{SO4^2-}")
        let four = inks(sulfate, glyph: scriptGlyph("4", 1)), charge = inks(sulfate, glyph: scriptGlyph("2", 1))
        #expect(four.count == 1)
        #expect(charge.count == 1)
        #expect(four[0].origin.y < 0)
        #expect(charge[0].origin.y > 0)
        #expect(abs(four[0].origin.x - charge[0].origin.x) < 0.5)
    }

    @Test func isotopeNumbersRightAlignOnTheLeft() throws {
        let isotope = try box("\\ce{^{227}_{90}Th}")
        let seven = inks(isotope, glyph: scriptGlyph("7", 1)), zero = inks(isotope, glyph: scriptGlyph("0", 1))
        let scale = size * 0.7 / 1000
        let sevenRight = (seven.first?.origin.x ?? 0) + font.metrics(scriptGlyph("7", 1)).advance * scale
        let zeroRight = (zero.first?.origin.x ?? 0) + font.metrics(scriptGlyph("0", 1)).advance * scale
        #expect(seven.count == 1)
        #expect(zero.count == 1)
        #expect(abs(sevenRight - zeroRight) < 0.01)
        #expect(extent(seven).minY > extent(zero).maxY)
    }

    @Test func llapTakesNoWidth() throws { #expect(abs(try box("x\\llap{y}").width - (try box("x")).width) < 0.01) }

    @Test func llapOverlapsLeftwards() throws {
        let lapY = inks(try box("x\\llap{y}"), glyph: glyph("𝑦"))
        #expect(lapY.count == 1)
        #expect(lapY[0].origin.x < (try box("x")).width - 1)
    }

    func harpoonHalves(_ latex: String) throws -> (CGRect, CGRect) {
        let marks = try box(latex).inks.filter { ink in
            if case .glyph(let value, _) = ink.content { return value != glyph("A") && value != glyph("B") }
            return false
        }
        return (extent(marks.filter { extent([$0]).midY > axis }), extent(marks.filter { extent([$0]).midY < axis }))
    }

    @Test func equilibriumHarpoonsStackAroundTheAxis() throws {
        let balanced = try harpoonHalves("\\ce{A <=> B}")
        #expect(!balanced.0.isNull)
        #expect(!balanced.1.isNull)
    }

    @Test func balancedHarpoonsMatch() throws {
        let balanced = try harpoonHalves("\\ce{A <=> B}")
        #expect(abs(balanced.0.width - balanced.1.width) < 0.6)
        #expect(balanced.0.minY > balanced.1.maxY - 0.01)
    }

    @Test func theEquilibriumArrowIsLong() { #expect((try? harpoonHalves("\\ce{A <=> B}"))?.0.width ?? 0 >= size * 1.3) }

    @Test func rightLeaningEquilibriumHasALongTopHarpoon() throws {
        let right = try harpoonHalves("\\ce{A <=>> B}")
        #expect(right.0.width > right.1.width * 1.3)
    }

    @Test func leftLeaningEquilibriumHasALongBottomHarpoon() throws {
        let left = try harpoonHalves("\\ce{A <<=> B}")
        #expect(left.1.width > left.0.width * 1.3)
    }

    @Test func arrowLabelsSitAboveAndBelow() throws {
        let label = try box("\\ce{A ->[heat][cat] B}")
        #expect(label.ascent > size * 0.7)
        #expect(label.descent > size * 0.3)
    }

    @Test func arrowsStretchForLabels() throws {
        #expect(try box("\\ce{A ->[very long label] B}").width > (try box("\\ce{A -> B}")).width + size)
    }

    @Test func aPrecipitateArrow() throws { #expect(inks(try box("\\ce{BaSO4 v}"), glyph: glyph("↓")).count == 1) }

    @Test func unitsFollowTheirNumber() throws { #expect(try box("\\pu{9.81 m/s^2}").width > (try box("9.81")).width + size) }

    @Test func tagsOnASingleLineSitOnTheBaseline() throws {
        let single = try tagged("x = y \\tag{1}")
        #expect(single.tags.count == 1)
        #expect(abs(single.tags[0].baseline) < 0.001)
    }

    @Test func theTagStaysOutOfTheFormulaBox() throws {
        let single = try tagged("x = y \\tag{1}")
        #expect(abs(single.width - (try box("x = y")).width) < 0.001)
        #expect(single.inks.count == (try box("x = y")).inks.count)
    }

    @Test func alignTagsSitOnTheirRows() throws {
        let align = try tagged("\\begin{align} a &= b \\\\ c &= d \\end{align}")
        let equals = inks(align, glyph: glyph("=")).map(\.origin.y).sorted(by: >)
        let baselines = align.tags.map(\.baseline).sorted(by: >)
        #expect(align.tags.count == 2)
        #expect(equals.count == 2)
        #expect(zip(equals, baselines).allSatisfy { abs($0 - $1) < 0.001 })
    }

    @Test func notagLeavesTheNumberOnTheLastLine() throws {
        let align = try tagged("\\begin{align} a &= b \\\\ c &= d \\end{align}")
        let equals = inks(align, glyph: glyph("=")).map(\.origin.y).sorted(by: >)
        let last = try tagged("\\begin{align} a &= b \\notag \\\\ c &= d \\end{align}")
        #expect(last.tags.count == 1)
        #expect(abs(last.tags[0].baseline - equals[1]) < 0.001)
    }

    @Test func multiLineTagsCentreOnTheEquation() throws {
        let lines = try tagged("a \\\\ b \\\\ c \\tag{1}")
        let middle = (lines.ascent - lines.descent) / 2
        let tagBox = lines.tags[0].box
        #expect(abs(lines.tags[0].baseline + (tagBox.ascent - tagBox.descent) / 2 - middle) < 0.001)
    }

    @Test func tagsLineUpWithTheMiddleOfTallFormulas() throws {
        let matrix = try tagged("\\begin{pmatrix} 1 \\\\ 2 \\\\ 3 \\end{pmatrix} \\tag{M}")
        #expect(abs((matrix.ascent - matrix.descent) / 2 - axis) < 0.5)
        #expect(abs(matrix.tags[0].baseline) < 0.001)
    }

    @Test func renderingsKnowAboutTags() {
        let rendering = NoteMathRenderer.render("E = mc^2 \\tag{1}", fontSize: 40, color: .black, display: true)
        #expect(rendering.error == nil)
        #expect(rendering.hasTags)
        #expect(!NoteMathRenderer.render("E = mc^2", fontSize: 40, color: .black, display: true).hasTags)
    }

    @Test func theNaturalSizeLeavesRoomForTheTag() {
        let rendering = NoteMathRenderer.render("E = mc^2 \\tag{1}", fontSize: 40, color: .black, display: true)
        let plain = NoteMathRenderer.render("E = mc^2", fontSize: 40, color: .black, display: true)
        #expect(rendering.size.width > plain.size.width + 40)
    }

    func wideTagged() -> (NoteMathRendering, NoteMathRendering, Bitmap) {
        let rendering = NoteMathRenderer.render("E = mc^2 \\tag{1}", fontSize: 40, color: .black, display: true)
        let plain = NoteMathRenderer.render("E = mc^2", fontSize: 40, color: .black, display: true)
        let width: CGFloat = 600
        let canvasWidth = Int(width * 2), canvasHeight = Int((rendering.size.height * 2).rounded(.up))
        var pixels = [UInt8](repeating: 0, count: canvasWidth * canvasHeight * 4)
        pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: canvasWidth, height: canvasHeight, bitsPerComponent: 8,
                                          bytesPerRow: canvasWidth * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            context.scaleBy(x: 2, y: 2)
            rendering.draw(in: context, at: .zero, width: width)
        }
        return (rendering, plain, Bitmap(width: canvasWidth, height: canvasHeight, alpha: stride(from: 3, to: pixels.count, by: 4).map { pixels[$0] }))
    }

    @Test func theTagSitsFlushRight() { #expect(wideTagged().2.ink(x: 0.9...1, y: 0...1) > 30) }

    @Test func theFormulaStaysCentred() { #expect(wideTagged().2.ink(x: 0.35...0.65, y: 0...1) > 100) }

    @Test func thereIsOpenSpaceEitherSide() {
        let wide = wideTagged().2
        #expect(wide.ink(x: 0...0.3, y: 0...1) == 0)
        #expect(wide.ink(x: 0.7...0.88, y: 0...1) == 0)
    }

    @Test func theFormulaCentresAsIfUntagged() {
        let (rendering, plain, _) = wideTagged()
        #expect(abs(rendering.equationOffset(width: 600) - (600 - plain.size.width) / 2) < 1.5)
    }

    let crowded = NoteMathRenderer.render("\\sum_{n=1}^{\\infty} \\frac{1}{n^2} = \\frac{\\pi^2}{6} \\tag{Basel}", fontSize: 40, color: .black, display: true)

    @Test func aCrowdedFormulaSlidesLeftToMakeRoomForItsTag() {
        let snug = crowded.size.width + 20
        #expect(crowded.equationOffset(width: snug) + crowded.size.width - crowded.equationOffset(width: crowded.size.width) <= snug + 0.5)
    }

    @Test func aNarrowBlockFallsBackToTheNaturalLayout() { #expect(crowded.equationOffset(width: 10) == 0) }

    @Test func theNaturalSizeDrawsFormulaThenTag() {
        let tight = bitmap(crowded)
        #expect(tight.ink(x: 0.85...1, y: 0.2...0.8) > 30)
        #expect(tight.ink(x: 0...0.5, y: 0...1) > 100)
    }

    @Test func alignDrawsANumberPerRow() {
        let numbered = bitmap(NoteMathRenderer.render("\\begin{align} a &= b \\\\ c &= d \\end{align}", fontSize: 40, color: .black, display: true))
        #expect(numbered.ink(x: 0.75...1, y: 0...0.5) > 30)
        #expect(numbered.ink(x: 0.75...1, y: 0.5...1) > 30)
    }

    @Test func inlineTagsShowAnError() {
        #expect(NoteMathRenderer.render("x \\tag{1}", fontSize: 20, color: .black, display: false).error == "\\tag only works in display equations")
    }

    var simple: NoteMathRendering { NoteMathRenderer.render("x^2 + y^2 = z^2", fontSize: size, color: .black, display: true) }

    @Test func aRenderingHasNoError() {
        #expect(simple.error == nil)
        #expect(simple.size.width > size * 4)
        #expect(simple.baseline > 0)
    }

    @Test func theBaselineSitsInsideTheFrame() {
        #expect(simple.baseline < simple.size.height)
        #expect(simple.descent > 0)
    }

    @Test func errorsRenderTheSource() {
        let broken = NoteMathRenderer.render("\\frac{a}", fontSize: size, color: .black, display: true)
        #expect(broken.error == "\\frac needs 2 arguments")
        #expect(broken.size.width > size)
        #expect(broken.errorRange == NSRange(location: 7, length: 1))
    }

    @Test func emptyInputIsEmpty() {
        let empty = NoteMathRenderer.render("   ", fontSize: size, color: .black, display: false)
        #expect(empty.isEmpty)
        #expect(empty.error == nil)
        #expect(empty.size == .zero)
    }

    @Test func layoutsAreCached() {
        let first = NoteMathRenderer.layout("\\frac{1}{2}", fontSize: size, display: true)
        #expect(first === NoteMathRenderer.layout("\\frac{1}{2}", fontSize: size, display: true))
        #expect(NoteMathRenderer.layout("\\frac{1}{2}", fontSize: size, display: false) !== first)
    }

    @Test func theInlineSizeMatchesTheTextXHeight() {
        let matched = NoteMathRenderer.fontSize(matching: NSFont.systemFont(ofSize: 16))
        #expect(matched >= 16 * 0.9)
        #expect(matched <= 16 * 1.35)
    }

    @Test func anAttachmentSitsOnTheBaseline() {
        let attachment = NoteMathRenderer.attachment(for: "\\sqrt{2}", font: NSFont.systemFont(ofSize: 16), color: .black)
        #expect(attachment.image != nil)
        #expect(attachment.bounds.minY < 0)
        #expect(attachment.bounds.height > 10)
    }

    @Test func theImageHelper() {
        let image = simple.image()
        #expect(image.size == simple.size)
        #expect(image.accessibilityDescription == "Equation: x^2 + y^2 = z^2")
    }

    @Test func theCGImageHelper() { #expect(simple.cgImage(scale: 2)?.width == Int((simple.size.width * 2).rounded(.up))) }

    @Test func theAppearanceResolvedImageHelper() { #expect(simple.image(appearance: NSAppearance(named: .darkAqua)).size == simple.size) }

    struct Bitmap {
        let width: Int
        let height: Int
        let alpha: [UInt8]

        func ink(x: ClosedRange<Double>, y: ClosedRange<Double>) -> Int {
            var count = 0
            let columns = Int(x.lowerBound * Double(width))..<max(Int(x.upperBound * Double(width)), Int(x.lowerBound * Double(width)) + 1)
            let rows = Int(y.lowerBound * Double(height))..<max(Int(y.upperBound * Double(height)), Int(y.lowerBound * Double(height)) + 1)
            for row in rows where row >= 0 && row < height {
                for column in columns where column >= 0 && column < width {
                    if alpha[row * width + column] > 40 { count += 1 }
                }
            }
            return count
        }

        func fullRows() -> [Int] {
            (0..<height).filter { row in (0..<width).filter { alpha[row * width + $0] > 200 }.count > width * 6 / 10 }
        }
    }

    func bitmap(_ rendering: NoteMathRendering, scale: CGFloat = 2) -> Bitmap {
        let width = Int((rendering.size.width * scale).rounded(.up)), height = Int((rendering.size.height * scale).rounded(.up))
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            context.scaleBy(x: scale, y: scale)
            rendering.draw(in: context, at: .zero)
        }
        return Bitmap(width: width, height: height, alpha: stride(from: 3, to: pixels.count, by: 4).map { pixels[$0] })
    }

    func picture(_ latex: String, scale: CGFloat = 2) -> Bitmap {
        bitmap(NoteMathRenderer.render(latex, fontSize: 40, color: .black, display: true), scale: scale)
    }

    @Test func aScriptSizeGlyphDrawsHeavierStrokesThanAShrunkenTextGlyph() {
        let typesetter = NoteMathTypesetter(font: font, baseSize: 40)
        func rendered(_ glyph: CGGlyph) -> Bitmap {
            let entry = NoteMathLayoutEntry(box: typesetter.glyphBox(glyph, size: 28, color: .inherited), error: nil, isEmpty: false)
            return bitmap(NoteMathRendering(source: "2", fontSize: 28, color: .black, display: true, entry: entry), scale: 4)
        }
        let plain = rendered(glyph("2")).ink(x: 0...1, y: 0...1)
        let optical = rendered(scriptGlyph("2", 1)).ink(x: 0...1, y: 0...1)
        #expect(Double(optical) > Double(plain) * 1.05)
    }

    @Test func theScriptAlternateSuperscriptDraws() { #expect(picture("x^{2}", scale: 4).ink(x: 0.62...1, y: 0...0.45) > 30) }

    @Test func aFractionDrawsNumeratorInkInTheTopBand() { #expect(picture("\\frac{a}{b}").ink(x: 0...1, y: 0...0.4) > 50) }

    @Test func aFractionDrawsDenominatorInkInTheBottomBand() { #expect(picture("\\frac{a}{b}").ink(x: 0...1, y: 0.6...1) > 50) }

    @Test func theFractionRuleSpansTheWidth() { #expect(!picture("\\frac{a}{b}").fullRows().isEmpty) }

    @Test func aSuperscriptDrawsAtTheTopRight() {
        let power = picture("x^2")
        #expect(power.ink(x: 0.62...1, y: 0...0.45) > 30)
        #expect(power.ink(x: 0.62...1, y: 0.75...1) == 0)
    }

    @Test func theBaseDrawsAtTheBottomLeft() { #expect(picture("x^2").ink(x: 0...0.55, y: 0.4...1) > 50) }

    @Test func aRadicalDrawsItsOverbarOnTop() { #expect(picture("\\sqrt{x}").ink(x: 0.5...1, y: 0...0.2) > 20) }

    @Test func glyphsAfterATextRunStayInPlace() { #expect(picture("\\text{ab}\\,x").ink(x: 0.7...1, y: 0...1) > 30) }

    @Test func aFractionAfterAFunctionNameStaysInPlace() {
        let afterFunction = picture("\\sin\\frac{x}{y}")
        #expect(afterFunction.ink(x: 0.6...1, y: 0...0.4) > 20)
        #expect(afterFunction.ink(x: 0.6...1, y: 0.6...1) > 20)
    }

    @Test func cancelDrawsARisingStroke() {
        let struck = picture("\\cancel{\\phantom{x}}")
        #expect(struck.ink(x: 0...0.4, y: 0.6...1) > 5)
        #expect(struck.ink(x: 0.6...1, y: 0...0.4) > 5)
    }

    @Test func colouredInkDraws() { #expect(picture("\\color{red}{x}").ink(x: 0...1, y: 0...1) > 50) }

    @Test func errorSourceDraws() { #expect(picture("\\frac{a}").ink(x: 0...1, y: 0...1) > 50) }

    @Test func bracketsDrawOnBothSides() {
        let matrix = picture("\\begin{bmatrix} a & b \\\\ c & d \\end{bmatrix}")
        #expect(matrix.ink(x: 0...0.12, y: 0.1...0.9) > 50)
        #expect(matrix.ink(x: 0.88...1, y: 0.1...0.9) > 50)
    }

    @Test func cellsDrawInTheirQuadrants() {
        let matrix = picture("\\begin{bmatrix} a & b \\\\ c & d \\end{bmatrix}")
        #expect(matrix.ink(x: 0.2...0.45, y: 0...0.5) > 30)
        #expect(matrix.ink(x: 0.55...0.8, y: 0.5...1) > 30)
    }

    @Test func aReactionRenders() { #expect(picture("\\ce{N2 + 3H2 <=> 2NH3}", scale: 2).ink(x: 0...1, y: 0...1) > 400) }

    @Test func theEquilibriumArrowDrawsTwoStrokes() {
        let arrowBand = picture("\\ce{<=>}")
        #expect(arrowBand.ink(x: 0.1...0.9, y: 0...0.48) > 20)
        #expect(arrowBand.ink(x: 0.1...0.9, y: 0.52...1) > 20)
    }

    @Test func macroFractionsDrawTheirRuleAndNumerator() {
        let macro = picture("\\def\\half#1{\\frac{#1}{2}}\\half{x}")
        #expect(!macro.fullRows().isEmpty)
        #expect(macro.ink(x: 0...1, y: 0...0.4) > 30)
    }

    @Test func runawayMacrosRenderAsAClearError() {
        let error = NoteMathRenderer.render("\\def\\a{\\a}\\a", fontSize: 20, color: .black, display: true)
        #expect(error.error?.hasPrefix("\\a keeps expanding") == true)
        #expect(error.errorRange == NSRange(location: 10, length: 2))
    }

    func lineInks(_ box: NoteMathBox) -> [NoteMathInk] {
        box.inks.filter { if case .line = $0.content { return true } else { return false } }
    }

    func fallbackFont(_ ink: NoteMathInk) -> CTFont? {
        guard case .line(let run) = ink.content, let first = (CTLineGetGlyphRuns(run) as? [CTRun])?.first else { return nil }
        return (CTRunGetAttributes(first) as NSDictionary)[kCTFontAttributeName] as! CTFont?
    }

    @Test(arguments: ["日本", "😀"]) func fallbackTextFallsBackToOneSystemRun(text: String) throws {
        #expect(lineInks(try box("x\\text{\(text)}")).count == 1)
        #expect(lineInks(try box("x_{\\text{\(text)}}")).count == 1)
    }

    @Test(arguments: ["日本", "😀"]) func fallbackTextUsesTheTextSize(text: String) throws {
        let inks = lineInks(try box("x\\text{\(text)}"))
        let first = try #require(inks.first)
        let used = try #require(fallbackFont(first))
        #expect(abs(CTFontGetSize(used) - size) < 0.01)
    }

    @Test(arguments: ["日本", "😀"]) func fallbackTextInASubscriptScalesToScriptSize(text: String) throws {
        let inks = lineInks(try box("x_{\\text{\(text)}}"))
        let first = try #require(inks.first)
        let used = try #require(fallbackFont(first))
        #expect(abs(CTFontGetSize(used) - size * font.constants.scriptPercentScaleDown / 100) < 0.01)
        #expect(CTFontCopyPostScriptName(used) as String != "STIXTwoMath-Regular")
    }

    @Test(arguments: ["日本", "😀"]) func fallbackTextInASubscriptIsNarrowerAndSitsBelowTheBaseline(text: String) throws {
        let script = try box("x_{\\text{\(text)}}")
        #expect(script.width < (try box("x\\text{\(text)}")).width)
        #expect(try #require(lineInks(script).first).origin.y < -0.5)
    }

    @Test(arguments: ["日本", "😀"]) func fallbackTextKeepsSensibleMetrics(text: String) throws {
        let typographic = try box("\\text{\(text)}")
        #expect(typographic.ascent > 0)
        #expect(typographic.ascent < size * 1.3)
        #expect(typographic.descent < size * 0.5)
    }

    @Test func coveredLettersKeepTheScriptGlyphAndOnlyTheGapFallsBack() throws {
        let mixed = try box("x_{\\text{a日}}")
        #expect(!inks(mixed, glyph: scriptGlyph("a", 1)).isEmpty)
        #expect(lineInks(mixed).count == 1)
    }

    @Test func aSymbolFromEitherFontDrawsInASuperscript() throws { #expect(try box("x^{★}").width > (try box("x")).width) }

    @Test func fallbackSubscriptInkIsAtTheBottomRight() { #expect(picture("x_{\\text{日本}}").ink(x: 0.4...1, y: 0.35...1) > 30) }

    @Test func nothingFloatsAboveTheFallbackSubscript() { #expect(picture("x_{\\text{日本}}").ink(x: 0.45...1, y: 0...0.2) == 0) }

    var numbering: NoteMathNumberingContext { NoteMathNumberingContext(references: ["e": [.text("12", .roman)]], referenceDigest: "e=12") }

    func referenced(_ key: String) -> NoteMathRendering {
        NoteMathRenderer.render("x = \\eqref{\(key)}", fontSize: 40, color: .black, display: false, numbering: numbering)
    }

    @Test func aResolvedReferenceIsALink() {
        let found = referenced("e").links(width: referenced("e").size.width)
        #expect(found.count == 1)
        #expect(found[0].key == "e")
        #expect(found[0].resolved)
    }

    @Test func theLinkSitsOnTheReference() {
        let resolved = referenced("e")
        let found = resolved.links(width: resolved.size.width)
        #expect(found[0].rect.maxX <= resolved.size.width + 0.5)
        #expect(found[0].rect.minX > resolved.size.width * 0.3)
    }

    @Test func aMissingReferenceIsMarked() {
        let missing = referenced("gone")
        let lost = missing.links(width: missing.size.width)
        #expect(lost.count == 1)
        #expect(!lost[0].resolved)
    }

    @Test func missingReferencesUseMutedInk() throws {
        let missingBox = NoteMathTypesetter(font: font, baseSize: size).typeset([.reference("gone", parenthesized: true, label: nil)], display: false)
        #expect(missingBox.inks.allSatisfy { if case .muted = $0.color { return true } else { return false } })
    }

    @Test func theCacheKeepsNumberedAndUnnumberedRendersApart() {
        let plain = NoteMathRenderer.render("x = \\eqref{e}", fontSize: 40, color: .black, display: false)
        #expect(plain.size.width != referenced("e").size.width)
    }

    @Test func pageNumberingKeepsTheTag() {
        let display = NoteMathRenderer.render("\\begin{equation} a \\end{equation}", fontSize: 40, color: .black, display: true,
                                              numbering: NoteMathNumberingContext(firstNumber: 6))
        #expect(display.hasTags)
    }

    @Test func theReferenceNumberDraws() { #expect(bitmap(referenced("e")).ink(x: 0.55...1, y: 0...1) > 40) }

    @Test func theMissingMarkerDraws() { #expect(bitmap(referenced("gone")).ink(x: 0.55...1, y: 0...1) > 40) }

    @Test func aComposedAccentIsOneLetter() throws {
        #expect(abs(try box("\\text{\\'e}", display: false).width - (try box("\\text{é}", display: false)).width) < 0.01)
    }

    @Test func sizesWorkInText() throws {
        #expect(try box("\\text{\\Huge a}", display: false).width > (try box("\\text{a}", display: false)).width * 2)
    }

    @Test func linksWorkInsideText() throws {
        #expect(try box("\\text{see \\href{https://a.b}{this}}", display: false).links.first?.url == "https://a.b")
    }

    @Test func utildeHangsATildeBelow() throws {
        #expect(try box("\\utilde{ABCD}", display: false).descent > (try box("ABCD", display: false)).descent + 0.1 * size)
    }

    func inkSpan(_ target: NoteMathBox, above floor: CGFloat) -> CGFloat {
        var low = CGFloat.infinity, high = -CGFloat.infinity
        for ink in target.inks {
            guard case .glyph(let glyph, let ctFont) = ink.content else { continue }
            let scale = CTFontGetSize(ctFont) / font.unitsPerEm
            let bounds = font.metrics(glyph).bounds
            guard ink.origin.y + bounds.minY * scale > floor else { continue }
            low = min(low, ink.origin.x + bounds.minX * scale)
            high = max(high, ink.origin.x + bounds.maxX * scale)
        }
        return high - low
    }

    @Test(arguments: ["Overrightarrow", "overleftharpoon", "overrightharpoon"]) func stretchyMarksStretchOverTheirBase(mark: String) throws {
        let marked = try box("\\\(mark){ABCDEFGH}", display: false), base = try box("ABCDEFGH", display: false)
        #expect(marked.ascent > base.ascent + 0.15 * size)
        #expect(inkSpan(marked, above: base.ascent) > base.width * 0.9)
    }

    @Test func overlinesegmentMatchesKaTeXsBox() throws {
        let plain = try box("ABCD", display: false), over = try box("\\overlinesegment{ABCD}", display: false)
        #expect(abs(over.ascent - plain.ascent - 0.522 * size) < 0.01)
        #expect(ruleCount(over) == 3)
    }

    @Test func underlinesegmentHangsBelow() throws {
        let plain = try box("ABCD", display: false), under = try box("\\underlinesegment{ABCD}", display: false)
        #expect(abs(under.descent - plain.descent - 0.522 * size) < 0.01)
        #expect(ruleCount(under) == 3)
    }

    @Test func phaseDrawsItsAngle() throws {
        let phase = try box("\\phase{-78^\\circ}", display: false), base = try box("-78^\\circ", display: false)
        #expect(phase.width > base.width + 0.3 * size)
        #expect(phase.descent > base.descent + 0.15 * size)
        #expect(segments(phase) >= 1)
    }

    @Test func anglRoofsItsContent() throws {
        let angle = try box("\\angl{n}", display: false), letter = try box("n", display: false)
        #expect(ruleCount(angle) == 2)
        #expect(abs(angle.ascent - letter.ascent - 0.16 * size) < 0.01)
    }

    @Test func twoHeadedArrowsStretch() throws {
        let short = try box("\\xtwoheadrightarrow{a}", display: false)
        #expect(try box("\\xtwoheadrightarrow{abcdefgh}", display: false).width > short.width + 2 * size)
        #expect(try box("\\xtwoheadleftarrow{abcdefgh}", display: false).width > short.width + 2 * size)
    }

    @Test func xlongequalDrawsTwoLongBars() throws {
        let equal = try box("\\xlongequal{abcdefgh}", display: false)
        #expect(ruleCount(equal) == 2)
        #expect(equal.width > 3 * size)
    }

    @Test func mathchoicePicksTheDisplayBranchInDisplay() throws {
        let choice = "\\mathchoice{MMMM}{MM}{M}{i}"
        #expect(try box(choice).width > (try box(choice, display: false)).width * 1.5)
    }

    @Test func mathchoicePicksTheScriptBranch() throws {
        let choice = "\\mathchoice{MMMM}{MM}{M}{i}"
        #expect(abs(try box("x^{" + choice + "}", display: false).width - (try box("x^{M}", display: false)).width) < 0.01)
    }

    @Test func mathchoiceIsInvisibleToSpacing() throws {
        #expect(abs(try box("a\\mathchoice{+}{+}{+}{+}b", display: false).width - (try box("a+b", display: false)).width) < 0.01)
    }

    @Test func vcenterCentresOnTheAxis() throws {
        let centered = try box("\\vcenter{\\frac{a}{b}}", display: false)
        #expect(abs((centered.ascent - centered.descent) / 2 - font.constants[.axisHeight] * size / font.unitsPerEm) < 0.01)
    }

    @Test func pmodSpreadsOutInDisplay() throws { #expect(try box("\\pmod{a}").width > (try box("\\pmod{a}", display: false)).width) }

    @Test func mathstrutIsAParenthesisTall() throws {
        let strut = try box("\\mathstrut", display: false)
        #expect(strut.width == 0)
        #expect(strut.ascent > 0)
        #expect(strut.descent > 0)
    }

    @Test(arguments: ["\\TeX", "\\LaTeX", "\\KaTeX"]) func logosDraw(logo: String) throws { #expect(try box(logo, display: false).width > 0.9 * size) }

    @Test func pmbDoublesUp() throws { #expect(try box("\\pmb{x}", display: false).width > (try box("x", display: false)).width) }

    @Test func hugeIsTwoPointFourEightEightTimesAsWide() throws {
        #expect(abs(try box("\\Huge x", display: false).width / (try box("x", display: false)).width - 2.488) < 0.02)
    }

    @Test func tinyIsHalfAsWide() throws {
        #expect(abs(try box("\\tiny x", display: false).width / (try box("x", display: false)).width - 0.5) < 0.02)
    }

    @Test func sizesAreAbsoluteNotNested() throws {
        #expect(abs(try box("\\Huge{\\tiny x}", display: false).width - (try box("\\tiny x", display: false)).width) < 0.01)
    }

    @Test func normalsizeInAScriptKeepsTheScript() throws {
        #expect(abs(try box("x^{\\normalsize y}", display: false).width - (try box("x^{y}", display: false)).width) < 0.01)
    }

    @Test func raiseboxLiftsByItsLength() throws {
        #expect(abs(try box("\\raisebox{0.5em}{x}", display: false).ascent - (try box("\\text{x}", display: false)).ascent - 0.5 * size) < 0.01)
    }

    @Test func smashKeepsInkAndDropsHeight() throws {
        let smashed = try box("\\smash{\\frac{a}{b}}", display: false)
        #expect(smashed.ascent == 0)
        #expect(smashed.descent == 0)
        #expect(!smashed.inks.isEmpty)
    }

    @Test func smashBKeepsTheHeight() throws {
        let bottomless = try box("\\smash[b]{y}", display: false)
        #expect(bottomless.ascent > 0)
        #expect(bottomless.descent == 0)
    }

    @Test func substackStacksRows() throws {
        #expect(try box("\\substack{a\\\\b\\\\c}", display: false).height > (try box("\\substack{a}", display: false)).height * 2)
    }

    @Test func substackCellsUseScriptSize() throws {
        #expect(abs(try box("\\substack{a}", display: false).width - (try box("{\\scriptstyle a}", display: false)).width) < 0.01)
    }

    @Test func genfracDrawsItsOwnRuleThickness() throws {
        let thin = try box("\\genfrac{}{}{0.1em}{}{a}{b}", display: false)
        let found = thin.inks.compactMap { ink -> CGSize? in if case .rule(let ruleSize) = ink.content { return ruleSize }; return nil }
        #expect(found.count == 1)
        #expect(abs(found[0].height - 0.1 * size) < 0.01)
    }

    @Test func colorboxPadsByFboxsep() throws {
        #expect(abs(try box("\\colorbox{red}{hi}", display: false).width - (try box("\\text{hi}", display: false)).width - 0.6 * size) < 0.01)
    }

    @Test func theBackgroundDrawsFirst() throws {
        let colorBox = try box("\\colorbox{red}{hi}", display: false)
        #expect(colorBox.inks.first.map { if case .rule = $0.content, case .custom = $0.color { true } else { false } } == true)
    }

    @Test func fcolorboxAddsAFrame() throws {
        let framed = try box("\\fcolorbox{blue}{red}{hi}", display: false), text = try box("\\text{hi}", display: false)
        #expect(abs(framed.width - text.width - 0.68 * size) < 0.01)
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
        let url = try box("\\url{https://parc.is}", display: false)
        #expect(url.links.first?.url == "https://parc.is")
        #expect(url.inks.contains { if case .link = $0.color { true } else { false } })
    }

    @Test func overgroupArcsOverItsBase() throws {
        #expect(try box("\\overgroup{ABCD}", display: false).ascent > (try box("ABCD", display: false)).ascent + 0.1 * size)
    }

    @Test func undergroupHangsBelow() throws {
        #expect(try box("\\undergroup{ABCD}", display: false).descent > (try box("ABCD", display: false)).descent + 0.1 * size)
    }

    @Test func tripledashKeepsAMinusStrut() throws { #expect(try box("\\tripledash", display: false).ascent >= (try box("-", display: false)).ascent - 0.01) }

    @Test func aDashedBondAddsItsDashesAboveTheLine() throws {
        #expect(try box("\\ce{A\\bond{~-}B}", display: false).inks.count > (try box("\\ce{A\\bond{-}B}", display: false)).inks.count)
    }

    @Test(arguments: ["~", "~-", "~=", "~--", "-~-", "...", "...."]) func aBondDrawsBetweenTheAtoms(bond: String) {
        let rendering = NoteMathRenderer.render("\\ce{C\\bond{\(bond)}C}", fontSize: 30, color: .black, display: false)
        #expect(rendering.error == nil)
        #expect(bitmap(rendering).ink(x: 0.35...0.65, y: 0...1) > 4)
    }

    nonisolated static let formulas = [
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

    @Test(arguments: NoteMathLayoutTests.formulas)
    func aSampleFormulaRendersInDisplayStyle(formula: String) {
        let rendering = NoteMathRenderer.render(formula, fontSize: 18, color: .black, display: true)
        #expect(rendering.error == nil)
        #expect(rendering.size.width.isFinite && rendering.size.height.isFinite)
        #expect(bitmap(rendering, scale: 1).ink(x: 0...1, y: 0...1) > 0)
    }

    @Test(arguments: NoteMathLayoutTests.formulas)
    func aSampleFormulaRendersInlineToo(formula: String) {
        let rendering = NoteMathRenderer.render(formula, fontSize: 18, color: .black, display: false)
        #expect(rendering.error == nil)
        #expect(rendering.size.width.isFinite && rendering.size.height.isFinite)
        #expect(bitmap(rendering, scale: 1).ink(x: 0...1, y: 0...1) > 0)
    }
}
