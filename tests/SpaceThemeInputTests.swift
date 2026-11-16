import AppKit

private final class ThemeInputEvent: NSEvent {
    let inputPhase: NSEvent.Phase
    let inputMomentum: NSEvent.Phase
    let degrees: Float
    let delta: CGFloat
    let time: TimeInterval
    let location: NSPoint
    init(over view: NSView? = nil, at point: NSPoint? = nil, phase: NSEvent.Phase = [], momentum: NSEvent.Phase = [],
         rotation: Float = 0, delta: CGFloat = 0, time: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        inputPhase = phase; inputMomentum = momentum; degrees = rotation
        self.delta = delta; self.time = time
        location = view.map { $0.convert(point ?? NSPoint(x: $0.bounds.midX, y: $0.bounds.midY), to: nil) } ?? .zero
        super.init()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override var locationInWindow: NSPoint { location }
    override var phase: NSEvent.Phase { inputPhase }
    override var momentumPhase: NSEvent.Phase { inputMomentum }
    override var rotation: Float { degrees }
    override var scrollingDeltaY: CGFloat { delta }
    override var timestamp: TimeInterval { time }
}

@main @MainActor struct SpaceThemeInputTests {
    static var assertions = 0
    static func expect(_ value: @autoclosure () -> Bool, _ message: String, line: Int = #line) {
        assertions += 1
        precondition(value(), "Line \(line): \(message)")
    }
    static func near(_ value: Double, _ expected: Double, _ message: String, line: Int = #line) {
        expect(abs(value - expected) < 0.000001, message, line: line)
    }
    static func children(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(children) }
    static func control(_ name: String, _ view: NSView) -> NSView {
        children(view).first { $0.accessibilityLabel() == name }!
    }
    static func mouse(_ type: NSEvent.EventType, _ view: NSView, _ point: NSPoint) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: view.convert(point, to: nil), modifierFlags: [],
                          timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: 0,
                          context: nil, eventNumber: 0, clickCount: 1, pressure: 0)!
    }
    static func drain(_ seconds: Double = 0.035) { RunLoop.main.run(until: Date(timeIntervalSinceNow: seconds)) }
    static func make(_ theme: SpaceTheme = SpaceTheme()) -> SpaceThemeEditorView {
        let result = SpaceThemeEditorView(theme: theme, performHapticFeedback: {})
        result.layoutSubtreeIfNeeded()
        return result
    }
    static func hoverCenter(_ noise: NSView) {
        noise.mouseMoved(with: mouse(.mouseMoved, noise, NSPoint(x: noise.bounds.midX, y: noise.bounds.midY)))
    }
    static func hosted(_ theme: SpaceTheme) -> (SpaceThemeEditorView, NSWindow) {
        let view = make(theme)
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: view.frame.width, height: view.frame.height),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        view.layoutSubtreeIfNeeded()
        drain()
        return (view, window)
    }
    static func knobs(_ pad: NSView) -> [CALayer] {
        pad.layer!.sublayers!.first { layer in
            !pad.subviews.contains { $0.layer === layer } && layer.sublayers?.isEmpty == false
        }!.sublayers!
    }
    static func drawn(_ knob: CALayer, _ pad: NSView, in view: NSView) -> NSPoint {
        var point = knob.position, layer = knob.superlayer!
        while true {
            if layer.isGeometryFlipped { point.y = layer.bounds.height - point.y }
            if layer === view.layer { break }
            point.x += layer.frame.minX - layer.bounds.minX
            point.y += layer.frame.minY - layer.bounds.minY
            layer = layer.superlayer!
        }
        return pad.convert(NSPoint(x: point.x, y: view.isFlipped ? view.bounds.height - point.y : point.y), from: view)
    }
    static func cursorUpdate(_ view: NSView, _ point: NSPoint) -> NSEvent {
        NSEvent.enterExitEvent(with: .cursorUpdate, location: view.convert(point, to: nil), modifierFlags: [],
                               timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: 0, context: nil,
                               eventNumber: 0, trackingNumber: 0, userData: nil)!
    }
    static func main() { exitOnFailure(runChecks) }
    static func runChecks() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        padCoordinatesAndTransactions()
        linkedHandleStartAndRelativeDrag()
        drawnKnobFollowsGrabOffset()
        padCursorRegions()
        buttonStylePresses()
        intensityLifetime()
        cancelledPadCannotEnterNewGesture()
        pendingNoiseCannotEnterNewGesture()
        discreteInputRetiresPhysicalGesture()
        rejectedCommitPreservesNewInput()
        dialMappingAndRotation()
        dialKnobGeometry()
        editorTooltips()
        wheelThrottleAndUndo()
        interruptionAndLifetime()
        print("Space theme input: \(assertions) assertions passed")
    }
    static func padCoordinatesAndTransactions() {
        let view = make(), pad = control("Theme color pad", view)
        var previews = 0, commits = 0
        view.onPreview = { _ in previews += 1 }; view.onCommit = { _ in commits += 1 }
        let right = NSPoint(x: pad.bounds.width * 0.995, y: pad.bounds.midY)
        pad.mouseDown(with: mouse(.leftMouseDown, pad, right))
        near(view.theme.primaryColor!.hsl.lightness, 0.97, "right pad edge reaches radial maximum")
        near(view.theme.primaryColor!.hsl.hue, 0, "right pad axis is hue zero")
        expect(previews == 1 && commits == 0, "mouse down previews without writing persistence")
        let down = NSPoint(x: pad.bounds.midX, y: pad.bounds.height * 0.995)
        pad.mouseDragged(with: mouse(.leftMouseDragged, pad, down))
        near(view.theme.primaryColor!.hsl.hue, 0.25, "flipped downward pad axis is quarter hue")
        pad.mouseDragged(with: mouse(.leftMouseDragged, pad, NSPoint(x: -500, y: -500)))
        near(view.theme.primaryColor!.hsl.lightness, 0.97, "drag outside pad clamps radius")
        pad.mouseUp(with: mouse(.leftMouseUp, pad, down))
        expect(commits == 1, "all pointer updates form one durable transaction")
        let final = view.theme
        pad.mouseUp(with: mouse(.leftMouseUp, pad, down))
        expect(commits == 1 && view.theme == final, "duplicate release cannot recommit")
        view.undo(nil)
        expect(view.theme == SpaceTheme(), "one Undo restores the full pre-drag theme")
        pad.mouseDragged(with: mouse(.leftMouseDragged, pad, right))
        expect(view.theme == SpaceTheme(), "retired pointer cannot edit after Undo")
        view.redo(nil)
        expect(view.theme == final, "stale pointer input leaves Redo intact")
    }
    static func linkedHandleStartAndRelativeDrag() {
        let primary = ThemeColor.hsl(hue: 0, saturation: 0.7, lightness: 0.5, colorSpace: .displayP3)!
        var theme = SpaceTheme.singleColor(primary); theme.colorCount = 2; theme.wheel = .complimentary
        let view = make(theme), pad = control("Theme color pad", view)
        let positions = SpaceThemeEditorState(theme: theme)
        let normalized = positions.normalizedPosition(for: theme.colors[1])
        let center = NSPoint(x: (normalized.x + 1) * pad.bounds.midX, y: (normalized.y + 1) * pad.bounds.midY)
        let pointer = NSPoint(x: center.x + 3, y: center.y + 2)
        pad.mouseDown(with: mouse(.leftMouseDown, pad, pointer))
        near(view.theme.primaryColor!.hsl.hue, 0.5, "zero-distance linked handle adopts its color as primary")
        near(view.theme.primaryColor!.hsl.lightness, 0.5, "handle grab offset does not change radial lightness")
        let translated = NSPoint(x: pointer.x + 12, y: pointer.y + 20)
        pad.mouseDragged(with: mouse(.leftMouseDragged, pad, translated))
        let expected = SpaceThemeEditorState(theme: theme)
        expected.moveColor(x: (center.x + 12 - pad.bounds.midX) / pad.bounds.midX,
                           y: (center.y + 20 - pad.bounds.midY) / pad.bounds.midY)
        near(view.theme.primaryColor!.hsl.hue, expected.theme.primaryColor!.hsl.hue, "drag retains captured handle center")
        near(view.theme.primaryColor!.hsl.lightness, expected.theme.primaryColor!.hsl.lightness, "drag uses translation from original grab")
        pad.mouseUp(with: mouse(.leftMouseUp, pad, translated))
        view.undo(nil)
        expect(view.theme == theme, "linked handle promotion and drag share one Undo")
    }
    static let offAxisColor = ThemeColor.hsl(hue: 0.15, saturation: 0.85, lightness: 0.81, colorSpace: .displayP3)!
    static func drawnKnobFollowsGrabOffset() {
        var theme = SpaceTheme.singleColor(offAxisColor); theme.appearance = .light
        let (view, window) = hosted(theme)
        defer { window.contentView = nil }
        var commits = 0; view.onCommit = { _ in commits += 1 }
        let pad = control("Theme color pad", view), knob = knobs(pad)[0]
        let start = drawn(knob, pad, in: view)
        expect(start.x > pad.bounds.midX && start.y > pad.bounds.midY, "a 54° hue is drawn right of and below centre, y down")
        let grab = NSPoint(x: start.x + 9, y: start.y + 6)
        func atGrabOffset(_ pointer: NSPoint, _ message: String, line: Int = #line) {
            let center = drawn(knob, pad, in: view)
            expect(abs(center.x - (pointer.x - 9)) < 0.001 && abs(center.y - (pointer.y - 6)) < 0.001, message, line: line)
        }
        pad.mouseDown(with: mouse(.leftMouseDown, pad, grab))
        atGrabOffset(grab, "pressing the drawn knob grabs it without a jump")
        for delta in [NSPoint(x: -30, y: -25), NSPoint(x: -70, y: -45), NSPoint(x: -110, y: -20), NSPoint(x: -150, y: -60)] {
            let pointer = NSPoint(x: grab.x + delta.x, y: grab.y + delta.y)
            pad.mouseDragged(with: mouse(.leftMouseDragged, pad, pointer))
            atGrabOffset(pointer, "the knob stays at the grab offset inside the rim")
        }
        pad.mouseDragged(with: mouse(.leftMouseDragged, pad, NSPoint(x: grab.x - 400, y: grab.y)))
        let center = NSPoint(x: pad.bounds.midX, y: pad.bounds.midY), rim = 0.99 * pad.bounds.midX
        let target = NSPoint(x: start.x - 400 - center.x, y: start.y - center.y), length = hypot(target.x, target.y)
        let clamped = drawn(knob, pad, in: view)
        expect(hypot(clamped.x - (center.x + target.x * rim / length), clamped.y - (center.y + target.y * rim / length)) < 0.001,
               "beyond the rim the knob keeps the pointer's angle on the 0.99 radius")
        near(view.theme.primaryColor!.hsl.lightness, 0.97, "the rim is the lightness maximum")
        pad.mouseUp(with: mouse(.leftMouseUp, pad, NSPoint(x: grab.x - 400, y: grab.y)))
        expect(commits == 1, "the visible drag remains one transaction")
    }
    static func padCursorRegions() {
        var theme = SpaceTheme.singleColor(offAxisColor); theme.appearance = .light; theme.colorCount = 3
        let (view, window) = hosted(theme)
        defer { window.contentView = nil; NSCursor.arrow.set() }
        let pad = control("Theme color pad", view), knobs = knobs(pad)
        func hover(_ point: NSPoint) -> NSCursor {
            NSCursor.iBeam.set()
            pad.mouseMoved(with: mouse(.mouseMoved, pad, point))
            return NSCursor.current
        }
        let primary = drawn(knobs[0], pad, in: view), background = NSPoint(x: 12, y: 12)
        expect(hover(background) == .arrow, "the pad background shows the arrow, not a crosshair")
        expect(hover(primary) == .openHand, "the drawn primary knob shows the open hand")
        expect(hover(drawn(knobs[1], pad, in: view)) == .openHand, "a drawn companion knob shows the open hand")
        expect(hover(NSPoint(x: primary.x, y: pad.bounds.height - primary.y)) == .arrow, "a knob's vertical mirror is plain pad")
        for name in ["Add color", "Remove color", "Automatic appearance", "Light appearance", "Dark appearance"] {
            let button = control(name, view)
            expect(hover(pad.convert(NSPoint(x: button.bounds.midX, y: button.bounds.midY), from: button)) == .pointingHand,
                   "\(name) shows the button pointing hand from the pad")
        }
        expect(!(control("Add color", view) as! NSButton).isEnabled, "a full palette disables Add color")
        for name in ["Previous color presets", "Next color presets", "Add color", "Remove color", "Light appearance"] {
            let button = control(name, view)
            button.updateTrackingAreas()
            expect(button.trackingAreas.contains { $0.options.contains(.cursorUpdate) }, "\(name) requests cursor updates")
            NSCursor.iBeam.set()
            button.cursorUpdate(with: cursorUpdate(button, NSPoint(x: button.bounds.midX, y: button.bounds.midY)))
            expect(NSCursor.current == .pointingHand, "\(name) shows the pointing hand, enabled or not")
        }
        NSCursor.iBeam.set()
        pad.cursorUpdate(with: cursorUpdate(pad, primary))
        expect(NSCursor.current == .openHand, "entering the pad resolves the cursor under the pointer")

        pad.mouseDown(with: mouse(.leftMouseDown, pad, primary))
        expect(NSCursor.current == .closedHand, "grabbing a knob shows the closed hand")
        expect(knobs[0].transform.m11 > 1 && knobs[1].transform.m11 == 1, "the grabbed knob shows its hover growth")
        NSCursor.arrow.set()
        let moved = NSPoint(x: primary.x - 40, y: primary.y - 30)
        pad.mouseDragged(with: mouse(.leftMouseDragged, pad, moved))
        expect(NSCursor.current == .closedHand, "each drag change restores the closed hand")
        pad.cursorUpdate(with: cursorUpdate(pad, moved))
        expect(NSCursor.current == .closedHand, "a cursor update cannot replace the closed hand mid-drag")
        pad.mouseUp(with: mouse(.leftMouseUp, pad, moved))
        expect(NSCursor.current == .openHand, "release on the knob returns to the open hand")
        let outside = NSPoint(x: -60, y: moved.y)
        pad.mouseDown(with: mouse(.leftMouseDown, pad, moved))
        pad.mouseDragged(with: mouse(.leftMouseDragged, pad, outside))
        pad.mouseExited(with: NSEvent.enterExitEvent(with: .mouseExited, location: pad.convert(outside, to: nil), modifierFlags: [],
                                                     timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0,
                                                     trackingNumber: 0, userData: nil)!)
        expect(knobs[0].transform.m11 > 1 && NSCursor.current == .closedHand, "a knob held past the pad's edge keeps its growth and the closed hand")
        pad.mouseDragged(with: mouse(.leftMouseDragged, pad, outside))
        pad.mouseUp(with: mouse(.leftMouseUp, pad, outside))
        expect(NSCursor.current == .arrow, "release outside the pad restores the arrow")
        expect(knobs[0].transform.m11 == 1, "release outside the pad drops the knob's hover growth with the arrow")
        NSCursor.arrow.set()
        pad.mouseDown(with: mouse(.leftMouseDown, pad, background))
        expect(NSCursor.current == .arrow, "a background press makes no cursor change")
        let interior = NSPoint(x: pad.bounds.midX - 30, y: pad.bounds.midY + 20), corner = NSPoint(x: 4, y: 4)
        pad.mouseDragged(with: mouse(.leftMouseDragged, pad, interior))
        let followed = drawn(knobs[0], pad, in: view)
        expect(hypot(followed.x - interior.x, followed.y - interior.y) < 0.001, "a background drag brings the primary knob to the pointer")
        expect(NSCursor.current == .openHand, "the knob arriving under a background drag shows the open hand")
        expect(knobs[0].transform.m11 > 1, "the knob arriving under a background drag shows its hover growth with the open hand")
        pad.cursorUpdate(with: cursorUpdate(pad, corner))
        expect(NSCursor.current == .openHand, "a cursor update makes no change during a background drag")
        pad.mouseDragged(with: mouse(.leftMouseDragged, pad, corner))
        expect(NSCursor.current == .arrow, "past the rim the knob stays behind and the arrow returns")
        expect(knobs[0].transform.m11 == 1, "the knob left behind at the rim drops its hover growth with the arrow")
        pad.mouseUp(with: mouse(.leftMouseUp, pad, corner))
        expect(NSCursor.current == .arrow, "a background release makes no cursor change")

        pad.mouseDown(with: mouse(.leftMouseDown, pad, background))
        pad.mouseDragged(with: mouse(.leftMouseDragged, pad, interior))
        expect(knobs[0].transform.m11 > 1, "a background drag grows the knob it brings under the pointer")
        view.finishEditing()
        expect(knobs[0].transform.m11 == 1 && NSCursor.current == .arrow, "a cancelled drag drops the knob's hover growth with the arrow")
        pad.mouseUp(with: mouse(.leftMouseUp, pad, interior))
        pad.mouseMoved(with: mouse(.mouseMoved, pad, background))
        let candidates = stride(from: 60.0, through: pad.bounds.width - 60, by: 20).flatMap { x in
            stride(from: 80.0, through: pad.bounds.height - 80, by: 20).map { NSPoint(x: x, y: $0) }
        }
        let clicked = candidates.first { point in
            knobs.allSatisfy { let knob = drawn($0, pad, in: view); return hypot(knob.x - point.x, knob.y - point.y) > 60 }
        }!
        NSCursor.arrow.set()
        pad.mouseDown(with: mouse(.leftMouseDown, pad, clicked)); pad.mouseUp(with: mouse(.leftMouseUp, pad, clicked))
        expect(knobs[0].transform.m11 == 1 && NSCursor.current == .arrow, "a plain click on the pad moves the knob there without growing it under the arrow")
        pad.mouseDown(with: mouse(.leftMouseDown, pad, background))
        pad.mouseDragged(with: mouse(.leftMouseDragged, pad, interior))
        pad.mouseDragged(with: mouse(.leftMouseDragged, pad, NSPoint(x: -10, y: pad.bounds.midY)))
        expect(knobs[0].transform.m11 == 1 && NSCursor.current == .arrow, "outside the pad a background drag shows no knob growth and the arrow")
        pad.mouseUp(with: mouse(.leftMouseUp, pad, NSPoint(x: -10, y: pad.bounds.midY)))
        let companion = drawn(knobs[1], pad, in: view)
        pad.mouseMoved(with: mouse(.mouseMoved, pad, companion))
        pad.mouseDown(with: mouse(.leftMouseDown, pad, companion))
        let grabbedUnder = drawn(knobs[0], pad, in: view)
        expect(hypot(grabbedUnder.x - companion.x, grabbedUnder.y - companion.y) < 0.5 && knobs[0].transform.m11 > 1
               && knobs[1].transform.m11 == 1 && knobs[2].transform.m11 == 1,
               "grabbing a companion grows the primary that takes its place under the closed hand, not the companion that moves away")
        pad.mouseUp(with: mouse(.leftMouseUp, pad, companion))

        let add = control("Add color", view) as! NSButton
        let addCenter = pad.convert(NSPoint(x: add.bounds.midX, y: add.bounds.midY), from: add)
        pad.mouseDown(with: mouse(.leftMouseDown, pad, background))
        pad.mouseDragged(with: mouse(.leftMouseDragged, pad, addCenter))
        expect(NSCursor.current == .pointingHand, "a background drag over + shows its pointing hand")
        pad.mouseUp(with: mouse(.leftMouseUp, pad, addCenter))
        let underAdd = drawn(knobs[0], pad, in: view)
        expect(hypot(underAdd.x - addCenter.x, underAdd.y - addCenter.y) < 0.001, "the primary knob is drawn beneath +")
        expect(hover(addCenter) == .pointingHand, "a pad button wins over a knob beneath it")
        expect(knobs[0].transform.m11 == 1, "a knob beneath a button shows no hover scale")
        let knobEdge = NSPoint(x: add.frame.maxX + 3, y: addCenter.y)
        expect(hypot(knobEdge.x - underAdd.x, knobEdge.y - underAdd.y) < 22, "the probe point lies on the 44-point knob")
        expect(hover(knobEdge) == .openHand, "the knob outside the button frame shows the open hand")
        expect(knobs[0].transform.m11 > 1, "the knob outside the button frame shows its hover scale")

        let remove = control("Remove color", view)
        func edgeFill() -> CGFloat {
            let rep = remove.bitmapImageRepForCachingDisplay(in: remove.bounds)!
            remove.cacheDisplay(in: remove.bounds, to: rep)
            return rep.colorAt(x: 2, y: rep.pixelsHigh / 2)!.alphaComponent
        }
        remove.mouseEntered(with: NSEvent.enterExitEvent(with: .mouseEntered, location: .zero, modifierFlags: [], timestamp: 0,
                                                         windowNumber: window.windowNumber, context: nil, eventNumber: 0,
                                                         trackingNumber: 0, userData: nil)!)
        pad.mouseMoved(with: mouse(.mouseMoved, pad, background))
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        expect(edgeFill() > 0.03, "a hovered − shows its hover fill")
        pad.mouseMoved(with: mouse(.mouseMoved, pad, knobEdge))
        expect(edgeFill() < 0.01, "a hovered knob turns off −'s hover styling")
        pad.mouseMoved(with: mouse(.mouseMoved, pad, background))
        expect(edgeFill() > 0.03, "leaving the knob restores it")
        (remove as! NSButton).highlight(true); drain(0.4)
        expect(edgeFill() < 0.01, "a press dragged off − drops its hover")
        (remove as! NSButton).highlight(false)
        remove.mouseEntered(with: NSEvent.enterExitEvent(with: .mouseEntered, location: .zero, modifierFlags: [], timestamp: 0,
                                                         windowNumber: window.windowNumber, context: nil, eventNumber: 0,
                                                         trackingNumber: 0, userData: nil)!)
        drain(0.4)
        expect(edgeFill() > 0.03, "− is hovered again before it leaves the window")

        var previews = 0; view.onPreview = { _ in previews += 1 }
        let beforeDisabledPress = view.theme
        add.mouseDown(with: mouse(.leftMouseDown, add, NSPoint(x: add.bounds.midX, y: add.bounds.midY)))
        pad.mouseDragged(with: mouse(.leftMouseDragged, pad, NSPoint(x: addCenter.x - 60, y: addCenter.y - 60)))
        pad.mouseUp(with: mouse(.leftMouseUp, pad, NSPoint(x: addCenter.x - 60, y: addCenter.y - 60)))
        expect(previews == 0 && view.theme == beforeDisabledPress, "a press on disabled + cannot grab the knob beneath it")

        window.contentView = nil; window.contentView = view; view.layoutSubtreeIfNeeded()
        pad.mouseMoved(with: mouse(.mouseMoved, pad, knobEdge))
        pad.mouseMoved(with: mouse(.mouseMoved, pad, background))
        expect(edgeFill() < 0.01, "a button hovered before the editor left its window shows no hover after it returns")
    }
    static func knobTexture(_ noise: NSView) -> [NSColor] {
        let rep = noise.bitmapImageRepForCachingDisplay(in: noise.bounds)!
        noise.cacheDisplay(in: noise.bounds, to: rep)
        let scale = CGFloat(rep.pixelsWide) / noise.bounds.width
        return (0..<12).map { index in
            let angle = Double(index) * .pi / 6, radius = 6 + Double(index % 3) * 4
            return rep.colorAt(x: Int((noise.bounds.midX + CGFloat(cos(angle) * radius)) * scale),
                               y: Int((noise.bounds.midY + CGFloat(sin(angle) * radius)) * scale))!
        }
    }
    static func pixels(_ view: NSView) -> [UInt8] {
        let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
        view.cacheDisplay(in: view.bounds, to: rep)
        return Array(UnsafeBufferPointer(start: rep.bitmapData, count: rep.bytesPerRow * rep.pixelsHigh))
    }
    static func buttonStylePresses() {
        let view = make(), noise = control("Theme texture and noise", view)
        let c = NSPoint(x: noise.bounds.midX, y: noise.bounds.midY)
        noise.mouseMoved(with: mouse(.mouseMoved, noise, c))
        let resting = knobTexture(noise)
        noise.mouseDown(with: mouse(.leftMouseDown, noise, c))
        expect(knobTexture(noise) != resting, "a knob press scales its texture")
        noise.rotate(with: ThemeInputEvent(over: noise, phase: .began, rotation: 36))
        expect(knobTexture(noise) == resting, "a rotation that starts during the knob press releases it")
        noise.mouseDragged(with: mouse(.leftMouseDragged, noise, c))
        expect(knobTexture(noise) == resting, "the press stays released for the rest of that mouse press")
        noise.rotate(with: ThemeInputEvent(over: noise, phase: .ended))
        noise.mouseUp(with: mouse(.leftMouseUp, noise, c))
        expect(knobTexture(noise) == resting, "the release leaves the knob at rest")

        let next = control("Next color presets", view) as! NSButton, idle = pixels(next)
        next.highlight(true)
        expect(pixels(next) != idle, "pressing > draws it at the press scale")
        next.highlight(false)
        expect(pixels(next) == idle, "releasing > returns it to rest")
    }
    static func intensityLifetime() {
        let view = make(), intensity = control("Theme intensity", view)
        let start = NSPoint(x: 16, y: intensity.bounds.midY)
        intensity.mouseDown(with: mouse(.leftMouseDown, intensity, start))
        near(view.theme.intensity, 0, "intensity starts at wave padding")
        intensity.mouseDragged(with: mouse(.leftMouseDragged, intensity,
                                           NSPoint(x: intensity.bounds.width - 16, y: start.y)))
        near(view.theme.intensity, 1, "intensity reaches upper endpoint")
        view.finishEditing()
        view.undo(nil)
        near(view.theme.intensity, 0.8, "finish commits once and Undo restores baseline")
        let noise = control("Theme texture and noise", view)
        noise.rotate(with: ThemeInputEvent(over: noise, phase: .began, rotation: 10))
        intensity.mouseDragged(with: mouse(.leftMouseDragged, intensity, start))
        near(view.theme.intensity, 0.8, "stale intensity drag cannot enter a new noise gesture")
        noise.rotate(with: ThemeInputEvent(over: noise, phase: .ended))
    }
    static func dialMappingAndRotation() {
        let view = make(), noise = control("Theme texture and noise", view)
        var commits = 0; view.onCommit = { _ in commits += 1 }
        let right = NSPoint(x: noise.bounds.width - 2, y: noise.bounds.midY)
        noise.mouseDown(with: mouse(.leftMouseDown, noise, right))
        noise.mouseUp(with: mouse(.leftMouseUp, noise, right))
        near(view.theme.noise, 0.25, "dial right edge is one quarter turn")
        expect(commits == 1, "ring click is discrete")
        let bottom = NSPoint(x: noise.bounds.midX, y: noise.bounds.height - 2)
        noise.mouseDown(with: mouse(.leftMouseDown, noise, right))
        noise.mouseDragged(with: mouse(.leftMouseDragged, noise, NSPoint(x: right.x - 3, y: right.y + 2)))
        near(view.theme.noise, 0.25, "dial drag waits for ten point recognition")
        noise.mouseDragged(with: mouse(.leftMouseDragged, noise, bottom))
        near(view.theme.noise, 0.5, "recognized drag uses absolute clockwise dial angle")
        expect(commits == 1, "recognized drag previews")
        noise.mouseUp(with: mouse(.leftMouseUp, noise, bottom))
        expect(commits == 2, "dial drag commits on physical end")
        noise.rotate(with: ThemeInputEvent(over: noise, phase: .began, rotation: 0.4))
        near(view.theme.noise, 0.5, "rotation waits for one degree")
        noise.rotate(with: ThemeInputEvent(over: noise, phase: .changed, rotation: 0.4))
        near(view.theme.noise, 0.5, "subthreshold rotation accumulates")
        noise.rotate(with: ThemeInputEvent(over: noise, phase: .changed, rotation: 0.4))
        near(view.theme.noise, 0.5 + 1.2 / 720, "rotation is continuous at half a revolution per turn")
        noise.rotate(with: ThemeInputEvent(over: noise, phase: .changed, rotation: 72))
        near(view.theme.noise, 0.6 + 1.2 / 720, "subsequent rotation uses event delta once")
        noise.rotate(with: ThemeInputEvent(over: noise, phase: .ended, rotation: 99))
        near(view.theme.noise, 0.6 + 1.2 / 720, "terminal rotation does not replay a sample")
        expect(commits == 3, "rotation has one completed transaction")
        view.undo(nil)
        near(view.theme.noise, 0.5, "Undo restores entire rotation")
        noise.rotate(with: ThemeInputEvent(over: noise, phase: .began, rotation: -720))
        near(view.theme.noise, 0, "negative rotation clamps low")
        noise.rotate(with: ThemeInputEvent(over: noise, phase: .cancelled))
        expect(commits == 5, "physical cancellation retires and commits admitted value once")
    }
    static func editorTooltips() {
        let view = make(), noise = control("Theme texture and noise", view)
        let knob = NSRect(x: noise.bounds.midX - 20, y: noise.bounds.midY - 20, width: 40, height: 40)
        let anchors = noise.subviews.compactMap { $0 as? TooltipAnchorView }
        expect(noise.parcTooltip == nil && anchors.count == 1, "the dial's square and ring carry no tooltip of their own")
        let anchor = anchors[0]
        expect(noise.bounds.size == NSSize(width: 80, height: 80) && anchor.frame == knob
               && anchor.parcTooltip == TooltipConfiguration("Noise", anchor: .bottom),
               "Noise belongs to the dial's 40-point centre knob and sits below it")
        noise.setFrameSize(NSSize(width: 100, height: 100))
        expect(anchor.frame == NSRect(x: 25, y: 25, width: 50, height: 50),
               "the anchor follows the knob when the dial's frame changes")
        let tooltips = children(view).compactMap(\.parcTooltip)
        expect(tooltips.count >= 6 && tooltips.allSatisfy { $0.palette == nil },
               "the editor's tooltips leave their palette to the popover window")
        noiseTooltipRegion()
    }
    final class KeyHostWindow: NSWindow {
        var pointer = NSPoint.zero
        override var isKeyWindow: Bool { true }
        override var mouseLocationOutsideOfEventStream: NSPoint { pointer }
    }
    static func noiseTooltipRegion() {
        InputOverrides.install()
        InputOverrides.pressedMouseButtons = 0; InputOverrides.modifierFlags = []
        defer { InputOverrides.pressedMouseButtons = nil; InputOverrides.modifierFlags = nil }
        let view = make()
        let window = KeyHostWindow(contentRect: NSRect(x: 200, y: 200, width: view.frame.width, height: view.frame.height),
                                   styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        view.layoutSubtreeIfNeeded()
        defer { window.contentView = nil; window.close() }
        let noise = control("Theme texture and noise", view)
        let anchor = noise.subviews.compactMap { $0 as? TooltipAnchorView }.first!
        let owner = anchor.trackingAreas.compactMap { $0.owner as? NSResponder }.first!
        func enter(_ point: NSPoint) {
            window.pointer = noise.convert(point, to: nil)
            owner.mouseEntered(with: NSEvent.enterExitEvent(with: .mouseEntered, location: window.pointer, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil,
                eventNumber: 0, trackingNumber: 0, userData: nil)!)
        }
        func label() -> String? { (window.childWindows?.first?.contentView as? TooltipView)?.content.label }
        let c = NSPoint(x: noise.bounds.midX, y: noise.bounds.midY)
        expect(noise.hitTest(noise.convert(c, to: noise.superview)) === noise, "in a window, clicks on the knob still reach the dial")
        enter(NSPoint(x: c.x + 30, y: c.y)); drain(0.6)
        expect(label() == nil, "the ring shows no Noise tooltip")
        enter(NSPoint(x: c.x - 30, y: c.y - 30)); drain(0.6)
        expect(label() == nil, "the dial's corner shows no Noise tooltip")
        enter(NSPoint(x: c.x + 19, y: c.y + 19)); drain(0.6)
        expect(label() == "Noise", "the centre knob's frame shows Noise, where the pointing hand shows")
        expect(window.childWindows?.first?.isVisible == false && !window.isVisible, "nothing was put on screen")
    }
    static func dialKnobGeometry() {
        var theme = SpaceTheme(); theme.noise = 0.5
        let view = make(theme), noise = control("Theme texture and noise", view)
        var commits = 0; view.onCommit = { _ in commits += 1 }
        let c = NSPoint(x: noise.bounds.midX, y: noise.bounds.midY)
        func click(_ point: NSPoint) {
            noise.mouseDown(with: mouse(.leftMouseDown, noise, point)); noise.mouseUp(with: mouse(.leftMouseUp, noise, point))
        }
        click(NSPoint(x: c.x + 19, y: c.y))
        expect(view.theme.texture == .sand && view.theme.noise == 0.5 && commits == 1,
               "a click inside the knob's 20-point radius cycles the texture")
        click(NSPoint(x: c.x + 24, y: c.y))
        expect(view.theme.texture == .sand, "a click beyond the knob circle is not a knob click")
        near(view.theme.noise, 0.25, "a click beyond the knob circle sets the dial by angle")
        expect(commits == 2, "the ring click is its own transaction")
        click(NSPoint(x: c.x + 19, y: c.y + 8))
        expect(view.theme.texture == .sand && commits == 3, "the knob frame's corner outside the circle belongs to the ring")
        near(view.theme.noise, 0.3, "the corner click sets the dial by its angle")

        noise.mouseDown(with: mouse(.leftMouseDown, noise, c))
        noise.mouseDragged(with: mouse(.leftMouseDragged, noise, NSPoint(x: noise.bounds.width - 2, y: c.y)))
        noise.mouseDragged(with: mouse(.leftMouseDragged, noise, NSPoint(x: c.x, y: noise.bounds.height - 2)))
        let afterDrag = view.theme
        noise.mouseUp(with: mouse(.leftMouseUp, noise, NSPoint(x: c.x, y: noise.bounds.height - 2)))
        expect(view.theme == afterDrag && afterDrag.texture == .sand && commits == 3,
               "a press on the knob never drags the dial, and releasing outside it does nothing")
        near(view.theme.noise, 0.3, "the knob press leaves the dial value alone")
        noise.mouseDown(with: mouse(.leftMouseDown, noise, c))
        noise.mouseDragged(with: mouse(.leftMouseDragged, noise, NSPoint(x: noise.bounds.width - 2, y: c.y)))
        noise.mouseUp(with: mouse(.leftMouseUp, noise, NSPoint(x: c.x - 10, y: c.y + 10)))
        expect(view.theme.texture == .denim && commits == 4, "a knob press released back on the knob still clicks")

        noise.rotate(with: ThemeInputEvent(over: noise, at: NSPoint(x: c.x + 24, y: c.y), phase: .began, rotation: 36))
        noise.rotate(with: ThemeInputEvent(over: noise, at: NSPoint(x: c.x + 24, y: c.y), phase: .changed, rotation: 36))
        noise.rotate(with: ThemeInputEvent(over: noise, at: NSPoint(x: c.x + 24, y: c.y), phase: .ended))
        near(view.theme.noise, 0.3, "rotation over the ring is not the knob's rotation")
        expect(commits == 4, "an ignored ring rotation records nothing")
        noise.rotate(with: ThemeInputEvent(over: noise, at: NSPoint(x: c.x, y: c.y - 19), phase: .began, rotation: 18))
        noise.rotate(with: ThemeInputEvent(over: noise, at: NSPoint(x: c.x, y: c.y - 19), phase: .ended))
        near(view.theme.noise, 0.325, "rotation that begins on the knob adjusts the noise")
        expect(commits == 5, "the knob rotation commits once")

        noise.mouseMoved(with: mouse(.mouseMoved, noise, NSPoint(x: c.x + 19, y: c.y + 19)))
        expect(NSCursor.current == .pointingHand, "the knob frame's corner shows the knob's pointing hand")
        noise.scrollWheel(with: ThemeInputEvent(phase: .began, delta: 1)); drain(0.23)
        near(view.theme.noise, 0.45, "the knob frame's corner counts as hovering the centre for the wheel")
        noise.mouseMoved(with: mouse(.mouseMoved, noise, NSPoint(x: c.x + 24, y: c.y)))
        expect(NSCursor.current == .openHand, "beyond the knob frame the dial shows the open hand")
        noise.scrollWheel(with: ThemeInputEvent(phase: .began, delta: 1)); drain(0.23)
        near(view.theme.noise, 0.45, "the wheel ignores a pointer outside the knob frame")
    }
    static func cancelledPadCannotEnterNewGesture() {
        let view = make(), pad = control("Theme color pad", view)
        let point = NSPoint(x: pad.bounds.width * 0.8, y: pad.bounds.midY)
        pad.mouseDown(with: mouse(.leftMouseDown, pad, point))
        var restored = SpaceTheme(); restored.intensity = 0.3
        view.synchronizeTheme(restored)
        let noise = control("Theme texture and noise", view)
        var commits = 0; view.onCommit = { _ in commits += 1 }
        noise.rotate(with: ThemeInputEvent(over: noise, phase: .began, rotation: 36))
        let preview = view.theme
        pad.mouseDragged(with: mouse(.leftMouseDragged, pad, point))
        expect(view.theme == preview, "cancelled pad cannot edit inside a fresh rotation snapshot")
        pad.mouseUp(with: mouse(.leftMouseUp, pad, point))
        expect(commits == 0, "cancelled pad release cannot finish another control's gesture")
        noise.rotate(with: ThemeInputEvent(over: noise, phase: .changed, rotation: 36))
        near(view.theme.noise, 0.1, "new rotation continues after stale pad drag and release")
        noise.rotate(with: ThemeInputEvent(over: noise, phase: .ended))
        expect(commits == 1, "fresh rotation retains its one-transaction boundary")
    }
    static func pendingNoiseCannotEnterNewGesture() {
        for rotation in [false, true] {
            let view = make(), noise = control("Theme texture and noise", view), pad = control("Theme color pad", view)
            var commits = 0; view.onCommit = { _ in commits += 1 }
            hoverCenter(noise)
            if rotation { noise.rotate(with: ThemeInputEvent(over: noise, phase: .began, rotation: 0.5)) }
            else { noise.scrollWheel(with: ThemeInputEvent(phase: .began, delta: 1)) }
            let point = NSPoint(x: pad.bounds.width * 0.8, y: pad.bounds.midY)
            pad.mouseDown(with: mouse(.leftMouseDown, pad, point))
            let preview = view.theme
            if rotation {
                noise.rotate(with: ThemeInputEvent(over: noise, phase: .changed, rotation: 90))
                noise.rotate(with: ThemeInputEvent(over: noise, phase: .ended))
            } else { drain(0.23) }
            expect(view.theme == preview && commits == 0, "unrecognized or queued noise cannot take over a new pad gesture")
            pad.mouseUp(with: mouse(.leftMouseUp, pad, point))
            expect(commits == 1, "pending noise cancellation preserves the pad transaction")
        }
    }
    static func discreteInputRetiresPhysicalGesture() {
        let view = make(), noise = control("Theme texture and noise", view)
        var commits = 0; view.onCommit = { _ in commits += 1 }
        noise.rotate(with: ThemeInputEvent(over: noise, phase: .began, rotation: 72))
        _ = noise.accessibilityPerformIncrement()
        near(view.theme.noise, 0.15, "AX increment begins from the completed rotation")
        expect(commits == 2, "physical rotation and AX increment are separate transactions")
        noise.rotate(with: ThemeInputEvent(over: noise, phase: .changed, rotation: 72))
        noise.rotate(with: ThemeInputEvent(over: noise, phase: .ended))
        near(view.theme.noise, 0.15, "AX input retires physical rotation continuation")
        view.undo(nil)
        near(view.theme.noise, 0.1, "Undo reverses only the discrete AX step")
        view.undo(nil)
        near(view.theme.noise, 0, "second Undo reverses the complete physical rotation")

        let intensity = control("Theme intensity", view)
        let point = NSPoint(x: 16 + (intensity.bounds.width - 32) * 0.4, y: intensity.bounds.midY)
        intensity.mouseDown(with: mouse(.leftMouseDown, intensity, point))
        _ = intensity.accessibilityPerformIncrement()
        near(view.theme.intensity, 0.45, "intensity AX begins from the completed drag")
        intensity.mouseDragged(with: mouse(.leftMouseDragged, intensity, .zero))
        intensity.mouseUp(with: mouse(.leftMouseUp, intensity, .zero))
        near(view.theme.intensity, 0.45, "AX retires intensity drag and release")
        view.undo(nil)
        near(view.theme.intensity, 0.4, "intensity AX step retains an independent inverse")

        let pad = control("Theme color pad", view)
        let right = NSPoint(x: pad.bounds.width * 0.8, y: pad.bounds.midY)
        pad.mouseDown(with: mouse(.leftMouseDown, pad, right))
        let beforeKey = view.theme
        let key = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                  windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "",
                                  isARepeat: false, keyCode: 125)!
        pad.keyDown(with: key)
        let afterKey = view.theme
        expect(afterKey != beforeKey, "pad arrow applies its own step after physical drag")
        pad.mouseDragged(with: mouse(.leftMouseDragged, pad, .zero))
        pad.mouseUp(with: mouse(.leftMouseUp, pad, .zero))
        expect(view.theme == afterKey, "arrow step retires inherited pad pointer events")
        view.undo(nil)
        expect(view.theme == beforeKey, "pad arrow has an independent inverse")
    }
    static func rejectedCommitPreservesNewInput() {
        for next in ["pad", "drag", "rotation", "AX"] {
            let view = make(), intensity = control("Theme intensity", view)
            var authoritative = SpaceTheme(); authoritative.noise = 0.2; authoritative.intensity = 0.3
            var proposals: [SpaceTheme] = []
            view.onCommitChange = { _, proposed in
                proposals.append(proposed)
                return proposals.count == 1 ? authoritative : proposed
            }
            intensity.mouseDown(with: mouse(.leftMouseDown, intensity, .zero))
            if next == "pad" {
                let pad = control("Theme color pad", view)
                let point = NSPoint(x: pad.bounds.width * 0.8, y: pad.bounds.midY)
                pad.mouseDown(with: mouse(.leftMouseDown, pad, point))
                let started = view.theme
                pad.mouseDragged(with: mouse(.leftMouseDragged, pad, NSPoint(x: point.x, y: point.y + 30)))
                expect(view.theme != started, "new pad continues after prior commit is rejected")
                pad.mouseUp(with: mouse(.leftMouseUp, pad, point))
            } else if next == "AX" {
                _ = intensity.accessibilityPerformIncrement()
                near(view.theme.intensity, 0.35, "discrete step reads the authoritative post-rejection baseline")
            } else {
                let noise = control("Theme texture and noise", view)
                if next == "rotation" {
                    noise.rotate(with: ThemeInputEvent(over: noise, phase: .began, rotation: 36))
                    noise.rotate(with: ThemeInputEvent(over: noise, phase: .changed, rotation: 36))
                    near(view.theme.noise, 0.3, "new rotation continues from post-rejection baseline")
                    noise.rotate(with: ThemeInputEvent(over: noise, phase: .ended))
                } else {
                    let right = NSPoint(x: noise.bounds.width - 2, y: noise.bounds.midY)
                    let bottom = NSPoint(x: noise.bounds.midX, y: noise.bounds.height - 2)
                    noise.mouseDown(with: mouse(.leftMouseDown, noise, right))
                    noise.mouseDragged(with: mouse(.leftMouseDragged, noise, bottom))
                    noise.mouseDragged(with: mouse(.leftMouseDragged, noise, NSPoint(x: 2, y: noise.bounds.midY)))
                    near(view.theme.noise, 0.75, "new dial drag continues after prior commit rejection")
                    noise.mouseUp(with: mouse(.leftMouseUp, noise, bottom))
                }
            }
            expect(proposals.count == 2, "new input retains its commit boundary after prior rejection")
            if next != "AX" { near(view.theme.intensity, 0.3, "new input preserves authoritative unrelated fields") }
        }
    }
    static func wheelThrottleAndUndo() {
        var theme = SpaceTheme(); theme.noise = 0.5
        let view = make(theme), noise = control("Theme texture and noise", view)
        var commits = 0; view.onCommit = { _ in commits += 1 }
        hoverCenter(noise)
        noise.scrollWheel(with: ThemeInputEvent(phase: .began, delta: 1)); drain()
        near(view.theme.noise, 0.65, "positive wheel direction adds one eighth then quantizes")
        expect(commits == 1, "first admitted wheel tick commits independently")
        noise.scrollWheel(with: ThemeInputEvent(phase: .changed, delta: -100))
        noise.scrollWheel(with: ThemeInputEvent(phase: .changed, delta: 0.001))
        drain(0.23)
        near(view.theme.noise, 0.8, "latest direction wins and delta magnitude does not scale the tick")
        expect(commits == 2, "rapid wheel events are throttled to one latest tick")
        view.undo(nil)
        near(view.theme.noise, 0.65, "wheel Undo reverses one accepted tick")
        noise.scrollWheel(with: ThemeInputEvent(phase: .changed, delta: 1))
        noise.scrollWheel(with: ThemeInputEvent(momentum: .changed, delta: 1)); drain(0.23)
        near(view.theme.noise, 0.65, "Undo rejects inherited physical and momentum input")
        view.redo(nil)
        near(view.theme.noise, 0.8, "rejected continuation preserves wheel Redo")
        noise.scrollWheel(with: ThemeInputEvent(phase: .began, delta: -1)); drain()
        let beforeZero = view.theme.noise, beforeCommits = commits
        noise.scrollWheel(with: ThemeInputEvent(phase: .changed, delta: 1))
        noise.scrollWheel(with: ThemeInputEvent(phase: .ended, delta: 0)); drain(0.23)
        near(view.theme.noise, beforeZero, "latest zero is filtered after throttling")
        expect(commits == beforeCommits, "ending zero cannot create a history record")
    }
    static func interruptionAndLifetime() {
        let view = make(), noise = control("Theme texture and noise", view)
        var commits = 0; view.onCommit = { _ in commits += 1 }
        hoverCenter(noise)
        noise.scrollWheel(with: ThemeInputEvent(phase: .began, delta: 1))
        view.finishEditing(); drain(0.23)
        expect(commits == 0 && view.theme.noise == 0, "dismissal cancels queued wheel delivery")
        noise.rotate(with: ThemeInputEvent(over: noise, phase: .began, rotation: 0.5))
        var restored = SpaceTheme(); restored.noise = 0.4
        view.synchronizeTheme(restored)
        noise.rotate(with: ThemeInputEvent(over: noise, phase: .changed, rotation: 90))
        noise.rotate(with: ThemeInputEvent(over: noise, phase: .ended))
        expect(view.theme == restored && commits == 0, "parent replacement cancels even an unrecognized physical rotation")
        noise.scrollWheel(with: ThemeInputEvent(phase: .began, delta: 1))
        noise.rotate(with: ThemeInputEvent(over: noise, phase: .began, rotation: 72))
        noise.rotate(with: ThemeInputEvent(over: noise, phase: .ended))
        let rotated = view.theme
        drain(0.23)
        expect(view.theme == rotated && commits == 1, "new rotation retires pending wheel input even when rotation ends before delivery")
        view.synchronizeTheme(restored)
        noise.scrollWheel(with: ThemeInputEvent(phase: .began, delta: 1))
        noise.mouseExited(with: mouse(.mouseMoved, noise, .zero)); drain(0.23)
        expect(view.theme == restored, "hover is checked when the throttled event is delivered")
        noise.scrollWheel(with: ThemeInputEvent(phase: .began, delta: 1))
        hoverCenter(noise); drain(0.23)
        near(view.theme.noise, 0.55, "entering the center before delivery admits an event observed over the ring")
        weak var released: SpaceThemeEditorView?
        autoreleasepool {
            let transient = make(); released = transient
            let control = control("Theme texture and noise", transient)
            hoverCenter(control)
            control.scrollWheel(with: ThemeInputEvent(phase: .began, delta: 1))
        }
        drain(0.23)
        expect(released == nil, "pending scroll subscription does not retain a retired editor")
    }
}
