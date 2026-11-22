import AppKit
@testable import ParcCore
import Testing
@testable import Parc

struct HistorySwipeDriverTestsEligibility {
    private typealias Hand = HistorySwipeDriverTestsSupport.Hand
    private typealias Page = HistorySwipeDriverTestsSupport.Page

    @Test
    func losingEligibilityMidSwipeCancels() {
        var hand = Hand(Page())
        hand.openBack()
        hand.page.allowsHistorySwipe = false
        hand.armBack()
        #expect(hand.page.gestures.last == .cancel)
        #expect(hand.page.ends == 1)
    }

    @Test(arguments: [true, false])
    func aDisabledSwipeDoesNotOpenASession(systemEnabled: Bool) {
        var hand = Hand(Page())
        hand.page.swipesBetweenPages = systemEnabled
        hand.page.allowsHistorySwipe = !systemEnabled
        hand.openBack()
        #expect(hand.page.begun.isEmpty)
        #expect(hand.page.shown.isEmpty)
    }

    @Test
    func aDeallocatedPageStopsTracking() {
        let page = Page()
        weak var gone: Page?
        let driver: HistorySwipeDriver
        do {
            let temporary = Page()
            gone = temporary
            driver = HistorySwipeDriver(target: temporary, presenter: page, clock: page)
        }
        #expect(gone == nil)
        #expect(driver.receive(.cancel).stopsTracking)
    }
}
