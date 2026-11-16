import AppKit
import QuartzCore

@MainActor
final class PeekStepBack {
    nonisolated static let key = "parc.peek.stepBack"
    nonisolated static let openDuration: CFTimeInterval = 0.3
    nonisolated static let slideKey = "bounds"
    nonisolated static let samplesPerSecond: Double = 120
    private let views: [NSView]
    private(set) var progress: CGFloat = 0
    private(set) var scale: CGFloat = 1
    private var applied: [ObjectIdentifier: CATransform3D] = [:]
    private var slides: [ObjectIdentifier: (target: CGRect, start: CGRect, began: CFTimeInterval)] = [:]
    private var openingEnds: CFTimeInterval = 0

    init(_ views: [NSView]) { self.views = views }

    func set(_ progress: CGFloat, scale: CGFloat) {
        self.progress = min(1, max(0, progress)); self.scale = scale
        let remaining = openingEnds - CACurrentMediaTime()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        for view in views {
            if remaining > 0, let shown = view.layer?.presentation()?.transform {
                animate(view, from: shown, duration: remaining)
            } else { hold(view, transform(for: view)) }
        }
        CATransaction.commit()
    }

    func animateIn(scale: CGFloat, duration: CFTimeInterval = PeekStepBack.openDuration) {
        let start = progress
        progress = 1; self.scale = scale
        guard duration > 0 else { set(1, scale: scale); return }
        openingEnds = CACurrentMediaTime() + duration
        CATransaction.begin(); CATransaction.setDisableActions(true)
        for view in views {
            guard let layer = view.layer else { continue }
            let from = layer.animation(forKey: Self.key) == nil ? Self.transform(for: layer, scale: 1 - start * (1 - scale))
                : layer.presentation()?.transform ?? CATransform3DIdentity
            animate(view, from: from, duration: duration)
        }
        CATransaction.commit()
    }

    func reset() {
        guard progress > 0 || !applied.isEmpty else { return }
        progress = 0; openingEnds = 0
        for view in views { view.layer?.removeAnimation(forKey: Self.key) }
        applied.removeAll(); slides.removeAll()
    }

    func refresh() {
        guard progress > 0 else { return }
        let remaining = openingEnds - CACurrentMediaTime()
        for view in views where applied[ObjectIdentifier(view)].map({ !CATransform3DEqualToTransform($0, transform(for: view)) }) ?? true
            || (remaining <= 0 && !followsSlide(of: view)) {
            CATransaction.begin(); CATransaction.setDisableActions(true)
            if remaining > 0, let shown = view.layer?.presentation()?.transform {
                animate(view, from: shown, duration: remaining)
            } else { hold(view, transform(for: view)) }
            CATransaction.commit()
        }
    }

    private func transform(for view: NSView) -> CATransform3D {
        guard let layer = view.layer else { return CATransform3DIdentity }
        return Self.transform(for: layer, scale: 1 - progress * (1 - scale))
    }

    private static func transform(for layer: CALayer, scale: CGFloat, bounds: CGRect? = nil) -> CATransform3D {
        PeekWindowLayout.stepTransform(bounds: bounds ?? layer.bounds, anchor: layer.anchorPoint, scale: scale)
    }

    private func slidePath(_ slide: CABasicAnimation, on layer: CALayer, id: ObjectIdentifier) -> (start: CGRect, began: CFTimeInterval)? {
        let known = slides[id].flatMap { $0.target == layer.bounds ? $0 : nil }
        guard let start = known?.start ?? Self.start(of: slide, model: layer.bounds) ?? layer.presentation()?.bounds,
              start.size != layer.bounds.size else { return nil }
        return (start, slide.beginTime > 0 ? slide.beginTime : known?.began ?? layer.convertTime(CACurrentMediaTime(), from: nil))
    }

    private func follow(_ slide: CABasicAnimation, on layer: CALayer, id: ObjectIdentifier, to transform: CATransform3D) -> Bool {
        guard let path = slidePath(slide, on: layer, id: id), let follow = slide.copy() as? CABasicAnimation else { return false }
        let start = path.start, began = path.began
        follow.beginTime = began
        follow.keyPath = "transform"
        follow.fromValue = NSValue(caTransform3D: Self.transform(for: layer, scale: 1 - progress * (1 - scale), bounds: start))
        follow.toValue = NSValue(caTransform3D: transform)
        follow.byValue = nil
        follow.delegate = nil
        follow.isAdditive = true
        follow.isRemovedOnCompletion = false
        follow.fillMode = .both
        layer.add(follow, forKey: Self.key)
        slides[id] = (layer.bounds, start, began)
        return true
    }

    private func followsSlide(of view: NSView) -> Bool {
        guard let layer = view.layer else { return true }
        let id = ObjectIdentifier(view)
        guard layer.animation(forKey: Self.slideKey) is CABasicAnimation else { return slides[id] == nil }
        return slides[id]?.target == layer.bounds
    }

    private static func start(of slide: CABasicAnimation, model: CGRect) -> CGRect? {
        guard let from = (slide.fromValue as? NSValue)?.rectValue else { return nil }
        guard slide.isAdditive else { return from }
        return CGRect(x: model.origin.x + from.origin.x, y: model.origin.y + from.origin.y,
                      width: model.size.width + from.size.width, height: model.size.height + from.size.height)
    }

    private func animate(_ view: NSView, from: CATransform3D, duration: CFTimeInterval) {
        guard let layer = view.layer else { return }
        let to = transform(for: view)
        if let slide = layer.animation(forKey: Self.slideKey) as? CABasicAnimation,
           let path = slidePath(slide, on: layer, id: ObjectIdentifier(view)) {
            open(view, from: from, to: to, duration: duration, riding: slide, start: path.start, began: path.began)
            return
        }
        let animation = CABasicAnimation(keyPath: "transform")
        animation.fromValue = NSValue(caTransform3D: from); animation.toValue = NSValue(caTransform3D: to)
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        animation.isAdditive = true
        animation.isRemovedOnCompletion = false
        animation.fillMode = .both
        layer.add(animation, forKey: Self.key)
        applied[ObjectIdentifier(view)] = to
    }

    private func open(_ view: NSView, from: CATransform3D, to: CATransform3D, duration: CFTimeInterval,
                      riding slide: CABasicAnimation, start: CGRect, began: CFTimeInterval) {
        guard let layer = view.layer else { return }
        let now = layer.convertTime(CACurrentMediaTime(), from: nil)
        let span = max(duration, began + slide.duration - now)
        let count = max(2, Int((span * Self.samplesPerSecond).rounded(.up)) + 1)
        let opening = CAMediaTimingFunction(name: .easeOut)
        let end = layer.bounds
        let values = (0..<count).map { index -> NSValue in
            guard index < count - 1 else { return NSValue(caTransform3D: to) }
            let time = now + span * Double(index) / Double(count - 1)
            let eased = CGFloat(Self.timingFraction(opening, (time - now) / duration))
            let slid = Self.slideFraction(slide, at: time - began)
            let bounds = CGRect(x: 0, y: 0, width: start.width + (end.width - start.width) * slid,
                                height: start.height + (end.height - start.height) * slid)
            return NSValue(caTransform3D: PeekWindowLayout.stepTransform(bounds: bounds, anchor: layer.anchorPoint,
                                                                         scale: from.m11 + (to.m11 - from.m11) * eased))
        }
        let animation = CAKeyframeAnimation(keyPath: "transform")
        animation.values = values
        animation.keyTimes = (0..<count).map { NSNumber(value: Double($0) / Double(count - 1)) }
        animation.calculationMode = .linear
        animation.beginTime = now
        animation.duration = span
        animation.isAdditive = true
        animation.isRemovedOnCompletion = false
        animation.fillMode = .both
        layer.add(animation, forKey: Self.key)
        let id = ObjectIdentifier(view)
        slides[id] = (end, start, began)
        applied[id] = to
    }

    private static func slideFraction(_ slide: CABasicAnimation, at elapsed: CFTimeInterval) -> CGFloat {
        guard elapsed > 0 else { return 0 }
        guard elapsed < slide.duration else { return 1 }
        guard let spring = slide as? CASpringAnimation else { return CGFloat(timingFraction(slide.timingFunction, elapsed / slide.duration)) }
        let mass = Double(spring.mass), stiffness = Double(spring.stiffness), velocity = Double(spring.initialVelocity)
        let natural = (stiffness / mass).squareRoot()
        var overdamps = false
        if #available(macOS 14, *) { overdamps = spring.allowsOverdamping }
        let damping = Double(spring.damping) / (2 * (stiffness * mass).squareRoot())
        let ratio = overdamps ? damping : min(damping, 1)
        let left: Double
        if ratio < 1 {
            let damped = natural * (1 - ratio * ratio).squareRoot()
            left = exp(-ratio * natural * elapsed) * (cos(damped * elapsed) + (ratio * natural - velocity) / damped * sin(damped * elapsed))
        } else if ratio == 1 {
            left = exp(-natural * elapsed) * (1 + (natural - velocity) * elapsed)
        } else {
            let root = (ratio * ratio - 1).squareRoot(), fast = -natural * (ratio + root), slow = -natural * (ratio - root)
            let share = (-velocity - fast) / (slow - fast)
            left = share * exp(slow * elapsed) + (1 - share) * exp(fast * elapsed)
        }
        return CGFloat(1 - left)
    }

    private static func timingFraction(_ function: CAMediaTimingFunction?, _ fraction: Double) -> Double {
        let x = min(1, max(0, fraction))
        guard let function, x > 0, x < 1 else { return x }
        var first = [Float](repeating: 0, count: 2), second = [Float](repeating: 0, count: 2)
        function.getControlPoint(at: 1, values: &first)
        function.getControlPoint(at: 2, values: &second)
        func curve(_ t: Double, _ a: Float, _ b: Float) -> Double {
            3 * (1 - t) * (1 - t) * t * Double(a) + 3 * (1 - t) * t * t * Double(b) + t * t * t
        }
        var low = 0.0, high = 1.0
        for _ in 0..<32 {
            let middle = (low + high) / 2
            if curve(middle, first[0], second[0]) < x { low = middle } else { high = middle }
        }
        return curve((low + high) / 2, first[1], second[1])
    }

    private func hold(_ view: NSView, _ transform: CATransform3D) {
        guard let layer = view.layer else { return }
        let id = ObjectIdentifier(view)
        if CATransform3DIsIdentity(transform) {
            layer.removeAnimation(forKey: Self.key); applied[id] = nil; slides[id] = nil; return
        }
        let slide = layer.animation(forKey: Self.slideKey) as? CABasicAnimation
        if let current = applied[id], CATransform3DEqualToTransform(current, transform),
           layer.animation(forKey: Self.key) != nil, followsSlide(of: view) { return }
        if let slide, follow(slide, on: layer, id: id, to: transform) { applied[id] = transform; return }
        slides[id] = nil
        let animation = CABasicAnimation(keyPath: "transform")
        animation.fromValue = NSValue(caTransform3D: transform); animation.toValue = NSValue(caTransform3D: transform)
        animation.duration = 1
        animation.isAdditive = true
        animation.isRemovedOnCompletion = false
        animation.fillMode = .both
        layer.add(animation, forKey: Self.key)
        applied[id] = transform
    }
}
