import AppKit
@testable import ParcCore
import Testing
@testable import Parc

struct HistorySwipeDriverTestsSession {
    private typealias Hand = HistorySwipeDriverTestsSupport.Hand
    private typealias Page = HistorySwipeDriverTestsSupport.Page

    private let parameters = HistorySwipeParameters()

    @Test
    func openingBackPresentsTheSession() {
        var hand = Hand(Page())
        hand.openBack()
        #expect(hand.page.begun == [.back])
        #expect(hand.page.gestures == [.begin(.back)])
    }

    @Test
    func openingBackConsumesTheScroll() {
        var hand = Hand(Page())
        hand.openBack()
        #expect(hand.steps.last?.consumesEvent == true)
    }

    @Test
    func likelyBackPreloadsOnce() {
        var hand = Hand(Page())
        hand.openBack()
        hand.touch(.moved, x: 0.5 + parameters.consumeDistance * 2)
        hand.armBack()
        #expect(hand.page.preloads == 1)
    }

    @Test
    func liftingAnArmedSwipeNavigatesBackOnce() {
        var hand = Hand(Page())
        hand.openBack()
        hand.armBack()
        hand.touch(.ended)
        #expect(hand.page.commits == [.adjacent(.back)])
    }

    @Test
    func liftingAnArmedSwipePresentsTheCommit() {
        var hand = Hand(Page())
        hand.openBack()
        hand.armBack()
        hand.touch(.ended)
        #expect(hand.page.gestures == [.begin(.back), .armed(true), .commit(.adjacent(.back))])
    }

    @Test
    func committingEndsTheSession() {
        var hand = Hand(Page())
        hand.openBack()
        hand.armBack()
        hand.touch(.ended)
        #expect(hand.page.ends == 1)
        #expect(!hand.driver.isActive)
    }

    @Test
    func refusingBackStopsTrackingWithoutAnIndicator() {
        var hand = Hand(Page())
        hand.page.opens = false
        hand.openBack()
        #expect(hand.page.begun == [.back])
        #expect(hand.page.shown.isEmpty)
        #expect(hand.steps.last?.stopsTracking == true)
    }

    @Test
    func liftingAfterRefusalDoesNotNavigate() {
        var hand = Hand(Page())
        hand.page.opens = false
        hand.openBack()
        hand.armBack(multiplier: 1.5)
        hand.touch(.ended)
        #expect(hand.page.commits.isEmpty)
        #expect(hand.page.shown.isEmpty)
    }

    @Test
    func cancelEndsTheSessionAndIndicator() {
        var hand = Hand(Page())
        hand.openBack()
        hand.armBack()
        hand.driver.cancel()
        #expect(hand.page.gestures.last == .cancel)
        #expect(hand.page.ends == 1)
    }

    @Test
    func liftingAfterCancelDoesNotNavigate() {
        var hand = Hand(Page())
        hand.openBack()
        hand.armBack()
        hand.driver.cancel()
        hand.touch(.ended)
        #expect(hand.page.commits.isEmpty)
    }

    @Test
    func cancellingTwicePresentsOneCancel() {
        var hand = Hand(Page())
        hand.openBack()
        hand.armBack()
        hand.driver.cancel()
        hand.driver.cancel()
        #expect(hand.page.gestures.filter { $0 == .cancel }.count == 1)
    }

    @Test
    func refusedNavigationCancelsTheIndicator() {
        var hand = Hand(Page())
        hand.openBack()
        hand.armBack()
        hand.page.lands = false
        hand.touch(.ended)
        #expect(hand.page.commits == [.adjacent(.back)])
        #expect(hand.page.gestures.last == .cancel)
    }

    @Test
    func navigationCanRequestCancellationWithoutCancellingItsOwnCommit() {
        var hand = Hand(Page())
        hand.openBack()
        hand.armBack()
        hand.page.duringNavigation = { [weak driver = hand.driver] in driver?.cancel() }
        hand.touch(.ended)
        #expect(hand.page.gestures.last == .commit(.adjacent(.back)))
        #expect(!hand.page.gestures.contains(.cancel))
    }
}
