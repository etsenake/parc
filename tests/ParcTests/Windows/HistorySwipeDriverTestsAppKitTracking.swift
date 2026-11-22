import AppKit
@testable import ParcCore
import Testing
@testable import Parc

struct HistorySwipeDriverTestsAppKitTracking {
    private typealias Hand = HistorySwipeDriverTestsSupport.Hand
    private typealias Page = HistorySwipeDriverTestsSupport.Page

    @Test
    func aSwipeWithoutTouchesRequestsAppKitTracking() throws {
        var hand = Hand(Page())
        let generation = try hand.openTrackedBack()
        #expect(generation > 0)
        #expect(hand.steps.last?.startsTracking?.direction == .back)
        #expect(hand.steps.last?.consumesEvent == true)
    }

    @Test
    func appKitTrackingBeginsTheSession() throws {
        var hand = Hand(Page())
        let generation = try hand.openTrackedBack()
        #expect(hand.update(generation, 0, .began))
        #expect(hand.page.begun == [.back])
        #expect(hand.page.gestures == [.begin(.back)])
    }

    @Test
    func appKitAmountArmsTheSwipe() throws {
        var hand = Hand(Page())
        let generation = try hand.openTrackedBack()
        _ = hand.update(generation, 0, .began)
        #expect(hand.update(generation, 0.35, .changed))
        #expect(hand.page.gestures.contains(.armed(true)))
    }

    @Test
    func appKitEndingCommitsTheSwipe() throws {
        var hand = Hand(Page())
        let generation = try hand.openTrackedBack()
        _ = hand.update(generation, 0, .began)
        _ = hand.update(generation, 0.35, .changed)
        #expect(hand.update(generation, 0.6, .ended))
        #expect(hand.page.commits == [.adjacent(.back)])
    }

    @Test
    func appKitCanFinishItsAnimationAfterCommit() throws {
        var hand = Hand(Page())
        let generation = try hand.openTrackedBack()
        _ = hand.update(generation, 0, .began)
        _ = hand.update(generation, 0.35, .changed)
        _ = hand.update(generation, 0.6, .ended)
        #expect(hand.update(generation, 1, .changed, complete: true))
    }

    @Test
    func aStaleAppKitGenerationStopsTracking() throws {
        var hand = Hand(Page())
        let generation = try hand.openTrackedBack()
        _ = hand.update(generation, 0, .began)
        #expect(!hand.update(generation + 1, 0.2, .changed))
    }

    @Test
    func aLateAppKitEndAfterCancelStopsWithoutNavigating() throws {
        var hand = Hand(Page())
        let generation = try hand.openTrackedBack()
        _ = hand.update(generation, 0, .began)
        hand.driver.cancel()
        #expect(!hand.update(generation, 0.5, .ended))
        #expect(hand.page.commits.isEmpty)
    }
}
