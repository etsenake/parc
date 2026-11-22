import Foundation
import Testing
@testable import Parc
@testable import ParcCore

struct PeekSwipeDismissalTestsParentTab {
    private typealias Support = PeekSwipeDismissalTestsSupport

    private typealias Peek = Support.Peek

    @MainActor @Test func whenTheParentTabStartsClosingMidFadeThePeekLeavesItsCloseToTheTabs() {
        let peek = Support.closingParent()
        #expect(peek.closeRequests == 0)
        #expect(peek.transition.waitsForParent)
        #expect(peek.transition.cardHidden)
    }

    @MainActor @Test func theCardStaysGoneWhileTheTabCloses() {
        let peek = Support.closingParent()
        #expect(!peek.reappeared)
        #expect(peek.transition.isLeaving)
    }

    @MainActor @Test func thePeekGoesWithItsTabWithNoReturnFlashAndNoSecondClose() {
        let peek = Support.closingParent()
        peek.apply(peek.transition.finish())
        #expect(peek.effects.last == .vanish)
        #expect(peek.closeRequests == 0)
        #expect(!peek.reappeared)
    }

    @MainActor @Test func aTabCloseThatTookOverWaitsInsteadOfSpringingTheCardBack() {
        let peek = Support.takenOver()
        #expect(peek.closeRequests == 1)
        #expect(!peek.reappeared)
        #expect(peek.transition.waitsForParent)
        #expect(peek.transition.phase == .closing)
    }

    @MainActor @Test func ifTheTabStaysOpenTheOwnCloseCarriesOnStillInvisible() {
        let peek = Support.takenOver()
        let resumed = peek.transition.parentClosingChanged(false)
        #expect(resumed == [.requestClose])
        peek.apply(resumed)
        #expect(peek.closeRequests == 2)
        #expect(peek.transition.cardHidden)
        #expect(!peek.reappeared)
    }

    @MainActor @Test func repeatedOrNewerTabNoticesCannotAskAgainWhileThatCloseIsOut() {
        let peek = Support.takenOver()
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

    @MainActor @Test func aQuestionAskedWhileFadingDoesNotBringTheCardBackDuringTabClose() {
        let peek = Peek()
        peek.requestDismiss(.closeButton)
        peek.apply(peek.transition.sheetBegan(visible: true))
        peek.apply(peek.transition.parentClosingChanged(true))
        peek.apply(peek.transition.exitFinished(peek.transition.generation))
        #expect(!peek.reappeared)
    }

    @MainActor @Test func refusingTabCloseAfterAQuestionDuringFadeCancelsThePeeksClose() {
        let peek = Peek()
        peek.requestDismiss(.closeButton)
        peek.apply(peek.transition.sheetBegan(visible: true))
        peek.apply(peek.transition.parentClosingChanged(true))
        peek.apply(peek.transition.exitFinished(peek.transition.generation))
        #expect(peek.transition.parentClosingChanged(false) == [.cancelClose])
    }

    @MainActor @Test func theCardReturnsAfterAQuestionDuringFadeIsRefused() {
        let peek = Peek()
        peek.requestDismiss(.closeButton)
        peek.apply(peek.transition.sheetBegan(visible: true))
        peek.apply(peek.transition.parentClosingChanged(true))
        peek.apply(peek.transition.exitFinished(peek.transition.generation))
        _ = peek.transition.parentClosingChanged(false)
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

    @Test func hidingAWaitingPeekKeepsItWaiting() {
        var transition = PeekCloseTransition()
        _ = transition.parentClosingChanged(true)
        _ = transition.close(visible: false, exit: .fade)
        _ = transition.holdForParent(visible: false)
        #expect(transition.hide().isEmpty)
        #expect(transition.waitsForParent)
    }

    @Test func aHiddenPeekResumesClosingWhenTheTabIsDone() {
        var transition = PeekCloseTransition()
        _ = transition.parentClosingChanged(true)
        _ = transition.close(visible: false, exit: .fade)
        _ = transition.holdForParent(visible: false)
        _ = transition.hide()
        #expect(transition.parentClosingChanged(false) == [.requestClose])
        #expect(!transition.waitsForParent)
    }

    @Test func aResumedCloseDoesNotWaitForTheFinishedTabAgain() {
        var transition = PeekCloseTransition()
        _ = transition.parentClosingChanged(true)
        _ = transition.close(visible: false, exit: .fade)
        _ = transition.holdForParent(visible: false)
        _ = transition.hide()
        _ = transition.parentClosingChanged(false)
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

    @Test func aCardStillFadingDoesNotHoldTheClose() {
        var transition = PeekCloseTransition()
        _ = transition.close(visible: true, exit: .fade)
        _ = transition.parentClosingChanged(true)
        let held4 = transition.holdForParent(visible: true)
        #expect(!held4)
    }

    @Test func aTabThatStopsClosingDuringTheFadeHasNoRequestToResume() {
        var transition = PeekCloseTransition()
        _ = transition.close(visible: true, exit: .fade)
        _ = transition.parentClosingChanged(true)
        _ = transition.holdForParent(visible: true)
        #expect(transition.parentClosingChanged(false).isEmpty)
    }

    @Test func theFadesEndRequestsTheCloseAfterTheTabStopsClosing() {
        var transition = PeekCloseTransition()
        _ = transition.close(visible: true, exit: .fade)
        _ = transition.parentClosingChanged(true)
        _ = transition.holdForParent(visible: true)
        _ = transition.parentClosingChanged(false)
        #expect(transition.exitFinished(transition.generation) == [.requestClose])
    }

    @Test func aRequestAfterTheTabStopsClosingIsNotHeld() {
        var transition = PeekCloseTransition()
        _ = transition.close(visible: true, exit: .fade)
        _ = transition.parentClosingChanged(true)
        _ = transition.holdForParent(visible: true)
        _ = transition.parentClosingChanged(false)
        _ = transition.exitFinished(transition.generation)
        let held5 = transition.holdForParent(visible: true)
        #expect(!held5)
    }

    @MainActor @Test func theWaitingPeekIsStillWaitingSoOrphanPromotionCanTakeIt() {
        let peek = Support.closingParent()
        #expect(peek.transition.waitsForParent)
        #expect(peek.closeRequests == 0)
        #expect(peek.transition.phase == .closing)
    }

    @MainActor @Test func aWaitingPeekPromotedToItsOwnTabRetiresItsCardCleanly() {
        let peek = Support.closingParent()
        peek.apply(peek.transition.finish())
        #expect(peek.effects.last == .vanish)
        #expect(!peek.transition.waitsForParent)
        #expect(peek.transition.phase == .finished)
    }

    @MainActor @Test func theTabsLateAllClearCannotCloseOrReviveAPromotedPeek() {
        let peek = Support.closingParent()
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

    @Test func aSecondTabCloseDoesNotHoldAnUnsentCloseRequest() {
        var transition = PeekCloseTransition()
        _ = transition.close(visible: true, exit: .fade)
        _ = transition.parentClosingChanged(true)
        _ = transition.exitFinished(transition.generation)
        _ = transition.holdForParent(visible: true)
        _ = transition.parentClosingChanged(false)
        #expect(transition.parentClosingChanged(true).isEmpty)
        #expect(!transition.waitsForParent)
    }

    @Test func sendingACloseRequestDuringTheSecondTabCloseHoldsIt() {
        var transition = PeekCloseTransition()
        _ = transition.close(visible: true, exit: .fade)
        _ = transition.parentClosingChanged(true)
        _ = transition.exitFinished(transition.generation)
        _ = transition.holdForParent(visible: true)
        _ = transition.parentClosingChanged(false)
        _ = transition.parentClosingChanged(true)
        let held6 = transition.holdForParent(visible: true)
        #expect(held6)
    }

    @Test func finishingTheSecondTabCloseResumesTheHeldRequest() {
        var transition = PeekCloseTransition()
        _ = transition.close(visible: true, exit: .fade)
        _ = transition.parentClosingChanged(true)
        _ = transition.exitFinished(transition.generation)
        _ = transition.holdForParent(visible: true)
        _ = transition.parentClosingChanged(false)
        _ = transition.parentClosingChanged(true)
        _ = transition.holdForParent(visible: true)
        #expect(transition.parentClosingChanged(false) == [.requestClose])
    }

    @Test func aRefusedPeekCloseReturnsTheCardAndClearsTheWait() {
        var transition = PeekCloseTransition()
        _ = transition.close(visible: true, exit: .slide)
        _ = transition.parentClosingChanged(true)
        _ = transition.exitFinished(transition.generation)
        let held7 = transition.holdForParent(visible: true)
        #expect(held7)
        #expect(transition.refused(visible: true) == [.reappear])
        #expect(!transition.waitsForParent)
    }

    @Test func aTabNoticeAfterRefusalCannotCloseThePeek() {
        var transition = PeekCloseTransition()
        _ = transition.close(visible: true, exit: .slide)
        _ = transition.parentClosingChanged(true)
        _ = transition.exitFinished(transition.generation)
        _ = transition.holdForParent(visible: true)
        _ = transition.refused(visible: true)
        #expect(transition.parentClosingChanged(false).isEmpty)
    }
}
