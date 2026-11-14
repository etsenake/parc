import AppKit
import QuartzCore
import SceneKit

struct WindowFrameCrankPalette: Equatable {
    var accent: NSColor
    var deep: NSColor
    var cap: NSColor
    var dark: Bool
}

@MainActor
final class WindowFrameCrankView: NSView {
    enum Phase: Equatable {
        case idle, presenting, shown, dismissing(commit: Bool), finished
    }

    private struct Settle {
        var from: Double
        var to: Double
        var clock: Double = 0
    }

    static let margin: CGFloat = 28
    static let side: CGFloat = 2 * (WindowFrameCrankPlacement.extent + margin)
    static let slideDistance: CGFloat = 26
    static let presentDuration = 0.42
    static let reducedPresentDuration = 0.2
    static let dismissDuration = 0.2
    static let reducedDismissDuration = 0.16
    static let settleDuration = 0.42
    static let reducedSettleDuration = 0.15
    static let wheelIdle: TimeInterval = 0.25
    static let gestureIdle: TimeInterval = 0.6
    static let trembleDegrees = 1.26
    static let trembleHertz = 6.1
    static let dragDeadZone: CGFloat = 6

    var onPreview: ((CGFloat) -> Void)?
    var onEvent: ((WindowFrameCrank.Event) -> Void)?
    var onFinish: ((_ commit: Bool, _ value: Int) -> Void)?
    var palette: WindowFrameCrankPalette {
        didSet {
            guard palette != oldValue else { return }
            model.apply(palette)
            lights.palette = palette
        }
    }

    private(set) var crank: WindowFrameCrank
    private(set) var shown: Double
    private(set) var phase: Phase = .idle
    private(set) var flash: Double = 0
    private(set) var tremble: Double = 0
    let model: WindowFrameCrankModel
    let lights: WindowFrameCrankLightsView
    let sceneView: SCNView
    private let stage = NSView()
    private let feedback: WindowFrameCrankFeedback
    private let reducesMotion: () -> Bool
    private var phaseClock: Double = 0
    private var trembleClock: Double = 0
    private var settle: Settle?
    private var held = false
    private var dragPoint: CGPoint?
    private var dismissFrom: (alpha: CGFloat, offset: CGFloat) = (1, 0)
    private var finalValue: Int
    private weak var priorResponder: NSResponder?
    private var windowCloseObserver: NSObjectProtocol?
    private var timer: Timer?
    private var wheelTimer: Timer?
    private var lastTick: CFTimeInterval = 0
    private var monitor: Any?

    convenience init(value: Int, palette: WindowFrameCrankPalette) {
        self.init(value: value, palette: palette, feedback: WindowFrameCrankFeedback(),
                  reducesMotion: { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion })
    }

    init(value: Int, palette: WindowFrameCrankPalette, feedback: WindowFrameCrankFeedback, reducesMotion: @escaping () -> Bool) {
        let square = NSRect(x: 0, y: 0, width: Self.side, height: Self.side)
        let start = WindowFrameCrank(value: value)
        crank = start
        shown = start.displayed
        finalValue = start.value
        self.palette = palette
        self.feedback = feedback
        self.reducesMotion = reducesMotion
        model = WindowFrameCrankModel(side: Self.side, palette: palette)
        lights = WindowFrameCrankLightsView(frame: square, litCount: start.litCount, readout: start.value, palette: palette)
        sceneView = SCNView(frame: square, options: nil)
        super.init(frame: square)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        stage.frame = square
        stage.wantsLayer = true
        addSubview(stage)
        stage.addSubview(lights)
        stage.addSubview(sceneView)
        sceneView.wantsLayer = true
        sceneView.scene = model.scene
        sceneView.pointOfView = model.camera
        sceneView.backgroundColor = .clear
        sceneView.layer?.isOpaque = false
        sceneView.antialiasingMode = .multisampling4X
        sceneView.autoenablesDefaultLighting = false
        sceneView.allowsCameraControl = false
        sceneView.rendersContinuously = false
        sceneView.isPlaying = false
        sceneView.isHidden = true
        sceneView.prepare([model.scene], completionHandler: nil)
        alphaValue = 0
        render()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    var acceptsInput: Bool { phase == .presenting || phase == .shown }
    var hub: CGPoint { CGPoint(x: bounds.midX, y: bounds.midY) }
    var stageOffset: CGPoint { stage.frame.origin }
    var isAnimating: Bool { timer != nil }
    var isWaitingForGesture: Bool { wheelTimer != nil }
    var value: Int {
        switch phase {
        case .dismissing(commit: false): return crank.initialValue
        case .finished: return finalValue
        case .idle, .presenting, .shown, .dismissing: return crank.value
        }
    }
    override var acceptsFirstResponder: Bool { acceptsInput }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func present(takingFocus: Bool = true) {
        guard phase == .idle else { return }
        phase = .presenting
        phaseClock = 0
        sceneView.isHidden = false
        applyTransition()
        if takingFocus { claimFocus() } else { installMonitor() }
        schedule()
        feedback.begin()
    }

    func finishNow(commit: Bool) {
        guard phase != .finished else { return }
        if case .dismissing(let pending) = phase {
            complete(commit: pending, announce: true)
        } else {
            complete(commit: commit, announce: true)
        }
    }

    func dismiss(commit: Bool) {
        guard acceptsInput else { return }
        wheelTimer?.invalidate(); wheelTimer = nil
        dragPoint = nil
        if held {
            held = false
            let from = shown
            let events = crank.release()
            if commit {
                handle(events)
                begin(Settle(from: from, to: crank.displayed))
            }
        }
        if !commit {
            let announced = lights.readout
            lights.light(crank.initialValue - WindowFrameThickness.range.lowerBound + 1, celebrate: false)
            lights.readout = crank.initialValue
            if announced != crank.initialValue { NSAccessibility.post(element: self, notification: .valueChanged) }
            begin(Settle(from: shown, to: Double(crank.initialValue)))
        }
        removeMonitor()
        dismissFrom = phase == .presenting ? Self.presentation(phaseClock, reduceMotion: reducesMotion()) : (1, 0)
        phase = .dismissing(commit: commit)
        phaseClock = 0
        schedule()
    }

    func turn(by degrees: Double) {
        guard acceptsInput, degrees.isFinite, degrees != 0 else { return }
        var stops: [WindowFrameCrank.Event] = []
        if settle != nil {
            settle = nil
            stops = crank.turn(degrees: (Self.raw(showing: shown) - crank.raw) * WindowFrameCrank.degreesPerPoint)
                .filter { if case .end = $0 { return true } else { return false } }
        }
        held = true
        let events = stops + crank.turn(degrees: degrees)
        setShown(crank.displayed)
        handle(events)
        render()
        schedule()
    }

    func releaseTurn() {
        guard held else { return }
        held = false
        let from = shown
        let events = crank.release()
        handle(events)
        begin(Settle(from: from, to: crank.displayed))
    }

    func step(_ points: Int) {
        guard acceptsInput else { return }
        held = false
        let from = shown
        let events = crank.step(points: points)
        handle(events)
        begin(Settle(from: from, to: crank.displayed))
    }

    func advance(by dt: Double) {
        let motion = !reducesMotion()
        phaseClock += dt
        switch phase {
        case .presenting:
            if phaseClock >= (motion ? Self.presentDuration : Self.reducedPresentDuration) { phase = .shown }
            applyTransition()
        case .dismissing(let commit):
            applyTransition()
            if phaseClock >= (motion ? Self.dismissDuration : Self.reducedDismissDuration) { finish(commit: commit) }
        case .idle, .shown, .finished:
            break
        }
        if var active = settle {
            active.clock += dt
            if let remaining = Self.settleRemaining(active.clock, reduceMotion: !motion) {
                settle = active
                setShown(active.to + (active.from - active.to) * remaining)
            } else {
                settle = nil
                setShown(active.to)
            }
        }
        flash = flash * exp(-dt * 6)
        if flash < 0.01 { flash = 0 }
        lights.flash = flash
        if motion && acceptsInput && crank.strain > 0 {
            trembleClock += dt
            tremble = crank.strain * Self.trembleDegrees * sin(2 * .pi * Self.trembleHertz * trembleClock)
        } else {
            trembleClock = 0
            tremble = 0
        }
        let lightsBusy = lights.advance(by: dt)
        render()
        let busy = phase == .presenting || isDismissing || settle != nil || flash > 0 || (motion && acceptsInput && crank.strain > 0) || lightsBusy
        if !busy { stopTimer() }
    }

    static func presentation(_ t: Double, reduceMotion: Bool) -> (alpha: CGFloat, offset: CGFloat) {
        if reduceMotion { return (CGFloat(smoothstep(t / reducedPresentDuration)), 0) }
        let p = min(1, max(0, t / presentDuration))
        let remaining = p >= 1 ? 0 : exp(-7 * p) * cos(9 * p)
        return (CGFloat(min(1, p * 2.5)), slideDistance * CGFloat(remaining))
    }

    static func dismissal(_ t: Double, reduceMotion: Bool,
                          from start: (alpha: CGFloat, offset: CGFloat) = (1, 0)) -> (alpha: CGFloat, offset: CGFloat) {
        if reduceMotion { return (start.alpha * CGFloat(1 - smoothstep(t / reducedDismissDuration)), start.offset) }
        let p = CGFloat(min(1, max(0, t / dismissDuration)))
        return (start.alpha * (1 - p * p), start.offset + (slideDistance - start.offset) * p * p)
    }

    static func raw(showing displayed: Double) -> Double {
        let low = Double(WindowFrameThickness.range.lowerBound), high = Double(WindowFrameThickness.range.upperBound)
        let reach = 0.999
        if displayed > high {
            return high + WindowFrameCrank.giveSoftness * atanh(min(reach, (displayed - high) / WindowFrameCrank.give))
        }
        if displayed < low {
            return low - WindowFrameCrank.giveSoftness * atanh(min(reach, (low - displayed) / WindowFrameCrank.give))
        }
        return displayed
    }

    static func scrollDelta(x: CGFloat, y: CGFloat) -> CGFloat { abs(x) > abs(y) ? x : y }

    static func settleRemaining(_ t: Double, reduceMotion: Bool) -> Double? {
        if reduceMotion { return t >= reducedSettleDuration ? nil : 1 - smoothstep(t / reducedSettleDuration) }
        return t >= settleDuration ? nil : exp(-14 * t) * cos(20 * t)
    }

    static func smoothstep(_ x: Double) -> Double {
        let t = min(1, max(0, x))
        return t * t * (3 - 2 * t)
    }

    func contains(local point: CGPoint) -> Bool {
        hypot(point.x - hub.x, point.y - hub.y) <= WindowFrameCrankPlacement.extent
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard acceptsInput, !isHidden else { return nil }
        let local = superview.map { convert(point, from: $0) } ?? point
        return contains(local: local) ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        guard acceptsInput else { return }
        claimFocus()
        let point = convert(event.locationInWindow, from: nil)
        guard hypot(point.x - hub.x, point.y - hub.y) <= WindowFrameCrankPlacement.swingRadius else { return }
        dragPoint = point
    }

    override func mouseDragged(with event: NSEvent) {
        guard acceptsInput, let previous = dragPoint else { return }
        let next = convert(event.locationInWindow, from: nil)
        guard hypot(next.x - hub.x, next.y - hub.y) >= Self.dragDeadZone else { return }
        dragPoint = next
        turn(by: WindowFrameCrank.dragDegrees(from: previous, to: next, around: hub))
    }

    override func mouseUp(with event: NSEvent) {
        guard dragPoint != nil else { return }
        dragPoint = nil
        releaseTurn()
    }

    override func scrollWheel(with event: NSEvent) {
        guard acceptsInput, event.momentumPhase.isEmpty else { return }
        if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
            wheelTimer?.invalidate(); wheelTimer = nil
            releaseTurn()
            return
        }
        let delta = Self.scrollDelta(x: event.scrollingDeltaX, y: event.scrollingDeltaY)
        turn(by: WindowFrameCrank.scrollDegrees(deltaY: Double(delta), precise: event.hasPreciseScrollingDeltas))
        if held { scheduleWheelRelease(after: event.phase.isEmpty ? Self.wheelIdle : Self.gestureIdle) }
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 126, 124: step(1)
        case 125, 123: step(-1)
        case 36, 76: dismiss(commit: true)
        case 53: dismiss(commit: false)
        default: super.keyDown(with: event)
        }
    }

    override func cancelOperation(_ sender: Any?) { dismiss(commit: false) }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned, acceptsInput, window != nil { dismiss(commit: true) }
        return resigned
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        observeWindowClose()
        if window == nil {
            switch phase {
            case .presenting, .shown: complete(commit: true, announce: false)
            case .dismissing(let commit): complete(commit: commit, announce: false)
            case .idle, .finished: tearDown()
            }
        } else if acceptsInput {
            claimFocus()
        }
    }

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .slider }
    override func accessibilityLabel() -> String? { "Window frame" }
    override func accessibilityValue() -> Any? { NSNumber(value: value) }
    override func accessibilityValueDescription() -> String? { WindowFrameThickness.spokenValue(value) }
    override func accessibilityMinValue() -> Any? { NSNumber(value: WindowFrameThickness.range.lowerBound) }
    override func accessibilityMaxValue() -> Any? { NSNumber(value: WindowFrameThickness.range.upperBound) }
    override func accessibilityPerformIncrement() -> Bool { step(1); return acceptsInput }
    override func accessibilityPerformDecrement() -> Bool { step(-1); return acceptsInput }

    private var isDismissing: Bool {
        if case .dismissing = phase { return true }
        return false
    }

    private func handle(_ events: [WindowFrameCrank.Event]) {
        let before = lights.readout
        for event in events {
            if case .end = event { flash = 1 }
            feedback.perform(event)
            onEvent?(event)
        }
        lights.light(crank.litCount, celebrate: !reducesMotion())
        lights.readout = crank.value
        lights.flash = flash
        if before != crank.value { NSAccessibility.post(element: self, notification: .valueChanged) }
    }

    private func begin(_ next: Settle) {
        if next.from == next.to {
            settle = nil
            setShown(next.to)
        } else {
            settle = next
        }
        render()
        schedule()
    }

    private func setShown(_ value: Double) {
        guard value != shown else { return }
        shown = value
        onPreview?(CGFloat(value))
    }

    private func render() {
        model.setArm(degrees: crank.armDegrees - (shown - crank.displayed) * WindowFrameCrank.degreesPerPoint + tremble)
    }

    private func applyTransition() {
        let motion = !reducesMotion()
        let state: (alpha: CGFloat, offset: CGFloat)
        switch phase {
        case .presenting: state = Self.presentation(phaseClock, reduceMotion: !motion)
        case .dismissing: state = Self.dismissal(phaseClock, reduceMotion: !motion, from: dismissFrom)
        case .shown: state = (1, 0)
        case .idle, .finished: state = (0, 0)
        }
        alphaValue = state.alpha
        let shift = -state.offset * CGFloat(0.5).squareRoot()
        stage.frame = NSRect(x: shift, y: shift, width: bounds.width, height: bounds.height)
    }

    private func finish(commit: Bool) {
        complete(commit: commit, announce: false)
    }

    private func complete(commit: Bool, announce: Bool) {
        guard phase != .finished else { return }
        phase = .finished
        if held {
            held = false
            crank.release()
        }
        dragPoint = nil
        settle = nil
        let final = commit ? crank.value : crank.initialValue
        finalValue = final
        if announce || shown != Double(final) {
            shown = Double(final)
            onPreview?(CGFloat(final))
        }
        alphaValue = 0
        stage.frame = bounds
        sceneView.isHidden = true
        tearDown()
        returnFocus()
        onFinish?(commit, final)
    }

    private func observeWindowClose() {
        if let windowCloseObserver { NotificationCenter.default.removeObserver(windowCloseObserver) }
        windowCloseObserver = nil
        guard let window else { return }
        windowCloseObserver = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window,
                                                                     queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.windowWillClose() }
        }
    }

    private func windowWillClose() {
        switch phase {
        case .presenting, .shown: complete(commit: true, announce: false)
        case .dismissing(let commit): complete(commit: commit, announce: false)
        case .idle, .finished: tearDown()
        }
    }

    private func tearDown() {
        if let windowCloseObserver { NotificationCenter.default.removeObserver(windowCloseObserver) }
        windowCloseObserver = nil
        stopTimer()
        wheelTimer?.invalidate(); wheelTimer = nil
        removeMonitor()
        feedback.stop()
    }

    private func claimFocus() {
        guard let window else { return }
        if window.firstResponder !== self {
            let current = window.firstResponder
            if window.makeFirstResponder(self), current !== window { priorResponder = current }
        }
        installMonitor()
    }

    private func returnFocus() {
        defer { priorResponder = nil }
        guard let window, window.firstResponder === self, let target = Self.focusTarget(priorResponder, in: window) else { return }
        window.makeFirstResponder(target)
    }

    static func focusTarget(_ responder: NSResponder?, in window: NSWindow) -> NSResponder? {
        var view = responder as? NSView
        if let text = view as? NSTextView, text.isFieldEditor { view = text.delegate as? NSView }
        guard let view, SavedFocus.mayReturn(to: view, in: window), view.acceptsFirstResponder else { return nil }
        return view
    }

    private func installMonitor() {
        guard monitor == nil, acceptsInput else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            MainActor.assumeIsolated { self?.outsideClick(event) }
            return event
        }
    }

    private func removeMonitor() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    func outsideClick(_ event: NSEvent) {
        guard acceptsInput, let window, event.window === window else { return }
        if !contains(local: convert(event.locationInWindow, from: nil)) { dismiss(commit: true) }
    }

    private func scheduleWheelRelease(after interval: TimeInterval) {
        wheelTimer?.invalidate()
        let timer = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.wheelTimer = nil
                self.releaseTurn()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        wheelTimer = timer
    }

    private func schedule() {
        guard timer == nil, phase != .finished else { return }
        lastTick = CACurrentMediaTime()
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated { if let self { self.tick() } else { timer.invalidate() } }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        let now = CACurrentMediaTime()
        let dt = min(0.05, max(0, now - lastTick))
        lastTick = now
        advance(by: dt)
    }
}

@MainActor
final class WindowFrameCrankLightsView: NSView {
    struct Sparkle {
        var point: CGPoint
        var velocity: CGVector
        var age: Double
        var life: Double
        var size: CGFloat
        var accent: Bool
    }

    static let count = WindowFrameThickness.range.count
    static let popDuration = 0.32
    static let defaultIndex = WindowFrameThickness.standard - WindowFrameThickness.range.lowerBound

    var palette: WindowFrameCrankPalette { didSet { if palette != oldValue { needsDisplay = true } } }
    var readout: Int { didSet { if readout != oldValue { needsDisplay = true } } }
    var flash: Double = 0 { didSet { if flash != oldValue { needsDisplay = true } } }
    private(set) var litCount: Int
    private(set) var bright: [Double]
    private(set) var pop: [Double]
    private(set) var sparkles: [Sparkle] = []
    private var seed: UInt64 = 7

    init(frame: NSRect, litCount: Int, readout: Int, palette: WindowFrameCrankPalette) {
        let lit = min(Self.count, max(0, litCount))
        self.litCount = lit
        self.readout = readout
        self.palette = palette
        bright = (0..<Self.count).map { $0 < lit ? 1 : 0 }
        pop = [Double](repeating: Self.popDuration, count: Self.count)
        super.init(frame: frame)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    static func angle(_ index: Int) -> CGFloat { (225 - CGFloat(index) * 27) * .pi / 180 }

    func pillCenter(_ index: Int) -> CGPoint {
        let a = Self.angle(index), r = WindowFrameCrankPlacement.lightsRadius
        return CGPoint(x: bounds.midX + r * cos(a), y: bounds.midY + r * sin(a))
    }

    var isAnimating: Bool {
        !sparkles.isEmpty || pop.contains { $0 < Self.popDuration }
            || (0..<Self.count).contains { bright[$0] != ($0 < litCount ? 1 : 0) }
    }

    func light(_ count: Int, celebrate: Bool) {
        let next = min(Self.count, max(0, count))
        guard next != litCount else { return }
        if celebrate, next > litCount {
            for index in litCount..<next {
                pop[index] = 0
                burst(at: index)
            }
        }
        litCount = next
        needsDisplay = true
    }

    @discardableResult
    func advance(by dt: Double) -> Bool {
        guard isAnimating else { return false }
        for index in 0..<Self.count {
            let target: Double = index < litCount ? 1 : 0
            bright[index] += (target - bright[index]) * min(1, dt * 18)
            if abs(bright[index] - target) < 0.004 { bright[index] = target }
            pop[index] = min(Self.popDuration, pop[index] + dt)
        }
        for index in sparkles.indices {
            sparkles[index].age += dt
            sparkles[index].point.x += sparkles[index].velocity.dx * CGFloat(dt)
            sparkles[index].point.y += sparkles[index].velocity.dy * CGFloat(dt)
            let drag = CGFloat(pow(0.93, dt * 60))
            sparkles[index].velocity.dx *= drag
            sparkles[index].velocity.dy *= drag
        }
        sparkles.removeAll { $0.age >= $0.life }
        needsDisplay = true
        return isAnimating
    }

    private func nextRandom() -> CGFloat {
        seed = seed &* 6364136223846793005 &+ 1442695040888963407
        return CGFloat((seed >> 33) & 0xFFFF) / 65535
    }

    private func burst(at index: Int) {
        let a = Self.angle(index)
        let origin = pillCenter(index)
        for _ in 0..<7 {
            let direction = a + (nextRandom() - 0.5) * 1.6
            let speed = 28 + nextRandom() * 46
            sparkles.append(Sparkle(point: origin, velocity: CGVector(dx: cos(direction) * speed, dy: sin(direction) * speed), age: 0,
                                    life: 0.45 + Double(nextRandom()) * 0.35, size: 1.2 + nextRandom() * 1.8, accent: nextRandom() > 0.55))
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let dark = palette.dark
        let accent = WindowFrameCrankModel.srgb(palette.accent), deep = WindowFrameCrankModel.srgb(palette.deep)
        let glow = Self.mix(accent, deep, 0.25)
        let radius = WindowFrameCrankPlacement.lightsRadius
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let flashing = CGFloat(flash)
        for index in 0..<Self.count {
            let a = Self.angle(index)
            let b = CGFloat(bright[index])
            let age = CGFloat(pop[index] / Self.popDuration)
            let popScale = 1 + 0.38 * max(0, 1 - age) * sin(min(age, 1) * .pi)
            let isDefault = index == Self.defaultIndex
            ctx.saveGState()
            ctx.translateBy(x: center.x + radius * cos(a), y: center.y + radius * sin(a))
            ctx.rotate(by: a)
            ctx.scaleBy(x: popScale, y: popScale)
            let length: CGFloat = isDefault ? 15 : 13, width: CGFloat = isDefault ? 7 : 6
            let rect = CGRect(x: -length / 2, y: -width / 2, width: length, height: width)
            let path = CGPath(roundedRect: rect, cornerWidth: width / 2, cornerHeight: width / 2, transform: nil)
            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 0, height: -0.5), blur: 1.5, color: NSColor(white: 0, alpha: dark ? 0.5 : 0.12).cgColor)
            ctx.addPath(path)
            ctx.setFillColor((dark ? NSColor(white: 1, alpha: 0.16) : NSColor(white: 0.45, alpha: 0.2)).cgColor)
            ctx.fillPath()
            ctx.restoreGState()
            if b > 0.02 {
                let lit = b * (1 + 0.3 * flashing)
                ctx.saveGState()
                ctx.setShadow(offset: .zero, blur: 6 + 8 * b + flashing * 14,
                              color: glow.withAlphaComponent(min(1, 0.9 * b + flashing * 0.3)).cgColor)
                ctx.addPath(path)
                ctx.setFillColor(glow.withAlphaComponent(min(1, b)).cgColor)
                ctx.fillPath()
                ctx.restoreGState()
                let core = rect.insetBy(dx: 3.4, dy: 2.4)
                ctx.addPath(CGPath(roundedRect: core, cornerWidth: core.height / 2, cornerHeight: core.height / 2, transform: nil))
                ctx.setFillColor(NSColor(white: 1, alpha: min(1, 0.6 * lit)).cgColor)
                ctx.fillPath()
            }
            ctx.restoreGState()
            if isDefault {
                ctx.setFillColor(glow.withAlphaComponent(0.9).cgColor)
                ctx.fillEllipse(in: CGRect(x: center.x + (radius + 12) * cos(a) - 1.8, y: center.y + (radius + 12) * sin(a) - 1.8,
                                           width: 3.6, height: 3.6))
            }
        }
        for sparkle in sparkles {
            let f = CGFloat(1 - sparkle.age / sparkle.life)
            let color = sparkle.accent ? accent.withAlphaComponent(0.9 * f) : Self.mix(deep, .white, 0.35).withAlphaComponent(0.95 * f)
            ctx.saveGState()
            ctx.setShadow(offset: .zero, blur: 4, color: accent.withAlphaComponent(0.6 * f).cgColor)
            ctx.setFillColor(color.cgColor)
            ctx.fillEllipse(in: CGRect(x: sparkle.point.x - sparkle.size, y: sparkle.point.y - sparkle.size,
                                       width: sparkle.size * 2, height: sparkle.size * 2))
            ctx.restoreGState()
        }
        drawReadout(ctx, center: center, radius: radius, dark: dark)
    }

    private func drawReadout(_ ctx: CGContext, center: CGPoint, radius: CGFloat, dark: Bool) {
        var font = NSFont.systemFont(ofSize: 12.5, weight: .semibold)
        if let rounded = font.fontDescriptor.withDesign(.rounded) { font = NSFont(descriptor: rounded, size: 12.5) ?? font }
        let ink = dark ? NSColor(white: 1, alpha: 0.9) : NSColor(srgbRed: 0.23, green: 0.12, blue: 0.16, alpha: 0.85)
        let text = NSAttributedString(string: WindowFrameThickness.label(readout), attributes: [.font: font, .foregroundColor: ink])
        let size = text.size()
        let capsule = CGRect(x: center.x - (size.width + 26) / 2, y: center.y - radius - 13, width: size.width + 26, height: 26)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -2), blur: 8, color: NSColor(white: 0, alpha: dark ? 0.5 : 0.16).cgColor)
        ctx.addPath(CGPath(roundedRect: capsule, cornerWidth: 13, cornerHeight: 13, transform: nil))
        ctx.setFillColor((dark ? NSColor(white: 0.16, alpha: 0.92) : NSColor(white: 1, alpha: 0.92)).cgColor)
        ctx.fillPath()
        ctx.restoreGState()
        text.draw(at: CGPoint(x: capsule.midX - size.width / 2, y: capsule.midY - size.height / 2))
    }

    private static func mix(_ a: NSColor, _ b: NSColor, _ t: CGFloat) -> NSColor {
        let a = WindowFrameCrankModel.srgb(a), b = WindowFrameCrankModel.srgb(b)
        return NSColor(srgbRed: a.redComponent + (b.redComponent - a.redComponent) * t,
                       green: a.greenComponent + (b.greenComponent - a.greenComponent) * t,
                       blue: a.blueComponent + (b.blueComponent - a.blueComponent) * t, alpha: 1)
    }
}
