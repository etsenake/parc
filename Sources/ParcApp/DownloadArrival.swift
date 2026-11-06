import AppKit
import Combine
import QuartzCore
import SwiftUI

///
///
///
///
///
/// entry's own BoxOfThingsIcon item (DownloadBinBoxOfThingsItem in
///
@MainActor enum DownloadArrivalBinItem {
    static let size = NSSize(width: 32, height: 32)
    static func make(palette: ThemeChromePalette) -> NSView? { DownloadBinBoxOfThingsItem(palette: palette) }
}

/// Main-queue timing for the arrival. A test substitutes a manual clock and
/// drives display frames itself.
@MainActor class DownloadArrivalSchedule {
    static let main = DownloadArrivalSchedule()
    var drivesFrames: Bool { true }
    func after(_ delay: TimeInterval, _ body: @escaping @MainActor () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { MainActor.assumeIsolated { body() } }
    }
    /// `DispatchGroup.notify(queue: .main)` runs its block on a later main turn.
    func async(_ body: @escaping @MainActor () -> Void) {
        DispatchQueue.main.async { MainActor.assumeIsolated { body() } }
    }
}

///
/// CVDisplayLink (`Motion.CoreVideoDriver`); Parc uses the view's display link
/// with that frame's interval, or a 60 Hz timer before macOS 14 measuring the
/// real elapsed time. `onFrame` returns false when nothing is left to tick.
@MainActor final class DownloadArrivalFrameDriver: NSObject {
    private let onFrame: (Double) -> Bool
    private var link: AnyObject?
    private var timer: Timer?
    private var previous: CFTimeInterval?
    init(onFrame: @escaping (Double) -> Bool) { self.onFrame = onFrame }
    var isRunning: Bool { link != nil || timer != nil }
    func start(in view: NSView) {
        guard !isRunning else { return }
        if #available(macOS 14.0, *) {
            let link = view.displayLink(target: self, selector: #selector(displayFrame(_:)))
            link.add(to: .main, forMode: .common); self.link = link
        } else {
            let timer = Timer(timeInterval: 1 / 60, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.timerFrame() }
            }
            RunLoop.main.add(timer, forMode: .common); self.timer = timer
        }
    }
    func stop() {
        if #available(macOS 14.0, *) { (link as? CADisplayLink)?.invalidate() }
        link = nil; timer?.invalidate(); timer = nil; previous = nil
    }
    @available(macOS 14.0, *)
    @objc private func displayFrame(_ link: CADisplayLink) {
        if !onFrame(link.targetTimestamp - link.timestamp) { stop() }
    }
    private func timerFrame() {
        let now = CACurrentMediaTime(), dt = previous.map { now - $0 } ?? 1 / 60
        previous = now
        if !onFrame(dt) { stop() }
    }
}

///
///
/// 12-point card in palette.background with a card-only radius-12 shadow
/// (white 0.15 in dark, black 0.3 otherwise), and the centred 32-point item.
@MainActor final class DownloadArrivalBinView: NSView {
    static let side: CGFloat = 62
    let card = CALayer()
    let item: NSView?
    private let fill: NSColor
    private let paletteAppearance: NSAppearance?

    init(palette: ThemeChromePalette) {
        fill = palette.background
        paletteAppearance = NSAppearance(named: palette.isDark ? .darkAqua : .aqua)
        item = DownloadArrivalBinItem.make(palette: palette)
        super.init(frame: NSRect(x: 0, y: 0, width: Self.side, height: Self.side))
        wantsLayer = true
        card.frame = bounds.insetBy(dx: 8, dy: 8)
        card.cornerRadius = 12; card.cornerCurve = .continuous
        card.shadowRadius = 12; card.shadowOffset = .zero; card.shadowOpacity = 1
        layer?.addSublayer(card)
        if let item {
            let size = DownloadArrivalBinItem.size
            item.frame = NSRect(x: (Self.side - size.width) / 2, y: (Self.side - size.height) / 2,
                                width: size.width, height: size.height)
            addSubview(item)
        }
        updateColors()
    }
    required init?(coder: NSCoder) { nil }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); updateColors() }
    /// The shadow follows the hosting window's colorScheme environment; the card
    /// colour is the window palette captured when the controller was created.
    private func updateColors() {
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        CATransaction.begin(); CATransaction.setDisableActions(true)
        (paletteAppearance ?? effectiveAppearance).performAsCurrentDrawingAppearance { card.backgroundColor = fill.cgColor }
        card.shadowColor = (dark ? NSColor.white.withAlphaComponent(0.15) : NSColor.black.withAlphaComponent(0.3)).cgColor
        CATransaction.commit()
    }
}

///
///
///
///
/// scale; two linear, forwards-filled Core Animation keyframe animations carry
/// it there. Its icon is centred on the content origin, so positions are the
/// icon centre and the scale pivots on it.
@MainActor final class DownloadArrivalPathView: NSView {
    let flight: DownloadArrivalFlight
    let content = NSView(frame: .zero)
    /// Shadow carrier; `face` holds the opacity and rotation.
    let icon = CALayer()
    let face = CALayer()
    private let circle = CALayer()
    private let glyph = CALayer()
    private let palette: ThemeChromePalette
    private(set) var started = false

    init(flight: DownloadArrivalFlight, size: CGSize, palette: ThemeChromePalette) {
        self.flight = flight; self.palette = palette
        super.init(frame: NSRect(origin: .zero, size: size))
        wantsLayer = true
        content.wantsLayer = true
        addSubview(content)
        guard flight.isRenderable, let layer = content.layer, let position = flight.positions.last,
              let scale = flight.scales.last else { return }
        content.setFrameOrigin(position)
        layer.masksToBounds = false
        layer.transform = CATransform3DMakeScale(scale.x, scale.y, 1)
        let side = DownloadArrivalFlight.iconSize
        icon.frame = CGRect(x: -side / 2, y: -side / 2, width: side, height: side)
        // SwiftUI .shadow(color: .blue.opacity(0.25), radius: 8, x: 0, y: 4)
        // outside the opacity and rotation; y is down there and up here.
        icon.shadowRadius = 8; icon.shadowOffset = CGSize(width: 0, height: -4); icon.shadowOpacity = 1
        face.frame = icon.bounds
        // Initial State: alpha 0, rotation −35° (clockwise-positive in SwiftUI).
        face.opacity = 0
        face.transform = CATransform3DMakeRotation(Self.radians(35), 0, 0, 1)
        circle.frame = face.bounds; circle.cornerRadius = side / 2
        glyph.frame = face.bounds
        face.addSublayer(circle); face.addSublayer(glyph); icon.addSublayer(face)
        layer.addSublayer(icon)
    }
    required init?(coder: NSCoder) { nil }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); if started { updateShadow() } }
    /// SwiftUI's `Color.blue` follows the hosting window's colorScheme.
    private func updateShadow() {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        effectiveAppearance.performAsCurrentDrawingAppearance {
            icon.shadowColor = NSColor.systemBlue.withAlphaComponent(0.25).cgColor
        }
        CATransaction.commit()
    }

    static func radians(_ degrees: Double) -> CGFloat { CGFloat(degrees * 0.017453292519943295) }

    ///
    /// both start in one transaction, as the hosted content first appears.
    func start() {
        guard !started, flight.isRenderable, let layer = content.layer else { return }
        started = true
        CATransaction.begin(); CATransaction.setDisableActions(true)
        // Rasterized for the flight's largest scale, (1.6, 1.6) at the apex, so
        // the transform never enlarges the glyph bitmap.
        let scale = (window?.backingScaleFactor ?? 2) * max(1, flight.scales.map { max($0.x, $0.y) }.max() ?? 1)
        let appearance = palette.isDark ? NSAppearance(named: .darkAqua) : NSAppearance(named: .aqua)
        (appearance ?? effectiveAppearance).performAsCurrentDrawingAppearance {
            circle.backgroundColor = palette.backgroundExtra.cgColor
            glyph.contents = Self.glyph(color: palette.maxContrastColor, scale: scale)
        }
        glyph.contentsScale = scale; glyph.minificationFilter = .trilinear
        updateShadow()
        let begin = layer.convertTime(CACurrentMediaTime(), from: nil)
        let position = CAKeyframeAnimation(keyPath: "position")
        position.values = flight.positions.map { NSValue(point: $0) }
        let transform = CAKeyframeAnimation(keyPath: "transform")
        transform.values = flight.scales.map { NSValue(caTransform3D: CATransform3DMakeScale($0.x, $0.y, 1)) }
        for animation in [position, transform] {
            animation.duration = flight.duration; animation.fillMode = .forwards
            animation.isRemovedOnCompletion = false; animation.beginTime = begin
            animation.timingFunction = CAMediaTimingFunction(name: .linear)
            layer.add(animation, forKey: "parc.arrival." + (animation.keyPath ?? ""))
        }
        // withAnimation(.spring(response: 0.3, dampingFraction: 1)) { alpha = 1 }
        // and (.spring(response: 1.2, dampingFraction: 1)) { rotation = 5 }.
        face.opacity = 1
        face.transform = CATransform3DMakeRotation(Self.radians(-5), 0, 0, 1)
        face.add(Self.spring("opacity", from: 0, to: 1, response: 0.3, begin: begin), forKey: "parc.arrival.alpha")
        face.add(Self.spring("transform.rotation.z", from: Self.radians(35), to: Self.radians(-5), response: 1.2, begin: begin),
                 forKey: "parc.arrival.rotation")
        CATransaction.commit()
    }

    /// SwiftUI's spring(response:dampingFraction:) is the unit-mass oscillator
    /// with stiffness (2π/response)² and damping 4π·ζ/response; Core Animation
    /// renders the same curve here (an AppKit rendering adaptation).
    private static func spring(_ keyPath: String, from: CGFloat, to: CGFloat, response: Double, begin: CFTimeInterval) -> CASpringAnimation {
        let spring = CASpringAnimation(keyPath: keyPath)
        spring.mass = 1; spring.stiffness = pow(2 * .pi / response, 2); spring.damping = 4 * .pi / response
        spring.initialVelocity = 0; spring.fromValue = from; spring.toValue = to
        spring.duration = spring.settlingDuration; spring.beginTime = begin; spring.fillMode = .backwards
        return spring
    }

    ///
    ///
    /// resizingMode: .stretch)`, maxContrastColor, 30 × 30. SwiftUI stretches the
    /// glyph's bounds, not the padded NSImage, so the ring meets the 30-point disc.
    static func glyph(color: NSColor, scale: CGFloat) -> CGImage? {
        let side = DownloadArrivalFlight.iconSize
        let renderer = ImageRenderer(content: Image(systemName: "arrow.down.circle").renderingMode(.template)
            .resizable(capInsets: EdgeInsets(), resizingMode: .stretch)
            .foregroundColor(Color(nsColor: color)).frame(width: side, height: side))
        renderer.scale = scale
        return renderer.cgImage
    }
}

///
/// bottom-leading stack framed to the parent window's size, the bin first and
/// each download above it in arrival order.
@MainActor final class DownloadArrivalView: NSView {
    let bin: DownloadArrivalBinView
    init(size: CGSize, palette: ThemeChromePalette) {
        bin = DownloadArrivalBinView(palette: palette)
        super.init(frame: NSRect(origin: .zero, size: size))
        wantsLayer = true
        addSubview(bin)
    }
    required init?(coder: NSCoder) { nil }
    /// `.position(x: binPositionX, y: windowHeight − 53)` in SwiftUI's
    /// top-left space is a centre 53 points above this view's bottom.
    func placeBin(x: CGFloat) {
        let half = DownloadArrivalBinView.side / 2
        bin.setFrameOrigin(NSPoint(x: x - half, y: 53 - half))
    }
}

///
///
///
///
///
///
@MainActor final class DownloadArrivalController {
    enum Status { case preparing, animating, ending }

    /// `DownloadViewModel`'s live state beside its precomputed flight.
    @MainActor final class Download {
        let flight: DownloadArrivalFlight
        let view: DownloadArrivalPathView
        ///
        var offset = DownloadArrivalSpring()
        var offsetRunning = false
        private(set) var iconOffsetX: CGFloat = 0
        init(flight: DownloadArrivalFlight, view: DownloadArrivalPathView) {
            self.flight = flight; self.view = view
            offset.configure(response: 0.9, dampingRatio: 0.82)
        }
        /// `.offset(x: iconOffsetX)` on the whole path view; keyframes keep running inside.
        func setIconOffsetX(_ x: CGFloat) { iconOffsetX = x; view.setFrameOrigin(NSPoint(x: x, y: 0)) }
    }

    let window: NSWindow
    let root: DownloadArrivalView
    let showsBin: Bool
    let windowSize: CGSize
    private(set) var status = Status.preparing
    private(set) var isAnimating = false
    private(set) var downloads: [Download] = []
    private(set) var binPositionX: CGFloat = -80
    private(set) var retired = false
    private var presented = false
    /// `binPositionXAnimator`: initial 0, response 0.9, ratio 0.82, then −80.
    private var bin = DownloadArrivalSpring()
    private var binRunning = false
    private var binCompletion: (() -> Void)?
    /// The DispatchGroup: entered per download, left T + 1 s later.
    private var pending = 0
    private var notifyRegistered = false
    private weak var parent: NSWindow?
    private let palette: ThemeChromePalette
    private let schedule: DownloadArrivalSchedule
    private var onRetire: ((DownloadArrivalController) -> Void)?
    private var securityObserver: NSObjectProtocol?
    private lazy var driver = DownloadArrivalFrameDriver { [weak self] dt in self?.advance(dt) ?? false }

    ///
    /// base coordinates shifted by half the 30-point icon, or (70, 70) when
    /// either coordinate is not finite.
    static func source(screenPoint: NSPoint, in parent: NSWindow) -> CGPoint {
        let point = parent.convertPoint(fromScreen: screenPoint)
        guard point.x.isFinite, point.y.isFinite else { return CGPoint(x: 70, y: 70) }
        let half = DownloadArrivalFlight.iconSize * 0.5
        return CGPoint(x: point.x + half, y: point.y - half)
    }

    init(parent: NSWindow, screenPoint: NSPoint, showsBin: Bool, palette: ThemeChromePalette,
         schedule: DownloadArrivalSchedule? = nil, onRetire: @escaping (DownloadArrivalController) -> Void) {
        self.parent = parent; self.showsBin = showsBin; self.palette = palette
        self.schedule = schedule ?? .main; self.onRetire = onRetire
        let frame = parent.frame
        windowSize = frame.size
        root = DownloadArrivalView(size: frame.size, palette: palette)
        // A plain borderless NSWindow: clear, non-opaque, shadowless, never
        // key, ignoresMouseEvents never set. Its frame is the parent inset by
        //
        // point on each side, so root coordinates are parent frame coordinates.
        let inset = frame.insetBy(dx: 1, dy: 1)
        window = NSWindow(contentRect: inset, styleMask: [], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let container = NSView(frame: NSRect(origin: .zero, size: inset.size))
        root.setFrameOrigin(NSPoint(x: -1, y: -1))
        container.addSubview(root)
        window.contentView = container
        window.isOpaque = false; window.backgroundColor = .clear; window.hasShadow = false
        bin.configure(response: 0.9, dampingRatio: 0.82)
        bin.value = SIMD2(-80, 0)
        root.placeBin(x: binPositionX)
        animateDownload(source: Self.source(screenPoint: screenPoint, in: parent),
                        destination: DownloadArrivalFlight.destinationArgument)
        isAnimating = true
        parent.addChildWindow(window, ordered: .above)
        window.setFrame(inset, display: false)
        window.level = .floating
        window.orderFront(nil)
        presented = true
        if binRunning { startFrames() }
        // Parc adaptation: a security surface on the parent retires the arrival,
        // whose drawn pixels would otherwise cover and swallow clicks over it.
        securityObserver = NotificationCenter.default.addObserver(forName: Notification.Name("PCNativeWindowSecurityStateChanged"),
                                                                  object: parent, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.dismiss(force: true) }
        }
        for download in downloads { download.view.start() }
    }

    ///
    /// append. Bin choice, palette and window size stay at creation values.
    func animate(fromScreenPoint screenPoint: NSPoint) {
        guard !retired, let parent else { return }
        animateDownload(source: Self.source(screenPoint: screenPoint, in: parent),
                        destination: DownloadArrivalFlight.destinationArgument)
    }

    ///
    private func animateDownload(source: CGPoint, destination: CGPoint) {
        guard status != .ending else { return }
        if status == .preparing && showsBin { setBin(show: true, completion: nil) }
        pending += 1
        let flight = DownloadArrivalFlight(source: source, destination: destination, windowSize: windowSize, showsBin: showsBin)
        let download = Download(flight: flight, view: DownloadArrivalPathView(flight: flight, size: windowSize, palette: palette))
        downloads.append(download)
        root.addSubview(download.view)
        scheduleCompletion(download)
        if status == .preparing { notifyRegistered = true }
        status = .animating
        if presented { download.view.start() }
    }

    ///
    /// (only when shown), then the group is left while that slide is starting.
    private func scheduleCompletion(_ download: Download) {
        schedule.after(download.flight.projectileDuration + 1.0) { [weak self, weak download] in
            guard let download else { return }
            if download.flight.showsBin {
                download.offset.value = .zero
                download.offset.toValue = SIMD2(-133, 0)
                self?.start(download)
            }
            self?.leave()
        }
    }

    private func start(_ download: Download) {
        guard !download.offset.hasResolved else { return }
        download.offsetRunning = true; startFrames()
    }

    private func leave() {
        pending -= 1
        guard pending == 0, notifyRegistered else { return }
        notifyRegistered = false
        schedule.async { [weak self] in self?.groupDidDrain() }
    }

    ///
    /// or retire at once without the bin.
    private func groupDidDrain() {
        guard !retired else { return }
        status = .ending
        if showsBin { setBin(show: false) { [weak self] in self?.complete() } } else { complete() }
    }

    ///
    /// is skipped for an already resolved spring.
    private func setBin(show: Bool, completion: (() -> Void)?) {
        bin.toValue = SIMD2(show ? 53 : -80, 0)
        binCompletion = completion
        guard !bin.hasResolved else { return }
        binRunning = true; startFrames()
    }

    private func startFrames() {
        guard !retired, presented, schedule.drivesFrames else { return }
        driver.start(in: root)
    }

    /// One display frame for the live springs. Each tick publishes its value;
    /// a resolved spring settles on toValue, stops and runs its completion
    ///
    /// Returns whether a spring is still running.
    @discardableResult func advance(_ dt: Double) -> Bool {
        guard !retired, dt.isFinite, dt > 0 else { return !retired && (binRunning || downloads.contains { $0.offsetRunning }) }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        for download in downloads where download.offsetRunning {
            download.offset.tick(dt)
            if download.offset.hasResolved { download.offset.value = download.offset.toValue; download.offsetRunning = false }
            download.setIconOffsetX(download.offset.value.x)
        }
        var completion: (() -> Void)?
        if binRunning {
            bin.tick(dt)
            if bin.hasResolved { bin.value = bin.toValue; binRunning = false; completion = binCompletion; binCompletion = nil }
            binPositionX = bin.value.x; root.placeBin(x: binPositionX)
        }
        CATransaction.commit()
        completion?()
        return !retired && (binRunning || downloads.contains { $0.offsetRunning })
    }

    ///
    /// animating, which is the controller's whole life.
    func dismiss(force: Bool) {
        if !force && isAnimating { return }
        retire()
    }

    ///
    /// released by the window owner. Exactly once.
    private func complete() {
        isAnimating = false
        retire()
    }

    private func retire() {
        guard !retired else { return }
        retired = true
        driver.stop(); binRunning = false
        for download in downloads { download.offsetRunning = false }
        if let securityObserver { NotificationCenter.default.removeObserver(securityObserver) }
        securityObserver = nil
        window.orderOut(nil)
        let owner = onRetire; onRetire = nil
        owner?(self)
    }
}

///
///
/// and the forced dismissal when any window resigns key or main
///
@MainActor final class DownloadArrivalOwner {
    private(set) var controller: DownloadArrivalController?
    private var resign: AnyCancellable?
    private let schedule: DownloadArrivalSchedule

    init(schedule: DownloadArrivalSchedule? = nil) {
        self.schedule = schedule ?? .main
        resign = Publishers.CombineLatest(
            NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification).map { _ in () },
            NotificationCenter.default.publisher(for: NSWindow.didResignMainNotification).map { _ in () })
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.dismiss(force: true) } }
    }

    ///
    ///
    /// the window palette, or append to the existing controller.
    func arrive(at screenPoint: NSPoint, in parent: NSWindow, showsBin: @autoclosure () -> Bool,
                palette: @autoclosure () -> ThemeChromePalette) {
        if let controller { controller.animate(fromScreenPoint: screenPoint); return }
        controller = DownloadArrivalController(parent: parent, screenPoint: screenPoint, showsBin: showsBin(),
                                               palette: palette(), schedule: schedule) { [weak self] retired in
            if self?.controller === retired { self?.controller = nil }
        }
    }

    func dismiss(force: Bool) { controller?.dismiss(force: force) }

    ///
    /// requires the live original window; Parc also keeps the receipt's
    /// original identity, Profile and private context (an ownership rule).
    ///
    ///
    ///
    ///
    /// Parc popup window never shows the arrival.
    static func admits(valid: Bool, hasPage: Bool, popupWindow: Bool, privateWindow: Bool, privateContext: String?,
                       privateContextLive: Bool, profileKnown: Bool) -> Bool {
        guard valid, hasPage, !popupWindow, profileKnown, privateWindow == (privateContext != nil) else { return false }
        return !privateWindow || privateContextLive
    }
}
