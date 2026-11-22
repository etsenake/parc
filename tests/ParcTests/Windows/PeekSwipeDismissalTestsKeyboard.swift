import Foundation
import Testing
@testable import Parc
@testable import ParcCore

struct PeekSwipeDismissalTestsKeyboard {
    @Test func aRestingPeekKeepsTheKeyboard() {
        #expect(!PeekCloseTransition().isLeaving)
    }

    @Test func draggingTheCardDoesNotMoveTheKeyboard() {
        var transition = PeekCloseTransition()
        _ = transition.beginDrag()
        _ = transition.drag(.progress(HistorySwipeProgress(fraction: 0.6, stretch: 0.6)))
        #expect(!transition.isLeaving)
    }

    @Test func theSlideHandsTypingToTheParentPageAsSoonAsItStarts() {
        let transition = PeekSwipeDismissalTestsSupport.midExit()
        #expect(transition.isLeaving)
    }

    @Test func theParentKeepsTypingAfterTheSlideFinishes() {
        var transition = PeekSwipeDismissalTestsSupport.midExit()
        _ = transition.exitFinished(transition.generation)
        #expect(transition.isLeaving)
    }

    @Test func thePeekTakesTheKeyboardBackForTheLeaveSiteAnswer() {
        var transition = PeekSwipeDismissalTestsSupport.midExit()
        _ = transition.exitFinished(transition.generation)
        _ = transition.sheetBegan(visible: true)
        #expect(!transition.isLeaving)
    }

    @Test func choosingStayKeepsTheKeyboardWithThePeek() {
        var transition = PeekSwipeDismissalTestsSupport.midExit()
        _ = transition.exitFinished(transition.generation)
        _ = transition.sheetBegan(visible: true)
        _ = transition.refused(visible: true)
        #expect(!transition.isLeaving)
        #expect(transition.phase == .resting)
    }

    @Test func aFadeHandsTheKeyboardOverAsItStarts() {
        var transition = PeekCloseTransition()
        _ = transition.close(visible: true, exit: .fade)
        #expect(transition.isLeaving)
    }

    @Test func aRefusedFadeReturnsTheKeyboard() {
        var transition = PeekCloseTransition()
        _ = transition.close(visible: true, exit: .fade)
        _ = transition.exitFinished(transition.generation)
        _ = transition.refused(visible: true)
        #expect(!transition.isLeaving)
    }

    @Test func aPeekHiddenMidFadeKeepsTheKeyboardWithTheParent() {
        var transition = PeekCloseTransition()
        _ = transition.close(visible: true, exit: .fade)
        _ = transition.hide()
        #expect(transition.isLeaving)
    }

    @Test func finishingAHiddenFadeClearsTheLeavingState() {
        var transition = PeekCloseTransition()
        _ = transition.close(visible: true, exit: .fade)
        _ = transition.hide()
        _ = transition.finish()
        #expect(!transition.isLeaving)
    }

    @Test func aPeekClosedInTheBackgroundHasNoKeyboardToHandOver() {
        var hidden = PeekCloseTransition()
        _ = hidden.close(visible: false, exit: .fade)
        #expect(!hidden.isLeaving)
    }
}
