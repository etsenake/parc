import AppKit

final class LibraryRailAnimation {
    enum Name: String { case media = "screenshots", downloads, easels, spaces, archive }
    @MainActor static let directory = Bundle.main.resourceURL?.appendingPathComponent("Library", isDirectory: true)
    @MainActor private static var cache: [Name: LibraryRailAnimation] = [:]
    @MainActor static func named(_ name: Name) -> LibraryRailAnimation? {
        if let cached = cache[name] { return cached }
        guard let directory,
              let data = try? Data(contentsOf: directory.appendingPathComponent(name.rawValue + ".json")),
              let animation = LibraryRailAnimation(data: data) else { return nil }
        cache[name] = animation
        return animation
    }

    let size: CGSize
    let frameRate: Double
    let startFrame: Double
    private let layers: [Layer]
    private let markers: [String: Double]

    init?(data: Data) {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let width = (root["w"] as? NSNumber)?.doubleValue, let height = (root["h"] as? NSNumber)?.doubleValue,
              let layers = root["layers"] as? [[String: Any]] else { return nil }
        size = CGSize(width: width, height: height)
        frameRate = (root["fr"] as? NSNumber)?.doubleValue ?? 60
        startFrame = (root["ip"] as? NSNumber)?.doubleValue ?? 0
        self.layers = layers.compactMap(Layer.init)
        var markers: [String: Double] = [:]
        for marker in root["markers"] as? [[String: Any]] ?? [] {
            if let name = marker["cm"] as? String, let time = (marker["tm"] as? NSNumber)?.doubleValue { markers[name] = time }
        }
        self.markers = markers
    }

    func frame(forMarker name: String) -> Double? { markers[name] }

    func draw(in context: CGContext, rect: CGRect, frame: Double, primary: CGColor, secondary: CGColor) {
        let scale = min(rect.width / size.width, rect.height / size.height)
        context.saveGState()
        context.translateBy(x: rect.midX - size.width * scale / 2, y: rect.midY - size.height * scale / 2)
        context.scaleBy(x: scale, y: scale)
        let byIndex = Dictionary(layers.map { ($0.index, $0) }, uniquingKeysWith: { first, _ in first })
        func matrix(_ layer: Layer, depth: Int = 0) -> CGAffineTransform {
            let local = layer.transform.matrix(at: frame)
            guard depth < 16, let parent = layer.parent.flatMap({ byIndex[$0] }) else { return local }
            return local.concatenating(matrix(parent, depth: depth + 1))
        }
        for layer in layers.reversed() where frame >= layer.inPoint && frame < layer.outPoint {
            let opacity = layer.transform.opacity(at: frame)
            guard opacity > 0 else { continue }
            context.saveGState()
            context.concatenate(matrix(layer))
            if !layer.masks.isEmpty {
                let clip = CGMutablePath()
                for mask in layer.masks { if let path = mask.value(at: frame) { clip.addPath(path) } }
                context.addPath(clip); context.clip()
            }
            context.setAlpha(opacity)
            context.beginTransparencyLayer(auxiliaryInfo: nil)
            let color = layer.name == "secondaryColor" ? secondary : primary
            Shape.group(layer.shapes, nil).draw(in: context, frame: frame, color: color)
            context.endTransparencyLayer()
            context.restoreGState()
        }
        context.restoreGState()
    }

    private struct Layer {
        let index: Int
        let parent: Int?
        let name: String
        let inPoint, outPoint: Double
        let transform: Transform
        let masks: [Property<CGPath>]
        let shapes: [Shape]
        init?(_ json: [String: Any]) {
            guard (json["ty"] as? NSNumber)?.intValue == 4, let index = (json["ind"] as? NSNumber)?.intValue,
                  let ks = json["ks"] as? [String: Any] else { return nil }
            self.index = index
            parent = (json["parent"] as? NSNumber)?.intValue
            name = json["nm"] as? String ?? ""
            inPoint = (json["ip"] as? NSNumber)?.doubleValue ?? 0
            outPoint = (json["op"] as? NSNumber)?.doubleValue ?? .infinity
            transform = Transform(ks)
            masks = (json["masksProperties"] as? [[String: Any]] ?? []).compactMap { mask in
                guard (mask["mode"] as? String ?? "a") == "a", mask["inv"] as? Bool != true,
                      let pt = mask["pt"] as? [String: Any] else { return nil }
                return Property(pt, Shape.path)
            }
            shapes = (json["shapes"] as? [[String: Any]] ?? []).compactMap(Shape.init)
        }
    }

    private struct Transform {
        let anchor, position, scale: Property<[Double]>
        let x, y: Property<Double>?
        let rotation, opacity: Property<Double>
        init(_ json: [String: Any]) {
            anchor = Property(json["a"], Self.vector, default: [0, 0])
            scale = Property(json["s"], Self.vector, default: [100, 100])
            rotation = Property(json["r"], Self.scalar, default: 0)
            opacity = Property(json["o"], Self.scalar, default: 100)
            let p = json["p"] as? [String: Any]
            if p?["s"] as? Bool == true {
                x = Property(p?["x"], Self.scalar, default: 0); y = Property(p?["y"], Self.scalar, default: 0)
                position = Property(nil, Self.vector, default: [0, 0])
            } else {
                x = nil; y = nil
                position = Property(p, Self.vector, default: [0, 0])
            }
        }
        func matrix(at frame: Double) -> CGAffineTransform {
            let a = anchor.value(at: frame) ?? [0, 0], s = scale.value(at: frame) ?? [100, 100]
            let p = x.flatMap { x in y.map { [x.value(at: frame) ?? 0, $0.value(at: frame) ?? 0] } } ?? position.value(at: frame) ?? [0, 0]
            return CGAffineTransform(translationX: -a[0], y: -a[safe: 1])
                .concatenating(CGAffineTransform(scaleX: s[0] / 100, y: s[safe: 1, or: s[0]] / 100))
                .concatenating(CGAffineTransform(rotationAngle: (rotation.value(at: frame) ?? 0) * .pi / 180))
                .concatenating(CGAffineTransform(translationX: p[0], y: p[safe: 1]))
        }
        func opacity(at frame: Double) -> CGFloat { CGFloat(max(0, min(1, (opacity.value(at: frame) ?? 100) / 100))) }
        static func vector(_ value: Any) -> [Double]? {
            if let array = value as? [NSNumber] { return array.map(\.doubleValue) }
            if let number = value as? NSNumber { return [number.doubleValue] }
            return nil
        }
        static func scalar(_ value: Any) -> Double? { vector(value)?.first }
    }

    private indirect enum Shape {
        case group([Shape], Transform?)
        case path(Property<CGPath>)
        case fill(Property<Double>, CGPathFillRule)
        case stroke(Property<Double>, Property<Double>, CGLineCap, CGLineJoin)

        init?(_ json: [String: Any]) {
            guard json["hd"] as? Bool != true else { return nil }
            switch json["ty"] as? String {
            case "gr":
                let items = json["it"] as? [[String: Any]] ?? []
                self = .group(items.compactMap { $0["ty"] as? String == "tr" ? nil : Shape($0) },
                              items.first { $0["ty"] as? String == "tr" }.map(Transform.init))
            case "sh":
                guard let ks = json["ks"] as? [String: Any] else { return nil }
                self = .path(Property(ks, Self.path))
            case "fl":
                self = .fill(Property(json["o"], Transform.scalar, default: 100),
                             (json["r"] as? NSNumber)?.intValue == 2 ? .evenOdd : .winding)
            case "st":
                let cap: [Int: CGLineCap] = [1: .butt, 2: .round, 3: .square]
                let join: [Int: CGLineJoin] = [1: .miter, 2: .round, 3: .bevel]
                self = .stroke(Property(json["o"], Transform.scalar, default: 100), Property(json["w"], Transform.scalar, default: 1),
                               cap[(json["lc"] as? NSNumber)?.intValue ?? 2] ?? .round,
                               join[(json["lj"] as? NSNumber)?.intValue ?? 2] ?? .round)
            default:
                return nil
            }
        }

        func draw(in context: CGContext, frame: Double, color: CGColor) {
            guard case let .group(items, transform) = self else { return }
            context.saveGState()
            if let transform {
                context.concatenate(transform.matrix(at: frame))
                context.setAlpha(transform.opacity(at: frame))
            }
            var paths: [CGPath] = []
            for item in items {
                switch item {
                case .path(let property): if let path = property.value(at: frame) { paths.append(path) }
                case .group:
                    item.draw(in: context, frame: frame, color: color)
                    paths.append(contentsOf: item.collectPaths(at: frame))
                case let .fill(opacity, rule):
                    guard !paths.isEmpty else { continue }
                    let combined = CGMutablePath(); paths.forEach { combined.addPath($0) }
                    context.addPath(combined)
                    context.setFillColor(color.copy(alpha: color.alpha * CGFloat((opacity.value(at: frame) ?? 100) / 100)) ?? color)
                    context.fillPath(using: rule)
                case let .stroke(opacity, width, cap, join):
                    guard !paths.isEmpty else { continue }
                    let combined = CGMutablePath(); paths.forEach { combined.addPath($0) }
                    context.addPath(combined)
                    context.setStrokeColor(color.copy(alpha: color.alpha * CGFloat((opacity.value(at: frame) ?? 100) / 100)) ?? color)
                    context.setLineWidth(width.value(at: frame) ?? 1); context.setLineCap(cap); context.setLineJoin(join)
                    context.strokePath()
                }
            }
            context.restoreGState()
        }
        private func collectPaths(at frame: Double) -> [CGPath] {
            guard case let .group(items, transform) = self else { return [] }
            let matrix = transform?.matrix(at: frame) ?? .identity
            let result = CGMutablePath()
            for item in items {
                if case let .path(property) = item, let path = property.value(at: frame) { result.addPath(path, transform: matrix) }
                for nested in item.collectPaths(at: frame) { result.addPath(nested, transform: matrix) }
            }
            return result.isEmpty ? [] : [result]
        }

        static func path(_ value: Any) -> CGPath? {
            guard let shape = (value as? [Any])?.first as? [String: Any] ?? value as? [String: Any],
                  let vertices = shape["v"] as? [[NSNumber]], !vertices.isEmpty else { return nil }
            let ins = shape["i"] as? [[NSNumber]] ?? [], outs = shape["o"] as? [[NSNumber]] ?? []
            func point(_ list: [[NSNumber]], _ index: Int) -> CGPoint {
                guard list.indices.contains(index), list[index].count >= 2 else { return .zero }
                return CGPoint(x: list[index][0].doubleValue, y: list[index][1].doubleValue)
            }
            let path = CGMutablePath()
            path.move(to: point(vertices, 0))
            let closed = shape["c"] as? Bool ?? false
            let count = vertices.count
            for index in 1..<(closed ? count + 1 : count) {
                let from = (index - 1) % count, to = index % count
                let start = point(vertices, from), end = point(vertices, to)
                let control1 = CGPoint(x: start.x + point(outs, from).x, y: start.y + point(outs, from).y)
                let control2 = CGPoint(x: end.x + point(ins, to).x, y: end.y + point(ins, to).y)
                path.addCurve(to: end, control1: control1, control2: control2)
            }
            if closed { path.closeSubpath() }
            return path
        }
    }

    private struct Property<Value> {
        private struct Keyframe {
            let time: Double
            let value: Value
            let hold: Bool
            let out: CGPoint, `in`: CGPoint
        }
        private let constant: Value?
        private let keyframes: [Keyframe]
        private let interpolate: (Value, Value, Double) -> Value

        init(_ json: Any?, _ parse: (Any) -> Value?, default fallback: Value? = nil) {
            let object = json as? [String: Any]
            interpolate = Self.interpolator
            if (object?["a"] as? NSNumber)?.intValue == 1, let frames = object?["k"] as? [[String: Any]] {
                var parsed: [Keyframe] = []
                for frame in frames {
                    guard let time = (frame["t"] as? NSNumber)?.doubleValue,
                          let raw = frame["s"] ?? frame["e"], let value = parse(raw) else { continue }
                    parsed.append(Keyframe(time: time, value: value, hold: (frame["h"] as? NSNumber)?.intValue == 1,
                                           out: Self.handle(frame["o"], default: CGPoint(x: 0, y: 0)),
                                           in: Self.handle(frame["i"], default: CGPoint(x: 1, y: 1))))
                }
                keyframes = parsed
                constant = parsed.isEmpty ? fallback : nil
            } else {
                keyframes = []
                constant = object?["k"].flatMap(parse) ?? fallback
            }
        }
        func value(at frame: Double) -> Value? {
            if let constant { return constant }
            guard let first = keyframes.first else { return nil }
            if frame <= first.time || keyframes.count == 1 { return first.value }
            guard let next = keyframes.firstIndex(where: { $0.time > frame }) else { return keyframes[keyframes.count - 1].value }
            let start = keyframes[next - 1], end = keyframes[next]
            if start.hold { return start.value }
            let linear = (frame - start.time) / max(.ulpOfOne, end.time - start.time)
            return interpolate(start.value, end.value, Self.ease(linear, start.out, start.in))
        }
        private static func handle(_ value: Any?, default fallback: CGPoint) -> CGPoint {
            guard let object = value as? [String: Any] else { return fallback }
            func first(_ key: String) -> Double? {
                (object[key] as? NSNumber)?.doubleValue ?? (object[key] as? [NSNumber])?.first?.doubleValue
            }
            return CGPoint(x: first("x") ?? fallback.x, y: first("y") ?? fallback.y)
        }
        private static func ease(_ t: Double, _ c1: CGPoint, _ c2: CGPoint) -> Double {
            func bezier(_ s: Double, _ a: Double, _ b: Double) -> Double {
                3 * (1 - s) * (1 - s) * s * a + 3 * (1 - s) * s * s * b + s * s * s
            }
            var low = 0.0, high = 1.0, s = t
            for _ in 0..<24 {
                s = (low + high) / 2
                if bezier(s, c1.x, c2.x) < t { low = s } else { high = s }
            }
            return bezier(s, c1.y, c2.y)
        }
        private static func interpolator(_ a: Value, _ b: Value, _ t: Double) -> Value {
            switch (a, b) {
            case let (a as Double, b as Double): return (a + (b - a) * t) as! Value
            case let (a as [Double], b as [Double]):
                return zip(a, b).map { $0 + ($1 - $0) * t } as! Value
            case let (a as CGPath, b as CGPath):
                return (LibraryRailAnimation.blend(a, b, t) ?? (t < 1 ? a : b)) as! Value
            default: return t < 1 ? a : b
            }
        }
    }

    fileprivate static func blend(_ a: CGPath, _ b: CGPath, _ t: Double) -> CGPath? {
        func elements(_ path: CGPath) -> [(CGPathElementType, [CGPoint])] {
            var result: [(CGPathElementType, [CGPoint])] = []
            path.applyWithBlock { pointer in
                let element = pointer.pointee
                let count: Int
                switch element.type {
                case .moveToPoint, .addLineToPoint: count = 1
                case .addQuadCurveToPoint: count = 2
                case .addCurveToPoint: count = 3
                default: count = 0
                }
                result.append((element.type, (0..<count).map { element.points[$0] }))
            }
            return result
        }
        let left = elements(a), right = elements(b)
        guard left.count == right.count, zip(left, right).allSatisfy({ $0.0 == $1.0 && $0.1.count == $1.1.count }) else { return nil }
        let path = CGMutablePath()
        for ((type, from), (_, to)) in zip(left, right) {
            let points = zip(from, to).map { CGPoint(x: $0.x + ($1.x - $0.x) * t, y: $0.y + ($1.y - $0.y) * t) }
            switch type {
            case .moveToPoint: path.move(to: points[0])
            case .addLineToPoint: path.addLine(to: points[0])
            case .addQuadCurveToPoint: path.addQuadCurve(to: points[1], control: points[0])
            case .addCurveToPoint: path.addCurve(to: points[2], control1: points[0], control2: points[1])
            case .closeSubpath: path.closeSubpath()
            @unknown default: break
            }
        }
        return path
    }
}

private extension Array where Element == Double {
    subscript(safe index: Int, or fallback: Double = 0) -> Double { indices.contains(index) ? self[index] : fallback }
}
