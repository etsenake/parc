import CoreGraphics
import Foundation
@testable import ParcCore
import Testing
@testable import Parc

struct HistorySwipeOverlayCardTests {
    @Test
    func openingTheListPlaysAGenericHaptic() {
        var driver = HistorySwipeOverlaySupport.Driver.armed(back: 3)
        driver.send(.hold)
        driver.send(.selection(0))
        #expect(driver.haptics == [.levelChange, .generic])
    }

    @Test
    func theListStartsHiddenInsideTheCircle() throws {
        var driver = HistorySwipeOverlaySupport.Driver.armed(back: 3)
        let circle = try #require(driver.frame).circle
        driver.send(.hold)
        driver.send(.selection(0))
        #expect(driver.frame.map { HistorySwipeOverlaySupport.close($0.capsule, circle) && $0.list?.opacity == 0 && $0.list?.scale == 0.9
                && $0.list?.blur == 10 && $0.chevronOpacity == 1 } == true)
    }

    @Test
    func theListAndChevronEaseThroughTheSwap() throws {
        var driver = HistorySwipeOverlaySupport.Driver.armed(back: 3)
        driver.send(.hold)
        driver.send(.selection(0))
        driver.advance(0.11)
        let half = HistorySwipeCurve.easeOut(0.5)
        let frame = try #require(driver.frame)
        let list = try #require(frame.list)
        #expect(HistorySwipeOverlaySupport.close(list.opacity, half) && HistorySwipeOverlaySupport.close(frame.chevronScale, 1 - 0.1 * half)
                && HistorySwipeOverlaySupport.close(frame.chevronBlur, 10 * half) && HistorySwipeOverlaySupport.close(frame.chevronOpacity, 1 - half))
    }

    @Test
    func theCircleMorphsTowardTheCardOnASpring() {
        var driver = HistorySwipeOverlaySupport.Driver.armed(back: 3)
        driver.send(.hold)
        driver.send(.selection(0))
        let opened = driver.time
        driver.advance(0.11)
        let zeta = 0.77, omega = 2 * Double.pi / 0.22, damped = omega * (1 - zeta * zeta).squareRoot()
        let t = driver.time - opened
        let morph = 1 - exp(-zeta * omega * t) * (cos(damped * t) + zeta * omega / damped * sin(damped * t))
        #expect(driver.frame.map { HistorySwipeOverlaySupport.close($0.capsule.width, 82 + (200 - 82) * CGFloat(morph), 1e-6) } == true)
    }

    @Test
    func theSwapEndsWithOnlyTheUnblurredList() {
        var driver = HistorySwipeOverlaySupport.Driver.armed(back: 3)
        driver.send(.hold)
        driver.send(.selection(0))
        driver.advance(0.11)
        driver.advance(0.1101)
        #expect(driver.frame.map { $0.list?.opacity == 1 && $0.list?.scale == 1 && $0.list?.blur == 0 && $0.chevronOpacity == 0 } == true)
    }

    @Test
    func theOpenCardRestsAtItsListGeometry() throws {
        var driver = HistorySwipeOverlaySupport.Driver.armed(back: 3)
        driver.send(.hold)
        driver.send(.selection(0))
        driver.settle()
        let frame = try #require(driver.frame)
        let list = try #require(frame.list)
        #expect(HistorySwipeOverlaySupport.close(frame.capsule, list.card) && frame.cornerRadius == 18)
    }

    @Test
    func theCardFitsTheCurrentPageAndHistoryRows() throws {
        let back = HistorySwipeOverlaySupport.Driver.holding(.back, back: 3)
        let frame = try #require(back.frame)
        let list = try #require(frame.list)
        #expect(list.rows == 4 && HistorySwipeOverlaySupport.close(list.card.width, 200) && HistorySwipeOverlaySupport.close(list.card.height, 4 * 38 + 16))
    }

    @Test
    func theBackCardAnchorsToTheLeftEdge() throws {
        let back = HistorySwipeOverlaySupport.Driver.holding(.back, back: 3)
        let frame = try #require(back.frame)
        let list = try #require(frame.list)
        #expect(HistorySwipeOverlaySupport.close(list.card.minX, frame.circle.minX))
    }

    @Test
    func theForwardCardAnchorsToTheRightEdge() throws {
        let forward = HistorySwipeOverlaySupport.Driver.holding(.forward, forward: 3)
        let ahead = try #require(forward.frame)
        let rows = try #require(ahead.list)
        #expect(HistorySwipeOverlaySupport.close(rows.card.maxX, ahead.circle.maxX))
    }

    @Test
    func theListHighlightsTheCurrentPageAtTheCircleCenter() throws {
        let back = HistorySwipeOverlaySupport.Driver.holding(.back, back: 3)
        let frame = try #require(back.frame)
        let list = try #require(frame.list)
        #expect(list.selection == 0 && HistorySwipeOverlaySupport.close(list.highlight.midY, frame.circle.midY) && HistorySwipeOverlaySupport.close(list.row(0), list.highlight))
    }

    @Test
    func backRowsStackAboveTheCurrentPage() throws {
        let back = HistorySwipeOverlaySupport.Driver.holding(.back, back: 3)
        let frame = try #require(back.frame)
        let list = try #require(frame.list)
        #expect(HistorySwipeOverlaySupport.close(list.row(1).maxY, list.row(0).minY) && HistorySwipeOverlaySupport.close(list.row(2).maxY, list.row(1).minY)
              && HistorySwipeOverlaySupport.close(list.row(3).maxY, list.row(2).minY))
    }

    @Test
    func forwardRowsStackBelowTheCurrentPage() throws {
        let forward = HistorySwipeOverlaySupport.Driver.holding(.forward, forward: 3)
        let rows = try #require(forward.frame?.list)
        #expect(HistorySwipeOverlaySupport.close(rows.row(0), rows.highlight) && HistorySwipeOverlaySupport.close(rows.row(1).minY, rows.row(0).maxY)
              && HistorySwipeOverlaySupport.close(rows.row(3).minY, rows.row(2).maxY))
    }

    @Test
    func rowsAndHighlightSitInsideTheCardInsets() throws {
        let back = HistorySwipeOverlaySupport.Driver.holding(.back, back: 3)
        let frame = try #require(back.frame)
        let list = try #require(frame.list)
        #expect(HistorySwipeOverlaySupport.close(list.row(0).minX, list.content.minX + 8) && HistorySwipeOverlaySupport.close(list.row(0).width, 184)
              && HistorySwipeOverlaySupport.close(list.highlight.width, 184))
    }

    @Test(arguments: 0...50)
    func eachBackRowCanScrollIntoView(row: Int) throws {
        var driver = HistorySwipeOverlaySupport.Driver.holding(.back, back: 50)
        driver.send(.selection(row))
        driver.settle()
        let list = try #require(driver.frame?.list)
        #expect(HistorySwipeOverlaySupport.close(list.row(row), list.highlight))
        #expect(list.card.contains(list.highlight))
    }

    @Test(arguments: 0...50)
    func theLongCardStaysInsideThePaneWhileRowsScroll(row: Int) throws {
        var driver = HistorySwipeOverlaySupport.Driver.holding(.back, back: 50)
        driver.send(.selection(row))
        driver.settle()
        let card = try #require(driver.frame?.list).card
        #expect(card.minY >= 14 - 1e-9)
        #expect(card.maxY <= HistorySwipeOverlaySupport.pane.height - 14 + 1e-9)
    }

    @Test
    func theLongCardClipsTheFullList() throws {
        let driver = HistorySwipeOverlaySupport.Driver.holding(.back, back: 50)
        let list = try #require(driver.frame?.list)
        #expect(HistorySwipeOverlaySupport.close(list.content.height, 51 * 38 + 16) && list.card.height < list.content.height)
    }

    @Test
    func theCapsuleFollowsTheVisibleCard() throws {
        let driver = HistorySwipeOverlaySupport.Driver.holding(.back, back: 50)
        let frame = try #require(driver.frame)
        let list = try #require(frame.list)
        #expect(HistorySwipeOverlaySupport.close(frame.capsule, list.card))
    }

    @Test
    func aShortListShowsTheWholeCard() throws {
        let short = try #require(HistorySwipeOverlaySupport.Driver.holding(.back, back: 2).frame?.list)
        #expect(HistorySwipeOverlaySupport.close(short.card, short.content))
    }

    @Test
    func aShortPaneKeepsTheScrollingCardInside() throws {
        var squat = HistorySwipeOverlaySupport.Driver.holding(.forward, forward: 30)
        squat.size = CGSize(width: 600, height: 300)
        squat.send(.selection(15))
        squat.settle()
        let list = try #require(squat.frame?.list)
        #expect(HistorySwipeOverlaySupport.close(list.row(15), list.highlight) && list.card.minY >= 14 && list.card.maxY <= 286)
    }
}
