import AppKit
import CoreText
import Testing
@testable import Parc
@testable import ParcCore
@testable import ParcNotes

@MainActor
struct NoteMathLayoutTestsChemistry {
    private let fixture: NoteMathLayoutTestsSupport.Fixture

    init() throws { fixture = try NoteMathLayoutTestsSupport.Fixture() }

    @Test func macrosLayOutLikeTheirExpansion() throws {
        #expect(abs(try fixture.box("\\newcommand{\\sq}[1]{#1^2}\\sq{x}").width - (try fixture.box("x^2")).width) < 0.001)
    }

    @Test func formulaNumbersAreSubscripts() throws {
        let two = fixture.inks(try fixture.box("\\ce{H2O}"), glyph: fixture.scriptGlyph("2", 1))
        #expect(two.count == 1)
        #expect(two[0].origin.y < 0)
    }

    @Test func elementsAreUpright() throws {
        let water = try fixture.box("\\ce{H2O}")
        #expect(fixture.inks(water, glyph: fixture.glyph("H")).count == 1)
        #expect(fixture.inks(water, glyph: fixture.glyph("𝐻")).isEmpty)
    }

    @Test func chargeAboveAndCountBelowShareAColumn() throws {
        let sulfate = try fixture.box("\\ce{SO4^2-}")
        let four = fixture.inks(sulfate, glyph: fixture.scriptGlyph("4", 1)), charge = fixture.inks(sulfate, glyph: fixture.scriptGlyph("2", 1))
        #expect(four.count == 1)
        #expect(charge.count == 1)
        #expect(four[0].origin.y < 0)
        #expect(charge[0].origin.y > 0)
        #expect(abs(four[0].origin.x - charge[0].origin.x) < 0.5)
    }

    @Test func isotopeNumbersRightAlignOnTheLeft() throws {
        let isotope = try fixture.box("\\ce{^{227}_{90}Th}")
        let seven = fixture.inks(isotope, glyph: fixture.scriptGlyph("7", 1)), zero = fixture.inks(isotope, glyph: fixture.scriptGlyph("0", 1))
        let scale = fixture.size * 0.7 / 1000
        let sevenRight = (seven.first?.origin.x ?? 0) + fixture.font.metrics(fixture.scriptGlyph("7", 1)).advance * scale
        let zeroRight = (zero.first?.origin.x ?? 0) + fixture.font.metrics(fixture.scriptGlyph("0", 1)).advance * scale
        #expect(seven.count == 1)
        #expect(zero.count == 1)
        #expect(abs(sevenRight - zeroRight) < 0.01)
        #expect(fixture.extent(seven).minY > fixture.extent(zero).maxY)
    }

    @Test func llapTakesNoWidth() throws { #expect(abs(try fixture.box("x\\llap{y}").width - (try fixture.box("x")).width) < 0.01) }

    @Test func llapOverlapsLeftwards() throws {
        let lapY = fixture.inks(try fixture.box("x\\llap{y}"), glyph: fixture.glyph("𝑦"))
        #expect(lapY.count == 1)
        #expect(lapY[0].origin.x < (try fixture.box("x")).width - 1)
    }

    private func harpoonHalves(_ latex: String) throws -> (CGRect, CGRect) {
        let marks = try fixture.box(latex).inks.filter { ink in
            if case .glyph(let value, _) = ink.content { return value != fixture.glyph("A") && value != fixture.glyph("B") }
            return false
        }
        return (fixture.extent(marks.filter { fixture.extent([$0]).midY > fixture.axis }), fixture.extent(marks.filter { fixture.extent([$0]).midY < fixture.axis }))
    }

    @Test func equilibriumHarpoonsStackAroundTheAxis() throws {
        let balanced = try harpoonHalves("\\ce{A <=> B}")
        #expect(!balanced.0.isNull)
        #expect(!balanced.1.isNull)
    }

    @Test func balancedHarpoonsHaveEqualWidths() throws {
        let balanced = try harpoonHalves("\\ce{A <=> B}")
        #expect(abs(balanced.0.width - balanced.1.width) < 0.6)
    }

    @Test func balancedHarpoonsDoNotOverlap() throws {
        let balanced = try harpoonHalves("\\ce{A <=> B}")
        #expect(balanced.0.minY > balanced.1.maxY - 0.01)
    }

    @Test func theEquilibriumArrowIsLong() { #expect((try? harpoonHalves("\\ce{A <=> B}"))?.0.width ?? 0 >= fixture.size * 1.3) }

    @Test func rightLeaningEquilibriumHasALongTopHarpoon() throws {
        let right = try harpoonHalves("\\ce{A <=>> B}")
        #expect(right.0.width > right.1.width * 1.3)
    }

    @Test func leftLeaningEquilibriumHasALongBottomHarpoon() throws {
        let left = try harpoonHalves("\\ce{A <<=> B}")
        #expect(left.1.width > left.0.width * 1.3)
    }

    @Test func arrowLabelsSitAboveAndBelow() throws {
        let label = try fixture.box("\\ce{A ->[heat][cat] B}")
        #expect(label.ascent > fixture.size * 0.7)
        #expect(label.descent > fixture.size * 0.3)
    }

    @Test func arrowsStretchForLabels() throws {
        #expect(try fixture.box("\\ce{A ->[very long label] B}").width > (try fixture.box("\\ce{A -> B}")).width + fixture.size)
    }

    @Test func aPrecipitateDrawsADownArrow() throws { #expect(fixture.inks(try fixture.box("\\ce{BaSO4 v}"), glyph: fixture.glyph("↓")).count == 1) }

    @Test func unitsFollowTheirNumber() throws { #expect(try fixture.box("\\pu{9.81 m/s^2}").width > (try fixture.box("9.81")).width + fixture.size) }
}
