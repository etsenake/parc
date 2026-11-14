import AppKit
import SceneKit

@MainActor final class RecordingOutput: WindowFrameCrankSoundOutput {
    var played: [WindowFrameCrankCue] = []
    var stops = 0
    var warms = 0
    func warm() { warms += 1 }
    func play(_ cue: WindowFrameCrankCue) { played.append(cue) }
    func stop() { stops += 1 }
}

@MainActor final class Harness {
    let window: NSWindow
    let view: WindowFrameCrankView
    let output = RecordingOutput()
    var haptics: [NSHapticFeedbackManager.FeedbackPattern] = []
    var events: [WindowFrameCrank.Event] = []
    var previews: [CGFloat] = []
    var finishes: [(Bool, Int)] = []
    var reduceMotion = false
    var clock = 0.0

    init(value: Int, palette: WindowFrameCrankPalette) {
        window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 800, height: 600), styleMask: [.borderless],
                          backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let box = Box()
        let feedback = WindowFrameCrankFeedback(allowsSound: { true }, haptic: { box.haptic?($0) }, output: { box.output! },
                                                now: { box.now?() ?? 0 })
        view = WindowFrameCrankView(value: value, palette: palette, feedback: feedback, reducesMotion: { box.reduce?() ?? false })
        box.output = output
        box.haptic = { [weak self] in self?.haptics.append($0) }
        box.now = { [weak self] in self?.clock ?? 0 }
        box.reduce = { [weak self] in self?.reduceMotion ?? false }
        view.frame.origin = CGPoint(x: 40, y: 30)
        window.contentView?.addSubview(view)
        view.onEvent = { [weak self] in self?.events.append($0) }
        view.onPreview = { [weak self] in self?.previews.append($0) }
        view.onFinish = { [weak self] in self?.finishes.append(($0, $1)) }
    }

    func run(_ seconds: Double, step: Double = 1.0 / 60) {
        var t = 0.0
        while t < seconds { view.advance(by: step); clock += step; t += step }
    }

    func windowPoint(_ local: CGPoint) -> CGPoint { view.convert(local, to: nil) }
    func superPoint(_ local: CGPoint) -> CGPoint { view.convert(local, to: view.superview) }

    func mouse(_ type: NSEvent.EventType, _ local: CGPoint) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: windowPoint(local), modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                           context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
    }

    func key(_ code: UInt16) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                         context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code)!
    }

    func scroll(_ delta: Int32, precise: Bool, phase: Int64 = 0, momentum: Int64 = 0, horizontal: Int32 = 0) -> NSEvent {
        let event = CGEvent(scrollWheelEvent2Source: nil, units: precise ? .pixel : .line, wheelCount: 2, wheel1: delta, wheel2: horizontal,
                            wheel3: 0)!
        event.setIntegerValueField(.scrollWheelEventScrollPhase, value: phase)
        event.setIntegerValueField(.scrollWheelEventMomentumPhase, value: momentum)
        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: precise ? 1 : 0)
        return NSEvent(cgEvent: event)!
    }
}

final class FocusView: NSView {
    override var acceptsFirstResponder: Bool { true }
}

@MainActor final class Box {
    var output: RecordingOutput?
    var haptic: ((NSHapticFeedbackManager.FeedbackPattern) -> Void)?
    var now: (() -> Double)?
    var reduce: (() -> Bool)?
}

@main @MainActor struct WindowFrameViewTests {
    static var count = 0
    static func check(_ value: @autoclosure () -> Bool, _ message: String) {
        count += 1
        guard value() else { fatalError("WindowFrame view: \(message)") }
    }
    static func near(_ a: CGFloat, _ b: CGFloat, _ tolerance: CGFloat = 0.01) -> Bool { abs(a - b) < tolerance }
    static func near(_ a: CGPoint, _ b: CGPoint, _ tolerance: CGFloat = 0.01) -> Bool { hypot(a.x - b.x, a.y - b.y) < tolerance }

    static let light = WindowFrameCrankPalette(accent: NSColor(srgbRed: 0.76, green: 0.31, blue: 0.42, alpha: 1),
                                               deep: NSColor(srgbRed: 0.93, green: 0.59, blue: 0.71, alpha: 1),
                                               cap: NSColor(srgbRed: 0.90, green: 0.56, blue: 0.62, alpha: 1), dark: false)
    static let dark = WindowFrameCrankPalette(accent: NSColor(srgbRed: 0.30, green: 0.55, blue: 1, alpha: 1),
                                              deep: NSColor(srgbRed: 0.05, green: 0.06, blue: 0.08, alpha: 1),
                                              cap: NSColor(srgbRed: 0.14, green: 0.15, blue: 0.18, alpha: 1), dark: true)

    static func main() {
        _ = NSApplication.shared
        geometry()
        transitions()
        turning()
        dismissal()
        handoff()
        focus()
        leaving()
        gestures()
        drawing()
        print("WindowFrame view: \(count) checks passed")
    }

    static func geometry() {
        let model = WindowFrameCrankModel(side: WindowFrameCrankView.side, palette: light)
        let reach = WindowFrameCrankModel.armLength * WindowFrameCrankModel.scale
        model.setArm(degrees: 90)
        check(near(model.knobCenter, CGPoint(x: 0, y: reach), 0.05), "the arm points up at 90 degrees")
        model.setArm(degrees: -30)
        check(near(model.knobCenter, CGPoint(x: reach * cos(.pi / 6), y: -reach / 2), 0.05), "the arm follows the model's angle")
        check(model.ghostRotors.count == WindowFrameCrankModel.shadowSpread.count, "every shadow ghost turns with the crank")
        check(model.ghostRotors.allSatisfy { near($0.eulerAngles.z, model.rotor.eulerAngles.z, 0.0001) }, "the shadow follows the arm")
        let (low, high) = model.rotor.boundingBox
        let scale = WindowFrameCrankModel.scale
        check(abs(high.x * scale - WindowFrameCrankPlacement.swingRadius) < 2, "the knob sweeps the placement radius (\(high.x * scale))")
        check((high.x - low.x) * scale > 100 && (high.x - low.x) * scale < 112, "the crank is about 105 points long (\((high.x - low.x) * scale))")
        check(WindowFrameCrankView.side >= 2 * WindowFrameCrankPlacement.extent, "the view holds the whole lights circle")
        check(model.scene.lightingEnvironment.contents != nil, "the metal is lit by an environment")
        let environment = WindowFrameCrankModel.cachedEnvironment(deep: light.deep, dark: false)
        check(environment != nil && (model.scene.lightingEnvironment.contents as AnyObject) === environment,
              "the environment is drawn once per palette")
        let cached = WindowFrameCrankModel.cachedEnvironmentCount
        model.apply(dark)
        check(near(model.scene.lightingEnvironment.intensity, 1.6, 0.001), "dark palettes relight the metal")
        model.apply(light)
        model.apply(dark)
        check(WindowFrameCrankModel.cachedEnvironmentCount == cached + 1, "switching back and forth reuses the drawn environments")
        let twin = WindowFrameCrankModel(side: WindowFrameCrankView.side, palette: dark)
        check(twin.arm?.geometry != nil && twin.arm?.geometry === model.arm?.geometry, "the crank is built once and cloned")
        check(twin.knob !== model.knob && twin.rotor.childNodes.count == model.rotor.childNodes.count, "each view gets its own crank nodes")

        let arm = WindowFrameCrankModel.positions(model.arm?.geometry ?? SCNGeometry())
        let knobEnd = arm.filter { $0.x > 45 }.map(\.z), hubEnd = arm.filter { $0.x < 5 }.map(\.z)
        let rise = (knobEnd.max() ?? 0) - (hubEnd.max() ?? 0)
        check(!knobEnd.isEmpty && !hubEnd.isEmpty && abs(rise - WindowFrameCrankModel.paddleLift) < 0.5, "the paddle bends up toward the knob (\(rise))")
        check(WindowFrameCrankModel.paddleGeometry(depth: WindowFrameCrankModel.paddleDepth) === WindowFrameCrankModel.paddleGeometry(depth: WindowFrameCrankModel.paddleDepth),
              "the paddle is bent once per depth")
        let planes = model.scene.rootNode.childNodes { node, _ in node.geometry is SCNPlane }
        check(planes.count == 1, "the PARC label casts no shadow")
        check(model.shadowParts > 0 && model.shadowParts < model.root.childNodes { node, _ in node.geometry != nil }.count,
              "tiny parts cast no shadow")
    }

    static func transitions() {
        typealias V = WindowFrameCrankView
        check(V.presentation(0, reduceMotion: false) == (0, V.slideDistance), "it starts out in the corner")
        check(V.presentation(V.presentDuration, reduceMotion: false) == (1, 0), "it lands in place")
        check((0..<42).contains { V.presentation(Double($0) / 100, reduceMotion: false).offset < 0 }, "it springs a little past")
        check(V.presentation(0.05, reduceMotion: true).offset == 0 && V.presentation(0.1, reduceMotion: true).alpha > 0, "Reduce Motion fades in place")
        check(V.dismissal(V.dismissDuration, reduceMotion: false).alpha == 0 && V.dismissal(0.1, reduceMotion: true).offset == 0, "it leaves fully")
        check(V.settleRemaining(0, reduceMotion: false) == 1 && V.settleRemaining(V.settleDuration, reduceMotion: false) == nil, "the spring settles")
        check((0..<42).contains { (V.settleRemaining(Double($0) / 100, reduceMotion: false) ?? 0) < 0 }, "the spring overshoots slightly")
        check((0..<15).allSatisfy { (V.settleRemaining(Double($0) / 100, reduceMotion: true) ?? 0) >= 0 }, "Reduce Motion does not overshoot")

        let h = Harness(value: 10, palette: light)
        let view = h.view
        check(view.phase == .idle && view.alphaValue == 0 && view.sceneView.isHidden, "it waits hidden until presented")
        check(view.hitTest(h.superPoint(view.hub)) == nil, "a hidden crank never catches clicks")
        view.present()
        check(view.phase == .presenting && h.window.firstResponder === view && !view.sceneView.isHidden, "presenting takes the keyboard and renders")
        check(view.stageOffset.x < 0 && view.stageOffset.y < 0, "it slides in from the lower left")
        check(view.isAnimating, "presenting animates")
        h.run(0.5)
        check(view.phase == .shown && view.alphaValue == 1 && view.stageOffset == .zero, "it settles in place")
        check(view.hitTest(h.superPoint(view.hub)) === view, "the hub catches clicks")
        check(view.hitTest(h.superPoint(CGPoint(x: view.hub.x + WindowFrameCrankPlacement.extent - 1, y: view.hub.y))) === view, "the lights catch clicks")
        check(view.hitTest(h.superPoint(CGPoint(x: view.hub.x + WindowFrameCrankPlacement.extent + 2, y: view.hub.y))) == nil, "clicks past the lights reach the page")
        check(view.hitTest(h.superPoint(CGPoint(x: 2, y: 2))) == nil, "the corners stay transparent to clicks")
        check(!view.isAnimating, "it stops ticking when still")
        check(view.isAccessibilityElement() && view.accessibilityRole() == .slider && view.accessibilityLabel() == "Window frame", "VoiceOver reads a slider")
        check(view.accessibilityValueDescription() == "10 points, Classic", "VoiceOver reads the value and name")
        check((view.accessibilityValue() as? NSNumber)?.intValue == 10, "the slider exposes its number")
        check((view.accessibilityMinValue() as? NSNumber)?.intValue == 3 && (view.accessibilityMaxValue() as? NSNumber)?.intValue == 13,
              "the slider exposes its range")
        check(view.accessibilityPerformIncrement() && view.crank.value == 11 && view.accessibilityValueDescription() == "11 points, Roomy", "VoiceOver can increment")
        check(view.accessibilityPerformDecrement() && view.crank.value == 10, "VoiceOver can decrement")
        view.palette = dark
        check(view.lights.palette == dark && near(view.model.scene.lightingEnvironment.intensity, 1.6, 0.001), "palette changes reach the lights and the metal")

        let calm = Harness(value: 10, palette: light)
        calm.reduceMotion = true
        calm.view.present()
        var offsets: [CGPoint] = []
        for _ in 0..<20 { calm.run(1.0 / 60); offsets.append(calm.view.stageOffset) }
        check(offsets.allSatisfy { $0 == .zero } && calm.view.alphaValue == 1, "Reduce Motion fades in without sliding")
        check(!h.window.isVisible && !calm.window.isVisible, "the checks never put a window on screen")

        let early = Harness(value: 10, palette: light)
        early.view.present()
        early.run(0.05)
        let alpha = early.view.alphaValue, offset = early.view.stageOffset
        check(alpha > 0 && alpha < 0.9, "it is still fading in")
        early.view.dismiss(commit: true)
        early.run(1.0 / 60)
        check(early.view.alphaValue <= alpha && early.view.stageOffset.x <= offset.x + 0.001 && early.view.stageOffset.x > offset.x - 2,
              "leaving mid-entrance carries on from where it was")
        check(V.dismissal(0, reduceMotion: false, from: (0.3, 5)) == (0.3, 5), "the exit starts from the entrance's state")
    }

    static func turning() {
        let h = Harness(value: 10, palette: light)
        let view = h.view
        view.present()
        h.run(0.5)

        view.keyDown(with: h.key(126))
        check(view.crank.value == 11 && h.events == [.notch(11)], "the up arrow adds a point")
        check(h.output.played == [.notch(11)] && h.haptics == [.alignment], "the notch clicks and ticks before the owner hears it")
        check(view.lights.litCount == 9 && view.lights.readout == 11, "the next light comes on and the readout follows")
        check(!view.lights.sparkles.isEmpty && view.lights.pop[8] < WindowFrameCrankLightsView.popDuration, "the new light pops with sparkles")
        h.run(1)
        check(h.previews.last == 11 && h.previews.max()! < 11.2 && h.previews.max()! > 11, "the frame springs to 11 with a small overshoot")
        check(view.lights.sparkles.isEmpty && !view.lights.isAnimating && !view.isAnimating, "sparkles fade and the timer stops")
        check(near(CGFloat(view.model.armDegrees), CGFloat(view.crank.armDegrees), 0.0001), "the arm rests at the model's angle")
        view.keyDown(with: h.key(123))
        view.keyDown(with: h.key(125))
        check(view.crank.value == 9 && h.events.suffix(2) == [.notch(10), .notch(9)], "left and down take points away")
        view.keyDown(with: h.key(124))
        check(view.crank.value == 10, "right adds a point")
        h.run(1)

        var reference = WindowFrameCrank(value: 10)
        let began = h.scroll(40, precise: true, phase: 1)
        let changed = h.scroll(40, precise: true, phase: 2)
        view.scrollWheel(with: began)
        view.scrollWheel(with: changed)
        reference.turn(degrees: WindowFrameCrank.scrollDegrees(deltaY: Double(began.scrollingDeltaY), precise: began.hasPreciseScrollingDeltas))
        reference.turn(degrees: WindowFrameCrank.scrollDegrees(deltaY: Double(changed.scrollingDeltaY), precise: changed.hasPreciseScrollingDeltas))
        check(began.hasPreciseScrollingDeltas && began.scrollingDeltaY != 0, "the synthetic scroll is a trackpad scroll")
        check(view.crank == reference && h.previews.last == CGFloat(reference.displayed), "a trackpad scroll turns the crank 1:1")
        let held = view.crank
        view.scrollWheel(with: h.scroll(400, precise: true, momentum: 2))
        check(view.crank == held, "momentum does not keep turning")
        view.scrollWheel(with: h.scroll(0, precise: true, phase: 4))
        reference.release()
        check(view.crank == reference, "lifting the fingers settles to the nearest point")
        h.run(1)
        check(h.previews.last == CGFloat(reference.value), "the frame lands on the settled point")

        let wheelStart = view.crank.value
        let line = h.scroll(-3, precise: false)
        check(!line.hasPreciseScrollingDeltas && line.phase.isEmpty, "the synthetic wheel is a plain mouse wheel")
        view.scrollWheel(with: line)
        check(view.crank.displayed != Double(view.crank.value) || view.crank.value != wheelStart, "a wheel click turns the crank")
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.4))
        check(view.crank.displayed == Double(view.crank.value), "the wheel lets go after a short pause")
        h.run(1)

        let hub = view.hub
        let start = view.crank.value
        let r: CGFloat = 60
        view.mouseDown(with: h.mouse(.leftMouseDown, CGPoint(x: hub.x, y: hub.y + r)))
        for k in 1...12 {
            let a = (90 - CGFloat(k) * 10) * .pi / 180
            view.mouseDragged(with: h.mouse(.leftMouseDragged, CGPoint(x: hub.x + r * cos(a), y: hub.y + r * sin(a))))
        }
        check(view.crank.value == start + 1 && h.events.last == .notch(start + 1), "dragging a third of a turn clockwise adds a point")
        view.mouseUp(with: h.mouse(.leftMouseUp, CGPoint(x: hub.x + r, y: hub.y)))
        check(view.crank.displayed == Double(start + 1), "letting go of the knob settles")
        h.run(1)
        let before = view.crank
        view.mouseDown(with: h.mouse(.leftMouseDown, CGPoint(x: hub.x, y: hub.y + 100)))
        view.mouseDragged(with: h.mouse(.leftMouseDragged, CGPoint(x: hub.x + 100, y: hub.y)))
        view.mouseUp(with: h.mouse(.leftMouseUp, CGPoint(x: hub.x + 100, y: hub.y)))
        check(view.crank == before, "dragging on the lights does not turn it")

        for _ in 0..<12 { view.keyDown(with: h.key(126)) }
        check(view.crank.value == 13 && h.events.last == .end(.thick) && h.output.played.last == .end(.thick), "keys stop at 13 with a thunk")
        check(view.flash == 1, "the lights flash at the end")
        h.run(1)
        check(view.flash == 0, "the flash fades")
        view.turn(by: 60)
        check(h.events.last == .end(.thick) && view.crank.strain > 0 && view.flash == 1, "pushing past 13 gives and flashes")
        h.run(0.05)
        check(view.tremble != 0 && !near(CGFloat(view.model.armDegrees), CGFloat(view.crank.armDegrees), 0.0001), "the crank trembles while strained")
        check(view.isAnimating, "the tremble keeps ticking while held")
        h.reduceMotion = true
        h.run(0.05)
        check(view.tremble == 0, "Reduce Motion stills the tremble")
        view.releaseTurn()
        h.run(1)
        check(view.crank.value == 13 && h.previews.last == 13 && view.crank.strain == 0, "letting go springs back to 13")
        let sparkles = view.lights.sparkles.count
        view.keyDown(with: h.key(125))
        check(view.lights.sparkles.count == sparkles && view.lights.litCount == 10, "Reduce Motion lights without sparkles")
        h.run(1)
        check(h.previews.last == 12, "Reduce Motion still lands the frame")
    }

    static func dismissal() {
        let h = Harness(value: 10, palette: light)
        let view = h.view
        view.present()
        h.run(0.5)
        view.keyDown(with: h.key(126))
        view.keyDown(with: h.key(126))
        h.run(0.1)
        view.keyDown(with: h.key(53))
        check(view.phase == .dismissing(commit: false) && view.hitTest(h.superPoint(view.hub)) == nil, "Escape starts leaving and lets clicks through")
        check(view.lights.readout == 10 && view.lights.litCount == 8, "Escape shows the restored value")
        check(view.value == 10 && (view.accessibilityValue() as? NSNumber)?.intValue == 10 && view.accessibilityValueDescription() == "10 points, Classic",
              "VoiceOver hears the restored value while it leaves")
        view.keyDown(with: h.key(126))
        check(view.crank.value == 12, "keys stop working while it leaves")
        h.run(0.6)
        check(h.finishes.count == 1 && h.finishes[0] == (false, 10), "Escape finishes once with the original value")
        check(h.previews.contains { $0 > 10.5 } && h.previews.last == 10, "Escape winds the frame back")
        check(view.phase == .finished && view.sceneView.isHidden && view.alphaValue == 0 && !view.isAnimating, "it stops rendering when gone")
        check(h.output.stops == 1, "it lets the audio rest")
        view.dismiss(commit: true)
        h.run(0.5)
        check(h.finishes.count == 1, "a second dismiss does nothing")

        let keep = Harness(value: 7, palette: dark)
        keep.view.present()
        keep.run(0.5)
        keep.view.keyDown(with: keep.key(125))
        keep.view.keyDown(with: keep.key(36))
        keep.run(0.5)
        check(keep.finishes.count == 1 && keep.finishes[0] == (true, 6), "Return keeps the new value")

        let held = Harness(value: 10, palette: light)
        held.view.present()
        held.run(0.5)
        held.view.turn(by: 80)
        held.view.dismiss(commit: true)
        held.run(0.6)
        check(held.finishes.count == 1 && held.finishes[0] == (true, 11), "leaving mid-turn keeps the nearest point")

        let away = Harness(value: 10, palette: light)
        away.view.present()
        away.run(0.5)
        NSApp.sendEvent(away.mouse(.leftMouseDown, CGPoint(x: away.view.hub.x, y: away.view.hub.y + 60)))
        check(away.view.phase == .shown, "a click on the crank keeps it")
        NSApp.sendEvent(away.mouse(.leftMouseDown, CGPoint(x: -20, y: -20)))
        check(away.view.phase == .dismissing(commit: true), "a click elsewhere in the window keeps the value and leaves")
        away.run(0.5)
        check(away.finishes.count == 1 && away.finishes[0] == (true, 10), "the click-away finishes once")
        away.view.removeFromSuperview()
    }

    static func handoff() {
        let h = Harness(value: 10, palette: light)
        h.view.present()
        h.run(0.5)
        h.view.turn(by: 80)
        check(h.view.value == 11, "the value is the point it would settle on")
        let previews = h.previews.count
        h.view.finishNow(commit: true)
        check(h.finishes.count == 1 && h.finishes[0] == (true, 11), "finishing now keeps the nearest point")
        check(h.previews.count == previews + 1 && h.previews.last == 11, "finishing now reports the final frame once")
        check(h.view.phase == .finished && !h.view.isAnimating && !h.view.isWaitingForGesture && h.view.alphaValue == 0, "finishing now stops at once")
        check(h.output.stops == 1 && h.view.value == 11, "finishing now lets the audio rest")
        h.view.finishNow(commit: false)
        h.view.dismiss(commit: false)
        check(h.finishes.count == 1, "it finishes only once")

        let back = Harness(value: 10, palette: light)
        back.view.present()
        back.run(0.5)
        back.view.keyDown(with: back.key(126))
        back.run(1)
        back.view.turn(by: 30)
        back.view.finishNow(commit: false)
        check(back.finishes.count == 1 && back.finishes[0] == (false, 10) && back.previews.last == 10 && back.view.value == 10,
              "finishing now without keeping restores the original")

        let still = Harness(value: 9, palette: light)
        still.view.present()
        still.run(0.5)
        let before = still.previews.count
        still.view.finishNow(commit: true)
        check(still.previews.count == before + 1 && still.previews.last == 9 && still.finishes[0] == (true, 9), "finishing now always reports the frame")

        let escaping = Harness(value: 10, palette: light)
        escaping.view.present()
        escaping.run(0.5)
        escaping.view.keyDown(with: escaping.key(126))
        escaping.view.keyDown(with: escaping.key(53))
        escaping.view.finishNow(commit: true)
        check(escaping.finishes.count == 1 && escaping.finishes[0] == (false, 10), "finishing now honours an Escape already under way")
    }

    static func focus() {
        let h = Harness(value: 10, palette: light)
        let field = FocusView(frame: NSRect(x: 600, y: 400, width: 60, height: 20))
        h.window.contentView?.addSubview(field)
        h.window.makeFirstResponder(field)
        h.view.present()
        h.run(0.5)
        check(h.window.firstResponder === h.view, "the crank takes the keyboard")
        h.view.keyDown(with: h.key(36))
        h.run(0.5)
        check(h.finishes.count == 1 && h.window.firstResponder === field, "focus goes back where it was")

        let gone = Harness(value: 10, palette: light)
        let old = FocusView(frame: NSRect(x: 600, y: 400, width: 60, height: 20))
        gone.window.contentView?.addSubview(old)
        gone.window.makeFirstResponder(old)
        gone.view.present()
        gone.run(0.5)
        old.removeFromSuperview()
        gone.view.keyDown(with: gone.key(36))
        gone.run(0.5)
        check(gone.finishes.count == 1 && gone.window.firstResponder !== old, "focus is left alone when the old view has gone")

        let taken = Harness(value: 10, palette: light)
        let other = FocusView(frame: NSRect(x: 600, y: 400, width: 60, height: 20))
        taken.window.contentView?.addSubview(other)
        taken.view.present()
        taken.run(0.5)
        taken.view.keyDown(with: taken.key(125))
        taken.window.makeFirstResponder(other)
        check(taken.view.phase == .dismissing(commit: true), "focus moving elsewhere keeps the value and leaves")
        taken.run(0.5)
        check(taken.finishes.count == 1 && taken.finishes[0] == (true, 9) && taken.window.firstResponder === other, "the new focus stays put")
    }

    static func leaving() {
        let held = Harness(value: 10, palette: light)
        held.view.present()
        held.run(0.5)
        held.view.turn(by: 80)
        held.view.removeFromSuperview()
        check(held.finishes.count == 1 && held.finishes[0] == (true, 11) && held.previews.last == 11, "leaving the window mid-turn finishes with the nearest point")
        check(held.view.phase == .finished && !held.view.isAnimating && held.output.stops == 1, "leaving the window stops everything")

        let escaping = Harness(value: 10, palette: light)
        escaping.view.present()
        escaping.run(0.5)
        escaping.view.keyDown(with: escaping.key(126))
        escaping.run(0.1)
        escaping.view.keyDown(with: escaping.key(53))
        escaping.run(0.05)
        check(escaping.previews.last != 10, "the frame is still winding back")
        escaping.view.removeFromSuperview()
        check(escaping.finishes.count == 1 && escaping.finishes[0] == (false, 10) && escaping.previews.last == 10, "leaving during Escape restores")

        let arriving = Harness(value: 8, palette: light)
        arriving.view.present()
        arriving.view.removeFromSuperview()
        check(arriving.finishes.count == 1 && arriving.finishes[0] == (true, 8) && !arriving.view.isAnimating, "leaving during the entrance finishes")

        let abandoned = Harness(value: 10, palette: light)
        abandoned.view.present()
        abandoned.run(0.5)
        abandoned.view.onPreview = nil
        abandoned.view.onEvent = nil
        abandoned.view.onFinish = nil
        abandoned.view.removeFromSuperview()
        check(abandoned.finishes.isEmpty && abandoned.output.stops == 1 && !abandoned.view.isAnimating, "an abandoned crank tears down quietly")
    }

    static func gestures() {
        let h = Harness(value: 10, palette: light)
        let view = h.view
        view.present()
        h.run(0.5)

        view.scrollWheel(with: h.scroll(30, precise: true, phase: 1))
        check(view.crank.displayed > 10.2 && view.isWaitingForGesture, "a trackpad turn waits for the fingers")
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.3))
        check(view.crank.displayed > 10.2, "a short pause keeps holding")
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.5))
        check(view.crank.displayed == Double(view.crank.value) && !view.isWaitingForGesture, "a lost gesture end still lets go")
        h.run(1)

        var reference = view.crank
        let sideways = h.scroll(0, precise: true, phase: 1, horizontal: 20)
        check(abs(sideways.scrollingDeltaX) > abs(sideways.scrollingDeltaY), "the synthetic scroll is sideways")
        view.scrollWheel(with: sideways)
        reference.turn(degrees: WindowFrameCrank.scrollDegrees(deltaY: Double(sideways.scrollingDeltaX), precise: true))
        check(view.crank == reference, "a sideways scroll turns the crank")
        view.scrollWheel(with: h.scroll(0, precise: true, phase: 4))
        h.run(1)
        check(WindowFrameCrankView.scrollDelta(x: 3, y: -1) == 3 && WindowFrameCrankView.scrollDelta(x: 1, y: -2) == -2, "the larger axis wins")

        view.keyDown(with: h.key(126))
        h.run(0.03)
        let shown = h.previews.last ?? 0
        check(abs(shown - CGFloat(view.crank.value)) > 0.05, "the key settle is still moving")
        view.turn(by: 1)
        check(abs((h.previews.last ?? 0) - (shown + 1 / 120)) < 0.0001, "grabbing mid-settle carries on from where it was")
        view.releaseTurn()
        h.run(1)

        for _ in 0..<12 { view.keyDown(with: h.key(126)) }
        h.run(1)
        view.turn(by: 40)
        view.releaseTurn()
        h.run(0.02)
        let strained = h.previews.last ?? 0
        check(strained > 13, "it springs back from the give")
        view.turn(by: -1)
        check(abs((h.previews.last ?? 0) - CGFloat(WindowFrameCrank.rubber(WindowFrameCrankView.raw(showing: Double(strained)) - 1.0 / 120))) < 0.0001,
              "grabbing during the spring-back carries on from the give")
        check(abs(WindowFrameCrank.rubber(WindowFrameCrankView.raw(showing: 13.2)) - 13.2) < 0.0001
              && abs(WindowFrameCrank.rubber(WindowFrameCrankView.raw(showing: 2.9)) - 2.9) < 0.0001, "the give inverts exactly")
    }

    static func drawing() {
        let h = Harness(value: 10, palette: light)
        let lights = h.view.lights
        let rep = lights.bitmapImageRepForCachingDisplay(in: lights.bounds)!
        lights.cacheDisplay(in: lights.bounds, to: rep)
        let scale = CGFloat(rep.pixelsWide) / lights.bounds.width
        func alpha(_ p: CGPoint) -> CGFloat {
            rep.colorAt(x: Int(p.x * scale), y: Int((lights.bounds.height - p.y) * scale))?.alphaComponent ?? 0
        }
        check(alpha(lights.pillCenter(0)) > 0.5 && alpha(lights.pillCenter(7)) > 0.5, "lit pills glow")
        check(alpha(lights.pillCenter(10)) > 0 && alpha(lights.pillCenter(10)) < alpha(lights.pillCenter(7)), "unlit pills are faint dashes")
        check(alpha(CGPoint(x: lights.bounds.midX + 50, y: lights.bounds.midY + 30)) == 0, "there is no backdrop behind the lights")
        check(alpha(CGPoint(x: lights.bounds.midX, y: lights.bounds.midY - WindowFrameCrankPlacement.lightsRadius)) > 0.8, "the readout sits under the arc")

        let renderer = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)
        renderer.scene = h.view.model.scene
        renderer.pointOfView = h.view.model.camera
        renderer.autoenablesDefaultLighting = false
        let side = WindowFrameCrankView.side
        let image = renderer.snapshot(atTime: 0, with: CGSize(width: side, height: side), antialiasingMode: .none)
        var rect = CGRect(origin: .zero, size: image.size)
        let crank = NSBitmapImageRep(cgImage: image.cgImage(forProposedRect: &rect, context: nil, hints: nil)!)
        func crankAlpha(_ p: CGPoint) -> CGFloat {
            crank.colorAt(x: Int(p.x * CGFloat(crank.pixelsWide) / side), y: Int((side - p.y) * CGFloat(crank.pixelsHigh) / side))?.alphaComponent ?? 0
        }
        let knob = h.view.model.knobCenter
        check(crankAlpha(CGPoint(x: side / 2, y: side / 2)) > 0.9, "the hub renders solid")
        check(crankAlpha(CGPoint(x: side / 2 + knob.x, y: side / 2 + knob.y)) > 0.9, "the knob renders where the model puts it")
        check(crankAlpha(CGPoint(x: 4, y: 4)) == 0 && crankAlpha(CGPoint(x: side - 4, y: side - 4)) == 0, "the 3D view stays transparent around the crank")

        h.view.model.setArm(degrees: 90)
        h.view.model.root.isHidden = true
        let shadow = renderer.snapshot(atTime: 0, with: CGSize(width: side, height: side), antialiasingMode: .none)
        var shadowRect = CGRect(origin: .zero, size: shadow.size)
        let shade = NSBitmapImageRep(cgImage: shadow.cgImage(forProposedRect: &shadowRect, context: nil, hints: nil)!)
        func shadeAlpha(_ x: CGFloat, _ y: CGFloat) -> CGFloat {
            let o = WindowFrameCrankModel.shadowOffset
            return shade.colorAt(x: Int((side / 2 + o.dx + x) * CGFloat(shade.pixelsWide) / side),
                                 y: Int((side / 2 - o.dy - y) * CGFloat(shade.pixelsHigh) / side))?.alphaComponent ?? 0
        }
        let hubShade = shadeAlpha(0, 0), armShade = shadeAlpha(0, 36)
        check(armShade > 0.2 && armShade < 0.7, "the shadow is soft (\(armShade))")
        check(abs(hubShade - armShade) < 0.03, "overlapping parts do not darken the shadow (hub \(hubShade), arm \(armShade))")
        check(shadeAlpha(0, 110) < 0.02, "the shadow ends past the knob")
    }
}
