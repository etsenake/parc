import CoreGraphics
import Foundation
import Testing
@testable import ParcCore

struct PageContentResizeTests {
    typealias R = PageContentResizeReasons
    typealias H = PageContentResizeHold
    private let bounds = CGRect(x: 0, y: 0, width: 700, height: 600)
    private func size(_ width: CGFloat, _ height: CGFloat = 600) -> CGSize { CGSize(width: width, height: height) }

    private func throttled(at width: CGFloat = 800) -> H {
        var hold = H()
        hold.setMode(.throttle, frameSize: size(width))
        return hold
    }

    private func holding780() -> H {
        var hold = throttled()
        hold.didApply(frameSize: size(800), lastReport: size(780))
        hold.acknowledge(size(800))
        hold.didApply(frameSize: size(780), lastReport: size(800))
        return hold
    }

    @Test func eachReasonHasItsOwnBit() {
        #expect(R.windowResize.rawValue == 1)
        #expect(R.splitDividerResize.rawValue == 2)
        #expect(R.splitInteractiveEditing.rawValue == 4)
        #expect(R.sidebarResize.rawValue == 8)
        #expect(R.frameAdjust.rawValue == 0x10)
    }

    @Test func noReasonIsIntrinsic() {
        #expect(R().mode == .intrinsic)
    }

    @Test(arguments: [R.sidebarResize, .windowResize, .splitDividerResize, .frameAdjust])
    func eachNonLockingReasonThrottles(reason: R) {
        #expect(reason.mode == .throttle)
    }

    @Test func reasonsCombineIntoThrottle() {
        #expect(R([.sidebarResize, .windowResize]).mode == .throttle)
    }

    @Test(arguments: [R.sidebarResize, .windowResize, .splitDividerResize, .frameAdjust])
    func interactiveEditingLocksOverEveryThrottleReason(reason: R) {
        #expect(R([reason, .splitInteractiveEditing]).mode == .locked)
    }

    @Test func interactiveEditingAloneLocks() {
        #expect(R.splitInteractiveEditing.mode == .locked)
    }

    @Test func theHoldQueuesOneFrameWithAToleranceOfAPointFiveTenThousandth() {
        #expect(H.maxPendingFrames == 1)
        #expect(H.tolerance == 1.00001)
    }

    @Test func aSizeWithinToleranceDoesNotDiffer() {
        #expect(!H.differs(size(800), size(801.00001)))
    }

    @Test(arguments: [(800.0, 600.0, 801.00002, 600.0), (800.0, 600.0, 800.0, 602.0)])
    func aSizeBeyondToleranceInEitherDimensionDiffers(w1: Double, h1: Double, w2: Double, h2: Double) {
        #expect(H.differs(size(w1, h1), size(w2, h2)))
    }

    @Test func anIntrinsicHoldFillsTheContent() {
        let hold = H()
        #expect(hold.mode == .intrinsic)
        #expect(hold.frame(in: bounds) == bounds)
    }

    @Test func anIntrinsicHoldKeepsNoPendingFrames() {
        var hold = H()
        hold.didApply(frameSize: size(700), lastReport: size(500))
        #expect(hold.pendingFrames.isEmpty)
        #expect(hold.lockedSize == nil)
    }

    @Test func anUnchangedModeNeedsNoLayout() {
        var hold = H()
        let needsLayout = hold.setMode(.intrinsic, frameSize: size(700))
        #expect(!needsLayout)
    }

    @Test func enteringThrottleNeedsLayoutAndHoldsNothingYet() {
        var hold = H()
        let needsLayout = hold.setMode(.throttle, frameSize: size(800))
        #expect(needsLayout)
        #expect(hold.lockedSize == nil)
    }

    @Test func aChangeWithinAPointFollowsLive() {
        var hold = throttled()
        hold.didApply(frameSize: size(801), lastReport: size(800))
        #expect(hold.pendingFrames.isEmpty)
        #expect(hold.lockedSize == nil)
    }

    @Test func anEmptyQueueComparesWithTheLatestReport() {
        var hold = throttled()
        hold.didApply(frameSize: size(800), lastReport: size(780))
        #expect(hold.pendingFrames == [size(800)])
        #expect(hold.lockedSize == size(800))
    }

    @Test func oneUnreportedSizeHoldsThePage() {
        let hold = holding780()
        #expect(hold.pendingFrames == [size(780)])
        #expect(hold.lockedSize == size(780))
    }

    @Test func theHoldKeepsTheTopLeadingCorner() {
        #expect(holding780().frame(in: bounds) == CGRect(x: 0, y: 0, width: 780, height: 600))
    }

    @Test func aHeldPageKeepsItsSizeInALargerOrShorterContainer() {
        #expect(holding780().frame(in: CGRect(x: 0, y: 30, width: 900, height: 500)) == CGRect(x: 0, y: 30, width: 780, height: 600))
    }

    @Test func aHeldPageQueuesNothingMore() {
        var hold = holding780()
        hold.didApply(frameSize: size(780), lastReport: size(10))
        #expect(hold.pendingFrames == [size(780)])
    }

    @Test func theMatchingReportReleasesTheHold() {
        var hold = holding780()
        hold.acknowledge(size(780.4))
        #expect(hold.pendingFrames.isEmpty)
        #expect(hold.lockedSize == nil)
    }

    @Test func theNextSizeHoldsAgainAfterARelease() {
        var hold = holding780()
        hold.acknowledge(size(780.4))
        hold.didApply(frameSize: size(700), lastReport: size(780))
        #expect(hold.lockedSize == size(700))
    }

    @Test func aReportThatMatchesNothingDropsEveryFrameAndReleases() {
        var hold = holding780()
        hold.acknowledge(size(1200))
        #expect(hold.pendingFrames.isEmpty)
        #expect(hold.lockedSize == nil)
    }

    private func queuedBehindALeftThrottle() -> H {
        var hold = H()
        hold.setMode(.throttle, frameSize: size(900))
        hold.didApply(frameSize: size(880), lastReport: size(900))
        hold.setMode(.intrinsic, frameSize: size(880))
        return hold
    }

    @Test func leavingThrottleDropsTheHoldNotTheQueue() {
        let hold = queuedBehindALeftThrottle()
        #expect(hold.lockedSize == nil)
        #expect(hold.pendingFrames == [size(880)])
    }

    @Test func aStaleFrameIsTheBaselineForTheNextSize() {
        var hold = queuedBehindALeftThrottle()
        hold.setMode(.throttle, frameSize: size(880))
        hold.didApply(frameSize: size(860), lastReport: size(870))
        #expect(hold.pendingFrames == [size(880), size(860)])
        #expect(hold.lockedSize == size(860))
    }

    @Test func aMatchKeepsTheNewerFrames() {
        var hold = queuedBehindALeftThrottle()
        hold.setMode(.throttle, frameSize: size(880))
        hold.didApply(frameSize: size(860), lastReport: size(870))
        hold.acknowledge(size(880))
        #expect(hold.pendingFrames == [size(860)])
        #expect(hold.lockedSize == nil)
    }

    @Test func aLaterReportDrainsTheRest() {
        var hold = queuedBehindALeftThrottle()
        hold.setMode(.throttle, frameSize: size(880))
        hold.didApply(frameSize: size(860), lastReport: size(870))
        hold.acknowledge(size(880))
        hold.acknowledge(size(860))
        #expect(hold.pendingFrames.isEmpty)
    }

    @Test func lockingHoldsTheCurrentSize() {
        var hold = H()
        let needsLayout = hold.setMode(.locked, frameSize: size(640))
        #expect(needsLayout)
        #expect(hold.lockedSize == size(640))
    }

    @Test func aLockedHoldQueuesNothing() {
        var hold = H()
        hold.setMode(.locked, frameSize: size(640))
        hold.didApply(frameSize: size(640), lastReport: size(10))
        #expect(hold.pendingFrames.isEmpty)
        #expect(hold.frame(in: bounds).size == size(640))
    }

    @Test func throttleReplacesALock() {
        var hold = H()
        hold.setMode(.locked, frameSize: size(640))
        hold.setMode(.throttle, frameSize: size(640))
        #expect(hold.lockedSize == nil)
    }

    @Test func unlockingFillsTheContentAgain() {
        var hold = H()
        hold.setMode(.locked, frameSize: size(620))
        hold.setMode(.intrinsic, frameSize: size(620))
        #expect(hold.lockedSize == nil)
        #expect(hold.frame(in: bounds) == bounds)
    }

    @Test func theViewportPageSizeAddsBackDockedChrome() {
        #expect(H.pageSize(ofViewport: size(700, 560), page: size(1000, 600), renderer: size(700, 560)) == size(1000, 600))
    }

    @Test func anOlderFrameKeepsItsOwnPageSize() {
        #expect(H.pageSize(ofViewport: size(690, 560), page: size(1000, 600), renderer: size(700, 560)) == size(990, 600))
    }

    @Test func noFrameYetStaysZero() {
        #expect(H.pageSize(ofViewport: .zero, page: size(1000), renderer: size(700)) == .zero)
    }
}
