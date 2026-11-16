import AppKit
import QuartzCore
import ObjectiveC

struct Tally {
    var counts: [ObjectIdentifier: (label: String, count: Int)] = [:]
    var byKey: [String: Int] = [:]
    @MainActor mutating func add(_ view: NSView, _ key: String? = nil) {
        counts[ObjectIdentifier(view), default: (Meter.label(view), 0)].count += 1
        if let key { byKey["\(key) \(Meter.label(view))", default: 0] += 1 }
    }
    var total: Int { counts.values.reduce(0) { $0 + $1.count } }
    var most: Int { counts.values.map(\.count).max() ?? 0 }
    var mostOutsideAppKit: Int { counts.values.filter { !$0.label.hasPrefix("_NS") }.map(\.count).max() ?? 0 }
    var byLabel: [String: Int] { counts.values.reduce(into: [:]) { $0[$1.label, default: 0] += $1.count } }
    static func + (a: Tally, b: Tally) -> Tally {
        var result = a
        for (id, entry) in b.counts { result.counts[id, default: (entry.label, 0)].count += entry.count }
        result.byKey.merge(b.byKey, uniquingKeysWith: +)
        return result
    }
}
@MainActor final class Meter {
    static var on = false
    static weak var root: NSView?
    static weak var exemptSurface: NSView?
    static var exemptFrames = Tally()
    static var layouts = Tally(), frames = Tally(), layerSets = Tally(), text = Tally(), draws = Tally(), animations = Tally()
    static var invalidations = Tally()
    static var redundantLayerSets = 0
    static var viewSeconds: CFTimeInterval = 0
    private static var depth = 0

    static func reset() {
        layouts = Tally(); frames = Tally(); layerSets = Tally(); text = Tally(); draws = Tally(); animations = Tally()
        invalidations = Tally(); redundantLayerSets = 0; viewSeconds = 0; exemptFrames = Tally()
    }
    static func isExempt(_ view: NSView) -> Bool {
        exemptSurface?.subviews.contains { $0 is NSVisualEffectView && !$0.isHidden && (view === $0 || view.isDescendant(of: $0)) } == true
    }
    static func timed(_ counted: Bool, _ body: () -> Void) {
        guard counted, depth == 0 else { depth += counted ? 1 : 0; body(); depth -= counted ? 1 : 0; return }
        depth = 1
        let began = CACurrentMediaTime()
        body()
        viewSeconds += CACurrentMediaTime() - began
        depth = 0
    }
    static func inScope(_ view: NSView) -> Bool {
        guard on, let root, view === root || view.isDescendant(of: root) else { return false }
        return !isExempt(view)
    }
    static func frameChanged(_ view: NSView) {
        if inScope(view) { frames.add(view) } else if on, isExempt(view) { exemptFrames.add(view) }
    }
    static func owner(_ layer: CALayer) -> NSView? {
        var current: CALayer? = layer
        while let layer = current {
            if let view = layer.delegate as? NSView { return view }
            current = layer.superlayer
        }
        return nil
    }
    static func label(_ view: NSView) -> String { view.identifier?.rawValue ?? String(describing: type(of: view)) }
    static func layer(_ layer: CALayer, _ key: String, changed: Bool) {
        guard on, let view = owner(layer), inScope(view) else { return }
        if changed { layerSets.add(view, key) } else { redundantLayerSets += 1 }
    }
}
extension NSView {
    @objc dynamic func pacing_layout() {
        MainActor.assumeIsolated {
            let counted = Meter.inScope(self)
            if counted { Meter.layouts.add(self) }
            Meter.timed(counted) { pacing_layout() }
        }
    }
    @objc dynamic func pacing_setFrameSize(_ size: NSSize) {
        MainActor.assumeIsolated {
            let counted = size != frame.size && Meter.inScope(self)
            if size != frame.size { Meter.frameChanged(self) }
            if counted, self is NSTextField { Meter.text.add(self) }
            Meter.timed(counted) { pacing_setFrameSize(size) }
        }
    }
    @objc dynamic func pacing_setNeedsDisplay(_ rect: NSRect) {
        MainActor.assumeIsolated { if !rect.isEmpty, Meter.inScope(self) { Meter.invalidations.add(self) } }
        pacing_setNeedsDisplay(rect)
    }
    @objc dynamic func pacing_setFrameOrigin(_ origin: NSPoint) {
        MainActor.assumeIsolated { if origin != frame.origin { Meter.frameChanged(self) } }
        pacing_setFrameOrigin(origin)
    }
}
extension NSCell {
    @objc dynamic func pacing_drawInterior(withFrame frame: NSRect, in view: NSView) {
        MainActor.assumeIsolated { if Meter.inScope(view) { Meter.text.add(view, "draw") } }
        pacing_drawInterior(withFrame: frame, in: view)
    }
}
extension CALayer {
    @objc dynamic func pacing_setPosition(_ value: CGPoint) {
        MainActor.assumeIsolated { Meter.layer(self, "position", changed: value != position) }; pacing_setPosition(value)
    }
    @objc dynamic func pacing_setBounds(_ value: CGRect) {
        MainActor.assumeIsolated { Meter.layer(self, "bounds", changed: value != bounds) }; pacing_setBounds(value)
    }
    @objc dynamic func pacing_setCornerRadius(_ value: CGFloat) {
        MainActor.assumeIsolated { Meter.layer(self, "cornerRadius", changed: value != cornerRadius) }; pacing_setCornerRadius(value)
    }
    @objc dynamic func pacing_setMasksToBounds(_ value: Bool) {
        MainActor.assumeIsolated { Meter.layer(self, "masksToBounds", changed: value != masksToBounds) }; pacing_setMasksToBounds(value)
    }
    @objc dynamic func pacing_setOpacity(_ value: Float) {
        MainActor.assumeIsolated { Meter.layer(self, "opacity", changed: value != opacity) }; pacing_setOpacity(value)
    }
    @objc dynamic func pacing_setShadowPath(_ value: CGPath?) {
        MainActor.assumeIsolated { Meter.layer(self, "shadowPath", changed: value != shadowPath) }; pacing_setShadowPath(value)
    }
    @objc dynamic func pacing_display() {
        MainActor.assumeIsolated {
            let view = Meter.on ? Meter.owner(self) : nil
            let counted = view.map(Meter.inScope) == true
            if counted, let view { Meter.draws.add(view) }
            Meter.timed(counted) { pacing_display() }
        }
    }
    @objc dynamic func pacing_add(_ animation: CAAnimation, forKey key: String?) {
        MainActor.assumeIsolated {
            if Meter.on, let view = Meter.owner(self), Meter.inScope(view) { Meter.animations.add(view, key ?? "?") }
        }
        pacing_add(animation, forKey: key)
    }
}
func exchange(_ type: AnyClass, _ original: Selector, _ replacement: Selector) {
    method_exchangeImplementations(class_getInstanceMethod(type, original)!, class_getInstanceMethod(type, replacement)!)
}
@MainActor func instrument() {
    exchange(NSView.self, #selector(NSView.layout), #selector(NSView.pacing_layout))
    exchange(NSView.self, #selector(NSView.setFrameSize(_:)), #selector(NSView.pacing_setFrameSize(_:)))
    exchange(NSView.self, #selector(NSView.setFrameOrigin(_:)), #selector(NSView.pacing_setFrameOrigin(_:)))
    exchange(NSView.self, #selector(NSView.setNeedsDisplay(_:)), #selector(NSView.pacing_setNeedsDisplay(_:)))
    exchange(NSCell.self, #selector(NSCell.drawInterior(withFrame:in:)), #selector(NSCell.pacing_drawInterior(withFrame:in:)))
    exchange(CALayer.self, #selector(setter: CALayer.position), #selector(CALayer.pacing_setPosition(_:)))
    exchange(CALayer.self, #selector(setter: CALayer.bounds), #selector(CALayer.pacing_setBounds(_:)))
    exchange(CALayer.self, #selector(setter: CALayer.cornerRadius), #selector(CALayer.pacing_setCornerRadius(_:)))
    exchange(CALayer.self, #selector(setter: CALayer.masksToBounds), #selector(CALayer.pacing_setMasksToBounds(_:)))
    exchange(CALayer.self, #selector(setter: CALayer.opacity), #selector(CALayer.pacing_setOpacity(_:)))
    exchange(CALayer.self, #selector(setter: CALayer.shadowPath), #selector(CALayer.pacing_setShadowPath(_:)))
    exchange(CALayer.self, #selector(CALayer.display), #selector(CALayer.pacing_display))
    exchange(CALayer.self, #selector(CALayer.add(_:forKey:)), #selector(CALayer.pacing_add(_:forKey:)))
}

@MainActor final class BusyClock {
    private(set) var seconds: CFTimeInterval = 0
    private var awake: CFTimeInterval?
    var on = false
    private var observer: CFRunLoopObserver?
    init() {
        observer = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.afterWaiting.rawValue | CFRunLoopActivity.beforeWaiting.rawValue,
                                                      true, 0) { [unowned self] _, activity in
            MainActor.assumeIsolated {
                let now = CACurrentMediaTime()
                if activity == .afterWaiting { self.awake = now }
                else if let start = self.awake { if self.on { self.seconds += now - start }; self.awake = nil }
            }
        }
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
    }
    func reset() { seconds = 0; awake = on ? CACurrentMediaTime() : nil }
}

struct Work: CustomStringConvertible {
    var layouts = Tally(), frames = Tally(), layerSets = Tally(), text = Tally(), draws = Tally(), animations = Tally()
    var invalidations = Tally(), redundantLayerSets = 0, exempt = Tally()
    var seconds: CFTimeInterval = 0, viewSeconds: CFTimeInterval = 0
    @MainActor static func take(_ clock: BusyClock?, seconds: CFTimeInterval? = nil) -> Work {
        defer { Meter.reset(); clock?.reset() }
        return Work(layouts: Meter.layouts, frames: Meter.frames, layerSets: Meter.layerSets, text: Meter.text, draws: Meter.draws,
                    animations: Meter.animations, invalidations: Meter.invalidations, redundantLayerSets: Meter.redundantLayerSets, exempt: Meter.exemptFrames,
                    seconds: seconds ?? clock?.seconds ?? 0,
                    viewSeconds: Meter.viewSeconds)
    }
    var isIdle: Bool { [layouts, frames, layerSets, text, draws, invalidations].allSatisfy { $0.total == 0 } }
    var description: String {
        func list(_ tally: Tally, keys: Bool = false) -> String {
            let counts = keys ? tally.byKey : tally.byLabel
            return tally.total == 0 ? "0" : "\(tally.total) (" + counts.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: ", ") + ")"
        }
        return "layouts \(list(layouts)); frames \(list(frames)); layer sets \(list(layerSets, keys: true)), \(redundantLayerSets) unchanged; "
            + "text \(list(text)); draws \(list(draws)), requested \(list(invalidations)); animations \(list(animations, keys: true)); "
            + "main \(String(format: "%.2f", seconds * 1000)) ms, \(String(format: "%.2f", viewSeconds * 1000)) ms of it view work"
    }
    static func + (a: Work, b: Work) -> Work {
        Work(layouts: a.layouts + b.layouts, frames: a.frames + b.frames, layerSets: a.layerSets + b.layerSets, text: a.text + b.text,
             draws: a.draws + b.draws, animations: a.animations + b.animations, invalidations: a.invalidations + b.invalidations,
             redundantLayerSets: a.redundantLayerSets + b.redundantLayerSets, exempt: a.exempt + b.exempt, seconds: a.seconds + b.seconds,
             viewSeconds: a.viewSeconds + b.viewSeconds)
    }
}

extension NSView {
    func identified(_ name: String) -> Self { identifier = .init(name); return self }
}
class LayoutHostView: NSView {
    var onLayout: (() -> Void)?
    override var isFlipped: Bool { true }
    override func layout() { super.layout(); onLayout?() }
}
final class DrawnStrip: LayoutHostView {
    override func draw(_ dirtyRect: NSRect) { NSColor.separatorColor.setFill(); dirtyRect.fill() }
}
final class PageView: NSView {
    let host = NSView()
    private(set) var boundsSent = 0
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true; host.wantsLayer = true; host.identifier = .init("page.renderWidget"); addSubview(host)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func resizeSubviews(withOldSize oldSize: NSSize) {}
    override func setFrameSize(_ newSize: NSSize) {
        let changed = newSize != frame.size
        super.setFrameSize(newSize)
        for subview in subviews { subview.frame = bounds }
        if changed { boundsSent += 1 }
    }
}
@MainActor final class Pane: LayoutHostView {
    let content = LayoutHostView(), page = PageView(frame: .zero)
    let developerToolbar = DrawnStrip(), browserToolbar = DrawnStrip(), failure = DrawnStrip()
    let toolbarField = NSTextField(string: "parc://start"), failureTitle = NSTextField(labelWithString: "This page couldn’t load")
    let header = NSButton(title: "", target: nil, action: nil), headerLabel = NSTextField(labelWithString: "A long page title for the slot")
    let grabber = NSView()
    init(visibleStrip: Bool) {
        super.init(frame: .zero)
        wantsLayer = true; layer?.backgroundColor = NSColor.white.cgColor
        for (view, name) in [(content, "pane.content"), (page, "page"), (developerToolbar, "developerToolbar"), (browserToolbar, "browserToolbar"),
                             (failure, "failure"), (toolbarField, "browserToolbar.field"), (failureTitle, "failure.title"),
                             (header, "header"), (headerLabel, "header.label"), (grabber, "grabber")] as [(NSView, String)] {
            view.identifier = .init(name)
        }
        addSubview(content); addSubview(grabber); addSubview(header); header.addSubview(headerLabel)
        addSubview(developerToolbar); addSubview(browserToolbar); browserToolbar.addSubview(toolbarField)
        content.addSubview(page); content.addSubview(failure); failure.addSubview(failureTitle)
        SidebarMotionController.pinDrawnContent(failure, to: .scaleAxesIndependently)
        SidebarMotionController.pinDrawnContent(failureTitle, to: .center)
        header.isBordered = false; header.isHidden = true
        developerToolbar.isHidden = !visibleStrip; browserToolbar.isHidden = true; failure.isHidden = true
        content.onLayout = { [unowned self] in
            for view in [page, failure] as [NSView] { view.frame = content.bounds }
            failureTitle.frame = NSRect(x: 0, y: content.bounds.midY, width: content.bounds.width, height: 24)
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func layout() {
        super.layout()
        let strip: CGFloat = developerToolbar.isHidden ? 0 : 40
        browserToolbar.frame = NSRect(x: 0, y: 0, width: bounds.width, height: 0)
        toolbarField.frame = NSRect(x: 60, y: 0, width: max(0, bounds.width - 120), height: 0)
        developerToolbar.frame = NSRect(x: 0, y: 0, width: bounds.width, height: strip)
        header.frame = NSRect(x: 13, y: 0, width: max(0, min(bounds.width - 80, 900)), height: 26)
        headerLabel.frame = header.bounds
        content.frame = NSRect(x: 0, y: strip, width: bounds.width, height: bounds.height - strip)
        grabber.frame = NSRect(x: 0, y: 0, width: bounds.width, height: 10)
    }
}

@MainActor final class EmptyContent: LayoutHostView {
    let highlight = CAShapeLayer()
    override var wantsUpdateLayer: Bool { true }
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true; highlight.fillColor = nil; highlight.opacity = 0; layer?.addSublayer(highlight)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func updateLayer() { layer?.backgroundColor = NSColor(white: 1, alpha: 0.1).cgColor }
    override func layout() {
        super.layout()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        highlight.frame = bounds; highlight.path = CGPath(rect: bounds, transform: nil)
        CATransaction.commit()
    }
}

@MainActor final class Window {
    enum Pass { case full, preparation, geometry }
    let window = NSWindow(contentRect: NSRect(x: -12000, y: -12000, width: 1470, height: 831),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
    let rootView = ThemeRendererView(), sidebarContainer = ThemeRendererView(), sidebar = LayoutHostView()
    let lights = WindowStandardButtons(), toggle = NSButton(title: "", target: nil, action: nil)
    let rows = (0..<12).map { index in NSTextField(labelWithString: "Sidebar row \(index)").identified("sidebar.row") }
    let pageHost = LayoutHostView(), splitView = LayoutHostView(), pane: Pane, empty = EmptyContent()
    let pageShadow = PageCardShadowView()
    let showsPage: Bool
    let loadingIndicator = PageLoadingIndicatorHost(), findHost = NSView()
    let motion = SidebarMotionController()
    let width: CGFloat = 228
    var presentation = SidebarPresentation.locked
    var pass = Pass.full
    var motionVisible = false, floatingSurface = false, revealsAnchored = false
    var settled = 0
    var didPrepare: (() -> Void)?, willSettle: (() -> Void)?

    var passesTwice = false

    init(showsPage: Bool = false, pinsSurface: Bool = true, visibleStrip: Bool = false) {
        pane = Pane(visibleStrip: visibleStrip)
        self.showsPage = showsPage
        for (view, name) in [(rootView, "root"), (sidebarContainer, "sidebarContainer"), (sidebar, "sidebar"), (pageHost, "pageHost"),
                             (splitView, "splitView"), (pane, "pane"), (empty, "emptyContent"), (pageShadow, "pageShadow"),
                             (loadingIndicator, "loadingIndicator"), (findHost, "findHost"),
                             (toggle, "toggle")] as [(NSView, String)] {
            view.identifier = .init(name)
        }
        window.titleVisibility = .hidden; window.titlebarAppearsTransparent = true; window.isReleasedWhenClosed = false
        _ = WindowStandardButtons.systemButtons(of: window).map { $0.isHidden = true }
        window.contentView = rootView
        rootView.wantsLayer = true
        rootView.addSubview(pageShadow); rootView.addSubview(pageHost); rootView.addSubview(loadingIndicator); rootView.addSubview(findHost)
        rootView.addSubview(sidebarContainer)
        sidebarContainer.coordinateSpace = rootView
        if let color = ThemeColor(red: 0.42, green: 0.36, blue: 0.86) { rootView.theme = .singleColor(color); sidebarContainer.theme = .singleColor(color) }
        sidebarContainer.addSubview(sidebar)
        if pinsSurface { SidebarMotionController.pinSurface(of: sidebarContainer, except: sidebar) }
        sidebar.addSubview(lights); sidebar.addSubview(toggle); rows.forEach(sidebar.addSubview)
        sidebar.onLayout = { [unowned self] in
            let bar = SidebarChromeLayout.toolbar(width: sidebar.bounds.width, windowButtons: WindowStandardButtons.stackSize, showsNavigation: true)
            lights.frame = bar.windowButtons ?? .zero; toggle.frame = bar.toggle ?? .zero
            for (index, row) in rows.enumerated() {
                row.frame = NSRect(x: 16, y: 90 + CGFloat(index) * 36, width: sidebar.bounds.width - 32, height: 20)
            }
        }
        pageHost.wantsLayer = true; pageHost.layer?.cornerRadius = PageCard.cornerRadius; pageHost.layer?.cornerCurve = .continuous
        pageHost.layer?.masksToBounds = true
        pageHost.layer?.backgroundColor = (showsPage ? NSColor.white : .clear).cgColor
        pageHost.addSubview(splitView)
        splitView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([splitView.leadingAnchor.constraint(equalTo: pageHost.leadingAnchor),
                                     splitView.trailingAnchor.constraint(equalTo: pageHost.trailingAnchor),
                                     splitView.topAnchor.constraint(equalTo: pageHost.topAnchor),
                                     splitView.bottomAnchor.constraint(equalTo: pageHost.bottomAnchor)])
        let content: NSView = showsPage ? pane : empty
        splitView.addSubview(content)
        splitView.onLayout = { [unowned self] in content.frame = splitView.bounds }
        findHost.isHidden = true
        rootView.onLayout = { [unowned self] in layoutChrome() }
        window.orderFront(nil)
        rootView.layoutSubtreeIfNeeded(); rootView.displayIfNeeded(); CATransaction.flush()
        Meter.root = rootView
    }

    var participants: [NSView] { [sidebarContainer, pageHost, pageShadow, findHost, loadingIndicator] }
    func frames() -> SidebarChromeFrames {
        let placement = SidebarPresentationFrame(presentation, inMotion: motionVisible, floatingSurface: floatingSurface, revealsAnchored: revealsAnchored)
        return SidebarChromeFrames(bounds: rootView.bounds, sidebarWidth: width, presentation: presentation, placement: placement)
    }
    func layoutChrome() {
        let frames = frames()
        if pass == .geometry {
            sidebarContainer.frame = frames.sidebar
            sidebar.frame = sidebarContainer.bounds
            if floatingSurface && presentation == .locked { sidebarContainer.docksFloatingSurface = true }
            pageHost.frame = frames.pageHost; pageShadow.place(around: frames.pageHost)
            loadingIndicator.frame = PageLoadingIndicatorHost.frame(pageHost: frames.pageHost)
            pageHost.needsLayout = true
            pageHost.layoutSubtreeIfNeeded()
            return
        }
        let surface = presentation == .floating || floatingSurface
        if sidebarContainer.drawsBackground != surface { sidebarContainer.drawsBackground = surface }
        sidebarContainer.frame = frames.sidebar
        sidebarContainer.floatingCornerRadius = surface ? FloatingSidebarSurface.cornerRadius : nil
        sidebarContainer.docksFloatingSurface = pass == .full && floatingSurface && presentation == .locked
        if pass == .full { sidebarContainer.preparesFloatingDock = false }
        sidebar.layer?.cornerRadius = surface ? FloatingSidebarSurface.cornerRadius : 0
        sidebar.clipsToBounds = surface
        if pass == .full { sidebarContainer.invalidateCoordinates() }
        sidebar.frame = sidebarContainer.bounds
        pageHost.frame = frames.pageHost; pageShadow.place(around: frames.pageHost)
        loadingIndicator.frame = PageLoadingIndicatorHost.frame(pageHost: frames.pageHost)
        guard pass == .full else { return }
        pageHost.layoutSubtreeIfNeeded()
    }
    func present(_ next: SidebarPresentation) {
        let transition = SidebarTransition(from: presentation, to: next)
        motionVisible = true
        floatingSurface = transition.keepsFloatingSurface
        revealsAnchored = transition.revealsAnchored
        pass = .preparation
        layoutChrome()
        sidebarContainer.preparesFloatingDock = transition.docksFloatingSurface
        didPrepare?()
        pass = .geometry
        motion.animate(layoutRoot: rootView, views: participants, style: transition.style, flushesPreviousLayout: transition.flushesPreparation) {
            presentation = next
            if passesTwice {
                let final = frames().pageHost
                pageHost.frame = final.insetBy(dx: 20, dy: 0); pageHost.layoutSubtreeIfNeeded()
            }
            layoutChrome()
        } completion: { [unowned self] in
            willSettle?()
            motionVisible = false; floatingSurface = false
            layoutChrome()
            settled += 1
        }
        pass = .full
        revealsAnchored = false
    }
    func settle() { motion.cancel(); motionVisible = false; floatingSurface = false; layoutChrome() }
    func commit() { rootView.displayIfNeeded(); CATransaction.flush() }
    func set(_ settledPresentation: SidebarPresentation) { motion.cancel(); presentation = settledPresentation; settle() }
    func close() { window.orderOut(nil); window.close() }
}

@MainActor final class Checks {
    var count = 0, failures: [String] = []
    func expect(_ value: Bool, _ description: String) {
        count += 1
        if !value { failures.append(description); print("FAIL: \(description)") }
    }
}

enum Curve {
    static func cubicPeak(distance: CGFloat) -> CGFloat {
        let (x1, y1, x2, y2) = (0.25, 0.46, 0.45, 0.94)
        func point(_ t: Double, _ a: Double, _ b: Double) -> Double { 3 * (1 - t) * (1 - t) * t * a + 3 * (1 - t) * t * t * b + t * t * t }
        var peak = 0.0, previous = (x: 0.0, y: 0.0)
        for step in 1...2000 {
            let t = Double(step) / 2000, current = (x: point(t, x1, x2), y: point(t, y1, y2))
            if current.x > previous.x { peak = max(peak, (current.y - previous.y) / (current.x - previous.x)) }
            previous = current
        }
        return CGFloat(peak) * distance / 0.08
    }
    static func springPeak(distance: CGFloat) -> CGFloat {
        let omega = 2 * Double.pi / 0.18, damping = 2 * 0.8 * omega
        var x = Double(distance), v = 0.0, peak = 0.0
        for _ in 0..<20000 { let a = -omega * omega * x - damping * v; v += a * 0.00005; x += v * 0.00005; peak = max(peak, abs(v)) }
        return CGFloat(peak)
    }
}

@MainActor final class Sampler {
    struct Sample { let time: CFTimeInterval; let sidebar: CGFloat; let page: CGFloat; let pageWidth: CGFloat }
    private(set) var samples: [Sample] = []
    private var timer: Timer?
    func start(_ window: Window) {
        samples = []
        let timer = Timer(timeInterval: 0.001, repeats: true) { [weak self, unowned window] _ in
            MainActor.assumeIsolated { self?.sample(window) }
        }
        RunLoop.main.add(timer, forMode: .common); self.timer = timer
    }
    func sample(_ window: Window) {
        let sidebar = window.sidebarContainer.layer?.presentation()?.frame ?? window.sidebarContainer.frame
        let page = window.pageHost.layer?.presentation()?.frame ?? window.pageHost.frame
        samples.append(Sample(time: CACurrentMediaTime(), sidebar: sidebar.minX, page: page.minX, pageWidth: page.width))
    }
    func stop() { timer?.invalidate(); timer = nil }
    var peakSpeed: CGFloat {
        var peak: CGFloat = 0, later = 0
        for (index, sample) in samples.enumerated() {
            later = max(later, index + 1)
            while later < samples.count, samples[later].time - sample.time < 0.002 { later += 1 }
            guard later < samples.count else { break }
            let next = samples[later], dt = CGFloat(next.time - sample.time)
            peak = max(peak, abs(next.sidebar - sample.sidebar) / dt, abs(next.page - sample.page) / dt, abs(next.pageWidth - sample.pageWidth) / dt)
        }
        return peak
    }
    func largestExcess(speed: CGFloat) -> CGFloat {
        zip(samples, samples.dropFirst()).reduce(0) { excess, pair in
            let allowance = speed * CGFloat(pair.1.time - pair.0.time)
            return max(excess, abs(pair.1.sidebar - pair.0.sidebar) - allowance, abs(pair.1.page - pair.0.page) - allowance,
                       abs(pair.1.pageWidth - pair.0.pageWidth) - allowance)
        }
    }
}

struct Result {
    let name: String
    let preparation: Work, group: Work, flight: Work, completion: Work
    let frames: Double
    func perFrame(_ seconds: CFTimeInterval) -> Double { frames > 0 ? seconds / frames : 0 }
}

@MainActor final class Harness {
    let checks = Checks()
    var snapJump: CGFloat = 0
    let clock = BusyClock()
    let refresh = Double(NSScreen.screens.map(\.maximumFramesPerSecond).max() ?? 60)

    func wait(_ seconds: TimeInterval) { RunLoop.main.run(until: Date(timeIntervalSinceNow: seconds)) }
    func baseline() -> Double {
        clock.on = true; clock.reset()
        let began = CACurrentMediaTime()
        until({ false }, limit: 0.1)
        clock.on = false
        return clock.seconds / ((CACurrentMediaTime() - began) * refresh)
    }
    func until(_ done: () -> Bool, limit: TimeInterval = 2) {
        let deadline = Date(timeIntervalSinceNow: limit)
        while !done(), Date() < deadline { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.005)) }
    }
    func settle(_ window: Window, at presentation: SidebarPresentation) {
        window.set(presentation); window.rootView.layoutSubtreeIfNeeded(); window.rootView.displayIfNeeded()
        CATransaction.flush(); wait(0.05)
    }

    func measure(_ name: String, _ window: Window, from start: SidebarPresentation, to next: SidebarPresentation,
                 reversing reversal: SidebarPresentation? = nil, reverseAfter: TimeInterval = 0.03) -> Result {
        settle(window, at: start)
        Meter.root = window.rootView
        let anchoredFloat = SidebarTransition(from: start, to: next).keepsFloatingSurface && (next == .locked || start == .locked)
        Meter.exemptSurface = anchoredFloat ? window.sidebarContainer : nil
        let target = window.settled + 1
        var flight = Work(), preparation = Work(), flightStart: CFTimeInterval = 0, duration: CFTimeInterval = 0, settling = false
        window.willSettle = { [unowned self] in
            duration = CACurrentMediaTime() - flightStart; clock.on = false
            flight = flight + Work.take(clock); settling = true
        }
        var began = CACurrentMediaTime()
        window.didPrepare = { preparation = Work.take(nil, seconds: CACurrentMediaTime() - began); began = CACurrentMediaTime() }
        Meter.on = true; Meter.reset()
        window.present(next); window.commit()
        var group = Work.take(nil, seconds: CACurrentMediaTime() - began)
        flightStart = CACurrentMediaTime(); clock.on = true; clock.reset()
        if let reversal {
            wait(reverseAfter)
            clock.on = false; flight = Work.take(clock)
            began = CACurrentMediaTime()
            window.present(reversal); window.commit()
            group = Work.take(nil, seconds: CACurrentMediaTime() - began)
            clock.on = true; clock.reset()
        }
        until { settling }
        let completion = Work.take(nil)
        Meter.on = false; Meter.exemptSurface = nil; window.willSettle = nil; window.didPrepare = nil
        until { window.settled >= target }
        CATransaction.flush()
        let total = CACurrentMediaTime() - flightStart
        return Result(name: name, preparation: preparation, group: group, flight: flight, completion: completion,
                      frames: (duration > 0 ? duration : total) * refresh)
    }

    func continuity(_ window: Window, from start: SidebarPresentation, to next: SidebarPresentation,
                    reversing reversal: SidebarPresentation? = nil, snap: Bool = false) -> (peak: CGFloat, allowed: CGFloat, excess: CGFloat) {
        settle(window, at: start)
        func tracks() -> [CGFloat] { let f = window.frames(); return [f.sidebar.minX, f.pageHost.minX, f.pageHost.width] }
        let before = tracks()
        let target = window.settled + 1
        window.present(next); window.commit()
        let sampler = Sampler(); sampler.start(window)
        var legs = [zip(before, tracks()).map { abs($1 - $0) }.max() ?? 0]
        var style = SidebarTransition(from: start, to: next).style
        if let reversal {
            wait(0.03)
            let mid = tracks()
            window.present(reversal); window.commit()
            legs.append(zip(mid, tracks()).map { abs($1 - $0) }.max() ?? 0)
            if SidebarTransition(from: next, to: reversal).style == .floating { style = .floating }
        }
        if snap {
            wait(0.01)
            let before = window.sidebarContainer.layer?.presentation()?.frame.minX ?? 0
            sampler.sample(window)
            window.settle(); window.commit()
            sampler.sample(window)
            snapJump = abs(window.sidebarContainer.frame.minX - before)
        }
        until { window.settled >= target || (snap && !window.motion.isAnimating) }
        wait(0.05); sampler.stop()
        let travel = legs.max() ?? 0
        let allowed = 1.3 * (style == .anchored ? Curve.cubicPeak(distance: travel) : Curve.springPeak(distance: travel))
        return (sampler.peakSpeed, allowed, sampler.largestExcess(speed: allowed))
    }
}

let snapTolerance: CGFloat = 20

let budget = "Parc's budget: no per-frame main-thread work in its views"

@MainActor func run() -> Int32 {
    _ = NSApplication.shared
    instrument()
    let harness = Harness(), c = harness.checks
    print("SidebarPacing: display \(Int(harness.refresh)) Hz; \(budget)")
    c.expect(FloatingSidebarSurface.shadowImage != nil, "the floating shadow measures with its real artwork (check.py copies it)")
    let empty = Window(), page = Window(showsPage: true)
    let idle = (0..<3).map { _ in harness.baseline() }.max() ?? 0
    print("idle main thread: \(String(format: "%.3f", idle * 1000)) ms/frame")
    let scenarios: [(String, Window, SidebarPresentation, SidebarPresentation, SidebarPresentation?)] = [
        ("content cost: ⌘S hide, empty content", empty, .locked, .hidden, nil),
        ("content cost: ⌘S reveal, empty content", empty, .hidden, .locked, nil),
        ("⌘S hide, web page", page, .locked, .hidden, nil),
        ("⌘S reveal, web page", page, .hidden, .locked, nil),
        ("⌘S with a pending pane floats", empty, .locked, .floating, nil),
        ("⌘S with a pending pane floats, reversed by ⌘S", empty, .locked, .floating, .locked),
        ("hover reveal, or a pending pane opening (floating)", empty, .hidden, .floating, nil),
        ("content cost: floating dismissal, empty content", empty, .floating, .hidden, nil),
        ("⌘S locks a floating sidebar", empty, .floating, .locked, nil),
        ("⌘S with a pending pane floats after a dock", empty, .locked, .floating, nil),
        ("⌘S hide reversed by ⌘S", page, .locked, .hidden, .locked),
        ("⌘S reveal reversed by ⌘S", page, .hidden, .locked, .hidden),
        ("content cost: hover reveal reversed by dismissal, empty content", empty, .hidden, .floating, .hidden)]
    for (name, window, from, to, reversal) in scenarios {
        let result = harness.measure(name, window, from: from, to: to, reversing: reversal)
        print("\n\(name): \(String(format: "%.1f", result.frames)) display frames in flight")
        print("  preparation: \(result.preparation)")
        print("  group:       \(result.group)")
        print("  per frame:   " + (result.flight.isIdle ? "idle" : "\(result.flight)")
              + String(format: " · view work %.3f ms/frame; run loop busy %.3f ms/frame (idle %.3f)",
                       result.perFrame(result.flight.viewSeconds) * 1000, result.perFrame(result.flight.seconds) * 1000, idle * 1000))
        if result.flight.exempt.total > 0 {
            print("  outside budget: the floating materials, resized \(result.flight.exempt.byLabel) on frames AppKit drove")
        }
        print("  completion:  \(result.completion)")
        c.expect(result.flight.isIdle, "\(name): per-frame layout, frame, layer, text, draw or redraw-request work in flight: \(result.flight)")
        c.expect(result.flight.viewSeconds == 0, "\(name): \(result.flight.viewSeconds * 1000) ms of view work in flight")
        for (pass, work) in [("preparation", result.preparation), ("group", result.group)] {
            c.expect(work.layouts.mostOutsideAppKit <= 1, "\(name): a view laid out twice in the \(pass): \(work.layouts.byLabel)")
            c.expect(work.text.most <= 1, "\(name): a label relaid out twice in the \(pass): \(work.text.byLabel)")
        }
        c.expect(result.flight.frames.byLabel["page.renderWidget"] == nil && (result.group.frames.byLabel["page.renderWidget"] ?? 0) <= 1,
                 "\(name): the page's renderer view resized more than once")
        let settled = window.frames()
        c.expect(window.sidebarContainer.frame == settled.sidebar && window.pageHost.frame == settled.pageHost
                 && window.pageShadow.frame == ContentShadowImage.frame(around: settled.pageHost)
                 && window.loadingIndicator.frame == PageLoadingIndicatorHost.frame(pageHost: settled.pageHost), "\(name): settled frames differ from SidebarChromeFrames")
        c.expect(window.participants.allSatisfy { view in ["position", "bounds"].allSatisfy { view.layer?.animation(forKey: $0) == nil } },
                 "\(name): a geometry animation outlived the transition")
        if from == .floating && to == .locked {
            c.expect(result.group.animations.byKey["opacity FloatingSidebarShadowView"] == 1
                     && (result.group.animations.byKey["bounds FloatingSidebarShadowView"] ?? 0) <= 1,
                     "\(name): the floating shadow does not fade once inside the group: \(result.group.animations.byKey)")
        }
        let (peak, allowed, excess) = harness.continuity(window, from: from, to: to, reversing: reversal)
        print("  continuity:  peak \(Int(peak)) pt/s against the recovered curve's \(Int(allowed));"
              + String(format: " largest step beyond it %.1f pt", excess))
        c.expect(excess <= snapTolerance, "\(name): presentation jumped \(excess) points beyond the recovered curve")
    }
    c.expect(page.pane.page.boundsSent > 0, "the page's renderer view heard its sizes")

    func dockState(_ window: Window) -> (alpha: CGFloat, hidden: Bool, radius: CGFloat) {
        let shadow = window.sidebarContainer.subviews.first { $0 is FloatingSidebarShadowView }
        return (shadow?.alphaValue ?? -1, shadow?.isHidden ?? true, window.sidebarContainer.layer?.cornerRadius ?? -1)
    }
    func materialState(_ window: Window) -> (blur: CGFloat, dock: CGFloat, dockHidden: Bool) {
        let materials = window.sidebarContainer.subviews.compactMap { $0 as? NSVisualEffectView }
        return (materials.first?.alphaValue ?? -1, materials.count == 2 ? materials[1].alphaValue : -1, materials.count == 2 ? materials[1].isHidden : false)
    }
    func fades(_ window: Window) -> [CFTimeInterval?] {
        window.sidebarContainer.subviews.filter { $0 is NSVisualEffectView || $0 is FloatingSidebarShadowView }
            .map { ($0.layer?.animation(forKey: "opacity") as? CABasicAnimation)?.duration }
    }
    harness.settle(empty, at: .floating)
    var target = empty.settled + 1
    empty.present(.locked); empty.commit()
    let dockFades = fades(empty)
    c.expect(dockFades.count == 3 && dockFades.allSatisfy { $0.map { abs($0 - 0.08) < 1e-6 } == true },
             "the dock fades its shadow, blur and the window's material once each on the group's 0.08 s timing: \(dockFades)")
    empty.layoutChrome()
    let midDock = dockState(empty), midMaterials = materialState(empty)
    c.expect(midDock.alpha == 0 && !midDock.hidden && midDock.radius == FloatingSidebarSurface.cornerRadius,
             "a full pass during the dock restored the shadow or corners: \(midDock)")
    c.expect(midMaterials.blur == 0 && midMaterials.dock == 1 && !midMaterials.dockHidden,
             "a full pass during the dock undid the material cross-fade: \(midMaterials)")
    harness.until { empty.settled >= target }
    let docked = dockState(empty), dockedMaterials = materialState(empty)
    c.expect(docked.hidden && docked.alpha == FloatingSidebarSurface.shadowAlpha && docked.radius == 0, "the settled dock: \(docked)")
    c.expect(dockedMaterials.blur == 1 && dockedMaterials.dock == 0 && dockedMaterials.dockHidden, "the settled dock's materials: \(dockedMaterials)")
    harness.settle(empty, at: .floating)
    let floated = dockState(empty), floatedMaterials = materialState(empty)
    c.expect(!floated.hidden && floated.alpha == FloatingSidebarSurface.shadowAlpha, "the next float lost its shadow: \(floated)")
    c.expect(floatedMaterials.blur == 1 && floatedMaterials.dockHidden, "the next float shows the dock material: \(floatedMaterials)")
    target = empty.settled + 1
    empty.present(.locked); empty.commit()
    empty.present(.floating); empty.commit()
    let reversed = dockState(empty), reversedMaterials = materialState(empty)
    c.expect(!reversed.hidden && reversed.alpha == FloatingSidebarSurface.shadowAlpha && reversed.radius == FloatingSidebarSurface.cornerRadius,
             "a dock reversed into floating lost its shadow: \(reversed)")
    c.expect(reversedMaterials.blur == 1 && reversedMaterials.dock == 0 && reversedMaterials.dockHidden && fades(empty).allSatisfy { $0 == nil },
             "a dock reversed into floating kept the dock material or a fade in flight: \(reversedMaterials), \(fades(empty))")
    harness.until { empty.settled >= target }
    harness.settle(empty, at: .locked)

    print("\nControls (each must violate the budget):")
    let unpinned = Window(pinsSurface: false)
    let surface = harness.measure("control: unpinned theme canvas", unpinned, from: .floating, to: .locked)
    print("  unpinned theme canvas, ⌘S locks a floating sidebar: \(surface.flight)")
    c.expect(!surface.flight.isIdle && (surface.flight.frames.byLabel["ThemeMetalCanvas"] ?? 0) > 1 && surface.flight.viewSeconds > 0,
             "control: an unpinned theme canvas is resized and rendered every frame of floating → locked")
    let owner = Window(showsPage: true, visibleStrip: true)
    let strip = harness.measure("control: visible owner-drawn strip", owner, from: .locked, to: .hidden)
    print("  visible drawing strip (an owner's unpinned view), ⌘S hide: \(strip.flight)")
    c.expect(!strip.flight.isIdle && (strip.flight.frames.byLabel["developerToolbar"] ?? 0) > 1
             && (strip.flight.invalidations.byLabel["developerToolbar"] ?? 0) > 1 && strip.flight.viewSeconds > 0,
             "control: a visible unpinned drawing view is redrawn every frame")
    var snapExcess: CGFloat = 0
    for _ in 0..<5 {
        snapExcess = harness.continuity(empty, from: .locked, to: .hidden, snap: true).excess
        if harness.snapJump > 40 { break }
    }
    print("  settling mid-flight (a \(Int(harness.snapJump))-point snap): \(String(format: "%.1f", snapExcess)) points beyond the curve")
    c.expect(harness.snapJump > 40 && snapExcess > snapTolerance, "control: a mid-flight settle is detected as a jump")
    let twice = Window(showsPage: true); twice.passesTwice = true
    let double = harness.measure("control: two geometry passes", twice, from: .locked, to: .hidden)
    print("  a second geometry pass, ⌘S hide: layouts \(double.group.layouts.byLabel.filter { !$0.key.hasPrefix("_NS") }.values.max() ?? 0)/view, "
          + "text \(double.group.text.most)/label, renderer sizes \(double.group.frames.byLabel["page.renderWidget"] ?? 0)")
    c.expect(double.group.layouts.mostOutsideAppKit > 1 && double.group.text.most > 1 && (double.group.frames.byLabel["page.renderWidget"] ?? 0) > 1,
             "control: a second pass lays views out twice, relays out labels and resizes the renderer twice")
    for window in [empty, page, unpinned, owner, twice] { window.close() }
    print("\nSidebarPacing: \(c.count) assertions, \(c.failures.count) failed")
    return c.failures.isEmpty ? 0 : 1
}
exit(MainActor.assumeIsolated { run() })
