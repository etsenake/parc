import CoreGraphics
import Foundation
@testable import ParcCore
import Testing
@testable import Parc

struct HistorySwipeOverlayClosingTests {
    @Test
    func disarmingSilentlyClosesTheList() {
        var driver = HistorySwipeOverlaySupport.Driver.holding(.back, back: 3)
        driver.send(.selection(2))
        driver.settle()
        driver.send(.rowRemainder(0.5))
        driver.progress(0.9)
        driver.send(.armed(false))
        #expect(driver.haptics == [.levelChange, .generic] && !driver.model.listOpen && !driver.model.armed)
    }

    @Test
    func closingTheListClearsItsLean() {
        var driver = HistorySwipeOverlaySupport.Driver.holding(.back, back: 3)
        driver.send(.selection(2))
        driver.settle()
        driver.send(.rowRemainder(0.5))
        driver.progress(0.9)
        driver.send(.armed(false))
        #expect(driver.model.remainder == 0)
    }

    @Test
    func closingTheListStartsAtTheOpenCard() throws {
        var driver = HistorySwipeOverlaySupport.Driver.holding(.back, back: 3)
        driver.send(.selection(2))
        driver.settle()
        let open = try #require(driver.frame?.list)
        driver.send(.rowRemainder(0.5))
        driver.progress(0.9)
        driver.send(.armed(false))
        let start = try #require(driver.frame)
        #expect(HistorySwipeOverlaySupport.close(start.capsule, open.card) && start.list?.opacity == 1 && start.chevronOpacity == 0)
    }

    @Test
    func theClosingListBlursAndShrinks() throws {
        var driver = HistorySwipeOverlaySupport.Driver.holding(.back, back: 3)
        driver.send(.selection(2))
        driver.settle()
        driver.send(.rowRemainder(0.5))
        driver.progress(0.9)
        driver.send(.armed(false))
        driver.advance(0.11)
        let mid = try #require(driver.frame), half = HistorySwipeCurve.easeOut(0.5)
        let swapIn = 1 - half
        #expect(mid.list.map { HistorySwipeOverlaySupport.close($0.opacity, swapIn) && HistorySwipeOverlaySupport.close($0.scale, 0.9 + 0.1 * swapIn) && HistorySwipeOverlaySupport.close($0.blur, 10 * half) } == true)
    }

    @Test
    func theChevronSwapsBackInWhileTheListCloses() throws {
        var driver = HistorySwipeOverlaySupport.Driver.holding(.back, back: 3)
        driver.send(.selection(2))
        driver.settle()
        driver.send(.rowRemainder(0.5))
        driver.progress(0.9)
        driver.send(.armed(false))
        driver.advance(0.11)
        let mid = try #require(driver.frame), half = HistorySwipeCurve.easeOut(0.5)
        let swapIn = 1 - half, armedAmount = 1 - HistorySwipeCurve.easeOut(0.11 / 0.18)
        #expect(HistorySwipeOverlaySupport.close(mid.chevronOpacity, (0.5 + 0.5 * armedAmount) * half) && HistorySwipeOverlaySupport.close(mid.chevronScale, 1 - 0.1 * swapIn)
              && HistorySwipeOverlaySupport.close(mid.chevronBlur, 10 * swapIn))
    }

    @Test
    func theClosingCardFoldsTowardTheCircleAndKeepsItsRows() throws {
        var driver = HistorySwipeOverlaySupport.Driver.holding(.back, back: 3)
        driver.send(.selection(2))
        driver.settle()
        driver.send(.rowRemainder(0.5))
        driver.progress(0.9)
        driver.send(.armed(false))
        driver.advance(0.11)
        let zeta = 0.77, omega = 2 * Double.pi / 0.22, damped = omega * (1 - zeta * zeta).squareRoot(), t = 0.11
        let morph = exp(-zeta * omega * t) * (cos(damped * t) + zeta * omega / damped * sin(damped * t))
        let mid = try #require(driver.frame)
        #expect(HistorySwipeOverlaySupport.close(mid.capsule.width, mid.circle.width + (200 - mid.circle.width) * CGFloat(morph), 1e-6)
              && mid.list.map { HistorySwipeOverlaySupport.close($0.row(2), $0.highlight) } == true)
    }

    @Test
    func theFoldEndsAtTheRestingCircle() throws {
        var driver = HistorySwipeOverlaySupport.Driver.holding(.back, back: 3)
        driver.send(.selection(2))
        driver.settle()
        driver.send(.rowRemainder(0.5))
        driver.progress(0.9)
        driver.send(.armed(false))
        driver.settle()
        let rest = try #require(driver.frame)
        #expect(rest.list == nil && HistorySwipeOverlaySupport.close(rest.capsule, rest.circle) && rest.cornerRadius == 36 && rest.circle.width == 72
              && rest.chevronOpacity == 0.5 && rest.chevronScale == 1 && rest.chevronBlur == 0 && rest.wash == 0
              && !driver.model.isAnimating)
    }

    @Test
    func rearmingAndReopeningPlayTheirHapticsAgain() {
        var driver = HistorySwipeOverlaySupport.Driver.holding(.back, back: 3)
        driver.send(.selection(2))
        driver.settle()
        driver.send(.rowRemainder(0.5))
        driver.progress(0.9)
        driver.send(.armed(false))
        driver.settle()
        driver.progress(1.1)
        driver.send(.armed(true))
        driver.settle()
        driver.send(.hold)
        driver.send(.selection(0))
        #expect(driver.haptics == [.levelChange, .generic, .levelChange, .generic])
    }

    @Test
    func theListReopensFromTheCircle() throws {
        var driver = HistorySwipeOverlaySupport.Driver.holding(.back, back: 3)
        driver.send(.selection(2))
        driver.settle()
        driver.send(.rowRemainder(0.5))
        driver.progress(0.9)
        driver.send(.armed(false))
        driver.settle()
        driver.progress(1.1)
        driver.send(.armed(true))
        driver.settle()
        let circle = try #require(driver.frame).circle
        driver.send(.hold)
        driver.send(.selection(0))
        #expect(driver.frame.map { HistorySwipeOverlaySupport.close($0.capsule, circle) && $0.list?.opacity == 0 && $0.list?.scale == 0.9 && $0.list?.blur == 10 } == true)
    }

    @Test
    func theReopenedListResetsToTheCurrentPage() throws {
        var driver = HistorySwipeOverlaySupport.Driver.holding(.back, back: 3)
        driver.send(.selection(2))
        driver.settle()
        driver.send(.rowRemainder(0.5))
        driver.progress(0.9)
        driver.send(.armed(false))
        driver.settle()
        driver.progress(1.1)
        driver.send(.armed(true))
        driver.settle()
        driver.send(.hold)
        driver.send(.selection(0))
        driver.settle()
        let frame = try #require(driver.frame)
        let list = try #require(frame.list)
        #expect(HistorySwipeOverlaySupport.close(frame.capsule, list.card) && HistorySwipeOverlaySupport.close(list.row(0), list.highlight))
    }

    @Test
    func reopeningMidCollapsePreservesTheCurrentFrame() throws {
        var driver = HistorySwipeOverlaySupport.Driver.holding(.back, back: 3)
        driver.send(.selection(2))
        driver.settle()
        driver.progress(0.9)
        driver.send(.armed(false))
        driver.advance(0.1)
        driver.progress(1.1)
        driver.send(.armed(true))
        let before = try #require(driver.frame)
        driver.send(.hold)
        driver.send(.selection(0))
        let after = try #require(driver.frame)
        let previousList = try #require(before.list)
        let reopenedList = try #require(after.list)
        #expect(HistorySwipeOverlaySupport.close(after.capsule, before.capsule))
        #expect(HistorySwipeOverlaySupport.close(reopenedList.content, previousList.content))
        #expect(HistorySwipeOverlaySupport.close(reopenedList.opacity, previousList.opacity))
        #expect(HistorySwipeOverlaySupport.close(after.chevronOpacity, before.chevronOpacity))
    }

    @Test
    func reopeningMidCollapseMorphsSmoothly() throws {
        var driver = HistorySwipeOverlaySupport.Driver.holding(.back, back: 3)
        driver.send(.selection(2))
        driver.settle()
        driver.progress(0.9)
        driver.send(.armed(false))
        driver.advance(0.1)
        driver.progress(1.1)
        driver.send(.armed(true))
        driver.send(.hold)
        driver.send(.selection(0))
        var widths: [CGFloat] = []
        for _ in 0..<60 {
            driver.advance(1.0 / 120)
            widths.append(try #require(driver.frame).capsule.width)
        }
        let jumps = zip(widths, widths.dropFirst()).map { abs($1 - $0) }
        let largestJump = try #require(jumps.max())
        #expect(largestJump < 20)
    }

    @Test
    func reopeningMidCollapseEndsOnTheCurrentPage() throws {
        var driver = HistorySwipeOverlaySupport.Driver.holding(.back, back: 3)
        driver.send(.selection(2))
        driver.settle()
        driver.progress(0.9)
        driver.send(.armed(false))
        driver.advance(0.1)
        driver.progress(1.1)
        driver.send(.armed(true))
        driver.send(.hold)
        driver.send(.selection(0))
        driver.settle()
        let frame = try #require(driver.frame)
        let list = try #require(frame.list)
        #expect(HistorySwipeOverlaySupport.close(frame.capsule, list.card) && HistorySwipeOverlaySupport.close(list.row(0), list.highlight) && list.opacity == 1)
    }
}
