import Foundation
import Testing
@testable import Parc
@testable import ParcCore

struct PeekSwipeDismissalTestsTrackpad {
    private typealias Support = PeekSwipeDismissalTestsSupport

    private typealias Peek = Support.Peek

    @MainActor @Test func theCardFollowsTheFingers() {
        let peek = Support.swiped()
        #expect(peek.follows.count >= 4)
        #expect(abs(peek.follows[3] - 2.0 / 3) < 1e-9)
    }

    @MainActor @Test func crossingHalfwayTapsOnce() {
        #expect(Support.swiped().haptics == 1)
    }

    @MainActor @Test func aSwipePastHalfwaySlidesOnFromWhereTheFingersLetGo() throws {
        let exit = try #require(Support.swiped().lastExit)
        #expect(exit.0 == .slide)
        #expect(abs(exit.1 - 2.0 / 3) < 0.01)
    }

    @MainActor @Test func thePageIsNotAskedToCloseUntilTheCardHasGone() {
        let peek = Support.swiped()
        #expect(peek.transition.phase == .exiting)
        #expect(peek.closeRequests == 0)
    }

    @MainActor @Test func onceTheCardHasSlidOffThePagesRealCloseIsRequested() throws {
        let peek = Support.swiped()
        let exit = try #require(peek.lastExit)
        peek.apply(peek.transition.exitFinished(exit.3))
        #expect(peek.closeRequests == 1)
        #expect(peek.transition.phase == .closing)
        #expect(peek.transition.cardHidden)
    }

    @MainActor @Test func aLateExitTimerNeverAsksTwice() throws {
        let peek = Support.swiped()
        let exit = try #require(peek.lastExit)
        peek.apply(peek.transition.exitFinished(exit.3))
        peek.apply(peek.transition.exitFinished(exit.3))
        #expect(peek.closeRequests == 1)
    }

    @MainActor @Test func aClosedPeekStaysInvisibleAsItIsRemoved() throws {
        let peek = Support.swiped()
        peek.apply(peek.transition.exitFinished(try #require(peek.lastExit).3))
        peek.apply(peek.transition.finish())
        #expect(peek.effects.last == .vanish)
        #expect(peek.transition.phase == .finished)
    }

    @MainActor @Test func whenThePageAsksLeaveSiteTheCardSpringsBackUnderTheQuestion() {
        let peek = Support.exitedAndHandedOver()
        peek.apply(peek.transition.sheetBegan(visible: true))
        #expect(peek.effects.last == .reappear)
        #expect(!peek.transition.cardHidden)
    }

    @MainActor @Test func choosingToStayLeavesTheCardInPlaceWithoutASecondSpring() {
        let peek = Support.exitedAndHandedOver()
        peek.apply(peek.transition.sheetBegan(visible: true))
        peek.apply(peek.transition.refused(visible: true))
        #expect(peek.effects.last == .reappear)
        #expect(peek.transition.phase == .resting)
    }

    @MainActor @Test func thePeekCanBeSwipedAgainAfterStaying() {
        let peek = Support.exitedAndHandedOver()
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
        #expect(Support.isSpringBack(peek.effects.last))
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
        #expect(Support.isSpringBack(peek.effects.last))
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
        #expect(peek.effects.contains { Support.isSpringBack($0) })
    }
}
