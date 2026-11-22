import AppKit
import Testing
@testable import Parc
@testable import ParcCore
@testable import ParcEasels

@MainActor private final class MotionWindow: NSWindow {
    override var isKeyWindow: Bool { true }
}

@MainActor private final class MotionAnnotation: NSView {
    var duration: TimeInterval = -1
    var implicit = false
    override var isHidden: Bool {
        didSet {
            duration = NSAnimationContext.current.duration
            implicit = NSAnimationContext.current.allowsImplicitAnimation
        }
    }
}

struct EaselMotionTests {
    @MainActor
    private final class Pinch {
        let window = MotionWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 400),
                                  styleMask: .borderless, backing: .buffered, defer: false)
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 500, height: 400))
        let canvas = NSView(frame: NSRect(x: 0, y: 0, width: 1000, height: 1000))
        var valid = true
        var pulses = 0
        var settles = 0
        lazy var motion = EaselCanvasMotion(owner: canvas, validOwner: { [unowned self] in valid },
            changed: {}, settleAnnotations: { [unowned self] in settles += 1 },
            feedback: { [unowned self] in pulses += 1 })

        init() {
            window.isReleasedWhenClosed = false
            scroll.allowsMagnification = true
            scroll.minMagnification = 0.1
            scroll.maxMagnification = 4
            scroll.documentView = canvas
            window.contentView = scroll
            motion.bind(scroll)
        }

        func begin() {
            update(0.8)
            NotificationCenter.default.post(name: NSScrollView.willStartLiveMagnifyNotification, object: scroll)
        }

        func update(_ zoom: CGFloat) {
            scroll.magnification = zoom
            NotificationCenter.default.post(name: NSView.boundsDidChangeNotification, object: scroll.contentView)
        }
    }

    @Test(arguments: [(CGFloat(0.8), CGFloat(0.99), CGFloat(1.1)), (CGFloat(1.2), CGFloat(1.01), CGFloat(0.9))])
    func crossingActualSizeInTheOriginalDirectionPulses(_ initial: CGFloat, _ approach: CGFloat, _ overshoot: CGFloat) throws {
        var pinch = try #require(EaselZoomInteraction(zoom: initial))
        let pulses = [approach, 1, 1, overshoot, approach, 1].map { pinch.record($0) }
        #expect(pulses == [false, true, false, false, false, true])
    }

    @Test(arguments: [CGFloat(0.99), 1, 1.01])
    func pinchesStartingNearActualSizeStaySilent(_ start: CGFloat) {
        var band = EaselZoomInteraction(zoom: start)!
        #expect(!band.record(0.8) && !band.record(1.2) && !band.record(1), "Inclusive initial band is silent for the entire pinch")
    }

    @Test(arguments: [CGFloat.nan, 0])
    func invalidStartingMagnificationIsRefused(_ start: CGFloat) {
        #expect(EaselZoomInteraction(zoom: start) == nil)
    }

    @Test
    func invalidUpdatesLeaveThePreviousValueAlone() {
        var finite = EaselZoomInteraction(zoom: 0.8)!
        #expect(!finite.record(.infinity) && finite.previous == 0.8 && finite.record(1), "Invalid updates preserve the actual previous value")
    }

    @MainActor @Test
    func programmaticZoomDoesNotStartAPinch() {
        let pinch = Pinch()
        pinch.update(0.8)
        pinch.update(1.1)
        #expect(!pinch.motion.isInteracting && pinch.pulses == 0)
    }

    @MainActor @Test
    func nativePinchUpdatesPulseAtActualSize() {
        let pinch = Pinch()
        pinch.begin()
        #expect(pinch.motion.isInteracting)
        pinch.update(1)
        #expect(pinch.pulses == 1)
    }

    @MainActor @Test
    func endingThePinchStopsFeedback() {
        let pinch = Pinch()
        pinch.begin()
        NotificationCenter.default.post(name: NSScrollView.didEndLiveMagnifyNotification, object: pinch.scroll)
        pinch.update(1)
        #expect(!pinch.motion.isInteracting && pinch.pulses == 0)
    }

    @MainActor @Test
    func invalidatedOwnershipStopsFeedback() {
        let pinch = Pinch()
        pinch.begin()
        pinch.valid = false
        pinch.update(1)
        #expect(!pinch.motion.isInteracting && pinch.pulses == 0)
    }

    @MainActor @Test
    func hidingTheCanvasStopsFeedback() {
        let pinch = Pinch()
        pinch.begin()
        pinch.canvas.isHidden = true
        pinch.update(1)
        #expect(!pinch.motion.isInteracting && pinch.pulses == 0)
    }

    @MainActor @Test
    func anotherScrollViewCannotEndThePinch() {
        let pinch = Pinch()
        pinch.begin()
        let other = NSScrollView()
        NotificationCenter.default.post(name: NSScrollView.didEndLiveMagnifyNotification, object: other)
        #expect(pinch.motion.isInteracting)
    }

    @MainActor @Test
    func replacingTheScrollOwnerRetiresThePinch() {
        let pinch = Pinch()
        pinch.begin()
        let other = NSScrollView()
        pinch.motion.bind(other)
        pinch.update(1)
        #expect(!pinch.motion.isInteracting && pinch.pulses == 0)
    }

    @MainActor @Test
    func explicitCancellationSettlesAnnotations() {
        let pinch = Pinch()
        pinch.begin()
        let previousSettles = pinch.settles
        pinch.motion.cancel()
        pinch.update(1)
        #expect(!pinch.motion.isInteracting && pinch.pulses == 0)
        #expect(pinch.settles > previousSettles)
    }

    @MainActor @Test(arguments: [false, true])
    func annotationVisibilityChangesSynchronously(reduceMotion: Bool) {
        let annotation = MotionAnnotation()
        annotation.wantsLayer = true
        EaselCanvasMotion.setAnnotationHidden(true, view: annotation, animated: true, reduceMotion: reduceMotion)
        #expect(annotation.isHidden, "Hide updates input visibility synchronously")
        #expect(annotation.duration == (reduceMotion ? 0 : 0.1))
        #expect(annotation.implicit == !reduceMotion)
        EaselCanvasMotion.setAnnotationHidden(false, view: annotation, animated: true, reduceMotion: reduceMotion)
        #expect(!annotation.isHidden, "Immediate reversal cannot be undone by a delayed completion")
    }

    @MainActor @Test
    func nonanimatedRetirementSettlesHiddenAnnotations() {
        let annotation = MotionAnnotation(); annotation.wantsLayer = true
        EaselCanvasMotion.setAnnotationHidden(true, view: annotation, animated: false)
        EaselCanvasMotion.settle(annotation)
        #expect(annotation.isHidden && annotation.layer?.animationKeys() == nil, "Nonanimated retirement settles without reviving a hidden control")
        #expect(annotation.duration == 0 && !annotation.implicit, "Retirement disables native implicit motion")
    }

}
