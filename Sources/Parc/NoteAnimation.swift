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
    static let glide = highlight
    static let check = press
    static let tile = panel
    static let bounce = NoteSpring(response: 0.7, damping: 0.9)
    static let pill = NoteSpring(response: 0.25, damping: 0.8)
    static let tracking = NoteSpring(response: 0.35, damping: 0.87)
    static let open = NoteSpring(response: 0.25, damping: 0.9)
    static let close = NoteSpring(response: 0.15, damping: 0.95)
    static let lift = NoteSpring(response: 0.3, damping: 0.95)
    static let flyoutOpen = NoteSpring(response: 0.36, damping: 0.82)
    static let flyoutClose = NoteSpring(response: 0.28, damping: 0.85)

    var angularFrequency: Double { 2 * Double.pi / Double(response) }
    var stiffness: Double { angularFrequency * angularFrequency }
    var dampingCoefficient: Double { 2 * Double(damping) * angularFrequency }

    var settlingDuration: CFTimeInterval {
        let probe = CASpringAnimation()
        probe.mass = 1
        probe.stiffness = stiffness
        probe.damping = dampingCoefficient
        return probe.settlingDuration
    }

    func progress(at time: CFTimeInterval) -> CGFloat {
        guard time > 0 else { return 0 }
        let omega = angularFrequency
        let zeta = Double(damping)
        if zeta < 1 {
            let damped = omega * (1 - zeta * zeta).squareRoot()
            let envelope = exp(-zeta * omega * time)
            return CGFloat(1 - envelope * (cos(damped * time) + zeta * omega / damped * sin(damped * time)))
        }
        return CGFloat(1 - exp(-omega * time) * (1 + omega * time))
    }
}

enum NoteCurve {
    static var hud: CAMediaTimingFunction { CAMediaTimingFunction(controlPoints: 0.215, 0.61, 0.355, 1) }
    static var hover: CAMediaTimingFunction { CAMediaTimingFunction(controlPoints: 0.42, 0, 1, 1) }
    static var easeOut: CAMediaTimingFunction { CAMediaTimingFunction(name: .easeOut) }
    static var easeInOut: CAMediaTimingFunction { CAMediaTimingFunction(name: .easeInEaseOut) }
    static var tooltip: CAMediaTimingFunction { CAMediaTimingFunction(controlPoints: 0, 0, 0.58, 1) }
    static var sidebar: CAMediaTimingFunction { CAMediaTimingFunction(controlPoints: 0.25, 0.46, 0.45, 0.94) }
}

@MainActor
final class NoteAnimationToken {
    let generation: Int
    private weak var layer: CALayer?
    private let key: String

    init(layer: CALayer, key: String, generation: Int) {
        self.layer = layer
        self.key = key
        self.generation = generation
    }

    var isCurrent: Bool {
        guard let layer else { return false }
        return NoteAnimation.generation(of: layer, key: key) == generation
    }
}

private final class NoteAnimationCompletion: NSObject, CAAnimationDelegate {
    let body: (Bool) -> Void
    init(_ body: @escaping (Bool) -> Void) { self.body = body }
    func animationDidStop(_ animation: CAAnimation, finished: Bool) {
        MainActor.assumeIsolated { body(finished) }
    }
}

@MainActor
private final class NoteReduceMotionObserver {
    static let shared = NoteReduceMotionObserver()
    private var handlers: [(owner: () -> AnyObject?, handler: @MainActor () -> Void)] = []
    private var observer: NSObjectProtocol?
    private var wasReduced = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

    func add(_ owner: AnyObject, _ handler: @escaping @MainActor () -> Void) {
        handlers.removeAll { $0.owner() == nil }
        handlers.append(({ [weak owner] in owner }, handler))
        guard observer == nil else { return }
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { NoteReduceMotionObserver.shared.changed() }
        }
    }

    private func changed() {
        let reduced = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        defer { wasReduced = reduced }
        guard reduced, !wasReduced else { return }
        handlers.removeAll { $0.owner() == nil }
        for entry in handlers { entry.handler() }
    }
}

@MainActor
enum NoteAnimation {
    static var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    nonisolated static let hudHiddenScale: CGFloat = 0.95
    nonisolated static let hudOpenDuration: CFTimeInterval = 0.1
    nonisolated static let hudFadeDuration: CFTimeInterval = 0.05
    nonisolated static let hudCloseDuration: CFTimeInterval = 0.07
    nonisolated static let hoverDuration: CFTimeInterval = 0.1
    nonisolated static let insertDuration: CFTimeInterval = 0.2
    nonisolated static let removeDuration: CFTimeInterval = 0.15
    nonisolated static let revealDuration: CFTimeInterval = 0.2
    nonisolated static let reducedFadeDuration: CFTimeInterval = 0.15
    nonisolated static let insertRise: CGFloat = 4
    nonisolated static let pressedScale: CGFloat = 0.95
    nonisolated static let rowPressedScale: CGFloat = 0.992
    nonisolated static let checkPopScale: CGFloat = 0.85
    nonisolated static let liftScale: CGFloat = 1.02

    nonisolated static let keyPrefix = "parc.note."
    nonisolated static let fadeKey = keyPrefix + "fade"
    nonisolated static let popKey = keyPrefix + "pop"
    nonisolated static let hudTransformKey = keyPrefix + "hud.transform"
    nonisolated static let hudOpacityKey = keyPrefix + "hud.opacity"
    nonisolated static let positionKey = keyPrefix + "position"
    nonisolated static let boundsKey = keyPrefix + "bounds"
    nonisolated static let shadowPathKey = keyPrefix + "shadowPath"
    nonisolated static let revealKey = keyPrefix + "reveal"
    nonisolated static let riseKey = keyPrefix + "rise"

    static func spring(_ keyPath: String, _ spring: NoteSpring, from: Any?, to: Any?) -> CASpringAnimation {
        let animation = CASpringAnimation(keyPath: keyPath)
        animation.mass = 1
        animation.stiffness = spring.stiffness
        animation.damping = spring.dampingCoefficient
        animation.fromValue = from
        animation.toValue = to
        animation.duration = animation.settlingDuration
        return animation
    }

    static func basic(_ keyPath: String, from: Any?, to: Any?, duration: CFTimeInterval,
                      curve: CAMediaTimingFunction = NoteCurve.easeOut) -> CABasicAnimation {
        let animation = CABasicAnimation(keyPath: keyPath)
        animation.fromValue = from
        animation.toValue = to
        animation.duration = duration
        animation.timingFunction = curve
        return animation
    }

    static func withoutAnimation(_ body: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        body()
        CATransaction.commit()
    }

    static func generation(of layer: CALayer, key: String) -> Int {
        layer.value(forKey: keyPrefix + "generation." + key) as? Int ?? 0
    }

    @discardableResult
    static func advanceGeneration(of layer: CALayer, key: String) -> NoteAnimationToken {
        let next = generation(of: layer, key: key) + 1
        layer.setValue(next, forKey: keyPrefix + "generation." + key)
        return NoteAnimationToken(layer: layer, key: key, generation: next)
    }

    static func run(_ animation: CAAnimation, on layer: CALayer, key: String,
                    completion: ((Bool) -> Void)? = nil) -> NoteAnimationToken {
        let token = advanceGeneration(of: layer, key: key)
        if let completion {
            animation.delegate = NoteAnimationCompletion { finished in
                guard token.isCurrent else { return }
                completion(finished)
            }
        }
        layer.add(animation, forKey: key)
        return token
    }

    static func animate(_ layer: CALayer, _ keyPath: String, to value: Any, spring: NoteSpring, key: String? = nil) {
        self.spring(layer, keyPath, to: value, spring: spring, key: key)
    }

    @discardableResult
    static func spring(_ layer: CALayer, _ keyPath: String, to value: Any, spring: NoteSpring, key: String? = nil,
                       completion: (() -> Void)? = nil) -> NoteAnimationToken {
        let key = key ?? keyPrefix + keyPath
        let current = layer.presentation()?.value(forKeyPath: keyPath) ?? layer.value(forKeyPath: keyPath)
        withoutAnimation { layer.setValue(value, forKeyPath: keyPath) }
        guard !reduceMotion, let current, !(current as AnyObject).isEqual(value) else {
            layer.removeAnimation(forKey: key)
            let token = advanceGeneration(of: layer, key: key)
            completion?()
            return token
        }
        return run(self.spring(keyPath, spring, from: current, to: value), on: layer, key: key) { _ in completion?() }
    }

    static func fade(_ view: NSView, visible: Bool, duration: CFTimeInterval = 0.12, completion: (() -> Void)? = nil) {
        view.wantsLayer = true
        guard let layer = view.layer else { view.alphaValue = visible ? 1 : 0; completion?(); return }
        fade(layer, to: visible ? 1 : 0, duration: duration, completion: completion)
        withoutAnimation { view.alphaValue = visible ? 1 : 0 }
    }

    @discardableResult
    static func fade(_ layer: CALayer, to opacity: Float, duration: CFTimeInterval = 0.12,
                     curve: CAMediaTimingFunction = NoteCurve.easeOut, key: String = fadeKey,
                     completion: (() -> Void)? = nil) -> NoteAnimationToken {
        let from = layer.presentation()?.opacity ?? layer.opacity
        withoutAnimation { layer.opacity = opacity }
        let length = reduceMotion ? min(duration, reducedFadeDuration) : duration
        guard length > 0, from != opacity else {
            layer.removeAnimation(forKey: key)
            let token = advanceGeneration(of: layer, key: key)
            completion?()
            return token
        }
        return run(basic("opacity", from: from, to: opacity, duration: length, curve: curve), on: layer, key: key) { _ in
            completion?()
        }
    }

    static func scaleTransform(_ scale: CGFloat, about point: CGPoint) -> CATransform3D {
        var transform = CATransform3DMakeTranslation(point.x, point.y, 0)
        transform = CATransform3DScale(transform, scale, scale, 1)
        return CATransform3DTranslate(transform, -point.x, -point.y, 0)
    }

    static func layerCenter(_ layer: CALayer) -> CGPoint {
        CGPoint(x: layer.bounds.width * (0.5 - layer.anchorPoint.x), y: layer.bounds.height * (0.5 - layer.anchorPoint.y))
    }

    static func layerPoint(_ point: NSPoint, in view: NSView) -> CGPoint {
        let superFlipped = view.superview?.isFlipped ?? view.isFlipped
        return CGPoint(x: point.x, y: superFlipped == view.isFlipped ? point.y : view.bounds.height - point.y)
    }

    @discardableResult
    static func pop(_ view: NSView, from scale: CGFloat = checkPopScale, spring: NoteSpring = .check,
                    about point: NSPoint? = nil) -> NoteAnimationToken? {
        view.wantsLayer = true
        guard let layer = view.layer else { return nil }
        let center = layerPoint(point ?? NSPoint(x: view.bounds.midX, y: view.bounds.midY), in: view)
        return pop(layer, from: scale, spring: spring, about: center)
    }

    @discardableResult
    static func pop(_ layer: CALayer, from scale: CGFloat = checkPopScale, spring: NoteSpring = .check,
                    about point: CGPoint? = nil) -> NoteAnimationToken {
        let center = point ?? layerCenter(layer)
        guard !reduceMotion else {
            layer.removeAnimation(forKey: popKey)
            return advanceGeneration(of: layer, key: popKey)
        }
        let animation = self.spring("transform", spring,
                                    from: NSValue(caTransform3D: scaleTransform(scale, about: center)),
                                    to: NSValue(caTransform3D: CATransform3DIdentity))
        animation.isAdditive = false
        return run(animation, on: layer, key: popKey)
    }

    @discardableResult
    static func springScale(_ layer: CALayer, to scale: CGFloat, spring: NoteSpring = .press,
                            key: String = keyPrefix + "scale") -> NoteAnimationToken {
        self.spring(layer, "transform.scale", to: scale, spring: spring, key: key)
    }

    static func presentHUD(_ view: NSView, about point: NSPoint, completion: (() -> Void)? = nil) {
        view.wantsLayer = true
        guard let layer = view.layer else { completion?(); return }
        let anchor = layerPoint(point, in: view)
        layer.removeAnimation(forKey: hudTransformKey)
        let fromOpacity = layer.presentation()?.opacity ?? 0
        withoutAnimation {
            layer.opacity = 1
            view.alphaValue = 1
        }
        if reduceMotion {
            advanceGeneration(of: layer, key: hudTransformKey)
            _ = run(basic("opacity", from: fromOpacity, to: 1, duration: hudFadeDuration, curve: NoteCurve.hud),
                    on: layer, key: hudOpacityKey) { _ in completion?() }
            return
        }
        let presented = layer.presentation()?.transform
        let start = presented.flatMap { CATransform3DIsIdentity($0) ? nil : $0 } ?? scaleTransform(hudHiddenScale, about: anchor)
        _ = run(basic("transform", from: NSValue(caTransform3D: start), to: NSValue(caTransform3D: CATransform3DIdentity),
                      duration: hudOpenDuration, curve: NoteCurve.hud), on: layer, key: hudTransformKey) { _ in completion?() }
        _ = run(basic("opacity", from: fromOpacity == 1 ? 0 : fromOpacity, to: 1, duration: hudFadeDuration, curve: NoteCurve.hud),
                on: layer, key: hudOpacityKey)
    }

    static func dismissHUD(_ view: NSView, about point: NSPoint, completion: @escaping () -> Void) {
        view.wantsLayer = true
        guard let layer = view.layer else { completion(); return }
        let anchor = layerPoint(point, in: view)
        let current = layer.presentation()
        let fromOpacity = current?.opacity ?? layer.opacity
        let fromTransform = current?.transform ?? CATransform3DIdentity
        withoutAnimation { layer.opacity = 0 }
        if reduceMotion {
            advanceGeneration(of: layer, key: hudTransformKey)
            layer.removeAnimation(forKey: hudTransformKey)
            _ = run(basic("opacity", from: fromOpacity, to: 0, duration: hudCloseDuration, curve: NoteCurve.hud),
                    on: layer, key: hudOpacityKey) { _ in completion() }
            return
        }
        let transform = basic("transform", from: NSValue(caTransform3D: fromTransform),
                              to: NSValue(caTransform3D: scaleTransform(hudHiddenScale, about: anchor)),
                              duration: hudCloseDuration, curve: NoteCurve.hud)
        transform.fillMode = .forwards
        transform.isRemovedOnCompletion = false
        _ = run(transform, on: layer, key: hudTransformKey)
        _ = run(basic("opacity", from: fromOpacity, to: 0, duration: hudCloseDuration, curve: NoteCurve.hud),
                on: layer, key: hudOpacityKey) { _ in completion() }
    }

    static func cancelHUD(_ view: NSView) {
        guard let layer = view.layer else { return }
        advanceGeneration(of: layer, key: hudTransformKey)
        advanceGeneration(of: layer, key: hudOpacityKey)
        layer.removeAnimation(forKey: hudTransformKey)
        layer.removeAnimation(forKey: hudOpacityKey)
        withoutAnimation { layer.opacity = 1 }
    }

    @discardableResult
    static func slide(_ view: NSView, to frame: NSRect, spring: NoteSpring = .reorder,
                      completion: (() -> Void)? = nil) -> NoteAnimationToken? {
        view.wantsLayer = true
        guard let layer = view.layer else { view.frame = frame; completion?(); return nil }
        let presentation = layer.presentation()
        let fromPosition = presentation?.position ?? layer.position
        let fromBounds = presentation?.bounds ?? layer.bounds
        withoutAnimation { view.frame = frame }
        guard !reduceMotion, view.window != nil || layer.superlayer != nil else {
            settle(layer, keys: [positionKey, boundsKey])
            completion?()
            return nil
        }
        var token: NoteAnimationToken?
        if fromPosition != layer.position {
            token = run(self.spring("position", spring, from: NSValue(point: fromPosition), to: NSValue(point: layer.position)),
                        on: layer, key: positionKey) { _ in completion?() }
        } else {
            layer.removeAnimation(forKey: positionKey)
        }
        if fromBounds.size != layer.bounds.size {
            let boundsToken = run(self.spring("bounds", spring, from: NSValue(rect: fromBounds), to: NSValue(rect: layer.bounds)),
                                  on: layer, key: boundsKey) { _ in if token == nil { completion?() } }
            token = token ?? boundsToken
        } else {
            layer.removeAnimation(forKey: boundsKey)
        }
        if token == nil { completion?() }
        return token
    }

    static func slideLayer(_ layer: CALayer, to frame: CGRect, spring: NoteSpring = .reorder) {
        let presentation = layer.presentation()
        let fromPosition = presentation?.position ?? layer.position
        let fromBounds = presentation?.bounds ?? layer.bounds
        withoutAnimation { layer.frame = frame }
        guard !reduceMotion else { settle(layer, keys: [positionKey, boundsKey]); return }
        if fromPosition != layer.position {
            _ = run(self.spring("position", spring, from: NSValue(point: fromPosition), to: NSValue(point: layer.position)),
                    on: layer, key: positionKey)
        }
        if fromBounds != layer.bounds {
            _ = run(self.spring("bounds", spring, from: NSValue(rect: fromBounds), to: NSValue(rect: layer.bounds)),
                    on: layer, key: boundsKey)
        }
    }

    static func offsetSlide(_ view: NSView, from offset: CGSize, spring: NoteSpring = .reorder) {
        view.wantsLayer = true
        guard let layer = view.layer, !reduceMotion, offset != .zero else { return }
        let shift = CATransform3DMakeTranslation(offset.width, offset.height, 0)
        let animation = self.spring("transform", spring, from: NSValue(caTransform3D: shift),
                                    to: NSValue(caTransform3D: CATransform3DIdentity))
        _ = run(animation, on: layer, key: positionKey)
    }

    static func insert(_ view: NSView, completion: (() -> Void)? = nil) {
        view.wantsLayer = true
        guard let layer = view.layer else { completion?(); return }
        withoutAnimation { layer.opacity = 1; view.alphaValue = 1 }
        let fade = basic("opacity", from: 0, to: 1, duration: reduceMotion ? reducedFadeDuration : insertDuration)
        _ = run(fade, on: layer, key: fadeKey) { _ in completion?() }
        guard !reduceMotion else { return }
        let down = view.superview?.isFlipped == true ? insertRise : -insertRise
        let rise = basic("transform", from: NSValue(caTransform3D: CATransform3DMakeTranslation(0, down, 0)),
                         to: NSValue(caTransform3D: CATransform3DIdentity), duration: insertDuration)
        _ = run(rise, on: layer, key: riseKey)
    }

    static func remove(_ view: NSView, completion: @escaping () -> Void) {
        view.wantsLayer = true
        guard let layer = view.layer else { completion(); return }
        fade(layer, to: 0, duration: removeDuration, completion: completion)
    }

    static func reveal(_ view: NSView, expanded: Bool, fullHeight: CGFloat, completion: (() -> Void)? = nil) {
        view.wantsLayer = true
        guard let layer = view.layer else { completion?(); return }
        layer.masksToBounds = true
        let duration = reduceMotion ? reducedFadeDuration : revealDuration
        fade(layer, to: expanded ? 1 : 0, duration: duration, key: revealKey + ".opacity", completion: completion)
        guard !reduceMotion else { return }
        let presentation = layer.presentation()?.bounds ?? layer.bounds
        let target = CGRect(x: 0, y: 0, width: layer.bounds.width, height: expanded ? fullHeight : 0)
        let from = CGRect(x: 0, y: 0, width: layer.bounds.width, height: expanded ? min(presentation.height, fullHeight) : presentation.height)
        let start = expanded && presentation.height >= fullHeight ? CGRect(x: 0, y: 0, width: layer.bounds.width, height: 0) : from
        let animation = basic("bounds", from: NSValue(rect: start), to: NSValue(rect: target), duration: duration, curve: NoteCurve.easeOut)
        _ = run(animation, on: layer, key: revealKey)
    }

    static func lift(_ layer: CALayer, lifted: Bool) {
        let target = lifted ? scaleTransform(liftScale, about: layerCenter(layer)) : CATransform3DIdentity
        spring(layer, "transform", to: NSValue(caTransform3D: target), spring: .lift, key: keyPrefix + "lift")
        spring(layer, "shadowOpacity", to: Float(lifted ? 0.18 : 0), spring: .lift, key: keyPrefix + "lift.shadow")
    }

    static func settle(_ view: NSView) {
        if let layer = view.layer { settle(layer) }
        view.subviews.forEach(settle)
    }

    static func settle(_ layer: CALayer) {
        for key in layer.animationKeys() ?? [] where key.hasPrefix(keyPrefix) || key.hasPrefix("note.") {
            layer.removeAnimation(forKey: key)
        }
        layer.sublayers?.forEach(settle)
    }

    static func settle(_ layer: CALayer, keys: [String]) {
        for key in keys {
            advanceGeneration(of: layer, key: key)
            layer.removeAnimation(forKey: key)
        }
    }

    static func observeReduceMotion(_ owner: AnyObject, settle handler: @escaping @MainActor () -> Void) {
        NoteReduceMotionObserver.shared.add(owner, handler)
    }
}
