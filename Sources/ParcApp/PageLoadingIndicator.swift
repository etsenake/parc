import AppKit
import QuartzCore

/// Layer values one loading-pill display-link tick would write. Identical
/// fingerprints are a true presentation no-op: the display link still samples
/// pulse/sweep so the recovered motion continues, but `needsDisplay`-equivalent
/// CALayer transactions skip when scale/opacity/stroke would not change.
struct PageLoadingPresentation: Equatable {
    var scale: Float
    var fillOpacity: Float
    var trackOpacity: Float
    var strokeStart: Float
    var strokeEnd: Float
}

/// True no-op gate for loading-pill presentation. Display-link ticks whose
/// pulse/sweep fingerprint already matches the last apply skip the layer
/// transaction; a changed frame still presents. The link keeps running while
/// loading/sweeping (or hidden settle) can still produce a different frame.
enum PageLoadingPresentationSkip {
    static func shouldSkip(previous: PageLoadingPresentation?, next: PageLoadingPresentation) -> Bool {
        previous == next
    }
}

///
/// `WindowContentViewController.scrimLoader` places over the window content
///
///
///
///   half its height, continuous curve, clipping) with a 128 × 4 fill layer
///
///
///
///
///
///
///
///
///   `NSColor(named:bundle:)`), not the Space palette. It resolves under the
///   Space's content appearance, which the window content sets on the loader
///
///
///   load starts the loading phase, whose `pulseProgress` runs on an undamped
///
///
///
///   it sweeps: the pulse settles to 1 (damping 0.92, response 0.8 s), fill
///
///
///
///
///   after initialising it to clear, so its brightness reads 0.
///
///
/// not have. Reduce Motion keeps a static, fully shown 48-point track while
/// loading and never sweeps (adaptation). The display link pauses while the
/// window is occluded or minimized and resumes from the current phase; it stops
/// when idle (hidden and settled, or Reduce Motion's static track). While the
/// link runs, identical pulse/sweep presentation fingerprints skip the layer
/// write.
@MainActor final class PageLoadingIndicator: NSView {
    static let size = NSSize(width: 128, height: 4)
    static let sweepDelay: CFTimeInterval = 3.2
    static let sweepPeriod: CFTimeInterval = 1.125
    static let sweepBarOpacity: Float = 0.92

    ///
    static func foregroundPrimary(dark: Bool) -> NSColor {
        dark ? NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.8)
             : NSColor(displayP3Red: 14.0 / 255, green: 15.0 / 255, blue: 16.0 / 255, alpha: 0.9)
    }

    static func trackSize(sweeping: Bool) -> CGSize {
        CGSize(width: sweeping ? size.width : 48, height: size.height)
    }

    ///
    /// response 0.8 s.
    static func phaseSpring(keyPath: String, from: Any?, to: Any?) -> CASpringAnimation {
        let omega = 2 * Double.pi / 0.8
        let spring = CASpringAnimation(keyPath: keyPath)
        spring.mass = 1
        spring.stiffness = omega * omega
        spring.damping = 2 * 0.92 * omega
        spring.fromValue = from
        spring.toValue = to
        spring.duration = spring.settlingDuration
        return spring
    }

    private enum Phase { case hidden, loading, sweeping }

    private let track = CALayer()
    private let fill = CALayer()
    private let bar = CAShapeLayer()
    private var phase = Phase.hidden
    private var pulse: Double = 0, velocity: Double = 0
    private var loadingStart: CFTimeInterval = 0, sweepStart: CFTimeInterval = 0
    private var lastTick: CFTimeInterval = 0
    private var lastPresentation: PageLoadingPresentation?
    private let frames = ViewDisplayFrameDriver()

    /// Centred over one pane (its horizontal span in the host) in the host's
    ///
    /// were not recovered.
    static func frame(paneMinX: CGFloat, paneWidth: CGFloat, bandHeight: CGFloat) -> NSRect {
        let width = min(size.width, max(0, paneWidth))
        return NSRect(x: (paneMinX + paneWidth / 2 - width / 2).rounded(), y: max(0, bandHeight / 2 - size.height / 2),
                      width: width, height: size.height)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = false
        track.masksToBounds = true
        track.cornerCurve = .continuous
        track.cornerRadius = Self.size.height / 2
        track.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        track.bounds = CGRect(origin: .zero, size: Self.trackSize(sweeping: false))
        fill.opacity = 0
        bar.lineWidth = 4
        bar.fillColor = nil
        bar.opacity = 0
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: 2)); path.addLine(to: CGPoint(x: Self.size.width, y: 2))
        bar.path = path
        bar.strokeStart = 0; bar.strokeEnd = 0
        for sublayer in [track, fill, bar] as [CALayer] { sublayer.actions = Self.noActions }
        track.addSublayer(fill); track.addSublayer(bar)
        layer?.addSublayer(track)
        applyColor()
        presentPulse(stroke: (0, 0), force: true)
        setAccessibilityElement(false)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private static let noActions: [String: CAAction] = ["position": NSNull(), "bounds": NSNull(), "transform": NSNull(),
                                                        "opacity": NSNull(), "strokeStart": NSNull(), "strokeEnd": NSNull(),
                                                        "backgroundColor": NSNull(), "strokeColor": NSNull()]

    override func layout() {
        super.layout()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        track.bounds = CGRect(origin: .zero, size: Self.trackSize(sweeping: phase == .sweeping))
        track.position = CGPoint(x: bounds.midX, y: bounds.midY)
        fill.frame = CGRect(origin: .zero, size: Self.size)
        bar.frame = CGRect(origin: .zero, size: Self.size)
        CATransaction.commit()
    }

    ///
    /// on-screen bounds.
    private func setTrackSize(animated: Bool) {
        let target = CGRect(origin: .zero, size: Self.trackSize(sweeping: phase == .sweeping))
        guard track.bounds != target else { return }
        if animated, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            let from = track.presentation()?.bounds ?? track.bounds
            track.add(Self.phaseSpring(keyPath: "bounds", from: NSValue(rect: from), to: NSValue(rect: target)), forKey: "bounds")
        } else {
            track.removeAnimation(forKey: "bounds")
        }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        track.bounds = target
        CATransaction.commit()
    }

    var isLoading: Bool { phase != .hidden }

    func setLoading(_ loading: Bool) {
        if loading == isLoading { return }
        let now = CACurrentMediaTime()
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if loading {
            phase = .loading; loadingStart = now
            if reduceMotion { pulse = 1; velocity = 0 }
        } else {
            phase = .hidden
            setBarVisible(false); setTrackSize(animated: true)
            if reduceMotion { pulse = 0; velocity = 0 }
        }
        presentPulse(stroke: (bar.strokeStart, bar.strokeEnd), force: true)
        if needsFrames { startFrames() } else { stopFrames(); if !loading, !windowVisible { settleHidden() } }
    }

    /// True while the recovered pulse/sweep still has work. Reduce Motion's
    /// static shown track and a settled hidden rest are no-ops.
    private var needsFrames: Bool {
        guard windowVisible else { return false }
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            return phase == .hidden && (abs(pulse) >= 0.001 || abs(velocity) >= 0.01)
        }
        switch phase {
        case .loading, .sweeping: return true
        case .hidden: return abs(pulse) >= 0.001 || abs(velocity) >= 0.01
        }
    }

    private func startFrames() {
        guard !frames.isRunning, windowVisible else { return }
        lastTick = CACurrentMediaTime()
        frames.start(in: self) { [weak self] in self?.tick() ?? false }
    }
    private func stopFrames() { frames.stop() }

    private func tick() -> Bool {
        tick(now: CACurrentMediaTime())
    }

    private func tick(now: CFTimeInterval) -> Bool {
        let step = min(1.0 / 20, max(0, now - lastTick)); lastTick = now
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        var stroke = (start: bar.strokeStart, end: bar.strokeEnd)
        switch phase {
        case .loading:
            if reduceMotion { pulse = 1; velocity = 0 }
            else { integrate(target: 0.5, response: 3.2, damping: 0, step: step) }
            if !reduceMotion, now - loadingStart > Self.sweepDelay, pulse <= 0.05 {
                phase = .sweeping; sweepStart = now
                setBarVisible(true); setTrackSize(animated: true)
                stroke = Self.stroke(at: 0)
            }
        case .sweeping:
            if reduceMotion {
                // A preference change mid-sweep returns to the static track.
                phase = .loading; pulse = 1; velocity = 0
                setBarVisible(false); setTrackSize(animated: false)
            } else {
                integrate(target: 1, response: 0.8, damping: 0.92, step: step)
                stroke = Self.stroke(at: now - sweepStart)
            }
        case .hidden:
            integrate(target: 0, response: 0.8, damping: 0.92, step: step)
            if reduceMotion || (abs(pulse) < 0.001 && abs(velocity) < 0.01) {
                pulse = 0; velocity = 0
                stroke = (0, 0)
            }
        }
        presentPulse(stroke: stroke)
        return needsFrames
    }

    /// Spring toward `target` (SwiftUI-style response / damping fraction).
    private func integrate(target: Double, response: Double, damping: Double, step: Double) {
        let omega = 2 * Double.pi / response
        var remaining = step
        while remaining > 0 {
            let dt = min(remaining, 1.0 / 240); remaining -= dt
            velocity += (-omega * omega * (pulse - target) - 2 * damping * omega * velocity) * dt
            pulse += velocity * dt
        }
    }

    ///
    /// start for 0.375 s, then stays empty for 0.375 s.
    static func stroke(at time: CFTimeInterval) -> (start: CGFloat, end: CGFloat) {
        let t = time.truncatingRemainder(dividingBy: sweepPeriod)
        if t < 0.375 { return (0, CGFloat(t / 0.375)) }
        if t < 0.75 { return (CGFloat((t - 0.375) / 0.375), 1) }
        return (0, 0)
    }

    /// Samples the same scale/opacity/stroke values a tick would write.
    static func presentation(
        pulse: Double,
        sweeping: Bool,
        stroke: (start: CGFloat, end: CGFloat),
        barOpacity: Float,
        hidden: Bool
    ) -> PageLoadingPresentation {
        let clamped = max(0, pulse)
        let fill = (sweeping ? 0.276 : 0.92) * clamped
        let trackOpacity: Float = hidden && clamped < 0.001 && barOpacity == 0 ? 0 : 1
        return PageLoadingPresentation(
            scale: Float(0.88 + 0.12 * clamped),
            fillOpacity: Float(min(1, fill)),
            trackOpacity: trackOpacity,
            strokeStart: Float(stroke.start),
            strokeEnd: Float(stroke.end)
        )
    }

    private func setBarVisible(_ visible: Bool) {
        let target: Float = visible ? Self.sweepBarOpacity : 0
        guard bar.opacity != target else { return }
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            let from = bar.presentation()?.opacity ?? bar.opacity
            bar.add(Self.phaseSpring(keyPath: "opacity", from: from, to: target), forKey: "opacity")
        } else {
            bar.removeAnimation(forKey: "opacity")
        }
        bar.opacity = target
        // Track opacity depends on bar opacity; force the next present.
        lastPresentation = nil
    }

    private func presentPulse(stroke: (start: CGFloat, end: CGFloat), force: Bool = false) {
        let next = Self.presentation(
            pulse: pulse,
            sweeping: phase == .sweeping,
            stroke: stroke,
            barOpacity: bar.opacity,
            hidden: phase == .hidden
        )
        if !force, PageLoadingPresentationSkip.shouldSkip(previous: lastPresentation, next: next) {
            return
        }
        lastPresentation = next
        CATransaction.begin(); CATransaction.setDisableActions(true)
        track.transform = CATransform3DMakeScale(CGFloat(next.scale), CGFloat(next.scale), 1)
        fill.opacity = next.fillOpacity
        track.opacity = next.trackOpacity
        bar.strokeStart = CGFloat(next.strokeStart)
        bar.strokeEnd = CGFloat(next.strokeEnd)
        CATransaction.commit()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyColor()
    }

    private func applyColor() {
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let cgColor = Self.foregroundPrimary(dark: dark).cgColor
        CATransaction.begin(); CATransaction.setDisableActions(true)
        fill.backgroundColor = cgColor
        bar.strokeColor = cgColor
        CATransaction.commit()
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    /// Stops at once and returns to the hidden resting state (window close,
    /// pane removal).
    func reset() {
        stopFrames()
        phase = .hidden
        settleHidden()
    }

    private var occlusionObserver: NSObjectProtocol?
    private var windowVisible: Bool {
        guard let window, !isHiddenOrHasHiddenAncestor else { return false }
        return window.occlusionState.contains(.visible) && !window.isMiniaturized
    }
    /// A hidden Peek or indicator host pauses the pulse like an occluded window.
    override func viewDidHide() { super.viewDidHide(); occlusionChanged() }
    override func viewDidUnhide() { super.viewDidUnhide(); occlusionChanged() }
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if let occlusionObserver { NotificationCenter.default.removeObserver(occlusionObserver) }
        occlusionObserver = nil
        super.viewWillMove(toWindow: newWindow)
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { stopFrames(); return }
        occlusionObserver = NotificationCenter.default.addObserver(forName: NSWindow.didChangeOcclusionStateNotification,
                                                                   object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.occlusionChanged() }
        }
        occlusionChanged()
    }
    private func occlusionChanged() {
        if !windowVisible {
            stopFrames()
            // A load that ends while nothing can see the fade-out rests at
            // once, so no fading pill shows up on return.
            if phase == .hidden { settleHidden() }
        } else if needsFrames { startFrames() }
    }
    private func settleHidden() {
        pulse = 0; velocity = 0
        bar.removeAllAnimations(); bar.opacity = 0
        track.removeAllAnimations(); setTrackSize(animated: false)
        presentPulse(stroke: (0, 0), force: true)
    }
}

///
/// `scrimLoadingIndicatorEnabledAboveWindowContent` (WindowContent.State field
///
///
/// of the split's window contents or whose split is not stacked vertically. Each
///
///
@MainActor final class PageLoadingIndicatorHost: NSView {
    struct Pane: Equatable {
        let id: UUID
        /// The pane's horizontal span in host coordinates.
        let minX: CGFloat, width: CGFloat
        let loading: Bool
    }
    private(set) var indicators: [UUID: PageLoadingIndicator] = [:]

    ///
    static func eligible(_ ids: [UUID], stacked: Bool) -> [UUID] { stacked ? Array(ids.prefix(1)) : ids }

    ///
    /// without a scrim (page full screen, inset 0) was not recovered, so the
    /// band then has no height and the host hides (adaptation).
    static func frame(pageHost: NSRect) -> NSRect {
        NSRect(x: pageHost.minX, y: 0, width: pageHost.width, height: max(0, min(10, pageHost.minY)))
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(false)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func update(_ panes: [Pane]) {
        isHidden = bounds.height < PageLoadingIndicator.size.height
        let live = Set(panes.map(\.id))
        for (id, indicator) in indicators where !live.contains(id) {
            indicator.reset(); indicator.removeFromSuperview(); indicators.removeValue(forKey: id)
        }
        for pane in panes {
            let indicator = indicators[pane.id] ?? {
                let made = PageLoadingIndicator()
                addSubview(made); indicators[pane.id] = made
                return made
            }()
            indicator.frame = PageLoadingIndicator.frame(paneMinX: pane.minX, paneWidth: pane.width, bandHeight: bounds.height)
            indicator.setLoading(pane.loading && !isHidden)
        }
    }

    func reset() {
        for indicator in indicators.values { indicator.reset(); indicator.removeFromSuperview() }
        indicators.removeAll()
    }
}
