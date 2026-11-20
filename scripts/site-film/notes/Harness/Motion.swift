import AppKit
import ObjectiveC
import QuartzCore

@MainActor final class FilmMotion {
    static let shared = FilmMotion()

    final class Entry {
        let key: String
        let animation: CAAnimation
        let start: Double
        var from: Any?
        var to: Any?
        var notified = false
        var snapshot: CGImage?
        init(key: String, animation: CAAnimation, start: Double) {
            self.key = key; self.animation = animation; self.start = start
        }
    }

    final class Track {
        weak var layer: CALayer?
        var entries: [Entry] = []
        init(_ layer: CALayer) { self.layer = layer }
    }

    var now: Double = 0
    var tracks: [ObjectIdentifier: Track] = [:]
    var stops: [(CAAnimation, Bool)] = []
    var previous: [ObjectIdentifier: [String: Any]] = [:]
    var saved: [(CALayer, String, Any?)] = []
    var overlays: [CALayer] = []
    var history: [String] = []
    private var counter = 0

    static let copiedKeys = ["bounds", "position", "anchorPoint", "zPosition", "transform", "sublayerTransform", "opacity",
                             "backgroundColor", "borderColor", "borderWidth", "cornerRadius", "shadowOpacity", "shadowRadius",
                             "shadowOffset", "shadowColor", "shadowPath", "hidden", "contentsRect", "masksToBounds"]
    static let shapeKeys = ["path", "fillColor", "strokeColor", "lineWidth", "strokeStart", "strokeEnd"]

    func install() {
        let cls: AnyClass = CALayer.self
        func swap<T>(_ name: String, _ block: T) -> IMP? {
            guard let method = class_getInstanceMethod(cls, NSSelectorFromString(name)) else { fatalError("no \(name)") }
            return method_setImplementation(method, imp_implementationWithBlock(block))
        }
        typealias Add = @convention(c) (CALayer, Selector, CAAnimation, NSString?) -> Void
        typealias Action = @convention(c) (CALayer, Selector, NSString) -> CAAction?
        let add: @convention(block) (CALayer, CAAnimation, NSString?) -> Void = { layer, animation, key in
            MainActor.assumeIsolated { FilmMotion.shared.add(animation, key: key as String?, to: layer) }
        }
        _ = swap("addAnimation:forKey:", add)
        let remove: @convention(block) (CALayer, NSString) -> Void = { layer, key in
            MainActor.assumeIsolated { FilmMotion.shared.remove(key as String, from: layer) }
        }
        _ = swap("removeAnimationForKey:", remove)
        let removeAll: @convention(block) (CALayer) -> Void = { layer in
            MainActor.assumeIsolated { FilmMotion.shared.removeAll(from: layer) }
        }
        _ = swap("removeAllAnimations", removeAll)
        let lookup: @convention(block) (CALayer, NSString) -> CAAnimation? = { layer, key in
            MainActor.assumeIsolated { FilmMotion.shared.track(layer)?.entries.last { $0.key == key as String }?.animation }
        }
        _ = swap("animationForKey:", lookup)
        let keys: @convention(block) (CALayer) -> NSArray? = { layer in
            MainActor.assumeIsolated {
                guard let entries = FilmMotion.shared.track(layer)?.entries, !entries.isEmpty else { return nil }
                return entries.map(\.key) as NSArray
            }
        }
        _ = swap("animationKeys", keys)
        let presentation: @convention(block) (CALayer) -> CALayer? = { layer in
            MainActor.assumeIsolated { FilmMotion.shared.presentation(of: layer) }
        }
        _ = swap("presentationLayer", presentation)
        var actionIMP: IMP?
        let action: @convention(block) (CALayer, NSString) -> CAAction? = { layer, key in
            MainActor.assumeIsolated {
                if !FilmMotion.isStructural(key as String), let value = FilmMotion.shared.current(layer, key as String) {
                    FilmMotion.shared.previous[ObjectIdentifier(layer), default: [:]][key as String] = value
                }
            }
            return unsafeBitCast(actionIMP!, to: Action.self)(layer, NSSelectorFromString("actionForKey:"), key)
        }
        actionIMP = swap("actionForKey:", action)
    }

    static func isStructural(_ key: String) -> Bool {
        ["onOrderIn", "onOrderOut", "sublayers", "contents", "onLayout", "kCAOnOrderIn", "kCAOnOrderOut", "kCATransition"].contains(key)
    }

    func track(_ layer: CALayer) -> Track? { tracks[ObjectIdentifier(layer)].flatMap { $0.layer === layer ? $0 : nil } }

    func add(_ original: CAAnimation, key: String?, to layer: CALayer) {
        guard let animation = original.copy() as? CAAnimation else { return }
        counter += 1
        let name = key ?? "film.anonymous.\(counter)"
        let id = ObjectIdentifier(layer)
        if tracks[id]?.layer !== layer { tracks[id] = Track(layer) }
        let track = tracks[id]!
        var delay = 0.0
        if animation.beginTime > 0 { delay = animation.beginTime - CACurrentMediaTime() }
        let entry = Entry(key: name, animation: animation, start: now + max(0, delay))
        if let basic = animation as? CABasicAnimation, let path = basic.keyPath { resolve(entry, basic, path, layer) }
        if animation is CATransition, let view = layer.delegate as? NSView { entry.snapshot = Self.snapshot(view) }
        if let index = track.entries.firstIndex(where: { $0.key == name }) {
            let replaced = track.entries.remove(at: index)
            if !replaced.notified { stops.append((replaced.animation, false)) }
        }
        track.entries.append(entry)
        history.append(String(format: "%.3f add %@ %@ on %@", now, name, describe(animation), String(describing: type(of: layer))))
    }

    private func resolve(_ entry: Entry, _ basic: CABasicAnimation, _ path: String, _ layer: CALayer) {
        let model = layer.value(forKeyPath: path)
        let base = current(layer, path, excluding: entry.key) ?? model
        switch (basic.fromValue, basic.toValue, basic.byValue) {
        case let (from?, to?, _): entry.from = from; entry.to = to
        case let (from?, nil, by?): entry.from = from; entry.to = Self.add(from, by)
        case let (nil, to?, by?): entry.from = Self.subtract(to, by); entry.to = to
        case let (from?, nil, nil): entry.from = from; entry.to = model
        case let (nil, to?, nil): entry.from = base; entry.to = to
        case let (nil, nil, by?): entry.from = base; entry.to = base.flatMap { Self.add($0, by) }
        default:
            entry.from = previous[ObjectIdentifier(layer)]?[path] ?? model
            entry.to = model
        }
        if basic.isAdditive { entry.from = basic.fromValue ?? entry.from; entry.to = basic.toValue ?? entry.to }
    }

    func remove(_ key: String, from layer: CALayer) {
        guard let track = track(layer) else { return }
        for entry in track.entries where entry.key == key && !entry.notified { stops.append((entry.animation, false)) }
        track.entries.removeAll { $0.key == key }
    }

    func removeAll(from layer: CALayer) {
        guard let track = track(layer) else { return }
        for entry in track.entries where !entry.notified { stops.append((entry.animation, false)) }
        track.entries.removeAll()
    }

    func describe(_ animation: CAAnimation) -> String {
        if let spring = animation as? CASpringAnimation {
            return "spring(\(spring.keyPath ?? "?") k=\(Int(spring.stiffness)) c=\(String(format: "%.1f", spring.damping)) d=\(String(format: "%.2f", spring.duration)))"
        }
        if let basic = animation as? CABasicAnimation { return "basic(\(basic.keyPath ?? "?") d=\(String(format: "%.2f", basic.duration)))" }
        if let frames = animation as? CAKeyframeAnimation { return "keyframes(\(frames.keyPath ?? "?") d=\(frames.duration))" }
        if animation is CAAnimationGroup { return "group(d=\(animation.duration))" }
        return String(describing: type(of: animation))
    }

    static func duration(_ animation: CAAnimation) -> Double {
        let base = animation.duration > 0 ? animation.duration : 0.25
        let repeats = animation.repeatCount > 0 ? Double(animation.repeatCount) : 1
        return base * repeats * (animation.autoreverses ? 2 : 1) / Double(max(0.0001, animation.speed))
    }

    func advance() {
        for track in tracks.values {
            guard track.layer != nil else { track.entries.removeAll(); continue }
            var keep: [Entry] = []
            for entry in track.entries {
                let end = entry.start + Self.duration(entry.animation)
                if now >= end - 1e-9 {
                    if !entry.notified { entry.notified = true; stops.append((entry.animation, true)) }
                    if !entry.animation.isRemovedOnCompletion { keep.append(entry) }
                } else {
                    keep.append(entry)
                }
            }
            track.entries = keep
        }
        tracks = tracks.filter { $0.value.layer != nil }
        deliverStops()
    }

    func deliverStops() {
        var guardCount = 0
        while !stops.isEmpty && guardCount < 50 {
            guardCount += 1
            let batch = stops
            stops.removeAll()
            for (animation, finished) in batch {
                animation.delegate?.animationDidStop?(animation, finished: finished)
            }
        }
    }

    var isAnimating: Bool { tracks.values.contains { !$0.entries.isEmpty } }

    func current(_ layer: CALayer, _ path: String, excluding: String? = nil) -> Any? {
        var value: Any? = layer.value(forKeyPath: path)
        guard let track = track(layer) else { return value }
        for entry in track.entries where entry.key != excluding {
            if let next = evaluate(entry, path: path, base: value, layer: layer) { value = next }
        }
        return value
    }

    func paths(_ layer: CALayer) -> [String] {
        guard let track = track(layer) else { return [] }
        var result: [String] = []
        for entry in track.entries { for path in Self.keyPaths(entry.animation) where !result.contains(path) { result.append(path) } }
        return result
    }

    static func keyPaths(_ animation: CAAnimation) -> [String] {
        if let group = animation as? CAAnimationGroup { return (group.animations ?? []).flatMap(keyPaths) }
        if let property = animation as? CAPropertyAnimation, let path = property.keyPath { return [path] }
        return []
    }

    func presentation(of layer: CALayer) -> CALayer? {
        let animated = paths(layer)
        guard !animated.isEmpty else { return nil }
        let copy = type(of: layer).init(layer: layer)
        var keys = Self.copiedKeys
        if layer is CAShapeLayer { keys += Self.shapeKeys }
        NoteAnimation.withoutAnimation {
            for key in keys { copy.setValue(layer.value(forKey: key), forKey: key) }
            for path in animated { copy.setValue(current(layer, path), forKeyPath: path) }
        }
        return copy
    }

    static func snapshot(_ view: NSView) -> CGImage? {
        let size = view.bounds.size
        guard size.width >= 1, size.height >= 1,
              let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(ceil(size.width * 2)), pixelsHigh: Int(ceil(size.height * 2)),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        rep.size = size
        view.effectiveAppearance.performAsCurrentDrawingAppearance { view.cacheDisplay(in: view.bounds, to: rep) }
        return rep.cgImage
    }

    func applyTransitions() {
        for track in tracks.values {
            guard let layer = track.layer, let superlayer = layer.superlayer else { continue }
            for entry in track.entries {
                guard let transition = entry.animation as? CATransition, transition.type == .fade, let snapshot = entry.snapshot else { continue }
                let local = now - entry.start, span = Self.duration(transition)
                guard local >= 0, local < span else { continue }
                let progress = Float(Self.timing(transition.timingFunction, local / span))
                let opacity = layer.opacity
                saved.append((layer, "opacity", NSNumber(value: opacity)))
                layer.opacity = opacity * progress
                let overlay = CALayer()
                overlay.contents = snapshot
                overlay.contentsScale = 2
                overlay.frame = layer.frame
                overlay.opacity = opacity * (1 - progress)
                superlayer.insertSublayer(overlay, above: layer)
                overlays.append(overlay)
            }
        }
    }

    func apply(in root: CALayer?) {
        saved.removeAll()
        NoteAnimation.withoutAnimation { applyTransitions() }
        NoteAnimation.withoutAnimation {
            for track in tracks.values {
                guard let layer = track.layer, !track.entries.isEmpty else { continue }
                if let root, !Self.isDescendant(layer, of: root) { continue }
                for path in paths(layer) {
                    let model = layer.value(forKeyPath: path)
                    guard let value = current(layer, path) else { continue }
                    saved.append((layer, path, model))
                    layer.setValue(value, forKeyPath: path)
                }
            }
        }
    }

    func restore() {
        NoteAnimation.withoutAnimation {
            for overlay in overlays { overlay.removeFromSuperlayer() }
            for (layer, path, model) in saved.reversed() { layer.setValue(model, forKeyPath: path) }
        }
        overlays.removeAll()
        saved.removeAll()
    }

    static func isDescendant(_ layer: CALayer, of root: CALayer) -> Bool {
        var cursor: CALayer? = layer
        while let current = cursor { if current === root { return true }; cursor = current.superlayer }
        return false
    }

    func evaluate(_ entry: Entry, path: String, base: Any?, layer: CALayer) -> Any? {
        evaluate(entry.animation, entry: entry, local: now - entry.start, path: path, base: base)
    }

    private func evaluate(_ animation: CAAnimation, entry: Entry?, local: Double, path: String, base: Any?) -> Any? {
        let total = Self.duration(animation)
        let fill = animation.fillMode
        var time = local
        if time < 0 {
            guard fill == .backwards || fill == .both else { return nil }
            time = 0
        }
        if time > total {
            guard fill == .forwards || fill == .both || !animation.isRemovedOnCompletion else { return nil }
            time = total
        }
        time *= Double(animation.speed)
        if let group = animation as? CAAnimationGroup {
            var value = base
            for child in group.animations ?? [] where Self.keyPaths(child).contains(path) {
                if let next = evaluate(child, entry: nil, local: time - child.beginTime, path: path, base: value) { value = next }
            }
            return value
        }
        guard let property = animation as? CAPropertyAnimation, property.keyPath == path else { return nil }
        let single = animation.duration > 0 ? animation.duration : 0.25
        var cycle = time
        if animation.repeatCount > 0 || animation.autoreverses {
            let span = single * (animation.autoreverses ? 2 : 1)
            cycle = time >= total ? (animation.autoreverses ? 0 : single) : time.truncatingRemainder(dividingBy: span)
            if animation.autoreverses && cycle > single { cycle = span - cycle }
        }
        var value: Any?
        if let spring = animation as? CASpringAnimation {
            let from = entry?.from ?? spring.fromValue ?? base
            let to = entry?.to ?? spring.toValue ?? base
            let progress = Self.spring(spring, at: min(cycle, single))
            value = Self.interpolate(from, to, progress)
        } else if let basic = animation as? CABasicAnimation {
            let from = entry?.from ?? basic.fromValue ?? base
            let to = entry?.to ?? basic.toValue ?? base
            let fraction = min(1, max(0, cycle / single))
            let eased = Self.timing(basic.timingFunction, fraction)
            value = Self.interpolate(from, to, eased)
        } else if let frames = animation as? CAKeyframeAnimation, let values = frames.values, !values.isEmpty {
            let fraction = min(1, max(0, cycle / single))
            value = Self.keyframe(frames, values, fraction)
        }
        if property.isAdditive, let value, let base { return Self.add(base, value) }
        return value
    }

    static func keyframe(_ frames: CAKeyframeAnimation, _ values: [Any], _ fraction: Double) -> Any? {
        let times = frames.keyTimes?.map { $0.doubleValue } ?? values.indices.map { values.count > 1 ? Double($0) / Double(values.count - 1) : 0 }
        let eased = timing(frames.timingFunction, fraction)
        guard values.count > 1 else { return values.first }
        var index = 0
        while index < times.count - 2 && eased > times[index + 1] { index += 1 }
        let span = max(1e-9, times[index + 1] - times[index])
        var local = min(1, max(0, (eased - times[index]) / span))
        if frames.calculationMode == .discrete { return values[local >= 1 ? index + 1 : index] }
        if let functions = frames.timingFunctions, index < functions.count { local = timing(functions[index], local) }
        return interpolate(values[index], values[index + 1], local)
    }

    static func timing(_ function: CAMediaTimingFunction?, _ x: Double) -> Double {
        guard let function else { return x }
        var a: [Float] = [0, 0], b: [Float] = [0, 0]
        function.getControlPoint(at: 1, values: &a)
        function.getControlPoint(at: 2, values: &b)
        let x1 = Double(a[0]), y1 = Double(a[1]), x2 = Double(b[0]), y2 = Double(b[1])
        func bezier(_ s: Double, _ p1: Double, _ p2: Double) -> Double {
            let u = 1 - s
            return 3 * u * u * s * p1 + 3 * u * s * s * p2 + s * s * s
        }
        var low = 0.0, high = 1.0
        for _ in 0..<50 {
            let mid = (low + high) / 2
            if bezier(mid, x1, x2) < x { low = mid } else { high = mid }
        }
        return bezier((low + high) / 2, y1, y2)
    }

    static func spring(_ spring: CASpringAnimation, at t: Double) -> Double {
        guard t > 0 else { return 0 }
        let mass = Double(spring.mass), stiffness = Double(spring.stiffness), damping = Double(spring.damping)
        let velocity = Double(spring.initialVelocity)
        let omega = (stiffness / mass).squareRoot()
        let zeta = damping / (2 * (stiffness * mass).squareRoot())
        let x: Double
        if zeta < 1 {
            let damped = omega * (1 - zeta * zeta).squareRoot()
            x = exp(-zeta * omega * t) * (cos(damped * t) + (zeta * omega - velocity) / damped * sin(damped * t))
        } else if zeta == 1 {
            x = exp(-omega * t) * (1 + (omega - velocity) * t)
        } else {
            let root = (zeta * zeta - 1).squareRoot()
            let r1 = -omega * (zeta - root), r2 = -omega * (zeta + root)
            let c2 = (-velocity - r1) / (r2 - r1)
            let c1 = 1 - c2
            x = c1 * exp(r1 * t) + c2 * exp(r2 * t)
        }
        return 1 - x
    }

    static func number(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let double = value as? Double { return double }
        if let float = value as? CGFloat { return Double(float) }
        return nil
    }

    static func interpolate(_ from: Any?, _ to: Any?, _ p: Double) -> Any? {
        guard let from, let to else { return p >= 0.5 ? to : from }
        let q = CGFloat(p)
        if let a = number(from), let b = number(to) { return NSNumber(value: a + (b - a) * p) }
        if let a = from as? NSValue, let b = to as? NSValue {
            let type = String(cString: a.objCType)
            if type.hasPrefix("{CGPoint") {
                let x = a.pointValue, y = b.pointValue
                return NSValue(point: NSPoint(x: x.x + (y.x - x.x) * q, y: x.y + (y.y - x.y) * q))
            }
            if type.hasPrefix("{CGSize") {
                let x = a.sizeValue, y = b.sizeValue
                return NSValue(size: NSSize(width: x.width + (y.width - x.width) * q, height: x.height + (y.height - x.height) * q))
            }
            if type.hasPrefix("{CGRect") {
                let x = a.rectValue, y = b.rectValue
                return NSValue(rect: NSRect(x: x.minX + (y.minX - x.minX) * q, y: x.minY + (y.minY - x.minY) * q,
                                            width: x.width + (y.width - x.width) * q, height: x.height + (y.height - x.height) * q))
            }
            if type.hasPrefix("{CATransform3D") {
                return NSValue(caTransform3D: transform(a.caTransform3DValue, b.caTransform3DValue, q))
            }
        }
        if CFGetTypeID(from as CFTypeRef) == CGColor.typeID, CFGetTypeID(to as CFTypeRef) == CGColor.typeID {
            let space = CGColorSpace(name: CGColorSpace.sRGB)!
            let a = (from as! CGColor).converted(to: space, intent: .defaultIntent, options: nil)?.components ?? [0, 0, 0, 0]
            let b = (to as! CGColor).converted(to: space, intent: .defaultIntent, options: nil)?.components ?? [0, 0, 0, 0]
            guard a.count == b.count else { return p >= 0.5 ? to : from }
            return CGColor(colorSpace: space, components: zip(a, b).map { $0 + ($1 - $0) * q })
        }
        if CFGetTypeID(from as CFTypeRef) == CGPath.typeID, CFGetTypeID(to as CFTypeRef) == CGPath.typeID {
            let a = (from as! CGPath).boundingBoxOfPath, b = (to as! CGPath).boundingBoxOfPath
            guard b.width > 0, b.height > 0 else { return to }
            let rect = CGRect(x: a.minX + (b.minX - a.minX) * q, y: a.minY + (b.minY - a.minY) * q,
                              width: a.width + (b.width - a.width) * q, height: a.height + (b.height - a.height) * q)
            var map = CGAffineTransform(translationX: rect.minX, y: rect.minY)
                .scaledBy(x: rect.width / b.width, y: rect.height / b.height)
                .translatedBy(x: -b.minX, y: -b.minY)
            return (to as! CGPath).copy(using: &map)
        }
        return p >= 1 ? to : from
    }

    static func transform(_ a: CATransform3D, _ b: CATransform3D, _ q: CGFloat) -> CATransform3D {
        func parts(_ m: CATransform3D) -> (CGFloat, CGFloat, CGFloat, CGFloat, CGFloat) {
            let sx = hypot(m.m11, m.m12)
            let angle = atan2(m.m12, m.m11)
            let sy = sx == 0 ? 0 : (m.m11 * m.m22 - m.m12 * m.m21) / sx
            return (m.m41, m.m42, sx, sy, angle)
        }
        let x = parts(a), y = parts(b)
        var angle = y.4 - x.4
        if angle > .pi { angle -= 2 * .pi } else if angle < -.pi { angle += 2 * .pi }
        let tx = x.0 + (y.0 - x.0) * q, ty = x.1 + (y.1 - x.1) * q
        let sx = x.2 + (y.2 - x.2) * q, sy = x.3 + (y.3 - x.3) * q
        let theta = x.4 + angle * q
        var m = CATransform3DIdentity
        m.m11 = sx * cos(theta); m.m12 = sx * sin(theta)
        m.m21 = -sy * sin(theta); m.m22 = sy * cos(theta)
        m.m41 = tx; m.m42 = ty
        m.m43 = a.m43 + (b.m43 - a.m43) * q
        return m
    }

    static func add(_ a: Any, _ b: Any) -> Any? {
        if let x = number(a), let y = number(b) { return NSNumber(value: x + y) }
        if let x = a as? NSValue, let y = b as? NSValue {
            let type = String(cString: x.objCType)
            if type.hasPrefix("{CGPoint") { return NSValue(point: NSPoint(x: x.pointValue.x + y.pointValue.x, y: x.pointValue.y + y.pointValue.y)) }
            if type.hasPrefix("{CGSize") { return NSValue(size: NSSize(width: x.sizeValue.width + y.sizeValue.width, height: x.sizeValue.height + y.sizeValue.height)) }
            if type.hasPrefix("{CATransform3D") { return NSValue(caTransform3D: CATransform3DConcat(y.caTransform3DValue, x.caTransform3DValue)) }
        }
        return b
    }

    static func subtract(_ a: Any, _ b: Any) -> Any? {
        if let x = number(a), let y = number(b) { return NSNumber(value: x - y) }
        if let x = a as? NSValue, let y = b as? NSValue {
            let type = String(cString: x.objCType)
            if type.hasPrefix("{CGPoint") { return NSValue(point: NSPoint(x: x.pointValue.x - y.pointValue.x, y: x.pointValue.y - y.pointValue.y)) }
            if type.hasPrefix("{CGSize") { return NSValue(size: NSSize(width: x.sizeValue.width - y.sizeValue.width, height: x.sizeValue.height - y.sizeValue.height)) }
        }
        return a
    }
}
