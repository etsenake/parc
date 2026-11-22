import AppKit
import Testing
@testable import Parc
@testable import ParcSidebar

@MainActor
struct SidebarSpaceStandInTests {
    typealias M = SidebarSpacePagingModel
    typealias Strip = SidebarSpacePagerTests.Strip

    private func row() -> Strip {
        let s = Strip(count: 4, selected: 2)
        s.offers = true
        return s
    }

    private func caughtLongClick() -> (Strip, CGFloat) {
        let s = row()
        #expect(s.pager.slideIn(from: 0, to: 2) && s.pager.standInSide == -1)
        s.advance(0.08)
        return (s, s.pager.offset)
    }

    @Test func aLongClickSlidesInWithThePageItLeftStandingInOnTheLeft() {
        let (s, caught) = caughtLongClick()
        #expect(caught > 120 && caught < 240 && M.shownSource(0, selected: 2, offset: caught) == 0)
        _ = s
    }

    @Test func touchingTheTrackpadMidSlideHoldsTheStripAndItsStandIn() {
        let (s, caught) = caughtLongClick()
        s.gesture(.mayBegin, 0, at: 60)
        #expect(s.pager.isTracking && s.pager.offset == caught && s.pager.standInSide == -1 && s.pager.reach == 1...3)
        #expect(M.shownSource(0, selected: 2, offset: s.pager.offset) == 0)
    }

    @Test func pullingTowardThePageItLeftGoesNoFurtherAndPushingBackFollows() {
        let (s, caught) = caughtLongClick()
        s.gesture(.mayBegin, 0, at: 60); s.gesture(.began, 2, at: 60.01); s.gesture(.changed, 40, at: 60.02)
        #expect(abs(s.pager.offset - caught) < 1e-9)
        s.gesture(.changed, -60, at: 60.03)
        #expect(abs(s.pager.offset - (caught - 30)) < 1e-9 && M.shownSource(0, selected: 2, offset: s.pager.offset) == 0)
    }

    @Test func theReleaseSpringsHomeWithThePageItLeftStillBesideIt() {
        let (s, caught) = caughtLongClick()
        s.gesture(.mayBegin, 0, at: 60); s.gesture(.began, 2, at: 60.01); s.gesture(.changed, 40, at: 60.02); s.gesture(.changed, -60, at: 60.03)
        let near = s.pager.offset
        #expect(abs(near - (caught - 30)) < 1e-9)
        #expect(M.target(position: 480 - near, velocity: 0, width: 240, count: 4, begin: 2) == 1)
        s.gesture(.ended, 0, at: 60.3)
        #expect(s.selections.isEmpty && s.pager.isAnimating && s.pager.offset == near && s.pager.standInSide == -1)
    }

    @Test func caughtAgainWhileSettlingTheStandInHoldsAndIsGoneAtRest() {
        let (s, _) = caughtLongClick()
        s.gesture(.mayBegin, 0, at: 60); s.gesture(.began, 2, at: 60.01); s.gesture(.changed, 40, at: 60.02); s.gesture(.changed, -60, at: 60.03)
        let near = s.pager.offset
        s.gesture(.ended, 0, at: 60.3)
        s.advance(0.05)
        let settling = s.pager.offset
        s.gesture(.began, 2, at: 60.4); s.gesture(.changed, 30, at: 60.41)
        #expect(settling > 0 && settling < near && abs(s.pager.offset - settling) < 1e-9 && s.pager.standInSide == -1)
        s.gesture(.ended, 0, at: 60.6)
        s.rest()
        #expect(s.pager.offset == 0 && s.pager.standInSide == nil && s.pager.reach == nil && s.selected == s.id(2))
    }

    @Test func pushedThroughHomeTheRealNeighbourFollowsAndCanBeLandedOn() {
        let (s, pushed) = caughtLongClick()
        s.gesture(.began, -2, at: 62); s.gesture(.changed, -2 * (pushed + 72), at: 62.01)
        #expect(abs(s.pager.offset + 72) < 1e-9 && M.shownSource(0, selected: 2, offset: s.pager.offset) == nil
                && s.pager.reach?.contains(3) == true)
        s.gesture(.changed, -2 * 60, at: 62.02); s.gesture(.ended, 0, at: 62.3)
        #expect(s.selections == [s.id(3)] && s.pager.standInSide == nil)
    }

    @Test func letGoGentlyPastHomeItSettlesBackAndACatchIsAnOrdinarySwipe() {
        let (s, crossing) = caughtLongClick()
        s.gesture(.began, -2, at: 63); s.gesture(.changed, -2 * (crossing + 60), at: 63.01); s.gesture(.ended, 0, at: 63.3)
        #expect(s.selections.isEmpty && s.pager.offset < 0 && s.pager.standInSide == -1)
        s.advance(0.05)
        let far = s.pager.offset
        s.gesture(.began, 2, at: 63.4)
        #expect(far < 0 && s.pager.standInSide == nil && s.pager.reach == 1...3)
        s.gesture(.changed, 2 * (150 - far), at: 63.41)
        #expect(abs(s.pager.offset - 150) < 1e-9)
        s.gesture(.ended, 0, at: 63.7)
        #expect(s.selections == [s.id(1)])
    }

    @Test func aClickNextDoorNeedsNoStandInAndASwipeStillPullsBack() {
        let s = row()
        #expect(s.pager.slideIn(from: 1, to: 2) && s.pager.standInSide == nil)
        s.advance(0.08)
        let adjacent = s.pager.offset
        s.gesture(.began, 2, at: 64); s.gesture(.changed, 40, at: 64.01)
        #expect(abs(s.pager.offset - (adjacent + 20)) < 1e-9)
        s.gesture(.ended, 0, at: 64.3)
        #expect(s.selections == [s.id(1)])
    }

    @Test func aSlideNextDoorMidSlideDropsTheStandIn() {
        let s = row()
        #expect(s.pager.slideIn(from: 0, to: 2) && s.pager.standInSide == -1)
        s.advance(0.05)
        #expect(s.pager.slideIn(from: 2, to: 3) && s.pager.standInSide == nil)
    }

    @Test func aLongClickBackLeavesTheStandInOnTheRightAndAPageFlipClearsIt() {
        let s = row()
        s.select(1)
        #expect(s.pager.slideIn(from: 3, to: 1) && s.pager.standInSide == 1)
        s.advance(0.05)
        #expect(s.pager.swipe(deltaX: -1) && s.selected == s.id(2) && s.pager.standInSide == nil)
    }

    @Test func cancellingClearsTheStandIn() {
        let s = row()
        #expect(s.pager.slideIn(from: 0, to: 2))
        s.pager.cancel()
        #expect(s.pager.standInSide == nil && s.pager.offset == 0)
    }

    final class Sidebar: NSView {
        var received = 0
        override func scrollWheel(with event: NSEvent) { received += 1 }
    }
    final class Flipped: NSView { override var isFlipped: Bool { true } }

    private func scroll(_ dx: Int32, _ dy: Int32, phase: Int64?, at time: UInt64) -> NSEvent {
        let units: CGScrollEventUnit = phase == nil ? .line : .pixel
        let event = CGEvent(scrollWheelEvent2Source: nil, units: units, wheelCount: 2, wheel1: dy, wheel2: dx, wheel3: 0)!
        if let phase {
            event.setIntegerValueField(.scrollWheelEventScrollPhase, value: phase)
            event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        }
        event.timestamp = time
        return NSEvent(cgEvent: event)!
    }

    private func list<V: NSScrollView>(_ view: V) -> (V, Sidebar, NSWindow) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 240, height: 400), styleMask: [.borderless], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        let sidebar = Sidebar(frame: NSRect(x: 0, y: 0, width: 240, height: 400))
        view.frame = sidebar.bounds
        view.hasVerticalScroller = true; view.horizontalScrollElasticity = .none
        view.documentView = Flipped(frame: NSRect(x: 0, y: 0, width: 240, height: 2000))
        sidebar.addSubview(view); window.contentView = sidebar
        return (view, sidebar, window)
    }

    @Test func aPlainScrollViewKeepsAHorizontalScrollFromTheSidebar() {
        let (plain, sidebar, window) = list(NSScrollView())
        plain.scrollWheel(with: scroll(-3, 0, phase: nil, at: 1))
        #expect(sidebar.received == 0)
        _ = window
    }

    @MainActor final class Tablist {
        let s = Strip(selected: 0)
        var declined = 0
        let view: SidebarPagingScrollView
        let window: NSWindow
        init(_ make: (SidebarPagingScrollView) -> (SidebarPagingScrollView, Sidebar, NSWindow)) {
            (view, _, window) = make(SidebarPagingScrollView())
            s.offers = false
            view.offerScroll = { [weak self] event in
                guard let self else { return false }
                let used = s.pager.scrollWheel(event)
                if !used { declined += 1 }
                return used
            }
        }
    }

    private let second: UInt64 = 1_000_000_000

    @Test func aHorizontalSwipeOverTheListDragsTheStripWithoutScrollingIt() {
        let t = Tablist { list($0) }
        t.view.scrollWheel(with: scroll(0, 0, phase: 128, at: 40 * second))
        t.view.scrollWheel(with: scroll(-4, 0, phase: 1, at: 40 * second + second / 100))
        for k in 0..<12 { t.view.scrollWheel(with: scroll(-12, 0, phase: 2, at: 40 * second + UInt64(k + 2) * second / 100)) }
        #expect(t.s.pager.isTracking && t.s.pager.offset == -72)
        #expect(t.view.contentView.bounds.origin == .zero)
        t.view.scrollWheel(with: scroll(0, 0, phase: 4, at: 41 * second))
        #expect(!t.s.pager.isTracking)
        #expect(t.declined == 0)
    }

    @Test func aVerticalSwipeAndAWheelGoOnToTheListsOwnScrolling() {
        let t = Tablist { list($0) }
        t.view.scrollWheel(with: scroll(0, 0, phase: 128, at: 42 * second))
        t.view.scrollWheel(with: scroll(0, -6, phase: 1, at: 42 * second + second / 100))
        t.view.scrollWheel(with: scroll(0, -9, phase: 2, at: 42 * second + second / 50))
        t.view.scrollWheel(with: scroll(0, 0, phase: 4, at: 42 * second + second / 20))
        t.view.scrollWheel(with: scroll(0, -3, phase: nil, at: 43 * second))
        #expect(t.declined == 4 && !t.s.pager.isTracking && t.s.pager.offset == 0)
    }
}
