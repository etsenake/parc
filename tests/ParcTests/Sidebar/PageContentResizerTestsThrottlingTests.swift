import AppKit
import QuartzCore
import Testing
@testable import Parc

@MainActor
struct PageContentResizerTestsThrottlingTests {
    private typealias Support = PageContentResizerTestsSupport
    private typealias Resizing = Support.Resizing

    @Test func throttleSubscribesToTheRenderer() {
        let r = Resizing()
        r.page.viewport = Support.size(700)
        r.resizer.mode = .throttle
        #expect(r.resizer.hold.mode == .throttle)
        #expect(r.page.liveLeases == 1)
    }

    @Test func enteringThrottleRelaysOut() {
        let r = Resizing()
        r.page.viewport = Support.size(700)
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
        #expect(r.page.frame.size == Support.size(660))
        #expect(r.resizer.hold.lockedSize == Support.size(660))
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
        #expect(r.page.frame.size == Support.size(600))
        #expect(r.resizer.hold.lockedSize == Support.size(600))
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
        r.page.emit(Support.size(10))
        r.root.layoutSubtreeIfNeeded()
        #expect(r.page.frame.size == Support.size(640))
    }

    @Test func anUnchangedSizeAfterItsReportDoesNotHold() {
        let r = Resizing().throttling()
        heldAt600(r)
        r.page.drawn()
        r.root.layoutSubtreeIfNeeded()
        r.resize(640)
        r.page.emit(Support.size(10))
        r.root.layoutSubtreeIfNeeded()
        r.page.emit(Support.size(640))
        r.root.layoutSubtreeIfNeeded()
        #expect(r.resizer.hold.lockedSize == nil)
        #expect(r.page.frame.size == Support.size(640))
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
}
