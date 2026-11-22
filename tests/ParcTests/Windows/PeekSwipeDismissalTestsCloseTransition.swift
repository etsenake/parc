import Foundation
import Testing
@testable import Parc
@testable import ParcCore

struct PeekSwipeDismissalTestsCloseTransition {
    private typealias Support = PeekSwipeDismissalTestsSupport

    @Test func switchingTabsMidExitHidesTheCardAtOnceAndClosesThePageWithoutWaiting() {
        var transition = Support.midExit()
        #expect(transition.hide() == [.vanish, .requestClose])
        #expect(transition.cardHidden)
    }

    @Test func theOldExitTimerCannotActAfterTheTabSwitch() {
        var transition = Support.midExit()
        _ = transition.hide()
        #expect(transition.exitFinished(1).isEmpty)
    }

    @Test func aPageThatRefusesWhileItsTabIsHiddenIsPutBackAtRest() {
        var transition = Support.midExit()
        _ = transition.hide()
        #expect(transition.refused(visible: false) == [.settle])
        #expect(transition.phase == .resting)
    }

    @Test func aLaterSheetNeverRevivesARestingCard() {
        var transition = Support.midExit()
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

    @Test func removingAFadedPeekKeepsItInvisible() {
        var transition = PeekCloseTransition()
        _ = transition.close(visible: true, exit: .fade)
        _ = transition.exitFinished(1)
        #expect(transition.finish() == [.vanish])
    }

    @Test func finishingAFadedPeekTwiceDoesNothing() {
        var transition = PeekCloseTransition()
        _ = transition.close(visible: true, exit: .fade)
        _ = transition.exitFinished(1)
        _ = transition.finish()
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

    @Test func aNewCloseAdvancesTheExitGeneration() {
        var first = PeekCloseTransition()
        _ = first.close(visible: true, exit: .slide)
        let generation = first.generation
        _ = first.hide()
        _ = first.refused(visible: true)
        _ = first.close(visible: true, exit: .fade)
        #expect(first.generation == generation + 1)
    }

    @Test func anExitTimerFromAnEarlierCloseCannotFinishANewerOne() {
        var first = PeekCloseTransition()
        _ = first.close(visible: true, exit: .slide)
        let generation = first.generation
        _ = first.hide()
        _ = first.refused(visible: true)
        _ = first.close(visible: true, exit: .fade)
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
}
