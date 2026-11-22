import Foundation
import Testing
@testable import ParcCore

struct EaselEquationGeometryTests {
    private static let natural = EaselEquation.natural(typeset: EaselEquationSize(width: 100, height: 40))
    private static let centre = EaselPoint(x: 300, y: 200)

    @Test(arguments: ["", " \n\t "])
    func emptyOrWhitespaceEquationsAreBlank(tex: String) {
        #expect(EaselEquation.isBlank(tex))
    }

    @Test func texIsNotBlank() {
        #expect(!EaselEquation.isBlank("x"))
    }

    @Test func longTexIsCapped() {
        #expect(EaselEquation.clamped(String(repeating: "x", count: EaselEquation.maximumLength + 50)).count == EaselEquation.maximumLength)
    }

    @Test func shortTexIsUntouched() {
        #expect(EaselEquation.clamped("x^2") == "x^2")
    }

    @Test func theFrameIsTheTypesetSizePlusPadding() {
        #expect(Self.natural == EaselEquationSize(width: 100 + 2 * EaselEquation.padding, height: 40 + 2 * EaselEquation.padding))
    }

    @Test(arguments: [nil, EaselEquationSize(width: 0, height: 10), EaselEquationSize(width: .nan, height: 10)])
    func missingDegenerateOrNonFiniteTypesettingUsesThePlaceholderSize(typeset: EaselEquationSize?) {
        #expect(EaselEquation.natural(typeset: typeset) == EaselEquation.emptySize)
    }

    @Test func scaleOneKeepsTheNaturalSizeCentred() {
        let frame = EaselEquation.frame(natural: Self.natural, scale: 1, centeredOn: Self.centre)
        #expect(frame.width == Self.natural.width && frame.height == Self.natural.height)
        #expect(frame.x + frame.width / 2 == 300 && frame.y + frame.height / 2 == 200)
    }

    @Test(arguments: [1.0, 2.0])
    func theScaleReadsBackFromTheFrame(scale: Double) {
        let frame = EaselEquation.frame(natural: Self.natural, scale: scale, centeredOn: Self.centre)
        #expect(EaselEquation.scale(of: frame, natural: Self.natural) == scale)
    }

    @Test func scalingKeepsTheAspect() {
        let doubled = EaselEquation.frame(natural: Self.natural, scale: 2, centeredOn: Self.centre)
        #expect(doubled.width == Self.natural.width * 2 && doubled.height == Self.natural.height * 2)
    }

    @Test func typingKeepsTheChosenScaleAndCentre() {
        let wider = EaselEquationSize(width: 400, height: 80)
        let roomy = EaselEquation.frame(natural: Self.natural, scale: 2, centeredOn: EaselPoint(x: 1000, y: 600))
        let refit = EaselEquation.refitted(roomy, from: Self.natural, to: wider)
        #expect(refit.width == wider.width * 2 && refit.height == wider.height * 2)
        #expect(abs((refit.x + refit.width / 2) - (roomy.x + roomy.width / 2)) < 0.001)
        #expect(abs((refit.y + refit.height / 2) - (roomy.y + roomy.height / 2)) < 0.001)
    }

    @Test func growingNearTheEdgeStaysOnTheBoard() {
        let doubled = EaselEquation.frame(natural: Self.natural, scale: 2, centeredOn: Self.centre)
        let grown = EaselEquation.refitted(doubled, from: Self.natural, to: EaselEquationSize(width: 400, height: 80))
        #expect(grown.x >= 0 && grown.y >= 0)
    }

    @Test func tinyFramesClampToTheMinimumScale() {
        #expect(EaselEquation.scale(of: EaselRect(x: 0, y: 0, width: 1, height: 1), natural: Self.natural) == EaselEquation.minimumScale)
    }

    @Test func hugeFramesClampToTheMaximumScale() {
        #expect(EaselEquation.scale(of: EaselRect(x: 0, y: 0, width: 1_000_000, height: 1), natural: Self.natural) == EaselEquation.maximumScale)
    }

    @Test func anUnusableNaturalSizeReadsAsScaleOne() {
        let frame = EaselEquation.frame(natural: Self.natural, scale: 1, centeredOn: Self.centre)
        #expect(EaselEquation.scale(of: frame, natural: EaselEquationSize(width: 0, height: 0)) == 1)
    }

    @Test func framesNeverGoNegative() {
        #expect(EaselEquation.frame(natural: Self.natural, scale: .nan, centeredOn: EaselPoint(x: 0, y: 0)).x >= 0)
    }

    @Test func theInnerBoxIsTheTypesetSizeAtScaleInsetByTheScaledPadding() {
        let doubled = EaselEquation.frame(natural: Self.natural, scale: 2, centeredOn: Self.centre)
        let inner = EaselEquation.inner(doubled, natural: Self.natural)
        #expect(inner.width == 200 && inner.height == 80)
        #expect(inner.x == doubled.x + EaselEquation.padding * 2)
    }

    @Test func aSecondEquationStepsAside() {
        let visible = EaselRect(x: 0, y: 0, width: 800, height: 600)
        let first = EaselEquation.placed(natural: EaselEquation.emptySize, visible: visible, occupied: [])
        let second = EaselEquation.placed(natural: EaselEquation.emptySize, visible: visible, occupied: [first])
        #expect(first.x != second.x && first.y != second.y)
    }
}
