import Foundation
import Testing
@testable import ParcCore

struct HistorySwipeRecognizerListCollapseTests {
    private typealias Page = HistorySwipeRecognizerTestsSupport.Page
    private typealias Trace = HistorySwipeRecognizerTestsSupport.Trace
    private typealias Run = HistorySwipeRecognizerTestsSupport.Run

    private func collapsedList() -> (trace: Trace, belowIndex: Int) {
        var trace = Trace.opening(from: 0.30, toward: 1)
        trace.move(0.40)
        trace.clock(trace.time + 0.3)
        trace.move(0.40, 0.59)
        trace.move(0.40, 0.67)
        trace.move(0.36, 0.67)
        let belowIndex = trace.inputs.count - 1
        trace.scroll(.changed, dx: -3)
        return (trace, belowIndex)
    }

    @Test func slidingBelowCommitClosesTheListAndContinuesTheSwipe() {
        let page = Page()
        let (trace, belowIndex) = collapsedList()
        let collapsed = Run(trace, page)
        #expect(collapsed.gestures == [.begin(.back), .armed(true), .hold, .selection(0), .selection(1), .detent,
                                     .selection(2), .detent, .armed(false)]
              && collapsed.steps[belowIndex].outputs.first.map { if case .progress = $0 { true } else { false } } == true,
              "sliding below the commit point disarms and closes the list, and the swipe carries on")
        #expect(collapsed.recognizer.state == .tracking && collapsed.recognizer.selection == nil
              && collapsed.steps.last?.clockDeadline == nil && collapsed.scrollConsumes.last == true,
              "the collapsed swipe keeps its events, drops the selection and asks for no tick")
    }

    @Test func liftingAfterTheListClosesBelowCommitCancels() {
        let page = Page()
        var lifted = collapsedList().trace
        lifted.lift()
        #expect(Run(lifted, page).gestures.last == .cancel, "lifting below the commit point after the list closed cancels")
    }

    @Test func travelUsedForRowSelectionDoesNotCountTowardLaterVerticalCancellation() {
        let page = Page()
        var vertical = collapsedList().trace
        vertical.move(0.365, 0.69)
        vertical.move(0.37, 0.67)
        #expect(Run(vertical, page).gestures.last == .armed(false),
              "vertical travel spent choosing rows doesn't count toward the vertical cancel afterwards")
    }

    @Test func rearmingSchedulesAHoldWithoutReopeningTheListImmediately() {
        let page = Page()
        var reopened = collapsedList().trace
        reopened.move(0.41, 0.67)
        let rearmedAt = reopened.time
        reopened.move(0.42, 0.67, after: 0.1)
        let again = Run(reopened, page)
        #expect(again.gestures.suffix(2) == [.armed(false), .armed(true)] && !again.steps.suffix(2).contains { $0.outputs.contains(.hold) },
              "sliding back past the commit point rearms without reopening the list at once")
        #expect(again.steps.last?.clockDeadline == rearmedAt + 0.3, "rearming schedules a new hold")
    }

    @Test func anotherHoldReopensTheListOnTheCurrentPage() {
        let page = Page()
        var reopened = collapsedList().trace
        reopened.move(0.41, 0.67)
        reopened.move(0.42, 0.67, after: 0.1)
        let restAt = reopened.time
        var again = Run(reopened, page)
        let wakes = again.tickUntilQuiet(page)
        #expect(abs(wakes.last! - (restAt + 0.3)) < 1e-9 && again.steps.last?.outputs == [.hold, .selection(0)],
              "resting another 0.3 s reopens the list on the current page")
    }

    @Test func aReopenedListStepsFromTheCurrentPage() {
        let page = Page()
        var reopened = collapsedList().trace
        reopened.move(0.41, 0.67)
        reopened.move(0.42, 0.67, after: 0.1)
        let restAt = reopened.time
        var again = Run(reopened, page)
        _ = again.tickUntilQuiet(page)
        var pick = Trace()
        pick.x = 0.42; pick.y = 0.67; pick.time = restAt + 0.3
        pick.move(0.42, 0.76)
        pick.lift()
        again.play(pick.inputs, page)
        #expect(again.gestures.suffix(3) == [.selection(1), .detent, .commit(.entry(.back, distance: 1))],
              "the reopened list steps from the current page again")
    }

    @Test func liftingAfterRearmingBeforeTheListReopensCommitsTheAdjacentPage() {
        let page = Page()
        var commit = collapsedList().trace
        commit.move(0.42, 0.67)
        commit.lift()
        #expect(Run(commit, page).gestures.suffix(2) == [.armed(true), .commit(.adjacent(.back))],
              "lifting after rearming, before the list reopens, goes to the adjacent page")
    }

    @Test func slidingThroughTheCommitPointThenPastTheStartCancelsAndReturnsEvents() {
        var out = Trace.opening(from: 0.30, toward: 1)
        out.move(0.40)
        out.clock(out.time + 0.3)
        out.move(0.33)
        out.scroll(.changed, dx: -3)
        out.move(0.29)
        out.scroll(.changed, dx: -3)
        out.lift()
        let slid = Run(out)
        #expect(slid.gestures == [.begin(.back), .armed(true), .hold, .selection(0), .armed(false), .cancel],
              "sliding back below the commit point closes the list, and sliding on past the start cancels")
        #expect(slid.scrollConsumes.suffix(2) == [true, false], "the page gets its events back after sliding out")
    }

    @Test func slidingStraightFromTheListPastTheStartCancels() {
        var jump = Trace.opening(from: 0.30, toward: 1)
        jump.move(0.40)
        jump.clock(jump.time + 0.3)
        jump.move(0.29)
        #expect(Run(jump).gestures == [.begin(.back), .armed(true), .hold, .selection(0), .cancel],
              "a single slide from the list past the start cancels")
    }

    @Test func aLittleDriftBelowCommitKeepsTheListAndItsPick() {
        var jitter = Trace.opening(from: 0.30, toward: 1)
        jitter.move(0.3804)
        jitter.clock(jitter.time + 0.3)
        jitter.move(0.3799, 0.665)
        jitter.lift()
        let slipped = Run(jitter)
        #expect(slipped.gestures.contains(.hold) && slipped.gestures.last == .commit(.entry(.back, distance: 2)),
              "a hair of drift below the commit point keeps the open list and its pick")
    }

    @Test func slidingBackAfterVerticalTravelClosesTheListAndKeepsTheSwipeGoing() {
        var drifted = Trace.opening(from: 0.30, toward: 1)
        drifted.move(0.34, 0.52)
        drifted.move(0.38, 0.55)
        drifted.move(0.42, 0.58)
        drifted.clock(drifted.time + 0.3)
        let opened = drifted.inputs.count
        drifted.move(0.364, 0.58)
        let folded = Run(drifted)
        #expect(folded.steps.prefix(opened).flatMap(Run.gestures(in:)).contains(.hold)
              && folded.steps.dropFirst(opened).flatMap(Run.gestures(in:)) == [.armed(false)]
              && folded.recognizer.state == .tracking,
              "sliding back after earlier vertical travel folds the list and keeps the swipe going")
    }
}
