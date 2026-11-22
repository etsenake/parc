import Foundation
import Testing
@testable import ParcCore

struct HistorySwipeRecognizerParametersTests {
    private typealias Page = HistorySwipeRecognizerTestsSupport.Page
    private typealias Trace = HistorySwipeRecognizerTestsSupport.Trace
    private typealias Run = HistorySwipeRecognizerTestsSupport.Run

    @Test func theDefaultTrackpadDistancesMatchChromium() {
        let p = HistorySwipeParameters.dia
        #expect(p.commitDistance == 0.08 && p.consumeDistance == 0.01 && p.directionDistance == 0.001,
              "Chromium's commit, consume and direction distances, which Dia shares")
    }

    @Test func theDefaultVerticalCancellationRulesMatchChromium() {
        let p = HistorySwipeParameters.dia
        #expect(p.verticalCancelDistance == 0.24 && p.verticalDriftDistance == 0.01
              && p.verticalDominance == 2 && p.verticalExcess == 1.3, "Chromium's vertical cancel rules")
    }

    @Test func theDefaultTrackedArmPointMatchesChromium() {
        let p = HistorySwipeParameters.dia
        #expect(p.trackedArmAmount == 0.3, "Chromium's tracked-swipe arm point")
    }

    @Test func theDefaultRubberBandHoldAndRowSettingsMatchDia() {
        let p = HistorySwipeParameters.dia
        #expect(p.rubberBand == 0.15 && p.holdDelay == 0.3 && p.rowStep == 0.08, "Dia's rubber band, hold delay and row step")
    }

    @Test func theDefaultEdgeZoneTicksTenTimesPerSecond() {
        let p = HistorySwipeParameters.dia
        #expect(p.edgeZone == 0.15 && p.edgeStepInterval == 0.1, "long histories keep stepping ten rows a second at the edges")
    }

    @Test func theDefaultEdgeMarginRequiresDeliberateTravel() {
        let p = HistorySwipeParameters.dia
        #expect(p.edgeMargin == 0.03, "edge stepping needs a deliberate 3% of travel and stops 3% outside its zone")
    }

    @Test func theDefaultListCloseProgressAllowsSomeDrift() {
        let p = HistorySwipeParameters.dia
        #expect(p.listCloseProgress == 0.85, "an open list closes only once the fingers slide clearly below the commit point")
    }

    @Test func anInjectedCommitDistanceChangesProgress() {
        var tuned = HistorySwipeParameters.dia
        tuned.commitDistance = 0.1
        var trace = Trace.opening(from: 0.30, toward: 1)
        trace.move(0.315)
        trace.move(0.39)
        trace.move(0.45)
        trace.move(0.60)
        let restAt = trace.time
        trace.clock(restAt + 0.5)
        trace.clock(restAt + 1)
        trace.time = restAt + 1
        trace.move(0.60, 0.56)
        trace.move(0.60, 0.61)
        let run = Run(trace, parameters: tuned)
        #expect(HistorySwipeRecognizerTestsSupport.near(run.fractions, [0.15, 0.9, 1, 1]), "the commit distance is injectable")
    }

    @Test func anInjectedRubberBandChangesStretch() {
        var tuned = HistorySwipeParameters.dia
        tuned.commitDistance = 0.1
        tuned.rubberBand = 0.5
        var trace = Trace.opening(from: 0.30, toward: 1)
        trace.move(0.315)
        trace.move(0.39)
        trace.move(0.45)
        trace.move(0.60)
        let restAt = trace.time
        trace.clock(restAt + 0.5)
        trace.clock(restAt + 1)
        trace.time = restAt + 1
        trace.move(0.60, 0.56)
        trace.move(0.60, 0.61)
        let run = Run(trace, parameters: tuned)
        #expect(HistorySwipeRecognizerTestsSupport.near(run.stretches, [0.15, 0.9, 1.2, 1.5]), "the rubber band's resistance is injectable")
    }

    @Test func theHoldDelayAndRowStepCanBeInjected() {
        var tuned = HistorySwipeParameters.dia
        tuned.holdDelay = 1
        tuned.rowStep = 0.1
        var trace = Trace.opening(from: 0.30, toward: 1)
        trace.move(0.315)
        trace.move(0.39)
        trace.move(0.45)
        trace.move(0.60)
        let restAt = trace.time
        trace.clock(restAt + 0.5)
        trace.clock(restAt + 1)
        trace.time = restAt + 1
        trace.move(0.60, 0.56)
        trace.move(0.60, 0.61)
        let run = Run(trace, parameters: tuned)
        #expect(run.gestures == [.begin(.back), .armed(true), .hold, .selection(0), .selection(1), .detent],
              "the hold delay and row step are injectable")
    }

    @Test func anInfiniteHoldDelayTurnsTheListOff() {
        var off = HistorySwipeParameters.dia
        off.holdDelay = .infinity
        var never = Trace.opening(from: 0.30, toward: 1)
        never.move(0.40)
        never.clock(1e9)
        never.lift()
        #expect(Run(never, parameters: off).gestures == [.begin(.back), .armed(true), .commit(.adjacent(.back))],
              "an infinite hold delay turns the list off")
    }

    @Test func anEmptyEdgeZoneLeavesSteppingToFingerTravel() {
        var still = HistorySwipeParameters.dia
        still.edgeZone = 0
        var edge = Trace.opening(from: 0.30, toward: 1)
        edge.move(0.40)
        edge.clock(edge.time + 0.3)
        edge.move(0.40, 0.95)
        let page = Page(back: 20)
        var fixed = Run(edge, page, parameters: still)
        #expect(fixed.tickUntilQuiet(page).isEmpty && fixed.selections == [0, 1, 2, 3, 4, 5],
              "an empty edge zone leaves long histories to finger travel alone")
    }

    @Test func theDefaultDismissalUsesHalfwayCommitWithRoomToDisarm() {
        let p = HistorySwipeParameters.dia
        #expect(p.dismissDistance == 0.3 && p.dismissCommitProgress == 0.5 && p.dismissDisarmProgress == 0.45,
              "a Peek card leaves over 30% of the trackpad, closes past halfway and disarms just below it")
    }

    @Test func theDefaultFlickRequiresRecentSpeedAndSomeTravel() {
        let p = HistorySwipeParameters.dia
        #expect(p.flickVelocity == 0.6 && p.flickProgress == 0.1 && p.velocityWindow == 0.08,
              "a flick is 60% of the trackpad a second after a tenth of the card's travel, measured over 80 ms")
    }
}
