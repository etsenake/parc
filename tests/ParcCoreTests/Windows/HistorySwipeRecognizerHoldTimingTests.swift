import Foundation
import Testing
@testable import ParcCore

struct HistorySwipeRecognizerHoldTimingTests {
    private typealias Page = HistorySwipeRecognizerTestsSupport.Page
    private typealias Trace = HistorySwipeRecognizerTestsSupport.Trace
    private typealias Run = HistorySwipeRecognizerTestsSupport.Run

    @Test func armingSchedulesTheListAfterTheFullHoldDelay() {
        var trace = Trace.opening(from: 0.30, toward: 1)
        trace.move(0.315)
        trace.move(0.40)
        let armedAt = trace.time
        let armedIndex = trace.inputs.count - 1
        trace.clock(armedAt + 0.29)
        trace.clock(armedAt + 0.3)
        let run = Run(trace)
        #expect(run.steps[armedIndex].clockDeadline == armedAt + 0.3, "arming schedules the hold after Dia's 0.3 s")
        #expect(run.steps[armedIndex + 1].outputs.isEmpty, "the list waits for the full delay")
    }

    @Test func movingFingersKeepTheListClosed() {
        let page = Page()
        var sliding = Trace.opening(from: 0.30, toward: 1)
        sliding.move(0.40)
        for x in [0.41, 0.42, 0.43, 0.44, 0.45] { sliding.move(x, after: 0.1) }
        let run = Run(sliding, page)
        #expect(!run.outputs.contains(.hold) && run.recognizer.state == .armed,
              "fingers still moving past the commit point keep the list closed though 0.5 s has passed since arming")
    }

    @Test func movementBeforeTheFirstWakeKeepsItsDeadline() {
        let page = Page()
        var sliding = Trace.opening(from: 0.30, toward: 1)
        sliding.move(0.40)
        let armedAt = sliding.time
        let armedIndex = sliding.inputs.count - 1
        for x in [0.41, 0.42, 0.43, 0.44, 0.45] { sliding.move(x, after: 0.1) }
        let run = Run(sliding, page)
        #expect(run.steps[armedIndex].clockDeadline == armedAt + 0.3
              && run.steps[(armedIndex + 1)...(armedIndex + 2)].allSatisfy { $0.clockDeadline == armedAt + 0.3 },
              "movements before the first wake keep its deadline, so the clock isn't rescheduled on every movement")
    }

    @Test func theListOpensAfterTheFingersRest() {
        let page = Page()
        var sliding = Trace.opening(from: 0.30, toward: 1)
        sliding.move(0.40)
        for x in [0.41, 0.42, 0.43, 0.44, 0.45] { sliding.move(x, after: 0.1) }
        let restAt = sliding.time
        var run = Run(sliding, page)
        let wakes = run.tickUntilQuiet(page)
        #expect(abs(wakes.last! - (restAt + 0.3)) < 1e-9 && run.steps.last?.outputs == [.hold, .selection(0)],
              "the list opens 0.3 s after the last movement, once the fingers rest past the commit point")
    }

    @Test func earlyWakesOnlyRescheduleTheHold() {
        let page = Page()
        var sliding = Trace.opening(from: 0.30, toward: 1)
        sliding.move(0.40)
        for x in [0.41, 0.42, 0.43, 0.44, 0.45] { sliding.move(x, after: 0.1) }
        var run = Run(sliding, page)
        let wakes = run.tickUntilQuiet(page)
        #expect(run.steps.suffix(wakes.count).dropLast().allSatisfy(\.outputs.isEmpty) && wakes == wakes.sorted(),
              "earlier wakes only reschedule the hold")
    }

    @Test func aMovementAfterArmingRestartsTheHoldDelay() {
        let page = Page()
        var settled = Trace.opening(from: 0.30, toward: 1)
        settled.move(0.40)
        settled.move(0.44, after: 0.2)
        let stillAt = settled.time
        settled.clock(stillAt + 0.29)
        settled.clock(stillAt + 0.3)
        let rested = Run(settled, page)
        #expect(rested.steps.dropLast().allSatisfy { !$0.outputs.contains(.hold) } && rested.steps.last?.outputs == [.hold, .selection(0)],
              "a movement 0.2 s after arming pushes the list to 0.3 s after that movement")
    }

    @Test func movingFartherPastCommitLeavesTheOpenListAlone() {
        let page = Page()
        var held = Trace.opening(from: 0.30, toward: 1)
        held.move(0.40)
        held.clock(held.time + 0.3)
        held.move(0.42, 0.5, after: 0.05)
        held.move(0.44, 0.5, after: 0.05)
        #expect(Run(held, page).gestures == [.begin(.back), .armed(true), .hold, .selection(0)],
              "once the list is open, moving past the commit point doesn't close or reopen it")
    }

    @Test func movementAfterRestCanOpenTheListBeforeTheClockFires() {
        var dwell = Trace.opening(from: 0.30, toward: 1)
        dwell.move(0.40)
        dwell.move(0.41, after: 0.6)
        #expect(Run(dwell).gestures == [.begin(.back), .armed(true), .hold, .selection(0)],
              "fingers that already rested for the delay open the list on their next movement without waiting for the clock")
    }

    @Test func disarmingRestartsTheDwell() {
        var reset = Trace.opening(from: 0.30, toward: 1)
        reset.move(0.40)
        let armedAt = reset.time
        reset.move(0.36, after: 0.2)
        reset.move(0.40, after: 0.1)
        reset.clock(armedAt + 0.45)
        reset.clock(armedAt + 0.65)
        let restarted = Run(reset)
        #expect(restarted.gestures == [.begin(.back), .armed(true), .armed(false), .armed(true), .hold, .selection(0)]
              && restarted.steps.last?.outputs == [.hold, .selection(0)], "disarming restarts the dwell")
    }

    @Test func liftingWithoutOpeningTheListCommitsTheAdjacentPage() {
        var lifted = Trace.opening(from: 0.30, toward: 1)
        lifted.move(0.40)
        lifted.time += 0.6
        lifted.lift()
        #expect(Run(lifted).gestures == [.begin(.back), .armed(true), .commit(.adjacent(.back))],
              "a lift never opens the list itself, so without it the swipe commits the adjacent page")
    }

    @Test func tremblingFingersKeepTheSwipeArmedWithoutOpeningTheList() {
        var tremor = Trace.opening(from: 0.30, toward: 1)
        tremor.move(0.39)
        let restAt = tremor.time
        for index in 0..<70 { tremor.move(0.39, index.isMultiple(of: 2) ? 0.501 : 0.5, after: 0.007) }
        tremor.clock(restAt + 0.5)
        let trembling = Run(tremor)
        #expect(trembling.gestures == [.begin(.back), .armed(true)] && trembling.recognizer.state == .armed,
              "resting fingers that tremble while the list waits never cancel, and each tremor restarts the wait")
    }

    @Test func theListOpensAfterTheTremblingStops() {
        var tremor = Trace.opening(from: 0.30, toward: 1)
        tremor.move(0.39)
        let restAt = tremor.time
        for index in 0..<70 { tremor.move(0.39, index.isMultiple(of: 2) ? 0.501 : 0.5, after: 0.007) }
        let stillAt = tremor.time
        tremor.clock(restAt + 0.5)
        tremor.clock(stillAt + 0.3)
        #expect(Run(tremor).gestures == [.begin(.back), .armed(true), .hold, .selection(0)],
              "the list opens 0.3 s after the trembling stops")
    }

    @Test func aVerticalSlideCancelsWhileWaitingForTheList() {
        var slide = Trace.opening(from: 0.30, toward: 1)
        slide.move(0.39)
        slide.move(0.39, 0.6, after: 0.1)
        #expect(Run(slide).gestures == [.begin(.back), .armed(true), .cancel],
              "a real vertical slide while the list waits still cancels")
    }
}
