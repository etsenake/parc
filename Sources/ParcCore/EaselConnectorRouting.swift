import Foundation

private enum RouteMath {
    static func add(_ a: EaselPoint, _ b: EaselPoint) -> EaselPoint { EaselPoint(x: a.x + b.x, y: a.y + b.y) }
    static func subtract(_ a: EaselPoint, _ b: EaselPoint) -> EaselPoint { EaselPoint(x: a.x - b.x, y: a.y - b.y) }
    static func scaled(_ a: EaselPoint, _ s: Double) -> EaselPoint { EaselPoint(x: a.x * s, y: a.y * s) }
    static func length(_ a: EaselPoint) -> Double { hypot(a.x, a.y) }
    static func distance(_ a: EaselPoint, _ b: EaselPoint) -> Double { hypot(b.x - a.x, b.y - a.y) }
    static func dot(_ a: EaselPoint, _ b: EaselPoint) -> Double { a.x * b.x + a.y * b.y }
    static func lerp(_ a: EaselPoint, _ b: EaselPoint, _ t: Double) -> EaselPoint {
        EaselPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
    }
    static func unit(_ a: EaselPoint, fallback: EaselPoint = EaselPoint(x: 1, y: 0)) -> EaselPoint {
        let size = length(a)
        guard size.isFinite, size > 1e-9 else { return fallback }
        return EaselPoint(x: a.x / size, y: a.y / size)
    }
    static func same(_ a: EaselPoint, _ b: EaselPoint, tolerance: Double = 1e-6) -> Bool {
        abs(a.x - b.x) <= tolerance && abs(a.y - b.y) <= tolerance
    }
    static func center(_ r: EaselRect) -> EaselPoint { EaselPoint(x: r.x + r.width / 2, y: r.y + r.height / 2) }
    static func finite(_ p: EaselPoint) -> Bool { p.x.isFinite && p.y.isFinite }
    static func bounds(_ points: [EaselPoint]) -> EaselRect? {
        guard let first = points.first else { return nil }
        var minX = first.x, minY = first.y, maxX = first.x, maxY = first.y
        for point in points.dropFirst() {
            minX = min(minX, point.x); minY = min(minY, point.y)
            maxX = max(maxX, point.x); maxY = max(maxY, point.y)
        }
        return EaselRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
    static func segmentDistance(_ p: EaselPoint, _ a: EaselPoint, _ b: EaselPoint) -> (distance: Double, t: Double) {
        let dx = b.x - a.x, dy = b.y - a.y, squared = dx * dx + dy * dy
        let t = squared > 0 ? min(1, max(0, ((p.x - a.x) * dx + (p.y - a.y) * dy) / squared)) : 0
        return (hypot(p.x - a.x - t * dx, p.y - a.y - t * dy), t)
    }
}

enum EaselRouteDirection: Int, CaseIterable, Equatable {
    case up, right, down, left

    var dx: Double { self == .right ? 1 : self == .left ? -1 : 0 }
    var dy: Double { self == .down ? 1 : self == .up ? -1 : 0 }
    var vector: EaselPoint { EaselPoint(x: dx, y: dy) }
    var horizontal: Bool { self == .left || self == .right }

    var opposite: EaselRouteDirection {
        switch self {
        case .up: return .down
        case .down: return .up
        case .left: return .right
        case .right: return .left
        }
    }

    init(_ side: EaselConnection.Side) {
        switch side {
        case .top: self = .up
        case .right: self = .right
        case .bottom: self = .down
        case .left: self = .left
        }
    }

    var side: EaselConnection.Side {
        switch self {
        case .up: return .top
        case .right: return .right
        case .down: return .bottom
        case .left: return .left
        }
    }

    static func dominant(_ dx: Double, _ dy: Double) -> EaselRouteDirection {
        abs(dx) >= abs(dy) ? (dx >= 0 ? .right : .left) : (dy >= 0 ? .down : .up)
    }
}

struct EaselConnectorTerminal: Equatable {
    var point: EaselPoint
    var normal: EaselPoint?
    var box: EaselRect?
    var exit: EaselPoint?
    var direction: EaselRouteDirection? { normal.map { EaselRouteDirection.dominant($0.x, $0.y) } }
    var attached: Bool { normal != nil }
}

enum EaselConnectorAttachment {
    static let magnetReach = 18.0

    static func canAttach(to item: EaselItem) -> Bool { item.kind != .arrow && !item.isLocked }
    static func resolves(_ item: EaselItem) -> Bool { item.kind != .arrow }

    static func magnet(_ side: EaselConnection.Side, on item: EaselItem) -> EaselPoint {
        if let point = EaselShapeGeometry.anchorPoint(of: item, side: side), RouteMath.finite(point) { return point }
        let r = item.frame
        let local: EaselPoint
        switch side {
        case .top: local = EaselPoint(x: r.x + r.width / 2, y: r.y)
        case .right: local = EaselPoint(x: r.x + r.width, y: r.y + r.height / 2)
        case .bottom: local = EaselPoint(x: r.x + r.width / 2, y: r.y + r.height)
        case .left: local = EaselPoint(x: r.x, y: r.y + r.height / 2)
        }
        return EaselShapeGeometry.rotationTransform(for: item).apply(local)
    }

    static func magnets(on item: EaselItem) -> [(side: EaselConnection.Side, point: EaselPoint)] {
        EaselConnection.Side.allCases.map { ($0, magnet($0, on: item)) }
    }

    static func outward(_ side: EaselConnection.Side, on item: EaselItem) -> EaselPoint {
        let degrees = EaselShapeGeometry.rotation(of: item)
        let base = EaselRouteDirection(side).vector
        guard degrees != 0 else { return base }
        let radians = degrees * .pi / 180
        return RouteMath.unit(EaselPoint(x: base.x * cos(radians) - base.y * sin(radians),
                                         y: base.x * sin(radians) + base.y * cos(radians)), fallback: base)
    }

    static func anchorPoint(_ anchor: EaselPoint, on item: EaselItem) -> EaselPoint {
        let r = item.frame
        let local = EaselPoint(x: r.x + min(1, max(0, anchor.x)) * r.width, y: r.y + min(1, max(0, anchor.y)) * r.height)
        return EaselShapeGeometry.transform(for: item).apply(local)
    }

    static func anchor(at point: EaselPoint, on item: EaselItem) -> EaselPoint {
        let r = item.frame, local = EaselShapeGeometry.localPoint(point, in: item)
        let u = r.width > 0 ? (local.x - r.x) / r.width : 0.5, v = r.height > 0 ? (local.y - r.y) / r.height : 0.5
        return EaselPoint(x: u.isFinite ? min(1, max(0, u)) : 0.5, y: v.isFinite ? min(1, max(0, v)) : 0.5)
    }

    static func nearestSide(of anchor: EaselPoint, on item: EaselItem) -> EaselConnection.Side {
        var u = anchor.x, v = anchor.y
        if item.flipHorizontal == true { u = 1 - u }
        if item.flipVertical == true { v = 1 - v }
        let w = max(item.frame.width, 1), h = max(item.frame.height, 1)
        let distances: [(EaselConnection.Side, Double)] = [(.top, v * h), (.right, (1 - u) * w), (.bottom, (1 - v) * h), (.left, u * w)]
        return distances.min { $0.1 < $1.1 }?.0 ?? .right
    }

    static func automaticSide(of item: EaselItem, toward point: EaselPoint) -> EaselConnection.Side {
        let r = item.frame
        let local = EaselShapeGeometry.rotationTransform(for: item).inverted?.apply(point) ?? point
        let c = RouteMath.center(r)
        let nx = (local.x - c.x) / max(r.width / 2, 1), ny = (local.y - c.y) / max(r.height / 2, 1)
        if abs(nx) >= abs(ny) { return nx >= 0 ? .right : .left }
        return ny >= 0 ? .bottom : .top
    }

    static func box(of item: EaselItem) -> EaselRect { EaselShapeGeometry.visualBounds(of: item) }

    static func reference(_ connection: EaselConnection?, stored: EaselPoint, lookup: (UUID) -> EaselItem?) -> EaselPoint {
        guard let connection, let target = lookup(connection.itemID), resolves(target) else { return stored }
        if let anchor = connection.anchor { return anchorPoint(anchor, on: target) }
        return RouteMath.center(target.frame)
    }

    static func terminal(_ connection: EaselConnection?, stored: EaselPoint, other: EaselPoint,
                         lookup: (UUID) -> EaselItem?) -> EaselConnectorTerminal {
        guard let connection, let target = lookup(connection.itemID), resolves(target) else {
            return EaselConnectorTerminal(point: stored, normal: nil, box: nil)
        }
        if let anchor = connection.anchor {
            let side = connection.side ?? nearestSide(of: anchor, on: target)
            let point = anchorPoint(anchor, on: target), normal = outward(side, on: target)
            let axis = EaselRouteDirection.dominant(normal.x, normal.y).vector
            return EaselConnectorTerminal(point: point, normal: normal, box: box(of: target), exit: outlineExit(from: point, along: axis, on: target))
        }
        let side = connection.side ?? automaticSide(of: target, toward: other)
        return EaselConnectorTerminal(point: magnet(side, on: target), normal: outward(side, on: target), box: box(of: target))
    }

    static func outline(of item: EaselItem) -> [[EaselPoint]] {
        if let path = EaselShapeGeometry.outline(for: item) {
            let rings = path.subpaths(tolerance: 0.5).map(\.points).filter { $0.count > 2 }
            if !rings.isEmpty { return rings }
        }
        let r = item.frame, transform = EaselShapeGeometry.transform(for: item)
        return [[EaselPoint(x: r.x, y: r.y), EaselPoint(x: r.x + r.width, y: r.y),
                 EaselPoint(x: r.x + r.width, y: r.y + r.height), EaselPoint(x: r.x, y: r.y + r.height)].map(transform.apply)]
    }

    static func outlineExit(from point: EaselPoint, along direction: EaselPoint, on item: EaselItem) -> EaselPoint? {
        var farthest: Double?
        for ring in outline(of: item) {
            for index in ring.indices {
                let a = ring[index], b = ring[(index + 1) % ring.count]
                let ex = b.x - a.x, ey = b.y - a.y
                let denominator = direction.x * ey - direction.y * ex
                guard abs(denominator) > 1e-12 else { continue }
                let t = ((a.x - point.x) * ey - (a.y - point.y) * ex) / denominator
                let u = ((a.x - point.x) * direction.y - (a.y - point.y) * direction.x) / denominator
                guard t > 1e-9, u >= -1e-9, u <= 1 + 1e-9 else { continue }
                farthest = max(farthest ?? t, t)
            }
        }
        return farthest.map { EaselPoint(x: point.x + direction.x * $0, y: point.y + direction.y * $0) }
    }

    static func clockwise(_ side: EaselConnection.Side) -> EaselConnection.Side {
        switch side {
        case .top: return .right
        case .right: return .bottom
        case .bottom: return .left
        case .left: return .top
        }
    }

    static func snap(_ point: EaselPoint, to target: EaselItem?, pin: Bool, scale: Double) -> (connection: EaselConnection?, point: EaselPoint) {
        guard let target, canAttach(to: target), RouteMath.finite(point) else { return (nil, point) }
        if pin {
            let anchor = anchor(at: point, on: target)
            return (EaselConnection(itemID: target.id, side: nil, anchor: anchor), anchorPoint(anchor, on: target))
        }
        let candidates = magnets(on: target)
        guard let nearest = candidates.min(by: { RouteMath.distance($0.point, point) < RouteMath.distance($1.point, point) }) else {
            return (nil, point)
        }
        let safeScale = scale.isFinite && scale > 0 ? scale : 1
        let r = target.frame, local = EaselShapeGeometry.localPoint(point, in: target)
        let inner = EaselRect(x: r.x + r.width * 0.3, y: r.y + r.height * 0.3, width: r.width * 0.4, height: r.height * 0.4)
        let roomy = r.width * safeScale >= 72 && r.height * safeScale >= 72
        if roomy, RouteMath.distance(nearest.point, point) > magnetReach / safeScale,
           local.x >= inner.x, local.x <= inner.x + inner.width, local.y >= inner.y, local.y <= inner.y + inner.height {
            return (EaselConnection(itemID: target.id, side: nil, anchor: nil), RouteMath.center(r))
        }
        return (EaselConnection(itemID: target.id, side: nearest.side, anchor: nil), nearest.point)
    }
}

struct EaselConnectorRoute: Equatable {
    enum Segment: Equatable {
        case line(EaselPoint, EaselPoint)
        case cubic(EaselPoint, EaselPoint, EaselPoint, EaselPoint)

        var start: EaselPoint {
            switch self {
            case .line(let a, _), .cubic(let a, _, _, _): return a
            }
        }

        var end: EaselPoint {
            switch self {
            case .line(_, let b), .cubic(_, _, _, let b): return b
            }
        }

        func point(_ t: Double) -> EaselPoint {
            switch self {
            case .line(let a, let b): return RouteMath.lerp(a, b, t)
            case .cubic(let a, let c1, let c2, let b):
                let u = 1 - t
                let w0 = u * u * u, w1 = 3 * u * u * t, w2 = 3 * u * t * t, w3 = t * t * t
                return EaselPoint(x: w0 * a.x + w1 * c1.x + w2 * c2.x + w3 * b.x,
                                  y: w0 * a.y + w1 * c1.y + w2 * c2.y + w3 * b.y)
            }
        }

        func split(_ t: Double) -> (Segment, Segment) {
            switch self {
            case .line(let a, let b):
                let m = RouteMath.lerp(a, b, t)
                return (.line(a, m), .line(m, b))
            case .cubic(let a, let c1, let c2, let b):
                let ab = RouteMath.lerp(a, c1, t), bc = RouteMath.lerp(c1, c2, t), cd = RouteMath.lerp(c2, b, t)
                let abc = RouteMath.lerp(ab, bc, t), bcd = RouteMath.lerp(bc, cd, t), m = RouteMath.lerp(abc, bcd, t)
                return (.cubic(a, ab, abc, m), .cubic(m, bcd, cd, b))
            }
        }

        func portion(from t0: Double, to t1: Double) -> Segment {
            let low = min(1, max(0, t0)), high = min(1, max(0, t1))
            guard high > low else { let p = point(low); return .line(p, p) }
            let head = high >= 1 ? self : split(high).0
            guard low > 0 else { return head }
            return head.split(low / high).1
        }

        var samples: [EaselPoint] {
            switch self {
            case .line(let a, let b): return [a, b]
            case .cubic:
                return (0...EaselConnectorRoute.curveSamples).map { point(Double($0) / Double(EaselConnectorRoute.curveSamples)) }
            }
        }
    }

    static let curveSamples = 24

    let routing: EaselConnectorRouting
    let segments: [Segment]
    let vertices: [EaselPoint]
    let polyline: [EaselPoint]
    let cumulative: [Double]
    private let sampleOwners: [(segment: Int, t: Double)]

    init?(routing: EaselConnectorRouting, segments: [Segment], vertices: [EaselPoint]) {
        guard !segments.isEmpty else { return nil }
        var polyline: [EaselPoint] = [], owners: [(segment: Int, t: Double)] = [], cumulative: [Double] = []
        for (index, segment) in segments.enumerated() {
            let samples = segment.samples, count = samples.count - 1
            for (offset, point) in samples.enumerated() where !(offset == 0 && index > 0) {
                guard RouteMath.finite(point) else { return nil }
                let distance = polyline.last.map { RouteMath.distance($0, point) } ?? 0
                cumulative.append((cumulative.last ?? 0) + distance)
                polyline.append(point)
                owners.append((index, count > 0 ? Double(offset) / Double(count) : 0))
            }
        }
        guard polyline.count >= 2 else { return nil }
        self.routing = routing
        self.segments = segments
        self.vertices = vertices
        self.polyline = polyline
        self.cumulative = cumulative
        self.sampleOwners = owners
    }

    static func == (lhs: EaselConnectorRoute, rhs: EaselConnectorRoute) -> Bool {
        lhs.routing == rhs.routing && lhs.segments == rhs.segments && lhs.vertices == rhs.vertices
    }

    var length: Double { cumulative.last ?? 0 }
    var start: EaselPoint { polyline.first ?? EaselPoint(x: 0, y: 0) }
    var end: EaselPoint { polyline.last ?? EaselPoint(x: 0, y: 0) }

    var startDirection: EaselPoint {
        if case .cubic(let a, let c1, let c2, let b)? = segments.first {
            for control in [c1, c2, b] where !RouteMath.same(control, a, tolerance: 1e-6) {
                return RouteMath.unit(RouteMath.subtract(a, control), fallback: EaselPoint(x: -1, y: 0))
            }
        }
        for index in polyline.indices.dropFirst() where !RouteMath.same(polyline[index], start, tolerance: 1e-6) {
            return RouteMath.unit(RouteMath.subtract(start, polyline[index]), fallback: EaselPoint(x: -1, y: 0))
        }
        return EaselPoint(x: -1, y: 0)
    }

    var endDirection: EaselPoint {
        if case .cubic(let a, let c1, let c2, let b)? = segments.last {
            for control in [c2, c1, a] where !RouteMath.same(control, b, tolerance: 1e-6) {
                return RouteMath.unit(RouteMath.subtract(b, control))
            }
        }
        for index in polyline.indices.reversed().dropFirst() where !RouteMath.same(polyline[index], end, tolerance: 1e-6) {
            return RouteMath.unit(RouteMath.subtract(end, polyline[index]))
        }
        return EaselPoint(x: 1, y: 0)
    }

    var bounds: EaselRect { RouteMath.bounds(polyline) ?? EaselRect(x: start.x, y: start.y, width: 0, height: 0) }

    private func sampleIndex(at arc: Double) -> Int {
        var low = 0, high = cumulative.count - 1
        while high - low > 1 {
            let middle = (low + high) / 2
            if cumulative[middle] <= arc { low = middle } else { high = middle }
        }
        return low
    }

    func location(at arc: Double) -> (point: EaselPoint, tangent: EaselPoint) {
        let clamped = min(length, max(0, arc.isFinite ? arc : 0))
        let index = min(sampleIndex(at: clamped), polyline.count - 2)
        let a = polyline[index], b = polyline[index + 1]
        let span = cumulative[index + 1] - cumulative[index]
        let t = span > 0 ? (clamped - cumulative[index]) / span : 0
        return (RouteMath.lerp(a, b, t), RouteMath.unit(RouteMath.subtract(b, a), fallback: endDirection))
    }

    func location(atFraction fraction: Double) -> (point: EaselPoint, tangent: EaselPoint) {
        location(at: length * min(1, max(0, fraction.isFinite ? fraction : 0.5)))
    }

    func nearest(to point: EaselPoint) -> (arc: Double, distance: Double, point: EaselPoint) {
        var best = (arc: 0.0, distance: Double.infinity, point: start)
        for index in polyline.indices.dropLast() {
            let a = polyline[index], b = polyline[index + 1]
            let hit = RouteMath.segmentDistance(point, a, b)
            if hit.distance < best.distance {
                best = (cumulative[index] + (cumulative[index + 1] - cumulative[index]) * hit.t, hit.distance, RouteMath.lerp(a, b, hit.t))
            }
        }
        return best
    }

    func distance(to point: EaselPoint) -> Double { nearest(to: point).distance }

    private func parameter(at arc: Double) -> (segment: Int, t: Double) {
        let clamped = min(length, max(0, arc))
        let index = min(sampleIndex(at: clamped), polyline.count - 2)
        let lower = sampleOwners[index], upper = sampleOwners[index + 1]
        let span = cumulative[index + 1] - cumulative[index]
        let fraction = span > 0 ? (clamped - cumulative[index]) / span : 0
        if upper.segment != lower.segment { return (upper.segment, upper.t * fraction) }
        return (lower.segment, lower.t + (upper.t - lower.t) * fraction)
    }

    func subpath(from a: Double, to b: Double) -> [Segment] {
        guard b - a > 1e-6 else { return [] }
        let first = parameter(at: a), last = parameter(at: b)
        if first.segment == last.segment { return [segments[first.segment].portion(from: first.t, to: last.t)] }
        var result = [segments[first.segment].portion(from: first.t, to: 1)]
        if last.segment - first.segment > 1 { result += segments[(first.segment + 1)..<last.segment] }
        if last.t > 0 { result.append(segments[last.segment].portion(from: 0, to: last.t)) }
        return result
    }

    func pieces(hiding ranges: [ClosedRange<Double>]) -> [[Segment]] {
        var visible: [ClosedRange<Double>] = [0...length]
        for hidden in ranges {
            visible = visible.flatMap { range -> [ClosedRange<Double>] in
                guard hidden.upperBound > range.lowerBound, hidden.lowerBound < range.upperBound else { return [range] }
                var parts: [ClosedRange<Double>] = []
                if hidden.lowerBound > range.lowerBound { parts.append(range.lowerBound...hidden.lowerBound) }
                if hidden.upperBound < range.upperBound { parts.append(hidden.upperBound...range.upperBound) }
                return parts
            }
        }
        return visible.compactMap { range in
            let path = subpath(from: range.lowerBound, to: range.upperBound)
            return path.isEmpty ? nil : path
        }
    }

    static func pathData(_ pieces: [[Segment]]) -> String {
        var data = ""
        for piece in pieces {
            guard let first = piece.first else { continue }
            data += "M" + number(first.start)
            for segment in piece {
                switch segment {
                case .line(_, let b): data += "L" + number(b)
                case .cubic(_, let c1, let c2, let b): data += "C" + number(c1) + " " + number(c2) + " " + number(b)
                }
            }
        }
        return data
    }

    static func number(_ point: EaselPoint) -> String {
        EaselPath.svgNumber(point.x) + " " + EaselPath.svgNumber(point.y)
    }
}

struct EaselArrowHeadGeometry: Equatable {
    struct Stroke: Equatable {
        var points: [EaselPoint]
        var closed: Bool
        var filled: Bool
    }

    struct Dot: Equatable {
        var center: EaselPoint
        var radius: Double
        var filled: Bool
    }

    var strokes: [Stroke] = []
    var dots: [Dot] = []
    var inset = 0.0
    var gaps: [ClosedRange<Double>] = []

    var isEmpty: Bool { strokes.isEmpty && dots.isEmpty }

    static func make(_ head: EaselArrowHead, tip: EaselPoint, direction: EaselPoint, width: Double) -> EaselArrowHeadGeometry {
        let w = width.isFinite ? max(0, width) : EaselPaintRules.lineWidth
        let size = EaselPaintRules.arrowHeadLength(width: w)
        let u = RouteMath.unit(direction), n = EaselPoint(x: -u.y, y: u.x)
        func at(_ back: Double, _ across: Double = 0) -> EaselPoint {
            EaselPoint(x: tip.x - u.x * back + n.x * across, y: tip.y - u.y * back + n.y * across)
        }
        let angle = atan2(u.y, u.x)
        let wingA = EaselPoint(x: tip.x - cos(angle - 0.5) * size, y: tip.y - sin(angle - 0.5) * size)
        let wingB = EaselPoint(x: tip.x - cos(angle + 0.5) * size, y: tip.y - sin(angle + 0.5) * size)
        let base = size * cos(0.5)
        func bar(_ back: Double) -> Stroke { Stroke(points: [at(back, size * 0.5), at(back, -size * 0.5)], closed: false, filled: false) }
        let foot = Stroke(points: [at(0, size * 0.6), at(size), at(0, -size * 0.6)], closed: false, filled: false)
        let ring = size * 0.3
        var result = EaselArrowHeadGeometry()
        switch head {
        case .none: break
        case .arrow: result.strokes = [Stroke(points: [wingA, tip, wingB], closed: false, filled: false)]
        case .solidArrow:
            result.strokes = [Stroke(points: [wingA, tip, wingB], closed: true, filled: true)]
            result.inset = base * 0.5
        case .triangle:
            result.strokes = [Stroke(points: [wingA, tip, wingB], closed: true, filled: false)]
            result.inset = base
        case .diamond:
            let length = size * 1.2, half = size * 0.42
            result.strokes = [Stroke(points: [tip, at(length / 2, half), at(length), at(length / 2, -half)], closed: true, filled: true)]
            result.inset = length * 0.5
        case .circle:
            let radius = max(2.5, size * 0.32)
            result.dots = [Dot(center: at(radius), radius: radius, filled: true)]
            result.inset = radius
        case .bar: result.strokes = [bar(0)]
        case .erdOne: result.strokes = [bar(size * 0.6)]
        case .erdMany: result.strokes = [foot]
        case .erdExactlyOne: result.strokes = [bar(size * 0.5), bar(size * 0.9)]
        case .erdZeroOrOne:
            result.strokes = [bar(size * 0.5)]
            result.dots = [Dot(center: at(size * 1.1 + ring), radius: ring, filled: false)]
            result.gaps = [(size * 1.1)...(size * 1.1 + 2 * ring)]
        case .erdOneOrMore: result.strokes = [foot, bar(size * 1.3)]
        case .erdZeroOrMore:
            result.strokes = [foot]
            result.dots = [Dot(center: at(size * 1.25 + ring), radius: ring, filled: false)]
            result.gaps = [(size * 1.25)...(size * 1.25 + 2 * ring)]
        }
        return result
    }

    var pathData: String {
        var data = ""
        for stroke in strokes {
            guard let first = stroke.points.first else { continue }
            data += "M" + EaselConnectorRoute.number(first)
            for point in stroke.points.dropFirst() { data += "L" + EaselConnectorRoute.number(point) }
            if stroke.closed { data += "Z" }
        }
        for dot in dots { data += Self.circleData(dot) }
        return data
    }

    var filledPathData: String {
        var data = ""
        for stroke in strokes where stroke.filled {
            guard let first = stroke.points.first else { continue }
            data += "M" + EaselConnectorRoute.number(first)
            for point in stroke.points.dropFirst() { data += "L" + EaselConnectorRoute.number(point) }
            data += "Z"
        }
        for dot in dots where dot.filled { data += Self.circleData(dot) }
        return data
    }

    var openPathData: String {
        var data = ""
        for stroke in strokes where !stroke.filled {
            guard let first = stroke.points.first else { continue }
            data += "M" + EaselConnectorRoute.number(first)
            for point in stroke.points.dropFirst() { data += "L" + EaselConnectorRoute.number(point) }
            if stroke.closed { data += "Z" }
        }
        for dot in dots where !dot.filled { data += Self.circleData(dot) }
        return data
    }

    private static func circleData(_ dot: Dot) -> String {
        let r = EaselPath.svgNumber(dot.radius)
        return "M" + EaselConnectorRoute.number(EaselPoint(x: dot.center.x - dot.radius, y: dot.center.y))
            + "A" + r + " " + r + " 0 1 0 " + EaselConnectorRoute.number(EaselPoint(x: dot.center.x + dot.radius, y: dot.center.y))
            + "A" + r + " " + r + " 0 1 0 " + EaselConnectorRoute.number(EaselPoint(x: dot.center.x - dot.radius, y: dot.center.y)) + "Z"
    }
}

struct EaselConnectorDrawing: Equatable {
    var route: EaselConnectorRoute
    var startHead: EaselArrowHeadGeometry
    var endHead: EaselArrowHeadGeometry
    var pieces: [[EaselConnectorRoute.Segment]]
    var label: EaselRect?

    init(route: EaselConnectorRoute, item: EaselItem, labelSize: (width: Double, height: Double)? = nil) {
        let width = EaselPaintRules.strokeWidth(item)
        self.route = route
        startHead = EaselArrowHeadGeometry.make(item.resolvedStartHead, tip: route.start, direction: route.startDirection, width: width)
        endHead = EaselArrowHeadGeometry.make(item.resolvedEndHead, tip: route.end, direction: route.endDirection, width: width)
        let length = route.length
        var hidden: [ClosedRange<Double>] = []
        let startTrim = min(startHead.inset, length / 2), endTrim = min(endHead.inset, length / 2)
        if startTrim > 0 { hidden.append(0...startTrim) }
        if endTrim > 0 { hidden.append((length - endTrim)...length) }
        for gap in startHead.gaps where gap.upperBound < length { hidden.append(gap) }
        for gap in endHead.gaps where gap.upperBound < length { hidden.append((length - gap.upperBound)...(length - gap.lowerBound)) }
        if let labelSize {
            let rect = EaselConnectorLabel.rect(on: route, position: item.resolvedLabelPosition, size: labelSize)
            label = rect
            if item.labelBackground != true, let range = EaselConnectorLabel.hiddenRange(on: route, rect: rect) { hidden.append(range) }
        } else {
            label = nil
        }
        pieces = route.pieces(hiding: hidden)
    }

    var linePathData: String { EaselConnectorRoute.pathData(pieces) }
}

enum EaselConnectorLabel {
    static let paddingX = 7.0
    static let paddingY = 3.0
    static let maximumWidth = 240.0
    static let slideMargin = 10.0

    static func rect(on route: EaselConnectorRoute, position: Double, size: (width: Double, height: Double)) -> EaselRect {
        let anchor = route.location(atFraction: clampedPosition(position, on: route, size: size)).point
        let width = max(1, size.width) + 2 * paddingX, height = max(1, size.height) + 2 * paddingY
        return EaselRect(x: anchor.x - width / 2, y: anchor.y - height / 2, width: width, height: height)
    }

    static func canSlide(on route: EaselConnectorRoute, size: (width: Double, height: Double)) -> Bool {
        route.length >= max(size.width, size.height) + 2 * paddingX + 4 * slideMargin
    }

    static func clampedPosition(_ position: Double, on route: EaselConnectorRoute, size: (width: Double, height: Double)) -> Double {
        let value = position.isFinite ? min(1, max(0, position)) : 0.5
        guard canSlide(on: route, size: size), route.length > 0 else { return 0.5 }
        let reserve = (max(size.width, size.height) / 2 + paddingX + slideMargin) / route.length
        guard reserve < 0.5 else { return 0.5 }
        return min(1 - reserve, max(reserve, value))
    }

    static func position(nearest point: EaselPoint, on route: EaselConnectorRoute, size: (width: Double, height: Double)) -> Double {
        guard route.length > 0 else { return 0.5 }
        return clampedPosition(route.nearest(to: point).arc / route.length, on: route, size: size)
    }

    static func hiddenRange(on route: EaselConnectorRoute, rect: EaselRect) -> ClosedRange<Double>? {
        let center = RouteMath.center(rect)
        let middle = route.nearest(to: center).arc
        func inside(_ arc: Double) -> Bool {
            let p = route.location(at: arc).point
            return p.x >= rect.x && p.x <= rect.x + rect.width && p.y >= rect.y && p.y <= rect.y + rect.height
        }
        guard inside(middle) else { return nil }
        let step = max(0.5, min(rect.width, rect.height) / 8)
        var low = middle, high = middle
        while low > 0, inside(max(0, low - step)) { low = max(0, low - step) }
        while high < route.length, inside(min(route.length, high + step)) { high = min(route.length, high + step) }
        return max(0, low - step / 2)...min(route.length, high + step / 2)
    }
}

enum EaselConnectorRouter {
    static let stub = 20.0
    static let bendPenalty = 32.0
    static let minimumLeg = 6.0

    static func isRouted(_ item: EaselItem) -> Bool {
        item.kind == .arrow && (item.startConnection != nil || item.endConnection != nil || item.routing != nil || item.waypoints != nil)
    }

    static func absolutePoints(_ item: EaselItem) -> [EaselPoint] {
        item.points.map { EaselPoint(x: item.frame.x + $0.x, y: item.frame.y + $0.y) }
    }

    static func storedRoute(_ item: EaselItem) -> EaselConnectorRoute? {
        guard item.kind == .arrow, item.points.count >= 2 else { return nil }
        let points = absolutePoints(item)
        let segments = zip(points, points.dropFirst()).map { EaselConnectorRoute.Segment.line($0, $1) }
        return EaselConnectorRoute(routing: item.resolvedRouting, segments: segments, vertices: points)
    }

    static func terminals(for item: EaselItem, lookup: (UUID) -> EaselItem?) -> (start: EaselConnectorTerminal, end: EaselConnectorTerminal)? {
        let points = absolutePoints(item)
        guard item.kind == .arrow, let first = points.first, let last = points.last, points.count >= 2 else { return nil }
        var start = item.startConnection, end = item.endConnection
        if var s = start, var e = end, s.itemID == e.itemID, let target = lookup(s.itemID) {
            let startSide = s.side ?? s.anchor.map { EaselConnectorAttachment.nearestSide(of: $0, on: target) }
            let endSide = e.side ?? e.anchor.map { EaselConnectorAttachment.nearestSide(of: $0, on: target) }
            switch (startSide, endSide) {
            case (nil, nil): s.side = .right; e.side = .bottom
            case (let side?, nil): e.side = EaselConnectorAttachment.clockwise(side)
            case (nil, let side?): s.side = EaselConnectorAttachment.clockwise(EaselConnectorAttachment.clockwise(EaselConnectorAttachment.clockwise(side)))
            default: break
            }
            start = s; end = e
        }
        let startReference = EaselConnectorAttachment.reference(start, stored: first, lookup: lookup)
        let endReference = EaselConnectorAttachment.reference(end, stored: last, lookup: lookup)
        return (EaselConnectorAttachment.terminal(start, stored: first, other: endReference, lookup: lookup),
                EaselConnectorAttachment.terminal(end, stored: last, other: startReference, lookup: lookup))
    }

    static func route(for item: EaselItem, lookup: (UUID) -> EaselItem?) -> EaselConnectorRoute? {
        guard item.kind == .arrow, item.points.count >= 2 else { return nil }
        guard isRouted(item) else { return storedRoute(item) }
        guard let ends = terminals(for: item, lookup: lookup) else { return nil }
        let waypoints = (item.waypoints ?? []).filter(RouteMath.finite)
        switch item.resolvedRouting {
        case .straight:
            return EaselConnectorRoute(routing: .straight, segments: [.line(ends.start.point, ends.end.point)],
                                       vertices: [ends.start.point, ends.end.point])
        case .elbow:
            let points = (waypoints.isEmpty ? nil : manualElbow(from: ends.start, to: ends.end, corners: waypoints))
                ?? elbow(from: ends.start, to: ends.end)
            let segments = zip(points, points.dropFirst()).map { EaselConnectorRoute.Segment.line($0, $1) }
            return EaselConnectorRoute(routing: .elbow, segments: segments.isEmpty ? [.line(ends.start.point, ends.end.point)] : segments,
                                       vertices: points)
        case .curved:
            return EaselConnectorRoute(routing: .curved, segments: curve(from: ends.start, to: ends.end, through: waypoints),
                                       vertices: [ends.start.point] + waypoints + [ends.end.point])
        }
    }

    static func storedGeometry(of route: EaselConnectorRoute) -> (frame: EaselRect, points: [EaselPoint]) {
        let points = route.routing == .curved ? route.polyline : route.vertices
        let box = RouteMath.bounds(points) ?? EaselRect(x: route.start.x, y: route.start.y, width: 0, height: 0)
        return (EaselRect(x: box.x, y: box.y, width: max(1, box.width), height: max(1, box.height)),
                points.map { EaselPoint(x: $0.x - box.x, y: $0.y - box.y) })
    }

    static func settled(_ item: EaselItem, lookup: (UUID) -> EaselItem?) -> EaselItem {
        guard item.kind == .arrow else { return item }
        var next = item
        if let id = next.startConnection?.itemID, lookup(id).map(EaselConnectorAttachment.resolves) != true || id == item.id {
            next.startConnection = nil
        }
        if let id = next.endConnection?.itemID, lookup(id).map(EaselConnectorAttachment.resolves) != true || id == item.id {
            next.endConnection = nil
        }
        guard isRouted(next), let route = route(for: next, lookup: lookup) else { return next }
        let stored = storedGeometry(of: route)
        guard RouteMath.finite(EaselPoint(x: stored.frame.x, y: stored.frame.y)),
              stored.points.allSatisfy(RouteMath.finite) else { return next }
        let absolute = stored.points.map { EaselPoint(x: stored.frame.x + $0.x, y: stored.frame.y + $0.y) }
        let current = absolutePoints(next)
        let unchanged = absolute.count == current.count && zip(absolute, current).allSatisfy { RouteMath.same($0, $1, tolerance: 1e-6) }
            && abs(stored.frame.width - next.frame.width) < 1e-6 && abs(stored.frame.height - next.frame.height) < 1e-6
        if !unchanged { next.frame = stored.frame; next.points = stored.points }
        return next
    }

    static func detached(_ item: EaselItem, from removed: Set<UUID>) -> EaselItem {
        guard item.kind == .arrow else { return item }
        let startGone = item.startConnection.map { removed.contains($0.itemID) } == true
        let endGone = item.endConnection.map { removed.contains($0.itemID) } == true
        guard startGone || endGone else { return item }
        var next = item
        if startGone { next.startConnection = nil }
        if endGone { next.endConnection = nil }
        switch next.resolvedRouting {
        case .elbow where item.points.count > 2:
            next.waypoints = Array(absolutePoints(item).dropFirst().dropLast())
        case .curved where (item.waypoints ?? []).isEmpty:
            if let middle = storedRoute(item)?.location(atFraction: 0.5).point { next.waypoints = [middle] }
        default:
            break
        }
        return next
    }

    static func leaving(_ terminal: EaselConnectorTerminal) -> EaselConnectorTerminal {
        var copy = terminal
        if let exit = terminal.exit { copy.point = exit }
        return copy
    }

    static func clearance(_ terminal: EaselConnectorTerminal, _ direction: EaselRouteDirection) -> Double {
        guard terminal.attached else { return 0 }
        guard let box = terminal.box else { return stub }
        let p = terminal.point
        let needed: Double
        switch direction {
        case .right: needed = box.x + box.width + stub - p.x
        case .left: needed = p.x - (box.x - stub)
        case .down: needed = box.y + box.height + stub - p.y
        case .up: needed = p.y - (box.y - stub)
        }
        return needed.isFinite ? max(stub, needed) : stub
    }

    static func elbow(from start: EaselConnectorTerminal, to end: EaselConnectorTerminal) -> [EaselPoint] {
        let s = leaving(start), e = leaving(end)
        let sDirection = s.direction ?? .dominant(e.point.x - s.point.x, e.point.y - s.point.y)
        let eDirection = e.direction ?? .dominant(s.point.x - e.point.x, s.point.y - e.point.y)
        let s1 = nonNegative(RouteMath.add(s.point, RouteMath.scaled(sDirection.vector, clearance(s, sDirection))), keeping: s.point)
        let e1 = nonNegative(RouteMath.add(e.point, RouteMath.scaled(eDirection.vector, clearance(e, eDirection))), keeping: e.point)
        let boxes = [s.box, e.box].compactMap { $0 }
        for obstacles in [boxes, []] {
            if let path = gridRoute(from: s1, leaving: sDirection, strictStart: s.attached,
                                    to: e1, entering: eDirection, strictEnd: e.attached, boxes: boxes, obstacles: obstacles) {
                return simplified([s.point] + path + [e.point])
            }
        }
        let corner = sDirection.horizontal ? EaselPoint(x: e1.x, y: s1.y) : EaselPoint(x: s1.x, y: e1.y)
        return simplified([s.point, s1, corner, e1, e.point])
    }

    static func manualElbow(from start: EaselConnectorTerminal, to end: EaselConnectorTerminal, corners: [EaselPoint]) -> [EaselPoint]? {
        guard !corners.isEmpty else { return nil }
        let s = leaving(start), e = leaving(end)
        var c = corners
        func horizontalSegment(_ a: EaselPoint, _ b: EaselPoint) -> Bool { abs(a.y - b.y) <= abs(a.x - b.x) }
        let firstHorizontal: Bool
        if let direction = s.direction { firstHorizontal = direction.horizontal }
        else if c.count >= 2 { firstHorizontal = !horizontalSegment(c[0], c[1]) }
        else { firstHorizontal = abs(c[0].y - s.point.y) <= abs(c[0].x - s.point.x) }
        let lastHorizontal: Bool
        if let direction = e.direction { lastHorizontal = direction.horizontal }
        else if c.count >= 2 { lastHorizontal = !horizontalSegment(c[c.count - 2], c[c.count - 1]) }
        else { lastHorizontal = !firstHorizontal }
        if c.count == 1, firstHorizontal == lastHorizontal {
            let only = c[0]
            c = firstHorizontal ? [EaselPoint(x: only.x, y: s.point.y), EaselPoint(x: only.x, y: e.point.y)]
                : [EaselPoint(x: s.point.x, y: only.y), EaselPoint(x: e.point.x, y: only.y)]
        } else {
            let wasFirst = c[0]
            if firstHorizontal { c[0].y = s.point.y } else { c[0].x = s.point.x }
            if c.count > 1, firstHorizontal ? abs(c[1].x - wasFirst.x) < 1e-6 : abs(c[1].y - wasFirst.y) < 1e-6 {
                if firstHorizontal { c[1].x = c[0].x } else { c[1].y = c[0].y }
            }
            let last = c.count - 1, wasLast = c[last]
            if lastHorizontal { c[last].y = e.point.y } else { c[last].x = e.point.x }
            if last > 0, lastHorizontal ? abs(c[last - 1].x - wasLast.x) < 1e-6 : abs(c[last - 1].y - wasLast.y) < 1e-6 {
                if lastHorizontal { c[last - 1].x = c[last].x } else { c[last - 1].y = c[last].y }
            }
        }
        if let direction = s.direction, s.attached {
            push(&c, first: true, from: s.point, direction: direction, clearance: clearance(s, direction))
        }
        if let direction = e.direction, e.attached {
            push(&c, first: false, from: e.point, direction: direction, clearance: clearance(e, direction))
        }
        var path = [s.point]
        for point in c + [e.point] {
            guard let previous = path.last else { continue }
            if abs(previous.x - point.x) > 1e-6, abs(previous.y - point.y) > 1e-6 {
                let before = path.count >= 2 ? path[path.count - 2] : nil
                let cameHorizontal = before.map { abs($0.y - previous.y) <= 1e-6 } ?? !firstHorizontal
                path.append(cameHorizontal ? EaselPoint(x: previous.x, y: point.y) : EaselPoint(x: point.x, y: previous.y))
            }
            path.append(point)
        }
        let result = simplified(path)
        guard result.count >= 2 else { return nil }
        if let direction = s.direction, s.attached,
           RouteMath.dot(RouteMath.subtract(result[1], result[0]), direction.vector) < minimumLeg { return nil }
        if let direction = e.direction, e.attached,
           RouteMath.dot(RouteMath.subtract(result[result.count - 2], result[result.count - 1]), direction.vector) < minimumLeg { return nil }
        return result
    }

    private static func push(_ corners: inout [EaselPoint], first: Bool, from point: EaselPoint, direction: EaselRouteDirection,
                             clearance: Double) {
        let index = first ? 0 : corners.count - 1
        guard corners.indices.contains(index) else { return }
        let neighbour = first ? 1 : corners.count - 2
        if direction.horizontal {
            let required = point.x + direction.dx * clearance
            guard (corners[index].x - point.x) * direction.dx < clearance else { return }
            let old = corners[index].x
            corners[index].x = required
            if corners.indices.contains(neighbour), neighbour != index, abs(corners[neighbour].x - old) < 1e-6 { corners[neighbour].x = required }
        } else {
            let required = point.y + direction.dy * clearance
            guard (corners[index].y - point.y) * direction.dy < clearance else { return }
            let old = corners[index].y
            corners[index].y = required
            if corners.indices.contains(neighbour), neighbour != index, abs(corners[neighbour].y - old) < 1e-6 { corners[neighbour].y = required }
        }
    }

    static func curve(from s: EaselConnectorTerminal, to e: EaselConnectorTerminal,
                      through waypoints: [EaselPoint]) -> [EaselConnectorRoute.Segment] {
        let points = [s.point] + waypoints + [e.point]
        if waypoints.isEmpty {
            let span = RouteMath.distance(s.point, e.point)
            let reach = max(24, min(span * 0.4, 300))
            let startVector = s.normal ?? EaselRouteDirection.dominant(e.point.x - s.point.x, e.point.y - s.point.y).vector
            let endVector = e.normal ?? EaselRouteDirection.dominant(s.point.x - e.point.x, s.point.y - e.point.y).vector
            if s.normal == nil, e.normal == nil, abs(e.point.x - s.point.x) < 1e-6 || abs(e.point.y - s.point.y) < 1e-6 {
                return [.line(s.point, e.point)]
            }
            return [.cubic(s.point, RouteMath.add(s.point, RouteMath.scaled(startVector, reach)),
                           RouteMath.add(e.point, RouteMath.scaled(endVector, reach)), e.point)]
        }
        var tangents: [EaselPoint] = []
        for index in points.indices {
            if index == 0 {
                tangents.append(s.normal ?? RouteMath.unit(RouteMath.subtract(points[1], points[0])))
            } else if index == points.count - 1 {
                tangents.append(e.normal.map { RouteMath.scaled($0, -1) }
                    ?? RouteMath.unit(RouteMath.subtract(points[index], points[index - 1])))
            } else {
                tangents.append(RouteMath.unit(RouteMath.subtract(points[index + 1], points[index - 1])))
            }
        }
        return points.indices.dropLast().map { index in
            let a = points[index], b = points[index + 1], reach = RouteMath.distance(a, b) / 3
            return .cubic(a, RouteMath.add(a, RouteMath.scaled(tangents[index], reach)),
                          RouteMath.subtract(b, RouteMath.scaled(tangents[index + 1], reach)), b)
        }
    }

    static func simplified(_ points: [EaselPoint]) -> [EaselPoint] {
        var result: [EaselPoint] = []
        for point in points where result.last.map({ !RouteMath.same($0, point, tolerance: 1e-6) }) ?? true {
            if result.count >= 2 {
                let a = result[result.count - 2], b = result[result.count - 1]
                let sameX = abs(a.x - b.x) <= 1e-6 && abs(b.x - point.x) <= 1e-6
                let sameY = abs(a.y - b.y) <= 1e-6 && abs(b.y - point.y) <= 1e-6
                if sameX || sameY { result.removeLast() }
            }
            result.append(point)
        }
        return result
    }

    private static func nonNegative(_ point: EaselPoint, keeping original: EaselPoint) -> EaselPoint {
        EaselPoint(x: point.x < 0 ? max(0, min(original.x, point.x)) : point.x, y: point.y < 0 ? max(0, min(original.y, point.y)) : point.y)
    }

    private static func gridRoute(from a: EaselPoint, leaving aDirection: EaselRouteDirection, strictStart: Bool,
                                  to b: EaselPoint, entering bDirection: EaselRouteDirection, strictEnd: Bool,
                                  boxes: [EaselRect], obstacles: [EaselRect]) -> [EaselPoint]? {
        var xs = [a.x, b.x], ys = [a.y, b.y]
        for box in boxes {
            xs += [box.x - stub, box.x + box.width + stub]
            ys += [box.y - stub, box.y + box.height + stub]
        }
        var middleX = (a.x + b.x) / 2, middleY = (a.y + b.y) / 2
        if boxes.count == 2 {
            let first = boxes[0], second = boxes[1]
            if first.x + first.width < second.x { middleX = (first.x + first.width + second.x) / 2 }
            else if second.x + second.width < first.x { middleX = (second.x + second.width + first.x) / 2 }
            if first.y + first.height < second.y { middleY = (first.y + first.height + second.y) / 2 }
            else if second.y + second.height < first.y { middleY = (second.y + second.height + first.y) / 2 }
        }
        xs.append(middleX); ys.append(middleY)
        func unique(_ values: [Double], keep: [Double]) -> [Double] {
            var result: [Double] = []
            for value in values.sorted() where value.isFinite && (value >= 0 || keep.contains(value)) {
                if let last = result.last, abs(last - value) < 1e-6 { continue }
                result.append(value)
            }
            return result
        }
        xs = unique(xs, keep: [a.x, b.x]); ys = unique(ys, keep: [a.y, b.y])
        guard let startX = xs.firstIndex(where: { abs($0 - a.x) < 1e-6 }), let startY = ys.firstIndex(where: { abs($0 - a.y) < 1e-6 }),
              let goalX = xs.firstIndex(where: { abs($0 - b.x) < 1e-6 }), let goalY = ys.firstIndex(where: { abs($0 - b.y) < 1e-6 }) else { return nil }
        let blocked = obstacles.map { EaselRect(x: $0.x - stub + 0.5, y: $0.y - stub + 0.5, width: $0.width + 2 * stub - 1, height: $0.height + 2 * stub - 1) }
        func clear(_ p: EaselPoint, _ q: EaselPoint) -> Bool {
            blocked.allSatisfy { r in
                let minX = min(p.x, q.x), maxX = max(p.x, q.x), minY = min(p.y, q.y), maxY = max(p.y, q.y)
                return maxX <= r.x || minX >= r.x + r.width || maxY <= r.y || minY >= r.y + r.height
            }
        }
        let width = xs.count, count = xs.count * ys.count
        func node(_ x: Int, _ y: Int) -> Int { y * width + x }
        let start = node(startX, startY), goal = node(goalX, goalY)
        var cost = [Double](repeating: .infinity, count: count * 4)
        var previous = [Int](repeating: -1, count: count * 4)
        var settled = [Bool](repeating: false, count: count * 4)
        cost[start * 4 + aDirection.rawValue] = 0
        var queue = RouteQueue()
        queue.push(0, start * 4 + aDirection.rawValue)
        while let entry = queue.pop() {
            let current = entry.state, best = entry.cost
            guard !settled[current], best <= cost[current] + 1e-9 else { continue }
            settled[current] = true
            let place = current / 4, heading = EaselRouteDirection(rawValue: current % 4) ?? .right
            let x = place % width, y = place / width
            for direction in EaselRouteDirection.allCases {
                var turn = direction == heading ? 0 : bendPenalty
                if direction == heading.opposite {
                    guard place == start, !strictStart else { continue }
                    turn = 2 * bendPenalty
                }
                let nx = x + (direction == .right ? 1 : direction == .left ? -1 : 0)
                let ny = y + (direction == .down ? 1 : direction == .up ? -1 : 0)
                guard nx >= 0, nx < width, ny >= 0, ny < ys.count else { continue }
                let p = EaselPoint(x: xs[x], y: ys[y]), q = EaselPoint(x: xs[nx], y: ys[ny])
                guard clear(p, q) else { continue }
                let onMiddle = direction.horizontal ? abs(p.y - middleY) < 1e-6 : abs(p.x - middleX) < 1e-6
                let step = RouteMath.distance(p, q) * (onMiddle ? 0.98 : 1)
                let next = node(nx, ny) * 4 + direction.rawValue
                let total = best + step + turn
                if total < cost[next] - 1e-9 { cost[next] = total; previous[next] = current; queue.push(total, next) }
            }
        }
        var finish = -1, finishCost = Double.infinity
        for direction in EaselRouteDirection.allCases {
            let state = goal * 4 + direction.rawValue
            guard cost[state].isFinite else { continue }
            var extra = 0.0
            if direction == bDirection { guard !strictEnd else { continue }; extra = 2 * bendPenalty }
            else if direction != bDirection.opposite { extra = bendPenalty }
            if goal == start && direction == aDirection { extra = 0 }
            if cost[state] + extra < finishCost { finishCost = cost[state] + extra; finish = state }
        }
        guard finish >= 0 else { return nil }
        var states: [Int] = []
        var cursor = finish
        while cursor >= 0, states.count <= count * 4 {
            states.append(cursor)
            cursor = previous[cursor]
        }
        return states.reversed().map { state in
            let place = state / 4
            return EaselPoint(x: xs[place % width], y: ys[place / width])
        }
    }
}

private struct RouteQueue {
    private var entries: [(cost: Double, state: Int)] = []

    mutating func push(_ cost: Double, _ state: Int) {
        entries.append((cost, state))
        var child = entries.count - 1
        while child > 0 {
            let parent = (child - 1) / 2
            guard entries[child].cost < entries[parent].cost else { break }
            entries.swapAt(child, parent)
            child = parent
        }
    }

    mutating func pop() -> (cost: Double, state: Int)? {
        guard let first = entries.first, let last = entries.popLast() else { return nil }
        guard !entries.isEmpty else { return first }
        entries[0] = last
        var parent = 0
        while true {
            let left = 2 * parent + 1, right = left + 1
            var smallest = parent
            if left < entries.count, entries[left].cost < entries[smallest].cost { smallest = left }
            if right < entries.count, entries[right].cost < entries[smallest].cost { smallest = right }
            guard smallest != parent else { break }
            entries.swapAt(parent, smallest)
            parent = smallest
        }
        return first
    }
}

enum EaselConnectorHit {
    static func reach(for item: EaselItem, scale: Double) -> Double {
        let safe = scale.isFinite && scale > 0 ? scale : 1
        return max(15 / safe, EaselPaintRules.strokeWidth(item) / 2 + 4 / safe)
    }

    static func contains(_ point: EaselPoint, drawing: EaselConnectorDrawing, item: EaselItem, scale: Double) -> Bool {
        guard RouteMath.finite(point) else { return false }
        if let label = drawing.label, EaselContentHitTest.contains(point, rect: label) { return true }
        let reach = reach(for: item, scale: scale)
        if drawing.route.distance(to: point) <= reach { return true }
        for head in [drawing.startHead, drawing.endHead] {
            for stroke in head.strokes {
                let points = stroke.points + (stroke.closed ? stroke.points.prefix(1) : [])
                for (a, b) in zip(points, points.dropFirst()) where RouteMath.segmentDistance(point, a, b).distance <= reach { return true }
            }
            for dot in head.dots where RouteMath.distance(point, dot.center) <= dot.radius + reach { return true }
        }
        return false
    }

    static func intersects(_ rect: EaselRect, route: EaselConnectorRoute) -> Bool {
        guard rect.width > 0, rect.height > 0 else { return false }
        let points = route.polyline
        if points.contains(where: { EaselContentHitTest.contains($0, rect: rect) }) { return true }
        return zip(points, points.dropFirst()).contains { segment($0, $1, intersects: rect) }
    }

    static func segment(_ a: EaselPoint, _ b: EaselPoint, intersects r: EaselRect) -> Bool {
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
}

enum EaselConnectorPath {
    struct SegmentHandle: Equatable {
        var index: Int
        var point: EaselPoint
        var horizontal: Bool
    }

    struct CurveHandle: Equatable {
        var point: EaselPoint
        var waypoint: Int?
        var insertion: Int
    }

    static func elbowHandles(_ route: EaselConnectorRoute, scale: Double, attachedStart: Bool, attachedEnd: Bool) -> [SegmentHandle] {
        let safe = scale.isFinite && scale > 0 ? scale : 1
        let points = route.vertices
        return points.indices.dropLast().compactMap { index in
            let a = points[index], b = points[index + 1]
            guard RouteMath.distance(a, b) * safe >= 28 else { return nil }
            if index == 0, attachedStart, RouteMath.distance(a, b) <= EaselConnectorRouter.stub + 1e-6, points.count > 2 { return nil }
            if index == points.count - 2, attachedEnd, RouteMath.distance(a, b) <= EaselConnectorRouter.stub + 1e-6, points.count > 2 { return nil }
            return SegmentHandle(index: index, point: RouteMath.lerp(a, b, 0.5), horizontal: abs(a.y - b.y) <= abs(a.x - b.x))
        }
    }

    static func movingElbowSegment(_ vertices: [EaselPoint], index: Int, by offset: Double) -> [EaselPoint]? {
        guard vertices.count >= 2, vertices.indices.contains(index), vertices.indices.contains(index + 1), offset.isFinite else { return nil }
        let a = vertices[index], b = vertices[index + 1]
        let horizontal = abs(a.y - b.y) <= abs(a.x - b.x)
        func shifted(_ p: EaselPoint) -> EaselPoint { horizontal ? EaselPoint(x: p.x, y: p.y + offset) : EaselPoint(x: p.x + offset, y: p.y) }
        var points = vertices
        let along = RouteMath.unit(RouteMath.subtract(b, a))
        let segmentLength = RouteMath.distance(a, b)
        let lead = min(EaselConnectorRouter.stub, segmentLength / 3)
        if index == 0 {
            let stubEnd = RouteMath.add(a, RouteMath.scaled(along, lead))
            points.insert(contentsOf: [stubEnd, shifted(stubEnd)], at: 1)
            let moved = index + 3
            if points.indices.contains(moved), moved < points.count - 1 { points[moved] = shifted(points[moved]) }
            else if moved == points.count - 1 {
                let endLead = RouteMath.subtract(b, RouteMath.scaled(along, lead))
                points.insert(contentsOf: [shifted(endLead), endLead], at: moved)
            }
        } else if index + 1 == vertices.count - 1 {
            points[index] = shifted(points[index])
            let endLead = RouteMath.subtract(b, RouteMath.scaled(along, lead))
            points.insert(contentsOf: [shifted(endLead), endLead], at: index + 1)
        } else {
            points[index] = shifted(points[index]); points[index + 1] = shifted(points[index + 1])
        }
        let simplified = EaselConnectorRouter.simplified(points)
        guard simplified.count >= 3 else { return [] }
        return Array(simplified.dropFirst().dropLast())
    }

    static func curveHandles(_ route: EaselConnectorRoute, waypoints: [EaselPoint]) -> [CurveHandle] {
        var handles: [CurveHandle] = []
        for (index, segment) in route.segments.enumerated() {
            handles.append(CurveHandle(point: segment.point(0.5), waypoint: nil, insertion: index))
            if index < waypoints.count { handles.append(CurveHandle(point: waypoints[index], waypoint: index, insertion: index)) }
        }
        return handles
    }

    static func mapped(_ waypoints: [EaselPoint], from old: EaselRect, to new: EaselRect) -> [EaselPoint] {
        let sx = old.width > 1e-9 ? new.width / old.width : 1, sy = old.height > 1e-9 ? new.height / old.height : 1
        return waypoints.map { EaselPoint(x: new.x + ($0.x - old.x) * sx, y: new.y + ($0.y - old.y) * sy) }
    }
}

struct EaselConnectorStyle: Equatable {
    var startHead: EaselArrowHead?
    var endHead: EaselArrowHead?
    var routing: EaselConnectorRouting?
    var strokeWidth: Double?
    var strokeDash: EaselStrokeDash?
    var color: String
    var labelBackground: Bool?

    init(startHead: EaselArrowHead? = nil, endHead: EaselArrowHead? = nil, routing: EaselConnectorRouting? = nil,
         strokeWidth: Double? = nil, strokeDash: EaselStrokeDash? = nil, color: String = EaselPalette.automaticInk,
         labelBackground: Bool? = nil) {
        self.startHead = startHead; self.endHead = endHead; self.routing = routing
        self.strokeWidth = strokeWidth; self.strokeDash = strokeDash; self.color = color; self.labelBackground = labelBackground
    }

    init(_ item: EaselItem) {
        self.init(startHead: item.startHead, endHead: item.endHead, routing: item.routing, strokeWidth: item.strokeWidth,
                  strokeDash: item.strokeDash, color: item.color, labelBackground: item.labelBackground)
    }

    func apply(to item: inout EaselItem, routing override: EaselConnectorRouting? = nil) {
        guard item.kind == .arrow else { return }
        item.startHead = startHead; item.endHead = endHead
        let chosen = override ?? routing
        item.routing = chosen == .straight ? nil : chosen
    }
}

extension EaselConnectorRouter {
    static func placing(_ item: EaselItem, end: EaselArrowEndpoint, at point: EaselPoint) -> EaselItem {
        guard item.kind == .arrow, item.points.count >= 2, RouteMath.finite(point) else { return item }
        var absolute = absolutePoints(item)
        absolute[end.index(in: item)] = point
        if isRouted(item) { absolute = [absolute[0], absolute[absolute.count - 1]] }
        guard let box = RouteMath.bounds(absolute) else { return item }
        var next = item
        next.frame = EaselRect(x: box.x, y: box.y, width: max(1, box.width), height: max(1, box.height))
        next.points = absolute.map { EaselPoint(x: $0.x - box.x, y: $0.y - box.y) }
        return next
    }

    static func connecting(_ item: EaselItem, end: EaselArrowEndpoint, to connection: EaselConnection?, at point: EaselPoint,
                           lookup: (UUID) -> EaselItem?) -> EaselItem {
        var next = placing(item, end: end, at: point)
        let previous = end == .start ? item.startConnection : item.endConnection
        if end == .start { next.startConnection = connection } else { next.endConnection = connection }
        if previous != connection, next.resolvedRouting == .elbow { next.waypoints = nil }
        return settled(next, lookup: lookup)
    }

    static func make(from start: EaselPoint, to end: EaselPoint, style: EaselConnectorStyle, routing: EaselConnectorRouting?,
                     startConnection: EaselConnection?, endConnection: EaselConnection?, zIndex: Int,
                     lookup: (UUID) -> EaselItem?) -> EaselItem {
        let minX = min(start.x, end.x), minY = min(start.y, end.y)
        var item = EaselItem(kind: .arrow, frame: EaselRect(x: minX, y: minY, width: max(1, abs(end.x - start.x)), height: max(1, abs(end.y - start.y))),
                             zIndex: zIndex)
        item.points = [EaselPoint(x: start.x - minX, y: start.y - minY), EaselPoint(x: end.x - minX, y: end.y - minY)]
        style.apply(to: &item, routing: routing)
        item.startConnection = startConnection
        item.endConnection = endConnection
        return settled(item, lookup: lookup)
    }
}

struct EaselConnectorLabelArt: Equatable {
    var text: EaselVectorText
    var width: Double
    var height: Double
}

extension EaselVectorExport {
    static func connector(_ item: EaselItem, art: EaselVectorArt) -> String {
        guard let route = art.connectorRoutes[item.id] ?? EaselConnectorRouter.storedRoute(item) else { return "" }
        let label = art.connectorLabels[item.id]
        let drawing = EaselConnectorDrawing(route: route, item: item, labelSize: label.map { (width: $0.width, height: $0.height) })
        let width = EaselPaintRules.strokeWidth(item), tone = EaselPaintRules.ink(item), ink = paint(tone.hex, role: tone.role)
        var result = "<g class=\"easel-connector\">"
        if width > 0, !drawing.pieces.isEmpty {
            result += "<path d=\"" + drawing.linePathData + "\" style=\"fill:none;" + strokeStyle(item, dashed: true, rounded: true) + "\"/>"
        }
        for head in [drawing.startHead, drawing.endHead] where !head.isEmpty {
            let filled = head.filledPathData, open = head.openPathData
            if !filled.isEmpty {
                result += "<path d=\"" + filled + "\" style=\"fill:" + ink + ";" + strokeStyle(item, dashed: false, rounded: true) + "\"/>"
            }
            if !open.isEmpty, width > 0 {
                result += "<path d=\"" + open + "\" style=\"fill:none;" + strokeStyle(item, dashed: false, rounded: true) + "\"/>"
            }
        }
        if let rect = drawing.label, let label {
            let background = item.labelBackground == true
            if background {
                let radius = min(8, rect.height / 2)
                result += "<rect x=\"" + number(rect.x) + "\" y=\"" + number(rect.y) + "\" width=\"" + number(rect.width) + "\" height=\""
                    + number(rect.height) + "\" rx=\"" + number(radius) + "\" ry=\"" + number(radius) + "\" style=\"fill:" + ink + "\"/>"
            }
            let fill = background ? labelInk(on: item.color) : nil
            result += "<g transform=\"translate(" + number(rect.x + EaselConnectorLabel.paddingX) + " "
                + number(rect.y + EaselConnectorLabel.paddingY) + ")\">"
            for run in label.text.runs where !run.text.isEmpty {
                var shown = run
                if fill != nil { shown.color = nil }
                let body = textRun(shown)
                result += fill.map { body.replacingOccurrences(of: "fill:var(--easel-ink)", with: "fill:" + $0) } ?? body
            }
            result += "</g>"
        }
        return result + "</g>"
    }

    static func labelInk(on hex: String) -> String {
        if isAutomatic(hex) { return "var(--easel-card)" }
        guard let value = color(hex), let rgb = UInt32(value.dropFirst(), radix: 16) else { return "#FFFFFF" }
        let r = Double(rgb >> 16 & 255) / 255, g = Double(rgb >> 8 & 255) / 255, b = Double(rgb & 255) / 255
        return 0.2126 * r + 0.7152 * g + 0.0722 * b > 0.6 ? EaselPalette.inkLight : EaselPalette.neutralLight
    }
}
