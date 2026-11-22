import AppKit
import CoreText
import Testing
@testable import Parc
@testable import ParcCore
@testable import ParcNotes

@MainActor
struct NoteMathLayoutTestsFontSpacingAndScripts {
    private struct AlphabetCase: Sendable, CustomTestStringConvertible {
        let symbol: String
        let variant: NoteMathVariant
        let expected: UInt32

        var testDescription: String { "\(symbol) in \(variant)" }
    }

    nonisolated private static let alphabetCases = [
        AlphabetCase(symbol: "x", variant: NoteMathVariant.normal, expected: 0x1D465),
        AlphabetCase(symbol: "h", variant: .normal, expected: 0x210E),
        AlphabetCase(symbol: "α", variant: .normal, expected: 0x1D6FC),
        AlphabetCase(symbol: "Γ", variant: .normal, expected: 0x393),
        AlphabetCase(symbol: "2", variant: .normal, expected: 0x32),
        AlphabetCase(symbol: "R", variant: .doubleStruck, expected: 0x211D),
        AlphabetCase(symbol: "Z", variant: .doubleStruck, expected: 0x2124),
        AlphabetCase(symbol: "L", variant: .script, expected: 0x2112),
        AlphabetCase(symbol: "g", variant: .fraktur, expected: 0x1D524),
        AlphabetCase(symbol: "v", variant: .bold, expected: 0x1D42F),
        AlphabetCase(symbol: "Γ", variant: .italic, expected: 0x1D6E4),
        AlphabetCase(symbol: "μ", variant: .boldItalic, expected: 0x1D741),
        AlphabetCase(symbol: "x", variant: .roman, expected: 0x78),
        AlphabetCase(symbol: "1", variant: .monospace, expected: 0x1D7F7),
        AlphabetCase(symbol: "a", variant: .sansSerif, expected: 0x1D5BA),
        AlphabetCase(symbol: "ϕ", variant: .normal, expected: 0x1D719),
        AlphabetCase(symbol: "∂", variant: .normal, expected: 0x1D715),
    ]

    private let fixture: NoteMathLayoutTestsSupport.Fixture

    init() throws { fixture = try NoteMathLayoutTestsSupport.Fixture() }

    @Test func theFontHasAMathTable() { #expect(fixture.font.hasMathTable) }

    @Test func theFontHasOneThousandUnitsPerEm() { #expect(fixture.font.unitsPerEm == 1000) }

    @Test func axisHeightIsAboutAQuarterEm() {
        #expect(fixture.font.constants[.axisHeight] > 200)
        #expect(fixture.font.constants[.axisHeight] < 300)
    }

    @Test func firstLevelScriptsScaleToSeventyPercent() {
        #expect(fixture.font.constants.scriptPercentScaleDown == 70)
    }

    @Test func secondLevelScriptsScaleToFiftyFivePercent() {
        #expect(fixture.font.constants.scriptScriptPercentScaleDown == 55)
    }

    @Test func theFractionRuleThicknessIsPositive() {
        #expect(fixture.font.constants[.fractionRuleThickness] > 0)
    }

    @Test func theKernAfterARadicalDegreeIsNegative() {
        #expect(fixture.font.constants[.radicalKernAfterDegree] < 0)
    }

    @Test func theFontRequiresPositiveConnectorOverlap() { #expect(fixture.font.minConnectorOverlap > 0) }

    @Test func parenthesesHaveMoreThanFiveVariants() {
        let paren = fixture.font.verticalConstruction(fixture.glyph("("))
        #expect((paren?.variants.count ?? 0) > 5)
    }

    @Test func parenthesesHaveAnExtensibleAssembly() {
        let paren = fixture.font.verticalConstruction(fixture.glyph("("))
        #expect(paren?.parts.contains(where: { $0.isExtender }) == true)
    }

    @Test func overbraceAssemblesHorizontally() { #expect(fixture.font.horizontalConstruction(fixture.glyph("\u{23DE}"))?.parts.isEmpty == false) }

    @Test func italicFHasAnItalicCorrection() { #expect(fixture.font.italicCorrection(fixture.glyph("𝑓")) > 0) }

    @Test func italicXHasAnAccentAttachment() { #expect(fixture.font.topAccentAttachment(fixture.glyph("𝑥")) != nil) }

    @Test func italicVHasMathKerning() { #expect(fixture.font.kernSet(fixture.glyph("𝑉")) != nil) }

    @Test(arguments: NoteMathLayoutTestsFontSpacingAndScripts.alphabetCases)
    private func aLetterMapsIntoItsAlphabet(sample: AlphabetCase) {
        let mapped = NoteMathAlphabet.map(sample.symbol, variant: sample.variant)
        #expect(mapped.unicodeScalars.first?.value == sample.expected)
    }

    @Test(arguments: NoteMathLayoutTestsFontSpacingAndScripts.alphabetCases)
    private func theFontCoversTheMappedLetter(sample: AlphabetCase) {
        let mapped = NoteMathAlphabet.map(sample.symbol, variant: sample.variant)
        #expect(fixture.font.glyph(for: mapped.unicodeScalars.first!) != 0)
    }

    @Test func boldTextMapsAsciiAndKeepsAccents() { #expect(NoteMathAlphabet.mapText("ab1é", style: .bold) == "𝐚𝐛𝟏é") }

    private func advance(_ symbol: String) -> CGFloat { fixture.font.metrics(fixture.glyph(symbol)).advance * fixture.size / 1000 }

    @Test func binaryOperatorsGetMediumSpaces() throws {
        let gap = try fixture.box("a+b").width - (try fixture.box("a").width + (try fixture.box("b").width) + advance("+"))
        #expect(abs(gap - 2 * 4 * fixture.size / 18) < 0.01)
    }

    @Test func relationsGetThickSpaces() throws {
        let gap = try fixture.box("a=b").width - (try fixture.box("a").width + (try fixture.box("b").width) + advance("="))
        #expect(abs(gap - 2 * 5 * fixture.size / 18) < 0.01)
    }

    @Test func aLeadingMinusIsUnary() throws {
        #expect(abs(try fixture.box("-b").width - (advance("\u{2212}") + (try fixture.box("b").width))) < 0.01)
    }

    @Test func punctuationGetsAThinSpace() throws {
        #expect(try fixture.box("a,b").width > (try fixture.box("a").width) + (try fixture.box("b").width) + advance(",") + 0.1)
    }

    @Test func noMediumSpaceInsideScripts() throws {
        let sum = try fixture.box("x^{a+b}").width - (try fixture.box("x^{ab}").width)
        #expect(abs(sum - fixture.font.metrics(fixture.scriptGlyph("+", 1)).advance * fixture.size * 0.7 / 1000) < 0.01)
    }

    @Test func quadIsOneEm() throws {
        #expect(abs(try fixture.box("a\\quad b").width - (try fixture.box("a").width + (try fixture.box("b").width) + fixture.size)) < 0.01)
    }

    @Test func functionNamesAreUprightAndSpaced() throws { #expect(try fixture.box("\\sin x").width > (try fixture.box("sinx").width) - 3) }

    @Test func superscriptsAreRaised() throws {
        let two = fixture.inks(try fixture.box("x^2"), glyph: fixture.scriptGlyph("2", 1))
        #expect(two.count == 1)
        #expect(two[0].origin.y > fixture.size * 0.25)
    }

    @Test func aSuperscriptGrowsTheBox() throws {
        let raised = try fixture.box("x^2"), base = try fixture.box("x")
        #expect(raised.ascent > base.ascent)
        #expect(raised.width > base.width)
    }

    @Test func scriptSizeIsSeventyPercent() throws {
        let two = fixture.inks(try fixture.box("x^2"), glyph: fixture.scriptGlyph("2", 1))
        guard case .glyph(_, let scriptFont)? = two.first?.content else {
            Issue.record("the superscript is a glyph")
            return
        }
        #expect(abs(CTFontGetSize(scriptFont) - fixture.size * 0.7) < 0.01)
    }

    @Test func subscriptsAreLowered() throws {
        let lowered = try fixture.box("x_2")
        let sub = fixture.inks(lowered, glyph: fixture.scriptGlyph("2", 1))
        #expect(sub.count == 1)
        #expect(sub[0].origin.y < 0)
        #expect(lowered.descent > (try fixture.box("x")).descent)
    }

    private func scriptPair() throws -> [NoteMathInk] { fixture.inks(try fixture.box("x_2^2"), glyph: fixture.scriptGlyph("2", 1)).sorted { $0.origin.y > $1.origin.y } }

    @Test func theSuperscriptSitsAboveTheSubscript() throws {
        let pair = try scriptPair()
        #expect(pair.count == 2)
        #expect(pair[0].origin.y > 0)
        #expect(pair[1].origin.y < 0)
    }

    @Test func subAndSuperscriptKeepTheirGap() throws {
        let pair = try scriptPair()
        #expect(fixture.extent([pair[0]]).minY - fixture.extent([pair[1]]).maxY >= fixture.font.constants[.subSuperscriptGapMin] * fixture.size / 1000 - 0.01)
    }

    @Test func theSuperscriptIsNudgedByTheItalicCorrection() throws {
        let pair = try scriptPair()
        #expect(pair[0].origin.x > pair[1].origin.x)
    }

    @Test func primesRideHigh() throws {
        #expect(fixture.inks(try fixture.box("f'"), glyph: fixture.scriptGlyph("′", 1)).first.map { $0.origin.y > 0 } == true)
    }

    @Test func secondLevelScriptsAreFiftyFivePercent() throws {
        let nestedTwo = fixture.inks(try fixture.box("e^{x^2}"), glyph: fixture.scriptGlyph("2", 2))
        guard case .glyph(_, let tiny)? = nestedTwo.first?.content else {
            Issue.record("nested script exists")
            return
        }
        #expect(abs(CTFontGetSize(tiny) - fixture.size * 0.55) < 0.01)
    }

    @Test func aClosingParenthesisCanCarryASuperscript() throws { #expect(try fixture.box("(x+y)^2").ascent > (try fixture.box("(x+y)")).ascent) }
}
