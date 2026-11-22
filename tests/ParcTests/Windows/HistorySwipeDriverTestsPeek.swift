import AppKit
@testable import ParcCore
import Testing
@testable import Parc

struct HistorySwipeDriverTestsPeek {
    private typealias Hand = HistorySwipeDriverTestsSupport.Hand
    private typealias Page = HistorySwipeDriverTestsSupport.Page

    private let parameters = HistorySwipeParameters()

    @Test
    func theFirstPeekPageOpensDismissal() {
        var hand = Hand(Page.peek)
        hand.openBack()
        #expect(hand.page.begun.isEmpty)
        #expect(hand.page.dismissals == 1)
        #expect(hand.page.gestures == [.beginDismissal])
    }

    @Test
    func releasingAnArmedPeekAsksItToCloseOnce() {
        var hand = Hand(Page.peek)
        hand.openBack()
        hand.touch(.moved, x: 0.5 + parameters.dismissDistance * 0.6)
        hand.rest()
        hand.touch(.ended)
        #expect(hand.page.commits == [.dismiss])
    }

    @Test
    func thePeekReceivesArmingAndReleaseBeforeClose() {
        var hand = Hand(Page.peek)
        hand.openBack()
        hand.touch(.moved, x: 0.5 + parameters.dismissDistance * 0.3)
        hand.touch(.moved, x: 0.5 + parameters.dismissDistance * 0.6)
        hand.rest()
        hand.touch(.ended)
        #expect(hand.page.shape == [.beginDismissal, .armed(true), .release(velocity: 0), .commit(.dismiss)])
    }

    @Test
    func peekDismissalEndsWithoutPreloadingBack() {
        var hand = Hand(Page.peek)
        hand.openBack()
        hand.touch(.moved, x: 0.5 + parameters.dismissDistance * 0.6)
        hand.rest()
        hand.touch(.ended)
        #expect(hand.page.ends == 1)
        #expect(hand.page.preloads == 0)
        #expect(!hand.driver.isActive)
    }

    @Test
    func refusingPeekDismissalStopsTrackingWithoutPresentation() {
        var hand = Hand(Page.peek)
        hand.page.dismissalOpens = false
        hand.openBack()
        #expect(hand.page.dismissals == 1)
        #expect(hand.page.shown.isEmpty)
        #expect(hand.steps.last?.stopsTracking == true)
    }

    @Test
    func releasingARefusedPeekDragDoesNotClose() {
        var hand = Hand(Page.peek)
        hand.page.dismissalOpens = false
        hand.openBack()
        hand.touch(.moved, x: 0.5 + parameters.dismissDistance * 0.8)
        hand.touch(.ended)
        #expect(hand.page.commits.isEmpty)
        #expect(hand.page.shown.isEmpty)
    }

    @Test
    func aPeekThatRefusesToCloseSpringsBack() {
        var hand = Hand(Page.peek)
        hand.openBack()
        hand.touch(.moved, x: 0.5 + parameters.dismissDistance * 0.6)
        hand.page.lands = false
        hand.rest()
        hand.touch(.ended)
        #expect(hand.page.commits == [.dismiss])
        #expect(hand.page.gestures.last == .cancel)
    }

    @Test
    func cancellingAPeekDragEndsItOnceWithoutClosing() {
        var hand = Hand(Page.peek)
        hand.openBack()
        hand.touch(.moved, x: 0.5 + parameters.dismissDistance * 0.6)
        hand.driver.cancel()
        hand.touch(.ended)
        #expect(hand.page.commits.isEmpty)
        #expect(hand.page.gestures.filter { $0 == .cancel }.count == 1)
        #expect(hand.page.ends == 1)
    }

    @Test
    func appKitTrackingBeginsPeekDismissal() throws {
        var hand = Hand(Page.peek)
        let generation = try hand.openTrackedBack()
        #expect(generation > 0)
        #expect(hand.update(generation, 0, .began))
        #expect(hand.page.gestures == [.beginDismissal])
    }

    @Test
    func appKitCanTrackAnArmedPeekSwipe() throws {
        var hand = Hand(Page.peek)
        let generation = try hand.openTrackedBack()
        _ = hand.update(generation, 0, .began)
        #expect(hand.update(generation, 0.6, .changed))
    }

    @Test
    func appKitEndingClosesThePeek() throws {
        var hand = Hand(Page.peek)
        let generation = try hand.openTrackedBack()
        _ = hand.update(generation, 0, .began)
        _ = hand.update(generation, 0.6, .changed)
        #expect(hand.update(generation, 0.7, .ended))
        #expect(hand.page.commits == [.dismiss])
    }

    @Test
    func aPeekWithPreviousPagesOpensBackInsteadOfDismissal() {
        var hand = Hand(Page())
        hand.page.peekFirstPage = true
        hand.openBack()
        #expect(hand.page.begun == [.back])
        #expect(hand.page.dismissals == 0)
    }
}
