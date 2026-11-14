import QuartzCore

enum StartPageMarkCharge {
    static let ramp = 0.65
    static let launchLevel: CGFloat = 0.6
    static let squish: CGFloat = 0.24
    static let spread: CGFloat = 0.16
    static let relaxSpread: CGFloat = 0.66
    static let buzz: CGFloat = 0.8
    static let buzzFrames = 12
    static let frameRate = 60.0
    static let glowCycle = 0.42
    static let glowFadeRate = 4.0
    static let loopDuration = 0.95
    static let loopRadius: CGFloat = 52
    static let launchDuration = 0.18
    static let launchThin: CGFloat = 0.1
    static let launchStretch: CGFloat = 0.16
    static let loopGlowFade = 0.5
    static let relaxStiffness = 420.0
    static let relaxDamping = 14.0
    static let relaxSettle = 0.002

    static func level(held: TimeInterval) -> CGFloat { StartPageMarkEasing.clamp(CGFloat(held / ramp)) }

    static func launches(_ level: CGFloat) -> Bool { level >= launchLevel }

    static func holdPose(level: CGFloat) -> StartPageMarkPose {
        let amount = StartPageMarkEasing.outCubic(level)
        return StartPageMarkPose(scale: CGSize(width: 1 + spread * amount, height: 1 - squish * amount), origin: StartPageMarkPose.bottom)
    }

    static func glow(_ amount: CGFloat, scale: CGFloat) -> (radius: CGFloat, opacity: Float) {
        guard amount > 0.001 else { return (0, 0) }
        return ((3 + 14 * amount) / 2 * scale, Float(0.35 + 0.55 * amount))
    }

    static func loopPose(at time: Double, radius: CGFloat) -> StartPageMarkPose {
        let angle = 2 * .pi * StartPageMarkEasing.inOutCubic(CGFloat(time / loopDuration))
        let launch = max(0, 1 - CGFloat(time / launchDuration))
        return StartPageMarkPose(offset: CGVector(dx: radius * sin(angle), dy: -radius * (1 - cos(angle))), rotation: -angle,
                                 scale: CGSize(width: 1 - launchThin * launch, height: 1 + launchStretch * launch))
    }

    static func loopGlow(at time: Double) -> CGFloat { max(0, 1 - CGFloat(time / loopGlowFade)) }

    static func relaxSquish(level: CGFloat) -> CGFloat { squish * StartPageMarkEasing.outCubic(level) }

    static func relaxSpring(level: CGFloat) -> StartPageMarkSpring {
        StartPageMarkSpring(stiffness: relaxStiffness, damping: relaxDamping,
                            settleThreshold: min(1, relaxSettle / max(Double(relaxSquish(level: level)), 1e-6)))
    }

    static func relaxPose(_ squish: CGFloat) -> StartPageMarkPose {
        StartPageMarkPose(scale: CGSize(width: 1 + relaxSpread * squish, height: 1 - squish), origin: StartPageMarkPose.bottom)
    }

    static var relaxGlowDuration: Double { 1 / glowFadeRate }

    static func relaxGlow(at time: Double, level: CGFloat) -> CGFloat {
        max(0, 1 - CGFloat(glowFadeRate * time)) * StartPageMarkEasing.outCubic(level)
    }
}

struct StartPageMarkConfettiPiece: Equatable {
    var velocity: CGVector
    var rotation: CGFloat
    var spin: CGFloat
    var size: CGSize
    var life: Double
    var color: Int

    func offset(at time: Double) -> CGVector {
        let drag = StartPageMarkConfetti.drag, gravity = StartPageMarkConfetti.gravity
        let settle = CGFloat((1 - exp(-drag * time)) / drag)
        let terminal = gravity / CGFloat(drag)
        return CGVector(dx: velocity.dx * settle, dy: terminal * CGFloat(time) + (velocity.dy - terminal) * settle)
    }

    func angle(at time: Double) -> CGFloat { rotation + spin * CGFloat(time) }

    func flutter(at time: Double) -> CGFloat {
        guard size.height > 0 else { return 1 }
        let face = abs(cos(StartPageMarkConfetti.flutterRate * angle(at: time)))
        return (size.height * face + StartPageMarkConfetti.flutterFloor) / size.height
    }

    func opacity(at time: Double) -> CGFloat {
        let fade = StartPageMarkConfetti.fadeStart * life
        guard time > fade else { return 1 }
        return max(0, 1 - CGFloat((time - fade) / (life - fade)))
    }
}

enum StartPageMarkConfetti {
    static let count = 90
    static let spread: CGFloat = 80
    static let speeds: ClosedRange<CGFloat> = 240...600
    static let drag = -log(0.35)
    static let gravity: CGFloat = 900
    static let spin: CGFloat = 12
    static let widths: ClosedRange<CGFloat> = 4...8
    static let heights: ClosedRange<CGFloat> = 2...5
    static let lives: ClosedRange<Double> = 1.5...2.3
    static let fadeStart = 0.7
    static let flutterRate: CGFloat = 1.7
    static let flutterFloor: CGFloat = 0.6
    static let sampleRate = 60.0

    static func pieces<Generator: RandomNumberGenerator>(colors: Int, using generator: inout Generator) -> [StartPageMarkConfettiPiece] {
        guard colors > 0 else { return [] }
        return (0..<count).map { index in
            let angle = (-90 + CGFloat.random(in: -spread...spread, using: &generator)) * .pi / 180
            let speed = CGFloat.random(in: speeds, using: &generator)
            return StartPageMarkConfettiPiece(velocity: CGVector(dx: cos(angle) * speed, dy: sin(angle) * speed),
                                              rotation: CGFloat.random(in: 0...(2 * .pi), using: &generator),
                                              spin: CGFloat.random(in: -spin...spin, using: &generator),
                                              size: CGSize(width: CGFloat.random(in: widths, using: &generator),
                                                           height: CGFloat.random(in: heights, using: &generator)),
                                              life: Double.random(in: lives, using: &generator), color: index % colors)
        }
    }

    static func animation(for piece: StartPageMarkConfettiPiece, from origin: CGPoint) -> CAAnimationGroup {
        let times = StartPageMarkSampling.times(duration: piece.life, rate: sampleRate)
        let path = CGMutablePath()
        path.addLines(between: times.map {
            let offset = piece.offset(at: $0)
            return CGPoint(x: origin.x + offset.dx, y: origin.y + offset.dy)
        })
        let position = CAKeyframeAnimation(keyPath: "position")
        position.path = path
        position.calculationMode = .linear
        position.duration = piece.life
        let spinning = StartPageMarkSampling.keyframes("transform", values: times.map { time -> NSValue in
            let turn = CATransform3DMakeRotation(piece.angle(at: time), 0, 0, 1)
            return NSValue(caTransform3D: CATransform3DConcat(CATransform3DMakeScale(1, piece.flutter(at: time), 1), turn))
        }, times: times)
        let opacity = CAKeyframeAnimation(keyPath: "opacity")
        opacity.values = [1, 1, 0]
        opacity.keyTimes = [0, NSNumber(value: fadeStart), 1]
        opacity.duration = piece.life
        let group = CAAnimationGroup()
        group.animations = [position, spinning, opacity]
        group.duration = piece.life
        return group
    }
}
