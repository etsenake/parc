import AppKit
@testable import ParcCore
import Testing

struct HistorySwipeDriverTestsHold {
    private typealias Hand = HistorySwipeDriverTestsSupport.Hand
    private typealias Page = HistorySwipeDriverTestsSupport.Page

    private let parameters = HistorySwipeParameters()

    @Test
    func armingSchedulesTheHoldDelay() throws {
        var hand = Hand(Page())
        hand.openBack()
        hand.armBack()
        let tick = try #require(hand.page.ticks.first)
        #expect(hand.page.ticks.count == 1)
        #expect(abs(tick.deadline - (hand.time + parameters.holdDelay)) < 1e-9)
    }

    @Test
    func movingWithTheSameDeadlineDoesNotScheduleAgain() {
        var hand = Hand(Page())
        hand.openBack()
        hand.armBack()
        hand.armBack(multiplier: 1.25)
        #expect(hand.page.ticks.count == 1)
    }

    @Test
    func holdingOpensTheListOnTheCurrentPage() {
        var hand = Hand(Page())
        hand.openBack()
        hand.armBack()
        hand.armBack(multiplier: 1.25)
        hand.tick()
        hand.tick()
        #expect(hand.page.gestures.suffix(2) == [.hold, .selection(0)])
    }

    @Test
    func liftingOnAHistoryRowNavigatesToThatEntry() {
        var hand = Hand(Page())
        hand.openBack()
        hand.armBack()
        hand.armBack(multiplier: 1.25)
        hand.tick()
        hand.tick()
        hand.touch(.moved, y: 0.5 + parameters.rowStep * 1.1)
        hand.touch(.ended)
        #expect(hand.page.commits == [.entry(.back, distance: 1)])
    }

    @Test
    func rearmingSchedulesANewHold() {
        var hand = Hand(Page())
        hand.openBack()
        hand.armBack()
        hand.armBack(multiplier: 0.5)
        hand.armBack()
        #expect(hand.page.ticks.count == 2)
    }

    @Test
    func rearmingDiscardsTheEarlierHold() throws {
        var hand = Hand(Page())
        hand.openBack()
        hand.armBack()
        let stale = try #require(hand.page.ticks.first)
        hand.armBack(multiplier: 0.5)
        hand.armBack()
        hand.page.now = stale.deadline
        stale.tick()
        #expect(!hand.page.gestures.contains(.hold))
    }
}
