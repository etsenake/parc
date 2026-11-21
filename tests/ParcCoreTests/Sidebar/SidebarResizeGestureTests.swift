import Foundation
import Testing
@testable import ParcCore

struct SidebarResizeGestureTests {
    typealias G = SidebarResizeGesture

    private func hiddenPreview() -> G {
        var gesture = G(width: 200, locked: true)
        _ = gesture.change(translationX: -118.6, velocityX: -900, now: 0)
        return gesture
    }

    private func armed() -> G {
        var gesture = G(width: 300, locked: true)
        _ = gesture.change(translationX: -30, velocityX: -200, now: 1)
        return gesture
    }

    private func snapped() -> G {
        var gesture = armed()
        _ = gesture.change(translationX: -63, velocityX: 10, now: 2)
        return gesture
    }

    private func snappedAgainAtThree() -> G {
        var gesture = snapped()
        _ = gesture.change(translationX: -86, velocityX: -900, now: 2.3)
        _ = gesture.change(translationX: -77, velocityX: -10, now: 3)
        return gesture
    }

    private func snappedAgainAtFour() -> G {
        var gesture = snappedAgainAtThree()
        _ = gesture.change(translationX: -58, velocityX: 0, now: 3.5)
        _ = gesture.change(translationX: -63, velocityX: 0, now: 4)
        return gesture
    }

    @Test func theMinimumAndMaximumWidthsAndTheCollapseThresholdAreFixed() {
        #expect(G.minimumWidth == 164)
        #expect(G.maximumWidth == 500)
        #expect(G.collapseThreshold == 82)
    }

    @Test func theDefaultDetentHasItsWidthBandAndVelocityLimit() {
        #expect(G.defaultWidth == 8 + 8 + 4 * 47 + 3 * 8)
        #expect(G.snapBand == 14)
        #expect(G.snapMaximumVelocity == 50)
    }

    @Test func theReleaseFeedbackHoldsForHalfASecond() {
        #expect(G.releaseFeedbackHold == 0.5)
    }

    @Test func aNewGestureIsUnarmedAtTheStoreWidth() {
        let gesture = G(width: 300, locked: true)
        #expect(!gesture.canSnap)
        #expect(!gesture.isSnapped)
        #expect(gesture.effectiveWidth == 300)
    }

    @Test(arguments: [(0.5, 301.0), (0.49, 300.0), (400.0, 500.0)])
    func theDragWidthRoundsTiesAwayFromZeroAndStopsAtTheMaximum(translation: Double, expected: Double) {
        var gesture = G(width: 300, locked: true)
        #expect(gesture.change(translationX: translation, velocityX: 0, now: 0).width == expected)
    }

    @Test(arguments: [-36.5, -118.0])
    func aDragBelowTheMinimumClampsToItWithoutPreviewingHidden(translation: Double) {
        var gesture = G(width: 200, locked: true)
        let result = gesture.change(translationX: translation, velocityX: 0, now: 0)
        #expect(result.width == 164)
        #expect(!gesture.isPreviewingHidden)
    }

    @Test func releasingExactlyAtTheCollapseThresholdCollapses() {
        var gesture = G(width: 200, locked: true)
        _ = gesture.change(translationX: -118, velocityX: 0, now: 0)
        #expect(gesture.end(.ended, translationX: -118).collapses)
    }

    @Test func draggingBelowTheCollapseThresholdPreviewsHiddenOnce() {
        var gesture = G(width: 200, locked: true)
        let result = gesture.change(translationX: -118.6, velocityX: -900, now: 0)
        #expect(result.width == 0)
        #expect(result.events == [.previewHiddenChanged(true)])
        #expect(gesture.isPreviewingHidden)
    }

    @Test func stayingHiddenRepeatsNoEvent() {
        var gesture = hiddenPreview()
        #expect(gesture.change(translationX: -150, velocityX: -900, now: 0).events.isEmpty)
    }

    @Test func anUnchangedHiddenWidthNeedsNoRelayout() {
        var gesture = hiddenPreview()
        #expect(gesture.change(translationX: -150, velocityX: 0, now: 0) == .init(width: 0, widthChanged: false, events: []))
    }

    @Test func releasingAHiddenPreviewInALockedSidebarCommitsTheStartWidthAndCollapses() {
        let gesture = hiddenPreview()
        #expect(gesture.end(.ended, translationX: -150) == .init(width: 200, collapses: true))
    }

    @Test func leavingTheHiddenPreviewPublishesOnce() {
        var gesture = hiddenPreview()
        let result = gesture.change(translationX: -30, velocityX: 900, now: 0)
        #expect(result.width == 170)
        #expect(result.events == [.previewHiddenChanged(false)])
    }

    @Test func anOrdinaryReleaseCommitsTheEffectiveWidth() {
        var gesture = hiddenPreview()
        _ = gesture.change(translationX: -30, velocityX: 900, now: 0)
        #expect(gesture.end(.ended, translationX: -30) == .init(width: 170, collapses: false))
    }

    @Test func aFloatingDragPreviewsHiddenToo() {
        var gesture = G(width: 200, locked: false)
        _ = gesture.change(translationX: -190, velocityX: 0, now: 0)
        #expect(gesture.isPreviewingHidden)
    }

    @Test func aFloatingReleaseClampsWithoutCollapsing() {
        var gesture = G(width: 200, locked: false)
        _ = gesture.change(translationX: -190, velocityX: 0, now: 0)
        #expect(gesture.end(.ended, translationX: -190) == .init(width: 164, collapses: false))
    }

    @Test(arguments: [(G.Completion.cancelled, -150.0), (.failed, 300.0)])
    func aCancelledOrFailedDragRestoresTheStartWidth(completion: G.Completion, translation: Double) {
        let gesture = hiddenPreview()
        #expect(gesture.end(completion, translationX: translation) == .init(width: 200, collapses: false))
    }

    @Test func aRestoredWidthIsClamped() {
        #expect(G(width: 600, locked: true).end(.cancelled, translationX: 0).width == 500)
    }

    @Test func anUnarmedBandPassesTheDragThrough() {
        var gesture = G(width: 230, locked: true)
        #expect(gesture.change(translationX: -1, velocityX: -10, now: 0) == .init(width: 229, widthChanged: true, events: []))
        #expect(!gesture.canSnap)
    }

    @Test func leavingTheBandArmsTheSnap() {
        var gesture = G(width: 230, locked: true)
        let result = gesture.change(translationX: 12, velocityX: 10, now: 0)
        #expect(result.width == 242)
        #expect(gesture.canSnap)
    }

    @Test func draggingOutsideTheBandArmsTheSnap() {
        #expect(armed().canSnap)
    }

    @Test func aVelocityAtTheMaximumSkipsTheSnap() {
        var gesture = armed()
        #expect(gesture.change(translationX: -70, velocityX: -50, now: 1).width == 230)
        #expect(!gesture.isSnapped)
    }

    @Test func movingLeftAboveTheDefaultDoesNotSnap() {
        var gesture = armed()
        #expect(gesture.change(translationX: -62, velocityX: -10, now: 1).width == 238)
        #expect(!gesture.isSnapped)
    }

    @Test func movingRightAboveTheDefaultSnapsToIt() {
        var gesture = armed()
        let result = gesture.change(translationX: -63, velocityX: 10, now: 2)
        #expect(result == .init(width: 228, widthChanged: true, events: [.snapEngaged]))
        #expect(gesture.isSnapped)
    }

    @Test func theSnapRecordsWhenItEngaged() {
        #expect(snapped().timeOfSnap == 2)
    }

    @Test func aSnappedGestureHoldsWithinTheBandAtAnyVelocity() {
        var gesture = snapped()
        #expect(gesture.change(translationX: -60, velocityX: 900, now: 2.1) == .init(width: 228, widthChanged: false, events: []))
    }

    @Test func aSnappedGestureHoldsOnTheOtherSideOfTheDefault() {
        var gesture = snapped()
        #expect(gesture.change(translationX: -85, velocityX: -900, now: 2.2).width == 228)
    }

    @Test func aShortHoldReleasesTheSnapWithoutAHaptic() {
        var gesture = snapped()
        let result = gesture.change(translationX: -86, velocityX: -900, now: 2.3)
        #expect(result == .init(width: 214, widthChanged: true, events: [.snapReleased(haptic: false)]))
        #expect(!gesture.isSnapped)
    }

    @Test func movingLeftBelowTheDefaultSnapsAfterARelease() {
        var gesture = snapped()
        _ = gesture.change(translationX: -86, velocityX: -900, now: 2.3)
        let again = gesture.change(translationX: -77, velocityX: -10, now: 3)
        #expect(again.width == 228)
        #expect(again.events == [.snapEngaged])
    }

    @Test func aSnapHoldsWhileTheDragStaysInsideTheReleaseBand() {
        var gesture = snappedAgainAtThree()
        #expect(gesture.change(translationX: -73, velocityX: 0, now: 3.5).width == 228)
    }

    @Test func exactlyHalfASecondIsNotLongerThanTheHold() {
        var gesture = snappedAgainAtThree()
        #expect(gesture.change(translationX: -58, velocityX: 0, now: 3.5).events == [.snapReleased(haptic: false)])
    }

    @Test func zeroVelocityAboveTheDefaultSnaps() {
        var gesture = snappedAgainAtThree()
        _ = gesture.change(translationX: -58, velocityX: 0, now: 3.5)
        _ = gesture.change(translationX: -63, velocityX: 0, now: 4)
        #expect(gesture.isSnapped)
    }

    @Test func aHoldLongerThanHalfASecondReleasesWithAHaptic() {
        var gesture = snappedAgainAtFour()
        let late = gesture.change(translationX: -40, velocityX: 0, now: 4.51)
        #expect(late.width == 260)
        #expect(late.events == [.snapReleased(haptic: true)])
    }

    @Test func aSnapReleaseFiresOnce() {
        var gesture = snappedAgainAtFour()
        _ = gesture.change(translationX: -40, velocityX: 0, now: 4.51)
        #expect(gesture.change(translationX: -40, velocityX: 0, now: 5).events.isEmpty)
    }

    @Test func releasingAfterASnapReleaseCommitsTheLiveWidth() {
        var gesture = snappedAgainAtFour()
        _ = gesture.change(translationX: -40, velocityX: 0, now: 4.51)
        #expect(gesture.end(.ended, translationX: -40) == .init(width: 260, collapses: false))
    }

    @Test func releasingWhileSnappedCommitsTheDefault() {
        var gesture = G(width: 300, locked: true)
        _ = gesture.change(translationX: -30, velocityX: 0, now: 0)
        _ = gesture.change(translationX: -66, velocityX: 0, now: 0)
        #expect(gesture.end(.ended, translationX: -66) == .init(width: 228, collapses: false))
    }

    @Test func diveFromASnapReleasesItBeforePreviewingHidden() {
        var gesture = G(width: 300, locked: true)
        _ = gesture.change(translationX: -30, velocityX: 0, now: 0)
        _ = gesture.change(translationX: -66, velocityX: 0, now: 0)
        let dived = gesture.change(translationX: -280, velocityX: -900, now: 1)
        #expect(dived.events == [.snapReleased(haptic: true), .previewHiddenChanged(true)])
        #expect(dived.width == 0)
    }

    @Test(arguments: [(99.0, 0), (100.0, 1), (300.0, 2)])
    func aWidthMapsToTheBreakpointItHasReached(width: Double, expected: Int) {
        #expect(G.breakpointIndex(for: width, in: [100, 200]) == expected)
    }

    @Test func noBreakpointsMeansIndexZero() {
        #expect(G.breakpointIndex(for: 50, in: []) == 0)
    }

    @Test func aGestureStartsAtTheBreakpointOfItsWidth() {
        #expect(G(width: 150, locked: false, breakpoints: [100, 200]).breakpointIndex == 1)
    }

    @Test func stayingInTheSameBreakpointIsSilent() {
        var gesture = G(width: 150, locked: false, breakpoints: [100, 200])
        #expect(gesture.change(translationX: 10, velocityX: 0, now: 0).events.isEmpty)
    }

    @Test func crossingABreakpointPublishesIt() {
        var gesture = G(width: 150, locked: false, breakpoints: [100, 200])
        #expect(gesture.change(translationX: 60, velocityX: 0, now: 0).events == [.breakpointChanged(2)])
    }

    @Test func aHiddenPreviewIsBelowTheFirstBreakpoint() {
        var gesture = G(width: 150, locked: false, breakpoints: [100, 200])
        #expect(gesture.change(translationX: -140, velocityX: 0, now: 0).events == [.previewHiddenChanged(true), .breakpointChanged(0)])
    }

    @Test func aNonFiniteTranslationIsIgnored() {
        var gesture = G(width: 240, locked: true)
        #expect(gesture.change(translationX: .nan, velocityX: 0, now: 0) == .init(width: 240, widthChanged: false, events: []))
    }

    @Test func aNonFiniteVelocityIsIgnored() {
        var gesture = G(width: 240, locked: true)
        #expect(gesture.change(translationX: 0, velocityX: .infinity, now: 0).width == 240)
    }

    @Test func aNonFiniteReleaseDoesNotCollapse() {
        let gesture = G(width: 240, locked: true)
        #expect(gesture.end(.ended, translationX: .nan) == .init(width: 240, collapses: false))
    }
}
