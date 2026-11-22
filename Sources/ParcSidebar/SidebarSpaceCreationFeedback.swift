import AppKit
import QuartzCore

@MainActor
final class SidebarSpaceCreationFeedbackView: NSView {
    static let width: CGFloat = 85

    var presentation: CGFloat = 0 {
        didSet { if presentation != oldValue { spring.retarget(presentation, now: CACurrentMediaTime()); run() } }
    }
    var progress: CGFloat {
        get { ring.progress }
        set { ring.progress = newValue }
    }
    var isActivated: Bool {
        get { ring.isActivated }
        set { ring.isActivated = newValue }
    }

    private let glow = CAGradientLayer()
    private let ring = SidebarSpaceCreationRing(frame: NSRect(x: 0, y: 0, width: 30, height: 30))
    private var spring = SidebarSpring(response: 0.4, damping: 0.8)
    private var timer: Timer?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true
        glow.type = .radial
        glow.startPoint = CGPoint(x: 0.5, y: 0.5)
        glow.endPoint = CGPoint(x: 0, y: 1)
        glow.opacity = 0
        layer?.addSublayer(glow)
        ring.alphaValue = 0
        addSubview(ring)
        updateGlowColors()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func accessibilityChildren() -> [Any]? { [] }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateGlowColors()
    }

    private func updateGlowColors() {
        let key = NSColor(displayP3Red: 49 / 255, green: 57 / 255, blue: 251 / 255, alpha: 0.22)
        glow.colors = [key.cgColor, key.withAlphaComponent(0).cgColor]
    }

    override func layout() {
        super.layout()
        let p = min(1, max(0, spring.value(at: CACurrentMediaTime()))), w = bounds.width, h = bounds.height
        let ringStart = w + 5, ringEnd = w - 12 - 30
        ring.frame = NSRect(x: ringStart + p * (ringEnd - ringStart), y: (h - 30) / 2, width: 30, height: 30)
        CATransaction.begin(); CATransaction.setDisableActions(true)
        glow.frame = CGRect(x: (w - 10) * (1 - p), y: bounds.minY, width: 2 * w, height: h)
        CATransaction.commit()
    }

    private func apply(_ value: CGFloat) {
        let p = min(1, max(0, value))
        ring.alphaValue = min(1, p / 0.2)
        CATransaction.begin(); CATransaction.setDisableActions(true)
        glow.opacity = Float(min(1, 2 * p))
        CATransaction.commit()
        needsLayout = true
    }

    private func run() {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { spring.place(presentation) }
        tick()
        guard timer == nil, !spring.isSettled(at: CACurrentMediaTime()) else { return }
        let timer = Timer(timeInterval: 1.0 / 120, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated { if let self { self.tick() } else { timer.invalidate() } }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        let now = CACurrentMediaTime()
        if spring.isSettled(at: now) {
            spring.place(presentation)
            timer?.invalidate(); timer = nil
        }
        apply(spring.value(at: now))
    }
}

@MainActor
final class SidebarSpaceCreationRing: NSView {
    static let lineWidth: CGFloat = 2.5

    var progress: CGFloat = 0 {
        didSet {
            guard progress != oldValue else { return }
            CATransaction.begin(); CATransaction.setDisableActions(true)
            progressLayer.strokeEnd = progress
            CATransaction.commit()
        }
    }
    var isActivated = false {
        didSet { if isActivated != oldValue { activationChanged() } }
    }

    private let shadowLayer = CALayer()
    private let container = NSView()
    private let icon = NSImageView()
    private let progressLayer = CAShapeLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = false
        shadowLayer.shadowColor = NSColor.black.cgColor
        shadowLayer.shadowOpacity = 0.3
        shadowLayer.shadowRadius = 1.5
        shadowLayer.shadowOffset = CGSize(width: 0, height: -1)
        layer?.addSublayer(shadowLayer)
        container.wantsLayer = true
        container.layer?.masksToBounds = true
        addSubview(container)
        progressLayer.fillColor = CGColor.clear
        progressLayer.lineCap = .round
        progressLayer.strokeEnd = 0
        container.layer?.addSublayer(progressLayer)
        icon.image = NSImage(systemSymbolName: "plus", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 16, weight: .medium))
        icon.imageScaling = .scaleNone
        container.addSubview(icon)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var wantsUpdateLayer: Bool { true }

    override func layout() {
        super.layout()
        let radius = bounds.width / 2
        container.frame = bounds
        container.layer?.cornerRadius = radius
        container.layer?.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        container.layer?.position = CGPoint(x: bounds.midX, y: bounds.midY)
        icon.frame = container.bounds
        CATransaction.begin(); CATransaction.setDisableActions(true)
        shadowLayer.frame = bounds
        shadowLayer.shadowPath = CGPath(roundedRect: bounds, cornerWidth: radius, cornerHeight: radius, transform: nil)
        let inset = Self.lineWidth / 2
        progressLayer.frame = container.bounds.insetBy(dx: inset, dy: inset)
        progressLayer.path = Self.ringPath(in: progressLayer.bounds)
        CATransaction.commit()
    }

    private static func ringPath(in rect: CGRect) -> CGPath {
        let radius = rect.width / 2
        let path = CGMutablePath()
        path.addArc(center: CGPoint(x: rect.midX, y: rect.midY), radius: radius,
                    startAngle: -.pi / 2, endAngle: 3 * .pi / 2, clockwise: false)
        return path
    }

    override func updateLayer() {
        container.layer?.backgroundColor = Self.color(.background, appearance: effectiveAppearance).cgColor
        CATransaction.begin(); CATransaction.setDisableActions(true)
        progressLayer.strokeColor = Self.color(.progress, appearance: effectiveAppearance).cgColor
        progressLayer.lineWidth = lineWidth
        CATransaction.commit()
        icon.contentTintColor = Self.color(isActivated ? .activatedIcon : .icon, appearance: effectiveAppearance)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    private var lineWidth: CGFloat { isActivated ? bounds.width - Self.lineWidth : Self.lineWidth }

    private func activationChanged() {
        let tint = Self.color(isActivated ? .activatedIcon : .icon, appearance: effectiveAppearance)
        let width = lineWidth
        CATransaction.begin(); CATransaction.setAnimationDuration(0.05)
        progressLayer.lineWidth = width
        CATransaction.commit()
        icon.contentTintColor = tint
        guard isActivated, let layer = container.layer,
              !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        let bounce = CABasicAnimation(keyPath: "transform")
        bounce.timingFunction = CAMediaTimingFunction(name: .easeOut)
        bounce.duration = 0.07
        bounce.beginTime = CACurrentMediaTime() + 0.05
        bounce.autoreverses = true
        bounce.isRemovedOnCompletion = true
        bounce.toValue = CATransform3DMakeScale(1.15, 1.15, 1)
        layer.add(bounce, forKey: "bounceAnimation")
    }

    package enum Role { case background, progress, icon, activatedIcon }

    static func color(_ role: Role, appearance: NSAppearance) -> NSColor {
        let dark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let purple = NSColor(displayP3Red: 0.153, green: 0.008, blue: 0.761, alpha: 1)
        switch role {
        case .background, .activatedIcon: return dark ? .black : .white
        case .progress, .icon: return dark ? .white : purple
        }
    }
}
