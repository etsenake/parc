import Foundation
import Testing
@testable import Parc
@testable import ParcCore

struct PeekSwipeDismissalTestsParentWindow {
    private typealias Peek = PeekSwipeDismissalTestsSupport.Peek

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

    @MainActor @Test func anUnansweredCloseWaitsForTheWindow() {
        let peek = Self.closedByPage()
        peek.apply(peek.transition.parentClosingChanged(true))
        peek.apply(peek.transition.sheetBegan(visible: true))
        peek.cancelled()
        #expect(peek.transition.waitsForParent)
        #expect(!peek.reappeared)
    }

    @MainActor @Test func aWaitingPeeksCardGoesWithTheWindowWithoutAFlash() {
        let peek = Self.closedByPage()
        peek.apply(peek.transition.parentClosingChanged(true))
        peek.apply(peek.transition.sheetBegan(visible: true))
        peek.cancelled()
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

    @MainActor @Test func aWindowCloseRefusedAfterAQuestionCancelsThePeeksClose() {
        let peek = Peek()
        peek.requestDismiss(.escape(prefersConfirmation: false))
        peek.apply(peek.transition.parentClosingChanged(true))
        peek.apply(peek.transition.exitFinished(peek.transition.generation))
        peek.apply(peek.transition.sheetBegan(visible: true))
        #expect(peek.transition.parentClosingChanged(false) == [.cancelClose])
    }

    @MainActor @Test func theCardReturnsOnceAfterTheWindowCloseIsRefused() {
        let peek = Peek()
        peek.requestDismiss(.escape(prefersConfirmation: false))
        peek.apply(peek.transition.parentClosingChanged(true))
        peek.apply(peek.transition.exitFinished(peek.transition.generation))
        peek.apply(peek.transition.sheetBegan(visible: true))
        _ = peek.transition.parentClosingChanged(false)
        peek.apply(peek.transition.refused(visible: true))
        #expect(peek.effects.filter { $0 == .reappear }.count == 1)
        #expect(peek.transition.phase == .resting)
    }

    @MainActor @Test func aWindowCloseRefusedWithoutAskingLetsThePeeksOwnCloseCarryOn() {
        let peek = PeekSwipeDismissalTestsSupport.closingParent(.background)
        let resumed = peek.transition.parentClosingChanged(false)
        #expect(resumed == [.requestClose])
        peek.apply(resumed)
        #expect(peek.closeRequests == 1)
        #expect(!peek.reappeared)
    }

    @MainActor @Test func leaveSiteBringsTheCardBackBeforeTheTabStartsClosing() {
        let peek = Self.closedByPage()
        peek.apply(peek.transition.sheetBegan(visible: true))
        #expect(peek.reappeared)
    }

    @MainActor @Test func choosingStayWhileTheTabStartsClosingSettlesTheCloseAtOnce() {
        let peek = Self.closedByPage()
        peek.apply(peek.transition.sheetBegan(visible: true))
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
}
