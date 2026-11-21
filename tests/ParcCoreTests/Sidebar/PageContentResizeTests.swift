import CoreGraphics
import Foundation
import Testing
@testable import ParcCore

struct PageContentResizeTests {
    typealias R = PageContentResizeReasons
    typealias H = PageContentResizeHold
    let bounds = CGRect(x: 0, y: 0, width: 700, height: 600)
    func size(_ width: CGFloat, _ height: CGFloat = 600) -> CGSize { CGSize(width: width, height: height) }

    @Test func resizeReasonsCombineIntoIntrinsicThrottleOrLockedModes() {
        typealias R = PageContentResizeReasons
        typealias H = PageContentResizeHold
        #expect(R.windowResize.rawValue == 1 && R.splitDividerResize.rawValue == 2
              && R.splitInteractiveEditing.rawValue == 4 && R.sidebarResize.rawValue == 8, "recovered bit values")
        #expect(R().mode == .intrinsic, "no reason is intrinsic")
        #expect(R.sidebarResize.mode == .throttle && R.windowResize.mode == .throttle && R.splitDividerResize.mode == .throttle,
              "each non-locking reason throttles")
        #expect(R([.sidebarResize, .windowResize]).mode == .throttle, "reasons combine")
        #expect(R.frameAdjust.rawValue == 0x10 && R.frameAdjust.mode == .throttle, "turning the window crank throttles pages")
        #expect(R([.frameAdjust, .splitInteractiveEditing]).mode == .locked, "interactive editing still locks over the crank")
        #expect(R.splitInteractiveEditing.mode == .locked && R([.splitInteractiveEditing, .sidebarResize]).mode == .locked,
              "interactive editing locks over every throttle reason")
        #expect(H.maxPendingFrames == 1 && H.tolerance == 1.00001, "recovered flag default and tolerance")
        #expect(!H.differs(size(800), size(801.00001)) && H.differs(size(800), size(801.00002))
              && H.differs(size(800, 600), size(800, 602)), "tolerance is strict in either dimension")
    }

    @Test func theHoldIsIntrinsicUntilThrottledQueuesUnreportedSizesAndReleasesOnTheMatchingReport() {
        var hold = H()
        #expect(hold.mode == .intrinsic && hold.frame(in: bounds) == bounds, "intrinsic fills the content")
        hold.didApply(frameSize: size(700), lastReport: size(500))
        #expect(hold.pendingFrames.isEmpty && hold.lockedSize == nil, "intrinsic keeps no pending frames")
        let r1 = hold.setMode(.intrinsic, frameSize: size(700))
        #expect(!r1, "an unchanged mode does nothing")

        let r2 = hold.setMode(.throttle, frameSize: size(800))
        #expect(r2, "entering throttle needs layout")
        #expect(hold.lockedSize == nil, "entering throttle holds nothing yet")
        hold.didApply(frameSize: size(801), lastReport: size(800))
        #expect(hold.pendingFrames.isEmpty && hold.lockedSize == nil, "a change within a point follows live")
        hold.didApply(frameSize: size(800), lastReport: size(780))
        #expect(hold.pendingFrames == [size(800)] && hold.lockedSize == size(800), "an empty queue compares with the latest report")
        hold.acknowledge(size(800))
        hold.didApply(frameSize: size(780), lastReport: size(800))
        #expect(hold.pendingFrames == [size(780)] && hold.lockedSize == size(780), "one unreported size holds the page")
        #expect(hold.frame(in: bounds) == CGRect(x: 0, y: 0, width: 780, height: 600), "the hold keeps the top-leading corner")
        #expect(hold.frame(in: CGRect(x: 0, y: 30, width: 900, height: 500)) == CGRect(x: 0, y: 30, width: 780, height: 600),
              "a held page keeps its size in a larger or shorter container")
        hold.didApply(frameSize: size(780), lastReport: size(10))
        #expect(hold.pendingFrames == [size(780)], "a held page queues nothing")

        hold.acknowledge(size(780.4))
        #expect(hold.pendingFrames.isEmpty && hold.lockedSize == nil, "the matching report releases the hold")
        hold.didApply(frameSize: size(700), lastReport: size(780))
        #expect(hold.lockedSize == size(700), "the next size holds again")
        hold.acknowledge(size(1200))
        #expect(hold.pendingFrames.isEmpty && hold.lockedSize == nil, "a report that matches nothing drops every frame and releases")
    }

    @Test func leavingThrottleDropsTheHoldNotTheQueue() {
        var queued = H()
        queued.setMode(.throttle, frameSize: size(900))
        queued.didApply(frameSize: size(880), lastReport: size(900))
        queued.setMode(.intrinsic, frameSize: size(880))
        #expect(queued.lockedSize == nil && queued.pendingFrames == [size(880)], "leaving throttle drops the hold, not the queue")
        queued.setMode(.throttle, frameSize: size(880))
        queued.didApply(frameSize: size(860), lastReport: size(870))
        #expect(queued.pendingFrames == [size(880), size(860)] && queued.lockedSize == size(860),
              "a stale frame is the baseline for the next size")
        queued.acknowledge(size(880))
        #expect(queued.pendingFrames == [size(860)] && queued.lockedSize == nil, "a match keeps the newer frames")
        queued.acknowledge(size(860))
        #expect(queued.pendingFrames.isEmpty, "a later report drains the rest")
    }

    @Test func lockingHoldsTheCurrentSizeAndQueuesNothing() {
        var locked = H()
        let r3 = locked.setMode(.locked, frameSize: size(640))
        #expect(r3 && locked.lockedSize == size(640), "locking holds the current size")
        locked.didApply(frameSize: size(640), lastReport: size(10))
        #expect(locked.pendingFrames.isEmpty && locked.frame(in: bounds).size == size(640), "locked queues nothing")
        locked.setMode(.throttle, frameSize: size(640))
        #expect(locked.lockedSize == nil, "throttle replaces a lock")
        locked.setMode(.locked, frameSize: size(620))
        locked.setMode(.intrinsic, frameSize: size(620))
        #expect(locked.lockedSize == nil && locked.frame(in: bounds) == bounds, "unlocking fills the content again")
    }

    @Test func theViewportPageSizeAddsBackDockedChrome() {
        #expect(H.pageSize(ofViewport: size(700, 560), page: size(1000, 600), renderer: size(700, 560)) == size(1000, 600),
              "docked chrome around the renderer is added back")
        #expect(H.pageSize(ofViewport: size(690, 560), page: size(1000, 600), renderer: size(700, 560)) == size(990, 600),
              "an older frame keeps its own size")
        #expect(H.pageSize(ofViewport: .zero, page: size(1000), renderer: size(700)) == .zero, "no frame yet stays zero")

    }
}
