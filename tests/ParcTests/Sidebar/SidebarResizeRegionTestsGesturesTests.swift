import AppKit
import Combine
import QuartzCore
import Testing
@testable import Parc
@testable import ParcCore
@testable import ParcSidebar

@MainActor
struct SidebarResizeRegionTestsGesturesTests {
    private typealias Strip = SidebarResizeRegionTestsSupport.Strip

    private final class FakeClick: NSClickGestureRecognizer {
        var fakeState: NSGestureRecognizer.State = .possible
        override var state: NSGestureRecognizer.State { get { fakeState } set { fakeState = newValue } }
    }

    @Test func layoutEventsHaveNoFeedback() {
        let s = Strip()
        s.region.isResizing = true
        s.region.present([.previewHiddenChanged(true), .breakpointChanged(1)])
        #expect(s.haptics == 0)
        #expect(s.indicator.animationKeys() == nil)
    }

    @Test func engagePerformsOneHapticAfterRemovingAnimations() {
        let s = Strip()
        s.region.isResizing = true
        s.indicator.add(CABasicAnimation(keyPath: "opacity"), forKey: "opacity")
        s.region.present([.snapEngaged])
        #expect(s.haptics == 1)
        #expect(s.fade() == nil)
    }

    @Test func engageScalesTheLineXOneToOnePointSeven() throws {
        let s = Strip()
        s.region.isResizing = true
        s.region.present([.snapEngaged])
        let pulse = try #require(s.indicator.animation(forKey: "transform.scale.x") as? CABasicAnimation)
        #expect(pulse.keyPath == "transform.scale.x")
        #expect(pulse.fromValue as? Double == 1)
        #expect(pulse.toValue as? Double == 1.7)
        #expect(pulse.duration == 0.08)
        #expect(pulse.autoreverses)
        #expect(pulse.fillMode == .forwards)
    }

    struct PulsePoint: CustomTestStringConvertible {
        let testDescription: String
        let index: Int
        let expected: [Float]
    }

    @Test(arguments: [
        PulsePoint(testDescription: "First control point", index: 1, expected: [Float]([0.215, 0.61])),
        PulsePoint(testDescription: "Second control point", index: 2, expected: [Float]([0.355, 1])),
    ])
    func thePulseTimingHasItsControlPoints(_ sample: PulsePoint) throws {
        let index = sample.index
        let expected = sample.expected
        let s = Strip()
        s.region.isResizing = true
        s.region.present([.snapEngaged])
        let pulse = try #require(s.indicator.animation(forKey: "transform.scale.x") as? CABasicAnimation)
        var points = [Float](repeating: 0, count: 2)
        pulse.timingFunction?.getControlPoint(at: index, values: &points)
        #expect(points == expected)
    }

    @Test func aShortHoldReleaseIsSilent() {
        let s = Strip()
        s.region.present([.snapReleased(haptic: false)])
        #expect(s.haptics == 0)
    }

    @Test func aLongHoldReleasePerformsTheHaptic() {
        let s = Strip()
        s.region.present([.snapReleased(haptic: true)])
        #expect(s.haptics == 1)
    }

    @Test func aChangeWithoutABeganSessionIsIgnored() {
        let s = Strip()
        s.send(.changed, 5, 1)
        #expect(s.pans.isEmpty)
    }

    @Test func beganForwardsAndDisablesCursorRects() {
        let s = Strip()
        s.send(.began, 0, 0)
        #expect(s.pans.count == 1)
        #expect(s.pans[0].0 == .began)
        #expect(!s.window.areCursorRectsEnabled)
    }

    @Test func translationIsMeasuredInTheReferenceView() {
        let s = Strip()
        s.send(.began, 0, 0)
        #expect(s.pan.measuredIn.allSatisfy { $0 === s.sidebar })
    }

    @Test func aChangeForwardsXTranslationAndVelocity() {
        let s = Strip()
        s.send(.began, 0, 0)
        s.send(.changed, -12.5, -40)
        #expect(s.pans.count == 2)
        #expect(s.pans[1].0 == .changed)
        #expect(s.pans[1].1 == -12.5)
        #expect(s.pans[1].2 == -40)
    }

    @Test func anEndForwardsAndRestoresCursorRects() {
        let s = Strip()
        s.send(.began, 0, 0)
        s.send(.ended, -20, -60)
        #expect(s.pans.count == 2)
        #expect(s.pans[1].0 == .ended)
        #expect(s.pans[1].1 == -20)
        #expect(s.window.areCursorRectsEnabled)
    }

    @Test func anEndIsReportedOnce() {
        let s = Strip()
        s.send(.began, 0, 0)
        s.send(.ended, -20, -60)
        s.send(.ended, -20, -60)
        #expect(s.pans.count == 2)
    }

    @Test func hidingCancelsTheDragOnce() {
        let s = Strip()
        s.send(.began, 0, 0)
        s.send(.changed, 30, 10)
        s.region.isHidden = true
        #expect(s.pans.count == 3)
        #expect(s.pans[2].0 == .cancelled)
        #expect(s.pans[2].1 == 30)
        #expect(s.window.areCursorRectsEnabled)
    }

    @Test func lateNativeCallbacksBelongToNoSession() {
        let s = Strip()
        s.send(.began, 0, 0)
        s.region.isHidden = true
        let count = s.pans.count
        s.send(.changed, 40, 0)
        s.send(.cancelled, 40, 0)
        #expect(s.pans.count == count)
    }

    @Test func resigningKeyCancelsTheDrag() {
        let s = Strip()
        s.send(.began, 0, 0)
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: s.window)
        #expect(s.pans.count == 2)
        #expect(s.pans[1].0 == .cancelled)
        #expect(s.window.areCursorRectsEnabled)
    }

    @Test func failureForwards() {
        let s = Strip()
        s.send(.began, 0, 0)
        s.send(.failed, 3, 0)
        #expect(s.pans.count == 2)
        #expect(s.pans[1].0 == .failed)
    }

    @Test func aRecognizedDoubleClickForwards() {
        let s = Strip()
        var doubleClicks = 0
        s.region.onDoubleClick = { doubleClicks += 1 }
        let click = FakeClick(target: nil, action: nil)
        click.fakeState = .ended
        s.region.perform(NSSelectorFromString("handleDoubleClick:"), with: click)
        #expect(doubleClicks == 1)
    }

    @Test func anUnrecognizedClickDoesNothing() {
        let s = Strip()
        var doubleClicks = 0
        s.region.onDoubleClick = { doubleClicks += 1 }
        let click = FakeClick(target: nil, action: nil)
        click.fakeState = .began
        s.region.perform(NSSelectorFromString("handleDoubleClick:"), with: click)
        #expect(doubleClicks == 0)
    }

    @Test func leavingTheWindowClearsHover() {
        let s = Strip()
        s.region.mouseEntered(with: s.event(.mouseEntered))
        s.region.removeFromSuperview()
        #expect(!s.region.isHovered)
    }
}
