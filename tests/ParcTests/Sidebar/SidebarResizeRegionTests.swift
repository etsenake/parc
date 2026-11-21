import AppKit
import Combine
import QuartzCore
import Testing
@testable import Parc
@testable import ParcCore

private final class FakePan: NSPanGestureRecognizer {
    var fakeState: NSGestureRecognizer.State = .possible
    var translationX: CGFloat = 0
    var velocityX: CGFloat = 0
    var measuredIn: [NSView?] = []
    override var state: NSGestureRecognizer.State { get { fakeState } set { fakeState = newValue } }
    override func translation(in view: NSView?) -> NSPoint { measuredIn.append(view); return NSPoint(x: translationX, y: 7) }
    override func velocity(in view: NSView?) -> NSPoint { NSPoint(x: velocityX, y: 9) }
}

private final class FakeClick: NSClickGestureRecognizer {
    var fakeState: NSGestureRecognizer.State = .possible
    override var state: NSGestureRecognizer.State { get { fakeState } set { fakeState = newValue } }
}

@MainActor private final class ManualClock {
    private var now: TimeInterval = 0
    private var pending: [(at: TimeInterval, work: () -> Void)] = []

    func schedule(after delay: TimeInterval, _ work: @escaping () -> Void) { pending.append((now + delay, work)) }

    func advance(by seconds: TimeInterval) {
        now += seconds
        while let index = pending.indices.filter({ pending[$0].at <= now }).min(by: { pending[$0].at < pending[$1].at }) {
            pending.remove(at: index).work()
        }
    }
}

@MainActor
struct SidebarResizeRegionTests {
    typealias R = SidebarResizeRegionView

    @MainActor private final class Strip {
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 1000, height: 700),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 1000, height: 700))
        let sidebar = NSView(frame: NSRect(x: 0, y: 0, width: 228, height: 700))
        let region = R(frame: .zero)
        var haptics = 0
        var pans: [(NSGestureRecognizer.State, CGFloat, CGFloat)] = []
        let pan = FakePan(target: nil, action: nil)
        let clock = ManualClock()

        init() {
            window.isReleasedWhenClosed = false
            region.reducesMotion = { false }
            region.delay = { [clock] seconds in
                let subject = PassthroughSubject<Void, Never>()
                clock.schedule(after: seconds) { subject.send(()); subject.send(completion: .finished) }
                return subject.eraseToAnyPublisher()
            }
            region.runFadeOut = { [clock, indicator = region.indicatorLayer] animations, completion in
                animations()
                clock.schedule(after: indicator.animation(forKey: "opacity")?.duration ?? 0, completion)
            }
            root.wantsLayer = true
            window.contentView = root
            region.performHaptic = { [weak self] in self?.haptics += 1 }
            region.referenceView = sidebar
            root.addSubview(sidebar)
            root.addSubview(region)
            region.frame = R.frame(trailing: sidebar.frame, in: root.bounds)
            root.layoutSubtreeIfNeeded()
            region.onPan = { [weak self] in self?.pans.append(($0, $1, $2)) }
        }

        deinit { MainActor.assumeIsolated { window.close() } }

        var indicator: CAShapeLayer { region.indicatorLayer }
        var center: NSPoint { region.convert(NSPoint(x: region.bounds.midX, y: region.bounds.midY), to: nil) }

        func send(_ state: NSGestureRecognizer.State, _ x: CGFloat, _ v: CGFloat) {
            pan.fakeState = state
            pan.translationX = x
            pan.velocityX = v
            region.perform(NSSelectorFromString("handlePan:"), with: pan)
        }

        func event(_ type: NSEvent.EventType) -> NSEvent {
            NSEvent.enterExitEvent(with: type, location: center, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                                   context: nil, eventNumber: 0, trackingNumber: 0, userData: nil)!
        }

        func fade() -> CABasicAnimation? { indicator.animation(forKey: "opacity") as? CABasicAnimation }
    }

    @Test func aLockedStripStraddlesTheTrailingEdge() {
        #expect(R.frame(trailing: NSRect(x: 0, y: 0, width: 228, height: 700), in: NSRect(x: 0, y: 0, width: 1000, height: 700))
                == NSRect(x: 224, y: 11, width: 8, height: 678))
    }

    @Test func aFloatingStripFollowsTheContainerMaxX() {
        #expect(R.frame(trailing: NSRect(x: 5, y: 5, width: 228, height: 690), in: NSRect(x: 0, y: 0, width: 1000, height: 700))
                == NSRect(x: 229, y: 11, width: 8, height: 678))
    }

    @Test func verticalInsetsFollowTheContainerAndNeverGoNegative() {
        #expect(R.frame(trailing: NSRect(x: 0, y: 0, width: 300, height: 10), in: NSRect(x: 0, y: 40, width: 500, height: 10))
                == NSRect(x: 296, y: 51, width: 8, height: 0))
    }

    @Test func theStripIsLayerBackedAndUnclipped() {
        let s = Strip()
        #expect(s.region.wantsLayer)
        #expect(s.region.layer?.masksToBounds == false)
    }

    @Test func theIndicatorIsAHiddenSublayer() {
        let s = Strip()
        #expect(s.indicator.superlayer === s.region.layer)
        #expect(s.indicator.isHidden)
        #expect(s.indicator.opacity == 0.5)
    }

    @Test func theIndicatorIsThreePointsByHeightMinusEight() {
        #expect(Strip().indicator.bounds.size == CGSize(width: 3, height: 670))
    }

    @Test func theIndicatorIsCentredOnTheLeadingEdge() {
        let s = Strip()
        #expect(s.indicator.anchorPoint == CGPoint(x: 0.5, y: 0.5))
        #expect(s.indicator.position == CGPoint(x: 0, y: 339))
        #expect(s.indicator.frame.minX == -1.5)
        #expect(s.indicator.frame.minY == 4)
    }

    @Test func theRoundedPathFillsTheLine() {
        #expect(Strip().indicator.path?.boundingBox == CGRect(x: 0, y: 0, width: 3, height: 670))
    }

    @Test func theStripNeverDragsTheWindow() {
        #expect(!Strip().region.mouseDownCanMoveWindow)
    }

    @Test func trackingAreasAreReplacedOnEachUpdateWithTheRecoveredOptions() {
        let s = Strip()
        s.region.updateTrackingAreas()
        s.region.updateTrackingAreas()
        let area = s.region.trackingAreas.first
        #expect(s.region.trackingAreas.count == 1)
        #expect(area?.options.rawValue == 0x227)
        #expect(area?.owner === s.region)
    }

    @Test func thereAreTwoRecognizersWithoutADelegate() {
        let s = Strip()
        #expect(s.region.gestureRecognizers.count == 2)
        #expect(s.region.gestureRecognizers.allSatisfy { $0.delegate == nil })
    }

    @Test func thePanAndDoubleClickRecognizersAreInstalled() {
        let s = Strip()
        #expect(s.region.panGestureRecognizer.view === s.region)
        #expect(s.region.doubleClickGestureRecognizer.numberOfClicksRequired == 2)
        #expect(s.region.doubleClickGestureRecognizer.view === s.region)
    }

    @Test func fillAndStrokeUseTheThemeColour() {
        let s = Strip()
        s.region.color = NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)
        s.region.updateLayer()
        #expect(s.indicator.fillColor == s.region.color.cgColor)
        #expect(s.indicator.strokeColor == s.region.color.cgColor)
    }

    @Test func theIndicatorHeightFollowsRelayout() {
        let s = Strip()
        s.region.frame.size.height = 100
        s.root.layoutSubtreeIfNeeded()
        #expect(s.indicator.bounds.height == 92)
        #expect(s.indicator.position.y == 50)
    }

    @Test func anUnobstructedStripOwnsTheCursor() {
        let s = Strip()
        #expect(s.region.isUnobstructed(atWindowPoint: s.center))
    }

    @Test func thePageAreaDoesNotOwnTheCursor() {
        let s = Strip()
        #expect(!s.region.isUnobstructed(atWindowPoint: NSPoint(x: 600, y: 300)))
    }

    @Test func aViewAboveTheStripObstructsIt() {
        let s = Strip()
        s.root.addSubview(NSView(frame: NSRect(x: 200, y: 0, width: 60, height: 700)))
        #expect(!s.region.isUnobstructed(atWindowPoint: s.center))
    }

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

    @Test(arguments: [(1, [Float]([0.215, 0.61])), (2, [Float]([0.355, 1]))])
    func thePulseTimingHasItsControlPoints(index: Int, expected: [Float]) throws {
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
