import Foundation

struct EaselTransform: Equatable {
    var a = 1.0, b = 0.0, c = 0.0, d = 1.0, tx = 0.0, ty = 0.0

    static let identity = EaselTransform()

    static func rotation(degrees: Double, around center: EaselPoint) -> EaselTransform {
        guard degrees.isFinite, degrees.truncatingRemainder(dividingBy: 360) != 0 else { return .identity }
        let radians = degrees * .pi / 180, cosine = cos(radians), sine = sin(radians)
        return EaselTransform(a: cosine, b: sine, c: -sine, d: cosine,
                              tx: center.x - center.x * cosine + center.y * sine,
                              ty: center.y - center.x * sine - center.y * cosine)
    }

    var isIdentity: Bool { self == .identity }

    func apply(_ point: EaselPoint) -> EaselPoint {
        EaselPoint(x: a * point.x + c * point.y + tx, y: b * point.x + d * point.y + ty)
    }

    var inverted: EaselTransform? {
        let determinant = a * d - b * c
        guard determinant.isFinite, abs(determinant) > 1e-12 else { return nil }
        return EaselTransform(a: d / determinant, b: -b / determinant, c: -c / determinant, d: a / determinant,
                              tx: (c * ty - d * tx) / determinant, ty: (b * tx - a * ty) / determinant)
    }

    static func mirror(horizontally: Bool, vertically: Bool, around center: EaselPoint) -> EaselTransform {
        guard horizontally || vertically else { return .identity }
        return EaselTransform(a: horizontally ? -1 : 1, b: 0, c: 0, d: vertically ? -1 : 1,
                              tx: horizontally ? 2 * center.x : 0, ty: vertically ? 2 * center.y : 0)
    }

    func concatenating(_ next: EaselTransform) -> EaselTransform {
        EaselTransform(a: next.a * a + next.c * b, b: next.b * a + next.d * b,
                       c: next.a * c + next.c * d, d: next.b * c + next.d * d,
                       tx: next.a * tx + next.c * ty + next.tx, ty: next.b * tx + next.d * ty + next.ty)
    }

    func bounds(of r: EaselRect) -> EaselRect {
        let corners = [EaselPoint(x: r.x, y: r.y), EaselPoint(x: r.x + r.width, y: r.y),
                       EaselPoint(x: r.x + r.width, y: r.y + r.height), EaselPoint(x: r.x, y: r.y + r.height)].map(apply)
        let xs = corners.map(\.x), ys = corners.map(\.y)
        let minX = xs.min() ?? r.x, minY = ys.min() ?? r.y
        return EaselRect(x: minX, y: minY, width: (xs.max() ?? minX) - minX, height: (ys.max() ?? minY) - minY)
    }
}

struct EaselPath: Equatable {
    enum Element: Equatable {
        case move(EaselPoint)
        case line(EaselPoint)
        case quad(control: EaselPoint, to: EaselPoint)
        case cubic(control1: EaselPoint, control2: EaselPoint, to: EaselPoint)
        case close
    }

    enum FillRule { case nonZero, evenOdd }

    struct Subpath: Equatable {
        var points: [EaselPoint]
        var closed: Bool
    }

    static let kappa = 0.5522847498307936

    private(set) var elements: [Element] = []

    init() {}

    init(polygon points: [EaselPoint]) {
        guard let first = points.first else { return }
        move(to: first)
        for point in points.dropFirst() { line(to: point) }
        close()
    }

    var isEmpty: Bool { elements.isEmpty }

    private var lastPoint: EaselPoint? {
        switch elements.last {
        case .move(let p), .line(let p), .quad(_, let p), .cubic(_, _, let p): return p
        case .close, .none: return nil
        }
    }

    mutating func move(to point: EaselPoint) { elements.append(.move(point)) }
    mutating func line(to point: EaselPoint) { elements.append(.line(point)) }
    mutating func quad(to point: EaselPoint, control: EaselPoint) { elements.append(.quad(control: control, to: point)) }
    mutating func cubic(to point: EaselPoint, control1: EaselPoint, control2: EaselPoint) {
        elements.append(.cubic(control1: control1, control2: control2, to: point))
    }
    mutating func close() { elements.append(.close) }
    mutating func append(_ other: EaselPath) { elements.append(contentsOf: other.elements) }

    mutating func arc(center: EaselPoint, radiusX: Double, radiusY: Double, from start: Double, to end: Double) {
        let sweep = end - start
        guard sweep.isFinite, sweep != 0, radiusX.isFinite, radiusY.isFinite else { return }
        let steps = max(1, Int((abs(sweep) / (.pi / 2) - 1e-9).rounded(.up)))
        let step = sweep / Double(steps), handle = 4.0 / 3.0 * tan(step / 4)
        func point(_ angle: Double) -> EaselPoint {
            EaselPoint(x: center.x + radiusX * cos(angle), y: center.y + radiusY * sin(angle))
        }
        let origin = point(start)
        if let last = lastPoint {
            if abs(last.x - origin.x) > 1e-9 || abs(last.y - origin.y) > 1e-9 { line(to: origin) }
        } else {
            move(to: origin)
        }
        for index in 0..<steps {
            let a0 = start + Double(index) * step, a1 = a0 + step
            let p0 = point(a0), p1 = point(a1)
            cubic(to: p1,
                  control1: EaselPoint(x: p0.x - handle * radiusX * sin(a0), y: p0.y + handle * radiusY * cos(a0)),
                  control2: EaselPoint(x: p1.x + handle * radiusX * sin(a1), y: p1.y - handle * radiusY * cos(a1)))
        }
    }

    static func ellipse(in r: EaselRect) -> EaselPath {
        let rx = r.width / 2, ry = r.height / 2, cx = r.x + rx, cy = r.y + ry
        let kx = rx * kappa, ky = ry * kappa, maxX = r.x + r.width, maxY = r.y + r.height
        var path = EaselPath()
        path.move(to: EaselPoint(x: cx, y: r.y))
        path.cubic(to: EaselPoint(x: maxX, y: cy), control1: EaselPoint(x: cx + kx, y: r.y), control2: EaselPoint(x: maxX, y: cy - ky))
        path.cubic(to: EaselPoint(x: cx, y: maxY), control1: EaselPoint(x: maxX, y: cy + ky), control2: EaselPoint(x: cx + kx, y: maxY))
        path.cubic(to: EaselPoint(x: r.x, y: cy), control1: EaselPoint(x: cx - kx, y: maxY), control2: EaselPoint(x: r.x, y: cy + ky))
        path.cubic(to: EaselPoint(x: cx, y: r.y), control1: EaselPoint(x: r.x, y: cy - ky), control2: EaselPoint(x: cx - kx, y: r.y))
        path.close()
        return path
    }

    static func roundedRect(_ r: EaselRect, radius requested: Double) -> EaselPath {
        let radius = max(0, min(requested, r.width / 2, r.height / 2))
        let minX = r.x, minY = r.y, maxX = r.x + r.width, maxY = r.y + r.height
        guard radius > 0 else {
            return EaselPath(polygon: [EaselPoint(x: minX, y: minY), EaselPoint(x: maxX, y: minY),
                                       EaselPoint(x: maxX, y: maxY), EaselPoint(x: minX, y: maxY)])
        }
        let k = radius * (1 - kappa)
        var path = EaselPath()
        path.move(to: EaselPoint(x: minX + radius, y: minY))
        path.line(to: EaselPoint(x: maxX - radius, y: minY))
        path.cubic(to: EaselPoint(x: maxX, y: minY + radius), control1: EaselPoint(x: maxX - k, y: minY), control2: EaselPoint(x: maxX, y: minY + k))
        path.line(to: EaselPoint(x: maxX, y: maxY - radius))
        path.cubic(to: EaselPoint(x: maxX - radius, y: maxY), control1: EaselPoint(x: maxX, y: maxY - k), control2: EaselPoint(x: maxX - k, y: maxY))
        path.line(to: EaselPoint(x: minX + radius, y: maxY))
        path.cubic(to: EaselPoint(x: minX, y: maxY - radius), control1: EaselPoint(x: minX + k, y: maxY), control2: EaselPoint(x: minX, y: maxY - k))
        path.line(to: EaselPoint(x: minX, y: minY + radius))
        path.cubic(to: EaselPoint(x: minX + radius, y: minY), control1: EaselPoint(x: minX, y: minY + k), control2: EaselPoint(x: minX + k, y: minY))
        path.close()
        return path
    }

    func applying(_ transform: EaselTransform) -> EaselPath {
        guard !transform.isIdentity else { return self }
        var path = EaselPath()
        path.elements = elements.map { element in
            switch element {
            case .move(let p): return .move(transform.apply(p))
            case .line(let p): return .line(transform.apply(p))
            case .quad(let c, let p): return .quad(control: transform.apply(c), to: transform.apply(p))
            case .cubic(let c1, let c2, let p):
                return .cubic(control1: transform.apply(c1), control2: transform.apply(c2), to: transform.apply(p))
            case .close: return .close
            }
        }
        return path
    }

    var bounds: EaselRect? {
        var minX = Double.infinity, minY = Double.infinity, maxX = -Double.infinity, maxY = -Double.infinity
        func include(_ p: EaselPoint) {
            minX = min(minX, p.x); minY = min(minY, p.y); maxX = max(maxX, p.x); maxY = max(maxY, p.y)
        }
        var current = EaselPoint(x: 0, y: 0), start = current
        for element in elements {
            switch element {
            case .move(let p): include(p); current = p; start = p
            case .line(let p): include(current); include(p); current = p
            case .quad(let c, let p):
                include(current); include(p)
                for t in Self.quadExtrema(current, c, p) { include(Self.quadPoint(current, c, p, t)) }
                current = p
            case .cubic(let c1, let c2, let p):
                include(current); include(p)
                for t in Self.cubicExtrema(current, c1, c2, p) { include(Self.cubicPoint(current, c1, c2, p, t)) }
                current = p
            case .close: current = start
            }
        }
        guard [minX, minY, maxX, maxY].allSatisfy(\.isFinite) else { return nil }
        return EaselRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    func subpaths(tolerance: Double = 0.2) -> [Subpath] {
        let tolerance = tolerance.isFinite && tolerance > 0 ? tolerance : 0.2
        var result: [Subpath] = []
        var points: [EaselPoint] = []
        var current = EaselPoint(x: 0, y: 0), start = current
        func finish(closed: Bool) {
            if !points.isEmpty { result.append(Subpath(points: points, closed: closed)) }
            points = []
        }
        for element in elements {
            switch element {
            case .move(let p):
                finish(closed: false); points = [p]; current = p; start = p
            case .line(let p):
                if points.isEmpty { points = [current] }
                points.append(p); current = p
            case .quad(let c, let p):
                if points.isEmpty { points = [current] }
                let count = Self.segmentCount(secondDifference: Self.length(current.x - 2 * c.x + p.x, current.y - 2 * c.y + p.y),
                                              factor: 0.25, tolerance: tolerance)
                for index in 1...count { points.append(Self.quadPoint(current, c, p, Double(index) / Double(count))) }
                current = p
            case .cubic(let c1, let c2, let p):
                if points.isEmpty { points = [current] }
                let difference = max(Self.length(current.x - 2 * c1.x + c2.x, current.y - 2 * c1.y + c2.y),
                                     Self.length(c1.x - 2 * c2.x + p.x, c1.y - 2 * c2.y + p.y))
                let count = Self.segmentCount(secondDifference: difference, factor: 0.75, tolerance: tolerance)
                for index in 1...count { points.append(Self.cubicPoint(current, c1, c2, p, Double(index) / Double(count))) }
                current = p
            case .close:
                finish(closed: true); current = start
            }
        }
        finish(closed: false)
        return result
    }

    func contains(_ point: EaselPoint, rule: FillRule = .nonZero, tolerance: Double = 0.2) -> Bool {
        guard point.x.isFinite, point.y.isFinite else { return false }
        var winding = 0
        for subpath in subpaths(tolerance: tolerance) where subpath.points.count > 2 {
            let points = subpath.points
            for index in points.indices {
                let a = points[index], b = points[(index + 1) % points.count]
                let side = (b.x - a.x) * (point.y - a.y) - (point.x - a.x) * (b.y - a.y)
                if a.y <= point.y {
                    if b.y > point.y, side > 0 { winding += 1 }
                } else if b.y <= point.y, side < 0 {
                    winding -= 1
                }
            }
        }
        return rule == .nonZero ? winding != 0 : winding % 2 != 0
    }

    func distance(to point: EaselPoint, tolerance: Double = 0.2) -> Double {
        guard point.x.isFinite, point.y.isFinite else { return .infinity }
        var best = Double.infinity
        for subpath in subpaths(tolerance: tolerance) {
            let points = subpath.points
            guard let first = points.first, let last = points.last else { continue }
            if points.count == 1 { best = min(best, Self.length(point.x - first.x, point.y - first.y)); continue }
            for index in 0..<(points.count - 1) {
                best = min(best, Self.segmentDistance(point, points[index], points[index + 1]))
            }
            if subpath.closed { best = min(best, Self.segmentDistance(point, last, first)) }
        }
        return best
    }

    var svgPathData: String {
        elements.map { element in
            switch element {
            case .move(let p): return "M" + Self.svg(p)
            case .line(let p): return "L" + Self.svg(p)
            case .quad(let c, let p): return "Q" + Self.svg(c) + " " + Self.svg(p)
            case .cubic(let c1, let c2, let p): return "C" + Self.svg(c1) + " " + Self.svg(c2) + " " + Self.svg(p)
            case .close: return "Z"
            }
        }.joined(separator: " ")
    }

    static func svgNumber(_ value: Double) -> String {
        guard value.isFinite else { return "0" }
        let rounded = (value * 1000).rounded() / 1000
        guard rounded != 0 else { return "0" }
        var text = String(format: "%.3f", rounded)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }

    static func segmentDistance(_ p: EaselPoint, _ a: EaselPoint, _ b: EaselPoint) -> Double {
        let dx = b.x - a.x, dy = b.y - a.y, squared = dx * dx + dy * dy
        let t = squared > 0 ? min(1, max(0, ((p.x - a.x) * dx + (p.y - a.y) * dy) / squared)) : 0
        return length(p.x - a.x - t * dx, p.y - a.y - t * dy)
    }

    private static func svg(_ p: EaselPoint) -> String { svgNumber(p.x) + " " + svgNumber(p.y) }

    private static func length(_ x: Double, _ y: Double) -> Double { (x * x + y * y).squareRoot() }

    private static func segmentCount(secondDifference: Double, factor: Double, tolerance: Double) -> Int {
        guard secondDifference.isFinite, secondDifference > 0 else { return 1 }
        let estimate = (factor * secondDifference / tolerance).squareRoot().rounded(.up)
        return Int(min(256, max(1, estimate)))
    }

    private static func quadPoint(_ p0: EaselPoint, _ c: EaselPoint, _ p1: EaselPoint, _ t: Double) -> EaselPoint {
        let u = 1 - t
        return EaselPoint(x: u * u * p0.x + 2 * u * t * c.x + t * t * p1.x, y: u * u * p0.y + 2 * u * t * c.y + t * t * p1.y)
    }

    private static func cubicPoint(_ p0: EaselPoint, _ c1: EaselPoint, _ c2: EaselPoint, _ p1: EaselPoint, _ t: Double) -> EaselPoint {
        let u = 1 - t, a = u * u * u, b = 3 * u * u * t, c = 3 * u * t * t, d = t * t * t
        return EaselPoint(x: a * p0.x + b * c1.x + c * c2.x + d * p1.x, y: a * p0.y + b * c1.y + c * c2.y + d * p1.y)
    }

    private static func quadExtrema(_ p0: EaselPoint, _ c: EaselPoint, _ p1: EaselPoint) -> [Double] {
        [(p0.x, c.x, p1.x), (p0.y, c.y, p1.y)].compactMap { a, b, e in
            let denominator = a - 2 * b + e
            guard abs(denominator) > 1e-12 else { return nil }
            let t = (a - b) / denominator
            return t > 0 && t < 1 ? t : nil
        }
    }

    private static func cubicExtrema(_ p0: EaselPoint, _ c1: EaselPoint, _ c2: EaselPoint, _ p1: EaselPoint) -> [Double] {
        var result: [Double] = []
        for (a, b, c, d) in [(p0.x, c1.x, c2.x, p1.x), (p0.y, c1.y, c2.y, p1.y)] {
            let qa = -a + 3 * b - 3 * c + d, qb = 2 * (a - 2 * b + c), qc = b - a
            var roots: [Double] = []
            if abs(qa) < 1e-12 {
                if abs(qb) > 1e-12 { roots = [-qc / qb] }
            } else {
                let discriminant = qb * qb - 4 * qa * qc
                if discriminant >= 0 {
                    let root = discriminant.squareRoot()
                    roots = [(-qb + root) / (2 * qa), (-qb - root) / (2 * qa)]
                }
            }
            result += roots.filter { $0 > 0 && $0 < 1 }
        }
        return result
    }
}

enum EaselShapeGeometry {
    static let defaultStrokeWidth = 2.5
    static let rectangleRadius = 5.0

    static func outline(_ shape: EaselShape, in r: EaselRect) -> EaselPath {
        let w = r.width, h = r.height
        func p(_ x: Double, _ y: Double) -> EaselPoint { EaselPoint(x: r.x + x, y: r.y + y) }
        switch shape {
        case .rectangle, .roundedRectangle, .predefinedProcess, .internalStorage:
            return .roundedRect(r, radius: cornerRadius(shape, in: r))
        case .ellipse, .or, .summingJunction:
            return .ellipse(in: r)
        case .diamond:
            return EaselPath(polygon: [p(w / 2, 0), p(w, h / 2), p(w / 2, h), p(0, h / 2)])
        case .triangle:
            return EaselPath(polygon: [p(w / 2, 0), p(w, h), p(0, h)])
        case .triangleDown:
            return EaselPath(polygon: [p(0, 0), p(w, 0), p(w / 2, h)])
        case .parallelogram:
            let s = parallelogramSlant(w, h)
            return EaselPath(polygon: [p(s, 0), p(w, 0), p(w - s, h), p(0, h)])
        case .parallelogramLeft:
            let s = parallelogramSlant(w, h)
            return EaselPath(polygon: [p(0, 0), p(w - s, 0), p(w, h), p(s, h)])
        case .trapezoid:
            let i = trapezoidInset(w, h)
            return EaselPath(polygon: [p(i, 0), p(w - i, 0), p(w, h), p(0, h)])
        case .manualInput:
            let s = manualInputRise(w, h)
            return EaselPath(polygon: [p(0, s), p(w, 0), p(w, h), p(0, h)])
        case .pentagon:
            return EaselPath(polygon: normalizedPentagon.map { p($0.x * w, $0.y * h) })
        case .hexagon:
            let k = hexagonInset(w, h)
            return EaselPath(polygon: [p(k, 0), p(w - k, 0), p(w, h / 2), p(w - k, h), p(k, h), p(0, h / 2)])
        case .octagon:
            let c = octagonCut(w, h)
            return EaselPath(polygon: [p(c, 0), p(w - c, 0), p(w, c), p(w, h - c), p(w - c, h), p(c, h), p(0, h - c), p(0, c)])
        case .star:
            return EaselPath(polygon: normalizedStar.map { p($0.x * w, $0.y * h) })
        case .plus:
            let t = plusThickness(w, h), x0 = (w - t) / 2, x1 = x0 + t, y0 = (h - t) / 2, y1 = y0 + t
            return EaselPath(polygon: [p(x0, 0), p(x1, 0), p(x1, y0), p(w, y0), p(w, y1), p(x1, y1),
                                       p(x1, h), p(x0, h), p(x0, y1), p(0, y1), p(0, y0), p(x0, y0)])
        case .speechBubble:
            return speechBubble(r)
        case .arrowLeft, .arrowRight, .arrowUp, .arrowDown:
            return EaselPath(polygon: blockArrow(shape, in: r))
        case .chevron:
            let d = chevronDepth(w, h)
            return EaselPath(polygon: [p(0, 0), p(w - d, 0), p(w, h / 2), p(w - d, h), p(0, h), p(d, h / 2)])
        case .cylinder:
            let ry = cylinderCap(w, h)
            var path = EaselPath()
            path.move(to: p(0, ry))
            path.line(to: p(0, h - ry))
            path.arc(center: p(w / 2, h - ry), radiusX: w / 2, radiusY: ry, from: .pi, to: 0)
            path.line(to: p(w, ry))
            path.arc(center: p(w / 2, ry), radiusX: w / 2, radiusY: ry, from: 0, to: -.pi)
            path.close()
            return path
        case .cylinderHorizontal:
            let rx = cylinderCap(h, w)
            var path = EaselPath()
            path.move(to: p(rx, 0))
            path.line(to: p(w - rx, 0))
            path.arc(center: p(w - rx, h / 2), radiusX: rx, radiusY: h / 2, from: -.pi / 2, to: .pi / 2)
            path.line(to: p(rx, h))
            path.arc(center: p(rx, h / 2), radiusX: rx, radiusY: h / 2, from: .pi / 2, to: .pi * 3 / 2)
            path.close()
            return path
        case .file:
            let f = fileFold(w, h)
            return EaselPath(polygon: [p(0, 0), p(w - f, 0), p(w, f), p(w, h), p(0, h)])
        case .folder:
            let t = folderTab(w, h), tab = w * 0.38
            return EaselPath(polygon: [p(0, 0), p(tab, 0), p(tab + t, t), p(w, t), p(w, h), p(0, h)])
        case .document:
            var path = EaselPath()
            path.move(to: p(0, 0))
            path.line(to: p(w, 0))
            path.append(wavyBottom(r, amplitude: waveAmplitude(h)))
            path.close()
            return path
        case .documents:
            let o = stackOffset(w, h)
            let front = EaselRect(x: r.x, y: r.y + 2 * o, width: w - 2 * o, height: h - 2 * o)
            var path = EaselPath()
            path.move(to: p(0, 2 * o))
            path.line(to: p(o, 2 * o))
            path.line(to: p(o, o))
            path.line(to: p(2 * o, o))
            path.line(to: p(2 * o, 0))
            path.line(to: p(w, 0))
            path.line(to: p(w, h - 2 * o))
            path.line(to: p(w - o, h - 2 * o))
            path.line(to: p(w - o, h - o))
            path.line(to: p(w - 2 * o, h - o))
            path.append(wavyBottom(front, amplitude: stackWave(w, h)))
            path.close()
            return path
        case .shield:
            var path = EaselPath()
            path.move(to: p(0, 0))
            path.line(to: p(w, 0))
            path.line(to: p(w, h * 0.45))
            path.cubic(to: p(w / 2, h), control1: p(w, h * 0.75), control2: p(w * 0.75, h * 0.92))
            path.cubic(to: p(0, h * 0.45), control1: p(w * 0.25, h * 0.92), control2: p(0, h * 0.75))
            path.close()
            return path
        }
    }

    static func details(_ shape: EaselShape, in r: EaselRect) -> EaselPath {
        let w = r.width, h = r.height
        func p(_ x: Double, _ y: Double) -> EaselPoint { EaselPoint(x: r.x + x, y: r.y + y) }
        var path = EaselPath()
        switch shape {
        case .cylinder:
            let ry = cylinderCap(w, h)
            path.arc(center: p(w / 2, ry), radiusX: w / 2, radiusY: ry, from: .pi, to: 0)
        case .cylinderHorizontal:
            let rx = cylinderCap(h, w)
            path.arc(center: p(w - rx, h / 2), radiusX: rx, radiusY: h / 2, from: -.pi / 2, to: -.pi * 3 / 2)
        case .file:
            let f = fileFold(w, h)
            path.move(to: p(w - f, 0)); path.line(to: p(w - f, f)); path.line(to: p(w, f))
        case .documents:
            let o = stackOffset(w, h)
            path.move(to: p(o, 2 * o)); path.line(to: p(w - 2 * o, 2 * o)); path.line(to: p(w - 2 * o, h - o))
            path.move(to: p(2 * o, o)); path.line(to: p(w - o, o)); path.line(to: p(w - o, h - 2 * o))
        case .predefinedProcess:
            let v = processInset(w, h)
            path.move(to: p(v, 0)); path.line(to: p(v, h))
            path.move(to: p(w - v, 0)); path.line(to: p(w - v, h))
        case .internalStorage:
            let g = storageInset(w, h)
            path.move(to: p(g, 0)); path.line(to: p(g, h))
            path.move(to: p(0, g)); path.line(to: p(w, g))
        case .or:
            path.move(to: p(w / 2, 0)); path.line(to: p(w / 2, h))
            path.move(to: p(0, h / 2)); path.line(to: p(w, h / 2))
        case .summingJunction:
            let dx = w / 2 * 0.5.squareRoot(), dy = h / 2 * 0.5.squareRoot()
            path.move(to: p(w / 2 - dx, h / 2 - dy)); path.line(to: p(w / 2 + dx, h / 2 + dy))
            path.move(to: p(w / 2 + dx, h / 2 - dy)); path.line(to: p(w / 2 - dx, h / 2 + dy))
        default:
            break
        }
        return path
    }

    static func cornerRadius(_ shape: EaselShape, in r: EaselRect) -> Double {
        let limit = max(0, min(r.width, r.height) / 2)
        switch shape {
        case .rectangle, .predefinedProcess, .internalStorage: return min(rectangleRadius, limit)
        case .roundedRectangle: return min(max(min(r.width, r.height) * 0.2, 8), 36, limit)
        case .speechBubble: return min(max(min(r.width, r.height * 0.78) * 0.18, 6), 28, limit)
        default: return 0
        }
    }

    static func textRect(_ shape: EaselShape, in r: EaselRect) -> EaselRect {
        let w = r.width, h = r.height
        func area(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double) -> EaselRect {
            EaselRect(x: r.x + x0, y: r.y + y0, width: max(0, x1 - x0), height: max(0, y1 - y0))
        }
        let raw: EaselRect
        switch shape {
        case .rectangle, .roundedRectangle:
            let inset = cornerRadius(shape, in: r) * 0.3
            raw = area(inset, inset, w - inset, h - inset)
        case .ellipse, .or, .summingJunction:
            let fx = w * (1 - 0.5.squareRoot()) / 2, fy = h * (1 - 0.5.squareRoot()) / 2
            raw = area(fx, fy, w - fx, h - fy)
        case .diamond: raw = area(w / 4, h / 4, w * 3 / 4, h * 3 / 4)
        case .triangle: raw = area(w / 4, h / 2, w * 3 / 4, h)
        case .triangleDown: raw = area(w / 4, 0, w * 3 / 4, h / 2)
        case .parallelogram, .parallelogramLeft:
            let s = parallelogramSlant(w, h)
            raw = area(s, 0, w - s, h)
        case .trapezoid:
            let i = trapezoidInset(w, h)
            raw = area(i, 0, w - i, h)
        case .manualInput:
            raw = area(0, manualInputRise(w, h), w, h)
        case .pentagon: raw = area(w * 0.191, h * 0.236, w * 0.809, h)
        case .hexagon:
            let k = hexagonInset(w, h)
            raw = area(k * 0.7, h * 0.15, w - k * 0.7, h * 0.85)
        case .octagon:
            let c = octagonCut(w, h)
            raw = area(c / 2, c / 2, w - c / 2, h - c / 2)
        case .star: raw = area(w * 0.25, h * 0.382, w * 0.75, h * 0.573)
        case .plus:
            let t = plusThickness(w, h)
            raw = w >= h ? area(0, (h - t) / 2, w, (h + t) / 2) : area((w - t) / 2, 0, (w + t) / 2, h)
        case .speechBubble:
            let inset = cornerRadius(shape, in: r) * 0.3
            raw = area(inset, inset, w - inset, h * 0.78 - inset)
        case .arrowRight:
            raw = area(0, h / 4, w - arrowHead(length: w, breadth: h) / 2, h * 3 / 4)
        case .arrowLeft:
            raw = area(arrowHead(length: w, breadth: h) / 2, h / 4, w, h * 3 / 4)
        case .arrowDown:
            raw = area(w / 4, 0, w * 3 / 4, h - arrowHead(length: h, breadth: w) / 2)
        case .arrowUp:
            raw = area(w / 4, arrowHead(length: h, breadth: w) / 2, w * 3 / 4, h)
        case .chevron:
            let d = chevronDepth(w, h)
            raw = area(d, h * 0.1, w - d * 0.8, h * 0.9)
        case .cylinder:
            let ry = cylinderCap(w, h)
            raw = area(0, 2 * ry, w, h - ry)
        case .cylinderHorizontal:
            let rx = cylinderCap(h, w)
            raw = area(rx, 0, w - 2 * rx, h)
        case .file:
            let f = fileFold(w, h)
            raw = h >= w ? area(0, f, w, h) : area(0, 0, w - f, h)
        case .folder:
            raw = area(0, folderTab(w, h), w, h)
        case .document:
            raw = area(0, 0, w, h - 2 * waveAmplitude(h))
        case .documents:
            let o = stackOffset(w, h)
            raw = area(0, 2 * o, w - 2 * o, h - 2 * stackWave(w, h))
        case .predefinedProcess:
            let inset = cornerRadius(shape, in: r) * 0.3, v = max(processInset(w, h), inset)
            raw = area(v, inset, w - v, h - inset)
        case .internalStorage:
            let inset = cornerRadius(shape, in: r) * 0.3, g = max(storageInset(w, h), inset)
            raw = area(g, g, w - inset, h - inset)
        case .shield:
            raw = area(w * 0.12, h * 0.1, w * 0.88, h * 0.7)
        }
        let padding = min(6, raw.width * 0.05, raw.height * 0.05)
        return EaselRect(x: raw.x + padding, y: raw.y + padding,
                         width: max(1, raw.width - 2 * padding), height: max(1, raw.height - 2 * padding))
    }

    static func defaultSize(_ shape: EaselShape) -> (width: Double, height: Double) {
        switch shape {
        case .rectangle, .roundedRectangle, .parallelogram, .parallelogramLeft, .trapezoid, .manualInput, .predefinedProcess:
            return (200, 120)
        case .ellipse, .pentagon, .octagon, .star, .plus: return (160, 160)
        case .diamond, .internalStorage: return (180, 140)
        case .triangle, .triangleDown: return (160, 140)
        case .hexagon: return (184, 160)
        case .speechBubble: return (200, 150)
        case .arrowLeft, .arrowRight, .chevron, .cylinderHorizontal: return (200, 110)
        case .arrowUp, .arrowDown: return (110, 200)
        case .cylinder: return (140, 170)
        case .file, .shield: return (150, 180)
        case .folder: return (190, 150)
        case .document: return (200, 130)
        case .documents: return (200, 140)
        case .or, .summingJunction: return (100, 100)
        }
    }

    static func displayName(_ shape: EaselShape) -> String {
        switch shape {
        case .rectangle: return "Rectangle"
        case .roundedRectangle: return "Rounded rectangle"
        case .ellipse: return "Circle"
        case .diamond: return "Diamond"
        case .triangle: return "Triangle"
        case .triangleDown: return "Upside-down triangle"
        case .parallelogram: return "Right-leaning parallelogram"
        case .parallelogramLeft: return "Left-leaning parallelogram"
        case .trapezoid: return "Trapezoid"
        case .pentagon: return "Pentagon"
        case .hexagon: return "Hexagon"
        case .octagon: return "Octagon"
        case .star: return "Star"
        case .plus: return "Plus"
        case .speechBubble: return "Speech bubble"
        case .arrowLeft: return "Left arrow"
        case .arrowRight: return "Right arrow"
        case .arrowUp: return "Up arrow"
        case .arrowDown: return "Down arrow"
        case .chevron: return "Chevron"
        case .cylinder: return "Cylinder"
        case .cylinderHorizontal: return "Sideways cylinder"
        case .file: return "File"
        case .folder: return "Folder"
        case .document: return "Document"
        case .documents: return "Stack of documents"
        case .predefinedProcess: return "Predefined process"
        case .shield: return "Shield"
        case .manualInput: return "Manual input"
        case .internalStorage: return "Internal storage"
        case .or: return "Or"
        case .summingJunction: return "Summing junction"
        }
    }

    static func rotation(of item: EaselItem) -> Double {
        let degrees = item.rotation ?? 0
        guard degrees.isFinite else { return 0 }
        let normalized = degrees.truncatingRemainder(dividingBy: 360)
        return abs(normalized) < 1e-9 ? 0 : normalized
    }

    static func center(of r: EaselRect) -> EaselPoint { EaselPoint(x: r.x + r.width / 2, y: r.y + r.height / 2) }

    static func rotationTransform(for item: EaselItem) -> EaselTransform {
        .rotation(degrees: rotation(of: item), around: center(of: item.frame))
    }

    static func flipTransform(for item: EaselItem) -> EaselTransform {
        .mirror(horizontally: item.flipHorizontal == true, vertically: item.flipVertical == true, around: center(of: item.frame))
    }

    static func transform(for item: EaselItem) -> EaselTransform {
        flipTransform(for: item).concatenating(rotationTransform(for: item))
    }

    static func localPoint(_ point: EaselPoint, in item: EaselItem) -> EaselPoint {
        let transform = transform(for: item)
        guard !transform.isIdentity, let inverse = transform.inverted else { return point }
        return inverse.apply(point)
    }

    static func rotatedBounds(_ r: EaselRect, degrees: Double) -> EaselRect {
        let transform = EaselTransform.rotation(degrees: degrees, around: center(of: r))
        guard !transform.isIdentity else { return r }
        return transform.bounds(of: r)
    }

    static func visualBounds(of item: EaselItem) -> EaselRect { rotatedBounds(item.frame, degrees: rotation(of: item)) }

    static func outline(for item: EaselItem) -> EaselPath? {
        guard let shape = item.resolvedShape else { return nil }
        return outline(shape, in: item.frame).applying(transform(for: item))
    }

    static func details(for item: EaselItem) -> EaselPath? {
        guard let shape = item.resolvedShape else { return nil }
        return details(shape, in: item.frame).applying(transform(for: item))
    }

    static func textRect(for item: EaselItem) -> EaselRect? {
        guard let shape = item.resolvedShape else { return nil }
        let rect = textRect(shape, in: item.frame), flip = flipTransform(for: item)
        return flip.isIdentity ? rect : flip.bounds(of: rect)
    }

    static func strokeWidth(of item: EaselItem) -> Double {
        guard let width = item.strokeWidth, width.isFinite else { return defaultStrokeWidth }
        return min(64, max(0, width))
    }

    static func hasVisibleFill(_ item: EaselItem) -> Bool {
        guard let opacity = item.fillOpacity else { return true }
        return opacity.isFinite && opacity > 0.001
    }

    static func usesOriginalLook(_ item: EaselItem) -> Bool {
        item.shape == nil && item.fill == nil && item.fillOpacity == nil && item.strokeWidth == nil
            && item.strokeDash == nil && rotation(of: item) == 0
    }

    static func hits(_ point: EaselPoint, item: EaselItem, selected: Bool, scale: Double) -> Bool {
        guard let shape = item.resolvedShape, scale.isFinite, scale > 0, point.x.isFinite, point.y.isFinite else { return false }
        let local = localPoint(point, in: item)
        let r = item.frame, minimum = 30 / scale
        let band = max(minimum / 2, strokeWidth(of: item) / 2)
        let grow = max(max(0, minimum - r.width) / 2, band), rise = max(max(0, minimum - r.height) / 2, band)
        let target = EaselRect(x: r.x - grow, y: r.y - rise, width: r.width + 2 * grow, height: r.height + 2 * rise)
        guard EaselContentHitTest.contains(local, rect: target) else { return false }
        if r.width <= minimum || r.height <= minimum { return true }
        if selected { return EaselContentHitTest.contains(local, rect: r) || nearOutline(local, shape: shape, frame: r, band: band) }
        if isSolid(item), outline(shape, in: r).contains(local, tolerance: 0.5) { return true }
        return nearOutline(local, shape: shape, frame: r, band: band)
    }

    static func intersects(_ rect: EaselRect, item: EaselItem, selected: Bool) -> Bool {
        guard rect.width > 0, rect.height > 0, item.resolvedShape != nil else { return false }
        let bounds = visualBounds(of: item)
        guard EaselContentHitTest.intersects(rect, bounds) else { return false }
        if selected { return true }
        guard let path = outline(for: item) else { return false }
        for subpath in path.subpaths(tolerance: 0.5) {
            let points = subpath.points
            guard let first = points.first else { continue }
            if EaselContentHitTest.contains(first, rect: rect) { return true }
            let closing = subpath.closed && points.count > 2 ? [(points[points.count - 1], first)] : []
            for (a, b) in zip(points, points.dropFirst()).map({ ($0, $1) }) + closing where segment(a, b, intersects: rect) {
                return true
            }
        }
        guard isSolid(item) else { return false }
        let corners = [EaselPoint(x: rect.x, y: rect.y), EaselPoint(x: rect.x + rect.width, y: rect.y),
                       EaselPoint(x: rect.x, y: rect.y + rect.height), EaselPoint(x: rect.x + rect.width, y: rect.y + rect.height)]
        return corners.contains { path.contains($0, tolerance: 0.5) }
    }

    static func edgePoint(of item: EaselItem, toward target: EaselPoint) -> EaselPoint? {
        guard let path = outline(for: item), target.x.isFinite, target.y.isFinite else { return nil }
        let origin = center(of: item.frame)
        let dx = target.x - origin.x, dy = target.y - origin.y
        guard dx * dx + dy * dy > 1e-12 else { return nil }
        var best: Double?
        for subpath in path.subpaths(tolerance: 0.25) where subpath.points.count > 1 {
            let points = subpath.points
            let pairs = zip(points, points.dropFirst()).map { ($0, $1) } + (subpath.closed ? [(points[points.count - 1], points[0])] : [])
            for (a, b) in pairs {
                let ex = b.x - a.x, ey = b.y - a.y, denominator = dx * ey - dy * ex
                guard abs(denominator) > 1e-12 else { continue }
                let t = ((a.x - origin.x) * ey - (a.y - origin.y) * ex) / denominator
                let u = ((a.x - origin.x) * dy - (a.y - origin.y) * dx) / denominator
                guard t >= 0, u >= -1e-9, u <= 1 + 1e-9 else { continue }
                best = max(best ?? t, t)
            }
        }
        guard let best else { return nil }
        return EaselPoint(x: origin.x + dx * best, y: origin.y + dy * best)
    }

    static func anchorPoint(of item: EaselItem, side: EaselConnection.Side) -> EaselPoint? {
        let r = item.frame, origin = center(of: r)
        let direction: EaselPoint
        switch side {
        case .top: direction = EaselPoint(x: origin.x, y: r.y - r.height)
        case .bottom: direction = EaselPoint(x: origin.x, y: r.y + 2 * r.height)
        case .left: direction = EaselPoint(x: r.x - r.width, y: origin.y)
        case .right: direction = EaselPoint(x: r.x + 2 * r.width, y: origin.y)
        }
        return edgePoint(of: item, toward: rotationTransform(for: item).apply(direction))
    }

    private static func nearOutline(_ local: EaselPoint, shape: EaselShape, frame: EaselRect, band: Double) -> Bool {
        outline(shape, in: frame).distance(to: local, tolerance: 0.5) <= band
    }

    private static func isSolid(_ item: EaselItem) -> Bool {
        hasVisibleFill(item) || !item.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static func segment(_ a: EaselPoint, _ b: EaselPoint, intersects r: EaselRect) -> Bool {
        var low = 0.0, high = 1.0
        for (origin, delta, minimum, maximum) in [(a.x, b.x - a.x, r.x, r.x + r.width), (a.y, b.y - a.y, r.y, r.y + r.height)] {
            if abs(delta) < 1e-12 {
                if origin < minimum || origin > maximum { return false }
            } else {
                let t1 = (minimum - origin) / delta, t2 = (maximum - origin) / delta
                low = max(low, min(t1, t2)); high = min(high, max(t1, t2))
                if low > high { return false }
            }
        }
        return true
    }

    private static let normalizedPentagon: [EaselPoint] = regularPoints(count: 5, inner: nil)
    private static let normalizedStar: [EaselPoint] = regularPoints(count: 5, inner: (3 - 5.0.squareRoot()) / 2)

    private static func regularPoints(count: Int, inner: Double?) -> [EaselPoint] {
        var raw: [EaselPoint] = []
        for index in 0..<count {
            let angle = -Double.pi / 2 + Double(index) * 2 * .pi / Double(count)
            raw.append(EaselPoint(x: cos(angle), y: sin(angle)))
            if let inner {
                let between = angle + .pi / Double(count)
                raw.append(EaselPoint(x: inner * cos(between), y: inner * sin(between)))
            }
        }
        let xs = raw.map(\.x), ys = raw.map(\.y)
        let minX = xs.min() ?? -1, maxX = xs.max() ?? 1, minY = ys.min() ?? -1, maxY = ys.max() ?? 1
        return raw.map { EaselPoint(x: ($0.x - minX) / (maxX - minX), y: ($0.y - minY) / (maxY - minY)) }
    }

    private static func parallelogramSlant(_ w: Double, _ h: Double) -> Double { min(w * 0.22, h * 0.6) }
    private static func trapezoidInset(_ w: Double, _ h: Double) -> Double { min(w * 0.2, h * 0.6) }
    private static func manualInputRise(_ w: Double, _ h: Double) -> Double { min(h * 0.3, w * 0.25) }
    private static func hexagonInset(_ w: Double, _ h: Double) -> Double { min(w * 0.25, h * 0.577) }
    private static func octagonCut(_ w: Double, _ h: Double) -> Double { min(w, h) * (1 - 1 / 2.0.squareRoot()) }
    private static func plusThickness(_ w: Double, _ h: Double) -> Double { min(w, h) / 3 }
    private static func chevronDepth(_ w: Double, _ h: Double) -> Double { min(w * 0.4, h * 0.5) }
    private static func cylinderCap(_ across: Double, _ along: Double) -> Double { min(along * 0.14, across * 0.25) }
    private static func arrowHead(length: Double, breadth: Double) -> Double { min(length * 0.5, breadth * 0.6) }
    private static func fileFold(_ w: Double, _ h: Double) -> Double { min(w, h) * 0.24 }
    private static func folderTab(_ w: Double, _ h: Double) -> Double { min(h * 0.16, w * 0.12, 28) }
    private static func waveAmplitude(_ h: Double) -> Double { max(0, min(h * 0.06, 12)) }
    private static func stackOffset(_ w: Double, _ h: Double) -> Double { min(min(w, h) * 0.06, 10) }
    private static func processInset(_ w: Double, _ h: Double) -> Double { min(w * 0.1, 18) }
    private static func storageInset(_ w: Double, _ h: Double) -> Double { min(min(w, h) * 0.14, 20) }

    private static func stackWave(_ w: Double, _ h: Double) -> Double {
        let o = stackOffset(w, h)
        return min(waveAmplitude(h - 2 * o), o)
    }

    private static func wavyBottom(_ r: EaselRect, amplitude: Double) -> EaselPath {
        let base = r.y + r.height - amplitude, lift = amplitude / 0.2886751345948129
        var path = EaselPath()
        path.line(to: EaselPoint(x: r.x + r.width, y: base))
        path.cubic(to: EaselPoint(x: r.x, y: base),
                   control1: EaselPoint(x: r.x + r.width * 2 / 3, y: base - lift),
                   control2: EaselPoint(x: r.x + r.width / 3, y: base + lift))
        return path
    }

    private static func blockArrow(_ shape: EaselShape, in r: EaselRect) -> [EaselPoint] {
        let vertical = shape == .arrowUp || shape == .arrowDown
        let length = vertical ? r.height : r.width, breadth = vertical ? r.width : r.height
        let head = arrowHead(length: length, breadth: breadth)
        let outline: [(Double, Double)] = [(0, breadth / 4), (length - head, breadth / 4), (length - head, 0), (length, breadth / 2),
                                           (length - head, breadth), (length - head, breadth * 3 / 4), (0, breadth * 3 / 4)]
        return outline.map { along, across in
            switch shape {
            case .arrowLeft: return EaselPoint(x: r.x + r.width - along, y: r.y + across)
            case .arrowDown: return EaselPoint(x: r.x + across, y: r.y + along)
            case .arrowUp: return EaselPoint(x: r.x + across, y: r.y + r.height - along)
            default: return EaselPoint(x: r.x + along, y: r.y + across)
            }
        }
    }

    private static func speechBubble(_ r: EaselRect) -> EaselPath {
        let w = r.width, h = r.height, body = h * 0.78
        let radius = cornerRadius(.speechBubble, in: r)
        let k = radius * (1 - EaselPath.kappa)
        let minX = r.x, minY = r.y, maxX = r.x + w, bottom = r.y + body
        let tailStart = min(max(minX + w * 0.2, minX + radius), maxX - radius)
        let tailEnd = min(max(tailStart + 1, minX + w * 0.38), maxX - radius)
        let tip = EaselPoint(x: minX + w * 0.14, y: r.y + h)
        var path = EaselPath()
        path.move(to: EaselPoint(x: minX + radius, y: minY))
        path.line(to: EaselPoint(x: maxX - radius, y: minY))
        path.cubic(to: EaselPoint(x: maxX, y: minY + radius), control1: EaselPoint(x: maxX - k, y: minY), control2: EaselPoint(x: maxX, y: minY + k))
        path.line(to: EaselPoint(x: maxX, y: bottom - radius))
        path.cubic(to: EaselPoint(x: maxX - radius, y: bottom), control1: EaselPoint(x: maxX, y: bottom - k), control2: EaselPoint(x: maxX - k, y: bottom))
        path.line(to: EaselPoint(x: tailEnd, y: bottom))
        path.line(to: tip)
        path.line(to: EaselPoint(x: tailStart, y: bottom))
        path.line(to: EaselPoint(x: minX + radius, y: bottom))
        path.cubic(to: EaselPoint(x: minX, y: bottom - radius), control1: EaselPoint(x: minX + k, y: bottom), control2: EaselPoint(x: minX, y: bottom - k))
        path.line(to: EaselPoint(x: minX, y: minY + radius))
        path.cubic(to: EaselPoint(x: minX + radius, y: minY), control1: EaselPoint(x: minX, y: minY + k), control2: EaselPoint(x: minX + k, y: minY))
        path.close()
        return path
    }
}
