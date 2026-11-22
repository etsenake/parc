import AppKit
import QuartzCore
import Testing
@testable import Parc

@MainActor
struct PageContentResizerTestsAttachmentTests {
    private typealias Support = PageContentResizerTestsSupport
    private typealias FakePage = Support.FakePage
    private typealias Content = Support.Content
    private typealias Resizing = Support.Resizing

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
        f.fresh.frame.size = Support.size(500)
        f.r.root.layoutSubtreeIfNeeded()
        #expect(f.late.frame.size == Support.size(500))
        #expect(f.resizer.hold.lockedSize == Support.size(500))
    }

    @Test func aPageThatJoinsALockTakesTheHeldContentSize() {
        let f = Fresh()
        f.resizer.mode = .locked
        f.resizer.place(f.late, in: f.fresh)
        f.fresh.frame.size = Support.size(500)
        f.r.root.layoutSubtreeIfNeeded()
        let joining = FakePage(frame: .zero)
        f.late.removeFromSuperview()
        f.late = joining
        f.fresh.addSubview(joining)
        f.resizer.place(joining, in: f.fresh)
        #expect(joining.frame.size == Support.size(500))
        #expect(f.resizer.hold.lockedSize == Support.size(500))
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
        f.fresh.frame.size = Support.size(480)
        f.r.root.layoutSubtreeIfNeeded()
        #expect(f.late.frame.size == Support.size(480))
        #expect(f.late.liveLeases == 1)
        #expect(f.resizer.hold.lockedSize == Support.size(480))
    }

    @Test func itsReportReleasesThePage() {
        let f = Fresh()
        emptyThrottle(f)
        f.fresh.frame.size = Support.size(480)
        f.r.root.layoutSubtreeIfNeeded()
        f.late.drawn()
        f.r.root.layoutSubtreeIfNeeded()
        #expect(f.resizer.hold.lockedSize == nil)
        #expect(f.late.frame.size == Support.size(480))
    }

    @Test func aReturningPageDropsTheHoldItLeftWith() {
        let r = Resizing()
        let home = Content(frame: NSRect(origin: .zero, size: Support.size(800)))
        let elsewhere = Content(frame: NSRect(origin: .zero, size: Support.size(600)))
        r.root.addSubview(home)
        r.root.addSubview(elsewhere)
        let homeResizer = PageContentResizer()
        let mover = FakePage(frame: home.bounds)
        var homePage: FakePage? = mover
        home.addSubview(mover)
        home.onLayout = { if let homePage { homeResizer.place(homePage, in: home) } }
        r.root.layoutSubtreeIfNeeded()
        mover.viewport = Support.size(800)
        homeResizer.mode = .throttle
        for width: CGFloat in [790, 780] {
            home.frame.size.width = width
            r.root.layoutSubtreeIfNeeded()
        }
        #expect(mover.frame.size == Support.size(790))
        homePage = nil
        elsewhere.addSubview(mover)
        homeResizer.mode = .intrinsic
        r.root.layoutSubtreeIfNeeded()
        homePage = mover
        home.addSubview(mover)
        homeResizer.place(mover, in: home)
        #expect(mover.frame.size == Support.size(780))
        #expect(mover.autoresizingMask == [.width, .height])
        #expect(homeResizer.hold.lockedSize == nil)
    }
}
