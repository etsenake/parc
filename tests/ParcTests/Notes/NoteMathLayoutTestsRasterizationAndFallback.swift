import AppKit
import CoreText
import Testing
@testable import ParcCore
@testable import ParcNotes

@MainActor
struct NoteMathLayoutTestsRasterizationAndFallback {
    private let fixture: NoteMathLayoutTestsSupport.Fixture

    init() throws { fixture = try NoteMathLayoutTestsSupport.Fixture() }

    @Test func aScriptSizeGlyphDrawsHeavierStrokesThanAShrunkenTextGlyph() {
        let typesetter = NoteMathTypesetter(font: fixture.font, baseSize: 40)
        func rendered(_ glyph: CGGlyph) -> NoteMathLayoutTestsSupport.Fixture.Bitmap {
            let entry = NoteMathLayoutEntry(box: typesetter.glyphBox(glyph, size: 28, color: .inherited), error: nil, isEmpty: false)
            return fixture.bitmap(NoteMathRendering(source: "2", fontSize: 28, color: .black, display: true, entry: entry), scale: 4)
        }
        let plain = rendered(fixture.glyph("2")).ink(x: 0...1, y: 0...1)
        let optical = rendered(fixture.scriptGlyph("2", 1)).ink(x: 0...1, y: 0...1)
        #expect(Double(optical) > Double(plain) * 1.05)
    }

    @Test func theScriptAlternateSuperscriptDraws() { #expect(fixture.picture("x^{2}", scale: 4).ink(x: 0.62...1, y: 0...0.45) > 30) }

    @Test func aFractionDrawsNumeratorInkInTheTopBand() { #expect(fixture.picture("\\frac{a}{b}").ink(x: 0...1, y: 0...0.4) > 50) }

    @Test func aFractionDrawsDenominatorInkInTheBottomBand() { #expect(fixture.picture("\\frac{a}{b}").ink(x: 0...1, y: 0.6...1) > 50) }

    @Test func theFractionRuleSpansTheWidth() { #expect(!fixture.picture("\\frac{a}{b}").fullRows().isEmpty) }

    @Test func aSuperscriptDrawsAtTheTopRight() {
        let power = fixture.picture("x^2")
        #expect(power.ink(x: 0.62...1, y: 0...0.45) > 30)
        #expect(power.ink(x: 0.62...1, y: 0.75...1) == 0)
    }

    @Test func theBaseDrawsAtTheBottomLeft() { #expect(fixture.picture("x^2").ink(x: 0...0.55, y: 0.4...1) > 50) }

    @Test func aRadicalDrawsItsOverbarOnTop() { #expect(fixture.picture("\\sqrt{x}").ink(x: 0.5...1, y: 0...0.2) > 20) }

    @Test func glyphsAfterATextRunStayInPlace() { #expect(fixture.picture("\\text{ab}\\,x").ink(x: 0.7...1, y: 0...1) > 30) }

    @Test func aFractionAfterAFunctionNameStaysInPlace() {
        let afterFunction = fixture.picture("\\sin\\frac{x}{y}")
        #expect(afterFunction.ink(x: 0.6...1, y: 0...0.4) > 20)
        #expect(afterFunction.ink(x: 0.6...1, y: 0.6...1) > 20)
    }

    @Test func cancelDrawsARisingStroke() {
        let struck = fixture.picture("\\cancel{\\phantom{x}}")
        #expect(struck.ink(x: 0...0.4, y: 0.6...1) > 5)
        #expect(struck.ink(x: 0.6...1, y: 0...0.4) > 5)
    }

    @Test func colouredInkDraws() { #expect(fixture.picture("\\color{red}{x}").ink(x: 0...1, y: 0...1) > 50) }

    @Test func errorSourceDraws() { #expect(fixture.picture("\\frac{a}").ink(x: 0...1, y: 0...1) > 50) }

    @Test func aSpaceTooBigToDrawShowsAsATypoAndStillRasterizes() {
        let source = "x\\hspace{" + String(repeating: "9", count: 400) + "em}y"
        let rendering = NoteMathRenderer.render(source, fontSize: 20, color: .black, display: true)
        #expect(rendering.error != nil)
        #expect(rendering.size.width.isFinite && rendering.size.height.isFinite)
        #expect(rendering.cgImage() != nil)
    }

    @Test func aGiantEquationRasterizesWithinTheBitmapBudgetAndKeepsItsShape() throws {
        let rendering = NoteMathRenderer.render("\\rule{1600em}{800em}", fontSize: 16, color: .black, display: true)
        #expect(rendering.error == nil)
        let image = try #require(rendering.cgImage())
        #expect(CGFloat(image.width * image.height) <= NoteMathRendering.largestBitmapPixels + CGFloat(image.width + image.height + 1))
        #expect(abs(CGFloat(image.width) / CGFloat(image.height) - rendering.size.width / rendering.size.height) < 0.01)
    }

    @Test func aLargeButValidTeXSpaceStillTypesets() {
        let rendering = NoteMathRenderer.render("x\\hspace{200em}y", fontSize: 16, color: .black, display: true)
        #expect(rendering.error == nil)
        #expect(rendering.size.width > 3000)
    }

    @Test func bracketsDrawOnBothSides() {
        let matrix = fixture.picture("\\begin{bmatrix} a & b \\\\ c & d \\end{bmatrix}")
        #expect(matrix.ink(x: 0...0.12, y: 0.1...0.9) > 50)
        #expect(matrix.ink(x: 0.88...1, y: 0.1...0.9) > 50)
    }

    @Test func cellsDrawInTheirQuadrants() {
        let matrix = fixture.picture("\\begin{bmatrix} a & b \\\\ c & d \\end{bmatrix}")
        #expect(matrix.ink(x: 0.2...0.45, y: 0...0.5) > 30)
        #expect(matrix.ink(x: 0.55...0.8, y: 0.5...1) > 30)
    }

    @Test func aReactionRenders() { #expect(fixture.picture("\\ce{N2 + 3H2 <=> 2NH3}", scale: 2).ink(x: 0...1, y: 0...1) > 400) }

    @Test func theEquilibriumArrowDrawsTwoStrokes() {
        let arrowBand = fixture.picture("\\ce{<=>}")
        #expect(arrowBand.ink(x: 0.1...0.9, y: 0...0.48) > 20)
        #expect(arrowBand.ink(x: 0.1...0.9, y: 0.52...1) > 20)
    }

    @Test func macroFractionsDrawTheirRuleAndNumerator() {
        let macro = fixture.picture("\\def\\half#1{\\frac{#1}{2}}\\half{x}")
        #expect(!macro.fullRows().isEmpty)
        #expect(macro.ink(x: 0...1, y: 0...0.4) > 30)
    }

    @Test func runawayMacrosRenderAsAClearError() {
        let error = NoteMathRenderer.render("\\def\\a{\\a}\\a", fontSize: 20, color: .black, display: true)
        #expect(error.error?.hasPrefix("\\a keeps expanding") == true)
        #expect(error.errorRange == NSRange(location: 10, length: 2))
    }

    private func lineInks(_ box: NoteMathBox) -> [NoteMathInk] {
        box.inks.filter { if case .line = $0.content { return true } else { return false } }
    }

    private func fallbackFont(_ ink: NoteMathInk) -> CTFont? {
        guard case .line(let run) = ink.content, let first = (CTLineGetGlyphRuns(run) as? [CTRun])?.first else { return nil }
        return (CTRunGetAttributes(first) as NSDictionary)[kCTFontAttributeName] as! CTFont?
    }

    @Test(arguments: ["日本", "😀"]) func bodyTextFallsBackToOneSystemRun(text: String) throws {
        #expect(lineInks(try fixture.box("x\\text{\(text)}")).count == 1)
    }

    @Test(arguments: ["日本", "😀"]) func subscriptTextFallsBackToOneSystemRun(text: String) throws {
        #expect(lineInks(try fixture.box("x_{\\text{\(text)}}")).count == 1)
    }

    @Test(arguments: ["日本", "😀"]) func fallbackTextUsesTheTextSize(text: String) throws {
        let inks = lineInks(try fixture.box("x\\text{\(text)}"))
        let first = try #require(inks.first)
        let used = try #require(fallbackFont(first))
        #expect(abs(CTFontGetSize(used) - fixture.size) < 0.01)
    }

    @Test(arguments: ["日本", "😀"]) func fallbackTextInASubscriptScalesToScriptSize(text: String) throws {
        let inks = lineInks(try fixture.box("x_{\\text{\(text)}}"))
        let first = try #require(inks.first)
        let used = try #require(fallbackFont(first))
        #expect(abs(CTFontGetSize(used) - fixture.size * fixture.font.constants.scriptPercentScaleDown / 100) < 0.01)
        #expect(CTFontCopyPostScriptName(used) as String != "STIXTwoMath-Regular")
    }

    @Test(arguments: ["日本", "😀"]) func fallbackTextInASubscriptIsNarrower(text: String) throws {
        let script = try fixture.box("x_{\\text{\(text)}}")
        #expect(script.width < (try fixture.box("x\\text{\(text)}")).width)
    }

    @Test(arguments: ["日本", "😀"]) func fallbackTextInASubscriptSitsBelowTheBaseline(text: String) throws {
        let script = try fixture.box("x_{\\text{\(text)}}")
        #expect(try #require(lineInks(script).first).origin.y < -0.5)
    }

    @Test(arguments: ["日本", "😀"]) func fallbackTextKeepsSensibleMetrics(text: String) throws {
        let typographic = try fixture.box("\\text{\(text)}")
        #expect(typographic.ascent > 0)
        #expect(typographic.ascent < fixture.size * 1.3)
        #expect(typographic.descent < fixture.size * 0.5)
    }

    @Test func coveredLettersKeepTheScriptGlyphAndOnlyTheGapFallsBack() throws {
        let mixed = try fixture.box("x_{\\text{a日}}")
        #expect(!fixture.inks(mixed, glyph: fixture.scriptGlyph("a", 1)).isEmpty)
        #expect(lineInks(mixed).count == 1)
    }

    @Test func aSymbolFromEitherFontDrawsInASuperscript() throws { #expect(try fixture.box("x^{★}").width > (try fixture.box("x")).width) }

    @Test func fallbackSubscriptInkIsAtTheBottomRight() { #expect(fixture.picture("x_{\\text{日本}}").ink(x: 0.4...1, y: 0.35...1) > 30) }

    @Test func nothingFloatsAboveTheFallbackSubscript() { #expect(fixture.picture("x_{\\text{日本}}").ink(x: 0.45...1, y: 0...0.2) == 0) }
}
