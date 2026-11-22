import AppKit
import CoreText
import Testing
@testable import ParcCore
@testable import ParcNotes

@MainActor
struct NoteMathLayoutTestsArraysAndScriptGlyphs {
    private let fixture: NoteMathLayoutTestsSupport.Fixture

    init() throws { fixture = try NoteMathLayoutTestsSupport.Fixture() }

    @Test func alignedLinesUpTheEqualsSigns() throws {
        let aligned = try fixture.box("\\begin{aligned} a &= b + c \\\\ x + y + z &= d \\end{aligned}")
        let equals = fixture.inks(aligned, glyph: fixture.glyph("="))
        #expect(equals.count == 2)
        #expect(abs(equals[0].origin.x - equals[1].origin.x) < 0.01)
        #expect(equals[0].origin.y > equals[1].origin.y)
    }

    @Test func matrixColumnsCentreTheirCells() throws {
        let matrix = try fixture.box("\\begin{matrix} 1 \\\\ 333 \\end{matrix}")
        #expect(abs(fixture.extent(fixture.inks(matrix, glyph: fixture.glyph("1"))).midX - fixture.extent(fixture.inks(matrix, glyph: fixture.glyph("3"))).midX) < 0.6)
    }

    @Test func matrixColumnsAlignWithAGap() throws {
        let columns = try fixture.box("\\begin{pmatrix} 1 & 2 \\\\ 3 & 4 \\end{pmatrix}")
        let x1 = fixture.inks(columns, glyph: fixture.glyph("1"))[0].origin.x, x3 = fixture.inks(columns, glyph: fixture.glyph("3"))[0].origin.x
        let x2 = fixture.inks(columns, glyph: fixture.glyph("2"))[0].origin.x, x4 = fixture.inks(columns, glyph: fixture.glyph("4"))[0].origin.x
        #expect(abs(x1 - x3) < 0.01)
        #expect(abs(x2 - x4) < 0.01)
        #expect(x2 > x1 + fixture.size * 0.9)
    }

    @Test func matricesCentreOnTheAxis() throws {
        let columns = try fixture.box("\\begin{pmatrix} 1 & 2 \\\\ 3 & 4 \\end{pmatrix}")
        #expect(abs((columns.ascent - columns.descent) / 2 - fixture.axis) < 0.5)
    }

    @Test func casesStackTheirRows() throws {
        #expect(try fixture.box("f = \\begin{cases} 1 & x > 0 \\\\ 0 & \\text{else} \\end{cases}").height > fixture.size * 1.8)
    }

    @Test func anArrayDrawsItsVerticalAndHorizontalRules() throws {
        #expect(fixture.ruleCount(try fixture.box("\\begin{array}{c|c} a & b \\\\ \\hline c & d \\end{array}")) == 2)
    }

    @Test func topLevelLineBreaksStackLines() throws { #expect(try fixture.box("a = b \\\\ c = d").height > fixture.size * 1.5) }

    @Test func linesAreCentred() throws {
        let centred = fixture.inks(try fixture.box("x \\\\ xxx"), glyph: fixture.glyph("𝑥"))
        let top = fixture.extent(centred.filter { $0.origin.y > 0 }), bottom = fixture.extent(centred.filter { $0.origin.y < 0 })
        #expect(abs(top.midX - bottom.midX) < 0.6)
        #expect(top.width < bottom.width)
    }

    @Test func alignatDropsAlignedsQuadBetweenPairs() throws {
        let alignat = try fixture.box("\\begin{alignat*}{2} a &= b & c &= d \\end{alignat*}")
        let aligned = try fixture.box("\\begin{aligned} a &= b & c &= d \\end{aligned}")
        #expect(abs(aligned.width - alignat.width - fixture.size) < 0.5)
    }

    private func multlineRows() throws -> (NoteMathBox, [NoteMathInk]) {
        let multline = try fixture.box("\\begin{multline*} a+b+c+d+e \\\\ x \\\\ y \\end{multline*}")
        return (multline, multline.inks.sorted { $0.origin.y > $1.origin.y })
    }

    @Test func multlinesFirstLineHugsTheLeft() throws {
        let (_, rows) = try multlineRows()
        #expect(try #require(rows.first).origin.x < 0.2 * fixture.size)
    }

    @Test func multlinesLastLineHugsTheRight() throws {
        let (multline, rows) = try multlineRows()
        #expect(try #require(rows.last).origin.x > multline.width - fixture.size)
    }

    @Test func multlineCentresTheMiddleLine() throws {
        let (multline, rows) = try multlineRows()
        let first = try #require(rows.first), last = try #require(rows.last)
        let middle = rows.filter { abs($0.origin.y - (first.origin.y + last.origin.y) / 2) < 0.3 * fixture.size }
        #expect(middle.count == 1)
        #expect(abs(middle[0].origin.x - multline.width / 2) < 0.6 * fixture.size)
    }

    @Test func subarrayIsScriptSizedAndTight() throws {
        let subarray = try fixture.box("\\begin{subarray}{c} a \\\\ b \\end{subarray}"), matrix = try fixture.box("\\begin{matrix} a \\\\ b \\end{matrix}")
        #expect(subarray.height < matrix.height * 0.75)
        #expect(subarray.width < matrix.width)
    }

    @Test func subarrayLeftAlignsLeft() throws {
        let rows = try fixture.box("\\begin{subarray}{l} abc \\\\ d \\end{subarray}").inks.sorted { $0.origin.y > $1.origin.y }
        #expect(abs((rows.first?.origin.x ?? 1) - (rows.last?.origin.x ?? 0)) < 0.1 * fixture.size)
    }

    @Test func dcasesSetsItsCellsInDisplayStyle() throws {
        #expect(try fixture.box("\\begin{dcases} \\frac{1}{2} & x \\end{dcases}").height > (try fixture.box("\\begin{cases} \\frac{1}{2} & x \\end{cases}")).height)
    }

    @Test func darraySetsItsCellsInDisplayStyle() throws {
        #expect(try fixture.box("\\begin{darray}{c} \\sum_{i=1}^n i \\end{darray}").height > (try fixture.box("\\begin{array}{c} \\sum_{i=1}^n i \\end{array}")).height)
    }

    @Test func matrixStarRightPushesShortEntriesRight() throws {
        let right = try fixture.box("\\begin{matrix*}[r] 1 \\\\ -10 \\end{matrix*}").inks.max { $0.origin.y < $1.origin.y }
        let left = try fixture.box("\\begin{matrix*}[l] 1 \\\\ -10 \\end{matrix*}").inks.max { $0.origin.y < $1.origin.y }
        #expect((right?.origin.x ?? 0) > (left?.origin.x ?? 0) + 0.5 * fixture.size)
    }

    @Test func aDashedColumnDrawsAsDashes() throws { #expect(fixture.ruleCount(try fixture.box("\\begin{array}{c:c} a & b \\\\ c & d \\end{array}")) > 2) }

    @Test func aSolidColumnIsOneRule() throws { #expect(fixture.ruleCount(try fixture.box("\\begin{array}{c|c} a & b \\\\ c & d \\end{array}")) == 1) }

    @Test func hdashlineDrawsAsDashes() throws { #expect(fixture.ruleCount(try fixture.box("\\begin{array}{cc} a & b \\\\ \\hdashline c & d \\end{array}")) > 2) }

    @Test func cdArrowsReachAtLeastThreeEmsWithHalfEmGaps() throws {
        let plain = try fixture.box("\\begin{CD} A @>>> B \\end{CD}")
        let objects = try fixture.box("A").width + (try fixture.box("B").width)
        #expect(plain.width >= objects + 3 * fixture.size + fixture.size - 0.5)
    }

    @Test func aLongLabelStretchesTheCDArrow() throws {
        let plain = try fixture.box("\\begin{CD} A @>>> B \\end{CD}")
        let labelled = try fixture.box("\\begin{CD} A @>{\\text{a long label}}>> B \\end{CD}")
        #expect(labelled.width > plain.width + fixture.size)
    }

    @Test func aLabelAboveTheCDArrowRaisesItsAscent() throws {
        let plain = try fixture.box("\\begin{CD} A @>>> B \\end{CD}")
        let labelled = try fixture.box("\\begin{CD} A @>{\\text{a long label}}>> B \\end{CD}")
        #expect(labelled.ascent > plain.ascent)
    }

    @Test func labelsBelowHangUnderTheCDArrow() throws {
        #expect(try fixture.box("\\begin{CD} A @>>{g}> B \\end{CD}").descent > (try fixture.box("\\begin{CD} A @>>> B \\end{CD}")).descent)
    }

    @Test func atEqualsDrawsALongEquals() throws { #expect(fixture.ruleCount(try fixture.box("\\begin{CD} A @= B \\end{CD}")) == 2) }

    @Test func aVerticalArrowRowSitsBetweenObjects() throws {
        let column = try fixture.box("\\begin{CD} A \\\\ @VVV \\\\ B \\end{CD}")
        #expect(column.height > (try fixture.box("\\begin{matrix} A \\\\ B \\end{matrix}")).height + 0.8 * fixture.size)
    }

    @Test func sideLabelsWidenTheDiagramInsteadOfSpillingOut() throws {
        let column = try fixture.box("\\begin{CD} A \\\\ @VVV \\\\ B \\end{CD}")
        let sides = try fixture.box("\\begin{CD} A \\\\ @VfVgV \\\\ B \\end{CD}")
        #expect(sides.width > column.width + 0.3 * fixture.size)
        let ink = fixture.extent(sides.inks)
        #expect(ink.minX >= -0.01)
        #expect(ink.maxX <= sides.width + 0.01)
    }

    @Test func aSquareDiagramLaysOut() throws {
        let grid = try fixture.box("\\begin{CD} A @>>> B \\\\ @VVV @AAA \\\\ C @<<< D \\end{CD}")
        #expect(grid.width >= 2 * (try fixture.box("A")).width + 3 * fixture.size)
        #expect(grid.height > 2.5 * fixture.size)
    }

    @Test func scriptAlternatesExist() { #expect(fixture.font.hasScriptAlternates) }

    @Test(arguments: ["𝑥", "2", "+", "(", "∑", "′"])
    func aSymbolHasDistinctScriptLevels(symbol: String) {
        let one = fixture.scriptGlyph(symbol, 1), two = fixture.scriptGlyph(symbol, 2)
        #expect(one != fixture.glyph(symbol))
        #expect(two != one)
        #expect(two != fixture.glyph(symbol))
    }

    @Test func superscriptsUseLevelOneAlternates() throws {
        let level1 = try fixture.box("x^{y}")
        #expect(fixture.inks(level1, glyph: fixture.scriptGlyph("𝑦", 1)).count == 1)
        #expect(fixture.inks(level1, glyph: fixture.glyph("𝑦")).isEmpty)
    }

    @Test func secondLevelScriptsUseLevelTwoAlternates() throws { #expect(fixture.inks(try fixture.box("x^{y^{z}}"), glyph: fixture.scriptGlyph("𝑧", 2)).count == 1) }

    @Test func alternateGlyphsStillUseTheMathScriptScale() throws {
        let found = fixture.inks(try fixture.box("x^{y^{z}}"), glyph: fixture.scriptGlyph("𝑧", 2)).first
        guard case .glyph(_, let tiny)? = found?.content else {
            Issue.record("the level two glyph exists")
            return
        }
        #expect(abs(CTFontGetSize(tiny) - fixture.size * 0.55) < 0.01)
    }

    @Test func styleSwitchesPickTheMatchingLevel() throws {
        let styled = try fixture.box("\\scriptstyle a \\scriptscriptstyle b")
        #expect(fixture.inks(styled, glyph: fixture.scriptGlyph("𝑎", 1)).count == 1)
        #expect(fixture.inks(styled, glyph: fixture.scriptGlyph("𝑏", 2)).count == 1)
    }

    @Test func functionNamesInScriptsUseAlternates() throws { #expect(fixture.inks(try fixture.box("e^{\\sin x}"), glyph: fixture.scriptGlyph("s", 1)).count == 1) }

    @Test func textStyleFractionsUseScriptGlyphs() throws {
        #expect(fixture.inks(try fixture.box("\\frac{a}{b}", display: false), glyph: fixture.scriptGlyph("𝑎", 1)).count == 1)
    }

    @Test func smallDelimitersInScriptsUseAlternates() throws {
        #expect(fixture.inks(try fixture.box("x_{\\left( a \\right)}"), glyph: fixture.scriptGlyph("(", 1)).count == 1)
    }

    @Test func scriptSizeTwoIsWiderThanTheTextTwo() { #expect(fixture.font.metrics(fixture.scriptGlyph("2", 1)).advance > fixture.font.metrics(fixture.glyph("2")).advance) }

    @Test func tallBasesGetTheFlattenedAccent() throws {
        let flat = try #require(fixture.font.flattenedAccent(fixture.glyph("\u{0302}")))
        #expect(fixture.inks(try fixture.box("\\hat{A}"), glyph: flat).count == 1)
    }

    @Test func shortBasesKeepTheFullAccent() throws {
        let flat = try #require(fixture.font.flattenedAccent(fixture.glyph("\u{0302}")))
        #expect(fixture.inks(try fixture.box("\\hat{x}"), glyph: flat).isEmpty)
        #expect(fixture.inks(try fixture.box("\\hat{x}"), glyph: fixture.glyph("\u{0302}")).count == 1)
    }
}
