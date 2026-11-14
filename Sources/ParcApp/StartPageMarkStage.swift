import QuartzCore

@MainActor
final class StartPageMarkStage {
    static let swoopKey = "parc.start-page-mark.swoop"
    static let landingKey = "parc.start-page-mark.landing"
    static let holdKey = "parc.start-page-mark.hold"
    static let buzzKey = "parc.start-page-mark.buzz"
    static let loopKey = "parc.start-page-mark.loop"
    static let relaxKey = "parc.start-page-mark.relax"
    static let glowOpacityKey = "parc.start-page-mark.glow-opacity"
    static let glowRadiusKey = "parc.start-page-mark.glow-radius"
    static let glowColorKey = "parc.start-page-mark.glow-color"
    static let lifetimeKey = "parc.start-page-mark.lifetime"
    static let ribbonKey = "parc.start-page-mark.ribbon"
    static let confettiKey = "parc.start-page-mark.confetti"
    static let bodyKeys = [TaffyAnimator.key, swoopKey, landingKey, holdKey, buzzKey, loopKey, relaxKey,
                           glowOpacityKey, glowRadiusKey, glowColorKey]

    let body: CALayer
    let shimmer: CALayer
    var colors: [CGColor] = []
    var shimmerColors: [CGColor] = []
    var contentsScale: CGFloat = 2
    private(set) var effects: CALayer?
    private var token = 0
    private let taffy = TaffyAnimator()

    init(body: CALayer, shimmer: CALayer) {
        self.body = body
        self.shimmer = shimmer
    }

    func track(_ pull: CGVector) { taffy.track(pull, stage: body) }

    func snap(from pull: CGVector, completion: @escaping @MainActor () -> Void) {
        token += 1
        taffy.play(from: pull, stage: body, completion: completion)
    }

    func swoop(in host: CALayer?, home: CGPoint, pageWidth: CGFloat,
               landed: @escaping @MainActor () -> Void, completion: @escaping @MainActor () -> Void) {
        token += 1
        let token = token, frame = StartPageMarkFrame(layer: body)
        let reach = StartPageMarkSwoop.reach(pageWidth: pageWidth)
        let ribbonColors = Array(colors.prefix(StartPageMarkSwoop.maximumStripes))
        let ribbon = host != nil && !ribbonColors.isEmpty
        let join = StartPageMarkJoin(ribbon ? 2 : 1, done: completion)
        if let host, ribbon {
            addRibbon(in: host, colors: ribbonColors, home: home, reach: reach, frame: frame, token: token) { join.arrive() }
        }
        let flight = StartPageMarkSwoop.flight(reach: reach)
        animate(flight.poses, times: flight.times, key: Self.swoopKey, frame: frame) { [weak self] in
            guard let self, self.token == token else { return }
            landed()
            self.land(frame: frame, token: token) { join.arrive() }
        }
    }

    func charge(_ style: StartPageMarkMotionStyle) {
        token += 1
        let frame = StartPageMarkFrame(layer: body)
        let times = StartPageMarkSampling.times(duration: StartPageMarkCharge.ramp, rate: StartPageMarkCharge.frameRate)
        let levels = times.map { CGFloat($0 / StartPageMarkCharge.ramp) }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if style == .motion {
            let hold = StartPageMarkSampling.keyframes("transform", values: levels.map {
                NSValue(caTransform3D: StartPageMarkCharge.holdPose(level: $0).transform(in: frame))
            }, times: times)
            hold.fillMode = .forwards
            hold.isRemovedOnCompletion = false
            body.transform = CATransform3DIdentity
            body.add(hold, forKey: Self.holdKey)
            body.add(buzz(frame: frame), forKey: Self.buzzKey)
        }
        addGlow(levels.map(StartPageMarkEasing.outCubic), times: times, frame: frame, holds: true, then: nil)
        CATransaction.commit()
    }

    func loop(in host: CALayer?, home: CGPoint,
              landed: @escaping @MainActor () -> Void, completion: @escaping @MainActor () -> Void) {
        token += 1
        let token = token, frame = StartPageMarkFrame(layer: body)
        let confetti = host != nil && !colors.isEmpty
        let join = StartPageMarkJoin(confetti ? 2 : 1, done: completion)
        if let host, confetti { addConfetti(in: host, home: home, token: token) { join.arrive() } }
        let glowTimes = StartPageMarkSampling.times(duration: StartPageMarkCharge.loopGlowFade, rate: StartPageMarkCharge.frameRate)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        body.removeAnimation(forKey: Self.holdKey)
        body.removeAnimation(forKey: Self.buzzKey)
        addGlow(glowTimes.map(StartPageMarkCharge.loopGlow), times: glowTimes, frame: frame, holds: false) { [weak self] in
            guard let self, self.token == token else { return }
            self.body.removeAnimation(forKey: Self.glowColorKey)
        }
        CATransaction.commit()
        let times = StartPageMarkSampling.times(duration: StartPageMarkCharge.loopDuration)
        let radius = StartPageMarkCharge.loopRadius * frame.scale
        animate(times.map { StartPageMarkCharge.loopPose(at: $0, radius: radius) }, times: times, key: Self.loopKey, frame: frame) { [weak self] in
            guard let self, self.token == token else { return }
            landed()
            self.land(frame: frame, token: token) { join.arrive() }
        }
    }

    func relax(level: CGFloat, style: StartPageMarkMotionStyle, completion: @escaping @MainActor () -> Void) {
        token += 1
        let token = token, frame = StartPageMarkFrame(layer: body)
        let moves = style == .motion && StartPageMarkCharge.relaxSquish(level: level) > 0
        let join = StartPageMarkJoin(moves ? 2 : 1) { [weak self] in
            guard let self, self.token == token else { return }
            self.body.removeAnimation(forKey: Self.glowColorKey)
            completion()
        }
        let glowTimes = StartPageMarkSampling.times(duration: StartPageMarkCharge.relaxGlowDuration, rate: StartPageMarkCharge.frameRate)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        body.removeAnimation(forKey: Self.holdKey)
        body.removeAnimation(forKey: Self.buzzKey)
        addGlow(glowTimes.map { StartPageMarkCharge.relaxGlow(at: $0, level: level) }, times: glowTimes, frame: frame, holds: false) {
            join.arrive()
        }
        CATransaction.commit()
        guard moves else { return }
        let spring = StartPageMarkCharge.relaxSpring(level: level)
        let squish = StartPageMarkCharge.relaxSquish(level: level)
        animate(spring.samples().map { StartPageMarkCharge.relaxPose(squish * CGFloat($0)) }, times: spring.times(),
                key: Self.relaxKey, frame: frame) { join.arrive() }
    }

    func playShimmer(completion: @escaping @MainActor () -> Void) {
        token += 1
        let token = token
        StartPageMarkShimmer.play(on: shimmer, colors: shimmerColors) { [weak self] in
            if let self, self.token == token { self.clearGlow() }
            completion()
        }
    }

    func reset() {
        token += 1
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for key in Self.bodyKeys { body.removeAnimation(forKey: key) }
        body.transform = CATransform3DIdentity
        body.shadowOpacity = 0
        CATransaction.commit()
        StartPageMarkShimmer.reset(shimmer)
        removeEffects()
    }

    private func land(frame: StartPageMarkFrame, token: Int, done: @escaping @MainActor () -> Void) {
        animate(StartPageMarkLanding.poses(), times: StartPageMarkLanding.spring.times(), key: Self.landingKey, frame: frame) { [weak self] in
            guard let self, self.token == token else { return }
            done()
        }
    }

    private func animate(_ poses: [StartPageMarkPose], times: [Double], key: String, frame: StartPageMarkFrame,
                         then: @escaping @MainActor () -> Void) {
        let animation = StartPageMarkSampling.keyframes("transform", values: poses.map { NSValue(caTransform3D: $0.transform(in: frame)) },
                                                        times: times)
        animation.delegate = StartPageMarkAnimationEnd(then)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        body.transform = CATransform3DIdentity
        body.add(animation, forKey: key)
        CATransaction.commit()
    }

    private func buzz(frame: StartPageMarkFrame) -> CAKeyframeAnimation {
        let animation = CAKeyframeAnimation(keyPath: "transform.translation.x")
        let amplitude = StartPageMarkCharge.buzz * frame.scale
        animation.values = (0..<StartPageMarkCharge.buzzFrames).map { _ in NSNumber(value: Double(CGFloat.random(in: -amplitude...amplitude))) }
        animation.calculationMode = .discrete
        animation.isAdditive = true
        animation.duration = Double(StartPageMarkCharge.buzzFrames) / StartPageMarkCharge.frameRate
        animation.repeatCount = .infinity
        animation.beginTime = body.convertTime(CACurrentMediaTime(), from: nil) + StartPageMarkCharge.ramp
        return animation
    }

    private func addGlow(_ amounts: [CGFloat], times: [Double], frame: StartPageMarkFrame, holds: Bool,
                         then: (@MainActor () -> Void)?) {
        let glows = amounts.map { StartPageMarkCharge.glow($0, scale: frame.scale) }
        let opacity = StartPageMarkSampling.keyframes("shadowOpacity", values: glows.map { NSNumber(value: $0.opacity) }, times: times)
        let radius = StartPageMarkSampling.keyframes("shadowRadius", values: glows.map { NSNumber(value: Double($0.radius)) }, times: times)
        if holds {
            for animation in [opacity, radius] {
                animation.fillMode = .forwards
                animation.isRemovedOnCompletion = false
            }
        }
        if let then { opacity.delegate = StartPageMarkAnimationEnd(then) }
        body.shadowOffset = .zero
        body.shadowOpacity = 0
        body.add(opacity, forKey: Self.glowOpacityKey)
        body.add(radius, forKey: Self.glowRadiusKey)
        guard body.animation(forKey: Self.glowColorKey) == nil, let first = colors.first else { return }
        body.shadowColor = first
        guard colors.count > 1 else { return }
        let cycle = CAKeyframeAnimation(keyPath: "shadowColor")
        cycle.values = colors + [first]
        cycle.duration = StartPageMarkCharge.glowCycle * Double(colors.count)
        cycle.calculationMode = .linear
        cycle.repeatCount = .infinity
        body.add(cycle, forKey: Self.glowColorKey)
    }

    private func clearGlow() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for key in [Self.glowOpacityKey, Self.glowRadiusKey, Self.glowColorKey] { body.removeAnimation(forKey: key) }
        body.shadowOpacity = 0
        CATransaction.commit()
    }

    private func makeEffects(in host: CALayer, lifetime: Double, token: Int, done: @escaping @MainActor () -> Void) -> CALayer {
        removeEffects()
        let container = CALayer()
        let life = CABasicAnimation(keyPath: "opacity")
        life.fromValue = 1
        life.toValue = 1
        life.duration = lifetime
        life.delegate = StartPageMarkAnimationEnd { [weak self, weak container] in
            guard let self, self.token == token else { return }
            if let container, self.effects === container { self.removeEffects() }
            done()
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        container.frame = host.bounds
        container.isGeometryFlipped = !host.contentsAreFlipped()
        container.contentsScale = contentsScale
        container.add(life, forKey: Self.lifetimeKey)
        host.addSublayer(container)
        CATransaction.commit()
        effects = container
        return container
    }

    private func removeEffects() {
        guard let effects else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        effects.removeFromSuperlayer()
        CATransaction.commit()
        self.effects = nil
    }

    private func addRibbon(in host: CALayer, colors: [CGColor], home: CGPoint, reach: CGFloat, frame: StartPageMarkFrame, token: Int,
                           done: @escaping @MainActor () -> Void) {
        let container = makeEffects(in: host, lifetime: StartPageMarkSwoop.ribbonDuration, token: token, done: done)
        let times = StartPageMarkSampling.times(duration: StartPageMarkSwoop.ribbonDuration)
        let frames = times.map {
            StartPageMarkSwoop.ribbon(at: $0, home: home, reach: reach, mark: frame.size,
                                      width: StartPageMarkSwoop.ribbonWidth * frame.scale, stripes: colors.count)
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (index, color) in colors.enumerated() {
            let stripe = CAShapeLayer()
            stripe.frame = container.bounds
            stripe.contentsScale = contentsScale
            stripe.fillColor = color.copy(alpha: StartPageMarkSwoop.ribbonAlpha) ?? color
            stripe.add(StartPageMarkSampling.keyframes("path", values: frames.map { $0[index] }, times: times), forKey: Self.ribbonKey)
            container.addSublayer(stripe)
        }
        CATransaction.commit()
    }

    private func addConfetti(in host: CALayer, home: CGPoint, token: Int, done: @escaping @MainActor () -> Void) {
        var generator = SystemRandomNumberGenerator()
        let pieces = StartPageMarkConfetti.pieces(colors: colors.count, using: &generator)
        let container = makeEffects(in: host, lifetime: pieces.map(\.life).max() ?? 0, token: token, done: done)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for piece in pieces {
            let layer = CALayer()
            layer.bounds = CGRect(origin: .zero, size: piece.size)
            layer.position = home
            layer.backgroundColor = colors[piece.color]
            layer.opacity = 0
            layer.add(StartPageMarkConfetti.animation(for: piece, from: home), forKey: Self.confettiKey)
            container.addSublayer(layer)
        }
        CATransaction.commit()
    }
}
