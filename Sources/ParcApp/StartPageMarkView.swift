import AppKit
import ParcCore

@MainActor
final class StartPageMarkView: NSView {
    static let width: CGFloat = 65
    static let tintAlpha: CGFloat = 0.25

    var theme = SpaceTheme() { didSet { if theme != oldValue { refreshFill() } } }
    var incognito = false { didSet { if incognito != oldValue { refreshFill() } } }
    weak var coordinateSpace: NSView? { didSet { renderer?.coordinateSpace = coordinateSpace } }
    weak var effectsHost: NSView? { didSet { if effectsHost !== oldValue { stopInteraction() } } }
    var pagingTransition: ThemePagingTransition? { didSet { if pagingTransition != oldValue { refreshFill() } } }
    var style = ParcBrandMark.Style.borderless { didSet { if style != oldValue { refreshFill() } } }
    private var fill = StartPageMarkFill.ink

    private let body = NSView()
    private let stage = NSView()
    private let ink = NSView()
    private let art = NSImageView()
    private let shimmer = NSView()
    private let shape = CALayer()
    private let monochrome: CGImage?
    private var renderer: ThemeRendererView?
    private var motion: StartPageMarkStage?
    private var recognizer = StartPageMarkGestureRecognizer()
    private var session = StartPageMarkSession()
    private var holdTimer: Timer?
    private var holdDeadline: TimeInterval?
    private var pagingInks: (key: [SpaceTheme], appearance: NSAppearance.Name?, from: CGColor, to: CGColor)?
    private var observers: [NSObjectProtocol] = []
    private var windowAppearanceObservation: NSKeyValueObservation?

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override var intrinsicContentSize: NSSize {
        guard let monochrome, monochrome.width > 0 else { return .zero }
        return NSSize(width: Self.width, height: (Self.width * CGFloat(monochrome.height) / CGFloat(monochrome.width)).rounded())
    }

    private let performHapticFeedback: @MainActor () -> Void

    override convenience init(frame frameRect: NSRect) {
        self.init(frame: frameRect, performHapticFeedback: ThemeHapticFeedback.perform)
    }

    init(frame frameRect: NSRect, performHapticFeedback: @escaping @MainActor () -> Void) {
        self.performHapticFeedback = performHapticFeedback
        monochrome = ParcBrandMark.image(.monochrome)?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        super.init(frame: frameRect)
        wantsLayer = true
        clipsToBounds = false
        for view in [body, stage] {
            view.wantsLayer = true
            view.clipsToBounds = false
        }
        for view in [ink, art, shimmer] as [NSView] {
            view.wantsLayer = true
            stage.addSubview(view)
        }
        art.imageScaling = .scaleProportionallyUpOrDown
        art.setAccessibilityElement(false)
        shape.contents = monochrome
        shape.contentsGravity = .resizeAspect
        stage.layer?.mask = shape
        body.addSubview(stage)
        addSubview(body)
        if let bodyLayer = body.layer, let shimmerLayer = shimmer.layer {
            motion = StartPageMarkStage(body: bodyLayer, shimmer: shimmerLayer)
        }
        refreshFill()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
        holdTimer?.invalidate()
    }

    override func isAccessibilityElement() -> Bool { false }
    override func accessibilityChildren() -> [Any]? { [] }

    func invalidateCoordinates() { renderer?.invalidateCoordinates() }

    override func setFrameSize(_ newSize: NSSize) {
        let changed = newSize != frame.size
        super.setFrameSize(newSize)
        if changed { needsLayout = true }
    }
    override func setFrameOrigin(_ newOrigin: NSPoint) {
        let changed = newOrigin != frame.origin
        super.setFrameOrigin(newOrigin)
        if changed { invalidateCoordinates() }
    }
    override func layout() {
        super.layout()
        var moved = false
        if body.frame != bounds { body.frame = bounds; moved = true }
        if stage.frame != body.bounds { stage.frame = body.bounds; moved = true }
        for view in stage.subviews where view.frame != stage.bounds { view.frame = stage.bounds; moved = true }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if shape.frame != stage.bounds { shape.frame = stage.bounds }
        CATransaction.commit()
        if moved { invalidateCoordinates() }
    }

    override func hitTest(_ point: NSPoint) -> NSView? { super.hitTest(point) == nil ? nil : self }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        windowAppearanceObservation = nil
        stopInteraction()
        super.viewWillMove(toWindow: newWindow)
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window {
            for name in [NSWindow.didChangeOcclusionStateNotification, NSWindow.didMiniaturizeNotification] {
                observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.activityChanged() }
                })
            }
            observers.append(NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: window,
                                                                    queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.stopInteraction() }
            })
            windowAppearanceObservation = window.observe(\.effectiveAppearance) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.refreshFill() }
            }
        }
        refreshFill()
    }
    override func viewDidHide() { super.viewDidHide(); activityChanged() }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); refreshFill() }

    override func mouseDown(with event: NSEvent) {
        guard !event.modifierFlags.contains(.control) else { super.mouseDown(with: event); return }
        abandonInteraction()
        recognizer.clickInterval = NSEvent.doubleClickInterval
        route(recognizer.pointerDown(at: location(of: event), time: event.timestamp, idle: session.isIdle))
    }
    override func mouseDragged(with event: NSEvent) {
        route(recognizer.pointerDragged(to: location(of: event), time: event.timestamp))
    }
    override func mouseUp(with event: NSEvent) {
        route(recognizer.pointerUp(at: location(of: event), time: event.timestamp))
    }

    private var activity: StartPageMarkActivity {
        guard let window else { return .inactive }
        return StartPageMarkActivity(windowVisible: window.isVisible, occluded: !window.occlusionState.contains(.visible),
                                     miniaturized: window.isMiniaturized, hidden: isHiddenOrHasHiddenAncestor)
    }

    private func location(of event: NSEvent) -> CGPoint { convert(event.locationInWindow, from: nil) }

    private func activityChanged() {
        if !activity.canAnimate { stopInteraction() }
    }

    private func abandonInteraction() {
        if case .interacting = session.phase { stopInteraction() }
    }

    private func stopInteraction() {
        perform(session.pause())
        recognizer.reset()
        scheduleHold()
    }

    private func route(_ cues: [StartPageMarkCue]) {
        if !cues.isEmpty {
            let canAnimate = activity.canAnimate
            let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            for cue in cues { perform(session.handle(cue, canAnimate: canAnimate, reduceMotion: reduceMotion)) }
        }
        scheduleHold()
    }

    private func scheduleHold() {
        let deadline = recognizer.holdDeadline
        guard deadline != holdDeadline else { return }
        holdTimer?.invalidate()
        holdTimer = nil
        holdDeadline = deadline
        guard let deadline else { return }
        let timer = Timer(timeInterval: max(0, deadline - ProcessInfo.processInfo.systemUptime), repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.holdElapsed() }
        }
        RunLoop.main.add(timer, forMode: .common)
        holdTimer = timer
    }

    private func holdElapsed() {
        holdTimer = nil
        holdDeadline = nil
        guard NSEvent.pressedMouseButtons & 1 != 0 else { return stopInteraction() }
        route(recognizer.holdElapsed(at: ProcessInfo.processInfo.systemUptime))
    }

    private func perform(_ effects: [StartPageMarkSession.Effect]) {
        guard !effects.isEmpty else { return }
        let generation = session.generation
        let finish: @MainActor () -> Void = { [weak self] in self?.session.finish(generation: generation) }
        let landed: @MainActor () -> Void = { [weak self] in
            guard let self else { return }
            self.perform(self.session.land(generation: generation))
        }
        motion?.contentsScale = window?.backingScaleFactor ?? 2
        for effect in effects {
            switch effect {
            case .track(let pull):
                motion?.track(pull)
            case .charge(let style):
                motion?.charge(style)
            case .play(let play):
                guard let motion else { finish(); continue }
                let place = effectPlacement()
                switch play {
                case .snap(let pull):
                    motion.snap(from: pull, completion: finish)
                case .swoop:
                    motion.swoop(in: place?.layer, home: place?.home ?? .zero, pageWidth: place?.width ?? superview?.bounds.width ?? 0,
                                 landed: landed, completion: finish)
                case .loop:
                    motion.loop(in: place?.layer, home: place?.home ?? .zero, landed: landed, completion: finish)
                case .relax(let level, let style):
                    motion.relax(level: level, style: style, completion: finish)
                }
            case .shimmer:
                if let motion { motion.playShimmer(completion: finish) } else { finish() }
            case .haptic:
                performHapticFeedback()
            case .reset:
                motion?.reset()
                recognizer.reset()
                scheduleHold()
            }
        }
    }

    private func effectPlacement() -> (layer: CALayer, home: CGPoint, width: CGFloat)? {
        guard let host = effectsHost, let window, host.window === window, let layer = host.layer else { return nil }
        let center = host.convert(NSPoint(x: bounds.midX, y: bounds.midY), from: self)
        return (layer, host.isFlipped ? center : CGPoint(x: center.x, y: host.bounds.height - center.y), host.bounds.width)
    }

    private func refreshFill() {
        let appearance = window?.effectiveAppearance ?? effectiveAppearance
        let source = incognito ? IncognitoWindowTheme.paletteTheme : theme
        let palette = incognito
            ? ThemeChromePalette(theme: source, isDark: appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua)
            : ThemeChromePalette(theme: theme, appearance: appearance)
        let content = palette.contentAppearance
        let paging = incognito || style == .borderless ? nil : pagingTransition
        fill = StartPageMarkFill(colorMark: style == .borderless, themeHasColor: Self.hasColor(theme),
                                 pagingHasColor: paging.map { (Self.hasColor($0.from), Self.hasColor($0.theme)) }, incognito: incognito)
        if fill == .theme {
            let renderer = renderer ?? makeRenderer()
            renderer.theme = theme
            renderer.pagingTransition = paging
        } else if renderer?.pagingTransition != nil {
            renderer?.pagingTransition = nil
        }
        renderer?.isHidden = fill != .theme
        ink.isHidden = fill == .art
        let inkColor: CGColor
        if let paging, fill != .art {
            let inks = inks(for: paging, appearance: appearance)
            inkColor = StartPageMarkTint.blend(inks.from, inks.to, progress: paging.progress)
        } else {
            pagingInks = nil
            inkColor = fill == .theme
                ? palette.maxContrastColor.cgColor(in: content).copy(alpha: Self.tintAlpha) ?? palette.maxContrastColor.cgColor(in: content)
                : palette.foregroundSecondary.cgColor(in: content)
        }
        if ink.layer?.backgroundColor != inkColor { ink.layer?.backgroundColor = inkColor }
        art.isHidden = fill != .art
        if fill == .art, art.image == nil { art.image = ParcBrandMark.image(.borderless) }
        let colors = source.colors.map(Self.color)
        motion?.shimmerColors = StartPageMarkShimmer.sequence(((colors.isEmpty ? [palette.foregroundPrimary] : colors)
            + [palette.maxContrastColor]).map { $0.cgColor(in: content) })
        motion?.colors = (colors.isEmpty ? [palette.foregroundSecondary, palette.foregroundTertiary, palette.foregroundPrimary] : colors)
            .prefix(StartPageMarkSwoop.maximumStripes).map { $0.cgColor(in: content) }
    }

    private func inks(for paging: ThemePagingTransition, appearance: NSAppearance) -> (from: CGColor, to: CGColor) {
        let key = [paging.from, paging.theme]
        if let cached = pagingInks, cached.key == key, cached.appearance == appearance.name { return (cached.from, cached.to) }
        func tint(_ theme: SpaceTheme) -> CGColor {
            let palette = ThemeChromePalette(theme: theme, appearance: appearance)
            let content = palette.contentAppearance
            guard Self.hasColor(theme) else { return palette.foregroundSecondary.cgColor(in: content) }
            let color = palette.maxContrastColor.cgColor(in: content)
            return color.copy(alpha: Self.tintAlpha) ?? color
        }
        let inks = (from: tint(paging.from), to: tint(paging.theme))
        pagingInks = (key, appearance.name, inks.from, inks.to)
        return inks
    }

    private func makeRenderer() -> ThemeRendererView {
        let view = ThemeRendererView(frame: stage.bounds)
        view.drawsMaterial = false
        view.coordinateSpace = coordinateSpace
        stage.addSubview(view, positioned: .below, relativeTo: ink)
        renderer = view
        return view
    }

    private static func hasColor(_ theme: SpaceTheme) -> Bool { theme.isValid && theme.colorCount > 0 }

    private static func color(_ value: ThemeColor) -> NSColor {
        let space: NSColorSpace
        switch value.colorSpace {
        case .sRGB: space = .sRGB
        case .displayP3: space = .displayP3
        case .linearSRGB: space = NSColorSpace(cgColorSpace: CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!)!
        }
        return NSColor(colorSpace: space, components: [value.red, value.green, value.blue, 1], count: 4)
    }
}
