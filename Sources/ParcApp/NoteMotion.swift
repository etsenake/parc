import AppKit

///
///
/// `Animation.spring(response: 0.15, dampingFraction: 0.825, blendDuration: 0)`
/// as `_AnimationModifier<Int>` on `FormatMenu.State.selectedIndex`. Item rows
///
///
/// `addSubview` / `setFrame:` / `removeFromSuperview` with no animation API.
///
/// canvas appearance only invalidates display. Helpers found no Notes-owned
/// haptic, `UIImpactFeedback`, `NSHapticFeedback` or `performFeedbackPattern:`
/// call; tab-reorder and drop haptics belong to other families and are not
/// copied here.
@MainActor
enum NoteMotion {
    static let selectedIndexResponse: CGFloat = 0.15
    static let selectedIndexDamping: CGFloat = 0.825
    static let highlightKey = "note.selectedIndex"
    static let insertionKey = "note.itemOpacity"

    static func matchesRecovered(_ spring: CASpringAnimation) -> Bool {
        let omega = 2 * Double.pi / Double(selectedIndexResponse)
        return abs(spring.mass - 1) < 0.001
            && abs(spring.stiffness - omega * omega) < 0.05
            && abs(spring.damping - 2 * Double(selectedIndexDamping) * omega) < 0.05
            && abs(spring.duration - spring.settlingDuration) < 0.001
    }

    static func selectedIndexSpring(keyPath: String, from: Any?, to: Any?) -> CASpringAnimation {
        let omega = 2 * Double.pi / Double(selectedIndexResponse)
        let spring = CASpringAnimation(keyPath: keyPath)
        spring.mass = 1
        spring.stiffness = omega * omega
        spring.damping = 2 * Double(selectedIndexDamping) * omega
        spring.fromValue = from
        spring.toValue = to
        spring.duration = spring.settlingDuration
        return spring
    }

    static func makeHighlight() -> NSView {
        let highlight = NSView()
        highlight.wantsLayer = true
        highlight.layer?.cornerRadius = 4
        highlight.setAccessibilityElement(false)
        highlight.alphaValue = 0
        refreshHighlight(highlight)
        return highlight
    }

    static func refreshHighlight(_ highlight: NSView) {
        let fill = NoteFormattingAppearance.hover
        CATransaction.begin(); CATransaction.setDisableActions(true)
        highlight.effectiveAppearance.performAsCurrentDrawingAppearance {
            highlight.layer?.backgroundColor = fill.cgColor
        }
        CATransaction.commit()
    }

    static func layoutHighlight(_ highlight: NSView, over button: NSView) {
        highlight.frame = button.frame.insetBy(dx: 2, dy: 2)
    }

    @discardableResult
    static func setHighlight(_ highlight: NSView, selected: Bool, animated: Bool) -> CASpringAnimation? {
        animateOpacity(highlight, to: selected ? 1 : 0, key: highlightKey, animated: animated)
    }

    @discardableResult
    static func fadeItem(_ view: NSView, visible: Bool, completion: (() -> Void)? = nil) -> CASpringAnimation? {
        animateOpacity(view, to: visible ? 1 : 0, key: insertionKey, animated: true, completion: completion)
    }

    static func settle(_ view: NSView) {
        view.layer?.removeAnimation(forKey: highlightKey)
        view.layer?.removeAnimation(forKey: insertionKey)
        view.subviews.forEach(settle)
    }

    ///
    /// its laid-out frame with no recovered presentation animation.
    static func presentImmediately(_ view: NSView, in host: NSView) {
        host.addSubview(view)
    }

    ///
    /// no recovered dismissal animation.
    static func dismissImmediately(_ view: NSView?) {
        guard let view else { return }
        settle(view)
        view.removeFromSuperview()
    }

    private static func animateOpacity(
        _ view: NSView, to target: CGFloat, key: String, animated: Bool,
        completion: (() -> Void)? = nil
    ) -> CASpringAnimation? {
        view.wantsLayer = true
        let from = view.layer?.presentation()?.opacity ?? Float(view.alphaValue)
        let to = Float(target)
        CATransaction.begin(); CATransaction.setDisableActions(true)
        view.alphaValue = target
        CATransaction.commit()
        view.layer?.removeAnimation(forKey: key)
        guard animated, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, let layer = view.layer, from != to else {
            completion?(); return nil
        }
        let spring = selectedIndexSpring(keyPath: "opacity", from: from, to: to)
        CATransaction.begin()
        CATransaction.setCompletionBlock(completion)
        layer.add(spring, forKey: key)
        CATransaction.commit()
        return spring
    }
}
