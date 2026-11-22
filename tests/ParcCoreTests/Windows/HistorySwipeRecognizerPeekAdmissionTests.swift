import Foundation
import Testing
@testable import ParcCore

struct HistorySwipeRecognizerPeekAdmissionTests {
    private typealias Page = HistorySwipeRecognizerTestsSupport.Page
    private typealias Trace = HistorySwipeRecognizerTestsSupport.Trace
    private typealias Run = HistorySwipeRecognizerTestsSupport.Run

    @Test func verticalDriftCancelsDismissalAndHandsEventsBack() {
        var drift = Trace.opening(from: 0.30, toward: 1)
        drift.move(0.36)
        drift.move(0.37, 0.56)
        drift.move(0.50, 0.56)
        drift.scroll(.changed, dx: 8)
        drift.lift()
        let run = Run(drift, Page.peek)
        #expect(run.shape == [.beginDismissal, .cancel], "drifting mostly up or down springs the card back")
        #expect(run.scrollConsumes.last == false, "a drift-cancelled drag hands its events back to the page")
    }

    @Test func largeVerticalTravelCancelsEvenAnArmedDismissal() {
        var long = Trace.opening(from: 0.30, toward: 1)
        long.move(0.50)
        long.move(0.50, 0.38)
        long.move(0.50, 0.24)
        #expect(Run(long, Page.peek).shape == [.beginDismissal, .armed(true), .cancel],
              "large vertical travel cancels even an armed dismissal")
    }

    @Test func aMouseSwipeOnTheFirstPeekPageAsksAppKitToTrack() {
        var trace = Trace.wheel(dx: 4)
        trace.tracked(0, .began)
        trace.tracked(0.3, .changed)
        trace.tracked(0.55, .changed)
        trace.tracked(0.47, .changed)
        trace.tracked(0.6, .ended)
        trace.tracked(1, .ended, complete: true)
        let run = Run(trace, Page.peek)
        #expect(run.steps.compactMap(\.startsTracking) == [HistorySwipeTrackingRequest(direction: .back, generation: 1)],
              "a Magic Mouse swipe on a Peek's first page asks AppKit to track it")
    }

    @Test func appKitAmountDragsAndArmsTheCardAndItsEndClosesIt() {
        var trace = Trace.wheel(dx: 4)
        trace.tracked(0, .began)
        trace.tracked(0.3, .changed)
        trace.tracked(0.55, .changed)
        trace.tracked(0.47, .changed)
        trace.tracked(0.6, .ended)
        trace.tracked(1, .ended, complete: true)
        let run = Run(trace, Page.peek)
        #expect(run.gestures == [.beginDismissal, .armed(true), .commit(.dismiss)],
              "AppKit's amount drags the card, arms at halfway and its end closes it")
        #expect(HistorySwipeRecognizerTestsSupport.near(run.fractions, [0.3, 0.55, 0.47]), "the card follows AppKit's gesture amount")
    }

    @Test func appKitCancellationSpringsTheCardBack() {
        var early = Trace.wheel(dx: 4)
        early.tracked(0, .began)
        early.tracked(0.52, .changed)
        early.tracked(0.4, .changed)
        early.tracked(0.2, .cancelled)
        early.tracked(0, .cancelled, complete: true)
        #expect(Run(early, Page.peek).gestures == [.beginDismissal, .armed(true), .armed(false), .cancel],
              "AppKit's cancel springs the card back")
    }

    @Test func aPeekWithPagesBehindItStillGoesBack() {
        var trace = Trace.opening(from: 0.30, toward: 1)
        trace.move(0.42)
        trace.lift()
        #expect(Run(trace, Page(back: 2, forward: 0, peekFirstPage: true)).gestures
              == [.begin(.back), .armed(true), .commit(.adjacent(.back))],
              "with pages behind it a Peek's swipe still goes Back")
    }

    @Test func anOrdinaryFirstPageKeepsTheBackGesture() {
        var trace = Trace.opening(from: 0.30, toward: 1)
        trace.move(0.42)
        trace.lift()
        #expect(Run(trace, Page(back: 0)).outputs.isEmpty, "an ordinary first page keeps the gesture")
    }

    @Test func swipingForwardNeverDismissesThePeek() {
        var forward = Trace.opening(from: 0.60, toward: -1)
        forward.move(0.48)
        forward.lift()
        #expect(Run(forward, Page.peek).outputs.isEmpty, "swiping toward Forward never dismisses")
    }

    @Test func aPeekWithForwardHistoryStillGoesForward() {
        var forward = Trace.opening(from: 0.60, toward: -1)
        forward.move(0.48)
        forward.lift()
        #expect(Run(forward, Page(back: 0, forward: 1, peekFirstPage: true)).gestures
              == [.begin(.forward), .armed(true), .commit(.adjacent(.forward))],
              "a Peek with pages ahead still goes Forward")
    }

    @Test func aCarouselThatTakesTheFirstScrollKeepsThePeekGesture() {
        var trace = Trace.opening(from: 0.30, toward: 1, consumed: true)
        trace.move(0.50)
        trace.lift()
        #expect(Run(trace, Page.peek).outputs.isEmpty, "a carousel that takes the first scroll keeps the gesture")
    }

    @Test func disablingOverscrollKeepsTheCardStill() {
        var none = Trace.opening(from: 0.30, toward: 1, propagatesX: false)
        none.move(0.50)
        #expect(Run(none, Page.peek).outputs.isEmpty, "overscroll-behavior: none keeps the card still")
    }

    @Test func turningOffSystemSwipesAlsoTurnsOffDismissal() {
        var plain = Trace.opening(from: 0.30, toward: 1)
        plain.move(0.50)
        let off = Page.peek
        off.swipesBetweenPages = false
        #expect(Run(plain, off).outputs.isEmpty, "the system swipe setting turns dismissal off too")
    }

    @Test func losingThePageDuringDismissalSpringsTheCardBack() {
        let page = Page.peek
        var covered = Run(Trace.opening(from: 0.30, toward: 1), page)
        page.allowsHistorySwipe = false
        var more = Trace()
        more.x = 0.305
        more.move(0.40)
        covered.play(more.inputs, page)
        #expect(covered.gestures == [.beginDismissal, .cancel], "losing the page mid-drag springs the card back")
    }

    @Test func aNewTouchCancelsThePeekDrag() {
        var touch = Trace.opening(from: 0.30, toward: 1)
        touch.move(0.40)
        touch.land(0.5)
        #expect(Run(touch, Page.peek).gestures == [.beginDismissal, .cancel], "a new touch cancels the drag")
    }
}
