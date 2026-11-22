import AppKit
import QuartzCore
import Testing
@testable import ParcCore

struct SplitDividerTestsResizeSteps {
    private typealias Support = SplitDividerTestsSupport

    private typealias Steps = SplitPaneResize

    struct DividerDirection: CustomTestStringConvertible {
        let label: String
        let forward: Bool
        let factors: [Double]

        var testDescription: String { label }
    }

    @Test(arguments: [
        DividerDirection(label: "Toward the trailing pane", forward: true, factors: [0.6, 0.4]),
        DividerDirection(label: "Toward the leading pane", forward: false, factors: [0.4, 0.6]),
    ])
    func aDividerStepMovesOneTenthOfTheSplit(_ sample: DividerDirection) {
        let factors = Steps.movingDivider(0, in: [0.5, 0.5], forward: sample.forward, minimum: 0.2)
        #expect(Support.near(factors!, sample.factors))
    }

    @Test func aStepThatCrossesTheEvenPointStopsOnIt() {
        #expect(Support.near(Steps.movingDivider(0, in: [0.45, 0.55], forward: true, minimum: 0.2)!, [0.5, 0.5]))
    }

    @Test func aStepThatStartsOnTheEvenPointMovesAWholeStep() {
        #expect(Support.near(Steps.movingDivider(0, in: [0.505, 0.495], forward: true, minimum: 0.2)!, [0.6, 0.4]))
    }

    @Test func dividerStepsClampAtTheMinimum() {
        #expect(Support.near(Steps.movingDivider(0, in: [0.75, 0.25], forward: true, minimum: 0.2)!, [0.8, 0.2]))
    }

    struct UnavailableDivider: CustomTestStringConvertible {
        let label: String
        let index: Int
        let factors: [Double]
        let minimum: Double

        var testDescription: String { label }
    }

    @Test(arguments: [
        UnavailableDivider(label: "Pane already at minimum", index: 0, factors: [0.8, 0.2], minimum: 0.2),
        UnavailableDivider(label: "Divider outside the split", index: 2, factors: [0.5, 0.5], minimum: 0.2),
        UnavailableDivider(label: "Minimum exceeds available space", index: 0, factors: [0.5, 0.5], minimum: 0.6),
    ])
    func aDividerStepRefusesAnUnavailableMove(_ sample: UnavailableDivider) {
        #expect(Steps.movingDivider(sample.index, in: sample.factors, forward: true, minimum: sample.minimum) == nil)
    }

    @Test func narrowingGivesTheFreedRoomToTheOtherPanesInProportion() {
        #expect(Support.near(Steps.resizingPane(1, in: [0.2, 0.6, 0.2], growing: false, minimum: 0.2)!, [0.25, 0.5, 0.25]))
    }

    @Test func narrowingThatCrossesTheEqualShareStopsOnIt() {
        #expect(Support.near(Steps.resizingPane(1, in: [0.3, 0.4, 0.3], growing: false, minimum: 0.2)!, [1.0 / 3, 1.0 / 3, 1.0 / 3]))
    }

    @Test func wideningTakesRoomFromEachOtherPaneInProportionToItsRoomAboveTheMinimum() {
        #expect(Support.near(Steps.resizingPane(0, in: [0.2, 0.3, 0.5], growing: true, minimum: 0.2)!, [0.3, 0.3 - 0.1 / 4, 0.5 - 0.3 / 4]))
    }

    struct UnavailablePane: CustomTestStringConvertible {
        let label: String
        let index: Int
        let factors: [Double]
        let growing: Bool
        let minimum: Double

        var testDescription: String { label }
    }

    @Test(arguments: [
        UnavailablePane(label: "Neighbours already at minimum", index: 1, factors: [0.2, 0.6, 0.2], growing: true, minimum: 0.2),
        UnavailablePane(label: "Focused pane already at minimum", index: 0, factors: [0.2, 0.6, 0.2], growing: false, minimum: 0.2),
        UnavailablePane(label: "Pane outside the split", index: 3, factors: [0.2, 0.6, 0.2], growing: true, minimum: 0.2),
        UnavailablePane(label: "Single pane", index: 0, factors: [1], growing: true, minimum: 0),
    ])
    func aPaneStepRefusesAnUnavailableMove(_ sample: UnavailablePane) {
        #expect(Steps.resizingPane(sample.index, in: sample.factors, growing: sample.growing, minimum: sample.minimum) == nil)
    }

    @Test func aSplitHasEqualSharesAvailable() {
        #expect(Support.near(Steps.equal(count: 4)!, [0.25, 0.25, 0.25, 0.25]))
    }

    @Test func aSinglePaneHasNoEqualSharesAvailable() {
        #expect(Steps.equal(count: 1) == nil)
    }

    struct EqualityCase: CustomTestStringConvertible {
        let label: String
        let factors: [Double]
        let isEqual: Bool

        var testDescription: String { label }
    }

    @Test(arguments: [
        EqualityCase(label: "Equal panes", factors: [2, 2, 2], isEqual: true),
        EqualityCase(label: "Unequal panes", factors: [1, 2], isEqual: false),
        EqualityCase(label: "Single pane", factors: [1], isEqual: false),
    ])
    func equalPanesAreRecognizedOnlyInARealSplit(_ sample: EqualityCase) {
        #expect(Steps.isEqual(sample.factors) == sample.isEqual)
    }
}
