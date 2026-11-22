import Foundation
import Testing
@testable import ParcCore

struct HistorySwipeRecognizerTrackedSwipeTests {
    private typealias Page = HistorySwipeRecognizerTestsSupport.Page
    private typealias Trace = HistorySwipeRecognizerTestsSupport.Trace
    private typealias Run = HistorySwipeRecognizerTestsSupport.Run

    @Test func aMagicMouseSwipeRequestsAppKitTrackingOnceAndTakesTheEvent() {
        let trace = Trace.wheel(dx: 4, dy: 1)
        let run = Run(trace)
        let request = run.steps.compactMap(\.startsTracking)
        #expect(request == [HistorySwipeTrackingRequest(direction: .back, generation: 1)],
              "a Magic Mouse swipe asks AppKit to track it once, Back for natural rightward travel")
        #expect(run.scrollConsumes == [false, false, true], "the swipe takes the event that starts AppKit tracking")
    }

    @Test func appKitTrackedProgressArmsAndCommitsTheAdjacentPage() {
        var trace = Trace.wheel(dx: 4, dy: 1)
        trace.tracked(0, .began)
        trace.tracked(0.12, .changed)
        trace.tracked(0.36, .changed)
        trace.clock(500)
        trace.tracked(0.4, .ended)
        trace.tracked(0.7, .ended)
        trace.tracked(1, .ended, complete: true)
        trace.tracked(1, .ended)
        let run = Run(trace)
        #expect(run.gestures == [.begin(.back), .armed(true), .commit(.adjacent(.back))],
              "AppKit's tracked progress arms and commits the adjacent page")
        #expect(HistorySwipeRecognizerTestsSupport.near(run.fractions, [0.4, 1]), "tracked progress is the gesture amount over Chromium's 0.3")
    }

    @Test func aTrackedSwipeWithoutFingerPositionsNeverSchedulesOrOpensTheList() {
        var trace = Trace.wheel(dx: 4, dy: 1)
        trace.tracked(0, .began)
        trace.tracked(0.12, .changed)
        trace.tracked(0.36, .changed)
        trace.clock(500)
        trace.tracked(0.4, .ended)
        trace.tracked(0.7, .ended)
        trace.tracked(1, .ended, complete: true)
        trace.tracked(1, .ended)
        let run = Run(trace)
        #expect(run.steps.contains { $0.clockDeadline != nil } == false, "a tracked swipe never schedules the list")
        #expect(!run.outputs.contains(.hold), "without finger positions there is no hold list")
    }

    @Test func appKitCanFinishSettlingAndLateCallbacksStop() {
        var trace = Trace.wheel(dx: 4, dy: 1)
        trace.tracked(0, .began)
        trace.tracked(0.12, .changed)
        trace.tracked(0.36, .changed)
        trace.clock(500)
        trace.tracked(0.4, .ended)
        trace.tracked(0.7, .ended)
        trace.tracked(1, .ended, complete: true)
        trace.tracked(1, .ended)
        let run = Run(trace)
        #expect(run.steps.dropLast().allSatisfy { !$0.stopsTracking } && run.steps.last?.stopsTracking == true,
              "AppKit's settle animation runs out, and a callback after completion stops")
    }

    @Test func naturalLeftwardMouseTravelGoesForward() {
        let forward = Run(Trace.wheel(dx: -4, dy: 1))
        #expect(forward.steps.compactMap(\.startsTracking).map(\.direction) == [.forward],
              "natural leftward Magic Mouse travel goes Forward")
    }

    @Test func mostlyVerticalMouseTravelStaysWithThePage() {
        let vertical = Run(Trace.wheel(dx: 1, dy: 4))
        #expect(vertical.steps.allSatisfy { $0.startsTracking == nil && !$0.consumesEvent },
              "a mostly vertical Magic Mouse scroll stays with the page")
    }

    @Test func aPageThatConsumesTheScrollKeepsTheMouseGesture() {
        let consumed = Run(Trace.wheel(dx: 4, consumed: true))
        #expect(consumed.steps.allSatisfy { $0.startsTracking == nil }, "a page that takes the scroll keeps the Magic Mouse")
    }

    @Test func laterScrollEventsNeverStartTrackingTwice() {
        var repeated = Trace.wheel(dx: 4)
        repeated.scroll(.changed, dx: 5)
        repeated.scroll(.changed, dx: 6)
        repeated.tracked(0, .began)
        repeated.scroll(.changed, dx: 4)
        let once = Run(repeated)
        #expect(once.steps.compactMap(\.startsTracking).count == 1 && once.scrollConsumes.suffix(3) == [true, true, true],
              "later scroll events in the same gesture never ask AppKit to track again")
    }

    @Test func appKitCanCommitEvenBelowTheArmAmount() {
        var short = Trace.wheel(dx: 4)
        short.tracked(0, .began)
        short.tracked(0.1, .changed)
        short.tracked(0.12, .ended)
        #expect(Run(short).gestures == [.begin(.back), .commit(.adjacent(.back))],
              "AppKit's ended phase decides a tracked commit; the arm amount only moves the armed look")
    }

    @Test func theNextMouseGestureWaitsForItsOwnPageAnswer() {
        var next = Trace.wheel(dx: 4)
        next.tracked(0, .began)
        next.tracked(0.4, .ended, complete: true)
        next.scroll(.began, dx: 2)
        next.scroll(.changed, dx: 4)
        next.scroll(.changed, dx: 4)
        #expect(Run(next).steps.compactMap(\.startsTracking).count == 1,
              "a new Magic Mouse gesture waits for the page's own answer instead of reusing the last one")
    }

    @Test func anEarlyReleaseCancelsAndLetsAppKitFinishAnimating() {
        var released = Trace.wheel(dx: 4)
        released.tracked(0, .began)
        released.tracked(0.1, .changed)
        released.tracked(0.08, .cancelled)
        released.tracked(0.03, .cancelled)
        released.tracked(0, .cancelled, complete: true)
        let early = Run(released)
        #expect(early.gestures == [.begin(.back), .cancel], "releasing a Magic Mouse swipe early cancels")
        #expect(early.steps.allSatisfy { !$0.stopsTracking }, "AppKit's own cancel animation is not interrupted")
    }

    @Test func aNewGestureCancelsAndStartsANewTrackingGeneration() {
        var interrupted = Trace.wheel(dx: 4)
        interrupted.tracked(0, .began)
        interrupted.tracked(0.2, .changed)
        interrupted.scroll(.began, dx: 1)
        interrupted.tracked(0.25, .changed)
        interrupted.pageAnswers()
        interrupted.scroll(.changed, dx: 3)
        interrupted.tracked(0.1, .changed, generation: 2)
        let stale = Run(interrupted)
        #expect(stale.gestures == [.begin(.back), .cancel, .begin(.back)],
              "a new gesture cancels the old tracked swipe and starts its own")
        #expect(stale.steps.compactMap(\.startsTracking).map(\.generation) == [1, 2], "each tracking gets a new generation")
    }

    @Test func aStaleTrackingCallbackStopsWithoutOutput() {
        var interrupted = Trace.wheel(dx: 4)
        interrupted.tracked(0, .began)
        interrupted.tracked(0.2, .changed)
        interrupted.scroll(.began, dx: 1)
        let late = interrupted.inputs.count
        interrupted.tracked(0.25, .changed)
        interrupted.pageAnswers()
        interrupted.scroll(.changed, dx: 3)
        interrupted.tracked(0.1, .changed, generation: 2)
        let stale = Run(interrupted)
        #expect(stale.steps[late].stopsTracking && stale.steps[late].outputs.isEmpty, "a late callback from the old tracking stops it")
    }

    @Test func aSheetCancelsAndStopsAppKitTracking() {
        let page = Page()
        var covered = Run(Trace.wheel(dx: 4), page)
        covered.play([.trackedSwipe(HistorySwipeTrackedUpdate(generation: 1, amount: 0, phase: .began))], page)
        page.allowsHistorySwipe = false
        covered.play([.trackedSwipe(HistorySwipeTrackedUpdate(generation: 1, amount: 0.2, phase: .changed))], page)
        #expect(covered.gestures == [.begin(.back), .cancel] && covered.steps.last?.stopsTracking == true,
              "a sheet arriving mid-swipe cancels and stops AppKit tracking")
    }

    @Test func aBackgroundSwipeWithoutTouchesUsesTrackedProgress() {
        let background = Page(back: 3, forward: 0)
        var untouched = Trace.wheel(dx: 4)
        untouched.tracked(0, .began)
        untouched.tracked(0.35, .changed)
        untouched.tracked(0.4, .ended)
        #expect(Run(untouched, background).gestures == [.begin(.back), .armed(true), .commit(.adjacent(.back))],
              "a background trackpad swipe that arrives without touches still goes Back through tracked progress")
    }
}
