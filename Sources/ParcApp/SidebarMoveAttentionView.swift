import AppKit
import QuartzCore

///
/// command reveals: the item's cell (`SelectableCellView.shakeAnimator`, built
///
/// response and damping ratio 0.2, kicked from rest at 200 points a second
///
/// frame sets the cell layer's transform to that horizontal translation
///
/// animation, ending once the swing stays under a tenth of a point.
enum SidebarAttentionShake {
    static let key = "parc.sidebar.attention"
    static let response = 0.8
    static let dampingRatio = 0.2
    static let velocity = 200.0
    private static var omega: Double { 2 * .pi / response }
    private static var dampedOmega: Double { omega * (1 - dampingRatio * dampingRatio).squareRoot() }

    /// The underdamped spring released at 0 with the kick's velocity.
    static func offset(at time: Double) -> Double {
        velocity / dampedOmega * exp(-dampingRatio * omega * time) * sin(dampedOmega * time)
    }
    static var duration: Double { log(velocity / dampedOmega / 0.1) / (dampingRatio * omega) }

    static func animation(frameRate: Double = 120) -> CAKeyframeAnimation {
        let count = Int((duration * frameRate).rounded(.up))
        let animation = CAKeyframeAnimation(keyPath: "transform.translation.x")
        animation.values = (0..<count).map { offset(at: Double($0) / frameRate) } + [0.0]
        animation.keyTimes = (0...count).map { NSNumber(value: Double($0) / Double(count)) }
        animation.duration = duration
        animation.calculationMode = .linear
        animation.isAdditive = true
        return animation
    }
    static func play(on view: NSView) {
        view.wantsLayer = true
        guard let layer = view.layer else { return }
        layer.removeAnimation(forKey: key)
        layer.add(animation(), forKey: key)
    }
}
