import AppKit
import QuartzCore

@MainActor
final class PeekDismissalAnimator {
    private weak var stage: NSView?
    private weak var wash: NSView?
    private var motion = PeekDismissalMotion()
    private let frames = ViewDisplayFrameDriver()
    var onWash: ((Double) -> Void)?

    var restingWash: CGFloat {
        didSet { if restingWash != oldValue { apply() } }
    }

    init(stage: NSView, wash: NSView, restingWash: CGFloat) {
        self.stage = stage
        self.wash = wash
        self.restingWash = restingWash
        stage.wantsLayer = true
    }

    var geometry: PeekDismissalMotion.Geometry {
        get { motion.geometry }
        set {
            guard newValue != motion.geometry else { return }
            motion.geometry = newValue
            apply()
        }
    }

    var washProgress: Double { motion.frame(at: CACurrentMediaTime()).wash }

    var isAtRest: Bool { !motion.isFollowing && motion.frame(at: CACurrentMediaTime()) == .rest }

    func begin() {
        frames.stop()
        motion.begin(reducesMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        apply()
    }

    func follow(_ fraction: Double) {
        frames.stop()
        motion.follow(fraction)
        apply()
    }

    func springBack(velocity: Double) {
        motion.springBack(velocity: velocity, at: CACurrentMediaTime())
        run()
    }

    func exit(_ kind: PeekCloseTransition.Exit, velocity: Double) -> TimeInterval {
        let duration = motion.exit(kind, velocity: velocity,
                                   reducesMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
                                   at: CACurrentMediaTime())
        run()
        return duration
    }

    func reappear() {
        motion.reappear(reducesMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, at: CACurrentMediaTime())
        run()
    }

    func vanish() {
        frames.stop()
        motion.vanish(at: CACurrentMediaTime())
        apply()
    }

    func settle() {
        frames.stop()
        motion.settle()
        apply()
    }

    func complete() {
        frames.stop()
        motion.complete(at: CACurrentMediaTime())
        apply()
    }

    func apply() {
        apply(at: CACurrentMediaTime())
    }

    private func apply(at time: TimeInterval) {
        let frame = motion.frame(at: time)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        stage?.layer?.setValue(frame.offset, forKeyPath: "transform.translation.x")
        stage?.alphaValue = CGFloat(frame.card)
        wash?.alphaValue = restingWash * CGFloat(frame.wash)
        CATransaction.commit()
        onWash?(frame.wash)
    }

    private func run() {
        let now = CACurrentMediaTime()
        apply(at: now)
        guard let stage, motion.isAnimating(at: now) else { return }
        frames.start(in: stage) { [weak self] in
            guard let self else { return false }
            let now = CACurrentMediaTime()
            self.apply(at: now)
            return self.motion.isAnimating(at: now)
        }
    }
}
