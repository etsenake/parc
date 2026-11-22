import AppKit
import CoreText
import Testing
@testable import ParcCore
@testable import ParcNotes

@MainActor
struct NoteMathLayoutTestsReferencesAndText {
    private let fixture: NoteMathLayoutTestsSupport.Fixture

    init() throws { fixture = try NoteMathLayoutTestsSupport.Fixture() }

    private var numbering: NoteMathNumberingContext { NoteMathNumberingContext(references: ["e": [.text("12", .roman)]], referenceDigest: "e=12") }

    private func referenced(_ key: String) -> NoteMathRendering {
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
        let missingBox = NoteMathTypesetter(font: fixture.font, baseSize: fixture.size).typeset([.reference("gone", parenthesized: true, label: nil)], display: false)
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

    @Test func theReferenceNumberDraws() { #expect(fixture.bitmap(referenced("e")).ink(x: 0.55...1, y: 0...1) > 40) }

    @Test func theMissingMarkerDraws() { #expect(fixture.bitmap(referenced("gone")).ink(x: 0.55...1, y: 0...1) > 40) }

    @Test func aComposedAccentIsOneLetter() throws {
        #expect(abs(try fixture.box("\\text{\\'e}", display: false).width - (try fixture.box("\\text{é}", display: false)).width) < 0.01)
    }

    @Test func sizesWorkInText() throws {
        #expect(try fixture.box("\\text{\\Huge a}", display: false).width > (try fixture.box("\\text{a}", display: false)).width * 2)
    }

    @Test func linksWorkInsideText() throws {
        #expect(try fixture.box("\\text{see \\href{https://a.b}{this}}", display: false).links.first?.url == "https://a.b")
    }

    @Test func utildeHangsATildeBelow() throws {
        #expect(try fixture.box("\\utilde{ABCD}", display: false).descent > (try fixture.box("ABCD", display: false)).descent + 0.1 * fixture.size)
    }

    private func inkSpan(_ target: NoteMathBox, above floor: CGFloat) -> CGFloat {
        var low = CGFloat.infinity, high = -CGFloat.infinity
        for ink in target.inks {
            guard case .glyph(let glyph, let ctFont) = ink.content else { continue }
            let scale = CTFontGetSize(ctFont) / fixture.font.unitsPerEm
            let bounds = fixture.font.metrics(glyph).bounds
            guard ink.origin.y + bounds.minY * scale > floor else { continue }
            low = min(low, ink.origin.x + bounds.minX * scale)
            high = max(high, ink.origin.x + bounds.maxX * scale)
        }
        return high - low
    }

    @Test(arguments: ["Overrightarrow", "overleftharpoon", "overrightharpoon"]) func stretchyMarksStretchOverTheirBase(mark: String) throws {
        let marked = try fixture.box("\\\(mark){ABCDEFGH}", display: false), base = try fixture.box("ABCDEFGH", display: false)
        #expect(marked.ascent > base.ascent + 0.15 * fixture.size)
        #expect(inkSpan(marked, above: base.ascent) > base.width * 0.9)
    }

    @Test func overlinesegmentMatchesKaTeXsBox() throws {
        let plain = try fixture.box("ABCD", display: false), over = try fixture.box("\\overlinesegment{ABCD}", display: false)
        #expect(abs(over.ascent - plain.ascent - 0.522 * fixture.size) < 0.01)
        #expect(fixture.ruleCount(over) == 3)
    }

    @Test func underlinesegmentHangsBelow() throws {
        let plain = try fixture.box("ABCD", display: false), under = try fixture.box("\\underlinesegment{ABCD}", display: false)
        #expect(abs(under.descent - plain.descent - 0.522 * fixture.size) < 0.01)
        #expect(fixture.ruleCount(under) == 3)
    }

    @Test func phaseDrawsItsAngle() throws {
        let phase = try fixture.box("\\phase{-78^\\circ}", display: false), base = try fixture.box("-78^\\circ", display: false)
        #expect(phase.width > base.width + 0.3 * fixture.size)
        #expect(phase.descent > base.descent + 0.15 * fixture.size)
        #expect(fixture.segments(phase) >= 1)
    }

    @Test func anglRoofsItsContent() throws {
        let angle = try fixture.box("\\angl{n}", display: false), letter = try fixture.box("n", display: false)
        #expect(fixture.ruleCount(angle) == 2)
        #expect(abs(angle.ascent - letter.ascent - 0.16 * fixture.size) < 0.01)
    }

    @Test func twoHeadedArrowsStretch() throws {
        let short = try fixture.box("\\xtwoheadrightarrow{a}", display: false)
        #expect(try fixture.box("\\xtwoheadrightarrow{abcdefgh}", display: false).width > short.width + 2 * fixture.size)
        #expect(try fixture.box("\\xtwoheadleftarrow{abcdefgh}", display: false).width > short.width + 2 * fixture.size)
    }

    @Test func xlongequalDrawsTwoLongBars() throws {
        let equal = try fixture.box("\\xlongequal{abcdefgh}", display: false)
        #expect(fixture.ruleCount(equal) == 2)
        #expect(equal.width > 3 * fixture.size)
    }

    @Test func mathchoicePicksTheDisplayBranchInDisplay() throws {
        let choice = "\\mathchoice{MMMM}{MM}{M}{i}"
        #expect(try fixture.box(choice).width > (try fixture.box(choice, display: false)).width * 1.5)
    }

    @Test func mathchoicePicksTheScriptBranch() throws {
        let choice = "\\mathchoice{MMMM}{MM}{M}{i}"
        #expect(abs(try fixture.box("x^{" + choice + "}", display: false).width - (try fixture.box("x^{M}", display: false)).width) < 0.01)
    }

    @Test func mathchoiceIsInvisibleToSpacing() throws {
        #expect(abs(try fixture.box("a\\mathchoice{+}{+}{+}{+}b", display: false).width - (try fixture.box("a+b", display: false)).width) < 0.01)
    }

    @Test func vcenterCentresOnTheAxis() throws {
        let centered = try fixture.box("\\vcenter{\\frac{a}{b}}", display: false)
        #expect(abs((centered.ascent - centered.descent) / 2 - fixture.font.constants[.axisHeight] * fixture.size / fixture.font.unitsPerEm) < 0.01)
    }

    @Test func pmodSpreadsOutInDisplay() throws { #expect(try fixture.box("\\pmod{a}").width > (try fixture.box("\\pmod{a}", display: false)).width) }

    @Test func mathstrutIsAParenthesisTall() throws {
        let strut = try fixture.box("\\mathstrut", display: false)
        #expect(strut.width == 0)
        #expect(strut.ascent > 0)
        #expect(strut.descent > 0)
    }

    @Test(arguments: ["\\TeX", "\\LaTeX", "\\KaTeX"]) func logosDraw(logo: String) throws { #expect(try fixture.box(logo, display: false).width > 0.9 * fixture.size) }

    @Test func pmbDoublesUp() throws { #expect(try fixture.box("\\pmb{x}", display: false).width > (try fixture.box("x", display: false)).width) }
}
