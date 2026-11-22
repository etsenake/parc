import CoreGraphics
import Foundation
@testable import ParcCore
import Testing
@testable import Parc

struct HistorySwipeOverlayReducedMotionTests {
    @Test
    func reduceMotionHidesTheCircleBelowTheThreshold() {
        var driver = HistorySwipeOverlaySupport.Driver(reduced: true)
        driver.send(.begin(.back))
        driver.progress(0.1)
        #expect(driver.frame?.opacity == 0)
    }

    @Test
    func reduceMotionFadesInAStaticCircle() {
        var driver = HistorySwipeOverlaySupport.Driver(reduced: true)
        driver.send(.begin(.back))
        driver.progress(0.1)
        driver.progress(0.25)
        driver.advance(0.06)
        #expect(driver.frame.map { HistorySwipeOverlaySupport.close($0.opacity, 0.5) && HistorySwipeOverlaySupport.close($0.circle.minX, 14) && $0.circle.width == 72 } == true)
    }

    @Test
    func reduceMotionKeepsTheCircleStillDuringTravel() throws {
        var driver = HistorySwipeOverlaySupport.Driver(reduced: true)
        driver.send(.begin(.back))
        driver.progress(0.1)
        driver.progress(0.25)
        driver.advance(0.1201)
        driver.progress(0.8)
        let still = try #require(driver.frame).circle
        driver.progress(HistorySwipeOverlaySupport.band(2))
        #expect(driver.frame.map { $0.opacity == 1 && HistorySwipeOverlaySupport.close($0.circle, still) } == true)
    }

    @Test
    func reduceMotionKeepsTheArmingHaptic() {
        var driver = HistorySwipeOverlaySupport.Driver(reduced: true)
        driver.send(.begin(.back))
        driver.progress(0.25)
        driver.send(.armed(true))
        #expect(driver.haptics == [.levelChange])
    }

    @Test
    func reduceMotionArmingCrossfadesLinearly() {
        var driver = HistorySwipeOverlaySupport.Driver(reduced: true)
        driver.send(.begin(.back))
        driver.progress(0.25)
        driver.send(.armed(true))
        driver.advance(0.06)
        #expect(driver.frame.map { HistorySwipeOverlaySupport.close($0.wash, 0.5) } == true)
    }

    @Test
    func reduceMotionArmingChangesOnlyOpacity() {
        var driver = HistorySwipeOverlaySupport.Driver(reduced: true)
        driver.send(.begin(.back))
        driver.progress(0.25)
        driver.send(.armed(true))
        driver.settle()
        #expect(driver.frame.map { $0.circle.width == 72 && $0.chevronSize == 28 && $0.wash == 1 && $0.chevronOpacity == 1 } == true)
    }

    @Test
    func reduceMotionKeepsTheArmedCircleAtItsRestingSize() throws {
        var driver = HistorySwipeOverlaySupport.Driver(reduced: true)
        driver.send(.begin(.back))
        driver.progress(0.25)
        driver.send(.armed(true))
        driver.settle()
        #expect(driver.frame.map { $0.circle.width == 72 && $0.chevronSize == 28 && $0.wash == 1 && $0.chevronOpacity == 1 } == true)
    }

    @Test
    func reduceMotionReplacesTheCircleWithoutMorphing() throws {
        var driver = HistorySwipeOverlaySupport.Driver(reduced: true)
        driver.send(.begin(.back))
        driver.progress(0.25)
        driver.send(.armed(true))
        driver.settle()
        driver.send(.hold)
        driver.send(.selection(0))
        let frame = try #require(driver.frame)
        let list = try #require(frame.list)
        #expect(HistorySwipeOverlaySupport.close(frame.capsule, list.card) && frame.opacity == 0 && list.scale == 1
                && list.blur == 0 && frame.chevronBlur == 0 && frame.chevronScale == 1)
    }

    @Test
    func reduceMotionCrossfadesInTheList() throws {
        var driver = HistorySwipeOverlaySupport.Driver(reduced: true)
        driver.send(.begin(.back))
        driver.progress(0.25)
        driver.send(.armed(true))
        driver.settle()
        driver.send(.hold)
        driver.send(.selection(0))
        driver.advance(0.075)
        let frame = try #require(driver.frame)
        let list = try #require(frame.list)
        #expect(HistorySwipeOverlaySupport.close(frame.opacity, 0.5) && HistorySwipeOverlaySupport.close(list.opacity, 0.5))
    }

    @Test(arguments: [0.0, 0.6])
    func reduceMotionSelectionMovesToTheNextRowImmediately(remainder: Double) throws {
        var driver = HistorySwipeOverlaySupport.Driver.holding(.back, reduced: true)
        let originalY = try #require(driver.frame?.list).content.minY
        driver.send(.selection(1))
        driver.send(.rowRemainder(remainder))
        let immediate = try #require(driver.frame?.list)
        #expect(HistorySwipeOverlaySupport.close(immediate.content.minY, originalY + 38))
    }

    @Test(arguments: [0.0, 0.6])
    func reduceMotionSelectionDoesNotLeanAfterSettling(remainder: Double) throws {
        var driver = HistorySwipeOverlaySupport.Driver.holding(.back, reduced: true)
        let originalY = try #require(driver.frame?.list).content.minY
        driver.send(.selection(1))
        driver.send(.rowRemainder(remainder))
        _ = try #require(driver.frame?.list)
        driver.settle()
        let settled = try #require(driver.frame?.list)
        #expect(HistorySwipeOverlaySupport.close(settled.content.minY, originalY + 38))
    }

    @Test
    func reduceMotionEndingOnlyFades() {
        var driver = HistorySwipeOverlaySupport.Driver.holding(.back, reduced: true)
        driver.send(.selection(1))
        driver.send(.commit(.entry(.back, distance: 1)))
        driver.advance(0.075)
        #expect(driver.frame.map { HistorySwipeOverlaySupport.close($0.opacity, 0.5) && $0.scale == 1 && $0.blur == 0 } == true)
    }

    @Test
    func reduceMotionEndingRemovesTheIndicator() {
        var driver = HistorySwipeOverlaySupport.Driver.holding(.back, reduced: true)
        driver.send(.commit(.entry(.back, distance: 1)))
        driver.advance(0.155)
        #expect(driver.frame == nil)
    }

    @Test
    func reduceMotionFadesOutWhenBackingOff() {
        var retreat = HistorySwipeOverlaySupport.Driver(reduced: true)
        retreat.send(.begin(.back))
        retreat.progress(0.5)
        retreat.advance(0.2)
        retreat.progress(0.1)
        retreat.advance(0.1201)
        #expect(retreat.frame?.opacity == 0)
    }

    @Test
    func reduceMotionReplacesTheClosingCardWithTheCircle() {
        var driver = HistorySwipeOverlaySupport.Driver.holding(.back, back: 3, reduced: true)
        driver.send(.selection(2))
        driver.settle()
        driver.progress(0.9)
        driver.send(.armed(false))
        #expect(driver.frame.map { $0.list == nil && HistorySwipeOverlaySupport.close($0.capsule, $0.circle) && $0.opacity == 0 && $0.scale == 1 && $0.blur == 0 } == true)
    }

    @Test
    func reduceMotionCrossfadesTheCircleBackIn() {
        var driver = HistorySwipeOverlaySupport.Driver.holding(.back, back: 3, reduced: true)
        driver.send(.selection(2))
        driver.settle()
        driver.progress(0.9)
        driver.send(.armed(false))
        driver.advance(0.075)
        #expect(driver.frame.map { HistorySwipeOverlaySupport.close($0.opacity, 0.5) && $0.chevronBlur == 0 && $0.chevronScale == 1 } == true)
    }

    @Test
    func reduceMotionClosingSettlesOnAStaticCircle() {
        var driver = HistorySwipeOverlaySupport.Driver.holding(.back, back: 3, reduced: true)
        driver.send(.selection(2))
        driver.settle()
        driver.progress(0.9)
        driver.send(.armed(false))
        driver.settle()
        #expect(driver.frame.map { $0.opacity == 1 && $0.list == nil && $0.circle.width == 72 } == true && !driver.model.isAnimating)
    }

    @Test
    func reduceMotionReopensTheCardOnTheCurrentPage() throws {
        var driver = HistorySwipeOverlaySupport.Driver.holding(.back, back: 3, reduced: true)
        driver.send(.selection(2))
        driver.settle()
        driver.progress(0.9)
        driver.send(.armed(false))
        driver.settle()
        driver.send(.armed(true))
        driver.send(.hold)
        driver.send(.selection(0))
        let frame = try #require(driver.frame)
        let list = try #require(frame.list)
        #expect(HistorySwipeOverlaySupport.close(frame.capsule, list.card) && frame.opacity == 0 && HistorySwipeOverlaySupport.close(list.row(0), list.highlight))
    }

    @Test
    func reduceMotionCrossfadesTheReopenedCard() {
        var driver = HistorySwipeOverlaySupport.Driver.holding(.back, back: 3, reduced: true)
        driver.send(.selection(2))
        driver.settle()
        driver.progress(0.9)
        driver.send(.armed(false))
        driver.settle()
        driver.send(.armed(true))
        driver.send(.hold)
        driver.send(.selection(0))
        driver.advance(0.075)
        #expect(driver.frame.map { HistorySwipeOverlaySupport.close($0.opacity, 0.5) } == true)
    }

    @Test
    func reduceMotionLeavesAnOpenListVisibleWithShortTravel() {
        var open = HistorySwipeOverlaySupport.Driver.holding(.back, back: 3, reduced: true)
        open.send(.selection(2))
        open.progress(0.12)
        open.settle()
        #expect(open.frame.map { $0.opacity == 1 && $0.list != nil } == true)
    }

    @Test
    func reduceMotionClosingAtShortTravelDoesNotFlash() throws {
        var open = HistorySwipeOverlaySupport.Driver.holding(.back, back: 3, reduced: true)
        open.send(.selection(2))
        open.progress(0.12)
        open.settle()
        open.send(.armed(false))
        var brightest = try #require(open.frame).opacity
        for _ in 0..<40 {
            open.advance(1.0 / 120)
            brightest = max(brightest, open.frame?.opacity ?? 0)
        }
        #expect(brightest == 0 && open.frame?.list == nil)
    }
}
