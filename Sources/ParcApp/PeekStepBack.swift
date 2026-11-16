import AppKit
import QuartzCore

@MainActor
final class PeekStepBack {
    nonisolated static let key = "parc.peek.stepBack"
    nonisolated static let openDuration: CFTimeInterval = 0.3
    private let views: [NSView]
    private(set) var progress: CGFloat = 0
    private(set) var scale: CGFloat = 1
    private var applied: [ObjectIdentifier: CATransform3D] = [:]
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
        applied.removeAll()
    }

    func refresh() {
        guard progress > 0 else { return }
        let remaining = openingEnds - CACurrentMediaTime()
        for view in views where applied[ObjectIdentifier(view)].map({ !CATransform3DEqualToTransform($0, transform(for: view)) }) ?? true {
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

    private static func transform(for layer: CALayer, scale: CGFloat) -> CATransform3D {
        PeekWindowLayout.stepTransform(bounds: layer.bounds, anchor: layer.anchorPoint, scale: scale)
    }

    private func animate(_ view: NSView, from: CATransform3D, duration: CFTimeInterval) {
        guard let layer = view.layer else { return }
        let to = transform(for: view)
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

    private func hold(_ view: NSView, _ transform: CATransform3D) {
        guard let layer = view.layer else { return }
        let id = ObjectIdentifier(view)
        if CATransform3DIsIdentity(transform) {
            layer.removeAnimation(forKey: Self.key); applied[id] = nil; return
        }
        if let current = applied[id], CATransform3DEqualToTransform(current, transform),
           layer.animation(forKey: Self.key) != nil { return }
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
