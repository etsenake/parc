import AppKit

///
///
/// AppKit's layer spring is a physical approximation of that SwiftUI spring.
@MainActor
final class MiniPlayerMotion {
    static let hoverOffDelay: TimeInterval = 2
    private static let keys = ["parc.media.position", "parc.media.bounds", "parc.media.opacity"]
    private let animatedLayers = NSHashTable<CALayer>.weakObjects()

    private struct Snapshot {
        let layer: CALayer
        let modelPosition: CGPoint
        let modelBounds: CGRect
        let modelOpacity: Float
        let visiblePosition: CGPoint
        let visibleBounds: CGRect
        let visibleOpacity: Float
    }

    private func snapshot(_ view: NSView) -> Snapshot? {
        guard let layer = view.layer else { return nil }
        let visible = layer.presentation() ?? layer
        return Snapshot(layer: layer, modelPosition: layer.position, modelBounds: layer.bounds,
                        modelOpacity: layer.opacity, visiblePosition: visible.position,
                        visibleBounds: visible.bounds, visibleOpacity: visible.opacity)
    }

    private func deckSnapshots(_ view: NSView) -> [Snapshot] {
        (snapshot(view).map { [$0] } ?? []) + view.subviews.flatMap { deckSnapshots($0) }
    }

    /// Only remove animations installed by this deck, even if a layer has since
    /// left the view hierarchy. Weak references do not extend layer lifetimes.
    func settle() {
        for layer in animatedLayers.allObjects { Self.keys.forEach { layer.removeAnimation(forKey: $0) } }
        animatedLayers.removeAllObjects()
    }

    func layout(in root: NSView, deck: NSView, companion: NSView?, animated: Bool, changes: () -> Void) {
        let canAnimate = animated && root.window != nil && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        var before = canAnimate ? deckSnapshots(deck) : []
        if canAnimate, let companion, let entry = snapshot(companion) { before.append(entry) }
        if !canAnimate { settle() }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        changes()
        root.layoutSubtreeIfNeeded()
        CATransaction.commit()
        guard canAnimate else { return }
        for old in before {
            let layer = old.layer
            animate(layer, keyPath: "position", key: Self.keys[0], from: NSValue(point: old.visiblePosition), to: NSValue(point: layer.position), changed: old.modelPosition != layer.position)
            animate(layer, keyPath: "bounds", key: Self.keys[1], from: NSValue(rect: old.visibleBounds), to: NSValue(rect: layer.bounds), changed: old.modelBounds != layer.bounds)
            animate(layer, keyPath: "opacity", key: Self.keys[2], from: old.visibleOpacity, to: layer.opacity, changed: old.modelOpacity != layer.opacity)
        }
    }

    private func animate(_ layer: CALayer, keyPath: String, key: String, from: Any, to: Any, changed: Bool) {
        guard changed else { return }
        let omega = 2 * Double.pi / 0.25
        let spring = CASpringAnimation(keyPath: keyPath)
        spring.mass = 1; spring.stiffness = omega * omega; spring.damping = 2 * 0.9 * omega
        spring.fromValue = from; spring.toValue = to; spring.duration = spring.settlingDuration
        animatedLayers.add(layer)
        layer.add(spring, forKey: key)
    }
}
