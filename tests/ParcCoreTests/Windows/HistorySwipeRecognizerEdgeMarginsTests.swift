import Foundation
import Testing
@testable import ParcCore

struct HistorySwipeRecognizerEdgeMarginsTests {
    private typealias Page = HistorySwipeRecognizerTestsSupport.Page
    private typealias Trace = HistorySwipeRecognizerTestsSupport.Trace
    private typealias Run = HistorySwipeRecognizerTestsSupport.Run

    @Test func tremorAcrossTheTopBoundaryDoesNotStartTicksWhenTheListOpenedInside() {
        let page = Page(back: 50)
        var inside = Trace.opening(from: 0.30, toward: 1, y: 0.851)
        inside.move(0.40)
        inside.clock(inside.time + 0.3)
        for y in [0.849, 0.851, 0.849, 0.852, 0.8505] { inside.move(0.40, y, after: 0.03) }
        var parkedInside = Run(inside, page)
        #expect(parkedInside.tickUntilQuiet(page).isEmpty && parkedInside.selections == [0],
              "a list that opens just inside the top zone ignores tremor across the zone's edge")
    }

    @Test func liftingAfterTremorStillGoesNowhere() {
        let page = Page(back: 50)
        var inside = Trace.opening(from: 0.30, toward: 1, y: 0.851)
        inside.move(0.40)
        inside.clock(inside.time + 0.3)
        for y in [0.849, 0.851, 0.849, 0.852, 0.8505] { inside.move(0.40, y, after: 0.03) }
        var parkedInside = Run(inside, page)
        var liftInside = Trace()
        liftInside.x = 0.40; liftInside.y = 0.8505; liftInside.time = inside.time + 1
        liftInside.lift()
        parkedInside.play(liftInside.inputs, page)
        #expect(parkedInside.gestures.last == .cancel, "so lifting there still goes nowhere")
    }

    @Test func tremorIntoTheTopZoneDoesNotStartTicksWhenTheListOpenedOutside() {
        let page = Page(back: 50)
        var outside = Trace.opening(from: 0.30, toward: 1, y: 0.849)
        outside.move(0.40)
        outside.clock(outside.time + 0.3)
        for y in [0.851, 0.849, 0.852, 0.8515] { outside.move(0.40, y, after: 0.03) }
        var parkedOutside = Run(outside, page)
        #expect(parkedOutside.tickUntilQuiet(page).isEmpty && parkedOutside.selections == [0],
              "a list that opens just outside the top zone ignores tremor into it")
    }

    @Test func tremorIntoTheBottomZoneDoesNotStartForwardTicks() {
        let ahead = Page(back: 0, forward: 30)
        var low = Trace.opening(from: 0.60, toward: -1, y: 0.151)
        low.move(0.50)
        low.clock(low.time + 0.3)
        for y in [0.149, 0.151, 0.148, 0.1495] { low.move(0.50, y, after: 0.03) }
        var parkedLow = Run(low, ahead)
        #expect(parkedLow.tickUntilQuiet(ahead).isEmpty && parkedLow.selections == [0],
              "a Forward list that opens just above the bottom zone ignores tremor into it")
    }

    @Test func aDeliberatePushFromNearTheEdgeStartsTheSteps() {
        let page = Page(back: 50)
        var push = Trace.opening(from: 0.30, toward: 1, y: 0.84)
        push.move(0.40)
        push.clock(push.time + 0.3)
        push.move(0.40, 0.88)
        var pushed = Run(push, page)
        #expect(pushed.steps.last?.clockDeadline != nil && !pushed.tickUntilQuiet(page, limit: 3).isEmpty
              && pushed.selections == [0, 1, 2, 3],
              "a deliberate push toward the edge starts the steps even from a list that opened near it")
    }

    @Test func tremorAcrossTheBoundaryDoesNotInterruptActiveStepping() {
        let page = Page(back: 50)
        var engaged = Trace.opening(from: 0.30, toward: 1)
        engaged.move(0.40)
        engaged.clock(engaged.time + 0.3)
        engaged.move(0.40, 0.86)
        var stepping = Run(engaged, page)
        _ = stepping.tickUntilQuiet(page, limit: 2)
        var hand = Trace()
        hand.x = 0.40; hand.y = 0.86; hand.time = stepping.steps.last?.clockDeadline ?? 0
        var stillStepping = true
        for y in [0.849, 0.84, 0.851, 0.83] {
            hand.move(0.40, y, after: 0.001)
            stepping.play(Array(hand.inputs.suffix(1)), page)
            stillStepping = stillStepping && stepping.steps.last?.clockDeadline != nil
        }
        let before = stepping.selections.count
        _ = stepping.tickUntilQuiet(page, limit: 2)
        #expect(stillStepping && stepping.selections.count == before + 2,
              "once stepping, tremor back across the zone's edge doesn't stop it")
    }

    @Test func movingThreePercentOutOfTheZoneStopsActiveStepping() {
        let page = Page(back: 50)
        var engaged = Trace.opening(from: 0.30, toward: 1)
        engaged.move(0.40)
        engaged.clock(engaged.time + 0.3)
        engaged.move(0.40, 0.86)
        var stepping = Run(engaged, page)
        _ = stepping.tickUntilQuiet(page, limit: 2)
        var hand = Trace()
        hand.x = 0.40; hand.y = 0.86; hand.time = stepping.steps.last?.clockDeadline ?? 0
        for y in [0.849, 0.84, 0.851, 0.83] {
            hand.move(0.40, y, after: 0.001)
            stepping.play(Array(hand.inputs.suffix(1)), page)
        }
        _ = stepping.tickUntilQuiet(page, limit: 2)
        hand.move(0.40, 0.81)
        stepping.play(Array(hand.inputs.suffix(1)), page)
        #expect(stepping.steps.last?.clockDeadline == nil, "moving 3% out of the zone stops it")
    }

    @Test func remaindersDoNotAppearBeforeTheListOpens() {
        var trace = Trace.opening(from: 0.30, toward: 1)
        trace.move(0.40)
        trace.clock(trace.time + 0.3)
        let opened = trace.inputs.count
        trace.move(0.40, 0.54)
        trace.move(0.40, 0.60)
        trace.move(0.40, 0.46)
        trace.move(0.40, 0.40)
        let run = Run(trace)
        #expect(!run.steps.prefix(opened).contains { $0.outputs.contains { if case .rowRemainder = $0 { true } else { false } } },
              "nothing reports a remainder before the list opens")
    }

    @Test func remaindersMeasureTravelTowardTheNextRowAndStopAtTheCurrentPage() {
        var trace = Trace.opening(from: 0.30, toward: 1)
        trace.move(0.40)
        trace.clock(trace.time + 0.3)
        trace.move(0.40, 0.54)
        trace.move(0.40, 0.60)
        trace.move(0.40, 0.46)
        trace.move(0.40, 0.40)
        let run = Run(trace)
        #expect(HistorySwipeRecognizerTestsSupport.near(run.remainders, [0.5, 0.25, 0]),
              "between rows the recognizer reports how far the fingers are toward the next row, and nothing past the current page")
    }

    @Test func aRowStepReportsItsSelectionBeforeTheRemainder() {
        var trace = Trace.opening(from: 0.30, toward: 1)
        trace.move(0.40)
        trace.clock(trace.time + 0.3)
        trace.move(0.40, 0.54)
        trace.move(0.40, 0.60)
        let stepped = trace.inputs.count - 1
        trace.move(0.40, 0.46)
        trace.move(0.40, 0.40)
        let run = Run(trace)
        let outputs = run.steps[stepped].outputs
        #expect(outputs.count == 3 && outputs[0] == .selection(1) && outputs[1] == .detent
              && { if case .rowRemainder = outputs[2] { true } else { false } }(),
              "a row step reports its selection first, then the remainder past it")
    }

    @Test func forwardRemaindersFollowDownwardMovementTowardNewerPages() {
        var forward = Trace.opening(from: 0.60, toward: -1)
        forward.move(0.50)
        forward.clock(forward.time + 0.3)
        forward.move(0.50, 0.46)
        #expect(HistorySwipeRecognizerTestsSupport.near(Run(forward).remainders, [0.5]), "a Forward list leans toward newer pages as the fingers move down")
    }

    @Test func anEdgeTickLandsSquarelyOnItsRow() {
        let page = Page(back: 50)
        var edge = Trace.opening(from: 0.30, toward: 1)
        edge.move(0.40)
        edge.clock(edge.time + 0.3)
        edge.move(0.40, 0.88)
        var climbing = Run(edge, page)
        let leaning = climbing.remainders.last ?? 0
        _ = climbing.tickUntilQuiet(page, limit: 1)
        #expect(abs(leaning - 0.75) < 1e-9 && climbing.remainders.last == 0, "an edge step lands squarely on its row")
    }

    @Test func aClosedListReportsNoRemainder() {
        var collapse = Trace.opening(from: 0.30, toward: 1)
        collapse.move(0.40)
        collapse.clock(collapse.time + 0.3)
        collapse.move(0.40, 0.54)
        let held = collapse.inputs.count
        collapse.move(0.36, 0.54)
        collapse.move(0.36, 0.58)
        let closed = Run(collapse)
        #expect(!closed.steps.dropFirst(held).contains { $0.outputs.contains { if case .rowRemainder = $0 { true } else { false } } },
              "a closed list reports no remainder")
    }

    @Test func theLastRowNeverLeansBeyondItsHistory() {
        var end = Trace.opening(from: 0.30, toward: 1)
        end.move(0.40)
        end.clock(end.time + 0.3)
        end.move(0.40, 0.59)
        let atEnd = end.inputs.count
        end.move(0.40, 0.63)
        let last = Run(end, Page(back: 1))
        let beyond = last.steps.dropFirst(atEnd).flatMap(\.outputs).compactMap { output -> Double? in
            if case let .rowRemainder(value) = output { value } else { nil }
        }
        #expect(last.recognizer.selection == 1 && beyond.allSatisfy { $0 <= 0 },
              "the last row leans toward nothing past the end of history")
    }
}
