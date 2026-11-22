import AppKit
import CoreText
import Testing
@testable import Parc
@testable import ParcCore

@MainActor
struct NoteMathLayoutTestsTagsAndRendering {
    private let fixture: NoteMathLayoutTestsSupport.Fixture

    init() throws { fixture = try NoteMathLayoutTestsSupport.Fixture() }

    @Test func tagsOnASingleLineSitOnTheBaseline() throws {
        let single = try fixture.tagged("x = y \\tag{1}")
        #expect(single.tags.count == 1)
        #expect(abs(single.tags[0].baseline) < 0.001)
    }

    @Test func theTagStaysOutOfTheFormulaBox() throws {
        let single = try fixture.tagged("x = y \\tag{1}")
        #expect(abs(single.width - (try fixture.box("x = y")).width) < 0.001)
        #expect(single.inks.count == (try fixture.box("x = y")).inks.count)
    }

    @Test func alignTagsSitOnTheirRows() throws {
        let align = try fixture.tagged("\\begin{align} a &= b \\\\ c &= d \\end{align}")
        let equals = fixture.inks(align, glyph: fixture.glyph("=")).map(\.origin.y).sorted(by: >)
        let baselines = align.tags.map(\.baseline).sorted(by: >)
        #expect(align.tags.count == 2)
        #expect(equals.count == 2)
        #expect(zip(equals, baselines).allSatisfy { abs($0 - $1) < 0.001 })
    }

    @Test func notagLeavesTheNumberOnTheLastLine() throws {
        let align = try fixture.tagged("\\begin{align} a &= b \\\\ c &= d \\end{align}")
        let equals = fixture.inks(align, glyph: fixture.glyph("=")).map(\.origin.y).sorted(by: >)
        let last = try fixture.tagged("\\begin{align} a &= b \\notag \\\\ c &= d \\end{align}")
        #expect(last.tags.count == 1)
        #expect(abs(last.tags[0].baseline - equals[1]) < 0.001)
    }

    @Test func multiLineTagsCentreOnTheEquation() throws {
        let lines = try fixture.tagged("a \\\\ b \\\\ c \\tag{1}")
        let middle = (lines.ascent - lines.descent) / 2
        let tagBox = lines.tags[0].box
        #expect(abs(lines.tags[0].baseline + (tagBox.ascent - tagBox.descent) / 2 - middle) < 0.001)
    }

    @Test func tagsLineUpWithTheMiddleOfTallFormulas() throws {
        let matrix = try fixture.tagged("\\begin{pmatrix} 1 \\\\ 2 \\\\ 3 \\end{pmatrix} \\tag{M}")
        #expect(abs((matrix.ascent - matrix.descent) / 2 - fixture.axis) < 0.5)
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

    private func wideTagged() -> (NoteMathRendering, NoteMathRendering, NoteMathLayoutTestsSupport.Fixture.Bitmap) {
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
        return (rendering, plain, NoteMathLayoutTestsSupport.Fixture.Bitmap(width: canvasWidth, height: canvasHeight, alpha: stride(from: 3, to: pixels.count, by: 4).map { pixels[$0] }))
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

    private let crowded = NoteMathRenderer.render("\\sum_{n=1}^{\\infty} \\frac{1}{n^2} = \\frac{\\pi^2}{6} \\tag{Basel}", fontSize: 40, color: .black, display: true)

    @Test func aCrowdedFormulaSlidesLeftToMakeRoomForItsTag() {
        let snug = crowded.size.width + 20
        #expect(crowded.equationOffset(width: snug) + crowded.size.width - crowded.equationOffset(width: crowded.size.width) <= snug + 0.5)
    }

    @Test func aNarrowBlockFallsBackToTheNaturalLayout() { #expect(crowded.equationOffset(width: 10) == 0) }

    @Test func theNaturalSizeDrawsFormulaThenTag() {
        let tight = fixture.bitmap(crowded)
        #expect(tight.ink(x: 0.85...1, y: 0.2...0.8) > 30)
        #expect(tight.ink(x: 0...0.5, y: 0...1) > 100)
    }

    @Test func alignDrawsANumberPerRow() {
        let numbered = fixture.bitmap(NoteMathRenderer.render("\\begin{align} a &= b \\\\ c &= d \\end{align}", fontSize: 40, color: .black, display: true))
        #expect(numbered.ink(x: 0.75...1, y: 0...0.5) > 30)
        #expect(numbered.ink(x: 0.75...1, y: 0.5...1) > 30)
    }

    @Test func inlineTagsShowAnError() {
        #expect(NoteMathRenderer.render("x \\tag{1}", fontSize: 20, color: .black, display: false).error == "\\tag only works in display equations")
    }

    private var simple: NoteMathRendering { NoteMathRenderer.render("x^2 + y^2 = z^2", fontSize: fixture.size, color: .black, display: true) }

    @Test func aValidFormulaRendersWithoutAnError() {
        #expect(simple.error == nil)
    }

    @Test func aValidFormulaHasAWidth() {
        #expect(simple.size.width > fixture.size * 4)
    }

    @Test func aValidFormulaHasAPositiveBaseline() {
        #expect(simple.baseline > 0)
    }

    @Test func theBaselineSitsInsideTheFrame() {
        #expect(simple.baseline < simple.size.height)
        #expect(simple.descent > 0)
    }

    @Test func anIncompleteFractionReportsTheMissingArguments() {
        let broken = NoteMathRenderer.render("\\frac{a}", fontSize: fixture.size, color: .black, display: true)
        #expect(broken.error == "\\frac needs 2 arguments")
    }

    @Test func anIncompleteFractionRendersItsSource() {
        let broken = NoteMathRenderer.render("\\frac{a}", fontSize: fixture.size, color: .black, display: true)
        #expect(broken.size.width > fixture.size)
    }

    @Test func anIncompleteFractionMarksTheErrorRange() {
        let broken = NoteMathRenderer.render("\\frac{a}", fontSize: fixture.size, color: .black, display: true)
        #expect(broken.errorRange == NSRange(location: 7, length: 1))
    }

    @Test func emptyInputIsEmpty() {
        let empty = NoteMathRenderer.render("   ", fontSize: fixture.size, color: .black, display: false)
        #expect(empty.isEmpty)
        #expect(empty.error == nil)
        #expect(empty.size == .zero)
    }

    @Test func identicalLayoutsReuseTheCachedResult() {
        let first = NoteMathRenderer.layout("\\frac{1}{2}", fontSize: fixture.size, display: true)
        #expect(first === NoteMathRenderer.layout("\\frac{1}{2}", fontSize: fixture.size, display: true))
    }

    @Test func changingDisplayStyleUsesASeparateLayout() {
        let first = NoteMathRenderer.layout("\\frac{1}{2}", fontSize: fixture.size, display: true)
        #expect(NoteMathRenderer.layout("\\frac{1}{2}", fontSize: fixture.size, display: false) !== first)
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

    @Test func anImageKeepsTheRenderSize() {
        let image = simple.image()
        #expect(image.size == simple.size)
    }

    @Test func anImageDescribesItsEquationForAccessibility() {
        let image = simple.image()
        #expect(image.accessibilityDescription == "Equation: x^2 + y^2 = z^2")
    }

    @Test func theCGImageHelper() { #expect(simple.cgImage(scale: 2)?.width == Int((simple.size.width * 2).rounded(.up))) }

    @Test func theAppearanceResolvedImageHelper() { #expect(simple.image(appearance: NSAppearance(named: .darkAqua)).size == simple.size) }
}
