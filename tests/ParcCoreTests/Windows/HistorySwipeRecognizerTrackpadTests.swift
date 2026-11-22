import Foundation
import Testing
@testable import ParcCore

struct HistorySwipeRecognizerTrackpadTests {
    private typealias Page = HistorySwipeRecognizerTestsSupport.Page
    private typealias Trace = HistorySwipeRecognizerTestsSupport.Trace
    private typealias Run = HistorySwipeRecognizerTestsSupport.Run

    private func band(_ progress: Double, _ resistance: Double = 0.15) -> Double {
        let resisted = (progress - 1) * resistance
        return 1 + resisted / (resisted + 1)
    }

    private func backSwipe() -> (trace: Trace, opened: Int) {
        var trace = Trace.opening(from: 0.30, toward: 1)
        let opened = trace.inputs.count
        trace.move(0.315)
        trace.scroll(.changed, dx: 4)
        trace.move(0.35)
        trace.scroll(.changed, dx: 6)
        trace.move(0.40)
        trace.scroll(.changed, dx: 8)
        trace.move(0.41)
        trace.lift()
        trace.scroll(.ended)
        trace.scroll(.none, dx: 5, momentum: .began)
        trace.scroll(.none, dx: 4, momentum: .changed)
        trace.scroll(.none, momentum: .ended)
        return (trace, opened)
    }

    @Test func aNaturalRightwardSwipeCommitsBack() {
        let run = Run(backSwipe().trace)
        #expect(run.gestures == [.begin(.back), .armed(true), .commit(.adjacent(.back))],
              "a natural rightward two-finger swipe arms and commits Back")
        #expect(run.recognizer.state == .completed, "lifting armed completes the gesture")
    }

    @Test func backProgressIsClampedAndStretchesPastTheCommitDistance() {
        let run = Run(backSwipe().trace)
        #expect(HistorySwipeRecognizerTestsSupport.near(run.fractions, [0.1875, 0.625, 1, 1]), "progress is finger travel over the commit distance, clamped")
        #expect(HistorySwipeRecognizerTestsSupport.near(run.stretches, [0.1875, 0.625, band(1.25), band(1.375)]),
              "travel past the commit point stretches with Dia's 0.15 rubber band")
    }

    @Test func rubberBandStretchIncreasesByLessAsTravelGrows() {
        var far = Trace.opening(from: 0.30, toward: 1)
        for x in [0.46, 0.54, 0.62, 0.70] { far.move(x) }
        let stretched = Run(far).stretches.suffix(4)
        let gains = zip(stretched, stretched.dropFirst()).map { $1 - $0 }
        #expect(HistorySwipeRecognizerTestsSupport.near(Array(stretched), [band(2), band(3), band(4), band(5)]) && gains == gains.sorted(by: >)
              && stretched.last! < 1.4, "each further reach past the commit point moves the indicator less")
    }

    @Test func aBackSwipeTakesEventsOnceItCanBeginAndSwallowsMomentum() {
        let run = Run(backSwipe().trace)
        #expect(run.scrollConsumes == [false, false, true, true, true, true, false, false, true, false],
              "the page keeps events until the swipe is possible, then momentum after the lift is swallowed")
    }

    @Test func aBackSwipeHintsNavigationOnce() {
        let (trace, opened) = backSwipe()
        let run = Run(trace)
        #expect(run.steps[opened].preloadsBack && run.steps.filter(\.preloadsBack).count == 1,
              "tracking a Back swipe hints a likely back navigation once")
    }

    private func forwardSwipe() -> Trace {
        var trace = Trace.opening(from: 0.60, toward: -1)
        trace.move(0.585)
        trace.scroll(.changed, dx: -4)
        trace.move(0.55)
        trace.move(0.50)
        trace.lift()
        return trace
    }

    @Test func aNaturalLeftwardSwipeCommitsForward() {
        let run = Run(forwardSwipe())
        #expect(run.gestures == [.begin(.forward), .armed(true), .commit(.adjacent(.forward))],
              "a natural leftward two-finger swipe arms and commits Forward")
    }

    @Test func forwardProgressIncreasesAsTheFingersMoveLeft() {
        let run = Run(forwardSwipe())
        #expect(HistorySwipeRecognizerTestsSupport.near(run.fractions, [0.1875, 0.625, 1]), "Forward progress grows as the fingers travel left")
    }

    @Test func aForwardSwipeNeverHintsBack() {
        let run = Run(forwardSwipe())
        #expect(!run.steps.contains { $0.preloadsBack }, "Forward never hints a back navigation")
    }

    struct DirectionCase: Sendable, CustomTestStringConvertible {
        let testDescription: String
        let start: Double
        let sign: Double
        let end: Double
        let expected: HistorySwipeDirection
    }

    @Test(arguments: [
        DirectionCase(testDescription: "Rightward", start: 0.30, sign: 1, end: 0.40, expected: .forward),
        DirectionCase(testDescription: "Leftward", start: 0.60, sign: -1, end: 0.50, expected: .back),
    ])
    func turningOffNaturalScrollingReversesTheSwipeDirection(_ swipe: DirectionCase) {
        var trace = Trace.opening(from: swipe.start, toward: swipe.sign, natural: false)
        trace.move(swipe.end)
        trace.lift()
        #expect(Run(trace).gestures == [.begin(swipe.expected), .armed(true), .commit(.adjacent(swipe.expected))])
    }

    @Test func aSwipeNeedsEnoughHorizontalTravelToPickADirection() {
        var still = Trace(natural: true)
        still.land(0.30)
        still.scroll(.began, dx: 1)
        still.pageAnswers()
        still.move(0.3005)
        still.scroll(.changed, dx: 1)
        #expect(Run(still).gestures.isEmpty, "a swipe needs Chromium's minimum horizontal travel to choose a direction")
    }

    @Test func aPageWithNoBackHistoryKeepsItsEvents() {
        var trace = Trace.opening(from: 0.30, toward: 1)
        trace.move(0.40)
        trace.scroll(.changed, dx: 8)
        trace.lift()
        let noBack = Run(trace, Page(back: 0))
        #expect(noBack.outputs.isEmpty && !noBack.scrollConsumes.contains(true),
              "a page with nothing Back keeps every event")
    }

    @Test func turningOffSystemSwipesLeavesEveryEventWithThePage() {
        var trace = Trace.opening(from: 0.30, toward: 1)
        trace.move(0.40)
        trace.scroll(.changed, dx: 8)
        trace.lift()
        let off = Page()
        off.swipesBetweenPages = false
        let disabled = Run(trace, off)
        #expect(disabled.outputs.isEmpty && !disabled.scrollConsumes.contains(true),
              "the system swipe-between-pages setting turns the gesture off")
    }

    @Test func aCoveredWindowNeverBeginsASwipe() {
        var trace = Trace.opening(from: 0.30, toward: 1)
        trace.move(0.40)
        trace.scroll(.changed, dx: 8)
        trace.lift()
        let covered = Page()
        covered.allowsHistorySwipe = false
        #expect(Run(trace, covered).outputs.isEmpty, "a covered window never begins a swipe")
    }

    @Test func backingOffTheCommitPointCancelsOnLift() {
        var trace = Trace.opening(from: 0.30, toward: 1)
        trace.move(0.315)
        trace.move(0.40)
        trace.move(0.36)
        trace.scroll(.changed, dx: -3)
        trace.lift()
        trace.scroll(.none, dx: -3, momentum: .changed)
        let run = Run(trace)
        #expect(run.gestures == [.begin(.back), .armed(true), .armed(false), .cancel],
              "backing off below the commit point disarms, and lifting there cancels")
        #expect(run.recognizer.state == .completed, "the lift finishes the gesture without navigating")
    }

    @Test func aDisarmedSwipeStillOwnsEventsAndMomentum() {
        var trace = Trace.opening(from: 0.30, toward: 1)
        trace.move(0.315)
        trace.move(0.40)
        trace.move(0.36)
        trace.scroll(.changed, dx: -3)
        trace.lift()
        trace.scroll(.none, dx: -3, momentum: .changed)
        let run = Run(trace)
        #expect(run.scrollConsumes.suffix(2) == [true, true], "a disarmed swipe still owns its events and momentum")
    }

    @Test func rearmingAfterAReversalCommits() {
        var again = Trace.opening(from: 0.30, toward: 1)
        again.move(0.40)
        again.move(0.36)
        again.move(0.42)
        again.lift()
        #expect(Run(again).gestures == [.begin(.back), .armed(true), .armed(false), .armed(true), .commit(.adjacent(.back))],
              "rearming after a reversal commits")
    }

    @Test func aBackgroundWindowCanSwipeAndHoldWithJustPageHistory() {
        let background = Page(back: 3, forward: 0)
        var trace = Trace.opening(from: 0.30, toward: 1)
        trace.move(0.40)
        trace.clock(trace.time + 0.3)
        trace.move(0.40, 0.59)
        trace.lift()
        #expect(Run(trace, background).gestures == [.begin(.back), .armed(true), .hold, .selection(0),
                                                  .selection(1), .detent, .commit(.entry(.back, distance: 1))],
              "a swipe and hold need nothing from the page beyond coverage and history")
    }
}
