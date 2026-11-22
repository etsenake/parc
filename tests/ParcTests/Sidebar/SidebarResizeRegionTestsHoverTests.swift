import AppKit
import Combine
import QuartzCore
import Testing
@testable import ParcCore
@testable import ParcSidebar

@MainActor
struct SidebarResizeRegionTestsHoverTests {
    private typealias Strip = SidebarResizeRegionTestsSupport.Strip

    @Test func hoverDoesNotShowTheIndicatorAtOnce() {
        let s = Strip()
        s.region.mouseEntered(with: s.event(.mouseEntered))
        #expect(s.region.isHovered)
        #expect(s.indicator.isHidden)
    }

    @Test func hoverIsStillWaitingAtPointOneFiveSeconds() {
        let s = Strip()
        s.region.mouseEntered(with: s.event(.mouseEntered))
        s.clock.advance(by: 0.15)
        #expect(s.indicator.isHidden)
        #expect(s.fade() == nil)
    }

    @Test func hoverShowsTheIndicatorAfterAQuarterSecond() {
        let s = Strip()
        s.region.mouseEntered(with: s.event(.mouseEntered))
        s.clock.advance(by: 0.25)
        #expect(!s.indicator.isHidden)
        #expect(s.indicator.opacity == 0.5)
    }

    @Test func theRevealFadesFromZeroToHalfOverPointTwoSeconds() throws {
        let s = Strip()
        s.region.mouseEntered(with: s.event(.mouseEntered))
        s.clock.advance(by: 0.25)
        let fade = try #require(s.fade())
        #expect(fade.fromValue as? Double == 0)
        #expect(fade.toValue as? Double == 0.5)
        #expect(fade.duration == 0.2)
        #expect(fade.fillMode == .forwards)
    }

    private func shown() -> Strip {
        let s = Strip()
        s.region.mouseEntered(with: s.event(.mouseEntered))
        s.clock.advance(by: 0.25)
        return s
    }

    @Test func leavingAShownIndicatorFadesItFromHalfToZero() throws {
        let s = shown()
        s.region.mouseExited(with: s.event(.mouseExited))
        let fade = try #require(s.fade())
        #expect(fade.fromValue as? Double == 0.5)
        #expect(fade.toValue as? Double == 0)
        #expect(fade.duration == 0.2)
    }

    @Test func theIndicatorStaysVisibleWhileItFadesOut() {
        let s = shown()
        s.region.mouseExited(with: s.event(.mouseExited))
        s.clock.advance(by: 0.1)
        #expect(!s.indicator.isHidden)
    }

    @Test func afterItsFadeOutTheIndicatorIsHiddenAtModelOpacityHalf() {
        let s = shown()
        s.region.mouseExited(with: s.event(.mouseExited))
        s.clock.advance(by: 0.2)
        #expect(s.indicator.isHidden)
        #expect(s.indicator.opacity == 0.5)
        #expect(s.fade() == nil)
    }

    @Test func hoverEndingBeforeAQuarterSecondCancelsTheShow() {
        let s = Strip()
        s.region.mouseEntered(with: s.event(.mouseEntered))
        s.clock.advance(by: 0.1)
        s.region.mouseExited(with: s.event(.mouseExited))
        s.clock.advance(by: 0.4)
        #expect(s.indicator.isHidden)
        #expect(s.fade() == nil)
    }

    @Test func anInterruptedFadeCannotHideAResizingIndicator() {
        let s = Strip()
        s.region.isResizing = true
        s.region.mouseEntered(with: s.event(.mouseEntered))
        s.region.isResizing = false
        s.region.mouseExited(with: s.event(.mouseExited))
        s.region.isResizing = true
        s.clock.advance(by: 0.35)
        #expect(!s.indicator.isHidden)
    }

    @Test func anUnhoveredEndOfResizingFadeOutCompletes() {
        let s = Strip()
        s.region.isResizing = true
        s.region.isResizing = false
        s.clock.advance(by: 0.35)
        #expect(s.indicator.isHidden)
    }

    @Test func movementInsideReestablishesHover() {
        let s = Strip()
        let entered = s.event(.mouseEntered)
        s.region.mouseEntered(with: entered)
        s.region.mouseExited(with: s.event(.mouseExited))
        s.region.mouseMoved(with: entered)
        #expect(s.region.isHovered)
    }

    @Test func aCommandSurfaceOverTheStripKeepsItsHoverOff() {
        let s = Strip()
        s.root.addSubview(NSView(frame: NSRect(x: 200, y: 0, width: 60, height: 700)))
        let entered = s.event(.mouseEntered)
        s.region.mouseEntered(with: entered)
        s.region.mouseMoved(with: entered)
        #expect(!s.region.isHovered)
    }

    @Test func movingOutFromUnderTheCoverRestoresHover() {
        let s = Strip()
        let cover = NSView(frame: NSRect(x: 200, y: 0, width: 60, height: 700))
        s.root.addSubview(cover)
        let entered = s.event(.mouseEntered)
        s.region.mouseEntered(with: entered)
        s.region.mouseMoved(with: entered)
        cover.removeFromSuperview()
        s.region.mouseMoved(with: entered)
        #expect(s.region.isHovered)
    }

    @Test func resizingShowsTheIndicatorAtOnceWithoutAnimation() {
        let s = Strip()
        s.region.isResizing = true
        #expect(!s.indicator.isHidden)
        #expect(s.indicator.animationKeys() == nil)
    }

    @Test func hoverWhileResizingAddsNoFade() {
        let s = Strip()
        s.region.isResizing = true
        s.region.mouseEntered(with: s.event(.mouseEntered))
        #expect(!s.indicator.isHidden)
        #expect(s.fade() == nil)
    }

    @Test func theEndOfResizingKeepsAHoveredIndicator() {
        let s = Strip()
        s.region.isResizing = true
        s.region.mouseEntered(with: s.event(.mouseEntered))
        s.region.isResizing = false
        #expect(!s.indicator.isHidden)
        #expect(s.fade() == nil)
    }

    @Test func aLaterExitFadesOut() {
        let s = Strip()
        s.region.isResizing = true
        s.region.mouseEntered(with: s.event(.mouseEntered))
        s.region.isResizing = false
        s.region.mouseExited(with: s.event(.mouseExited))
        #expect(s.fade()?.toValue as? Double == 0)
        #expect(s.fade()?.fromValue as? Double == 0.5)
        #expect(s.fade()?.duration == 0.2)
    }

    @Test func anUnhoveredEndOfResizingFadesOut() {
        let s = Strip()
        s.region.isResizing = true
        s.region.isResizing = false
        #expect(s.fade()?.toValue as? Double == 0)
    }

    @Test func anUnchangedResizingValueDoesNothing() {
        let s = Strip()
        s.region.isResizing = false
        #expect(s.fade() == nil)
    }
}
