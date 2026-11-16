import AppKit

private final class HapticGestureEvent: NSEvent {
    let eventPhase: NSEvent.Phase
    let angle: Float
    let delta: CGFloat
    let location: NSPoint
    init(over view: NSView? = nil, phase: NSEvent.Phase = [], angle: Float = 0, delta: CGFloat = 0) {
        eventPhase = phase; self.angle = angle; self.delta = delta
        location = view.map { $0.convert(NSPoint(x: $0.bounds.midX, y: $0.bounds.midY), to: nil) } ?? .zero
        super.init()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override var locationInWindow: NSPoint { location }
    override var phase: NSEvent.Phase { eventPhase }
    override var momentumPhase: NSEvent.Phase { [] }
    override var rotation: Float { angle }
    override var scrollingDeltaY: CGFloat { delta }
    override var timestamp: TimeInterval { ProcessInfo.processInfo.systemUptime }
}

@main @MainActor
struct SpaceThemeHapticTests {
    static var assertions = 0
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String, line: Int = #line) {
        assertions += 1
        guard condition() else { fatalError("Line \(line): \(message)") }
    }
    static func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
    static func control(_ label: String, in view: NSView) -> NSView {
        guard let result = descendants(view).first(where: { $0.accessibilityLabel() == label }) else {
            fatalError("Missing production control: \(label)")
        }
        return result
    }
    static func event(_ type: NSEvent.EventType, in view: NSView, point: NSPoint) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: view.convert(point, to: nil), modifierFlags: [],
                          timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: 0, context: nil,
                          eventNumber: 0, clickCount: 1, pressure: 0)!
    }
    static func predicateChecks() {
        expect(NSHapticFeedbackManager.FeedbackPattern.generic.rawValue == 0, "Native generic pattern matches the recovered ABI")
        expect(NSHapticFeedbackManager.PerformanceTime.now.rawValue == 1, "Native immediate timing matches the recovered ABI")
        for gesture in [SpaceThemeNoiseGesture.rotation, .drag] {
            expect(!ThemeHapticFeedback.shouldPerformNoise(from: 0.21, to: 0.29, gesture: gesture), "Motion inside one noise interval is silent")
            expect(ThemeHapticFeedback.shouldPerformNoise(from: 0.19, to: 0.2, gesture: gesture), "Arriving at a noise detent emits")
            expect(ThemeHapticFeedback.shouldPerformNoise(from: 0.2, to: 0.21, gesture: gesture), "Leaving the same detent is a separate effect")
            expect(ThemeHapticFeedback.shouldPerformNoise(from: 0.21, to: 0.19, gesture: gesture), "Reversal across a detent emits")
            expect(ThemeHapticFeedback.shouldPerformNoise(from: 0.05, to: 0.95, gesture: gesture), "A jump across many detents qualifies once")
            expect(!ThemeHapticFeedback.shouldPerformNoise(from: 0.2, to: 0.2, gesture: gesture), "Repeated detent values are silent")
        }
        for gesture in [SpaceThemeNoiseGesture.slider, .dialClick, .scrollWheel] {
            expect(!ThemeHapticFeedback.shouldPerformNoise(from: 0, to: 1, gesture: gesture), "Nonphysical or discrete noise route stays silent: \(gesture)")
        }
        expect(!ThemeHapticFeedback.shouldPerformIntensity(from: 0.21, to: 0.39), "Intensity ignores the intermediate noise detent")
        expect(ThemeHapticFeedback.shouldPerformIntensity(from: 0.39, to: 0.4), "Intensity arrival at a fifth emits")
        expect(ThemeHapticFeedback.shouldPerformIntensity(from: 0.4, to: 0.41), "Intensity departure includes its old endpoint")
        expect(ThemeHapticFeedback.shouldPerformIntensity(from: 0.41, to: 0.39), "Intensity reversal emits")
        expect(ThemeHapticFeedback.shouldPerformIntensity(from: 0, to: 0.01), "Leaving zero emits")
        expect(ThemeHapticFeedback.shouldPerformIntensity(from: 0.99, to: 1), "Arriving at one emits")
        expect(!ThemeHapticFeedback.shouldPerformIntensity(from: 1, to: 1), "Repeated limit input is silent")
        expect(!ThemeHapticFeedback.shouldPerformIntensity(from: .nan, to: 0.4), "Invalid old value cannot produce feedback")
        expect(!ThemeHapticFeedback.shouldPerformIntensity(from: 0.4, to: .infinity), "Invalid proposed value cannot produce feedback")
    }
    static func intensityChecks() {
        var baseline = SpaceTheme.singleColor(ThemeColor(hex: "6688AA")!)
        baseline.intensity = 0.35
        var pulses = 0, commits = 0
        let view = SpaceThemeEditorView(theme: baseline, performHapticFeedback: { pulses += 1 })
        view.onCommit = { _ in commits += 1 }
        view.layoutSubtreeIfNeeded()
        let intensity = control("Theme intensity", in: view)
        _ = intensity.accessibilityPerformIncrement()
        expect(pulses == 0, "Floating point value just below the detent does not invent tolerance")
        _ = intensity.accessibilityPerformIncrement()
        expect(pulses == 1, "The real intensity action emits after crossing the detent")
        _ = intensity.accessibilityPerformIncrement()
        expect(pulses == 1 && commits == 3, "An interior change commits without feedback")
        view.undo(nil); view.redo(nil)
        expect(pulses == 1, "Local Undo and Redo never replay the physical effect")
        baseline.intensity = 1
        view.synchronizeTheme(baseline)
        _ = intensity.accessibilityPerformIncrement()
        expect(pulses == 1, "Parent refresh and clamped no-op do not emit")

        baseline.intensity = 0.1
        view.synchronizeTheme(baseline)
        let start = NSPoint(x: 16 + (intensity.bounds.width - 32) * 0.1, y: intensity.bounds.midY)
        let end = NSPoint(x: 16 + (intensity.bounds.width - 32) * 0.9, y: intensity.bounds.midY)
        intensity.mouseDown(with: event(.leftMouseDown, in: intensity, point: start))
        let beforeDrag = pulses
        intensity.mouseDragged(with: event(.leftMouseDragged, in: intensity, point: end))
        expect(pulses == beforeDrag + 1, "One physical intensity update crossing four detents emits once")
        intensity.mouseUp(with: event(.leftMouseUp, in: intensity, point: end))
        view.finishEditing()
        expect(pulses == beforeDrag + 1, "Release and commit do not add a pulse")

        intensity.mouseDown(with: event(.leftMouseDown, in: intensity, point: start))
        baseline.intensity = 0.3
        view.synchronizeTheme(baseline)
        let beforeCancelledInput = pulses
        intensity.mouseDragged(with: event(.leftMouseDragged, in: intensity, point: end))
        intensity.mouseUp(with: event(.leftMouseUp, in: intensity, point: end))
        expect(view.theme == baseline && pulses == beforeCancelledInput, "Parent replacement rejects inherited intensity input before feedback")
    }
    static func noiseAndSilentActionChecks() {
        var baseline = SpaceTheme.singleColor(ThemeColor(hex: "6688AA")!)
        baseline.noise = 0.15
        var pulses = 0
        let view = SpaceThemeEditorView(theme: baseline, performHapticFeedback: { pulses += 1 })
        view.layoutSubtreeIfNeeded()
        let noise = control("Theme texture and noise", in: view)
        noise.rotate(with: HapticGestureEvent(over: noise, phase: .began))
        noise.rotate(with: HapticGestureEvent(over: noise, phase: .changed, angle: 180))
        expect(pulses == 1, "An admitted physical rotation emits one detent effect")
        noise.rotate(with: HapticGestureEvent(over: noise, phase: .ended))
        view.finishEditing()
        expect(pulses == 1, "Rotation release has no extra effect")
        noise.rotate(with: HapticGestureEvent(over: noise, phase: .began, angle: 45))
        let beforeReplacement = pulses
        baseline.noise = 0.35
        view.synchronizeTheme(baseline)
        noise.rotate(with: HapticGestureEvent(over: noise, phase: .changed, angle: 180))
        noise.rotate(with: HapticGestureEvent(over: noise, phase: .ended))
        expect(pulses == beforeReplacement && view.theme == baseline, "Cancelled physical rotation is silent after parent replacement")
        _ = noise.accessibilityPerformIncrement()
        _ = noise.accessibilityPerformDecrement()
        _ = noise.accessibilityPerformPress()
        let center = NSPoint(x: noise.bounds.midX, y: noise.bounds.midY)
        noise.mouseMoved(with: event(.mouseMoved, in: noise, point: center))
        let beforeScroll = view.theme.noise
        noise.scrollWheel(with: HapticGestureEvent(phase: .began, delta: 1))
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.03))
        expect(view.theme.noise != beforeScroll && pulses == beforeReplacement, "Delivered physical scroll changes noise without feedback")
        noise.scrollWheel(with: HapticGestureEvent(phase: .ended))
        (control("Add color", in: view) as! NSButton).performClick(nil)
        view.finishEditing(); view.undo(nil); view.redo(nil)
        expect(pulses == beforeReplacement, "Noise slider/texture/scroll, color count and Undo routes stay silent")

        baseline.noise = 0.05
        view.synchronizeTheme(baseline)
        let top = NSPoint(x: noise.bounds.midX, y: 4)
        let bottom = NSPoint(x: noise.bounds.midX, y: noise.bounds.height - 4)
        noise.mouseDown(with: event(.leftMouseDown, in: noise, point: top))
        noise.mouseDragged(with: event(.leftMouseDragged, in: noise, point: bottom))
        expect(pulses == beforeReplacement + 1, "One physical noise drag crossing several detents emits once")
        noise.mouseDragged(with: event(.leftMouseDragged, in: noise, point: bottom))
        noise.mouseUp(with: event(.leftMouseUp, in: noise, point: bottom))
        expect(pulses == beforeReplacement + 1, "Repeated quantized drag values and release are silent")
        noise.mouseDown(with: event(.leftMouseDown, in: noise, point: top))
        noise.mouseUp(with: event(.leftMouseUp, in: noise, point: top))
        expect(pulses == beforeReplacement + 1, "Dial clicks stay silent even when they cross noise detents")
    }
    static func main() { exitOnFailure(runChecks) }
    static func runChecks() {
        _ = NSApplication.shared
        predicateChecks()
        intensityChecks()
        noiseAndSilentActionChecks()
        print("Space theme haptics: \(assertions) assertions passed")
    }
}
