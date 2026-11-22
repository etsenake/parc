import QuartzCore

enum StartPageMarkEasing {
    static func clamp(_ value: CGFloat) -> CGFloat { min(1, max(0, value)) }
    static func outCubic(_ value: CGFloat) -> CGFloat { 1 - pow(1 - clamp(value), 3) }
    static func inOutCubic(_ value: CGFloat) -> CGFloat {
        let t = clamp(value)
        return t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
    }
    static func inOutSine(_ value: CGFloat) -> CGFloat { -(cos(.pi * clamp(value)) - 1) / 2 }
}

struct StartPageMarkFrame: Equatable {
    static let mockupHeight: CGFloat = 65

    var size: CGSize
    var anchor: CGPoint
    var yDown: Bool

    init(size: CGSize, anchor: CGPoint, yDown: Bool) {
        self.size = size; self.anchor = anchor; self.yDown = yDown
    }

    init(layer: CALayer) {
        self.init(size: layer.bounds.size, anchor: layer.anchorPoint, yDown: layer.superlayer?.contentsAreFlipped() ?? true)
    }

    var scale: CGFloat { size.height > 0 ? size.height / Self.mockupHeight : 1 }
}

struct StartPageMarkPose: Equatable {
    static let identity = Self()
    static let bottom = CGPoint(x: 0.5, y: 1)

    var offset = CGVector(dx: 0, dy: 0)
    var rotation: CGFloat = 0
    var scale = CGSize(width: 1, height: 1)
    var origin = CGPoint(x: 0.5, y: 0.5)

    func transform(in frame: StartPageMarkFrame) -> CATransform3D {
        let width = frame.size.width, height = frame.size.height
        let cosine = cos(rotation), sine = sin(rotation)
        let a = cosine * scale.width, b = -sine * scale.height
        let c = sine * scale.width, d = cosine * scale.height
        let rx = (origin.x - frame.anchor.x) * width
        let ry = (origin.y - (frame.yDown ? frame.anchor.y : 1 - frame.anchor.y)) * height
        let flip: CGFloat = frame.yDown ? 1 : -1
        var result = CATransform3DIdentity
        result.m11 = a; result.m21 = b * flip; result.m12 = c * flip; result.m22 = d
        result.m41 = rx - (a * rx + b * ry) + offset.dx
        result.m42 = (ry - (c * rx + d * ry) + offset.dy) * flip
        return result
    }
}

struct StartPageMarkSpring: Equatable {
    static let sampleRate = 120.0

    var stiffness: Double
    var damping: Double
    var settleThreshold: Double

    init(stiffness: Double, damping: Double, settleThreshold: Double = 0.01) {
        self.stiffness = stiffness; self.damping = damping; self.settleThreshold = settleThreshold
    }

    init(response: Double, dampingRatio: Double, settleThreshold: Double = 0.01) {
        self.init(stiffness: pow(2 * Double.pi / response, 2), damping: 4 * Double.pi * dampingRatio / response,
                  settleThreshold: settleThreshold)
    }

    private var decay: Double { damping / 2 }
    private var dampedFrequency: Double { max(stiffness - decay * decay, stiffness * 0.01).squareRoot() }

    func displacement(at time: Double) -> Double {
        exp(-decay * time) * (cos(dampedFrequency * time) + decay / dampedFrequency * sin(dampedFrequency * time))
    }

    var settlingDuration: Double {
        max(0, log((1 + pow(decay / dampedFrequency, 2)).squareRoot() / settleThreshold) / decay)
    }

    func samples() -> [Double] {
        let count = max(1, Int((settlingDuration * Self.sampleRate).rounded(.up)))
        var values = (0...count).map { displacement(at: Double($0) / Self.sampleRate) }
        values[count] = 0
        return values
    }

    func times() -> [Double] { (0..<samples().count).map { Double($0) / Self.sampleRate } }
}

enum StartPageMarkSampling {
    static func times(duration: Double, rate: Double = StartPageMarkSpring.sampleRate) -> [Double] {
        let count = max(1, Int((duration * rate).rounded(.up)))
        var values = (0...count).map { Double($0) / rate }
        values[count] = duration
        return values
    }

    static func keyframes(_ keyPath: String, values: [Any], times: [Double]) -> CAKeyframeAnimation {
        let animation = CAKeyframeAnimation(keyPath: keyPath)
        let duration = max(times.last ?? 0, 1e-3)
        animation.values = values
        animation.keyTimes = times.map { NSNumber(value: $0 / duration) }
        animation.duration = duration
        animation.calculationMode = .linear
        return animation
    }
}

enum StartPageMarkLanding {
    static let squash: CGFloat = 0.32
    static let spread: CGFloat = 0.8
    static let spring = StartPageMarkSpring(stiffness: 420, damping: 13, settleThreshold: 0.002 / 0.32)

    static func pose(_ squash: CGFloat) -> StartPageMarkPose {
        StartPageMarkPose(scale: CGSize(width: 1 + spread * squash, height: 1 - squash), origin: StartPageMarkPose.bottom)
    }

    static func poses() -> [StartPageMarkPose] { spring.samples().map { pose(squash * CGFloat($0)) } }

    static var duration: Double { spring.times().last ?? 0 }
}

final class StartPageMarkAnimationEnd: NSObject, CAAnimationDelegate {
    private let action: @MainActor () -> Void

    init(_ action: @escaping @MainActor () -> Void) { self.action = action }

    func animationDidStop(_ anim: CAAnimation, finished flag: Bool) { MainActor.assumeIsolated { action() } }
}

@MainActor
final class StartPageMarkJoin {
    private var remaining: Int
    private let done: @MainActor () -> Void

    init(_ count: Int, done: @escaping @MainActor () -> Void) {
        remaining = max(1, count)
        self.done = done
    }

    func arrive() {
        guard remaining > 0 else { return }
        remaining -= 1
        if remaining == 0 { done() }
    }
}
