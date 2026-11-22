import AppKit
import Testing
@testable import Parc
@testable import ParcKit

@MainActor
struct TooltipPresentationStateTests {
    typealias State = TooltipPresentationState<String>
    private static let t0 = Date(timeIntervalSinceReferenceDate: 1000)
    private static let t1 = t0.addingTimeInterval(1)
    private static let idle = TooltipConfiguration.Behavior.onMouseIdle(delay: 0.45)
    private static let commandS = KeyboardShortcut(key: "s", flags: .command)

    private func scheduled(_ target: String = "toggle", at time: Date? = nil) -> State {
        var state = State()
        _ = state.schedule(target, anchor: .bottomTrailing, behavior: Self.idle, now: time ?? Self.t0)
        return state
    }
    private func presented(_ target: String = "toggle") -> State {
        var state = scheduled(target)
        state.didPresent(target)
        return state
    }

    @Test func itStartsTrackingWithNoWindow() {
        let state = State()
        #expect(state.phase == .tracking && !state.isShowing && state.schedulesWhenPointerStops)
    }

    @Test func anIdleTooltipWaitsItsDelay() {
        var state = State()
        #expect(state.schedule("toggle", anchor: .bottomTrailing, behavior: Self.idle, now: Self.t0) == .presentAfter(0.45))
        #expect(state.phase == .scheduled("toggle") && !state.schedulesWhenPointerStops)
    }

    @Test func movementCancelsThePendingPresentation() {
        var state = scheduled()
        let cancelled = state.pointerMoved()
        #expect(cancelled)
        #expect(state.phase == .tracking)
        let again = state.pointerMoved()
        #expect(!again)
    }

    @Test func movementKeepsAPresentedTooltip() {
        var state = presented()
        #expect(state.phase == .presented("toggle") && state.isShowing)
        let moved = state.pointerMoved()
        #expect(!moved)
    }

    @Test func aWarmHandoffShowsAnotherViewsTooltipAtOnce() {
        var state = presented()
        #expect(state.schedule("back", anchor: .bottomTrailing, behavior: Self.idle, now: Self.t0) == .present)
    }

    @Test func aCursorTooltipIsNotScheduledWhileOneIsUp() {
        var state = presented("back")
        #expect(state.schedule("row", anchor: .cursor, behavior: .onMouseIdle(delay: 1.5), now: Self.t0) == nil)
        #expect(state.phase == .presented("back"))
    }

    @Test func hidingFadesTheWindowAndItStillShowsWhileFading() {
        var state = presented("back")
        #expect(state.hide(State.Fade(duration: 0.3), now: Self.t1) == State.Fade(duration: 0.3))
        #expect(state.phase == .tracking)
        #expect(state.isShowing && state.lastDismissal == Self.t1)
    }

    @Test func aWarmHandoffDuringTheFadeShowsAtOnce() {
        var state = presented("back")
        _ = state.hide(State.Fade(duration: 0.3), now: Self.t1)
        #expect(state.schedule("forward", anchor: .bottomTrailing, behavior: Self.idle, now: Self.t1) == .present)
    }

    @Test func aReplacedFadeLeavesTheWindowUp() {
        var state = presented("back")
        _ = state.hide(State.Fade(duration: 0.3), now: Self.t1)
        state.didPresent("forward")
        #expect(!state.fadeDidFinish() && state.isShowing)
    }

    @Test func anUnreplacedFadeClosesTheWindow() {
        var state = presented("forward")
        _ = state.hide(.init(duration: 0.3), now: Self.t1)
        #expect(state.fadeDidFinish() && !state.isShowing)
    }

    @Test func afterTheFadeTheDelayAppliesAgain() {
        var state = presented("forward")
        _ = state.hide(.init(duration: 0.3), now: Self.t1)
        _ = state.fadeDidFinish()
        #expect(state.schedule("toggle", anchor: .bottomTrailing, behavior: Self.idle, now: Self.t1) == .presentAfter(0.45))
    }

    @Test func nothingToHideLeavesNoDismissal() {
        var idle = State()
        #expect(idle.hide(.init(duration: 0.1), now: Self.t1) == nil && idle.lastDismissal == .distantPast)
    }

    @Test func hidingAPendingTooltipCancelsIt() {
        var idle = scheduled(at: Self.t1)
        #expect(idle.hide(.init(duration: 0.1), now: Self.t1) == nil)
        #expect(idle.phase == .tracking && idle.lastDismissal == Self.t1)
    }

    @Test func aScrollLeavesNoWarmState() {
        var idle = scheduled(at: Self.t1)
        _ = idle.hide(.init(duration: 0.1), scrolled: true, now: Self.t1)
        #expect(idle.lastDismissal == .distantPast)
    }

    private func dismissedCursor() -> State {
        var cursor = State()
        _ = cursor.schedule("row", anchor: .cursor, behavior: .onMouseIdle(delay: 1.5), now: Self.t0)
        _ = cursor.hide(.init(duration: 0.1), now: Self.t0)
        return cursor
    }

    @Test func aCursorTooltipWithinSixTenthsOfADismissalWaitsOneHundredth() {
        var cursor = dismissedCursor()
        #expect(cursor.schedule("row", anchor: .cursor, behavior: .onMouseIdle(delay: 1.5), now: Self.t0.addingTimeInterval(0.5)) == .presentAfter(0.01))
    }

    @Test func laterACursorTooltipWaitsItsOwnDelay() {
        var cursor = dismissedCursor()
        #expect(cursor.schedule("row", anchor: .cursor, behavior: .onMouseIdle(delay: 1.5), now: Self.t0.addingTimeInterval(0.7)) == .presentAfter(1.5))
    }

    @Test func anImmediateTooltipPresentsWithoutScheduling() {
        var immediate = State()
        #expect(immediate.schedule("info", anchor: .top, behavior: .immediate, now: Self.t0) == .present)
        #expect(immediate.phase == .tracking)
    }

    @Test func withNoTargetAnExitDoesNothing() {
        let exit = State()
        #expect(exit.exit(targetUnderPointer: false, enclosing: nil, enclosingAnchor: nil, anchor: .bottomTrailing) == .keep)
    }

    @Test func aTooltipStillOverItsViewIsKept() {
        let exit = presented("inner")
        #expect(exit.exit(targetUnderPointer: true, enclosing: nil, enclosingAnchor: nil, anchor: .bottomTrailing) == .keep)
    }

    @Test func anExitHandsOffToAnEnclosingViewAnchoredView() {
        let exit = presented("inner")
        #expect(exit.exit(targetUnderPointer: false, enclosing: "outer", enclosingAnchor: .bottomTrailing, anchor: .bottomTrailing) == .handOff("outer"))
    }

    @Test(arguments: [(TooltipConfiguration.Anchor.bottomTrailing, 0.3), (.cursor, 0.1)])
    func aViewTooltipFadesInThreeTenthsAndACursorTooltipInOneTenth(_ anchor: TooltipConfiguration.Anchor, _ duration: Double) {
        let exit = presented("inner")
        #expect(exit.exit(targetUnderPointer: false, enclosing: nil, enclosingAnchor: nil, anchor: anchor) == .hide(.init(duration: duration)))
    }

    @Test func aCursorAnchoredEnclosingViewIsNotHandedOffToWhileATooltipShows() {
        let row = presented("close")
        #expect(row.exit(targetUnderPointer: false, enclosing: "row", enclosingAnchor: .cursor, anchor: .bottomTrailing) == .hide(.init(duration: 0.3)))
    }

    @Test func thePillFadesAndThePointersNextStopMayScheduleAgain() {
        var row = presented("close")
        #expect(row.hide(.init(duration: 0.3), now: Self.t0) == .init(duration: 0.3))
        #expect(row.isShowing && row.schedulesWhenPointerStops)
    }

    @Test func duringTheFadeTheRowIsDeclined() {
        var row = presented("close")
        _ = row.hide(.init(duration: 0.3), now: Self.t0)
        #expect(row.schedule("row", anchor: .cursor, behavior: .onMouseIdle(delay: 1.5), now: Self.t0.addingTimeInterval(0.1)) == nil)
    }

    @Test func afterTheFadeTheNextStopSchedulesTheRowWithTheCursorWarmDelay() {
        var row = presented("close")
        _ = row.hide(.init(duration: 0.3), now: Self.t0)
        _ = row.schedule("row", anchor: .cursor, behavior: .onMouseIdle(delay: 1.5), now: Self.t0.addingTimeInterval(0.1))
        let closed = row.fadeDidFinish()
        #expect(closed)
        #expect(row.schedule("row", anchor: .cursor, behavior: .onMouseIdle(delay: 1.5), now: Self.t0.addingTimeInterval(0.35)) == .presentAfter(0.01))
        #expect(row.target == "row")
    }

    @Test func withNothingShownAPendingChildHandsOffToTheCursorAnchoredRow() {
        let pending = scheduled("close")
        #expect(pending.exit(targetUnderPointer: false, enclosing: "row", enclosingAnchor: .cursor, anchor: .bottomTrailing) == .handOff("row"))
    }

    @Test func otherKeysNeverDismiss() {
        var keys = State()
        keys.didPresent("toggle")
        #expect(keys.keyDown(escape: false, modifiers: .command, characters: "d", shortcut: Self.commandS, now: Self.t0) == nil)
    }

    @Test func aDifferentChordDoesNotDismiss() {
        var keys = State()
        keys.didPresent("toggle")
        #expect(keys.keyDown(escape: false, modifiers: [.command, .shift], characters: "s", shortcut: Self.commandS, now: Self.t0) == nil)
    }

    @Test func performingTheShownShortcutFadesAfterAQuarterSecond() {
        var keys = State()
        keys.didPresent("toggle")
        #expect(keys.keyDown(escape: false, modifiers: [.command, .capsLock], characters: "S", shortcut: Self.commandS, now: Self.t0)
                == State.Fade(duration: 0.3, delay: 0.25))
    }

    @Test func escapeFadesInOneTenth() {
        var keys = State()
        keys.didPresent("toggle")
        #expect(keys.keyDown(escape: true, modifiers: [], characters: nil, shortcut: Self.commandS, now: Self.t0) == State.Fade(duration: 0.1))
    }

    @Test func theShortcutOnlyDismissesAShownTooltip() {
        var pending = scheduled()
        #expect(pending.keyDown(escape: false, modifiers: .command, characters: "s", shortcut: Self.commandS, now: Self.t0) == nil)
        #expect(pending.isScheduled)
    }

    @Test func escapeCancelsAPendingOne() {
        var pending = scheduled()
        #expect(pending.keyDown(escape: true, modifiers: [], characters: nil, shortcut: nil, now: Self.t0) == nil)
        #expect(pending.phase == .tracking)
    }

    @Test func aFailedPresentationClosesTheWindow() {
        var failed = State()
        failed.didPresent("toggle")
        failed.didFailToPresent()
        #expect(failed.phase == .tracking && !failed.isShowing)
    }

    @Test func aPendingPresentationCanBeCancelled() {
        var failed = scheduled()
        failed.cancelSchedule()
        #expect(failed.phase == .tracking)
    }
}
