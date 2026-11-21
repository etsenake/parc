import Foundation
import Testing
@testable import Parc
@testable import ParcCore

private typealias Effect = PeekCloseTransition.Effect

private struct Pad: HistorySwipeEnvironment {
    var swipesBetweenPages = true
    var allowsHistorySwipe = true
    var back = 0
    func historyEntries(toward direction: HistorySwipeDirection) -> Int { direction == .back ? back : 0 }
    func dismisses(toward direction: HistorySwipeDirection) -> Bool { back == 0 && direction == .back }
}

@MainActor private final class Peek {
    var transition = PeekCloseTransition()
    let confirmation = PeekDismissalConfirmation()
    var recognizer = HistorySwipeRecognizer()
    var pad = Pad()
    var visible = true
    var call = false
    var effects: [Effect] = []
    var closeRequests = 0
    var hangUp = false
    var time = 100.0
    var x = 0.3
    var y = 0.5

    func apply(_ list: [Effect]) {
        effects += list
        for effect in list where effect == .requestClose && !transition.holdForParent(visible: visible) { closeRequests += 1 }
    }

    func cancelled() {
        if !transition.holdForParent(visible: visible) { apply(transition.refused(visible: visible)) }
    }

    var reappeared: Bool { effects.contains(.reappear) }

    func requestDismiss(_ mechanism: PeekDismissalConfirmation.Dismissal) {
        guard transition.phase == .resting || transition.phase == .dragging else { return }
        if let reason = confirmation.request(mechanism, mediaInput: call, onExpiry: {}) {
            hangUp = reason == .mediaInput
            return
        }
        apply(transition.close(visible: visible, exit: mechanism == .swipe ? .slide : .fade))
    }

    func commit() {
        guard transition.phase == .dragging else { return }
        requestDismiss(.swipe)
        if transition.phase == .dragging { apply(transition.springBack()) }
    }

    func feed(_ input: HistorySwipeInput) {
        let step = recognizer.receive(input, in: pad)
        for output in step.outputs {
            switch output {
            case .beginDismissal:
                let began = transition.beginDrag()
                #expect(began)
            case .commit(.dismiss):
                commit()
            default:
                apply(transition.drag(output))
            }
        }
    }

    var fingers: [HistorySwipePoint] { [HistorySwipePoint(x: x - 0.06, y: y), HistorySwipePoint(x: x + 0.06, y: y)] }

    func open() {
        feed(.touches(.began, fingers, time: time))
        feed(.scroll(HistorySwipeScroll(phase: .began, deltaX: 2, directionInverted: true)))
        feed(.pageScroll(.began(synthetic: false, momentum: false)))
        feed(.overscroll(propagatesX: true))
        feed(.pageScroll(.updated(consumed: false)))
        move(0.305)
        feed(.scroll(HistorySwipeScroll(phase: .changed, deltaX: 3, directionInverted: true)))
    }

    func move(_ to: Double, _ toY: Double? = nil, after delay: Double = 0.008) {
        time += delay
        x = to
        if let toY { y = toY }
        feed(.touches(.moved, fingers, time: time))
    }

    func lift(rested: Bool = true) {
        if rested { move(x + 0.0005, after: 0.2) }
        time += 0.008
        feed(.touches(.ended, fingers, time: time))
    }

    var haptics: Int { effects.filter { $0 == .haptic }.count }
    var follows: [Double] { effects.compactMap { if case let .follow(value) = $0 { value } else { nil } } }
    var lastExit: (PeekCloseTransition.Exit, Double, Double, Int)? {
        for effect in effects.reversed() {
            if case let .exit(kind, from, velocity, generation) = effect { return (kind, from, velocity, generation) }
        }
        return nil
    }
}


private func near(_ a: Double, _ b: Double, _ tolerance: Double = 1e-6) -> Bool { abs(a - b) <= tolerance }

private func isSpringBack(_ effect: Effect?) -> Bool {
    if case .springBack? = effect { return true }
    return false
}

struct PeekSwipeDismissalTests {
    @MainActor private static func swiped() -> Peek {
        let peek = Peek()
        peek.open()
        for x in [0.36, 0.42, 0.47, 0.5] { peek.move(x) }
        peek.lift()
        return peek
    }

    @MainActor private static func exitedAndHandedOver() -> Peek {
        let peek = Peek()
        peek.open()
        for x in [0.42, 0.5] { peek.move(x) }
        peek.lift()
        peek.apply(peek.transition.exitFinished(peek.lastExit?.3 ?? 0))
        return peek
    }

    @MainActor @Test func theCardFollowsTheFingers() {
        let peek = Self.swiped()
        #expect(peek.follows.count >= 4)
        #expect(abs(peek.follows[3] - 2.0 / 3) < 1e-9)
    }

    @MainActor @Test func crossingHalfwayTapsOnce() {
        #expect(Self.swiped().haptics == 1)
    }

    @MainActor @Test func aSwipePastHalfwaySlidesOnFromWhereTheFingersLetGo() throws {
        let exit = try #require(Self.swiped().lastExit)
        #expect(exit.0 == .slide)
        #expect(abs(exit.1 - 2.0 / 3) < 0.01)
    }

    @MainActor @Test func thePageIsNotAskedToCloseUntilTheCardHasGone() {
        let peek = Self.swiped()
        #expect(peek.transition.phase == .exiting)
        #expect(peek.closeRequests == 0)
    }

    @MainActor @Test func onceTheCardHasSlidOffThePagesRealCloseIsRequested() throws {
        let peek = Self.swiped()
        let exit = try #require(peek.lastExit)
        peek.apply(peek.transition.exitFinished(exit.3))
        #expect(peek.closeRequests == 1)
        #expect(peek.transition.phase == .closing)
        #expect(peek.transition.cardHidden)
    }

    @MainActor @Test func aLateExitTimerNeverAsksTwice() throws {
        let peek = Self.swiped()
        let exit = try #require(peek.lastExit)
        peek.apply(peek.transition.exitFinished(exit.3))
        peek.apply(peek.transition.exitFinished(exit.3))
        #expect(peek.closeRequests == 1)
    }

    @MainActor @Test func aClosedPeekStaysInvisibleAsItIsRemoved() throws {
        let peek = Self.swiped()
        peek.apply(peek.transition.exitFinished(try #require(peek.lastExit).3))
        peek.apply(peek.transition.finish())
        #expect(peek.effects.last == .vanish)
        #expect(peek.transition.phase == .finished)
    }

    @MainActor @Test func whenThePageAsksLeaveSiteTheCardSpringsBackUnderTheQuestion() {
        let peek = Self.exitedAndHandedOver()
        peek.apply(peek.transition.sheetBegan(visible: true))
        #expect(peek.effects.last == .reappear)
        #expect(!peek.transition.cardHidden)
    }

    @MainActor @Test func choosingToStayLeavesTheCardInPlaceWithoutASecondSpring() {
        let peek = Self.exitedAndHandedOver()
        peek.apply(peek.transition.sheetBegan(visible: true))
        peek.apply(peek.transition.refused(visible: true))
        #expect(peek.effects.last == .reappear)
        #expect(peek.transition.phase == .resting)
    }

    @MainActor @Test func thePeekCanBeSwipedAgainAfterStaying() {
        let peek = Self.exitedAndHandedOver()
        peek.apply(peek.transition.sheetBegan(visible: true))
        peek.apply(peek.transition.refused(visible: true))
        let began = peek.transition.beginDrag()
        #expect(began)
    }

    @MainActor private static func refusedWithoutAsking() -> Peek {
        let peek = Peek()
        peek.open()
        peek.move(0.5)
        peek.lift()
        peek.apply(peek.transition.exitFinished(peek.lastExit?.3 ?? 0))
        peek.apply(peek.transition.refused(visible: true))
        return peek
    }

    @MainActor @Test func aPageThatRefusesWithoutAskingBringsTheCardBack() {
        let peek = Self.refusedWithoutAsking()
        #expect(peek.effects.last == .reappear)
        #expect(peek.transition.phase == .resting)
    }

    @MainActor @Test func aSecondRefusalIsIgnored() {
        let peek = Self.refusedWithoutAsking()
        peek.apply(peek.transition.refused(visible: true))
        #expect(peek.effects.filter { $0 == .reappear }.count == 1)
    }

    @MainActor private static func swipe(_ peek: Peek) {
        peek.x = 0.3
        peek.recognizer = HistorySwipeRecognizer()
        peek.open()
        peek.move(0.5)
        peek.lift()
    }

    @MainActor private static func duringACall() -> Peek {
        let peek = Peek()
        peek.call = true
        peek.open()
        for x in [0.42, 0.5] { peek.move(x) }
        peek.lift()
        return peek
    }

    @MainActor @Test func duringACallASwipePastHalfwayShowsHangUpInsteadOfClosing() {
        let peek = Self.duringACall()
        #expect(peek.hangUp)
        #expect(peek.closeRequests == 0)
        #expect(peek.lastExit == nil)
        peek.confirmation.cancel()
    }

    @MainActor @Test func theCardSpringsBackBesideTheRedHangUp() {
        let peek = Self.duringACall()
        #expect(isSpringBack(peek.effects.last))
        #expect(peek.transition.phase == .resting)
        peek.confirmation.cancel()
    }

    @MainActor @Test func aSecondSwipeKeepsHangUpPendingAndStillNeverCloses() {
        let peek = Self.duringACall()
        Self.swipe(peek)
        #expect(peek.confirmation.attempts == 2)
        #expect(peek.closeRequests == 0)
        peek.confirmation.cancel()
    }

    @MainActor @Test func aSwipeAfterTheCallStoppedStillNeedsHangUp() {
        let peek = Self.duringACall()
        Self.swipe(peek)
        peek.call = false
        Self.swipe(peek)
        #expect(peek.closeRequests == 0)
        #expect(peek.confirmation.reason == .mediaInput)
        peek.confirmation.cancel()
    }

    @MainActor @Test func lettingGoBeforeHalfwaySpringsTheCardBack() {
        let peek = Peek()
        peek.open()
        peek.move(0.42)
        peek.lift()
        #expect(peek.lastExit == nil)
        #expect(isSpringBack(peek.effects.last))
    }

    @MainActor @Test func aSwipeThatNeverReachedHalfwayNeverTaps() {
        let peek = Peek()
        peek.open()
        peek.move(0.42)
        peek.lift()
        #expect(peek.haptics == 0)
    }

    @MainActor @Test func aFlickSlidesOffAtItsOwnSpeedWithoutATap() throws {
        let peek = Peek()
        peek.open()
        peek.move(0.31)
        peek.move(0.34, after: 0.01)
        peek.lift(rested: false)
        let exit = try #require(peek.lastExit)
        #expect(exit.0 == .slide)
        #expect(exit.2 > 2)
        #expect(peek.haptics == 0)
    }

    @MainActor @Test func pullingBackStaysSilentAndSpringsBack() {
        let peek = Peek()
        peek.open()
        for x in [0.4, 0.47, 0.43, 0.38] { peek.move(x) }
        peek.lift()
        #expect(peek.haptics == 1)
        #expect(peek.lastExit == nil)
    }

    @MainActor @Test func driftingUpOrDownSpringsTheCardBack() {
        let peek = Peek()
        peek.open()
        peek.move(0.36)
        peek.move(0.37, 0.56)
        peek.move(0.5, 0.56)
        peek.lift()
        #expect(peek.lastExit == nil)
        #expect(peek.transition.phase == .resting)
        #expect(peek.effects.contains { isSpringBack($0) })
    }

    private static func midExit() -> PeekCloseTransition {
        var transition = PeekCloseTransition()
        _ = transition.beginDrag()
        _ = transition.drag(.progress(HistorySwipeProgress(fraction: 0.6, stretch: 0.6)))
        _ = transition.close(visible: true, exit: .slide)
        return transition
    }

    @Test func switchingTabsMidExitHidesTheCardAtOnceAndClosesThePageWithoutWaiting() {
        var transition = Self.midExit()
        #expect(transition.hide() == [.vanish, .requestClose])
        #expect(transition.cardHidden)
    }

    @Test func theOldExitTimerCannotActAfterTheTabSwitch() {
        var transition = Self.midExit()
        _ = transition.hide()
        #expect(transition.exitFinished(1).isEmpty)
    }

    @Test func aPageThatRefusesWhileItsTabIsHiddenIsPutBackAtRest() {
        var transition = Self.midExit()
        _ = transition.hide()
        #expect(transition.refused(visible: false) == [.settle])
        #expect(transition.phase == .resting)
    }

    @Test func aLaterSheetNeverRevivesARestingCard() {
        var transition = Self.midExit()
        _ = transition.hide()
        _ = transition.refused(visible: false)
        #expect(transition.sheetBegan(visible: true).isEmpty)
    }

    @Test func escapeAClickOutsideOrCloseFadeTheCardInPlace() {
        var transition = PeekCloseTransition()
        #expect(transition.close(visible: true, exit: .fade) == [.exit(.fade, from: 0, velocity: 0, generation: 1)])
    }

    @Test func aClosingPeekCannotBeGrabbed() {
        var transition = PeekCloseTransition()
        _ = transition.close(visible: true, exit: .fade)
        #expect(transition.beginDrag() == false)
    }

    @Test func aSecondCloseIsIgnored() {
        var transition = PeekCloseTransition()
        _ = transition.close(visible: true, exit: .fade)
        #expect(transition.close(visible: true, exit: .fade).isEmpty)
    }

    @Test func theFadesEndAsksThePageToClose() {
        var transition = PeekCloseTransition()
        _ = transition.close(visible: true, exit: .fade)
        #expect(transition.exitFinished(1) == [.requestClose])
    }

    @Test func aSheetInAHiddenTabDoesNotShowTheCard() {
        var transition = PeekCloseTransition()
        _ = transition.close(visible: true, exit: .fade)
        _ = transition.exitFinished(1)
        #expect(transition.sheetBegan(visible: false).isEmpty)
    }

    @Test func removingAFadedPeekKeepsItInvisibleAndFinishingTwiceDoesNothing() {
        var transition = PeekCloseTransition()
        _ = transition.close(visible: true, exit: .fade)
        _ = transition.exitFinished(1)
        #expect(transition.finish() == [.vanish])
        #expect(transition.finish().isEmpty)
    }

    @Test func aHiddenPeekClosesStraightAway() {
        var transition = PeekCloseTransition()
        #expect(transition.close(visible: false, exit: .fade) == [.requestClose])
        #expect(!transition.cardHidden)
    }

    @Test func aHiddenPeekThatRefusesIsUntouched() {
        var transition = PeekCloseTransition()
        _ = transition.close(visible: false, exit: .fade)
        #expect(transition.refused(visible: false).isEmpty)
        #expect(transition.phase == .resting)
    }

    @Test func hidingMidDragDropsTheCardBack() {
        var transition = PeekCloseTransition()
        _ = transition.beginDrag()
        #expect(transition.hide() == [.settle])
        #expect(transition.phase == .resting)
    }

    @Test func aPeekRemovedMidDragLeavesNothingBehind() {
        var transition = PeekCloseTransition()
        _ = transition.beginDrag()
        _ = transition.drag(.progress(HistorySwipeProgress(fraction: 0.4, stretch: 0.4)))
        #expect(transition.finish() == [.vanish])
    }

    @Test func anExitTimerFromAnEarlierCloseCannotFinishANewerOne() {
        var first = PeekCloseTransition()
        _ = first.close(visible: true, exit: .slide)
        let generation = first.generation
        _ = first.hide()
        _ = first.refused(visible: true)
        _ = first.close(visible: true, exit: .fade)
        #expect(first.generation == generation + 1)
        #expect(first.exitFinished(generation).isEmpty)
    }

    @Test func theNewerExitFinishesNormally() {
        var first = PeekCloseTransition()
        _ = first.close(visible: true, exit: .slide)
        _ = first.hide()
        _ = first.refused(visible: true)
        _ = first.close(visible: true, exit: .fade)
        #expect(first.exitFinished(first.generation) == [.requestClose])
    }

    @Test func aRestingPeekKeepsTheKeyboard() {
        #expect(!PeekCloseTransition().isLeaving)
    }

    @Test func draggingTheCardDoesNotMoveTheKeyboard() {
        var transition = PeekCloseTransition()
        _ = transition.beginDrag()
        _ = transition.drag(.progress(HistorySwipeProgress(fraction: 0.6, stretch: 0.6)))
        #expect(!transition.isLeaving)
    }

    @Test func theMomentTheSlideStartsTypingBelongsToTheParentPage() {
        var transition = Self.midExit()
        #expect(transition.isLeaving)
        _ = transition.exitFinished(transition.generation)
        #expect(transition.isLeaving)
    }

    @Test func leaveSiteBringsTheCardBackSoThePeekTakesTheKeyboardBackForItsAnswer() {
        var transition = Self.midExit()
        _ = transition.exitFinished(transition.generation)
        _ = transition.sheetBegan(visible: true)
        #expect(!transition.isLeaving)
        _ = transition.refused(visible: true)
        #expect(!transition.isLeaving)
        #expect(transition.phase == .resting)
    }

    @Test func aFadeHandsTheKeyboardOverAsItStartsAndARefusalReturnsIt() {
        var transition = PeekCloseTransition()
        _ = transition.close(visible: true, exit: .fade)
        #expect(transition.isLeaving)
        _ = transition.exitFinished(transition.generation)
        _ = transition.refused(visible: true)
        #expect(!transition.isLeaving)
    }

    @Test func aPeekHiddenMidFadeNeverTakesTheKeyboardBackOnItsWayOut() {
        var transition = PeekCloseTransition()
        _ = transition.close(visible: true, exit: .fade)
        _ = transition.hide()
        #expect(transition.isLeaving)
        _ = transition.finish()
        #expect(!transition.isLeaving)
    }

    @Test func aPeekClosedInTheBackgroundHasNoKeyboardToHandOver() {
        var hidden = PeekCloseTransition()
        _ = hidden.close(visible: false, exit: .fade)
        #expect(!hidden.isLeaving)
    }

    @MainActor private static func closingParent(_ mechanism: PeekDismissalConfirmation.Dismissal = .closeButton) -> Peek {
        let peek = Peek()
        peek.requestDismiss(mechanism)
        peek.apply(peek.transition.parentClosingChanged(true))
        peek.apply(peek.transition.exitFinished(peek.transition.generation))
        return peek
    }

    @MainActor @Test func whenTheParentTabStartsClosingMidFadeThePeekLeavesItsCloseToTheTabs() {
        let peek = Self.closingParent()
        #expect(peek.closeRequests == 0)
        #expect(peek.transition.waitsForParent)
        #expect(peek.transition.cardHidden)
    }

    @MainActor @Test func theCardStaysGoneWhileTheTabCloses() {
        let peek = Self.closingParent()
        #expect(!peek.reappeared)
        #expect(peek.transition.isLeaving)
    }

    @MainActor @Test func thePeekGoesWithItsTabWithNoReturnFlashAndNoSecondClose() {
        let peek = Self.closingParent()
        peek.apply(peek.transition.finish())
        #expect(peek.effects.last == .vanish)
        #expect(peek.closeRequests == 0)
        #expect(!peek.reappeared)
    }

    @MainActor private static func takenOver() -> Peek {
        let peek = Peek()
        peek.requestDismiss(.escape(prefersConfirmation: false))
        peek.apply(peek.transition.exitFinished(peek.transition.generation))
        peek.apply(peek.transition.parentClosingChanged(true))
        peek.cancelled()
        return peek
    }

    @MainActor @Test func aTabCloseThatTookOverWaitsInsteadOfSpringingTheCardBack() {
        let peek = Self.takenOver()
        #expect(peek.closeRequests == 1)
        #expect(!peek.reappeared)
        #expect(peek.transition.waitsForParent)
        #expect(peek.transition.phase == .closing)
    }

    @MainActor @Test func ifTheTabStaysOpenTheOwnCloseCarriesOnStillInvisible() {
        let peek = Self.takenOver()
        let resumed = peek.transition.parentClosingChanged(false)
        #expect(resumed == [.requestClose])
        peek.apply(resumed)
        #expect(peek.closeRequests == 2)
        #expect(peek.transition.cardHidden)
        #expect(!peek.reappeared)
    }

    @MainActor @Test func repeatedOrNewerTabNoticesCannotAskAgainWhileThatCloseIsOut() {
        let peek = Self.takenOver()
        peek.apply(peek.transition.parentClosingChanged(false))
        #expect(peek.transition.parentClosingChanged(false).isEmpty)
        #expect(peek.transition.parentClosingChanged(true).isEmpty)
    }

    @MainActor private static func leaveSiteFromTabClose() -> Peek {
        let peek = Peek()
        peek.requestDismiss(.background)
        peek.apply(peek.transition.parentClosingChanged(true))
        peek.apply(peek.transition.exitFinished(peek.transition.generation))
        peek.apply(peek.transition.sheetBegan(visible: true))
        return peek
    }

    @MainActor @Test func aLeaveSiteFromTheTabsCloseLeavesTheHandedOverCardGone() {
        let peek = Self.leaveSiteFromTabClose()
        #expect(!peek.reappeared)
        #expect(peek.transition.cardHidden)
        #expect(peek.closeRequests == 0)
    }

    @MainActor @Test func ifTheTabThenStaysOpenThePeeksCloseCountsAsRefused() {
        let peek = Self.leaveSiteFromTabClose()
        #expect(peek.transition.parentClosingChanged(false) == [.cancelClose])
    }

    @MainActor @Test func choosingStayBringsTheCardBackOnce() {
        let peek = Self.leaveSiteFromTabClose()
        _ = peek.transition.parentClosingChanged(false)
        peek.apply(peek.transition.refused(visible: true))
        #expect(peek.transition.phase == .resting)
        #expect(!peek.transition.cardHidden)
        #expect(peek.effects.filter { $0 == .reappear }.count == 1)
        let began = peek.transition.beginDrag()
        #expect(began)
    }

    @MainActor @Test func aQuestionAskedWhileTheCardWasStillFadingAlsoCounts() {
        let peek = Peek()
        peek.requestDismiss(.closeButton)
        peek.apply(peek.transition.sheetBegan(visible: true))
        peek.apply(peek.transition.parentClosingChanged(true))
        peek.apply(peek.transition.exitFinished(peek.transition.generation))
        #expect(!peek.reappeared)
        #expect(peek.transition.parentClosingChanged(false) == [.cancelClose])
        peek.apply(peek.transition.refused(visible: true))
        #expect(peek.effects.last == .reappear)
        #expect(peek.transition.phase == .resting)
    }

    @Test func aHiddenPeekClosedWhileItsTabIsClosingWaitsToo() {
        var transition = PeekCloseTransition()
        _ = transition.parentClosingChanged(true)
        #expect(transition.close(visible: false, exit: .fade) == [.requestClose])
        let held1 = transition.holdForParent(visible: false)
        #expect(held1)
    }

    @Test func hidingAWaitingPeekChangesNothingAndItClosesOnceTheTabIsDone() {
        var transition = PeekCloseTransition()
        _ = transition.parentClosingChanged(true)
        _ = transition.close(visible: false, exit: .fade)
        _ = transition.holdForParent(visible: false)
        #expect(transition.hide().isEmpty)
        #expect(transition.waitsForParent)
        #expect(transition.parentClosingChanged(false) == [.requestClose])
        #expect(!transition.waitsForParent)
        let held2 = transition.holdForParent(visible: true)
        #expect(!held2)
    }

    @Test func aRestingPeekHasNothingToHoldOrResume() {
        var transition = PeekCloseTransition()
        _ = transition.parentClosingChanged(true)
        let held3 = transition.holdForParent(visible: true)
        #expect(!held3)
        #expect(transition.parentClosingChanged(false).isEmpty)
    }

    @Test func aCardStillFadingIsNotHeldAndTheFadesEndDecides() {
        var transition = PeekCloseTransition()
        _ = transition.close(visible: true, exit: .fade)
        _ = transition.parentClosingChanged(true)
        let held4 = transition.holdForParent(visible: true)
        #expect(!held4)
        #expect(transition.parentClosingChanged(false).isEmpty)
        #expect(transition.exitFinished(transition.generation) == [.requestClose])
        let held5 = transition.holdForParent(visible: true)
        #expect(!held5)
    }

    @MainActor @Test func theWaitingPeekIsStillWaitingSoOrphanPromotionCanTakeIt() {
        let peek = Self.closingParent()
        #expect(peek.transition.waitsForParent)
        #expect(peek.closeRequests == 0)
        #expect(peek.transition.phase == .closing)
    }

    @MainActor @Test func aWaitingPeekPromotedToItsOwnTabRetiresItsCardCleanly() {
        let peek = Self.closingParent()
        peek.apply(peek.transition.finish())
        #expect(peek.effects.last == .vanish)
        #expect(!peek.transition.waitsForParent)
        #expect(peek.transition.phase == .finished)
    }

    @MainActor @Test func theTabsLateAllClearCannotCloseOrReviveAPromotedPeek() {
        let peek = Self.closingParent()
        peek.apply(peek.transition.finish())
        #expect(peek.transition.parentClosingChanged(false).isEmpty)
        #expect(peek.closeRequests == 0)
        #expect(!peek.reappeared)
    }

    @Test func aPeekWhoseTabCloseEndedByEitherRouteCarriesOnAsSoonAsItHearsTheAllClear() {
        var transition = PeekCloseTransition()
        _ = transition.close(visible: true, exit: .fade)
        _ = transition.parentClosingChanged(true)
        _ = transition.exitFinished(transition.generation)
        _ = transition.holdForParent(visible: true)
        #expect(transition.parentClosingChanged(false) == [.requestClose])
    }

    @Test func aSecondTabCloseStartingBeforeTheRequestIsSentOnlyHoldsItAgainWhenTheRequestIsMade() {
        var transition = PeekCloseTransition()
        _ = transition.close(visible: true, exit: .fade)
        _ = transition.parentClosingChanged(true)
        _ = transition.exitFinished(transition.generation)
        _ = transition.holdForParent(visible: true)
        _ = transition.parentClosingChanged(false)
        #expect(transition.parentClosingChanged(true).isEmpty)
        #expect(!transition.waitsForParent)
        let held6 = transition.holdForParent(visible: true)
        #expect(held6)
        #expect(transition.parentClosingChanged(false) == [.requestClose])
    }

    @Test func aRefusalThatStillArrivesClearsTheWaitSoALaterTabNoticeCannotCloseThePeek() {
        var transition = PeekCloseTransition()
        _ = transition.close(visible: true, exit: .slide)
        _ = transition.parentClosingChanged(true)
        _ = transition.exitFinished(transition.generation)
        let held7 = transition.holdForParent(visible: true)
        #expect(held7)
        #expect(transition.refused(visible: true) == [.reappear])
        #expect(!transition.waitsForParent)
        #expect(transition.parentClosingChanged(false).isEmpty)
    }

    @MainActor private static func closedByPage() -> Peek {
        let peek = Peek()
        peek.requestDismiss(.closeButton)
        peek.apply(peek.transition.exitFinished(peek.transition.generation))
        return peek
    }

    @MainActor @Test func theFadesEndHasAlreadyAskedThePageToClose() {
        let peek = Self.closedByPage()
        #expect(peek.closeRequests == 1)
        #expect(peek.transition.cardHidden)
    }

    @MainActor @Test func aLeaveSiteFromTheClosingWindowKeepsTheFadedCardGoneWhileTheOwnCloseIsOut() {
        let peek = Self.closedByPage()
        peek.apply(peek.transition.parentClosingChanged(true))
        peek.apply(peek.transition.sheetBegan(visible: true))
        #expect(!peek.reappeared)
        #expect(peek.transition.cardHidden)
        #expect(peek.transition.isLeaving)
    }

    @MainActor @Test func anUnansweredCloseWaitsForTheWindowAndTheCardGoesWithItWithNoFlash() {
        let peek = Self.closedByPage()
        peek.apply(peek.transition.parentClosingChanged(true))
        peek.apply(peek.transition.sheetBegan(visible: true))
        peek.cancelled()
        #expect(peek.transition.waitsForParent)
        #expect(!peek.reappeared)
        peek.apply(peek.transition.finish())
        #expect(peek.effects.last == .vanish)
        #expect(peek.closeRequests == 1)
    }

    @MainActor @Test func withoutAClosingWindowOrTabThePagesLeaveSiteBringsTheCardBackWithTheKeyboard() {
        let peek = Self.closedByPage()
        peek.apply(peek.transition.sheetBegan(visible: true))
        #expect(peek.reappeared)
        #expect(!peek.transition.isLeaving)
    }

    @MainActor @Test func aWindowCloseRefusedAfterAQuestionCountsAsThePeeksRefusalTooAndTheCardReturnsOnce() {
        let peek = Peek()
        peek.requestDismiss(.escape(prefersConfirmation: false))
        peek.apply(peek.transition.parentClosingChanged(true))
        peek.apply(peek.transition.exitFinished(peek.transition.generation))
        peek.apply(peek.transition.sheetBegan(visible: true))
        #expect(peek.transition.parentClosingChanged(false) == [.cancelClose])
        peek.apply(peek.transition.refused(visible: true))
        #expect(peek.effects.filter { $0 == .reappear }.count == 1)
        #expect(peek.transition.phase == .resting)
    }

    @MainActor @Test func aWindowCloseRefusedWithoutAskingLetsThePeeksOwnCloseCarryOn() {
        let peek = Self.closingParent(.background)
        let resumed = peek.transition.parentClosingChanged(false)
        #expect(resumed == [.requestClose])
        peek.apply(resumed)
        #expect(peek.closeRequests == 1)
        #expect(!peek.reappeared)
    }

    @MainActor @Test func choosingStayWhileTheTabStartsClosingSettlesTheCloseAtOnce() {
        let peek = Self.closedByPage()
        peek.apply(peek.transition.sheetBegan(visible: true))
        #expect(peek.reappeared)
        peek.apply(peek.transition.parentClosingChanged(true))
        peek.cancelled()
        #expect(!peek.transition.waitsForParent)
        #expect(peek.transition.phase == .resting)
        #expect(!peek.transition.cardHidden)
    }

    @MainActor @Test func theTabsCloseEndingAfterwardsNeitherAsksAgainNorTouchesTheCard() {
        let peek = Self.closedByPage()
        peek.apply(peek.transition.sheetBegan(visible: true))
        peek.apply(peek.transition.parentClosingChanged(true))
        peek.cancelled()
        #expect(peek.transition.parentClosingChanged(false).isEmpty)
        #expect(peek.closeRequests == 1)
        #expect(peek.transition.close(visible: true, exit: .fade).count == 1)
    }

    @MainActor @Test func aPeekClosedInTheBackgroundAsksAtOnce() {
        let peek = Peek()
        peek.visible = false
        peek.requestDismiss(.closeButton)
        #expect(peek.closeRequests == 1)
        #expect(!peek.transition.cardHidden)
    }

    @MainActor @Test func aBackgroundPeekWhoseCloseComesBackWhileItsTabClosesStillWaits() {
        let peek = Peek()
        peek.visible = false
        peek.requestDismiss(.closeButton)
        peek.apply(peek.transition.parentClosingChanged(true))
        peek.cancelled()
        #expect(peek.transition.waitsForParent)
    }

    @MainActor private static func questionDuringWindowClose() -> Peek {
        let peek = Self.closedByPage()
        peek.apply(peek.transition.parentClosingChanged(true))
        peek.apply(peek.transition.sheetBegan(visible: true))
        return peek
    }

    @MainActor @Test func thePagesQuestionDuringTheWindowCloseLeavesTheCardGone() {
        #expect(!Self.questionDuringWindowClose().reappeared)
    }

    @MainActor @Test func aWindowCloseRefusedWhileThePagesQuestionIsStillUpResumesNothing() {
        let peek = Self.questionDuringWindowClose()
        #expect(peek.transition.parentClosingChanged(false).isEmpty)
        #expect(!peek.transition.waitsForParent)
    }

    @MainActor @Test func theCardThenComesBackUnderTheQuestionStillShowingWithTheKeyboard() {
        let peek = Self.questionDuringWindowClose()
        _ = peek.transition.parentClosingChanged(false)
        peek.apply(peek.transition.sheetBegan(visible: true))
        #expect(peek.effects.last == .reappear)
        #expect(!peek.transition.isLeaving)
    }

    @MainActor @Test func choosingStayAfterwardsSettlesItWithoutASecondReturn() {
        let peek = Self.questionDuringWindowClose()
        _ = peek.transition.parentClosingChanged(false)
        peek.apply(peek.transition.sheetBegan(visible: true))
        peek.cancelled()
        #expect(peek.transition.phase == .resting)
        #expect(peek.effects.filter { $0 == .reappear }.count == 1)
    }

    private static let geometry = PeekDismissalMotion.Geometry(paneWidth: 508, cardMinX: 53)

    @Test func theCardIsFullyOffOncePastThePanesRightEdgeAndItsShadow() {
        #expect(Self.geometry.exitDistance == 463)
        #expect(Self.geometry.paneWidth == 508)
    }

    @Test func theApprovedSpringSlideFadeAndReduceMotionTimings() {
        #expect(PeekDismissalTiming.springDamping == 0.86)
        #expect(PeekDismissalTiming.springResponse == 0.34)
        #expect(PeekDismissalTiming.slide == 0.22)
        #expect(PeekDismissalTiming.fade == 0.2)
        #expect(PeekDismissalTiming.reduced == 0.15)
    }

    private static func dragging() -> PeekDismissalMotion {
        var m = PeekDismissalMotion(geometry: geometry)
        m.begin(reducesMotion: false)
        return m
    }

    @Test func aNewCardRestsInPlaceFullyShown() {
        let m = PeekDismissalMotion(geometry: Self.geometry)
        #expect(m.frame(at: 0) == .rest)
        #expect(!m.isAnimating(at: 0))
    }

    @Test func theCardSlidesWithTheFingersAndTheWashFades() {
        var m = Self.dragging()
        m.follow(0.4)
        let drag = m.frame(at: 0)
        #expect(near(Double(drag.offset), 0.4 * 463))
        #expect(drag.card == 1)
        #expect(near(drag.wash, 0.6))
    }

    @Test func theCardStopsOnceItIsFullyOff() {
        var m = Self.dragging()
        m.follow(1.4)
        #expect(m.frame(at: 0).offset == 463)
        #expect(m.frame(at: 0).wash == 0)
    }

    @Test func pullingPastTheStartHoldsItAtRest() {
        var m = Self.dragging()
        m.follow(-0.2)
        #expect(m.frame(at: 0) == PeekDismissalFrame(offset: 0, card: 1, wash: 1))
    }

    private static func springingHome() -> PeekDismissalMotion {
        var m = dragging()
        m.follow(0.35)
        m.springBack(velocity: 0, at: 10)
        return m
    }

    @Test func theWashReturnsWithTheCard() {
        let m = Self.springingHome()
        for step in 1...60 {
            let frame = m.frame(at: 10 + Double(step) / 120)
            #expect(near(frame.wash, 1 - min(max(Double(frame.offset) / 463, 0), 1)))
        }
    }

    @Test func theSpringBringsTheCardHomeWithoutPassingItsRestingPlace() {
        let m = Self.springingHome()
        var lowest = CGFloat.infinity, previous = m.frame(at: 10).offset, monotonic = true
        for step in 1...60 {
            let frame = m.frame(at: 10 + Double(step) / 120)
            if frame.offset > previous + 1e-9 && frame.offset > 0 { monotonic = false }
            lowest = min(lowest, frame.offset)
            previous = frame.offset
        }
        #expect(monotonic)
        #expect(lowest == 0)
    }

    @Test func theSpringSettlesWithinASecond() {
        let m = Self.springingHome()
        #expect(!m.isAnimating(at: 11))
        #expect(m.frame(at: 11) == .rest)
    }

    @Test func aCardLetGoWhileStillMovingOutCarriesOnBrieflyBeforeReturning() {
        var flung = Self.dragging()
        flung.follow(0.3)
        flung.springBack(velocity: 2, at: 0)
        #expect(flung.frame(at: 0.02).offset > 0.3 * 463)
    }

    @Test func aHardFlickBackLandsTheCardAtRestNeverPastIt() {
        var thrown = Self.dragging()
        thrown.follow(0.5)
        thrown.springBack(velocity: -12, at: 0)
        var leftmost = CGFloat.infinity
        for step in 0...60 { leftmost = min(leftmost, thrown.frame(at: Double(step) / 120).offset) }
        #expect(leftmost == 0)
        #expect(thrown.frame(at: 2) == .rest)
    }

    private static func slidOut() -> (PeekDismissalMotion, Double) {
        var exit = dragging()
        exit.follow(0.62)
        let duration = exit.exit(.slide, velocity: 1.2, reducesMotion: false, at: 5)
        return (exit, duration)
    }

    @Test func theSlideMatchesTheApprovedMockupHalfwayThrough() {
        let (exit, duration) = Self.slidOut()
        let start = 0.62 * 463.0, travel = 1.2 * 463 * 0.22 / 2
        let middle = exit.frame(at: 5.11)
        #expect(duration == 0.22)
        #expect(near(Double(middle.offset), start + travel * 0.75, 1e-3))
        #expect(near(middle.card, 0.75))
        #expect(near(middle.wash, 0.38 * 0.25, 1e-9))
    }

    @Test func theSlideEndsFullyFadedWhereItStopped() {
        let (exit, _) = Self.slidOut()
        let start = 0.62 * 463.0, travel = 1.2 * 463 * 0.22 / 2
        let end = exit.frame(at: 5.2201)
        #expect(end.card == 0)
        #expect(end.wash == 0)
        #expect(near(Double(end.offset), start + travel, 1e-3))
        #expect(!exit.isAnimating(at: 5.2201))
    }

    @Test func settlingAFinishedSlideNeverBringsTheCardBackForAFrame() {
        var (exit, _) = Self.slidOut()
        exit.complete(at: 5.3)
        #expect(exit.frame(at: 6).card == 0)
    }

    @Test func aThreeFingerSwipeOrMagicMouseCloseStillSlidesAShortWayWhileItFades() {
        var still = PeekDismissalMotion(geometry: Self.geometry)
        _ = still.exit(.slide, velocity: 0, reducesMotion: false, at: 0)
        #expect(near(Double(still.frame(at: 0.22).offset), 0.12 * 508, 1e-6))
    }

    @Test func aVeryFastFlickTravelsAtMostHalfThePane() {
        var fast = PeekDismissalMotion(geometry: Self.geometry)
        _ = fast.exit(.slide, velocity: 20, reducesMotion: false, at: 0)
        #expect(near(Double(fast.frame(at: 0.22).offset), 0.5 * 508, 1e-6))
    }

    @Test func escapeAClickOutsideOrCloseFadeInPointTwoSeconds() {
        var fade = PeekDismissalMotion(geometry: Self.geometry)
        #expect(fade.exit(.fade, velocity: 3, reducesMotion: false, at: 0) == 0.2)
    }

    @Test func theQuickFadeDimsCardAndWashTogetherWithoutMoving() {
        var fade = PeekDismissalMotion(geometry: Self.geometry)
        _ = fade.exit(.fade, velocity: 3, reducesMotion: false, at: 0)
        #expect(fade.frame(at: 0.1).offset == 0)
        #expect(near(fade.frame(at: 0.1).card, 0.25))
        #expect(near(fade.frame(at: 0.1).wash, 0.25))
    }

    @Test func theQuickFadeEndsInvisible() {
        var fade = PeekDismissalMotion(geometry: Self.geometry)
        _ = fade.exit(.fade, velocity: 3, reducesMotion: false, at: 0)
        #expect(fade.frame(at: 0.2).card == 0)
        #expect(!fade.isAnimating(at: 0.2))
    }

    @Test func aRefusedFadeOutFadesBackInPlace() {
        var fade = PeekDismissalMotion(geometry: Self.geometry)
        _ = fade.exit(.fade, velocity: 3, reducesMotion: false, at: 0)
        fade.reappear(reducesMotion: false, at: 1)
        #expect(fade.frame(at: 1.1).offset == 0)
        #expect(fade.frame(at: 1.1).card > 0)
        #expect(fade.frame(at: 1.2) == .rest)
    }

    private static func vanished() -> (PeekDismissalMotion, PeekDismissalFrame) {
        var back = dragging()
        back.follow(0.64)
        _ = back.exit(.slide, velocity: 1.5, reducesMotion: false, at: 0)
        back.vanish(at: 0.22)
        return (back, back.frame(at: 0.22))
    }

    @Test func aVanishedCardStaysOffAndInvisible() {
        let (_, gone) = Self.vanished()
        #expect(gone.card == 0)
        #expect(gone.offset > 0.64 * 463)
    }

    @Test func aCardThePageRefusedToLoseSpringsBackInFadingUpAsItComes() {
        var (back, gone) = Self.vanished()
        back.reappear(reducesMotion: false, at: 1)
        let early = back.frame(at: 1.06), later = back.frame(at: 1.14)
        #expect(early.offset < gone.offset)
        #expect(early.card > 0 && early.card < 1)
        #expect(later.card > early.card)
        #expect(near(early.wash, early.card))
    }

    @Test func theSpringBackFromOffScreenSettlesAtRest() {
        var (back, _) = Self.vanished()
        back.reappear(reducesMotion: false, at: 1)
        #expect(back.frame(at: 2) == .rest)
        #expect(!back.isAnimating(at: 2))
    }

    private static func reduced() -> PeekDismissalMotion {
        var m = PeekDismissalMotion(geometry: geometry)
        m.begin(reducesMotion: true)
        m.follow(0.5)
        return m
    }

    @Test func withReduceMotionTheFingersFadeTheCardInPlaceInsteadOfSlidingIt() {
        #expect(Self.reduced().frame(at: 0) == PeekDismissalFrame(offset: 0, card: 0.65, wash: 0.5))
    }

    @Test func withReduceMotionLettingGoEarlyFadesBackInPointOneFiveSeconds() {
        var m = Self.reduced()
        m.springBack(velocity: 2, at: 0)
        #expect(m.frame(at: 0.075).offset == 0)
        #expect(m.frame(at: 0.075).card > 0.65)
        #expect(m.frame(at: 0.15) == .rest)
    }

    @Test func reduceMotionFadesOutInPointOneFiveSeconds() {
        var m = Self.reduced()
        m.follow(0.62)
        #expect(m.exit(.slide, velocity: 3, reducesMotion: true, at: 1) == 0.15)
    }

    @Test func nothingSlidesUnderReduceMotion() {
        var m = Self.reduced()
        m.follow(0.62)
        _ = m.exit(.slide, velocity: 3, reducesMotion: true, at: 1)
        var offsets = Set<CGFloat>()
        for step in 0...10 { offsets.insert(m.frame(at: 1 + Double(step) * 0.015).offset) }
        #expect(offsets == [0])
        #expect(m.frame(at: 1.1501).card == 0)
    }

    @Test func aRefusedCloseUnderReduceMotionFadesBackInPlace() {
        var m = Self.reduced()
        m.follow(0.62)
        _ = m.exit(.slide, velocity: 3, reducesMotion: true, at: 1)
        m.reappear(reducesMotion: true, at: 2)
        #expect(m.frame(at: 2.07).offset == 0)
        #expect(m.frame(at: 2.1501) == .rest)
    }

    @Test func settlingOtherMotionLeavesALiveDragUnderTheFingers() {
        var settled = Self.dragging()
        settled.follow(0.5)
        settled.complete(at: 0)
        #expect(settled.frame(at: 0).offset == 0.5 * 463)
    }

    @Test func settlingASpringPutsTheCardHomeAtOnce() {
        var settled = Self.dragging()
        settled.follow(0.5)
        settled.springBack(velocity: 0, at: 0)
        settled.complete(at: 0.01)
        #expect(settled.frame(at: 0.01) == .rest)
    }

    @Test func settlePutsTheCardBackAtRest() {
        var settled = Self.dragging()
        settled.follow(0.3)
        settled.settle()
        #expect(settled.frame(at: 0) == .rest)
        #expect(!settled.isFollowing)
    }
}
