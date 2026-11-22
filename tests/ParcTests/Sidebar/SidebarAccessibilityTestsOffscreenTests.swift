import AppKit
import Testing
@testable import Parc
@testable import ParcSidebar

@MainActor
struct SidebarAccessibilityTestsOffscreenTests {
    private typealias Support = SidebarAccessibilityTestsSupport
    private typealias Offscreen = Support.Offscreen

    @Test func lockedPointerAndAccessibilityHitTestsReachTheAddress() {
        let o = Offscreen()
        let locked = o.hits(o.addressCentre)
        #expect(locked.view)
        #expect(locked.element)
    }

    @Test func theHiddenSidebarIsUnhiddenAndWhollyOutsideTheContent() {
        let o = Offscreen()
        o.hide()
        #expect(!o.container.isHidden)
        #expect(o.container.frame.maxX < 0)
        #expect(o.address.convert(o.address.bounds, to: nil).maxX < 0)
    }

    @Test func itsControlsStayInTheWindowsAccessibilityChildrenAndNavigationOrder() {
        let o = Offscreen()
        o.hide()
        #expect(o.listed(o.browser.accessibilityChildren(), o.headerToggle))
        #expect(o.listed(o.browser.accessibilityChildren(), o.address))
        let navigation = o.browser.perform(#selector(NSWindow.accessibilityChildrenInNavigationOrder))?.takeUnretainedValue() as? [Any]
        #expect(o.listed(navigation, o.address))
    }

    @Test func theirAccessibilityFramesLieLeftOfTheWindow() {
        let o = Offscreen()
        o.hide()
        let element = o.exposed(o.address) as? NSAccessibilityElementProtocol
        #expect((element?.accessibilityFrame().maxX ?? .infinity) <= o.browser.frame.minX)
    }

    @Test func hiddenNeitherHitTestReachesThemWhereTheyWereOrWhereTheyAre() {
        let o = Offscreen()
        let lockedPoint = o.addressCentre
        o.hide()
        let formerPlace = o.hits(lockedPoint)
        let offScreen = o.hits(o.addressCentre)
        #expect(!formerPlace.view)
        #expect(!formerPlace.element)
        #expect(!offScreen.view)
        #expect(!offScreen.element)
    }

    @Test func anOffScreenFieldsVisibleRectIsNotEmpty() {
        let o = Offscreen()
        o.hide()
        #expect(!o.address.visibleRect.isEmpty)
        #expect(!o.address.bounds.contains(o.address.visibleRect))
    }

    @Test func aSelfClippingViewsVisibleRectIsItsBounds() {
        let o = Offscreen()
        let clipping = NSView(frame: NSRect(x: 600, y: 100, width: 100, height: 28))
        clipping.clipsToBounds = true
        o.content.addSubview(clipping)
        #expect(clipping.visibleRect == clipping.bounds)
    }

    @Test func anOffScreenFieldTakesFocus() {
        let o = Offscreen()
        o.hide()
        #expect(o.browser.makeFirstResponder(o.address))
        #expect(o.browser.firstResponder is NSTextView)
    }

    @Test func appKitsComputedLoopIncludesTheOffScreenField() {
        let o = Offscreen()
        o.hide()
        _ = o.browser.makeFirstResponder(nil)
        o.browser.recalculateKeyViewLoop()
        #expect(o.forward(from: o.page).contains { $0 === o.address })
    }

    @Test func unbypassedTabReachesTheOffScreenChainPastItsGate() {
        let o = Offscreen()
        o.hide()
        o.browser.recalculateKeyViewLoop()
        let c = Support.chain(o)
        SidebarAccessibility.link(c, within: o.sidebar, exit: nil)
        #expect(o.forward(from: o.page).contains { $0 === o.address })
        #expect(!c[0].canBecomeKeyView)
    }

    @Test func withoutAnExitTheChainsEndKeepsTheComputedLoopsWayOn() {
        let o = Offscreen()
        o.hide()
        o.browser.recalculateKeyViewLoop()
        SidebarAccessibility.link(Support.chain(o), within: o.sidebar, exit: nil)
        #expect(o.sidebar.nextKeyView.map { !$0.isDescendant(of: o.container) } == true)
        #expect(o.sidebar.nextValidKeyView != nil)
    }

    @Test func bypassedWithoutAnExitTabAndShiftTabPassTheHiddenChain() {
        let o = Offscreen()
        o.hide()
        o.browser.recalculateKeyViewLoop()
        let c = Support.chain(o)
        o.sidebar.presented = false
        SidebarAccessibility.link(c, within: o.sidebar, exit: nil, bypassed: true)
        #expect(!o.inside(o.forward(from: o.page) + o.backward(from: o.page) + o.forward(from: o.pageEnd) + o.backward(from: o.pageEnd)))
    }

    @Test func theWindowOwnersWayInAndOut() {
        let o = Offscreen()
        o.hide()
        o.browser.recalculateKeyViewLoop()
        let c = Support.chain(o)
        SidebarAccessibility.link(c, within: o.sidebar, exit: nil)
        o.pageEnd.nextKeyView = c[0]
        SidebarAccessibility.link(c, within: o.sidebar, exit: o.page)
        #expect([o.headerToggle, o.address].contains { $0 === o.pageEnd.nextValidKeyView })
        #expect(o.sidebar.nextValidKeyView === o.page)
        #expect(o.page.previousValidKeyView === o.sidebar)
    }

    @Test func tabAndShiftTabBypassTheHiddenSidebar() {
        let o = Offscreen()
        o.hide()
        o.browser.recalculateKeyViewLoop()
        let c = Support.chain(o)
        SidebarAccessibility.link(c, within: o.sidebar, exit: nil)
        o.pageEnd.nextKeyView = c[0]
        SidebarAccessibility.link(c, within: o.sidebar, exit: o.page)
        o.sidebar.presented = false
        SidebarAccessibility.link(c, within: o.sidebar, exit: o.page, bypassed: true)
        #expect(o.pageEnd.nextValidKeyView === o.page)
        #expect(o.page.previousValidKeyView === o.pageEnd)
        #expect(!o.inside(o.forward(from: o.page) + o.backward(from: o.page) + o.forward(from: o.pageEnd)))
    }

    @Test func relinkingKeepsTheHiddenSidebarBypassed() {
        let o = Offscreen()
        o.hide()
        o.browser.recalculateKeyViewLoop()
        let c = Support.chain(o)
        SidebarAccessibility.link(c, within: o.sidebar, exit: nil)
        o.pageEnd.nextKeyView = c[0]
        SidebarAccessibility.link(c, within: o.sidebar, exit: o.page)
        o.sidebar.presented = false
        SidebarAccessibility.link(c, within: o.sidebar, exit: o.page, bypassed: true)
        SidebarAccessibility.link(c, within: o.sidebar, exit: o.page, bypassed: true)
        #expect(o.pageEnd.nextValidKeyView === o.page)
        #expect(o.page.previousValidKeyView === o.pageEnd)
    }

    @Test func presentingItAgainRestoresTheChainBehindItsWayInAndTheWayBackToItsEnd() {
        let o = Offscreen()
        o.hide()
        o.browser.recalculateKeyViewLoop()
        let c = Support.chain(o)
        o.pageEnd.nextKeyView = c[0]
        o.sidebar.presented = false
        SidebarAccessibility.link(c, within: o.sidebar, exit: o.page, bypassed: true)
        o.sidebar.presented = true
        SidebarAccessibility.link(c, within: o.sidebar, exit: o.page)
        #expect([o.headerToggle, o.address].contains { $0 === o.pageEnd.nextValidKeyView })
        #expect(o.page.previousValidKeyView === o.sidebar)
        #expect(o.address.nextKeyView === o.sidebar)
        #expect(o.sidebar.previousKeyView === o.address)
    }
}
