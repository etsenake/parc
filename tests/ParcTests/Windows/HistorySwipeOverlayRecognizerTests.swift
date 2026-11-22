import CoreGraphics
import Foundation
@testable import ParcCore
import Testing
@testable import Parc

struct HistorySwipeOverlayRecognizerTests {
    @Test
    func recognizerCommitTravelPlacesTheCircleAtItsInset() {
        var hand = HistorySwipeOverlaySupport.Fingers(back: 50)
        hand.open()
        hand.touch(.moved, 0.38)
        #expect(hand.overlay.frame.map { abs($0.circle.minX - 14) < 0.001 } == true)
    }

    @Test
    func recognizerArmingProducesOneHaptic() {
        var hand = HistorySwipeOverlaySupport.Fingers(back: 50)
        hand.open()
        hand.touch(.moved, 0.38)
        #expect(hand.overlay.haptics == [.levelChange])
    }

    @Test
    func recognizerHoldOpensTheListWithAHaptic() {
        var hand = HistorySwipeOverlaySupport.Fingers(back: 50)
        hand.open()
        hand.touch(.moved, 0.38)
        hand.clock()
        #expect(hand.overlay.haptics == [.levelChange, .generic] && hand.overlay.model.listOpen)
    }

    @Test
    func recognizerHoldHighlightsTheCurrentPage() throws {
        var hand = HistorySwipeOverlaySupport.Fingers(back: 50)
        hand.open()
        hand.touch(.moved, 0.38)
        hand.clock()
        let list = try #require(hand.overlay.frame?.list)
        #expect(hand.overlay.model.selection == 0 && HistorySwipeOverlaySupport.close(list.row(0), list.highlight))
    }

    @Test
    func recognizerRowTravelProducesOneHapticPerRow() {
        var hand = HistorySwipeOverlaySupport.Fingers(back: 50)
        hand.open()
        hand.touch(.moved, 0.38)
        hand.clock()
        hand.touch(.moved, 0.38, 0.70)
        hand.touch(.moved, 0.38, 0.88)
        #expect(hand.overlay.model.selection == 4 && hand.overlay.haptics.filter { $0 == .alignment }.count == 4)
    }

    @Test
    func recognizerRemainderReachesTheOverlay() {
        var hand = HistorySwipeOverlaySupport.Fingers(back: 50)
        hand.open()
        hand.touch(.moved, 0.38)
        hand.clock()
        hand.touch(.moved, 0.38, 0.70)
        hand.touch(.moved, 0.38, 0.88)
        #expect(abs(hand.overlay.model.remainder - 0.75) < 1e-9)
    }

    @Test
    func edgeScrollingVisitsEveryRowAndHighlightsTheOldest() throws {
        var hand = HistorySwipeOverlaySupport.Fingers(back: 50)
        hand.open()
        hand.touch(.moved, 0.38)
        hand.clock()
        hand.touch(.moved, 0.38, 0.70)
        hand.touch(.moved, 0.38, 0.88)
        hand.scrollToHistoryEdge()
        hand.overlay.settle()
        #expect(hand.overlay.model.selection == 50 && hand.overlay.haptics.filter { $0 == .alignment }.count == 50)
        let list = try #require(hand.overlay.frame?.list)
        #expect(HistorySwipeOverlaySupport.close(list.row(50), list.highlight))
    }

    @Test
    func releasingAtTheEdgeCommitsTheOldestEntry() {
        var hand = HistorySwipeOverlaySupport.Fingers(back: 50)
        hand.open()
        hand.touch(.moved, 0.38)
        hand.clock()
        hand.touch(.moved, 0.38, 0.70)
        hand.touch(.moved, 0.38, 0.88)
        hand.scrollToHistoryEdge()
        hand.overlay.settle()
        hand.touch(.ended, 0.38)
        #expect(hand.recognizer.state == .completed)
        #expect(hand.commits == [.entry(.back, distance: 50)])
    }

    @Test
    func theListCollapsesAfterTheOldestEntryCommits() {
        var hand = HistorySwipeOverlaySupport.Fingers(back: 50)
        hand.open()
        hand.touch(.moved, 0.38)
        hand.clock()
        hand.touch(.moved, 0.38, 0.70)
        hand.touch(.moved, 0.38, 0.88)
        hand.scrollToHistoryEdge()
        hand.overlay.settle()
        hand.touch(.ended, 0.38)
        hand.overlay.advance(HistorySwipeOverlaySupport.Timing.collapse + 0.0001)
        #expect(hand.overlay.frame == nil)
    }

    @Test
    func theReducedMotionListHighlightsTheRecognizerSelection() throws {
        var hand = HistorySwipeOverlaySupport.Fingers(back: 3, reduced: true)
        hand.open()
        hand.touch(.moved, 0.38)
        hand.clock()
        hand.touch(.moved, 0.38, 0.59)
        hand.touch(.moved, 0.38, 0.67)
        hand.overlay.settle()
        let frame = try #require(hand.overlay.frame)
        let list = try #require(frame.list)
        #expect(hand.recognizer.selection == 2 && frame.opacity == 1 && HistorySwipeOverlaySupport.close(list.row(2), list.highlight))
    }

    @Test
    func backingOffClosesBothTheRecognizerListAndOverlay() {
        var hand = HistorySwipeOverlaySupport.Fingers(back: 3, reduced: true)
        hand.open()
        hand.touch(.moved, 0.38)
        hand.clock()
        hand.touch(.moved, 0.38, 0.59)
        hand.touch(.moved, 0.38, 0.67)
        hand.overlay.settle()
        hand.touch(.moved, 0.3096, 0.67)
        #expect(hand.recognizer.state == .tracking && !hand.overlay.model.listOpen && hand.overlay.frame?.list == nil)
    }

    @Test
    func theReducedMotionIndicatorHidesBelowTheTravelThreshold() {
        var hand = HistorySwipeOverlaySupport.Fingers(back: 3, reduced: true)
        hand.open()
        hand.touch(.moved, 0.38)
        hand.clock()
        hand.touch(.moved, 0.38, 0.59)
        hand.touch(.moved, 0.38, 0.67)
        hand.overlay.settle()
        hand.touch(.moved, 0.3096, 0.67)
        hand.overlay.settle()
        #expect(hand.overlay.frame?.opacity == 0)
    }

    @Test
    func releasingAfterBackingOffNavigatesNowhere() {
        var hand = HistorySwipeOverlaySupport.Fingers(back: 3, reduced: true)
        hand.open()
        hand.touch(.moved, 0.38)
        hand.clock()
        hand.touch(.moved, 0.38, 0.59)
        hand.touch(.moved, 0.38, 0.67)
        hand.overlay.settle()
        hand.touch(.moved, 0.3096, 0.67)
        hand.touch(.ended, 0.3096)
        #expect(hand.commits.isEmpty && hand.outputs.last == .cancel)
    }

    @Test
    func rearmingUnderReduceMotionReopensOnTheCurrentPage() throws {
        var back = HistorySwipeOverlaySupport.Fingers(back: 3, reduced: true)
        back.open()
        back.touch(.moved, 0.38)
        back.clock()
        back.touch(.moved, 0.38, 0.59)
        back.touch(.moved, 0.36, 0.59)
        back.touch(.moved, 0.385, 0.59)
        back.clock()
        back.overlay.settle()
        let frame = try #require(back.overlay.frame)
        let list = try #require(frame.list)
        #expect(back.overlay.model.listOpen && frame.opacity == 1 && HistorySwipeOverlaySupport.close(list.row(0), list.highlight))
    }

    @Test
    func releasingImmediatelyAfterReopeningCancels() {
        var back = HistorySwipeOverlaySupport.Fingers(back: 3, reduced: true)
        back.open()
        back.touch(.moved, 0.38)
        back.clock()
        back.touch(.moved, 0.38, 0.59)
        back.touch(.moved, 0.36, 0.59)
        back.touch(.moved, 0.385, 0.59)
        back.clock()
        back.overlay.settle()
        back.touch(.ended, 0.385)
        #expect(back.commits.isEmpty && back.outputs.last == .cancel)
    }
}
