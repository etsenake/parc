import AppKit

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

@main struct EaselMotionTests {
    @MainActor static var count = 0
    @MainActor static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        count += 1
        precondition(condition(), message)
    }

    @MainActor static func main() {
        _ = NSApplication.shared
        var below = EaselZoomInteraction(zoom: 0.8)!
        expect(!below.record(0.99), "Approaching actual size is silent")
        expect(below.record(1), "Upward crossing includes exactly one")
        expect(!below.record(1) && !below.record(1.1), "Same side and same value are silent")
        expect(!below.record(0.9) && below.record(1.01), "A later upward recross retains original gesture direction")
        var above = EaselZoomInteraction(zoom: 1.2)!
        expect(!above.record(1.01) && above.record(1), "Downward crossing includes exactly one")
        expect(!above.record(0.9) && !above.record(1.1) && above.record(0.99), "Downward gesture can recross only downward")
        for start: CGFloat in [0.99, 1, 1.01] {
            var band = EaselZoomInteraction(zoom: start)!
            expect(!band.record(0.8) && !band.record(1.2) && !band.record(1), "Inclusive initial band is silent for the entire pinch")
        }
        expect(EaselZoomInteraction(zoom: .nan) == nil && EaselZoomInteraction(zoom: 0) == nil,
               "Invalid initial magnification is refused")
        var finite = EaselZoomInteraction(zoom: 0.8)!
        expect(!finite.record(.infinity) && finite.previous == 0.8 && finite.record(1), "Invalid updates preserve the actual previous value")

        let window = MotionWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 400),
                                  styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.contentView = nil; window.close() }
        let scroll = NSScrollView(frame: window.contentView!.bounds)
        let canvas = NSView(frame: NSRect(x: 0, y: 0, width: 1000, height: 1000))
        scroll.allowsMagnification = true; scroll.minMagnification = 0.1; scroll.maxMagnification = 4
        scroll.documentView = canvas; window.contentView = scroll
        var valid = true, pulses = 0, changes = 0, settled = 0
        let owner = EaselCanvasMotion(owner: canvas, validOwner: { valid },
            changed: { changes += 1 }, settleAnnotations: { settled += 1 }, feedback: { pulses += 1 })
        owner.bind(scroll)
        func begin() { NotificationCenter.default.post(name: NSScrollView.willStartLiveMagnifyNotification, object: scroll) }
        func update(_ zoom: CGFloat) {
            scroll.magnification = zoom
            NotificationCenter.default.post(name: NSView.boundsDidChangeNotification, object: scroll.contentView)
        }
        update(0.8); update(1.1)
        expect(pulses == 0 && !owner.isInteracting, "Programmatic magnification without a pinch is silent")
        update(0.8); begin()
        expect(owner.isInteracting, "Live magnification claims the original pair")
        update(1)
        expect(pulses == 1, "Real native magnification feeds the injected feedback boundary once")
        update(1.1)
        NotificationCenter.default.post(name: NSScrollView.didEndLiveMagnifyNotification, object: scroll)
        expect(!owner.isInteracting, "Pinch end retires the interaction")
        update(0.8); update(1)
        expect(pulses == 1, "A retired pinch cannot emit feedback")
        update(0.8); begin(); valid = false; update(1)
        expect(!owner.isInteracting && pulses == 1, "Closed document ownership retires before feedback")
        valid = true; update(0.8); begin(); canvas.isHidden = true; update(1)
        expect(!owner.isInteracting && pulses == 1, "Hidden source cannot emit feedback")
        canvas.isHidden = false; update(0.8); begin()
        let other = NSScrollView()
        NotificationCenter.default.post(name: NSScrollView.didEndLiveMagnifyNotification, object: other)
        expect(owner.isInteracting, "Another scroll view cannot end this pinch")
        owner.bind(other)
        update(1)
        expect(!owner.isInteracting && pulses == 1, "Replacement detaches old notification ownership")
        owner.bind(scroll); update(0.8); begin(); owner.cancel(); update(1)
        expect(!owner.isInteracting && pulses == 1 && settled > 0 && changes > 0, "Explicit retirement clears feedback and settles owned annotations")
        let annotation = MotionAnnotation(); annotation.wantsLayer = true
        EaselCanvasMotion.setAnnotationHidden(true, view: annotation, animated: true)
        expect(annotation.isHidden, "Hide updates input visibility synchronously")
        let reducesMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        expect(annotation.duration == (reducesMotion ? 0 : 0.1) && annotation.implicit == !reducesMotion,
               "The real native hidden setter receives the recovered group and current motion preference")
        EaselCanvasMotion.setAnnotationHidden(false, view: annotation, animated: true)
        expect(!annotation.isHidden, "Immediate reversal cannot be undone by a delayed completion")
        EaselCanvasMotion.setAnnotationHidden(true, view: annotation, animated: false)
        EaselCanvasMotion.settle(annotation)
        expect(annotation.isHidden && annotation.layer?.animationKeys() == nil, "Nonanimated retirement settles without reviving a hidden control")
        expect(annotation.duration == 0 && !annotation.implicit, "Retirement disables native implicit motion")
        print("Easel motion: \(count) assertions passed")
    }
}
