import Foundation
import Testing
@testable import ParcCore

struct HistorySwipeRecognizerPageEventsTests {
    private typealias Page = HistorySwipeRecognizerTestsSupport.Page
    private typealias Trace = HistorySwipeRecognizerTestsSupport.Trace
    private typealias Run = HistorySwipeRecognizerTestsSupport.Run

    @Test func aCarouselThatTakesTheFirstScrollKeepsTheGesture() {
        var trace = Trace.opening(from: 0.30, toward: 1, consumed: true)
        trace.move(0.35)
        trace.scroll(.changed, dx: 6)
        trace.move(0.42)
        trace.scroll(.changed, dx: 8)
        trace.lift()
        let run = Run(trace)
        #expect(run.outputs.isEmpty && !run.scrollConsumes.contains(true),
              "a carousel that takes the first scroll keeps the whole gesture")
    }

    @Test func theSwipeWaitsForThePagesScrollAnswer() {
        var late = Trace(natural: true)
        late.land(0.30)
        late.move(0.302)
        late.scroll(.began, dx: 2)
        late.move(0.305)
        late.scroll(.changed, dx: 3)
        late.pageAnswers()
        late.move(0.31)
        late.scroll(.changed, dx: 3)
        let waiting = Run(late)
        #expect(waiting.scrollConsumes == [false, false, true] && waiting.gestures == [.begin(.back)],
              "the swipe waits for the page's answer before it can begin")
    }

    @Test func syntheticAndMomentumScrollsDoNotSupplyThePagesAnswer() {
        var synthetic = Trace(natural: true)
        synthetic.land(0.30)
        synthetic.move(0.302)
        synthetic.scroll(.began, dx: 2)
        synthetic.inputs += [.pageScroll(.began(synthetic: true, momentum: false)), .overscroll(propagatesX: true),
                             .pageScroll(.updated(consumed: false))]
        synthetic.move(0.305)
        synthetic.scroll(.changed, dx: 3)
        synthetic.inputs += [.pageScroll(.began(synthetic: false, momentum: true)), .pageScroll(.updated(consumed: false))]
        synthetic.move(0.31)
        synthetic.scroll(.changed, dx: 3)
        #expect(Run(synthetic).outputs.isEmpty, "synthetic and momentum scroll starts are not the page's answer")
    }

    @Test func anEarlierScrollAnswerCannotStartTheNextSwipe() {
        var stale = Trace.opening(from: 0.30, toward: 1)
        stale.lift()
        stale.land(0.30)
        stale.move(0.302)
        stale.scroll(.began, dx: 2)
        stale.move(0.31)
        stale.scroll(.changed, dx: 3)
        #expect(Run(stale).gestures == [.begin(.back), .cancel],
              "an earlier gesture's answer never lets the next one start before the page replies")
    }

    @Test func disablingOverscrollKeepsTheGestureWithThePage() {
        var none = Trace.opening(from: 0.30, toward: 1, propagatesX: false)
        none.move(0.42)
        none.scroll(.changed, dx: 8)
        none.lift()
        let blocked = Run(none)
        #expect(blocked.outputs.isEmpty && !blocked.scrollConsumes.contains(true),
              "overscroll-behavior: none keeps the swipe off the page")
    }

    @Test func aPageThatNeverOverscrollsHorizontallyKeepsTheGesture() {
        var silent = Trace.opening(from: 0.30, toward: 1, propagatesX: nil)
        silent.move(0.42)
        silent.scroll(.changed, dx: 8)
        #expect(Run(silent).outputs.isEmpty, "a page that never overscrolls horizontally keeps the gesture")
    }

    @Test func verticalDriftCancelsAndReturnsEventsToThePage() {
        var drift = Trace.opening(from: 0.30, toward: 1)
        drift.move(0.31, 0.53)
        drift.scroll(.changed, dx: 2, dy: 6)
        drift.move(0.40, 0.53)
        drift.scroll(.changed, dx: 8)
        drift.lift()
        let run = Run(drift)
        #expect(run.gestures == [.begin(.back), .cancel], "more vertical than horizontal travel cancels")
        #expect(run.scrollConsumes.suffix(2) == [false, false], "a cancelled swipe hands the events back to the page")
    }

    @Test func aVerticalStartNeverShowsASwipe() {
        var early = Trace(natural: true)
        early.land(0.30)
        early.move(0.302, 0.52)
        early.scroll(.began, dx: 2)
        early.pageAnswers()
        early.move(0.31, 0.52)
        early.scroll(.changed, dx: 3)
        #expect(Run(early).outputs.isEmpty, "a vertical start never shows a swipe")
    }

    @Test func largeVerticalTravelCancelsAnArmedSwipeBeforeHold() {
        var long = Trace.opening(from: 0.30, toward: 1)
        long.move(0.65)
        long.move(0.65, 0.40)
        long.move(0.65, 0.25)
        let far = Run(long)
        #expect(far.gestures == [.begin(.back), .armed(true), .cancel],
              "Chromium's large vertical travel cancels even an armed swipe before the hold")
    }

    @Test func coveringThePageCancelsTheSwipeAndReturnsEvents() {
        let sheet = Page()
        var covered = Run(Trace.opening(from: 0.30, toward: 1), sheet)
        sheet.allowsHistorySwipe = false
        var rest = Trace()
        rest.x = 0.30
        rest.move(0.40)
        rest.scroll(.changed, dx: 8)
        covered.play(rest.inputs, sheet)
        #expect(covered.gestures == [.begin(.back), .cancel] && covered.scrollConsumes.last == false,
              "covering the page cancels the swipe and hands its events back")
    }

    @Test func navigationCancelsAnInProgressSwipe() {
        let page = Page()
        var lifecycle = Run(Trace.opening(from: 0.30, toward: 1), page)
        lifecycle.play([.cancel], page)
        var rest = Trace()
        rest.x = 0.30
        rest.move(0.40)
        rest.scroll(.changed, dx: 8)
        rest.lift()
        lifecycle.play(rest.inputs, page)
        #expect(lifecycle.gestures == [.begin(.back), .cancel] && lifecycle.scrollConsumes.last == false,
              "a navigation or page change cancels the swipe")
    }

    @Test func navigationAfterCommitDoesNotUndoTheSwipe() {
        var committed = Trace.opening(from: 0.30, toward: 1)
        committed.move(0.40)
        committed.lift()
        committed.inputs.append(.cancel)
        committed.scroll(.none, dx: 4, momentum: .changed)
        let after = Run(committed)
        #expect(after.gestures == [.begin(.back), .armed(true), .commit(.adjacent(.back))]
              && after.scrollConsumes.last == true, "the navigation a commit starts does not undo the finished swipe")
    }

    @Test func aNewTouchCancelsALiveSwipe() {
        var touch = Trace.opening(from: 0.30, toward: 1)
        touch.move(0.40)
        touch.land(0.5)
        #expect(Run(touch).gestures == [.begin(.back), .armed(true), .cancel], "a new touch cancels the live swipe")
    }

    @Test func aNewScrollCancelsALiveSwipe() {
        var scroll = Trace.opening(from: 0.30, toward: 1)
        scroll.move(0.35)
        scroll.scroll(.began, dx: 1)
        #expect(Run(scroll).gestures == [.begin(.back), .cancel], "a new scroll gesture cancels the live swipe")
    }

    @Test func verticalEventsReachThePageWhileTheSwipeIsOnlyPossible() {
        var vertical = Trace.opening(from: 0.30, toward: 1)
        vertical.scroll(.changed, dx: 3, dy: 1)
        #expect(Run(vertical).scrollConsumes.suffix(2) == [true, false],
              "while the swipe is only possible, events with vertical travel still reach the page")
    }

    @Test func cancelledTouchesCancelTheSwipe() {
        var cancelled = Trace.opening(from: 0.30, toward: 1)
        cancelled.move(0.40)
        cancelled.inputs.append(.touches(.cancelled, cancelled.fingers, time: cancelled.time))
        #expect(Run(cancelled).gestures == [.begin(.back), .armed(true), .cancel], "cancelled touches cancel the swipe")
    }
}
