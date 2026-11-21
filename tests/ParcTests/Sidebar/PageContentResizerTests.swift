import AppKit
import QuartzCore
import Testing
@testable import Parc

private final class FakePage: NSView, RenderFrameReporting {
    final class Lease: RenderFrameObservation {
        var handler: ((CGSize) -> Void)?
        func invalidate() { handler = nil }
    }

    var reports = true
    var viewport = CGSize.zero
    private(set) var leases: [Lease] = []
    private(set) var sentSizes: [CGSize] = []
    override var isFlipped: Bool { true }

    override func setFrameSize(_ newSize: NSSize) {
        if newSize != frame.size { sentSizes.append(newSize) }
        super.setFrameSize(newSize)
    }

    var renderFrameViewport: CGSize { reports ? viewport : .zero }

    func observeRenderFrameViewport(_ handler: @escaping (CGSize) -> Void) -> RenderFrameObservation? {
        guard reports else { return nil }
        let lease = Lease()
        lease.handler = handler
        leases.append(lease)
        return lease
    }

    var liveLeases: Int { leases.filter { $0.handler != nil }.count }
    func emit(_ size: CGSize) { viewport = size; leases.forEach { $0.handler?(size) } }
    func drawn() { emit(frame.size) }
}

private final class Content: NSView {
    var onLayout: (() -> Void)?
    var layouts = 0
    override var isFlipped: Bool { true }
    override func layout() { super.layout(); layouts += 1; onLayout?() }
}

private final class FillingChild: NSView {
    var layouts = 0
    override func layout() {
        super.layout()
        layouts += 1
        frame = superview?.bounds ?? frame
    }
}

@MainActor
struct PageContentResizerTests {
    private func size(_ width: CGFloat, _ height: CGFloat = 600) -> CGSize { CGSize(width: width, height: height) }

    @MainActor private final class Resizing {
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 1200, height: 700),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 1200, height: 700))
        let content = Content(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        let resizer = PageContentResizer()
        var page: FakePage
        let ownClipping: Bool

        init() {
            window.isReleasedWhenClosed = false
            root.wantsLayer = true
            window.contentView = root
            root.addSubview(content)
            page = FakePage(frame: content.bounds)
            content.addSubview(page)
            ownClipping = content.clipsToBounds
            let resizer = self.resizer
            content.onLayout = { [unowned self] in resizer.place(page, in: content) }
            root.layoutSubtreeIfNeeded()
        }

        deinit { MainActor.assumeIsolated { window.close() } }

        func resize(_ width: CGFloat) {
            content.frame.size.width = width
            root.layoutSubtreeIfNeeded()
        }

        func throttling() -> Resizing {
            resize(700)
            page.reports = true
            page.viewport = CGSize(width: 700, height: 600)
            resizer.mode = .throttle
            root.layoutSubtreeIfNeeded()
            return self
        }
    }

    @Test func intrinsicFillsTheContent() {
        let r = Resizing()
        #expect(r.page.autoresizingMask == [.width, .height])
        #expect(r.page.frame == r.content.bounds)
    }

    @Test func intrinsicResizesAtOnce() {
        let r = Resizing()
        r.resize(760)
        #expect(r.page.frame.size == size(760))
        #expect(r.resizer.hold.pendingFrames.isEmpty)
    }

    @Test func hostedViewsThatSizeInLayoutFollowThePageImmediately() {
        let r = Resizing()
        let filler = FillingChild(frame: NSRect(x: 0, y: 0, width: 1, height: 1))
        r.page.addSubview(filler)
        r.resizer.place(r.page, in: r.content)
        #expect(filler.frame.size == r.page.frame.size)
    }

    @Test func anUnchangedPageSizeDoesNotRelayoutTheHostedSubtree() {
        let r = Resizing()
        let filler = FillingChild(frame: NSRect(x: 0, y: 0, width: 1, height: 1))
        r.page.addSubview(filler)
        r.resizer.place(r.page, in: r.content)
        let hostedLayouts = filler.layouts
        r.resizer.place(r.page, in: r.content)
        #expect(filler.layouts == hostedLayouts)
        #expect(filler.frame.size == r.page.frame.size)
    }

    @Test func aDirectHostedChildThatNoLongerFillsStillFlushesInTheSamePass() {
        let r = Resizing()
        let filler = FillingChild(frame: NSRect(x: 0, y: 0, width: 1, height: 1))
        r.page.addSubview(filler)
        r.resizer.place(r.page, in: r.content)
        let hostedLayouts = filler.layouts
        filler.frame = NSRect(x: 0, y: 0, width: 1, height: 1)
        filler.needsLayout = false
        r.resizer.place(r.page, in: r.content)
        #expect(filler.frame.size == r.page.frame.size)
        #expect(filler.layouts == hostedLayouts + 1)
    }

    @Test func aLaterSizeIsPushedIntoTheHostedSubtreeInTheSamePass() {
        let r = Resizing()
        let filler = FillingChild(frame: NSRect(x: 0, y: 0, width: 1, height: 1))
        r.page.addSubview(filler)
        r.resizer.place(r.page, in: r.content)
        let afterFill = filler.layouts
        r.content.frame.size.width = 740
        r.resizer.place(r.page, in: r.content)
        #expect(filler.frame.width == 740)
        #expect(filler.frame.size == r.page.frame.size)
        #expect(filler.layouts == afterFill + 1)
    }

    @Test func noReportKeepsThePageIntrinsic() {
        let r = Resizing()
        r.page.reports = false
        r.resizer.mode = .throttle
        #expect(r.resizer.hold.mode == .intrinsic)
        #expect(r.page.leases.isEmpty)
    }

    @Test func withoutTheReportEverySizeReachesThePage() {
        let r = Resizing()
        r.page.reports = false
        r.resizer.mode = .throttle
        let before = r.page.sentSizes.count
        for width in stride(from: 750, through: 700, by: -10) { r.resize(CGFloat(width)) }
        #expect(r.page.sentSizes.count == before + 6)
        #expect(r.page.frame.size == size(700))
    }

    @Test func throttleSubscribesToTheRenderer() {
        let r = Resizing()
        r.page.viewport = size(700)
        r.resizer.mode = .throttle
        #expect(r.resizer.hold.mode == .throttle)
        #expect(r.page.liveLeases == 1)
    }

    @Test func enteringThrottleRelaysOut() {
        let r = Resizing()
        r.page.viewport = size(700)
        r.resizer.mode = .throttle
        #expect(r.content.needsLayout)
    }

    @Test func throttleStopsAutoresizingWithoutHoldingYet() {
        let r = Resizing().throttling()
        #expect(r.page.autoresizingMask == [])
        #expect(r.resizer.hold.lockedSize == nil)
    }

    @Test func theFirstNewSizeReachesThePageAndHolds() {
        let r = Resizing().throttling()
        r.resize(660)
        #expect(r.page.frame.size == size(660))
        #expect(r.resizer.hold.lockedSize == size(660))
    }

    @Test func aHeldPageIsClippedToItsContent() {
        let r = Resizing().throttling()
        r.resize(660)
        #expect(r.content.clipsToBounds)
    }

    @Test func unreportedSizesNeverReachThePage() {
        let r = Resizing().throttling()
        let sent = r.page.sentSizes.count
        r.resize(660)
        for width in stride(from: 650, through: 600, by: -10) { r.resize(CGFloat(width)) }
        #expect(r.page.sentSizes.count == sent + 1)
    }

    @Test func theHeldPageKeepsItsTopLeadingCorner() {
        let r = Resizing().throttling()
        r.resize(660)
        for width in stride(from: 650, through: 600, by: -10) { r.resize(CGFloat(width)) }
        #expect(r.page.frame == NSRect(x: 0, y: 0, width: 660, height: 600))
    }

    private func heldAt600(_ r: Resizing) {
        r.resize(660)
        for width in stride(from: 650, through: 600, by: -10) { r.resize(CGFloat(width)) }
    }

    @Test func theRenderersReportReleasesTheHold() {
        let r = Resizing().throttling()
        heldAt600(r)
        r.page.drawn()
        #expect(r.resizer.hold.lockedSize == nil)
        #expect(r.resizer.hold.pendingFrames.isEmpty)
    }

    @Test func aReportRelaysOut() {
        let r = Resizing().throttling()
        heldAt600(r)
        r.page.drawn()
        #expect(r.content.needsLayout)
    }

    @Test func theLatestSizeFollowsAndHoldsAgain() {
        let r = Resizing().throttling()
        let sent = r.page.sentSizes.count
        heldAt600(r)
        r.page.drawn()
        r.root.layoutSubtreeIfNeeded()
        #expect(r.page.frame.size == size(600))
        #expect(r.resizer.hold.lockedSize == size(600))
        #expect(r.page.sentSizes.count == sent + 2)
    }

    @Test func aGrowingContentKeepsTheHeldPageAtTheLeadingEdge() {
        let r = Resizing().throttling()
        heldAt600(r)
        r.page.drawn()
        r.root.layoutSubtreeIfNeeded()
        r.resize(640)
        #expect(r.page.frame == NSRect(x: 0, y: 0, width: 600, height: 600))
    }

    @Test func aReportOfAnySizeReleasesTheHold() {
        let r = Resizing().throttling()
        heldAt600(r)
        r.page.drawn()
        r.root.layoutSubtreeIfNeeded()
        r.resize(640)
        r.page.emit(size(10))
        r.root.layoutSubtreeIfNeeded()
        #expect(r.page.frame.size == size(640))
    }

    @Test func anUnchangedSizeAfterItsReportDoesNotHold() {
        let r = Resizing().throttling()
        heldAt600(r)
        r.page.drawn()
        r.root.layoutSubtreeIfNeeded()
        r.resize(640)
        r.page.emit(size(10))
        r.root.layoutSubtreeIfNeeded()
        r.page.emit(size(640))
        r.root.layoutSubtreeIfNeeded()
        #expect(r.resizer.hold.lockedSize == nil)
        #expect(r.page.frame.size == size(640))
    }

    @Test func aChangeWithinAPointFollowsLive() {
        let r = Resizing().throttling()
        r.resize(640)
        r.page.drawn()
        r.root.layoutSubtreeIfNeeded()
        r.resize(640.5)
        #expect(r.resizer.hold.lockedSize == nil)
        #expect(r.page.frame.size.width == 640.5)
    }

    @Test func aSizeIsHeldBeforeTheDragEnds() {
        let r = Resizing().throttling()
        r.resize(660)
        r.page.drawn()
        r.root.layoutSubtreeIfNeeded()
        r.resize(620)
        #expect(r.resizer.hold.lockedSize == size(620))
    }

    @Test func leavingThrottleCancelsTheSubscription() {
        let r = Resizing().throttling()
        r.resize(620)
        r.resizer.mode = .intrinsic
        #expect(r.page.liveLeases == 0)
    }

    @Test func theFinalSizeIsAppliedAfterTheDrag() {
        let r = Resizing().throttling()
        r.resize(620)
        r.resize(580)
        r.resizer.mode = .intrinsic
        r.root.layoutSubtreeIfNeeded()
        #expect(r.page.frame == r.content.bounds)
        #expect(r.page.frame.size == size(580))
    }

    @Test func autoresizingAndClippingAreRestoredAfterTheDrag() {
        let r = Resizing().throttling()
        r.resize(620)
        r.resizer.mode = .intrinsic
        r.root.layoutSubtreeIfNeeded()
        #expect(r.page.autoresizingMask == [.width, .height])
        #expect(r.content.clipsToBounds == r.ownClipping)
    }

    @Test func theCurrentReportDrainsAnyStaleFrame() {
        let r = Resizing().throttling()
        r.resize(620)
        r.resizer.mode = .intrinsic
        r.root.layoutSubtreeIfNeeded()
        r.page.viewport = size(620)
        r.resizer.mode = .throttle
        #expect(r.page.liveLeases == 1)
        #expect(r.resizer.hold.pendingFrames.isEmpty)
    }

    @Test func aReplacedPageResubscribes() {
        let r = Resizing().throttling()
        let first = r.page
        r.page = FakePage(frame: r.content.bounds)
        first.removeFromSuperview()
        r.content.addSubview(r.page)
        r.page.viewport = r.content.bounds.size
        r.resizer.place(r.page, in: r.content)
        #expect(first.liveLeases == 0)
        #expect(r.page.liveLeases == 1)
        #expect(r.resizer.hold.mode == .throttle)
    }

    @Test func theNewPageIsHeld() {
        let r = Resizing().throttling()
        let first = r.page
        r.page = FakePage(frame: r.content.bounds)
        first.removeFromSuperview()
        r.content.addSubview(r.page)
        r.page.viewport = r.content.bounds.size
        r.resizer.place(r.page, in: r.content)
        r.resize(540)
        #expect(r.resizer.hold.lockedSize == size(540))
    }

    @Test func lockedHoldsTheCurrentSize() {
        let r = Resizing()
        r.resize(540)
        r.page.reports = false
        r.resizer.mode = .locked
        #expect(r.resizer.hold.mode == .locked)
        #expect(r.resizer.hold.lockedSize == size(540))
    }

    @Test func aLockedPageIgnoresItsContentSize() {
        let r = Resizing()
        r.resize(540)
        r.page.reports = false
        r.resizer.mode = .locked
        r.resize(700)
        #expect(r.page.frame.size == size(540))
        #expect(r.content.clipsToBounds)
    }

    @Test func unlockingFillsTheContent() {
        let r = Resizing()
        r.resize(540)
        r.page.reports = false
        r.resizer.mode = .locked
        r.resize(700)
        r.resizer.mode = .intrinsic
        r.root.layoutSubtreeIfNeeded()
        #expect(r.page.frame.size == size(700))
        #expect(r.content.clipsToBounds == r.ownClipping)
    }

    @MainActor private final class Fresh {
        let r = Resizing()
        let fresh = Content(frame: .zero)
        let resizer = PageContentResizer()
        var late = FakePage(frame: .zero)

        init() {
            r.root.addSubview(fresh)
            fresh.addSubview(late)
            let resizer = self.resizer
            fresh.onLayout = { [unowned self] in resizer.place(late, in: fresh) }
        }
    }

    @Test func anEmptyContentLocksNothing() {
        let f = Fresh()
        f.resizer.mode = .locked
        f.resizer.place(f.late, in: f.fresh)
        #expect(f.resizer.hold.lockedSize == nil)
    }

    @Test func theLockHoldsTheContentsFirstSize() {
        let f = Fresh()
        f.resizer.mode = .locked
        f.resizer.place(f.late, in: f.fresh)
        f.fresh.frame.size = size(500)
        f.r.root.layoutSubtreeIfNeeded()
        #expect(f.late.frame.size == size(500))
        #expect(f.resizer.hold.lockedSize == size(500))
    }

    @Test func aPageThatJoinsALockHoldsTheContentsSizeNotItsOwnEmptyFrame() {
        let f = Fresh()
        f.resizer.mode = .locked
        f.resizer.place(f.late, in: f.fresh)
        f.fresh.frame.size = size(500)
        f.r.root.layoutSubtreeIfNeeded()
        let joining = FakePage(frame: .zero)
        f.late.removeFromSuperview()
        f.late = joining
        f.fresh.addSubview(joining)
        f.resizer.place(joining, in: f.fresh)
        #expect(joining.frame.size == size(500))
        #expect(f.resizer.hold.lockedSize == size(500))
    }

    private func emptyThrottle(_ f: Fresh) {
        f.resizer.mode = .intrinsic
        f.fresh.frame.size = .zero
        f.r.root.layoutSubtreeIfNeeded()
        let unrendered = FakePage(frame: .zero)
        f.late.removeFromSuperview()
        f.late = unrendered
        f.fresh.addSubview(unrendered)
        f.resizer.mode = .throttle
        f.resizer.place(unrendered, in: f.fresh)
    }

    @Test func anEmptyContentDoesNotThrottleYet() {
        let f = Fresh()
        emptyThrottle(f)
        #expect(f.resizer.hold.mode == .intrinsic)
        #expect(f.late.liveLeases == 0)
    }

    @Test func theFirstSizeReachesThePageAndHoldsUntilTheRendererDrawsIt() {
        let f = Fresh()
        emptyThrottle(f)
        f.fresh.frame.size = size(480)
        f.r.root.layoutSubtreeIfNeeded()
        #expect(f.late.frame.size == size(480))
        #expect(f.late.liveLeases == 1)
        #expect(f.resizer.hold.lockedSize == size(480))
    }

    @Test func itsReportReleasesThePage() {
        let f = Fresh()
        emptyThrottle(f)
        f.fresh.frame.size = size(480)
        f.r.root.layoutSubtreeIfNeeded()
        f.late.drawn()
        f.r.root.layoutSubtreeIfNeeded()
        #expect(f.resizer.hold.lockedSize == nil)
        #expect(f.late.frame.size == size(480))
    }

    @Test func aReturningPageDropsTheHoldItLeftWith() {
        let r = Resizing()
        let home = Content(frame: NSRect(origin: .zero, size: size(800)))
        let elsewhere = Content(frame: NSRect(origin: .zero, size: size(600)))
        r.root.addSubview(home)
        r.root.addSubview(elsewhere)
        let homeResizer = PageContentResizer()
        let mover = FakePage(frame: home.bounds)
        var homePage: FakePage? = mover
        home.addSubview(mover)
        home.onLayout = { if let homePage { homeResizer.place(homePage, in: home) } }
        r.root.layoutSubtreeIfNeeded()
        mover.viewport = size(800)
        homeResizer.mode = .throttle
        for width: CGFloat in [790, 780] {
            home.frame.size.width = width
            r.root.layoutSubtreeIfNeeded()
        }
        #expect(mover.frame.size == size(790))
        homePage = nil
        elsewhere.addSubview(mover)
        homeResizer.mode = .intrinsic
        r.root.layoutSubtreeIfNeeded()
        homePage = mover
        home.addSubview(mover)
        homeResizer.place(mover, in: home)
        #expect(mover.frame.size == size(780))
        #expect(mover.autoresizingMask == [.width, .height])
        #expect(homeResizer.hold.lockedSize == nil)
    }
}
