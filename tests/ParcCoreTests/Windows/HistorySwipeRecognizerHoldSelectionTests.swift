import Foundation
import Testing
@testable import ParcCore

struct HistorySwipeRecognizerHoldSelectionTests {
    private typealias Page = HistorySwipeRecognizerTestsSupport.Page
    private typealias Trace = HistorySwipeRecognizerTestsSupport.Trace
    private typealias Run = HistorySwipeRecognizerTestsSupport.Run

    @Test func verticalTravelSelectsAndTicksEveryRowUntilItReturnsToTheCurrentPage() {
        var trace = Trace.opening(from: 0.30, toward: 1)
        trace.move(0.315)
        trace.move(0.40)
        let armedAt = trace.time
        trace.clock(armedAt + 0.29)
        trace.clock(armedAt + 0.3)
        trace.scroll(.changed, dx: 1)
        trace.move(0.40, 0.59)
        trace.move(0.40, 0.67)
        trace.move(0.40, 0.84)
        trace.move(0.40, 0.75)
        trace.move(0.40, 0.66)
        trace.move(0.40, 0.40)
        trace.lift()
        let run = Run(trace)
        #expect(run.gestures == [.begin(.back), .armed(true), .hold, .selection(0),
                               .selection(1), .detent, .selection(2), .detent, .selection(3), .detent,
                               .selection(2), .detent, .selection(1), .detent, .selection(0), .detent, .cancel],
              "vertical travel steps one row at a time with a detent each, clamps at the ends, and lifting on the current page cancels")
    }

    @Test func theOpenListOwnsItsScrollEvents() {
        var trace = Trace.opening(from: 0.30, toward: 1)
        trace.move(0.315)
        trace.move(0.40)
        let armedAt = trace.time
        trace.clock(armedAt + 0.29)
        trace.clock(armedAt + 0.3)
        trace.scroll(.changed, dx: 1)
        let run = Run(trace)
        #expect(run.scrollConsumes.last == true, "the hold owns its events")
    }

    @Test func liftingOnARowCommitsThatHistoryEntry() {
        var pick = Trace.opening(from: 0.30, toward: 1)
        pick.move(0.40)
        pick.clock(pick.time + 0.3)
        pick.move(0.40, 0.59)
        pick.lift()
        #expect(Run(pick).gestures == [.begin(.back), .armed(true), .hold, .selection(0), .selection(1), .detent,
                                     .commit(.entry(.back, distance: 1))],
              "lifting on a row commits that history entry")
    }

    @Test func movingDownTheForwardListStopsAtItsLastEntry() {
        var forward = Trace.opening(from: 0.60, toward: -1)
        forward.move(0.50)
        forward.clock(forward.time + 0.3)
        forward.move(0.50, 0.41)
        forward.move(0.50, 0.25)
        forward.lift()
        #expect(Run(forward).gestures == [.begin(.forward), .armed(true), .hold, .selection(0), .selection(1), .detent,
                                        .selection(2), .detent, .commit(.entry(.forward, distance: 2))],
              "Forward holds too, steps as the fingers move down its top-to-bottom list, and stops at the last entry")
    }

    @Test func movingUpTheForwardListStopsAtTheCurrentPage() {
        var upward = Trace.opening(from: 0.60, toward: -1)
        upward.move(0.50)
        upward.clock(upward.time + 0.3)
        upward.move(0.50, 0.41)
        upward.move(0.50, 0.52)
        upward.move(0.50, 0.70)
        upward.lift()
        #expect(Run(upward).gestures == [.begin(.forward), .armed(true), .hold, .selection(0), .selection(1), .detent,
                                       .selection(0), .detent, .cancel],
              "moving up a Forward list heads back to the current page at its top, stops there, and lifting there cancels")
    }

    @Test func movingDownTheBackListStopsAtTheCurrentPage() {
        var down = Trace.opening(from: 0.30, toward: 1)
        down.move(0.40)
        down.clock(down.time + 0.3)
        down.move(0.40, 0.59)
        down.move(0.40, 0.48)
        down.move(0.40, 0.30)
        down.lift()
        #expect(Run(down).gestures == [.begin(.back), .armed(true), .hold, .selection(0), .selection(1), .detent,
                                     .selection(0), .detent, .cancel],
              "moving down a Back list heads back to the current page at its bottom, stops there, and lifting there cancels")
    }

    @Test func travelShortOfOneRowKeepsTheSelection() {
        var short = Trace.opening(from: 0.30, toward: 1)
        short.move(0.40)
        short.clock(short.time + 0.3)
        short.move(0.40, 0.575)
        #expect(Run(short).gestures.suffix(1) == [.selection(0)], "travel short of 8% of the trackpad keeps the row")
    }

    @Test func aFastVerticalSweepStillTicksEveryRow() {
        var jump = Trace.opening(from: 0.30, toward: 1)
        jump.move(0.40)
        jump.clock(jump.time + 0.3)
        jump.move(0.40, 0.75)
        #expect(Run(jump, Page(back: 5)).gestures.suffix(6) == [.selection(1), .detent, .selection(2), .detent,
                                                              .selection(3), .detent],
              "a fast vertical sweep still steps and ticks every row")
    }

    @Test func theBackListOpensOnTheCurrentPage() {
        var trace = Trace.opening(from: 0.30, toward: 1)
        trace.move(0.40)
        trace.clock(trace.time + 0.3)
        let opened = Run(trace)
        #expect(opened.gestures == [.begin(.back), .armed(true), .hold, .selection(0)] && opened.recognizer.selection == 0,
              "the list opens with the current page selected")
    }

    @Test func liftingWhenTheListOpensNavigatesNowhere() {
        var trace = Trace.opening(from: 0.30, toward: 1)
        trace.move(0.40)
        trace.clock(trace.time + 0.3)
        trace.lift()
        let lifted = Run(trace)
        #expect(lifted.gestures.last == .cancel && !lifted.gestures.contains { if case .commit = $0 { true } else { false } },
              "lifting as soon as the list opens navigates nowhere")
    }

    @Test func theForwardListOpensOnTheCurrentPage() {
        var forward = Trace.opening(from: 0.60, toward: -1)
        forward.move(0.50)
        forward.clock(forward.time + 0.3)
        forward.lift()
        #expect(Run(forward).gestures == [.begin(.forward), .armed(true), .hold, .selection(0), .cancel],
              "a Forward list opens on the current page too")
    }

    @Test func movingUpFromTheBottomOfTheBackListCanPickThePreviousPage() {
        var older = Trace.opening(from: 0.30, toward: 1)
        older.move(0.40)
        older.clock(older.time + 0.3)
        older.move(0.40, 0.40)
        older.move(0.40, 0.49)
        older.lift()
        #expect(Run(older).gestures == [.begin(.back), .armed(true), .hold, .selection(0), .selection(1), .detent,
                                      .commit(.entry(.back, distance: 1))],
              "moving down a Back list stays on the current page; moving up reaches the previous page")
    }
}
