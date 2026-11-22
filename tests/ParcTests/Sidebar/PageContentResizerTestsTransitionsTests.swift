import AppKit
import QuartzCore
import Testing
@testable import Parc
@testable import ParcCore

@MainActor
struct PageContentResizerTestsTransitionsTests {
    private typealias Support = PageContentResizerTestsSupport
    private typealias FakePage = Support.FakePage
    private typealias Resizing = Support.Resizing

    @Test func aSizeIsHeldBeforeTheDragEnds() {
        let r = Resizing().throttling()
        r.resize(660)
        r.page.drawn()
        r.root.layoutSubtreeIfNeeded()
        r.resize(620)
        #expect(r.resizer.hold.lockedSize == Support.size(620))
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
        #expect(r.page.frame.size == Support.size(580))
    }

    @Test func endingTheDragRestoresPageAutoresizing() {
        let r = Resizing().throttling()
        r.resize(620)
        r.resizer.mode = .intrinsic
        r.root.layoutSubtreeIfNeeded()
        #expect(r.page.autoresizingMask == [.width, .height])
    }

    @Test func endingTheDragRestoresContentClipping() {
        let r = Resizing().throttling()
        r.resize(620)
        r.resizer.mode = .intrinsic
        r.root.layoutSubtreeIfNeeded()
        #expect(r.content.clipsToBounds == r.ownClipping)
    }

    @Test func theCurrentReportDrainsAnyStaleFrame() {
        let r = Resizing().throttling()
        r.resize(620)
        r.resizer.mode = .intrinsic
        r.root.layoutSubtreeIfNeeded()
        r.page.viewport = Support.size(620)
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
        #expect(r.resizer.hold.lockedSize == Support.size(540))
    }

    @Test func lockedHoldsTheCurrentSize() {
        let r = Resizing()
        r.resize(540)
        r.page.reports = false
        r.resizer.mode = .locked
        #expect(r.resizer.hold.mode == .locked)
        #expect(r.resizer.hold.lockedSize == Support.size(540))
    }

    @Test func aLockedPageIgnoresItsContentSize() {
        let r = Resizing()
        r.resize(540)
        r.page.reports = false
        r.resizer.mode = .locked
        r.resize(700)
        #expect(r.page.frame.size == Support.size(540))
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
        #expect(r.page.frame.size == Support.size(700))
        #expect(r.content.clipsToBounds == r.ownClipping)
    }
}
