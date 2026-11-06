import AppKit

//
//
//
//
// 1 pt white 12% border over whatever it holds. Nothing inside adds a radius
// of its own, so the content meets the frame's corner exactly.
enum PictureInPictureFrame {
    static let cornerRadius: CGFloat = 6
    //
    // the content names no minimum of its own.
    static let defaultMinimumSize = NSSize(width: 224, height: 126)
    //
    static let screenMargin: CGFloat = 10

    static func style(_ layer: CALayer?) {
        guard let layer else { return }
        layer.backgroundColor = NSColor(white: 0, alpha: 0.8).cgColor
        layer.cornerRadius = cornerRadius
        layer.cornerCurve = .continuous
        layer.masksToBounds = true
        layer.borderWidth = 1
        layer.borderColor = NSColor(white: 1, alpha: 0.12).cgColor
    }

    ///
    ///
    static func maximumSize(on screen: NSScreen?, minimum: NSSize) -> NSSize {
        guard let screen = screen ?? NSScreen.main else {
            return NSSize(width: max(minimum.width, 1280), height: max(minimum.height, 800))
        }
        return NSSize(width: max(minimum.width, (screen.frame.width * 0.617).rounded(.down)),
                      height: max(minimum.height, screen.visibleFrame.height - 2 * screenMargin))
    }

    /// Size limits for a window that keeps the content's aspect ratio: the
    ///
    ///
    static func limits(aspect: NSSize, minimum: NSSize, on screen: NSScreen?) -> (minimum: NSSize, maximum: NSSize) {
        let maximum = maximumSize(on: screen, minimum: minimum)
        guard aspect.width > 0, aspect.height > 0, aspect.width.isFinite, aspect.height.isFinite else {
            return (minimum, maximum)
        }
        let low = max(minimum.width / aspect.width, minimum.height / aspect.height)
        let high = max(low, min(maximum.width / aspect.width, maximum.height / aspect.height))
        return (NSSize(width: aspect.width * low, height: aspect.height * low),
                NSSize(width: aspect.width * high, height: aspect.height * high))
    }

    /// Moves a frame inside the screen's visible area less the margin,
    /// shrinking it only when it can't fit.
    static func constrain(_ frame: NSRect, to screen: NSScreen?) -> NSRect {
        guard let screen = screen ?? NSScreen.main else { return frame }
        let area = restingArea(on: screen)
        var result = frame
        result.size.width = min(result.width, area.width)
        result.size.height = min(result.height, area.height)
        result.origin.x = min(max(result.minX, area.minX), area.maxX - result.width)
        result.origin.y = min(max(result.minY, area.minY), area.maxY - result.height)
        return result
    }

    /// Where a window may come to rest: the screen's visible area less the margin.
    static func restingArea(on screen: NSScreen) -> NSRect {
        screen.visibleFrame.insetBy(dx: screenMargin, dy: screenMargin)
    }

    /// The resting area of the screen under the pointer, else of the screen
    ///
    static func restingArea(for frame: NSRect, pointer: NSPoint) -> NSRect {
        let screens = NSScreen.screens
        func overlap(_ screen: NSScreen) -> CGFloat {
            let shared = screen.frame.intersection(frame)
            return shared.isNull ? 0 : shared.width * shared.height
        }
        guard let screen = screens.first(where: { $0.frame.contains(pointer) })
                ?? screens.max(by: { overlap($0) < overlap($1) }) ?? NSScreen.main else { return frame }
        return restingArea(on: screen)
    }
}

//
// window follows the pointer, giving way to only 35% of any distance past the
// screen margin; on release it springs back inside the margin or, flung faster
//
// corner. A fling carries its speed into the spring whether or not it reaches
// a corner; with Reduce Motion on, the window only springs back. Pinching
//
// its size limits with a haptic tick as it crosses one, and springs back
// within them on release. Double-clicking toggles its largest size about its
//
//
@MainActor
final class PictureInPictureMotion: NSObject {
    private static let edgeGive: CGFloat = 0.35
    private static let limitGive: CGFloat = 0.1
    private static let flingSpeed: CGFloat = 350
    private static let cornerAngle: CGFloat = .pi / 4
    private static let dragThreshold: CGFloat = 3

    private weak var window: NSWindow?
    private var pressed = false
    private var grab: NSPoint?
    private var dragStart = NSPoint.zero
    private var samples: [(time: TimeInterval, point: NSPoint)] = []
    private var pinchStart: NSRect?
    private var pastLimit = false
    private var frameBeforeLargest: NSRect?
    //
    private var originSpring = DownloadArrivalSpring()
    private var sizeSpring = DownloadArrivalSpring()
    private var target = NSRect.zero
    private var lastTick: CFTimeInterval = 0
    private var ticker: Timer?

    init(window: NSWindow) {
        self.window = window
        super.init()
    }

    func beginDrag(with event: NSEvent) {
        guard window != nil else { return }
        let mouse = NSEvent.mouseLocation
        pressed = true
        grab = nil
        dragStart = mouse
        samples = [(event.timestamp, mouse)]
    }

    func drag(with event: NSEvent) {
        guard let window, pressed else { return }
        let mouse = NSEvent.mouseLocation
        if grab == nil {
            guard hypot(mouse.x - dragStart.x, mouse.y - dragStart.y) >= Self.dragThreshold else { return }
            //
            // stops it once it begins; a plain click leaves it running. The
            // window then follows the pointer's whole way from the press.
            stop()
            grab = NSPoint(x: dragStart.x - window.frame.minX, y: dragStart.y - window.frame.minY)
        }
        guard let grab else { return }
        samples.append((event.timestamp, mouse))
        samples.removeAll { event.timestamp - $0.time > 0.1 }
        let size = window.frame.size
        var origin = NSPoint(x: mouse.x - grab.x, y: mouse.y - grab.y)
        let area = PictureInPictureFrame.restingArea(for: NSRect(origin: origin, size: size), pointer: mouse)
        origin.x = Self.give(origin.x, length: size.width, low: area.minX, high: area.maxX)
        origin.y = Self.give(origin.y, length: size.height, low: area.minY, high: area.maxY)
        window.setFrameOrigin(origin)
    }

    func endDrag(with event: NSEvent) {
        defer {
            pressed = false
            grab = nil
            samples.removeAll()
        }
        guard let window, pressed, grab != nil else { return }
        // The speed over the last 0.1 s up to release, so a pause first is no fling.
        samples.append((event.timestamp, NSEvent.mouseLocation))
        samples.removeAll { event.timestamp - $0.time > 0.1 }
        var velocity = CGVector.zero
        if let first = samples.first, let last = samples.last, last.time - first.time > 0.005 {
            let elapsed = CGFloat(last.time - first.time)
            velocity = CGVector(dx: (last.point.x - first.point.x) / elapsed,
                                dy: (last.point.y - first.point.y) / elapsed)
        }
        let frame = window.frame
        let area = PictureInPictureFrame.restingArea(for: frame, pointer: NSEvent.mouseLocation)
        let fling = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion &&
            hypot(velocity.dx, velocity.dy) > Self.flingSpeed
        var rest = NSRect(origin: Self.clamp(frame.origin, size: frame.size, in: area), size: frame.size)
        if fling, let corner = Self.corner(toward: velocity, from: frame, in: area) { rest.origin = corner }
        settle(to: rest, velocity: fling ? velocity : .zero)
    }

    @objc func magnify(_ recognizer: NSMagnificationGestureRecognizer) {
        guard let window, window.styleMask.contains(.resizable) else { return }
        switch recognizer.state {
        case .began:
            stop()
            pinchStart = window.frame
            pastLimit = false
        case .changed:
            guard let start = pinchStart else { return }
            let (low, high) = scaleLimits(for: start.size)
            var scale = 1 + recognizer.magnification
            if scale < low { scale = low + (scale - low) * Self.limitGive }
            if scale > high { scale = high + (scale - high) * Self.limitGive }
            let beyond = scale < low || scale > high
            if beyond, !pastLimit {
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
            }
            pastLimit = beyond
            window.setFrame(Self.scaled(start, by: scale), display: true)
        case .ended, .cancelled, .failed:
            guard let start = pinchStart else { return }
            pinchStart = nil
            let (low, high) = scaleLimits(for: start.size)
            var rest = Self.scaled(start, by: min(max(window.frame.width / max(start.width, 1), low), high))
            let area = PictureInPictureFrame.restingArea(for: rest, pointer: NSEvent.mouseLocation)
            rest.origin = Self.clamp(rest.origin, size: rest.size, in: area)
            settle(to: rest, velocity: .zero)
        default:
            break
        }
    }

    func toggleLargest() {
        guard let window, window.styleMask.contains(.resizable) else { return }
        // Mid-move, the size it is heading for counts as its size.
        let current = ticker == nil ? window.frame : target
        let largest = window.maxSize
        let grown = PictureInPictureFrame.constrain(
            NSRect(x: current.midX - largest.width / 2, y: current.midY - largest.height / 2,
                   width: largest.width, height: largest.height), to: window.screen)
        if let saved = frameBeforeLargest, current.integral == grown.integral {
            frameBeforeLargest = nil
            settle(to: PictureInPictureFrame.constrain(saved, to: window.screen), velocity: .zero)
        } else {
            frameBeforeLargest = current
            settle(to: grown, velocity: .zero)
        }
    }

    /// Stops a move where it is, as a new drag, pinch or resize does.
    func stop() {
        ticker?.invalidate()
        ticker = nil
    }

    private func scaleLimits(for size: NSSize) -> (CGFloat, CGFloat) {
        guard let window, size.width > 0, size.height > 0 else { return (1, 1) }
        let low = max(window.minSize.width / size.width, window.minSize.height / size.height)
        let high = min(window.maxSize.width / size.width, window.maxSize.height / size.height)
        return (min(low, 1), max(high, 1))
    }

    private static func scaled(_ frame: NSRect, by scale: CGFloat) -> NSRect {
        let size = NSSize(width: (frame.width * scale).rounded(), height: (frame.height * scale).rounded())
        return NSRect(x: (frame.midX - size.width / 2).rounded(), y: (frame.midY - size.height / 2).rounded(),
                      width: size.width, height: size.height)
    }

    private static func give(_ origin: CGFloat, length: CGFloat, low: CGFloat, high: CGFloat) -> CGFloat {
        guard high - low >= length else { return origin }
        if origin < low { return low - (low - origin) * edgeGive }
        if origin + length > high { return high - length + (origin + length - high) * edgeGive }
        return origin
    }

    private static func clamp(_ origin: NSPoint, size: NSSize, in area: NSRect) -> NSPoint {
        NSPoint(x: min(max(origin.x, area.minX), max(area.minX, area.maxX - size.width)),
                y: min(max(origin.y, area.minY), max(area.minY, area.maxY - size.height)))
    }

    /// The corner whose direction from the window is nearest the fling's,
    /// if within 45° of it.
    private static func corner(toward velocity: CGVector, from frame: NSRect, in area: NSRect) -> NSPoint? {
        let heading = atan2(velocity.dy, velocity.dx)
        let corners = [NSPoint(x: area.minX, y: area.minY), NSPoint(x: area.maxX - frame.width, y: area.minY),
                       NSPoint(x: area.minX, y: area.maxY - frame.height),
                       NSPoint(x: area.maxX - frame.width, y: area.maxY - frame.height)]
        var best: (corner: NSPoint, difference: CGFloat)?
        for corner in corners where hypot(corner.x - frame.minX, corner.y - frame.minY) >= 1 {
            var difference = abs(atan2(corner.y - frame.minY, corner.x - frame.minX) - heading)
                .truncatingRemainder(dividingBy: 2 * .pi)
            if difference > .pi { difference = 2 * .pi - difference }
            if difference < cornerAngle, difference < (best?.difference ?? .infinity) {
                best = (corner, difference)
            }
        }
        return best?.corner
    }

    private func settle(to rest: NSRect, velocity: CGVector) {
        guard let window else { return }
        stop()
        let from = window.frame
        guard from != rest || velocity != .zero else { return }
        originSpring = DownloadArrivalSpring(initialValue: SIMD2(from.minX, from.minY))
        originSpring.configure(response: 0.9, dampingRatio: 0.9)
        originSpring.toValue = SIMD2(rest.minX, rest.minY)
        originSpring.setVelocity(SIMD2(velocity.dx, velocity.dy))
        sizeSpring = DownloadArrivalSpring(initialValue: SIMD2(from.width, from.height))
        sizeSpring.configure(response: 0.9, dampingRatio: 0.9)
        sizeSpring.toValue = SIMD2(rest.width, rest.height)
        target = rest
        lastTick = CACurrentMediaTime()
        let ticker = Timer(timeInterval: 1.0 / 120, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self else {
                    timer.invalidate()
                    return
                }
                self.tick()
            }
        }
        RunLoop.main.add(ticker, forMode: .common)
        self.ticker = ticker
    }

    private func tick() {
        guard let window, window.isVisible else {
            stop()
            return
        }
        let now = CACurrentMediaTime()
        originSpring.tick(now - lastTick)
        sizeSpring.tick(now - lastTick)
        lastTick = now
        if originSpring.hasResolved && sizeSpring.hasResolved {
            stop()
            if window.frame != target { window.setFrame(target, display: true) }
            return
        }
        // Whole points: a sub-point change would only make the page lay out again.
        let frame = NSRect(x: originSpring.value.x.rounded(), y: originSpring.value.y.rounded(),
                           width: sizeSpring.value.x.rounded(), height: sizeSpring.value.y.rounded())
        if frame.size != window.frame.size {
            window.setFrame(frame, display: true)
        } else if frame.origin != window.frame.origin {
            window.setFrameOrigin(frame.origin)
        }
    }
}

// The video presenter (Sources/ParcEngine/VideoPiPWindow.m) is an overlay
//
// panel: the clipped container, a single radius (the presenter also rounds
// the video view, rounding each corner twice), the aspect-locked size limits
// it never set, and MovableWindow's drag, pinch and double-click in place of
// the presenter's plain window drag.
@MainActor
final class VideoPictureInPictureFrame {
    private weak var panel: NSPanel?
    private let motion: PictureInPictureMotion
    private var observers: [NSObjectProtocol] = []

    init(presenter: PCVideoPiPPresenter) {
        let panel = presenter.panel
        self.panel = panel
        motion = PictureInPictureMotion(window: panel)
        PictureInPictureFrame.style(panel.contentView?.layer)
        if let video = presenter.videoView.layer {
            video.cornerRadius = 0
            video.masksToBounds = false
        }
        panel.contentView?.addGestureRecognizer(
            NSMagnificationGestureRecognizer(target: motion, action: #selector(PictureInPictureMotion.magnify(_:))))
        let center = NotificationCenter.default
        // The aspect arrives with the first natural size, which also sizes
        // the panel; a later change is caught before the next user resize.
        for name in [NSWindow.didResizeNotification, NSWindow.willStartLiveResizeNotification,
                     NSWindow.didChangeScreenNotification] {
            observers.append(center.addObserver(forName: name, object: panel, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.updateLimits() }
            })
        }
        observers.append(center.addObserver(forName: NSWindow.willStartLiveResizeNotification, object: panel,
                                            queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.motion.stop() }
        })
        // A transparent window's shadow follows its shape only when redrawn:
        // after a pinch or settle step, and once a live resize ends.
        for name in [NSWindow.didResizeNotification, NSWindow.didEndLiveResizeNotification] {
            observers.append(center.addObserver(forName: name, object: panel, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let panel = self?.panel, !panel.inLiveResize else { return }
                    panel.invalidateShadow()
                }
            })
        }
        if let content = panel.contentView {
            let surface = VideoPictureInPictureDragSurface(frame: content.bounds)
            surface.autoresizingMask = [.width, .height]
            surface.motion = motion
            content.addSubview(surface)
        }
        updateLimits()
    }

    func invalidate() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        motion.stop()
    }

    private func updateLimits() {
        guard let panel else { return }
        let limits = PictureInPictureFrame.limits(aspect: panel.contentAspectRatio,
                                                  minimum: PictureInPictureFrame.defaultMinimumSize,
                                                  on: panel.screen)
        if panel.minSize != limits.minimum { panel.minSize = limits.minimum }
        if panel.maxSize != limits.maximum { panel.maxSize = limits.maximum }
    }
}

// Lies over the presenter's video and controls and takes the clicks that
// reach no button or slider, which AppKit delivers only away from the panel's
// resize edges; the presenter's own handler would start a plain window drag.
@MainActor
private final class VideoPictureInPictureDragSurface: NSView {
    weak var motion: PictureInPictureMotion?

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let superview, !isHidden, frame.contains(point) else { return nil }
        for sibling in superview.subviews.reversed() where sibling !== self && !sibling.isHidden {
            if Self.isControl(sibling.hitTest(point)) { return nil }
        }
        return self
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 { motion?.toggleLargest() } else { motion?.beginDrag(with: event) }
    }
    override func mouseDragged(with event: NSEvent) { motion?.drag(with: event) }
    override func mouseUp(with event: NSEvent) { motion?.endDrag(with: event) }

    private static func isControl(_ view: NSView?) -> Bool {
        var view = view
        while let current = view {
            if current is NSButton || current is NSSlider { return true }
            view = current.superview
        }
        return false
    }
}
