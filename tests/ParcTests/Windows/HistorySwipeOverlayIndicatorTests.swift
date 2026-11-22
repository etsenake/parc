import CoreGraphics
import Foundation
@testable import ParcCore
import Testing
@testable import Parc

struct HistorySwipeOverlayIndicatorTests {
    @Test(arguments: [HistorySwipeDirection.back, .forward])
    func theCircleStartsJustOutsideThePane(direction: HistorySwipeDirection) throws {
        var driver = HistorySwipeOverlaySupport.Driver()
        driver.send(.begin(direction))
        let circle = try #require(driver.frame).circle
        if direction == .back {
            #expect(circle.maxX == 0)
        } else {
            #expect(circle.minX == HistorySwipeOverlaySupport.pane.width)
        }
    }

    @Test
    func theCircleTracksFingerTravelImmediately() {
        var back = HistorySwipeOverlaySupport.Driver()
        back.send(.begin(.back))
        back.progress(0.5)
        #expect(back.frame.map { HistorySwipeOverlaySupport.close($0.circle.minX, 0.5 * 86 - 72) } == true)
    }

    @Test
    func backPlacesTheCircleAtItsInsetAtCommit() {
        var back = HistorySwipeOverlaySupport.Driver()
        back.send(.begin(.back))
        back.progress(1)
        #expect(back.frame.map { HistorySwipeOverlaySupport.close($0.circle.minX, 14) && HistorySwipeOverlaySupport.close($0.circle.midY, HistorySwipeOverlaySupport.pane.height / 2) } == true)
    }

    @Test
    func forwardMirrorsTheInsetAtCommit() {
        var forward = HistorySwipeOverlaySupport.Driver()
        forward.send(.begin(.forward))
        forward.progress(1)
        #expect(forward.frame.map { HistorySwipeOverlaySupport.close($0.circle.maxX, HistorySwipeOverlaySupport.pane.width - 14) } == true)
    }

    @Test
    func theChevronIsCenteredInTheCircle() {
        var forward = HistorySwipeOverlaySupport.Driver()
        forward.send(.begin(.forward))
        forward.progress(1)
        #expect(forward.frame.map { HistorySwipeOverlaySupport.close($0.chevronCenter.x, $0.circle.midX) && HistorySwipeOverlaySupport.close($0.chevronCenter.y, $0.circle.midY) } == true)
    }

    @Test
    func theRestingCircleFollowsTheRubberBandPastCommit() {
        var back = HistorySwipeOverlaySupport.Driver()
        back.send(.begin(.back))
        back.progress(HistorySwipeOverlaySupport.band(2))
        #expect(back.frame.map { HistorySwipeOverlaySupport.close($0.circle.minX, 14 + 86 * (HistorySwipeOverlaySupport.band(2) - 1)) } == true)
    }

    @Test
    func theArmedCircleFollowsTheRubberBandAtItsLargerSize() {
        let armed = HistorySwipeOverlaySupport.Driver.armed(stretch: HistorySwipeOverlaySupport.band(2))
        #expect(armed.frame.map { abs($0.circle.minX - 26.5) < 0.1 && HistorySwipeOverlaySupport.close($0.circle.width, 82) } == true)
    }

    @Test
    func theArmedCircleTracksAdjustedRubberBandProgress() {
        var armed = HistorySwipeOverlaySupport.Driver.armed(stretch: HistorySwipeOverlaySupport.band(2))
        armed.progress(HistorySwipeOverlaySupport.band(1.5))
        #expect(armed.frame.map { HistorySwipeOverlaySupport.close($0.circle.minX, CGFloat(HistorySwipeOverlaySupport.band(1.5)) * 96 - 82) } == true)
    }

    @Test
    func theUnarmedChevronIsSmallAndDim() {
        var driver = HistorySwipeOverlaySupport.Driver()
        driver.send(.begin(.back))
        driver.progress(1)
        #expect(driver.frame.map { $0.wash == 0 && $0.chevronOpacity == 0.5 && $0.chevronSize == 28 } == true)
    }

    @Test
    func armingPlaysALevelChangeHaptic() {
        var driver = HistorySwipeOverlaySupport.Driver()
        driver.send(.begin(.back))
        driver.progress(1)
        driver.send(.armed(true))
        #expect(driver.haptics == [.levelChange])
    }

    @Test
    func armingBrightensTheWashAndChevronWithEaseOut() {
        var driver = HistorySwipeOverlaySupport.Driver()
        driver.send(.begin(.back))
        driver.progress(1)
        driver.send(.armed(true))
        driver.advance(0.09)
        let half = HistorySwipeCurve.easeOut(0.5)
        #expect(driver.frame.map { HistorySwipeOverlaySupport.close($0.wash, half) && HistorySwipeOverlaySupport.close($0.chevronOpacity, 0.5 + 0.5 * half) } == true)
    }

    @Test
    func armingCompletesTheFade() {
        var driver = HistorySwipeOverlaySupport.Driver()
        driver.send(.begin(.back))
        driver.progress(1)
        let start = driver.time
        driver.send(.armed(true))
        driver.advance(0.09)
        driver.advance(0.6)
        #expect(driver.frame.map { $0.wash == 1 && $0.chevronOpacity == 1 } == true && driver.time - start > HistorySwipeOverlaySupport.Timing.fade)
    }

    @Test
    func armingOvershootsTheCircleDiameterAndSettles() throws {
        var driver = HistorySwipeOverlaySupport.Driver()
        driver.send(.begin(.back))
        driver.progress(1)
        driver.send(.armed(true))
        driver.advance(0.09)
        var sizes: [CGFloat] = []
        for _ in 0..<60 {
            driver.advance(0.01)
            if let frame = driver.frame { sizes.append(frame.circle.width) }
        }
        let peak = try #require(sizes.max())
        #expect(peak > 82.3 && peak < 82.6)
        #expect(sizes.last == 82)
    }

    @Test
    func theArmedChevronRestsAtFullSize() {
        var driver = HistorySwipeOverlaySupport.Driver()
        driver.send(.begin(.back))
        driver.progress(1)
        driver.send(.armed(true))
        driver.advance(0.09)
        var sizes: [CGFloat] = []
        for _ in 0..<60 {
            driver.advance(0.01)
            if let frame = driver.frame { sizes.append(frame.circle.width) }
        }
        #expect(driver.frame?.chevronSize == 34 && !driver.model.isAnimating)
    }

    @Test
    func disarmingIsSilent() {
        var driver = HistorySwipeOverlaySupport.Driver()
        driver.send(.begin(.back))
        driver.progress(1)
        driver.send(.armed(true))
        driver.send(.armed(false))
        #expect(driver.haptics == [.levelChange])
    }

    @Test
    func disarmingFadesTheWashAndChevron() {
        var driver = HistorySwipeOverlaySupport.Driver()
        driver.send(.begin(.back))
        driver.progress(1)
        driver.send(.armed(true))
        driver.advance(0.6)
        driver.send(.armed(false))
        driver.advance(HistorySwipeOverlaySupport.Timing.fade + 0.0001)
        #expect(driver.frame?.wash == 0 && driver.frame?.chevronOpacity == 0.5)
    }

    @Test
    func disarmingReturnsTheCircleAndChevronToRest() {
        var driver = HistorySwipeOverlaySupport.Driver()
        driver.send(.begin(.back))
        driver.progress(1)
        driver.send(.armed(true))
        driver.advance(0.6)
        driver.send(.armed(false))
        driver.settle()
        #expect(driver.frame?.circle.width == 72 && driver.frame?.chevronSize == 28)
    }

    @Test
    func committingCollapsesInPlaceWithBlurAndFade() throws {
        var commit = HistorySwipeOverlaySupport.Driver.armed()
        let before = try #require(commit.frame).capsule
        commit.send(.commit(.adjacent(.back)))
        commit.advance(0.1)
        let amount = HistorySwipeCurve.easeIn(0.5)
        #expect(commit.frame.map { HistorySwipeOverlaySupport.close($0.opacity, 1 - amount) && HistorySwipeOverlaySupport.close($0.scale, 1 - 0.99 * amount)
                && HistorySwipeOverlaySupport.close($0.blur, 10 * amount) && HistorySwipeOverlaySupport.close($0.capsule, before) } == true)
    }

    @Test
    func commitAndCancelHaveTheSameCollapse() {
        var commit = HistorySwipeOverlaySupport.Driver.armed()
        var cancel = HistorySwipeOverlaySupport.Driver.armed()
        commit.send(.commit(.adjacent(.back)))
        cancel.send(.cancel)
        commit.advance(0.1)
        cancel.advance(0.1)
        #expect(commit.frame == cancel.frame)
    }

    @Test(arguments: [HistorySwipeOutput.commit(.adjacent(.back)), .cancel])
    func endingDoesNotPlayAHaptic(output: HistorySwipeOutput) {
        var driver = HistorySwipeOverlaySupport.Driver.armed()
        driver.send(output)
        #expect(driver.haptics == [.levelChange])
    }

    @Test
    func theIndicatorIsGoneAfterCollapse() {
        var commit = HistorySwipeOverlaySupport.Driver.armed()
        commit.send(.commit(.adjacent(.back)))
        commit.advance(0.1)
        commit.advance(0.1001)
        #expect(commit.frame == nil && !commit.model.isAnimating)
    }

    @Test
    func lateProgressCannotReviveTheIndicator() {
        var commit = HistorySwipeOverlaySupport.Driver.armed()
        commit.send(.commit(.adjacent(.back)))
        commit.advance(0.1)
        commit.advance(0.1001)
        commit.send(.progress(HistorySwipeProgress(fraction: 1, stretch: 1)))
        #expect(commit.frame == nil)
    }

    @Test
    func anIdleOverlayHasNoFrameOrAnimation() {
        let idle = HistorySwipeOverlaySupport.Driver()
        #expect(idle.frame == nil && !idle.model.isAnimating)
    }

    @Test
    func outputsBeforeBeginDoNotDrawOrPlayHaptics() {
        var idle = HistorySwipeOverlaySupport.Driver()
        idle.send(.progress(HistorySwipeProgress(fraction: 1, stretch: 1)))
        idle.send(.armed(true))
        idle.send(.hold)
        #expect(idle.frame == nil && idle.haptics.isEmpty)
    }

    @Test
    func aNewSwipeStartsFreshDuringCollapse() {
        var again = HistorySwipeOverlaySupport.Driver.armed()
        again.send(.cancel)
        again.advance(0.05)
        again.send(.begin(.forward))
        #expect(again.frame.map { $0.opacity == 1 && $0.scale == 1 && $0.direction == .forward && $0.wash == 0 } == true)
    }

    @Test
    func resetImmediatelyDropsTheIndicator() {
        var reset = HistorySwipeOverlaySupport.Driver.holding()
        reset.model.reset()
        #expect(reset.frame == nil && !reset.model.isAnimating)
    }
}
