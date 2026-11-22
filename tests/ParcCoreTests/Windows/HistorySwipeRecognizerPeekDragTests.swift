import Foundation
import Testing
@testable import ParcCore

struct HistorySwipeRecognizerPeekDragTests {
    private typealias Page = HistorySwipeRecognizerTestsSupport.Page
    private typealias Trace = HistorySwipeRecognizerTestsSupport.Trace
    private typealias Run = HistorySwipeRecognizerTestsSupport.Run

    private let release0 = HistorySwipeOutput.release(velocity: 0)

    private func dismissalSwipe() -> Trace {
        var trace = Trace.opening(from: 0.30, toward: 1)
        for x in [0.36, 0.42, 0.47, 0.50] { trace.move(x) }
        trace.rest()
        trace.lift()
        trace.scroll(.none, dx: 4, momentum: .changed)
        return trace
    }

    @Test func aNaturalBackSwipeDismissesThePeekPastHalfway() {
        let run = Run(dismissalSwipe(), Page.peek)
        #expect(run.shape == [.beginDismissal, .armed(true), release0, .commit(.dismiss)],
              "on a Peek's first page a natural rightward swipe drags the card and closes it past halfway")
        #expect(run.recognizer.dismissing && run.recognizer.state == .completed, "the lift finishes the dismissal")
    }

    @Test func theCardProgressFollowsFingerTravelWithoutRubberBanding() {
        let run = Run(dismissalSwipe(), Page.peek)
        #expect(HistorySwipeRecognizerTestsSupport.near(run.fractions.prefix(4).map { ($0 * 1e6).rounded() / 1e6 }, [0.2, 0.4, 0.566667, 0.666667]),
              "card progress is finger travel over 30% of the trackpad")
        #expect(run.fractions == run.stretches, "the card follows the fingers with no rubber band")
    }

    @Test func restingBeforeLiftReleasesTheCardWithoutSpeed() {
        let run = Run(dismissalSwipe(), Page.peek)
        #expect(run.releases.count == 1 && abs(run.releases[0]) < 0.05, "resting before the lift releases with no speed")
    }

    @Test func dismissingAPeekNeverWarmsBackNavigation() {
        let run = Run(dismissalSwipe(), Page.peek)
        #expect(!run.steps.contains { $0.preloadsBack }, "a dismissal never warms a Back navigation")
    }

    @Test func dismissingAPeekNeverSchedulesTheList() {
        let run = Run(dismissalSwipe(), Page.peek)
        #expect(run.steps.allSatisfy { $0.clockDeadline == nil }, "a dismissal never schedules the history list")
    }

    @Test func momentumAfterDismissalStaysOffThePage() {
        let run = Run(dismissalSwipe(), Page.peek)
        #expect(run.scrollConsumes.last == true, "the momentum after a dismissal stays off the page")
    }

    @Test func restingPastHalfwayNeverOpensTheList() {
        var held = Trace.opening(from: 0.30, toward: 1)
        held.move(0.48)
        held.clock(held.time + 1)
        held.move(0.4805, after: 1)
        #expect(!Run(held, Page.peek).gestures.contains(.hold), "resting past halfway never opens a history list")
    }

    @Test func theBackDirectionStillDismissesWithNaturalScrollingOff() {
        var unnatural = Trace.opening(from: 0.60, toward: -1, natural: false)
        for x in [0.54, 0.48, 0.44] { unnatural.move(x) }
        unnatural.rest()
        unnatural.lift()
        #expect(Run(unnatural, Page.peek).shape == [.beginDismissal, .armed(true), release0, .commit(.dismiss)],
              "without natural scrolling the Back-direction swipe dismisses")
    }

    @Test func lettingGoBeforeHalfwaySpringsTheCardBack() {
        var trace = Trace.opening(from: 0.30, toward: 1)
        trace.move(0.36)
        trace.move(0.40)
        trace.rest()
        trace.lift()
        let run = Run(trace, Page.peek)
        #expect(run.shape == [.beginDismissal, release0, .cancel], "letting go before halfway springs the card back")
    }

    @Test func liftingBeforeTheCardMovesNeverClosesIt() {
        var tiny = Trace.opening(from: 0.30, toward: 1)
        tiny.lift()
        #expect(Run(tiny, Page.peek).shape == [.beginDismissal, release0, .cancel],
              "lifting before the card moves never closes")
    }

    @Test func aQuickFlickClosesBeforeHalfway() {
        var flick = Trace.opening(from: 0.30, toward: 1)
        flick.move(0.31)
        flick.move(0.34, after: 0.01)
        flick.lift()
        let fast = Run(flick, Page.peek)
        #expect(fast.shape == [.beginDismissal, release0, .commit(.dismiss)],
              "a quick flick closes the card even though it never reached halfway")
    }

    @Test func flickSpeedIsReportedInCardLengthsPerSecond() {
        var flick = Trace.opening(from: 0.30, toward: 1)
        flick.move(0.31)
        flick.move(0.34, after: 0.01)
        flick.lift()
        let fast = Run(flick, Page.peek)
        #expect(fast.releases.first.map { $0 > 2 } == true, "the flick's speed is reported in card lengths a second")
    }

    @Test func aFlickNeedsATenthOfTheCardsTravelToClose() {
        var short = Trace.opening(from: 0.30, toward: 1)
        short.move(0.31)
        short.move(0.325, after: 0.01)
        short.lift()
        #expect(Run(short, Page.peek).shape == [.beginDismissal, release0, .cancel],
              "a flick needs a tenth of the card's travel before it can close")
    }

    @Test func aSlowShortDragSpringsBack() {
        var lazy = Trace.opening(from: 0.30, toward: 1)
        lazy.move(0.31)
        lazy.move(0.34, after: 0.2)
        lazy.lift()
        #expect(Run(lazy, Page.peek).shape == [.beginDismissal, release0, .cancel], "a slow short drag springs back")
    }

    @Test func speedOlderThanEightyMillisecondsDoesNotCountAsAFlick() {
        var stale = Trace.opening(from: 0.30, toward: 1)
        stale.move(0.31)
        stale.move(0.34, after: 0.01)
        stale.rest(0.15)
        stale.lift()
        #expect(Run(stale, Page.peek).shape == [.beginDismissal, release0, .cancel],
              "speed from more than 80 ms before the lift doesn't count as a flick")
    }

    @Test func pullingBackDisarmsTheCardAndSpringsItBackOnLift() {
        var trace = Trace.opening(from: 0.30, toward: 1)
        for x in [0.40, 0.47, 0.44, 0.43, 0.38] { trace.move(x) }
        trace.rest()
        trace.lift()
        let back = Run(trace, Page.peek)
        #expect(back.shape == [.beginDismissal, .armed(true), .armed(false), release0, .cancel],
              "pulling back below the disarm point silently disarms and letting go springs back")
    }

    @Test func theCardFollowsTheFingersBack() {
        var trace = Trace.opening(from: 0.30, toward: 1)
        for x in [0.40, 0.47, 0.44, 0.43, 0.38] { trace.move(x) }
        trace.rest()
        trace.lift()
        let back = Run(trace, Page.peek)
        #expect(back.fractions.suffix(3).allSatisfy { $0 < 0.5 }, "the card follows the fingers back")
    }

    @Test func tremorAroundHalfwayArmsTheCardJustOnce() {
        var tremor = Trace.opening(from: 0.30, toward: 1)
        for x in [0.46, 0.449, 0.456, 0.447, 0.455, 0.448] { tremor.move(x) }
        tremor.rest()
        tremor.lift()
        let shaky = Run(tremor, Page.peek)
        #expect(shaky.gestures.filter { $0 == .armed(true) }.count == 1 && !shaky.gestures.contains(.armed(false)),
              "tremor around halfway arms once, so the tap plays once")
    }

    @Test func lettingGoWhileArmedClosesTheCard() {
        var tremor = Trace.opening(from: 0.30, toward: 1)
        for x in [0.46, 0.449, 0.456, 0.447, 0.455, 0.448] { tremor.move(x) }
        tremor.rest()
        tremor.lift()
        let shaky = Run(tremor, Page.peek)
        #expect(shaky.shape.last == .commit(.dismiss), "letting go while armed closes")
    }

    @Test func crossingHalfwayAfterDisarmingArmsAgainAndClosesOnLift() {
        var again = Trace.opening(from: 0.30, toward: 1)
        for x in [0.47, 0.42, 0.47] { again.move(x) }
        again.rest()
        again.lift()
        #expect(Run(again, Page.peek).shape == [.beginDismissal, .armed(true), .armed(false), .armed(true), release0,
                                               .commit(.dismiss)], "crossing halfway again taps again and closes")
    }

    @Test func flickingBackTowardTheStartKeepsTheCardEvenPastHalfway() {
        var thrown = Trace.opening(from: 0.30, toward: 1)
        for x in [0.40, 0.48, 0.52] { thrown.move(x) }
        thrown.move(0.47, after: 0.01)
        thrown.lift()
        #expect(Run(thrown, Page.peek).shape == [.beginDismissal, .armed(true), release0, .cancel],
              "flicking back toward the start keeps the card even past halfway")
    }

    @Test func pullingPastTheStartHoldsTheCardAtRest() {
        var behind = Trace.opening(from: 0.30, toward: 1)
        behind.move(0.36)
        behind.move(0.25)
        behind.rest()
        behind.lift()
        let past = Run(behind, Page.peek)
        #expect(past.fractions.last == 0 && past.shape.last == .cancel, "pulling past the start holds the card at rest")
    }
}
