import Foundation
import Testing
@testable import ParcCore

struct HistorySwipeRecognizerEdgeSteppingTests {
    private typealias Page = HistorySwipeRecognizerTestsSupport.Page
    private typealias Trace = HistorySwipeRecognizerTestsSupport.Trace
    private typealias Run = HistorySwipeRecognizerTestsSupport.Run

    @Test func reachingTheTopEdgeStepsByTravelAndSchedulesATick() {
        let page = Page(back: 50)
        var climb = Trace.opening(from: 0.30, toward: 1)
        climb.move(0.40)
        climb.clock(climb.time + 0.3)
        climb.move(0.40, 0.70)
        climb.move(0.40, 0.88)
        let entered = climb.time
        let run = Run(climb, page)
        #expect(run.selections == [0, 1, 2, 3, 4] && run.steps.last?.clockDeadline == entered + 0.1,
              "fingers that reach the top edge step by travel, then ask for a clock tick")
    }

    @Test func theTopEdgeTicksThroughEveryBackEntryAndStopsAtTheOldest() {
        let page = Page(back: 50)
        var climb = Trace.opening(from: 0.30, toward: 1)
        climb.move(0.40)
        climb.clock(climb.time + 0.3)
        climb.move(0.40, 0.70)
        climb.move(0.40, 0.88)
        var run = Run(climb, page)
        let deadlines = run.tickUntilQuiet(page)
        #expect(run.selections == Array(0...50) && run.detents == 50,
              "resting at the top edge reaches all 50 Back entries, one selection and detent per row")
        #expect(deadlines.count == 46 && zip(deadlines, deadlines.dropFirst()).allSatisfy { abs($1 - $0 - 0.1) < 1e-9 },
              "the edge steps one row every tenth of a second")
        #expect(run.steps.last?.clockDeadline == nil, "the ticks stop at the oldest entry")
    }

    @Test func liftingOnTheOldestEntryOpensIt() {
        let page = Page(back: 50)
        var climb = Trace.opening(from: 0.30, toward: 1)
        climb.move(0.40)
        climb.clock(climb.time + 0.3)
        climb.move(0.40, 0.70)
        climb.move(0.40, 0.88)
        var run = Run(climb, page)
        let deadlines = run.tickUntilQuiet(page)
        var lift = Trace()
        lift.x = 0.40; lift.y = 0.88; lift.time = deadlines.last ?? 0
        lift.lift()
        run.play(lift.inputs, page)
        #expect(run.gestures.last == .commit(.entry(.back, distance: 50)), "lifting there opens the oldest entry")
    }

    @Test func leavingTheEdgeStopsTicksAndResumesTravelFromTheCurrentRow() {
        let page = Page(back: 50)
        var back = Trace.opening(from: 0.30, toward: 1)
        back.move(0.40)
        back.clock(back.time + 0.3)
        back.move(0.40, 0.88)
        var down = Run(back, page)
        let first = down.steps.last?.clockDeadline ?? 0
        down.play([.clock(first), .clock(first + 0.1), .clock(first + 0.2)], page)
        let high = down.selections.last ?? 0
        var leave = Trace()
        leave.x = 0.40; leave.y = 0.88; leave.time = first + 0.25
        leave.move(0.40, 0.72)
        down.play(leave.inputs, page)
        let settled = down.selections.last ?? 0
        #expect(high == 7 && settled == 5 && down.steps.last?.clockDeadline == nil,
              "leaving the edge stops the ticks and travel steps back from where the edge left off")
    }

    @Test func aStaleTickAfterLeavingTheEdgeChangesNothing() {
        let page = Page(back: 50)
        var back = Trace.opening(from: 0.30, toward: 1)
        back.move(0.40)
        back.clock(back.time + 0.3)
        back.move(0.40, 0.88)
        var down = Run(back, page)
        let first = down.steps.last?.clockDeadline ?? 0
        down.play([.clock(first), .clock(first + 0.1), .clock(first + 0.2)], page)
        var leave = Trace()
        leave.x = 0.40; leave.y = 0.88; leave.time = first + 0.25
        leave.move(0.40, 0.72)
        down.play(leave.inputs, page)
        down.play([.clock(first + 0.4)], page)
        #expect(down.steps.last?.outputs.isEmpty == true, "a stale tick after leaving the edge changes nothing")
    }

    @Test func travelAloneCanReturnToTheCurrentPageWithoutStartingBottomEdgeTicks() {
        let page = Page(back: 50)
        var back = Trace.opening(from: 0.30, toward: 1)
        back.move(0.40)
        back.clock(back.time + 0.3)
        back.move(0.40, 0.88)
        var down = Run(back, page)
        let first = down.steps.last?.clockDeadline ?? 0
        down.play([.clock(first), .clock(first + 0.1), .clock(first + 0.2)], page)
        var leave = Trace()
        leave.x = 0.40; leave.y = 0.88; leave.time = first + 0.25
        leave.move(0.40, 0.72)
        down.play(leave.inputs, page)
        down.play([.clock(first + 0.4)], page)
        #expect(down.steps.last?.outputs.isEmpty == true, "a stale tick after leaving the edge changes nothing")
        var bottom = Trace()
        bottom.x = 0.40; bottom.y = 0.72; bottom.time = first + 0.5
        bottom.move(0.40, 0.12)
        down.play(bottom.inputs, page)
        #expect(down.selections.last == 0, "travel alone can come back to the current page")
        #expect(down.steps.last?.clockDeadline == nil, "at the current page the bottom edge has nowhere left to go")
    }

    @Test func restingAtTheBottomEdgeReturnsToTheCurrentPage() {
        let page = Page(back: 50)
        var homeward = Trace.opening(from: 0.30, toward: 1)
        homeward.move(0.40)
        homeward.clock(homeward.time + 0.3)
        homeward.move(0.40, 0.88)
        var home = Run(homeward, page)
        _ = home.tickUntilQuiet(page, limit: 30)
        let far = home.selections.last ?? 0
        var sink = Trace()
        sink.x = 0.40; sink.y = 0.88; sink.time = (home.steps.last?.clockDeadline ?? 0) - 0.05
        sink.move(0.40, 0.14)
        home.play(sink.inputs, page)
        let afterTravel = home.selections.last ?? 0
        _ = home.tickUntilQuiet(page)
        #expect(far == 34 && afterTravel == 25 && home.selections.last == 0,
              "resting at the bottom edge steps a long Back list all the way back to the current page")
    }

    @Test func theForwardListStepsThroughEveryEntryAtTheBottomEdge() {
        let ahead = Page(back: 0, forward: 30)
        var forward = Trace.opening(from: 0.60, toward: -1)
        forward.move(0.50)
        forward.clock(forward.time + 0.3)
        forward.move(0.50, 0.10)
        var newer = Run(forward, ahead)
        _ = newer.tickUntilQuiet(ahead)
        #expect(newer.selections == Array(0...30) && newer.gestures.contains(.begin(.forward)),
              "a long Forward list keeps stepping at the bottom edge")
    }

    @Test func openingWithFingersAlreadyAtTheEdgeWaitsForMovement() {
        let page = Page(back: 50)
        var high0 = Trace(natural: true)
        high0.land(0.30, 0.9)
        high0.scroll(.mayBegin)
        high0.move(0.302)
        high0.scroll(.began, dx: 2)
        high0.pageAnswers()
        high0.move(0.305)
        high0.scroll(.changed, dx: 3)
        high0.move(0.40)
        high0.clock(high0.time + 0.3)
        high0.move(0.40, 0.92)
        let parked = Run(high0, page)
        #expect(parked.gestures == [.begin(.back), .armed(true), .hold, .selection(0)] && parked.steps.last?.clockDeadline == nil,
              "a list that opens with the fingers already at the edge waits instead of scrolling by itself")
    }

    @Test func leavingAndReenteringTheEdgeStartsTheSteps() {
        let page = Page(back: 50)
        var high0 = Trace(natural: true)
        high0.land(0.30, 0.9)
        high0.scroll(.mayBegin)
        high0.move(0.302)
        high0.scroll(.began, dx: 2)
        high0.pageAnswers()
        high0.move(0.305)
        high0.scroll(.changed, dx: 3)
        high0.move(0.40)
        high0.clock(high0.time + 0.3)
        high0.move(0.40, 0.92)
        var parked = Run(high0, page)
        var again = Trace()
        again.x = 0.40; again.y = 0.92; again.time = high0.time
        again.move(0.40, 0.80)
        again.move(0.40, 0.87)
        parked.play(again.inputs, page)
        let rearmed = parked.steps.last?.clockDeadline
        _ = parked.tickUntilQuiet(page, limit: 3)
        #expect(rearmed != nil && parked.selections == [0, 1, 2, 3],
              "leaving the edge and coming back starts the steps")
    }

    @Test func aLateTickStepsJustOneRowAndSchedulesTheNext() {
        let page = Page(back: 50)
        var late = Trace.opening(from: 0.30, toward: 1)
        late.move(0.40)
        late.clock(late.time + 0.3)
        late.move(0.40, 0.88)
        var lagging = Run(late, page)
        let due = lagging.steps.last?.clockDeadline ?? 0
        lagging.play([.clock(due + 1)], page)
        #expect(lagging.steps.last.map(Run.gestures(in:)) == [.selection(5), .detent]
              && abs((lagging.steps.last?.clockDeadline ?? 0) - (due + 1.1)) < 1e-9,
              "a late tick steps a single row instead of jumping")
    }

    @Test func liftingCommitsTheCurrentEdgeRowAndStopsTicks() {
        let page = Page(back: 50)
        var lifted = Trace.opening(from: 0.30, toward: 1)
        lifted.move(0.40)
        lifted.clock(lifted.time + 0.3)
        lifted.move(0.40, 0.88)
        let pending = lifted.time + 0.1
        lifted.lift()
        lifted.clock(pending)
        let gone = Run(lifted, page)
        #expect(gone.gestures.last == .commit(.entry(.back, distance: 4)) && gone.steps.last?.outputs.isEmpty == true,
              "lifting ends the edge steps")
        #expect(gone.steps.suffix(2).allSatisfy { $0.clockDeadline == nil }, "a finished swipe asks for no more ticks")
    }
}
