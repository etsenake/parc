import QuartzCore

enum TaffyStretch {
    static let reach: CGFloat = 36
    static let resistance: CGFloat = 0.55

    static func pull(_ drag: CGVector) -> CGVector {
        let slop = StartPageMarkGestureRecognizer.slop
        let length = hypot(drag.dx, drag.dy)
        guard length > slop else { return CGVector(dx: 0, dy: 0) }
        let scale = (length - slop) / length
        return CGVector(dx: drag.dx * scale, dy: drag.dy * scale)
    }

    static func elongation(_ distance: CGFloat) -> CGFloat {
        guard distance > 0 else { return 0 }
        return reach * (1 - 1 / (1 + resistance * distance / reach))
    }

    static func transform(pull: CGVector, size: CGSize, anchor: CGPoint, yDown: Bool) -> CATransform3D {
        let distance = hypot(pull.dx, pull.dy)
        guard distance > 0, size.width > 0, size.height > 0 else { return CATransform3DIdentity }
        let ux = pull.dx / distance, uy = (yDown ? pull.dy : -pull.dy) / distance
        let stretch = elongation(distance)
        let along = 1 + stretch / (abs(ux) * size.width + abs(uy) * size.height)
        let across = 1 / along.squareRoot()
        let a = along * ux * ux + across * uy * uy
        let b = (along - across) * ux * uy
        let d = along * uy * uy + across * ux * ux
        let cx = (0.5 - anchor.x) * size.width, cy = (0.5 - anchor.y) * size.height
        var result = CATransform3DIdentity
        result.m11 = a; result.m12 = b; result.m21 = b; result.m22 = d
        result.m41 = cx - (a * cx + b * cy) + ux * stretch / 2
        result.m42 = cy - (b * cx + d * cy) + uy * stretch / 2
        return result
    }

    static func blend(_ stretched: CATransform3D, _ amount: CGFloat) -> CATransform3D {
        var result = CATransform3DIdentity
        result.m11 = 1 + (stretched.m11 - 1) * amount
        result.m12 = stretched.m12 * amount
        result.m21 = stretched.m21 * amount
        result.m22 = 1 + (stretched.m22 - 1) * amount
        result.m41 = stretched.m41 * amount
        result.m42 = stretched.m42 * amount
        return result
    }
}

enum TaffySpring {
    static let response = 0.42
    static let dampingRatio = 0.3
    static let spring = StartPageMarkSpring(response: response, dampingRatio: dampingRatio)
}

@MainActor
struct TaffyAnimator {
    static let key = "parc.start-page-mark.taffy"

    func track(_ pull: CGVector, stage: CALayer) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        stage.removeAnimation(forKey: Self.key)
        stage.transform = Self.stretch(pull, stage: stage)
        CATransaction.commit()
    }

    func play(from pull: CGVector, stage: CALayer, completion: @escaping @MainActor () -> Void) {
        let stretched = Self.stretch(pull, stage: stage)
        let samples = TaffySpring.spring.samples()
        let animation = CAKeyframeAnimation(keyPath: "transform")
        animation.values = samples.map { NSValue(caTransform3D: TaffyStretch.blend(stretched, CGFloat($0))) }
        animation.duration = Double(samples.count - 1) / StartPageMarkSpring.sampleRate
        animation.calculationMode = .linear
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        CATransaction.setCompletionBlock { MainActor.assumeIsolated { completion() } }
        stage.transform = CATransform3DIdentity
        stage.add(animation, forKey: Self.key)
        CATransaction.commit()
    }

    func reset(stage: CALayer) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        stage.removeAnimation(forKey: Self.key)
        stage.transform = CATransform3DIdentity
        CATransaction.commit()
    }

    private static func stretch(_ pull: CGVector, stage: CALayer) -> CATransform3D {
        TaffyStretch.transform(pull: pull, size: stage.bounds.size, anchor: stage.anchorPoint,
                               yDown: stage.superlayer?.contentsAreFlipped() ?? true)
    }
}
