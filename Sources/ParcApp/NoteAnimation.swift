import AppKit

struct NoteSpring: Hashable {
    let response: CGFloat
    let damping: CGFloat

    static let highlight = NoteSpring(response: 0.15, damping: 0.825)
    static let reorder = NoteSpring(response: 0.15, damping: 0.95)
    static let settle = NoteSpring(response: 0.34, damping: 0.86)
    static let press = NoteSpring(response: 0.3, damping: 0.6)
    static let pop = NoteSpring(response: 0.4, damping: 0.7)
    static let toggle = NoteSpring(response: 0.2, damping: 0.5)
    static let panel = NoteSpring(response: 0.18, damping: 0.8)
}

@MainActor
enum NoteAnimation {
    static var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    static func spring(_ keyPath: String, _ spring: NoteSpring, from: Any?, to: Any?) -> CASpringAnimation {
        let omega = 2 * Double.pi / Double(spring.response)
        let animation = CASpringAnimation(keyPath: keyPath)
        animation.mass = 1
        animation.stiffness = omega * omega
        animation.damping = 2 * Double(spring.damping) * omega
        animation.fromValue = from
        animation.toValue = to
        animation.duration = animation.settlingDuration
        return animation
    }

    static func animate(_ layer: CALayer, _ keyPath: String, to value: Any, spring: NoteSpring, key: String? = nil) {
        let current = layer.presentation()?.value(forKeyPath: keyPath) ?? layer.value(forKeyPath: keyPath)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.setValue(value, forKeyPath: keyPath)
        CATransaction.commit()
        guard !reduceMotion else { layer.removeAnimation(forKey: key ?? keyPath); return }
        layer.add(self.spring(keyPath, spring, from: current, to: value), forKey: key ?? keyPath)
    }

    static func fade(_ view: NSView, visible: Bool, duration: CFTimeInterval = 0.12, completion: (() -> Void)? = nil) {
        guard let layer = view.layer else { view.alphaValue = visible ? 1 : 0; completion?(); return }
        let from = layer.presentation()?.opacity ?? layer.opacity
        let to: Float = visible ? 1 : 0
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.opacity = to
        CATransaction.commit()
        guard !reduceMotion || duration > 0 else { completion?(); return }
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = from
        animation.toValue = to
        animation.duration = reduceMotion ? min(duration, 0.15) : duration
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        CATransaction.begin()
        CATransaction.setCompletionBlock { completion?() }
        layer.add(animation, forKey: "note.fade")
        CATransaction.commit()
    }
}
