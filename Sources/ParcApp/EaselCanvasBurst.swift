import AppKit
import QuartzCore

@MainActor
final class EaselCanvasBurst: NSView {
    enum Style: Equatable {
        case ripple
        case confetti
        case puff
        case glow
    }

    private let stage = CALayer()
    private var pool: [CALayer] = []
    private var shapes: [CAShapeLayer] = []
    private var running: [CALayer] = []
    private var batches: [Int: [CALayer]] = [:]
    private var nextBatch = 0
    var onIdle: (() -> Void)?

    var isPlaying: Bool { !running.isEmpty }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = false
        stage.masksToBounds = false
        layer?.addSublayer(stage)
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func accessibilityChildren() -> [Any]? { [] }

    override func layout() {
        super.layout()
        alignStage()
    }

    private func alignStage() {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        stage.frame = bounds
        stage.isGeometryFlipped = !(layer?.contentsAreFlipped() ?? true)
        CATransaction.commit()
    }

    private func dot() -> CALayer {
        let made = pool.popLast() ?? CALayer()
        made.removeAllAnimations()
        made.shadowOpacity = 0
        made.borderWidth = 0
        made.transform = CATransform3DIdentity
        made.opacity = 0
        stage.addSublayer(made)
        running.append(made)
        return made
    }

    private func outline() -> CAShapeLayer {
        let made = shapes.popLast() ?? CAShapeLayer()
        made.removeAllAnimations()
        made.transform = CATransform3DIdentity
        made.opacity = 0
        made.fillColor = nil
        made.shadowOpacity = 0
        made.lineDashPattern = nil
        made.strokeStart = 0
        made.strokeEnd = 1
        stage.addSublayer(made)
        running.append(made)
        return made
    }

    private func finish(batch: Int) {
        guard let layers = batches.removeValue(forKey: batch) else { return }
        let done = Set(layers.map(ObjectIdentifier.init))
        running.removeAll { done.contains(ObjectIdentifier($0)) }
        for layer in layers { recycle(layer) }
        if running.isEmpty { onIdle?() }
    }

    private func recycle(_ layer: CALayer) {
        layer.removeAllAnimations()
        layer.removeFromSuperlayer()
        if let shape = layer as? CAShapeLayer {
            if shapes.count < 16 { shapes.append(shape) }
        } else if pool.count < 48 {
            pool.append(layer)
        }
    }

    func settle() {
        batches.removeAll()
        let layers = running
        running.removeAll()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        for layer in layers { recycle(layer) }
        CATransaction.commit()
    }

    private var lead: TimeInterval = 0

    private func animation(_ keyPath: String, values: [Any], times: [NSNumber]? = nil, duration: TimeInterval,
                           delay: TimeInterval = 0, curve: CAMediaTimingFunction = NoteCurve.easeOut) -> CAKeyframeAnimation {
        let animation = CAKeyframeAnimation(keyPath: keyPath)
        animation.values = values
        animation.keyTimes = times
        animation.duration = duration
        let wait = lead + delay
        animation.beginTime = wait > 0 ? stage.convertTime(CACurrentMediaTime(), from: nil) + wait : 0
        animation.fillMode = .forwards
        animation.isRemovedOnCompletion = false
        animation.timingFunction = curve
        return animation
    }

    func play(_ style: Style, around rect: NSRect, tint: NSColor, scale: CGFloat, reduced: Bool, seed: UInt64, delay: TimeInterval = 0) {
        guard rect.width.isFinite, rect.height.isFinite, !rect.isNull, !(reduced && style != .glow) else { return }
        alignStage()
        lead = max(0, delay)
        defer { lead = 0 }
        let zoom = max(scale, 0.2)
        let colour = tint.usingColorSpace(.sRGB) ?? tint
        var layers: [CALayer] = []
        var longest: TimeInterval = 0
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        switch style {
        case .ripple:
            let ring = outline()
            let side = max(rect.width, rect.height)
            ring.bounds = CGRect(x: 0, y: 0, width: side, height: side)
            ring.position = centre
            ring.path = CGPath(ellipseIn: ring.bounds, transform: nil)
            ring.strokeColor = colour.withAlphaComponent(0.55).cgColor
            ring.lineWidth = 2.5 / zoom
            let duration = EaselBurstPlan.rippleDuration
            ring.add(animation("transform.scale", values: [EaselBurstPlan.rippleFrom, EaselBurstPlan.rippleTo], duration: duration), forKey: "scale")
            ring.add(animation("opacity", values: [0, 1, 0], times: [0, 0.18, 1], duration: duration, curve: NoteCurve.easeInOut), forKey: "opacity")
            ring.add(animation("lineWidth", values: [3.5 / zoom, 0.8 / zoom], duration: duration), forKey: "width")
            layers.append(ring)
            longest = duration
        case .confetti:
            let specks = EaselBurstPlan.confetti(width: Double(rect.width), height: Double(rect.height), seed: seed)
            let duration = EaselBurstPlan.confettiDuration
            for speck in specks {
                let piece = dot()
                let side = CGFloat(speck.size) / zoom
                let wide = speck.hue > 0.5
                piece.bounds = CGRect(x: 0, y: 0, width: wide ? side * 1.6 : side, height: side)
                piece.cornerRadius = wide ? side * 0.3 : side / 2
                let shade = speck.hue < 0.33 ? colour : colour.blended(withFraction: CGFloat(speck.hue - 0.33) * 0.6,
                                                                       of: speck.hue > 0.66 ? .white : NoteTheme.accent) ?? colour
                piece.backgroundColor = shade.cgColor
                piece.position = centre
                let far = CGPoint(x: centre.x + CGFloat(cos(speck.angle) * speck.distance),
                                  y: centre.y + CGFloat(sin(speck.angle) * speck.distance))
                let landing = CGPoint(x: far.x, y: far.y + 6 / zoom)
                piece.add(animation("position", values: [NSValue(point: centre), NSValue(point: far), NSValue(point: landing)],
                                         times: [0, 0.7, 1], duration: duration, delay: speck.delay), forKey: "position")
                piece.add(animation("opacity", values: [1, 1, 0], times: [0, 0.55, 1], duration: duration, delay: speck.delay), forKey: "opacity")
                piece.add(animation("transform.rotation.z", values: [0, speck.spin * Double.pi / 180], duration: duration, delay: speck.delay), forKey: "spin")
                piece.add(animation("transform.scale", values: [0.4, 1.1, 0.7], times: [0, 0.3, 1], duration: duration, delay: speck.delay), forKey: "scale")
                layers.append(piece)
                longest = max(longest, duration + speck.delay)
            }
        case .puff:
            let specks = EaselBurstPlan.puff(width: Double(rect.width), height: Double(rect.height), seed: seed)
            let duration = EaselBurstPlan.puffDuration
            let soft = NoteTheme.isDark(effectiveAppearance) ? NSColor.white : NSColor.black
            let ink = colour.blended(withFraction: 0.55, of: soft) ?? soft
            for speck in specks {
                let cloud = dot()
                let side = CGFloat(speck.size) / zoom
                cloud.bounds = CGRect(x: 0, y: 0, width: side, height: side)
                cloud.cornerRadius = side / 2
                cloud.backgroundColor = ink.withAlphaComponent(0.22).cgColor
                let reach = CGFloat(Double(max(rect.width, rect.height)) * 0.32)
                let from = CGPoint(x: centre.x + CGFloat(cos(speck.angle)) * reach, y: centre.y + CGFloat(sin(speck.angle)) * reach)
                let to = CGPoint(x: from.x + CGFloat(cos(speck.angle) * speck.distance), y: from.y + CGFloat(sin(speck.angle) * speck.distance) - 4 / zoom)
                cloud.position = from
                cloud.add(animation("position", values: [NSValue(point: from), NSValue(point: to)], duration: duration, delay: speck.delay), forKey: "position")
                cloud.add(animation("opacity", values: [0, 1, 0], times: [0, 0.2, 1], duration: duration, delay: speck.delay), forKey: "opacity")
                cloud.add(animation("transform.scale", values: [0.5, 1.4], duration: duration, delay: speck.delay), forKey: "scale")
                layers.append(cloud)
                longest = max(longest, duration + speck.delay)
            }
        case .glow:
            let halo = outline()
            let pad = 4 / zoom, radius = 8 / zoom
            let box = CGRect(x: 0, y: 0, width: rect.width + pad * 2, height: rect.height + pad * 2)
            halo.bounds = box
            halo.position = centre
            halo.path = CGPath(roundedRect: box, cornerWidth: radius, cornerHeight: radius, transform: nil)
            halo.strokeColor = colour.withAlphaComponent(0.85).cgColor
            halo.lineWidth = 2 / zoom
            halo.shadowColor = colour.cgColor
            halo.shadowRadius = 8 / zoom
            halo.shadowOffset = .zero
            halo.shadowOpacity = 0.9
            let duration = EaselBurstPlan.glowDuration
            halo.add(animation("opacity", values: [0, 1, 0], times: [0, 0.25, 1], duration: reduced ? EaselObjectTransition.reducedFade * 2 : duration,
                                    curve: NoteCurve.easeInOut), forKey: "opacity")
            if !reduced {
                halo.add(animation("transform.scale", values: [0.97, 1.02, 1.04], times: [0, 0.3, 1], duration: duration), forKey: "scale")
            }
            layers.append(halo)
            longest = reduced ? EaselObjectTransition.reducedFade * 2 : duration
        }
        CATransaction.commit()
        schedule(layers, after: longest + lead)
    }

    func sweep(_ rects: [NSRect], tint: NSColor, scale: CGFloat, reduced: Bool) {
        alignStage()
        let zoom = max(scale, 0.2)
        let colour = tint.usingColorSpace(.sRGB) ?? tint
        var layers: [CALayer] = []
        let duration = reduced ? EaselObjectTransition.reducedFade * 2 : EaselBurstPlan.sweepDuration
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for rect in rects.prefix(EaselBurstPlan.perCommand) where rect.width.isFinite && rect.height.isFinite {
            let pad = 3 / zoom, radius = 6 / zoom
            let box = rect.insetBy(dx: -pad, dy: -pad)
            let path = CGPath(roundedRect: box, cornerWidth: radius, cornerHeight: radius, transform: nil)
            let wash = outline()
            wash.frame = stage.bounds
            wash.path = path
            wash.strokeColor = colour.withAlphaComponent(0.35).cgColor
            wash.lineWidth = 5 / zoom
            wash.add(animation("opacity", values: [0, 1, 0], times: [0, 0.3, 1], duration: duration, curve: NoteCurve.easeInOut), forKey: "opacity")
            layers.append(wash)
            guard !reduced else { continue }
            let streak = outline()
            streak.frame = stage.bounds
            streak.path = path
            streak.strokeColor = NSColor.white.blended(withFraction: 0.35, of: colour)?.cgColor ?? colour.cgColor
            streak.lineWidth = 2.5 / zoom
            streak.lineCap = .round
            streak.shadowColor = colour.cgColor
            streak.shadowRadius = 5 / zoom
            streak.shadowOffset = .zero
            streak.shadowOpacity = 1
            streak.add(animation("strokeEnd", values: [0, 1], duration: duration * 0.8, curve: NoteCurve.easeInOut), forKey: "end")
            streak.add(animation("strokeStart", values: [0, 0, 1], times: [0, 0.25, 1], duration: duration, curve: NoteCurve.easeInOut), forKey: "start")
            streak.add(animation("opacity", values: [1, 1, 0], times: [0, 0.8, 1], duration: duration), forKey: "opacity")
            layers.append(streak)
        }
        CATransaction.commit()
        schedule(layers, after: duration)
    }

    private func schedule(_ layers: [CALayer], after duration: TimeInterval) {
        guard !layers.isEmpty else { if running.isEmpty { onIdle?() }; return }
        nextBatch &+= 1
        let batch = nextBatch
        batches[batch] = layers
        DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.02) { [weak self] in
            MainActor.assumeIsolated { self?.finish(batch: batch) }
        }
    }
}
