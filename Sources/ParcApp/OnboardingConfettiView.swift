import AppKit
import QuartzCore

/// NewSetupView `_confetti` overlay: `HStack(spacing: 200) { ForEach(0..<6) { Confetti } }`
///
///
///
///
final class OnboardingConfettiView: NSView {
    enum Config {
        static let cannons = 6
        static let cannonSpacing: CGFloat = 200
        static let piecesPerCannon = 16
        static let glyphs = ["●", "●", "\u{2665}\u{FE0E}"]
        static let colors: [NSColor] = [0x3139FB, 0xFF4151, 0x34E895, 0x00C7F3, 0xFFD335].map {
            NSColor(srgbRed: CGFloat($0 >> 16 & 255) / 255, green: CGFloat($0 >> 8 & 255) / 255,
                    blue: CGFloat($0 & 255) / 255, alpha: 1)
        }
        static let size: CGFloat = 12
        static let opacity: Float = 0.7
        static let openingDegrees: ClosedRange<Double> = 60...120
        static let radius: CGFloat = 300
        static let rainHeight: CGFloat = 800
        ///
        static let rainDuration: Double = Double(rainHeight + radius) / 200
        ///
        static let fadeDelay: ClosedRange<Double> = 1...4
        static let fadeDuration: Double = 0.5
        /// Explosion: `.spring(response: 0.5, dampingFraction: 0.75).delay(random(0.05...0.1))`.
        static let springResponse: Double = 0.5
        static let springDamping: Double = 0.75
        static let burstDelay: ClosedRange<Double> = 0.05...0.1
        ///
        static let distance: ClosedRange<Double> = 0.5...2
        /// Spin speeds `1 + random(0..<1)`; x spin repeats 10 times, z forever.
        static let spinSpeed: ClosedRange<Double> = 1...2
        static let xSpinRepeats: Float = 10
        static var lifetime: Double { max(rainDuration, fadeDelay.upperBound + fadeDuration) }
    }

    /// One piece's randomized ConfettiView/ConfettiAnimationView state.
    struct Piece {
        var cannon: Int
        var glyph: Int
        var color: Int
        var offset: CGVector
        var burstDelay: Double
        var fadeDelay: Double
        var xSpeed: Double
        var zSpeed: Double
        var xDirection: CGFloat
        var zDirection: CGFloat
        var anchor: CGFloat

        static func random<G: RandomNumberGenerator>(cannon: Int, using generator: inout G) -> Piece {
            let angle = Double.random(in: Config.openingDegrees, using: &generator) * .pi / 180
            let distance = Double(Config.radius) * Double.random(in: Config.distance, using: &generator)
            return Piece(cannon: cannon, glyph: Int.random(in: 0..<Config.glyphs.count, using: &generator),
                         color: Int.random(in: 0..<Config.colors.count, using: &generator),
                         offset: CGVector(dx: distance * cos(angle), dy: distance * sin(angle)),
                         burstDelay: Double.random(in: Config.burstDelay, using: &generator),
                         fadeDelay: Double.random(in: Config.fadeDelay, using: &generator),
                         xSpeed: Double.random(in: Config.spinSpeed, using: &generator),
                         zSpeed: Double.random(in: Config.spinSpeed, using: &generator),
                         xDirection: Bool.random(using: &generator) ? 1 : -1,
                         zDirection: Bool.random(using: &generator) ? 1 : -1,
                         anchor: Bool.random(using: &generator) ? 1 : 0)
        }

        /// Offset from the cannon (y up), opacity and spin angles `time` seconds after the burst.
        func sample(at time: Double) -> (offset: CGVector, opacity: Double, xAngle: Double, zAngle: Double) {
            let burst = OnboardingConfettiView.spring(time - burstDelay)
            let rain = OnboardingConfettiView.rainCurve(min(1, max(0, time / Config.rainDuration)))
            let fade = OnboardingConfettiView.rainCurve(min(1, max(0, (time - fadeDelay) / Config.fadeDuration)))
            let opacity = time < burstDelay ? 0 : max(0, min(1, Double(Config.opacity) * burst)) * (1 - fade)
            let xTurns = min(time / xSpeed, Double(Config.xSpinRepeats))
            return (CGVector(dx: offset.dx * burst, dy: offset.dy * burst - Config.rainHeight * rain), opacity,
                    2 * .pi * Double(xDirection) * xTurns, 2 * .pi * Double(zDirection) * time / zSpeed)
        }
    }

    private let pieces = CALayer()
    private var pending: DispatchWorkItem?
    private var cleanup: DispatchWorkItem?
    /// NewSetupView sets its counter to `!reduceMotion`, so a second visit doesn't refire.
    private(set) var hasFired = false
    var isPending: Bool { pending != nil }
    var livePieceCount: Int { pieces.sublayers?.count ?? 0 }
    override var isOpaque: Bool { false }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.addSublayer(pieces)
        setAccessibilityElement(false)
        setAccessibilityHidden(true)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        pieces.frame = bounds
        CATransaction.commit()
    }

    /// Cannon centres along the view's horizontal centre line.
    static func cannonPoints(in bounds: NSRect) -> [CGPoint] {
        (0..<Config.cannons).map { index in
            CGPoint(x: bounds.midX + (CGFloat(index) - CGFloat(Config.cannons - 1) / 2) * Config.cannonSpacing,
                    y: bounds.midY)
        }
    }

    static func makePieces<G: RandomNumberGenerator>(using generator: inout G) -> [Piece] {
        (0..<Config.cannons).flatMap { cannon in
            (0..<Config.piecesPerCannon).map { _ in Piece.random(cannon: cannon, using: &generator) }
        }
    }

    /// Fires once, `delay` seconds from now, unless cancelled or already fired.
    func fire(after delay: TimeInterval) {
        guard !hasFired, pending == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pending = nil
            // The delayed writer re-reads Reduce Motion when it runs.
            guard let window = self.window, window.isVisible, !self.isHiddenOrHasHiddenAncestor,
                  !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
            self.hasFired = true
            self.burst()
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    func cancelPending() {
        pending?.cancel(); pending = nil
    }

    func stop() {
        cancelPending()
        cleanup?.cancel(); cleanup = nil
        pieces.sublayers?.forEach { $0.removeFromSuperlayer() }
    }

    private func burst() {
        stop()
        guard !bounds.isEmpty else { return }
        layout()
        var generator = SystemRandomNumberGenerator()
        let scale = window?.backingScaleFactor ?? 2
        let images = Self.glyphImages(scale: scale)
        let points = Self.cannonPoints(in: bounds)
        let now = pieces.convertTime(CACurrentMediaTime(), from: nil)
        CATransaction.begin(); CATransaction.setDisableActions(true)
        for piece in Self.makePieces(using: &generator) {
            guard let image = images[piece.glyph][piece.color] else { continue }
            pieces.addSublayer(Self.layer(for: piece, image: image, at: points[piece.cannon], scale: scale, now: now))
        }
        CATransaction.commit()
        let work = DispatchWorkItem { [weak self] in self?.stop() }
        cleanup = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Config.lifetime + 0.2, execute: work)
    }

    private static func layer(for piece: Piece, image: (CGImage, CGSize), at point: CGPoint,
                              scale: CGFloat, now: CFTimeInterval) -> CALayer {
        let size = image.1
        let holder = CALayer()
        holder.bounds = CGRect(origin: .zero, size: size)
        holder.position = point
        holder.opacity = 0
        // ConfettiAnimationView: rotation3DEffect about x, then about z at UnitPoint(anchor, anchor).
        let orbit = CALayer()
        orbit.bounds = holder.bounds
        orbit.anchorPoint = CGPoint(x: piece.anchor, y: 1 - piece.anchor)
        orbit.position = CGPoint(x: piece.anchor * size.width, y: (1 - piece.anchor) * size.height)
        var perspective = CATransform3DIdentity
        perspective.m34 = -1 / max(size.width, size.height)
        orbit.sublayerTransform = perspective
        let glyph = CALayer()
        glyph.frame = orbit.bounds
        glyph.contents = image.0
        glyph.contentsScale = scale
        orbit.addSublayer(glyph); holder.addSublayer(orbit)

        let spring = { (key: String, from: Any, to: Any) -> CASpringAnimation in
            let animation = CASpringAnimation(keyPath: key)
            let frequency = 2 * Double.pi / Config.springResponse
            animation.mass = 1; animation.stiffness = frequency * frequency
            animation.damping = 2 * Config.springDamping * frequency
            animation.fromValue = from; animation.toValue = to
            animation.duration = animation.settlingDuration
            animation.beginTime = now + piece.burstDelay
            animation.fillMode = .both; animation.isRemovedOnCompletion = false
            return animation
        }
        let burst = spring("position", NSValue(point: .zero), NSValue(point: NSPoint(x: piece.offset.dx, y: piece.offset.dy)))
        burst.isAdditive = true
        holder.add(burst, forKey: "burst")
        holder.add(spring("opacity", 0, Config.opacity), forKey: "appear")
        let rain = CABasicAnimation(keyPath: "position.y")
        rain.fromValue = 0; rain.toValue = -Config.rainHeight; rain.isAdditive = true
        rain.duration = Config.rainDuration; rain.beginTime = now
        rain.timingFunction = rainTiming
        rain.fillMode = .both; rain.isRemovedOnCompletion = false
        holder.add(rain, forKey: "rain")
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = Config.opacity; fade.toValue = 0
        fade.duration = Config.fadeDuration; fade.beginTime = now + piece.fadeDelay
        fade.timingFunction = rainTiming
        fade.fillMode = .forwards; fade.isRemovedOnCompletion = false
        holder.add(fade, forKey: "fade")
        let flip = CABasicAnimation(keyPath: "transform.rotation.x")
        flip.fromValue = 0; flip.toValue = 2 * CGFloat.pi * piece.xDirection
        flip.duration = piece.xSpeed; flip.repeatCount = Config.xSpinRepeats; flip.beginTime = now
        glyph.add(flip, forKey: "spin")
        let turn = CABasicAnimation(keyPath: "transform.rotation.z")
        turn.fromValue = 0; turn.toValue = 2 * CGFloat.pi * piece.zDirection
        turn.duration = piece.zSpeed; turn.repeatCount = .infinity; turn.beginTime = now
        orbit.add(turn, forKey: "spin")
        return holder
    }

    /// `timingCurve(0.12, 0, 0.39, 0)` for the rain and the fade.
    private static let rainTiming = CAMediaTimingFunction(controlPoints: 0.12, 0, 0.39, 0)

    static func rainCurve(_ x: Double) -> Double {
        // Cubic Bézier (0.12, 0) (0.39, 0): solve x(t) by bisection, return y(t).
        func bezier(_ t: Double, _ a: Double, _ b: Double) -> Double {
            3 * (1 - t) * (1 - t) * t * a + 3 * (1 - t) * t * t * b + t * t * t
        }
        if x <= 0 { return 0 }
        if x >= 1 { return 1 }
        var low = 0.0, high = 1.0
        for _ in 0..<40 {
            let mid = (low + high) / 2
            if bezier(mid, 0.12, 0.39) < x { low = mid } else { high = mid }
        }
        return bezier((low + high) / 2, 0, 0)
    }

    /// Unit-step response of `.spring(response: 0.5, dampingFraction: 0.75)`.
    static func spring(_ time: Double) -> Double {
        guard time > 0 else { return 0 }
        let omega = 2 * Double.pi / Config.springResponse, zeta = Config.springDamping
        let damped = omega * (1 - zeta * zeta).squareRoot()
        return 1 - exp(-zeta * omega * time) * (cos(damped * time) + zeta * omega / damped * sin(damped * time))
    }

    /// `[glyph][color]` images of `Text(glyph).font(.system(size: 12))`.
    static func glyphImages(scale: CGFloat) -> [[(CGImage, CGSize)?]] {
        Config.glyphs.map { glyph in
            Config.colors.map { color in
                let text = NSAttributedString(string: glyph, attributes: [
                    .font: NSFont.systemFont(ofSize: Config.size), .foregroundColor: color])
                let measured = text.size()
                let size = CGSize(width: ceil(measured.width), height: ceil(measured.height))
                guard let context = CGContext(data: nil, width: Int(size.width * scale), height: Int(size.height * scale),
                    bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
                context.scaleBy(x: scale, y: scale)
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
                text.draw(at: NSPoint(x: (size.width - measured.width) / 2, y: (size.height - measured.height) / 2))
                NSGraphicsContext.restoreGraphicsState()
                return context.makeImage().map { ($0, size) }
            }
        }
    }
}
